param(
    [switch]$DryRun,
    [int]$FromYear = 0,
    [int]$ToYear = 9999
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "2.0"
$RepoRoot = "C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive"
$SourceRoot = "C:\Users\rbell\OneDrive\Pictures"
$VideoRoot = Join-Path $RepoRoot "videos"
$ManifestCsv = Join-Path $RepoRoot "website-video-manifest.csv"
$PublishTag = "Website"
$VideoExtensions = @('.mp4','.mov','.m4v','.avi','.wmv','.mpeg','.mpg','.mts','.m2ts','.3gp','.webm')

function Get-ExifToolPath {
    $cmd = Get-Command exiftool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($candidate in @(
        "C:\ExifTool\exiftool.exe",
        "C:\Program Files\ExifTool\exiftool.exe",
        "C:\Program Files (x86)\ExifTool\exiftool.exe",
        "$env:USERPROFILE\exiftool.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "ExifTool was not found."
}

function Get-FFmpegToolPath {
    param([Parameter(Mandatory=$true)][string]$ToolName)
    $exe = "$ToolName.exe"
    $cmd = Get-Command $exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "C:\ffmpeg\bin\$exe",
        "C:\Program Files\ffmpeg\bin\$exe",
        "C:\Program Files (x86)\ffmpeg\bin\$exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path -LiteralPath $wingetRoot) {
        $pkgDirs = @(Get-ChildItem -LiteralPath $wingetRoot -Directory -Filter 'Gyan.FFmpeg*' -ErrorAction SilentlyContinue)
        foreach ($pkg in $pkgDirs) {
            $found = Get-ChildItem -LiteralPath $pkg.FullName -Recurse -File -Filter $exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }

    throw "$ToolName was not found. Install FFmpeg first (for example: winget install Gyan.FFmpeg), then open a new PowerShell window."
}

function Test-DecadePlaceholderPath {
    param([string]$RelativePath)
    foreach ($part in ($RelativePath -split '[\\/]')) {
        if ($part -match '^(18|19|20)\d0s$') { return $true }
    }
    return $false
}

function Get-YearFromRelativePath {
    param([string]$RelativePath)
    foreach ($part in ($RelativePath -split '[\\/]')) {
        if ($part -match '^(18|19|20)\d{2}$') { return [int]$part }
    }
    return $null
}

function Get-SourceRelativePath {
    param([System.IO.FileInfo]$File)
    return $File.FullName.Substring($SourceRoot.Length).TrimStart('\')
}

function Get-WebsiteRelativePath {
    param([System.IO.FileInfo]$File)
    $sourceRelative = Get-SourceRelativePath $File
    $parts = $sourceRelative -split '\\'
    $year = $null
    foreach ($part in $parts) {
        if ($part -match '^(18|19|20)\d{2}$') { $year = $part; break }
    }
    if (!$year) { return $sourceRelative }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    return Join-Path $year ($base + '.mp4')
}

function Test-WebsiteTag {
    param($Record)
    foreach ($property in @('Subject','Keywords','HierarchicalSubject')) {
        if ($Record.PSObject.Properties.Name -notcontains $property) { continue }
        $v = $Record.$property
        $values = if ($v -is [System.Array]) { $v } else { @($v) }
        foreach ($value in $values) {
            if ($null -eq $value) { continue }
            foreach ($token in ([string]$value -split '[,;]')) {
                $token = $token.Trim()
                if (!$token) { continue }
                if ($token -ieq $PublishTag) { return $true }
                $segments = $token -split '[|/]'
                if ($segments.Count -gt 0 -and $segments[-1].Trim() -ieq $PublishTag) { return $true }
            }
        }
    }
    return $false
}

function Join-MetadataValues {
    param($Record,[string[]]$Names)
    $all = @()
    foreach ($name in $Names) {
        if ($Record.PSObject.Properties.Name -contains $name) {
            $v = $Record.$name
            if ($null -ne $v) {
                if ($v -is [System.Array]) { $all += $v } else { $all += [string]$v }
            }
        }
    }
    return (($all | ForEach-Object { [string]$_ } | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join '; ')
}

function Get-VideoProbe {
    param([Parameter(Mandatory=$true)][string]$Path)
    $json = & $FFprobe -v error -print_format json -show_streams -show_format -- $Path 2>$null
    if ($LASTEXITCODE -ne 0 -or !$json) { return $null }
    try { return (($json -join [Environment]::NewLine) | ConvertFrom-Json) } catch { return $null }
}

function Get-VideoCompatibility {
    param([Parameter(Mandatory=$true)][string]$Path)
    $probe = Get-VideoProbe $Path
    if (!$probe) {
        return [pscustomobject]@{ Readable=$false; VideoCodec=''; AudioCodec=''; HasAudio=$false; WebCodecs=$false; Mp4Container=$false; PixelFormat='' }
    }
    $v = @($probe.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1)
    $a = @($probe.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1)
    $videoCodec = if ($v.Count) { [string]$v[0].codec_name } else { '' }
    $pixelFormat = if ($v.Count) { [string]$v[0].pix_fmt } else { '' }
    $audioCodec = if ($a.Count) { [string]$a[0].codec_name } else { '' }
    $hasAudio = $a.Count -gt 0
    $formatName = [string]$probe.format.format_name
    $mp4Container = $formatName -match '(^|,)mp4(,|$)|(^|,)mov(,|$)' -and ([System.IO.Path]::GetExtension($Path) -ieq '.mp4')
    $webCodecs = ($videoCodec -eq 'h264') -and ((!$hasAudio) -or ($audioCodec -eq 'aac')) -and (($pixelFormat -eq '') -or ($pixelFormat -match '^yuv420p'))
    return [pscustomobject]@{
        Readable=$true; VideoCodec=$videoCodec; AudioCodec=$audioCodec; HasAudio=$hasAudio
        WebCodecs=$webCodecs; Mp4Container=$mp4Container; PixelFormat=$pixelFormat
    }
}

function Invoke-FFmpeg {
    param([string[]]$Arguments)
    & $FFmpeg @Arguments
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg failed (exit $LASTEXITCODE): $($Arguments -join ' ')" }
}

function Write-WebVideoDerivative {
    param(
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$Source,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)]$SourceCompatibility
    )
    $folder = Split-Path -Parent $Destination
    if (!(Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $temp = Join-Path $folder (([System.IO.Path]::GetFileNameWithoutExtension($Destination)) + '.tmp.mp4')
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }

    try {
        if ($SourceCompatibility.WebCodecs) {
            Write-Host "REMUX   $($Source.FullName)"
            Invoke-FFmpeg @('-hide_banner','-loglevel','error','-y','-i',$Source.FullName,'-map','0:v:0','-map','0:a?','-c','copy','-movflags','+faststart',$temp)
        } else {
            Write-Host "TRANSCODE $($Source.FullName) [$($SourceCompatibility.VideoCodec)/$($SourceCompatibility.AudioCodec)]"
            Invoke-FFmpeg @('-hide_banner','-loglevel','error','-y','-i',$Source.FullName,'-map','0:v:0','-map','0:a?','-c:v','libx264','-preset','medium','-crf','20','-pix_fmt','yuv420p','-c:a','aac','-b:a','160k','-movflags','+faststart',$temp)
        }
        Move-Item -LiteralPath $temp -Destination $Destination -Force
        (Get-Item -LiteralPath $Destination).LastWriteTimeUtc = $Source.LastWriteTimeUtc
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

if (!(Test-Path -LiteralPath $SourceRoot)) { throw "Source folder does not exist: $SourceRoot" }
$ExifTool = Get-ExifToolPath
$FFmpeg = Get-FFmpegToolPath 'ffmpeg'
$FFprobe = Get-FFmpegToolPath 'ffprobe'

Write-Host ""
Write-Host "Bell Family Archive Website Video Sync v$ScriptVersion"
Write-Host "Source: $SourceRoot"
Write-Host "Destination: $VideoRoot"
Write-Host "Years: $FromYear through $ToYear"
Write-Host "Decade placeholders: ignored"
Write-Host "Website format: MP4 / H.264 / AAC / yuv420p / faststart"
Write-Host "FFmpeg: $FFmpeg"
Write-Host "FFprobe: $FFprobe"
if ($DryRun) { Write-Host "*** DRY RUN - NO VIDEO FILES WILL BE WRITTEN ***" }
Write-Host ""

$files = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '[\\/]\.dtrash[\\/]' -and
        $VideoExtensions -contains $_.Extension.ToLowerInvariant()
    })

$rows = New-Object "System.Collections.Generic.List[object]"
$scanned = 0
$websiteTagged = 0
$copied = 0
$remuxed = 0
$transcoded = 0
$current = 0
$skippedPlaceholder = 0
$probeErrors = 0

for ($i=0; $i -lt $files.Count; $i += 50) {
    $batch = @($files[$i..([Math]::Min($i+49,$files.Count-1))])
    if ($batch.Count -eq 0) { continue }
    $args = @('-q','-q','-json','-Subject','-Keywords','-HierarchicalSubject','-PersonInImage','-RegionPersonDisplayName','-Title','-Description','-Caption-Abstract','-DateTimeOriginal','-CreateDate','-GPSLatitude','-GPSLongitude')
    foreach ($file in $batch) { $args += $file.FullName }
    $json = & $ExifTool @args 2>$null
    if ($LASTEXITCODE -ne 0) { throw "ExifTool failed while reading video metadata (exit $LASTEXITCODE)." }
    if (!$json) { continue }
    $records = (($json -join [Environment]::NewLine) | ConvertFrom-Json)
    if ($records -isnot [System.Array]) { $records = @($records) }

    foreach ($record in $records) {
        $scanned++
        if (!(Test-WebsiteTag $record)) { continue }
        $file = Get-Item -LiteralPath ([string]$record.SourceFile) -ErrorAction SilentlyContinue
        if (!$file) { continue }

        $sourceRelative = Get-SourceRelativePath $file
        if (Test-DecadePlaceholderPath $sourceRelative) { $skippedPlaceholder++; continue }
        $year = Get-YearFromRelativePath $sourceRelative
        if ($null -eq $year -or $year -lt $FromYear -or $year -gt $ToYear) { continue }

        $websiteTagged++
        $relative = Get-WebsiteRelativePath $file
        $dest = Join-Path $VideoRoot $relative
        $sourceCompat = Get-VideoCompatibility $file.FullName
        if (!$sourceCompat.Readable) {
            Write-Warning "FFprobe could not read video: $($file.FullName)"
            $probeErrors++
            continue
        }

        $destExists = Test-Path -LiteralPath $dest
        $destCompat = if ($destExists) { Get-VideoCompatibility $dest } else { $null }
        $destWebSafe = $destExists -and $destCompat -and $destCompat.Readable -and $destCompat.WebCodecs -and $destCompat.Mp4Container
        $timestampCurrent = $destExists -and ((Get-Item -LiteralPath $dest).LastWriteTimeUtc -eq $file.LastWriteTimeUtc)
        $needsWrite = !($destWebSafe -and $timestampCurrent)

        if ($needsWrite) {
            $mode = if ($sourceCompat.WebCodecs -and $file.Extension -ieq '.mp4') { 'COPY' } elseif ($sourceCompat.WebCodecs) { 'REMUX' } else { 'TRANSCODE' }
            Write-Host "$mode  videos\$relative"
            if (!$DryRun) {
                $folder = Split-Path -Parent $dest
                if (!(Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
                if ($mode -eq 'COPY') {
                    Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
                    (Get-Item -LiteralPath $dest).LastWriteTimeUtc = $file.LastWriteTimeUtc
                    $copied++
                } else {
                    Write-WebVideoDerivative -Source $file -Destination $dest -SourceCompatibility $sourceCompat
                    if ($mode -eq 'REMUX') { $remuxed++ } else { $transcoded++ }
                }
                $verify = Get-VideoCompatibility $dest
                if (!$verify -or !$verify.Readable -or !$verify.WebCodecs -or !$verify.Mp4Container) {
                    throw "Generated website video is not browser-safe: $dest"
                }
            } else {
                if ($mode -eq 'COPY') { $copied++ } elseif ($mode -eq 'REMUX') { $remuxed++ } else { $transcoded++ }
            }
        } else { $current++ }

        $tags = Join-MetadataValues $record @('Subject','Keywords','HierarchicalSubject')
        $cleanTags = @()
        foreach ($t in ($tags -split ';')) {
            $t=$t.Trim(); if(!$t){continue}
            $leaf=($t -split '[|/]')[-1].Trim()
            if($t -ieq $PublishTag -or $leaf -ieq $PublishTag){continue}
            $cleanTags += $t
        }
        $rows.Add([pscustomobject]@{
            SourcePath=$file.FullName
            RelativePath=$relative
            DestinationPath=$dest
            FileName=[System.IO.Path]::GetFileName($relative)
            Date=(Join-MetadataValues $record @('DateTimeOriginal','CreateDate'))
            People=(Join-MetadataValues $record @('PersonInImage','RegionPersonDisplayName'))
            Title=(Join-MetadataValues $record @('Title'))
            Description=(Join-MetadataValues $record @('Caption-Abstract','Description'))
            Tags=(($cleanTags | Select-Object -Unique) -join '; ')
            GPSLatitude=(Join-MetadataValues $record @('GPSLatitude'))
            GPSLongitude=(Join-MetadataValues $record @('GPSLongitude'))
            Length=$file.Length
            LastWriteUtc=$file.LastWriteTimeUtc.ToString('o')
        })
    }
}

if (!$DryRun) {
    $rows | Sort-Object RelativePath | Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8
}

Write-Host ""
Write-Host "Video files scanned:             $scanned"
Write-Host "Website-tagged videos selected:  $websiteTagged"
Write-Host "Compatible MP4s copied:          $copied"
Write-Host "Videos remuxed to MP4:           $remuxed"
Write-Host "Videos transcoded H.264/AAC:     $transcoded"
Write-Host "Already browser-safe/current:    $current"
Write-Host "FFprobe read errors:              $probeErrors"
Write-Host "Placeholder-decade videos skip:  $skippedPlaceholder"
if (!$DryRun) { Write-Host "Video manifest: $ManifestCsv" }

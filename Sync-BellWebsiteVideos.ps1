param(
    [switch]$DryRun,
    [int]$FromYear = 0,
    [int]$ToYear = 9999,
    [string[]]$SourceRoots = @(
        "C:\Users\rbell\OneDrive\Pictures",
        "G:\Pictures\Stephanie"
    )
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "2.3"
$RepoRoot = "C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive"
$DbSourceHelper = Join-Path $RepoRoot "tools\list_website_sources_from_digikam.py"
$GreenSyncHelper = Join-Path $RepoRoot "tools\ensure_website_green_in_digikam.py"
$VideoRoot = Join-Path $RepoRoot "videos"
$ManifestCsv = Join-Path $RepoRoot "website-video-manifest.csv"
$PublishTag = "Website"
$VideoExtensions = @('.mp4','.mov','.m4v','.avi','.wmv','.mpeg','.mpg','.mts','.m2ts','.3gp','.webm')
$MaxGitHubVideoBytes = 95MB

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

function Get-PythonCommand {
    if ($env:BELL_PYTHON -and (Test-Path -LiteralPath $env:BELL_PYTHON)) { return $env:BELL_PYTHON }
    foreach ($name in @("python.exe", "py.exe")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            & $command.Source --version *> $null
            if ($LASTEXITCODE -eq 0) { return $command.Source }
        }
    }
    throw "A working Python 3 runtime was not found."
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
    $sourceRoot = $SourceRoots | Where-Object {
        $File.FullName.StartsWith(($_.TrimEnd('\') + '\'), [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    if (!$sourceRoot) { throw "Source file is outside the configured collections: $($File.FullName)" }
    return $File.FullName.Substring($sourceRoot.Length).TrimStart('\')
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
    # FFmpeg reports full-range 4:2:0 H.264 as yuvj420p. It is the browser-safe
    # full-range alias of yuv420p, so accept both spellings during verification.
    $webCodecs = ($videoCodec -eq 'h264') -and ((!$hasAudio) -or ($audioCodec -eq 'aac')) -and (($pixelFormat -eq '') -or ($pixelFormat -match '^yuvj?420p'))
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
        [Parameter(Mandatory=$true)]$SourceCompatibility,
        [switch]$ForceSizeReduction
    )
    $folder = Split-Path -Parent $Destination
    if (!(Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $temp = Join-Path $folder (([System.IO.Path]::GetFileNameWithoutExtension($Destination)) + '.tmp.mp4')
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }

    try {
        if ($SourceCompatibility.WebCodecs -and !$ForceSizeReduction) {
            Write-Host "REMUX   $($Source.FullName)"
            Invoke-FFmpeg @('-hide_banner','-loglevel','error','-y','-i',$Source.FullName,'-map','0:v:0','-map','0:a?','-c','copy','-movflags','+faststart',$temp)
        } else {
            $crfValues = if ($ForceSizeReduction) { @(23,26,29,32) } else { @(20,23,26,29,32) }
            foreach ($crf in $crfValues) {
                Write-Host "TRANSCODE $($Source.FullName) [$($SourceCompatibility.VideoCodec)/$($SourceCompatibility.AudioCodec), CRF $crf]"
                Invoke-FFmpeg @('-hide_banner','-loglevel','error','-y','-i',$Source.FullName,'-map','0:v:0','-map','0:a?','-c:v','libx264','-preset','medium','-crf',"$crf",'-pix_fmt','yuv420p','-c:a','aac','-b:a','128k','-movflags','+faststart',$temp)
                if ((Get-Item -LiteralPath $temp).Length -le $MaxGitHubVideoBytes) { break }
                Remove-Item -LiteralPath $temp -Force
            }
            if (!(Test-Path -LiteralPath $temp) -or (Get-Item -LiteralPath $temp).Length -gt $MaxGitHubVideoBytes) {
                throw "Unable to create a GitHub-safe video under $([math]::Round($MaxGitHubVideoBytes/1MB)) MB: $($Source.FullName)"
            }
        }
        Move-Item -LiteralPath $temp -Destination $Destination -Force
        (Get-Item -LiteralPath $Destination).LastWriteTimeUtc = $Source.LastWriteTimeUtc
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

foreach ($sourceRoot in $SourceRoots) {
    if (!(Test-Path -LiteralPath $sourceRoot)) { throw "Source folder does not exist: $sourceRoot" }
}
if (!(Test-Path -LiteralPath $DbSourceHelper)) { throw "digiKam Website-source helper not found: $DbSourceHelper" }
if (!(Test-Path -LiteralPath $GreenSyncHelper)) { throw "digiKam green-label helper not found: $GreenSyncHelper" }
$python = Get-PythonCommand
$greenArgs = @($GreenSyncHelper)
if ($DryRun) { $greenArgs += '--dry-run' }
& $python @greenArgs
if ($LASTEXITCODE -ne 0) { throw "Could not synchronize Website tags to digiKam green labels." }
$websiteSourceJson = Join-Path $env:TEMP ("bell-website-video-sources-" + [guid]::NewGuid().ToString("N") + ".json")
$helperArgs = @($DbSourceHelper)
foreach ($sourceRoot in $SourceRoots) { $helperArgs += @('--source-root', $sourceRoot) }
$helperArgs += @('--output', $websiteSourceJson)
& $python @helperArgs
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $websiteSourceJson)) { throw "Could not read current Website tags from digiKam." }
$sourceData = Get-Content -LiteralPath $websiteSourceJson -Raw | ConvertFrom-Json
Remove-Item -LiteralPath $websiteSourceJson -Force -ErrorAction SilentlyContinue
$WebsiteSourcePaths = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($sourcePath in $sourceData.website_sources) {
    try { $normalized = [System.IO.Path]::GetFullPath([string]$sourcePath) } catch { $normalized = [string]$sourcePath }
    [void]$WebsiteSourcePaths.Add(($normalized -replace '/', '\').TrimEnd('\'))
}
$ExifTool = Get-ExifToolPath
$FFmpeg = Get-FFmpegToolPath 'ffmpeg'
$FFprobe = Get-FFmpegToolPath 'ffprobe'

Write-Host ""
Write-Host "Bell Family Archive Website Video Sync v$ScriptVersion"
Write-Host "Sources:"
foreach ($sourceRoot in $SourceRoots) { Write-Host "  $sourceRoot" }
Write-Host "Destination: $VideoRoot"
Write-Host "Years: $FromYear through $ToYear"
Write-Host "Publish rule: current digiKam Website tag (green label assigned automatically)"
Write-Host "Decade placeholders: ignored"
Write-Host "Website format: MP4 / H.264 / AAC / yuv420p / faststart"
Write-Host "GitHub file limit guard: website videos at or below $([math]::Round($MaxGitHubVideoBytes/1MB)) MB"
Write-Host "FFmpeg: $FFmpeg"
Write-Host "FFprobe: $FFprobe"
if ($DryRun) { Write-Host "*** DRY RUN - NO VIDEO FILES WILL BE WRITTEN ***" }
Write-Host ""

$files = @(
    foreach ($sourcePath in $sourceData.website_sources) {
        $file = Get-Item -LiteralPath ([string]$sourcePath) -ErrorAction SilentlyContinue
        if ($file -and $VideoExtensions -contains $file.Extension.ToLowerInvariant()) { $file }
    }
)

$rows = New-Object "System.Collections.Generic.List[object]"
$scanned = 0
$websiteTagged = 0
$copied = 0
$remuxed = 0
$transcoded = 0
$current = 0
$skippedPlaceholder = 0
$probeErrors = 0
$destinationSources = @{}

for ($i=0; $i -lt $files.Count; $i += 50) {
    $batch = @($files[$i..([Math]::Min($i+49,$files.Count-1))])
    if ($batch.Count -eq 0) { continue }
    $args = @('-q','-q','-json','-Subject','-Keywords','-HierarchicalSubject','-PersonInImage','-RegionPersonDisplayName','-Title','-Description','-Caption-Abstract','-DateTimeOriginal','-CreateDate','-GPSLatitude','-GPSLongitude')
    foreach ($file in $batch) { $args += $file.FullName }
    # Windows PowerShell promotes harmless native stderr text (including ExifTool's
    # Perl locale warning) to an error when the script uses ErrorActionPreference=Stop.
    # Suppress that stream for this call, but still enforce ExifTool's real exit code.
    $priorErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $json = & $ExifTool @args 2>$null
        $exifExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $priorErrorActionPreference
    }
    if ($exifExitCode -ne 0) { throw "ExifTool failed while reading video metadata (exit $exifExitCode)." }
    if (!$json) { continue }
    $records = (($json -join [Environment]::NewLine) | ConvertFrom-Json)
    if ($records -isnot [System.Array]) { $records = @($records) }

    foreach ($record in $records) {
        $scanned++
        $file = Get-Item -LiteralPath ([string]$record.SourceFile) -ErrorAction SilentlyContinue
        if (!$file) { continue }
        if (!$WebsiteSourcePaths.Contains($file.FullName.TrimEnd('\'))) { continue }

        $sourceRelative = Get-SourceRelativePath $file
        if (Test-DecadePlaceholderPath $sourceRelative) { $skippedPlaceholder++; continue }
        $year = Get-YearFromRelativePath $sourceRelative
        if ($null -eq $year -or $year -lt $FromYear -or $year -gt $ToYear) { continue }

        $websiteTagged++
        $relative = Get-WebsiteRelativePath $file
        $destinationKey = $relative.ToLowerInvariant()
        if ($destinationSources.ContainsKey($destinationKey) -and $destinationSources[$destinationKey] -ine $file.FullName) {
            throw "Two Website-tagged videos map to the same website path: $($destinationSources[$destinationKey]) and $($file.FullName) -> $relative"
        }
        $destinationSources[$destinationKey] = $file.FullName
        $dest = Join-Path $VideoRoot $relative
        $sourceCompat = Get-VideoCompatibility $file.FullName
        if (!$sourceCompat.Readable) {
            Write-Warning "FFprobe could not read video: $($file.FullName)"
            $probeErrors++
            continue
        }

        $destExists = Test-Path -LiteralPath $dest
        $destCompat = if ($destExists) { Get-VideoCompatibility $dest } else { $null }
        $destSizeSafe = $destExists -and ((Get-Item -LiteralPath $dest).Length -le $MaxGitHubVideoBytes)
        $destWebSafe = $destExists -and $destCompat -and $destCompat.Readable -and $destCompat.WebCodecs -and $destCompat.Mp4Container -and $destSizeSafe
        $timestampCurrent = $destExists -and ((Get-Item -LiteralPath $dest).LastWriteTimeUtc -eq $file.LastWriteTimeUtc)
        $needsWrite = !($destWebSafe -and $timestampCurrent)

        if ($needsWrite) {
            $sourceTooLarge = $file.Length -gt $MaxGitHubVideoBytes
            $mode = if ($sourceTooLarge) { 'TRANSCODE-SIZE' } elseif ($sourceCompat.WebCodecs -and $file.Extension -ieq '.mp4') { 'COPY' } elseif ($sourceCompat.WebCodecs) { 'REMUX' } else { 'TRANSCODE' }
            Write-Host "$mode  videos\$relative"
            if (!$DryRun) {
                $folder = Split-Path -Parent $dest
                if (!(Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
                if ($mode -eq 'COPY') {
                    Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
                    (Get-Item -LiteralPath $dest).LastWriteTimeUtc = $file.LastWriteTimeUtc
                    $copied++
                } else {
                    Write-WebVideoDerivative -Source $file -Destination $dest -SourceCompatibility $sourceCompat -ForceSizeReduction:($mode -eq 'TRANSCODE-SIZE')
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

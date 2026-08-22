param(
    [switch]$DryRun,
    [int]$FromYear = 0,
    [int]$ToYear = 9999
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "1.1"
$RepoRoot = "C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive"
$SourceRoot = "C:\Users\rbell\OneDrive\Pictures"
$AudioRoot = Join-Path $RepoRoot "audio"
$ManifestCsv = Join-Path $RepoRoot "website-audio-manifest.csv"
$PublishTag = "Website"
$AudioExtensions = @('.mp3','.m4a','.wav','.aac','.flac','.wma','.ogg','.oga','.opus')

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

function Get-DestinationRelativePath {
    param([System.IO.FileInfo]$File)
    $relative = $File.FullName.Substring($SourceRoot.Length).TrimStart('\')
    $parts = $relative -split '\\'
    foreach ($part in $parts) {
        if ($part -match '^(18|19|20)\d{2}$') { return Join-Path $part $File.Name }
    }
    return $relative
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

if (!(Test-Path -LiteralPath $SourceRoot)) { throw "Source folder does not exist: $SourceRoot" }
$ExifTool = Get-ExifToolPath

Write-Host ""
Write-Host "Bell Family Archive Website Audio Sync v$ScriptVersion"
Write-Host "Source: $SourceRoot"
Write-Host "Destination: $AudioRoot"
Write-Host "Years: $FromYear through $ToYear"
Write-Host "Decade placeholders: ignored"
if ($DryRun) { Write-Host "*** DRY RUN - NO AUDIO FILES WILL BE COPIED ***" }
Write-Host ""

$files = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch '[\\/]\.dtrash[\\/]' -and
        $AudioExtensions -contains $_.Extension.ToLowerInvariant()
    })

$rows = New-Object "System.Collections.Generic.List[object]"
$scanned = 0
$websiteTagged = 0
$copied = 0
$current = 0
$skippedPlaceholder = 0

for ($i=0; $i -lt $files.Count; $i += 50) {
    $end=[Math]::Min($i+49,$files.Count-1)
    if ($end -lt $i) { continue }
    $batch = @($files[$i..$end])
    # -q -q suppresses ExifTool's normal "N image files read" summary. Windows
    # PowerShell otherwise promotes that harmless stderr status line to a
    # NativeCommandError because this script uses ErrorActionPreference=Stop.
    $args = @('-q','-q','-json','-Subject','-Keywords','-HierarchicalSubject','-PersonInImage','-RegionPersonDisplayName','-Title','-Description','-Caption-Abstract','-DateTimeOriginal','-CreateDate','-GPSLatitude','-GPSLongitude')
    foreach ($file in $batch) { $args += $file.FullName }
    $json = & $ExifTool @args 2>$null
    if ($LASTEXITCODE -ne 0) { throw "ExifTool failed while reading audio metadata (exit $LASTEXITCODE)." }
    if (!$json) { continue }
    $records = (($json -join [Environment]::NewLine) | ConvertFrom-Json)
    if ($records -isnot [System.Array]) { $records = @($records) }

    foreach ($record in $records) {
        $scanned++
        if (!(Test-WebsiteTag $record)) { continue }
        $file = Get-Item -LiteralPath ([string]$record.SourceFile) -ErrorAction SilentlyContinue
        if (!$file) { continue }
        $relative = Get-DestinationRelativePath $file
        if (Test-DecadePlaceholderPath $relative) { $skippedPlaceholder++; continue }
        $year = Get-YearFromRelativePath $relative
        if ($null -eq $year -or $year -lt $FromYear -or $year -gt $ToYear) { continue }

        $websiteTagged++
        $dest = Join-Path $AudioRoot $relative
        $destExists = Test-Path -LiteralPath $dest
        $needsCopy = !$destExists
        if ($destExists) {
            $d = Get-Item -LiteralPath $dest
            $needsCopy = ($d.Length -ne $file.Length) -or ($d.LastWriteTimeUtc -lt $file.LastWriteTimeUtc)
        }
        if ($needsCopy) {
            Write-Host "$(if($destExists){'UPDATE'}else{'NEW   '})  audio\$relative"
            if (!$DryRun) {
                $folder = Split-Path -Parent $dest
                if (!(Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
                Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
                (Get-Item -LiteralPath $dest).LastWriteTimeUtc = $file.LastWriteTimeUtc
            }
            $copied++
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
            FileName=$file.Name
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
Write-Host "Audio files scanned:             $scanned"
Write-Host "Website-tagged audio selected:   $websiteTagged"
Write-Host "Audio files copied/updated:      $copied"
Write-Host "Already current:                 $current"
Write-Host "Placeholder-decade audio skip:   $skippedPlaceholder"
if (!$DryRun) { Write-Host "Audio manifest: $ManifestCsv" }

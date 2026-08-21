param(
    [switch]$DryRun,
    [switch]$RefreshManifest,
    [switch]$Live,
    [int]$FromYear = 0,
    [int]$ToYear = 9999
)

$ScriptVersion = "3.9"
$RepoRoot = "C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive"
$V36 = Join-Path $RepoRoot "Sync-BellWebsitePhotos-v3.6.ps1"
$ManifestCsv = Join-Path $RepoRoot "website-photo-manifest.csv"
$OldTestRoot = Join-Path $RepoRoot "website-test-v36"
$OutputRoot = if ($Live) { $RepoRoot } else { Join-Path $RepoRoot "website-test-v38" }
$ViewRoot = Join-Path $OutputRoot "images"
$ThumbRoot = Join-Path $OutputRoot "thumbs"
$HighResRoot = Join-Path $OutputRoot "highres"

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

function Get-CleanTags {
    param([string]$Tags)
    $out = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Tags)) { return @() }
    foreach ($raw in ($Tags -split ';')) {
        $tag = $raw.Trim()
        if (!$tag) { continue }
        $leaf = ($tag -split '[|/]')[-1].Trim()
        if ($tag -ieq 'Website' -or $leaf -ieq 'Website') { continue }
        if (!$out.Contains($tag)) { $out.Add($tag) }
    }
    return @($out)
}

function Copy-GenealogyMetadata {
    param([string]$ExifTool,[string]$Source,[string]$Destination,[string[]]$CleanTags)
    if (!(Test-Path -LiteralPath $Destination)) { return $false }
    $ext = [System.IO.Path]::GetExtension($Destination).ToLowerInvariant()

    if ($ext -eq '.png') {
        $args = @(
            '-overwrite_original','-TagsFromFile',$Source,
            '-XMP:DateTimeOriginal','-XMP:CreateDate','-XMP:GPSLatitude','-XMP:GPSLongitude',
            '-XMP:Title','-XMP:Description','-XMP:PersonInImage','-XMP:RegionPersonDisplayName',
            '-XMP:Copyright','-XMP:Creator','-XMP:Artist','-XMP:Orientation',$Destination
        )
        & $ExifTool @args | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        & $ExifTool -overwrite_original '-XMP:Subject=' '-XMP:HierarchicalSubject=' $Destination | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        if ($CleanTags.Count -gt 0) {
            $tagArgs = @('-overwrite_original')
            foreach ($tag in $CleanTags) {
                $tagArgs += "-XMP:Subject+=$tag"
                $tagArgs += "-XMP:HierarchicalSubject+=$tag"
            }
            $tagArgs += $Destination
            & $ExifTool @tagArgs | Out-Null
            if ($LASTEXITCODE -ne 0) { return $false }
        }
    }
    else {
        $args = @(
            '-overwrite_original','-TagsFromFile',$Source,
            '-DateTimeOriginal','-CreateDate','-GPSLatitude','-GPSLongitude','-GPSLatitudeRef','-GPSLongitudeRef',
            '-Title','-Description','-Caption-Abstract','-PersonInImage','-RegionPersonDisplayName',
            '-Copyright','-Creator','-Artist','-Orientation',$Destination
        )
        & $ExifTool @args | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        & $ExifTool -overwrite_original '-Subject=' '-Keywords=' '-HierarchicalSubject=' $Destination | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        if ($CleanTags.Count -gt 0) {
            $tagArgs = @('-overwrite_original')
            foreach ($tag in $CleanTags) {
                $tagArgs += "-Subject+=$tag"
                $tagArgs += "-Keywords+=$tag"
                $tagArgs += "-HierarchicalSubject+=$tag"
            }
            $tagArgs += $Destination
            & $ExifTool @tagArgs | Out-Null
            if ($LASTEXITCODE -ne 0) { return $false }
        }
    }
    return $true
}

if (!(Test-Path -LiteralPath $V36)) { throw "v3.6 script not found: $V36" }

Write-Host ""
Write-Host "Bell Family Archive Website Photo Generator v$ScriptVersion"
Write-Host "Years: $FromYear through $ToYear"
Write-Host "Output: $(if($Live){'LIVE'}else{'website-test-v38'})"
Write-Host "Public derivatives: thumbs + images + highres"
Write-Host "Decade placeholders: ignored"
Write-Host ""

$baseArgs = @('-ExecutionPolicy','Bypass','-File',$V36,'-FromYear',$FromYear,'-ToYear',$ToYear)
if ($DryRun) { $baseArgs += '-DryRun' }
if ($RefreshManifest) { $baseArgs += '-RefreshManifest' }
if ($Live) { $baseArgs += '-Live' }

& powershell.exe @baseArgs
if ($LASTEXITCODE -ne 0) { throw "v3.6 generation failed." }

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run complete. No files were created or changed."
    exit 0
}

if (!(Test-Path -LiteralPath $ManifestCsv)) { throw "Manifest not found: $ManifestCsv" }
$rows = Import-Csv -LiteralPath $ManifestCsv
$selected = @()
$placeholderSkipped = 0

foreach ($row in $rows) {
    if (Test-DecadePlaceholderPath $row.RelativePath) {
        $placeholderSkipped++
        continue
    }
    $year = Get-YearFromRelativePath $row.RelativePath
    if ($null -eq $year -or $year -lt $FromYear -or $year -gt $ToYear) { continue }
    if (!(Test-Path -LiteralPath $row.SourcePath)) { continue }
    $selected += $row
}

if (!$Live) {
    $copied = 0
    foreach ($row in $selected) {
        $relative = $row.RelativePath -replace '/', '\'
        foreach ($sub in @('images','thumbs','highres')) {
            $src = Join-Path (Join-Path $OldTestRoot $sub) $relative
            $dst = Join-Path (Join-Path $OutputRoot $sub) $relative
            if (Test-Path -LiteralPath $src) {
                $dstFolder = Split-Path -Parent $dst
                if (!(Test-Path -LiteralPath $dstFolder)) {
                    New-Item -ItemType Directory -Path $dstFolder -Force | Out-Null
                }
                Copy-Item -LiteralPath $src -Destination $dst -Force
                $copied++
            }
        }
    }
    Write-Host "Copied $copied generated files into website-test-v38."
}

Write-Host ""
Write-Host "========== METADATA MODE =========="
Write-Host "Binary derivative metadata embedding: DISABLED"
Write-Host "photo_metadata.json reads directly from DigiKam/master files."
Write-Host "Metadata-only edits will not rewrite images, thumbs, or highres."
Write-Host "==================================="
Write-Host ""
Write-Host "Output root: $OutputRoot"

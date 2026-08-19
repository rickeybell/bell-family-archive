param(
    [switch]$DryRun,
    [switch]$RefreshManifest,
    [switch]$Live,
    [int]$FromYear = 0,
    [int]$ToYear = 9999
)

$ScriptVersion = "3.7"
$RepoRoot = "C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive"
$V36 = Join-Path $RepoRoot "Sync-BellWebsitePhotos-v3.6.ps1"
$ManifestCsv = Join-Path $RepoRoot "website-photo-manifest.csv"
$OutputRoot = if ($Live) { $RepoRoot } else { Join-Path $RepoRoot "website-test-v36" }
$ViewRoot = Join-Path $OutputRoot "images"
$ThumbRoot = Join-Path $OutputRoot "thumbs"

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
    param(
        [string]$ExifTool,
        [string]$Source,
        [string]$Destination,
        [string[]]$CleanTags
    )

    if (!(Test-Path -LiteralPath $Destination)) { return $false }

    $copyArgs = @(
        '-overwrite_original',
        '-TagsFromFile', $Source,
        '-DateTimeOriginal',
        '-CreateDate',
        '-GPSLatitude',
        '-GPSLongitude',
        '-GPSLatitudeRef',
        '-GPSLongitudeRef',
        '-Title',
        '-Description',
        '-Caption-Abstract',
        '-PersonInImage',
        '-RegionPersonDisplayName',
        '-Copyright',
        '-Creator',
        '-Artist',
        '-Orientation',
        $Destination
    )
    & $ExifTool @copyArgs | Out-Null
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

    return $true
}

if (!(Test-Path -LiteralPath $V36)) { throw "v3.6 script not found: $V36" }

Write-Host ""
Write-Host "Bell Family Archive Website Photo Generator v$ScriptVersion"
Write-Host "Years: $FromYear through $ToYear"
Write-Host "Metadata: genealogy fields preserved in images + thumbnails"
Write-Host "Internal Website tag: removed from public copies"
Write-Host ""

$baseArgs = @('-ExecutionPolicy','Bypass','-File',$V36,'-FromYear',$FromYear,'-ToYear',$ToYear)
if ($DryRun) { $baseArgs += '-DryRun' }
if ($RefreshManifest) { $baseArgs += '-RefreshManifest' }
if ($Live) { $baseArgs += '-Live' }
& powershell.exe @baseArgs
if ($LASTEXITCODE -ne 0) { throw "v3.6 generation failed." }

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run complete. Metadata would be copied after image generation."
    exit 0
}

if (!(Test-Path -LiteralPath $ManifestCsv)) { throw "Manifest not found: $ManifestCsv" }
$ExifTool = Get-ExifToolPath
$rows = Import-Csv -LiteralPath $ManifestCsv
$selected = @()
foreach ($row in $rows) {
    $year = Get-YearFromRelativePath $row.RelativePath
    if ($null -eq $year -or $year -lt $FromYear -or $year -gt $ToYear) { continue }
    if (!(Test-Path -LiteralPath $row.SourcePath)) { continue }
    $selected += $row
}

$stats = [ordered]@{Processed=0;ViewsTagged=0;ThumbsTagged=0;Errors=0}
foreach ($row in $selected) {
    $stats.Processed++
    $relative = $row.RelativePath -replace '/','\'
    $source = $row.SourcePath
    $view = Join-Path $ViewRoot $relative
    $thumb = Join-Path $ThumbRoot $relative
    $tags = @(Get-CleanTags $row.Tags)

    if (Copy-GenealogyMetadata -ExifTool $ExifTool -Source $source -Destination $view -CleanTags $tags) { $stats.ViewsTagged++ } else { $stats.Errors++ }
    if (Copy-GenealogyMetadata -ExifTool $ExifTool -Source $source -Destination $thumb -CleanTags $tags) { $stats.ThumbsTagged++ } else { $stats.Errors++ }

    if (($stats.Processed % 50) -eq 0) {
        Write-Host "Metadata $($stats.Processed)/$($selected.Count) | views $($stats.ViewsTagged) | thumbs $($stats.ThumbsTagged) | errors $($stats.Errors)"
    }
}

Write-Host ""
Write-Host "========== METADATA RESULTS =========="
Write-Host "Selected:             $($selected.Count)"
Write-Host "Views tagged:         $($stats.ViewsTagged)"
Write-Host "Thumbnails tagged:    $($stats.ThumbsTagged)"
Write-Host "Metadata errors:      $($stats.Errors)"
Write-Host "Website tag removed:  yes"
Write-Host "======================================"
Write-Host ""
Write-Host "Preserved fields include people, descriptive tags, title/caption, dates, GPS, copyright/creator, and orientation."

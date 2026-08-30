param(
    [switch]$DryRun,
    [switch]$RefreshManifest,
    [switch]$Live,
    [int]$FromYear = 0,
    [int]$ToYear = 9999,
    [int]$ViewMax = 1600,
    [int]$ThumbMax = 400,
    [int]$JpegQuality = 85
)

$ScriptVersion = "3.5"
$RepoRoot = $PSScriptRoot
$ManifestCsv = Join-Path $RepoRoot "website-photo-manifest.csv"
$V34 = Join-Path $RepoRoot "Sync-BellWebsitePhotos-v3.4.ps1"

if ($Live) {
    $OutputRoot = $RepoRoot
} else {
    $OutputRoot = Join-Path $RepoRoot "website-test"
}

$ThumbRoot = Join-Path $OutputRoot "thumbs"
$ViewRoot = Join-Path $OutputRoot "images"
$OriginalRoot = Join-Path $OutputRoot "originals"

function Get-YearFromRelativePath {
    param([string]$RelativePath)
    foreach ($part in ($RelativePath -split '[\\/]')) {
        if ($part -match '^(18|19|20)\d{2}$') { return [int]$part }
    }
    return $null
}

function Get-JpegEncoder {
    foreach ($codec in [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()) {
        if ($codec.MimeType -eq 'image/jpeg') { return $codec }
    }
    return $null
}

function Save-ScaledImage {
    param(
        [string]$Source,
        [string]$Destination,
        [int]$MaxDimension,
        [int]$Quality
    )

    $src = $null
    $bmp = $null
    $g = $null
    try {
        $src = [System.Drawing.Image]::FromFile($Source)
        $scale = [Math]::Min(1.0, $MaxDimension / [double][Math]::Max($src.Width, $src.Height))
        $newW = [Math]::Max(1, [int][Math]::Round($src.Width * $scale))
        $newH = [Math]::Max(1, [int][Math]::Round($src.Height * $scale))

        $bmp = New-Object System.Drawing.Bitmap($newW, $newH)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($src, 0, 0, $newW, $newH)

        $folder = Split-Path -Parent $Destination
        if (!(Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }

        $ext = [System.IO.Path]::GetExtension($Destination).ToLowerInvariant()
        if ($ext -in @('.jpg', '.jpeg')) {
            $codec = Get-JpegEncoder
            $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
            $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$Quality)
            $bmp.Save($Destination, $codec, $encParams)
            $encParams.Dispose()
        }
        elseif ($ext -eq '.png') {
            $bmp.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        elseif ($ext -in @('.tif','.tiff')) {
            $bmp.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Tiff)
        }
        else {
            $bmp.Save($Destination, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        }
    }
    finally {
        if ($g) { $g.Dispose() }
        if ($bmp) { $bmp.Dispose() }
        if ($src) { $src.Dispose() }
    }
}

Write-Host ""
Write-Host "Bell Family Archive Website Photo Generator v$ScriptVersion"
Write-Host "Mode:        $(if($Live){'LIVE'}else{'TEST'})"
Write-Host "Years:       $FromYear through $ToYear"
Write-Host "View size:   $ViewMax px max"
Write-Host "Thumb size:  $ThumbMax px max"
Write-Host "JPEG quality:$JpegQuality"
if ($DryRun) { Write-Host "*** DRY RUN - NO FILES WILL BE CREATED OR CHANGED ***" }
Write-Host ""

if ($RefreshManifest) {
    if (!(Test-Path -LiteralPath $V34)) { throw "v3.4 script not found: $V34" }
    Write-Host "Refreshing Website-tag manifest with a full metadata scan..."
    & powershell.exe -ExecutionPolicy Bypass -File $V34 -DryRun -ForceFullScan
    if ($LASTEXITCODE -ne 0) { throw "v3.4 manifest refresh failed." }
}

if (!(Test-Path -LiteralPath $ManifestCsv)) {
    throw "Website manifest not found: $ManifestCsv. Run v3.4 -DryRun -ForceFullScan first, or use -RefreshManifest."
}

Add-Type -AssemblyName System.Drawing

$rows = Import-Csv -LiteralPath $ManifestCsv
$selected = @()
foreach ($row in $rows) {
    $year = Get-YearFromRelativePath -RelativePath $row.RelativePath
    if ($null -eq $year) { continue }
    if ($year -lt $FromYear -or $year -gt $ToYear) { continue }
    if (!(Test-Path -LiteralPath $row.SourcePath)) {
        Write-Warning "Source missing: $($row.SourcePath)"
        continue
    }
    $selected += [pscustomobject]@{ Row=$row; Year=$year }
}

$sourceBytes = 0L
foreach ($item in $selected) {
    $sourceBytes += (Get-Item -LiteralPath $item.Row.SourcePath).Length
}

Write-Host ("Selected Website-tagged files: {0:N0}" -f $selected.Count)
Write-Host ("Full-resolution source size:   {0:N2} GB" -f ($sourceBytes / 1GB))
Write-Host ""

$stats = [ordered]@{Processed=0;OriginalCopied=0;ViewsCreated=0;ThumbsCreated=0;SkippedCurrent=0;Errors=0}

foreach ($item in $selected) {
    $row = $item.Row
    $relative = $row.RelativePath -replace '/', '\'
    $source = $row.SourcePath
    $origDest = Join-Path $OriginalRoot $relative
    $viewDest = Join-Path $ViewRoot $relative
    $thumbDest = Join-Path $ThumbRoot $relative

    $stats.Processed++
    if (($stats.Processed % 50) -eq 0) {
        Write-Host ("Processed {0:N0}/{1:N0} | originals {2:N0} | views {3:N0} | thumbs {4:N0}" -f $stats.Processed,$selected.Count,$stats.OriginalCopied,$stats.ViewsCreated,$stats.ThumbsCreated)
    }

    if ($DryRun) {
        Write-Host "WOULD GENERATE  $relative"
        continue
    }

    try {
        $origFolder = Split-Path -Parent $origDest
        if (!(Test-Path -LiteralPath $origFolder)) { New-Item -ItemType Directory -Path $origFolder -Force | Out-Null }

        $copyOriginal = !(Test-Path -LiteralPath $origDest)
        if (!$copyOriginal) {
            $s = Get-Item -LiteralPath $source
            $d = Get-Item -LiteralPath $origDest
            $copyOriginal = ($s.Length -ne $d.Length) -or ($s.LastWriteTimeUtc -gt $d.LastWriteTimeUtc)
        }
        if ($copyOriginal) {
            Copy-Item -LiteralPath $source -Destination $origDest -Force
            (Get-Item -LiteralPath $origDest).LastWriteTimeUtc = (Get-Item -LiteralPath $source).LastWriteTimeUtc
            $stats.OriginalCopied++
        }

        $sourceTime = (Get-Item -LiteralPath $source).LastWriteTimeUtc
        $needView = !(Test-Path -LiteralPath $viewDest) -or ((Get-Item -LiteralPath $viewDest).LastWriteTimeUtc -lt $sourceTime)
        if ($needView) {
            Save-ScaledImage -Source $source -Destination $viewDest -MaxDimension $ViewMax -Quality $JpegQuality
            (Get-Item -LiteralPath $viewDest).LastWriteTimeUtc = $sourceTime
            $stats.ViewsCreated++
        }

        $needThumb = !(Test-Path -LiteralPath $thumbDest) -or ((Get-Item -LiteralPath $thumbDest).LastWriteTimeUtc -lt $sourceTime)
        if ($needThumb) {
            Save-ScaledImage -Source $source -Destination $thumbDest -MaxDimension $ThumbMax -Quality $JpegQuality
            (Get-Item -LiteralPath $thumbDest).LastWriteTimeUtc = $sourceTime
            $stats.ThumbsCreated++
        }

        if (!$copyOriginal -and !$needView -and !$needThumb) { $stats.SkippedCurrent++ }
    }
    catch {
        $stats.Errors++
        Write-Warning "Failed $relative : $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "============== RESULTS =============="
Write-Host ("Selected:          {0:N0}" -f $selected.Count)
Write-Host ("Originals copied:  {0:N0}" -f $stats.OriginalCopied)
Write-Host ("1600px views made: {0:N0}" -f $stats.ViewsCreated)
Write-Host ("400px thumbs made: {0:N0}" -f $stats.ThumbsCreated)
Write-Host ("Already current:   {0:N0}" -f $stats.SkippedCurrent)
Write-Host ("Errors:            {0:N0}" -f $stats.Errors)
Write-Host "====================================="
Write-Host ""
Write-Host "Output root: $OutputRoot"
if (!$Live) { Write-Host "TEST MODE: live website folders were not touched." }
if ($DryRun) { Write-Host "Dry run complete. No files were created or changed." }

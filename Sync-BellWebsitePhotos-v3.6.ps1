param(
    [switch]$DryRun,
    [switch]$RefreshManifest,
    [switch]$Live,
    [int]$FromYear = 0,
    [int]$ToYear = 9999,
    [int]$PhotoViewMax = 1600,
    [int]$DocumentViewMax = 3000,
    [int]$ThumbMax = 400,
    [int]$PhotoQuality = 85,
    [int]$DocumentQuality = 90,
    [double]$HighResScale = 0.50,
    [int]$HighResMin = 3000,
    [int]$HighResQuality = 92
)

$ScriptVersion = "3.9"
$RepoRoot = "C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive"
$ManifestCsv = Join-Path $RepoRoot "website-photo-manifest.csv"
$V34 = Join-Path $RepoRoot "Sync-BellWebsitePhotos-v3.4.ps1"
$OutputRoot = if ($Live) { $RepoRoot } else { Join-Path $RepoRoot "website-test-v36" }
$ThumbRoot = Join-Path $OutputRoot "thumbs"
$ViewRoot = Join-Path $OutputRoot "images"
$HighResRoot = Join-Path $OutputRoot "highres"

function Test-DecadePlaceholderPath {
    param([string]$RelativePath)
    foreach ($part in ($RelativePath -split '[\\/]')) {
        if ($part -match '^(18|19|20)\d0s$') { return $true }
    }
    return $false
}

function Get-YearFromRelativePath {
    param([string]$RelativePath)
    foreach($part in ($RelativePath -split '[\\/]')) {
        if($part -match '^(18|19|20)\d{2}$'){ return [int]$part }
    }
    return $null
}

function Test-DocumentTag {
    param([string]$Tags)
    if ([string]::IsNullOrWhiteSpace($Tags)) { return $false }
    foreach ($raw in ($Tags -split ';')) {
        $tag = $raw.Trim()
        if (!$tag) { continue }
        $segments = $tag -split '[|/]'
        foreach ($segment in $segments) {
            $leaf = $segment.Trim()
            if ($leaf -ieq 'Document' -or $leaf -ieq 'Newspaper') { return $true }
        }
    }
    return $false
}

function Get-JpegEncoder {
    foreach($codec in [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()){
        if($codec.MimeType -eq 'image/jpeg'){ return $codec }
    }
    return $null
}

function Get-ImageMaxDimension {
    param([string]$Path)
    $img = $null
    try {
        $img = [System.Drawing.Image]::FromFile($Path)
        return [int][Math]::Max($img.Width, $img.Height)
    }
    finally {
        if ($img) { $img.Dispose() }
    }
}

function Get-HighResMaxDimension {
    param([string]$Source)
    $srcMax = Get-ImageMaxDimension $Source
    $half = [int][Math]::Round($srcMax * $HighResScale)
    $target = [int][Math]::Max($HighResMin, $half)
    return [int][Math]::Min($srcMax, $target)
}

function Test-ScaledFileNeedsBuild {
    param(
        [string]$Source,
        [string]$Destination,
        [int]$ExpectedMax
    )
    if (!(Test-Path -LiteralPath $Destination)) { return $true }
    $sourceTime = (Get-Item -LiteralPath $Source).LastWriteTimeUtc
    $destTime = (Get-Item -LiteralPath $Destination).LastWriteTimeUtc
    if ($destTime -lt $sourceTime) { return $true }

    try {
        $actual = Get-ImageMaxDimension $Destination
        # Existing derivatives from the old workflow may still be full-size.
        # Rebuild if the pixel dimensions do not match the current rule.
        if ($actual -ne $ExpectedMax) { return $true }
    }
    catch {
        return $true
    }
    return $false
}

function Save-ScaledImage {
    param([string]$Source,[string]$Destination,[int]$MaxDimension,[int]$Quality)
    $src=$null;$bmp=$null;$g=$null;$encParams=$null
    try {
        $src=[System.Drawing.Image]::FromFile($Source)
        $scale=[Math]::Min(1.0,$MaxDimension/[double][Math]::Max($src.Width,$src.Height))
        $newW=[Math]::Max(1,[int][Math]::Round($src.Width*$scale))
        $newH=[Math]::Max(1,[int][Math]::Round($src.Height*$scale))
        $bmp=New-Object System.Drawing.Bitmap($newW,$newH)
        $g=[System.Drawing.Graphics]::FromImage($bmp)
        $g.CompositingQuality=[System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($src,0,0,$newW,$newH)

        $folder=Split-Path -Parent $Destination
        if(!(Test-Path -LiteralPath $folder)){
            New-Item -ItemType Directory -Path $folder -Force|Out-Null
        }

        $ext=[System.IO.Path]::GetExtension($Destination).ToLowerInvariant()
        if($ext -in @('.jpg','.jpeg')){
            $codec=Get-JpegEncoder
            $encParams=New-Object System.Drawing.Imaging.EncoderParameters(1)
            $encParams.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter(
                [System.Drawing.Imaging.Encoder]::Quality,[long]$Quality
            )
            $bmp.Save($Destination,$codec,$encParams)
        }
        elseif($ext -eq '.png'){$bmp.Save($Destination,[System.Drawing.Imaging.ImageFormat]::Png)}
        elseif($ext -in @('.tif','.tiff')){$bmp.Save($Destination,[System.Drawing.Imaging.ImageFormat]::Tiff)}
        else{$bmp.Save($Destination,[System.Drawing.Imaging.ImageFormat]::Jpeg)}
    }
    finally {
        if($encParams){$encParams.Dispose()}
        if($g){$g.Dispose()}
        if($bmp){$bmp.Dispose()}
        if($src){$src.Dispose()}
    }
}

Write-Host ""
Write-Host "Bell Family Archive Website Photo Generator v$ScriptVersion"
Write-Host "Mode:               $(if($Live){'LIVE'}else{'TEST'})"
Write-Host "Years:              $FromYear through $ToYear"
Write-Host "Photo viewer:       $PhotoViewMax px / JPEG $PhotoQuality"
Write-Host "Document/Newspaper: $DocumentViewMax px / JPEG $DocumentQuality"
Write-Host "Thumbnail:          $ThumbMax px"
Write-Host "HighRes download:   $([int]($HighResScale*100))% master, minimum $HighResMin px, never enlarged / JPEG $HighResQuality"
Write-Host "Decade placeholders: ignored (1940s, 1980s, 2000s, etc.)"
if($DryRun){Write-Host "*** DRY RUN - NO FILES WILL BE CREATED OR CHANGED ***"}

if($RefreshManifest){
    if(!(Test-Path -LiteralPath $V34)){throw "v3.4 script not found: $V34"}
    Write-Host "Refreshing Website-tag manifest with a full metadata scan..."
    & powershell.exe -ExecutionPolicy Bypass -File $V34 -DryRun -ForceFullScan
    if($LASTEXITCODE -ne 0){throw "v3.4 manifest refresh failed."}
}
if(!(Test-Path -LiteralPath $ManifestCsv)){throw "Website manifest not found: $ManifestCsv"}

Add-Type -AssemblyName System.Drawing
$rows=Import-Csv -LiteralPath $ManifestCsv
$selected=@()
$placeholderSkipped=0

foreach($row in $rows){
    if(Test-DecadePlaceholderPath $row.RelativePath){
        $placeholderSkipped++
        continue
    }
    $year=Get-YearFromRelativePath $row.RelativePath
    if($null -eq $year -or $year -lt $FromYear -or $year -gt $ToYear){continue}
    if(!(Test-Path -LiteralPath $row.SourcePath)){
        Write-Warning "Source missing: $($row.SourcePath)"
        continue
    }
    $isDoc=Test-DocumentTag $row.Tags
    $selected += [pscustomobject]@{Row=$row;Year=$year;IsDocument=$isDoc}
}

$sourceBytes=0L
foreach($item in $selected){
    $sourceBytes+=(Get-Item -LiteralPath $item.Row.SourcePath).Length
}
$docCount=@($selected|Where-Object{$_.IsDocument}).Count
$photoCount=$selected.Count-$docCount

Write-Host ""
Write-Host "Placeholder-decade files ignored: $placeholderSkipped"
Write-Host "Selected Website-tagged files:    $($selected.Count)"
Write-Host "  Regular photos:                 $photoCount"
Write-Host "  Documents/Newspapers:           $docCount"
Write-Host ("Full-resolution master size:     {0:N2} GB`n" -f ($sourceBytes/1GB))

$stats=[ordered]@{
    Processed=0
    PhotoViews=0
    DocumentViews=0
    HighRes=0
    Thumbs=0
    Current=0
    Errors=0
}

foreach($item in $selected){
    $row=$item.Row
    $relative=$row.RelativePath -replace '/','\'
    $source=$row.SourcePath
    $viewDest=Join-Path $ViewRoot $relative
    $thumbDest=Join-Path $ThumbRoot $relative
    $highDest=Join-Path $HighResRoot $relative

    $viewMax=if($item.IsDocument){$DocumentViewMax}else{$PhotoViewMax}
    $quality=if($item.IsDocument){$DocumentQuality}else{$PhotoQuality}

    $stats.Processed++
    if(($stats.Processed%50)-eq 0){
        Write-Host "Processed $($stats.Processed)/$($selected.Count) | views $($stats.PhotoViews+$stats.DocumentViews) | highres $($stats.HighRes) | thumbs $($stats.Thumbs)"
    }

    if($DryRun){
        $highMax=Get-HighResMaxDimension $source
        Write-Host "WOULD GENERATE $relative [view $viewMax px | highres $highMax px | thumb $ThumbMax px]"
        continue
    }

    try{
        $sourceTime=(Get-Item -LiteralPath $source).LastWriteTimeUtc
        $sourceMax=Get-ImageMaxDimension $source
        $expectedView=[int][Math]::Min($sourceMax,$viewMax)
        $expectedThumb=[int][Math]::Min($sourceMax,$ThumbMax)
        $expectedHigh=Get-HighResMaxDimension $source

        $needView=Test-ScaledFileNeedsBuild $source $viewDest $expectedView
        if($needView){
            Save-ScaledImage $source $viewDest $viewMax $quality
            (Get-Item -LiteralPath $viewDest).LastWriteTimeUtc=$sourceTime
            if($item.IsDocument){$stats.DocumentViews++}else{$stats.PhotoViews++}
        }

        $needThumb=Test-ScaledFileNeedsBuild $source $thumbDest $expectedThumb
        if($needThumb){
            Save-ScaledImage $source $thumbDest $ThumbMax $PhotoQuality
            (Get-Item -LiteralPath $thumbDest).LastWriteTimeUtc=$sourceTime
            $stats.Thumbs++
        }

        $needHigh=Test-ScaledFileNeedsBuild $source $highDest $expectedHigh
        if($needHigh){
            Save-ScaledImage $source $highDest $expectedHigh $HighResQuality
            (Get-Item -LiteralPath $highDest).LastWriteTimeUtc=$sourceTime
            $stats.HighRes++
        }

        if(!$needView-and!$needThumb-and!$needHigh){$stats.Current++}
    }
    catch{
        $stats.Errors++
        Write-Warning "Failed $relative : $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "============== RESULTS =============="
Write-Host "Placeholder files ignored: $placeholderSkipped"
Write-Host "Selected:                  $($selected.Count)"
Write-Host "Regular photos:            $photoCount"
Write-Host "Documents/Newspapers:      $docCount"
Write-Host "Photo views generated:     $($stats.PhotoViews)"
Write-Host "Document views generated:  $($stats.DocumentViews)"
Write-Host "HighRes downloads:         $($stats.HighRes)"
Write-Host "Thumbnails:                $($stats.Thumbs)"
Write-Host "Already current:           $($stats.Current)"
Write-Host "Errors:                    $($stats.Errors)"
Write-Host "====================================="
Write-Host ""
Write-Host "Output root: $OutputRoot"
if(!$Live){Write-Host "TEST MODE: live website folders were not touched."}
if($DryRun){Write-Host "Dry run complete. No files were created or changed."}

if($stats.Errors -gt 0){
    throw "Generation completed with $($stats.Errors) error(s). Live cleanup/publishing should not continue."
}

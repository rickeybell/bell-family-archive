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
    [int]$DocumentQuality = 90
)

$ScriptVersion = "3.6"
$RepoRoot = "C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive"
$ManifestCsv = Join-Path $RepoRoot "website-photo-manifest.csv"
$V34 = Join-Path $RepoRoot "Sync-BellWebsitePhotos-v3.4.ps1"
$OutputRoot = if ($Live) { $RepoRoot } else { Join-Path $RepoRoot "website-test-v36" }
$ThumbRoot = Join-Path $OutputRoot "thumbs"
$ViewRoot = Join-Path $OutputRoot "images"
$OriginalRoot = Join-Path $OutputRoot "originals"

function Get-YearFromRelativePath { param([string]$RelativePath); foreach($part in ($RelativePath -split '[\\/]')) { if($part -match '^(18|19|20)\d{2}$'){ return [int]$part } }; return $null }
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
function Get-JpegEncoder { foreach($codec in [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()){if($codec.MimeType -eq 'image/jpeg'){return $codec}}; return $null }
function Save-ScaledImage {
    param([string]$Source,[string]$Destination,[int]$MaxDimension,[int]$Quality)
    $src=$null;$bmp=$null;$g=$null;$encParams=$null
    try {
        $src=[System.Drawing.Image]::FromFile($Source)
        $scale=[Math]::Min(1.0,$MaxDimension/[double][Math]::Max($src.Width,$src.Height))
        $newW=[Math]::Max(1,[int][Math]::Round($src.Width*$scale));$newH=[Math]::Max(1,[int][Math]::Round($src.Height*$scale))
        $bmp=New-Object System.Drawing.Bitmap($newW,$newH)
        $g=[System.Drawing.Graphics]::FromImage($bmp)
        $g.CompositingQuality=[System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($src,0,0,$newW,$newH)
        $folder=Split-Path -Parent $Destination;if(!(Test-Path -LiteralPath $folder)){New-Item -ItemType Directory -Path $folder -Force|Out-Null}
        $ext=[System.IO.Path]::GetExtension($Destination).ToLowerInvariant()
        if($ext -in @('.jpg','.jpeg')){$codec=Get-JpegEncoder;$encParams=New-Object System.Drawing.Imaging.EncoderParameters(1);$encParams.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality,[long]$Quality);$bmp.Save($Destination,$codec,$encParams)}
        elseif($ext -eq '.png'){$bmp.Save($Destination,[System.Drawing.Imaging.ImageFormat]::Png)}
        elseif($ext -in @('.tif','.tiff')){$bmp.Save($Destination,[System.Drawing.Imaging.ImageFormat]::Tiff)}
        else{$bmp.Save($Destination,[System.Drawing.Imaging.ImageFormat]::Jpeg)}
    } finally { if($encParams){$encParams.Dispose()};if($g){$g.Dispose()};if($bmp){$bmp.Dispose()};if($src){$src.Dispose()} }
}

Write-Host "`nBell Family Archive Website Photo Generator v$ScriptVersion"
Write-Host "Mode:              $(if($Live){'LIVE'}else{'TEST'})"
Write-Host "Years:             $FromYear through $ToYear"
Write-Host "Photo viewer:      $PhotoViewMax px / JPEG $PhotoQuality"
Write-Host "Document/Newspaper:$DocumentViewMax px / JPEG $DocumentQuality"
Write-Host "Thumbnail:         $ThumbMax px"
if($DryRun){Write-Host "*** DRY RUN - NO FILES WILL BE CREATED OR CHANGED ***"}

if($RefreshManifest){if(!(Test-Path -LiteralPath $V34)){throw "v3.4 script not found: $V34"};Write-Host "Refreshing Website-tag manifest with a full metadata scan...";& powershell.exe -ExecutionPolicy Bypass -File $V34 -DryRun -ForceFullScan;if($LASTEXITCODE -ne 0){throw "v3.4 manifest refresh failed."}}
if(!(Test-Path -LiteralPath $ManifestCsv)){throw "Website manifest not found: $ManifestCsv"}
Add-Type -AssemblyName System.Drawing
$rows=Import-Csv -LiteralPath $ManifestCsv
$selected=@()
foreach($row in $rows){$year=Get-YearFromRelativePath $row.RelativePath;if($null -eq $year -or $year -lt $FromYear -or $year -gt $ToYear){continue};if(!(Test-Path -LiteralPath $row.SourcePath)){Write-Warning "Source missing: $($row.SourcePath)";continue};$isDoc=Test-DocumentTag $row.Tags;$selected += [pscustomobject]@{Row=$row;Year=$year;IsDocument=$isDoc}}
$sourceBytes=0L;foreach($item in $selected){$sourceBytes+=(Get-Item -LiteralPath $item.Row.SourcePath).Length}
$docCount=@($selected|Where-Object{$_.IsDocument}).Count;$photoCount=$selected.Count-$docCount
Write-Host "`nSelected Website-tagged files: $($selected.Count)"
Write-Host "  Regular photos:             $photoCount"
Write-Host "  Documents/Newspapers:       $docCount"
Write-Host ("Full-resolution source size: {0:N2} GB`n" -f ($sourceBytes/1GB))
$stats=[ordered]@{Processed=0;OriginalCopied=0;PhotoViews=0;DocumentViews=0;Thumbs=0;Current=0;Errors=0}
foreach($item in $selected){
    $row=$item.Row;$relative=$row.RelativePath -replace '/','\';$source=$row.SourcePath;$origDest=Join-Path $OriginalRoot $relative;$viewDest=Join-Path $ViewRoot $relative;$thumbDest=Join-Path $ThumbRoot $relative
    $viewMax=if($item.IsDocument){$DocumentViewMax}else{$PhotoViewMax};$quality=if($item.IsDocument){$DocumentQuality}else{$PhotoQuality}
    $stats.Processed++;if(($stats.Processed%50)-eq 0){Write-Host "Processed $($stats.Processed)/$($selected.Count) | photo views $($stats.PhotoViews) | document views $($stats.DocumentViews) | thumbs $($stats.Thumbs)"}
    if($DryRun){Write-Host "WOULD GENERATE  $relative  [$(if($item.IsDocument){'DOCUMENT/NEWSPAPER'}else{'PHOTO'}) $viewMax px]";continue}
    try{
        $origFolder=Split-Path -Parent $origDest;if(!(Test-Path -LiteralPath $origFolder)){New-Item -ItemType Directory -Path $origFolder -Force|Out-Null}
        $copyOriginal=!(Test-Path -LiteralPath $origDest);if(!$copyOriginal){$s=Get-Item -LiteralPath $source;$d=Get-Item -LiteralPath $origDest;$copyOriginal=($s.Length-ne$d.Length)-or($s.LastWriteTimeUtc-gt$d.LastWriteTimeUtc)}
        if($copyOriginal){Copy-Item -LiteralPath $source -Destination $origDest -Force;(Get-Item -LiteralPath $origDest).LastWriteTimeUtc=(Get-Item -LiteralPath $source).LastWriteTimeUtc;$stats.OriginalCopied++}
        $sourceTime=(Get-Item -LiteralPath $source).LastWriteTimeUtc
        $needView=!(Test-Path -LiteralPath $viewDest)-or((Get-Item -LiteralPath $viewDest).LastWriteTimeUtc-lt$sourceTime)
        if($needView){Save-ScaledImage $source $viewDest $viewMax $quality;(Get-Item -LiteralPath $viewDest).LastWriteTimeUtc=$sourceTime;if($item.IsDocument){$stats.DocumentViews++}else{$stats.PhotoViews++}}
        $needThumb=!(Test-Path -LiteralPath $thumbDest)-or((Get-Item -LiteralPath $thumbDest).LastWriteTimeUtc-lt$sourceTime)
        if($needThumb){Save-ScaledImage $source $thumbDest $ThumbMax $PhotoQuality;(Get-Item -LiteralPath $thumbDest).LastWriteTimeUtc=$sourceTime;$stats.Thumbs++}
        if(!$copyOriginal-and!$needView-and!$needThumb){$stats.Current++}
    }catch{$stats.Errors++;Write-Warning "Failed $relative : $($_.Exception.Message)"}
}
Write-Host "`n============== RESULTS =============="
Write-Host "Selected:               $($selected.Count)"
Write-Host "Regular photos:         $photoCount"
Write-Host "Documents/Newspapers:   $docCount"
Write-Host "Originals copied:       $($stats.OriginalCopied)"
Write-Host "1600px photo views:     $($stats.PhotoViews)"
Write-Host "3000px document views:  $($stats.DocumentViews)"
Write-Host "400px thumbnails:       $($stats.Thumbs)"
Write-Host "Already current:        $($stats.Current)"
Write-Host "Errors:                 $($stats.Errors)"
Write-Host "====================================="
Write-Host "`nOutput root: $OutputRoot"
if(!$Live){Write-Host "TEST MODE: live website folders were not touched."}
if($DryRun){Write-Host "Dry run complete. No files were created or changed."}

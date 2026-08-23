# Tag-Folder-ChesterCounty.ps1
# Chester County, South Carolina GPS geofence using U.S. Census TIGERweb.
#
# Default folder: C:\Users\rbell\OneDrive\Pictures\2019
#
# REPORT mode:
#   Reads GPS from supported photos/videos and reports which files fall
#   inside Chester County. Nothing is changed.
#
# WRITE mode:
#   Photos -> adds county tag to embedded XMP AND matching .xmp sidecar
#   Videos -> leaves video untouched and adds county tag to .xmp sidecar
#   Existing tags are preserved.
#
# DigiKam fields written:
#   XMP-digiKam:TagsList
#   XMP-lr:HierarchicalSubject
#   XMP-dc:Subject

param(
    [ValidateSet('REPORT','WRITE')]
    [string]$Mode = 'REPORT',

    [string]$Root = 'C:\Users\rbell\OneDrive\Pictures\2019'
)

$LeafTag = 'Chester County'
$DigiKamTag = 'Places/South Carolina/Chester County'
$HierTag = 'Places|South Carolina|Chester County'

$ReportPath = Join-Path $Root 'GPS-Chester-County-Report.csv'
$WriteLogPath = Join-Path $Root 'GPS-Chester-County-WriteLog.csv'
$BackupRoot = 'C:\Users\rbell\OneDrive\Pictures\_Tag_Backups\Chester_County'

$PhotoExtensions = @('jpg','jpeg','heic','png','tif','tiff')
$VideoExtensions = @('mp4','mov','m4v','avi')

# U.S. Census Bureau TIGERweb, Census 2020 county layer.
# Chester County, South Carolina GEOID = 45023.
$CountyQuery = "https://tigerweb.geo.census.gov/arcgis/rest/services/Census2020/State_County/MapServer/5/query?where=GEOID%3D%2745023%27&outFields=GEOID%2CNAME%2CBASENAME&returnGeometry=true&outSR=4326&f=geojson"

function Test-PointInRing {
    param(
        [double]$Latitude,
        [double]$Longitude,
        [array]$Ring
    )

    $inside = $false
    $j = $Ring.Count - 1

    for ($i = 0; $i -lt $Ring.Count; $i++) {
        $xi = [double]$Ring[$i][0]
        $yi = [double]$Ring[$i][1]
        $xj = [double]$Ring[$j][0]
        $yj = [double]$Ring[$j][1]

        if (($yi -gt $Latitude) -ne ($yj -gt $Latitude)) {
            $xIntersect = (($xj - $xi) * ($Latitude - $yi) / ($yj - $yi)) + $xi
            if ($Longitude -lt $xIntersect) {
                $inside = -not $inside
            }
        }
        $j = $i
    }

    return $inside
}

function Test-PointInPolygonWithHoles {
    param(
        [double]$Latitude,
        [double]$Longitude,
        [array]$PolygonCoordinates
    )

    if ($PolygonCoordinates.Count -eq 0) { return $false }

    # First ring is the outer boundary.
    if (-not (Test-PointInRing -Latitude $Latitude -Longitude $Longitude -Ring $PolygonCoordinates[0])) {
        return $false
    }

    # Remaining rings are holes.
    for ($i = 1; $i -lt $PolygonCoordinates.Count; $i++) {
        if (Test-PointInRing -Latitude $Latitude -Longitude $Longitude -Ring $PolygonCoordinates[$i]) {
            return $false
        }
    }

    return $true
}

function Test-PointInGeoJsonGeometry {
    param(
        [double]$Latitude,
        [double]$Longitude,
        $Geometry
    )

    if ($Geometry.type -eq 'Polygon') {
        return Test-PointInPolygonWithHoles `
            -Latitude $Latitude `
            -Longitude $Longitude `
            -PolygonCoordinates $Geometry.coordinates
    }

    if ($Geometry.type -eq 'MultiPolygon') {
        foreach ($polygon in $Geometry.coordinates) {
            if (Test-PointInPolygonWithHoles `
                -Latitude $Latitude `
                -Longitude $Longitude `
                -PolygonCoordinates $polygon) {
                return $true
            }
        }
        return $false
    }

    throw "Unsupported GeoJSON geometry type: $($Geometry.type)"
}

function Get-FileKind {
    param([string]$Extension)
    $e = $Extension.ToLowerInvariant()
    if ($PhotoExtensions -contains $e) { return 'Photo' }
    if ($VideoExtensions -contains $e) { return 'Video' }
    return 'Other'
}


function Test-HasFishingCreekTag {
    param(
        [string]$MediaPath,
        [string]$FileKind
    )

    $targets = @($MediaPath)

    # For videos, DigiKam tags are normally in the sidecar.
    # For photos, check both embedded metadata and sidecar if present.
    $sidecar = "$MediaPath.xmp"
    if (Test-Path -LiteralPath $sidecar) {
        $targets += $sidecar
    }

    foreach ($target in $targets) {
        $meta = (& $script:ExifTool.Source -json `
            -XMP-digiKam:TagsList `
            -XMP-lr:HierarchicalSubject `
            -XMP-dc:Subject `
            $target) | ConvertFrom-Json

        $allTags = @()
        $allTags += @($meta[0].TagsList)
        $allTags += @($meta[0].HierarchicalSubject)
        $allTags += @($meta[0].Subject)

        foreach ($tag in $allTags) {
            if ([string]$tag -match '(?i)(^|[/|])Fishing Creek($|[/|])' -or
                [string]$tag -ieq 'Fishing Creek') {
                return $true
            }
        }
    }

    return $false
}

function Add-TagsToTarget {
    param(
        [string]$Target,
        [bool]$PreserveTimestamp
    )

    $meta = (& $script:ExifTool.Source -json `
        -XMP-digiKam:TagsList `
        -XMP-lr:HierarchicalSubject `
        -XMP-dc:Subject `
        $Target) | ConvertFrom-Json

    $currentDigiKam = @($meta[0].TagsList)
    $currentHier = @($meta[0].HierarchicalSubject)
    $currentSubject = @($meta[0].Subject)

    $args = @('-overwrite_original')
    if ($PreserveTimestamp) {
        $args = @('-P','-overwrite_original')
    }

    if ($currentDigiKam -notcontains $script:DigiKamTag) {
        $args += "-XMP-digiKam:TagsList+=$($script:DigiKamTag)"
    }
    if ($currentHier -notcontains $script:HierTag) {
        $args += "-XMP-lr:HierarchicalSubject+=$($script:HierTag)"
    }
    if ($currentSubject -notcontains $script:LeafTag) {
        $args += "-XMP-dc:Subject+=$($script:LeafTag)"
    }

    $baseCount = if ($PreserveTimestamp) { 2 } else { 1 }

    if ($args.Count -eq $baseCount) {
        return 'Already tagged'
    }

    $args += $Target
    & $script:ExifTool.Source @args | Out-Null

    if ($LASTEXITCODE -eq 0) {
        return 'Tagged'
    }

    return 'ERROR'
}

Write-Host ""
Write-Host "Bell Family Archive - Chester County GPS Geofence" -ForegroundColor Cyan
Write-Host "Mode   : $Mode"
Write-Host "Folder : $Root"
Write-Host "Tag    : $DigiKamTag"
Write-Host ""

$ExifTool = Get-Command exiftool -ErrorAction SilentlyContinue
if (-not $ExifTool) {
    Write-Host "ERROR: ExifTool was not found in PATH." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $Root)) {
    Write-Host "ERROR: Folder does not exist: $Root" -ForegroundColor Red
    exit 1
}

Write-Host "Downloading official Chester County boundary from U.S. Census TIGERweb..." -ForegroundColor Cyan

try {
    $CountyGeoJson = Invoke-RestMethod -Uri $CountyQuery -Method Get
}
catch {
    Write-Host "ERROR: Could not download the Chester County boundary." -ForegroundColor Red
    Write-Host $_
    exit 1
}

if (-not $CountyGeoJson.features -or $CountyGeoJson.features.Count -lt 1) {
    Write-Host "ERROR: Census TIGERweb returned no Chester County feature." -ForegroundColor Red
    exit 1
}

$CountyGeometry = $CountyGeoJson.features[0].geometry

Write-Host "Boundary loaded successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Reading GPS from supported photos/videos..." -ForegroundColor Cyan

$ExifArgs = @(
    '-json','-n',
    '-GPSLatitude','-GPSLongitude',
    '-FileName','-Directory','-FileTypeExtension'
)

foreach ($ext in ($PhotoExtensions + $VideoExtensions)) {
    $ExifArgs += @('-ext', $ext)
}
$ExifArgs += @('-r', $Root)

try {
    $Items = (& $ExifTool.Source @ExifArgs) | ConvertFrom-Json
}
catch {
    Write-Host "ERROR: Could not read ExifTool output." -ForegroundColor Red
    exit 1
}

$Rows = @()

foreach ($Item in $Items) {
    $kind = Get-FileKind -Extension ([string]$Item.FileTypeExtension)
    $fullPath = Join-Path $Item.Directory $Item.FileName
    $hasGps = ($null -ne $Item.GPSLatitude -and $null -ne $Item.GPSLongitude)

    if (-not $hasGps) {
        $Rows += [PSCustomObject]@{
            FileName = $Item.FileName
            FileType = $kind
            FullPath = $fullPath
            HasGPS = 'NO'
            Latitude = ''
            Longitude = ''
            InChesterCounty = 'NO'
            FishingCreek = ''
            ProposedTag = ''
        }
        continue
    }

    $lat = [double]$Item.GPSLatitude
    $lon = [double]$Item.GPSLongitude

    $inside = Test-PointInGeoJsonGeometry `
        -Latitude $lat `
        -Longitude $lon `
        -Geometry $CountyGeometry

    $hasFishingCreek = Test-HasFishingCreekTag -MediaPath $fullPath -FileKind $kind

    $Rows += [PSCustomObject]@{
        FileName = $Item.FileName
        FileType = $kind
        FullPath = $fullPath
        HasGPS = 'YES'
        Latitude = [Math]::Round($lat,7)
        Longitude = [Math]::Round($lon,7)
        InChesterCounty = if ($inside) { 'YES' } else { 'NO' }
        FishingCreek = if ($hasFishingCreek) { 'YES' } else { 'NO' }
        ProposedTag = if ($inside -and -not $hasFishingCreek) { $DigiKamTag } else { '' }
    }
}

$Rows | Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding UTF8

$total = $Rows.Count
$gpsCount = @($Rows | Where-Object { $_.HasGPS -eq 'YES' }).Count
$insideCounty = @($Rows | Where-Object { $_.InChesterCounty -eq 'YES' })
$skippedFishingCreek = @($insideCounty | Where-Object { $_.FishingCreek -eq 'YES' })
$matches = @($insideCounty | Where-Object { $_.FishingCreek -ne 'YES' })
$photoMatches = @($matches | Where-Object { $_.FileType -eq 'Photo' }).Count
$videoMatches = @($matches | Where-Object { $_.FileType -eq 'Video' }).Count

Write-Host ""
Write-Host "REPORT SUMMARY" -ForegroundColor Cyan
Write-Host "Total supported files : $total"
Write-Host "Files with GPS        : $gpsCount"
Write-Host "Inside Chester County : $($insideCounty.Count)"
Write-Host "Skipped Fishing Creek : $($skippedFishingCreek.Count)"
Write-Host "Will tag Chester Cnty : $($matches.Count)"
Write-Host "  Photos              : $photoMatches"
Write-Host "  Videos              : $videoMatches"
Write-Host "Report                : $ReportPath"

if ($Mode -eq 'REPORT') {
    Write-Host ""
    Write-Host "REPORT mode only. Nothing was modified." -ForegroundColor Yellow
    Write-Host "After reviewing the CSV, run with -Mode WRITE." -ForegroundColor Cyan
    exit 0
}

if ($matches.Count -eq 0) {
    Write-Host ""
    Write-Host "No GPS files matched Chester County. Nothing to write." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "WRITE mode will:" -ForegroundColor Yellow
Write-Host "  Photos: tag image AND .xmp sidecar"
Write-Host "  Videos: tag .xmp sidecar only; video file is untouched"
Write-Host "  Existing tags will be preserved"
Write-Host ""
$answer = Read-Host "Type YES to continue"

if ($answer -cne 'YES') {
    Write-Host "Cancelled. Nothing was changed." -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

$WriteLog = @()
$changed = 0
$already = 0
$errors = 0

foreach ($row in $matches) {
    if ($row.FileType -eq 'Video') {
        $sidecar = "$($row.FullPath).xmp"
        $backup = ''

        if (Test-Path -LiteralPath $sidecar) {
            $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $backupName = (($row.FileName + "_$stamp.xmp") -replace '[\\/:*?"<>|]', '_')
            $backup = Join-Path $BackupRoot $backupName
            Copy-Item -LiteralPath $sidecar -Destination $backup
        }
        else {
            & $ExifTool.Source -o $sidecar $row.FullPath | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sidecar)) {
                $errors++
                $WriteLog += [PSCustomObject]@{
                    FileName = $row.FileName
                    FileType = 'Video'
                    Result = 'ERROR creating sidecar'
                    PhotoResult = ''
                    SidecarResult = ''
                    Backup = ''
                }
                continue
            }
        }

        $sidecarResult = Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false

        if ($sidecarResult -eq 'Tagged') { $changed++ }
        elseif ($sidecarResult -eq 'Already tagged') { $already++ }
        else { $errors++ }

        $WriteLog += [PSCustomObject]@{
            FileName = $row.FileName
            FileType = 'Video'
            Result = $sidecarResult
            PhotoResult = ''
            SidecarResult = $sidecarResult
            Backup = $backup
        }
    }
    elseif ($row.FileType -eq 'Photo') {
        $photo = $row.FullPath
        $sidecar = "$photo.xmp"

        # Backup original photo.
        $relative = $photo.Substring($Root.Length).TrimStart('\')
        $photoBackup = Join-Path $BackupRoot ($relative -replace '[\\/:*?"<>|]', '_')
        if (-not (Test-Path -LiteralPath $photoBackup)) {
            Copy-Item -LiteralPath $photo -Destination $photoBackup
        }

        # Backup existing sidecar or create one from the photo.
        $sidecarBackup = ''
        if (Test-Path -LiteralPath $sidecar) {
            $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $sidecarBackup = Join-Path $BackupRoot ((($row.FileName + "_$stamp.xmp")) -replace '[\\/:*?"<>|]', '_')
            Copy-Item -LiteralPath $sidecar -Destination $sidecarBackup
        }
        else {
            & $ExifTool.Source -o $sidecar $photo | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sidecar)) {
                $errors++
                $WriteLog += [PSCustomObject]@{
                    FileName = $row.FileName
                    FileType = 'Photo'
                    Result = 'ERROR creating photo sidecar'
                    PhotoResult = ''
                    SidecarResult = ''
                    Backup = $photoBackup
                }
                continue
            }
        }

        $photoResult = Add-TagsToTarget -Target $photo -PreserveTimestamp:$true
        $sidecarResult = Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false

        if ($photoResult -eq 'ERROR' -or $sidecarResult -eq 'ERROR') {
            $errors++
            $overall = 'ERROR'
        }
        elseif ($photoResult -eq 'Already tagged' -and $sidecarResult -eq 'Already tagged') {
            $already++
            $overall = 'Already tagged'
        }
        else {
            $changed++
            $overall = 'Tagged'
        }

        $WriteLog += [PSCustomObject]@{
            FileName = $row.FileName
            FileType = 'Photo'
            Result = $overall
            PhotoResult = $photoResult
            SidecarResult = $sidecarResult
            Backup = "$photoBackup | $sidecarBackup"
        }
    }
}

$WriteLog | Export-Csv -LiteralPath $WriteLogPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "WRITE COMPLETE" -ForegroundColor Green
Write-Host "Changed        : $changed"
Write-Host "Already tagged : $already"
Write-Host "Errors         : $errors"
Write-Host "Write log      : $WriteLogPath"
Write-Host "Backups        : $BackupRoot"
Write-Host ""
Write-Host "Then use DigiKam: Reread Metadata From File for the folder." -ForegroundColor Cyan

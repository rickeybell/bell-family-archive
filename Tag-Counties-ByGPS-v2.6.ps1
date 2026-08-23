param(
    [ValidateSet('REPORT','WRITE')]
    [string]$Mode = 'REPORT',

    [string]$Root = 'C:\Users\rbell\OneDrive\Pictures\2019',

    [switch]$NoRecurse
)

# v2.6: safer video sidecar handling. Existing .xmp sidecars are never recreated;
# they are backed up and updated additively. Missing video sidecars are created
# from the video's readable metadata before location/Video tags are appended.

# -----------------------------
# County definitions
# -----------------------------

$Counties = @(
    @{
        Name = 'Lancaster County'
        GeoId = '45057'
        LeafTag = 'Lancaster County'
        DigiKamTag = 'Places/South Carolina/Lancaster County'
        HierTag = 'Places|South Carolina|Lancaster County'
        ProtectedParents = @(
            'Lancaster County'
        )
    },
    @{
        Name = 'Chester County'
        GeoId = '45023'
        LeafTag = 'Chester County'
        DigiKamTag = 'Places/South Carolina/Chester County'
        HierTag = 'Places|South Carolina|Chester County'
        ProtectedParents = @(
            'Chester County',
            'Lancaster County'
        )
    },
    @{
        Name = 'York County'
        GeoId = '45091'
        LeafTag = 'York County'
        DigiKamTag = 'Places/South Carolina/York County'
        HierTag = 'Places|South Carolina|York County'
        ProtectedParents = @(
            'York County'
        )
    }
)

# Existing Confederate Avenue geofences carried forward from
# Tag-2022-20220506_173635-900-or-910-to-900-v3.ps1.
# Points are [Longitude, Latitude]. These rules are evaluated BEFORE county rules.
$ConfederateProperties = @(
    @{
        Name = '900 Confederate Ave'
        LeafTag = '900 Confederate Ave'
        DigiKamTag = 'Places/South Carolina/Lancaster County/900 Confederate Ave'
        HierTag = 'Places|South Carolina|Lancaster County|900 Confederate Ave'
        Polygon = @(
            @(-80.82542616455852, 34.69375765889696),
            @(-80.82484058767655, 34.69366359372555),
            @(-80.82499864827452, 34.69310043816064),
            @(-80.82558121447842, 34.69319202855739)
        )
    },
    @{
        Name = '910 Confederate Ave (map zone -> tag as 900)'
        LeafTag = '900 Confederate Ave'
        DigiKamTag = 'Places/South Carolina/Lancaster County/900 Confederate Ave'
        HierTag = 'Places|South Carolina|Lancaster County|900 Confederate Ave'
        Polygon = @(
            @(-80.82489026386473, 34.69366606912564),
            @(-80.82457564800784, 34.69361037259382),
            @(-80.82473069792773, 34.69305092979534),
            @(-80.82507240988713, 34.69309796274259)
        )
    },
    @{
        Name = '909 Confederate Ave'
        LeafTag = '909 Confederate Ave'
        DigiKamTag = 'Places/South Carolina/Lancaster County/909 Confederate Ave'
        HierTag = 'Places|South Carolina|Lancaster County|909 Confederate Ave'
        Polygon = @(
            @(-80.82485714639385, 34.69404604224939),
            @(-80.8245184451125, 34.69399034597329),
            @(-80.82461027079323, 34.69362274961097),
            @(-80.82494295071847, 34.69368463463474)
        )
    }
)

# Specific home geofence. This rule is evaluated BEFORE the county rules.
$CommunityLane = @{
    Name = '973 Community Lane'
    LeafTag = '973 Community Lane Deb_Irvin_Rickey_Jarred Home'
    DigiKamTag = 'Places/South Carolina/Lancaster County/973 Community Lane Deb_Irvin_Rickey_Jarred Home'
    HierTag = 'Places|South Carolina|Lancaster County|973 Community Lane Deb_Irvin_Rickey_Jarred Home'
    Latitude = 34.69869762098045
    Longitude = -80.70731253886053
    RadiusMeters = 152.4
}

# Specific Lancaster County address geofence. Evaluated before county rules.
$DouglasRoad = @{
    Name = '2044 Douglas Rd'
    LeafTag = '2044 Douglas Rd'
    DigiKamTag = 'Places/South Carolina/Lancaster County/2044 Douglas Rd'
    HierTag = 'Places|South Carolina|Lancaster County|2044 Douglas Rd'
    Latitude = 34.66143050673542
    Longitude = -80.78170258416881
    RadiusMeters = 152.4   # 500 ft
    ProtectedParents = @()
}

# Specific Chester County Sub Fiber geofence. Evaluated before county rules.
$SubFiber = @{
    Name = 'Sub Fiber'
    LeafTag = 'Sub Fiber'
    DigiKamTag = 'Places/South Carolina/Chester County/Sub Fiber'
    HierTag = 'Places|South Carolina|Chester County|Sub Fiber'
    Latitude = 34.75524566161995
    Longitude = -81.04388245618165
    RadiusMeters = 304.8   # 1000 ft
}

# Florida rules. Crystal River is checked before the generic Florida state rule.
$CrystalRiver = @{
    Name = 'Crystal River'
    LeafTag = 'Crystal River'
    DigiKamTag = 'Places/Florida/Crystal River'
    HierTag = 'Places|Florida|Crystal River'
    Latitude = 28.902479
    Longitude = -82.5926012
    RadiusMeters = 32186.88   # 20 miles
    ProtectedParents = @()
}

$Florida = @{
    Name = 'Florida'
    GeoId = '12'
    LeafTag = 'Florida'
    DigiKamTag = 'Places/Florida'
    HierTag = 'Places|Florida'
    ProtectedParents = @()
}

# Generic media-type tag applied to every supported video.
$VideoTag = @{
    Name = 'Video'
    LeafTag = 'Video'
    DigiKamTag = 'Video'
    HierTag = 'Video'
}

$PhotoExtensions = @('jpg','jpeg','heic','png','tif','tiff')
$VideoExtensions = @('mp4','mov','m4v','avi')

$ReportPath = Join-Path $Root 'GPS-County-Geofence-Report.csv'
$WriteLogPath = Join-Path $Root 'GPS-County-Geofence-WriteLog.csv'
$BackupRoot = Join-Path (Split-Path $Root -Parent) '_Tag_Backups\County_GPS_Tagging'

# -----------------------------
# Geometry helpers
# -----------------------------

function Test-PointInRing {
    param([double]$Latitude,[double]$Longitude,[array]$Ring)

    $inside = $false
    $j = $Ring.Count - 1

    for ($i=0; $i -lt $Ring.Count; $i++) {
        $xi=[double]$Ring[$i][0]
        $yi=[double]$Ring[$i][1]
        $xj=[double]$Ring[$j][0]
        $yj=[double]$Ring[$j][1]

        if (($yi -gt $Latitude) -ne ($yj -gt $Latitude)) {
            $xIntersect=(($xj-$xi)*($Latitude-$yi)/($yj-$yi))+$xi
            if ($Longitude -lt $xIntersect) {
                $inside = -not $inside
            }
        }
        $j=$i
    }

    return $inside
}

function Test-PointInPolygonWithHoles {
    param([double]$Latitude,[double]$Longitude,[array]$PolygonCoordinates)

    if ($PolygonCoordinates.Count -eq 0) { return $false }

    if (-not (Test-PointInRing -Latitude $Latitude -Longitude $Longitude -Ring $PolygonCoordinates[0])) {
        return $false
    }

    for ($i=1; $i -lt $PolygonCoordinates.Count; $i++) {
        if (Test-PointInRing -Latitude $Latitude -Longitude $Longitude -Ring $PolygonCoordinates[$i]) {
            return $false
        }
    }

    return $true
}

function Test-PointInGeoJsonGeometry {
    param([double]$Latitude,[double]$Longitude,$Geometry)

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

function Get-DistanceMeters {
    param(
        [double]$Lat1,
        [double]$Lon1,
        [double]$Lat2,
        [double]$Lon2
    )

    $earthRadius = 6371000.0
    $lat1Rad = $Lat1 * [Math]::PI / 180.0
    $lat2Rad = $Lat2 * [Math]::PI / 180.0
    $deltaLat = ($Lat2 - $Lat1) * [Math]::PI / 180.0
    $deltaLon = ($Lon2 - $Lon1) * [Math]::PI / 180.0

    $a =
        [Math]::Sin($deltaLat / 2.0) * [Math]::Sin($deltaLat / 2.0) +
        [Math]::Cos($lat1Rad) * [Math]::Cos($lat2Rad) *
        [Math]::Sin($deltaLon / 2.0) * [Math]::Sin($deltaLon / 2.0)

    $c = 2.0 * [Math]::Atan2(
        [Math]::Sqrt($a),
        [Math]::Sqrt(1.0 - $a)
    )

    return $earthRadius * $c
}

# -----------------------------
# Metadata helpers
# -----------------------------

function Get-FileKind {
    param([string]$Extension)

    $e=$Extension.ToLowerInvariant()

    if ($PhotoExtensions -contains $e) { return 'Photo' }
    if ($VideoExtensions -contains $e) { return 'Video' }

    return 'Other'
}

function New-VideoSidecarFromMedia {
    param(
        [string]$MediaPath,
        [string]$SidecarPath
    )

    # Never replace an existing DigiKam sidecar. Existing sidecars are
    # backed up by the caller and then updated additively by Add-TagsToTarget.
    if (Test-Path -LiteralPath $SidecarPath) {
        return 'Existing'
    }

    # Create a new XMP sidecar from metadata ExifTool can map from the video.
    # The video itself is never modified by this operation.
    & $script:ExifTool.Source -o $SidecarPath $MediaPath | Out-Null

    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $SidecarPath)) {
        return 'Created'
    }

    return 'ERROR'
}

function Get-AllTagsFromTarget {
    param([string]$Target)

    if (-not (Test-Path -LiteralPath $Target)) {
        return @()
    }

    $meta = (& $script:ExifTool.Source -json `
        -XMP-digiKam:TagsList `
        -XMP-lr:HierarchicalSubject `
        -XMP-dc:Subject `
        -XMP-MicrosoftPhoto:LastKeywordXMP `
        -IPTC:Keywords `
        $Target) | ConvertFrom-Json

    $all=@()
    $all += @($meta[0].TagsList)
    $all += @($meta[0].HierarchicalSubject)
    $all += @($meta[0].Subject)
    $all += @($meta[0].LastKeywordXMP)
    $all += @($meta[0].Keywords)

    return @(
        $all | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        }
    )
}

function Get-AllTagsForMedia {
    param([string]$MediaPath)

    $all=@()
    $all += Get-AllTagsFromTarget -Target $MediaPath

    $sidecar="$MediaPath.xmp"

    if (Test-Path -LiteralPath $sidecar) {
        $all += Get-AllTagsFromTarget -Target $sidecar
    }

    return @($all)
}

function Get-ProtectedChildTags {
    param(
        [string]$MediaPath,
        [array]$ProtectedParents
    )

    $allTags = Get-AllTagsForMedia -MediaPath $MediaPath
    $found=@()

    foreach ($tag in $allTags) {
        $t=[string]$tag

        foreach ($parent in $ProtectedParents) {
            $escaped=[regex]::Escape($parent)
            $pattern="(?i)Places[/|]South Carolina[/|]$escaped[/|][^,]+"

            foreach ($m in [regex]::Matches($t,$pattern)) {
                $found += $m.Value.Trim()
            }
        }
    }

    return @($found | Sort-Object -Unique)
}

function Test-AlreadyHasCountyTag {
    param(
        [string]$MediaPath,
        [hashtable]$County
    )

    $allTags = Get-AllTagsForMedia -MediaPath $MediaPath

    foreach ($tag in $allTags) {
        $t=[string]$tag

        if ($t -ieq $County.LeafTag -or
            $t -ieq $County.DigiKamTag -or
            $t -ieq $County.HierTag) {
            return $true
        }
    }

    return $false
}

function Add-TagsToTarget {
    param(
        [string]$Target,
        [bool]$PreserveTimestamp,
        [hashtable]$County
    )

    $meta = (& $script:ExifTool.Source -json `
        -XMP-digiKam:TagsList `
        -XMP-lr:HierarchicalSubject `
        -XMP-dc:Subject `
        $Target) | ConvertFrom-Json

    $currentDigiKam=@($meta[0].TagsList)
    $currentHier=@($meta[0].HierarchicalSubject)
    $currentSubject=@($meta[0].Subject)

    $args=@('-overwrite_original')

    if ($PreserveTimestamp) {
        $args=@('-P','-overwrite_original')
    }

    if ($currentDigiKam -notcontains $County.DigiKamTag) {
        $args += "-XMP-digiKam:TagsList+=$($County.DigiKamTag)"
    }

    if ($currentHier -notcontains $County.HierTag) {
        $args += "-XMP-lr:HierarchicalSubject+=$($County.HierTag)"
    }

    if ($currentSubject -notcontains $County.LeafTag) {
        $args += "-XMP-dc:Subject+=$($County.LeafTag)"
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

function Set-GpsOnPhoto {
    param(
        [string]$Target,
        [double]$Latitude,
        [double]$Longitude
    )

    $latRef = if ($Latitude -lt 0) { 'S' } else { 'N' }
    $lonRef = if ($Longitude -lt 0) { 'W' } else { 'E' }
    $latAbs = [Math]::Abs($Latitude)
    $lonAbs = [Math]::Abs($Longitude)

    & $script:ExifTool.Source `
        -P `
        -overwrite_original `
        "-GPSLatitude=$latAbs" `
        "-GPSLatitudeRef=$latRef" `
        "-GPSLongitude=$lonAbs" `
        "-GPSLongitudeRef=$lonRef" `
        $Target | Out-Null

    if ($LASTEXITCODE -eq 0) {
        return 'GPS written'
    }

    return 'ERROR'
}

function Set-GpsOnSidecar {
    param(
        [string]$Target,
        [double]$Latitude,
        [double]$Longitude
    )

    & $script:ExifTool.Source `
        -overwrite_original `
        "-XMP-exif:GPSLatitude=$Latitude" `
        "-XMP-exif:GPSLongitude=$Longitude" `
        $Target | Out-Null

    if ($LASTEXITCODE -eq 0) {
        return 'GPS written'
    }

    return 'ERROR'
}

# -----------------------------
# Setup
# -----------------------------

Write-Host ""
Write-Host "Bell Family Archive - Combined Property + County GPS Geotagger v2.6" -ForegroundColor Cyan
Write-Host "Mode   : $Mode"
Write-Host "Folder : $Root"
Write-Host "Recurse: $(if ($NoRecurse) { 'NO' } else { 'YES' })"
Write-Host "Confederate Ave     : existing 900/910->900 and 909 polygon rules"
Write-Host "973 Community Lane: $($CommunityLane.Latitude), $($CommunityLane.Longitude) / 500 ft"
Write-Host "2044 Douglas Rd    : $($DouglasRoad.Latitude), $($DouglasRoad.Longitude) / 500 ft"
Write-Host "Sub Fiber          : $($SubFiber.Latitude), $($SubFiber.Longitude) / 1000 ft"
Write-Host "Crystal River      : $($CrystalRiver.Latitude), $($CrystalRiver.Longitude) / 20 miles"
Write-Host "Florida            : anywhere else in Florida -> Places/Florida"
Write-Host "Videos             : add Video tag"
Write-Host ""

$ExifTool=Get-Command exiftool -ErrorAction SilentlyContinue

if (-not $ExifTool) {
    Write-Host "ERROR: ExifTool was not found in PATH." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $Root)) {
    Write-Host "ERROR: Folder does not exist: $Root" -ForegroundColor Red
    exit 1
}

# -----------------------------
# Load county boundaries
# -----------------------------

foreach ($County in $Counties) {
    Write-Host "Downloading $($County.Name) boundary..." -ForegroundColor Cyan

    $query="https://tigerweb.geo.census.gov/arcgis/rest/services/Census2020/State_County/MapServer/5/query?where=GEOID%3D%27$($County.GeoId)%27&outFields=GEOID%2CNAME%2CBASENAME&returnGeometry=true&outSR=4326&f=geojson"

    try {
        $geo=Invoke-RestMethod -Uri $query -Method Get
    }
    catch {
        Write-Host "ERROR: Could not download $($County.Name) boundary." -ForegroundColor Red
        Write-Host $_
        exit 1
    }

    if (-not $geo.features -or $geo.features.Count -lt 1) {
        Write-Host "ERROR: No geometry returned for $($County.Name)." -ForegroundColor Red
        exit 1
    }

    $County.Geometry=$geo.features[0].geometry
}

Write-Host "All county boundaries loaded successfully." -ForegroundColor Green
Write-Host ""

# Load Florida state boundary from Census TIGERweb.
Write-Host "Downloading Florida state boundary..." -ForegroundColor Cyan
$flQuery="https://tigerweb.geo.census.gov/arcgis/rest/services/Census2020/State_County/MapServer/4/query?where=GEOID%3D%27$($Florida.GeoId)%27&outFields=GEOID%2CNAME&returnGeometry=true&outSR=4326&f=geojson"
try {
    $flGeo=Invoke-RestMethod -Uri $flQuery -Method Get
}
catch {
    Write-Host "ERROR: Could not download Florida state boundary." -ForegroundColor Red
    Write-Host $_
    exit 1
}
if (-not $flGeo.features -or $flGeo.features.Count -lt 1) {
    Write-Host "ERROR: No geometry returned for Florida." -ForegroundColor Red
    exit 1
}
$Florida.Geometry=$flGeo.features[0].geometry
Write-Host "Florida state boundary loaded successfully." -ForegroundColor Green
Write-Host ""

# -----------------------------
# Scan media once
# -----------------------------

Write-Host "Reading GPS from supported photos/videos..." -ForegroundColor Cyan

$ExifArgs=@(
    '-json','-n',
    '-GPSLatitude','-GPSLongitude',
    '-FileName','-Directory','-FileTypeExtension'
)

foreach ($ext in ($PhotoExtensions+$VideoExtensions)) {
    $ExifArgs += @('-ext',$ext)
}

if ($NoRecurse) {
    $ExifArgs += $Root
}
else {
    $ExifArgs += @('-r',$Root)
}

$Items=(& $ExifTool.Source @ExifArgs) | ConvertFrom-Json
$Rows=@()

foreach ($Item in $Items) {
    $kind=Get-FileKind -Extension ([string]$Item.FileTypeExtension)
    $fullPath=Join-Path $Item.Directory $Item.FileName

    $hasGps=(
        $null -ne $Item.GPSLatitude -and
        $null -ne $Item.GPSLongitude
    )

    $hasVideoTag=$false
    $videoTagNeeded=$false
    if ($kind -eq 'Video') {
        $hasVideoTag=Test-AlreadyHasCountyTag -MediaPath $fullPath -County $VideoTag
        $videoTagNeeded=(-not $hasVideoTag)
    }

    if (-not $hasGps) {
        $hasCommunityLaneTag=Test-AlreadyHasCountyTag `
            -MediaPath $fullPath `
            -County $CommunityLane

        if ($hasCommunityLaneTag -and $kind -eq 'Photo') {
            $action='EMBED GPS 973 Community Lane'
            $proposed=$CommunityLane.DigiKamTag
            $countyMatch='Lancaster County'
        }
        elseif ($hasCommunityLaneTag -and $kind -eq 'Video') {
            $action='REVIEW - 973 tag but video has no GPS'
            $proposed=''
            $countyMatch='Lancaster County'
        }
        else {
            $action='No GPS'
            $proposed=''
            $countyMatch=''
        }

        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName
            FileType=$kind
            FullPath=$fullPath
            HasGPS='NO'
            Latitude=''
            Longitude=''
            DistanceTo973Ft=''
            DistanceToDouglasFt=''
            DistanceToSubFiberFt=''
            ConfederateMatch=''
            CountyMatch=$countyMatch
            ProtectedChildLocation=''
            AlreadyCountyTag=''
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action=$action
            ProposedTag=$proposed
        }
        continue
    }

    $lat=[double]$Item.GPSLatitude
    $lon=[double]$Item.GPSLongitude

    # Specific-home rule is intentionally checked before county classification.
    $distanceMeters=Get-DistanceMeters `
        -Lat1 $lat `
        -Lon1 $lon `
        -Lat2 $CommunityLane.Latitude `
        -Lon2 $CommunityLane.Longitude

    $distanceFeet=$distanceMeters * 3.280839895

    $douglasDistanceMeters=Get-DistanceMeters `
        -Lat1 $lat `
        -Lon1 $lon `
        -Lat2 $DouglasRoad.Latitude `
        -Lon2 $DouglasRoad.Longitude

    $douglasDistanceFeet=$douglasDistanceMeters * 3.280839895

    $subFiberDistanceMeters=Get-DistanceMeters `
        -Lat1 $lat `
        -Lon1 $lon `
        -Lat2 $SubFiber.Latitude `
        -Lon2 $SubFiber.Longitude

    $subFiberDistanceFeet=$subFiberDistanceMeters * 3.280839895

    $crystalRiverDistanceMeters=Get-DistanceMeters `
        -Lat1 $lat `
        -Lon1 $lon `
        -Lat2 $CrystalRiver.Latitude `
        -Lon2 $CrystalRiver.Longitude

    $crystalRiverDistanceMiles=$crystalRiverDistanceMeters / 1609.344

    # Existing Confederate Avenue property polygons are checked before all county rules.
    $confederateMatches=@()
    foreach ($Property in $ConfederateProperties) {
        if (Test-PointInRing -Latitude $lat -Longitude $lon -Ring $Property.Polygon) {
            $confederateMatches += $Property
        }
    }

    if ($confederateMatches.Count -gt 0) {
        # 900 and the old 910 map zone intentionally produce the same 900 tag.
        $uniqueConfederateTags=@($confederateMatches | ForEach-Object { $_.DigiKamTag } | Sort-Object -Unique)

        if ($uniqueConfederateTags.Count -gt 1) {
            $Rows += [PSCustomObject]@{
                FileName=$Item.FileName
                FileType=$kind
                FullPath=$fullPath
                HasGPS='YES'
                Latitude=[Math]::Round($lat,7)
                Longitude=[Math]::Round($lon,7)
                DistanceTo973Ft=[Math]::Round($distanceFeet,1)
                DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1)
                DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
                ConfederateMatch=($confederateMatches.Name -join ' | ')
                CountyMatch='Lancaster County'
                ProtectedChildLocation=''
                AlreadyCountyTag=''
                VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
                Action='REVIEW - overlapping Confederate zones map to different tags'
                ProposedTag=''
            }
            continue
        }

        $Property=$confederateMatches[0]
        $hasPropertyTag=Test-AlreadyHasCountyTag -MediaPath $fullPath -County $Property

        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName
            FileType=$kind
            FullPath=$fullPath
            HasGPS='YES'
            Latitude=[Math]::Round($lat,7)
            Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1)
            DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1)
            DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            ConfederateMatch=($confederateMatches.Name -join ' | ')
            CountyMatch='Lancaster County'
            ProtectedChildLocation=''
            AlreadyCountyTag=if($hasPropertyTag){'YES'}else{'NO'}
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action=if($hasPropertyTag){"SKIP - already $($Property.LeafTag) tagged"}else{"TAG $($Property.LeafTag)"}
            ProposedTag=if($hasPropertyTag){''}else{$Property.DigiKamTag}
        }
        continue
    }

    # 2044 Douglas Rd is checked before general Lancaster County classification.
    if ($douglasDistanceMeters -le $DouglasRoad.RadiusMeters) {
        $hasDouglasTag=Test-AlreadyHasCountyTag `
            -MediaPath $fullPath `
            -County $DouglasRoad

        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName
            FileType=$kind
            FullPath=$fullPath
            HasGPS='YES'
            Latitude=[Math]::Round($lat,7)
            Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1)
            DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1)
            DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            ConfederateMatch=''
            CountyMatch='Lancaster County'
            ProtectedChildLocation=''
            AlreadyCountyTag=if($hasDouglasTag){'YES'}else{'NO'}
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action=if($hasDouglasTag){'SKIP - already 2044 Douglas Rd tagged'}else{'TAG 2044 Douglas Rd'}
            ProposedTag=if($hasDouglasTag){''}else{$DouglasRoad.DigiKamTag}
        }
        continue
    }

    # Chester County Sub Fiber rule is checked before general county classification.
    if ($subFiberDistanceMeters -le $SubFiber.RadiusMeters) {
        $hasSubFiberTag=Test-AlreadyHasCountyTag `
            -MediaPath $fullPath `
            -County $SubFiber

        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName
            FileType=$kind
            FullPath=$fullPath
            HasGPS='YES'
            Latitude=[Math]::Round($lat,7)
            Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1)
            DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1)
            DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            ConfederateMatch=''
            CountyMatch='Chester County'
            ProtectedChildLocation=''
            AlreadyCountyTag=if($hasSubFiberTag){'YES'}else{'NO'}
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action=if($hasSubFiberTag){'SKIP - already Sub Fiber tagged'}else{'TAG Sub Fiber'}
            ProposedTag=if($hasSubFiberTag){''}else{$SubFiber.DigiKamTag}
        }
        continue
    }

    if ($distanceMeters -le $CommunityLane.RadiusMeters) {
        $hasCommunityLaneTag=Test-AlreadyHasCountyTag `
            -MediaPath $fullPath `
            -County $CommunityLane

        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName
            FileType=$kind
            FullPath=$fullPath
            HasGPS='YES'
            Latitude=[Math]::Round($lat,7)
            Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1)
            DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1)
            DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            ConfederateMatch=''
            CountyMatch='Lancaster County'
            ProtectedChildLocation=''
            AlreadyCountyTag=if($hasCommunityLaneTag){'YES'}else{'NO'}
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action=if($hasCommunityLaneTag){'SKIP - already 973 Community Lane tagged'}else{'TAG 973 Community Lane'}
            ProposedTag=if($hasCommunityLaneTag){''}else{$CommunityLane.DigiKamTag}
        }
        continue
    }

    # Florida rules: Crystal River first, then generic Florida.
    if (Test-PointInGeoJsonGeometry -Latitude $lat -Longitude $lon -Geometry $Florida.Geometry) {
        if ($crystalRiverDistanceMeters -le $CrystalRiver.RadiusMeters) {
            $TargetLocation=$CrystalRiver
            $actionName='Crystal River'
        }
        else {
            $TargetLocation=$Florida
            $actionName='Florida'
        }

        $alreadyFloridaLocation=Test-AlreadyHasCountyTag -MediaPath $fullPath -County $TargetLocation
        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName; FileType=$kind; FullPath=$fullPath; HasGPS='YES'
            Latitude=[Math]::Round($lat,7); Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1); DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1); DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            DistanceToCrystalRiverMiles=[Math]::Round($crystalRiverDistanceMiles,2)
            ConfederateMatch=''; CountyMatch=$actionName; ProtectedChildLocation=''
            AlreadyCountyTag=if($alreadyFloridaLocation){'YES'}else{'NO'}
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action=if($alreadyFloridaLocation){"SKIP - already $actionName tagged"}else{"TAG $actionName"}
            ProposedTag=if($alreadyFloridaLocation){''}else{$TargetLocation.DigiKamTag}
        }
        continue
    }

    $matchedCounties=@()

    foreach ($County in $Counties) {
        if (Test-PointInGeoJsonGeometry `
            -Latitude $lat `
            -Longitude $lon `
            -Geometry $County.Geometry) {

            $matchedCounties += $County
        }
    }

    if ($matchedCounties.Count -eq 0) {
        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName
            FileType=$kind
            FullPath=$fullPath
            HasGPS='YES'
            Latitude=[Math]::Round($lat,7)
            Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1)
            DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1)
            DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            ConfederateMatch=''
            CountyMatch=''
            ProtectedChildLocation=''
            AlreadyCountyTag=''
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action='Outside configured counties'
            ProposedTag=''
        }
        continue
    }

    if ($matchedCounties.Count -gt 1) {
        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName
            FileType=$kind
            FullPath=$fullPath
            HasGPS='YES'
            Latitude=[Math]::Round($lat,7)
            Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1)
            DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1)
            DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            ConfederateMatch=''
            CountyMatch=($matchedCounties.Name -join ' | ')
            ProtectedChildLocation=''
            AlreadyCountyTag=''
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action='REVIEW - multiple county match'
            ProposedTag=''
        }
        continue
    }

    $County=$matchedCounties[0]

    $protected=@(
        Get-ProtectedChildTags `
            -MediaPath $fullPath `
            -ProtectedParents $County.ProtectedParents
    )

    $already=Test-AlreadyHasCountyTag `
        -MediaPath $fullPath `
        -County $County

    if ($protected.Count -gt 0) {
        $action='SKIP - specific child location exists'
        $proposed=''
    }
    elseif ($already) {
        $action='SKIP - already county tagged'
        $proposed=''
    }
    else {
        $action="TAG $($County.Name)"
        $proposed=$County.DigiKamTag
    }

    $Rows += [PSCustomObject]@{
        FileName=$Item.FileName
        FileType=$kind
        FullPath=$fullPath
        HasGPS='YES'
        Latitude=[Math]::Round($lat,7)
        Longitude=[Math]::Round($lon,7)
        DistanceTo973Ft=[Math]::Round($distanceFeet,1)
        DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
        ConfederateMatch=''
        CountyMatch=$County.Name
        ProtectedChildLocation=($protected -join ' | ')
        AlreadyCountyTag=if($already){'YES'}else{'NO'}
        VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
        Action=$action
        ProposedTag=$proposed
    }
}

$Rows | Export-Csv `
    -LiteralPath $ReportPath `
    -NoTypeInformation `
    -Encoding UTF8

# -----------------------------
# Report summary
# -----------------------------

$total=$Rows.Count
$gpsCount=@($Rows | Where-Object {$_.HasGPS -eq 'YES'}).Count
$reviewCount=@($Rows | Where-Object {$_.Action -like 'REVIEW -*'}).Count
$skipChild=@($Rows | Where-Object {$_.Action -eq 'SKIP - specific child location exists'}).Count
$skipCounty=@($Rows | Where-Object {$_.Action -eq 'SKIP - already county tagged'}).Count
$skip973=@($Rows | Where-Object {$_.Action -eq 'SKIP - already 973 Community Lane tagged'}).Count
$tag973=@($Rows | Where-Object {$_.Action -eq 'TAG 973 Community Lane'})
$embed973=@($Rows | Where-Object {$_.Action -eq 'EMBED GPS 973 Community Lane'})
$tagDouglas=@($Rows | Where-Object {$_.Action -eq 'TAG 2044 Douglas Rd'})
$skipDouglas=@($Rows | Where-Object {$_.Action -eq 'SKIP - already 2044 Douglas Rd tagged'}).Count
$skip900=@($Rows | Where-Object {$_.Action -eq 'SKIP - already 900 Confederate Ave tagged'}).Count
$tag900=@($Rows | Where-Object {$_.Action -eq 'TAG 900 Confederate Ave'})
$skip909=@($Rows | Where-Object {$_.Action -eq 'SKIP - already 909 Confederate Ave tagged'}).Count
$tag909=@($Rows | Where-Object {$_.Action -eq 'TAG 909 Confederate Ave'})
$skipSubFiber=@($Rows | Where-Object {$_.Action -eq 'SKIP - already Sub Fiber tagged'}).Count
$tagSubFiber=@($Rows | Where-Object {$_.Action -eq 'TAG Sub Fiber'})
$tagCrystalRiver=@($Rows | Where-Object {$_.Action -eq 'TAG Crystal River'})
$skipCrystalRiver=@($Rows | Where-Object {$_.Action -eq 'SKIP - already Crystal River tagged'}).Count
$tagFlorida=@($Rows | Where-Object {$_.Action -eq 'TAG Florida'})
$skipFlorida=@($Rows | Where-Object {$_.Action -eq 'SKIP - already Florida tagged'}).Count
$videoTags=@($Rows | Where-Object {$_.VideoTagNeeded -eq 'YES'})
$toWrite=@($Rows | Where-Object {
    $_.Action -like 'TAG *' -or
    $_.Action -eq 'EMBED GPS 973 Community Lane' -or
    $_.VideoTagNeeded -eq 'YES'
})

Write-Host ""
Write-Host "REPORT SUMMARY" -ForegroundColor Cyan
Write-Host "Total supported files      : $total"
Write-Host "Files with GPS             : $gpsCount"
Write-Host "Skipped - child location   : $skipChild"
Write-Host "Skipped - already county   : $skipCounty"
Write-Host "Skipped - already 973 tag  : $skip973"
Write-Host "973 GPS matches to tag     : $($tag973.Count)"
Write-Host "973 tags needing GPS       : $($embed973.Count)"
Write-Host "Skipped - already Douglas  : $skipDouglas"
Write-Host "2044 Douglas GPS matches   : $($tagDouglas.Count)"
Write-Host "Skipped - already 900 tag  : $skip900"
Write-Host "900/910 GPS matches/tag    : $($tag900.Count)"
Write-Host "Skipped - already 909 tag  : $skip909"
Write-Host "909 GPS matches/tag        : $($tag909.Count)"
Write-Host "Skipped - already SubFiber : $skipSubFiber"
Write-Host "Sub Fiber GPS matches/tag  : $($tagSubFiber.Count)"
Write-Host "Skipped - already Crystal  : $skipCrystalRiver"
Write-Host "Crystal River matches/tag  : $($tagCrystalRiver.Count)"
Write-Host "Skipped - already Florida  : $skipFlorida"
Write-Host "Florida matches/tag        : $($tagFlorida.Count)"
Write-Host "Videos needing Video tag   : $($videoTags.Count)"
Write-Host "Needs review               : $reviewCount"
Write-Host "Total write actions        : $($toWrite.Count)"
Write-Host ""

foreach ($County in $Counties) {
    $countyRows=@($Rows | Where-Object {$_.CountyMatch -eq $County.Name})
    $countyTagRows=@($Rows | Where-Object {$_.Action -eq "TAG $($County.Name)"})
    $countySkipChild=@($Rows | Where-Object {
        $_.CountyMatch -eq $County.Name -and
        $_.Action -eq 'SKIP - specific child location exists'
    })

    Write-Host $County.Name -ForegroundColor Yellow
    Write-Host "  GPS matches              : $($countyRows.Count)"
    Write-Host "  Skipped child locations  : $($countySkipChild.Count)"
    Write-Host "  Will tag                 : $($countyTagRows.Count)"
}

Write-Host ""
Write-Host "Report: $ReportPath"

if ($Mode -eq 'REPORT') {
    Write-Host ""
    Write-Host "REPORT mode only. Nothing was modified." -ForegroundColor Yellow
    exit 0
}

# -----------------------------
# Write safety checks
# -----------------------------

if ($reviewCount -gt 0) {
    Write-Host ""
    Write-Host "WRITE STOPPED: one or more files need review." -ForegroundColor Red
    Write-Host "Review the CSV first. Nothing was changed."
    exit 1
}

if ($toWrite.Count -eq 0) {
    Write-Host ""
    Write-Host "Nothing needs location/county changes." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "WRITE mode will:" -ForegroundColor Yellow
Write-Host "  Confederate Ave: existing 900 polygon + 910 map-zone -> 900 tag; 909 polygon -> 909 tag"
Write-Host "  973 rule: GPS within 500 ft -> add the specific home tag"
Write-Host "  973 rule: photo has the home tag but no GPS -> embed the fixed GPS in photo + sidecar"
Write-Host "  2044 Douglas Rd: GPS within 500 ft -> add Places/South Carolina/Lancaster County/2044 Douglas Rd"
Write-Host "  Sub Fiber rule: GPS within 1000 ft -> add Places/South Carolina/Chester County/Sub Fiber"
Write-Host "  Florida: within 20 miles of Crystal River -> add Places/Florida/Crystal River"
Write-Host "  Florida: otherwise anywhere in Florida -> add Places/Florida"
Write-Host "  Every supported video -> add Video tag"
Write-Host "  Existing GPS is NEVER replaced"
Write-Host "  Photos: write location/county tags to image AND .xmp sidecar"
Write-Host "  Videos: write location/county tags to .xmp sidecar only"
Write-Host "  Existing tags are preserved"
Write-Host "  Protected child locations are re-checked before county writes"
Write-Host ""

$answer=Read-Host "Type YES to continue"

if ($answer -cne 'YES') {
    Write-Host "Cancelled. Nothing was changed." -ForegroundColor Yellow
    exit 0
}

New-Item `
    -ItemType Directory `
    -Force `
    -Path $BackupRoot | Out-Null

$WriteLog=@()
$changed=0
$already=0
$errors=0
$skippedAtWrite=0

foreach ($row in $toWrite) {

    # ---------------------------------------------------------
    # Confederate Avenue existing property geofences
    # ---------------------------------------------------------
    $ConfederateProperty=$ConfederateProperties | Where-Object {
        $_.DigiKamTag -eq $row.ProposedTag
    } | Select-Object -First 1

    if ($ConfederateProperty) {
        if ($row.FileType -eq 'Video') {
            $sidecar="$($row.FullPath).xmp"
            $backup=''

            if (Test-Path -LiteralPath $sidecar) {
                $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
                $backupName=(($row.FileName+"_$stamp.xmp") -replace '[\\/:*?"<>|]','_')
                $backup=Join-Path $BackupRoot $backupName
                Copy-Item -LiteralPath $sidecar -Destination $backup
            }
            else {
                $sidecarCreateResult=New-VideoSidecarFromMedia -MediaPath $row.FullPath -SidecarPath $sidecar
                if ($sidecarCreateResult -eq 'ERROR') {
                    $errors++
                    $WriteLog += [PSCustomObject]@{
                        FileName=$row.FileName; FileType='Video'; County=$ConfederateProperty.Name
                        Result='ERROR creating sidecar'; PhotoResult=''; SidecarResult=''; Backup=''
                    }
                    continue
                }
            }

            $locResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false -County $ConfederateProperty
            $videoResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false -County $VideoTag

            if ($locResult -eq 'ERROR' -or $videoResult -eq 'ERROR') { $errors++; $overall='ERROR' }
            elseif ($locResult -eq 'Already tagged' -and $videoResult -eq 'Already tagged') { $already++; $overall='Already tagged' }
            else { $changed++; $overall="$($ConfederateProperty.LeafTag) + Video tagged" }

            $WriteLog += [PSCustomObject]@{
                FileName=$row.FileName; FileType='Video'; County=$ConfederateProperty.Name; Result=$overall
                PhotoResult=''; SidecarResult="$locResult / $videoResult"; Backup=$backup
            }
            continue
        }

        if ($row.FileType -eq 'Photo') {
            $photo=$row.FullPath
            $sidecar="$photo.xmp"
            $relative=$photo.Substring($Root.Length).TrimStart('\')
            $photoBackup=Join-Path $BackupRoot ($relative -replace '[\\/:*?"<>|]','_')
            if (-not (Test-Path -LiteralPath $photoBackup)) { Copy-Item -LiteralPath $photo -Destination $photoBackup }

            $sidecarBackup=''
            if (Test-Path -LiteralPath $sidecar) {
                $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
                $sidecarBackup=Join-Path $BackupRoot ((($row.FileName+"_$stamp.xmp")) -replace '[\\/:*?"<>|]','_')
                Copy-Item -LiteralPath $sidecar -Destination $sidecarBackup
            }
            else {
                & $ExifTool.Source -o $sidecar $photo | Out-Null
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sidecar)) {
                    $errors++
                    $WriteLog += [PSCustomObject]@{
                        FileName=$row.FileName; FileType='Photo'; County=$ConfederateProperty.Name
                        Result='ERROR creating photo sidecar'; PhotoResult=''; SidecarResult=''; Backup=$photoBackup
                    }
                    continue
                }
            }

            $photoResult=Add-TagsToTarget -Target $photo -PreserveTimestamp:$true -County $ConfederateProperty
            $sidecarResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false -County $ConfederateProperty

            if ($photoResult -eq 'ERROR' -or $sidecarResult -eq 'ERROR') { $errors++; $overall='ERROR' }
            elseif ($photoResult -eq 'Already tagged' -and $sidecarResult -eq 'Already tagged') { $already++; $overall='Already tagged' }
            else { $changed++; $overall="$($ConfederateProperty.LeafTag) tagged" }

            $WriteLog += [PSCustomObject]@{
                FileName=$row.FileName; FileType='Photo'; County=$ConfederateProperty.Name; Result=$overall
                PhotoResult=$photoResult; SidecarResult=$sidecarResult; Backup="$photoBackup | $sidecarBackup"
            }
            continue
        }
    }

    # ---------------------------------------------------------
    # Sub Fiber special rule
    # ---------------------------------------------------------
    if ($row.ProposedTag -eq $SubFiber.DigiKamTag) {
        if ($row.FileType -eq 'Video') {
            $sidecar="$($row.FullPath).xmp"
            $backup=''

            if (Test-Path -LiteralPath $sidecar) {
                $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
                $backupName=(($row.FileName+"_$stamp.xmp") -replace '[\/:*?"<>|]','_')
                $backup=Join-Path $BackupRoot $backupName
                Copy-Item -LiteralPath $sidecar -Destination $backup
            }
            else {
                $sidecarCreateResult=New-VideoSidecarFromMedia -MediaPath $row.FullPath -SidecarPath $sidecar
                if ($sidecarCreateResult -eq 'ERROR') {
                    $errors++
                    continue
                }
            }

            $locResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false -County $SubFiber
            $videoResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false -County $VideoTag

            if ($locResult -eq 'ERROR' -or $videoResult -eq 'ERROR') { $errors++; $overall='ERROR' }
            elseif ($locResult -eq 'Already tagged' -and $videoResult -eq 'Already tagged') { $already++; $overall='Already tagged' }
            else { $changed++; $overall='Sub Fiber + Video tagged' }

            $WriteLog += [PSCustomObject]@{
                FileName=$row.FileName; FileType='Video'; County='Chester County/Sub Fiber'; Result=$overall
                PhotoResult=''; SidecarResult="$locResult / $videoResult"; Backup=$backup
            }
            continue
        }

        if ($row.FileType -eq 'Photo') {
            $photo=$row.FullPath
            $sidecar="$photo.xmp"
            $relative=$photo.Substring($Root.Length).TrimStart('\')
            $photoBackup=Join-Path $BackupRoot ($relative -replace '[\/:*?"<>|]','_')
            if (-not (Test-Path -LiteralPath $photoBackup)) { Copy-Item -LiteralPath $photo -Destination $photoBackup }

            $sidecarBackup=''
            if (Test-Path -LiteralPath $sidecar) {
                $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
                $sidecarBackup=Join-Path $BackupRoot ((($row.FileName+"_$stamp.xmp")) -replace '[\/:*?"<>|]','_')
                Copy-Item -LiteralPath $sidecar -Destination $sidecarBackup
            }
            else {
                & $ExifTool.Source -o $sidecar $photo | Out-Null
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sidecar)) { $errors++; continue }
            }

            $photoResult=Add-TagsToTarget -Target $photo -PreserveTimestamp:$true -County $SubFiber
            $sidecarResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false -County $SubFiber

            if ($photoResult -eq 'ERROR' -or $sidecarResult -eq 'ERROR') { $errors++; $overall='ERROR' }
            elseif ($photoResult -eq 'Already tagged' -and $sidecarResult -eq 'Already tagged') { $already++; $overall='Already tagged' }
            else { $changed++; $overall='Sub Fiber tagged' }

            $WriteLog += [PSCustomObject]@{
                FileName=$row.FileName; FileType='Photo'; County='Chester County/Sub Fiber'; Result=$overall
                PhotoResult=$photoResult; SidecarResult=$sidecarResult; Backup="$photoBackup | $sidecarBackup"
            }
            continue
        }
    }

    # ---------------------------------------------------------
    # Video-only generic tag (for videos that do not also need a location write)
    # ---------------------------------------------------------
    if ($row.FileType -eq 'Video' -and $row.VideoTagNeeded -eq 'YES' -and [string]::IsNullOrWhiteSpace([string]$row.ProposedTag)) {
        $sidecar="$($row.FullPath).xmp"
        $backup=''
        if (Test-Path -LiteralPath $sidecar) {
            $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
            $backupName=(($row.FileName+"_$stamp.xmp") -replace '[\/:*?"<>|]','_')
            $backup=Join-Path $BackupRoot $backupName
            Copy-Item -LiteralPath $sidecar -Destination $backup
        }
        else {
            $sidecarCreateResult=New-VideoSidecarFromMedia -MediaPath $row.FullPath -SidecarPath $sidecar
            if ($sidecarCreateResult -eq 'ERROR') { $errors++; continue }
        }

        $videoResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false -County $VideoTag
        if ($videoResult -eq 'Tagged') { $changed++ }
        elseif ($videoResult -eq 'Already tagged') { $already++ }
        else { $errors++ }

        $WriteLog += [PSCustomObject]@{
            FileName=$row.FileName; FileType='Video'; County=''; Result=$videoResult
            PhotoResult=''; SidecarResult=$videoResult; Backup=$backup
        }
        continue
    }

    # ---------------------------------------------------------
    # 973 Community Lane special rule
    # ---------------------------------------------------------
    if ($row.ProposedTag -eq $CommunityLane.DigiKamTag) {

        if ($row.FileType -eq 'Video') {
            # Existing-GPS videos may receive the home tag in the sidecar.
            # Missing-GPS videos are held for REVIEW during REPORT mode and
            # therefore never reach this branch.
            $sidecar="$($row.FullPath).xmp"
            $backup=''

            if (Test-Path -LiteralPath $sidecar) {
                $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
                $backupName=(($row.FileName+"_$stamp.xmp") -replace '[\\/:*?"<>|]','_')
                $backup=Join-Path $BackupRoot $backupName
                Copy-Item -LiteralPath $sidecar -Destination $backup
            }
            else {
                $sidecarCreateResult=New-VideoSidecarFromMedia -MediaPath $row.FullPath -SidecarPath $sidecar

                if ($sidecarCreateResult -eq 'ERROR') {
                    $errors++
                    $WriteLog += [PSCustomObject]@{
                        FileName=$row.FileName
                        FileType='Video'
                        County='973 Community Lane'
                        Result='ERROR creating sidecar'
                        PhotoResult=''
                        SidecarResult=''
                        Backup=''
                    }
                    continue
                }
            }

            $sidecarResult=Add-TagsToTarget `
                -Target $sidecar `
                -PreserveTimestamp:$false `
                -County $CommunityLane
            $videoResult=Add-TagsToTarget `
                -Target $sidecar `
                -PreserveTimestamp:$false `
                -County $VideoTag

            if ($sidecarResult -eq 'ERROR' -or $videoResult -eq 'ERROR') {
                $errors++
            }
            elseif ($sidecarResult -eq 'Already tagged' -and $videoResult -eq 'Already tagged') {
                $already++
            }
            else {
                $changed++
            }

            $WriteLog += [PSCustomObject]@{
                FileName=$row.FileName
                FileType='Video'
                County='973 Community Lane'
                Result=$sidecarResult
                PhotoResult=''
                SidecarResult="$sidecarResult / $videoResult"
                Backup=$backup
            }

            continue
        }

        if ($row.FileType -eq 'Photo') {
            $photo=$row.FullPath
            $sidecar="$photo.xmp"
            $relative=$photo.Substring($Root.Length).TrimStart('\')

            $photoBackup=Join-Path `
                $BackupRoot `
                ($relative -replace '[\\/:*?"<>|]','_')

            if (-not (Test-Path -LiteralPath $photoBackup)) {
                Copy-Item -LiteralPath $photo -Destination $photoBackup
            }

            $sidecarBackup=''

            if (Test-Path -LiteralPath $sidecar) {
                $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
                $sidecarBackup=Join-Path `
                    $BackupRoot `
                    ((($row.FileName+"_$stamp.xmp")) -replace '[\\/:*?"<>|]','_')
                Copy-Item -LiteralPath $sidecar -Destination $sidecarBackup
            }
            else {
                & $ExifTool.Source -o $sidecar $photo | Out-Null

                if (
                    $LASTEXITCODE -ne 0 -or
                    -not (Test-Path -LiteralPath $sidecar)
                ) {
                    $errors++
                    $WriteLog += [PSCustomObject]@{
                        FileName=$row.FileName
                        FileType='Photo'
                        County='973 Community Lane'
                        Result='ERROR creating photo sidecar'
                        PhotoResult=''
                        SidecarResult=''
                        Backup=$photoBackup
                    }
                    continue
                }
            }

            $photoTagResult=Add-TagsToTarget `
                -Target $photo `
                -PreserveTimestamp:$true `
                -County $CommunityLane

            $sidecarTagResult=Add-TagsToTarget `
                -Target $sidecar `
                -PreserveTimestamp:$false `
                -County $CommunityLane

            $photoGpsResult=''
            $sidecarGpsResult=''

            if ($row.Action -eq 'EMBED GPS 973 Community Lane') {
                # This path is only selected when no GPS was found.
                # Existing GPS is therefore never overwritten.
                $photoGpsResult=Set-GpsOnPhoto `
                    -Target $photo `
                    -Latitude $CommunityLane.Latitude `
                    -Longitude $CommunityLane.Longitude

                $sidecarGpsResult=Set-GpsOnSidecar `
                    -Target $sidecar `
                    -Latitude $CommunityLane.Latitude `
                    -Longitude $CommunityLane.Longitude
            }

            if (
                $photoTagResult -eq 'ERROR' -or
                $sidecarTagResult -eq 'ERROR' -or
                $photoGpsResult -eq 'ERROR' -or
                $sidecarGpsResult -eq 'ERROR'
            ) {
                $errors++
                $overall='ERROR'
            }
            elseif ($row.Action -eq 'EMBED GPS 973 Community Lane') {
                $changed++
                $overall='973 tag ensured + GPS embedded'
            }
            elseif (
                $photoTagResult -eq 'Already tagged' -and
                $sidecarTagResult -eq 'Already tagged'
            ) {
                $already++
                $overall='Already tagged'
            }
            else {
                $changed++
                $overall='973 Community Lane tagged'
            }

            $WriteLog += [PSCustomObject]@{
                FileName=$row.FileName
                FileType='Photo'
                County='973 Community Lane'
                Result=$overall
                PhotoResult="$photoTagResult$(if($photoGpsResult){' / '+$photoGpsResult})"
                SidecarResult="$sidecarTagResult$(if($sidecarGpsResult){' / '+$sidecarGpsResult})"
                Backup="$photoBackup | $sidecarBackup"
            }

            continue
        }
    }

    $AllGenericTargets=@($Counties) + @($DouglasRoad,$CrystalRiver,$Florida)
    $County=$AllGenericTargets | Where-Object {
        $_.DigiKamTag -eq $row.ProposedTag
    } | Select-Object -First 1

    if (-not $County) {
        $errors++
        continue
    }

    # Safety re-check immediately before writing.
    $protected=@(
        Get-ProtectedChildTags `
            -MediaPath $row.FullPath `
            -ProtectedParents $County.ProtectedParents
    )

    if ($protected.Count -gt 0) {
        $skippedAtWrite++

        $WriteLog += [PSCustomObject]@{
            FileName=$row.FileName
            FileType=$row.FileType
            County=$County.Name
            Result='SKIPPED at write - protected child location found'
            PhotoResult=''
            SidecarResult=''
            Backup=''
        }

        continue
    }

    if ($row.FileType -eq 'Video') {
        $sidecar="$($row.FullPath).xmp"
        $backup=''

        if (Test-Path -LiteralPath $sidecar) {
            $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'

            $backupName=(
                ($row.FileName+"_$stamp.xmp") `
                -replace '[\\/:*?"<>|]','_'
            )

            $backup=Join-Path $BackupRoot $backupName
            Copy-Item `
                -LiteralPath $sidecar `
                -Destination $backup
        }
        else {
            $sidecarCreateResult=New-VideoSidecarFromMedia -MediaPath $row.FullPath -SidecarPath $sidecar

            if ($sidecarCreateResult -eq 'ERROR') {
                $errors++

                $WriteLog += [PSCustomObject]@{
                    FileName=$row.FileName
                    FileType='Video'
                    County=$County.Name
                    Result='ERROR creating sidecar'
                    PhotoResult=''
                    SidecarResult=''
                    Backup=''
                }

                continue
            }
        }

        $sidecarResult=Add-TagsToTarget `
            -Target $sidecar `
            -PreserveTimestamp:$false `
            -County $County
        $videoResult=Add-TagsToTarget `
            -Target $sidecar `
            -PreserveTimestamp:$false `
            -County $VideoTag

        if ($sidecarResult -eq 'ERROR' -or $videoResult -eq 'ERROR') {
            $errors++
        }
        elseif ($sidecarResult -eq 'Already tagged' -and $videoResult -eq 'Already tagged') {
            $already++
        }
        else {
            $changed++
        }

        $WriteLog += [PSCustomObject]@{
            FileName=$row.FileName
            FileType='Video'
            County=$County.Name
            Result=$sidecarResult
            PhotoResult=''
            SidecarResult=$sidecarResult
            Backup=$backup
        }
    }
    elseif ($row.FileType -eq 'Photo') {
        $photo=$row.FullPath
        $sidecar="$photo.xmp"

        $relative=$photo.Substring($Root.Length).TrimStart('\')

        $photoBackup=Join-Path `
            $BackupRoot `
            ($relative -replace '[\\/:*?"<>|]','_')

        if (-not (Test-Path -LiteralPath $photoBackup)) {
            Copy-Item `
                -LiteralPath $photo `
                -Destination $photoBackup
        }

        $sidecarBackup=''

        if (Test-Path -LiteralPath $sidecar) {
            $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'

            $sidecarBackup=Join-Path `
                $BackupRoot `
                ((($row.FileName+"_$stamp.xmp")) `
                    -replace '[\\/:*?"<>|]','_')

            Copy-Item `
                -LiteralPath $sidecar `
                -Destination $sidecarBackup
        }
        else {
            & $ExifTool.Source `
                -o $sidecar `
                $photo | Out-Null

            if (
                $LASTEXITCODE -ne 0 -or
                -not (Test-Path -LiteralPath $sidecar)
            ) {
                $errors++

                $WriteLog += [PSCustomObject]@{
                    FileName=$row.FileName
                    FileType='Photo'
                    County=$County.Name
                    Result='ERROR creating photo sidecar'
                    PhotoResult=''
                    SidecarResult=''
                    Backup=$photoBackup
                }

                continue
            }
        }

        $photoResult=Add-TagsToTarget `
            -Target $photo `
            -PreserveTimestamp:$true `
            -County $County

        $sidecarResult=Add-TagsToTarget `
            -Target $sidecar `
            -PreserveTimestamp:$false `
            -County $County

        if (
            $photoResult -eq 'ERROR' -or
            $sidecarResult -eq 'ERROR'
        ) {
            $errors++
            $overall='ERROR'
        }
        elseif (
            $photoResult -eq 'Already tagged' -and
            $sidecarResult -eq 'Already tagged'
        ) {
            $already++
            $overall='Already tagged'
        }
        else {
            $changed++
            $overall='Tagged'
        }

        $WriteLog += [PSCustomObject]@{
            FileName=$row.FileName
            FileType='Photo'
            County=$County.Name
            Result=$overall
            PhotoResult=$photoResult
            SidecarResult=$sidecarResult
            Backup="$photoBackup | $sidecarBackup"
        }
    }
}

$WriteLog | Export-Csv `
    -LiteralPath $WriteLogPath `
    -NoTypeInformation `
    -Encoding UTF8

Write-Host ""
Write-Host "WRITE COMPLETE" -ForegroundColor Green
Write-Host "Changed          : $changed"
Write-Host "Already tagged   : $already"
Write-Host "Skipped at write : $skippedAtWrite"
Write-Host "Errors           : $errors"
Write-Host "Write log        : $WriteLogPath"
Write-Host "Backups          : $BackupRoot"
Write-Host ""
Write-Host "Then use DigiKam: Reread Metadata From File for the folder." -ForegroundColor Cyan

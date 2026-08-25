param(
    [ValidateSet('REPORT','WRITE')]
    [string]$Mode = 'REPORT',

    [string]$Root = 'C:\Users\rbell\OneDrive\Pictures\2019',

    [switch]$NoRecurse,

    [int]$FromYear = 0,

    [int]$ToYear = 9999,

    [string]$DigiKamDatabase = 'C:\Users\rbell\OneDrive\Pictures\digikam4.db',

    [string]$DigiKamCollectionRoot = 'C:\Users\rbell\OneDrive\Pictures',

    [switch]$SkipDigiKamCatalogSync
)

# Keep ExifTool's Perl runtime quiet and deterministic on Windows.
$env:LC_ALL = 'C'
$env:LC_CTYPE = 'C'
$env:LANG = 'C'
$ErrorActionPreference = 'Stop'

# v2.17: synchronizes affected tags/GPS into digiKam SQLite after verified metadata writes.
# v2.16: caches embedded and sidecar tags in two batch reads instead of rereading each file.
# v2.15: adds a scoped year range so multiple year folders can be scanned in one safe pass.
# v2.14: adds 500-foot Lancaster Rescue Squad and 212 S Main St QDS Office geofences.
# v2.10: adds travel-state/city GPS tagging for GA, VA, DC, TN, LA and additional FL destinations.
#       Photos get GPS in image + sidecar; videos get GPS in sidecar only.
# v2.6: safer video sidecar handling. Existing .xmp sidecars are never recreated;
# they are backed up and updated additively. Missing video sidecars are created
# from the video's readable metadata before location/Video tags are appended.
# v2.13: adds Myrtle Beach, South Carolina geofence with a 50-mile radius.
# v2.12: Video tag is now enforced unconditionally for every MOV/MP4/M4V/AVI.
#        REPORT marks every supported video for an additive Video-tag write.
#        Existing tags are preserved; missing sidecars are created safely.
# Confederate Avenue safeguard: an existing 900 Confederate Ave tag takes
# priority and prevents the 909 Confederate Ave tag from being added.

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

# Specific Lancaster County workplace geofences. Evaluated before county rules.
$LancasterRescueSquad = @{
    Name = 'Lancaster Rescue Squad'
    LeafTag = 'Lancaster Rescue Squad'
    DigiKamTag = 'Places/South Carolina/Lancaster County/Lancaster Rescue Squad'
    HierTag = 'Places|South Carolina|Lancaster County|Lancaster Rescue Squad'
    Latitude = 34.702819927107065
    Longitude = -80.77137060962954
    RadiusMeters = 152.4   # 500 ft
    ProtectedParents = @()
}

$QDSOffice = @{
    Name = '212 S Main St QDS Office'
    LeafTag = '212 S Main St QDS Office'
    DigiKamTag = 'Places/South Carolina/Lancaster County/212 S Main St QDS Office'
    HierTag = 'Places|South Carolina|Lancaster County|212 S Main St QDS Office'
    Latitude = 34.71835029983651
    Longitude = -80.77003196631922
    RadiusMeters = 152.4   # 500 ft
    ProtectedParents = @()
}


# Specific Lancaster County school geofences. Evaluated before general county rules.
$LancasterHighSchool = @{
    Name = 'Lancaster High School'
    LeafTag = 'Lancaster High School'
    DigiKamTag = 'Places/South Carolina/Lancaster County/Lancaster High School'
    HierTag = 'Places|South Carolina|Lancaster County|Lancaster High School'
    Latitude = 34.72695370065828
    Longitude = -80.77888507698339
    RadiusMeters = 304.8   # 1000 ft
    ProtectedParents = @()
}

$ErwinElementary = @{
    Name = 'Erwin Elementary'
    LeafTag = 'Erwin Elementary'
    DigiKamTag = 'Places/South Carolina/Lancaster County/Erwin Elementary'
    HierTag = 'Places|South Carolina|Lancaster County|Erwin Elementary'
    Latitude = 34.69832846941398
    Longitude = -80.80554197502941
    RadiusMeters = 304.8   # 1000 ft
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

# Myrtle Beach, South Carolina travel geofence. Evaluated before generic county/state rules.
$MyrtleBeach = @{
    Name = 'Myrtle Beach'
    LeafTag = 'Myrtle Beach'
    DigiKamTag = 'Places/South Carolina/Myrtle Beach'
    HierTag = 'Places|South Carolina|Myrtle Beach'
    Latitude = 33.6891
    Longitude = -78.8867
    RadiusMeters = 80467.2   # 50 miles
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



# Additional travel-state and city rules. City geofences use a 20-mile radius.
# State boundaries are loaded from Census TIGERweb and city rules take priority over state tags.
$TravelStates = @(
    @{ Name='Georgia'; GeoId='13'; LeafTag='Georgia'; DigiKamTag='Places/Georgia'; HierTag='Places|Georgia'; ProtectedParents=@(); Cities=@(
        @{ Name='Savannah'; LeafTag='Savannah'; DigiKamTag='Places/Georgia/Savannah'; HierTag='Places|Georgia|Savannah'; Latitude=32.0809; Longitude=-81.0912; RadiusMeters=32186.88; ProtectedParents=@() },
        @{ Name='Atlanta'; LeafTag='Atlanta'; DigiKamTag='Places/Georgia/Atlanta'; HierTag='Places|Georgia|Atlanta'; Latitude=33.7490; Longitude=-84.3880; RadiusMeters=32186.88; ProtectedParents=@() }
    )},
    @{ Name='Virginia'; GeoId='51'; LeafTag='Virginia'; DigiKamTag='Places/Virginia'; HierTag='Places|Virginia'; ProtectedParents=@(); Cities=@(
        @{ Name='Newport News'; LeafTag='Newport News'; DigiKamTag='Places/Virginia/Newport News'; HierTag='Places|Virginia|Newport News'; Latitude=37.0871; Longitude=-76.4730; RadiusMeters=32186.88; ProtectedParents=@() }
    )},
    @{ Name='Washington DC'; GeoId='11'; LeafTag='Washington DC'; DigiKamTag='Places/Washington DC'; HierTag='Places|Washington DC'; ProtectedParents=@(); Cities=@() },
    @{ Name='Tennessee'; GeoId='47'; LeafTag='Tennessee'; DigiKamTag='Places/Tennessee'; HierTag='Places|Tennessee'; ProtectedParents=@(); Cities=@(
        @{ Name='Nashville'; LeafTag='Nashville'; DigiKamTag='Places/Tennessee/Nashville'; HierTag='Places|Tennessee|Nashville'; Latitude=36.1627; Longitude=-86.7816; RadiusMeters=32186.88; ProtectedParents=@() },
        @{ Name='Memphis'; LeafTag='Memphis'; DigiKamTag='Places/Tennessee/Memphis'; HierTag='Places|Tennessee|Memphis'; Latitude=35.1495; Longitude=-90.0490; RadiusMeters=32186.88; ProtectedParents=@() },
        @{ Name='Knoxville'; LeafTag='Knoxville'; DigiKamTag='Places/Tennessee/Knoxville'; HierTag='Places|Tennessee|Knoxville'; Latitude=35.9606; Longitude=-83.9207; RadiusMeters=32186.88; ProtectedParents=@() },
        @{ Name='Chattanooga'; LeafTag='Chattanooga'; DigiKamTag='Places/Tennessee/Chattanooga'; HierTag='Places|Tennessee|Chattanooga'; Latitude=35.0456; Longitude=-85.3097; RadiusMeters=32186.88; ProtectedParents=@() }
    )},
    @{ Name='Louisiana'; GeoId='22'; LeafTag='Louisiana'; DigiKamTag='Places/Louisiana'; HierTag='Places|Louisiana'; ProtectedParents=@(); Cities=@(
        @{ Name='New Orleans'; LeafTag='New Orleans'; DigiKamTag='Places/Louisiana/New Orleans'; HierTag='Places|Louisiana|New Orleans'; Latitude=29.9511; Longitude=-90.0715; RadiusMeters=32186.88; ProtectedParents=@() }
    )}
)

$Orlando = @{ Name='Orlando'; LeafTag='Orlando'; DigiKamTag='Places/Florida/Orlando'; HierTag='Places|Florida|Orlando'; Latitude=28.5383; Longitude=-81.3792; RadiusMeters=32186.88; ProtectedParents=@() }
$DaytonaBeach = @{ Name='Daytona Beach'; LeafTag='Daytona Beach'; DigiKamTag='Places/Florida/Daytona Beach'; HierTag='Places|Florida|Daytona Beach'; Latitude=29.2108; Longitude=-81.0228; RadiusMeters=32186.88; ProtectedParents=@() }
$FloridaKeys = @{ Name='Keys'; LeafTag='Keys'; DigiKamTag='Places/Florida/Keys'; HierTag='Places|Florida|Keys'; ProtectedParents=@() }

# Generic media-type tag applied to every supported video.
$VideoTag = @{
    Name = 'Video'
    LeafTag = 'Video'
    DigiKamTag = 'Video'
    HierTag = 'Video'
}

$PhotoExtensions = @('jpg','jpeg','heic','png','tif','tiff')
$VideoExtensions = @('mp4','mov','m4v','avi')
$script:TargetTagCache = @{}
$script:VideoSidecarTagCache = @{}

$UseYearRange = ($FromYear -gt 0 -or $ToYear -lt 9999)
if ($FromYear -lt 0 -or $ToYear -lt $FromYear) {
    throw "Invalid year range: $FromYear through $ToYear"
}

$ScanRoots = @($Root)
$RangeSuffix = ''
if ($UseYearRange) {
    $ScanRoots = @(
        foreach ($year in $FromYear..$ToYear) {
            $yearPath = Join-Path $Root ([string]$year)
            if (Test-Path -LiteralPath $yearPath -PathType Container) { $yearPath }
        }
    )
    if ($ScanRoots.Count -eq 0) {
        throw "No year folders from $FromYear through $ToYear were found under $Root"
    }
    $RangeSuffix = "-$FromYear-$ToYear"
}

$ReportPath = Join-Path $Root "GPS-County-Geofence-Report$RangeSuffix.csv"
$WriteLogPath = Join-Path $Root "GPS-County-Geofence-WriteLog$RangeSuffix.csv"
$BackupRoot = if ($UseYearRange) {
    Join-Path $Root "_Tag_Backups\County_GPS_Tagging\$FromYear-$ToYear"
} else {
    Join-Path (Split-Path $Root -Parent) '_Tag_Backups\County_GPS_Tagging'
}

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

function Get-CacheKey {
    param([string]$Path)
    try { return [System.IO.Path]::GetFullPath($Path).ToLowerInvariant() }
    catch { return ([string]$Path).ToLowerInvariant() }
}

function Get-AllTagsFromRecord {
    param($Record)

    if ($null -eq $Record) { return @() }
    $all=@()
    $all += @($Record.TagsList)
    $all += @($Record.HierarchicalSubject)
    $all += @($Record.Subject)
    $all += @($Record.LastKeywordXMP)
    $all += @($Record.Keywords)
    return @($all | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

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

    $cacheKey=Get-CacheKey -Path $Target
    if ($script:TargetTagCache.ContainsKey($cacheKey)) {
        return @($script:TargetTagCache[$cacheKey])
    }

    if (-not (Test-Path -LiteralPath $Target)) {
        $script:TargetTagCache[$cacheKey]=@()
        return @()
    }

    $meta = (& $script:ExifTool.Source -json `
        -XMP-digiKam:TagsList `
        -XMP-lr:HierarchicalSubject `
        -XMP-dc:Subject `
        -XMP-MicrosoftPhoto:LastKeywordXMP `
        -IPTC:Keywords `
        $Target) | ConvertFrom-Json

    $all=@(Get-AllTagsFromRecord -Record $meta[0])
    $script:TargetTagCache[$cacheKey]=@($all)
    return @($all)
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

function Test-HasDigiKamVideoTag {
    param([string]$MediaPath)

    # For the generic Video tag, only trust the DigiKam XMP sidecar.
    # Do NOT treat a generic embedded media keyword/subject of "Video" as proof
    # that DigiKam has the Video tag. This avoids false "already tagged" results
    # on MOV/MP4 files whose internal metadata happens to contain that word.
    $sidecar="$MediaPath.xmp"
    if (-not (Test-Path -LiteralPath $sidecar)) { return $false }

    $cacheKey=Get-CacheKey -Path $sidecar
    if ($script:VideoSidecarTagCache.ContainsKey($cacheKey)) {
        return [bool]$script:VideoSidecarTagCache[$cacheKey]
    }

    $meta = (& $script:ExifTool.Source -json `
        -XMP-digiKam:TagsList `
        -XMP-lr:HierarchicalSubject `
        -XMP-dc:Subject `
        $sidecar) | ConvertFrom-Json

    if (-not $meta -or $meta.Count -eq 0) { return $false }

    $tags=@()
    $tags += @($meta[0].TagsList)
    $tags += @($meta[0].HierarchicalSubject)
    $tags += @($meta[0].Subject)

    $hasVideoTag=$false
    foreach ($tag in $tags) {
        if ([string]$tag -ieq 'Video') { $hasVideoTag=$true; break }
    }
    $script:VideoSidecarTagCache[$cacheKey]=$hasVideoTag
    return $hasVideoTag
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

function Get-PythonCommand {
    $candidates=@()
    $python=Get-Command python.exe -ErrorAction SilentlyContinue
    if ($python) { $candidates += @{ File=$python.Source; Prefix=@() } }
    $py=Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) { $candidates += @{ File=$py.Source; Prefix=@() } }
    $bundled=Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    if (Test-Path -LiteralPath $bundled) { $candidates += @{ File=$bundled; Prefix=@() } }
    foreach ($candidate in $candidates) {
        & $candidate.File @($candidate.Prefix + @('--version')) *> $null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    throw 'A working Python 3 runtime was not found for digiKam catalog synchronization.'
}

# -----------------------------
# Setup
# -----------------------------

Write-Host ""
Write-Host "Bell Family Archive - Combined Property + County GPS Geotagger v2.17" -ForegroundColor Cyan
Write-Host "Mode   : $Mode"
Write-Host "Folder : $Root"
if ($UseYearRange) { Write-Host "Years  : $FromYear through $ToYear ($($ScanRoots.Count) folders)" }
Write-Host "Recurse: $(if ($NoRecurse) { 'NO' } else { 'YES' })"
Write-Host "Confederate Ave     : existing 900/910->900 and 909 polygon rules"
Write-Host "973 Community Lane: $($CommunityLane.Latitude), $($CommunityLane.Longitude) / 500 ft"
Write-Host "2044 Douglas Rd    : $($DouglasRoad.Latitude), $($DouglasRoad.Longitude) / 500 ft"
Write-Host "Lancaster Rescue   : $($LancasterRescueSquad.Latitude), $($LancasterRescueSquad.Longitude) / 500 ft"
Write-Host "212 S Main QDS     : $($QDSOffice.Latitude), $($QDSOffice.Longitude) / 500 ft"
Write-Host "Lancaster High     : $($LancasterHighSchool.Latitude), $($LancasterHighSchool.Longitude) / 1000 ft"
Write-Host "Erwin Elementary   : $($ErwinElementary.Latitude), $($ErwinElementary.Longitude) / 1000 ft"
Write-Host "Sub Fiber          : $($SubFiber.Latitude), $($SubFiber.Longitude) / 1000 ft"
Write-Host "Myrtle Beach       : $($MyrtleBeach.Latitude), $($MyrtleBeach.Longitude) / 50 miles"
Write-Host "Crystal River      : $($CrystalRiver.Latitude), $($CrystalRiver.Longitude) / 20 miles"
Write-Host "Florida            : anywhere else in Florida -> Places/Florida"
Write-Host "Florida cities     : Orlando, Daytona Beach / 20 miles; Keys regional geofence"
Write-Host "Travel states      : Georgia (Savannah, Atlanta); Virginia (Newport News); Washington DC; Tennessee (Nashville, Memphis, Knoxville, Chattanooga); Louisiana (New Orleans)"
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

# Load travel state boundaries from Census TIGERweb.
$AllTravelStates=@($Florida)+@($TravelStates)
foreach ($State in $AllTravelStates) {
    Write-Host "Downloading $($State.Name) boundary..." -ForegroundColor Cyan
    $stateQuery="https://tigerweb.geo.census.gov/arcgis/rest/services/Census2020/State_County/MapServer/4/query?where=GEOID%3D%27$($State.GeoId)%27&outFields=GEOID%2CNAME&returnGeometry=true&outSR=4326&f=geojson"
    try { $stateGeo=Invoke-RestMethod -Uri $stateQuery -Method Get }
    catch { Write-Host "ERROR: Could not download $($State.Name) boundary." -ForegroundColor Red; Write-Host $_; exit 1 }
    if (-not $stateGeo.features -or $stateGeo.features.Count -lt 1) { Write-Host "ERROR: No geometry returned for $($State.Name)." -ForegroundColor Red; exit 1 }
    $State.Geometry=$stateGeo.features[0].geometry
}
Write-Host "All travel state boundaries loaded successfully." -ForegroundColor Green
Write-Host ""

# -----------------------------
# Scan media once
# -----------------------------

Write-Host "Reading GPS from supported photos/videos..." -ForegroundColor Cyan

$ExifArgs=@(
    '-json','-n',
    '-i','.dtrash',
    '-GPSLatitude','-GPSLongitude',
    '-FileName','-Directory','-FileTypeExtension',
    '-XMP-digiKam:TagsList','-XMP-lr:HierarchicalSubject','-XMP-dc:Subject',
    '-XMP-MicrosoftPhoto:LastKeywordXMP','-IPTC:Keywords'
)

foreach ($ext in ($PhotoExtensions+$VideoExtensions)) {
    $ExifArgs += @('-ext',$ext)
}

if ($NoRecurse) {
    $ExifArgs += $ScanRoots
}
else {
    $ExifArgs += '-r'
    $ExifArgs += $ScanRoots
}

$Items=(& $ExifTool.Source @ExifArgs) | ConvertFrom-Json
$Items=@($Items | Where-Object {
    $candidate=Join-Path $_.Directory $_.FileName
    $candidate -notmatch '(?i)(^|[\\/])\.dtrash([\\/]|$)'
})

foreach ($Item in $Items) {
    $target=Join-Path $Item.Directory $Item.FileName
    $script:TargetTagCache[(Get-CacheKey -Path $target)]=@(Get-AllTagsFromRecord -Record $Item)
}

Write-Host "Reading XMP sidecar tags in one batch..." -ForegroundColor Cyan
$SidecarArgs=@(
    '-json','-i','.dtrash',
    '-FileName','-Directory',
    '-XMP-digiKam:TagsList','-XMP-lr:HierarchicalSubject','-XMP-dc:Subject',
    '-XMP-MicrosoftPhoto:LastKeywordXMP','-IPTC:Keywords',
    '-ext','xmp'
)
if ($NoRecurse) {
    $SidecarArgs += $ScanRoots
}
else {
    $SidecarArgs += '-r'
    $SidecarArgs += $ScanRoots
}
$SidecarItems=(& $ExifTool.Source @SidecarArgs) | ConvertFrom-Json
$SidecarItems=@($SidecarItems)
foreach ($SidecarItem in $SidecarItems) {
    $target=Join-Path $SidecarItem.Directory $SidecarItem.FileName
    $cacheKey=Get-CacheKey -Path $target
    $script:TargetTagCache[$cacheKey]=@(Get-AllTagsFromRecord -Record $SidecarItem)
    $videoTags=@()
    $videoTags += @($SidecarItem.TagsList)
    $videoTags += @($SidecarItem.HierarchicalSubject)
    $videoTags += @($SidecarItem.Subject)
    $script:VideoSidecarTagCache[$cacheKey]=(@($videoTags | Where-Object { [string]$_ -ieq 'Video' }).Count -gt 0)
}
Write-Host "Cached tags for $($Items.Count) media files and $($SidecarItems.Count) sidecars." -ForegroundColor Green
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
        # v2.12 policy: EVERY supported video must receive the exact DigiKam
        # Video tag.  Do not skip based on metadata detection; the write is
        # additive/idempotent and preserves existing tags.
        $hasVideoTag=Test-HasDigiKamVideoTag -MediaPath $fullPath
        $videoTagNeeded=$true
    }

    if (-not $hasGps) {
        # Trusted point locations work in reverse too: if the file already has
        # a specific location tag but lacks GPS, use that location's fixed
        # reference coordinate. Existing GPS is never replaced.
        $trustedPoint=$null
        foreach ($point in @($CommunityLane,$DouglasRoad,$LancasterRescueSquad,$QDSOffice,$LancasterHighSchool,$ErwinElementary,$SubFiber)) {
            if (Test-AlreadyHasCountyTag -MediaPath $fullPath -County $point) {
                $trustedPoint=$point
                break
            }
        }

        if ($trustedPoint) {
            $action="EMBED GPS $($trustedPoint.Name)"
            $proposed=$trustedPoint.DigiKamTag
            if ($trustedPoint -eq $SubFiber) { $countyMatch='Chester County' }
            else { $countyMatch='Lancaster County' }
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

    $lancasterRescueDistanceMeters=Get-DistanceMeters `
        -Lat1 $lat `
        -Lon1 $lon `
        -Lat2 $LancasterRescueSquad.Latitude `
        -Lon2 $LancasterRescueSquad.Longitude

    $qdsOfficeDistanceMeters=Get-DistanceMeters `
        -Lat1 $lat `
        -Lon1 $lon `
        -Lat2 $QDSOffice.Latitude `
        -Lon2 $QDSOffice.Longitude


    $lancasterHighDistanceMeters=Get-DistanceMeters `
        -Lat1 $lat `
        -Lon1 $lon `
        -Lat2 $LancasterHighSchool.Latitude `
        -Lon2 $LancasterHighSchool.Longitude

    $erwinDistanceMeters=Get-DistanceMeters `
        -Lat1 $lat `
        -Lon1 $lon `
        -Lat2 $ErwinElementary.Latitude `
        -Lon2 $ErwinElementary.Longitude

    $subFiberDistanceMeters=Get-DistanceMeters `
        -Lat1 $lat `
        -Lon1 $lon `
        -Lat2 $SubFiber.Latitude `
        -Lon2 $SubFiber.Longitude

    $subFiberDistanceFeet=$subFiberDistanceMeters * 3.280839895

    $myrtleBeachDistanceMeters=Get-DistanceMeters `
        -Lat1 $lat `
        -Lon1 $lon `
        -Lat2 $MyrtleBeach.Latitude `
        -Lon2 $MyrtleBeach.Longitude

    $myrtleBeachDistanceMiles=$myrtleBeachDistanceMeters / 1609.344

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
        # Some GPS points can fall in or near the 909 property polygon even when
        # the media has already been intentionally identified as 900. Preserve
        # that existing identification and never add 909 in that situation.
        $has909Match=@($confederateMatches | Where-Object { $_.LeafTag -eq '909 Confederate Ave' }).Count -gt 0
        $confederate900Property=$ConfederateProperties | Where-Object {
            $_.LeafTag -eq '900 Confederate Ave'
        } | Select-Object -First 1
        $alreadyTagged900=$false

        if ($has909Match -and $confederate900Property) {
            $alreadyTagged900=Test-AlreadyHasCountyTag `
                -MediaPath $fullPath `
                -County $confederate900Property
        }

        if ($has909Match -and $alreadyTagged900) {
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
                ProtectedChildLocation='900 Confederate Ave'
                AlreadyCountyTag='YES'
                VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
                Action='SKIP - existing 900 Confederate Ave blocks 909 Confederate Ave'
                ProposedTag=''
            }
            continue
        }

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

    # Lancaster workplaces are checked before schools and general county classification.
    $workplaceMatch=$null
    if ($lancasterRescueDistanceMeters -le $LancasterRescueSquad.RadiusMeters) {
        $workplaceMatch=$LancasterRescueSquad
    }
    elseif ($qdsOfficeDistanceMeters -le $QDSOffice.RadiusMeters) {
        $workplaceMatch=$QDSOffice
    }

    if ($workplaceMatch) {
        $hasWorkplaceTag=Test-AlreadyHasCountyTag -MediaPath $fullPath -County $workplaceMatch
        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName; FileType=$kind; FullPath=$fullPath; HasGPS='YES'
            Latitude=[Math]::Round($lat,7); Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1)
            DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1)
            DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            ConfederateMatch=''; CountyMatch='Lancaster County'; ProtectedChildLocation=''
            AlreadyCountyTag=if($hasWorkplaceTag){'YES'}else{'NO'}
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action=if($hasWorkplaceTag){"SKIP - already $($workplaceMatch.Name) tagged"}else{"TAG $($workplaceMatch.Name)"}
            ProposedTag=if($hasWorkplaceTag){''}else{$workplaceMatch.DigiKamTag}
        }
        continue
    }

    # Lancaster schools are checked before general Lancaster County classification.
    $schoolMatch=$null
    if ($lancasterHighDistanceMeters -le $LancasterHighSchool.RadiusMeters) {
        $schoolMatch=$LancasterHighSchool
    }
    elseif ($erwinDistanceMeters -le $ErwinElementary.RadiusMeters) {
        $schoolMatch=$ErwinElementary
    }

    if ($schoolMatch) {
        $hasSchoolTag=Test-AlreadyHasCountyTag -MediaPath $fullPath -County $schoolMatch
        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName; FileType=$kind; FullPath=$fullPath; HasGPS='YES'
            Latitude=[Math]::Round($lat,7); Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1)
            DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1)
            DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            ConfederateMatch=''; CountyMatch='Lancaster County'; ProtectedChildLocation=''
            AlreadyCountyTag=if($hasSchoolTag){'YES'}else{'NO'}
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action=if($hasSchoolTag){"SKIP - already $($schoolMatch.Name) tagged"}else{"TAG $($schoolMatch.Name)"}
            ProposedTag=if($hasSchoolTag){''}else{$schoolMatch.DigiKamTag}
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

    # Myrtle Beach rule: 50-mile radius, evaluated before generic county/state rules.
    if ($myrtleBeachDistanceMeters -le $MyrtleBeach.RadiusMeters) {
        $alreadyLocation=Test-AlreadyHasCountyTag -MediaPath $fullPath -County $MyrtleBeach
        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName; FileType=$kind; FullPath=$fullPath; HasGPS='YES'
            Latitude=[Math]::Round($lat,7); Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1); DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1); DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            DistanceToMyrtleBeachMiles=[Math]::Round($myrtleBeachDistanceMiles,2)
            ConfederateMatch=''; CountyMatch='Myrtle Beach'; ProtectedChildLocation=''
            AlreadyCountyTag=if($alreadyLocation){'YES'}else{'NO'}
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action=if($alreadyLocation){'SKIP - already Myrtle Beach tagged'}else{'TAG Myrtle Beach'}
            ProposedTag=if($alreadyLocation){''}else{$MyrtleBeach.DigiKamTag}
        }
        continue
    }

    # Florida rules: specific destinations first, then generic Florida.
    if (Test-PointInGeoJsonGeometry -Latitude $lat -Longitude $lon -Geometry $Florida.Geometry) {
        $orlandoDistance=Get-DistanceMeters -Lat1 $lat -Lon1 $lon -Lat2 $Orlando.Latitude -Lon2 $Orlando.Longitude
        $daytonaDistance=Get-DistanceMeters -Lat1 $lat -Lon1 $lon -Lat2 $DaytonaBeach.Latitude -Lon2 $DaytonaBeach.Longitude
        # Regional Keys geofence: broad chain envelope, intentionally checked only after confirming the point is in Florida.
        $inKeys=($lat -ge 24.35 -and $lat -le 25.85 -and $lon -ge -82.15 -and $lon -le -80.00)
        if ($crystalRiverDistanceMeters -le $CrystalRiver.RadiusMeters) { $TargetLocation=$CrystalRiver; $actionName='Crystal River' }
        elseif ($orlandoDistance -le $Orlando.RadiusMeters) { $TargetLocation=$Orlando; $actionName='Orlando' }
        elseif ($daytonaDistance -le $DaytonaBeach.RadiusMeters) { $TargetLocation=$DaytonaBeach; $actionName='Daytona Beach' }
        elseif ($inKeys) { $TargetLocation=$FloridaKeys; $actionName='Keys' }
        else { $TargetLocation=$Florida; $actionName='Florida' }

        $alreadyLocation=Test-AlreadyHasCountyTag -MediaPath $fullPath -County $TargetLocation
        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName; FileType=$kind; FullPath=$fullPath; HasGPS='YES'
            Latitude=[Math]::Round($lat,7); Longitude=[Math]::Round($lon,7)
            DistanceTo973Ft=[Math]::Round($distanceFeet,1); DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1); DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
            DistanceToCrystalRiverMiles=[Math]::Round($crystalRiverDistanceMiles,2)
            ConfederateMatch=''; CountyMatch=$actionName; ProtectedChildLocation=''
            AlreadyCountyTag=if($alreadyLocation){'YES'}else{'NO'}
            VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
            Action=if($alreadyLocation){"SKIP - already $actionName tagged"}else{"TAG $actionName"}
            ProposedTag=if($alreadyLocation){''}else{$TargetLocation.DigiKamTag}
        }
        continue
    }

    # Other configured travel states: city first (20 miles), then state.
    $travelMatched=$false
    foreach ($State in $TravelStates) {
        if (Test-PointInGeoJsonGeometry -Latitude $lat -Longitude $lon -Geometry $State.Geometry) {
            $TargetLocation=$State
            $actionName=$State.Name
            foreach ($City in $State.Cities) {
                $cityDistance=Get-DistanceMeters -Lat1 $lat -Lon1 $lon -Lat2 $City.Latitude -Lon2 $City.Longitude
                if ($cityDistance -le $City.RadiusMeters) { $TargetLocation=$City; $actionName=$City.Name; break }
            }
            $alreadyLocation=Test-AlreadyHasCountyTag -MediaPath $fullPath -County $TargetLocation
            $Rows += [PSCustomObject]@{
                FileName=$Item.FileName; FileType=$kind; FullPath=$fullPath; HasGPS='YES'
                Latitude=[Math]::Round($lat,7); Longitude=[Math]::Round($lon,7)
                DistanceTo973Ft=[Math]::Round($distanceFeet,1); DistanceToDouglasFt=[Math]::Round($douglasDistanceFeet,1); DistanceToSubFiberFt=[Math]::Round($subFiberDistanceFeet,1)
                ConfederateMatch=''; CountyMatch=$actionName; ProtectedChildLocation=''
                AlreadyCountyTag=if($alreadyLocation){'YES'}else{'NO'}
                VideoTagNeeded=if($videoTagNeeded){'YES'}else{'NO'}
                Action=if($alreadyLocation){"SKIP - already $actionName tagged"}else{"TAG $actionName"}
                ProposedTag=if($alreadyLocation){''}else{$TargetLocation.DigiKamTag}
            }
            $travelMatched=$true
            break
        }
    }
    if ($travelMatched) { continue }

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
$embedDouglas=@($Rows | Where-Object {$_.Action -eq 'EMBED GPS 2044 Douglas Rd'})
$embedLancasterRescue=@($Rows | Where-Object {$_.Action -eq 'EMBED GPS Lancaster Rescue Squad'})
$embedQDSOffice=@($Rows | Where-Object {$_.Action -eq 'EMBED GPS 212 S Main St QDS Office'})
$embedLancasterHigh=@($Rows | Where-Object {$_.Action -eq 'EMBED GPS Lancaster High School'})
$embedErwin=@($Rows | Where-Object {$_.Action -eq 'EMBED GPS Erwin Elementary'})
$embedSubFiber=@($Rows | Where-Object {$_.Action -eq 'EMBED GPS Sub Fiber'})
$tagDouglas=@($Rows | Where-Object {$_.Action -eq 'TAG 2044 Douglas Rd'})
$skipDouglas=@($Rows | Where-Object {$_.Action -eq 'SKIP - already 2044 Douglas Rd tagged'}).Count
$tagLancasterRescue=@($Rows | Where-Object {$_.Action -eq 'TAG Lancaster Rescue Squad'})
$skipLancasterRescue=@($Rows | Where-Object {$_.Action -eq 'SKIP - already Lancaster Rescue Squad tagged'}).Count
$tagQDSOffice=@($Rows | Where-Object {$_.Action -eq 'TAG 212 S Main St QDS Office'})
$skipQDSOffice=@($Rows | Where-Object {$_.Action -eq 'SKIP - already 212 S Main St QDS Office tagged'}).Count
$tagLancasterHigh=@($Rows | Where-Object {$_.Action -eq 'TAG Lancaster High School'})
$skipLancasterHigh=@($Rows | Where-Object {$_.Action -eq 'SKIP - already Lancaster High School tagged'}).Count
$tagErwin=@($Rows | Where-Object {$_.Action -eq 'TAG Erwin Elementary'})
$skipErwin=@($Rows | Where-Object {$_.Action -eq 'SKIP - already Erwin Elementary tagged'}).Count
$skip900=@($Rows | Where-Object {$_.Action -eq 'SKIP - already 900 Confederate Ave tagged'}).Count
$tag900=@($Rows | Where-Object {$_.Action -eq 'TAG 900 Confederate Ave'})
$skip909=@($Rows | Where-Object {$_.Action -eq 'SKIP - already 909 Confederate Ave tagged'}).Count
$skip909Because900=@($Rows | Where-Object {$_.Action -eq 'SKIP - existing 900 Confederate Ave blocks 909 Confederate Ave'}).Count
$tag909=@($Rows | Where-Object {$_.Action -eq 'TAG 909 Confederate Ave'})
$skipSubFiber=@($Rows | Where-Object {$_.Action -eq 'SKIP - already Sub Fiber tagged'}).Count
$tagSubFiber=@($Rows | Where-Object {$_.Action -eq 'TAG Sub Fiber'})
$tagMyrtleBeach=@($Rows | Where-Object {$_.Action -eq 'TAG Myrtle Beach'})
$skipMyrtleBeach=@($Rows | Where-Object {$_.Action -eq 'SKIP - already Myrtle Beach tagged'}).Count
$tagCrystalRiver=@($Rows | Where-Object {$_.Action -eq 'TAG Crystal River'})
$skipCrystalRiver=@($Rows | Where-Object {$_.Action -eq 'SKIP - already Crystal River tagged'}).Count
$tagFlorida=@($Rows | Where-Object {$_.Action -eq 'TAG Florida'})
$skipFlorida=@($Rows | Where-Object {$_.Action -eq 'SKIP - already Florida tagged'}).Count
$videoTags=@($Rows | Where-Object {$_.VideoTagNeeded -eq 'YES'})
$toWrite=@($Rows | Where-Object {
    $_.Action -like 'TAG *' -or
    $_.Action -like 'EMBED GPS *' -or
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
Write-Host "2044 Douglas tags need GPS : $($embedDouglas.Count)"
Write-Host "Skipped - already Rescue   : $skipLancasterRescue"
Write-Host "Lancaster Rescue matches   : $($tagLancasterRescue.Count)"
Write-Host "Lancaster Rescue needs GPS : $($embedLancasterRescue.Count)"
Write-Host "Skipped - already QDS      : $skipQDSOffice"
Write-Host "212 S Main QDS matches     : $($tagQDSOffice.Count)"
Write-Host "212 S Main QDS needs GPS   : $($embedQDSOffice.Count)"
Write-Host "Skipped - already LHS      : $skipLancasterHigh"
Write-Host "Lancaster High matches/tag : $($tagLancasterHigh.Count)"
Write-Host "Lancaster High tags needGPS: $($embedLancasterHigh.Count)"
Write-Host "Skipped - already Erwin    : $skipErwin"
Write-Host "Erwin Elementary match/tag : $($tagErwin.Count)"
Write-Host "Erwin tags needing GPS     : $($embedErwin.Count)"
Write-Host "Skipped - already 900 tag  : $skip900"
Write-Host "900/910 GPS matches/tag    : $($tag900.Count)"
Write-Host "Skipped - already 909 tag  : $skip909"
Write-Host "Skipped 909 - kept 900 tag : $skip909Because900"
Write-Host "909 GPS matches/tag        : $($tag909.Count)"
Write-Host "Skipped - already SubFiber : $skipSubFiber"
Write-Host "Sub Fiber GPS matches/tag  : $($tagSubFiber.Count)"
Write-Host "Sub Fiber tags needing GPS : $($embedSubFiber.Count)"
Write-Host "Skipped - already Myrtle   : $skipMyrtleBeach"
Write-Host "Myrtle Beach matches/tag   : $($tagMyrtleBeach.Count)"
Write-Host "Skipped - already Crystal  : $skipCrystalRiver"
Write-Host "Crystal River matches/tag  : $($tagCrystalRiver.Count)"
Write-Host "Skipped - already Florida  : $skipFlorida"
Write-Host "Florida matches/tag        : $($tagFlorida.Count)"
Write-Host "Videos to enforce Video tag: $($videoTags.Count)"
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
Write-Host "  Confederate Ave: an existing 900 tag always blocks a new 909 tag"
Write-Host "  973 rule: GPS within 500 ft -> add the specific home tag"
Write-Host "  973 rule: photo has the home tag but no GPS -> embed the fixed GPS in photo + sidecar"
Write-Host "  2044 Douglas Rd: GPS within 500 ft -> tag; existing tag without GPS -> embed fixed GPS"
Write-Host "  Lancaster High School: GPS within 1000 ft -> tag; existing tag without GPS -> embed fixed GPS"
Write-Host "  Erwin Elementary: GPS within 1000 ft -> tag; existing tag without GPS -> embed fixed GPS"
Write-Host "  Sub Fiber: GPS within 1000 ft -> tag; existing tag without GPS -> embed fixed GPS"
Write-Host "  Myrtle Beach: GPS within 50 miles -> add Places/South Carolina/Myrtle Beach"
Write-Host "  Florida: within 20 miles of Crystal River -> add Places/Florida/Crystal River"
Write-Host "  Florida: otherwise anywhere in Florida -> add Places/Florida"
Write-Host "  Florida: Orlando and Daytona Beach within 20 miles; Keys regional geofence"
Write-Host "  Travel states: city tags within 20 miles, otherwise state tag for GA/VA/DC/TN/LA"
Write-Host "  Every supported video -> add Video tag"
Write-Host "  Existing GPS is NEVER replaced"
Write-Host "  Photos: write location/county tags to image AND .xmp sidecar"
Write-Host "  Videos: write location/county tags to .xmp sidecar only"
Write-Host "  Existing tags are preserved"
Write-Host "  Protected child locations are re-checked before county writes"
if (-not $SkipDigiKamCatalogSync) {
    Write-Host "  Affected tags and GPS are synchronized into the digiKam catalog"
    Write-Host "  digiKam must be closed; the catalog is backed up and verified"
}
Write-Host ""

$CatalogSyncHelper=Join-Path $PSScriptRoot 'tools\sync_gps_metadata_to_digikam.py'
$PythonCommand=$null
if (-not $SkipDigiKamCatalogSync) {
    if (Get-Process -Name digikam -ErrorAction SilentlyContinue) {
        Write-Host 'WRITE STOPPED: close digiKam before running catalog synchronization.' -ForegroundColor Red
        exit 1
    }
    foreach ($required in @($DigiKamDatabase,$DigiKamCollectionRoot,$CatalogSyncHelper)) {
        if (-not (Test-Path -LiteralPath $required)) {
            Write-Host "WRITE STOPPED: required catalog-sync path is missing: $required" -ForegroundColor Red
            exit 1
        }
    }
    $PythonCommand=Get-PythonCommand
}

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
    # Trusted point tag -> GPS reverse geocoding
    # ---------------------------------------------------------
    if ($row.Action -like 'EMBED GPS *') {
        $Point=@($CommunityLane,$DouglasRoad,$LancasterRescueSquad,$QDSOffice,$LancasterHighSchool,$ErwinElementary,$SubFiber) | Where-Object {
            $_.DigiKamTag -eq $row.ProposedTag
        } | Select-Object -First 1

        if (-not $Point) { $errors++; continue }

        if ($row.FileType -eq 'Video') {
            # Do not alter the media container. Put fixed GPS + tags in XMP sidecar.
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
                if ($sidecarCreateResult -eq 'ERROR') { $errors++; continue }
            }
            $tagResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false -County $Point
            $videoResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false -County $VideoTag
            $gpsResult=Set-GpsOnSidecar -Target $sidecar -Latitude $Point.Latitude -Longitude $Point.Longitude
            if ($tagResult -eq 'ERROR' -or $videoResult -eq 'ERROR' -or $gpsResult -eq 'ERROR') { $errors++; $overall='ERROR' }
            else { $changed++; $overall="$($Point.Name) tag ensured + GPS embedded in sidecar" }
            $WriteLog += [PSCustomObject]@{FileName=$row.FileName;FileType='Video';County=$Point.Name;Result=$overall;PhotoResult='';SidecarResult="$tagResult / $videoResult / $gpsResult";Backup=$backup}
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
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sidecar)) { $errors++; continue }
            }
            $photoTag=Add-TagsToTarget -Target $photo -PreserveTimestamp:$true -County $Point
            $sidecarTag=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false -County $Point
            $photoGps=Set-GpsOnPhoto -Target $photo -Latitude $Point.Latitude -Longitude $Point.Longitude
            $sidecarGps=Set-GpsOnSidecar -Target $sidecar -Latitude $Point.Latitude -Longitude $Point.Longitude
            if ($photoTag -eq 'ERROR' -or $sidecarTag -eq 'ERROR' -or $photoGps -eq 'ERROR' -or $sidecarGps -eq 'ERROR') { $errors++; $overall='ERROR' }
            else { $changed++; $overall="$($Point.Name) tag ensured + GPS embedded" }
            $WriteLog += [PSCustomObject]@{FileName=$row.FileName;FileType='Photo';County=$Point.Name;Result=$overall;PhotoResult="$photoTag / $photoGps";SidecarResult="$sidecarTag / $sidecarGps";Backup="$photoBackup | $sidecarBackup"}
            continue
        }
    }

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

    $TravelCityTargets=@($TravelStates | ForEach-Object { $_.Cities })
    $AllGenericTargets=@($Counties) + @($DouglasRoad,$LancasterRescueSquad,$QDSOffice,$LancasterHighSchool,$ErwinElementary,$MyrtleBeach,$CrystalRiver,$Orlando,$DaytonaBeach,$FloridaKeys,$Florida) + @($TravelStates) + @($TravelCityTargets)
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

$CatalogSyncStatus='SKIPPED'
if (-not $SkipDigiKamCatalogSync) {
    if (Get-Process -Name digikam -ErrorAction SilentlyContinue) {
        throw 'Metadata writes completed, but catalog sync stopped because digiKam was opened. Close digiKam and rerun the catalog helper using the affected-path list.'
    }
    $syncStamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $CatalogSyncPaths=Join-Path $BackupRoot "DigiKam-GPS-Sync-Paths-$syncStamp.txt"
    @($toWrite | ForEach-Object { $_.FullPath } | Sort-Object -Unique) |
        Set-Content -LiteralPath $CatalogSyncPaths -Encoding UTF8
    $syncArgs=@($PythonCommand.Prefix) + @(
        $CatalogSyncHelper,
        '--database',$DigiKamDatabase,
        '--collection-root',$DigiKamCollectionRoot,
        '--paths-file',$CatalogSyncPaths,
        '--backup-dir',$BackupRoot,
        '--exiftool',$ExifTool.Source
    )
    Write-Host ''
    Write-Host 'Synchronizing affected metadata into the digiKam catalog...' -ForegroundColor Cyan
    & $PythonCommand.File @syncArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Metadata files were written, but digiKam catalog synchronization failed (exit $LASTEXITCODE). Catalog path list: $CatalogSyncPaths"
    }
    $CatalogSyncStatus='COMPLETE'
}

Write-Host ""
Write-Host "WRITE COMPLETE" -ForegroundColor Green
Write-Host "Changed          : $changed"
Write-Host "Already tagged   : $already"
Write-Host "Skipped at write : $skippedAtWrite"
Write-Host "Errors           : $errors"
Write-Host "Write log        : $WriteLogPath"
Write-Host "Backups          : $BackupRoot"
Write-Host "DigiKam catalog  : $CatalogSyncStatus"
Write-Host ""
if ($SkipDigiKamCatalogSync) {
    Write-Host "Then use DigiKam: Reread Metadata From File for the folder." -ForegroundColor Cyan
}
else {
    Write-Host "No DigiKam metadata reread is required. Reopen digiKam." -ForegroundColor Cyan
}

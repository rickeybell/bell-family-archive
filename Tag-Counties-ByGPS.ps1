param(
    [ValidateSet('REPORT','WRITE')]
    [string]$Mode = 'REPORT',

    [string]$Root = 'C:\Users\rbell\OneDrive\Pictures\2019'
)

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

# -----------------------------
# Setup
# -----------------------------

Write-Host ""
Write-Host "Bell Family Archive - Combined County GPS Geotagger" -ForegroundColor Cyan
Write-Host "Mode   : $Mode"
Write-Host "Folder : $Root"
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

$ExifArgs += @('-r',$Root)

$Items=(& $ExifTool.Source @ExifArgs) | ConvertFrom-Json
$Rows=@()

foreach ($Item in $Items) {
    $kind=Get-FileKind -Extension ([string]$Item.FileTypeExtension)
    $fullPath=Join-Path $Item.Directory $Item.FileName

    $hasGps=(
        $null -ne $Item.GPSLatitude -and
        $null -ne $Item.GPSLongitude
    )

    if (-not $hasGps) {
        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName
            FileType=$kind
            FullPath=$fullPath
            HasGPS='NO'
            Latitude=''
            Longitude=''
            CountyMatch=''
            ProtectedChildLocation=''
            AlreadyCountyTag=''
            Action='No GPS'
            ProposedTag=''
        }
        continue
    }

    $lat=[double]$Item.GPSLatitude
    $lon=[double]$Item.GPSLongitude

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
            CountyMatch=''
            ProtectedChildLocation=''
            AlreadyCountyTag=''
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
            CountyMatch=($matchedCounties.Name -join ' | ')
            ProtectedChildLocation=''
            AlreadyCountyTag=''
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
        CountyMatch=$County.Name
        ProtectedChildLocation=($protected -join ' | ')
        AlreadyCountyTag=if($already){'YES'}else{'NO'}
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
$reviewCount=@($Rows | Where-Object {$_.Action -eq 'REVIEW - multiple county match'}).Count
$skipChild=@($Rows | Where-Object {$_.Action -eq 'SKIP - specific child location exists'}).Count
$skipCounty=@($Rows | Where-Object {$_.Action -eq 'SKIP - already county tagged'}).Count
$toWrite=@($Rows | Where-Object {$_.Action -like 'TAG *'})

Write-Host ""
Write-Host "REPORT SUMMARY" -ForegroundColor Cyan
Write-Host "Total supported files      : $total"
Write-Host "Files with GPS             : $gpsCount"
Write-Host "Skipped - child location   : $skipChild"
Write-Host "Skipped - already county   : $skipCounty"
Write-Host "Needs review               : $reviewCount"
Write-Host "Will tag                   : $($toWrite.Count)"
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
    Write-Host "WRITE STOPPED: one or more files matched multiple counties." -ForegroundColor Red
    Write-Host "Review the CSV first. Nothing was changed."
    exit 1
}

if ($toWrite.Count -eq 0) {
    Write-Host ""
    Write-Host "Nothing needs county tagging." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "WRITE mode will:" -ForegroundColor Yellow
Write-Host "  Photos: write county tag to image AND .xmp sidecar"
Write-Host "  Videos: write county tag to .xmp sidecar only"
Write-Host "  Existing tags are preserved"
Write-Host "  Protected child locations are re-checked before each write"
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
    $County=$Counties | Where-Object {
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
            & $ExifTool.Source `
                -o $sidecar `
                $row.FullPath | Out-Null

            if (
                $LASTEXITCODE -ne 0 -or
                -not (Test-Path -LiteralPath $sidecar)
            ) {
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

        if ($sidecarResult -eq 'Tagged') {
            $changed++
        }
        elseif ($sidecarResult -eq 'Already tagged') {
            $already++
        }
        else {
            $errors++
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

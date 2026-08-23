param(
    [ValidateSet('REPORT','WRITE')]
    [string]$Mode = 'REPORT',

    [string]$Root = 'C:\Users\rbell\OneDrive\Pictures\2019'
)

$LeafTag = 'Lancaster County'
$DigiKamTag = 'Places/South Carolina/Lancaster County'
$HierTag = 'Places|South Carolina|Lancaster County'

$ReportPath = Join-Path $Root 'GPS-Lancaster-County-Report.csv'
$WriteLogPath = Join-Path $Root 'GPS-Lancaster-County-WriteLog.csv'
$BackupRoot = 'C:\Users\rbell\OneDrive\Pictures\_Tag_Backups\Lancaster_County'

$PhotoExtensions = @('jpg','jpeg','heic','png','tif','tiff')
$VideoExtensions = @('mp4','mov','m4v','avi')

# Lancaster County, SC GEOID 45057
$CountyQuery = "https://tigerweb.geo.census.gov/arcgis/rest/services/Census2020/State_County/MapServer/5/query?where=GEOID%3D%2745057%27&outFields=GEOID%2CNAME%2CBASENAME&returnGeometry=true&outSR=4326&f=geojson"

function Test-PointInRing {
    param([double]$Latitude,[double]$Longitude,[array]$Ring)

    $inside = $false
    $j = $Ring.Count - 1

    for ($i=0; $i -lt $Ring.Count; $i++) {
        $xi=[double]$Ring[$i][0]; $yi=[double]$Ring[$i][1]
        $xj=[double]$Ring[$j][0]; $yj=[double]$Ring[$j][1]

        if (($yi -gt $Latitude) -ne ($yj -gt $Latitude)) {
            $xIntersect=(($xj-$xi)*($Latitude-$yi)/($yj-$yi))+$xi
            if ($Longitude -lt $xIntersect) { $inside = -not $inside }
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
        return Test-PointInPolygonWithHoles -Latitude $Latitude -Longitude $Longitude -PolygonCoordinates $Geometry.coordinates
    }

    if ($Geometry.type -eq 'MultiPolygon') {
        foreach ($polygon in $Geometry.coordinates) {
            if (Test-PointInPolygonWithHoles -Latitude $Latitude -Longitude $Longitude -PolygonCoordinates $polygon) {
                return $true
            }
        }
        return $false
    }

    throw "Unsupported GeoJSON geometry type: $($Geometry.type)"
}

function Get-FileKind {
    param([string]$Extension)

    $e=$Extension.ToLowerInvariant()
    if ($PhotoExtensions -contains $e) { return 'Photo' }
    if ($VideoExtensions -contains $e) { return 'Video' }
    return 'Other'
}

function Get-AllTagsFromTarget {
    param([string]$Target)

    if (-not (Test-Path -LiteralPath $Target)) { return @() }

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

    return @($all | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Test-HasSpecificLancasterTag {
    param([string]$MediaPath)

    $allTags=@()
    $allTags += Get-AllTagsFromTarget -Target $MediaPath

    $sidecar="$MediaPath.xmp"
    if (Test-Path -LiteralPath $sidecar) {
        $allTags += Get-AllTagsFromTarget -Target $sidecar
    }

    foreach ($tag in $allTags) {
        $t=[string]$tag

        # Any child under Places > South Carolina > Lancaster County counts as more specific.
        if ($t -match '(?i)^Places[/|]South Carolina[/|]Lancaster County[/|].+') {
            return $true
        }
    }

    return $false
}

function Test-AlreadyHasLancasterCounty {
    param([string]$MediaPath)

    $allTags=@()
    $allTags += Get-AllTagsFromTarget -Target $MediaPath

    $sidecar="$MediaPath.xmp"
    if (Test-Path -LiteralPath $sidecar) {
        $allTags += Get-AllTagsFromTarget -Target $sidecar
    }

    foreach ($tag in $allTags) {
        $t=[string]$tag
        if ($t -ieq 'Lancaster County' -or
            $t -ieq 'Places/South Carolina/Lancaster County' -or
            $t -ieq 'Places|South Carolina|Lancaster County') {
            return $true
        }
    }

    return $false
}

function Add-TagsToTarget {
    param([string]$Target,[bool]$PreserveTimestamp)

    $meta = (& $script:ExifTool.Source -json `
        -XMP-digiKam:TagsList `
        -XMP-lr:HierarchicalSubject `
        -XMP-dc:Subject `
        $Target) | ConvertFrom-Json

    $currentDigiKam=@($meta[0].TagsList)
    $currentHier=@($meta[0].HierarchicalSubject)
    $currentSubject=@($meta[0].Subject)

    $args=@('-overwrite_original')
    if ($PreserveTimestamp) { $args=@('-P','-overwrite_original') }

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
    if ($args.Count -eq $baseCount) { return 'Already tagged' }

    $args += $Target
    & $script:ExifTool.Source @args | Out-Null
    if ($LASTEXITCODE -eq 0) { return 'Tagged' }
    return 'ERROR'
}

Write-Host ""
Write-Host "Bell Family Archive - Lancaster County GPS Geofence" -ForegroundColor Cyan
Write-Host "Mode   : $Mode"
Write-Host "Folder : $Root"
Write-Host "Tag    : $DigiKamTag"
Write-Host ""
Write-Host "RULE: if a file already has Places/South Carolina/Lancaster County/<specific place>, it is skipped." -ForegroundColor Yellow
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

Write-Host "Downloading official Lancaster County boundary from U.S. Census TIGERweb..." -ForegroundColor Cyan
try {
    $CountyGeoJson=Invoke-RestMethod -Uri $CountyQuery -Method Get
}
catch {
    Write-Host "ERROR: Could not download Lancaster County boundary." -ForegroundColor Red
    Write-Host $_
    exit 1
}

if (-not $CountyGeoJson.features -or $CountyGeoJson.features.Count -lt 1) {
    Write-Host "ERROR: Census TIGERweb returned no Lancaster County feature." -ForegroundColor Red
    exit 1
}

$CountyGeometry=$CountyGeoJson.features[0].geometry
Write-Host "Boundary loaded successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Reading GPS and existing tags..." -ForegroundColor Cyan

$ExifArgs=@('-json','-n','-i','.dtrash','-GPSLatitude','-GPSLongitude','-FileName','-Directory','-FileTypeExtension')
foreach ($ext in ($PhotoExtensions+$VideoExtensions)) { $ExifArgs += @('-ext',$ext) }
$ExifArgs += @('-r',$Root)

$Items=(& $ExifTool.Source @ExifArgs) | ConvertFrom-Json
$Items=@($Items | Where-Object {
    $candidate=Join-Path $_.Directory $_.FileName
    $candidate -notmatch '(?i)(^|[\\/])\.dtrash([\\/]|$)'
})
$Rows=@()

foreach ($Item in $Items) {
    $kind=Get-FileKind -Extension ([string]$Item.FileTypeExtension)
    $fullPath=Join-Path $Item.Directory $Item.FileName
    $hasGps=($null -ne $Item.GPSLatitude -and $null -ne $Item.GPSLongitude)

    if (-not $hasGps) {
        $Rows += [PSCustomObject]@{
            FileName=$Item.FileName;FileType=$kind;FullPath=$fullPath;HasGPS='NO'
            Latitude='';Longitude='';InLancasterCounty='NO'
            HasSpecificLancasterTag='';AlreadyLancasterCounty=''
            Action='No GPS';ProposedTag=''
        }
        continue
    }

    $lat=[double]$Item.GPSLatitude
    $lon=[double]$Item.GPSLongitude

    $inside=Test-PointInGeoJsonGeometry -Latitude $lat -Longitude $lon -Geometry $CountyGeometry

    $hasSpecific=$false
    $alreadyCounty=$false

    if ($inside) {
        $hasSpecific=Test-HasSpecificLancasterTag -MediaPath $fullPath
        $alreadyCounty=Test-AlreadyHasLancasterCounty -MediaPath $fullPath
    }

    if (-not $inside) {
        $action='Outside Lancaster County'; $proposed=''
    }
    elseif ($hasSpecific) {
        $action='SKIP - specific Lancaster tag exists'; $proposed=''
    }
    elseif ($alreadyCounty) {
        $action='SKIP - already Lancaster County'; $proposed=''
    }
    else {
        $action='TAG Lancaster County'; $proposed=$DigiKamTag
    }

    $Rows += [PSCustomObject]@{
        FileName=$Item.FileName;FileType=$kind;FullPath=$fullPath;HasGPS='YES'
        Latitude=[Math]::Round($lat,7);Longitude=[Math]::Round($lon,7)
        InLancasterCounty=if($inside){'YES'}else{'NO'}
        HasSpecificLancasterTag=if($hasSpecific){'YES'}else{'NO'}
        AlreadyLancasterCounty=if($alreadyCounty){'YES'}else{'NO'}
        Action=$action;ProposedTag=$proposed
    }
}

$Rows | Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding UTF8

$total=$Rows.Count
$gpsCount=@($Rows | Where-Object {$_.HasGPS -eq 'YES'}).Count
$insideCounty=@($Rows | Where-Object {$_.InLancasterCounty -eq 'YES'})
$skippedSpecific=@($insideCounty | Where-Object {$_.HasSpecificLancasterTag -eq 'YES'})
$alreadyCounty=@($insideCounty | Where-Object {$_.AlreadyLancasterCounty -eq 'YES' -and $_.HasSpecificLancasterTag -ne 'YES'})
$matches=@($Rows | Where-Object {$_.Action -eq 'TAG Lancaster County'})
$photoMatches=@($matches | Where-Object {$_.FileType -eq 'Photo'}).Count
$videoMatches=@($matches | Where-Object {$_.FileType -eq 'Video'}).Count

Write-Host ""
Write-Host "REPORT SUMMARY" -ForegroundColor Cyan
Write-Host "Total supported files       : $total"
Write-Host "Files with GPS              : $gpsCount"
Write-Host "Inside Lancaster County     : $($insideCounty.Count)"
Write-Host "Skipped - specific address  : $($skippedSpecific.Count)"
Write-Host "Skipped - already county    : $($alreadyCounty.Count)"
Write-Host "Will tag Lancaster County   : $($matches.Count)"
Write-Host "  Photos                    : $photoMatches"
Write-Host "  Videos                    : $videoMatches"
Write-Host "Report                      : $ReportPath"

if ($Mode -eq 'REPORT') {
    Write-Host ""
    Write-Host "REPORT mode only. Nothing was modified." -ForegroundColor Yellow
    Write-Host "After reviewing the CSV, run with -Mode WRITE." -ForegroundColor Cyan
    exit 0
}

if ($matches.Count -eq 0) {
    Write-Host ""
    Write-Host "No files need Lancaster County tagging." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "WRITE mode will tag ONLY files with no specific Lancaster sub-place." -ForegroundColor Yellow
Write-Host "Photos: image + .xmp sidecar"
Write-Host "Videos: .xmp sidecar only; video untouched"
Write-Host "Existing tags are preserved."
Write-Host ""
$answer=Read-Host "Type YES to continue"

if ($answer -cne 'YES') {
    Write-Host "Cancelled. Nothing was changed." -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

$WriteLog=@()
$changed=0;$already=0;$errors=0

foreach ($row in $matches) {
    # Safety re-check immediately before writing.
    if (Test-HasSpecificLancasterTag -MediaPath $row.FullPath) {
        $WriteLog += [PSCustomObject]@{
            FileName=$row.FileName;FileType=$row.FileType
            Result='SKIPPED at write - specific Lancaster tag found'
            PhotoResult='';SidecarResult='';Backup=''
        }
        continue
    }

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
            & $ExifTool.Source -o $sidecar $row.FullPath | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sidecar)) {
                $errors++
                $WriteLog += [PSCustomObject]@{
                    FileName=$row.FileName;FileType='Video';Result='ERROR creating sidecar'
                    PhotoResult='';SidecarResult='';Backup=''
                }
                continue
            }
        }

        $sidecarResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false
        if ($sidecarResult -eq 'Tagged') {$changed++}
        elseif ($sidecarResult -eq 'Already tagged') {$already++}
        else {$errors++}

        $WriteLog += [PSCustomObject]@{
            FileName=$row.FileName;FileType='Video';Result=$sidecarResult
            PhotoResult='';SidecarResult=$sidecarResult;Backup=$backup
        }
    }
    elseif ($row.FileType -eq 'Photo') {
        $photo=$row.FullPath
        $sidecar="$photo.xmp"

        $relative=$photo.Substring($Root.Length).TrimStart('\')
        $photoBackup=Join-Path $BackupRoot ($relative -replace '[\\/:*?"<>|]','_')
        if (-not (Test-Path -LiteralPath $photoBackup)) {
            Copy-Item -LiteralPath $photo -Destination $photoBackup
        }

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
                    FileName=$row.FileName;FileType='Photo';Result='ERROR creating photo sidecar'
                    PhotoResult='';SidecarResult='';Backup=$photoBackup
                }
                continue
            }
        }

        $photoResult=Add-TagsToTarget -Target $photo -PreserveTimestamp:$true
        $sidecarResult=Add-TagsToTarget -Target $sidecar -PreserveTimestamp:$false

        if ($photoResult -eq 'ERROR' -or $sidecarResult -eq 'ERROR') {
            $errors++; $overall='ERROR'
        }
        elseif ($photoResult -eq 'Already tagged' -and $sidecarResult -eq 'Already tagged') {
            $already++; $overall='Already tagged'
        }
        else {
            $changed++; $overall='Tagged'
        }

        $WriteLog += [PSCustomObject]@{
            FileName=$row.FileName;FileType='Photo';Result=$overall
            PhotoResult=$photoResult;SidecarResult=$sidecarResult
            Backup="$photoBackup | $sidecarBackup"
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

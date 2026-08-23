param(
    [ValidateSet('REPORT','WRITE')]
    [string]$Mode = 'REPORT'
)

$Root = 'C:\Users\rbell\OneDrive\Pictures\2019'
$BackupRoot = 'C:\Users\rbell\OneDrive\Pictures\_Tag_Backups\2019_GPS_Tagging'
$ReportPath = Join-Path $Root 'GPS-Geofence-2019-Report.csv'
$WriteLogPath = Join-Path $Root 'GPS-Geofence-2019-WriteLog.csv'

$PhotoExtensions = @('jpg','jpeg','heic','png','tif','tiff')
$VideoExtensions = @('mp4','mov','m4v','avi')

$Zones = @(
    @{
        Name='900 Confederate Ave zone'
        LeafTag='900 Confederate Ave'
        DigiKamTag='Places/South Carolina/Lancaster/900 Confederate Ave'
        HierTag='Places|South Carolina|Lancaster|900 Confederate Ave'
        Polygon=@(
            @(-80.82542616455852,34.69375765889696),
            @(-80.82484058767655,34.69366359372555),
            @(-80.82499864827452,34.69310043816064),
            @(-80.82558121447842,34.69319202855739)
        )
    },
    @{
        Name='910 Confederate Ave zone -> tag as 900'
        LeafTag='900 Confederate Ave'
        DigiKamTag='Places/South Carolina/Lancaster/900 Confederate Ave'
        HierTag='Places|South Carolina|Lancaster|900 Confederate Ave'
        Polygon=@(
            @(-80.82489026386473,34.69366606912564),
            @(-80.82457564800784,34.69361037259382),
            @(-80.82473069792773,34.69305092979534),
            @(-80.82507240988713,34.69309796274259)
        )
    },
    @{
        Name='909 Confederate Ave zone'
        LeafTag='909 Confederate Ave'
        DigiKamTag='Places/South Carolina/Lancaster/909 Confederate Ave'
        HierTag='Places|South Carolina|Lancaster|909 Confederate Ave'
        Polygon=@(
            @(-80.82485714639385,34.69404604224939),
            @(-80.8245184451125,34.69399034597329),
            @(-80.82461027079323,34.69362274961097),
            @(-80.82494295071847,34.69368463463474)
        )
    }
)

function Test-PointInPolygon {
    param([double]$Latitude,[double]$Longitude,[array]$Polygon)
    $inside=$false
    $j=$Polygon.Count-1
    for($i=0;$i -lt $Polygon.Count;$i++){
        $xi=[double]$Polygon[$i][0]; $yi=[double]$Polygon[$i][1]
        $xj=[double]$Polygon[$j][0]; $yj=[double]$Polygon[$j][1]
        if((($yi -gt $Latitude) -ne ($yj -gt $Latitude))){
            $xIntersect=(($xj-$xi)*($Latitude-$yi)/($yj-$yi))+$xi
            if($Longitude -lt $xIntersect){$inside=-not $inside}
        }
        $j=$i
    }
    return $inside
}

function Get-FileKind([string]$Extension){
    $e=$Extension.ToLowerInvariant()
    if($PhotoExtensions -contains $e){return 'Photo'}
    if($VideoExtensions -contains $e){return 'Video'}
    return 'Other'
}

$ExifTool=Get-Command exiftool -ErrorAction SilentlyContinue
if(-not $ExifTool){Write-Host 'ERROR: ExifTool not found.' -ForegroundColor Red; exit 1}
if(-not (Test-Path -LiteralPath $Root)){Write-Host "ERROR: Folder not found: $Root" -ForegroundColor Red; exit 1}

Write-Host ""
Write-Host "Bell Family Archive - 2019 GPS Geofence Tagger" -ForegroundColor Cyan
Write-Host "Mode   : $Mode"
Write-Host "Folder : $Root"
Write-Host ""

$ExifArgs=@('-json','-n','-GPSLatitude','-GPSLongitude','-FileName','-Directory','-FileTypeExtension')
foreach($ext in ($PhotoExtensions+$VideoExtensions)){$ExifArgs+=@('-ext',$ext)}
$ExifArgs+=@('-r',$Root)

$Items=(& $ExifTool.Source @ExifArgs) | ConvertFrom-Json
$Rows=@()

foreach($Item in $Items){
    $ext=[string]$Item.FileTypeExtension
    $kind=Get-FileKind $ext
    $fullPath=Join-Path $Item.Directory $Item.FileName
    $hasGps=($null -ne $Item.GPSLatitude -and $null -ne $Item.GPSLongitude)

    if(-not $hasGps){
        $Rows += [PSCustomObject]@{FileName=$Item.FileName;FileType=$kind;FullPath=$fullPath;HasGPS='NO';Latitude='';Longitude='';Status='No GPS';Zone='';ProposedTag=''}
        continue
    }

    $lat=[double]$Item.GPSLatitude
    $lon=[double]$Item.GPSLongitude
    $matches=@()
    foreach($Zone in $Zones){
        if(Test-PointInPolygon $lat $lon $Zone.Polygon){$matches+=$Zone}
    }

    if($matches.Count -eq 0){
        $status='Outside known geofences'; $zoneName=''; $proposedTag=''
    } else {
        $uniqueTags=@($matches | ForEach-Object {$_.DigiKamTag} | Sort-Object -Unique)
        if($uniqueTags.Count -eq 1){
            $status=if($matches.Count -gt 1){'MATCH - overlapping same tag'}else{'MATCH'}
            $zoneName=($matches.Name -join ' | ')
            $proposedTag=$uniqueTags[0]
        } else {
            $status='OVERLAP - DIFFERENT TAGS - REVIEW'
            $zoneName=($matches.Name -join ' | ')
            $proposedTag=($uniqueTags -join ' | ')
        }
    }

    $Rows += [PSCustomObject]@{
        FileName=$Item.FileName;FileType=$kind;FullPath=$fullPath;HasGPS='YES'
        Latitude=[Math]::Round($lat,7);Longitude=[Math]::Round($lon,7)
        Status=$status;Zone=$zoneName;ProposedTag=$proposedTag
    }
}

$Rows | Export-Csv -LiteralPath $ReportPath -NoTypeInformation -Encoding UTF8
$matches=@($Rows | Where-Object {$_.Status -like 'MATCH*'})
$review=@($Rows | Where-Object {$_.Status -like 'OVERLAP - DIFFERENT*'}).Count
$gpsCount=@($Rows | Where-Object {$_.HasGPS -eq 'YES'}).Count

Write-Host "Total supported files : $($Rows.Count)"
Write-Host "Files with GPS        : $gpsCount"
Write-Host "Matched geofences     : $($matches.Count)"
Write-Host "Needs manual review   : $review"
Write-Host "Report                : $ReportPath"

if($Mode -eq 'REPORT'){
    Write-Host ""
    Write-Host "REPORT mode only. Nothing was modified." -ForegroundColor Yellow
    Write-Host "Run with -Mode WRITE after reviewing the CSV." -ForegroundColor Cyan
    exit 0
}

if($review -gt 0){
    Write-Host "WRITE STOPPED: conflicting overlaps need review." -ForegroundColor Red
    exit 1
}

if($matches.Count -eq 0){
    Write-Host "No matching files. Nothing to write." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "WRITE mode: photos get embedded XMP tags; videos get .xmp sidecars only." -ForegroundColor Yellow
$answer=Read-Host "Type YES to continue"
if($answer -cne 'YES'){Write-Host 'Cancelled. Nothing changed.' -ForegroundColor Yellow; exit 0}

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
$WriteLog=@()
$changed=0;$already=0;$errors=0

foreach($row in $matches){
    $tagObj=$Zones | Where-Object {$_.DigiKamTag -eq $row.ProposedTag} | Select-Object -First 1
    if(-not $tagObj){$errors++;continue}

    if($row.FileType -eq 'Video'){
        $target="$($row.FullPath).xmp"
        $backup=''
        if(Test-Path -LiteralPath $target){
            $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
            $backup=Join-Path $BackupRoot (($row.FileName+"_$stamp.xmp") -replace '[\\/:*?"<>|]','_')
            Copy-Item -LiteralPath $target -Destination $backup
        } else {
            & $ExifTool.Source -o $target $row.FullPath | Out-Null
            if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $target)){
                $errors++
                $WriteLog += [PSCustomObject]@{FileName=$row.FileName;FileType='Video';ProposedTag=$row.ProposedTag;Result='ERROR creating sidecar';Target=$target;Backup=''}
                continue
            }
        }
    } else {
        $target=$row.FullPath
        $relative=$target.Substring($Root.Length).TrimStart('\')
        $backup=Join-Path $BackupRoot ($relative -replace '[\\/:*?"<>|]','_')
        if(-not (Test-Path -LiteralPath $backup)){Copy-Item -LiteralPath $target -Destination $backup}
    }

    $meta=(& $ExifTool.Source -json -XMP-dc:Subject -XMP-lr:HierarchicalSubject -XMP-digiKam:TagsList $target) | ConvertFrom-Json
    $currentSubject=@($meta[0].Subject)
    $currentHier=@($meta[0].HierarchicalSubject)
    $currentDigiKam=@($meta[0].TagsList)

    $args=@('-overwrite_original')
    if($row.FileType -eq 'Photo'){$args=@('-P','-overwrite_original')}
    if($currentSubject -notcontains $tagObj.LeafTag){$args += "-XMP-dc:Subject+=$($tagObj.LeafTag)"}
    if($currentHier -notcontains $tagObj.HierTag){$args += "-XMP-lr:HierarchicalSubject+=$($tagObj.HierTag)"}
    if($currentDigiKam -notcontains $tagObj.DigiKamTag){$args += "-XMP-digiKam:TagsList+=$($tagObj.DigiKamTag)"}

    $baseCount=if($row.FileType -eq 'Photo'){2}else{1}
    if($args.Count -eq $baseCount){
        $already++; $result='Already tagged'
    } else {
        $args += $target
        & $ExifTool.Source @args | Out-Null
        if($LASTEXITCODE -eq 0){$changed++;$result=if($row.FileType -eq 'Video'){'Tagged sidecar'}else{'Tagged photo'}}
        else{$errors++;$result='ERROR writing metadata'}
    }

    $WriteLog += [PSCustomObject]@{FileName=$row.FileName;FileType=$row.FileType;ProposedTag=$row.ProposedTag;Result=$result;Target=$target;Backup=$backup}
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
Write-Host "In DigiKam, reread metadata only for the files you intentionally processed." -ForegroundColor Cyan

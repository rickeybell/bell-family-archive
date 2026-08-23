# Repair-2019-Photo-Sidecars.ps1
# Uses the existing 2019 GPS write log.
# For PHOTO rows only:
# - reads the place tag already embedded in the photo
# - creates/updates the matching .xmp sidecar
# - writes all three DigiKam-compatible tag fields
# - preserves existing sidecar metadata
# - backs up existing sidecars first
# - does NOT modify the photo itself
# - does NOT touch videos

$Root = 'C:\Users\rbell\OneDrive\Pictures\2019'
$WriteLogPath = Join-Path $Root 'GPS-Geofence-2019-WriteLog.csv'
$BackupRoot = 'C:\Users\rbell\OneDrive\Pictures\_Tag_Backups\2019_Photo_Sidecars'
$RepairLogPath = Join-Path $Root 'GPS-Geofence-2019-PhotoSidecarRepairLog.csv'

Write-Host ""
Write-Host "Bell Family Archive - 2019 Photo Sidecar Repair" -ForegroundColor Cyan
Write-Host "Photos only. Original image files will NOT be modified." -ForegroundColor Yellow
Write-Host ""

$ExifTool = Get-Command exiftool -ErrorAction SilentlyContinue
if (-not $ExifTool) {
    Write-Host "ERROR: ExifTool not found." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $WriteLogPath)) {
    Write-Host "ERROR: Write log not found:" -ForegroundColor Red
    Write-Host $WriteLogPath
    exit 1
}

$Rows = Import-Csv -LiteralPath $WriteLogPath
$Photos = @($Rows | Where-Object { $_.FileType -eq 'Photo' })

Write-Host "Photo rows in write log: $($Photos.Count)"

if ($Photos.Count -eq 0) {
    Write-Host "No photo rows found. Nothing to do." -ForegroundColor Green
    exit 0
}

Write-Host ""
$answer = Read-Host "Type YES to create/update sidecars for these photos"
if ($answer -cne 'YES') {
    Write-Host "Cancelled. Nothing was changed." -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

$RepairLog = @()
$changed = 0
$already = 0
$errors = 0

foreach ($Row in $Photos) {
    $Photo = $Row.Target
    if ([string]::IsNullOrWhiteSpace($Photo)) {
        $Photo = $Row.FullPath
    }

    if (-not (Test-Path -LiteralPath $Photo)) {
        $errors++
        $RepairLog += [PSCustomObject]@{
            FileName = $Row.FileName
            Photo = $Photo
            Sidecar = ''
            Result = 'ERROR - photo not found'
            Backup = ''
        }
        continue
    }

    $Sidecar = "$Photo.xmp"

    # Read the three tag fields from the PHOTO itself.
    $PhotoMeta = (& $ExifTool.Source -json `
        -XMP-digiKam:TagsList `
        -XMP-lr:HierarchicalSubject `
        -XMP-dc:Subject `
        $Photo) | ConvertFrom-Json

    $PhotoDigiKam = @($PhotoMeta[0].TagsList)
    $PhotoHier = @($PhotoMeta[0].HierarchicalSubject)
    $PhotoSubject = @($PhotoMeta[0].Subject)

    if ($PhotoDigiKam.Count -eq 0 -and $PhotoHier.Count -eq 0 -and $PhotoSubject.Count -eq 0) {
        $errors++
        $RepairLog += [PSCustomObject]@{
            FileName = $Row.FileName
            Photo = $Photo
            Sidecar = $Sidecar
            Result = 'ERROR - no XMP tags found in photo'
            Backup = ''
        }
        continue
    }

    $Backup = ''

    if (Test-Path -LiteralPath $Sidecar) {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $safeName = (($Row.FileName + "_$stamp.xmp") -replace '[\\/:*?"<>|]', '_')
        $Backup = Join-Path $BackupRoot $safeName
        Copy-Item -LiteralPath $Sidecar -Destination $Backup
    }
    else {
        # Create a sidecar from the image metadata first.
        & $ExifTool.Source -o $Sidecar $Photo | Out-Null

        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Sidecar)) {
            $errors++
            $RepairLog += [PSCustomObject]@{
                FileName = $Row.FileName
                Photo = $Photo
                Sidecar = $Sidecar
                Result = 'ERROR - could not create sidecar'
                Backup = ''
            }
            continue
        }
    }

    # Read current sidecar tags.
    $SideMeta = (& $ExifTool.Source -json `
        -XMP-digiKam:TagsList `
        -XMP-lr:HierarchicalSubject `
        -XMP-dc:Subject `
        $Sidecar) | ConvertFrom-Json

    $SideDigiKam = @($SideMeta[0].TagsList)
    $SideHier = @($SideMeta[0].HierarchicalSubject)
    $SideSubject = @($SideMeta[0].Subject)

    $args = @('-overwrite_original')

    foreach ($tag in $PhotoDigiKam) {
        if ($SideDigiKam -notcontains $tag) {
            $args += "-XMP-digiKam:TagsList+=$tag"
        }
    }

    foreach ($tag in $PhotoHier) {
        if ($SideHier -notcontains $tag) {
            $args += "-XMP-lr:HierarchicalSubject+=$tag"
        }
    }

    foreach ($tag in $PhotoSubject) {
        if ($SideSubject -notcontains $tag) {
            $args += "-XMP-dc:Subject+=$tag"
        }
    }

    if ($args.Count -eq 1) {
        $already++
        $result = 'Already synchronized'
    }
    else {
        $args += $Sidecar
        & $ExifTool.Source @args | Out-Null

        if ($LASTEXITCODE -eq 0) {
            $changed++
            $result = 'Sidecar synchronized'
        }
        else {
            $errors++
            $result = 'ERROR writing sidecar'
        }
    }

    $RepairLog += [PSCustomObject]@{
        FileName = $Row.FileName
        Photo = $Photo
        Sidecar = $Sidecar
        Result = $result
        Backup = $Backup
    }
}

$RepairLog | Export-Csv -LiteralPath $RepairLogPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "REPAIR COMPLETE" -ForegroundColor Green
Write-Host "Sidecars changed : $changed"
Write-Host "Already correct  : $already"
Write-Host "Errors           : $errors"
Write-Host "Repair log       : $RepairLogPath"
Write-Host "Backups          : $BackupRoot"
Write-Host ""
Write-Host "Next: in DigiKam, select the affected PHOTOS and use Reread Metadata From File." -ForegroundColor Cyan

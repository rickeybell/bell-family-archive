param(
    [switch]$DryRun,
    [switch]$ForceFullScan
)

$ScriptVersion = "3.4.1"
$RepoRoot   = "C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive"
$SourceRoot = "C:\Users\rbell\OneDrive\Pictures"
$DestRoot   = Join-Path $RepoRoot "images"
$PublishTag = "Website"
$ManifestPath = Join-Path $RepoRoot ".website-photo-manifest.json"
$WebsiteManifestCsv = Join-Path $RepoRoot "website-photo-manifest.csv"
$OrphanReportCsv = Join-Path $RepoRoot "website-photo-orphans.csv"

$ImageExtensions = @(".jpg", ".jpeg", ".png", ".tif", ".tiff")
$ProgressEvery = 250
$BatchSize = 50

function Get-ExifToolPath {
    $cmd = Get-Command exiftool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($candidate in @("C:\ExifTool\exiftool.exe", "C:\Program Files\ExifTool\exiftool.exe", "C:\Program Files (x86)\ExifTool\exiftool.exe", "$env:USERPROFILE\exiftool.exe")) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "ExifTool was not found. Put exiftool.exe in C:\ExifTool or add it to PATH."
}

function Get-ImageFilesSkippingDTrash {
    param([string]$Root)
    Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue | Where-Object { $ImageExtensions -contains $_.Extension.ToLowerInvariant() }
    foreach ($dir in (Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
        if ($dir.Name -ieq ".dtrash") { $script:stats.ExcludedDTrashFolders++; Write-Host "SKIP FOLDER  $($dir.FullName)"; continue }
        Get-ImageFilesSkippingDTrash -Root $dir.FullName
    }
}

function Get-YearFromMetadataRecord {
    param($Record)
    if (!$Record) { return $null }
    foreach ($property in @("DateTimeOriginal", "CreateDate")) {
        if ($Record.PSObject.Properties.Name -notcontains $property) { continue }
        $value = [string]$Record.$property
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($value -match '^((18|19|20)\d{2})[:\-]') { return [int]$Matches[1] }
    }
    return $null
}

function Get-DestinationRelativePath {
    param([System.IO.FileInfo]$File, $Record = $null)
    $relative = $File.FullName.Substring($SourceRoot.Length).TrimStart('\')
    $parts = $relative -split '\\'
    foreach ($part in $parts) {
        if ($part -match '^(18|19|20)\d{2}$') { return Join-Path $part $File.Name }
    }

    # Masters outside normal YYYY folders (for example Dad\... or Death Docs\...)
    # are published under the year from DigiKam/embedded date metadata. The master
    # file itself is never moved or renamed.
    $metadataYear = Get-YearFromMetadataRecord -Record $Record
    if ($null -ne $metadataYear) { return Join-Path ([string]$metadataYear) $File.Name }

    # If there is no usable date, preserve the old relative path. The derivative
    # generator will continue to skip paths that do not contain a four-digit year.
    return $relative
}

function Test-WebsiteTagFromRecord {
    param($Record)
    $values = @()
    foreach ($property in @("Subject", "Keywords", "HierarchicalSubject")) {
        if ($Record.PSObject.Properties.Name -contains $property) {
            $v = $Record.$property
            if ($null -ne $v) { if ($v -is [System.Array]) { $values += $v } else { $values += [string]$v } }
        }
    }
    foreach ($value in $values) {
        if ([string]$value -ieq $PublishTag) { return $true }
        foreach ($token in ([string]$value -split '[,;]')) {
            $token = $token.Trim()
            if ($token -ieq $PublishTag) { return $true }
            $segments = $token -split '[|/]'
            if ($segments.Count -gt 0 -and $segments[-1].Trim() -ieq $PublishTag) { return $true }
        }
    }
    return $false
}

function Get-NormalizedPathKey {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { $full = $Path }
    return ($full -replace '/', '\').TrimEnd('\').ToLowerInvariant()
}

function Join-MetadataValues {
    param($Record, [string[]]$Names)
    $all = @()
    foreach ($name in $Names) {
        if ($Record.PSObject.Properties.Name -contains $name) {
            $v = $Record.$name
            if ($null -ne $v) { if ($v -is [System.Array]) { $all += $v } else { $all += [string]$v } }
        }
    }
    return (($all | ForEach-Object { [string]$_ } | Where-Object { ![string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join "; ")
}

function Add-PublishedFromManifest {
    param([string]$SourcePath, $Old)
    if (!$Old -or ![bool]$Old.Published) { return }
    $destRelative = [string]$Old.Destination
    if ([string]::IsNullOrWhiteSpace($destRelative)) {
        $f = Get-Item -LiteralPath $SourcePath -ErrorAction SilentlyContinue
        if ($f) { $destRelative = Get-DestinationRelativePath -File $f }
    }
    if (![string]::IsNullOrWhiteSpace($destRelative)) {
        [void]$script:PublishedDestinations.Add((Get-NormalizedPathKey -Path (Join-Path $DestRoot $destRelative)))
    }
}

function Process-Batch {
    param([System.Collections.Generic.List[System.IO.FileInfo]]$Files, [string]$ExifTool)
    if ($Files.Count -eq 0) { return }
    $args = @("-json", "-Subject", "-Keywords", "-HierarchicalSubject", "-PersonInImage", "-RegionPersonDisplayName", "-Caption-Abstract", "-Description", "-ImageDescription", "-Title", "-DateTimeOriginal", "-CreateDate", "-GPSLatitude", "-GPSLongitude")
    foreach ($file in $Files) { $args += $file.FullName }
    $json = & $ExifTool @args 2>$null
    if ($LASTEXITCODE -ne 0 -and !$json) { $script:stats.Errors += $Files.Count; Write-Warning "ExifTool batch failed for $($Files.Count) files."; return }
    try { $records = ($json -join [Environment]::NewLine) | ConvertFrom-Json } catch { $script:stats.Errors += $Files.Count; Write-Warning "Could not parse ExifTool output for a batch."; return }
    if ($records -isnot [System.Array]) { $records = @($records) }
    $bySource = @{}
    foreach ($record in $records) { $key = Get-NormalizedPathKey ([string]$record.SourceFile); if ($key) { $bySource[$key] = $record } }

    foreach ($file in $Files) {
        $script:stats.MetadataRead++
        $record = $bySource[(Get-NormalizedPathKey $file.FullName)]
        if (!$record) {
            $matches = @($records | Where-Object { [System.IO.Path]::GetFileName([string]$_.SourceFile) -ieq $file.Name })
            if ($matches.Count -eq 1) { $record = $matches[0] }
        }
        if (!$record) { $script:stats.Errors++; Write-Warning "No metadata record matched: $($file.FullName)"; continue }

        $published = Test-WebsiteTagFromRecord $record
        $destRelative = Get-DestinationRelativePath -File $file -Record $record
        $destPath = Join-Path $DestRoot $destRelative
        if ($published) {
            [void]$script:PublishedDestinations.Add((Get-NormalizedPathKey $destPath))
            $tags = Join-MetadataValues $record @("Subject","Keywords","HierarchicalSubject")
            if ($tags) {
                $clean = @()
                foreach ($t in ($tags -split ';')) { $t=$t.Trim(); if(!$t){continue}; $leaf=($t -split '[|/]')[-1].Trim(); if($t -ieq $PublishTag -or $leaf -ieq $PublishTag){continue}; $clean += $t }
                $tags = (($clean | Select-Object -Unique) -join "; ")
            }
            $script:PublishedRows.Add([pscustomobject]@{SourcePath=$file.FullName;RelativePath=$destRelative;DestinationPath=$destPath;FileName=$file.Name;Date=(Join-MetadataValues $record @("DateTimeOriginal","CreateDate"));People=(Join-MetadataValues $record @("PersonInImage","RegionPersonDisplayName"));Title=(Join-MetadataValues $record @("Title"));Description=(Join-MetadataValues $record @("Caption-Abstract","Description","ImageDescription"));Tags=$tags;GPSLatitude=(Join-MetadataValues $record @("GPSLatitude"));GPSLongitude=(Join-MetadataValues $record @("GPSLongitude"));Length=$file.Length;LastWriteUtc=$file.LastWriteTimeUtc.ToString("o")})
            $destExists = Test-Path -LiteralPath $destPath
            $shouldCopy = !$destExists
            if ($destExists) { $destFile=Get-Item -LiteralPath $destPath; $shouldCopy=($destFile.Length -ne $file.Length) -or ($destFile.LastWriteTimeUtc -lt $file.LastWriteTimeUtc) }
            if ($shouldCopy) {
                $verb=if($destExists){"UPDATE"}else{"NEW   "}; Write-Host "$verb  $destRelative"
                if (!$DryRun) { $destFolder=Split-Path -Parent $destPath; if(!(Test-Path -LiteralPath $destFolder)){New-Item -ItemType Directory -Path $destFolder -Force|Out-Null}; Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force; (Get-Item -LiteralPath $destPath).LastWriteTimeUtc=$file.LastWriteTimeUtc }
                if($destExists){$script:stats.PublishedUpdated++}else{$script:stats.PublishedNew++}
            } else { $script:stats.PublishedAlreadyCurrent++ }
        } else { $script:stats.Unpublished++ }
        $script:NewManifest[$file.FullName]=@{LastWriteUtc=$file.LastWriteTimeUtc.ToString("o");Length=$file.Length;Published=$published;Destination=$destRelative}
    }
}

function Get-SiteReferences {
    param([string]$RelativePath, [string]$FileName)
    $refs = New-Object System.Collections.Generic.List[string]
    $needles = @(
        (($RelativePath -replace '\\','/')),
        ("images/" + ($RelativePath -replace '\\','/')),
        $FileName
    ) | Select-Object -Unique
    $textFiles = Get-ChildItem -LiteralPath $RepoRoot -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notlike "$DestRoot*" -and $_.Extension.ToLowerInvariant() -in @('.html','.htm','.css','.js','.json','.md')
    }
    foreach ($tf in $textFiles) {
        try {
            $content = Get-Content -LiteralPath $tf.FullName -Raw -ErrorAction Stop
            foreach ($needle in $needles) {
                if ($needle -and $content.IndexOf($needle,[System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $refs.Add($tf.FullName.Substring($RepoRoot.Length).TrimStart('\')); break
                }
            }
        } catch {}
    }
    return @($refs | Select-Object -Unique)
}

$ExifTool=Get-ExifToolPath
if(!(Test-Path -LiteralPath $SourceRoot)){throw "Source folder does not exist: $SourceRoot"}
if(!(Test-Path -LiteralPath $DestRoot)-and !$DryRun){New-Item -ItemType Directory -Path $DestRoot -Force|Out-Null}
$Manifest=@{}
if((Test-Path -LiteralPath $ManifestPath)-and !$ForceFullScan){try{$saved=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json;foreach($item in $saved.files){$Manifest[[string]$item.source]=@{LastWriteUtc=[string]$item.lastWriteUtc;Length=[int64]$item.length;Published=[bool]$item.published;Destination=[string]$item.destination}}}catch{Write-Warning "Manifest unreadable; performing a full scan.";$Manifest=@{}}}
$NewManifest=@{}
$PublishedRows=New-Object "System.Collections.Generic.List[object]"
$PublishedDestinations=New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
$stats=[ordered]@{Scanned=0;ExcludedDTrashFolders=0;MetadataRead=0;UnchangedSkipped=0;PublishedNew=0;PublishedUpdated=0;PublishedAlreadyCurrent=0;Unpublished=0;Orphans=0;OrphansReferenced=0;OrphansUnreferenced=0;Errors=0}
Write-Host "`nBell Family Archive Website Photo Sync v$ScriptVersion";Write-Host "Source:      $SourceRoot";Write-Host "Destination: $DestRoot";Write-Host "Publish tag: $PublishTag";Write-Host "Non-year masters: metadata year fallback";if($DryRun){Write-Host "*** DRY RUN - NO FILES WILL BE COPIED OR DELETED ***"};Write-Host ""
$batch=New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
Get-ImageFilesSkippingDTrash -Root $SourceRoot | ForEach-Object {
    $file=$_;$stats.Scanned++
    if(($stats.Scanned%$ProgressEvery)-eq 0){Write-Host ("Scanned {0:N0} | Metadata {1:N0} | Cached {2:N0} | New {3:N0} | Updated {4:N0}" -f $stats.Scanned,$stats.MetadataRead,$stats.UnchangedSkipped,$stats.PublishedNew,$stats.PublishedUpdated)}
    $sourceKey=$file.FullName;$lastWriteUtc=$file.LastWriteTimeUtc.ToString("o");$old=$Manifest[$sourceKey]
    $needsMetadata=$ForceFullScan -or !$old -or $old.LastWriteUtc -ne $lastWriteUtc -or [int64]$old.Length -ne $file.Length
    if(!$needsMetadata){
        $NewManifest[$sourceKey]=@{LastWriteUtc=$lastWriteUtc;Length=$file.Length;Published=[bool]$old.Published;Destination=[string]$old.Destination}
        Add-PublishedFromManifest -SourcePath $sourceKey -Old $old
        if([bool]$old.Published){$stats.PublishedAlreadyCurrent++}else{$stats.Unpublished++}
        $stats.UnchangedSkipped++;return
    }
    $batch.Add($file);if($batch.Count-ge$BatchSize){Process-Batch $batch $ExifTool;$batch.Clear()}
}
Process-Batch $batch $ExifTool;$batch.Clear()

$OrphanRows=New-Object "System.Collections.Generic.List[object]"
if(Test-Path -LiteralPath $DestRoot){
    Get-ChildItem -LiteralPath $DestRoot -Recurse -File -ErrorAction SilentlyContinue|Where-Object{$ImageExtensions -contains $_.Extension.ToLowerInvariant()}|ForEach-Object{
        $destFile=$_;$key=Get-NormalizedPathKey $destFile.FullName
        if(!$PublishedDestinations.Contains($key)){
            $stats.Orphans++;$relative=$destFile.FullName.Substring($DestRoot.Length).TrimStart('\')
            $refs=@(Get-SiteReferences -RelativePath $relative -FileName $destFile.Name)
            $referenced=$refs.Count -gt 0
            if($referenced){$stats.OrphansReferenced++;$action="KEEP - referenced by website"}else{$stats.OrphansUnreferenced++;$action="REVIEW - not referenced by website"}
            $OrphanRows.Add([pscustomobject]@{RelativePath=$relative;DestinationPath=$destFile.FullName;FileName=$destFile.Name;Length=$destFile.Length;LastWriteUtc=$destFile.LastWriteTimeUtc.ToString("o");ReferencedBySite=$referenced;ReferencedIn=($refs -join '; ');Action=$action})
            Write-Host ("ORPHAN  {0}  [{1}]" -f $relative,$action)
        }
    }
}
$PublishedRows|Sort-Object RelativePath|Export-Csv -LiteralPath $WebsiteManifestCsv -NoTypeInformation -Encoding UTF8
$OrphanRows|Sort-Object RelativePath|Export-Csv -LiteralPath $OrphanReportCsv -NoTypeInformation -Encoding UTF8
if(!$DryRun){
    $items=foreach($sourceKey in($NewManifest.Keys|Sort-Object)){$m=$NewManifest[$sourceKey];[pscustomobject]@{source=$sourceKey;lastWriteUtc=$m.LastWriteUtc;length=$m.Length;published=$m.Published;destination=$m.Destination}}
    [pscustomobject]@{version=4;sourceRoot=$SourceRoot;destRoot=$DestRoot;publishTag=$PublishTag;updatedUtc=[DateTime]::UtcNow.ToString('o');files=@($items)}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ManifestPath -Encoding UTF8
}
Write-Host "`n============== RESULTS =============="
Write-Host ("Images scanned:             {0:N0}" -f $stats.Scanned)
Write-Host ("Skipped .dtrash folders:    {0:N0}" -f $stats.ExcludedDTrashFolders)
Write-Host ("Metadata records read:      {0:N0}" -f $stats.MetadataRead)
Write-Host ("Unchanged/cache skipped:    {0:N0}" -f $stats.UnchangedSkipped)
Write-Host ("New Website-tagged files:   {0:N0}" -f $stats.PublishedNew)
Write-Host ("Updated website files:      {0:N0}" -f $stats.PublishedUpdated)
Write-Host ("Already current:            {0:N0}" -f $stats.PublishedAlreadyCurrent)
Write-Host ("Not Website-tagged:         {0:N0}" -f $stats.Unpublished)
Write-Host ("ORPHANS total:               {0:N0}" -f $stats.Orphans)
Write-Host ("  Referenced by site:        {0:N0}" -f $stats.OrphansReferenced)
Write-Host ("  Unreferenced/review:       {0:N0}" -f $stats.OrphansUnreferenced)
Write-Host ("Errors:                      {0:N0}" -f $stats.Errors)
Write-Host "====================================="
Write-Host "`nWebsite manifest report: $WebsiteManifestCsv"
Write-Host "Orphan review report:    $OrphanReportCsv"
if($DryRun){Write-Host "`nDry run complete. No photographs were copied or deleted."}else{Write-Host "`nWebsite image sync complete. No orphan photographs were deleted."}

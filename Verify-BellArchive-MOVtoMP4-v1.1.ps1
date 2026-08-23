[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [string]$LogFolderName = "_VideoConversionLogs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function In-DTrash([string]$Path) {
    return @((($Path -split '[\\/]') | Where-Object { $_ -ieq '.dtrash' })).Count -gt 0
}

function Exif([string]$Path) {
    $j = & exiftool -json -G1 -a -s -- "$Path" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $j) { throw "ExifTool could not read $Path" }
    $o = ($j | Out-String | ConvertFrom-Json)
    if ($o -is [array]) { return $o[0] }
    return $o
}

function Values($Obj,[string[]]$Names) {
    $a = @()
    foreach ($p in $Obj.PSObject.Properties) {
        $n = if ($p.Name -match '^[^:]+:(.+)$') { $Matches[1] } else { $p.Name }
        if ($Names -contains $n -and $null -ne $p.Value) {
            if ($p.Value -is [System.Collections.IEnumerable] -and -not ($p.Value -is [string])) {
                foreach ($v in $p.Value) { if ("$v".Trim()) { $a += "$v".Trim() } }
            } elseif ("$($p.Value)".Trim()) {
                $a += "$($p.Value)".Trim()
            }
        }
    }
    return @($a | Sort-Object -Unique)
}

function Cmp($A,$B) {
    $A = @($A | Sort-Object -Unique)
    $B = @($B | Sort-Object -Unique)
    if ($A.Count -eq 0) {
        return [pscustomobject]@{ Status="N/A"; A=""; B=($B -join " | ") }
    }
    $d = Compare-Object $A $B
    return [pscustomobject]@{
        Status = if ($null -eq $d) { "OK" } else { "DIFF" }
        A = ($A -join " | ")
        B = ($B -join " | ")
    }
}

function Sidecar($Mov,$Mp4) {
    $dir = $Mov.DirectoryName
    $base = $Mov.BaseName
    $shared = Join-Path $dir "$base.xmp"
    $movSpecific = @("$($Mov.FullName).xmp", (Join-Path $dir "$($Mov.Name).xmp")) | Sort-Object -Unique
    $mp4Specific = @("$($Mp4.FullName).xmp", (Join-Path $dir "$($Mp4.Name).xmp")) | Sort-Object -Unique

    if (Test-Path -LiteralPath $shared) {
        return [pscustomobject]@{Status="SHARED"; MOV=(Split-Path $shared -Leaf); MP4=(Split-Path $shared -Leaf)}
    }

    $m = @($movSpecific | Where-Object { Test-Path -LiteralPath $_ })
    $p = @($mp4Specific | Where-Object { Test-Path -LiteralPath $_ })

    if ($m.Count -eq 0) { return [pscustomobject]@{Status="N/A";MOV="";MP4=(($p|%{Split-Path $_ -Leaf}) -join " | ")} }
    if ($p.Count -gt 0) { return [pscustomobject]@{Status="OK";MOV=(($m|%{Split-Path $_ -Leaf}) -join " | ");MP4=(($p|%{Split-Path $_ -Leaf}) -join " | ")} }
    return [pscustomobject]@{Status="MISSING";MOV=(($m|%{Split-Path $_ -Leaf}) -join " | ");MP4=""}
}

if (-not (Get-Command exiftool -ErrorAction SilentlyContinue)) {
    throw "ExifTool is not available in PATH."
}

$Root = (Resolve-Path -LiteralPath $Root).Path
$logDir = Join-Path $Root $LogFolderName
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$csv = Join-Path $logDir ("MOVtoMP4_VERIFY_{0}.csv" -f (Get-Date -Format yyyyMMdd_HHmmss))

$movs = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.mov -ErrorAction SilentlyContinue |
          Where-Object { -not (In-DTrash $_.FullName) })

$tagNames     = @("Subject","Keywords","HierarchicalSubject","TagsList","Category","SupplementalCategories")
$peopleNames  = @("PersonInImage","RegionName","RegionPersonDisplayName")
$captionNames = @("Description","Caption-Abstract","Title","Headline","Comment","UserComment")
$ratingNames  = @("Rating","RatingPercent")
$gpsNames     = @("GPSLatitude","GPSLongitude","GPSAltitude","GPSPosition")
$dateNames    = @("DateTimeOriginal","CreateDate","MediaCreateDate","ContentCreateDate","CreationDate")

$rows = @()
$i = 0

Write-Host ""
Write-Host "======================================================================"
Write-Host "Bell Family Archive - MOV to MP4 Metadata Verifier v1.1"
Write-Host "======================================================================"
Write-Host "Root       : $Root"
Write-Host "Mode       : READ-ONLY VERIFY"
Write-Host "Excluded   : all .dtrash folders"
Write-Host "CSV log    : $csv"
Write-Host ""

foreach ($mov in $movs) {
    $i++
    Write-Progress -Activity "Verifying MOV/MP4 metadata" -Status "$i of $($movs.Count): $($mov.Name)" -PercentComplete ([int](100*$i/[math]::Max(1,$movs.Count)))

    $mp4Path = Join-Path $mov.DirectoryName "$($mov.BaseName).mp4"

    if (-not (Test-Path -LiteralPath $mp4Path)) {
        $rows += [pscustomobject]@{
            Folder=$mov.DirectoryName; MOV=$mov.Name; MP4=""; MOV_MB=[math]::Round($mov.Length/1MB,2); MP4_MB=0
            Saved_MB=0; Reduction_Pct=0; PairStatus="MISSING_MP4"; Tags="NOT_CHECKED"; People="NOT_CHECKED"
            Captions="NOT_CHECKED"; Ratings="NOT_CHECKED"; GPS="NOT_CHECKED"; Dates="NOT_CHECKED"; Sidecar="NOT_CHECKED"
            CriticalMismatch="YES"; MOV_Tags=""; MP4_Tags=""; MOV_People=""; MP4_People=""; MOV_Captions=""; MP4_Captions=""
            MOV_Ratings=""; MP4_Ratings=""; MOV_GPS=""; MP4_GPS=""; MOV_Dates=""; MP4_Dates=""; MOV_Sidecar=""; MP4_Sidecar=""
            Notes="Matching MP4 missing"
        }
        continue
    }

    $mp4 = Get-Item -LiteralPath $mp4Path
    try {
        $a = Exif $mov.FullName
        $b = Exif $mp4.FullName

        $tags = Cmp (Values $a $tagNames) (Values $b $tagNames)
        $people = Cmp (Values $a $peopleNames) (Values $b $peopleNames)
        $captions = Cmp (Values $a $captionNames) (Values $b $captionNames)
        $ratings = Cmp (Values $a $ratingNames) (Values $b $ratingNames)
        $gps = Cmp (Values $a $gpsNames) (Values $b $gpsNames)
        $dates = Cmp (Values $a $dateNames) (Values $b $dateNames)
        $side = Sidecar $mov $mp4

        $critical = @($tags.Status,$people.Status,$captions.Status,$ratings.Status,$gps.Status,$side.Status) |
                    Where-Object { $_ -in @("DIFF","MISSING") }

        $saved = $mov.Length - $mp4.Length
        $pct = if ($mov.Length) { 100*$saved/$mov.Length } else { 0 }

        $rows += [pscustomobject]@{
            Folder=$mov.DirectoryName; MOV=$mov.Name; MP4=$mp4.Name
            MOV_MB=[math]::Round($mov.Length/1MB,2); MP4_MB=[math]::Round($mp4.Length/1MB,2)
            Saved_MB=[math]::Round($saved/1MB,2); Reduction_Pct=[math]::Round($pct,2); PairStatus="OK"
            Tags=$tags.Status; People=$people.Status; Captions=$captions.Status; Ratings=$ratings.Status
            GPS=$gps.Status; Dates=$dates.Status; Sidecar=$side.Status
            CriticalMismatch=if ($critical.Count) {"YES"} else {"NO"}
            MOV_Tags=$tags.A; MP4_Tags=$tags.B; MOV_People=$people.A; MP4_People=$people.B
            MOV_Captions=$captions.A; MP4_Captions=$captions.B; MOV_Ratings=$ratings.A; MP4_Ratings=$ratings.B
            MOV_GPS=$gps.A; MP4_GPS=$gps.B; MOV_Dates=$dates.A; MP4_Dates=$dates.B
            MOV_Sidecar=$side.MOV; MP4_Sidecar=$side.MP4
            Notes=if ($dates.Status -eq "DIFF") {"Date fields differ; review before removing MOV"} else {""}
        }
    } catch {
        $rows += [pscustomobject]@{
            Folder=$mov.DirectoryName; MOV=$mov.Name; MP4=$mp4.Name; MOV_MB=[math]::Round($mov.Length/1MB,2)
            MP4_MB=[math]::Round($mp4.Length/1MB,2); Saved_MB=[math]::Round(($mov.Length-$mp4.Length)/1MB,2)
            Reduction_Pct=[math]::Round((100*($mov.Length-$mp4.Length)/[math]::Max(1,$mov.Length)),2); PairStatus="ERROR"
            Tags="ERROR"; People="ERROR"; Captions="ERROR"; Ratings="ERROR"; GPS="ERROR"; Dates="ERROR"; Sidecar="ERROR"
            CriticalMismatch="YES"; MOV_Tags=""; MP4_Tags=""; MOV_People=""; MP4_People=""; MOV_Captions=""; MP4_Captions=""
            MOV_Ratings=""; MP4_Ratings=""; MOV_GPS=""; MP4_GPS=""; MOV_Dates=""; MP4_Dates=""; MOV_Sidecar=""; MP4_Sidecar=""
            Notes=$_.Exception.Message
        }
    }
}

Write-Progress -Activity "Verifying MOV/MP4 metadata" -Completed
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8

function CountWhere($Script) { return @($rows | Where-Object $Script).Count }

Write-Host ""
Write-Host "======================================================================"
Write-Host "SUMMARY"
Write-Host "======================================================================"
Write-Host ("MOV files found                 : {0}" -f $movs.Count)
Write-Host ("Valid MOV/MP4 pairs             : {0}" -f (CountWhere {$_.PairStatus -eq "OK"}))
Write-Host ("Missing MP4                     : {0}" -f (CountWhere {$_.PairStatus -eq "MISSING_MP4"}))
Write-Host ("Read errors                     : {0}" -f (CountWhere {$_.PairStatus -eq "ERROR"}))
Write-Host ""
Write-Host ("Clean critical metadata matches : {0}" -f (CountWhere {$_.PairStatus -eq "OK" -and $_.CriticalMismatch -eq "NO"}))
Write-Host ("Critical mismatches             : {0}" -f (CountWhere {$_.CriticalMismatch -eq "YES"}))
Write-Host ("Tag/keyword differences         : {0}" -f (CountWhere {$_.Tags -eq "DIFF"}))
Write-Host ("People differences              : {0}" -f (CountWhere {$_.People -eq "DIFF"}))
Write-Host ("Caption differences             : {0}" -f (CountWhere {$_.Captions -eq "DIFF"}))
Write-Host ("Rating differences              : {0}" -f (CountWhere {$_.Ratings -eq "DIFF"}))
Write-Host ("GPS differences                 : {0}" -f (CountWhere {$_.GPS -eq "DIFF"}))
Write-Host ("Date-field differences          : {0}" -f (CountWhere {$_.Dates -eq "DIFF"}))
Write-Host ("Missing sidecars                : {0}" -f (CountWhere {$_.Sidecar -eq "MISSING"}))
Write-Host ""
Write-Host "CSV audit log                   : $csv"
Write-Host "READ-ONLY verification complete. No files were changed or deleted."
Write-Host ""

if ((CountWhere {$_.CriticalMismatch -eq "YES"}) -gt 0) {
    Write-Host "Do NOT remove or archive MOV originals yet."
    Write-Host "Review CriticalMismatch=YES rows in the CSV."
} else {
    Write-Host "Critical metadata checks passed."
    Write-Host "Next step: reread MP4 metadata in DigiKam and spot-check."
}

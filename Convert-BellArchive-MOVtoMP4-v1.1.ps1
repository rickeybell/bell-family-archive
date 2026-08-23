[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Root,

    [ValidateSet('REPORT','WRITE')]
    [string]$Mode = 'REPORT',

    [string]$Ffmpeg = 'ffmpeg',
    [string]$Ffprobe = 'ffprobe',
    [string]$ExifTool = 'exiftool',

    [ValidateRange(0,51)]
    [int]$Crf = 21,

    [ValidateSet('veryfast','faster','fast','medium','slow','slower')]
    [string]$Preset = 'medium',

    [switch]$IncludeHidden,
    [switch]$CopySidecars = $true,
    [switch]$CopyMetadata = $true,
    [switch]$VerifyExistingMp4 = $true,

    [string]$LogDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section([string]$Text) {
    Write-Host ""
    Write-Host ('=' * 78)
    Write-Host $Text
    Write-Host ('=' * 78)
}

function Format-Bytes([long]$Bytes) {
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Get-FileCodecInfo([string]$Path) {
    try {
        $json = & $Ffprobe -v error -print_format json -show_streams -show_format -- "$Path" 2>$null | Out-String
        if (-not $json.Trim()) { return $null }
        $o = $json | ConvertFrom-Json
        $v = @($o.streams | Where-Object { $_.codec_type -eq 'video' }) | Select-Object -First 1
        $a = @($o.streams | Where-Object { $_.codec_type -eq 'audio' }) | Select-Object -First 1
        [pscustomobject]@{
            VideoCodec = if ($v) { [string]$v.codec_name } else { '' }
            AudioCodec = if ($a) { [string]$a.codec_name } else { '' }
            Width      = if ($v -and $v.width)  { [int]$v.width } else { 0 }
            Height     = if ($v -and $v.height) { [int]$v.height } else { 0 }
            Duration   = if ($o.format.duration) { [double]$o.format.duration } else { 0 }
        }
    } catch {
        return $null
    }
}

function Test-Mp4Healthy([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $fi = Get-Item -LiteralPath $Path
    if ($fi.Length -le 0) { return $false }
    if (-not $VerifyExistingMp4) { return $true }
    $info = Get-FileCodecInfo $Path
    return ($null -ne $info -and -not [string]::IsNullOrWhiteSpace($info.VideoCodec))
}

function Get-Sidecars([string]$MovPath) {
    $dir  = Split-Path -Parent $MovPath
    $base = [IO.Path]::GetFileNameWithoutExtension($MovPath)
    $candidates = @(
        (Join-Path $dir ($base + '.xmp')),
        (Join-Path $dir ($base + '.XMP')),
        ($MovPath + '.xmp'),
        ($MovPath + '.XMP')
    ) | Select-Object -Unique
    return @($candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Copy-SidecarsForMp4([string]$MovPath, [string]$Mp4Path) {
    $results = @()
    foreach ($src in (Get-Sidecars $MovPath)) {
        $mp4Dir = Split-Path -Parent $Mp4Path
        $mp4Base = [IO.Path]::GetFileNameWithoutExtension($Mp4Path)
        $srcName = Split-Path -Leaf $src

        if ($srcName -ieq ((Split-Path -Leaf $MovPath) + '.xmp')) {
            $dst = $Mp4Path + '.xmp'
        } else {
            $dst = Join-Path $mp4Dir ($mp4Base + '.xmp')
        }

        if (-not (Test-Path -LiteralPath $dst)) {
            Copy-Item -LiteralPath $src -Destination $dst -Force:$false
            $results += "Copied:$([IO.Path]::GetFileName($dst))"
        } else {
            $results += "Exists:$([IO.Path]::GetFileName($dst))"
        }
    }
    return ($results -join '; ')
}

function Copy-Metadata([string]$Source, [string]$Target) {
    # Copy broadly first, then explicitly preserve common DigiKam/XMP/IPTC fields.
    # -overwrite_original avoids ExifTool backup files alongside the new MP4.
    & $ExifTool -overwrite_original -api QuickTimeUTC=1 `
        -TagsFromFile "$Source" -all:all `
        -XMP:All -IPTC:All -EXIF:All `
        -CreateDate -ModifyDate -TrackCreateDate -TrackModifyDate -MediaCreateDate -MediaModifyDate `
        -GPSLatitude -GPSLongitude -GPSAltitude `
        -Title -Description -Comment -Caption-Abstract -Subject -Keywords -HierarchicalSubject -Rating `
        "$Target" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "ExifTool metadata copy failed with exit code $LASTEXITCODE"
    }
}

function Invoke-Convert([string]$MovPath, [string]$Mp4Path, $Info) {
    $streamCopy = ($Info -and $Info.VideoCodec -eq 'h264' -and ($Info.AudioCodec -in @('', 'aac', 'mp3')))

    if ($streamCopy) {
        $args = @('-hide_banner','-loglevel','error','-y','-i',$MovPath,'-map','0:v:0','-map','0:a?','-map_metadata','0','-c','copy','-movflags','+faststart',$Mp4Path)
        & $Ffmpeg @args
        if ($LASTEXITCODE -ne 0) { throw "FFmpeg stream-copy failed with exit code $LASTEXITCODE" }
        return 'STREAM_COPY'
    }

    $args = @('-hide_banner','-loglevel','error','-y','-i',$MovPath,'-map','0:v:0','-map','0:a?','-map_metadata','0',
              '-c:v','libx264','-preset',$Preset,'-crf',"$Crf",'-pix_fmt','yuv420p',
              '-c:a','aac','-b:a','192k','-movflags','+faststart',$Mp4Path)
    & $Ffmpeg @args
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg transcode failed with exit code $LASTEXITCODE" }
    return 'TRANSCODE_H264_AAC'
}

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Root folder not found: $Root"
}

$Root = (Resolve-Path -LiteralPath $Root).Path

foreach ($tool in @($Ffmpeg,$Ffprobe,$ExifTool)) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool not found in PATH: $tool"
    }
}

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $LogDirectory = Join-Path $Root '_VideoConversionLogs'
}
if (-not (Test-Path -LiteralPath $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory | Out-Null
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath = Join-Path $LogDirectory "MOVtoMP4_${Mode}_$stamp.csv"

Write-Section "Bell Family Archive - MOV to MP4 Converter v1.1"
Write-Host "Mode        : $Mode"
Write-Host "Root        : $Root"
Write-Host "CRF/Preset  : $Crf / $Preset"
Write-Host "Log         : $csvPath"
Write-Host "Original MOV files are NEVER deleted or overwritten."

$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter *.mov -Force:$IncludeHidden)
$results = New-Object System.Collections.Generic.List[object]

$totalMovBytes = [int64]0
$totalExistingMp4Bytes = [int64]0
$totalFinalMp4Bytes = [int64]0
$totalSavingsBytes = [int64]0
$convertedCount = 0
$existingCount = 0
$failedCount = 0
$needCount = 0

$i = 0
foreach ($mov in $files) {
    $i++
    $totalMovBytes += $mov.Length
    $mp4 = Join-Path $mov.DirectoryName ($mov.BaseName + '.mp4')
    $existing = Test-Mp4Healthy $mp4
    $info = Get-FileCodecInfo $mov.FullName
    $sidecars = @(Get-Sidecars $mov.FullName)

    $status = ''
    $method = ''
    $mp4Bytes = [int64]0
    $saved = [int64]0
    $pct = 0.0
    $sidecarStatus = if ($sidecars.Count) { ($sidecars | ForEach-Object { Split-Path -Leaf $_ }) -join '; ' } else { '' }
    $metadataStatus = ''
    $errorText = ''

    Write-Progress -Activity "Scanning MOV files" -Status "$i of $($files.Count): $($mov.Name)" -PercentComplete (($i / [math]::Max(1,$files.Count))*100)

    if ($existing) {
        $existingCount++
        $fi = Get-Item -LiteralPath $mp4
        $mp4Bytes = $fi.Length
        $totalExistingMp4Bytes += $mp4Bytes
        $totalFinalMp4Bytes += $mp4Bytes
        $saved = $mov.Length - $mp4Bytes
        $totalSavingsBytes += $saved
        if ($mov.Length -gt 0) { $pct = ($saved / [double]$mov.Length) * 100 }
        $status = 'EXISTING_MP4_SKIPPED'
        $method = 'EXISTING'
    }
    elseif (Test-Path -LiteralPath $mp4 -PathType Leaf) {
        $status = 'EXISTING_MP4_INVALID'
        $method = 'SKIPPED'
        $failedCount++
        $errorText = 'Matching MP4 exists but failed validation; not overwritten.'
    }
    else {
        $needCount++
        if ($Mode -eq 'REPORT') {
            $status = 'NEEDS_CONVERSION'
            $method = if ($info -and $info.VideoCodec -eq 'h264' -and ($info.AudioCodec -in @('', 'aac', 'mp3'))) { 'WOULD_STREAM_COPY' } else { 'WOULD_TRANSCODE_H264_AAC' }
        } else {
            try {
                $method = Invoke-Convert -MovPath $mov.FullName -Mp4Path $mp4 -Info $info

                if ($CopyMetadata) {
                    Copy-Metadata -Source $mov.FullName -Target $mp4
                    $metadataStatus = 'COPIED'
                }

                if ($CopySidecars -and $sidecars.Count) {
                    $sidecarStatus = Copy-SidecarsForMp4 -MovPath $mov.FullName -Mp4Path $mp4
                }

                $targetInfo = Get-FileCodecInfo $mp4
                if (-not $targetInfo -or [string]::IsNullOrWhiteSpace($targetInfo.VideoCodec)) {
                    throw 'Output MP4 failed ffprobe validation.'
                }

                $fi = Get-Item -LiteralPath $mp4
                $mp4Bytes = $fi.Length
                $totalFinalMp4Bytes += $mp4Bytes
                $saved = $mov.Length - $mp4Bytes
                $totalSavingsBytes += $saved
                if ($mov.Length -gt 0) { $pct = ($saved / [double]$mov.Length) * 100 }
                $status = 'CONVERTED'
                $convertedCount++
            } catch {
                $status = 'FAILED'
                $failedCount++
                $errorText = $_.Exception.Message
                if (Test-Path -LiteralPath $mp4 -PathType Leaf) {
                    try { Remove-Item -LiteralPath $mp4 -Force } catch {}
                }
            }
        }
    }

    $results.Add([pscustomobject]@{
        Folder             = $mov.DirectoryName
        MOV                = $mov.Name
        MP4                = [IO.Path]::GetFileName($mp4)
        Status             = $status
        Method             = $method
        MOV_Bytes          = $mov.Length
        MOV_Size           = Format-Bytes $mov.Length
        MP4_Bytes          = $mp4Bytes
        MP4_Size           = if ($mp4Bytes -gt 0) { Format-Bytes $mp4Bytes } else { '' }
        Reduction_Bytes    = if ($mp4Bytes -gt 0) { $saved } else { '' }
        Reduction_Size     = if ($mp4Bytes -gt 0) { Format-Bytes $saved } else { '' }
        Percent_Smaller    = if ($mp4Bytes -gt 0) { [math]::Round($pct,2) } else { '' }
        VideoCodec         = if ($info) { $info.VideoCodec } else { '' }
        AudioCodec         = if ($info) { $info.AudioCodec } else { '' }
        Resolution         = if ($info -and $info.Width -gt 0) { "$($info.Width)x$($info.Height)" } else { '' }
        DurationSeconds    = if ($info) { [math]::Round($info.Duration,2) } else { '' }
        Sidecar            = $sidecarStatus
        Metadata           = $metadataStatus
        Error              = $errorText
    })
}

Write-Progress -Activity "Scanning MOV files" -Completed
$results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

Write-Section "SUMMARY"
Write-Host ("MOV files found                 : {0:N0}" -f $files.Count)
Write-Host ("Already have valid MP4          : {0:N0}" -f $existingCount)
Write-Host ("Need conversion                  : {0:N0}" -f $needCount)
if ($Mode -eq 'WRITE') {
    Write-Host ("Successfully converted          : {0:N0}" -f $convertedCount)
    Write-Host ("Failed / invalid existing MP4   : {0:N0}" -f $failedCount)
}
Write-Host ""
Write-Host ("Original MOV total size          : {0}" -f (Format-Bytes $totalMovBytes))
Write-Host ("Existing MP4 total size          : {0}" -f (Format-Bytes $totalExistingMp4Bytes))

if ($Mode -eq 'WRITE') {
    Write-Host ("All valid MP4 total size         : {0}" -f (Format-Bytes $totalFinalMp4Bytes))
    Write-Host ("Total potential MOV→MP4 savings  : {0}" -f (Format-Bytes $totalSavingsBytes))
    $overallPct = if ($totalMovBytes -gt 0) { ($totalSavingsBytes / [double]$totalMovBytes) * 100 } else { 0 }
    Write-Host ("Overall reduction                : {0:N2}%" -f $overallPct)
    Write-Host ("Current disk use (MOV + MP4)     : {0}" -f (Format-Bytes ($totalMovBytes + $totalFinalMp4Bytes)))
    Write-Host ("Disk use if MOVs later removed   : {0}" -f (Format-Bytes $totalFinalMp4Bytes))
} else {
    Write-Host "REPORT mode does not create MP4s, so exact post-conversion savings"
    Write-Host "cannot be known for files that still require transcoding. Existing MP4"
    Write-Host "savings are included in the CSV; exact totals appear after WRITE mode."
}

Write-Host ""
Write-Host "CSV audit log: $csvPath"
Write-Host "Original MOV files were not deleted."

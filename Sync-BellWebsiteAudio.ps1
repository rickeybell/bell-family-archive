param(
    [switch]$DryRun,
    [int]$FromYear = 0,
    [int]$ToYear = 9999
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "2.0"
$RepoRoot = "C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive"
$SourceRoot = "C:\Users\rbell\OneDrive\Pictures"
$AudioRoot = Join-Path $RepoRoot "audio"
$ManifestCsv = Join-Path $RepoRoot "website-audio-manifest.csv"
$DbHelper = Join-Path $RepoRoot "tools\build_audio_manifest_from_digikam.py"

function Get-PythonCommand {
    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($python) {
        & $python.Source --version *> $null
        if ($LASTEXITCODE -eq 0) { return $python.Source }
    }
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        & $py.Source --version *> $null
        if ($LASTEXITCODE -eq 0) { return $py.Source }
    }
    throw "A working Python 3 runtime was not found."
}

if (!(Test-Path -LiteralPath $SourceRoot)) { throw "Source folder does not exist: $SourceRoot" }
if (!(Test-Path -LiteralPath $DbHelper)) { throw "DigiKam audio helper not found: $DbHelper" }
$python = Get-PythonCommand

Write-Host ""
Write-Host "Bell Family Archive Website Audio Sync v$ScriptVersion"
Write-Host "Source: $SourceRoot"
Write-Host "Destination: $AudioRoot"
Write-Host "Metadata source: DigiKam database"
Write-Host "Publish rule: DigiKam tag Website"
Write-Host "Archive type: Sound"
Write-Host "Years: $FromYear through $ToYear"
Write-Host "Decade placeholders: ignored"
if ($DryRun) { Write-Host "*** DRY RUN - NO AUDIO FILES WILL BE COPIED ***" }
Write-Host ""

$tempManifest = $null
$manifestForRun = $ManifestCsv
if ($DryRun) {
    $tempManifest = Join-Path $env:TEMP ("bell-audio-manifest-" + [guid]::NewGuid().ToString("N") + ".csv")
    $manifestForRun = $tempManifest
}

try {
    & $python $DbHelper --source-root $SourceRoot --output $manifestForRun --from-year $FromYear --to-year $ToYear
    if ($LASTEXITCODE -ne 0) { throw "DigiKam audio manifest builder failed (exit $LASTEXITCODE)." }
    if (!(Test-Path -LiteralPath $manifestForRun)) { throw "Audio manifest was not created: $manifestForRun" }

    $rows = @(Import-Csv -LiteralPath $manifestForRun)
    $copied = 0
    $current = 0

    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace($row.SourcePath) -or [string]::IsNullOrWhiteSpace($row.RelativePath)) { continue }
        $source = $row.SourcePath
        if (!(Test-Path -LiteralPath $source)) {
            Write-Warning "Audio source missing: $source"
            continue
        }
        $relative = $row.RelativePath -replace '/', '\'
        $dest = Join-Path $AudioRoot $relative
        $destExists = Test-Path -LiteralPath $dest
        $needsCopy = !$destExists
        if ($destExists) {
            $s = Get-Item -LiteralPath $source
            $d = Get-Item -LiteralPath $dest
            $needsCopy = ($d.Length -ne $s.Length) -or ($d.LastWriteTimeUtc -lt $s.LastWriteTimeUtc)
        }
        if ($needsCopy) {
            Write-Host "$(if($destExists){'UPDATE'}else{'NEW   '})  audio\$relative"
            if (!$DryRun) {
                $folder = Split-Path -Parent $dest
                if (!(Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
                Copy-Item -LiteralPath $source -Destination $dest -Force
                (Get-Item -LiteralPath $dest).LastWriteTimeUtc = (Get-Item -LiteralPath $source).LastWriteTimeUtc
            }
            $copied++
        } else {
            $current++
        }
    }

    Write-Host ""
    Write-Host "Website-tagged audio selected:   $($rows.Count)"
    Write-Host "Audio files copied/updated:      $copied"
    Write-Host "Already current:                 $current"
    if (!$DryRun) { Write-Host "Audio manifest: $ManifestCsv" }
}
finally {
    if ($tempManifest -and (Test-Path -LiteralPath $tempManifest)) {
        Remove-Item -LiteralPath $tempManifest -Force -ErrorAction SilentlyContinue
    }
}

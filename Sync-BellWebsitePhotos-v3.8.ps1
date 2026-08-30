param(
    [switch]$DryRun,
    [switch]$RefreshManifest,
    [switch]$Live,
    [switch]$FullAudit,
    [switch]$ForceRebuild,
    [int]$Workers = 4,
    [int]$FromYear = 0,
    [int]$ToYear = 9999
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "4.0"
$RepoRoot = $PSScriptRoot
$ManifestBuilder = Join-Path $RepoRoot "Sync-BellWebsitePhotos-v3.4.ps1"
$ManifestCsv = Join-Path $RepoRoot "website-photo-manifest.csv"
$GreenSyncHelper = Join-Path $RepoRoot "tools\ensure_website_green_in_digikam.py"
$FastExporter = Join-Path $RepoRoot "tools\export_website_photos.py"
$OutputRoot = if ($Live) { $RepoRoot } else { Join-Path $RepoRoot "website-test-v38" }
$CachePath = Join-Path $OutputRoot ".website-derivative-cache.json"

function Get-PythonCommand {
    if ($env:BELL_PYTHON -and (Test-Path -LiteralPath $env:BELL_PYTHON)) { return $env:BELL_PYTHON }
    foreach ($name in @("python.exe", "py.exe")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            & $command.Source --version *> $null
            if ($LASTEXITCODE -eq 0) { return $command.Source }
        }
    }
    throw "A working Python 3 runtime was not found."
}

foreach ($required in @($ManifestBuilder,$GreenSyncHelper,$FastExporter)) {
    if (!(Test-Path -LiteralPath $required)) { throw "Required exporter component not found: $required" }
}
if ($Workers -lt 1 -or $Workers -gt 16) { throw "Workers must be between 1 and 16." }

$python = Get-PythonCommand
$greenArgs = @($GreenSyncHelper)
if ($DryRun) { $greenArgs += '--dry-run' }
& $python @greenArgs
if ($LASTEXITCODE -ne 0) { throw "Could not synchronize Website tags to digiKam green labels." }

if ($RefreshManifest) {
    if ($DryRun) {
        Write-Host "Dry run: using the current manifest; no manifest files will be changed."
    } else {
        $manifestArgs = @('-ExecutionPolicy','Bypass','-File',$ManifestBuilder,'-ManifestOnly','-SkipOrphanScan')
        if ($FullAudit) {
            $manifestArgs = @('-ExecutionPolicy','Bypass','-File',$ManifestBuilder,'-ManifestOnly','-ForceFullScan')
        }
        & powershell.exe @manifestArgs
        if ($LASTEXITCODE -ne 0) { throw "Photo manifest refresh failed." }
    }
}
if (!(Test-Path -LiteralPath $ManifestCsv)) { throw "Website photo manifest not found: $ManifestCsv" }

Write-Host ""
Write-Host "Bell Family Archive Website Photo Generator v$ScriptVersion"
Write-Host "Publish rule: Website tag only; green label assigned automatically"
Write-Host "Mode: $(if($FullAudit){'FULL AUDIT'}else{'INCREMENTAL'})"
Write-Host "Output: $(if($Live){'LIVE'}else{'website-test-v38'})"
Write-Host "Workers: $Workers"
Write-Host "Years: $FromYear through $ToYear"
Write-Host ""

$exportArgs = @(
    $FastExporter,
    '--manifest',$ManifestCsv,
    '--output-root',$OutputRoot,
    '--cache',$CachePath,
    '--from-year',"$FromYear",
    '--to-year',"$ToYear",
    '--workers',"$Workers"
)
if ($DryRun) { $exportArgs += '--dry-run' }
if ($FullAudit) { $exportArgs += '--full-audit' }
if ($ForceRebuild) { $exportArgs += '--force-rebuild' }
& $python @exportArgs
if ($LASTEXITCODE -ne 0) { throw "Fast photo export failed." }

Write-Host "Output root: $OutputRoot"
if (!$Live) { Write-Host "TEST MODE: live website folders were not touched." }

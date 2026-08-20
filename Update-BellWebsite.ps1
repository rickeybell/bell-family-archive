param(
    [switch]$DryRun,
    [switch]$Publish,
    [switch]$SkipPull,
    [switch]$SkipManifestRefresh,
    [int]$FromYear = 0,
    [int]$ToYear = 9999,
    [string]$CommitMessage = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = "C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive"
$Generator = Join-Path $RepoRoot "Sync-BellWebsitePhotos-v3.8.ps1"
$Manifest = Join-Path $RepoRoot "website-photo-manifest.csv"
$BuildMetadata = Join-Path $RepoRoot "tools\build_photo_metadata.py"
$BuildGallery = Join-Path $RepoRoot "tools\build_dynamic_gallery.py"

function Invoke-Checked {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $FilePath $($Arguments -join ' ')"
    }
}

function Get-PythonCommand {
    if (Get-Command py.exe -ErrorAction SilentlyContinue) {
        return @{ File = "py.exe"; Prefix = @("-3") }
    }
    if (Get-Command python.exe -ErrorAction SilentlyContinue) {
        return @{ File = "python.exe"; Prefix = @() }
    }
    throw "Python 3 was not found."
}

function Test-RepoClean {
    $status = git -C $RepoRoot status --porcelain
    return [string]::IsNullOrWhiteSpace(($status -join "`n"))
}

function Assert-MasterSourcesOutsideRepo {
    if (!(Test-Path -LiteralPath $Manifest)) {
        throw "Manifest not found: $Manifest"
    }

    $repoFull = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\') + '\'
    $bad = @()

    foreach ($row in (Import-Csv -LiteralPath $Manifest)) {
        if ([string]::IsNullOrWhiteSpace($row.SourcePath)) { continue }
        try {
            $srcFull = [System.IO.Path]::GetFullPath($row.SourcePath)
            if ($srcFull.StartsWith($repoFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                $bad += $row.SourcePath
            }
        } catch {}
    }

    if ($bad.Count -gt 0) {
        $sample = ($bad | Select-Object -First 10) -join "`n  "
        throw @"
SAFETY STOP: website/repository files appear in the manifest as source masters.

DigiKam/master photos must remain authoritative.
First entries found:
  $sample
"@
    }
}

Write-Host ""
Write-Host "=============================================="
Write-Host " Bell Family Archive Website Update"
Write-Host "=============================================="
Write-Host "Repository: $RepoRoot"
Write-Host "Years:      $FromYear through $ToYear"
Write-Host "Mode:       $(if ($DryRun) {'DRY RUN'} elseif ($Publish) {'UPDATE + PUBLISH'} else {'UPDATE ONLY'})"
Write-Host ""

if (!(Test-Path -LiteralPath $RepoRoot)) { throw "Repository not found: $RepoRoot" }
if (!(Test-Path -LiteralPath $Generator)) { throw "Generator not found: $Generator" }
if (!(Test-Path -LiteralPath $BuildMetadata)) { throw "Metadata builder not found: $BuildMetadata" }
if (!(Test-Path -LiteralPath $BuildGallery)) { throw "Gallery builder not found: $BuildGallery" }

Invoke-Checked git.exe -C $RepoRoot rev-parse --is-inside-work-tree | Out-Null

if (!(Test-RepoClean)) {
    Write-Host "Current repository changes:"
    git -C $RepoRoot status --short
    throw "Repository is not clean. Commit, stash, or discard existing changes before running the updater."
}

if (!$SkipPull) {
    Write-Host "[1/7] Updating local main branch..."
    Invoke-Checked git.exe -C $RepoRoot checkout main
    Invoke-Checked git.exe -C $RepoRoot pull --ff-only origin main
} else {
    Write-Host "[1/7] Git pull skipped."
}

Write-Host "[2/7] Refreshing DigiKam Website-tag manifest..."
$syncArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $Generator,
    "-FromYear", "$FromYear",
    "-ToYear", "$ToYear"
)

if (!$SkipManifestRefresh) { $syncArgs += "-RefreshManifest" }
if ($DryRun) { $syncArgs += "-DryRun" }
else { $syncArgs += "-Live" }

Invoke-Checked powershell.exe @syncArgs

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run finished. No website files were changed."
    exit 0
}

Write-Host "[3/7] Verifying that DigiKam/master files are authoritative..."
Assert-MasterSourcesOutsideRepo

$py = Get-PythonCommand

Write-Host "[4/7] Rebuilding photo_metadata.json from generated website images..."
Invoke-Checked $py.File @($py.Prefix + @($BuildMetadata))

Write-Host "[5/7] Rebuilding chronological and person photo galleries..."
Invoke-Checked $py.File @($py.Prefix + @($BuildGallery))

Write-Host "[6/7] Reviewing changed files..."
$status = git -C $RepoRoot status --short
if ([string]::IsNullOrWhiteSpace(($status -join "`n"))) {
    Write-Host "No website changes detected."
    exit 0
}

$status | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "Change summary:"
git -C $RepoRoot diff --stat

if (!$Publish) {
    Write-Host ""
    Write-Host "Update complete, but nothing was committed or pushed."
    Write-Host "Review the site locally, then run again with -Publish when ready."
    Write-Host ""
    Write-Host "Example:"
    Write-Host "  .\Update-BellWebsite.ps1 -FromYear 1940 -ToYear 1949 -Publish"
    exit 0
}

Write-Host "[7/7] Committing and pushing approved website changes..."

if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    if ($FromYear -eq 0 -and $ToYear -eq 9999) {
        $CommitMessage = "Update website from DigiKam master metadata and photos"
    } elseif ($FromYear -eq $ToYear) {
        $CommitMessage = "Update $FromYear photos, metadata, and galleries"
    } else {
        $CommitMessage = "Update $FromYear-$ToYear photos, metadata, and galleries"
    }
}

# Stage only known website-generated content and metadata.
$paths = @(
    "images",
    "thumbs",
    "originals",
    "photo_metadata.json",
    "gallery.html",
    "alma-photos.html",
    "buster-photos.html",
    "dickey-photos.html",
    "heather-photos.html",
    "jarred-photos.html",
    "rickey-photos.html",
    "sonja-photos.html",
    "spooky-photos.html",
    "stephanie-photos.html",
    "website-photo-manifest.csv"
)

foreach ($p in $paths) {
    if (Test-Path -LiteralPath (Join-Path $RepoRoot $p)) {
        git -C $RepoRoot add -- $p
        if ($LASTEXITCODE -ne 0) { throw "Failed to stage $p" }
    }
}

$staged = git -C $RepoRoot diff --cached --name-only
if ([string]::IsNullOrWhiteSpace(($staged -join "`n"))) {
    Write-Host "Nothing staged; no commit needed."
    exit 0
}

Write-Host ""
Write-Host "Files to commit:"
$staged | ForEach-Object { Write-Host "  $_" }

Invoke-Checked git.exe -C $RepoRoot commit -m $CommitMessage
Invoke-Checked git.exe -C $RepoRoot push origin main

Write-Host ""
Write-Host "Published successfully."
Write-Host "Commit:"
git -C $RepoRoot log -1 --oneline
Write-Host ""
Write-Host "Live site:"
Write-Host "  https://rickeybell.github.io/bell-family-archive/"

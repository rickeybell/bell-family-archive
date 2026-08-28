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
$VideoGenerator = Join-Path $RepoRoot "Sync-BellWebsiteVideos.ps1"
$AudioGenerator = Join-Path $RepoRoot "Sync-BellWebsiteAudio.ps1"
$Manifest = Join-Path $RepoRoot "website-photo-manifest.csv"
$VideoManifest = Join-Path $RepoRoot "website-video-manifest.csv"
$AudioManifest = Join-Path $RepoRoot "website-audio-manifest.csv"
$BuildMetadata = Join-Path $RepoRoot "tools\build_photo_metadata.py"
$BuildGallery = Join-Path $RepoRoot "tools\build_dynamic_gallery.py"
$AddAudioPlayers = Join-Path $RepoRoot "tools\add_audio_players.py"
$ReportRoot = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "BellWebsite-SizeReports"

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
    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($python) {
        & $python.Source --version *> $null
        if ($LASTEXITCODE -eq 0) { return @{ File = $python.Source; Prefix = @() } }
    }
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        & $py.Source --version *> $null
        if ($LASTEXITCODE -eq 0) { return @{ File = $py.Source; Prefix = @() } }
    }
    throw "A working Python 3 runtime was not found."
}

function Test-RepoClean {
    $status = git -C $RepoRoot status --porcelain --untracked-files=no
    return [string]::IsNullOrWhiteSpace(($status -join "`n"))
}

function Assert-MasterSourcesOutsideRepo {
    foreach ($manifestPath in @($Manifest,$VideoManifest,$AudioManifest)) {
        if (!(Test-Path -LiteralPath $manifestPath)) { continue }
        $repoFull = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\') + '\'
        $bad = @()
        foreach ($row in (Import-Csv -LiteralPath $manifestPath)) {
            if ([string]::IsNullOrWhiteSpace($row.SourcePath)) { continue }
            try {
                $srcFull = [System.IO.Path]::GetFullPath($row.SourcePath)
                if ($srcFull.StartsWith($repoFull, [System.StringComparison]::OrdinalIgnoreCase)) { $bad += $row.SourcePath }
            } catch {}
        }
        if ($bad.Count -gt 0) {
            $sample = ($bad | Select-Object -First 10) -join "`n  "
            throw "SAFETY STOP: repository files appear as source masters in $manifestPath.`n  $sample"
        }
    }
}

function Test-DecadePlaceholderFolderName {
    param([string]$Name)
    return ($Name -match '^(18|19|20)\d0s$')
}

function Remove-GeneratedPlaceholderDirectories {
    foreach ($rootName in @("images","thumbs","highres","videos","audio")) {
        $root = Join-Path $RepoRoot $rootName
        if (!(Test-Path -LiteralPath $root)) { continue }
        $matches = @(Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '(?i)(^|[\\/])\.dtrash([\\/]|$)' -and
                (Test-DecadePlaceholderFolderName $_.Name)
            } |
            Sort-Object { $_.FullName.Length } -Descending)
        foreach ($dir in $matches) {
            if (Test-Path -LiteralPath $dir.FullName) {
                Write-Host "Removing generated placeholder directory: $($dir.FullName)"
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force
            }
        }
    }
}

function Get-FolderStat {
    param([string]$Name)
    $path = Join-Path $RepoRoot $Name
    if (!(Test-Path -LiteralPath $path)) { return [pscustomobject]@{Folder=$Name;Files=0;TotalGB=0;AverageMB=0;LargestMB=0} }
    $files = @(Get-ChildItem -LiteralPath $path -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '(?i)(^|[\\/])\.dtrash([\\/]|$)'
    })
    if ($files.Count -eq 0) { return [pscustomobject]@{Folder=$Name;Files=0;TotalGB=0;AverageMB=0;LargestMB=0} }
    $sum = ($files | Measure-Object Length -Sum).Sum
    $largest = ($files | Sort-Object Length -Descending | Select-Object -First 1).Length
    return [pscustomobject]@{
        Folder=$Name; Files=$files.Count; TotalGB=[math]::Round($sum/1GB,3)
        AverageMB=[math]::Round(($sum/$files.Count)/1MB,3); LargestMB=[math]::Round($largest/1MB,3)
    }
}

function Save-SizeReport {
    param($Before,$After)
    if (!(Test-Path -LiteralPath $ReportRoot)) { New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null }
    $path = Join-Path $ReportRoot ("BellWebsite-Live-SizeReport-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt")
    $text = @"
Bell Family Archive LIVE Before/After Size Report
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

BEFORE
$($Before | Format-Table -AutoSize | Out-String)

AFTER
$($After | Format-Table -AutoSize | Out-String)
"@
    $text | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Host "Size report saved: $path"
}

Write-Host ""
Write-Host "=============================================="
Write-Host " Bell Family Archive Website Update"
Write-Host "=============================================="
Write-Host "Repository: $RepoRoot"
Write-Host "Years:      $FromYear through $ToYear"
Write-Host "Mode:       $(if ($DryRun) {'DRY RUN'} elseif ($Publish) {'UPDATE + PUBLISH'} else {'UPDATE ONLY'})"
Write-Host "Media:      Photos + Videos + Audio"
Write-Host ""

if (!(Test-Path -LiteralPath $RepoRoot)) { throw "Repository not found: $RepoRoot" }
if (!(Test-Path -LiteralPath $Generator)) { throw "Photo generator not found: $Generator" }
if (!(Test-Path -LiteralPath $VideoGenerator)) { throw "Video generator not found: $VideoGenerator" }
if (!(Test-Path -LiteralPath $AudioGenerator)) { throw "Audio generator not found: $AudioGenerator" }
if (!(Test-Path -LiteralPath $BuildMetadata)) { throw "Metadata builder not found: $BuildMetadata" }
if (!(Test-Path -LiteralPath $BuildGallery)) { throw "Gallery builder not found: $BuildGallery" }
if (!(Test-Path -LiteralPath $AddAudioPlayers)) { throw "Audio gallery post-processor not found: $AddAudioPlayers" }

Invoke-Checked git.exe -C $RepoRoot rev-parse --is-inside-work-tree | Out-Null
if (!(Test-RepoClean)) {
    Write-Host "Current tracked repository changes:"
    git -C $RepoRoot status --short --untracked-files=no
    throw "Repository has tracked changes. Commit, stash, or discard them before running the updater."
}

$before = @(
    Get-FolderStat "thumbs"; Get-FolderStat "images"; Get-FolderStat "highres"; Get-FolderStat "videos"; Get-FolderStat "audio"; Get-FolderStat "originals"
)

if (!$SkipPull) {
    Write-Host "[1/9] Updating local main branch..."
    Invoke-Checked git.exe -C $RepoRoot checkout main
    Invoke-Checked git.exe -C $RepoRoot pull --ff-only origin main
} else { Write-Host "[1/9] Git pull skipped." }

Write-Host "[2/9] Refreshing DigiKam Website-tag photo manifest and generating photo derivatives..."
$syncArgs = @("-ExecutionPolicy","Bypass","-File",$Generator,"-FromYear","$FromYear","-ToYear","$ToYear")
if (!$SkipManifestRefresh) { $syncArgs += "-RefreshManifest" }
if ($DryRun) { $syncArgs += "-DryRun" } else { $syncArgs += "-Live" }
Invoke-Checked powershell.exe @syncArgs

Write-Host "[3/9] Scanning and syncing Website-tagged videos..."
$videoArgs = @("-ExecutionPolicy","Bypass","-File",$VideoGenerator,"-FromYear","$FromYear","-ToYear","$ToYear")
if ($DryRun) { $videoArgs += "-DryRun" }
Invoke-Checked powershell.exe @videoArgs

Write-Host "[4/9] Scanning and syncing Website-tagged audio..."
$audioArgs = @("-ExecutionPolicy","Bypass","-File",$AudioGenerator,"-FromYear","$FromYear","-ToYear","$ToYear")
if ($DryRun) { $audioArgs += "-DryRun" }
Invoke-Checked powershell.exe @audioArgs

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run finished. No website files were changed."
    exit 0
}

Write-Host "[5/9] Safety cleanup and master verification..."
Assert-MasterSourcesOutsideRepo
Remove-GeneratedPlaceholderDirectories

$highresPath = Join-Path $RepoRoot "highres"
if (!(Test-Path -LiteralPath $highresPath)) { throw "SAFETY STOP: highres folder was not generated. originals will NOT be removed." }
$highCount = @(Get-ChildItem -LiteralPath $highresPath -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notmatch '(?i)(^|[\\/])\.dtrash([\\/]|$)'
}).Count
if ($highCount -eq 0) { throw "SAFETY STOP: highres folder is empty. originals will NOT be removed." }
$originalsPath = Join-Path $RepoRoot "originals"
if (Test-Path -LiteralPath $originalsPath) {
    Write-Host "Retiring GitHub originals folder after successful HighRes generation..."
    Remove-Item -LiteralPath $originalsPath -Recurse -Force
}

$py = Get-PythonCommand
Write-Host "[6/9] Rebuilding photo_metadata.json from DigiKam/master photos, videos, and audio..."
Invoke-Checked $py.File @($py.Prefix + @($BuildMetadata))
Write-Host "[7/9] Rebuilding chronological and person galleries..."
Invoke-Checked $py.File @($py.Prefix + @($BuildGallery))
Invoke-Checked $py.File @($py.Prefix + @($AddAudioPlayers))

$after = @(
    Get-FolderStat "thumbs"; Get-FolderStat "images"; Get-FolderStat "highres"; Get-FolderStat "videos"; Get-FolderStat "audio"; Get-FolderStat "originals"
)
Write-Host ""; Write-Host "BEFORE:"; $before | Format-Table -AutoSize
Write-Host "AFTER:"; $after | Format-Table -AutoSize
Save-SizeReport $before $after

Write-Host "[8/9] Reviewing changed files..."
$status = git -C $RepoRoot status --short --untracked-files=no
if ([string]::IsNullOrWhiteSpace(($status -join "`n"))) { Write-Host "No website changes detected."; exit 0 }
$status | ForEach-Object { Write-Host $_ }
Write-Host ""; Write-Host "Change summary:"; git -C $RepoRoot diff --stat

if (!$Publish) {
    Write-Host ""
    Write-Host "Update complete, but nothing was committed or pushed."
    Write-Host "Review the site and size report first."
    exit 0
}

Write-Host "[9/9] Committing and pushing approved website changes..."
if ([string]::IsNullOrWhiteSpace($CommitMessage)) { $CommitMessage = "Update website photos, videos, audio, metadata, and galleries" }

git -C $RepoRoot add -A -- .
if ($LASTEXITCODE -ne 0) { throw "Failed to stage all repository changes" }
$staged = git -C $RepoRoot diff --cached --name-only
if ([string]::IsNullOrWhiteSpace(($staged -join "`n"))) { Write-Host "Nothing staged; no commit needed."; exit 0 }
Write-Host ""; Write-Host "Files to commit:"; $staged | ForEach-Object { Write-Host "  $_" }
Invoke-Checked git.exe -C $RepoRoot commit -m $CommitMessage
Invoke-Checked git.exe -C $RepoRoot push origin main
Write-Host ""; Write-Host "Published successfully."
git -C $RepoRoot log -1 --oneline
Write-Host "https://bellfamilyarchive.us/"

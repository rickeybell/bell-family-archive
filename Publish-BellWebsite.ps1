param(
    [string]$CommitMessage = "Update Bell Family Archive website"
)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
$GreenSyncHelper = Join-Path $RepoRoot "tools\ensure_website_green_in_digikam.py"

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
    if ($env:BELL_PYTHON -and (Test-Path -LiteralPath $env:BELL_PYTHON)) {
        & $env:BELL_PYTHON --version *> $null
        if ($LASTEXITCODE -eq 0) { return $env:BELL_PYTHON }
    }
    foreach ($name in @("python.exe", "py.exe")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            & $command.Source --version *> $null
            if ($LASTEXITCODE -eq 0) { return $command.Source }
        }
    }
    throw "A working Python 3 runtime was not found."
}

if (!(Test-Path -LiteralPath $GreenSyncHelper)) {
    throw "digiKam green-label helper not found: $GreenSyncHelper"
}

$python = Get-PythonCommand
Write-Host "Updating digiKam color labels before publishing..."
Invoke-Checked $python $GreenSyncHelper

Write-Host "Checking website changes..."
Invoke-Checked -FilePath git.exe -Arguments @('-C',$RepoRoot,'diff','--check')
Invoke-Checked -FilePath git.exe -Arguments @('-C',$RepoRoot,'add','-A','--','.')

$staged = git -C $RepoRoot diff --cached --name-only
if ([string]::IsNullOrWhiteSpace(($staged -join "`n"))) {
    Write-Host "No website changes to publish."
    exit 0
}

Write-Host "Files to publish:"
$staged | ForEach-Object { Write-Host "  $_" }
Invoke-Checked -FilePath git.exe -Arguments @('-C',$RepoRoot,'commit','-m',$CommitMessage)
Invoke-Checked -FilePath git.exe -Arguments @('-C',$RepoRoot,'push','origin','main')

Write-Host "Published successfully."
Write-Host "https://bellfamilyarchive.us/"

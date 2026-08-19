$path = Join-Path $PSScriptRoot 'Sync-BellWebsitePhotos-v3.4.ps1'
$text = Get-Content -LiteralPath $path -Raw
$old = "-replace '\','/'"
$new = "-replace '\\','/'"
if ($text.Contains($old)) {
    $text = $text.Replace($old, $new)
    Set-Content -LiteralPath $path -Value $text -Encoding UTF8
    Write-Host 'Fixed v3.4 backslash pattern.'
} else {
    Write-Host 'No matching broken pattern found; file may already be fixed.'
}

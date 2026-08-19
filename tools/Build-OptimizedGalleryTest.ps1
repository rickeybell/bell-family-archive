param(
    [string]$TestRoot = "website-test-v38"
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Root = Join-Path $RepoRoot $TestRoot
$ThumbRoot = Join-Path $Root 'thumbs'
$ViewRoot = Join-Path $Root 'images'
$OriginalRoot = Join-Path $Root 'originals'
$Output = Join-Path $Root 'gallery-test.html'

foreach ($p in @($Root,$ThumbRoot,$ViewRoot,$OriginalRoot)) {
    if (!(Test-Path -LiteralPath $p)) { throw "Required folder not found: $p" }
}

function Html([string]$s) {
    if ($null -eq $s) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($s)
}
function UrlPath([string]$s) { return ($s -replace '\\','/') }

$exts = @('.jpg','.jpeg','.png','.tif','.tiff','.webp')
$thumbs = Get-ChildItem -LiteralPath $ThumbRoot -File -Recurse | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } | Sort-Object FullName
$cards = New-Object System.Collections.Generic.List[string]
$missingView = 0; $missingOriginal = 0

foreach ($thumb in $thumbs) {
    $relative = $thumb.FullName.Substring($ThumbRoot.Length).TrimStart('\','/')
    $view = Join-Path $ViewRoot $relative
    $original = Join-Path $OriginalRoot $relative
    if (!(Test-Path -LiteralPath $view)) { $missingView++; continue }
    if (!(Test-Path -LiteralPath $original)) { $missingOriginal++; continue }

    $thumbUrl = 'thumbs/' + (UrlPath $relative)
    $viewUrl = 'images/' + (UrlPath $relative)
    $origUrl = 'originals/' + (UrlPath $relative)
    $name = [IO.Path]::GetFileName($relative)
    $folder = Split-Path -Parent $relative
    $cards.Add(@"
<article class="card">
  <a class="photo-link" href="$(Html $viewUrl)" target="_blank" title="Open optimized viewing image">
    <img src="$(Html $thumbUrl)" alt="$(Html $name)" loading="lazy" decoding="async">
  </a>
  <div class="copy">
    <div class="name">$(Html $name)</div>
    <div class="folder">$(Html $folder)</div>
    <div class="actions"><a href="$(Html $viewUrl)" target="_blank">View</a><a href="$(Html $origUrl)" download>Download full resolution</a></div>
  </div>
</article>
"@)
}

$body = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Optimized Gallery Test — Bell Family Archive</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#f4f2ed;color:#242424}.main{max-width:1500px;margin:auto;padding:28px}h1{margin-bottom:6px}.note{margin:0 0 24px;color:#555}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:16px}.card{background:white;border-radius:12px;overflow:hidden;box-shadow:0 2px 10px #0002}.photo-link{display:block;background:#e7e7e7}.card img{display:block;width:100%;height:220px;object-fit:contain}.copy{padding:11px}.name{font-weight:600;overflow-wrap:anywhere}.folder{font-size:.82rem;color:#777;margin-top:4px}.actions{display:flex;gap:12px;flex-wrap:wrap;margin-top:10px}.actions a{font-size:.88rem}.stats{background:#fff;padding:12px 16px;border-radius:10px;margin:18px 0}
</style></head><body><main class="main">
<h1>Bell Family Archive — Optimized Gallery Test</h1>
<p class="note">Gallery grid uses 400px thumbnails. Click an image for the optimized viewer copy; use Download full resolution for the archival original.</p>
<div class="stats"><strong>$($cards.Count)</strong> complete three-level images &nbsp;·&nbsp; Missing viewer copies: $missingView &nbsp;·&nbsp; Missing originals: $missingOriginal</div>
<div class="grid">$($cards -join "`n")</div>
</main></body></html>
"@

[IO.File]::WriteAllText($Output,$body,[Text.UTF8Encoding]::new($false))
Write-Host "`nOptimized gallery test created."
Write-Host "Cards:             $($cards.Count)"
Write-Host "Missing views:     $missingView"
Write-Host "Missing originals: $missingOriginal"
Write-Host "Output:            $Output"

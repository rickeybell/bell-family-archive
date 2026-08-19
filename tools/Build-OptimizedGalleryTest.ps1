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
function Js([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '\\','\\\\' -replace '"','\"')
}

$exts = @('.jpg','.jpeg','.png','.tif','.tiff','.webp')
$thumbs = Get-ChildItem -LiteralPath $ThumbRoot -File -Recurse | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } | Sort-Object FullName
$cards = New-Object System.Collections.Generic.List[string]
$items = New-Object System.Collections.Generic.List[string]
$missingView = 0; $missingOriginal = 0; $index = 0

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
  <button class="photo-link" type="button" data-index="$index" title="Open optimized viewing image">
    <img src="$(Html $thumbUrl)" alt="$(Html $name)" loading="lazy" decoding="async">
  </button>
  <div class="copy">
    <div class="name">$(Html $name)</div>
    <div class="folder">$(Html $folder)</div>
    <div class="actions"><button type="button" class="view-btn" data-index="$index">View</button><a href="$(Html $origUrl)" download>Download full resolution</a></div>
  </div>
</article>
"@)
    $items.Add("{view:\"$(Js $viewUrl)\",original:\"$(Js $origUrl)\",name:\"$(Js $name)\",folder:\"$(Js $folder)\"}")
    $index++
}

$body = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Optimized Gallery Test — Bell Family Archive</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#f4f2ed;color:#242424}.main{max-width:1500px;margin:auto;padding:28px}h1{margin-bottom:6px}.note{margin:0 0 24px;color:#555}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:16px}.card{background:white;border-radius:12px;overflow:hidden;box-shadow:0 2px 10px #0002}.photo-link{display:block;width:100%;border:0;padding:0;background:#e7e7e7;cursor:pointer}.card img{display:block;width:100%;height:220px;object-fit:contain}.copy{padding:11px}.name{font-weight:600;overflow-wrap:anywhere}.folder{font-size:.82rem;color:#777;margin-top:4px}.actions{display:flex;gap:12px;flex-wrap:wrap;margin-top:10px}.actions a,.actions button{font-size:.88rem}.actions button{border:0;background:none;color:#06c;text-decoration:underline;padding:0;cursor:pointer}.stats{background:#fff;padding:12px 16px;border-radius:10px;margin:18px 0}
.modal{position:fixed;inset:0;background:rgba(0,0,0,.88);display:none;align-items:center;justify-content:center;z-index:9999}.modal.open{display:flex}.modal-inner{position:relative;width:min(96vw,1500px);height:min(94vh,1000px);display:grid;grid-template-rows:1fr auto;gap:10px}.modal-stage{position:relative;display:flex;align-items:center;justify-content:center;min-height:0}.modal-img{max-width:100%;max-height:100%;object-fit:contain;box-shadow:0 0 25px #000}.navbtn,.closebtn{position:absolute;border:0;background:rgba(0,0,0,.45);color:white;cursor:pointer;border-radius:999px}.navbtn{top:50%;transform:translateY(-50%);font-size:42px;width:58px;height:58px}.prev{left:12px}.next{right:12px}.closebtn{top:12px;right:12px;font-size:30px;width:48px;height:48px}.modal-info{color:white;text-align:center}.modal-name{font-weight:600}.modal-folder{font-size:.9rem;opacity:.75;margin-top:3px}.modal-actions{margin-top:8px}.modal-actions a{color:white}.counter{margin-left:14px;opacity:.75}.modal-backdrop{position:absolute;inset:0}
@media(max-width:700px){.navbtn{width:46px;height:46px;font-size:34px}.prev{left:4px}.next{right:4px}.closebtn{top:4px;right:4px}}
</style></head><body><main class="main">
<h1>Bell Family Archive — Optimized Gallery Test</h1>
<p class="note">Gallery grid uses 400px thumbnails. Click a thumbnail to view it in-page. Use the arrows or keyboard Left/Right keys to move through photos. Escape closes the viewer.</p>
<div class="stats"><strong>$($cards.Count)</strong> complete three-level images &nbsp;·&nbsp; Missing viewer copies: $missingView &nbsp;·&nbsp; Missing originals: $missingOriginal</div>
<div class="grid">$($cards -join "`n")</div>
</main>

<div class="modal" id="viewer" aria-hidden="true">
  <div class="modal-backdrop" id="backdrop"></div>
  <div class="modal-inner" role="dialog" aria-modal="true" aria-label="Photo viewer">
    <div class="modal-stage">
      <img id="modalImage" class="modal-img" src="" alt="">
      <button class="navbtn prev" id="prevBtn" type="button" aria-label="Previous photo">&#10094;</button>
      <button class="navbtn next" id="nextBtn" type="button" aria-label="Next photo">&#10095;</button>
      <button class="closebtn" id="closeBtn" type="button" aria-label="Close viewer">&times;</button>
    </div>
    <div class="modal-info">
      <div><span id="modalName" class="modal-name"></span><span id="counter" class="counter"></span></div>
      <div id="modalFolder" class="modal-folder"></div>
      <div class="modal-actions"><a id="downloadLink" href="" download>Download full resolution</a></div>
    </div>
  </div>
</div>

<script>
const items=[$($items -join ',')];
let current=0;
const viewer=document.getElementById('viewer');
const img=document.getElementById('modalImage');
const nameEl=document.getElementById('modalName');
const folderEl=document.getElementById('modalFolder');
const download=document.getElementById('downloadLink');
const counter=document.getElementById('counter');
function show(i){
  if(!items.length)return;
  current=(i+items.length)%items.length;
  const x=items[current];
  img.src=x.view; img.alt=x.name;
  nameEl.textContent=x.name; folderEl.textContent=x.folder;
  download.href=x.original;
  counter.textContent=(current+1)+' / '+items.length;
  viewer.classList.add('open'); viewer.setAttribute('aria-hidden','false');
  document.body.style.overflow='hidden';
}
function closeViewer(){viewer.classList.remove('open');viewer.setAttribute('aria-hidden','true');img.src='';document.body.style.overflow='';}
function prev(){show(current-1)}
function next(){show(current+1)}
document.querySelectorAll('[data-index]').forEach(el=>el.addEventListener('click',()=>show(Number(el.dataset.index))));
document.getElementById('prevBtn').addEventListener('click',prev);
document.getElementById('nextBtn').addEventListener('click',next);
document.getElementById('closeBtn').addEventListener('click',closeViewer);
document.getElementById('backdrop').addEventListener('click',closeViewer);
document.addEventListener('keydown',e=>{if(!viewer.classList.contains('open'))return;if(e.key==='ArrowLeft')prev();else if(e.key==='ArrowRight')next();else if(e.key==='Escape')closeViewer();});
let touchX=null;
viewer.addEventListener('touchstart',e=>{touchX=e.changedTouches[0].clientX;},{passive:true});
viewer.addEventListener('touchend',e=>{if(touchX===null)return;const dx=e.changedTouches[0].clientX-touchX;if(Math.abs(dx)>50){dx>0?prev():next()}touchX=null;},{passive:true});
</script>
</body></html>
"@

[IO.File]::WriteAllText($Output,$body,[Text.UTF8Encoding]::new($false))
Write-Host "`nOptimized gallery test created."
Write-Host "Cards:             $($cards.Count)"
Write-Host "Missing views:     $missingView"
Write-Host "Missing originals: $missingOriginal"
Write-Host "Viewer:            in-page modal with prev/next arrows + keyboard/swipe"
Write-Host "Output:            $Output"

param(
    [string]$TestRoot = "website-test-v38"
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Root = Join-Path $RepoRoot $TestRoot
$ThumbRoot = Join-Path $Root 'thumbs'
$ViewRoot = Join-Path $Root 'images'
$OriginalRoot = Join-Path $Root 'originals'
$MetadataPath = Join-Path $RepoRoot 'photo_metadata.json'
$Output = Join-Path $Root 'gallery-test.html'

foreach ($p in @($Root,$ThumbRoot,$ViewRoot,$OriginalRoot,$MetadataPath)) {
    if (!(Test-Path -LiteralPath $p)) { throw "Required path not found: $p" }
}

function Html([string]$s) { if ($null -eq $s) { return '' }; return [System.Net.WebUtility]::HtmlEncode($s) }
function UrlPath([string]$s) { return ($s -replace '\\','/') }
function Format-ArchiveDate([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    $v=$value.Trim()
    if ($v -match '^(\d{4})-(\d{2})-(\d{2})') {
        $year=[int]$Matches[1]; $month=[int]$Matches[2]; $day=[int]$Matches[3]
        if ($month -eq 1 -and $day -eq 1) { return "$year" }
        $culture=[System.Globalization.CultureInfo]::GetCultureInfo('en-US')
        $monthName=$culture.DateTimeFormat.GetMonthName($month)
        if ($day -eq 1) { return "$monthName $year" }
        return "$monthName $day, $year"
    }
    if ($v -match '^\d{4}$') { return $v }
    return $v
}
function Format-PeopleDisplay($people) {
    if (!$people) { return '' }
    $out = foreach ($person in @($people)) {
        $p = [string]$person
        if ($p -match '(?i)\s+Bell$') { $p -replace '(?i)\s+Bell$',' B' } else { $p }
    }
    return ($out -join ', ')
}

$StateAbbreviations=@{
'Alabama'='AL';'Alaska'='AK';'Arizona'='AZ';'Arkansas'='AR';'California'='CA';'Colorado'='CO';'Connecticut'='CT';'Delaware'='DE';'Florida'='FL';'Georgia'='GA';'Hawaii'='HI';'Idaho'='ID';'Illinois'='IL';'Indiana'='IN';'Iowa'='IA';'Kansas'='KS';'Kentucky'='KY';'Louisiana'='LA';'Maine'='ME';'Maryland'='MD';'Massachusetts'='MA';'Michigan'='MI';'Minnesota'='MN';'Mississippi'='MS';'Missouri'='MO';'Montana'='MT';'Nebraska'='NE';'Nevada'='NV';'New Hampshire'='NH';'New Jersey'='NJ';'New Mexico'='NM';'New York'='NY';'North Carolina'='NC';'North Dakota'='ND';'Ohio'='OH';'Oklahoma'='OK';'Oregon'='OR';'Pennsylvania'='PA';'Rhode Island'='RI';'South Carolina'='SC';'South Dakota'='SD';'Tennessee'='TN';'Texas'='TX';'Utah'='UT';'Vermont'='VT';'Virginia'='VA';'Washington'='WA';'West Virginia'='WV';'Wisconsin'='WI';'Wyoming'='WY';'District of Columbia'='DC'
}
function Get-StateAbbreviation([string]$state) {
    if ([string]::IsNullOrWhiteSpace($state)) { return '' }
    $s=$state.Trim(); if ($StateAbbreviations.ContainsKey($s)) { return $StateAbbreviations[$s] }
    if ($s -match '^[A-Za-z]{2}$') { return $s.ToUpperInvariant() }; return $s
}
function Get-LocationDisplay($m) {
    if ($null -eq $m) { return '' }
    $parts=New-Object System.Collections.Generic.List[string]
    $sub=if ($m.PSObject.Properties.Name -contains 'location') {[string]$m.location} elseif ($m.PSObject.Properties.Name -contains 'sublocation') {[string]$m.sublocation} else {''}
    $city=if ($m.PSObject.Properties.Name -contains 'city') {[string]$m.city} else {''}
    $stateRaw=if ($m.PSObject.Properties.Name -contains 'state') {[string]$m.state} elseif ($m.PSObject.Properties.Name -contains 'province') {[string]$m.province} else {''}
    $state=Get-StateAbbreviation $stateRaw
    $country=if ($m.PSObject.Properties.Name -contains 'country') {[string]$m.country} else {''}
    foreach ($p in @($sub,$city,$state)) { if (![string]::IsNullOrWhiteSpace($p) -and !$parts.Contains($p.Trim())) {$parts.Add($p.Trim())} }
    if (![string]::IsNullOrWhiteSpace($country)) { $c=$country.Trim(); if ($c -notmatch '^(USA|US|U\.S\.|U\.S\.A\.|United States|United States of America)$' -and !$parts.Contains($c)) {$parts.Add($c)} }
    return ($parts -join ', ')
}
function Get-ExifToolPath {
    $cmd=Get-Command exiftool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($candidate in @(
        'C:\ExifTool\exiftool.exe',
        'C:\Program Files\ExifTool\exiftool.exe',
        'C:\Program Files (x86)\ExifTool\exiftool.exe',
        "$env:USERPROFILE\exiftool.exe"
    )) { if (Test-Path -LiteralPath $candidate) { return $candidate } }
    return $null
}
function Get-PlacesLocationFromFile([string]$ExifTool,[string]$FilePath) {
    if (!$ExifTool -or !(Test-Path -LiteralPath $FilePath)) { return '' }
    try {
        $json = & $ExifTool -json -HierarchicalSubject -Subject -Keywords -TagsList -LastKeywordXMP $FilePath 2>$null
        if (!$json) { return '' }
        $rec = ($json | Out-String | ConvertFrom-Json)[0]
        $all = New-Object System.Collections.Generic.List[string]
        foreach ($prop in @('HierarchicalSubject','Subject','Keywords','TagsList','LastKeywordXMP')) {
            if ($rec.PSObject.Properties.Name -contains $prop) {
                foreach ($v in @($rec.$prop)) { if ($null -ne $v -and ![string]::IsNullOrWhiteSpace([string]$v)) { $all.Add([string]$v) } }
            }
        }
        $best = $null
        foreach ($raw in $all) {
            $s = $raw.Trim() -replace '\\','/' -replace '\|','/'
            if ($s -notmatch '^(?i)Places/') { continue }
            $parts = @($s -split '/' | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
            if ($parts.Count -lt 2) { continue }
            if ($null -eq $best -or $parts.Count -gt $best.Count) { $best = $parts }
        }
        if ($null -eq $best) { return '' }
        $stateRaw = if ($best.Count -ge 2) { $best[1] } else { '' }
        $city = if ($best.Count -ge 3) { $best[2] } else { '' }
        $detail = if ($best.Count -ge 4) { ($best[3..($best.Count-1)] -join ', ') } else { '' }
        $state = Get-StateAbbreviation $stateRaw
        return (@($detail,$city,$state) | Where-Object { ![string]::IsNullOrWhiteSpace($_) }) -join ', '
    } catch { return '' }
}

$metadata=Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
$metaByPath=@{}
foreach ($m in $metadata) { if ($m.path) {$key=([string]$m.path -replace '\\','/').ToLowerInvariant(); $metaByPath[$key]=$m} }
$ExifTool = Get-ExifToolPath
if ($ExifTool) { Write-Host "ExifTool:           $ExifTool" } else { Write-Warning 'ExifTool not found; embedded Places fallback unavailable.' }
$exts=@('.jpg','.jpeg','.png','.tif','.tiff','.webp')
$thumbs=Get-ChildItem -LiteralPath $ThumbRoot -File -Recurse | Where-Object {$exts -contains $_.Extension.ToLowerInvariant()} | Sort-Object FullName
$cards=New-Object System.Collections.Generic.List[string]
$items=New-Object System.Collections.Generic.List[string]
$missingView=0;$missingOriginal=0;$missingMetadata=0;$embeddedLocations=0;$index=0
$sep = ' ' + [char]183 + ' '
foreach ($thumb in $thumbs) {
    $relative=$thumb.FullName.Substring($ThumbRoot.Length).TrimStart('\','/')
    $view=Join-Path $ViewRoot $relative; $original=Join-Path $OriginalRoot $relative
    if (!(Test-Path -LiteralPath $view)) {$missingView++;continue}; if (!(Test-Path -LiteralPath $original)) {$missingOriginal++;continue}
    $thumbUrl='thumbs/'+(UrlPath $relative);$viewUrl='images/'+(UrlPath $relative);$origUrl='originals/'+(UrlPath $relative);$name=[IO.Path]::GetFileName($relative)
    $metaKey=('images/'+(UrlPath $relative)).ToLowerInvariant();$m=$metaByPath[$metaKey];if ($null -eq $m) {$missingMetadata++}
    $title=if ($m -and ![string]::IsNullOrWhiteSpace([string]$m.title)){[string]$m.title}else{''}
    $comments=if ($m -and ![string]::IsNullOrWhiteSpace([string]$m.description)){[string]$m.description}else{''}
    $date=if ($m){Format-ArchiveDate ([string]$m.date)}else{''}
    $people=if ($m){Format-PeopleDisplay $m.people}else{''}
    $location=Get-LocationDisplay $m
    if ([string]::IsNullOrWhiteSpace($location)) {
        $location=Get-PlacesLocationFromFile -ExifTool $ExifTool -FilePath $original
        if (![string]::IsNullOrWhiteSpace($location)) { $embeddedLocations++ }
    }
    $displayTitle=if ($title){$title}else{$name};$metaLine=(@($date,$location,$people)|Where-Object{![string]::IsNullOrWhiteSpace($_)})-join $sep
    $cards.Add(@"
<article class="card"><button class="photo-link" type="button" data-index="$index"><img src="$(Html $thumbUrl)" alt="$(Html $displayTitle)" loading="lazy" decoding="async"></button><div class="copy"><div class="title">$(Html $displayTitle)</div>$(if($metaLine){"<div class=`"meta`">$(Html $metaLine)</div>"})$(if($comments){"<div class=`"comments`">$(Html $comments)</div>"})<div class="file">$(Html $name)</div><div class="actions"><button type="button" data-index="$index">View</button><button type="button" data-download-index="$index">Download full resolution</button></div></div></article>
"@)
    $itemObj=[ordered]@{view=$viewUrl;original=$origUrl;name=$name;title=$displayTitle;date=$date;location=$location;people=$people;comments=$comments}
    $items.Add(($itemObj | ConvertTo-Json -Compress));$index++
}
$body=@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Optimized Gallery Test - Bell Family Archive</title><style>
body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#f4f2ed;color:#242424}.main{max-width:1500px;margin:auto;padding:28px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px}.card{background:white;border-radius:12px;overflow:hidden;box-shadow:0 2px 10px #0002}.photo-link{display:block;width:100%;border:0;padding:0;background:#e7e7e7;cursor:pointer}.card img{display:block;width:100%;height:220px;object-fit:contain}.copy{padding:12px}.title{font-weight:650}.meta{font-size:.88rem;color:#666;margin-top:5px}.comments{font-size:.9rem;line-height:1.35;margin-top:8px;white-space:pre-line}.file{font-size:.78rem;color:#888;margin-top:9px}.actions{display:flex;gap:12px;flex-wrap:wrap;margin-top:10px}.actions button{border:0;background:none;color:#06c;text-decoration:underline;padding:0;cursor:pointer}.modal{position:fixed;inset:0;background:rgba(0,0,0,.88);display:none;align-items:center;justify-content:center;z-index:9999}.modal.open{display:flex}.modal-inner{position:relative;width:min(96vw,1500px);height:min(94vh,1000px);display:grid;grid-template-rows:1fr auto;gap:10px}.modal-stage{position:relative;display:flex;align-items:center;justify-content:center;min-height:0}.modal-img{max-width:100%;max-height:100%;object-fit:contain}.navbtn,.closebtn{position:absolute;border:0;background:rgba(0,0,0,.45);color:white;cursor:pointer;border-radius:999px}.navbtn{top:50%;transform:translateY(-50%);font-size:42px;width:58px;height:58px}.prev{left:12px}.next{right:12px}.closebtn{top:12px;right:12px;font-size:30px;width:48px;height:48px}.modal-info{color:white;text-align:center}.modal-meta{font-size:.9rem;opacity:.8;margin-top:3px}.modal-comments{font-size:.9rem;margin:6px auto 0;max-width:900px;white-space:pre-line}.modal-actions button{border:0;background:none;color:white;text-decoration:underline;cursor:pointer;font:inherit}.modal-backdrop{position:absolute;inset:0}
</style></head><body><main class="main"><h1>Bell Family Archive - Optimized Gallery Test</h1><p>Gallery uses 400px thumbnails. Click a thumbnail to view it in-page.</p><div class="grid">$($cards -join "`n")</div></main>
<div class="modal" id="viewer"><div class="modal-backdrop" id="backdrop"></div><div class="modal-inner"><div class="modal-stage"><img id="modalImage" class="modal-img"><button class="navbtn prev" id="prevBtn">&#10094;</button><button class="navbtn next" id="nextBtn">&#10095;</button><button class="closebtn" id="closeBtn">&times;</button></div><div class="modal-info"><div id="modalName"></div><div id="modalMeta" class="modal-meta"></div><div id="modalComments" class="modal-comments"></div><div class="modal-actions"><button id="downloadButton">Download full resolution</button></div></div></div></div>
<script>
const items=[$($items -join ',')];let current=0;const viewer=document.getElementById('viewer'),img=document.getElementById('modalImage'),nameEl=document.getElementById('modalName'),metaEl=document.getElementById('modalMeta'),commentsEl=document.getElementById('modalComments');const sep=' '+String.fromCharCode(183)+' ';
function show(i){if(!items.length)return;current=(i+items.length)%items.length;const x=items[current];img.src=x.view;img.alt=x.title||x.name;nameEl.textContent=x.title||x.name;metaEl.textContent=[x.date,x.location,x.people].filter(Boolean).join(sep);commentsEl.textContent=x.comments||'';viewer.classList.add('open');document.body.style.overflow='hidden'}
function closeViewer(){viewer.classList.remove('open');img.src='';document.body.style.overflow=''}function prev(){show(current-1)}function next(){show(current+1)}
async function forceDownload(url,filename){try{const r=await fetch(url,{cache:'no-store'});if(!r.ok)throw new Error('download failed');const b=await r.blob(),u=URL.createObjectURL(b),a=document.createElement('a');a.href=u;a.download=filename||'photo';a.style.display='none';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(u),3000);return}catch(e){const a=document.createElement('a');a.href=url;a.download=filename||'photo';a.style.display='none';document.body.appendChild(a);a.click();a.remove()}}
document.querySelectorAll('[data-index]').forEach(el=>el.addEventListener('click',()=>show(Number(el.dataset.index))));document.querySelectorAll('[data-download-index]').forEach(el=>el.addEventListener('click',e=>{e.stopPropagation();const x=items[Number(el.dataset.downloadIndex)];forceDownload(x.original,x.name)}));document.getElementById('downloadButton').onclick=()=>{const x=items[current];forceDownload(x.original,x.name)};document.getElementById('prevBtn').onclick=prev;document.getElementById('nextBtn').onclick=next;document.getElementById('closeBtn').onclick=closeViewer;document.getElementById('backdrop').onclick=closeViewer;document.addEventListener('keydown',e=>{if(!viewer.classList.contains('open'))return;if(e.key==='ArrowLeft')prev();else if(e.key==='ArrowRight')next();else if(e.key==='Escape')closeViewer()});
</script></body></html>
"@
[IO.File]::WriteAllText($Output,$body,[Text.UTF8Encoding]::new($false))
Write-Host "`nOptimized gallery test created."
Write-Host "Cards:                 $($cards.Count)"
Write-Host "Missing views:         $missingView"
Write-Host "Missing originals:     $missingOriginal"
Write-Host "Missing metadata:      $missingMetadata"
Write-Host "Embedded Places used:  $embeddedLocations"
Write-Host "People display:        Bell abbreviated to B (source tags unchanged)"
Write-Host "Location:              photo metadata first, then DigiKam Places fallback"
Write-Host "Output:                $Output"
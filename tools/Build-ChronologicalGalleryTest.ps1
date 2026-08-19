param([string]$TestRoot='website-test-v38')
$ErrorActionPreference='Stop'
$RepoRoot=Split-Path -Parent $PSScriptRoot
$Root=Join-Path $RepoRoot $TestRoot
$ThumbRoot=Join-Path $Root 'thumbs'
$ViewRoot=Join-Path $Root 'images'
$OriginalRoot=Join-Path $Root 'originals'
$Output=Join-Path $Root 'gallery-chronological-test.html'
foreach($p in @($ThumbRoot,$ViewRoot,$OriginalRoot)){if(!(Test-Path -LiteralPath $p)){throw "Missing: $p"}}

function HtmlEncode([string]$s){[System.Net.WebUtility]::HtmlEncode([string]$s)}
function UrlPath([string]$s){$s-replace '\\','/'}
function Get-ExifToolPath {
    $cmd=Get-Command exiftool.exe -ErrorAction SilentlyContinue
    if($cmd){return $cmd.Source}
    foreach($c in @('C:\ExifTool\exiftool.exe','C:\Program Files\ExifTool\exiftool.exe','C:\Program Files (x86)\ExifTool\exiftool.exe',"$env:USERPROFILE\exiftool.exe")){if(Test-Path -LiteralPath $c){return $c}}
    throw 'ExifTool was not found.'
}
$ExifTool=Get-ExifToolPath

$StateAbbr=@{
'Alabama'='AL';'Alaska'='AK';'Arizona'='AZ';'Arkansas'='AR';'California'='CA';'Colorado'='CO';'Connecticut'='CT';'Delaware'='DE';'Florida'='FL';'Georgia'='GA';'Hawaii'='HI';'Idaho'='ID';'Illinois'='IL';'Indiana'='IN';'Iowa'='IA';'Kansas'='KS';'Kentucky'='KY';'Louisiana'='LA';'Maine'='ME';'Maryland'='MD';'Massachusetts'='MA';'Michigan'='MI';'Minnesota'='MN';'Mississippi'='MS';'Missouri'='MO';'Montana'='MT';'Nebraska'='NE';'Nevada'='NV';'New Hampshire'='NH';'New Jersey'='NJ';'New Mexico'='NM';'New York'='NY';'North Carolina'='NC';'North Dakota'='ND';'Ohio'='OH';'Oklahoma'='OK';'Oregon'='OR';'Pennsylvania'='PA';'Rhode Island'='RI';'South Carolina'='SC';'South Dakota'='SD';'Tennessee'='TN';'Texas'='TX';'Utah'='UT';'Vermont'='VT';'Virginia'='VA';'Washington'='WA';'West Virginia'='WV';'Wisconsin'='WI';'Wyoming'='WY';'District of Columbia'='DC'
}
function State([string]$s){if(!$s){return ''};$s=$s.Trim();if($StateAbbr.ContainsKey($s)){return $StateAbbr[$s]};if($s-match'^[A-Za-z]{2}$'){return $s.ToUpper()};return $s}
function ArchiveDate([string]$v){
    if(!$v){return ''};$v=$v.Trim()
    if($v-match'^(\d{4})[:\-](\d{2})[:\-](\d{2})'){$y=[int]$Matches[1];$m=[int]$Matches[2];$d=[int]$Matches[3];if($m-eq 1-and$d-eq 1){return "$y"};$mn=[Globalization.CultureInfo]::GetCultureInfo('en-US').DateTimeFormat.GetMonthName($m);if($d-eq 1){return "$mn $y"};return "$mn $d, $y"}
    if($v-match'^\d{4}$'){return $v};return $v
}
function SortKey([string]$v,[string]$name){if($v-match'^(\d{4})[:\-](\d{2})[:\-](\d{2})'){return ('{0:D4}{1:D2}{2:D2}|{3}'-f [int]$Matches[1],[int]$Matches[2],[int]$Matches[3],$name.ToLower())};if($v-match'^\d{4}$'){return "$v`0101|$($name.ToLower())"};return "99999999|$($name.ToLower())"}
function CleanLoc([string]$s){if(!$s){return ''};$s=$s.Trim();if($s-match'(?i)^Mason St Orig Bell Family Home$'){return 'Mason St'};return $s}
function ReadMeta([string]$file){
    $json=& $ExifTool -json -DateTimeOriginal -CreateDate -DateCreated -Title -Description -Caption-Abstract -Location -Sublocation -City -State -Province-State -Country -Country-PrimaryLocationName -HierarchicalSubject -Subject -Keywords -TagsList -LastKeywordXMP $file 2>$null
    if(!$json){return $null};return (($json|Out-String|ConvertFrom-Json)[0])
}
function First($m,[string[]]$names){foreach($n in $names){if($m.PSObject.Properties.Name-contains$n){$v=$m.$n;if($null-ne$v-and![string]::IsNullOrWhiteSpace([string]$v)){return [string]$v}}};return ''}
function GetTags($m){
    $all=New-Object System.Collections.Generic.List[string]
    foreach($n in @('HierarchicalSubject','Subject','Keywords','TagsList','LastKeywordXMP')){if($m.PSObject.Properties.Name-contains$n){foreach($v in @($m.$n)){if($null-ne$v-and![string]::IsNullOrWhiteSpace([string]$v)){$all.Add([string]$v)}}}}
    return @($all)
}
function GetPeople([string[]]$tags){
    $out=New-Object System.Collections.Generic.List[string]
    foreach($raw in $tags){$s=$raw.Trim()-replace'\\','/'-replace'\|','/';if($s-match'^(?i)People/'){$p=($s-split'/')[-1].Trim();if($p -match'(?i)\s+Bell$'){$p=$p-replace'(?i)\s+Bell$',' B'};if($p-and!$out.Contains($p)){$out.Add($p)}}}
    return ($out -join ', ')
}
function GetPlace([string[]]$tags,$m){
    $best=$null
    foreach($raw in $tags){$s=$raw.Trim()-replace'\\','/'-replace'\|','/';if($s-notmatch'^(?i)Places/'){continue};$parts=@($s-split'/'|Where-Object{$_});if($null-eq$best-or$parts.Count-gt$best.Count){$best=$parts}}
    if($best){$st=if($best.Count-ge2){State $best[1]}else{''};$city=if($best.Count-ge3){$best[2]}else{''};$detail=if($best.Count-ge4){CleanLoc (($best[3..($best.Count-1)]-join', '))}else{''};return ((@($detail,$city,$st)|Where-Object{$_})-join', ')}
    $loc=CleanLoc (First $m @('Location','Sublocation'));$city=First $m @('City');$st=State (First $m @('State','Province-State'));return ((@($loc,$city,$st)|Where-Object{$_})-join', ')
}

$exts=@('.jpg','.jpeg','.png','.tif','.tiff','.webp')
$rows=New-Object System.Collections.Generic.List[object]
$counter=0
foreach($t in Get-ChildItem -LiteralPath $ThumbRoot -File -Recurse|Where-Object{$exts-contains$_.Extension.ToLowerInvariant()}){
    $rel=$t.FullName.Substring($ThumbRoot.Length).TrimStart('\','/');$orig=Join-Path $OriginalRoot $rel;$view=Join-Path $ViewRoot $rel
    if(!(Test-Path -LiteralPath $orig)-or!(Test-Path -LiteralPath $view)){continue}
    $m=ReadMeta $orig;if($null-eq$m){continue};$tags=GetTags $m
    $rawDate=First $m @('DateTimeOriginal','DateCreated','CreateDate');if($rawDate-match'^(.{10})'){$rawDate=$Matches[1]}
    $title=First $m @('Title');if(!$title){$title=[IO.Path]::GetFileName($rel)}
    $desc=First $m @('Description','Caption-Abstract')
    $people=GetPeople $tags;$loc=GetPlace $tags $m
    $rows.Add([pscustomobject]@{Rel=$rel;Name=[IO.Path]::GetFileName($rel);Title=$title;Desc=$desc;DateRaw=$rawDate;Date=(ArchiveDate $rawDate);Location=$loc;People=$people;Key=(SortKey $rawDate ([IO.Path]::GetFileName($rel)) )})
    $counter++;if(($counter%25)-eq0){Write-Host "Read embedded metadata: $counter"}
}
$rows=@($rows|Sort-Object Key)
$cards=New-Object System.Collections.Generic.List[string];$items=New-Object System.Collections.Generic.List[string];$i=0
foreach($r in $rows){$thumb='thumbs/'+(UrlPath $r.Rel);$view='images/'+(UrlPath $r.Rel);$orig='originals/'+(UrlPath $r.Rel);$cards.Add("<article class='card'><button class='pic' data-i='$i'><img src='$(HtmlEncode $thumb)' loading='lazy'></button><div class='copy'><h3>$(HtmlEncode $r.Title)</h3>$(if($r.Date){"<div class='meta'>$(HtmlEncode $r.Date)</div>"})$(if($r.Location){"<div class='meta'>$(HtmlEncode $r.Location)</div>"})$(if($r.People){"<div class='meta'>$(HtmlEncode $r.People)</div>"})$(if($r.Desc){"<p>$(HtmlEncode $r.Desc)</p>"})<div class='file'>$(HtmlEncode $r.Name)</div><div class='actions'><button data-i='$i'>View</button><a href='$(HtmlEncode $orig)' download>Download full resolution</a></div></div></article>");$items.Add(([ordered]@{view=$view;orig=$orig;title=$r.Title;date=$r.Date;location=$r.Location;people=$r.People;description=$r.Desc;name=$r.Name}|ConvertTo-Json -Compress));$i++}
$html=@"
<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Chronological Gallery Test</title><style>body{font-family:Segoe UI,Arial,sans-serif;margin:0;background:#f5f5f5}.main{max-width:1500px;margin:auto;padding:28px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:18px}.card{background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 10px #0002}.pic{width:100%;border:0;padding:0;background:#eee}.pic img{width:100%;height:230px;object-fit:contain;display:block}.copy{padding:12px}.copy h3{margin:0 0 7px}.meta{font-size:.9rem;line-height:1.45;color:#555}.copy p{white-space:pre-line}.file{font-size:.78rem;color:#888;margin-top:8px}.actions{display:flex;gap:12px;margin-top:9px}.actions button{border:0;background:none;color:#06c;text-decoration:underline;padding:0}.modal{position:fixed;inset:0;background:#000e;display:none;align-items:center;justify-content:center;z-index:10}.modal.open{display:flex}.inner{width:96vw;height:94vh;display:grid;grid-template-rows:1fr auto}.stage{position:relative;display:flex;align-items:center;justify-content:center}.stage img{max-width:100%;max-height:100%;object-fit:contain}.nav,.close{position:absolute;border:0;border-radius:50%;background:#0008;color:#fff}.nav{top:50%;transform:translateY(-50%);font-size:40px;width:56px;height:56px}.prev{left:12px}.next{right:12px}.close{right:12px;top:12px;font-size:28px;width:46px;height:46px}.info{color:#fff;text-align:center;padding:8px}.line{margin:2px 0}</style></head><body><main class='main'><h1>Chronological Gallery Test</h1><p>Oldest first. Metadata is read directly from the refreshed originals in website-test-v38.</p><div class='grid'>$($cards -join "`n")</div></main><div class='modal' id='m'><div class='inner'><div class='stage'><img id='mi'><button class='nav prev' id='p'>&#10094;</button><button class='nav next' id='n'>&#10095;</button><button class='close' id='c'>&times;</button></div><div class='info'><h3 id='mt'></h3><div class='line' id='md'></div><div class='line' id='ml'></div><div class='line' id='mp'></div><div class='line' id='mc'></div></div></div></div><script>const x=[$($items -join ',')];let k=0;const m=document.getElementById('m');function show(i){k=(i+x.length)%x.length;const a=x[k];mi.src=a.view;mt.textContent=a.title;md.textContent=a.date||'';ml.textContent=a.location||'';mp.textContent=a.people||'';mc.textContent=a.description||'';m.classList.add('open')}document.querySelectorAll('[data-i]').forEach(e=>e.onclick=()=>show(+e.dataset.i));p.onclick=()=>show(k-1);n.onclick=()=>show(k+1);c.onclick=()=>m.classList.remove('open');document.onkeydown=e=>{if(!m.classList.contains('open'))return;if(e.key==='ArrowLeft')show(k-1);if(e.key==='ArrowRight')show(k+1);if(e.key==='Escape')m.classList.remove('open')}</script></body></html>
"@
[IO.File]::WriteAllText($Output,$html,[Text.UTF8Encoding]::new($false))
Write-Host "Created: $Output"
Write-Host "Cards:   $($rows.Count)"
Write-Host "Source:  embedded metadata from website-test-v38/originals"
Write-Host "Order:   chronological ascending (unknown dates last)"

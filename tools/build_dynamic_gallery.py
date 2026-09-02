#!/usr/bin/env python3
import json, html, pathlib, re, urllib.parse
from datetime import datetime

ROOT=pathlib.Path(__file__).resolve().parents[1]
DATA=json.loads((ROOT/'photo_metadata.json').read_text(encoding='utf-8'))
HOBBY_MEMBERSHIP_PATH=ROOT/'hobby_tag_membership.json'
HOBBY_SNAPSHOT=json.loads(HOBBY_MEMBERSHIP_PATH.read_text(encoding='utf-8')) if HOBBY_MEMBERSHIP_PATH.exists() else {'memberships':{},'taggedCounts':{},'publicCounts':{}}
STATE_ABBR={'Florida':'FL','Georgia':'GA','North Carolina':'NC','South Carolina':'SC','Virginia':'VA','Tennessee':'TN','New York':'NY','Pennsylvania':'PA','Maryland':'MD','Alabama':'AL','Mississippi':'MS','Texas':'TX','California':'CA','Ohio':'OH','West Virginia':'WV'}

def esc(v): return html.escape(str(v or ''),quote=True)
def url(v): return urllib.parse.quote(str(v or ''),safe='/')
def nice_date(v):
    if not v:return 'Date unknown'
    if re.fullmatch(r'\d{4}',v):return f'Circa {v}'
    try:
        dt=datetime.strptime(v,'%Y-%m-%d')
        if dt.month==1 and dt.day==1:return f'Circa {dt.year}'
        if dt.day==1:return f"Circa {dt.strftime('%B %Y')}"
        return dt.strftime('%B %d, %Y').replace(' 0',' ')
    except Exception:return v

def date_sort_key(x):
    v=str(x.get('date') or '').strip();name=str(x.get('path') or '').lower()
    if re.fullmatch(r'\d{4}',v):return(0,f'{v}-01-01',name)
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}',v):return(0,v,name)
    folder=str(x.get('folder') or '')
    if re.fullmatch(r'\d{4}',folder):return(1,f'{folder}-12-31',name)
    return(2,'9999-12-31',name)

def display_people(values):return ', '.join(re.sub(r'\s+Bell$',' B',str(p),flags=re.I) for p in(values or []))
HOUSE_NUMBER_RE=re.compile(r'^\s*\d+[A-Za-z]?(?:\s*[-/]\s*\d+[A-Za-z]?)?\s+(?=.*\b(?:Ave(?:nue)?|St(?:reet)?|Rd|Road|Ln|Lane|Dr|Drive|Blvd|Boulevard|Ct|Court|Way|Hwy|Highway|Pkwy|Parkway|Cir|Circle|Ter|Terrace)\b)',re.I)
def strip_house_number(value):return HOUSE_NUMBER_RE.sub('',str(value or '').strip())
def clean_location_label(value):
    v=strip_house_number(value)
    return {'Mason St Orig Bell Family Home':'Mason St','Mason St Original Bell Family Home':'Mason St','Mason Street Orig Bell Family Home':'Mason St','Mason Street Original Bell Family Home':'Mason St'}.get(v,v)
def clean_tag_label(value):
    parts=[]
    for part in re.split(r'([/|\\])',str(value or '')):
        if part in {'/','|','\\'}: parts.append(part)
        else:
            label=strip_house_number(part)
            parts.append('Xavier Lear' if label.casefold()=='xavier charles lear' else label)
    return ''.join(parts)
def display_location(x):
    parts=[];loc=clean_location_label(x.get('location'));city=clean_location_label(x.get('city'));state=str(x.get('state') or '').strip();country=str(x.get('country') or '').strip()
    if state in STATE_ABBR:state=STATE_ABBR[state]
    elif re.fullmatch(r'[A-Za-z]{2}',state):state=state.upper()
    for p in(loc,city,state):
        if p and p not in parts:parts.append(p)
    if country and country.lower() not in {'usa','us','u.s.','u.s.a.','united states','united states of america'} and country not in parts:parts.append(country)
    return ', '.join(parts)

def media_paths(x):
    p=str(x.get('path') or '').replace('\\','/')
    if x.get('media_type') in {'video','audio'} or p.startswith(('videos/','audio/')):
        return (p,p,p)
    rel=p[7:] if p.startswith('images/') else p
    return ('thumbs/'+rel if(ROOT/'thumbs'/rel).exists() else p,
            'images/'+rel if(ROOT/'images'/rel).exists() else p,
            'highres/'+rel if(ROOT/'highres'/rel).exists() else p)

def page(title,subtitle,items,filename,empty_html=''):
    ordered=sorted(items,key=date_sort_key);years={}
    for x in ordered:
        d=str(x.get('date') or '')
        y=d[:4] if re.match(r'^\d{4}',d) else (x.get('folder') if re.fullmatch(r'\d{4}',str(x.get('folder') or '')) else 'Unknown')
        years.setdefault(y,[]).append(x)

    viewer=[];sections=[];idx=0
    for y in sorted(years,key=lambda z:(z=='Unknown',z)):
        cards=[]
        for x in years[y]:
            t,v,o=media_paths(x)
            is_video=(x.get('media_type')=='video' or str(x.get('path') or '').startswith('videos/'))
            is_audio=(x.get('media_type')=='audio' or str(x.get('path') or '').startswith('audio/'))
            ttl=str(x.get('title') or '').strip();desc='\n'.join(line.rstrip() for line in str(x.get('description') or '').strip().splitlines())
            date=nice_date(str(x.get('date') or ''));loc=display_location(x);ppl=display_people(x.get('people'))
            fn=str(x.get('file') or pathlib.PurePosixPath(str(x.get('path') or '')).name)
            lines=[f'<div class="archive-meta-line">{esc(date)}</div>']
            if loc:lines.append(f'<div class="archive-meta-line">{esc(loc)}</div>')
            if ppl:lines.append(f'<div class="archive-meta-line">{esc(ppl)}</div>')
            th=f'<h3>{esc(ttl)}</h3>' if ttl else ''
            if is_video:
                media=f'<div class="archive-video-wrap"><video controls preload="metadata" playsinline src="{esc(url(v))}">Your browser does not support this video.</video><div class="archive-video-label">Video</div></div>'
                actions=f'<div class="archive-actions"><a href="{esc(url(o))}" download>Download video</a></div>'
            elif is_audio:
                media=f'<div class="archive-audio-wrap"><div class="archive-audio-label">Sound</div><audio controls preload="metadata" src="{esc(url(v))}">Your browser does not support this audio.</audio></div>'
                actions=f'<div class="archive-actions"><a href="{esc(url(o))}" download>Download audio</a></div>'
            else:
                media=f'<button class="archive-pic" data-view-i="{idx}"><img src="{esc(url(t))}" alt="{esc(ttl or "Archive photo")}" loading="lazy"></button>'
                actions=f'<div class="archive-actions"><button data-view-i="{idx}">View</button><a href="{esc(url(o))}" download>Download high resolution</a></div>'
            card_class='archive-card archive-card-wide' if len(desc) >= 240 else 'archive-card'
            cards.append(f'''<article class="{card_class}" data-i="{idx}">{media}<div class="archive-copy">{th}<div class="archive-meta">{''.join(lines)}</div>{f'<p>{esc(desc)}</p>' if desc else ''}<div class="archive-file">{esc(fn)}</div>{actions}</div></article>''')
            viewer.append({'view':url(v),'orig':url(o),'title':ttl,'date':date,'location':loc,'people':ppl,'people_raw':x.get('people') or [],'categories':x.get('categories') or [],'tags':[clean_tag_label(tag) for tag in x.get('tags') or []],'description':desc,'name':fn,'media_type':'video' if is_video else ('audio' if is_audio else 'photo')})
            idx+=1
        sections.append(f'<section class="archive-year"><h2>{esc(y)}</h2><div class="archive-grid">{"".join(cards)}</div></section>')

    jsdata=json.dumps(viewer,ensure_ascii=False).replace('</','<\\/')
    base_person=None
    if filename.endswith('-photos.html') and filename!='gallery.html':
        slug=filename[:-12]
        base_person={'dickey':'Dickey Bell','spooky':'Spooky Bell','buster':'Buster Bell','alma':'Alma Bell','rickey':'Rickey Bell','sonja':'Sonja Bell','heather':'Heather Bell','helen':'Helen Bell','stephanie':'Stephanie Bell','jarred':'Jarred Bell','samatha':'Samatha Bell','ivy':'Ivy Bell','olivia':'Olivia Bell','sophia':'Sophia Bell','dominique':'Dominique Burwell','debbie':'Debbie Phillips','irvin':'Irvin Phillips','rickii':'Rickii Lear','breana':'Anna Lear','xavier':'Xavier Lear','donna':'Donna Brown','charlie':'Charlie Brown','jason':'Jason Hoke','mike-morgan':'Mike Morgan','teri-wallace':'Teri Wallace','mickey-morgan':'Mickey Morgan','andrew-morgan':'Andrew Morgan','teresa-cooper':'Teresa Cooper','carla-pittman':'Carla Pittman','dick-bell':'Dick Bell','rachel-bell':'Rachel Bell','johnny-tharp':'Johnny Tharp','everate-faulkenberry':'Everate Faulkenberry','peggy-faulkenberry':'Peggy Faulkenberry','lisa-steen':'Lisa Steen','macey-steen':'Macey Steen','kathleen-brown':'Kathleen Brown','tony-neely':'Tony Neely','alice-neely':'Alice Neely','tim-neely':'Tim Neely','cindy-neely':'Cindy Green','ken-brown':'Ken Brown','mary-ellen-whitaker':'Mary Ellen Whitaker'}.get(slug)
    if filename.endswith('-photos.html') and filename!='gallery.html' and slug == 'karen-gaskin': base_person='Karen Gaskin'
    person_label=f'Person &mdash; with {esc(base_person)}' if base_person else 'Person'
    person_all=f'Anyone with {esc(base_person)}' if base_person else 'All people'
    person_context=(f'<div class="archive-filter-context">This album already shows items containing <strong>{esc(base_person)}</strong>. Choosing a person below narrows it to items containing both people.</div>' if base_person else '')
    sidebar=f'''<aside class="archive-sidebar" id="archiveSidebar"><div class="archive-filter-title">Filter archive</div>{person_context}<label>Search<input id="filterSearch" type="search" placeholder="Name, place, filename, tag..."></label><label>{person_label}<select id="filterPerson"><option value="">{person_all}</option></select></label><label>Location<select id="filterLocation"><option value="">All locations</option></select></label><div class="archive-type-filter"><div class="archive-type-label">Type</div><div id="filterTypeChecks" class="archive-type-checks"></div></div><label>Tag<select id="filterTag"><option value="">All tags</option></select></label><button id="clearArchiveFilters" type="button">Clear filters</button><div class="archive-filter-count"><span id="visibleArchiveCount">0</span> shown</div><div class="archive-year-title">Years</div><nav class="archive-year-nav" id="archiveYearNav"></nav></aside>'''

    results=empty_html if empty_html else f'<div class="archive-shell">{sidebar}<div class="archive-results">{"".join(sections)}</div></div>'
    body=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc(title)} &mdash; The Bell Family</title><link rel="stylesheet" href="style.css"><style>
.archive-main{{max-width:1600px;margin:auto;padding:28px}}.archive-shell{{display:grid;grid-template-columns:220px minmax(0,1fr);gap:24px;align-items:start}}.archive-sidebar{{position:sticky;top:14px;max-height:calc(100vh - 28px);overflow:auto;background:#fff;border:1px solid #ddd;border-radius:10px;padding:14px;box-shadow:0 2px 10px #0001}}.archive-sidebar label{{display:block;font-size:.86rem;font-weight:600;margin:10px 0}}.archive-sidebar input,.archive-sidebar select{{display:block;width:100%;box-sizing:border-box;margin-top:4px;padding:7px;border:1px solid #bbb;border-radius:6px;background:#fff}}.archive-sidebar button{{width:100%;padding:8px;margin-top:8px;border:1px solid #999;border-radius:6px;background:#f7f7f7;cursor:pointer}}.archive-filter-title,.archive-year-title{{font-weight:700;margin-bottom:6px}}.archive-filter-context{{font-size:.82rem;line-height:1.35;padding:8px 9px;margin:6px 0 10px;background:#f5f5f5;border-radius:6px}}.archive-type-filter{{margin:10px 0}}.archive-type-label{{font-size:.86rem;font-weight:600;margin-bottom:5px}}.archive-type-checks{{display:grid;gap:4px}}.archive-type-checks label{{display:flex;align-items:center;gap:3px;margin:0;font-size:.86rem;font-weight:400;cursor:pointer}}.archive-type-checks input{{width:auto;margin:0}}.archive-year-title{{margin-top:16px}}.archive-filter-count{{font-size:.85rem;opacity:.7;margin-top:8px}}.archive-year-nav{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:4px 8px}}.archive-year-nav a{{text-decoration:none;padding:3px 0}}.archive-results{{min-width:0}}.archive-grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:18px}}.archive-card[hidden],.archive-year[hidden]{{display:none!important}}.archive-card{{background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px #0002}}.archive-card-wide{{grid-column:span 3;display:grid;grid-template-columns:minmax(240px,1fr) minmax(0,2fr)}}.archive-card-wide>.archive-pic,.archive-card-wide>.archive-video-wrap,.archive-card-wide>.archive-audio-wrap{{height:100%;min-height:240px}}.archive-card-wide>.archive-pic img,.archive-card-wide>.archive-video-wrap video{{height:100%;min-height:240px;max-height:460px}}.archive-pic{{width:100%;padding:0;border:0;background:#eee;cursor:pointer}}.archive-pic img{{width:100%;height:240px;object-fit:contain;display:block}}.archive-video-wrap{{position:relative;background:#111}}.archive-video-wrap video{{width:100%;height:240px;display:block;background:#000;object-fit:contain}}.archive-video-label{{position:absolute;left:9px;top:9px;background:#000b;color:#fff;padding:4px 7px;border-radius:5px;font-size:.78rem}}.archive-audio-wrap{{min-height:150px;background:#eee;display:flex;flex-direction:column;justify-content:center;gap:18px;padding:22px;box-sizing:border-box}}.archive-audio-wrap audio{{width:100%}}.archive-audio-label{{font-weight:700}}.archive-copy{{padding:12px}}.archive-copy h3{{margin:0 0 6px;font-size:1rem}}.archive-meta{{font-size:.88rem;opacity:.78;line-height:1.4}}.archive-meta-line{{display:block}}.archive-file{{font-size:.82rem;opacity:.65;margin-top:8px}}.archive-copy p{{white-space:pre-line}}.archive-year{{margin:32px 0}}.archive-year>h2{{border-bottom:1px solid #ccc;padding-bottom:6px}}.archive-actions{{display:flex;gap:12px;align-items:center;margin-top:9px}}.archive-actions button{{border:0;padding:0;background:none;color:#06c;text-decoration:underline;cursor:pointer}}.archive-actions a{{color:#06c}}
.viewer{{position:fixed;inset:0;background:#000e;display:none;z-index:9999;color:#fff}}.viewer.open{{display:grid;grid-template-rows:minmax(0,1fr) auto}}.viewer-stage{{position:relative;overflow:auto;display:block;min-width:0;min-height:0;padding:0;box-sizing:border-box;cursor:default;scrollbar-gutter:stable both-edges}}.viewer-stage.pannable{{cursor:grab}}.viewer-stage.dragging{{cursor:grabbing;user-select:none}}.viewer-canvas{{position:relative;min-width:100%;min-height:100%;box-sizing:border-box}}.viewer-stage img{{position:absolute;display:block;max-width:none;max-height:none;user-select:none;-webkit-user-drag:none}}.viewer-nav,.viewer-close{{position:fixed;border:0;border-radius:50%;background:#0009;color:#fff;cursor:pointer;z-index:10001}}.viewer-nav{{top:50%;transform:translateY(-50%);font-size:38px;width:54px;height:54px}}.viewer-prev{{left:12px}}.viewer-next{{right:12px}}.viewer-close{{right:14px;top:14px;font-size:28px;width:46px;height:46px}}.viewer-controls{{position:fixed;top:14px;left:50%;transform:translateX(-50%);display:flex;gap:8px;z-index:10001}}.viewer-controls button{{border:0;border-radius:6px;padding:8px 13px;font-size:18px;cursor:pointer}}.viewer-info{{text-align:center;padding:8px 70px 14px;background:#0008}}.viewer-info h3{{margin:0 0 5px}}.viewer-line{{margin:2px 0}}@media(max-width:900px){{.archive-shell{{grid-template-columns:1fr}}.archive-sidebar{{position:relative;top:auto;max-height:none}}}}@media(max-width:650px){{.archive-card-wide{{grid-column:span 1;display:block}}.archive-card-wide>.archive-pic,.archive-card-wide>.archive-video-wrap,.archive-card-wide>.archive-audio-wrap{{height:auto;min-height:0}}.archive-card-wide>.archive-pic img,.archive-card-wide>.archive-video-wrap video{{height:240px;min-height:0;max-height:none}}.viewer-info{{padding-left:12px;padding-right:12px}}}}
@media(max-width:780px){{.archive-card-wide{{grid-column:span 1;display:block}}.archive-card-wide>.archive-pic,.archive-card-wide>.archive-video-wrap,.archive-card-wide>.archive-audio-wrap{{height:auto;min-height:0}}.archive-card-wide>.archive-pic img,.archive-card-wide>.archive-video-wrap video{{height:240px;min-height:0;max-height:none}}}}
</style></head><body><header class="site-header"><a class="brand brand-home" href="index.html" aria-label="Bell Family home"><div class="tree-mark" aria-hidden="true"><svg class="tree-logo" viewBox="0 0 72 72" aria-hidden="true"><path d="M13 31C7 25 12 15 22 17C24 8 37 7 42 14C51 9 61 17 58 26C66 31 60 43 51 42H20C10 44 5 36 13 31Z" fill="currentColor" opacity=".95"/><path d="M34 62C34 53 35 45 31 37M38 62C38 53 37 45 43 37M36 46L25 35M37 44L49 32M36 62L24 68M36 62L48 68M36 61L31 69M37 61L42 69" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/></svg></div><div><div class="brand-title">The Bell Family</div><div class="brand-tagline">Generations of Love, Memories &amp; Legacy</div></div></a><nav class="top-nav"><a href="index.html">Family Tree</a><a href="gallery.html">Photo Gallery</a></nav></header><main class="archive-main"><span class="eyebrow">Bell Family Archive</span><h1>{esc(title)}</h1><p>{esc(subtitle)}</p><p><strong>{len(items)} archive items</strong></p>{results}</main><footer>&copy; 2026 The Bell Family Archive &middot; Preserving Our Legacy for Future Generations</footer>
<div class="viewer" id="viewer"><div class="viewer-stage" id="viewerStage"><div class="viewer-canvas" id="viewerCanvas"><img id="viewerImg"></div><button class="viewer-nav viewer-prev" id="viewerPrev">&#10094;</button><button class="viewer-nav viewer-next" id="viewerNext">&#10095;</button><button class="viewer-close" id="viewerClose">&times;</button><div class="viewer-controls"><button id="zoomOut">&minus;</button><button id="zoomFit">Fit</button><button id="zoomIn">+</button></div></div><div class="viewer-info"><h3 id="viewerTitle"></h3><div class="viewer-line" id="viewerDate"></div><div class="viewer-line" id="viewerLocation"></div><div class="viewer-line" id="viewerPeople"></div><div class="viewer-line" id="viewerDescription"></div><div class="viewer-line"><a id="viewerDownload" style="color:white" download>Download high resolution</a></div></div></div>
<script>
const archiveItems={jsdata};
const filterCards=[...document.querySelectorAll('.archive-card')],filterYears=[...document.querySelectorAll('.archive-year')];
const fSearch=document.getElementById('filterSearch'),fPerson=document.getElementById('filterPerson'),fLocation=document.getElementById('filterLocation'),fTypeChecks=document.getElementById('filterTypeChecks'),fTag=document.getElementById('filterTag'),clearFilters=document.getElementById('clearArchiveFilters'),visibleCount=document.getElementById('visibleArchiveCount'),yearNav=document.getElementById('archiveYearNav');
function vals(v){{return Array.isArray(v)?v:(v?[v]:[])}} function norm(v){{return String(v||'').toLowerCase()}}
function mediaType(a){{if(a.media_type==='video')return 'Videos';if(a.media_type==='audio')return 'Sound';const tags=vals(a.tags).map(norm);if(tags.includes('newspaper'))return 'Newspapers';if(tags.includes('document'))return 'Documents';if(tags.includes('sound'))return 'Sound';return 'Photos'}}
function itemFor(card){{return archiveItems[+(card.dataset.i??-1)]||{{}}}} function itemHay(a){{return[a.title,a.description,a.name,a.date,a.location,...vals(a.people_raw),...vals(a.categories),...vals(a.tags)].join(' ').toLowerCase()}}
function currentFilters(){{return{{q:(fSearch?.value||'').trim().toLowerCase(),person:fPerson?.value||'',location:fLocation?.value||'',types:[...document.querySelectorAll('input[name="archiveType"]:checked')].map(x=>x.value),tag:fTag?.value||''}}}}
function itemMatches(a,f){{const people=vals(a.people_raw).map(norm),tags=vals(a.tags).map(norm),type=norm(mediaType(a)),loc=norm(a.location),hay=itemHay(a);return(!f.q||hay.includes(f.q))&&(!f.person||people.includes(f.person))&&(!f.location||loc===f.location)&&(!f.types.length||f.types.includes(type))&&(!f.tag||tags.includes(f.tag))}}
function populate(){{const people=[...new Set(archiveItems.flatMap(a=>vals(a.people_raw)).filter(Boolean))].sort(),locs=[...new Set(archiveItems.map(a=>a.location).filter(Boolean))].sort(),types=[...new Set(archiveItems.map(mediaType))].sort(),tags=[...new Set(archiveItems.flatMap(a=>vals(a.tags)).filter(Boolean))].sort();people.forEach(v=>fPerson?.add(new Option(v,norm(v))));locs.forEach(v=>fLocation?.add(new Option(v,norm(v))));tags.forEach(v=>fTag?.add(new Option(v,norm(v))));if(fTypeChecks)types.forEach(v=>{{const l=document.createElement('label'),c=document.createElement('input');c.type='checkbox';c.name='archiveType';c.value=norm(v);c.onchange=apply;l.append(c,document.createTextNode(' '+v));fTypeChecks.append(l)}});filterYears.forEach(sec=>{{const y=sec.querySelector('h2')?.textContent?.trim()||'Unknown';sec.id='year-'+y.replace(/[^A-Za-z0-9_-]/g,'-');const a=document.createElement('a');a.href='#'+sec.id;a.textContent=y;yearNav?.append(a)}})}}
function apply(){{const f=currentFilters();let shown=0;filterCards.forEach(card=>{{const ok=itemMatches(itemFor(card),f);card.hidden=!ok;if(ok)shown++}});filterYears.forEach(sec=>sec.hidden=![...sec.querySelectorAll('.archive-card')].some(c=>!c.hidden));if(visibleCount)visibleCount.textContent=shown}}
[fSearch,fPerson,fLocation,fTag].forEach(el=>el?.addEventListener(el===fSearch?'input':'change',apply));clearFilters?.addEventListener('click',()=>{{if(fSearch)fSearch.value='';if(fPerson)fPerson.value='';if(fLocation)fLocation.value='';if(fTag)fTag.value='';document.querySelectorAll('input[name="archiveType"]').forEach(c=>c.checked=false);apply()}});populate();apply();
let current=0,zoomLevel=1,fitScale=1,dragging=false,dragX=0,dragY=0,startLeft=0,startTop=0;const V=document.getElementById('viewer'),S=document.getElementById('viewerStage'),C=document.getElementById('viewerCanvas'),I=document.getElementById('viewerImg');
function layoutCanvas(){{const pad=24,cw=Math.max(S.clientWidth,I.offsetWidth+pad),ch=Math.max(S.clientHeight,I.offsetHeight+pad);C.style.width=cw+'px';C.style.height=ch+'px';I.style.left=Math.max(12,(cw-I.offsetWidth)/2)+'px';I.style.top=Math.max(12,(ch-I.offsetHeight)/2)+'px'}} function panState(){{S.classList.toggle('pannable',C.scrollWidth>S.clientWidth||C.scrollHeight>S.clientHeight)}} function applySize(mult){{if(!I.naturalWidth||!I.naturalHeight)return;I.style.width=Math.max(1,Math.round(I.naturalWidth*fitScale*mult))+'px';I.style.height=Math.max(1,Math.round(I.naturalHeight*fitScale*mult))+'px';requestAnimationFrame(()=>{{layoutCanvas();panState()}})}} function fit(){{if(!I.naturalWidth||!I.naturalHeight)return;fitScale=Math.min((S.clientWidth-24)/I.naturalWidth,(S.clientHeight-24)/I.naturalHeight,1);zoomLevel=1;applySize(1)}} function zoom(delta){{zoomLevel=Math.max(.25,Math.min(5,zoomLevel+delta));applySize(zoomLevel)}}
function show(i){{const a=archiveItems[i];if(!a||a.media_type==='video'||a.media_type==='audio')return;current=i;document.getElementById('viewerTitle').textContent=a.title||'';document.getElementById('viewerDate').textContent=a.date||'';document.getElementById('viewerLocation').textContent=a.location||'';document.getElementById('viewerPeople').textContent=a.people||'';document.getElementById('viewerDescription').textContent=a.description||'';const dl=document.getElementById('viewerDownload');dl.href=a.orig;dl.setAttribute('download',a.name||'');V.classList.add('open');I.onload=()=>requestAnimationFrame(fit);I.src=a.view}}
document.querySelectorAll('[data-view-i]').forEach(e=>e.onclick=()=>show(+e.dataset.viewI));document.getElementById('viewerPrev').onclick=()=>{{let i=current-1;while(i>=0&&archiveItems[i]?.media_type!=='photo')i--;if(i>=0)show(i)}};document.getElementById('viewerNext').onclick=()=>{{let i=current+1;while(i<archiveItems.length&&archiveItems[i]?.media_type!=='photo')i++;if(i<archiveItems.length)show(i)}};document.getElementById('viewerClose').onclick=()=>V.classList.remove('open');document.getElementById('zoomIn').onclick=()=>zoom(.25);document.getElementById('zoomOut').onclick=()=>zoom(-.25);document.getElementById('zoomFit').onclick=fit;
</script></body></html>'''
    (ROOT/filename).write_text(body,encoding='utf-8')

page('Photo Gallery','Chronological gallery generated from the current Bell Family Archive metadata.',DATA,'gallery.html')
people={'dickey':'Dickey Bell','spooky':'Spooky Bell','buster':'Buster Bell','alma':'Alma Bell','rickey':'Rickey Bell','sonja':'Sonja Bell','heather':'Heather Bell','helen':'Helen Bell','stephanie':'Stephanie Bell','jarred':'Jarred Bell','samatha':'Samatha Bell','ivy':'Ivy Bell','olivia':'Olivia Bell','sophia':'Sophia Bell','dominique':'Dominique Burwell','debbie':'Debbie Phillips','irvin':'Irvin Phillips','rickii':'Rickii Lear','breana':'Anna Lear','xavier':'Xavier Lear','donna':'Donna Brown','charlie':'Charlie Brown','jason':'Jason Hoke','mike-morgan':'Mike Morgan','teri-wallace':'Teri Wallace','mickey-morgan':'Mickey Morgan','andrew-morgan':'Andrew Morgan','teresa-cooper':'Teresa Cooper','carla-pittman':'Carla Pittman','dick-bell':'Dick Bell','rachel-bell':'Rachel Bell','johnny-tharp':'Johnny Tharp','everate-faulkenberry':'Everate Faulkenberry','peggy-faulkenberry':'Peggy Faulkenberry','lisa-steen':'Lisa Steen','macey-steen':'Macey Steen','kathleen-brown':'Kathleen Brown','tony-neely':'Tony Neely','alice-neely':'Alice Neely','tim-neely':'Tim Neely','cindy-neely':'Cindy Green','ken-brown':'Ken Brown','mary-ellen-whitaker':'Mary Ellen Whitaker'}
people['karen-gaskin']='Karen Gaskin'
for slug,name in people.items():
    display_name={'samatha':'Samatha Bell','breana':'BreeAna Lear','teri-wallace':'Teri Wallace Harrison','teresa-cooper':'Teresa Cooper Justice','carla-pittman':'Carla Pittman Lilly','peggy-faulkenberry':'Peggy Elliot Faulkenberry','lisa-steen':'Lisa Faulkenberry Steen','macey-steen':'Macey Steen Payne','cindy-neely':'Cindy Neely'}.get(slug,name)
    page(f'{display_name} - Photo Archive',f'Archive items currently tagged {name} in the Bell Family Archive.',[x for x in DATA if name in(x.get('people') or [])],f'{slug}-photos.html')
pets={'aria':'Aria','lady':'Lady','gabby':'Gabby','midnight':'Midnight','tanisha':'Tanisha','patsy-clines-angel':"Patsy Cline's Angel",'suade':'Suade','blaze':'Blaze'}
for slug,name in pets.items():
    page(f'{name} - Family Pet Archive',f'Archive items currently tagged {name} in the Bell Family Archive.',[x for x in DATA if name in(x.get('tags') or [])],f'{slug}-photos.html')
hobbies={
    'aviation':('Aviation','Pilots, aircraft, and the family connection to flight.'),
    'scuba':('Scuba','Dive trips and memories from beneath the surface.'),
    'shooting':('Shooting','Marksmanship, range days, and family shooting traditions.'),
    'boating':('Boating','Boat trips, days on the water, and shoreline memories.'),
    'off-roading':('Off-Roading','Dirt bikes, trail rides, and adventures beyond the pavement.'),
    'camping':('Camping','Campgrounds, campfires, and time together in the outdoors.'),
}
for slug,(name,description) in hobbies.items():
    tag=f'Hobbies/{name}'
    items=[]
    for item in DATA:
        path=str(item.get('path') or '').replace('\\','/')
        if name not in HOBBY_SNAPSHOT.get('memberships',{}).get(path,[]):continue
        hobby_item=dict(item)
        hobby_item['tags']=list(item.get('tags') or [])+[tag]
        items.append(hobby_item)
    tagged=HOBBY_SNAPSHOT.get('taggedCounts',{}).get(name,len(items))
    subtitle=f'{description} Collected from the family archive\'s {tag} category.'
    empty=(f'<section style="max-width:760px;background:#fff;border:1px solid #ddd;border-radius:12px;padding:18px;box-shadow:0 2px 12px #0002">'
           f'<img src="tree_thumbs/hobby_camping_2025.jpg" alt="Camper and campfire at a wooded lakeside campsite" style="display:block;width:100%;max-height:430px;object-fit:cover;border-radius:9px">'
           f'<h2>Camping in the family catalog</h2><p>{tagged} media items are cataloged under Camping. Public gallery items will appear here as they are added to the website archive.</p></section>') if name=='Camping' and not items else ''
    page(f'{name} - Hobbies',subtitle,items,f'hobby-{slug}.html',empty)
print('Generated gallery,',len(people),'person galleries,',len(pets),'pet galleries, and',len(hobbies),'hobby galleries from',len(DATA),'metadata records including video and audio support')

#!/usr/bin/env python3
import json, html, pathlib, re
from datetime import datetime
ROOT=pathlib.Path(__file__).resolve().parents[1]
DATA=json.loads((ROOT/'photo_metadata.json').read_text(encoding='utf-8'))
STATE_ABBR={'Florida':'FL','Georgia':'GA','North Carolina':'NC','South Carolina':'SC','Virginia':'VA','Tennessee':'TN','New York':'NY','Pennsylvania':'PA','Maryland':'MD','Alabama':'AL','Mississippi':'MS','Texas':'TX','California':'CA','Ohio':'OH','West Virginia':'WV'}
def esc(v): return html.escape(str(v or ''),quote=True)
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
    v=str(x.get('date') or '').strip(); name=str(x.get('path') or '').lower()
    if re.fullmatch(r'\d{4}',v):return (0,f'{v}-01-01',name)
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}',v):return (0,v,name)
    folder=str(x.get('folder') or '')
    if re.fullmatch(r'\d{4}',folder):return (1,f'{folder}-12-31',name)
    return (2,'9999-12-31',name)
def display_people(values):return ', '.join(re.sub(r'\s+Bell$',' B',str(p),flags=re.I) for p in(values or []))
def clean_location_label(value):
    v=str(value or '').strip();return {'Mason St Orig Bell Family Home':'Mason St','Mason St Original Bell Family Home':'Mason St','Mason Street Orig Bell Family Home':'Mason St','Mason Street Original Bell Family Home':'Mason St'}.get(v,v)
def display_location(x):
    parts=[];loc=clean_location_label(x.get('location'));city=str(x.get('city') or '').strip();state=str(x.get('state') or '').strip();country=str(x.get('country') or '').strip()
    if state in STATE_ABBR:state=STATE_ABBR[state]
    elif re.fullmatch(r'[A-Za-z]{2}',state):state=state.upper()
    for p in(loc,city,state):
        if p and p not in parts:parts.append(p)
    if country and country.lower() not in {'usa','us','u.s.','u.s.a.','united states','united states of america'} and country not in parts:parts.append(country)
    return ', '.join(parts)
def media_paths(x):
    p=str(x.get('path') or '').replace('\\','/'); rel=p[7:] if p.startswith('images/') else p
    thumb='thumbs/'+rel if (ROOT/'thumbs'/rel).exists() else p
    view='images/'+rel if (ROOT/'images'/rel).exists() else p
    orig='originals/'+rel if (ROOT/'originals'/rel).exists() else p
    return thumb,view,orig
def page(title,subtitle,items,filename):
    ordered=sorted(items,key=date_sort_key); years={}
    for x in ordered:
        d=str(x.get('date') or '');y=d[:4] if re.match(r'^\d{4}',d) else(x.get('folder') if re.fullmatch(r'\d{4}',str(x.get('folder') or '')) else 'Unknown');years.setdefault(y,[]).append(x)
    viewer=[];sections=[];idx=0
    for y in sorted(years,key=lambda z:(z=='Unknown',z)):
        cards=[]
        for x in years[y]:
            t,v,o=media_paths(x);ttl=str(x.get('title') or '').strip();desc=str(x.get('description') or '');date=nice_date(str(x.get('date') or ''));loc=display_location(x);ppl=display_people(x.get('people'));fn=str(x.get('file') or pathlib.PurePosixPath(str(x.get('path') or '')).name)
            lines=[f'<div class="archive-meta-line">{esc(date)}</div>']
            if loc:lines.append(f'<div class="archive-meta-line">{esc(loc)}</div>')
            if ppl:lines.append(f'<div class="archive-meta-line">{esc(ppl)}</div>')
            th=f'<h3>{esc(ttl)}</h3>' if ttl else ''
            cards.append(f'''<article class="archive-card"><button class="archive-pic" data-i="{idx}"><img src="{esc(t)}" alt="{esc(ttl or 'Archive photo')}" loading="lazy"></button><div class="archive-copy">{th}<div class="archive-meta">{''.join(lines)}</div>{f'<p>{esc(desc)}</p>' if desc else ''}<div class="archive-file">{esc(fn)}</div><div class="archive-actions"><button data-i="{idx}">View</button><a href="{esc(o)}" download>Download full resolution</a></div></div></article>''')
            viewer.append({'view':v,'orig':o,'title':ttl,'date':date,'location':loc,'people':ppl,'description':desc,'name':fn});idx+=1
        sections.append(f'<section class="archive-year"><h2>{esc(y)}</h2><div class="archive-grid">{"".join(cards)}</div></section>')
    jsdata=json.dumps(viewer,ensure_ascii=False).replace('</','<\\/')
    body=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc(title)} — The Bell Family</title><link rel="stylesheet" href="style.css"><style>
.archive-main{{max-width:1500px;margin:auto;padding:28px}}.archive-grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:18px}}.archive-card{{background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px #0002}}.archive-pic{{width:100%;padding:0;border:0;background:#eee;cursor:pointer}}.archive-pic img{{width:100%;height:240px;object-fit:contain;display:block}}.archive-copy{{padding:12px}}.archive-copy h3{{margin:0 0 6px;font-size:1rem}}.archive-meta{{font-size:.88rem;opacity:.78;line-height:1.4}}.archive-meta-line{{display:block}}.archive-file{{font-size:.82rem;opacity:.65;margin-top:8px}}.archive-copy p{{white-space:pre-line}}.archive-year{{margin:32px 0}}.archive-year>h2{{border-bottom:1px solid #ccc;padding-bottom:6px}}.archive-actions{{display:flex;gap:12px;align-items:center;margin-top:9px}}.archive-actions button{{border:0;padding:0;background:none;color:#06c;text-decoration:underline;cursor:pointer}}.archive-actions a{{color:#06c}}
.viewer{{position:fixed;inset:0;background:#000e;display:none;z-index:9999;color:#fff}}.viewer.open{{display:grid;grid-template-rows:1fr auto}}.viewer-stage{{position:relative;overflow:auto;display:flex;align-items:center;justify-content:center;min-height:0}}.viewer-stage img{{display:block;transform-origin:center center;transition:transform .08s}}.viewer.fit img{{max-width:100%;max-height:100%;width:auto;height:auto}}.viewer-nav,.viewer-close{{position:fixed;border:0;border-radius:50%;background:#0009;color:#fff;cursor:pointer;z-index:10001}}.viewer-nav{{top:50%;transform:translateY(-50%);font-size:38px;width:54px;height:54px}}.viewer-prev{{left:12px}}.viewer-next{{right:12px}}.viewer-close{{right:14px;top:14px;font-size:28px;width:46px;height:46px}}.viewer-controls{{position:fixed;top:14px;left:50%;transform:translateX(-50%);display:flex;gap:8px;z-index:10001}}.viewer-controls button{{border:0;border-radius:6px;padding:8px 13px;font-size:18px;cursor:pointer}}.viewer-info{{text-align:center;padding:8px 70px 14px;background:#0008}}.viewer-info h3{{margin:0 0 5px}}.viewer-line{{margin:2px 0}}@media(max-width:650px){{.viewer-info{{padding-left:12px;padding-right:12px}}}}
</style></head><body><header class="site-header"><div class="brand"><div class="tree-mark">♧</div><div><div class="brand-title">The Bell Family</div><div class="brand-tagline">Generations of Love, Memories &amp; Legacy</div></div></div><nav class="top-nav"><a href="index.html">Family Tree</a><a href="gallery.html">Photo Gallery</a></nav></header><main class="archive-main"><span class="eyebrow">Bell Family Archive</span><h1>{esc(title)}</h1><p>{esc(subtitle)}</p><p><strong>{len(items)} archive items</strong></p>{''.join(sections)}</main><footer>© 2026 The Bell Family Archive · Preserving Our Legacy for Future Generations</footer>
<div class="viewer fit" id="viewer"><div class="viewer-stage" id="viewerStage"><img id="viewerImg"><button class="viewer-nav viewer-prev" id="viewerPrev">&#10094;</button><button class="viewer-nav viewer-next" id="viewerNext">&#10095;</button><button class="viewer-close" id="viewerClose">&times;</button><div class="viewer-controls"><button id="zoomOut">−</button><button id="zoomFit">Fit</button><button id="zoomIn">+</button></div></div><div class="viewer-info"><h3 id="viewerTitle"></h3><div class="viewer-line" id="viewerDate"></div><div class="viewer-line" id="viewerLocation"></div><div class="viewer-line" id="viewerPeople"></div><div class="viewer-line" id="viewerDescription"></div><div class="viewer-line"><a id="viewerDownload" style="color:white" download>Download full resolution</a></div></div></div>
<script>const archiveItems={jsdata};let current=0,scale=1;const V=document.getElementById('viewer'),S=document.getElementById('viewerStage'),I=document.getElementById('viewerImg');function fit(){{scale=1;V.classList.add('fit');I.style.transform='scale(1)';S.scrollTop=0;S.scrollLeft=0}}function zoom(delta){{V.classList.remove('fit');scale=Math.max(.25,Math.min(5,scale+delta));I.style.maxWidth='none';I.style.maxHeight='none';I.style.transform='scale('+scale+')'}}function show(i){{current=(i+archiveItems.length)%archiveItems.length;const a=archiveItems[current];I.src=a.view;document.getElementById('viewerTitle').textContent=a.title||'';document.getElementById('viewerDate').textContent=a.date||'';document.getElementById('viewerLocation').textContent=a.location||'';document.getElementById('viewerPeople').textContent=a.people||'';document.getElementById('viewerDescription').textContent=a.description||'';const dl=document.getElementById('viewerDownload');dl.href=a.orig;dl.setAttribute('download',a.name||'');V.classList.add('open');fit()}}document.querySelectorAll('[data-i]').forEach(e=>e.onclick=()=>show(+e.dataset.i));document.getElementById('viewerPrev').onclick=()=>show(current-1);document.getElementById('viewerNext').onclick=()=>show(current+1);document.getElementById('viewerClose').onclick=()=>V.classList.remove('open');document.getElementById('zoomIn').onclick=()=>zoom(.25);document.getElementById('zoomOut').onclick=()=>zoom(-.25);document.getElementById('zoomFit').onclick=fit;document.onkeydown=e=>{{if(!V.classList.contains('open'))return;if(e.key==='ArrowLeft')show(current-1);else if(e.key==='ArrowRight')show(current+1);else if(e.key==='Escape')V.classList.remove('open');else if(e.key==='+'||e.key==='=')zoom(.25);else if(e.key==='-')zoom(-.25);else if(e.key==='0')fit()}}</script></body></html>'''
    (ROOT/filename).write_text(body,encoding='utf-8')
page('Photo Gallery','Chronological gallery generated from the metadata embedded in the current archive photographs.',DATA,'gallery.html')
people={'dickey':'Dickey Bell','spooky':'Spooky Bell','buster':'Buster Bell','alma':'Alma Bell','rickey':'Rickey Bell','sonja':'Sonja Bell','heather':'Heather Bell','stephanie':'Stephanie Bell','jarred':'Jarred Bell'}
for slug,name in people.items():page(f'{name} — Photo Archive',f'Photographs currently tagged {name} in the Bell Family Archive.',[x for x in DATA if name in(x.get('people') or [])],f'{slug}-photos.html')
print('Generated gallery and',len(people),'photo-only person galleries from',len(DATA),'metadata records in chronological order with popup viewer')
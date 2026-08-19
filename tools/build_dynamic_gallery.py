#!/usr/bin/env python3
import json, html, pathlib, re
from datetime import datetime
ROOT=pathlib.Path(__file__).resolve().parents[1]
DATA=json.loads((ROOT/'photo_metadata.json').read_text(encoding='utf-8'))
STATE_ABBR={'Florida':'FL','Georgia':'GA','North Carolina':'NC','South Carolina':'SC','Virginia':'VA','Tennessee':'TN','New York':'NY','Pennsylvania':'PA','Maryland':'MD','Alabama':'AL','Mississippi':'MS','Texas':'TX','California':'CA','Ohio':'OH','West Virginia':'WV'}
def esc(v): return html.escape(str(v or ''), quote=True)
def nice_date(v):
    if not v: return 'Date unknown'
    if re.fullmatch(r'\d{4}',v): return f'Circa {v}'
    try:
        dt=datetime.strptime(v,'%Y-%m-%d')
        if dt.month==1 and dt.day==1: return f'Circa {dt.year}'
        if dt.day==1: return f"Circa {dt.strftime('%B %Y')}"
        return dt.strftime('%B %d, %Y').replace(' 0',' ')
    except Exception: return v
def date_sort_key(x):
    v=str(x.get('date') or '').strip()
    if re.fullmatch(r'\d{4}',v): return (0,f'{v}-01-01',str(x.get('path') or '').lower())
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}',v): return (0,v,str(x.get('path') or '').lower())
    folder=str(x.get('folder') or '')
    if re.fullmatch(r'\d{4}',folder): return (1,f'{folder}-12-31',str(x.get('path') or '').lower())
    return (2,'9999-12-31',str(x.get('path') or '').lower())
def display_people(values):
    return ', '.join(re.sub(r'\s+Bell$',' B',str(p),flags=re.I) for p in (values or []))
def clean_location_label(value):
    v=str(value or '').strip()
    return {'Mason St Orig Bell Family Home':'Mason St','Mason St Original Bell Family Home':'Mason St','Mason Street Orig Bell Family Home':'Mason St','Mason Street Original Bell Family Home':'Mason St'}.get(v,v)
def display_location(x):
    parts=[]; loc=clean_location_label(x.get('location')); city=str(x.get('city') or '').strip(); state=str(x.get('state') or '').strip(); country=str(x.get('country') or '').strip()
    if state in STATE_ABBR: state=STATE_ABBR[state]
    elif re.fullmatch(r'[A-Za-z]{2}',state): state=state.upper()
    for p in (loc,city,state):
        if p and p not in parts: parts.append(p)
    if country and country.lower() not in {'usa','us','u.s.','u.s.a.','united states','united states of america'} and country not in parts: parts.append(country)
    return ', '.join(parts)
def cards(items):
    out=[]
    for x in sorted(items,key=date_sort_key):
        title=str(x.get('title') or '').strip(); desc=x.get('description') or ''; date=nice_date(x.get('date')); location=display_location(x); people=display_people(x.get('people'))
        meta_lines=[f'<div class="archive-meta-line">{esc(date)}</div>']
        if location: meta_lines.append(f'<div class="archive-meta-line">{esc(location)}</div>')
        if people: meta_lines.append(f'<div class="archive-meta-line">{esc(people)}</div>')
        title_html=f'<h3>{esc(title)}</h3>' if title else ''
        out.append(f'''<article class="archive-card"><a href="{esc(x['path'])}" target="_blank"><img src="{esc(x['path'])}" alt="{esc(title or 'Archive photo')}" loading="lazy"></a><div class="archive-copy">{title_html}<div class="archive-meta">{''.join(meta_lines)}</div>{f'<p>{esc(desc)}</p>' if desc else ''}<div class="archive-file">{esc(x.get('file'))}</div></div></article>''')
    return '\n'.join(out)
def page(title,subtitle,items,filename):
    years={}
    for x in items:
        d=str(x.get('date') or ''); y=d[:4] if re.match(r'^\d{4}',d) else (x.get('folder') if re.fullmatch(r'\d{4}',str(x.get('folder') or '')) else 'Unknown'); years.setdefault(y,[]).append(x)
    sections=[]
    for y in sorted(years,key=lambda y:(y=='Unknown',y)): sections.append(f'<section class="archive-year"><h2>{esc(y)}</h2><div class="archive-grid">{cards(years[y])}</div></section>')
    body=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc(title)} — The Bell Family</title><link rel="stylesheet" href="style.css"><style>.archive-main{{max-width:1500px;margin:auto;padding:28px}}.archive-grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:18px}}.archive-card{{background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px #0002}}.archive-card img{{width:100%;height:240px;object-fit:contain;background:#eee;display:block}}.archive-copy{{padding:12px}}.archive-copy h3{{margin:0 0 6px;font-size:1rem}}.archive-meta{{font-size:.88rem;opacity:.78;line-height:1.4}}.archive-meta-line{{display:block}}.archive-file{{font-size:.88rem;opacity:.75;margin-top:8px}}.archive-copy p{{white-space:pre-line}}.archive-year{{margin:32px 0}}.archive-year>h2{{border-bottom:1px solid #ccc;padding-bottom:6px}}</style></head><body><header class="site-header"><div class="brand"><div class="tree-mark">♧</div><div><div class="brand-title">The Bell Family</div><div class="brand-tagline">Generations of Love, Memories &amp; Legacy</div></div></div><nav class="top-nav"><a href="index.html">Family Tree</a><a href="gallery.html">Photo Gallery</a></nav></header><main class="archive-main"><span class="eyebrow">Bell Family Archive</span><h1>{esc(title)}</h1><p>{esc(subtitle)}</p><p><strong>{len(items)} archive items</strong></p>{''.join(sections)}</main><footer>© 2026 The Bell Family Archive · Preserving Our Legacy for Future Generations</footer></body></html>'''
    (ROOT/filename).write_text(body,encoding='utf-8')
page('Photo Gallery','Chronological gallery generated from the metadata embedded in the current archive photographs.',DATA,'gallery.html')
people={'dickey':'Dickey Bell','spooky':'Spooky Bell','buster':'Buster Bell','alma':'Alma Bell','rickey':'Rickey Bell','sonja':'Sonja Bell','heather':'Heather Bell','stephanie':'Stephanie Bell','jarred':'Jarred Bell'}
for slug,name in people.items(): page(f'{name} — Photo Archive',f'Photographs currently tagged {name} in the Bell Family Archive.',[x for x in DATA if name in (x.get('people') or [])],f'{slug}-photos.html')
print('Generated gallery and',len(people),'photo-only person galleries from',len(DATA),'metadata records in chronological order')
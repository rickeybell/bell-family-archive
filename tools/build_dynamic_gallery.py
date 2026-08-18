#!/usr/bin/env python3
import json, html, pathlib, re
ROOT=pathlib.Path(__file__).resolve().parents[1]
DATA=json.loads((ROOT/'photo_metadata.json').read_text(encoding='utf-8'))

def esc(v): return html.escape(str(v or ''), quote=True)
def nice_date(v):
    if not v: return 'Date unknown'
    if re.fullmatch(r'\d{4}',v): return v
    try:
        from datetime import datetime
        return datetime.strptime(v,'%Y-%m-%d').strftime('%B %-d, %Y')
    except Exception: return v

def cards(items):
    out=[]
    for x in items:
        title=x.get('title') or x.get('file','Photo')
        desc=x.get('description') or ''
        people=', '.join(x.get('people') or [])
        meta=' · '.join(y for y in (nice_date(x.get('date')), people) if y)
        out.append(f'''<article class="archive-card"><a href="{esc(x['path'])}" target="_blank"><img src="{esc(x['path'])}" alt="{esc(title)}" loading="lazy"></a><div class="archive-copy"><h3>{esc(title)}</h3><div class="archive-meta">{esc(meta)}</div>{f'<p>{esc(desc)}</p>' if desc else ''}</div></article>''')
    return '\n'.join(out)

def page(title, subtitle, items, filename):
    years={}
    for x in items:
        y=(x.get('date') or x.get('folder') or 'Unknown')[:4]
        years.setdefault(y,[]).append(x)
    sections=[]
    for y in sorted(years, key=lambda s:(s=='Unkn',s)):
        sections.append(f'<section class="archive-year"><h2>{esc(y)}</h2><div class="archive-grid">{cards(years[y])}</div></section>')
    body=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc(title)} — The Bell Family</title><link rel="stylesheet" href="style.css"><style>.archive-main{{max-width:1500px;margin:auto;padding:28px}}.archive-grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:18px}}.archive-card{{background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px #0002}}.archive-card img{{width:100%;height:240px;object-fit:contain;background:#eee;display:block}}.archive-copy{{padding:12px}}.archive-copy h3{{margin:0 0 6px;font-size:1rem}}.archive-meta{{font-size:.88rem;opacity:.75}}.archive-copy p{{white-space:pre-line}}.archive-year{{margin:32px 0}}.archive-year>h2{{border-bottom:1px solid #ccc;padding-bottom:6px}}</style></head><body><header class="site-header"><div class="brand"><div class="tree-mark">♧</div><div><div class="brand-title">The Bell Family</div><div class="brand-tagline">Generations of Love, Memories &amp; Legacy</div></div></div><nav class="top-nav"><a href="index.html">Family Tree</a><a href="gallery.html">Photo Gallery</a></nav></header><main class="archive-main"><span class="eyebrow">Bell Family Archive</span><h1>{esc(title)}</h1><p>{esc(subtitle)}</p><p><strong>{len(items)} archive items</strong></p>{''.join(sections)}</main><footer>© 2026 The Bell Family Archive · Preserving Our Legacy for Future Generations</footer></body></html>'''
    (ROOT/filename).write_text(body,encoding='utf-8')

page('Photo Gallery','Chronological gallery generated from the metadata embedded in the current archive photographs.',DATA,'gallery.html')
people={'dickey.html':'Dickey Bell','spooky.html':'Spooky Bell','buster.html':'Buster Bell','alma.html':'Alma Bell','rickey.html':'Rickey Bell','sonja.html':'Sonja Bell','heather.html':'Heather Bell','stephanie.html':'Stephanie Bell','jarred.html':'Jarred Bell'}
for fn,name in people.items():
    subset=[x for x in DATA if name in (x.get('people') or [])]
    page(name,f'Photographs currently tagged {name} in the Bell Family Archive.',subset,fn)
print('Generated gallery and',len(people),'person pages from',len(DATA),'metadata records')

#!/usr/bin/env python3
import json, html, pathlib, re
ROOT=pathlib.Path(__file__).resolve().parents[1]
DATA=json.loads((ROOT/'photo_metadata.json').read_text(encoding='utf-8'))

STATE_ABBR={
'Alabama':'AL','Alaska':'AK','Arizona':'AZ','Arkansas':'AR','California':'CA','Colorado':'CO','Connecticut':'CT','Delaware':'DE','Florida':'FL','Georgia':'GA','Hawaii':'HI','Idaho':'ID','Illinois':'IL','Indiana':'IN','Iowa':'IA','Kansas':'KS','Kentucky':'KY','Louisiana':'LA','Maine':'ME','Maryland':'MD','Massachusetts':'MA','Michigan':'MI','Minnesota':'MN','Mississippi':'MS','Missouri':'MO','Montana':'MT','Nebraska':'NE','Nevada':'NV','New Hampshire':'NH','New Jersey':'NJ','New Mexico':'NM','New York':'NY','North Carolina':'NC','North Dakota':'ND','Ohio':'OH','Oklahoma':'OK','Oregon':'OR','Pennsylvania':'PA','Rhode Island':'RI','South Carolina':'SC','South Dakota':'SD','Tennessee':'TN','Texas':'TX','Utah':'UT','Vermont':'VT','Virginia':'VA','Washington':'WA','West Virginia':'WV','Wisconsin':'WI','Wyoming':'WY','District of Columbia':'DC'
}

def esc(v): return html.escape(str(v or ''), quote=True)
def nice_date(v):
    if not v: return 'Date unknown'
    if re.fullmatch(r'\d{4}',v): return v
    try:
        from datetime import datetime
        dt=datetime.strptime(v,'%Y-%m-%d')
        if dt.month == 1 and dt.day == 1:
            return str(dt.year)
        if dt.day == 1:
            return dt.strftime('%B %Y')
        return dt.strftime('%B %d, %Y').replace(' 0',' ')
    except Exception: return v

def display_people(values):
    out=[]
    for p in values or []:
        p=str(p)
        p=re.sub(r'\s+Bell$', ' B', p, flags=re.I)
        out.append(p)
    return ', '.join(out)

def clean_place_name(value):
    s=str(value or '').strip()
    # Shorten archive-internal descriptive place labels for public display.
    s=re.sub(r'\s+Orig(?:inal)?\s+Bell\s+Family\s+Home$', '', s, flags=re.I)
    s=re.sub(r'\s+Bell\s+Family\s+Home$', '', s, flags=re.I)
    return s.strip(' ,')

def display_location(x):
    parts=[]
    loc=clean_place_name(x.get('location'))
    city=clean_place_name(x.get('city'))
    state=str(x.get('state') or '').strip()
    country=str(x.get('country') or '').strip()
    if state in STATE_ABBR:
        state=STATE_ABBR[state]
    elif re.fullmatch(r'[A-Za-z]{2}',state):
        state=state.upper()
    for p in (loc,city,state):
        if p and p not in parts:
            parts.append(p)
    if country and country.lower() not in {'usa','us','u.s.','u.s.a.','united states','united states of america'} and country not in parts:
        parts.append(country)
    return ', '.join(parts)

def cards(items):
    out=[]
    for x in items:
        title=x.get('title') or x.get('file','Photo')
        desc=x.get('description') or ''
        date=nice_date(x.get('date'))
        location=display_location(x)
        people=display_people(x.get('people'))
        meta_lines=[f'<div class="archive-meta-line archive-date">{esc(date)}</div>']
        if location:
            meta_lines.append(f'<div class="archive-meta-line archive-location">{esc(location)}</div>')
        if people:
            meta_lines.append(f'<div class="archive-meta-line archive-people">{esc(people)}</div>')
        meta=''.join(meta_lines)
        out.append(f'''<article class="archive-card"><a href="{esc(x['path'])}" target="_blank"><img src="{esc(x['path'])}" alt="{esc(title)}" loading="lazy"></a><div class="archive-copy"><h3>{esc(title)}</h3><div class="archive-meta">{meta}</div>{f'<p>{esc(desc)}</p>' if desc else ''}<div class="archive-file">{esc(x.get('file'))}</div></div></article>''')
    return '\n'.join(out)

def page(title, subtitle, items, filename):
    years={}
    for x in items:
        d=x.get('date') or ''
        y=d[:4] if re.match(r'^\d{4}',d) else (x.get('folder') if re.fullmatch(r'\d{4}',str(x.get('folder') or '')) else 'Unknown')
        years.setdefault(y,[]).append(x)
    def ykey(y): return (y=='Unknown', y)
    sections=[]
    for y in sorted(years,key=ykey):
        sections.append(f'<section class="archive-year"><h2>{esc(y)}</h2><div class="archive-grid">{cards(years[y])}</div></section>')
    body=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc(title)} — The Bell Family</title><link rel="stylesheet" href="style.css"><style>.archive-main{{max-width:1500px;margin:auto;padding:28px}}.archive-grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:18px}}.archive-card{{background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px #0002}}.archive-card img{{width:100%;height:240px;object-fit:contain;background:#eee;display:block}}.archive-copy{{padding:12px}}.archive-copy h3{{margin:0 0 6px;font-size:1rem}}.archive-meta{{font-size:.88rem;opacity:.82;line-height:1.45}}.archive-meta-line{{display:block;margin:0}}.archive-file{{font-size:.88rem;opacity:.65;margin-top:8px}}.archive-copy p{{white-space:pre-line;margin:10px 0}}.archive-year{{margin:32px 0}}.archive-year>h2{{border-bottom:1px solid #ccc;padding-bottom:6px}}</style></head><body><header class="site-header"><div class="brand"><div class="tree-mark">♧</div><div><div class="brand-title">The Bell Family</div><div class="brand-tagline">Generations of Love, Memories &amp; Legacy</div></div></div><nav class="top-nav"><a href="index.html">Family Tree</a><a href="gallery.html">Photo Gallery</a></nav></header><main class="archive-main"><span class="eyebrow">Bell Family Archive</span><h1>{esc(title)}</h1><p>{esc(subtitle)}</p><p><strong>{len(items)} archive items</strong></p>{''.join(sections)}</main><footer>© 2026 The Bell Family Archive · Preserving Our Legacy for Future Generations</footer></body></html>'''
    (ROOT/filename).write_text(body,encoding='utf-8')

page('Photo Gallery','Chronological gallery generated from the metadata embedded in the current archive photographs.',DATA,'gallery.html')
people={'dickey':'Dickey Bell','spooky':'Spooky Bell','buster':'Buster Bell','alma':'Alma Bell','rickey':'Rickey Bell','sonja':'Sonja Bell','heather':'Heather Bell','stephanie':'Stephanie Bell','jarred':'Jarred Bell'}
for slug,name in people.items():
    subset=[x for x in DATA if name in (x.get('people') or [])]
    page(f'{name} — Photo Archive',f'Photographs currently tagged {name} in the Bell Family Archive.',subset,f'{slug}-photos.html')
print('Generated gallery and',len(people),'photo-only person galleries from',len(DATA),'metadata records')
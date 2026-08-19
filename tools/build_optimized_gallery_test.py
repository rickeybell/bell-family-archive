#!/usr/bin/env python3
import json, html, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[1]
TEST = ROOT / 'website-test-v38'
DATA = json.loads((ROOT / 'photo_metadata.json').read_text(encoding='utf-8'))


def esc(v):
    return html.escape(str(v or ''), quote=True)


def nice_date(v):
    if not v:
        return 'Date unknown'
    if re.fullmatch(r'\d{4}', v):
        return v
    try:
        from datetime import datetime
        dt = datetime.strptime(v, '%Y-%m-%d')
        if dt.day == 1:
            return dt.strftime('%B %Y')
        return dt.strftime('%B %d, %Y').replace(' 0', ' ')
    except Exception:
        return v


def rel_from_live_path(path):
    p = str(path or '').replace('\\', '/')
    if p.startswith('images/'):
        return p[len('images/'):]
    return p.lstrip('/')


def year_of(x):
    d = x.get('date') or ''
    if re.match(r'^\d{4}', d):
        return d[:4]
    folder = str(x.get('folder') or '')
    if re.fullmatch(r'\d{4}', folder):
        return folder
    rel = rel_from_live_path(x.get('path'))
    m = re.match(r'^(18|19|20)\d{2}/', rel)
    return rel[:4] if m else 'Unknown'


def exists_triplet(x):
    rel = rel_from_live_path(x.get('path'))
    return all((TEST / sub / pathlib.Path(rel)).exists() for sub in ('thumbs', 'images', 'originals'))


def card(x):
    rel = rel_from_live_path(x.get('path'))
    title = x.get('title') or x.get('file') or 'Photo'
    desc = x.get('description') or ''
    people = ', '.join(x.get('people') or [])
    meta = ' · '.join(y for y in (nice_date(x.get('date')), people) if y)
    thumb = 'thumbs/' + rel
    view = 'images/' + rel
    original = 'originals/' + rel
    return f'''<article class="archive-card">
      <a class="photo-link" href="{esc(view)}" target="_blank" rel="noopener">
        <img src="{esc(thumb)}" alt="{esc(title)}" loading="lazy" decoding="async">
      </a>
      <div class="archive-copy">
        <h3>{esc(title)}</h3>
        <div class="archive-meta">{esc(meta)}</div>
        {f'<p>{esc(desc)}</p>' if desc else ''}
        <div class="archive-actions">
          <a href="{esc(view)}" target="_blank" rel="noopener">View larger</a>
          <a href="{esc(original)}" download>Download full resolution</a>
        </div>
        <div class="archive-file">{esc(x.get('file'))}</div>
      </div>
    </article>'''


items = [x for x in DATA if exists_triplet(x)]
years = {}
for x in items:
    years.setdefault(year_of(x), []).append(x)

sections = []
for y in sorted(years, key=lambda k: (k == 'Unknown', k)):
    cards = '\n'.join(card(x) for x in years[y])
    sections.append(f'<section class="archive-year"><h2>{esc(y)}</h2><div class="archive-grid">{cards}</div></section>')

body = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Optimized Gallery Test — The Bell Family</title>
<link rel="stylesheet" href="../style.css">
<style>
body{{background:#f5f3ee}}
.archive-main{{max-width:1500px;margin:auto;padding:28px}}
.archive-grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:18px}}
.archive-card{{background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px #0002}}
.archive-card img{{width:100%;height:240px;object-fit:contain;background:#eee;display:block}}
.archive-copy{{padding:12px}}
.archive-copy h3{{margin:0 0 6px;font-size:1rem}}
.archive-meta,.archive-file{{font-size:.88rem;opacity:.75}}
.archive-copy p{{white-space:pre-line}}
.archive-actions{{display:flex;gap:12px;flex-wrap:wrap;margin:10px 0 6px}}
.archive-actions a{{font-size:.9rem}}
.archive-year{{margin:32px 0}}
.archive-year>h2{{border-bottom:1px solid #ccc;padding-bottom:6px}}
.test-note{{background:#fff3cd;border:1px solid #ffe69c;padding:12px;border-radius:8px;margin:14px 0}}
</style>
</head>
<body>
<main class="archive-main">
<h1>Optimized Gallery Test</h1>
<div class="test-note">This is a local test gallery. Grid cards use 400px thumbnails. Clicking a photo opens the 1600px photo or 3000px Document/Newspaper viewing copy. “Download full resolution” points to the archival original.</div>
<p><strong>{len(items)} test items</strong></p>
{''.join(sections)}
</main>
</body>
</html>'''

out = TEST / 'gallery-test.html'
out.write_text(body, encoding='utf-8')
print(f'Generated {out} with {len(items)} optimized test items')

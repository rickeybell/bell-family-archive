from pathlib import Path
from datetime import datetime
import json, re, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parent
INDEX = ROOT / "index.html"
META = ROOT / "photo_metadata.json"
BUILDER = ROOT / "tools" / "build_dynamic_gallery.py"
HELEN = ROOT / "helen.html"

for q in (INDEX, META, BUILDER):
    if not q.exists(): raise SystemExit(f"ERROR: Missing {q}")

backup = Path.home() / "Documents" / "BellWebsite-Backups" / f"HelenPage-{datetime.now():%Y%m%d-%H%M%S}"
backup.mkdir(parents=True, exist_ok=True)
for q in (INDEX, BUILDER): shutil.copy2(q, backup / q.name)
if HELEN.exists(): shutil.copy2(HELEN, backup / HELEN.name)

data = json.loads(META.read_text(encoding="utf-8"))
name = "Helen Bell"
count = sum(1 for item in data if name in (item.get("people") or []))

# Update Helen card in index.html
html = INDEX.read_text(encoding="utf-8-sig")
m = re.search(r'<a class="tree-person" href="spooky\.html">(?:(?!</a>).)*?<img src="tree_portraits/helen_bell\.jpg"(?:(?!</a>).)*?</a>', html, flags=re.S)
if not m: raise SystemExit("ERROR: Could not find Helen tree card")
card = m.group(0)
card = card.replace('href="spooky.html"', 'href="helen.html"', 1)
if 'class="tree-count"' in card:
    card = re.sub(r'<div class="tree-count"[^>]*>.*?</div>', f'<div class="tree-count" data-archive-person="Helen Bell">{count} archive items</div>', card, count=1, flags=re.S)
else:
    card = card.replace("</a>", f'<div class="tree-count" data-archive-person="Helen Bell">{count} archive items</div></a>', 1)
html = html[:m.start()] + card + html[m.end():]
INDEX.write_text(html, encoding="utf-8", newline="\n")

# Add Helen to both gallery mappings
b = BUILDER.read_text(encoding="utf-8-sig")
if "'helen':'Helen Bell'" not in b:
    first = b.find("'heather':'Heather Bell'")
    if first < 0: raise SystemExit("ERROR: Could not find first mapping insertion point")
    pos = first + len("'heather':'Heather Bell'")
    b = b[:pos] + ",'helen':'Helen Bell'" + b[pos:]
    second_start = b.find("people={")
    second = b.find("'heather':'Heather Bell'", second_start)
    if second >= 0 and "'helen':'Helen Bell'" not in b[second_start:]:
        pos2 = second + len("'heather':'Heather Bell'")
        b = b[:pos2] + ",'helen':'Helen Bell'" + b[pos2:]
BUILDER.write_text(b, encoding="utf-8", newline="\n")

# Create Helen personal page without inventing unknown facts
page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Helen Bell - The Bell Family Archive</title><link rel="stylesheet" href="style.css"></head><body>
<header class="site-header"><a class="brand brand-home" href="index.html" aria-label="Bell Family home"><div><div class="brand-title">The Bell Family</div><div class="brand-tagline">Generations of Love, Memories &amp; Legacy</div></div></a><nav class="top-nav"><a href="index.html">Family Tree</a><a href="dickey.html">Dickey Bell</a><a href="gallery.html">Photo Gallery</a></nav></header>
<div class="site-shell" style="display:block;max-width:1600px;margin:0 auto;"><main class="archive-content" style="width:100%;max-width:1500px;margin:0 auto;min-width:0;padding:28px 34px 50px;">
<section class="person-hero"><div class="person-hero-photo"><img src="tree_portraits/helen_bell.jpg" alt="Helen Bell"></div><div class="person-hero-copy"><div class="eyebrow">Bell Family Member</div><h1>Helen Bell</h1><p class="person-subtitle">Spooky Bell&rsquo;s wife</p><p>A dedicated archive page for Helen Bell, bringing together photographs, memories, and records connected to her.</p><div class="tree-vitals person-page-vitals"><span><strong>Born:</strong> circa 1946</span></div><div class="person-count">{count} currently identified archive items</div></div></section>
<section class="tree-note"><h2>Current Photo Archive</h2><p>Archive items currently tagged with Helen Bell.</p><p><a href="helen-photos.html"><strong>Open Helen Bell photo archive &rarr;</strong></a></p></section>
</main></div><footer>&copy; 2026 The Bell Family Archive &middot; Preserving Our Legacy for Future Generations</footer><script src="person.js"></script></body></html>"""
HELEN.write_text(page, encoding="utf-8", newline="\n")

result = subprocess.run([sys.executable, str(BUILDER)], cwd=str(ROOT))
if result.returncode != 0: raise SystemExit(f"Gallery rebuild failed: {result.returncode}")

print(f"Helen Bell: {count} archive items")
print("Created helen.html and helen-photos.html; updated tree card and gallery filters.")
print(f"Backup: {backup}")
print("No Git commit or push was performed.")

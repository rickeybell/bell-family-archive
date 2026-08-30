from pathlib import Path
from datetime import datetime
import json, re, shutil

ROOT = Path(__file__).resolve().parent
INDEX = ROOT / "index.html"
META = ROOT / "photo_metadata.json"

if not INDEX.exists():
    raise SystemExit(f"ERROR: Missing {INDEX}")
if not META.exists():
    raise SystemExit(f"ERROR: Missing {META}")

backup = Path.home() / "Documents" / "BellWebsite-Backups" / f"DominiqueTreeCount-{datetime.now():%Y%m%d-%H%M%S}"
backup.mkdir(parents=True, exist_ok=True)
shutil.copy2(INDEX, backup / INDEX.name)

data = json.loads(META.read_text(encoding="utf-8"))

name = "Dominique Burwell"
count = sum(1 for item in data if name in (item.get("people") or []))

html = INDEX.read_text(encoding="utf-8-sig")

card_match = re.search(
    r'(<a class="tree-person[^"]*" href="dominique\.html">.*?</a>)',
    html,
    flags=re.S
)

if not card_match:
    raise SystemExit("ERROR: Could not find Dominique tree card.")

card = card_match.group(1)

if 'class="tree-count"' in card:
    new_card = re.sub(
        r'<div class="tree-count"[^>]*>.*?</div>',
        f'<div class="tree-count" data-archive-person="{name}">{count} archive items</div>',
        card,
        count=1,
        flags=re.S
    )
else:
    # Insert the archive count immediately before the closing anchor.
    new_card = re.sub(
        r'(</a>)$',
        f'<div class="tree-count" data-archive-person="{name}">{count} archive items</div>\\n\\1',
        card,
        count=1,
        flags=re.S
    )

html = html[:card_match.start()] + new_card + html[card_match.end():]
INDEX.write_text(html, encoding="utf-8", newline="\n")

print("DOMINIQUE TREE COUNT UPDATED")
print(f"{name}: {count} archive items")
print("Backup:", backup)
print("No Git commit or push was performed.")

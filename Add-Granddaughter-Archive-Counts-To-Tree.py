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

backup = Path.home() / "Documents" / "BellWebsite-Backups" / f"GranddaughterTreeCounts-{datetime.now():%Y%m%d-%H%M%S}"
backup.mkdir(parents=True, exist_ok=True)
shutil.copy2(INDEX, backup / INDEX.name)

data = json.loads(META.read_text(encoding="utf-8"))

people = {
    "sophia.html": "Sophia Bell",
    "olivia.html": "Olivia Bell",
    "ivy.html": "Ivy Bell",
}

def count_for(name):
    return sum(1 for item in data if name in (item.get("people") or []))

html = INDEX.read_text(encoding="utf-8-sig")

for href, name in people.items():
    count = count_for(name)

    # Find this person's tree card and update or insert the tree-count element.
    card_match = re.search(
        rf'(<a class="tree-person[^"]*" href="{re.escape(href)}">.*?</a>)',
        html,
        flags=re.S
    )
    if not card_match:
        raise SystemExit(f"ERROR: Could not find tree card for {href}")

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
        # Insert count after the relation text, before closing </a>.
        new_card = re.sub(
            r'(</div>\s*)(</a>)$',
            rf'\1<div class="tree-count" data-archive-person="{name}">{count} archive items</div>\n\2',
            card,
            count=1,
            flags=re.S
        )

    html = html[:card_match.start()] + new_card + html[card_match.end():]
    print(f"{name}: {count} archive items")

INDEX.write_text(html, encoding="utf-8", newline="\n")

print()
print("TREE ARCHIVE COUNTS UPDATED")
print("Backup:", backup)
print("Updated index.html for Sophia Bell, Olivia Bell, and Ivy Bell.")
print("No Git commit or push was performed.")

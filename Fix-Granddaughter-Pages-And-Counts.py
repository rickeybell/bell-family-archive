from pathlib import Path
from datetime import datetime
import json, re, shutil

ROOT = Path(r"C:\Users\rbell\OneDrive\Documents\GitHub\bell-family-archive")
META = ROOT / "photo_metadata.json"
BUILDER = ROOT / "tools" / "build_dynamic_gallery.py"

people = {
    "sophia": {"old": "Sophia", "name": "Sophia Bell", "born": "November 21, 2016"},
    "olivia": {"old": "Olivia", "name": "Olivia Bell", "born": "May 22, 2025"},
    "ivy": {"old": "Ivy", "name": "Ivy Bell", "born": "May 3, 2022"},
}

if not META.exists():
    raise SystemExit(f"ERROR: Missing {META}")

data = json.loads(META.read_text(encoding="utf-8"))

backup = Path.home() / "Documents" / "BellWebsite-Backups" / f"GranddaughterPages-{datetime.now():%Y%m%d-%H%M%S}"
backup.mkdir(parents=True, exist_ok=True)

def count_for(name):
    return sum(1 for item in data if name in (item.get("people") or []))

# Update the three personal pages.
for slug, info in people.items():
    page = ROOT / f"{slug}.html"
    if not page.exists():
        raise SystemExit(f"ERROR: Missing {page}")

    shutil.copy2(page, backup / page.name)
    text = page.read_text(encoding="utf-8-sig")

    name = info["name"]
    old = info["old"]
    count = count_for(name)

    # Identity/display text.
    text = re.sub(rf"<title>{re.escape(old)}\s*-\s*The Bell Family Archive</title>",
                  f"<title>{name} - The Bell Family Archive</title>", text)
    text = re.sub(rf'alt="{re.escape(old)}"', f'alt="{name}"', text)
    text = re.sub(rf"<h1>{re.escape(old)}</h1>", f"<h1>{name}</h1>", text)
    text = text.replace(f"A dedicated archive page for {old},", f"A dedicated archive page for {name},")
    text = text.replace(f"tagged with {old}.", f"tagged with {name}.")

    # Accurate current archive count.
    text = re.sub(
        r'<div class="person-count">\d+\s+currently identified archive items</div>',
        f'<div class="person-count">{count} currently identified archive items</div>',
        text
    )

    # Point the Current Photo Archive section at the person's generated archive.
    text = re.sub(
        r'<p><a href="gallery\.html"><strong>Open the main photo gallery &rarr;</strong></a></p>',
        f'<p><a href="{slug}-photos.html"><strong>Open {name} photo archive &rarr;</strong></a></p>',
        text
    )

    page.write_text(text, encoding="utf-8", newline="\n")
    print(f"{name}: {count} identified archive items")

# Make the generated person-photo archives use the exact DigiKam person tags.
if BUILDER.exists():
    shutil.copy2(BUILDER, backup / BUILDER.name)
    b = BUILDER.read_text(encoding="utf-8-sig")

    replacements = {
        "'sophia':'Sophia'": "'sophia':'Sophia Bell'",
        "'olivia':'Olivia'": "'olivia':'Olivia Bell'",
        "'ivy':'Ivy'": "'ivy':'Ivy Bell'",
    }
    for old, new in replacements.items():
        b = b.replace(old, new)

    BUILDER.write_text(b, encoding="utf-8", newline="\n")
    print("Updated build_dynamic_gallery.py to use exact DigiKam tags:")
    print("  Sophia Bell / Olivia Bell / Ivy Bell")
else:
    print("WARNING: tools/build_dynamic_gallery.py not found; personal pages were still updated.")

print()
print("Backup:", backup)
print("No Git commit or push was performed.")

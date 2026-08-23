from pathlib import Path
import shutil
from datetime import datetime

repo = Path(r"C:\\Users\\rbell\\OneDrive\\Documents\\GitHub\\bell-family-archive")
index = repo / "index.html"
if not index.exists():
    raise SystemExit(f"ERROR: {index} not found")

text = index.read_text(encoding="utf-8")
backup = index.with_name(f"index.html.before-granddaughter-names-{datetime.now():%Y%m%d-%H%M%S}.bak")
shutil.copy2(index, backup)

for href, old, new in [
    ('href="sophia.html"', "Sophia", "Sophia Bell"),
    ('href="olivia.html"', "Olivia", "Olivia Bell"),
    ('href="ivy.html"', "Ivy", "Ivy Bell"),
]:
    pos = text.find(href)
    if pos < 0:
        raise SystemExit(f"ERROR: Could not find {href}")
    end = min(len(text), pos + 1500)
    block = text[pos:end]
    needle = f">{old}<"
    if needle not in block:
        raise SystemExit(f"ERROR: Could not safely locate displayed name {old} near {href}")
    block = block.replace(needle, f">{new}<", 1)
    text = text[:pos] + block + text[end:]

index.write_text(text, encoding="utf-8")
print("Updated index.html: Sophia Bell, Olivia Bell, Ivy Bell")
print("HTML filenames and person-filter/tag logic unchanged.")
print(f"Backup: {backup}")
print("No Git commit or push performed.")

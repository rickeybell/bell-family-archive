#!/usr/bin/env python3
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT / 'photo_metadata.json').read_text(encoding='utf-8'))

# Current image path by filename. Only use filenames that are unique in the archive.
paths = {}
duplicates = set()
for item in DATA:
    name = item.get('file')
    path = item.get('path')
    if not name or not path:
        continue
    if name in paths and paths[name] != path:
        duplicates.add(name)
    else:
        paths[name] = path
for name in duplicates:
    paths.pop(name, None)

# Repair HTML src/href attributes that still reference an old images/... location.
attr_re = re.compile(r'(?P<prefix>\b(?:src|href)=["\'])(?P<path>images/[^"\']+)(?P<suffix>["\'])', re.I)

changed = 0
repaired = 0
for html_file in ROOT.glob('*.html'):
    text = html_file.read_text(encoding='utf-8')

    def repl(m):
        nonlocal_count = None
        old = m.group('path')
        filename = pathlib.PurePosixPath(old).name
        new = paths.get(filename)
        if new and new != old:
            # Count through mutable outer list.
            count[0] += 1
            return m.group('prefix') + new + m.group('suffix')
        return m.group(0)

    count = [0]
    new_text = attr_re.sub(repl, text)
    if new_text != text:
        html_file.write_text(new_text, encoding='utf-8')
        changed += 1
        repaired += count[0]
        print(f'{html_file.name}: repaired {count[0]} image links')

print(f'Repaired {repaired} moved image links across {changed} HTML files')
if duplicates:
    print(f'Skipped {len(duplicates)} duplicate filenames because their destination was ambiguous')

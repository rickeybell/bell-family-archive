#!/usr/bin/env python3
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT / 'photo_metadata.json').read_text(encoding='utf-8'))
current_paths = {x.get('path') for x in DATA if x.get('path')}
current_names = {pathlib.PurePosixPath(p).name for p in current_paths}

people = {
    'dickey.html':'dickey-photos.html',
    'spooky.html':'spooky-photos.html',
    'buster.html':'buster-photos.html',
    'alma.html':'alma-photos.html',
    'rickey.html':'rickey-photos.html',
    'sonja.html':'sonja-photos.html',
    'heather.html':'heather-photos.html',
    'stephanie.html':'stephanie-photos.html',
    'jarred.html':'jarred-photos.html',
}

for page, gallery in people.items():
    f = ROOT / page
    if not f.exists():
        continue
    text = f.read_text(encoding='utf-8')
    original = text

    # Make any navigation link labelled Photo Gallery use the current generated page.
    text = re.sub(r'<a([^>]*?)href=["\']#archive["\']([^>]*?)>\s*Photo Gallery\s*</a>',
                  lambda m: f'<a{m.group(1)}href="{gallery}"{m.group(2)}>Photo Gallery</a>', text, flags=re.I)

    # Also point the sidebar "All Photos & Documents" link to the generated current gallery.
    text = re.sub(r'(<a[^>]*class=["\'][^"\']*sidebar-all[^"\']*["\'][^>]*?)href=["\']#archive["\']',
                  lambda m: m.group(1) + f'href="{gallery}"', text, flags=re.I)

    # Remove legacy photo cards whose referenced image no longer exists anywhere in the archive.
    fig_re = re.compile(r'<figure\b[^>]*class=["\'][^"\']*photo-card[^"\']*["\'][^>]*>.*?</figure>', re.I | re.S)
    removed = [0]
    def clean_fig(m):
        block = m.group(0)
        sm = re.search(r'\bsrc=["\'](images/[^"\']+)["\']', block, re.I)
        if not sm:
            return block
        src = sm.group(1)
        name = pathlib.PurePosixPath(src).name
        if src not in current_paths and name not in current_names:
            removed[0] += 1
            return ''
        return block
    text = fig_re.sub(clean_fig, text)

    # Add a clearly visible link to the live, tag-driven gallery near the start of the main content.
    if 'data-current-photo-gallery' not in text:
        marker = '<main class="archive-content">'
        banner = f'''<section class="tree-note" data-current-photo-gallery="true"><h2>Current Photo Archive</h2><p>This page preserves the family biography and stories. The photo collection is maintained automatically from the current files and DigiKam metadata.</p><p><a href="{gallery}"><strong>Open the current photo gallery →</strong></a></p></section>'''
        if marker in text:
            text = text.replace(marker, marker + banner, 1)

    if text != original:
        f.write_text(text, encoding='utf-8')
        print(f'{page}: linked to {gallery}; removed {removed[0]} deleted legacy photo cards')

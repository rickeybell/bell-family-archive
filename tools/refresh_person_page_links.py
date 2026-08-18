#!/usr/bin/env python3
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[1]

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

    # Any Photo Gallery navigation goes to the current metadata-driven page.
    text = re.sub(
        r'<a([^>]*?)href=["\'](?:#archive|[^"\']*-photos\.html)["\']([^>]*?)>\s*Photo Gallery\s*</a>',
        lambda m: f'<a{m.group(1)}href="{gallery}"{m.group(2)}>Photo Gallery</a>',
        text, flags=re.I)

    # Remove the old sidebar. Its year/person counts and anchors belong to the retired hand-built gallery.
    text = re.sub(r'<aside\b[^>]*class=["\'][^"\']*archive-sidebar[^"\']*["\'][^>]*>.*?</aside>', '', text, flags=re.I|re.S)

    # Remove every old hand-built year gallery section and archive heading from biography pages.
    text = re.sub(r'<section\b[^>]*class=["\'][^"\']*year-section[^"\']*["\'][^>]*>.*?</section>', '', text, flags=re.I|re.S)
    text = re.sub(r'<div\b[^>]*class=["\'][^"\']*archive-heading[^"\']*["\'][^>]*>.*?</div>', '', text, flags=re.I|re.S)

    # Remove any remaining legacy photo cards outside year sections.
    text = re.sub(r'<figure\b[^>]*class=["\'][^"\']*photo-card[^"\']*["\'][^>]*>.*?</figure>', '', text, flags=re.I|re.S)

    # Replace an existing current-gallery notice, or add one at the start of main content.
    banner = f'''<section class="tree-note" data-current-photo-gallery="true"><h2>Current Photo Archive</h2><p>The photographs are generated directly from the files and DigiKam metadata currently in the archive.</p><p><a href="{gallery}"><strong>Open the current photo gallery →</strong></a></p></section>'''
    text = re.sub(r'<section\b[^>]*data-current-photo-gallery=["\']true["\'][^>]*>.*?</section>', banner, text, flags=re.I|re.S)
    if 'data-current-photo-gallery="true"' not in text:
        marker = '<main class="archive-content">'
        if marker in text:
            text = text.replace(marker, marker + banner, 1)

    if text != original:
        f.write_text(text, encoding='utf-8')
        print(f'{page}: removed legacy photo archive; linked to {gallery}')

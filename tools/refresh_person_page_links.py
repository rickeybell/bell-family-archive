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

SHELL_STYLE = 'display:block;max-width:1600px;margin:0 auto;'
MAIN_STYLE = 'width:100%;max-width:1500px;margin:0 auto;min-width:0;padding:28px 34px 50px;'

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

    # Remove the retired sidebar and hand-built photo archive.
    text = re.sub(r'<aside\b[^>]*class=["\'][^"\']*archive-sidebar[^"\']*["\'][^>]*>.*?</aside>', '', text, flags=re.I|re.S)
    text = re.sub(r'<section\b[^>]*class=["\'][^"\']*year-section[^"\']*["\'][^>]*>.*?</section>', '', text, flags=re.I|re.S)
    text = re.sub(r'<div\b[^>]*class=["\'][^"\']*archive-heading[^"\']*["\'][^>]*>.*?</div>', '', text, flags=re.I|re.S)
    text = re.sub(r'<figure\b[^>]*class=["\'][^"\']*photo-card[^"\']*["\'][^>]*>.*?</figure>', '', text, flags=re.I|re.S)

    # The sidebar is gone, so write the one-column layout into the HTML itself.
    # This avoids stale CSS/JS caches leaving main content in the old 270px grid column.
    text = re.sub(
        r'<div\s+class=["\']site-shell["\'](?:\s+style=["\'][^"\']*["\'])?\s*>',
        f'<div class="site-shell" style="{SHELL_STYLE}">',
        text, count=1, flags=re.I)
    text = re.sub(
        r'<main\s+class=["\']archive-content["\'](?:\s+style=["\'][^"\']*["\'])?\s*>',
        f'<main class="archive-content" style="{MAIN_STYLE}">',
        text, count=1, flags=re.I)

    # Replace an existing current-gallery notice, or add one at the start of main content.
    banner = f'''<section class="tree-note" data-current-photo-gallery="true"><h2>Current Photo Archive</h2><p>The photographs are generated directly from the files and DigiKam metadata currently in the archive.</p><p><a href="{gallery}"><strong>Open the current photo gallery →</strong></a></p></section>'''
    text = re.sub(r'<section\b[^>]*data-current-photo-gallery=["\']true["\'][^>]*>.*?</section>', banner, text, flags=re.I|re.S)
    if 'data-current-photo-gallery="true"' not in text:
        marker = f'<main class="archive-content" style="{MAIN_STYLE}">'
        if marker in text:
            text = text.replace(marker, marker + banner, 1)

    if text != original:
        f.write_text(text, encoding='utf-8')
        print(f'{page}: full-width biography layout; linked to {gallery}')

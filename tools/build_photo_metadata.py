#!/usr/bin/env python3
# Generates the authoritative site metadata catalog from embedded photo metadata.
import json, subprocess, pathlib, re
ROOT=pathlib.Path(__file__).resolve().parents[1]
IMG=ROOT/'images'
exts={'.jpg','.jpeg','.png','.JPG','.JPEG','.PNG'}
files=[p for p in IMG.rglob('*') if p.is_file() and p.suffix in exts]
if not files:
    raise SystemExit('No images found')
base_cmd = [
    'exiftool', '-json', '-n',
    '-DateTimeOriginal', '-CreateDate', '-DateCreated',
    '-Subject', '-Keywords', '-HierarchicalSubject', '-TagsList',
    '-CatalogSets', '-LastKeywordXMP',
    '-Description', '-Caption-Abstract', '-Title',
    '-GPSLatitude', '-GPSLongitude',
    '-Location', '-Sublocation', '-Sub-location',
    '-City', '-State', '-Province-State',
    '-Country', '-Country-PrimaryLocationName'
]

raw = []

batch_size = 200

for i in range(0, len(files), batch_size):
    batch = files[i:i + batch_size]
    cmd = base_cmd + [str(p) for p in batch]
    batch_raw = json.loads(subprocess.check_output(cmd))
    raw.extend(batch_raw)

    print(f"Read metadata {min(i + batch_size, len(files))}/{len(files)}")
out=[]
STATE_ABBR={
    'Alabama':'AL','Alaska':'AK','Arizona':'AZ','Arkansas':'AR','California':'CA','Colorado':'CO','Connecticut':'CT','Delaware':'DE','Florida':'FL','Georgia':'GA','Hawaii':'HI','Idaho':'ID','Illinois':'IL','Indiana':'IN','Iowa':'IA','Kansas':'KS','Kentucky':'KY','Louisiana':'LA','Maine':'ME','Maryland':'MD','Massachusetts':'MA','Michigan':'MI','Minnesota':'MN','Mississippi':'MS','Missouri':'MO','Montana':'MT','Nebraska':'NE','Nevada':'NV','New Hampshire':'NH','New Jersey':'NJ','New Mexico':'NM','New York':'NY','North Carolina':'NC','North Dakota':'ND','Ohio':'OH','Oklahoma':'OK','Oregon':'OR','Pennsylvania':'PA','Rhode Island':'RI','South Carolina':'SC','South Dakota':'SD','Tennessee':'TN','Texas':'TX','Utah':'UT','Vermont':'VT','Virginia':'VA','Washington':'WA','West Virginia':'WV','Wisconsin':'WI','Wyoming':'WY','District of Columbia':'DC'
}
def place_from_tags(tags):
    paths=[]
    for rawtag in tags:
        s=str(rawtag).strip().replace('\\','/').replace('|','/')
        if not s.lower().startswith('places/'):
            continue
        parts=[x.strip() for x in s.split('/') if x.strip()]
        if len(parts)>1:
            paths.append(parts[1:])
    if not paths:
        return '', '', '', ''
    # Prefer the deepest Places hierarchy (e.g. SC/Lancaster/Mason St over SC/Lancaster).
    parts=max(paths,key=len)
    state=parts[0] if len(parts)>=1 else ''
    city=parts[1] if len(parts)>=2 else ''
    location=', '.join(parts[2:]) if len(parts)>=3 else ''
    return location, city, state, 'United States' if state in STATE_ABBR or state in STATE_ABBR.values() else ''
for m in raw:
    p=pathlib.Path(m['SourceFile'])
    rel=p.relative_to(ROOT).as_posix()
    folder=p.parent.name if p.parent!=IMG else ''
    def first(*keys):
        for k in keys:
            v=m.get(k)
            if v not in (None,'',[]): return v
        return ''
    date=first('DateTimeOriginal','DateCreated','CreateDate')
    if date:
        date=str(date).replace(':','-',2).split(' ')[0]
    elif re.fullmatch(r'\d{4}',folder):
        date=folder
    vals=[]
    for k in ('HierarchicalSubject','Subject','Keywords','TagsList','LastKeywordXMP'):
        v=m.get(k,[])
        if isinstance(v,str): v=[v]
        vals.extend(v or [])
    people=[]; tags=[]
    for v in vals:
        s=str(v).strip(); tags.append(s)
        low=s.lower().replace('\\','/').replace('|','/')
        if low.startswith('people/'):
            people.append(s.replace('\\','/').replace('|','/').split('/')[-1])
    known=('Dickey','Spooky','Buster','Alma','Rickey','Sonja','Heather','Stephanie','Jarred','Dickey Bell','Spooky Bell','Buster Bell','Alma Bell','Rickey Bell','Sonja Bell','Heather Bell','Stephanie Bell','Jarred Bell')
    for s in tags:
        if s in known and s not in people: people.append(s)
    location=first('Location','Sublocation','Sub-location')
    city=first('City')
    state=first('State','Province-State')
    country=first('Country','Country-PrimaryLocationName')
    tag_location,tag_city,tag_state,tag_country=place_from_tags(tags)
    if not location: location=tag_location
    if not city: city=tag_city
    if not state: state=tag_state
    if not country: country=tag_country
    out.append({
        'path':rel,'file':p.name,'folder':folder,'date':date,
        'people':sorted(set(people)),'tags':sorted(set(tags)),
        'title':first('Title'),'description':first('Description','Caption-Abstract'),
        'location':location,'city':city,'state':state,'country':country,
        'gps':{'lat':m.get('GPSLatitude'),'lon':m.get('GPSLongitude')} if m.get('GPSLatitude') is not None and m.get('GPSLongitude') is not None else None
    })
out.sort(key=lambda x:(x['date'] or '9999',x['path'].lower()))
(ROOT/'photo_metadata.json').write_text(json.dumps(out,indent=2,ensure_ascii=False),encoding='utf-8')
print(f'Wrote {len(out)} records')
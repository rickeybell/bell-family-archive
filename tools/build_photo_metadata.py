#!/usr/bin/env python3
# Generates the authoritative site metadata catalog from embedded photo metadata.
import json, subprocess, pathlib, re
ROOT=pathlib.Path(__file__).resolve().parents[1]
IMG=ROOT/'images'
exts={'.jpg','.jpeg','.png','.JPG','.JPEG','.PNG'}
files=[p for p in IMG.rglob('*') if p.is_file() and p.suffix in exts]
if not files:
    raise SystemExit('No images found')
cmd=['exiftool','-json','-n','-DateTimeOriginal','-CreateDate','-DateCreated','-Subject','-Keywords','-HierarchicalSubject','-Description','-Caption-Abstract','-Title','-GPSLatitude','-GPSLongitude']+[str(p) for p in files]
raw=json.loads(subprocess.check_output(cmd))
out=[]
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
    for k in ('HierarchicalSubject','Subject','Keywords'):
        v=m.get(k,[])
        if isinstance(v,str): v=[v]
        vals.extend(v or [])
    people=[]; tags=[]
    for v in vals:
        s=str(v).strip(); tags.append(s)
        low=s.lower().replace('\\','/')
        if low.startswith('people/'):
            people.append(s.split('/')[-1])
        elif low.startswith('people|'):
            people.append(s.split('|')[-1])
    known=('Dickey','Spooky','Buster','Alma','Rickey','Sonja','Heather','Stephanie','Jarred','Dickey Bell','Spooky Bell','Buster Bell','Alma Bell','Rickey Bell','Sonja Bell','Heather Bell','Stephanie Bell','Jarred Bell')
    for s in tags:
        if s in known and s not in people: people.append(s)
    out.append({'path':rel,'file':p.name,'folder':folder,'date':date,'people':sorted(set(people)),'tags':sorted(set(tags)),'title':first('Title'),'description':first('Description','Caption-Abstract'),'gps':{'lat':m.get('GPSLatitude'),'lon':m.get('GPSLongitude')} if m.get('GPSLatitude') is not None and m.get('GPSLongitude') is not None else None})
out.sort(key=lambda x:(x['date'] or '9999',x['path'].lower()))
(ROOT/'photo_metadata.json').write_text(json.dumps(out,indent=2,ensure_ascii=False),encoding='utf-8')
print(f'Wrote {len(out)} records')

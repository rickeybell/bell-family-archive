#!/usr/bin/env python3
import argparse, csv, os, pathlib, re, sqlite3

AUDIO_EXTS={'.mp3','.m4a','.wav','.aac','.flac','.wma','.ogg','.oga','.opus'}


def find_db(source_root: pathlib.Path):
    env=os.environ.get('DIGIKAM_DB')
    candidates=[]
    if env: candidates.append(pathlib.Path(env))
    home=pathlib.Path.home()
    for p in [
        source_root/'digikam4.db', source_root/'.digikam'/'digikam4.db',
        home/'Pictures'/'digikam4.db', home/'OneDrive'/'Pictures'/'digikam4.db',
        home/'digikam4.db',
        pathlib.Path(os.environ.get('LOCALAPPDATA',''))/'digikam'/'digikam4.db' if os.environ.get('LOCALAPPDATA') else None,
        pathlib.Path(os.environ.get('APPDATA',''))/'digikam'/'digikam4.db' if os.environ.get('APPDATA') else None,
    ]:
        if p: candidates.append(p)
    for p in candidates:
        if p.exists() and p.is_file(): return p
    roots=[]
    for r in [source_root, home/'OneDrive', home/'Pictures']:
        if r.exists() and r not in roots: roots.append(r)
    for r in roots:
        try:
            for p in r.rglob('digikam4.db'):
                if '.dtrash' in {part.lower() for part in p.parts}:
                    continue
                if p.is_file(): return p
        except OSError:
            pass
    return None


def table_exists(con, name):
    return con.execute("select 1 from sqlite_master where type='table' and name=?",(name,)).fetchone() is not None


def cols(con, table):
    if not table_exists(con,table): return set()
    return {r[1] for r in con.execute(f'pragma table_info("{table}")')}


def tag_paths(con):
    data={}
    if not table_exists(con,'Tags'): return data
    rows=con.execute('select id,pid,name from Tags').fetchall()
    raw={int(r[0]):(int(r[1]) if r[1] is not None else 0,str(r[2] or '')) for r in rows}
    def build(tid, seen=None):
        if tid in data:return data[tid]
        if tid not in raw:return ''
        seen=set() if seen is None else seen
        if tid in seen:return raw[tid][1]
        seen.add(tid)
        pid,name=raw[tid]
        parent=build(pid,seen) if pid and pid in raw else ''
        val=(parent+'/'+name).strip('/') if parent else name
        data[tid]=val
        return val
    for tid in raw: build(tid)
    return data


def get_comment(con,image_id):
    c=cols(con,'ImageComments')
    if not c or 'imageid' not in c or 'comment' not in c:return ''
    order=[]
    if 'type' in c: order.append('type')
    if 'id' in c: order.append('id')
    sql='select comment from ImageComments where imageid=? and comment is not null and trim(comment)<>\'\''
    if order: sql+=' order by '+','.join(order)
    row=con.execute(sql,(image_id,)).fetchone()
    return str(row[0]) if row and row[0] is not None else ''


def get_date(con,image_id):
    c=cols(con,'ImageInformation')
    if not c or 'imageid' not in c:return ''
    choices=[x for x in ('creationDate','digitizationDate') if x in c]
    if not choices:return ''
    row=con.execute('select '+','.join(choices)+' from ImageInformation where imageid=?',(image_id,)).fetchone()
    if not row:return ''
    for v in row:
        if v:return str(v)
    return ''


def normalized_date(value):
    value=str(value or '').strip()
    if not value:return ''
    return value.replace('T',' ').split(' ')[0].replace(':','-',2)


def year_from_date(value):
    d=normalized_date(value)
    m=re.match(r'^((?:18|19|20)\d{2})',d)
    return int(m.group(1)) if m else None


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--source-root',required=True)
    ap.add_argument('--output',required=True)
    ap.add_argument('--from-year',type=int,default=0)
    ap.add_argument('--to-year',type=int,default=9999)
    args=ap.parse_args()
    source_root=pathlib.Path(args.source_root).resolve()
    out=pathlib.Path(args.output)
    db=find_db(source_root)
    if not db:
        raise SystemExit('Could not locate DigiKam SQLite database (digikam4.db). Set DIGIKAM_DB to its full path if needed.')
    print(f'DigiKam database: {db}')
    con=sqlite3.connect(f'file:{db.as_posix()}?mode=ro',uri=True)
    con.row_factory=sqlite3.Row
    required={'Images','Albums','Tags','ImageTags'}
    missing=[t for t in required if not table_exists(con,t)]
    if missing: raise SystemExit('DigiKam database is missing expected tables: '+', '.join(missing))
    tpaths=tag_paths(con)

    disk=[]
    for p in source_root.rglob('*'):
        if p.is_file() and p.suffix.lower() in AUDIO_EXTS and '.dtrash' not in {x.lower() for x in p.parts}:
            disk.append(p)
    by_name={}
    for p in disk: by_name.setdefault(p.name.lower(),[]).append(p)

    rows=[]; db_matches=0; website=0; date_year_fallbacks=0
    q='''select i.id imageid,i.name,a.relativePath from Images i join Albums a on a.id=i.album where lower(i.name)=lower(?)'''
    for name,candidates in sorted(by_name.items()):
        recs=con.execute(q,(candidates[0].name,)).fetchall()
        for rec in recs:
            rel_album=str(rec['relativePath'] or '').replace('\\','/').strip('/')
            chosen=None
            for p in candidates:
                rel=p.relative_to(source_root).as_posix()
                parent=pathlib.PurePosixPath(rel).parent.as_posix().strip('.')
                if not rel_album or parent.lower().endswith(rel_album.lower()):
                    chosen=p; break
            if chosen is None:
                if len(candidates)==1: chosen=candidates[0]
                else: continue
            db_matches+=1
            image_id=int(rec['imageid'])
            tids=[int(r[0]) for r in con.execute('select tagid from ImageTags where imageid=?',(image_id,)).fetchall()]
            paths=[tpaths.get(t,'') for t in tids if tpaths.get(t,'')]
            leaves=[p.replace('\\','/').split('/')[-1].strip() for p in paths]
            if not any(x.lower()=='website' for x in leaves): continue
            website+=1

            source_rel=chosen.relative_to(source_root).as_posix()
            source_parts=source_rel.split('/')
            if any(re.fullmatch(r'(18|19|20)\d0s',x) for x in source_parts): continue

            db_date=normalized_date(get_date(con,image_id))
            year=None
            for part in source_parts:
                if re.fullmatch(r'(18|19|20)\d{2}',part):
                    year=int(part); break
            if year is None:
                year=year_from_date(db_date)
                if year is not None:
                    date_year_fallbacks+=1
            if year is None or year<args.from_year or year>args.to_year: continue

            # Website audio always lives under audio/<year>/ even when the source
            # master is stored in a non-year DigiKam album such as Dad or Voicemail.
            rel=f'{year}/{chosen.name}'

            people=[]
            for tp in paths:
                n=tp.replace('\\','/')
                if n.lower().startswith('people/'):
                    leaf=n.split('/')[-1].strip()
                    if leaf and leaf not in people: people.append(leaf)
            clean=[]
            for tp in paths:
                leaf=tp.replace('\\','/').split('/')[-1].strip()
                if leaf.lower()=='website': continue
                if tp not in clean: clean.append(tp)
            if not any(x.replace('\\','/').split('/')[-1].strip().lower()=='sound' for x in clean): clean.append('Sound')

            description=get_comment(con,image_id)
            rows.append({
                'SourcePath':str(chosen),'RelativePath':rel.replace('/','\\'),
                'DestinationPath':'','FileName':chosen.name,'Date':db_date,
                'People':'; '.join(people),'Title':'','Description':description,
                'Tags':'; '.join(clean),'GPSLatitude':'','GPSLongitude':'',
                'Length':chosen.stat().st_size,'LastWriteUtc':chosen.stat().st_mtime_ns
            })
            break
    con.close()
    fields=['SourcePath','RelativePath','DestinationPath','FileName','Date','People','Title','Description','Tags','GPSLatitude','GPSLongitude','Length','LastWriteUtc']
    out.parent.mkdir(parents=True,exist_ok=True)
    with out.open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(sorted(rows,key=lambda r:r['RelativePath'].lower()))
    print(f'Audio files on disk:              {len(disk)}')
    print(f'Audio files matched in DigiKam:   {db_matches}')
    print(f'Website-tagged audio selected:    {len(rows)}')
    print(f'DigiKam Website matches total:    {website}')
    print(f'Year from DigiKam date fallback:  {date_year_fallbacks}')
    print(f'Audio manifest: {out}')

if __name__=='__main__': main()

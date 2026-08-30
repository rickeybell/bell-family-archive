#!/usr/bin/env python3
import argparse, csv, hashlib, json, os, pathlib, re, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PHOTO_MANIFEST = ROOT / "website-photo-manifest.csv"
VIDEO_MANIFEST = ROOT / "website-video-manifest.csv"
AUDIO_MANIFEST = ROOT / "website-audio-manifest.csv"
OUT = ROOT / "photo_metadata.json"
CACHE = ROOT / ".website-metadata-cache.json"

parser=argparse.ArgumentParser()
parser.add_argument('--full-audit',action='store_true')
args=parser.parse_args()

metadata_cache={}
cache_existed=CACHE.exists()
if cache_existed:
    try: metadata_cache=json.loads(CACHE.read_text(encoding='utf-8-sig')).get('records',{})
    except (OSError,ValueError,TypeError): metadata_cache={}

previous_by_path={}
if OUT.exists():
    try:
        previous_by_path={str(x.get("path") or "").lower():x for x in json.loads(OUT.read_text(encoding="utf-8")) if x.get("path")}
    except (OSError,ValueError,TypeError):
        previous_by_path={}

if not PHOTO_MANIFEST.exists() and not VIDEO_MANIFEST.exists() and not AUDIO_MANIFEST.exists():
    raise SystemExit("No website photo/video/audio manifest found")

def eligible_rows(path, media_type):
    rows=[]
    if not path.exists(): return rows
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            src=pathlib.Path(row.get("SourcePath") or "")
            rel=(row.get("RelativePath") or "").replace(chr(92),"/").lstrip("/")
            if not rel: continue
            if any(re.fullmatch(r"(18|19|20)\d0s", p) for p in rel.split("/")): continue
            prefix={"video":"videos/","audio":"audio/"}.get(media_type,"images/")
            previous=previous_by_path.get((prefix+rel).lower())
            if not src.exists():
                if previous and (ROOT/(prefix+rel)).exists():
                    rows.append({"src":src,"rel":rel,"media_type":media_type,"row":row,"previous":previous})
                continue
            rows.append({"src":src,"rel":rel,"media_type":media_type,"row":row,"previous":None})
    return rows

rows=(eligible_rows(PHOTO_MANIFEST,"photo") + eligible_rows(VIDEO_MANIFEST,"video") + eligible_rows(AUDIO_MANIFEST,"audio"))
if not rows: raise SystemExit("No eligible manifest records found")

def public_path(item):
    prefix={"video":"videos/","audio":"audio/"}.get(item["media_type"],"images/")
    return prefix+item["rel"]

def item_signature(item):
    row=item["row"]
    state={"source":str(item["src"]),"type":item["media_type"],
           "length":str(row.get("Length") or ""),"mtime":str(row.get("LastWriteUtc") or "")}
    if item["media_type"]=="audio": state["manifest"]=row
    return hashlib.sha256(json.dumps(state,sort_keys=True).encode('utf-8')).hexdigest()

for item in rows:
    item["public_path"]=public_path(item)
    item["signature"]=item_signature(item)
    cached=metadata_cache.get(item["public_path"].lower())
    if not args.full_audit and cached and cached.get("signature")==item["signature"]:
        item["cached_record"]=cached.get("record")
    elif not args.full_audit and not cache_existed:
        item["cached_record"]=previous_by_path.get(item["public_path"].lower())

cmd0=["exiftool","-json","-n","-DateTimeOriginal","-CreateDate","-DateCreated",
      "-Subject","-Keywords","-HierarchicalSubject","-TagsList","-LastKeywordXMP",
      "-Description","-Caption-Abstract","-Title","-PersonInImage","-RegionPersonDisplayName",
      "-GPSLatitude","-GPSLongitude","-Location","-Sublocation","-Sub-location","-City","-State",
      "-Province-State","-Country","-Country-PrimaryLocationName"]

meta={}
sources=[x["src"] for x in rows if x["media_type"]!="audio" and not x.get("previous") and not x.get("cached_record")]
for i in range(0,len(sources),150):
    batch=sources[i:i+150]
    recs=json.loads(subprocess.check_output(cmd0+[str(p) for p in batch]))
    for m in recs: meta[str(pathlib.Path(m["SourceFile"]).resolve()).lower()]=m
    print(f"Read master metadata {min(i+150,len(sources))}/{len(sources)}")

STATE_ABBR={'South Carolina':'SC','North Carolina':'NC','Florida':'FL','Georgia':'GA','Virginia':'VA','Tennessee':'TN','New York':'NY','Pennsylvania':'PA','Maryland':'MD','Alabama':'AL','Mississippi':'MS','Texas':'TX','California':'CA','Ohio':'OH','West Virginia':'WV'}

def first(m,*keys):
    for k in keys:
        v=m.get(k)
        if v not in (None,"",[]): return v
    return ""

def split_manifest(value):
    return [x.strip() for x in str(value or '').split(';') if x.strip()]

def tags_for(m):
    vals=[]
    for k in ("HierarchicalSubject","Subject","Keywords","TagsList","LastKeywordXMP"):
        v=m.get(k,[])
        if isinstance(v,str): v=[v]
        vals.extend(v or [])
    out=[]
    for v in vals:
        s=str(v).strip()
        if not s: continue
        leaf=re.split(r"[|/\\]",s)[-1].strip()
        if s.lower()=="website" or leaf.lower()=="website": continue
        if s not in out: out.append(s)
    return out

def place_from_tags(tags):
    paths=[]
    for raw in tags:
        s=str(raw).strip().replace(chr(92),"/").replace("|","/")
        if s.lower().startswith("places/"):
            parts=[x.strip() for x in s.split("/") if x.strip()]
            if len(parts)>1: paths.append(parts[1:])
    if not paths:return "","","",""
    parts=max(paths,key=len);state=parts[0] if len(parts)>0 else "";city=parts[1] if len(parts)>1 else "";loc=", ".join(parts[2:]) if len(parts)>2 else ""
    country="United States" if state in STATE_ABBR or state in STATE_ABBR.values() else ""
    return loc,city,state,country

out=[]
for item in rows:
    src=item["src"];rel=item["rel"];media_type=item["media_type"];manifest=item["row"]
    folder=pathlib.PurePosixPath(rel).parent.name

    if item.get("previous"):
        out.append(item["previous"])
        print("WARNING preserved prior metadata for missing master:",src)
        continue

    if item.get("cached_record"):
        out.append(item["cached_record"])
        continue

    if media_type=="audio":
        tags=split_manifest(manifest.get("Tags"))
        if not any(re.split(r"[|/\\]",t)[-1].strip().lower()=="sound" for t in tags): tags.append("Sound")
        people=split_manifest(manifest.get("People"))
        date=str(manifest.get("Date") or '').strip()
        if date: date=date.replace('T',' ').split(' ')[0].replace(':','-',2)
        elif re.fullmatch(r"\d{4}",folder): date=folder
        loc,city,state,country=place_from_tags(tags)
        lat=str(manifest.get("GPSLatitude") or '').strip();lon=str(manifest.get("GPSLongitude") or '').strip()
        try: gps={"lat":float(lat),"lon":float(lon)} if lat and lon else None
        except ValueError: gps=None
        title=str(manifest.get("Title") or '')
        description=str(manifest.get("Description") or '')
    else:
        m=meta.get(str(src.resolve()).lower())
        if not m:
            print("WARNING no metadata:",src);continue
        date=first(m,"DateTimeOriginal","DateCreated","CreateDate")
        if date: date=str(date).replace(":","-",2).split(" ")[0]
        elif re.fullmatch(r"\d{4}",folder): date=folder
        tags=tags_for(m)
        required_tag={"video":"Video"}.get(media_type)
        if required_tag and not any(re.split(r"[|/\\]",t)[-1].strip().lower()==required_tag.lower() for t in tags): tags.append(required_tag)
        people=[]
        for tag in tags:
            n=tag.replace(chr(92),"/").replace("|","/")
            if n.lower().startswith("people/"):
                name=n.split("/")[-1].strip()
                if name and name not in people: people.append(name)
        for key in ("PersonInImage","RegionPersonDisplayName"):
            v=m.get(key,[])
            if isinstance(v,str): v=[v]
            for name in v or []:
                name=str(name).strip()
                if name and name not in people: people.append(name)
        loc=first(m,"Location","Sublocation","Sub-location");city=first(m,"City");state=first(m,"State","Province-State");country=first(m,"Country","Country-PrimaryLocationName")
        tl,tc,ts,tco=place_from_tags(tags);loc=loc or tl;city=city or tc;state=state or ts;country=country or tco
        gps={"lat":m.get("GPSLatitude"),"lon":m.get("GPSLongitude")} if m.get("GPSLatitude") is not None and m.get("GPSLongitude") is not None else None
        title=first(m,"Title");description=first(m,"Description","Caption-Abstract")

    prefix={"video":"videos/","audio":"audio/"}.get(media_type,"images/")
    out.append({"path":prefix+rel,"media_type":media_type,"file":pathlib.PurePosixPath(rel).name,"folder":folder,"date":date,
                "people":sorted(set(people)),"tags":sorted(set(tags)),"title":title,"description":description,
                "location":loc,"city":city,"state":state,"country":country,"gps":gps})

out.sort(key=lambda x:(x["date"] or "9999",x["path"].lower()))
OUT.write_text(json.dumps(out,indent=2,ensure_ascii=False),encoding="utf-8")
out_by_path={str(record.get("path") or "").lower():record for record in out}
cache_records={}
for item in rows:
    key=item["public_path"].lower();record=out_by_path.get(key)
    if record: cache_records[key]={"signature":item["signature"],"record":record}
fd,temp_name=tempfile.mkstemp(prefix='.website-metadata-cache-',suffix='.tmp',dir=ROOT);os.close(fd)
temp=pathlib.Path(temp_name)
try:
    temp.write_text(json.dumps({"version":1,"records":cache_records},separators=(',',':')),encoding='utf-8')
    os.replace(temp,CACHE)
finally: temp.unlink(missing_ok=True)
photo_count=sum(1 for x in out if x.get("media_type")=="photo");video_count=sum(1 for x in out if x.get("media_type")=="video");audio_count=sum(1 for x in out if x.get("media_type")=="audio")
print(f"Wrote {len(out)} records from DigiKam/master metadata ({photo_count} photos, {video_count} videos, {audio_count} audio)")
print(f"Master metadata reread: {len(sources)}; cached: {len(rows)-len(sources)}")

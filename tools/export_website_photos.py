#!/usr/bin/env python3
"""Fast incremental photo derivative exporter."""

import argparse, csv, hashlib, json, os, pathlib, re, sys, tempfile, uuid
from concurrent.futures import ThreadPoolExecutor, as_completed

try:
    from PIL import Image, ImageOps
except ImportError as exc:
    raise SystemExit("Pillow is required: python -m pip install -r requirements-export.txt") from exc

CACHE_VERSION = 1
ENGINE_VERSION = "pillow-fast-v1"
SETTINGS = {
    "photo_view_max": 1600, "document_view_max": 3000, "thumb_max": 400,
    "photo_quality": 85, "document_quality": 90,
    "highres_scale": 0.50, "highres_min": 3000, "highres_quality": 92,
}


def load_cache(path):
    if not path.is_file(): return {"version": CACHE_VERSION, "records": {}}
    try:
        data=json.loads(path.read_text(encoding="utf-8-sig"))
        if data.get("version") != CACHE_VERSION or not isinstance(data.get("records"),dict):
            raise ValueError("unsupported cache")
        return data
    except Exception as exc:
        print(f"WARNING: derivative cache will be rebuilt: {exc}")
        return {"version": CACHE_VERSION, "records": {}}


def write_json_atomic(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,name=tempfile.mkstemp(prefix=path.stem+"-",suffix=".tmp",dir=path.parent); os.close(fd)
    temp=pathlib.Path(name)
    try:
        temp.write_text(json.dumps(data,separators=(",",":")),encoding="utf-8")
        os.replace(temp,path)
    finally: temp.unlink(missing_ok=True)


def is_placeholder(relative):
    return any(re.fullmatch(r"(18|19|20)\d0s",p) for p in relative.parts)


def path_year(relative):
    for part in relative.parts:
        if re.fullmatch(r"(18|19|20)\d{2}",part): return int(part)
    return None


def is_document(tags):
    return any(seg.strip().casefold() in {"document","newspaper"}
               for tag in (tags or "").split(";") for seg in re.split(r"[|/]",tag))


def open_oriented(path):
    with Image.open(path) as original:
        image=ImageOps.exif_transpose(original); image.load()
        if image.mode=="P": image=image.convert("RGBA" if "transparency" in image.info else "RGB")
        else: image=image.copy()
    return image


def pixel_hash(image):
    digest=hashlib.sha256(f"{image.mode}:{image.width}x{image.height}".encode("ascii"))
    for top in range(0,image.height,256):
        digest.update(image.crop((0,top,image.width,min(image.height,top+256))).tobytes())
    return digest.hexdigest()


def file_hash(path):
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        while chunk:=stream.read(1024*1024): digest.update(chunk)
    return digest.hexdigest()


def scaled_size(size,maximum):
    width,height=size; scale=min(1.0,maximum/max(width,height))
    return max(1,round(width*scale)),max(1,round(height*scale))


def highres_max(size):
    source_max=max(size)
    return min(source_max,max(SETTINGS["highres_min"],round(source_max*SETTINGS["highres_scale"])))


def output_paths(root,relative):
    native=pathlib.Path(*relative.parts)
    return {name:root/name/native for name in ("images","thumbs","highres")}


def config_signature(document):
    data={"engine":ENGINE_VERSION,"document":document,**SETTINGS}
    return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()


def outputs_match_record(paths,record):
    if not record: return False
    saved=record.get("outputs",{})
    for name,path in paths.items():
        try:
            if path.stat().st_size!=int(saved[name]["size"]): return False
        except (FileNotFoundError,KeyError,TypeError,ValueError): return False
    return True


def outputs_have_dimensions(paths,expected):
    for name,path in paths.items():
        try:
            with Image.open(path) as image:
                if image.size!=expected[name]: return False
                image.verify()
        except Exception: return False
    return True


def output_metadata(paths):
    return {name:{"size":path.stat().st_size,"sha256":file_hash(path)} for name,path in paths.items()}


def save_derivative(master,destination,maximum,quality):
    destination.parent.mkdir(parents=True,exist_ok=True)
    size=scaled_size(master.size,maximum)
    image=master if size==master.size else master.resize(size,Image.Resampling.LANCZOS)
    suffix=destination.suffix.lower()
    temp=destination.with_name(destination.stem+".candidate-"+uuid.uuid4().hex+destination.suffix)
    try:
        if suffix in {".jpg",".jpeg"}:
            output=image if image.mode in {"RGB","L"} else image.convert("RGB")
            output.save(temp,format="JPEG",quality=quality)
            if output is not image: output.close()
        elif suffix==".png": image.save(temp,format="PNG",compress_level=6)
        elif suffix in {".tif",".tiff"}: image.save(temp,format="TIFF",compression="tiff_deflate")
        else: image.convert("RGB").save(temp,format="JPEG",quality=quality)
        os.replace(temp,destination)
    finally:
        temp.unlink(missing_ok=True)
        if image is not master: image.close()


def process_one(item,args,old):
    source=item["source"]; relative=item["relative"]; paths=output_paths(args.output_root,relative)
    stat=source.stat(); state={"size":stat.st_size,"mtime_ns":stat.st_mtime_ns}
    signature=config_signature(item["document"])
    current=(old and old.get("source")==state and old.get("config")==signature
             and outputs_match_record(paths,old))
    if current and not args.full_audit and not args.force_rebuild:
        return item["key"],"cached",old

    master=open_oriented(source)
    try:
        visual=pixel_hash(master)
        view_max=SETTINGS["document_view_max"] if item["document"] else SETTINGS["photo_view_max"]
        expected={"images":scaled_size(master.size,view_max),
                  "thumbs":scaled_size(master.size,SETTINGS["thumb_max"]),
                  "highres":scaled_size(master.size,highres_max(master.size))}
        valid=outputs_match_record(paths,old)
        if args.full_audit and valid:
            valid=outputs_have_dimensions(paths,expected)
            if valid:
                for name,path in paths.items():
                    if file_hash(path)!=old.get("outputs",{}).get(name,{}).get("sha256"):
                        valid=False; break
        if (not args.force_rebuild and old and old.get("pixel_sha256")==visual
                and old.get("config")==signature and valid):
            updated=dict(old); updated["source"]=state
            return item["key"],("audited" if args.full_audit else "metadata-only"),updated

        if not args.force_rebuild and not old and outputs_have_dimensions(paths,expected):
            return item["key"],"adopted",{"source":state,"config":signature,
                "pixel_sha256":visual,"outputs":output_metadata(paths)}

        if args.dry_run: return item["key"],"would-generate",old
        save_derivative(master,paths["images"],view_max,
                        SETTINGS["document_quality"] if item["document"] else SETTINGS["photo_quality"])
        save_derivative(master,paths["thumbs"],SETTINGS["thumb_max"],SETTINGS["photo_quality"])
        save_derivative(master,paths["highres"],highres_max(master.size),SETTINGS["highres_quality"])
        for path in paths.values(): os.utime(path,ns=(stat.st_atime_ns,stat.st_mtime_ns))
        return item["key"],"generated",{"source":state,"config":signature,
            "pixel_sha256":visual,"outputs":output_metadata(paths)}
    finally: master.close()


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--manifest",required=True,type=pathlib.Path)
    parser.add_argument("--output-root",required=True,type=pathlib.Path)
    parser.add_argument("--cache",required=True,type=pathlib.Path)
    parser.add_argument("--from-year",type=int,default=0); parser.add_argument("--to-year",type=int,default=9999)
    parser.add_argument("--workers",type=int,default=4)
    parser.add_argument("--dry-run",action="store_true"); parser.add_argument("--full-audit",action="store_true")
    parser.add_argument("--force-rebuild",action="store_true")
    args=parser.parse_args()
    if not 1<=args.workers<=16: parser.error("--workers must be between 1 and 16")

    cache=load_cache(args.cache); records=cache["records"]; selected=[]; seen=set()
    with args.manifest.open("r",encoding="utf-8-sig",newline="") as stream:
        for row in csv.DictReader(stream):
            relative=pathlib.PurePath(str(row.get("RelativePath","")).replace("\\","/"))
            year=path_year(relative)
            if is_placeholder(relative) or year is None or not args.from_year<=year<=args.to_year: continue
            source=pathlib.Path(row.get("SourcePath",""))
            if not source.is_file():
                print(f"WARNING: source missing; preserving derivatives: {source}"); continue
            key=str(source.resolve()).casefold()
            if key in seen: raise SystemExit(f"Duplicate source in photo manifest: {source}")
            seen.add(key); selected.append({"key":key,"source":source,"relative":relative,
                                            "document":is_document(row.get("Tags",""))})

    print("Bell Family Archive fast photo exporter")
    print(f"Selected photos: {len(selected)}"); print(f"Workers: {args.workers}")
    print(f"Mode: {'FULL AUDIT' if args.full_audit else 'INCREMENTAL'}{' / DRY RUN' if args.dry_run else ''}")
    counts={}; updated=dict(records); errors=[]
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures={pool.submit(process_one,item,args,records.get(item["key"])):item for item in selected}
        for done,future in enumerate(as_completed(futures),1):
            item=futures[future]
            try:
                key,action,record=future.result(); counts[action]=counts.get(action,0)+1
                if record is not None: updated[key]=record
                if action in {"generated","would-generate","metadata-only"}: print(f"{action.upper():14} {item['relative'].as_posix()}")
            except Exception as exc:
                errors.append((item["source"],exc)); print(f"ERROR {item['source']}: {exc}",file=sys.stderr)
            if done%100==0: print(f"Processed {done}/{len(selected)}")
    if errors:
        print(f"Photo export failed for {len(errors)} files; cache unchanged.",file=sys.stderr); return 1
    if not args.dry_run:
        active={item["key"] for item in selected}; updated={k:v for k,v in updated.items() if k in active}
        write_json_atomic(args.cache,{"version":CACHE_VERSION,"records":updated})
    print("Results:")
    for name in ("cached","adopted","metadata-only","audited","generated","would-generate"):
        if counts.get(name): print(f"  {name}: {counts[name]}")
    print(f"  errors: {len(errors)}")
    if not args.dry_run: print(f"Derivative cache: {args.cache}")
    return 0


if __name__=="__main__": raise SystemExit(main())

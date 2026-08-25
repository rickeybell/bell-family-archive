#!/usr/bin/env python3
"""Synchronize GPS/tag metadata for a scoped list of media into digiKam SQLite."""

import argparse
import csv
import datetime as dt
import json
import math
import os
import pathlib
import sqlite3
import subprocess
import sys


def stop_if_digikam_running():
    if os.name != "nt":
        return
    result = subprocess.run(
        ["tasklist", "/FI", "IMAGENAME eq digikam.exe", "/NH"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        encoding="utf-8",
        errors="replace",
    )
    if "digikam.exe" in result.stdout.lower():
        raise SystemExit("Safety stop: close digiKam before synchronizing its database")


def norm(path):
    return os.path.normcase(os.path.abspath(os.fspath(path)))


def values(record, key):
    value = record.get(key)
    if value in (None, ""):
        return []
    return value if isinstance(value, list) else [value]


def normalize_tag_path(value):
    text = str(value).strip().replace("\\", "/").replace("|", "/")
    return "/".join(part.strip() for part in text.split("/") if part.strip())


def run_exiftool(exiftool, paths):
    records = []
    env = os.environ.copy()
    env.update({"LC_ALL": "C", "LC_CTYPE": "C", "LANG": "C"})
    for start in range(0, len(paths), 75):
        batch = paths[start : start + 75]
        command = [
            str(exiftool), "-json", "-n",
            "-XMP-digiKam:TagsList", "-XMP-lr:HierarchicalSubject", "-XMP-dc:Subject",
            "-GPSLatitude", "-GPSLongitude", *map(str, batch),
        ]
        result = subprocess.run(
            command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            encoding="utf-8", errors="replace", env=env,
        )
        if result.returncode:
            raise RuntimeError(
                f"ExifTool metadata read failed ({result.returncode}): {result.stderr.strip()}"
            )
        records.extend(json.loads(result.stdout or "[]"))
    return records


def read_metadata(exiftool, media_paths):
    targets = []
    for media in media_paths:
        targets.append(media)
        sidecar = pathlib.Path(str(media) + ".xmp")
        if sidecar.exists():
            targets.append(sidecar)

    merged = {
        norm(media): {"path": media, "tags": set(), "latitude": None, "longitude": None}
        for media in media_paths
    }
    for record in run_exiftool(exiftool, targets):
        source = pathlib.Path(record["SourceFile"])
        media = pathlib.Path(str(source)[:-4]) if str(source).lower().endswith(".xmp") else source
        entry = merged.get(norm(media))
        if entry is None:
            continue
        tag_values = values(record, "TagsList") or values(record, "HierarchicalSubject")
        for raw in tag_values:
            tag = normalize_tag_path(raw)
            if tag:
                entry["tags"].add(tag)
        try:
            lat = float(record["GPSLatitude"])
            lon = float(record["GPSLongitude"])
            if math.isfinite(lat) and math.isfinite(lon):
                # Sidecars are processed after media and therefore take precedence.
                entry["latitude"] = lat
                entry["longitude"] = lon
        except (KeyError, TypeError, ValueError):
            pass
    return merged


def build_catalog_path_map(db, collection_root):
    result = {}
    for image_id, relative, name in db.execute(
        """SELECT i.id,a.relativePath,i.name
           FROM Images i JOIN Albums a ON a.id=i.album WHERE i.status=1"""
    ):
        path = collection_root / str(relative).strip("/\\") / name
        result[norm(path)] = image_id
    return result


def ensure_tag_path(db, path, cache):
    parent = 0
    for part in (piece for piece in path.split("/") if piece):
        cache_key = (parent, part.casefold())
        if cache_key in cache:
            parent = cache[cache_key]
            continue
        row = db.execute(
            "SELECT id FROM Tags WHERE pid=? AND name=? COLLATE NOCASE ORDER BY id LIMIT 1",
            (parent, part),
        ).fetchone()
        if row:
            tag_id = row[0]
        else:
            tag_id = db.execute(
                "INSERT INTO Tags(pid,name) VALUES(?,?)", (parent, part)
            ).lastrowid
            if parent == 0:
                db.execute("INSERT OR IGNORE INTO TagsTree(id,pid) VALUES(?,0)", (tag_id,))
            else:
                db.execute(
                    "INSERT OR IGNORE INTO TagsTree(id,pid) SELECT ?,pid FROM TagsTree WHERE id=?",
                    (tag_id, parent),
                )
                db.execute("INSERT OR IGNORE INTO TagsTree(id,pid) VALUES(?,?)", (tag_id, parent))
        cache[cache_key] = tag_id
        parent = tag_id
    return parent


def coordinate_text(number, positive, negative):
    absolute = abs(number)
    degrees = int(absolute)
    minutes = (absolute - degrees) * 60.0
    return f"{degrees},{minutes:.8f}{positive if number >= 0 else negative}"


def update_position(db, image_id, latitude, longitude):
    db.execute("INSERT OR IGNORE INTO ImagePositions(imageid) VALUES(?)", (image_id,))
    db.execute(
        """UPDATE ImagePositions
           SET latitude=?,latitudeNumber=?,longitude=?,longitudeNumber=? WHERE imageid=?""",
        (
            coordinate_text(latitude, "N", "S"), latitude,
            coordinate_text(longitude, "E", "W"), longitude, image_id,
        ),
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", required=True, type=pathlib.Path)
    parser.add_argument("--collection-root", required=True, type=pathlib.Path)
    parser.add_argument("--paths-file", required=True, type=pathlib.Path)
    parser.add_argument("--backup-dir", required=True, type=pathlib.Path)
    parser.add_argument("--exiftool", required=True, type=pathlib.Path)
    args = parser.parse_args()

    stop_if_digikam_running()
    for required in (args.database, args.collection_root, args.paths_file, args.exiftool):
        if not required.exists():
            raise SystemExit(f"Safety stop: required path is missing: {required}")

    with args.paths_file.open("r", encoding="utf-8-sig") as handle:
        supplied = [pathlib.Path(line.strip()) for line in handle if line.strip()]
    media_paths = []
    seen = set()
    for path in supplied:
        key = norm(path)
        if path.exists() and key not in seen:
            media_paths.append(pathlib.Path(os.path.abspath(path)))
            seen.add(key)
    if not media_paths:
        raise SystemExit("Safety stop: no existing affected media paths were supplied")

    print(f"Reading metadata for {len(media_paths)} affected items", flush=True)
    metadata = read_metadata(args.exiftool, media_paths)
    db = sqlite3.connect(args.database, timeout=60)
    db.execute("PRAGMA busy_timeout=60000")
    catalog_paths = build_catalog_path_map(db, args.collection_root)

    args.backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = args.backup_dir / f"digikam4-before-gps-sync-{stamp}.db"
    missing_path = args.backup_dir / f"digikam-gps-sync-missing-{stamp}.csv"
    backup = sqlite3.connect(backup_path)
    try:
        db.backup(backup)
    finally:
        backup.close()

    matched, missing = [], []
    for key, entry in metadata.items():
        image_id = catalog_paths.get(key)
        if image_id is None:
            missing.append((str(entry["path"]), "No active digiKam catalog record"))
        else:
            matched.append((image_id, entry))

    tag_cache, expected_pairs, gps_expected = {}, set(), {}
    created_tags_before = db.execute("SELECT COUNT(*) FROM Tags").fetchone()[0]
    try:
        db.execute("BEGIN IMMEDIATE")
        for image_id, entry in matched:
            for tag_path in sorted(entry["tags"]):
                tag_id = ensure_tag_path(db, tag_path, tag_cache)
                db.execute(
                    "INSERT OR IGNORE INTO ImageTags(imageid,tagid) VALUES(?,?)",
                    (image_id, tag_id),
                )
                expected_pairs.add((image_id, tag_id))
            if entry["latitude"] is not None and entry["longitude"] is not None:
                update_position(db, image_id, entry["latitude"], entry["longitude"])
                gps_expected[image_id] = (entry["latitude"], entry["longitude"])

        missing_pairs = [
            pair for pair in expected_pairs
            if db.execute("SELECT 1 FROM ImageTags WHERE imageid=? AND tagid=?", pair).fetchone() is None
        ]
        bad_gps = []
        for image_id, expected in gps_expected.items():
            row = db.execute(
                "SELECT latitudeNumber,longitudeNumber FROM ImagePositions WHERE imageid=?",
                (image_id,),
            ).fetchone()
            if (row is None or row[0] is None or row[1] is None
                    or abs(row[0] - expected[0]) > 1e-8
                    or abs(row[1] - expected[1]) > 1e-8):
                bad_gps.append(image_id)
        if missing_pairs or bad_gps:
            raise RuntimeError(
                f"Catalog verification failed: missing tags={len(missing_pairs)}, bad GPS={len(bad_gps)}"
            )
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        created_tags_after = db.execute("SELECT COUNT(*) FROM Tags").fetchone()[0]
        db.close()

    with missing_path.open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle)
        writer.writerow(["Path", "Reason"])
        writer.writerows(missing)

    print(f"Catalog items matched: {len(matched)}")
    print(f"Tag assignments verified: {len(expected_pairs)}")
    print(f"GPS positions verified: {len(gps_expected)}")
    print(f"New hierarchy tags created: {created_tags_after - created_tags_before}")
    print(f"Items not yet in catalog: {len(missing)}")
    print(f"Catalog backup: {backup_path}")
    print(f"Missing-items report: {missing_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)

#!/usr/bin/env python3
"""Map DigiKam Hobbies tags to media already present in the public website."""

import csv
import json
import os
import pathlib
import sqlite3


ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "hobby_tag_membership.json"
HOBBIES = {
    "aviation": "Aviation",
    "avation": "Aviation",  # Existing DigiKam spelling retained as an alias.
    "scuba": "Scuba",
    "shooting": "Shooting",
    "boating": "Boating",
    "off-roading": "Off-Roading",
    "camping": "Camping",
    "military_rescue_police_ems": "Military / Police / Rescue / EMS",
}


def locate_database():
    candidates = [
        pathlib.Path(os.environ.get("DIGIKAM_DB", "")),
        pathlib.Path.home() / "OneDrive" / "Pictures" / "digikam4.db",
        pathlib.Path.home() / "Pictures" / "digikam4.db",
    ]
    for candidate in candidates:
        if str(candidate) and candidate.is_file():
            return candidate
    raise SystemExit("Could not locate DigiKam database. Set DIGIKAM_DB to its full path.")


def public_media():
    by_source = {}
    for filename, prefix in (
        ("website-photo-manifest.csv", "images/"),
        ("website-video-manifest.csv", "videos/"),
        ("website-audio-manifest.csv", "audio/"),
    ):
        manifest = ROOT / filename
        if not manifest.exists():
            continue
        with manifest.open(encoding="utf-8-sig", newline="") as stream:
            for row in csv.DictReader(stream):
                source = pathlib.Path(row.get("SourcePath") or "")
                relative = (row.get("RelativePath") or "").replace("\\", "/").lstrip("/")
                if source and relative:
                    by_source[str(source.resolve()).casefold()] = prefix + relative
    return by_source


def collection_roots():
    roots = {
        "Pictures": pathlib.Path.home() / "OneDrive" / "Pictures",
        "Stephanie": pathlib.Path(os.environ.get("STEPHANIE_PICTURES_ROOT", r"G:\Pictures\Stephanie")),
    }
    return roots


def main():
    db = sqlite3.connect(locate_database())
    public = public_media()
    roots = collection_roots()
    rows = db.execute(
        """
        SELECT i.name, a.relativePath, ar.label, child.name
        FROM Images i
        JOIN Albums a ON a.id = i.album
        JOIN AlbumRoots ar ON ar.id = a.albumRoot
        JOIN ImageTags it ON it.imageid = i.id
        JOIN Tags child ON child.id = it.tagid
        JOIN Tags parent ON parent.id = child.pid
        WHERE lower(parent.name) = 'hobbies'
        ORDER BY child.name, a.relativePath, i.name
        """
    ).fetchall()

    all_counts = {name: 0 for name in HOBBIES.values()}
    memberships = {}
    for filename, relative, root_label, raw_tag in rows:
        hobby = HOBBIES.get(str(raw_tag).casefold())
        root = roots.get(root_label)
        if not hobby or not root:
            continue
        all_counts[hobby] += 1
        source = root / str(relative).lstrip("/").replace("/", os.sep) / filename
        public_path = public.get(str(source.resolve()).casefold())
        if public_path:
            memberships.setdefault(public_path, []).append(hobby)

    memberships = {path: sorted(set(values)) for path, values in sorted(memberships.items())}
    public_counts = {
        hobby: sum(hobby in values for values in memberships.values())
        for hobby in HOBBIES.values()
    }
    payload = {
        "tagRoot": "Hobbies",
        "memberships": memberships,
        "taggedCounts": all_counts,
        "publicCounts": public_counts,
    }
    OUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.name}: {len(memberships)} public media items mapped from DigiKam Hobbies tags")
    for hobby in dict.fromkeys(HOBBIES.values()):
        print(f"  {hobby}: {public_counts[hobby]} public / {all_counts[hobby]} tagged")


if __name__ == "__main__":
    main()

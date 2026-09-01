#!/usr/bin/env python3
"""Assign digiKam's green color label to every Website-tagged item."""

import argparse
import datetime as dt
import os
import pathlib
import sqlite3


def find_database() -> pathlib.Path:
    configured = os.environ.get("DIGIKAM_DB")
    home = pathlib.Path.home()
    candidates = [
        pathlib.Path(configured) if configured else None,
        home / "OneDrive" / "Pictures" / "digikam4.db",
        home / "Pictures" / "digikam4.db",
        home / "digikam4.db",
    ]
    for candidate in candidates:
        if candidate and candidate.is_file():
            return candidate.resolve()
    raise SystemExit(
        "Could not locate digikam4.db. Set DIGIKAM_DB to its full path."
    )


def tag_id(db: sqlite3.Connection, name: str) -> int:
    rows = db.execute(
        "SELECT id FROM Tags WHERE lower(name)=lower(?) ORDER BY id", (name,)
    ).fetchall()
    if len(rows) != 1:
        raise RuntimeError(
            f"Expected exactly one digiKam tag named {name!r}; found {len(rows)}."
        )
    return int(rows[0][0])


def missing_image_ids(
    db: sqlite3.Connection, website_tag_id: int, green_tag_id: int
) -> list[int]:
    return [
        int(row[0])
        for row in db.execute(
            """
            SELECT DISTINCT website.imageid
            FROM ImageTags AS website
            WHERE website.tagid=?
              AND NOT EXISTS (
                  SELECT 1 FROM ImageTags AS green
                  WHERE green.imageid=website.imageid AND green.tagid=?
              )
            ORDER BY website.imageid
            """,
            (website_tag_id, green_tag_id),
        )
    ]


def competing_color_label_pairs(
    db: sqlite3.Connection, website_tag_id: int, green_tag_id: int
) -> list[tuple[int, int]]:
    """Return Website-tagged items carrying a non-green color label."""
    return [
        (int(row[0]), int(row[1]))
        for row in db.execute(
            """
            SELECT DISTINCT website.imageid, color.tagid
            FROM ImageTags AS website
            JOIN ImageTags AS color ON color.imageid=website.imageid
            JOIN Tags AS color_tag ON color_tag.id=color.tagid
            WHERE website.tagid=?
              AND color.tagid<>?
              AND lower(color_tag.name) LIKE 'color label %'
            ORDER BY website.imageid, color.tagid
            """,
            (website_tag_id, green_tag_id),
        )
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=pathlib.Path)
    parser.add_argument("--backup-dir", type=pathlib.Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    database = (args.database or find_database()).resolve()
    backup_dir = (
        args.backup_dir
        or pathlib.Path(r"G:\BellWebsite-DigiKamBackups")
    ).resolve()

    db = sqlite3.connect(database, timeout=60)
    db.execute("PRAGMA busy_timeout=60000")
    try:
        website_tag_id = tag_id(db, "Website")
        green_tag_id = tag_id(db, "Color Label Green")
        missing = missing_image_ids(db, website_tag_id, green_tag_id)
        competing = competing_color_label_pairs(db, website_tag_id, green_tag_id)
        affected = sorted(set(missing) | {image_id for image_id, _ in competing})

        print(f"digiKam Website-tagged items missing green: {len(missing)}")
        print(
            "digiKam Website-tagged items with another color label: "
            f"{len({image_id for image_id, _ in competing})}"
        )
        if not affected:
            return
        if args.dry_run:
            print("Dry run: color labels were not changed.")
            return

        backup_dir.mkdir(parents=True, exist_ok=True)
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_path = backup_dir / f"digikam4-before-website-green-{stamp}.db"
        backup = sqlite3.connect(backup_path)
        try:
            db.backup(backup)
        finally:
            backup.close()

        db.execute("BEGIN IMMEDIATE")
        try:
            # Recheck under the write lock in case digiKam changed a label.
            # Locked is deliberately ignored: it protects place/GPS automation,
            # not the independent Website publishing color label.
            missing = missing_image_ids(db, website_tag_id, green_tag_id)
            competing = competing_color_label_pairs(
                db, website_tag_id, green_tag_id
            )
            db.executemany(
                "DELETE FROM ImageTags WHERE imageid=? AND tagid=?",
                competing,
            )
            db.executemany(
                "INSERT OR IGNORE INTO ImageTags(imageid,tagid) VALUES(?,?)",
                ((image_id, green_tag_id) for image_id in missing),
            )
            remaining_missing = missing_image_ids(
                db, website_tag_id, green_tag_id
            )
            remaining_competing = competing_color_label_pairs(
                db, website_tag_id, green_tag_id
            )
            if remaining_missing or remaining_competing:
                raise RuntimeError(
                    "Green-label verification failed: "
                    f"{len(remaining_missing)} missing green; "
                    f"{len(remaining_competing)} competing color labels remain."
                )
            db.commit()
        except Exception:
            db.rollback()
            raise

        print(f"digiKam green labels assigned: {len(missing)}")
        print(f"digiKam competing color labels removed: {len(competing)}")
        print(f"digiKam backup: {backup_path}")
    finally:
        db.close()


if __name__ == "__main__":
    main()

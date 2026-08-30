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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=pathlib.Path)
    parser.add_argument("--backup-dir", type=pathlib.Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    database = (args.database or find_database()).resolve()
    backup_dir = (
        args.backup_dir
        or pathlib.Path.home() / "Documents" / "BellWebsite-DigiKamBackups"
    ).resolve()

    db = sqlite3.connect(database, timeout=60)
    db.execute("PRAGMA busy_timeout=60000")
    try:
        website_tag_id = tag_id(db, "Website")
        green_tag_id = tag_id(db, "Color Label Green")
        missing = missing_image_ids(db, website_tag_id, green_tag_id)

        print(f"digiKam Website-tagged items missing green: {len(missing)}")
        if not missing:
            return
        if args.dry_run:
            print("Dry run: green labels were not changed.")
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
            missing = missing_image_ids(db, website_tag_id, green_tag_id)
            db.executemany(
                "INSERT OR IGNORE INTO ImageTags(imageid,tagid) VALUES(?,?)",
                ((image_id, green_tag_id) for image_id in missing),
            )
            remaining = missing_image_ids(db, website_tag_id, green_tag_id)
            if remaining:
                raise RuntimeError(
                    f"Green-label verification failed for {len(remaining)} items."
                )
            db.commit()
        except Exception:
            db.rollback()
            raise

        print(f"digiKam green labels assigned: {len(missing)}")
        print(f"digiKam backup: {backup_path}")
    finally:
        db.close()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Export active digiKam Website-tagged source paths for configured collections."""

import argparse
import datetime as dt
import json
import os
import pathlib
import sqlite3


def dotnet_utc_timestamp(mtime_ns: int) -> str:
    seconds, nanoseconds = divmod(mtime_ns, 1_000_000_000)
    moment = dt.datetime.fromtimestamp(seconds, dt.timezone.utc)
    return moment.strftime("%Y-%m-%dT%H:%M:%S") + f".{nanoseconds // 100:07d}Z"


def find_db(source_roots: list[pathlib.Path]) -> pathlib.Path | None:
    configured = os.environ.get("DIGIKAM_DB")
    candidates = [pathlib.Path(configured)] if configured else []
    home = pathlib.Path.home()
    candidates.extend(
        [
            home / "OneDrive" / "Pictures" / "digikam4.db",
            home / "Pictures" / "digikam4.db",
        ]
    )
    candidates.extend(root / "digikam4.db" for root in source_roots)
    return next((path for path in candidates if path.is_file()), None)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", action="append", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    roots = [pathlib.Path(value).resolve() for value in args.source_root]
    database = find_db(roots)
    if database is None:
        raise SystemExit("Could not locate the digiKam database")

    connection = sqlite3.connect(f"file:{database.as_posix()}?mode=ro", uri=True)
    root_rows = connection.execute("SELECT id,label FROM AlbumRoots").fetchall()
    root_by_label = {str(label).strip().casefold(): int(root_id) for root_id, label in root_rows}
    configured = {}
    for root in roots:
        root_id = root_by_label.get(root.name.casefold())
        if root_id is None:
            raise SystemExit(f"No digiKam album root label matches collection folder {root.name!r}")
        configured[root_id] = root

    website_rows = connection.execute(
        """
        SELECT DISTINCT a.albumRoot,a.relativePath,i.name
        FROM Images i
        JOIN Albums a ON a.id=i.album
        WHERE i.status=1
          AND a.albumRoot IN ({})
          AND EXISTS (
              SELECT 1 FROM ImageTags it JOIN Tags t ON t.id=it.tagid
              WHERE it.imageid=i.id AND lower(t.name)='website'
          )
        ORDER BY a.albumRoot,a.relativePath,i.name
        """.format(",".join("?" for _ in configured)),
        tuple(configured),
    ).fetchall()
    connection.close()

    paths = []
    items = []
    missing = []
    by_collection = {}
    for root_id, relative, name in website_rows:
        root = configured[int(root_id)]
        source = root / str(relative or "").strip("/\\") / str(name)
        normalized = str(source.resolve())
        if source.is_file():
            stat = source.stat()
            paths.append(normalized)
            items.append({"path": normalized, "length": stat.st_size,
                          "last_write_utc": dotnet_utc_timestamp(stat.st_mtime_ns)})
            by_collection[root.name] = by_collection.get(root.name, 0) + 1
        else:
            missing.append(normalized)

    if missing:
        sample = "\n  ".join(missing[:20])
        raise SystemExit(f"Active Website-tagged digiKam items are missing from disk:\n  {sample}")

    output = pathlib.Path(args.output)
    output.write_text(
        json.dumps(
            {
                "database": str(database),
                "source_roots": [str(root) for root in roots],
                "website_sources": paths,
                "website_items": items,
                "by_collection": by_collection,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"digiKam Website-tagged sources: {len(paths)}")
    for label, count in sorted(by_collection.items()):
        print(f"  {label}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

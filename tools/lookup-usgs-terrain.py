#!/usr/bin/env python3
"""Look up local USGS 3DEP GeoTIFF terrain elevations for a CSV of photos."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

from PIL import Image


def tile_name(latitude: float, longitude: float) -> str:
    north = math.ceil(latitude)
    west = math.floor(longitude)
    ns = "n" if north >= 0 else "s"
    ew = "e" if west >= 0 else "w"
    return f"{ns}{abs(north):02d}{ew}{abs(west):03d}"


def tag_values(image: Image.Image, tag_id: int):
    value = image.tag_v2.get(tag_id)
    if value is None:
        raise ValueError(f"GeoTIFF tag {tag_id} is missing")
    return tuple(float(item) for item in value)


def read_elevation(image: Image.Image, latitude: float, longitude: float) -> float:
    pixel_scale = tag_values(image, 33550)  # ModelPixelScaleTag
    tiepoint = tag_values(image, 33922)  # ModelTiepointTag
    origin_x = tiepoint[3] - tiepoint[0] * pixel_scale[0]
    origin_y = tiepoint[4] + tiepoint[1] * pixel_scale[1]
    column = int(round((longitude - origin_x) / pixel_scale[0]))
    row = int(round((origin_y - latitude) / pixel_scale[1]))
    if column < 0 or row < 0 or column >= image.width or row >= image.height:
        raise ValueError("coordinate is outside the tile raster")
    value = float(image.getpixel((column, row)))
    nodata_raw = image.tag_v2.get(42113)
    if nodata_raw is not None:
        try:
            nodata = float(str(nodata_raw).strip("\x00"))
            if math.isclose(value, nodata, rel_tol=0.0, abs_tol=0.001):
                raise ValueError("terrain pixel is NoData")
        except (TypeError, ValueError):
            if "NoData" in str(nodata_raw):
                raise
    if not math.isfinite(value) or value < -500.0 or value > 10000.0:
        raise ValueError("terrain elevation is invalid")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terrain-dir", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    terrain_dir = Path(args.terrain_dir)
    open_tiles: dict[str, Image.Image] = {}
    rows_out: list[dict[str, str]] = []

    try:
        with open(args.input, "r", encoding="utf-8-sig", newline="") as source:
            for row in csv.DictReader(source):
                name = tile_name(float(row["Latitude"]), float(row["Longitude"]))
                path = terrain_dir / f"USGS_1_{name}.tif"
                result = {
                    "FullPath": row["FullPath"],
                    "Tile": name,
                    "Status": "",
                    "GroundElevationMeters": "",
                    "Detail": "",
                }
                if not path.is_file() or path.stat().st_size == 0:
                    result["Status"] = "MISSING_TILE"
                    result["Detail"] = str(path)
                    rows_out.append(result)
                    continue
                try:
                    image = open_tiles.get(name)
                    if image is None:
                        image = Image.open(path)
                        open_tiles[name] = image
                    elevation = read_elevation(
                        image, float(row["Latitude"]), float(row["Longitude"])
                    )
                    result["Status"] = "OK"
                    result["GroundElevationMeters"] = f"{elevation:.3f}"
                except Exception as exc:  # Per-photo fallback is intentional.
                    result["Status"] = "ERROR"
                    result["Detail"] = str(exc)
                rows_out.append(result)
    finally:
        for image in open_tiles.values():
            image.close()

    with open(args.output, "w", encoding="utf-8-sig", newline="") as destination:
        writer = csv.DictWriter(
            destination,
            fieldnames=[
                "FullPath",
                "Tile",
                "Status",
                "GroundElevationMeters",
                "Detail",
            ],
        )
        writer.writeheader()
        writer.writerows(rows_out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

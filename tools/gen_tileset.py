#!/usr/bin/env python3
"""Generate the original Megacorp placeholder isometric tileset.

The output is deterministic: the same script writes the same PNG and
JSON. The pictures are flat-shaded diamonds and blocks. They are not
copied from Syndicate or any other game.

Writes web/assets/atlas.png, web/assets/tiles.json, and
web/assets/LICENCE.txt.
"""

import json
import struct
import zlib
from pathlib import Path

TILE_WIDTH = 32
DIAMOND_HEIGHT = 16
LEVEL_PX = 4
MAX_LEVEL = 15
CELL_HEIGHT = DIAMOND_HEIGHT + MAX_LEVEL * LEVEL_PX
COLUMNS = 16

TERRAINS = ("open", "road", "pavement", "building", "water")

BASE = {
    "open": (98, 142, 90),
    "road": (68, 68, 74),
    "pavement": (176, 168, 152),
    "building": (156, 84, 60),
    "water": (46, 118, 168),
}


def shade(rgb, factor):
    return tuple(max(0, min(255, int(channel * factor))) for channel in rgb)


def write_png(path, width, height, pixels):
    """RGBA8 PNG. zlib.compress has no timestamp, so the bytes are stable."""

    def chunk(tag, data):
        head = tag + data
        return (
            struct.pack(">I", len(data))
            + head
            + struct.pack(">I", zlib.crc32(head) & 0xFFFFFFFF)
        )

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        start = y * stride
        raw.extend(pixels[start : start + stride])
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(
        b"IHDR",
        struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0),
    )
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def fill_polygon(pixels, width, height, points, rgba):
    if len(points) < 3:
        return
    y_min = max(0, int(min(point[1] for point in points)))
    y_max = min(height - 1, int(max(point[1] for point in points)))
    count = len(points)
    for y in range(y_min, y_max + 1):
        crossings = []
        for index in range(count):
            x1, y1 = points[index]
            x2, y2 = points[(index + 1) % count]
            if y1 == y2:
                continue
            low = y1 if y1 < y2 else y2
            high = y2 if y1 < y2 else y1
            if y < low or y >= high:
                continue
            crossings.append(x1 + (y - y1) * (x2 - x1) / (y2 - y1))
        crossings.sort()
        pair = 0
        while pair + 1 < len(crossings):
            left = int(round(crossings[pair]))
            right = int(round(crossings[pair + 1]))
            if left > right:
                left, right = right, left
            if left < 0:
                left = 0
            if right >= width:
                right = width - 1
            row = y * width * 4
            for x in range(left, right + 1):
                at = row + x * 4
                pixels[at : at + 4] = rgba
            pair += 2


def diamond(center_x, south_y):
    half_w = TILE_WIDTH // 2
    half_h = DIAMOND_HEIGHT // 2
    return [
        (center_x, south_y),
        (center_x + half_w, south_y - half_h),
        (center_x, south_y - DIAMOND_HEIGHT),
        (center_x - half_w, south_y - half_h),
    ]


def paint_tile(pixels, atlas_width, atlas_height, column, row, terrain, level):
    origin_x = column * TILE_WIDTH
    origin_y = row * CELL_HEIGHT
    cell = bytearray(TILE_WIDTH * CELL_HEIGHT * 4)
    center_x = TILE_WIDTH // 2
    bottom = CELL_HEIGHT - 1
    elev = level * LEVEL_PX
    south = bottom - elev
    color = BASE[terrain]
    top = shade(color, 1.18) + (255,)
    left = shade(color, 0.62) + (255,)
    right = shade(color, 0.84) + (255,)
    top_pts = diamond(center_x, south)
    if terrain == "building" and level > 0:
        west = top_pts[3]
        east = top_pts[1]
        south_pt = top_pts[0]
        base_south = (south_pt[0], south_pt[1] + elev)
        base_west = (west[0], west[1] + elev)
        base_east = (east[0], east[1] + elev)
        fill_polygon(
            cell, TILE_WIDTH, CELL_HEIGHT,
            [west, south_pt, base_south, base_west], left,
        )
        fill_polygon(
            cell, TILE_WIDTH, CELL_HEIGHT,
            [south_pt, east, base_east, base_south], right,
        )
    elif terrain != "water" and terrain != "building":
        lip = LEVEL_PX
        west = top_pts[3]
        east = top_pts[1]
        south_pt = top_pts[0]
        fill_polygon(
            cell, TILE_WIDTH, CELL_HEIGHT,
            [west, south_pt,
             (south_pt[0], south_pt[1] + lip),
             (west[0], west[1] + lip)],
            left,
        )
        fill_polygon(
            cell, TILE_WIDTH, CELL_HEIGHT,
            [south_pt, east,
             (east[0], east[1] + lip),
             (south_pt[0], south_pt[1] + lip)],
            right,
        )
    fill_polygon(cell, TILE_WIDTH, CELL_HEIGHT, top_pts, top)
    for y in range(CELL_HEIGHT):
        src = y * TILE_WIDTH * 4
        dst = ((origin_y + y) * atlas_width + origin_x) * 4
        pixels[dst : dst + TILE_WIDTH * 4] = cell[src : src + TILE_WIDTH * 4]


def main():
    root = Path(__file__).resolve().parents[1] / "web" / "assets"
    root.mkdir(parents=True, exist_ok=True)
    atlas_w = COLUMNS * TILE_WIDTH
    atlas_h = len(TERRAINS) * CELL_HEIGHT
    pixels = bytearray(atlas_w * atlas_h * 4)
    tiles = []
    for row, terrain in enumerate(TERRAINS):
        for level in range(MAX_LEVEL + 1):
            tile_id = row * COLUMNS + level
            paint_tile(pixels, atlas_w, atlas_h, level, row, terrain, level)
            tiles.append({
                "id": tile_id,
                "terrain": terrain,
                "height": level,
                "column": level,
                "row": row,
            })
    lines = [
        "{",
        '  "format": 1,',
        f'  "tile_width": {TILE_WIDTH},',
        f'  "diamond_height": {DIAMOND_HEIGHT},',
        f'  "level_px": {LEVEL_PX},',
        f'  "cell_height": {CELL_HEIGHT},',
        f'  "columns": {COLUMNS},',
        '  "atlas": "assets/atlas.png",',
        '  "tiles": [',
    ]
    for index, tile in enumerate(tiles):
        comma = "," if index + 1 < len(tiles) else ""
        lines.append(
            '    {"id": %d, "terrain": "%s", "height": %d, '
            '"column": %d, "row": %d}%s'
            % (
                tile["id"],
                tile["terrain"],
                tile["height"],
                tile["column"],
                tile["row"],
                comma,
            )
        )
    lines.append("  ]")
    lines.append("}")
    (root / "tiles.json").write_text("\n".join(lines) + "\n", encoding="utf-8")
    write_png(root / "atlas.png", atlas_w, atlas_h, pixels)
    (root / "LICENCE.txt").write_text(
        "Megacorp Simulator placeholder tileset\n"
        "\n"
        "These pictures are original. They were drawn by\n"
        "tools/gen_tileset.py. They are not from Syndicate, Bullfrog,\n"
        "or Electronic Arts, and they contain no copied game art.\n"
        "\n"
        "They are part of Megacorp Simulator and are covered by the\n"
        "MIT licence. Copyright (c) 2026 Robert Boettcher. See\n"
        "LICENSE at the repository root.\n",
        encoding="utf-8",
    )
    print(f"wrote {root / 'atlas.png'} and {len(tiles)} tiles")


if __name__ == "__main__":
    main()

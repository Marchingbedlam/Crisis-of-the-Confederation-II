#!/usr/bin/env python3
"""
generate_starlight_positions.py - Populate starlight_colour_positions.txt from the star map objects

Derives the RGB -> XYZ pairs that bake_starlight.py consumes, so they no longer have
to be typed by hand. For every star instance in

    ../../live/gfx/map/map_object_data/*_star.txt

it samples the system's colour out of

    ../../live/gfx/map/terrain/cotc_starlight_mask.png

and appends the resulting pair to

    starlight_colour_positions.txt

The mask and the world are both 8192x4096, so one world unit is one pixel:

    col = floor(x)              row = floor(HEIGHT - z)      # the z axis is flipped

Stars sharing a mask colour are one multi-star system; they collapse to a single
entry at the centroid of the group. Colours already present in the file are skipped
and existing lines are never rewritten, so manual edits survive re-runs.

No third-party packages required (the PNG is decoded by hand). Run:

    python generate_starlight_positions.py

Optional flags:
    --colors PATH  --mask PATH  --stars GLOB  --y 5  --max-spread 50
"""

import argparse
import glob
import math
import os
import re
import sys
import zlib

# --- paths relative to this script ------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
LIVE = os.path.normpath(os.path.join(HERE, "..", "..", "live"))
DEF_COLORS = os.path.join(HERE, "starlight_colour_positions.txt")
DEF_MASK = os.path.join(LIVE, "gfx", "map", "terrain", "cotc_starlight_mask.png")
DEF_STARS = os.path.join(LIVE, "gfx", "map", "map_object_data", "*_star.txt")

# The Y component every entry carries; the stars themselves all sit at y = 0.
DEF_Y = 5
# Two stars further apart than this almost certainly are not one system.
DEF_MAX_SPREAD = 50.0

# Kept bit-identical to bake_starlight.py so the two tools can never disagree
# about what counts as an existing entry.
COMMENT = re.compile(r"#.*$")
ENTRY = re.compile(
    r"^\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:->|:|=)\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*$"
)

TRANSFORM = re.compile(r'transform\s*=\s*"([^"]*)"', re.S)
COUNT = re.compile(r"^\s*count\s*=\s*(\d+)\s*$", re.M)

PNG_SIG = b"\x89PNG\r\n\x1a\n"


# --- inputs -----------------------------------------------------------------

def load_existing_keys(path):
    """Return the set of (r,g,b) already in the pairs file. Missing file -> empty."""
    keys = set()
    if not os.path.exists(path):
        return keys
    with open(path, "r", encoding="utf-8") as fh:
        for ln, raw in enumerate(fh, 1):
            line = COMMENT.sub("", raw).strip()
            if not line:
                continue
            m = ENTRY.match(line)
            if not m:
                sys.exit(f"{os.path.basename(path)}:{ln}: cannot parse '{line}' (expected 'R,G,B -> X,Y,Z')")
            keys.add(tuple(int(v) for v in m.groups()[:3]))
    return keys


def load_stars(pattern):
    """Return list of (x, z) for every star instance across the matching files.

    The files use the compact packed-float form: one quoted blob under
    transform=, ten floats per row (posXYZ, quatXYZW, scaleXYZ).
    """
    stars = []
    paths = sorted(glob.glob(pattern))
    if not paths:
        sys.exit(f"no star files matched {pattern}")
    for path in paths:
        name = os.path.basename(path)
        with open(path, "r", encoding="utf-8-sig") as fh:
            text = fh.read()
        declared = [int(m.group(1)) for m in COUNT.finditer(text)]
        blocks = TRANSFORM.findall(text)
        if not blocks:
            sys.exit(f"{name}: no transform=\"...\" block found")
        if len(declared) != len(blocks):
            sys.exit(f"{name}: {len(declared)} count= keys but {len(blocks)} transform blocks")
        for block, count in zip(blocks, declared):
            rows = 0
            for ln, line in enumerate(block.splitlines(), 1):
                parts = line.split()
                if not parts:
                    continue
                if len(parts) < 3:
                    sys.exit(f"{name}: transform row {ln} has {len(parts)} fields, expected 10")
                try:
                    stars.append((float(parts[0]), float(parts[2])))
                except ValueError:
                    sys.exit(f"{name}: transform row {ln} is not numeric: '{line.strip()}'")
                rows += 1
            if rows != count:
                sys.exit(f"{name}: count={count} but found {rows} transform rows")
    if not stars:
        sys.exit(f"no star instances found in {len(paths)} file(s) matching {pattern}")
    return stars


# --- PNG ---------------------------------------------------------------------

def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _unfilter(ftype, cur, prev, bpp):
    """Reconstruct one scanline. `cur` is the filtered row, `prev` the row above."""
    if ftype == 0:
        return bytes(cur)
    if ftype == 2:
        return bytes([(a + b) & 0xFF for a, b in zip(cur, prev)])

    out = bytearray(cur)
    n = len(out)
    if ftype == 1:
        for i in range(bpp, n):
            out[i] = (out[i] + out[i - bpp]) & 0xFF
    elif ftype == 3:
        for i in range(n):
            left = out[i - bpp] if i >= bpp else 0
            out[i] = (out[i] + ((left + prev[i]) >> 1)) & 0xFF
    elif ftype == 4:
        for i in range(n):
            left = out[i - bpp] if i >= bpp else 0
            upleft = prev[i - bpp] if i >= bpp else 0
            out[i] = (out[i] + _paeth(left, prev[i], upleft)) & 0xFF
    else:
        raise ValueError(f"unknown PNG filter type {ftype}")
    return bytes(out)


def _read_png_header_and_idat(path):
    """Return (path, width, height, bpp, compressed_idat). Rejects formats we cannot read."""
    with open(path, "rb") as fh:
        data = fh.read()
    if not data.startswith(PNG_SIG):
        sys.exit(f"{path}: not a PNG")

    width = height = bpp = None
    idat = bytearray()
    pos = len(PNG_SIG)
    while pos + 8 <= len(data):
        length = int.from_bytes(data[pos:pos + 4], "big")
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            width = int.from_bytes(body[0:4], "big")
            height = int.from_bytes(body[4:8], "big")
            depth, colour, _comp, _filt, interlace = body[8], body[9], body[10], body[11], body[12]
            if depth != 8:
                sys.exit(f"{path}: bit depth {depth} unsupported (need 8)")
            if colour not in (2, 6):
                sys.exit(f"{path}: colour type {colour} unsupported (need 2=RGB or 6=RGBA)")
            if interlace != 0:
                sys.exit(f"{path}: interlaced PNGs unsupported; re-save without Adam7")
            bpp = 3 if colour == 2 else 4
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break
        pos += 12 + length

    if width is None:
        sys.exit(f"{path}: no IHDR chunk")
    if not idat:
        sys.exit(f"{path}: no IDAT data")
    return path, width, height, bpp, bytes(idat)


def sample_mask(image, points):
    """Return {(col,row): (r,g,b)} for the requested pixels of a decoded PNG header.

    Only the scanlines a requested pixel actually depends on are reconstructed.
    Filter types 0 and 1 are self-contained; 2, 3 and 4 reference the row above,
    so each wanted row is walked back to its nearest self-contained ancestor and
    only that chain is rebuilt.
    """
    path, width, height, bpp, comp = image
    stride = width * bpp
    rowlen = 1 + stride

    if not points:
        return {}
    for col, row in points:
        if not (0 <= col < width and 0 <= row < height):
            sys.exit(f"pixel ({col},{row}) outside the {width}x{height} mask")
    wanted_rows = sorted({r for _c, r in points})

    # Inflate only as far as the last row anyone needs.
    needed_bytes = (wanted_rows[-1] + 1) * rowlen
    raw = zlib.decompressobj().decompress(comp, needed_bytes)
    if len(raw) < needed_bytes:
        sys.exit(f"{path}: truncated image data ({len(raw)} of {needed_bytes} bytes)")

    # Filter bytes are readable without any reconstruction.
    build = set()
    for row in wanted_rows:
        r = row
        while r > 0 and raw[r * rowlen] in (2, 3, 4):
            build.add(r)
            r -= 1
        build.add(r)

    out = {}
    by_row = {}
    for col, row in points:
        by_row.setdefault(row, []).append(col)

    prev = bytes(stride)
    prev_index = -1
    for row in sorted(build):
        start = row * rowlen
        ftype = raw[start]
        if ftype in (2, 3, 4) and prev_index != row - 1:
            sys.exit(f"{path}: internal error, row {row} needs row {row - 1}")
        recon = _unfilter(ftype, raw[start + 1:start + rowlen], prev, bpp)
        prev, prev_index = recon, row
        for col in by_row.get(row, ()):
            off = col * bpp
            out[(col, row)] = (recon[off], recon[off + 1], recon[off + 2])

    return out


# --- output ------------------------------------------------------------------

def append_entries(path, entries):
    """Append 'R,G,B -> X,Y,Z' lines, matching the alignment of the existing file."""
    if not entries:
        return
    prefix = ""
    if os.path.exists(path) and os.path.getsize(path) > 0:
        with open(path, "rb") as fh:
            fh.seek(-1, os.SEEK_END)
            if fh.read(1) != b"\n":
                prefix = "\n"
    with open(path, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(prefix)
        for (r, g, b), (x, y, z) in entries:
            fh.write(f"{f'{r},{g},{b}':<12} -> {x},{y},{z}\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--colors", default=DEF_COLORS)
    ap.add_argument("--mask", default=DEF_MASK)
    ap.add_argument("--stars", default=DEF_STARS)
    ap.add_argument("--y", type=int, default=DEF_Y, help="Y component written to every entry")
    ap.add_argument("--max-spread", type=float, default=DEF_MAX_SPREAD,
                    help="warn when stars sharing a colour are further apart than this")
    args = ap.parse_args()

    existing = load_existing_keys(args.colors)
    stars = load_stars(args.stars)

    # World units map 1:1 onto mask pixels, with the z axis flipped.
    image = _read_png_header_and_idat(args.mask)
    height = image[2]
    placed = [(x, z, int(math.floor(x)), int(math.floor(height - z))) for x, z in stars]
    pixels = sample_mask(image, {(c, r) for _x, _z, c, r in placed})

    groups = {}
    unmasked = 0
    for x, z, col, row in placed:
        rgb = pixels[(col, row)]
        if rgb == (0, 0, 0):
            unmasked += 1
            continue
        groups.setdefault(rgb, []).append((x, z))

    new = []
    for rgb, members in groups.items():
        if len(members) > 1:
            spread = max(math.dist(a, b) for a in members for b in members)
            if spread > args.max_spread:
                print(f"warning: {len(members)} stars share colour {rgb[0]},{rgb[1]},{rgb[2]} "
                      f"but are up to {spread:.1f} units apart; check they are one system",
                      file=sys.stderr)
        if rgb in existing:
            continue
        # Multi-star systems collapse to the centroid of the group.
        x = sum(m[0] for m in members) / len(members)
        z = sum(m[1] for m in members) / len(members)
        xi, zi = int(math.floor(x)), int(math.floor(z))
        for label, v in (("X", xi), ("Y", args.y), ("Z", zi)):
            if not 0 <= v <= 65535:
                sys.exit(f"colour {rgb}: {label}={v} out of range 0-65535")
        new.append((rgb, (xi, args.y, zi)))

    new.sort(key=lambda e: e[1])
    append_entries(args.colors, new)

    if unmasked:
        print(f"warning: {unmasked} star(s) sit on unpainted mask pixels and were skipped",
              file=sys.stderr)
    print(f"OK: appended {len(new)} colours ({len(groups) - len(new)} already present)")
    print(f"    {len(stars)} stars -> {len(groups)} systems")
    print(f"    wrote {args.colors}")


if __name__ == "__main__":
    main()

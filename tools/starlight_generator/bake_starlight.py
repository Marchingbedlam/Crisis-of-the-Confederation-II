#!/usr/bin/env python3
"""
bake.py - Build the RGB-mask -> XYZ coordinate lookup assets

One RGB color maps to exactly one XYZ coordinate. Reads a single editable file:

    starlight_colour_positions.txt   lines of:  R,G,B -> X,Y,Z
                 R,G,B are 0-255 ; X,Y,Z are integers 0-65535

and writes two assets:

    ../../gfx/FX/generated/cotc_starlight_coord_lut.dds   the baked hash table
    ../../gfx/FX/generated/cotc_starlight_coord.fxh                         table dimensions

The .dds is an open-addressing hash table (linear probing) laid out as three
horizontal bands of ROWS rows each:
    band 0 (key)   rgb = color bytes, a = 255 if the slot is occupied
    band 1 (data0) rg = X (lo,hi), ba = Y (lo,hi)
    band 2 (data1) rg = Z (lo,hi)

No third-party packages required (the .dds is written by hand). Run:

    python bake.py

Optional flags:
    --colors PATH  --dds PATH  --fxh PATH  --load-factor 0.6
"""

import argparse
import os
import re
import struct
import sys

# --- paths relative to this script ------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
DEF_COLORS = os.path.join(HERE, "starlight_colour_positions.txt")
DEF_DDS = os.path.normpath(os.path.join(HERE, "..", "..", "live", "gfx", "FX", "generated", "cotc_starlight_coord_lut.dds"))
DEF_FXH = os.path.normpath(os.path.join(HERE, "..", "..", "live", "gfx", "FX", "generated", "cotc_starlight_coord.fxh"))

MASK32 = 0xFFFFFFFF
BANDS = 3  # key + data0 + data1
COMMENT = re.compile(r"#.*$")


def pack_color_key(r, g, b):
    """Pack an 8-bit RGB triple into a 24-bit key. Must match PackColorKey in the shader."""
    return (r << 16) | (g << 8) | b


def hash_color_key(k):
    """Wang-style finalizer. MUST stay bit-identical to HashColorKey in pdxterrain.shader."""
    k = ((k ^ 61) ^ (k >> 16)) & MASK32
    k = (k * 9) & MASK32
    k = (k ^ (k >> 4)) & MASK32
    k = (k * 0x27D4EB2D) & MASK32
    k = (k ^ (k >> 15)) & MASK32
    return k


def next_pow2(n):
    p = 1
    while p < n:
        p <<= 1
    return p


def load_colors(path):
    """Return list of ((r,g,b), (x,y,z)). Errors on duplicate colors or bad ranges."""
    entries = []
    seen = {}
    with open(path, "r", encoding="utf-8") as fh:
        for ln, raw in enumerate(fh, 1):
            line = COMMENT.sub("", raw).strip()
            if not line:
                continue
            m = re.match(
                r"^\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:->|:|=)\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*$",
                line,
            )
            if not m:
                sys.exit(f"starlight_colour_positions.txt:{ln}: cannot parse '{line}' (expected 'R,G,B -> X,Y,Z')")
            r, g, b, x, y, z = (int(v) for v in m.groups())
            for name, v in (("R", r), ("G", g), ("B", b)):
                if not 0 <= v <= 255:
                    sys.exit(f"starlight_colour_positions.txt:{ln}: {name}={v} out of range 0-255")
            for name, v in (("X", x), ("Y", y), ("Z", z)):
                if not 0 <= v <= 65535:
                    sys.exit(f"starlight_colour_positions.txt:{ln}: {name}={v} out of range 0-65535")
            key = (r, g, b)
            if key in seen:
                sys.exit(f"starlight_colour_positions.txt:{ln}: duplicate color {key} (already on line {seen[key]})")
            seen[key] = ln
            entries.append((key, (x, y, z)))
    return entries


def write_dds(path, width, height, pixels):
    """Write an uncompressed 32-bpp A8R8G8B8 (linear, no sRGB, no mips) DDS.
    `pixels` is a bytearray of width*height*4 in file order [B, G, R, A]."""
    DDSD = 0x1 | 0x2 | 0x4 | 0x8 | 0x1000            # CAPS|HEIGHT|WIDTH|PITCH|PIXELFORMAT
    DDPF = 0x1 | 0x40                                 # ALPHAPIXELS|RGB
    CAPS = 0x1000                                     # TEXTURE
    header = struct.pack(
        "<4sIIIIIII44sIIIIIIIIIIIII",
        b"DDS ", 124, DDSD, height, width, width * 4, 0, 0,
        b"\x00" * 44,                                 # 11 reserved dwords
        32, DDPF, 0, 32,                              # pf size, flags, fourCC, bitcount
        0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000,  # R,G,B,A masks
        CAPS, 0, 0, 0, 0,                             # caps1..4 + reserved2
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(header)
        fh.write(bytes(pixels))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--colors", default=DEF_COLORS)
    ap.add_argument("--dds", default=DEF_DDS)
    ap.add_argument("--fxh", default=DEF_FXH)
    ap.add_argument("--load-factor", type=float, default=0.6)
    args = ap.parse_args()

    colors = load_colors(args.colors)
    n = len(colors)
    if n == 0:
        sys.exit("starlight_colour_positions.txt has no entries")

    # Table sizing: power-of-two, kept under the load factor for short probes.
    table_size = next_pow2(max(4, int(n / args.load_factor) + 1))
    mask = table_size - 1
    # Square-ish 2D layout so we never exceed max texture width.
    w = 1
    while w * w < table_size:
        w <<= 1
    rows = table_size // w
    assert w * rows == table_size

    # Build the open-addressing table (linear probing) exactly like the shader.
    EMPTY = -1
    slots = [EMPTY] * table_size          # holds the index into `colors`
    max_probe = 0
    for ci, (key, _coord) in enumerate(colors):
        h = hash_color_key(pack_color_key(*key)) & mask
        probe = 0
        while slots[h] != EMPTY:
            h = (h + 1) & mask
            probe += 1
            if probe >= table_size:
                sys.exit("hash table full (should never happen)")
        slots[h] = ci
        max_probe = max(max_probe, probe)

    # Paint pixels. Texture is width=w, height=BANDS*rows.
    #   band 0 rows [0, rows)        key   : rgb = color, a = 255 if occupied
    #   band 1 rows [rows, 2*rows)   data0 : R,G = X(lo,hi)  B,A = Y(lo,hi)
    #   band 2 rows [2*rows, 3*rows) data1 : R,G = Z(lo,hi)
    height = BANDS * rows
    pixels = bytearray(w * height * 4)    # file order [B,G,R,A], zero-init = empty

    def put(x, y, b, g, r, a):
        off = (y * w + x) * 4
        pixels[off + 0] = b
        pixels[off + 1] = g
        pixels[off + 2] = r
        pixels[off + 3] = a

    for slot in range(table_size):
        ci = slots[slot]
        if ci == EMPTY:
            continue
        (r, g, b), (x, y, z) = colors[ci]
        px = slot % w
        py = slot // w
        # band 0: key
        put(px, py, b, g, r, 255)
        # band 1: data0  -> shader reads .r,.g,.b,.a = X_lo,X_hi,Y_lo,Y_hi
        put(px, py + rows,
            y & 0xFF,          # B channel = Y low
            x >> 8,            # G channel = X high
            x & 0xFF,          # R channel = X low
            y >> 8)            # A channel = Y high
        # band 2: data1  -> shader reads .r,.g = Z_lo,Z_hi
        put(px, py + 2 * rows,
            0,                 # B unused
            z >> 8,            # G channel = Z high
            z & 0xFF,          # R channel = Z low
            255)

    write_dds(args.dds, w, height, pixels)

    # Emit the generated .fxh (dimensions only; no palette).
    fxh = f"""# ============================================================================
# AUTO-GENERATED
# ============================================================================

PixelShader =
{{
\tCode
\t[[
\t\t// --- Hash table dimensions (must match the baked .dds) --------------
\t\t#define STARLIGHT_LUT_W\t\t\t{w}u\t\t// texels per row
\t\t#define STARLIGHT_LUT_ROWS\t\t{rows}u\t\t// slot rows per band
\t\t#define STARLIGHT_LUT_BANDS\t\t{BANDS}u\t\t// key + data0 + data1 (height = ROWS*BANDS)
\t\t#define STARLIGHT_LUT_TABLE_MASK\t{mask}u\t\t// (W*ROWS - 1), power-of-two table
\t]]
}}
"""
    os.makedirs(os.path.dirname(args.fxh), exist_ok=True)
    with open(args.fxh, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(fxh)

    print(f"OK: {n} colors")
    print(f"    table {w}x{height} ({table_size} slots, load {n/table_size:.2f}, max probe {max_probe})")
    print(f"    wrote {args.dds}")
    print(f"    wrote {args.fxh}")


if __name__ == "__main__":
    main()

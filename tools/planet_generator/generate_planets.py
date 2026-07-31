#!/usr/bin/env python3
"""
generate_planets.py - Place a planet at every province's building position

In this mod a province's "building" is a planet. This reads

    ../../live/common/province_terrain/00_province_terrain.txt   province -> terrain
    ../../live/gfx/map/map_object_data/building_locators.txt     province -> position

and, for each province that does not already have something standing on its building
position, appends a randomly chosen planet of the right terrain family to

    ../../live/gfx/map/map_object_data/cotc_planet_<family>.txt

The candidate entities for a terrain are discovered from the object blocks already in
that family's file, so adding a new variant is just a matter of adding an empty
object={} block with count=0 - no edit to this script required.

Nothing already placed is ever touched. A province is skipped if its building position
is already occupied in ANY object-form file in map_object_data (including files this
script does not own), so hand-placed and custom planets survive re-runs. Locator-form
files are excluded from that check - special_building_locators.txt shares 100% of
building_locators.txt's positions and would otherwise block every province.

No third-party packages required. Run:

    python generate_planets.py --dry-run
    python generate_planets.py

Optional flags:
    --terrain PATH  --locators PATH  --objects DIR  --seed S  --dry-run
"""

import argparse
import os
import random
import re
import sys

# --- paths relative to this script ------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
LIVE = os.path.normpath(os.path.join(HERE, "..", "..", "live"))
DEF_TERRAIN = os.path.join(LIVE, "common", "province_terrain", "00_province_terrain.txt")
DEF_OBJECTS = os.path.join(LIVE, "gfx", "map", "map_object_data")
DEF_LOCATORS = os.path.join(DEF_OBJECTS, "building_locators.txt")
DEF_SEED = "cotc"

# terrain -> the file whose object blocks supply that terrain's planet variants.
# Note the deliberate mismatch: the terrain is "frozen_giant", the art is "ice_giant".
TERRAIN_FILES = {
    "barren": "cotc_planet_barrens.txt",
    "frozen": "cotc_planet_frozens.txt",
    "corrosive": "cotc_planet_corrosives.txt",
    "gas_giant": "cotc_planet_gas_giants.txt",
    "frozen_giant": "cotc_planet_ice_giants.txt",
    "atmospheric": "cotc_planet_atmospherics.txt",
}

# Size weights taken from the 276 hand-placed planets. Giants and atmospherics are
# always 1.0 (size is baked into the mesh); only the rocky families vary. The single
# 1.25 row in cotc_planet_corrosive_02 is a one-off manual tweak and is excluded.
SCALE_WEIGHTS = {
    "barren": ((1.0, 44), (0.75, 25), (0.5, 22)),
    "frozen": ((1.0, 19), (0.75, 26), (0.5, 10)),
    "corrosive": ((1.0, 22), (0.75, 13), (0.5, 4)),
    "gas_giant": ((1.0, 1),),
    "frozen_giant": ((1.0, 1),),
    "atmospheric": ((1.0, 1),),
}

# Terrains that legitimately have no planet family, so their provinces are skipped
# quietly-by-design. Anything outside this set and TERRAIN_FILES is flagged as a typo.
SKIP_TERRAINS = frozenset({"asteroids", "nebula", "open_space", "hypermatter_stream"})

TERRAIN_LINE = re.compile(r"^(\d+)=(.*)$")
LOCATOR = re.compile(r"id=(\d+)\s*position=\{\s*(\S+)\s+(\S+)\s+(\S+)\s*\}")
# One object={...} block: header keys, then the quoted transform blob, then "}
BLOCK = re.compile(r'object=\{(?P<body>.*?)transform="(?P<rows>.*?)"\}', re.S)
ENTITY = re.compile(r'entity="([^"]+)"')
COUNT = re.compile(r"count=(\d+)")


def key(x, z):
    """Position identity. Both sources write 6 decimals, so this compares exactly."""
    return (f"{x:.6f}", f"{z:.6f}")


# --- inputs -----------------------------------------------------------------

def load_terrain(path):
    """Return (province -> terrain, messages, province ids already reported).

    Reported ids are dropped from the mapping so the caller never places a planet on
    data it could not trust, and never reports the same province twice.
    """
    terrain = {}
    seen_line = {}
    messages = []
    rejected = set()
    with open(path, "r", encoding="utf-8-sig") as fh:
        for ln, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("default_"):
                continue
            m = TERRAIN_LINE.match(line)
            if not m:
                messages.append(f"line {ln}: cannot parse '{line}'")
                continue
            pid, value = int(m.group(1)), m.group(2).strip()
            if not value or len(value.split()) > 1:
                rejected.add(pid)
                messages.append(f"line {ln}: province {pid} has malformed terrain '{value}'")
                continue
            if pid in terrain and terrain[pid] != value:
                rejected.add(pid)
                messages.append(f"line {ln}: province {pid} set to '{terrain[pid]}' on "
                                f"line {seen_line[pid]}, then '{value}' - ignoring both")
                continue
            terrain[pid] = value
            seen_line[pid] = ln
    for pid in rejected:
        terrain.pop(pid, None)
    return terrain, messages, rejected


def load_locators(path):
    """Return province -> (x, z) from a game_object_locator file."""
    with open(path, "r", encoding="utf-8-sig") as fh:
        text = fh.read()
    out = {}
    for m in LOCATOR.finditer(text):
        out[int(m.group(1))] = (float(m.group(2)), float(m.group(4)))
    if not out:
        sys.exit(f"{os.path.basename(path)}: no locator instances found")
    return out


def load_occupied(objects_dir, locators_path):
    """Return the set of positions already carrying an object.

    Every object-form file under objects_dir is scanned, including subfolders and
    files this script does not own. Locator-form files are skipped: they describe
    where things may go, not what is there, and they mirror building_locators.txt.
    """
    occupied = set()
    locators_real = os.path.realpath(locators_path)
    for root, _dirs, files in os.walk(objects_dir):
        for fname in sorted(files):
            if not fname.lower().endswith(".txt"):
                continue
            path = os.path.join(root, fname)
            with open(path, "r", encoding="utf-8-sig", errors="replace") as fh:
                text = fh.read()
            if "game_object_locator" in text or os.path.realpath(path) == locators_real:
                continue
            for m in BLOCK.finditer(text):
                for line in m.group("rows").splitlines():
                    parts = line.split()
                    if len(parts) >= 10:
                        occupied.add(key(float(parts[0]), float(parts[2])))
    return occupied


def load_variants(path):
    """Return the entity names of each object block in a planet file, in file order."""
    with open(path, "r", encoding="utf-8-sig") as fh:
        text = fh.read()
    names = []
    for m in BLOCK.finditer(text):
        em = ENTITY.search(m.group("body"))
        if em:
            names.append(em.group(1))
    return names


# --- output ------------------------------------------------------------------

def make_row(x, z, scale):
    """posX posY posZ  quatX quatY quatZ quatW  scaleX scaleY scaleZ"""
    return (f"{x:.6f} 0.000000 {z:.6f} "
            f"0.000000 0.000000 0.000000 1.000000 "
            f"{scale:.6f} {scale:.6f} {scale:.6f}")


def rewrite_file(path, additions):
    """Append rows to the matching object blocks and bump their count=.

    Everything outside the count value and the inserted rows is preserved verbatim,
    including the BOM, CRLF endings, tab indentation and any manual edits.
    """
    with open(path, "r", encoding="utf-8-sig", newline="") as fh:
        text = fh.read()
    added = 0

    def repl(m):
        nonlocal added
        body, rows = m.group("body"), m.group("rows")
        em = ENTITY.search(body)
        if not em:
            return m.group(0)
        new_rows = additions.get(em.group(1))
        if not new_rows:
            return m.group(0)
        cm = COUNT.search(body)
        if not cm:
            sys.exit(f"{os.path.basename(path)}: block for {em.group(1)} has no count=")
        body = body[:cm.start(1)] + str(int(cm.group(1)) + len(new_rows)) + body[cm.end(1):]
        if rows and not rows.endswith("\n"):
            rows += "\r\n"
        rows += "".join(r + "\r\n" for r in new_rows)
        added += len(new_rows)
        return 'object={' + body + 'transform="' + rows + '"}'

    text = BLOCK.sub(repl, text)
    if added != sum(len(v) for v in additions.values()):
        sys.exit(f"{os.path.basename(path)}: only matched {added} of "
                 f"{sum(len(v) for v in additions.values())} planned rows")

    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8-sig", newline="") as fh:
        fh.write(text)
    os.replace(tmp, path)
    return added


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--terrain", default=DEF_TERRAIN)
    ap.add_argument("--locators", default=DEF_LOCATORS)
    ap.add_argument("--objects", default=DEF_OBJECTS)
    ap.add_argument("--seed", default=DEF_SEED, help="change to reroll every province")
    ap.add_argument("--dry-run", action="store_true", help="report only, write nothing")
    args = ap.parse_args()

    terrain, messages, rejected = load_terrain(args.terrain)
    locators = load_locators(args.locators)
    occupied = load_occupied(args.objects, args.locators)

    variants = {}
    for name, fname in TERRAIN_FILES.items():
        path = os.path.join(args.objects, fname)
        if not os.path.exists(path):
            sys.exit(f"missing planet file for terrain '{name}': {path}")
        variants[name] = load_variants(path)
        if not variants[name]:
            sys.exit(f"{fname}: no object blocks with an entity= to choose from")

    # additions[filename][entity] = [row, ...]
    additions = {}
    per_terrain = {}
    skipped_occupied = 0
    by_design = {}
    unknown = {}
    no_terrain = []

    for pid in sorted(locators):
        x, z = locators[pid]
        if key(x, z) in occupied:
            skipped_occupied += 1
            continue
        name = terrain.get(pid)
        if name is None:
            if pid not in rejected:
                no_terrain.append(pid)
            continue
        if name in SKIP_TERRAINS:
            by_design[name] = by_design.get(name, 0) + 1
            continue
        if name not in TERRAIN_FILES:
            unknown.setdefault(name, []).append(pid)
            continue

        rng = random.Random(f"{args.seed}:{pid}")
        entity = rng.choice(variants[name])
        choices, weights = zip(*SCALE_WEIGHTS[name])
        scale = rng.choices(choices, weights=weights, k=1)[0]

        fname = TERRAIN_FILES[name]
        additions.setdefault(fname, {}).setdefault(entity, []).append(make_row(x, z, scale))
        per_terrain[name] = per_terrain.get(name, 0) + 1

    total = sum(per_terrain.values())

    terrain_name = os.path.basename(args.terrain)
    for msg in messages:
        print(f"BAD DATA: {terrain_name}:{msg}", file=sys.stderr)
    if no_terrain:
        print(f"BAD DATA: {len(no_terrain)} province(s) have a building locator but no "
              f"terrain entry: {', '.join(str(p) for p in no_terrain)}", file=sys.stderr)
    for name in sorted(unknown):
        ids = ", ".join(str(p) for p in unknown[name][:10])
        print(f"BAD DATA: terrain '{name}' is not a known terrain type - typo? "
              f"({len(unknown[name])} province(s): {ids})", file=sys.stderr)

    if args.dry_run:
        print(f"DRY RUN: {total} planets to place ({skipped_occupied} positions already occupied)")
    else:
        written = 0
        for fname in sorted(additions):
            written += rewrite_file(os.path.join(args.objects, fname), additions[fname])
        print(f"OK: placed {written} planets ({skipped_occupied} positions already occupied)")
    for name in sorted(per_terrain, key=lambda n: -per_terrain[n]):
        print(f"    {name:<14} {per_terrain[name]:>5}  -> {TERRAIN_FILES[name]}")
    if by_design:
        summary = ", ".join(f"{n} {by_design[n]}" for n in sorted(by_design))
        print(f"    (no planet family, skipped by design: {summary})")


if __name__ == "__main__":
    main()

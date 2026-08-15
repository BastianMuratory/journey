#!/usr/bin/env python3
"""
classify_body_types.py -- fill in the animation fields on every PokemonData.

WHY THIS EXISTS
---------------
PokemonAnimator plays a different idle and run cycle depending on how a species
carries itself: a Rattata rocks front-to-back, a Machop rolls side-to-side, a
Gastly drifts and never touches the floor, an Ekans slithers. That choice lives
in PokemonData.body_type, and there are 400+ species to set it on.

Guessing it from the mesh bounds does not work -- a Snorlax and a Golem have
almost identical proportions, and nothing in an AABB tells you a Zubat flies.
So the mapping below is written out by hand, one entry per species, keyed on
dex number so alternate forms and costumes inherit from their base form.

WHAT IT WRITES
--------------
Into each data/pokemon/*.tres:

    body_type         which animation set to play
    anim_speed_scale  tempo -- heavy species move slower, small ones twitchier
    anim_amplitude    how far it moves -- heavy species barely budge
    hover_height      resting altitude for HOVER/FLYER, in body heights

Existing values are overwritten, so re-running is safe and idempotent. Anything
you hand-tune in the Godot inspector WILL be overwritten -- put the override in
SPECIES_OVERRIDES here instead so it survives.

USAGE
-----
    python tools/classify_body_types.py plan
        Read-only. Prints what each species would get, plus a coverage report
        against assets/pokemons/ so you can see what is still unclassified.

    python tools/classify_body_types.py apply
        Dry run -- shows the exact edits.

    python tools/classify_body_types.py apply --execute
        Writes the .tres files.

Flags:
    --only PATTERN  Restrict to species whose filename contains PATTERN.
    --json          (plan only) also write tools/body_types.json, so
                    import_pokemons.py can stamp the fields on new .tres files.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

DATA_DIR = "data/pokemon"
ASSET_DIR = "assets/pokemons"
JSON_FILE = "tools/body_types.json"
# Hand edits made in the animation test scene land here, keyed by species slug.
# They beat everything in this file, so tuning done by eye in the game survives
# a re-run rather than being quietly reverted.
OVERRIDES_FILE = "data/body_type_overrides.json"

# Must match the order of PokemonData.BodyType. Godot stores enums as ints, so
# reordering the enum without reordering this will silently mislabel everything.
BIPED, QUADRUPED, HOVER, FLYER, SERPENTINE = range(5)

BODY_TYPE_NAMES = {
    BIPED: "BIPED",
    QUADRUPED: "QUADRUPED",
    HOVER: "HOVER",
    FLYER: "FLYER",
    SERPENTINE: "SERPENTINE",
}

# Resting altitude by body type, in multiples of the creature's own height.
# Grounded species stay at 0 -- their feet are the pivot.
DEFAULT_HOVER_HEIGHT = {
    BIPED: 0.0,
    QUADRUPED: 0.0,
    HOVER: 0.18,
    FLYER: 0.40,
    SERPENTINE: 0.0,
}

# --------------------------------------------------------------------------
# The classification, by dex number
# --------------------------------------------------------------------------
#
# Only the four non-default categories are listed. Everything not named here
# falls through to BIPED, which is the single most common body plan.
#
# The dividing line for FLYER vs BIPED is whether the model has legs it stands
# on: Pidgey and Charizard walk, so they are BIPED even though they can fly.
# FLYER is for species that are drawn airborne, with a wing beat.
# HOVER is airborne with no wings -- ghosts, magnets, balloons, jellyfish.

QUADRUPEDS = {
    1, 2, 3,            # bulbasaur line
    10, 13,             # caterpie, weedle -- grubs, they inch along the floor
    19, 20,             # rattata line
    29, 30, 32, 33,     # nidoran lines, pre-evolutions
    37, 38,             # vulpix line
    46, 47,             # paras line
    50, 51,             # diglett line
    52, 53,             # meowth line
    58, 59,             # growlithe line
    74, 75, 76,         # geodude line
    77, 78,             # ponyta line
    79,                 # slowpoke
    86, 87,             # seel line
    88, 89,             # grimer line
    90, 91,             # shellder line
    98, 99,             # krabby line
    100, 101,           # voltorb line -- spheres that roll, not float
    102,                # exeggcute
    111,                # rhyhorn
    118, 119,           # goldeen line
    128,                # tauros
    129,                # magikarp
    131,                # lapras
    132,                # ditto
    133, 134, 135, 136, # eevee + gen 1 eeveelutions
    138, 139, 140,      # omanyte / kabuto lines
    152, 153, 154,      # chikorita line
    155, 156,           # cyndaquil, quilava
    170, 171,           # chinchou line
    194, 195,           # wooper line
    196, 197,           # espeon, umbreon
    222,                # corsola
    223, 224,           # remoraid line
    228, 229,           # houndour line
    231, 232,           # phanpy line
    243, 244, 245,      # legendary beasts
    247,                # pupitar
    258,                # mudkip
    270,                # lotad
    318, 319,           # carvanha line
    320, 321,           # wailmer line
    322, 323,           # numel line
    324,                # torkoal
    328,                # trapinch
    349,                # feebas
    357,                # tropius -- wings, but it walks on four legs
    359,                # absol
    366,                # clamperl
    370,                # luvdisc
    372,                # shelgon
    376,                # metagross
    382,                # kyogre
    387, 388, 389,      # turtwig line
    399, 400,           # bidoof line
    470, 471,           # leafeon, glaceon
    483,                # dialga
    492,                # shaymin (land forme; sky is overridden below)
    493,                # arceus
    551,                # sandile -- the evolutions stand up
    570,                # zorua
    633, 634,           # deino, zweilous
    700,                # sylveon
    702,                # dedenne
    736, 737,           # grubbin, charjabug
    767,                # wimpod
    769, 770,           # sandygast line
    771,                # pyukumuku
    791,                # solgaleo
    878, 879,           # cufant line
    888, 889,           # zacian, zamazenta
    924, 925,           # tandemaus line
    977,                # dondozo
    978,                # tatsugiri
    980,                # clodsire
    999,                # gimmighoul
    1007, 1008,         # koraidon, miraidon
}

HOVERERS = {
    70, 71,             # weepinbell, victreebel -- both float
    72, 73,             # tentacool line
    81, 82,             # magnemite line
    92, 93,             # gastly, haunter (gengar stands, so it is BIPED)
    109, 110,           # koffing line
    116, 117,           # horsea line -- seahorses hang upright in the water
    120, 121,           # staryu line
    137,                # porygon
    151,                # mew
    200,                # misdreavus
    337, 338,           # lunatone, solrock
    343, 344,           # baltoy line
    374, 375,           # beldum, metang
    385,                # jirachi
    386,                # deoxys, every forme
    425, 426,           # drifloon line
    429,                # mismagius
    442,                # spiritomb
    479,                # rotom, every appliance
    480, 481, 482,      # lake trio
    489, 490,           # phione, manaphy
    491,                # darkrai
    546, 547,           # cottonee line
    597, 598,           # ferroseed line
    599, 600, 601,      # klink line
    607, 608, 609,      # litwick line
    707,                # klefki
    710, 711,           # pumpkaboo line
    885,                # dreepy
}

FLYERS = {
    12,                 # butterfree
    15,                 # beedrill
    41, 42,             # zubat line
    49,                 # venomoth
    142,                # aerodactyl
    176,                # togetic
    207,                # gligar
    227,                # skarmory
    249, 250,           # lugia, ho-oh
    251,                # celebi
    276, 277,           # taillow line
    278, 279,           # wingull line
    329, 330,           # vibrava, flygon
    333, 334,           # swablu line
    373,                # salamence
    380, 381,           # latias, latios
    468,                # togekiss
    472,                # gliscor
    487,                # giratina
    488,                # cresselia
    587,                # emolga
    635,                # hydreigon
    738,                # vikavolt
    792,                # lunala
    886, 887,           # drakloak, dragapult
    890,                # eternatus
}

SERPENTINES = {
    23, 24,             # ekans line
    95,                 # onix
    130,                # gyarados
    147, 148,           # dratini, dragonair (dragonite stands)
    350,                # milotic
    367, 368,           # huntail, gorebyss
    384,                # rayquaza
    718,                # zygarde
}

# Species whose folder name, not dex number, decides the answer. Matched against
# the .tres filename, so "0492_shaymin_sky" hits and "0492_shaymin_land" does not.
FORM_OVERRIDES = {
    "shaymin_sky": {"body_type": FLYER},
}

# Per-species tuning. Everything here is a deliberate exception to the defaults.
SPECIES_OVERRIDES = {
    # --- heavy things should look heavy: slower, and barely moving ---
    76:   {"speed": 0.75, "amplitude": 0.65},   # golem
    95:   {"speed": 0.55, "amplitude": 0.70},   # onix
    112:  {"speed": 0.80, "amplitude": 0.75},   # rhydon
    143:  {"speed": 0.55, "amplitude": 0.55},   # snorlax
    208:  {"speed": 0.55, "amplitude": 0.70},   # steelix
    248:  {"speed": 0.75, "amplitude": 0.75},   # tyranitar
    321:  {"speed": 0.50, "amplitude": 0.50},   # wailord
    323:  {"speed": 0.75, "amplitude": 0.70},   # camerupt
    376:  {"speed": 0.70, "amplitude": 0.60},   # metagross
    377:  {"speed": 0.65, "amplitude": 0.60},   # regirock
    378:  {"speed": 0.65, "amplitude": 0.60},   # regice
    379:  {"speed": 0.65, "amplitude": 0.60},   # registeel
    383:  {"speed": 0.70, "amplitude": 0.75},   # groudon
    389:  {"speed": 0.70, "amplitude": 0.65},   # torterra
    486:  {"speed": 0.55, "amplitude": 0.60},   # regigigas
    879:  {"speed": 0.70, "amplitude": 0.70},   # copperajah
    977:  {"speed": 0.70, "amplitude": 0.70},   # dondozo

    # --- small and twitchy: quicker, and moving more ---
    10:   {"speed": 1.30, "amplitude": 1.20},   # caterpie
    13:   {"speed": 1.30, "amplitude": 1.20},   # weedle
    19:   {"speed": 1.35, "amplitude": 1.15},   # rattata
    25:   {"speed": 1.25, "amplitude": 1.15},   # pikachu
    50:   {"speed": 1.20, "amplitude": 1.25},   # diglett
    172:  {"speed": 1.30, "amplitude": 1.20},   # pichu
    175:  {"speed": 1.25, "amplitude": 1.20},   # togepi
    183:  {"speed": 1.20, "amplitude": 1.15},   # marill
    311:  {"speed": 1.30, "amplitude": 1.15},   # plusle
    312:  {"speed": 1.30, "amplitude": 1.15},   # minun
    587:  {"speed": 1.35, "amplitude": 1.10},   # emolga
    702:  {"speed": 1.30, "amplitude": 1.20},   # dedenne
    924:  {"speed": 1.35, "amplitude": 1.20},   # tandemaus
    925:  {"speed": 1.30, "amplitude": 1.20},   # maushold

    # --- cocoons: alive, but only just ---
    11:   {"speed": 0.60, "amplitude": 0.45},   # metapod
    14:   {"speed": 0.60, "amplitude": 0.45},   # kakuna
    102:  {"speed": 0.80, "amplitude": 0.70},   # exeggcute
    247:  {"speed": 0.70, "amplitude": 0.55},   # pupitar

    # --- fliers whose altitude wants tuning away from the 0.40 default ---
    12:   {"hover": 0.30},                      # butterfree, flutters low
    41:   {"hover": 0.55},                      # zubat, roosts high
    42:   {"hover": 0.55},                      # golbat
    142:  {"hover": 0.50},                      # aerodactyl
    249:  {"hover": 0.30},                      # lugia
    250:  {"hover": 0.35},                      # ho-oh
    384:  {"hover": 0.50, "speed": 0.70},       # rayquaza, a serpent in the sky
    487:  {"hover": 0.25},                      # giratina
    718:  {"hover": 0.15},                      # zygarde
    890:  {"hover": 0.30, "speed": 0.80},       # eternatus

    # --- hoverers that sit closer to the ground than the 0.18 default ---
    50:   {"hover": 0.0},                       # diglett is IN the ground
    100:  {"hover": 0.0},                       # voltorb rests on it
    343:  {"hover": 0.08},                      # baltoy spins on its point
    607:  {"hover": 0.08},                      # litwick
    885:  {"hover": 0.25},                      # dreepy
}

# --------------------------------------------------------------------------
# .tres editing
# --------------------------------------------------------------------------

# Fields this script owns. Written in this order, and any pre-existing copy of
# them is removed first so re-runs cannot leave duplicates behind.
MANAGED_FIELDS = ("body_type", "anim_speed_scale", "anim_amplitude", "hover_height")

RESOURCE_HEADER = re.compile(r"^\s*\[resource\]\s*$")
SECTION_HEADER = re.compile(r"^\s*\[")
DEX_LINE = re.compile(r"^\s*dex_number\s*=\s*(?P<dex>\d+)\s*$")
MANAGED_LINE = re.compile(rf"^\s*({'|'.join(MANAGED_FIELDS)})\s*=")
# Everything we write goes after this, keeping the file grouped like the
# @export_group order in pokemon_data.gd.
ANCHOR_LINE = re.compile(r"^\s*model_scale\s*=")
METADATA_LINE = re.compile(r"^\s*metadata/")


class Console:
    """Minimal ANSI colouring that degrades to plain text when piped."""

    def __init__(self) -> None:
        self.enabled = sys.stdout.isatty()

    def _wrap(self, code: str, text: str) -> str:
        return f"\033[{code}m{text}\033[0m" if self.enabled else text

    def bold(self, text: str) -> str:
        return self._wrap("1", text)

    def green(self, text: str) -> str:
        return self._wrap("32", text)

    def yellow(self, text: str) -> str:
        return self._wrap("33", text)

    def red(self, text: str) -> str:
        return self._wrap("31", text)

    def dim(self, text: str) -> str:
        return self._wrap("2", text)


C = Console()


BODY_TYPE_VALUES = {name: value for value, name in BODY_TYPE_NAMES.items()}


def load_overrides(root: Path) -> dict[str, dict]:
    """
    Hand edits from the animation test scene, keyed by species slug.

    Missing or malformed is not an error -- the file only exists once somebody
    has actually saved an edit, and a broken one should not stop a re-classify.
    """
    path = root / OVERRIDES_FILE
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        print(C.yellow(f"warning: {OVERRIDES_FILE} is not valid JSON ({error}); ignoring"))
        return {}
    species = data.get("species", {})
    return species if isinstance(species, dict) else {}


def body_type_for(dex: int, slug: str, overrides: dict[str, dict] | None = None) -> int:
    entry = (overrides or {}).get(slug, {})
    if "body_type" in entry:
        wanted = entry["body_type"]
        # Accept either the name or the raw enum index, so the file stays
        # readable but a hand-typed integer still works.
        if isinstance(wanted, str) and wanted.upper() in BODY_TYPE_VALUES:
            return BODY_TYPE_VALUES[wanted.upper()]
        if isinstance(wanted, int) and wanted in BODY_TYPE_NAMES:
            return wanted
        print(C.yellow(f"warning: {slug} has an unknown body_type {wanted!r}; ignoring"))

    for needle, override in FORM_OVERRIDES.items():
        if needle in slug and "body_type" in override:
            return override["body_type"]
    if dex in QUADRUPEDS:
        return QUADRUPED
    if dex in HOVERERS:
        return HOVER
    if dex in FLYERS:
        return FLYER
    if dex in SERPENTINES:
        return SERPENTINE
    return BIPED


def settings_for(dex: int, slug: str, overrides: dict[str, dict] | None = None) -> dict:
    """
    The four managed values for one species, in priority order: the overrides
    file, then this script's per-dex tables, then the body-type defaults.
    """
    entry = (overrides or {}).get(slug, {})
    body_type = body_type_for(dex, slug, overrides)
    tuning = SPECIES_OVERRIDES.get(dex, {})

    def pick(override_key: str, table_key: str, fallback: float) -> float:
        if override_key in entry:
            return float(entry[override_key])
        return float(tuning.get(table_key, fallback))

    return {
        "body_type": body_type,
        "anim_speed_scale": round(pick("anim_speed_scale", "speed", 1.0), 2),
        "anim_amplitude": round(pick("anim_amplitude", "amplitude", 1.0), 2),
        "hover_height": round(
            pick("hover_height", "hover", DEFAULT_HOVER_HEIGHT[body_type]), 2
        ),
    }


def format_value(field: str, value) -> str:
    # Godot writes ints for enums and floats with a decimal point for reals.
    if field == "body_type":
        return str(int(value))
    return f"{float(value):g}" if float(value) % 1 else f"{float(value):.1f}"


def dex_from(path: Path) -> int | None:
    """Dex number from the file's contents, falling back to its name."""
    for line in path.read_text(encoding="utf-8").splitlines():
        match = DEX_LINE.match(line)
        if match:
            return int(match.group("dex"))
    digits = re.match(r"^(\d+)", path.stem)
    return int(digits.group(1)) if digits else None


def rewrite(path: Path, settings: dict) -> tuple[list[str], bool]:
    """
    Returns (new_lines, changed). Strips any existing copy of the managed fields
    and re-inserts them as a block inside [resource].
    """
    original = path.read_text(encoding="utf-8").splitlines(keepends=True)

    block = [
        f"{field} = {format_value(field, settings[field])}\n" for field in MANAGED_FIELDS
    ]

    output: list[str] = []
    in_resource = False
    inserted = False
    anchor_index: int | None = None

    for line in original:
        if RESOURCE_HEADER.match(line):
            in_resource = True
            output.append(line)
            continue

        if in_resource and SECTION_HEADER.match(line):
            # Leaving [resource] without having found an anchor -- append here.
            if not inserted:
                output.extend(block)
                inserted = True
            in_resource = False
            output.append(line)
            continue

        if in_resource and MANAGED_LINE.match(line):
            continue  # dropped; the block replaces it

        # Keep metadata/_custom_type_script last, the way Godot writes it.
        if in_resource and not inserted and METADATA_LINE.match(line):
            output.extend(block)
            inserted = True
            output.append(line)
            continue

        output.append(line)
        if in_resource and ANCHOR_LINE.match(line):
            anchor_index = len(output)

    if not inserted:
        if anchor_index is not None:
            output[anchor_index:anchor_index] = block
        else:
            if output and not output[-1].endswith("\n"):
                output[-1] += "\n"
            output.extend(block)

    return output, output != original


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------


def find_project_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "project.godot").is_file():
            return candidate
    sys.exit("error: could not locate project.godot -- run this from inside the project")


def data_files(root: Path, only: str | None) -> list[Path]:
    data_dir = root / DATA_DIR
    if not data_dir.is_dir():
        sys.exit(f"error: {DATA_DIR} not found under {root}")
    files = sorted(p for p in data_dir.glob("*.tres"))
    if only:
        files = [p for p in files if only.lower() in p.name.lower()]
    return files


def asset_species(root: Path) -> dict[int, list[str]]:
    """dex -> folder names under assets/pokemons, so forms group together."""
    asset_dir = root / ASSET_DIR
    found: dict[int, list[str]] = {}
    if not asset_dir.is_dir():
        return found
    for folder in sorted(asset_dir.iterdir()):
        if not folder.is_dir():
            continue
        digits = re.match(r"^(\d+)", folder.name)
        if not digits:
            continue
        found.setdefault(int(digits.group(1)), []).append(folder.name)
    return found


def command_plan(root: Path, only: str | None, write_json: bool) -> int:
    assets = asset_species(root)
    overrides = load_overrides(root)
    files = data_files(root, only)
    have_data = set()

    print(C.bold(f"\nAnimation settings for {len(files)} .tres files in {DATA_DIR}\n"))
    if overrides:
        print(C.dim(f"  {len(overrides)} hand override(s) loaded from {OVERRIDES_FILE}\n"))
    for path in files:
        dex = dex_from(path)
        if dex is None:
            print(f"  {C.red('skip')}  {path.name} -- no dex number")
            continue
        have_data.add(dex)
        settings = settings_for(dex, path.stem, overrides)
        tuning = ""
        if settings["anim_speed_scale"] != 1.0 or settings["anim_amplitude"] != 1.0:
            tuning = C.dim(
                f"  speed {settings['anim_speed_scale']}"
                f"  amp {settings['anim_amplitude']}"
            )
        hover = ""
        if settings["hover_height"]:
            hover = C.dim(f"  hover {settings['hover_height']}")
        mark = C.yellow(" *") if path.stem in overrides else ""
        print(
            f"  {path.stem:<34}{C.green(BODY_TYPE_NAMES[settings['body_type']]):<22}"
            f"{tuning}{hover}{mark}"
        )

    # Coverage counts folders, not dex numbers, because alternate forms get their
    # own .tres and can classify differently from their base form.
    tally: dict[int, int] = {}
    for dex, folders in sorted(assets.items()):
        for slug in folders:
            body_type = body_type_for(dex, slug, overrides)
            tally[body_type] = tally.get(body_type, 0) + 1

    total = sum(len(f) for f in assets.values())
    print(C.bold(f"\nCoverage across {total} folders ({len(assets)} dex numbers) in {ASSET_DIR}"))
    for body_type in (BIPED, QUADRUPED, HOVER, FLYER, SERPENTINE):
        print(f"  {BODY_TYPE_NAMES[body_type]:<12} {tally.get(body_type, 0):>4}")
    missing_data = sorted(set(assets) - have_data)
    if missing_data:
        print(
            C.yellow(f"\n  {len(missing_data)} dex numbers have art but no .tres yet")
            + C.dim(" -- run tools/generate_pokemon_data.py")
        )

    if write_json:
        payload = {
            "_comment": (
                "slug -> animation settings, generated by tools/classify_body_types.py. "
                "body_type indexes PokemonData.BodyType: "
                "0 BIPED, 1 QUADRUPED, 2 HOVER, 3 FLYER, 4 SERPENTINE."
            ),
            "species": {
                slug: settings_for(dex, slug, overrides)
                for dex, folders in sorted(assets.items())
                for slug in folders
            },
        }
        json_path = root / JSON_FILE
        json_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(C.bold(f"\nWrote {JSON_FILE}"))

    print(C.dim("\nNothing was modified. Run 'apply --execute' to write the .tres files."))
    return 0


def command_apply(root: Path, execute: bool, only: str | None) -> int:
    files = data_files(root, only)
    overrides = load_overrides(root)

    if not execute:
        print(C.yellow(C.bold("\nDRY RUN -- nothing will be written.")))
        print(C.dim("Re-run with --execute to apply.\n"))
    if overrides:
        print(C.dim(f"{len(overrides)} hand override(s) from {OVERRIDES_FILE} take priority.\n"))

    changed = 0
    unchanged = 0
    for path in files:
        dex = dex_from(path)
        if dex is None:
            print(f"  {C.red('skip')}  {path.name} -- no dex number")
            continue

        settings = settings_for(dex, path.stem, overrides)
        lines, is_changed = rewrite(path, settings)
        if not is_changed:
            unchanged += 1
            continue

        changed += 1
        print(C.bold(f"\n{path.name}"))
        for field in MANAGED_FIELDS:
            shown = (
                BODY_TYPE_NAMES[settings[field]]
                if field == "body_type"
                else format_value(field, settings[field])
            )
            print(f"  {field:<18} {shown}")
        if execute:
            path.write_text("".join(lines), encoding="utf-8")

    print(
        C.bold(f"\n{changed} file(s) updated, {unchanged} already correct")
    )
    if execute:
        print(C.green("Done. Reopen the project in Godot to pick the values up."))
    else:
        print(C.yellow("Dry run only. Re-run with --execute to apply."))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Set animation body types on Journey's PokemonData resources.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--only", help="restrict to .tres files matching this substring")
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan_parser = subparsers.add_parser("plan", help="report what would be set (read-only)")
    plan_parser.add_argument(
        "--json", action="store_true", help=f"also write {JSON_FILE}"
    )

    apply_parser = subparsers.add_parser("apply", help="write the .tres files")
    apply_parser.add_argument("--execute", action="store_true", help="actually write")

    # --only is accepted on either side of the subcommand. Argparse only allows
    # one position by default, and getting it wrong is a silent no-op that looks
    # like the tool ignored you.
    for subparser in (plan_parser, apply_parser):
        subparser.add_argument("--only", dest="only_after", help=argparse.SUPPRESS)

    args = parser.parse_args()
    root = find_project_root(Path(__file__).resolve().parent)
    only = args.only_after or args.only

    if args.command == "plan":
        return command_plan(root, only, args.json)
    return command_apply(root, args.execute, only)


if __name__ == "__main__":
    sys.exit(main())

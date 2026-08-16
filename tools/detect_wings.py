#!/usr/bin/env python3
"""
detect_wings.py -- find each flyer's wing hinge and write it onto its PokemonData.

WHY THIS EXISTS
---------------
The models are single static .obj meshes with no skeleton, so a wing beat cannot
be keyframed. pokemon/wing_deform.gdshaderinc bends the wings in the vertex
shader instead: every vertex past a hinge line rotates about that line, scaled by
how far out it sits, so the root barely moves and the tip sweeps the arc.

That needs one number per species -- where the body stops and the wing starts --
and eyeballing it 46 times is exactly the kind of job a script should do. The
meshes make it easy: they are symmetric about x = 0, and a wing is a thin sheet,
so the mesh's cross-section collapses the moment you leave the body:

    butterfree  [1.67, 3.12, 0.70, 0.03, 0.04, ...]   <- hinge at bin 3
    pidgeot     [8.41, 7.81, 1.99, 0.13, 0.09, ...]   <- hinge at bin 3
    charizard   [7.74,12.32, 5.17, 5.64, 0.34, ...]   <- hinge at bin 4

Each number is the y-by-z bounding area of one slice of |x|. Walking inward from
the tip and stopping at the first slice that is still solid finds the shoulder.

WHAT IT WRITES
--------------
Into each data/pokemon/*.tres, for FLYER species only:

    wing_hinge           where the wing leaves the body, as a fraction of the
                         half-width
    wing_root_height     height of the hinge line, as a fraction of mesh height
    flap_degrees         half the stroke; 0 means "no wings found", and the
                         animator falls back to its whole-body wing beat
    flap_twist_degrees   how far the wing feathers into the stroke
    wing_curve           how much of the bend sits out near the tip

Every value is a fraction of the mesh's own size, so nothing here breaks if
model_scale changes.

Species you have tuned by eye in the animation test scene are read from
data/body_type_overrides.json and win over anything measured here, the same way
classify_body_types.py treats them -- measuring and hand-tuning must not fight.

USAGE
-----
    python tools/detect_wings.py plan
        Read-only. Measures every flyer and prints what it would write, loudest
        about the ones it could not find wings on.

    python tools/detect_wings.py apply
        Dry run -- shows the exact edits.

    python tools/detect_wings.py apply --execute
        Writes the .tres files.

Flags:
    --only PATTERN  Restrict to species whose filename contains PATTERN.
    --all-species   Measure every species, not just the ones marked FLYER. Useful
                    for finding winged bipeds like Charizard; nothing is written
                    for them unless you also pass --execute.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

DATA_DIR = "data/pokemon"
OVERRIDES_FILE = "data/body_type_overrides.json"

FLYER = 3  # must match PokemonData.BodyType.FLYER

MANAGED_FIELDS = [
    "wing_hinge",
    "flap_degrees",
    "flap_twist_degrees",
    "wing_root_height",
    "wing_curve",
]

# How many slices of |x| the mesh is cut into when looking for the shoulder.
# 24 over a half-width places the hinge within ~4% of the span, and keeps enough
# vertices per slice that one stray point cannot open a gap in the middle of a
# body. These meshes run 350-2500 vertices, so finer than this reads as noise.
BINS = 24
# A slice counts as "body" while it is at least this fraction of the thickest
# slice. Measured wings sit around 0.05-0.20 of their own body's thickness, so
# 0.30 clears the thickest wings without reaching into the shoulder.
BODY_THRESHOLD = 0.30
# Below this, whatever was found is too small to be a wing -- a fin, a tail, or
# a mesh that simply is not built the way this script assumes.
MIN_WING_FRACTION = 0.22
# No hinge is allowed inside this much of the half-width. These meshes are built
# from boxes, so the slab right on x = 0 often holds no vertices at all -- it
# falls between the two faces of the body -- and reads as thin as any wing.
MIN_BODY_FRACTION = 0.12
# A wing that is only a handful of vertices bends into mush rather than flapping.
MIN_WING_VERTEX_FRACTION = 0.04

# Species classified FLYER for how they move rather than for having wings.
# Nothing here gets a hinge -- Rotom is a ball of plasma and Whimsicott is a
# cotton cloud, and bending either in half at 30 degrees looks like a bug.
# They keep the animator's whole-body wing beat, which is what they had before.
NOT_WINGED = {
    479,  # rotom, every form
    547,  # whimsicott
}

# Per-dex tuning, applied after measurement. Only species whose stroke reads
# wrong at the default are listed; everything else takes the computed value.
#
#   flap  -- half the stroke in degrees
#   twist -- angle of attack
#   curve -- >1.5 keeps the bend out at the tip
#   root  -- overrides the measured hinge height, for the handful of meshes
#            where legs or ears sit further out than the wing does
SPECIES_TUNING: dict[int, dict[str, float]] = {
    12: {"flap": 42, "twist": 16, "curve": 1.25},   # butterfree -- broad insect wings, near-rigid
    15: {"flap": 46, "twist": 10, "curve": 1.1},    # beedrill -- tiny wings, blurring beat
    41: {"flap": 38, "twist": 14},                  # zubat -- leathery, deep stroke
    42: {"flap": 38, "twist": 14},                  # golbat
    49: {"flap": 44, "twist": 16, "curve": 1.2},    # venomoth
    144: {"flap": 26, "twist": 10, "curve": 1.9},   # articuno -- huge span, soars
    321: {"flap": 16, "twist": 6, "curve": 1.2},    # wailord -- flippers, not wings
    329: {"root": 0.70},                            # vibrava -- measured its antennae
    373: {"root": 0.55},                            # salamence -- wings sit mid-back, feet are wider
    380: {"root": 0.55},                            # latias -- measured its head fins
    381: {"root": 0.55},                            # latios
    488: {"root": 0.55},                            # cresselia -- the crescents arc above the body
    587: {"root": 0.45},                            # emolga -- glide membrane, wrist to ankle
    145: {"flap": 26, "twist": 10, "curve": 1.9},   # zapdos
    146: {"flap": 26, "twist": 10, "curve": 1.9},   # moltres
    149: {"flap": 30, "twist": 12},                 # dragonite -- small wings, big body
    249: {"flap": 24, "twist": 8, "curve": 2.0},    # lugia -- glides more than it beats
    250: {"flap": 26, "twist": 10, "curve": 1.9},   # ho-oh
    384: {"flap": 22, "twist": 8, "curve": 2.0},    # rayquaza
}

# --------------------------------------------------------------------------
# .tres parsing and rewriting
# --------------------------------------------------------------------------

RESOURCE_HEADER = re.compile(r"^\s*\[resource\]\s*$")
SECTION_HEADER = re.compile(r"^\s*\[")
DEX_LINE = re.compile(r"^\s*dex_number\s*=\s*(?P<dex>\d+)\s*$")
BODY_TYPE_LINE = re.compile(r"^\s*body_type\s*=\s*(?P<value>\d+)\s*$")
MESH_LINE = re.compile(r'^\s*\[ext_resource[^\]]*path="res://(?P<path>[^"]+\.obj)"')
MANAGED_LINE = re.compile(rf"^\s*({'|'.join(MANAGED_FIELDS)})\s*=")
# Written straight after the animation block, matching the @export_group order
# in pokemon_data.gd. hover_height is the last field of that group.
ANCHOR_LINE = re.compile(r"^\s*hover_height\s*=")
FALLBACK_ANCHOR = re.compile(r"^\s*model_scale\s*=")
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


class Species:
    """One .tres, and the mesh it points at."""

    def __init__(self, path: Path, root: Path) -> None:
        self.path = path
        self.slug = path.stem
        self.dex: int | None = None
        self.body_type: int | None = None
        self.mesh: Path | None = None

        for line in path.read_text(encoding="utf-8").splitlines():
            mesh = MESH_LINE.match(line)
            if mesh and self.mesh is None:
                self.mesh = root / mesh.group("path")
                continue
            dex = DEX_LINE.match(line)
            if dex:
                self.dex = int(dex.group("dex"))
                continue
            body = BODY_TYPE_LINE.match(line)
            if body:
                self.body_type = int(body.group("value"))

        if self.dex is None:
            digits = re.match(r"^(\d+)", self.slug)
            self.dex = int(digits.group(1)) if digits else 0

    @property
    def is_flyer(self) -> bool:
        return self.body_type == FLYER


def read_vertices(path: Path) -> list[tuple[float, float, float]]:
    out: list[tuple[float, float, float]] = []
    with path.open(encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            if not line.startswith("v "):
                continue
            parts = line.split()
            if len(parts) >= 4:
                out.append((float(parts[1]), float(parts[2]), float(parts[3])))
    return out


# --------------------------------------------------------------------------
# Measurement
# --------------------------------------------------------------------------


def _thickness(points: list[tuple[float, float]]) -> float:
    """
    How thin a slice of the mesh is: the smaller principal spread of its points.
    Zero for a perfectly flat sheet whatever angle it sits at, large for anything
    with a body's worth of depth.
    """
    count = len(points)
    if count < 4:
        return 0.0
    mean_a = sum(p[0] for p in points) / count
    mean_b = sum(p[1] for p in points) / count
    var_a = sum((p[0] - mean_a) ** 2 for p in points) / count
    var_b = sum((p[1] - mean_b) ** 2 for p in points) / count
    covar = sum((p[0] - mean_a) * (p[1] - mean_b) for p in points) / count
    # Smaller eigenvalue of the 2x2 covariance, in closed form.
    half_trace = (var_a + var_b) / 2.0
    gap = max(half_trace * half_trace - (var_a * var_b - covar * covar), 0.0)
    return (max(half_trace - gap**0.5, 0.0)) ** 0.5


def measure(vertices: list[tuple[float, float, float]]) -> dict:
    """
    Everything the shader needs, as fractions of the mesh's own size, plus the
    profile and warnings that let a human check the guess without opening Godot.
    """
    result: dict = {"ok": False, "reason": "", "warnings": [], "profile": []}
    if len(vertices) < 24:
        result["reason"] = "mesh has too few vertices"
        return result

    xs = [v[0] for v in vertices]
    ys = [v[1] for v in vertices]
    span = max(abs(min(xs)), abs(max(xs)))
    low_y, high_y = min(ys), max(ys)
    height = high_y - low_y
    if span <= 0.0 or height <= 0.0:
        result["reason"] = "mesh is flat or has no width"
        return result

    # Slice by |x| and measure how *thick* each slice is, not how much of it
    # there is. A wing is a sheet: whatever else is true of it, it is thin in one
    # direction. So take the smaller principal spread of each slice's (y, z)
    # points -- the sheet's thickness, found without assuming which way the sheet
    # is turned. Bounding-box area fails here, because a bat wing is as tall as
    # the body it hangs off and only thin edge-on.
    buckets: list[list[tuple[float, float]]] = [[] for _ in range(BINS)]
    for x, y, z in vertices:
        index = min(BINS - 1, int(abs(x) / span * BINS))
        buckets[index].append((y, z))

    profile = [_thickness(bucket) for bucket in buckets]
    result["profile"] = [round(v, 3) for v in profile]

    body_thickness = max(profile)
    if body_thickness <= 0.0:
        result["reason"] = "could not measure a cross-section"
        return result

    # Scan outward for the first slice that is thin *and stays thin*: the mean of
    # everything past it has to be thin too. The tail test is what makes this
    # survive real meshes -- a waist between shoulders would otherwise read as
    # the hinge, and a claw or a stinger out at the tip would otherwise hide one.
    threshold = body_thickness * BODY_THRESHOLD
    hinge_bin = BINS
    for index in range(round(BINS * MIN_BODY_FRACTION), BINS):
        if profile[index] >= threshold:
            continue
        tail = profile[index:]
        if sum(tail) / len(tail) < threshold:
            hinge_bin = index
            break

    hinge = hinge_bin / BINS
    wing_fraction = 1.0 - hinge
    if wing_fraction < MIN_WING_FRACTION:
        result["reason"] = f"body fills {hinge:.0%} of the half-width -- no wing to bend"
        return result

    hinge_x = hinge * span
    wing = [v for v in vertices if abs(v[0]) > hinge_x]
    if len(wing) < len(vertices) * MIN_WING_VERTEX_FRACTION:
        result["reason"] = f"only {len(wing)} of {len(vertices)} vertices are past the hinge"
        return result

    # The hinge line sits at the height of the wing, not the body's middle, so
    # measure it out where there is nothing else: the outer half of the wing.
    # The inner half is contaminated on any species with legs or a tail wide
    # enough to reach past the hinge -- Salamence's feet read as "wing at ankle
    # height" and drag the hinge to the floor. Median, not mean, so a single
    # dangling feather cannot move it either.
    band = hinge_x + (span - hinge_x) * 0.5
    root_band = [v[1] for v in wing if abs(v[0]) >= band] or [v[1] for v in wing]
    root_height = (statistics.median(root_band) - low_y) / height

    # Both wings get the same hinge, so a lopsided mesh -- a held item, a single
    # raised wing -- is worth flagging even though the bend still works.
    right = [v for v in wing if v[0] > 0.0]
    left = [v for v in wing if v[0] < 0.0]
    if left and right:
        balance = min(len(left), len(right)) / max(len(left), len(right))
        if balance < 0.7:
            result["warnings"].append(
                f"wings are lopsided ({len(left)} vs {len(right)} vertices) -- check by eye"
            )
    else:
        result["warnings"].append("only one side has a wing -- check by eye")

    # A hinge down by the feet or up above the head is usually the detector
    # having found legs, a tail or a crest rather than a wing.
    if root_height < 0.2:
        result["warnings"].append(
            f"hinge sits at {root_height:.0%} of the height -- legs or a tail?"
        )
    elif root_height > 0.9:
        result["warnings"].append(
            f"hinge sits at {root_height:.0%} of the height -- a crest or ears?"
        )

    result.update(
        {
            "ok": True,
            "hinge": round(hinge, 2),
            "root_height": round(min(max(root_height, 0.0), 1.0), 2),
            "wing_fraction": wing_fraction,
            "span": span,
            "wing_vertices": len(wing),
            "vertices": len(vertices),
        }
    )
    return result


def settings_for(dex: int, measured: dict, entry: dict) -> dict:
    """
    Measured, then the per-dex table, then whatever the animation test scene
    saved -- last one wins, so tuning by eye always survives a re-run.
    """
    if not measured["ok"]:
        settings = {
            "wing_hinge": 0.0,
            "flap_degrees": 0.0,
            "flap_twist_degrees": 0.0,
            "wing_root_height": 0.5,
            "wing_curve": 1.5,
        }
    else:
        # A long wing swings further than a stub, so the default stroke scales
        # with how much of the silhouette is actually wing.
        flap = round(24.0 + 14.0 * min(measured["wing_fraction"], 1.0))
        settings = {
            "wing_hinge": measured["hinge"],
            "flap_degrees": float(flap),
            "flap_twist_degrees": float(min(round(flap * 0.35), 14)),
            "wing_root_height": measured["root_height"],
            "wing_curve": 1.5,
        }

        tuning = SPECIES_TUNING.get(dex, {})
        if "flap" in tuning:
            settings["flap_degrees"] = float(tuning["flap"])
        if "twist" in tuning:
            settings["flap_twist_degrees"] = float(tuning["twist"])
        if "curve" in tuning:
            settings["wing_curve"] = float(tuning["curve"])
        if "root" in tuning:
            settings["wing_root_height"] = float(tuning["root"])

    for field in MANAGED_FIELDS:
        if field in entry:
            settings[field] = float(entry[field])
    return settings


# --------------------------------------------------------------------------
# Writing
# --------------------------------------------------------------------------


def format_value(value: float) -> str:
    return f"{float(value):g}" if float(value) % 1 else f"{float(value):.1f}"


def rewrite(path: Path, settings: dict) -> tuple[list[str], bool]:
    """
    Returns (new_lines, changed). Strips any existing copy of the managed fields
    and re-inserts them as one block inside [resource]. Same shape as the rewrite
    in classify_body_types.py, deliberately -- two tools editing the same files
    should leave them looking the same.
    """
    original = path.read_text(encoding="utf-8").splitlines(keepends=True)
    block = [f"{field} = {format_value(settings[field])}\n" for field in MANAGED_FIELDS]

    # First pass strips any existing copy of the fields and notes every place the
    # block could go. Deciding where to put it only once everything is stripped
    # keeps the choice from depending on where the old copy happened to be.
    output: list[str] = []
    in_resource = False
    anchor_index: int | None = None      # after hover_height, where it belongs
    fallback_index: int | None = None    # after model_scale, if there is no anchor
    metadata_index: int | None = None    # before metadata/, which Godot keeps last
    end_index: int | None = None         # end of [resource]

    for line in original:
        if RESOURCE_HEADER.match(line):
            in_resource = True
            output.append(line)
            continue

        if in_resource and SECTION_HEADER.match(line):
            in_resource = False
            end_index = len(output)
            output.append(line)
            continue

        if in_resource and MANAGED_LINE.match(line):
            continue  # dropped; the block replaces it

        if in_resource and metadata_index is None and METADATA_LINE.match(line):
            metadata_index = len(output)

        output.append(line)
        if in_resource and ANCHOR_LINE.match(line):
            anchor_index = len(output)
        elif in_resource and FALLBACK_ANCHOR.match(line):
            fallback_index = len(output)

    # Straight after the animation fields, so the file reads in the same order as
    # the @export_group list in pokemon_data.gd.
    index = next(
        (i for i in (anchor_index, fallback_index, metadata_index, end_index) if i is not None),
        None,
    )
    if index is None:
        if output and not output[-1].endswith("\n"):
            output[-1] += "\n"
        output.extend(block)
    else:
        output[index:index] = block

    return output, output != original


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------


def find_project_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "project.godot").is_file():
            return candidate
    sys.exit("error: could not locate project.godot -- run this from inside the project")


def load_overrides(root: Path) -> dict[str, dict]:
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


def collect(root: Path, only: str | None, all_species: bool) -> list[Species]:
    data_dir = root / DATA_DIR
    if not data_dir.is_dir():
        sys.exit(f"error: {DATA_DIR} not found under {root}")

    out: list[Species] = []
    for path in sorted(data_dir.glob("*.tres")):
        if only and only.lower() not in path.name.lower():
            continue
        species = Species(path, root)
        if all_species or species.is_flyer:
            out.append(species)
    return out


def evaluate(species: Species, overrides: dict[str, dict]) -> tuple[dict, dict]:
    """(measurement, settings) for one species."""
    if (species.dex or 0) in NOT_WINGED:
        measured = {
            "ok": False,
            "reason": "hand-listed as wingless -- it hovers, it does not flap",
            "warnings": [],
            "profile": [],
        }
    elif species.mesh is None or not species.mesh.is_file():
        measured = {"ok": False, "reason": "no model.obj on disk", "warnings": [], "profile": []}
    else:
        measured = measure(read_vertices(species.mesh))
    return measured, settings_for(species.dex or 0, measured, overrides.get(species.slug, {}))


def describe(species: Species, measured: dict, settings: dict) -> str:
    if not measured["ok"]:
        return C.red(f"  {species.slug:<32} no wings -- {measured['reason']}")
    line = (
        f"  {species.slug:<32} hinge {settings['wing_hinge']:.2f}"
        f"  root {settings['wing_root_height']:.2f}"
        f"  flap {settings['flap_degrees']:.0f}deg"
        f"  twist {settings['flap_twist_degrees']:.0f}deg"
        f"  curve {settings['wing_curve']:.1f}"
    )
    for warning in measured["warnings"]:
        line += "\n" + C.yellow(f"      {warning}")
    return line


def command_plan(root: Path, only: str | None, all_species: bool) -> int:
    overrides = load_overrides(root)
    species_list = collect(root, only, all_species)
    if not species_list:
        print("Nothing to measure.")
        return 0

    print(C.bold(f"Measuring {len(species_list)} species\n"))
    found = 0
    missed: list[str] = []
    flagged = 0

    for species in species_list:
        measured, settings = evaluate(species, overrides)
        print(describe(species, measured, settings))
        if measured["ok"]:
            found += 1
            flagged += 1 if measured["warnings"] else 0
        else:
            missed.append(species.slug)

    print()
    print(C.green(f"{found} with wings"), C.dim("|"), f"{flagged} flagged for a look", end="")
    if missed:
        print(C.dim(" |"), C.red(f"{len(missed)} without"))
        print(C.dim("  " + ", ".join(missed)))
    else:
        print()
    if overrides:
        print(C.dim(f"\n{len(overrides)} hand-tuned species from {OVERRIDES_FILE} take priority."))
    return 0


def command_apply(root: Path, only: str | None, all_species: bool, execute: bool) -> int:
    overrides = load_overrides(root)
    species_list = collect(root, only, all_species)
    if not species_list:
        print("Nothing to write.")
        return 0

    print(C.bold(f"{'Writing' if execute else 'Would write'} {len(species_list)} species\n"))
    changed = 0
    for species in species_list:
        measured, settings = evaluate(species, overrides)
        lines, is_changed = rewrite(species.path, settings)
        if not is_changed:
            continue
        changed += 1
        print(describe(species, measured, settings))
        if execute:
            species.path.write_text("".join(lines), encoding="utf-8")

    print()
    if execute:
        print(C.green(f"Wrote {changed} file(s)."))
    else:
        print(C.yellow(f"{changed} file(s) would change. Re-run with --execute to write them."))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument("command", choices=["plan", "apply"])
    parser.add_argument("--execute", action="store_true", help="actually write the .tres files")
    parser.add_argument("--only", help="restrict to filenames containing this")
    parser.add_argument(
        "--all-species",
        action="store_true",
        help="measure every species, not just the ones marked FLYER",
    )
    args = parser.parse_args()

    root = find_project_root(Path(__file__).resolve().parent)
    if args.command == "plan":
        return command_plan(root, args.only, args.all_species)
    return command_apply(root, args.only, args.all_species, args.execute)


if __name__ == "__main__":
    raise SystemExit(main())

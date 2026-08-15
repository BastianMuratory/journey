#!/usr/bin/env python3
"""
import_pokemons.py -- turn the raw rips in Pokemons_not_ready/ into game-ready
creature folders under assets/pokemons/.

WHAT IT DOES
------------
Every source folder becomes one canonical folder that matches the layout the
project already uses (see assets/pokemons/0001_bulbasaur):

    assets/pokemons/0025_pikachu/
        model.obj          mtllib -> model.mtl
        model.mtl          map_Kd -> albedo.png
        albedo.png
        model_shiny.obj    mtllib -> model_shiny.mtl      (when a shiny exists)
        model_shiny.mtl    map_Kd -> albedo_shiny.png
        albedo_shiny.png

Along the way it:

  * Reads the dex number and species out of the source folder name, whatever
    shape it takes -- "0025_#0025 Pikachu", "#0194 Wooper (Paldean Form)" and
    "Mobile - Pokemon Quest - ... - #0656 Froakie" all parse.
  * Names alternate forms "<dex>_<species>_<form>", e.g. 0025_pikachu_ash_cap,
    so forms sort next to their base form instead of under a serial number.
  * Picks the main mesh when a folder holds several, and reports the extras
    rather than guessing (accessory props like pq0324gc, pq0324pc).
  * Prefers a "_fixed" mesh over the original when the ripper left both --
    Frogadier ships that way, with a ReadMe saying to use the fixed one.
  * Rebuilds every cross-reference from the files actually present. The rips
    disagree with each other about naming, so the old text is not trustworthy.
  * Normalises the material the same way tools/fix_pokemon_materials.gd does
    (Ns 1000, Ks 0 0 0, illum 1). Rips that declare Ks 1 1 1 import as
    metallic = 1.0 and render as black silhouettes.
  * Synthesises model_shiny.obj/.mtl when a rip ships a shiny *texture* but no
    shiny mesh -- the "pq" family does this. Same geometry, shiny albedo.
  * Splits shared .mtl files, keeping only the material blocks the .obj asks
    for by name. Some rips put base and shiny in one file.

Source files are COPIED, never moved: Pokemons_not_ready/ is left untouched so
you can re-run or roll back. .ply files and .import sidecars are not copied --
Godot cannot read .ply, and it mints fresh .import files (with fresh UIDs) on
next open, which is what you want for assets that have never been in the
project.

USAGE
-----
    python tools/import_pokemons.py plan
        Read-only. Prints a report and writes tools/import_plan.json.

    # ... edit tools/import_plan.json if you disagree with any target name ...

    python tools/import_pokemons.py apply
        Dry run. Prints exactly what would be written.

    python tools/import_pokemons.py apply --execute
        Actually writes the folders.

    python tools/import_pokemons.py verify
        Checks every folder under assets/pokemons: canonical filenames present,
        mtllib/map_Kd/usemtl all resolve, material values normalised.

Flags:
    --execute       Perform the changes (otherwise everything is a dry run).
    --overwrite     Replace target folders that already exist (skipped by
                    default, so the seven hand-built ones stay as they are).
    --only PATTERN  Restrict to targets whose folder name contains PATTERN.
                    Handy for trying one species first: --only pikachu

AFTERWARDS
----------
Reopen the project in Godot and let it import. Then run
tools/tidy_assets.py plan to confirm the new folders pass the existing audit.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

SOURCE_ROOT = "Pokemons_not_ready"
TARGET_ROOT = "assets/pokemons"
PLAN_FILE = "tools/import_plan.json"

# Canonical output names.
OUT_BASE = {"obj": "model.obj", "mtl": "model.mtl", "png": "albedo.png"}
OUT_SHINY = {
    "obj": "model_shiny.obj",
    "mtl": "model_shiny.mtl",
    "png": "albedo_shiny.png",
}

# Extensions we care about. Everything else is reported and left behind.
MESH_EXT = ".obj"
MATERIAL_EXT = ".mtl"
TEXTURE_EXT = ".png"
IGNORED_EXT = {".ply", ".import", ".txt", ".blend", ".uid"}

# Material lines forced to these values, keyed by their prefix. Mirrors
# tools/fix_pokemon_materials.gd -- see that file for why.
MATERIAL_FIXES = {
    "Ns ": "Ns 1000.000000",
    "Ks ": "Ks 0.000000 0.000000 0.000000",
    "illum ": "illum 1",
}

PROVENANCE = "# imported by tools/import_pokemons.py from {source}"

TEXT_ENCODING = "utf-8"
# surrogateescape round-trips stray non-UTF-8 bytes untouched rather than
# corrupting them, which matters for tool-exported .obj/.mtl files.
TEXT_ERRORS = "surrogateescape"

# --------------------------------------------------------------------------
# Line patterns
# --------------------------------------------------------------------------

# "#0025 Pikachu (Ash Cap)" -- the dex number is the only reliable anchor,
# since folder prefixes are a serial number that drifts from the dex.
FOLDER_NAME = re.compile(r"#(?P<dex>\d{3,4})\s*(?P<rest>.*)$")
# Fallback for folders with no "#": "0025_Pikachu", "0025 - Pikachu".
FOLDER_FALLBACK = re.compile(r"^(?P<dex>\d{3,4})[_\-\s]+(?P<rest>.+)$")
# Trailing " (2)" that a second download leaves behind.
DUPLICATE_MARKER = re.compile(r"\s*\((\d+)\)\s*$")
# "Pikachu (Ash Cap)" -> species, form
FORM_SUFFIX = re.compile(r"^(?P<species>.+?)\s*\((?P<form>[^)]+)\)\s*$")

MTLLIB_LINE = re.compile(r"^\s*mtllib\s+(?P<value>.+?)\s*$", re.IGNORECASE)
USEMTL_LINE = re.compile(r"^\s*usemtl\s+(?P<value>.+?)\s*$", re.IGNORECASE)
OBJECT_LINE = re.compile(r"^\s*o\s+(?P<value>.+?)\s*$")
NEWMTL_LINE = re.compile(r"^\s*newmtl\s+(?P<value>.+?)\s*$", re.IGNORECASE)
MAP_LINE = re.compile(
    r"^(?P<keyword>\s*(?:map_Kd|map_Ka|map_Ks|map_Ns|map_d|map_bump|bump|norm|refl)\s+)"
    r"(?P<value>.+?)\s*$",
    re.IGNORECASE,
)

# A shiny counterpart is the base stem plus one of these. Order matters: the
# bare "S" is checked case-sensitively so it cannot swallow the lowercase form
# letters the pq rips use (pq0194s is a form, pq0194S is the shiny texture).
SHINY_SUFFIXES = ("S", " - Shiny", "_shiny", "_s", "-shiny", " shiny")

# Modifier suffixes on a mesh stem that do not change which texture it wants.
# "pq0657_fixed.obj" is still painted by "pq0657.png".
MESH_MODIFIERS = ("_fixed", "_repaired", "_clean")

# Characters that carry meaning but do not survive slugification.
CHARACTER_MAP = {"♀": " f", "♂": " m", "&": " and "}

# Punctuation deleted outright rather than becoming a separator, so
# "Farfetch'd" reads as "farfetchd" and not "farfetch_d".
DROPPED_CHARACTERS = "'’.·"

# Words dropped from the tail of a form label: "Paldean Form" -> "paldean",
# "Sky Forme" -> "sky". Keeps folder names short without losing meaning.
FORM_NOISE = {"form", "forme"}


def line_ending(line: str) -> str:
    """The newline a line ends with, so rewrites can preserve it exactly."""
    if line.endswith("\r\n"):
        return "\r\n"
    if line.endswith("\n"):
        return "\n"
    return ""


def read_lines(path: Path) -> list[str]:
    with path.open("r", encoding=TEXT_ENCODING, errors=TEXT_ERRORS, newline="") as fh:
        return fh.readlines()


def write_lines(path: Path, lines: list[str]) -> None:
    with path.open("w", encoding=TEXT_ENCODING, errors=TEXT_ERRORS, newline="") as fh:
        fh.writelines(lines)


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


# --------------------------------------------------------------------------
# Naming
# --------------------------------------------------------------------------


def slugify(text: str) -> str:
    """'Mr. Mime' -> 'mr_mime', 'Nidoran<female>' -> 'nidoran_f'."""
    for character, replacement in CHARACTER_MAP.items():
        text = text.replace(character, replacement)
    for character in DROPPED_CHARACTERS:
        text = text.replace(character, "")
    # NFKD splits accented letters into letter + combining mark; dropping the
    # marks turns "Flabebe" back into ASCII without mangling the letters.
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").lower()
    return re.sub(r"_+", "_", text)


def parse_folder_name(name: str) -> tuple[str, str, str, list[str]]:
    """
    Pull (dex, species, form, notes) out of a source folder name.

    Returns a 4-digit dex string, a slugified species, a slugified form (empty
    for base forms) and any notes worth surfacing in the report.
    """
    notes: list[str] = []

    duplicate = DUPLICATE_MARKER.search(name)
    if duplicate:
        notes.append(f"folder is copy #{duplicate.group(1)} of an earlier download")
        name = DUPLICATE_MARKER.sub("", name)

    match = FOLDER_NAME.search(name) or FOLDER_FALLBACK.match(name)
    if not match:
        return "", slugify(name), "", ["cannot find a dex number in the folder name"]

    dex = match.group("dex").zfill(4)
    rest = match.group("rest").strip(" -_")

    form = ""
    form_match = FORM_SUFFIX.match(rest)
    if form_match:
        rest = form_match.group("species")
        words = [w for w in form_match.group("form").split() if w.lower() not in FORM_NOISE]
        form = slugify(" ".join(words) or form_match.group("form"))

    return dex, slugify(rest), form, notes


def target_folder_name(dex: str, species: str, form: str) -> str:
    return f"{dex}_{species}_{form}" if form else f"{dex}_{species}"


# --------------------------------------------------------------------------
# Working out what is in a source folder
# --------------------------------------------------------------------------


def strip_modifier(stem: str) -> str:
    """'pq0657_fixed' -> 'pq0657'."""
    for modifier in MESH_MODIFIERS:
        if stem.lower().endswith(modifier):
            return stem[: -len(modifier)]
    return stem


def shiny_of(stem: str, candidates: dict[str, Path]) -> Path | None:
    """The shiny counterpart of `stem` among `candidates`, if one exists."""
    for suffix in SHINY_SUFFIXES:
        # The bare "S" marker is case-sensitive; the word forms are not.
        if suffix == "S":
            hit = candidates.get(stem + suffix)
            if hit is not None:
                return hit
            continue
        for name, path in candidates.items():
            if name.lower() == (stem + suffix).lower():
                return path
    return None


def lowercase_shiny(stem: str, meshes: dict[str, Path], textures: dict[str, Path]) -> Path | None:
    """
    Last-resort shiny lookup for '<stem>s.png'.

    A trailing lowercase 's' is ambiguous in the pq rips: it usually marks a
    form (pq0194s is a whole separate creature, with its own pq0194sS shiny),
    but Zekrom's ripper used it for the shiny itself. Only accept it when the
    ambiguity cannot arise -- no mesh of that name, and no shiny of its own.
    """
    candidate = textures.get(stem + "s")
    if candidate is None:
        return None
    if (stem + "s") in meshes or (stem + "sS") in textures:
        return None
    return candidate


def is_shiny_of_any(stem: str, stems: set[str]) -> bool:
    """True if `stem` is some other stem's shiny counterpart."""
    for suffix in SHINY_SUFFIXES:
        if suffix == "S":
            if stem.endswith("S") and stem[:-1] in stems:
                return True
            continue
        if stem.lower().endswith(suffix.lower()):
            base = stem[: -len(suffix)]
            if any(other.lower() == base.lower() for other in stems):
                return True
    return False


def choose_primary(stems: list[str], dex: str) -> str:
    """
    Pick the main mesh when a folder holds several.

    Preference order: an author-fixed mesh, then the plain "pq<dex>" rip, then
    the shortest stem -- accessory variants are always the base stem plus a
    couple of letters (pq0324 vs pq0324gc).
    """
    fixed = [s for s in stems if strip_modifier(s) != s and strip_modifier(s) in stems]
    if fixed:
        return sorted(fixed)[0]

    exact = [s for s in stems if re.fullmatch(rf"pq0*{int(dex)}", s, re.IGNORECASE)]
    if exact:
        return exact[0]

    return sorted(stems, key=lambda s: (len(s), s))[0]


@dataclass
class Creature:
    """One source folder's worth of proposed output."""

    source: str
    target: str
    dex: str
    species: str
    form: str
    files: dict[str, str] = field(default_factory=dict)  # output name -> source name
    synth_shiny: bool = False
    skipped: list[str] = field(default_factory=list)
    issues: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return OUT_BASE["obj"] in self.files and OUT_BASE["png"] in self.files

    def to_json(self) -> dict:
        return {
            "source": self.source,
            "target": self.target,
            "dex": self.dex,
            "species": self.species,
            "form": self.form,
            "files": self.files,
            "synth_shiny": self.synth_shiny,
            "skipped": self.skipped,
            "issues": self.issues,
        }


def scan_source_folder(folder: Path, root: Path) -> Creature:
    dex, species, form, notes = parse_folder_name(folder.name)
    creature = Creature(
        source=folder.relative_to(root).as_posix(),
        target=f"{TARGET_ROOT}/{target_folder_name(dex, species, form)}",
        dex=dex,
        species=species,
        form=form,
        issues=list(notes),
    )
    if not dex:
        return creature

    # Bucket by extension, keyed on stem so counterparts can be matched by name.
    meshes: dict[str, Path] = {}
    materials: dict[str, Path] = {}
    textures: dict[str, Path] = {}
    for entry in sorted(folder.iterdir()):
        if not entry.is_file():
            continue
        extension = entry.suffix.lower()
        if extension in IGNORED_EXT:
            continue
        if extension == MESH_EXT:
            meshes[entry.stem] = entry
        elif extension == MATERIAL_EXT:
            materials[entry.stem] = entry
        elif extension == TEXTURE_EXT:
            textures[entry.stem] = entry
        else:
            creature.issues.append(f"unrecognised file ignored: {entry.name}")

    if not meshes:
        creature.issues.append("no .obj found")
        return creature

    # Meshes that are somebody else's shiny are not candidates in their own right.
    stems = set(meshes)
    candidates = [s for s in meshes if not is_shiny_of_any(s, stems)]
    primary = choose_primary(candidates or list(meshes), dex)

    creature.files[OUT_BASE["obj"]] = meshes[primary].name

    # Anything left over is an accessory or an alternate the rip bundled in.
    for stem, path in sorted(meshes.items()):
        if stem == primary or shiny_of(primary, meshes) is path:
            continue
        if strip_modifier(stem) == strip_modifier(primary) and stem != primary:
            creature.skipped.append(f"{path.name} (superseded by {meshes[primary].name})")
        else:
            creature.skipped.append(f"{path.name} (extra mesh)")

    base_material = materials.get(primary) or materials.get(strip_modifier(primary))
    if base_material:
        creature.files[OUT_BASE["mtl"]] = base_material.name
    else:
        creature.issues.append(f"{meshes[primary].name} has no .mtl -- will import untextured")

    # Texture, in descending order of confidence.
    texture_stem = primary
    base_texture = textures.get(primary)
    if base_texture is None:
        texture_stem = strip_modifier(primary)
        base_texture = textures.get(texture_stem)
    if base_texture is None and base_material:
        named = material_texture(base_material)
        if named and (folder / named).is_file():
            texture_stem = Path(named).stem
            base_texture = folder / named
    if base_texture is None:
        loose = [p for s, p in sorted(textures.items()) if not is_shiny_of_any(s, set(textures))]
        if len(loose) == 1:
            texture_stem = loose[0].stem
            base_texture = loose[0]

    if base_texture is None:
        creature.issues.append("no base texture (.png) found")
    else:
        creature.files[OUT_BASE["png"]] = base_texture.name

    # Shiny. A shiny mesh is ideal; a shiny texture alone means we clone the
    # base geometry so the game can swap the whole model in one line.
    shiny_mesh = shiny_of(primary, meshes)
    shiny_texture = shiny_of(texture_stem, textures)
    if shiny_texture is None:
        shiny_texture = lowercase_shiny(texture_stem, meshes, textures)
        if shiny_texture is not None:
            creature.issues.append(
                f"{shiny_texture.name} read as the shiny texture (lowercase marker)"
            )

    if shiny_mesh is not None:
        creature.files[OUT_SHINY["obj"]] = shiny_mesh.name
        shiny_material = materials.get(shiny_mesh.stem) or base_material
        if shiny_material:
            creature.files[OUT_SHINY["mtl"]] = shiny_material.name
        if shiny_texture is None:
            shiny_texture = shiny_of(shiny_mesh.stem, textures)
    elif shiny_texture is not None:
        creature.synth_shiny = True
        creature.files[OUT_SHINY["obj"]] = meshes[primary].name
        if base_material:
            creature.files[OUT_SHINY["mtl"]] = base_material.name

    if shiny_texture is not None:
        creature.files[OUT_SHINY["png"]] = shiny_texture.name
    elif shiny_mesh is not None:
        creature.issues.append("shiny mesh present but no shiny texture")
    else:
        creature.issues.append("no shiny variant in this rip")

    for stem, path in sorted(textures.items()):
        if path.name not in creature.files.values():
            creature.skipped.append(f"{path.name} (extra texture)")

    return creature


def material_texture(mtl_path: Path) -> str | None:
    """The first map_Kd filename declared in a .mtl."""
    for line in read_lines(mtl_path):
        match = MAP_LINE.match(line)
        if match and match.group("keyword").strip().lower() == "map_kd":
            _, filename = split_map_arguments(match.group("value"))
            if filename:
                return filename
    return None


def split_map_arguments(rest: str) -> tuple[str, str]:
    """
    Split an MTL map_* argument into (options, filename).

    MTL allows options before the filename, e.g. `map_Kd -o 1 1 1 tex.png`.
    """
    tokens = rest.split()
    index = 0
    while index < len(tokens) and tokens[index].startswith("-"):
        index += 1
        while index < len(tokens) and _is_number(tokens[index]):
            index += 1
    return " ".join(tokens[:index]), " ".join(tokens[index:])


def _is_number(token: str) -> bool:
    try:
        float(token)
    except ValueError:
        return False
    return True


# --------------------------------------------------------------------------
# Writing
# --------------------------------------------------------------------------


def obj_materials(lines: list[str]) -> list[str]:
    """Material names an .obj asks for, in order of first appearance."""
    names: list[str] = []
    for line in lines:
        match = USEMTL_LINE.match(line)
        if match and match.group("value") not in names:
            names.append(match.group("value"))
    return names


def transform_obj(
    source: Path, mtl_name: str, object_name: str, shiny: bool
) -> tuple[list[str], list[str]]:
    """
    Rewrite an .obj for its new home.

    Repoints mtllib at the canonical .mtl and renames the object so the mesh
    shows up in Godot as something readable. When `shiny` is set the material
    names get a " - Shiny" suffix, because a synthesised shiny shares its
    source .obj with the base model and the two must not collide.

    Returns (lines, material_names_used).
    """
    lines = read_lines(source)
    object_lines = [i for i, line in enumerate(lines) if OBJECT_LINE.match(line)]
    used: list[str] = []
    seen_mtllib = False

    for index, line in enumerate(lines):
        ending = line_ending(line)

        if MTLLIB_LINE.match(line):
            lines[index] = f"mtllib {mtl_name}{ending}"
            seen_mtllib = True
            continue

        # Only rename when there is exactly one object; a multi-object mesh
        # would lose the distinction between its parts.
        if index in object_lines and len(object_lines) == 1:
            lines[index] = f"o {object_name}{ending}"
            continue

        match = USEMTL_LINE.match(line)
        if match:
            name = match.group("value")
            if shiny:
                name = f"{name} - Shiny"
            if name not in used:
                used.append(name)
            lines[index] = f"usemtl {name}{ending}"

    if not seen_mtllib:
        lines.insert(0, f"mtllib {mtl_name}\n")

    return lines, used


def transform_mtl(
    source: Path, texture_name: str, keep: list[str], shiny: bool
) -> list[str]:
    """
    Rewrite a .mtl for its new home.

    Keeps only the material blocks named in `keep` (rips sometimes ship base
    and shiny in one file), repoints every texture map at `texture_name`, and
    forces the specular values that make Godot's OBJ importer behave.
    """
    lines = read_lines(source)
    output: list[str] = []
    current: str | None = None
    keeping = True
    kept_any = False

    for line in lines:
        ending = line_ending(line)
        match = NEWMTL_LINE.match(line)
        if match:
            current = match.group("value")
            name = f"{current} - Shiny" if shiny else current
            keeping = not keep or name in keep
            if keeping:
                kept_any = True
                output.append(f"newmtl {name}{ending}")
            continue

        if not keeping:
            continue

        # Preserve the file's header comments, which sit before any newmtl.
        if current is None and not line.strip():
            output.append(line)
            continue

        stripped = line.lstrip()
        replaced = False
        for prefix, wanted in MATERIAL_FIXES.items():
            if stripped.startswith(prefix):
                output.append(f"{wanted}{ending}")
                replaced = True
                break
        if replaced:
            continue

        map_match = MAP_LINE.match(line)
        if map_match:
            keyword = map_match.group("keyword").strip()
            options, _ = split_map_arguments(map_match.group("value"))
            prefix = f"{keyword} {options} " if options else f"{keyword} "
            output.append(f"{prefix}{texture_name}{ending}")
            continue

        output.append(line)

    if not kept_any:
        # The .obj named materials this file does not define. Better to ship
        # everything than to ship an empty material.
        return transform_mtl(source, texture_name, [], shiny)

    return output


class Runner:
    """Executes (or merely narrates) the writes."""

    def __init__(self, root: Path, execute: bool) -> None:
        self.root = root
        self.execute = execute
        self.folders = 0
        self.written = 0
        self.skipped = 0

    def rel(self, path: Path) -> str:
        return path.relative_to(self.root).as_posix()

    def copy(self, source: Path, destination: Path) -> None:
        print(f"  copy   {destination.name}  <- {source.name}")
        self.written += 1
        if self.execute:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

    def write(self, destination: Path, lines: list[str], note: str) -> None:
        print(f"  write  {destination.name}  ({note})")
        self.written += 1
        if self.execute:
            destination.parent.mkdir(parents=True, exist_ok=True)
            write_lines(destination, lines)


def build_creature(creature: Creature, root: Path, runner: Runner, overwrite: bool) -> None:
    source_folder = root / creature.source
    target_folder = root / creature.target

    if target_folder.exists() and not overwrite:
        print(C.dim(f"  skip   {creature.target} already exists (use --overwrite)"))
        runner.skipped += 1
        return

    runner.folders += 1
    slug = target_folder.name

    for shiny, names in ((False, OUT_BASE), (True, OUT_SHINY)):
        obj_name = creature.files.get(names["obj"])
        if not obj_name:
            continue

        mtl_name = creature.files.get(names["mtl"])
        png_name = creature.files.get(names["png"])

        object_name = f"{slug}_shiny" if shiny else slug
        # A synthesised shiny reuses the base .obj, so its materials must be
        # renamed to stay distinct. A real shiny .obj already has its own.
        rename_materials = shiny and creature.synth_shiny

        lines, used = transform_obj(
            source_folder / obj_name, names["mtl"], object_name, rename_materials
        )
        runner.write(
            target_folder / names["obj"],
            [PROVENANCE.format(source=obj_name) + "\n", *lines],
            f"mtllib -> {names['mtl']}",
        )

        if mtl_name and png_name:
            material_lines = transform_mtl(
                source_folder / mtl_name, names["png"], used, rename_materials
            )
            runner.write(
                target_folder / names["mtl"],
                [PROVENANCE.format(source=mtl_name) + "\n", *material_lines],
                f"map_Kd -> {names['png']}",
            )

        if png_name:
            runner.copy(source_folder / png_name, target_folder / names["png"])


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------


def find_project_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "project.godot").is_file():
            return candidate
    sys.exit("error: could not locate project.godot -- run this from inside the project")


def scan_all(root: Path) -> list[Creature]:
    source_root = root / SOURCE_ROOT
    if not source_root.is_dir():
        sys.exit(f"error: {SOURCE_ROOT} not found under {root}")

    creatures = [
        scan_source_folder(folder, root)
        for folder in sorted(source_root.iterdir())
        if folder.is_dir()
    ]
    return resolve_collisions(creatures)


def resolve_collisions(creatures: list[Creature]) -> list[Creature]:
    """
    Two source folders wanting the same target folder is a real case -- the
    same rip downloaded twice. Keep the healthier one and say so.
    """
    by_target: dict[str, list[Creature]] = {}
    for creature in creatures:
        by_target.setdefault(creature.target, []).append(creature)

    for target, group in by_target.items():
        if len(group) < 2:
            continue
        # Prefer the entry with the most complete file set, then the shortest
        # source name -- "... Clodsire (1)" loses to "... Clodsire".
        winner = sorted(group, key=lambda c: (-len(c.files), len(c.source)))[0]
        for creature in group:
            if creature is winner:
                creature.issues.append(
                    f"{len(group)} source folders map here; kept this one"
                )
                continue
            creature.issues.append(f"COLLISION: '{target}' already claimed by {winner.source}")
            creature.files.clear()

    return creatures


def command_plan(root: Path, only: str | None) -> int:
    creatures = [c for c in scan_all(root) if matches(c, only)]

    print(C.bold(f"\nScanned {len(creatures)} source folders under {SOURCE_ROOT}\n"))

    ready = [c for c in creatures if c.ok]
    blocked = [c for c in creatures if not c.ok]
    shiny = [c for c in ready if OUT_SHINY["png"] in c.files]
    synthesised = [c for c in ready if c.synth_shiny]
    forms = [c for c in ready if c.form]
    existing = [c for c in ready if (root / c.target).exists()]

    for creature in creatures:
        interesting = creature.issues or creature.skipped or not creature.ok
        if not interesting:
            continue
        print(C.bold(f"{creature.target}"))
        print(C.dim(f"  from {creature.source}"))
        for name in creature.skipped:
            print(f"  {C.yellow('skip')}   {name}")
        for issue in creature.issues:
            colour = C.red if not creature.ok else C.yellow
            print(f"  {colour('note')}   {issue}")
        print()

    print(C.bold("Summary"))
    print(f"  {C.green(str(len(ready)))} folders ready to build")
    print(f"  {len(shiny)} with a shiny texture ({len(synthesised)} shiny meshes synthesised)")
    print(f"  {len(forms)} alternate forms")
    if existing:
        print(f"  {C.yellow(str(len(existing)))} targets already exist and will be skipped")
    if blocked:
        print(f"  {C.red(str(len(blocked)))} folders cannot be built -- see notes above")

    plan_path = root / PLAN_FILE
    plan_path.parent.mkdir(parents=True, exist_ok=True)
    plan_path.write_text(
        json.dumps(
            {
                "_comment": (
                    "Edit 'target' to rename a folder, or 'files' to choose a "
                    "different source file for a slot. Delete an entry to skip "
                    "it. 'skipped' and 'issues' are advisory and ignored by apply."
                ),
                "source_root": SOURCE_ROOT,
                "target_root": TARGET_ROOT,
                "creatures": [c.to_json() for c in creatures],
            },
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    print(C.bold(f"\nPlan written to {PLAN_FILE}"))
    print("Review it, then run:  python tools/import_pokemons.py apply")
    return 0


def matches(creature: Creature, only: str | None) -> bool:
    if not only:
        return True
    needle = only.lower()
    return needle in creature.target.lower() or needle in creature.source.lower()


def load_plan(root: Path) -> list[Creature]:
    plan_path = root / PLAN_FILE
    if not plan_path.is_file():
        sys.exit(f"error: {PLAN_FILE} not found -- run 'plan' first")

    data = json.loads(plan_path.read_text(encoding="utf-8"))
    return [
        Creature(
            source=entry["source"],
            target=entry["target"],
            dex=entry.get("dex", ""),
            species=entry.get("species", ""),
            form=entry.get("form", ""),
            files=entry.get("files", {}),
            synth_shiny=entry.get("synth_shiny", False),
            skipped=entry.get("skipped", []),
            issues=entry.get("issues", []),
        )
        for entry in data.get("creatures", [])
    ]


def command_apply(root: Path, execute: bool, overwrite: bool, only: str | None) -> int:
    creatures = [c for c in load_plan(root) if c.ok and matches(c, only)]
    runner = Runner(root, execute)

    if not execute:
        print(C.yellow(C.bold("\nDRY RUN -- nothing will be written.")))
        print(C.dim("Re-run with --execute to apply.\n"))

    for creature in creatures:
        print(C.bold(f"\n{creature.target}"))
        build_creature(creature, root, runner, overwrite)

    print(
        C.bold(
            f"\n{runner.folders} folders, {runner.written} files, "
            f"{runner.skipped} skipped as already present"
        )
    )
    if execute:
        print(C.green("\nDone. Reopen the project in Godot to let it import."))
        print(C.dim("Then: python tools/import_pokemons.py verify"))
    else:
        print(C.yellow("\nDry run only. Re-run with --execute to apply."))
    return 0


def command_verify(root: Path, only: str | None) -> int:
    """Read-only health check over everything now sitting in assets/pokemons."""
    target_root = root / TARGET_ROOT
    folders = sorted(f for f in target_root.iterdir() if f.is_dir())
    if only:
        folders = [f for f in folders if only.lower() in f.name.lower()]

    problems: list[str] = []
    clean = 0

    for folder in folders:
        found: list[str] = []
        for shiny, names in ((False, OUT_BASE), (True, OUT_SHINY)):
            obj = folder / names["obj"]
            if not obj.is_file():
                if not shiny:
                    problems.append(f"{folder.name}: missing {names['obj']}")
                continue

            lines = read_lines(obj)
            declared = [
                m.group("value")
                for m in (MTLLIB_LINE.match(line) for line in lines)
                if m
            ]
            for name in declared:
                if not (folder / name).is_file():
                    problems.append(f"{folder.name}/{obj.name}: mtllib '{name}' missing")

            mtl = folder / names["mtl"]
            if not mtl.is_file():
                problems.append(f"{folder.name}: {obj.name} has no {names['mtl']}")
                continue

            material_lines = read_lines(mtl)
            defined = {
                m.group("value")
                for m in (NEWMTL_LINE.match(line) for line in material_lines)
                if m
            }
            for name in obj_materials(lines):
                if name not in defined:
                    problems.append(
                        f"{folder.name}/{mtl.name}: no material '{name}' for {obj.name}"
                    )

            for line in material_lines:
                match = MAP_LINE.match(line)
                if not match:
                    continue
                _, filename = split_map_arguments(match.group("value"))
                if filename and not (folder / filename).is_file():
                    problems.append(f"{folder.name}/{mtl.name}: texture '{filename}' missing")

            for prefix, wanted in MATERIAL_FIXES.items():
                offenders = [
                    line.strip()
                    for line in material_lines
                    if line.lstrip().startswith(prefix) and line.strip() != wanted
                ]
                if offenders:
                    problems.append(
                        f"{folder.name}/{mtl.name}: {offenders[0]} should be '{wanted}'"
                    )

            found.append("shiny" if shiny else "base")

        if "base" in found:
            clean += 1

    print(C.bold(f"\nChecked {len(folders)} folders under {TARGET_ROOT}"))
    if problems:
        print(C.red(f"\n{len(problems)} problem(s):"))
        for problem in problems:
            print(f"  {problem}")
        return 1
    print(C.green(f"All good -- {clean} folders with a usable base model."))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import raw Pokemon rips into Journey's asset layout.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--only", help="restrict to targets matching this substring")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("plan", help="scan and write an editable plan (read-only)")

    apply_parser = subparsers.add_parser("apply", help="build the asset folders")
    apply_parser.add_argument("--execute", action="store_true", help="actually write files")
    apply_parser.add_argument(
        "--overwrite", action="store_true", help="replace target folders that already exist"
    )

    subparsers.add_parser("verify", help="health-check assets/pokemons (read-only)")

    args = parser.parse_args()
    root = find_project_root(Path(__file__).resolve().parent)

    if args.command == "plan":
        return command_plan(root, args.only)
    if args.command == "verify":
        return command_verify(root, args.only)
    return command_apply(root, args.execute, args.overwrite, args.only)


if __name__ == "__main__":
    sys.exit(main())

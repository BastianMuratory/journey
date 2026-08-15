#!/usr/bin/env python3
"""
tidy_assets.py -- normalise creature asset folders in the Journey Godot project.

WHAT IT DOES
------------
Each creature folder under assets/pokemons/ should end up looking like this:

    assets/pokemons/0551_sandile/
        model.obj          model.obj.import
        model.mtl
        albedo.png         albedo.png.import
        model_shiny.obj    model_shiny.obj.import   (only if a shiny mesh exists)
        model_shiny.mtl
        albedo_shiny.png   albedo_shiny.png.import

On top of renaming, it repairs the cross-references between those files:

  * .obj  files point at their .mtl via a `mtllib` line
  * .mtl  files point at their texture via `map_Kd` (and friends)
  * .import sidecars point at their source via `source_file=`
  * .tscn / .tres / .gd files point at assets via "res://..." strings

Several of those references are ALREADY broken in the project (bulbasaur.obj
asks for "bulbasaure.mtl", which does not exist). So the repair step does not
do a find-and-replace of the old text -- that would faithfully preserve the
breakage. Instead it recomputes each reference from the files actually present
in the folder, pairing base with base and shiny with shiny.

USAGE
-----
    python tools/tidy_assets.py plan
        Scans the project, prints a health report, and writes an editable
        plan to tools/asset_plan.json. Nothing on disk is modified.

    # ... open tools/asset_plan.json and adjust any names you disagree with ...

    python tools/tidy_assets.py apply
        Dry run. Prints exactly what would happen. Still modifies nothing.

    python tools/tidy_assets.py apply --execute
        Actually does it.

Useful flags:
    --execute          Perform the changes (otherwise everything is a dry run).
    --allow-dirty      Skip the "commit your work first" guard.
    --clean-imported   Delete .godot/imported/ afterwards so Godot rebuilds its
                       cache from scratch. Safe: resource UIDs live in the
                       .import files, not the cache, so scene links survive.

AFTERWARDS
----------
Reopen the project in Godot. It will re-import the renamed files. Because the
`uid=` line inside each .import sidecar is preserved, every existing scene
reference keeps resolving even before the paths update.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

# --------------------------------------------------------------------------
# Configuration -- edit these if the project layout changes.
# --------------------------------------------------------------------------

CREATURE_ROOT = "assets/pokemons"
PLAN_FILE = "tools/asset_plan.json"

# Target filename for each (variant, extension) pair.
TARGET_NAMES: dict[tuple[str, str], str] = {
    ("base", ".obj"): "model.obj",
    ("base", ".mtl"): "model.mtl",
    ("base", ".png"): "albedo.png",
    ("shiny", ".obj"): "model_shiny.obj",
    ("shiny", ".mtl"): "model_shiny.mtl",
    ("shiny", ".png"): "albedo_shiny.png",
}

# Extensions removed outright. Godot cannot import .ply, so these are dead
# weight in the repository.
DELETE_EXTENSIONS = {".ply"}

# File types that may contain "res://" strings pointing at our assets.
REFERENCE_FILE_GLOBS = ("*.tscn", "*.tres", "*.gd", "*.import", "*.godot", "*.cfg")

# Directories never walked.
SKIP_DIRS = {".git", ".godot", ".import", "__pycache__"}

# --------------------------------------------------------------------------
# Line patterns
# --------------------------------------------------------------------------

# Matches "sandile_s", "010 - Caterpie - Shiny", "bulbasaur_s copy" but not
# "cauldron_silver" -- the marker has to be a whole token.
SHINY_TOKEN = re.compile(r"(?:^|[_\-\s])(?:s|shiny)(?:$|[_\-\s])", re.IGNORECASE)

MTLLIB_LINE = re.compile(r"^(\s*mtllib\s+)(.+?)\s*$", re.IGNORECASE)
MAP_LINE = re.compile(
    r"^(\s*(?:map_Kd|map_Ka|map_Ks|map_Ns|map_d|map_bump|bump|norm|refl)\s+)(.+?)\s*$",
    re.IGNORECASE,
)
SOURCE_FILE_LINE = re.compile(r'^(\s*source_file\s*=\s*")([^"]*)(".*)$')


def line_ending(line: str) -> str:
    """The newline a line ends with, so rewrites can preserve it exactly."""
    if line.endswith("\r\n"):
        return "\r\n"
    if line.endswith("\n"):
        return "\n"
    return ""

# Folder names look like "0551_sandile".
FOLDER_NAME = re.compile(r"^(?P<dex>\d{3,4})[_\-](?P<slug>.+)$")

TEXT_ENCODING = "utf-8"
# surrogateescape round-trips any stray non-UTF-8 bytes untouched rather than
# corrupting them, which matters for tool-exported .obj/.mtl files.
TEXT_ERRORS = "surrogateescape"


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------


def is_shiny(stem: str) -> bool:
    """True if a filename stem marks the shiny variant."""
    return bool(SHINY_TOKEN.search(stem))


def looks_like_duplicate(stem: str) -> bool:
    """True for the usual accidental-duplicate markers."""
    low = stem.lower()
    return "copy" in low or re.search(r"\(\d+\)$", low) is not None


def read_lines(path: Path) -> list[str]:
    with path.open("r", encoding=TEXT_ENCODING, errors=TEXT_ERRORS, newline="") as fh:
        return fh.readlines()


def write_lines(path: Path, lines: list[str]) -> None:
    with path.open("w", encoding=TEXT_ENCODING, errors=TEXT_ERRORS, newline="") as fh:
        fh.writelines(lines)


def split_map_arguments(rest: str) -> tuple[str, str]:
    """
    Split an MTL map_* argument into (options, filename).

    MTL allows options before the filename, e.g. `map_Kd -o 1 1 1 tex.png`.
    Options start with '-' and are followed by some number of numeric values.
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


class Console:
    """Minimal ANSI colouring that degrades to plain text when piped."""

    def __init__(self) -> None:
        self.enabled = sys.stdout.isatty() and os.name != "nt"

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
# Scanning
# --------------------------------------------------------------------------


@dataclass
class FolderPlan:
    """One creature folder's worth of proposed changes."""

    folder: str
    dex: str
    slug: str
    renames: dict[str, str] = field(default_factory=dict)
    deletes: list[str] = field(default_factory=list)
    issues: list[str] = field(default_factory=list)

    def to_json(self) -> dict:
        return {
            "folder": self.folder,
            "dex": self.dex,
            "slug": self.slug,
            "renames": self.renames,
            "deletes": self.deletes,
            "issues": self.issues,
        }


def find_project_root(start: Path) -> Path:
    """Walk upward until we find project.godot."""
    for candidate in [start, *start.parents]:
        if (candidate / "project.godot").is_file():
            return candidate
    sys.exit("error: could not locate project.godot -- run this from inside the project")


def scan_folder(folder: Path, root: Path) -> FolderPlan:
    rel = folder.relative_to(root).as_posix()
    match = FOLDER_NAME.match(folder.name)
    dex = match.group("dex") if match else ""
    slug = match.group("slug") if match else folder.name

    plan = FolderPlan(folder=rel, dex=dex, slug=slug)
    if not match:
        plan.issues.append(
            f"folder name '{folder.name}' does not match the ####_name convention"
        )

    # Bucket every asset by (variant, extension). .import sidecars are not
    # bucketed -- they travel automatically with whatever file they describe.
    buckets: dict[tuple[str, str], list[Path]] = {}
    for entry in sorted(folder.iterdir()):
        if not entry.is_file() or entry.name.endswith(".import"):
            continue

        extension = entry.suffix.lower()
        if extension in DELETE_EXTENSIONS:
            plan.deletes.append(entry.name)
            continue
        if (("base", extension) not in TARGET_NAMES) and (
            ("shiny", extension) not in TARGET_NAMES
        ):
            plan.issues.append(f"unrecognised file left untouched: {entry.name}")
            continue

        variant = "shiny" if is_shiny(entry.stem) else "base"
        buckets.setdefault((variant, extension), []).append(entry)

    # Resolve each bucket down to exactly one file.
    for key, candidates in sorted(buckets.items()):
        variant, extension = key
        chosen = candidates[0]

        if len(candidates) > 1:
            # Prefer a file that does not look like an accidental duplicate.
            clean = [c for c in candidates if not looks_like_duplicate(c.stem)]
            chosen = clean[0] if clean else candidates[0]
            for other in candidates:
                if other is chosen:
                    continue
                if looks_like_duplicate(other.stem):
                    plan.deletes.append(other.name)
                    plan.issues.append(f"duplicate removed: {other.name}")
                else:
                    plan.issues.append(
                        f"AMBIGUOUS: {other.name} and {chosen.name} are both "
                        f"{variant} {extension} -- keeping {chosen.name}, "
                        f"delete or rename the other by hand"
                    )

        target = TARGET_NAMES[key]
        if chosen.name != target:
            plan.renames[chosen.name] = target

    # Sanity checks on what the folder ends up containing.
    have = {key for key in buckets}
    if ("base", ".obj") not in have:
        plan.issues.append("no base mesh (.obj) found")
    if ("base", ".png") not in have:
        plan.issues.append("no base texture (.png) found")
    if ("base", ".mtl") not in have and ("base", ".obj") in have:
        plan.issues.append("base mesh has no .mtl -- it will import untextured")
    if ("shiny", ".png") in have and ("shiny", ".obj") not in have:
        plan.issues.append(
            "shiny texture present but no shiny mesh -- the texture is unused "
            "until you swap it on at runtime"
        )
    if ("shiny", ".obj") in have and ("shiny", ".mtl") not in have:
        plan.issues.append("shiny mesh has no .mtl")

    return plan


def scan_project(root: Path) -> list[FolderPlan]:
    creature_root = root / CREATURE_ROOT
    if not creature_root.is_dir():
        sys.exit(f"error: {CREATURE_ROOT} not found under {root}")

    plans = []
    for folder in sorted(creature_root.iterdir()):
        if folder.is_dir() and folder.name not in SKIP_DIRS:
            plans.append(scan_folder(folder, root))
    return plans


# --------------------------------------------------------------------------
# Reference auditing (read-only health check)
# --------------------------------------------------------------------------


def audit_references(root: Path) -> list[str]:
    """Report .obj -> .mtl and .mtl -> texture links that point at nothing."""
    problems = []
    creature_root = root / CREATURE_ROOT

    for obj_path in sorted(creature_root.glob("*/*.obj")):
        for line in read_lines(obj_path)[:64]:  # mtllib always sits in the header
            match = MTLLIB_LINE.match(line)
            if not match:
                continue
            referenced = match.group(2).strip()
            if not (obj_path.parent / referenced).is_file():
                problems.append(
                    f"{obj_path.relative_to(root).as_posix()} -> mtllib "
                    f"'{referenced}' does not exist"
                )

    for mtl_path in sorted(creature_root.glob("*/*.mtl")):
        for line in read_lines(mtl_path):
            match = MAP_LINE.match(line)
            if not match:
                continue
            _, filename = split_map_arguments(match.group(2))
            if filename and not (mtl_path.parent / filename).is_file():
                problems.append(
                    f"{mtl_path.relative_to(root).as_posix()} -> texture "
                    f"'{filename}' does not exist"
                )

    return problems


# --------------------------------------------------------------------------
# Applying
# --------------------------------------------------------------------------


class Runner:
    """Executes (or merely narrates) filesystem changes."""

    def __init__(self, root: Path, execute: bool) -> None:
        self.root = root
        self.execute = execute
        self.use_git = self._git_available()
        self.moves = 0
        self.deletions = 0
        self.rewrites = 0

    def _git_available(self) -> bool:
        try:
            subprocess.run(
                ["git", "rev-parse", "--is-inside-work-tree"],
                cwd=self.root,
                check=True,
                capture_output=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False
        return True

    def move(self, source: Path, destination: Path) -> None:
        rel_source = source.relative_to(self.root).as_posix()
        rel_destination = destination.relative_to(self.root).as_posix()
        print(f"  move   {rel_source}  ->  {destination.name}")
        self.moves += 1
        if not self.execute:
            return
        if destination.exists():
            sys.exit(f"error: refusing to overwrite existing {rel_destination}")
        # git mv keeps the file's history attached across the rename.
        if self.use_git and self._git_tracked(source):
            subprocess.run(
                ["git", "mv", rel_source, rel_destination], cwd=self.root, check=True
            )
        else:
            shutil.move(str(source), str(destination))

    def _git_tracked(self, path: Path) -> bool:
        result = subprocess.run(
            ["git", "ls-files", "--error-unmatch", path.relative_to(self.root).as_posix()],
            cwd=self.root,
            capture_output=True,
        )
        return result.returncode == 0

    def delete(self, path: Path) -> None:
        print(f"  {C.red('delete')} {path.relative_to(self.root).as_posix()}")
        self.deletions += 1
        if not self.execute:
            return
        if self.use_git and self._git_tracked(path):
            subprocess.run(
                ["git", "rm", "-q", "--", path.relative_to(self.root).as_posix()],
                cwd=self.root,
                check=True,
            )
        else:
            path.unlink()

    def note_rewrite(self, path: Path, detail: str) -> None:
        print(f"  {C.green('fix')}    {path.relative_to(self.root).as_posix()}: {detail}")
        self.rewrites += 1


def sidecars_for(path: Path) -> list[Path]:
    """The .import (and .uid) files that must travel with an asset."""
    found = []
    for suffix in (".import", ".uid"):
        candidate = path.with_name(path.name + suffix)
        if candidate.is_file():
            found.append(candidate)
    return found


def apply_plan(root: Path, plans: list[FolderPlan], runner: Runner) -> dict[str, str]:
    """
    Phase 1 -- delete junk and move files into place.

    Returns a map of old res:// path -> new res:// path, for phase 3.
    """
    path_map: dict[str, str] = {}

    for plan in plans:
        folder = root / plan.folder
        header_shown = False

        def header() -> None:
            nonlocal header_shown
            if not header_shown:
                print(C.bold(f"\n{plan.folder}"))
                header_shown = True

        for name in plan.deletes:
            target = folder / name
            if not target.exists():
                continue
            header()
            for sidecar in sidecars_for(target):
                runner.delete(sidecar)
            runner.delete(target)

        for old_name, new_name in plan.renames.items():
            source = folder / old_name
            if not source.exists():
                print(C.yellow(f"  skip   {plan.folder}/{old_name} (not found)"))
                continue
            header()
            destination = folder / new_name

            old_res = f"res://{plan.folder}/{old_name}"
            new_res = f"res://{plan.folder}/{new_name}"
            path_map[old_res] = new_res

            runner.move(source, destination)

            # The .import sidecar is named "<asset><ext>.import", so it has to
            # be renamed in lockstep or Godot will re-import from scratch and
            # mint a brand new UID -- which would break every scene link.
            for sidecar in sidecars_for(source):
                suffix = sidecar.name[len(source.name) :]
                runner.move(sidecar, folder / (new_name + suffix))

    return path_map


def repair_folder_links(root: Path, plans: list[FolderPlan], runner: Runner) -> None:
    """
    Phase 2 -- rebuild .obj -> .mtl and .mtl -> texture links.

    Deliberately ignores whatever the old reference said. Some are already
    broken, so the only trustworthy source of truth is the set of files now
    sitting in the folder.
    """
    for plan in plans:
        folder = root / plan.folder
        if not folder.is_dir():
            continue

        # After phase 1 these are the canonical names; fall back to whatever
        # is present so a dry run still reports something useful.
        def resolve(variant: str, extension: str) -> str | None:
            target = TARGET_NAMES[(variant, extension)]
            if (folder / target).is_file():
                return target
            for entry in sorted(folder.iterdir()):
                if entry.suffix.lower() != extension or entry.name.endswith(".import"):
                    continue
                if (variant == "shiny") == is_shiny(entry.stem):
                    return entry.name
            return None

        for variant in ("base", "shiny"):
            obj_name = resolve(variant, ".obj")
            mtl_name = resolve(variant, ".mtl")
            png_name = resolve(variant, ".png")

            if obj_name and mtl_name:
                _rewrite_first_match(
                    runner, folder / obj_name, MTLLIB_LINE, mtl_name, "mtllib"
                )
            if mtl_name and png_name:
                _rewrite_map_lines(runner, folder / mtl_name, png_name)


def _rewrite_first_match(
    runner: Runner, path: Path, pattern: re.Pattern, replacement: str, label: str
) -> None:
    if not path.is_file():
        return
    lines = read_lines(path)
    changed = False
    for index, line in enumerate(lines):
        match = pattern.match(line)
        if not match:
            continue
        current = match.group(2).strip()
        if current == replacement:
            break
        # Normalising the prefix also flattens oddities such as the literal
        # tab in krookodile.obj's "mtllib\tkrookodile.mtl".
        lines[index] = f"{label} {replacement}{line_ending(line)}"
        runner.note_rewrite(path, f"{label} '{current}' -> '{replacement}'")
        changed = True
        break
    if changed and runner.execute:
        write_lines(path, lines)


def _rewrite_map_lines(runner: Runner, path: Path, texture_name: str) -> None:
    if not path.is_file():
        return
    lines = read_lines(path)
    changed = False
    for index, line in enumerate(lines):
        match = MAP_LINE.match(line)
        if not match:
            continue
        keyword = match.group(1).strip()
        options, current = split_map_arguments(match.group(2))
        if current == texture_name:
            continue
        prefix = f"{keyword} {options} ".replace("  ", " ") if options else f"{keyword} "
        lines[index] = f"{prefix}{texture_name}{line_ending(line)}"
        runner.note_rewrite(path, f"{keyword} '{current}' -> '{texture_name}'")
        changed = True
    if changed and runner.execute:
        write_lines(path, lines)


def rewrite_project_references(
    root: Path, path_map: dict[str, str], runner: Runner
) -> None:
    """
    Phase 3 -- update every "res://" string across the project.

    Covers .tscn / .tres / .gd plus the source_file= line inside each .import
    sidecar, which Godot uses to tie an imported resource back to its origin.
    """
    if not path_map:
        return

    print(C.bold("\nproject-wide references"))

    for file_path in iter_reference_files(root):
        lines = read_lines(file_path)
        changed = False

        for index, line in enumerate(lines):
            original = line

            source_match = SOURCE_FILE_LINE.match(line)
            if source_match and source_match.group(2) in path_map:
                # `$` matches before a trailing newline, so group(3) does not
                # include it -- reattach it or the next line gets glued on.
                line = (
                    source_match.group(1)
                    + path_map[source_match.group(2)]
                    + source_match.group(3).rstrip("\r\n")
                    + line_ending(line)
                )
            else:
                for old_res, new_res in path_map.items():
                    if old_res in line:
                        line = line.replace(old_res, new_res)

            if line != original:
                lines[index] = line
                changed = True
                runner.note_rewrite(file_path, f"line {index + 1}")

        if changed and runner.execute:
            write_lines(file_path, lines)


def iter_reference_files(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for filename in filenames:
            path = Path(dirpath) / filename
            if any(path.match(pattern) for pattern in REFERENCE_FILE_GLOBS):
                yield path


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------


def command_plan(root: Path) -> int:
    plans = scan_project(root)

    print(C.bold(f"\nScanned {len(plans)} creature folders under {CREATURE_ROOT}\n"))

    for plan in plans:
        label = f"{plan.folder}"
        if not plan.renames and not plan.deletes and not plan.issues:
            print(f"{C.green('ok')}      {label}")
            continue

        print(C.bold(label))
        for old_name, new_name in plan.renames.items():
            print(f"  rename  {old_name}  ->  {new_name}")
        for name in plan.deletes:
            print(f"  {C.red('delete')}  {name}")
        for issue in plan.issues:
            print(f"  {C.yellow('note')}    {issue}")
        print()

    broken = audit_references(root)
    if broken:
        print(C.bold(C.red("\nBroken references found (these will be repaired):")))
        for problem in broken:
            print(f"  {problem}")
    else:
        print(C.green("\nNo broken references detected."))

    plan_path = root / PLAN_FILE
    plan_path.parent.mkdir(parents=True, exist_ok=True)
    plan_path.write_text(
        json.dumps(
            {
                "_comment": (
                    "Edit the 'renames' values to change target filenames. "
                    "Remove an entry to leave that file alone. Entries in "
                    "'deletes' are removed permanently. 'issues' is advisory "
                    "only and is ignored by apply."
                ),
                "creature_root": CREATURE_ROOT,
                "creatures": [p.to_json() for p in plans],
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    print(C.bold(f"\nPlan written to {PLAN_FILE}"))
    print("Review or edit it, then run:  python tools/tidy_assets.py apply")
    return 0


def load_plan(root: Path) -> list[FolderPlan]:
    plan_path = root / PLAN_FILE
    if not plan_path.is_file():
        sys.exit(f"error: {PLAN_FILE} not found -- run 'plan' first")

    data = json.loads(plan_path.read_text(encoding="utf-8"))
    plans = [
        FolderPlan(
            folder=entry["folder"],
            dex=entry.get("dex", ""),
            slug=entry.get("slug", ""),
            renames=entry.get("renames", {}),
            deletes=entry.get("deletes", []),
            issues=entry.get("issues", []),
        )
        for entry in data.get("creatures", [])
    ]

    # Guard against an edited plan that would collide two files onto one name.
    for plan in plans:
        seen: dict[str, str] = {}
        for old_name, new_name in plan.renames.items():
            if new_name in seen:
                sys.exit(
                    f"error: in {plan.folder}, both '{seen[new_name]}' and "
                    f"'{old_name}' would become '{new_name}'"
                )
            seen[new_name] = old_name

    return plans


def check_git_clean(root: Path, allow_dirty: bool) -> None:
    if allow_dirty:
        return
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=root,
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return
    if result.stdout.strip():
        print(C.red("Your git working tree has uncommitted changes."))
        print("This script moves and deletes files. Commit first so you can undo:")
        print("    git add -A && git commit -m 'wip'")
        print("Or re-run with --allow-dirty to proceed anyway.")
        sys.exit(1)


def command_apply(root: Path, execute: bool, allow_dirty: bool, clean_cache: bool) -> int:
    if execute:
        check_git_clean(root, allow_dirty)

    plans = load_plan(root)
    runner = Runner(root, execute)

    if not execute:
        print(C.yellow(C.bold("\nDRY RUN -- nothing will be modified.")))
        print(C.dim("Re-run with --execute to apply.\n"))

    path_map = apply_plan(root, plans, runner)
    repair_folder_links(root, plans, runner)
    rewrite_project_references(root, path_map, runner)

    if clean_cache and execute:
        imported = root / ".godot" / "imported"
        if imported.is_dir():
            shutil.rmtree(imported)
            print(C.bold("\nCleared .godot/imported/ -- Godot will rebuild it."))

    print(
        C.bold(
            f"\n{runner.moves} moves, {runner.deletions} deletions, "
            f"{runner.rewrites} reference fixes"
        )
    )

    if execute:
        print(C.green("\nDone. Reopen the project in Godot to let it re-import."))
        print(C.dim("Resource UIDs were preserved, so scene links still resolve."))
    else:
        print(C.yellow("\nDry run only. Re-run with --execute to apply."))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Normalise and repair Journey's creature asset folders.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("plan", help="scan and write an editable plan (read-only)")

    apply_parser = subparsers.add_parser("apply", help="carry out the plan")
    apply_parser.add_argument(
        "--execute", action="store_true", help="actually modify files"
    )
    apply_parser.add_argument(
        "--allow-dirty", action="store_true", help="skip the uncommitted-changes guard"
    )
    apply_parser.add_argument(
        "--clean-imported",
        action="store_true",
        help="delete .godot/imported/ so Godot rebuilds its cache",
    )

    args = parser.parse_args()
    root = find_project_root(Path(__file__).resolve().parent)

    if args.command == "plan":
        return command_plan(root)
    return command_apply(root, args.execute, args.allow_dirty, args.clean_imported)


if __name__ == "__main__":
    sys.exit(main())

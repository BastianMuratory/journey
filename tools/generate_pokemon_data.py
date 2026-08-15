#!/usr/bin/env python3
"""
generate_pokemon_data.py -- one PokemonData .tres per asset folder.

WHY THIS EXISTS
---------------
assets/pokemons/ has 410 ready-to-use folders, but the game can only see a
species once there is a PokemonData resource pointing at it. Writing those by
hand is 410 files of boilerplate, so this generates them.

Alternate forms get their own file: 0025_pikachu, 0025_pikachu_ash_cap and
0025_pikachu_explorer are three resources sharing one dex number. The registry
keys those by slug (the filename) as well as by dex, so they stay reachable.

WHAT IT WRITES
--------------
data/pokemon/<slug>.tres for each assets/pokemons/<slug>/, with:

    dex_number, display_name        read from the folder name
    mesh                            -> <slug>/model.obj
    albedo_shiny                    -> <slug>/albedo_shiny.png, when present
    model_scale                     1.0
    body_type + animation fields    from tools/classify_body_types.py

Existing files are LEFT ALONE by default. The handful you wrote by hand carry
evolution links this script knows nothing about, and regenerating them would
throw those away. Use --overwrite only if you mean it; --refresh-animation is
the safe middle ground that updates just the four animation fields.

Species and form names come from tools/import_plan.json when it is there, which
is how "0038_ninetales_alolan" becomes "Ninetales (Alolan)". Without it the
slug is title-cased instead, which is uglier but never wrong.

USAGE
-----
    python tools/generate_pokemon_data.py plan
        Read-only. What would be created, skipped, or refreshed.

    python tools/generate_pokemon_data.py apply
        Dry run.

    python tools/generate_pokemon_data.py apply --execute
        Write the files.

Flags:
    --execute            Actually write.
    --overwrite          Replace existing .tres files completely. Destroys any
                         evolution links you set by hand.
    --refresh-animation  For files that already exist, rewrite only the four
                         animation fields. Everything else is untouched.
    --only PATTERN       Restrict to folders whose name contains PATTERN.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import classify_body_types as classify  # noqa: E402  (needs the path above)

ASSET_DIR = "assets/pokemons"
DATA_DIR = "data/pokemon"
PLAN_FILE = "tools/import_plan.json"
SCRIPT_PATH = "res://data/pokemon_data.gd"
# Stable across the project; every existing .tres already points at it.
SCRIPT_UID = "uid://8hbuolxqt8i1"

MESH_FILE = "model.obj"
SHINY_FILE = "albedo_shiny.png"

C = classify.C

# Words that stay lowercase inside a form label, so we get "Pikachu (Ash Cap)"
# rather than "Pikachu (Ash Cap)" fighting with "Nidoran F".
GENDER_SUFFIX = {"f": "♀", "m": "♂"}


def find_project_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "project.godot").is_file():
            return candidate
    sys.exit("error: could not locate project.godot -- run this from inside the project")


def import_uid(asset: Path) -> str:
    """The uid Godot minted for an imported asset, from its .import sidecar."""
    sidecar = asset.with_suffix(asset.suffix + ".import")
    if not sidecar.is_file():
        return ""
    match = re.search(r'uid="(uid://[^"]+)"', sidecar.read_text(encoding="utf-8"))
    return match.group(1) if match else ""


def load_name_table(root: Path) -> dict[str, tuple[str, str]]:
    """slug -> (species, form), from the import plan. Empty if it isn't there."""
    path = root / PLAN_FILE
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    table: dict[str, tuple[str, str]] = {}
    for entry in data.get("creatures", []):
        target = entry.get("target", "")
        if target:
            table[Path(target).name] = (entry.get("species", ""), entry.get("form", ""))
    return table


def titleise(slug_part: str) -> str:
    """'ash_cap' -> 'Ash Cap', 'nidoran_f' -> 'Nidoran ♀'."""
    words = [w for w in slug_part.split("_") if w]
    if len(words) > 1 and words[-1] in GENDER_SUFFIX:
        return " ".join(w.capitalize() for w in words[:-1]) + " " + GENDER_SUFFIX[words[-1]]
    return " ".join(w.capitalize() for w in words)


def display_name_for(slug: str, names: dict[str, tuple[str, str]]) -> str:
    species, form = names.get(slug, ("", ""))
    if not species:
        # No plan entry -- fall back to everything after the dex prefix.
        species = re.sub(r"^\d+_", "", slug)
        form = ""
    label = titleise(species)
    return f"{label} ({titleise(form)})" if form else label


def dex_of(slug: str) -> int | None:
    match = re.match(r"^(\d+)", slug)
    return int(match.group(1)) if match else None


def build_tres(slug: str, dex: int, name: str, folder: Path, settings: dict) -> str:
    """The full text of one .tres file."""
    mesh = folder / MESH_FILE
    shiny = folder / SHINY_FILE
    has_shiny = shiny.is_file()

    resources: list[str] = []
    fields: list[str] = []

    def ext(kind: str, uid: str, path: str, ident: str) -> None:
        uid_part = f' uid="{uid}"' if uid else ""
        resources.append(f'[ext_resource type="{kind}"{uid_part} path="{path}" id="{ident}"]')

    ext("ArrayMesh", import_uid(mesh), f"res://{ASSET_DIR}/{slug}/{MESH_FILE}", "1_mesh")
    if has_shiny:
        ext("Texture2D", import_uid(shiny), f"res://{ASSET_DIR}/{slug}/{SHINY_FILE}", "2_shiny")
    ext("Script", SCRIPT_UID, SCRIPT_PATH, "3_script")

    fields.append(f'script = ExtResource("3_script")')
    fields.append(f"dex_number = {dex}")
    fields.append(f'display_name = "{name}"')
    fields.append('mesh = ExtResource("1_mesh")')
    if has_shiny:
        fields.append('albedo_shiny = ExtResource("2_shiny")')
    fields.append("model_scale = 1.0")
    for key in classify.MANAGED_FIELDS:
        fields.append(f"{key} = {classify.format_value(key, settings[key])}")
    fields.append(f'metadata/_custom_type_script = "{SCRIPT_UID}"')

    header = (
        f'[gd_resource type="Resource" script_class="PokemonData" '
        f"load_steps={len(resources) + 1} format=3]"
    )
    return "\n".join([header, "", *resources, "", "[resource]", *fields, ""])


def command(root: Path, execute: bool, overwrite: bool, refresh: bool, only: str | None,
            dry_report: bool) -> int:
    asset_root = root / ASSET_DIR
    data_root = root / DATA_DIR
    if not asset_root.is_dir():
        sys.exit(f"error: {ASSET_DIR} not found under {root}")

    names = load_name_table(root)
    overrides = classify.load_overrides(root)

    folders = sorted(f for f in asset_root.iterdir() if f.is_dir())
    if only:
        folders = [f for f in folders if only.lower() in f.name.lower()]

    created: list[str] = []
    refreshed: list[str] = []
    replaced: list[str] = []
    skipped: list[str] = []
    problems: list[str] = []

    for folder in folders:
        slug = folder.name
        dex = dex_of(slug)
        if dex is None:
            problems.append(f"{slug}: no dex number in the folder name")
            continue
        if not (folder / MESH_FILE).is_file():
            problems.append(f"{slug}: no {MESH_FILE}")
            continue

        target = data_root / f"{slug}.tres"
        settings = classify.settings_for(dex, slug, overrides)
        name = display_name_for(slug, names)

        if not target.exists():
            created.append(slug)
            if execute:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(build_tres(slug, dex, name, folder, settings), encoding="utf-8")
            continue

        if overwrite:
            replaced.append(slug)
            if execute:
                target.write_text(build_tres(slug, dex, name, folder, settings), encoding="utf-8")
        elif refresh:
            lines, changed = classify.rewrite(target, settings)
            if changed:
                refreshed.append(slug)
                if execute:
                    target.write_text("".join(lines), encoding="utf-8")
            else:
                skipped.append(slug)
        else:
            skipped.append(slug)

    if dry_report or not execute:
        print(C.yellow(C.bold("\nDRY RUN -- nothing will be written.")) if not execute
              else C.bold("\nPlan"))

    print(C.bold(f"\n{len(folders)} folder(s) under {ASSET_DIR}"))
    print(f"  {C.green(str(len(created)))} to create")
    if replaced:
        print(f"  {C.red(str(len(replaced)))} to REPLACE (evolution links will be lost)")
    if refreshed:
        print(f"  {C.yellow(str(len(refreshed)))} to refresh animation fields on")
    print(f"  {len(skipped)} left alone (already exist)")
    if problems:
        print(C.red(f"  {len(problems)} problem(s):"))
        for problem in problems:
            print(f"    {problem}")

    for label, group in (("create", created), ("replace", replaced), ("refresh", refreshed)):
        if not group:
            continue
        preview = ", ".join(group[:8])
        more = f" ... and {len(group) - 8} more" if len(group) > 8 else ""
        print(C.dim(f"\n  {label}: {preview}{more}"))

    if execute:
        print(C.green(f"\nDone. Reopen the project in Godot to import the new resources."))
    else:
        print(C.yellow("\nDry run only. Re-run with --execute to apply."))
    return 1 if problems else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate one PokemonData .tres per folder in assets/pokemons.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--only", help="restrict to folders matching this substring")
    subparsers = parser.add_subparsers(dest="command", required=True)

    plan_parser = subparsers.add_parser("plan", help="report what would happen (read-only)")

    apply_parser = subparsers.add_parser("apply", help="create the .tres files")
    apply_parser.add_argument("--execute", action="store_true", help="actually write")
    apply_parser.add_argument(
        "--overwrite", action="store_true",
        help="replace existing files completely -- destroys hand-set evolution links",
    )
    apply_parser.add_argument(
        "--refresh-animation", action="store_true", dest="refresh",
        help="for existing files, rewrite only the animation fields",
    )

    # --only is accepted on either side of the subcommand; argparse only allows
    # one position by default, and getting it wrong is a silent no-op.
    for subparser in (plan_parser, apply_parser):
        subparser.add_argument("--only", dest="only_after", help=argparse.SUPPRESS)

    args = parser.parse_args()
    root = find_project_root(Path(__file__).resolve().parent)
    only = args.only_after or args.only

    if args.command == "plan":
        return command(root, False, False, False, only, True)
    return command(root, args.execute, args.overwrite, args.refresh, only, False)


if __name__ == "__main__":
    sys.exit(main())

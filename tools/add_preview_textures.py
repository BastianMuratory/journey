#!/usr/bin/env python3
"""
add_preview_textures.py -- point every PokemonData at its icon and previews.

WHY THIS EXISTS
---------------
assets/pokemons/<slug>/ gained three images after the .tres files were already
written and hand-edited: icon.png, preview.png and preview_shiny.png. The
resources knew nothing about them, so the UI had no way to reach a portrait
without building a res:// path by hand at runtime -- which skips Godot's uid
indirection and breaks the moment a file is renamed.

This edits the existing .tres files in place rather than regenerating them,
because those files carry evolution links, mega links and hand-tuned animation
values that a regeneration would throw away.

WHAT IT WRITES
--------------
Into each data/pokemon/*.tres that is missing them:

    icon            -> <slug>/icon.png, when present
    preview         -> <slug>/preview.png, when present
    preview_shiny   -> <slug>/preview_shiny.png, when present

Each one adds an [ext_resource] line carrying the uid Godot minted in the
.import sidecar, bumps load_steps to match, and inserts the field into the
[resource] block just after model_scale, which is where PokemonData declares
them. Nothing else in the file is touched.

Missing images are simply skipped -- the costume forms and the clones were
never given a shiny render, and PokemonData.get_preview() falls back to the
ordinary preview for those. Re-running is idempotent: a resource that already
points at an image is left alone, so this is safe to run again after new art
lands.

USAGE
-----
    python tools/add_preview_textures.py plan
        Read-only. What is missing, and what would be added.

    python tools/add_preview_textures.py apply
        Dry run -- same work, still writes nothing.

    python tools/add_preview_textures.py apply --execute
        Write the .tres files.

Flags:
    --only PATTERN  Restrict to resources whose filename contains PATTERN.
    --report PATH   Write the gap report (what art is still missing) to a file.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import classify_body_types as classify  # noqa: E402  (needs the path above)

C = classify.C

DATA_DIR = "data/pokemon"
ASSET_DIR = "assets/pokemons"

# field name -> (file in the asset folder, ext_resource id suffix). Order is the
# order they are declared in PokemonData, and the order they get inserted.
TEXTURES = (
    ("icon", "icon.png", "icon"),
    ("preview", "preview.png", "preview"),
    ("preview_shiny", "preview_shiny.png", "preview_shiny"),
)

# The line the new fields go after -- the last of the Model group, so the file
# keeps matching the declaration order in pokemon_data.gd.
ANCHOR_FIELD = "model_scale"

EXT_RE = re.compile(r'^\[ext_resource .*?\bid="([^"]+)"', re.MULTILINE)
PATH_RE = re.compile(r'\bpath="([^"]+)"')
LOAD_STEPS_RE = re.compile(r"load_steps=(\d+)")
ID_NUM_RE = re.compile(r"^(\d+)")


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


def next_ext_id(existing: list[str], suffix: str, offset: int) -> str:
    """A fresh ext_resource id that cannot collide with one already in the file.

    Godot's ids are arbitrary strings, but every one it writes looks like
    "<n>_<hint>", so we keep that shape and start past the highest n in use.
    """
    highest = 0
    for ident in existing:
        match = ID_NUM_RE.match(ident)
        if match:
            highest = max(highest, int(match.group(1)))
    return f"{highest + offset}_{suffix}"


class Edit:
    """One resource's worth of pending changes."""

    def __init__(self, slug: str) -> None:
        self.slug = slug
        self.added: list[str] = []      # field names newly pointed at art
        self.present: list[str] = []    # field names that were already set
        self.missing: list[str] = []    # field names with no image on disk
        self.text: str | None = None    # rewritten file, when anything changed

    @property
    def changed(self) -> bool:
        return bool(self.added)


def plan_file(path: Path, asset_root: Path) -> Edit:
    slug = path.stem
    edit = Edit(slug)
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()

    existing_ids = EXT_RE.findall(text)
    existing_paths = {
        PATH_RE.search(line).group(1)
        for line in lines
        if line.startswith("[ext_resource") and PATH_RE.search(line)
    }
    # A field already written by hand in the inspector counts as present even if
    # we cannot match the path, so we never write a second assignment for it.
    assigned = {
        line.split("=", 1)[0].strip()
        for line in lines
        if "=" in line and not line.startswith("[")
    }

    new_ext: list[str] = []
    new_fields: list[str] = []
    offset = 1

    for field, filename, suffix in TEXTURES:
        image = asset_root / slug / filename
        res_path = f"res://{ASSET_DIR}/{slug}/{filename}"

        if res_path in existing_paths or field in assigned:
            edit.present.append(field)
            continue
        if not image.is_file():
            edit.missing.append(field)
            continue

        ident = next_ext_id(existing_ids, suffix, offset)
        offset += 1
        uid = import_uid(image)
        uid_part = f' uid="{uid}"' if uid else ""
        new_ext.append(
            f'[ext_resource type="Texture2D"{uid_part} path="{res_path}" id="{ident}"]'
        )
        new_fields.append(f'{field} = ExtResource("{ident}")')
        edit.added.append(field)

    if not edit.added:
        return edit

    edit.text = splice(lines, new_ext, new_fields, len(existing_ids))
    return edit


def splice(lines: list[str], new_ext: list[str], new_fields: list[str],
           ext_count: int) -> str:
    """Put the new ext_resource and field lines where Godot would have put them."""
    out = list(lines)

    # Fields go straight after model_scale, matching the declaration order in
    # PokemonData. If a hand-written file has no model_scale, fall back to just
    # before the trailing metadata line, and failing that the end of the block.
    anchor = last_index(out, lambda line: line.startswith(f"{ANCHOR_FIELD} "))
    if anchor is None:
        anchor = first_index(out, lambda line: line.startswith("metadata/"))
        anchor = (anchor - 1) if anchor is not None else len(out) - 1
    out[anchor + 1:anchor + 1] = new_fields

    # ext_resource lines go after the last existing one, keeping the blank line
    # that separates the header block from [resource].
    last_ext = last_index(out, lambda line: line.startswith("[ext_resource"))
    if last_ext is None:
        last_ext = first_index(out, lambda line: line.startswith("[gd_resource"))
        out[last_ext + 1:last_ext + 1] = ["", *new_ext]
    else:
        out[last_ext + 1:last_ext + 1] = new_ext

    # load_steps is the ext_resource count plus one for [resource] itself. Godot
    # tolerates it being too high but not too low -- it stops reading early.
    for i, line in enumerate(out):
        if line.startswith("[gd_resource"):
            out[i] = LOAD_STEPS_RE.sub(
                f"load_steps={ext_count + len(new_ext) + 1}", line
            )
            break

    return "\n".join(out) + "\n"


def first_index(lines: list[str], predicate) -> int | None:
    for i, line in enumerate(lines):
        if predicate(line):
            return i
    return None


def last_index(lines: list[str], predicate) -> int | None:
    for i in range(len(lines) - 1, -1, -1):
        if predicate(lines[i]):
            return i
    return None


def command(root: Path, execute: bool, only: str | None, report: str | None) -> int:
    data_root = root / DATA_DIR
    asset_root = root / ASSET_DIR
    if not data_root.is_dir():
        sys.exit(f"error: {DATA_DIR} not found under {root}")

    files = sorted(data_root.glob("*.tres"))
    if only:
        files = [f for f in files if only.lower() in f.name.lower()]

    edits = [plan_file(path, asset_root) for path in files]
    changed = [e for e in edits if e.changed]

    if not execute:
        print(C.yellow(C.bold("\nDRY RUN -- nothing will be written.")))

    print(C.bold(f"\n{len(files)} resource(s) under {DATA_DIR}"))
    for field, _, _ in TEXTURES:
        adds = sum(1 for e in edits if field in e.added)
        have = sum(1 for e in edits if field in e.present)
        gaps = sum(1 for e in edits if field in e.missing)
        line = f"  {field:<14} {C.green(f'+{adds}')} to add"
        if have:
            line += f", {have} already set"
        if gaps:
            line += f", {C.yellow(str(gaps))} with no image on disk"
        print(line)

    if changed:
        preview = ", ".join(e.slug for e in changed[:8])
        more = f" ... and {len(changed) - 8} more" if len(changed) > 8 else ""
        print(C.dim(f"\n  editing: {preview}{more}"))
    else:
        print(C.dim("\n  nothing to do -- every resource already points at its art."))

    gap_lines = gap_report(edits)
    if report:
        (root / report).write_text("\n".join(gap_lines) + "\n", encoding="utf-8")
        print(C.dim(f"\n  gap report written to {report}"))

    if execute:
        for edit in changed:
            (data_root / f"{edit.slug}.tres").write_text(edit.text, encoding="utf-8")
        print(C.green(f"\nDone -- {len(changed)} file(s) written. "
                      "Reopen the project in Godot to reimport."))
    else:
        print(C.yellow("\nDry run only. Re-run with --execute to apply."))
    return 0


def gap_report(edits: list[Edit]) -> list[str]:
    """The forms still waiting on art, grouped by which file is missing."""
    lines = ["# Missing art under assets/pokemons/", ""]
    for field, filename, _ in TEXTURES:
        gaps = [e.slug for e in edits if field in e.missing]
        lines.append(f"## {filename} -- {len(gaps)} missing")
        lines.extend(f"- {slug}" for slug in gaps)
        lines.append("")
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Point every PokemonData .tres at its icon and preview images.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name, help_text in (("plan", "report what would happen (read-only)"),
                            ("apply", "add the texture references")):
        sub = subparsers.add_parser(name, help=help_text)
        sub.add_argument("--only", help="restrict to filenames matching this substring")
        sub.add_argument("--report", help="write the missing-art report to this path")
        if name == "apply":
            sub.add_argument("--execute", action="store_true", help="actually write")

    args = parser.parse_args()
    root = find_project_root(Path(__file__).resolve().parent)
    execute = getattr(args, "execute", False)
    return command(root, execute, args.only, args.report)


if __name__ == "__main__":
    sys.exit(main())

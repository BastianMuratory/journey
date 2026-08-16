#!/usr/bin/env python3
"""
add_base_stats.py -- write the base stats onto every PokemonData.

WHY THIS EXISTS
---------------
PokemonData declares six base stats and there are 400+ resources to set them on.
The numbers come from tools/base_stats.json, which tools/download_base_stats.py
bakes out of PokeAPI, so this script needs no network: it is pure text editing
and can be re-run, reverted and re-run again offline.

It edits the existing .tres files in place rather than regenerating them, because
those files carry evolution links, mega links, hand-tuned animation values and
texture references that a regeneration would throw away.

WHAT IT WRITES
--------------
Into each data/pokemon/*.tres, at the end of the [resource] block (just before
the metadata/ lines, which is where the Stats group sits in the declaration
order of pokemon_data.gd):

    base_hp, base_attack, base_defense,
    base_special_attack, base_special_defense, base_speed

Existing values are overwritten, so re-running is idempotent and safe. Anything
you hand-tune in the Godot inspector WILL be overwritten -- edit
tools/base_stats.json instead, so the change survives a re-run.

A resource with no entry in base_stats.json is left completely untouched and
listed in the gap report, so a partial download can never half-fill a file.

USAGE
-----
    python tools/add_base_stats.py plan
        Read-only. Coverage, plus which resources have no stats yet.

    python tools/add_base_stats.py apply
        Dry run -- shows the exact edits, writes nothing.

    python tools/add_base_stats.py apply --execute
        Write the .tres files.

Flags:
    --only PATTERN  Restrict to resources whose filename contains PATTERN.

Stdlib only, matching the other scripts in this folder.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DATA_DIR = "data/pokemon"
STATS_FILE = "tools/base_stats.json"

# Declaration order in pokemon_data.gd's Stats group. The block is written in
# this order so the .tres files stay readable and diff cleanly.
FIELDS = (
    "base_hp",
    "base_attack",
    "base_defense",
    "base_special_attack",
    "base_special_defense",
    "base_speed",
)

RESOURCE_HEADER = re.compile(r"^\s*\[resource\]\s*$")
SECTION_HEADER = re.compile(r"^\s*\[")
MANAGED_LINE = re.compile(rf"^\s*({'|'.join(FIELDS)})\s*=")
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


def find_project_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "project.godot").is_file():
            return candidate
    sys.exit("error: could not locate project.godot -- run this from inside the project")


def load_stats(root: Path) -> dict[str, dict]:
    path = root / STATS_FILE
    if not path.is_file():
        sys.exit(
            f"error: {STATS_FILE} does not exist yet.\n"
            f"       run: python tools/download_base_stats.py fetch"
        )
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        sys.exit(f"error: {STATS_FILE} is not valid JSON ({error})")

    species = data.get("species", {})
    if not isinstance(species, dict) or not species:
        sys.exit(f"error: {STATS_FILE} has no species -- re-run the downloader")

    clean: dict[str, dict] = {}
    for slug, entry in species.items():
        missing = [f for f in FIELDS if f not in entry]
        if missing:
            print(C.yellow(f"warning: {slug} is missing {', '.join(missing)}; skipping"))
            continue
        clean[slug] = {f: int(entry[f]) for f in FIELDS}
    return clean


def data_files(root: Path, only: str | None) -> list[Path]:
    paths = sorted((root / DATA_DIR).glob("*.tres"))
    if only:
        paths = [p for p in paths if only in p.name]
    return paths


def current_values(text: str) -> dict[str, int]:
    """The stats a .tres already carries, for the dry-run diff."""
    found: dict[str, int] = {}
    for line in text.splitlines():
        match = re.match(rf"^\s*({'|'.join(FIELDS)})\s*=\s*(-?\d+)\s*$", line)
        if match:
            found[match.group(1)] = int(match.group(2))
    return found


def rewrite(text: str, stats: dict[str, int]) -> str:
    """
    Strip any existing copy of the managed fields and re-insert them as one block
    at the end of [resource], before the metadata/ lines Godot keeps last.
    """
    original = text.splitlines(keepends=True)
    block = [f"{field} = {stats[field]}\n" for field in FIELDS]

    output: list[str] = []
    held: list[str] = []  # metadata lines, held back so the block lands above them
    in_resource = False
    inserted = False

    for line in original:
        if RESOURCE_HEADER.match(line):
            in_resource = True
            output.append(line)
            continue

        if in_resource:
            if MANAGED_LINE.match(line):
                continue  # drop the stale copy
            if SECTION_HEADER.match(line):
                # A new section closes [resource]; flush before leaving it.
                if not inserted:
                    output.extend(block)
                    inserted = True
                output.extend(held)
                held = []
                in_resource = False
                output.append(line)
                continue
            if METADATA_LINE.match(line):
                held.append(line)
                continue

        output.append(line)

    if not inserted:
        output.extend(block)
    output.extend(held)

    # A file that did not end in a newline would otherwise glue the first stat
    # onto the last property.
    joined = "".join(output)
    return joined if joined.endswith("\n") else joined + "\n"


def command_plan(root: Path, only: str | None) -> int:
    paths = data_files(root, only)
    stats = load_stats(root)

    filled, empty, gaps = 0, 0, []
    for path in paths:
        if path.stem not in stats:
            gaps.append(path.stem)
            continue
        if current_values(path.read_text(encoding="utf-8")):
            filled += 1
        else:
            empty += 1

    print(C.bold(f"{len(paths)} resources, {len(stats)} entries in {STATS_FILE}"))
    print(f"  already carry stats: {filled}")
    print(f"  would be filled in:  {empty}")
    print(f"  no data available:   {len(gaps)}")

    if gaps:
        print(C.yellow(f"\n{len(gaps)} resource(s) have no entry in {STATS_FILE}:"))
        for slug in gaps:
            print(f"  {slug}")
        print(C.dim("  Run: python tools/download_base_stats.py fetch"))

    orphans = sorted(set(stats) - {p.stem for p in paths})
    if orphans and not only:
        print(C.dim(f"\n{len(orphans)} entr(ies) in the JSON have no .tres: "
                    f"{', '.join(orphans[:8])}"))
    return 0


def command_apply(root: Path, only: str | None, execute: bool) -> int:
    paths = data_files(root, only)
    stats = load_stats(root)

    changed, unchanged, skipped = 0, 0, []
    for path in paths:
        wanted = stats.get(path.stem)
        if wanted is None:
            skipped.append(path.stem)
            continue

        text = path.read_text(encoding="utf-8")
        before = current_values(text)
        updated = rewrite(text, wanted)
        if updated == text:
            unchanged += 1
            continue

        changed += 1
        total = sum(wanted.values())
        if before and before != wanted:
            delta = ", ".join(
                f"{f.removeprefix('base_')} {before.get(f, '-')}->{wanted[f]}"
                for f in FIELDS if before.get(f) != wanted[f]
            )
            print(f"  {path.stem:32s} {C.yellow('update')}  {delta}")
        else:
            spread = "/".join(str(wanted[f]) for f in FIELDS)
            print(f"  {path.stem:32s} {C.green('fill')}    {spread}  BST {total}")

        if execute:
            path.write_text(updated, encoding="utf-8")

    verb = "wrote" if execute else "would write"
    print(C.bold(f"\n{verb} {changed} file(s); {unchanged} already correct"))
    if skipped:
        print(C.yellow(f"{len(skipped)} skipped -- no entry in {STATS_FILE}: "
                       f"{', '.join(skipped[:8])}"
                       f"{' ...' if len(skipped) > 8 else ''}"))
    if changed and not execute:
        print(C.dim("dry run -- pass --execute to write"))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    plan = sub.add_parser("plan", help="read-only coverage report")
    plan.add_argument("--only", help="restrict to filenames containing PATTERN")

    apply = sub.add_parser("apply", help="edit the .tres files")
    apply.add_argument("--only", help="restrict to filenames containing PATTERN")
    apply.add_argument("--execute", action="store_true", help="actually write")

    args = parser.parse_args()
    root = find_project_root(Path(__file__).resolve().parent)

    if args.command == "plan":
        return command_plan(root, args.only)
    return command_apply(root, args.only, args.execute)


if __name__ == "__main__":
    raise SystemExit(main())

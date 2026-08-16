#!/usr/bin/env python3
"""
download_base_stats.py -- bake every species' base stats into tools/base_stats.json.

WHY THIS EXISTS
---------------
PokemonData grew a Stats group (base_hp, base_attack, ...) and there are 400+
resources to fill. The numbers are the mainline Gen 3+ spread, which PokeAPI
publishes, so they are fetched once and committed as JSON rather than being
re-fetched on every run.

Splitting the fetch from the write is deliberate: tools/add_base_stats.py, the
script that actually edits the .tres files, then needs no network at all. You
can re-run it, review its diff, revert it and run it again offline, and a
PokeAPI outage can never leave half the resources filled.

WHAT IT WRITES
--------------
tools/base_stats.json, keyed by resource slug:

    "0001_bulbasaur": {
        "base_hp": 45, "base_attack": 49, "base_defense": 49,
        "base_special_attack": 65, "base_special_defense": 65,
        "base_speed": 45, "source": "1"
    }

"source" is the PokeAPI key the numbers came from, so a wrong-looking spread is
traceable back to what was asked for.

FORMS
-----
Which PokeAPI entry a form maps to lives in tools/stat_form_overrides.json:
regionals, Rotom appliances, Deoxys and Shaymin get their own slug; costumes and
clones inherit the base species. A form file listed in neither is reported as a
warning -- it still inherits, but you get told, so new art does not quietly land
with the wrong stats.

USAGE
-----
    python tools/download_base_stats.py plan
        Read-only. What would be fetched, and from which PokeAPI key.

    python tools/download_base_stats.py fetch
        Download the missing entries and write tools/base_stats.json.

Flags:
    --only PATTERN  Restrict to resources whose filename contains PATTERN.
    --force         Re-fetch entries that are already in the JSON.
    --delay SECONDS Pause between requests (default 0.2 -- be kind to PokeAPI).

Stdlib only, matching the other scripts in this folder.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

DATA_DIR = "data/pokemon"
OUT_FILE = "tools/base_stats.json"
OVERRIDES_FILE = "tools/stat_form_overrides.json"

API = "https://pokeapi.co/api/v2/pokemon/{key}/"
UA = "journey-stat-fetcher/1.0 (godot asset import; contact: local script)"

# PokeAPI stat name -> the field it fills on PokemonData. The order here is the
# order the fields are declared in pokemon_data.gd.
STAT_FIELDS = {
    "hp": "base_hp",
    "attack": "base_attack",
    "defense": "base_defense",
    "special-attack": "base_special_attack",
    "special-defense": "base_special_defense",
    "speed": "base_speed",
}
FIELDS = tuple(STAT_FIELDS.values())

DEX_LINE = re.compile(r"^\s*dex_number\s*=\s*(?P<dex>\d+)\s*$")


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


def load_overrides(root: Path) -> tuple[dict[str, str], set[str]]:
    path = root / OVERRIDES_FILE
    if not path.is_file():
        print(C.yellow(f"warning: {OVERRIDES_FILE} is missing; every form will inherit"))
        return {}, set()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        sys.exit(f"error: {OVERRIDES_FILE} is not valid JSON ({error})")
    variants = data.get("variants", {})
    cosmetic = set(data.get("cosmetic", []))
    return (variants if isinstance(variants, dict) else {}), cosmetic


def data_files(root: Path, only: str | None) -> list[Path]:
    paths = sorted((root / DATA_DIR).glob("*.tres"))
    if only:
        paths = [p for p in paths if only in p.name]
    return paths


def dex_from(path: Path) -> int | None:
    """Dex number from the file's contents, falling back to its name."""
    for line in path.read_text(encoding="utf-8").splitlines():
        match = DEX_LINE.match(line)
        if match:
            return int(match.group("dex"))
    digits = re.match(r"^(\d+)", path.stem)
    return int(digits.group(1)) if digits else None


def plan_keys(
    paths: list[Path],
    variants: dict[str, str],
    cosmetic: set[str],
) -> tuple[dict[str, str], list[str]]:
    """
    slug -> PokeAPI key, plus the slugs that look like an unclassified form.

    A file is form-like when another resource with the same dex number has a stem
    that is a strict prefix of it: 0003_venusaur_clone sits under 0003_venusaur,
    so it is a form, while 0003_venusaur itself is not. Testing for a prefix
    rather than parsing the suffix avoids tripping over species whose own name
    carries an underscore -- nidoran_f, mr_mime, ho_oh.
    """
    dex_of: dict[str, int | None] = {p.stem: dex_from(p) for p in paths}
    by_dex: dict[int, list[str]] = {}
    for slug, dex in dex_of.items():
        if dex is not None:
            by_dex.setdefault(dex, []).append(slug)

    def is_form(slug: str, dex: int) -> bool:
        return any(
            other != slug and slug.startswith(other + "_")
            for other in by_dex.get(dex, ())
        )

    keys: dict[str, str] = {}
    unlisted: list[str] = []
    for slug, dex in dex_of.items():
        if slug in variants:
            keys[slug] = variants[slug]
            continue
        if dex is None:
            unlisted.append(slug)
            continue
        keys[slug] = str(dex)
        if slug not in cosmetic and is_form(slug, dex):
            unlisted.append(slug)
    return keys, unlisted


def fetch(key: str, timeout: float) -> dict[str, int]:
    request = urllib.request.Request(API.format(key=key), headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))

    stats: dict[str, int] = {}
    for entry in payload.get("stats", []):
        name = entry.get("stat", {}).get("name")
        field = STAT_FIELDS.get(name)
        if field:
            stats[field] = int(entry["base_stat"])

    missing = [f for f in FIELDS if f not in stats]
    if missing:
        raise ValueError(f"response for {key!r} is missing {', '.join(missing)}")
    return stats


def load_existing(root: Path) -> dict[str, dict]:
    path = root / OUT_FILE
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        sys.exit(f"error: {OUT_FILE} is not valid JSON ({error}); delete it to start over")
    species = data.get("species", {})
    return species if isinstance(species, dict) else {}


def write_json(root: Path, species: dict[str, dict]) -> None:
    path = root / OUT_FILE
    document = {
        "_comment": (
            "Base stats from PokeAPI, keyed by data/pokemon resource slug. "
            "Regenerate with tools/download_base_stats.py fetch; apply with "
            "tools/add_base_stats.py apply --execute."
        ),
        "_generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "_source": "https://pokeapi.co/api/v2/pokemon/",
        "species": dict(sorted(species.items())),
    }
    path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


def report_unlisted(unlisted: list[str]) -> None:
    if not unlisted:
        return
    print(C.yellow(f"\n{len(unlisted)} form(s) are in neither list in {OVERRIDES_FILE}:"))
    for slug in sorted(unlisted):
        print(f"  {slug}")
    print(C.dim("  They inherit their base species. Add them to \"variants\" if the"))
    print(C.dim("  form has its own spread, or to \"cosmetic\" to silence this."))


def command_plan(root: Path, only: str | None) -> int:
    paths = data_files(root, only)
    variants, cosmetic = load_overrides(root)
    keys, unlisted = plan_keys(paths, variants, cosmetic)
    have = load_existing(root)

    fresh = sorted(slug for slug in keys if slug not in have)
    print(C.bold(f"{len(paths)} resources, {len(set(keys.values()))} distinct PokeAPI keys"))
    print(f"  already in {OUT_FILE}: {len(keys) - len(fresh)}")
    print(f"  to fetch:             {len(fresh)}")
    for slug in fresh[:20]:
        print(C.dim(f"    {slug:32s} -> {keys[slug]}"))
    if len(fresh) > 20:
        print(C.dim(f"    ... and {len(fresh) - 20} more"))

    named = sorted(slug for slug in keys if slug in variants)
    if named:
        print(C.bold(f"\n{len(named)} form(s) fetched under their own slug:"))
        for slug in named:
            print(f"  {slug:32s} -> {keys[slug]}")

    report_unlisted(unlisted)
    return 0


def command_fetch(root: Path, only: str | None, force: bool, delay: float) -> int:
    paths = data_files(root, only)
    variants, cosmetic = load_overrides(root)
    keys, unlisted = plan_keys(paths, variants, cosmetic)
    species = load_existing(root)

    wanted = {slug: key for slug, key in keys.items() if force or slug not in species}
    if not wanted:
        print(C.green(f"nothing to do -- {len(keys)} resources already in {OUT_FILE}"))
        report_unlisted(unlisted)
        return 0

    # Many slugs share a key (every costume points at its base species), so the
    # cache turns 410 resources into far fewer requests.
    cache: dict[str, dict[str, int]] = {}
    failed: list[tuple[str, str]] = []
    done = 0

    print(C.bold(f"fetching {len(set(wanted.values()))} key(s) for {len(wanted)} resources"))
    for slug in sorted(wanted):
        key = wanted[slug]
        if key not in cache:
            try:
                cache[key] = fetch(key, timeout=20.0)
            except (urllib.error.URLError, ValueError, KeyError, TimeoutError) as error:
                failed.append((slug, f"{key}: {error}"))
                print(C.red(f"  {slug:32s} -> {key}  FAILED ({error})"))
                continue
            time.sleep(delay)
        stats = cache[key]
        species[slug] = {**stats, "source": key}
        done += 1
        total = stats["base_hp"] + sum(stats[f] for f in FIELDS[1:])
        print(f"  {slug:32s} -> {key:24s} BST {total}")

    write_json(root, species)
    print(C.green(f"\nwrote {OUT_FILE} -- {len(species)} resources total, {done} new"))

    if failed:
        print(C.red(f"\n{len(failed)} failed; re-run to retry just those:"))
        for slug, why in failed:
            print(f"  {slug}: {why}")

    report_unlisted(unlisted)
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    plan = sub.add_parser("plan", help="read-only: what would be fetched")
    plan.add_argument("--only", help="restrict to filenames containing PATTERN")

    fetch_cmd = sub.add_parser("fetch", help="download and write tools/base_stats.json")
    fetch_cmd.add_argument("--only", help="restrict to filenames containing PATTERN")
    fetch_cmd.add_argument("--force", action="store_true", help="re-fetch existing entries")
    fetch_cmd.add_argument("--delay", type=float, default=0.2,
                           help="seconds between requests (default 0.2)")

    args = parser.parse_args()
    root = find_project_root(Path(__file__).resolve().parent)

    if args.command == "plan":
        return command_plan(root, args.only)
    return command_fetch(root, args.only, args.force, args.delay)


if __name__ == "__main__":
    raise SystemExit(main())

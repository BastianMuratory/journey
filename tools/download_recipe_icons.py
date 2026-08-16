#!/usr/bin/env python3
"""
Download recipe previews and cooking ingredient icons from the Pokemon Quest
BWIKI.

Source: https://wiki.biligame.com/pq/食谱

Writes:
    assets/icons/recipes/<nnn>_<english>.png     recipe art (File:<配方名称>.png)
    assets/icons/recipes/manifest.json           index, names, ingredients, ...
    assets/icons/ingredients/<nn>_<english>.png  cooking ingredients
    assets/icons/ingredients/manifest.json

Recipes and ingredients are Quest-only items, so unlike moves there is no API
to translate them. Everything is numbered by its wiki index and listed in
tools/recipe_name_overrides.json with a blank English slot; fill those in and
re-run with --force to get names like 001_mulligan_stew.png.

Recipes come from three categories: 食谱 (permanent), 限定食谱 (limited) and
特别料理 (special). Ingredients are parsed from the 食谱 page's own wikitext,
since they are a hand-written table rather than a category.

Stdlib only. Usage:
    python tools/download_recipe_icons.py --dry-run
    python tools/download_recipe_icons.py
    python tools/download_recipe_icons.py --only ingredients
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import bwiki
from bwiki import ICONS_DIR, Downloader

TOOLS = Path(__file__).resolve().parent
OVERRIDES = TOOLS / "recipe_name_overrides.json"

RECIPE_PAGE = "食谱"
# category -> (subfolder tag, ask query)
RECIPE_SETS = [
    ("食谱", "permanent"),
    ("限定食谱", "limited"),
    ("特别料理", "special"),
]
ASK_TEMPLATE = "[[分类:{cat}]]|?编号|?配方说明|?吸引宝可梦类型|?食材备注|limit=1000"

# [[file:小蘑菇.png|center|30px]] in the 常驻食材 table
INGREDIENT_RE = re.compile(r"\[\[\s*[Ff]ile:\s*([^|\]]+?)\.png\s*\|[^\]]*?30px[^\]]*?\]\]")


def collect_recipes() -> list[dict]:
    rows: list[dict] = []
    for cat, kind in RECIPE_SETS:
        try:
            found = bwiki.ask(ASK_TEMPLATE.format(cat=cat))
        except RuntimeError as exc:
            print(f"  !! {cat}: {exc}", file=sys.stderr)
            continue
        print(f"  {cat}: {len(found)} recipes")
        for cn, props in found.items():
            idx = bwiki.one(props, "编号")
            rows.append(
                {
                    "index": int(idx) if idx.isdigit() else None,
                    "kind": kind,
                    "name_cn": cn,
                    "name_en": "",
                    "recipe": bwiki.one(props, "配方说明"),
                    "attracts": bwiki.one(props, "吸引宝可梦类型"),
                    "notes": bwiki.one(props, "食材备注"),
                }
            )
    order = {k: i for i, (_, k) in enumerate(RECIPE_SETS)}
    rows.sort(key=lambda r: (order[r["kind"]], r["index"] is None, r["index"] or 0))
    return rows


def collect_ingredients() -> list[str]:
    text = bwiki.page_wikitext(RECIPE_PAGE)
    seen, names = set(), []
    for name in INGREDIENT_RE.findall(text):
        name = name.strip()
        if name and name not in seen:
            seen.add(name)
            names.append(name)
    return names


def download_group(rows, folder, dl, overrides, unnamed, width, dry_run):
    out = ICONS_DIR / folder
    urls = bwiki.resolve_files(f"{r['name_cn']}.png" for r in rows)
    print(f"  {len(urls)}/{len(rows)} images available")
    for i, r in enumerate(rows, 1):
        if dl.aborted:
            break
        en = overrides.get(r["name_cn"]) or ""
        r["name_en"] = en
        if not en:
            unnamed.add(r["name_cn"])
        num = r.get("index") or i
        stem = f"{num:0{width}d}_{en}" if en else f"{num:0{width}d}"
        url = urls.get(f"{r['name_cn']}.png")
        if not url:
            print(f"  -- no image for {r['name_cn']}")
            dl.missing += 1
            r["file"] = None
            continue
        r["file"] = f"{stem}.png"
        dl.get(url, out / r["file"], f"{r['name_cn']} -> {stem}", number=f"{num:0{width}d}")
    if rows and not dry_run:
        bwiki.write_manifest(out / "manifest.json", rows)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true", help="re-download existing files")
    ap.add_argument("--delay", type=float, default=0.25)
    ap.add_argument(
        "--only",
        choices=["recipes", "ingredients"],
        action="append",
        help="limit to one set (repeatable); default is both",
    )
    args = ap.parse_args()
    want = set(args.only or ["recipes", "ingredients"])

    dl = Downloader(dry_run=args.dry_run, force=args.force, delay=args.delay)
    overrides = bwiki.load_overrides(OVERRIDES)
    unnamed: set[str] = set()

    if "recipes" in want:
        print("fetching recipe list ...")
        recipes = collect_recipes()
        if not recipes:
            print("  !! no recipes found - has the wiki schema changed?", file=sys.stderr)
            return 1
        print(f"  {len(recipes)} recipes total")
        download_group(recipes, "recipes", dl, overrides, unnamed, 3, args.dry_run)

    if "ingredients" in want and not dl.aborted:
        print("\nfetching ingredient list ...")
        names = collect_ingredients()
        if not names:
            print(
                "  !! no ingredients parsed from the 食谱 page - the table layout "
                "may have changed",
                file=sys.stderr,
            )
        else:
            print(f"  {len(names)} ingredients")
            rows = [{"index": i, "name_cn": n, "name_en": ""} for i, n in enumerate(names, 1)]
            download_group(rows, "ingredients", dl, overrides, unnamed, 2, args.dry_run)

    dl.report("recipe icons")

    if unnamed:
        print(f"\n{len(unnamed)} items have no English name yet (numbered instead).")
        if not args.dry_run:
            added = bwiki.save_override_stubs(OVERRIDES, unnamed)
            if added:
                print(f"  -> added {added} blank entries to {OVERRIDES.name}")
            print("  Fill in the English names there, then re-run with --force.")

    return 1 if dl.failed else 0


if __name__ == "__main__":
    sys.exit(main())

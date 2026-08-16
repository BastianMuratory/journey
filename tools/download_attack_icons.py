#!/usr/bin/env python3
"""
Download move icons and the badge icons that go with them from the Pokemon
Quest BWIKI.

Source: https://wiki.biligame.com/pq/招式

Writes:
    assets/icons/attacks/<nnn>_<english>.png    move icons        (File:<名称>.png)
    assets/icons/attacks/manifest.json          index, names, type, power, ...
    assets/icons/types/<english>.png            18 type badges
    assets/icons/move_categories/<english>.png  physical/special/status
    assets/icons/move_stones/<...>.png          stone icons used by moves

Move names come out in English: PokeAPI publishes a Simplified-Chinese name for
every move, so 超级吸取 -> mega_drain. That mapping is built once from two CSVs
and cached in tools/move_names_zh_en.json.

Anything with no English name (Quest-only moves, stones) is written as
<nnn>_<pinyin-free fallback> and listed in tools/attack_name_overrides.json for
you to fill in; re-run afterwards to rename.

Stdlib only. Usage:
    python tools/download_attack_icons.py --dry-run
    python tools/download_attack_icons.py
    python tools/download_attack_icons.py --force
    python tools/download_attack_icons.py --only attacks
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bwiki
from bwiki import ICONS_DIR, Downloader

TOOLS = Path(__file__).resolve().parent
MOVE_NAME_CACHE = TOOLS / "move_names_zh_en.json"
OVERRIDES = TOOLS / "attack_name_overrides.json"

# Confident, stable translations - these are the standard English names.
TYPES = {
    "一般": "normal", "格斗": "fighting", "飞行": "flying", "毒": "poison",
    "地面": "ground", "岩石": "rock", "虫": "bug", "幽灵": "ghost",
    "钢": "steel", "火": "fire", "水": "water", "草": "grass",
    "电": "electric", "超能力": "psychic", "冰": "ice", "龙": "dragon",
    "恶": "dark", "妖精": "fairy",
}
MOVE_CATEGORIES = {"物理": "physical", "特殊": "special", "变化": "status"}
ATTACK_STYLES = {"近战": "melee", "远程": "ranged"}

ASK_MOVES = (
    "[[分类:招式]]|?序号|?属性|?招式分类|?攻击力|?等待时间"
    "|?可使用招式石展示|?招式描述|?功能|?伤害|?状态|limit=1000|sort=排序号|order=asc"
)


def simple_set(mapping: dict[str, str], folder: str, dl: Downloader) -> None:
    """Download a small fixed set like types or categories."""
    urls = bwiki.resolve_files(f"{cn}.png" for cn in mapping)
    out = ICONS_DIR / folder
    for cn, en in sorted(mapping.items(), key=lambda kv: kv[1]):
        url = urls.get(f"{cn}.png")
        if not url:
            print(f"  -- no image for {cn} ({en})")
            dl.missing += 1
            continue
        if dl.aborted:
            return
        dl.get(url, out / f"{en}.png", f"{cn} -> {en}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true", help="re-download existing files")
    ap.add_argument("--delay", type=float, default=0.25)
    ap.add_argument(
        "--only",
        choices=["attacks", "types", "move_categories", "move_stones"],
        action="append",
        help="limit to these sets (repeatable); default is all of them",
    )
    args = ap.parse_args()
    want = set(args.only or ["attacks", "types", "move_categories", "move_stones"])
    dl = Downloader(dry_run=args.dry_run, force=args.force, delay=args.delay)

    overrides = bwiki.load_overrides(OVERRIDES)
    unnamed: set[str] = set()

    # ---------------------------------------------------------------- moves --
    manifest: list[dict] = []
    stone_names: set[str] = set()
    if "attacks" in want or "move_stones" in want:
        print("fetching move list ...")
        rows = bwiki.ask(ASK_MOVES)
        print(f"  {len(rows)} moves")
        if not rows:
            print("  !! no moves returned - has the wiki schema changed?", file=sys.stderr)
            return 1

        zh_en = bwiki.chinese_move_names(MOVE_NAME_CACHE)
        urls = bwiki.resolve_files(f"{name}.png" for name in rows)
        print(f"  {len(urls)} move icons available")

        out = ICONS_DIR / "attacks"
        entries = []
        for cn, props in rows.items():
            idx = bwiki.one(props, "序号")
            stones = [s.strip() for s in bwiki.one(props, "可使用招式石展示").split(",") if s.strip()]
            stone_names.update(stones)
            en = overrides.get(cn) or zh_en.get(cn, "")
            if not en:
                unnamed.add(cn)
            entries.append(
                {
                    "index": int(idx) if idx.isdigit() else None,
                    "name_cn": cn,
                    "name_en": en,
                    "type": TYPES.get(bwiki.one(props, "属性"), bwiki.one(props, "属性")),
                    "category": MOVE_CATEGORIES.get(
                        bwiki.one(props, "招式分类"), bwiki.one(props, "招式分类")
                    ),
                    "power": bwiki.one(props, "攻击力"),
                    "cooldown": bwiki.one(props, "等待时间"),
                    "stones": stones,
                    "description": bwiki.one(props, "招式描述"),
                }
            )
        entries.sort(key=lambda e: (e["index"] is None, e["index"] or 0, e["name_cn"]))

        if "attacks" in want:
            for i, e in enumerate(entries, 1):
                if dl.aborted:
                    break
                num = e["index"] if e["index"] is not None else i
                stem = f"{num:03d}_{e['name_en']}" if e["name_en"] else f"{num:03d}"
                e["file"] = f"{stem}.png"
                url = urls.get(f"{e['name_cn']}.png")
                if not url:
                    print(f"  -- no icon for {e['name_cn']}")
                    dl.missing += 1
                    e["file"] = None
                    continue
                dl.get(url, out / e["file"], f"{e['name_cn']} -> {stem}", number=f"{num:03d}")
            manifest = entries
            if not args.dry_run:
                bwiki.write_manifest(out / "manifest.json", manifest)

    # ------------------------------------------------------- badge icon sets --
    if "types" in want and not dl.aborted:
        print("\nfetching type icons ...")
        simple_set(TYPES, "types", dl)
        simple_set(ATTACK_STYLES, "attack_styles", dl)

    if "move_categories" in want and not dl.aborted:
        print("\nfetching move category icons ...")
        simple_set(MOVE_CATEGORIES, "move_categories", dl)

    if "move_stones" in want and stone_names and not dl.aborted:
        print(f"\nfetching {len(stone_names)} move stone icons ...")
        urls = bwiki.resolve_files(f"{n}.png" for n in stone_names)
        out = ICONS_DIR / "move_stones"
        rows = []
        for i, cn in enumerate(sorted(stone_names), 1):
            if dl.aborted:
                break
            en = overrides.get(cn) or ""
            if not en:
                unnamed.add(cn)
            stem = f"{i:02d}_{en}" if en else f"{i:02d}"
            url = urls.get(f"{cn}.png")
            if not url:
                print(f"  -- no icon for {cn}")
                dl.missing += 1
                continue
            rows.append({"name_cn": cn, "name_en": en, "file": f"{stem}.png"})
            dl.get(url, out / f"{stem}.png", f"{cn} -> {stem}", number=f"{i:02d}")
        if rows and not args.dry_run:
            bwiki.write_manifest(out / "manifest.json", rows)

    dl.report("attack icons")

    if unnamed:
        print(f"\n{len(unnamed)} items had no English name (numbered instead):")
        for cn in sorted(unnamed)[:15]:
            print(f"  {cn}")
        if len(unnamed) > 15:
            print(f"  ... and {len(unnamed) - 15} more")
        if not args.dry_run:
            added = bwiki.save_override_stubs(OVERRIDES, unnamed)
            if added:
                print(f"  -> added {added} blank entries to {OVERRIDES.name}; "
                      "fill them in and re-run with --force to rename")

    return 1 if dl.failed else 0


if __name__ == "__main__":
    sys.exit(main())

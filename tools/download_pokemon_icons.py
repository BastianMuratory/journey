#!/usr/bin/env python3
"""
Download Pokemon artwork from the Pokemon Quest BWIKI and drop it into
assets/pokemons/<dex>_<species>[_<form>]/.

Source: https://wiki.biligame.com/pq/宝可梦图鉴

The wiki keeps three images per Pokemon (including regional/costume forms).
Keyed by dex number + Chinese form suffix:

    button_icon_M<dex><form>.png   small inventory icon  -> icon.png
    普通<dex><form>.png             512x512 render        -> preview.png
    异色<dex><form>.png             512x512 shiny render  -> preview_shiny.png

Note there is no shiny *icon* on the wiki - 异色 is a full-size preview, the
shiny counterpart of 普通, not of button_icon_M.

Stdlib only. Usage:
    python tools/download_pokemon_icons.py                 # download missing
    python tools/download_pokemon_icons.py --dry-run       # plan only
    python tools/download_pokemon_icons.py --force         # re-download
    python tools/download_pokemon_icons.py --icons-only    # skip both previews
    python tools/download_pokemon_icons.py --no-shiny      # skip preview_shiny
    python tools/download_pokemon_icons.py --no-create     # never mkdir
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

WIKI_API = "https://wiki.biligame.com/pq/api.php"
DEX_PAGE = "宝可梦图鉴"
NORMAL_PREFIX = "普通"  # full-size normal render
SHINY_PREFIX = "异色"  # full-size shiny render
POKEAPI = "https://pokeapi.co/api/v2/pokemon-species/{dex}/"
UA = "journey-icon-fetcher/1.0 (godot asset import; contact: local script)"

REPO = Path(__file__).resolve().parent.parent
POKEMON_DIR = REPO / "assets" / "pokemons"
OVERRIDES_PATH = Path(__file__).resolve().parent / "icon_form_overrides.json"

# Chinese form suffix on the wiki -> folder suffix used in assets/pokemons.
# Extend via tools/icon_form_overrides.json (same shape) rather than editing here.
FORM_MAP = {
    "": "",
    "阿罗拉地区": "alolan",
    "伽勒尔地区": "galarian",
    "帕底亚地区": "paldean",
    "洗翠地区": "hisuian",
    "复制体": "clone",
    "武装": "armored",
    "戴着帽子": "ash_cap",
    "探险装扮": "explorer",
    "璀璨": "radiant",
    "新娘": "bride",
    "新郎": "groom",
    "西装": "suit",
    "邮差": "postman",
    "万圣节": "halloween",
    "墨镜": "sunglasses",
    "花环": "garland",
    "嘻哈": "hiphop",
    "棒球帽": "baseball_cap",
    "绅士": "gentleman",
    "圣诞帽": "christmas_hat",
    "樱花": "sakura",
    "厚眼镜": "thick_glasses",
}


# --------------------------------------------------------------------------- #
# http
# --------------------------------------------------------------------------- #

HEADERS = {
    "User-Agent": UA,
    "Accept": "*/*",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    "Referer": "https://wiki.biligame.com/pq/",
}
# bilibili's WAF answers 567 when it thinks you're crawling too fast
RETRY_CODES = {408, 429, 500, 502, 503, 504, 520, 567}
BACKOFF = (3, 8, 20, 45, 90)


def _get(url: str, *, binary: bool = False, retries: int = 5):
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=45) as resp:
                data = resp.read()
            return data if binary else data.decode("utf-8")
        except urllib.error.HTTPError as exc:
            last = exc
            if exc.code not in RETRY_CODES:
                break
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            last = exc
        if attempt < retries - 1:
            wait = BACKOFF[min(attempt, len(BACKOFF) - 1)]
            print(f"    ... {last}; retrying in {wait}s", file=sys.stderr)
            time.sleep(wait)
    raise RuntimeError(f"failed to fetch {url}: {last}")


def api(**params) -> dict:
    params.setdefault("format", "json")
    return json.loads(_get(f"{WIKI_API}?{urllib.parse.urlencode(params)}"))


# --------------------------------------------------------------------------- #
# scrape the dex table
# --------------------------------------------------------------------------- #

# Deliberately markup-agnostic: instead of walking <tr>/<td> (which broke as soon
# as the real table deviated from the sample), scan the whole document for every
# button_icon_M<dex><form>.png reference and de-duplicate on (dex, form).
ICON_URL_RE = re.compile(
    r'https?://[^\s"\'<>]*?[Bb]utton_icon_M(\d+)([^."\'\s/<>]*)\.png',
)
TITLE_RE = re.compile(r'title="([^"]*)"')
THUMB_RE = re.compile(r"^(https?://.+?/images/[^/]+/)thumb/(.+?\.png)/\d+px-[^/]+$")


def full_size(url: str) -> str:
    """.../images/pq/thumb/8/8f/HASH.png/50px-Button_icon_M1.png
    ->  .../images/pq/8/8f/HASH.png"""
    m = THUMB_RE.match(url)
    return m.group(1) + m.group(2) if m else url


def parse_dex_html(markup: str) -> list[dict]:
    entries, seen = [], {}
    for m in ICON_URL_RE.finditer(markup):
        url = html.unescape(m.group(0))
        dex = int(m.group(1))
        # the form suffix is percent-encoded in the URL (复制体 -> %E5%A4%8D...)
        form_cn = urllib.parse.unquote(m.group(2))
        key = (dex, form_cn)

        # nearest preceding title="..." is the Chinese species name
        window = markup[max(0, m.start() - 400) : m.start()]
        titles = TITLE_RE.findall(window)
        name_cn = html.unescape(titles[-1]).strip() if titles else ""
        if name_cn.lower().endswith(".png"):
            name_cn = ""

        if key in seen:
            # srcset repeats the same icon at 1.5x/2x - keep the first, but let a
            # non-thumbnail (already full size) URL win
            if not THUMB_RE.match(url):
                seen[key]["icon_url"] = url
            if name_cn and not seen[key]["name_cn"]:
                seen[key]["name_cn"] = name_cn
            continue

        entry = {
            "dex": dex,
            "form_cn": form_cn,
            "name_cn": name_cn,
            "icon_url": full_size(url),
        }
        seen[key] = entry
        entries.append(entry)

    return sorted(entries, key=lambda e: (e["dex"], e["form_cn"]))


def scrape_dex(dump: Path | None = None) -> list[dict]:
    payload = api(action="parse", page=DEX_PAGE, prop="text", disablelimitreport=1)
    if "error" in payload:
        raise RuntimeError(f"wiki API error: {payload['error']}")
    markup = payload["parse"]["text"]["*"]
    if dump:
        dump.write_text(markup, encoding="utf-8")
        print(f"  dumped {len(markup):,} chars of page HTML to {dump}")

    entries = parse_dex_html(markup)
    if not entries:
        raise RuntimeError(
            "parsed 0 icons - the wiki page layout probably changed "
            "(re-run with --debug-dump page.html to inspect)"
        )
    return entries


def resolve_prefix(prefix: str, wanted: set[str]) -> dict[str, str]:
    """Map <prefix><dex><form>.png -> original URL.

    Enumerating a prefix costs 1-2 requests; asking for ~420 titles in batches
    of 40 costs 11 and reliably trips the WAF (HTTP 567).
    """
    found: dict[str, str] = {}
    cont = None
    for _ in range(20):  # hard stop, guards against a broken continue loop
        params = dict(
            action="query",
            list="allimages",
            aiprefix=prefix,
            ailimit=500,
            aiprop="url",
        )
        if cont:
            params["aicontinue"] = cont
        payload = api(**params)
        for img in payload.get("query", {}).get("allimages", []):
            if img["name"] in wanted:
                found[img["name"]] = img["url"]
        cont = payload.get("continue", {}).get("aicontinue")
        if not cont:
            break
        time.sleep(1.0)
    return found


def resolve_renders(entries: list[dict], prefix: str) -> dict[str, str]:
    wanted = {f"{prefix}{e['dex']}{e['form_cn']}.png" for e in entries}
    return resolve_prefix(prefix, wanted)


# --------------------------------------------------------------------------- #
# local folders
# --------------------------------------------------------------------------- #

FOLDER_RE = re.compile(r"^(\d{4})_([a-z0-9]+(?:_[a-z0-9]+)*)$")


def scan_folders() -> dict[int, list[Path]]:
    by_dex: dict[int, list[Path]] = {}
    if not POKEMON_DIR.is_dir():
        return by_dex
    for path in sorted(POKEMON_DIR.iterdir()):
        if not path.is_dir():
            continue
        m = FOLDER_RE.match(path.name)
        if m:
            by_dex.setdefault(int(m.group(1)), []).append(path)
    return by_dex


def english_name(dex: int, cache: dict[int, str], offline: bool) -> str | None:
    if dex in cache:
        return cache[dex]
    if offline:
        return None
    try:
        data = json.loads(_get(POKEAPI.format(dex=dex), retries=2))
        name = next(
            n["name"] for n in data["names"] if n["language"]["name"] == "en"
        )
        slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
        cache[dex] = slug
        return slug
    except Exception:
        return None


# --------------------------------------------------------------------------- #
# matching
# --------------------------------------------------------------------------- #

def match_entries(entries, by_dex, form_map, *, allow_create, offline, unknown_forms):
    """Return (plan, problems). plan items: {entry, folder, created}"""
    plan, problems = [], []
    name_cache: dict[int, str] = {}

    # seed the English-name cache from folders we already have
    for dex, folders in by_dex.items():
        base = min(folders, key=lambda p: len(p.name))
        name_cache[dex] = base.name[5:].split("_")[0]

    grouped: dict[int, list[dict]] = {}
    for e in entries:
        grouped.setdefault(e["dex"], []).append(e)

    for dex, group in sorted(grouped.items()):
        folders = list(by_dex.get(dex, []))
        taken: set[Path] = set()

        for e in group:
            form_cn = e["form_cn"]
            form_en = form_map.get(form_cn)
            if form_en is None:
                unknown_forms.setdefault(form_cn, [])
                unknown_forms[form_cn].append(f"#{dex} {e['name_cn']}")

            target = None
            if form_en is not None:
                want = f"{dex:04d}_" + "_".join(
                    p for p in [name_cache.get(dex, ""), form_en] if p
                )
                for f in folders:
                    if f in taken:
                        continue
                    suffix = f.name[5:]
                    base = suffix.split("_")[0]
                    rest = suffix[len(base) :].lstrip("_")
                    if rest == form_en:
                        target = f
                        break
                if target is None and form_en == "" and len(group) == 1 and folders:
                    target = next((f for f in folders if f not in taken), None)

            if target is not None:
                taken.add(target)
                plan.append({"entry": e, "folder": target, "created": False})

        # second pass: unique leftover on both sides -> pair them
        unplanned = [e for e in group if not any(p["entry"] is e for p in plan)]
        leftover = [f for f in folders if f not in taken]
        if len(unplanned) == 1 and len(leftover) == 1:
            plan.append({"entry": unplanned[0], "folder": leftover[0], "created": False})
            taken.add(leftover[0])
            unplanned = []

        for e in unplanned:
            who = f"#{dex} {e['name_cn']} ({e['form_cn'] or 'base form'})"
            form_en = form_map.get(e["form_cn"])

            if form_en is None:
                problems.append(
                    f"{who}: unmapped form suffix {e['form_cn']!r} - "
                    f"add it to {OVERRIDES_PATH.name} and re-run"
                )
                continue
            if folders:
                # this dex already has folders, none of them fit -> don't guess,
                # creating a sibling here is almost always wrong
                problems.append(
                    f"{who}: no folder matched; existing folders for this dex are "
                    + ", ".join(f.name for f in folders)
                )
                continue

            species = name_cache.get(dex) or english_name(dex, name_cache, offline)
            if not species:
                problems.append(f"{who}: no local folder and no English name available")
                continue
            name = f"{dex:04d}_{species}" + (f"_{form_en}" if form_en else "")
            folder = POKEMON_DIR / name
            if folder.exists():
                plan.append({"entry": e, "folder": folder, "created": False})
            elif allow_create:
                plan.append({"entry": e, "folder": folder, "created": True})
            else:
                problems.append(f"{who}: would need new folder {name} (--no-create set)")

    matched = {p["folder"] for p in plan}
    for dex, folders in sorted(by_dex.items()):
        for f in folders:
            if f not in matched:
                problems.append(f"{f.name}: no wiki row matched this folder")

    return plan, problems


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true", help="print the plan, write nothing")
    ap.add_argument("--force", action="store_true", help="re-download files that exist")
    ap.add_argument(
        "--icons-only", action="store_true", help="only icon.png, no previews"
    )
    ap.add_argument(
        "--no-shiny", action="store_true", help="skip preview_shiny.png"
    )
    ap.add_argument("--no-create", action="store_true", help="never create new folders")
    ap.add_argument(
        "--offline-names",
        action="store_true",
        help="don't call PokeAPI for English names of unknown dex numbers",
    )
    ap.add_argument(
        "--delay",
        type=float,
        default=0.25,
        metavar="SECONDS",
        help="pause between downloads (default 0.25; raise if you get HTTP 567)",
    )
    ap.add_argument(
        "--debug-dump",
        metavar="FILE",
        help="save the raw wiki page HTML here (for diagnosing parse failures)",
    )
    args = ap.parse_args()

    form_map = dict(FORM_MAP)
    if OVERRIDES_PATH.exists():
        extra = json.loads(OVERRIDES_PATH.read_text(encoding="utf-8"))
        form_map.update({k: v for k, v in extra.items() if v})
        print(f"loaded {len(extra)} form override(s) from {OVERRIDES_PATH.name}")

    print(f"fetching dex table from {DEX_PAGE} ...")
    entries = scrape_dex(Path(args.debug_dump) if args.debug_dump else None)
    forms = sum(1 for e in entries if e["form_cn"])
    print(f"  {len(entries)} icons ({len(entries) - forms} base, {forms} alt forms)")
    if len(entries) < 100:
        print(
            "  !! that looks far too low - the page layout may have changed. "
            "Re-run with --debug-dump page.html and check the markup.",
            file=sys.stderr,
        )

    renders: dict[str, dict[str, str]] = {NORMAL_PREFIX: {}, SHINY_PREFIX: {}}
    for prefix, skip, what in (
        (NORMAL_PREFIX, args.icons_only, "normal previews"),
        (SHINY_PREFIX, args.icons_only or args.no_shiny, "shiny previews"),
    ):
        if skip:
            continue
        print(f"resolving {what} ({prefix}...) ...")
        try:
            renders[prefix] = resolve_renders(entries, prefix)
            print(f"  {len(renders[prefix])} available")
        except RuntimeError as exc:
            print(f"  !! {what} lookup failed ({exc}) - skipping", file=sys.stderr)

    by_dex = scan_folders()
    print(f"found {sum(len(v) for v in by_dex.values())} local pokemon folders")

    unknown_forms: dict[str, list[str]] = {}
    plan, problems = match_entries(
        entries,
        by_dex,
        form_map,
        allow_create=not args.no_create,
        offline=args.offline_names,
        unknown_forms=unknown_forms,
    )

    stats = {
        "icon.png": 0,
        "preview.png": 0,
        "preview_shiny.png": 0,
        "skipped": 0,
        "created": 0,
        "failed": 0,
        "migrated": 0,
    }
    consecutive_failures = 0
    aborted = False

    # earlier versions of this script saved the 异色 render as icon_shiny.png,
    # which was wrong - it's a 512x512 preview, not an icon. Rename in place so
    # a re-run doesn't leave both names lying around.
    for stale in sorted(POKEMON_DIR.glob("*/icon_shiny.png")):
        target = stale.with_name("preview_shiny.png")
        if args.dry_run:
            print(f"  [dry] rename {stale.parent.name}/icon_shiny.png -> preview_shiny.png")
            stats["migrated"] += 1
        elif target.exists():
            stale.unlink()
            stats["migrated"] += 1
        else:
            stale.rename(target)
            stats["migrated"] += 1
            print(f"  renamed {stale.parent.name}/icon_shiny.png -> preview_shiny.png")

    for item in plan:
        if aborted:
            break
        e, folder = item["entry"], item["folder"]
        label = f"#{e['dex']:04d} {e['name_cn']}{'/' + e['form_cn'] if e['form_cn'] else ''}"

        jobs = [("icon.png", e["icon_url"])]
        for prefix, filename in (
            (NORMAL_PREFIX, "preview.png"),
            (SHINY_PREFIX, "preview_shiny.png"),
        ):
            key = f"{prefix}{e['dex']}{e['form_cn']}.png"
            if key in renders[prefix]:
                jobs.append((filename, renders[prefix][key]))

        for filename, url in jobs:
            dest = folder / filename
            if dest.exists() and not args.force:
                stats["skipped"] += 1
                continue
            if args.dry_run:
                tag = " (new folder)" if item["created"] else ""
                print(f"  [dry] {label} -> {folder.name}/{filename}{tag}")
                stats[filename] += 1
                continue
            try:
                blob = _get(url, binary=True)
                consecutive_failures = 0
            except RuntimeError as exc:
                print(f"  !! {label}: {exc}", file=sys.stderr)
                stats["failed"] += 1
                consecutive_failures += 1
                if consecutive_failures >= 8:
                    print(
                        "\n!! 8 downloads failed in a row - the wiki is probably "
                        "rate-limiting you. Stopping.\n"
                        "   Everything downloaded so far is saved; just re-run "
                        "later and it will pick up where it left off.",
                        file=sys.stderr,
                    )
                    aborted = True
                    break
                continue
            if not folder.exists():
                folder.mkdir(parents=True)
                stats["created"] += 1
                print(f"  + created {folder.name}")
            dest.write_bytes(blob)
            stats[filename] += 1
            print(f"  {folder.name}/{filename}  ({len(blob):,} bytes)")
            time.sleep(args.delay)

    print("\n--- summary ---")
    print(f"icons:            {stats['icon.png']}")
    print(f"previews:         {stats['preview.png']}")
    print(f"shiny previews:   {stats['preview_shiny.png']}")
    print(f"skipped:          {stats['skipped']} (already present; use --force to refresh)")
    print(f"renamed old files:{stats['migrated']}")
    print(f"new folders:      {stats['created']}")
    print(f"failed:           {stats['failed']}")
    if aborted:
        print("\nSTOPPED EARLY - re-run to resume.")

    if unknown_forms:
        print("\nunmapped wiki form suffixes (add them to icon_form_overrides.json):")
        for form_cn, who in sorted(unknown_forms.items()):
            print(f"  {form_cn!r}  <- {', '.join(who[:4])}")
        if not args.dry_run:
            stub = {}
            if OVERRIDES_PATH.exists():
                stub = json.loads(OVERRIDES_PATH.read_text(encoding="utf-8"))
            for form_cn in unknown_forms:
                stub.setdefault(form_cn, "")
            OVERRIDES_PATH.write_text(
                json.dumps(stub, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            print(f"  -> wrote stubs to {OVERRIDES_PATH.name}; fill in the English "
                  "suffixes and re-run")

    if problems:
        print(f"\nunmatched ({len(problems)}):")
        for p in problems:
            print(f"  {p}")

    return 1 if stats["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())

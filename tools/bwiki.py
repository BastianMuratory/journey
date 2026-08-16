#!/usr/bin/env python3
"""
Shared helpers for scraping the Pokemon Quest BWIKI (wiki.biligame.com/pq).

Used by download_attack_icons.py and download_recipe_icons.py. Stdlib only.

The one non-obvious thing in here is WAF handling: bilibili answers HTTP 567
when it decides you're crawling, so every request retries with a long backoff,
batched API queries go out as POST (no 3KB URLs), and the download loop stops
itself after 8 consecutive failures instead of hammering the site.
"""

from __future__ import annotations

import json
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

WIKI_API = "https://wiki.biligame.com/pq/api.php"
REPO = Path(__file__).resolve().parent.parent
ICONS_DIR = REPO / "assets" / "icons"

UA = "journey-icon-fetcher/1.0 (godot asset import; contact: local script)"
HEADERS = {
    "User-Agent": UA,
    "Accept": "*/*",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    "Referer": "https://wiki.biligame.com/pq/",
}
RETRY_CODES = {408, 429, 500, 502, 503, 504, 520, 567}
BACKOFF = (3, 8, 20, 45, 90)


# --------------------------------------------------------------------------- #
# http
# --------------------------------------------------------------------------- #

def fetch(url: str, *, data: bytes | None = None, binary: bool = False, retries: int = 5):
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, data=data, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=45) as resp:
                blob = resp.read()
            return blob if binary else blob.decode("utf-8")
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
    """GET for small queries."""
    params.setdefault("format", "json")
    return json.loads(fetch(f"{WIKI_API}?{urllib.parse.urlencode(params)}"))


def api_post(**params) -> dict:
    """POST for anything with a long payload (batched titles, ask queries).

    Keeps URLs short, which both avoids server URL limits and looks far less
    like a crawler than a 3KB query string.
    """
    params.setdefault("format", "json")
    body = urllib.parse.urlencode(params).encode("utf-8")
    return json.loads(fetch(WIKI_API, data=body))


# --------------------------------------------------------------------------- #
# wiki queries
# --------------------------------------------------------------------------- #

def category_members(category: str, *, pause: float = 0.5) -> list[str]:
    """All page titles in 分类:<category>."""
    titles, cont = [], None
    for _ in range(40):
        params = dict(
            action="query",
            list="categorymembers",
            cmtitle=f"分类:{category}",
            cmlimit=500,
            cmnamespace=0,
        )
        if cont:
            params["cmcontinue"] = cont
        payload = api(**params)
        titles += [p["title"] for p in payload.get("query", {}).get("categorymembers", [])]
        cont = payload.get("continue", {}).get("cmcontinue")
        if not cont:
            break
        time.sleep(pause)
    return titles


def ask(query: str) -> dict[str, dict]:
    """Semantic MediaWiki #ask, returned as {page_title: {property: [values]}}."""
    payload = api_post(action="ask", query=query)
    if "error" in payload:
        raise RuntimeError(f"ask failed: {payload['error']}")
    results = payload.get("query", {}).get("results", {})
    return {name: row.get("printouts", {}) for name, row in results.items()}


def one(printouts: dict, key: str, default: str = "") -> str:
    vals = printouts.get(key) or []
    if not vals:
        return default
    val = vals[0]
    if isinstance(val, dict):  # SMW wraps page-valued properties
        val = val.get("fulltext", "")
    return str(val).strip()


def resolve_files(names, *, pause: float = 1.0, batch: int = 50) -> dict[str, str]:
    """{'寄生种子.png': 'https://patchwiki.../HASH.png'} for File:<name> pages.

    POSTed in batches of 50; the previous version of this code sent 40 titles
    per GET and tripped the WAF on the fourth request.
    """
    names = sorted(set(names))
    found: dict[str, str] = {}
    for i in range(0, len(names), batch):
        chunk = names[i : i + batch]
        payload = api_post(
            action="query",
            prop="imageinfo",
            iiprop="url",
            titles="|".join(f"File:{n}" for n in chunk),
        )
        for page in payload.get("query", {}).get("pages", {}).values():
            info = page.get("imageinfo")
            if info:
                found[page["title"].split(":", 1)[-1]] = info[0]["url"]
        if i + batch < len(names):
            time.sleep(pause)
    return found


def page_wikitext(title: str) -> str:
    payload = api(action="parse", page=title, prop="wikitext")
    if "error" in payload:
        raise RuntimeError(f"wiki API error for {title}: {payload['error']}")
    return payload["parse"]["wikitext"]["*"]


# --------------------------------------------------------------------------- #
# naming
# --------------------------------------------------------------------------- #

def slugify(text: str) -> str:
    """'Mega Drain' -> 'mega_drain'. Returns '' if nothing ASCII survives."""
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


POKEAPI_CSV = "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/{}"
ZH_HANS_LANGUAGE_ID = "12"


def _csv_rows(text: str):
    """Minimal CSV reader - PokeAPI's move files have no embedded commas/quotes
    in the columns we read, but fall back to csv.reader for safety."""
    import csv
    import io

    return list(csv.reader(io.StringIO(text)))


def chinese_move_names(cache_path: Path) -> dict[str, str]:
    """{'超级吸取': 'mega_drain'} built from PokeAPI's CSV data dump.

    Two requests instead of ~900 hits on /api/v2/move/<id>/, cached to disk so
    later runs are free.
    """
    if cache_path.exists():
        return json.loads(cache_path.read_text(encoding="utf-8"))

    print("  building Chinese -> English move map from PokeAPI CSVs ...")
    moves = _csv_rows(fetch(POKEAPI_CSV.format("moves.csv")))
    names = _csv_rows(fetch(POKEAPI_CSV.format("move_names.csv")))

    head = moves[0]
    id_i, ident_i = head.index("id"), head.index("identifier")
    identifiers = {row[id_i]: row[ident_i] for row in moves[1:] if len(row) > ident_i}

    head = names[0]
    mid_i = head.index("move_id")
    lang_i = head.index("local_language_id")
    name_i = head.index("name")

    mapping: dict[str, str] = {}
    for row in names[1:]:
        if len(row) <= name_i or row[lang_i] != ZH_HANS_LANGUAGE_ID:
            continue
        ident = identifiers.get(row[mid_i])
        if ident:
            mapping[row[name_i].strip()] = ident.replace("-", "_")

    cache_path.write_text(
        json.dumps(mapping, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"  cached {len(mapping)} move names to {cache_path.name}")
    return mapping


def load_overrides(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    return {k: v for k, v in json.loads(path.read_text(encoding="utf-8")).items() if v}


def save_override_stubs(path: Path, chinese_names) -> int:
    """Add blank entries for anything we couldn't name in English, so the user
    has one obvious file to fill in."""
    stub = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    added = 0
    for name in sorted(chinese_names):
        if name not in stub:
            stub[name] = ""
            added += 1
    if added:
        path.write_text(
            json.dumps(stub, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return added


# --------------------------------------------------------------------------- #
# download
# --------------------------------------------------------------------------- #

class Downloader:
    def __init__(self, *, dry_run=False, force=False, delay=0.25):
        self.dry_run, self.force, self.delay = dry_run, force, delay
        self.saved = self.skipped = self.failed = self.missing = 0
        self.retired = 0
        self._streak = 0
        self.aborted = False

    def _retire_old_names(self, dest: Path, number: str | None) -> None:
        """Drop earlier files for the same item under a different name.

        Filling in an English override renames 01.png -> 01_tiny_mushroom.png;
        without this the numbered file would linger and you'd import both.
        """
        if not number or not dest.parent.is_dir():
            return
        pattern = re.compile(rf"^{re.escape(number)}(_.+)?\.png$")
        for other in sorted(dest.parent.glob("*.png")):
            if other.name != dest.name and pattern.match(other.name):
                if self.dry_run:
                    print(f"  [dry] remove stale {other.parent.name}/{other.name}")
                else:
                    other.unlink()
                    print(f"  removed stale {other.parent.name}/{other.name}")
                self.retired += 1

    def get(self, url: str, dest: Path, label: str, number: str | None = None) -> bool:
        self._retire_old_names(dest, number)
        if dest.exists() and not self.force:
            self.skipped += 1
            return True
        if self.dry_run:
            print(f"  [dry] {label} -> {dest.parent.name}/{dest.name}")
            self.saved += 1
            return True
        try:
            blob = fetch(url, binary=True)
        except RuntimeError as exc:
            print(f"  !! {label}: {exc}", file=sys.stderr)
            self.failed += 1
            self._streak += 1
            if self._streak >= 8:
                print(
                    "\n!! 8 downloads failed in a row - the wiki is rate-limiting "
                    "you. Stopping; re-run later to resume.",
                    file=sys.stderr,
                )
                self.aborted = True
            return False
        self._streak = 0
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(blob)
        self.saved += 1
        print(f"  {dest.parent.name}/{dest.name}  ({len(blob):,} bytes)")
        time.sleep(self.delay)
        return True

    def report(self, title: str) -> None:
        print(f"\n--- {title} ---")
        print(f"downloaded:  {self.saved}")
        print(f"skipped:     {self.skipped} (already present; --force to refresh)")
        print(f"no image:    {self.missing}")
        print(f"renamed:     {self.retired} (stale name removed)")
        print(f"failed:      {self.failed}")
        if self.aborted:
            print("STOPPED EARLY - re-run to resume.")


def write_manifest(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"  wrote {path.parent.name}/{path.name} ({len(rows)} entries)")

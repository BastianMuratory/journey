import re
import time
import shutil
import zipfile
from pathlib import Path
from urllib.parse import urlparse, parse_qs

import requests


# ============================================================
# CONFIG
# ============================================================

INPUT_FILE = "assets.txt"
OUTPUT_DIR = Path("pokemon_quest_assets")
ZIP_DIR = OUTPUT_DIR / "_zips"

DELAY = 0.5
TIMEOUT = 60

# Set to True if you want to keep the downloaded ZIP files.
KEEP_ZIPS = False


# ============================================================
# SETUP
# ============================================================

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
ZIP_DIR.mkdir(parents=True, exist_ok=True)

session = requests.Session()

session.headers.update({
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/139.0 Safari/537.36"
    ),
    "Accept": "*/*",
})


# ============================================================
# HELPERS
# ============================================================

def sanitize_filename(name):
    """
    Make a name safe for Windows/Linux/macOS filenames.
    """
    name = re.sub(r'[<>:"/\\|?*]', "_", name)
    name = re.sub(r"\s+", " ", name)
    return name.strip(" .")


def parse_asset_line(line):
    """
    Parses:

    1/479  #0001 Bulbasaur ->
    https://models.spriters-resource.com/mobile/pokemonquest/asset/308542/
    """

    pattern = re.compile(
        r"^\s*(\d+)/479\s+(.+?)\s+->\s+(https?://\S+)\s*$"
    )

    match = pattern.match(line)

    if not match:
        return None

    index = int(match.group(1))
    name = match.group(2).strip()
    page_url = match.group(3).strip()

    # Extract asset ID from:
    # .../asset/308542/
    id_match = re.search(r"/asset/(\d+)/?", page_url)

    if not id_match:
        return None

    asset_id = id_match.group(1)

    return {
        "index": index,
        "name": name,
        "page_url": page_url,
        "asset_id": asset_id,
    }


def make_zip_url(asset_id, updated=None):
    """
    Converts an asset ID such as:

        308542

    into:

        https://models.spriters-resource.com/media/assets/305/308542.zip

    The folder is calculated using the first digits of the asset ID.

    For the current Models Resource URL structure, IDs in the
    308xxx range are stored under /media/assets/305/.
    """

    # The Spriters Resource CDN uses an asset bucket.
    #
    # For the asset list supplied by the user, the bucket can be
    # obtained from the asset ID using this formula.

    asset_number = int(asset_id)

    bucket = (asset_number // 1000) - 3

    if bucket < 1:
        bucket = 1

    url = (
        f"https://models.spriters-resource.com/"
        f"media/assets/{bucket}/{asset_id}.zip"
    )

    if updated:
        url += f"?updated={updated}"

    return url


def find_zip_url_from_page(page_url, asset_id):
    """
    Try to find the real ZIP URL from the asset page.

    If the page contains a direct .zip URL, use it.

    Otherwise fall back to the known CDN URL.
    """

    try:
        response = session.get(
            page_url,
            timeout=TIMEOUT
        )

        response.raise_for_status()

        html = response.text

        # Look for a direct .zip URL.
        matches = re.findall(
            r'https?://[^"\'>\s]+?\.zip(?:\?[^"\'>\s]*)?',
            html,
            flags=re.IGNORECASE
        )

        if matches:
            return matches[0]

        # Sometimes URLs are HTML escaped.
        html = html.replace("&amp;", "&")

        matches = re.findall(
            r'https?://[^"\'>\s]+?\.zip(?:\?[^"\'>\s]*)?',
            html,
            flags=re.IGNORECASE
        )

        if matches:
            return matches[0]

    except Exception as e:
        print(f"    Could not read asset page: {e}")

    # Fallback.
    return make_zip_url(asset_id)


def safe_extract(zip_path, destination):
    """
    Safely extract a ZIP without allowing files to escape
    the destination directory.
    """

    destination = destination.resolve()

    with zipfile.ZipFile(zip_path, "r") as z:
        for member in z.infolist():

            member_path = (destination / member.filename).resolve()

            if not str(member_path).startswith(
                str(destination) + str(Path("/"))
            ):
                raise RuntimeError(
                    f"Unsafe ZIP path detected: {member.filename}"
                )

        z.extractall(destination)


def download_file(url, destination):
    """
    Stream a file to disk.
    """

    with session.get(
        url,
        stream=True,
        timeout=TIMEOUT
    ) as response:

        response.raise_for_status()

        with open(destination, "wb") as f:
            for chunk in response.iter_content(
                chunk_size=1024 * 1024
            ):
                if chunk:
                    f.write(chunk)


# ============================================================
# LOAD ASSETS
# ============================================================

print(f"Reading {INPUT_FILE}...")

with open(INPUT_FILE, "r", encoding="utf-8") as f:
    lines = f.readlines()

assets = []

for line in lines:
    asset = parse_asset_line(line)

    if asset:
        assets.append(asset)

print(f"Found {len(assets)} assets.")


# ============================================================
# DOWNLOAD + EXTRACT
# ============================================================

successful = 0
failed = 0
skipped = 0

for number, asset in enumerate(assets, 1):

    index = asset["index"]
    name = asset["name"]
    asset_id = asset["asset_id"]
    page_url = asset["page_url"]

    safe_name = sanitize_filename(name)

    # Folder:
    #
    # pokemon_quest_assets/
    #   0001_Bulbasaur/
    #   0002_Ivysaur/
    #   ...

    asset_folder = (
        OUTPUT_DIR /
        f"{index:04d}_{safe_name}"
    )

    zip_path = (
        ZIP_DIR /
        f"{index:04d}_{asset_id}.zip"
    )

    print()
    print("=" * 70)
    print(f"[{number}/{len(assets)}] {name}")
    print(f"Asset ID: {asset_id}")

    # --------------------------------------------------------
    # Already extracted?
    # --------------------------------------------------------

    if asset_folder.exists() and any(asset_folder.iterdir()):

        print("    Already extracted - skipping.")

        skipped += 1
        continue

    # --------------------------------------------------------
    # Find ZIP
    # --------------------------------------------------------

    print("    Finding ZIP...")

    zip_url = find_zip_url_from_page(
        page_url,
        asset_id
    )

    print(f"    ZIP: {zip_url}")

    # --------------------------------------------------------
    # Download
    # --------------------------------------------------------

    try:

        if not zip_path.exists():

            print("    Downloading...")

            download_file(
                zip_url,
                zip_path
            )

            print(
                f"    Downloaded: "
                f"{zip_path.stat().st_size / 1024 / 1024:.2f} MB"
            )

        else:

            print("    ZIP already downloaded.")

        # ----------------------------------------------------
        # Verify ZIP
        # ----------------------------------------------------

        if not zipfile.is_zipfile(zip_path):

            raise RuntimeError(
                "Downloaded file is not a valid ZIP."
            )

        # ----------------------------------------------------
        # Extract
        # ----------------------------------------------------

        asset_folder.mkdir(
            parents=True,
            exist_ok=True
        )

        print("    Extracting...")

        safe_extract(
            zip_path,
            asset_folder
        )

        print(
            f"    Extracted to: {asset_folder}"
        )

        successful += 1

        # ----------------------------------------------------
        # Delete ZIP
        # ----------------------------------------------------

        if not KEEP_ZIPS:

            zip_path.unlink(missing_ok=True)

        time.sleep(DELAY)

    except Exception as e:

        print(
            f"    ERROR: {type(e).__name__}: {e}"
        )

        failed += 1


# ============================================================
# SUMMARY
# ============================================================

print()
print("=" * 70)
print("FINISHED")
print("=" * 70)

print(f"Successful : {successful}")
print(f"Skipped    : {skipped}")
print(f"Failed     : {failed}")
print(f"Total      : {len(assets)}")

print()
print(f"Output: {OUTPUT_DIR.resolve()}")

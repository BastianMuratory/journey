import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin

GAME_URL = "https://models.spriters-resource.com/mobile/pokemonquest/"

s = requests.Session()
s.headers.update({
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) "
                  "Chrome/138.0 Safari/537.36"
})

r = s.get(GAME_URL)
r.raise_for_status()

soup = BeautifulSoup(r.text, "html.parser")

assets = []

for a in soup.select('a[href*="/mobile/pokemonquest/asset/"]'):
    url = urljoin(GAME_URL, a["href"])
    name = a.get_text(" ", strip=True)

    # Remove the material-icon text
    name = name.replace("view_in_ar", "").strip()

    if url not in [x[0] for x in assets]:
        assets.append((url, name))

print(f"Found {len(assets)} assets")

for i, (url, name) in enumerate(assets, 1):
    print(f"{i:3}/{len(assets)}  {name} -> {url}")

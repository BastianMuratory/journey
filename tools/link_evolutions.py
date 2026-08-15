#!/usr/bin/env python3
"""Fill in `evolves_into` on every data/pokemon/*.tres that has a target.

Source of truth is EVOLVES_FROM below: child dex -> parent dex, transcribed from
PokeAPI's pokemon_species.csv (evolves_from_species_id). It is inverted here into
parent -> children, which is the direction PokemonData stores.

`evolves_into` is an Array[PokemonData], so branches are kept whole: Eevee gets
all eight of its targets, Kirlia both of hers. They come out in dex order, and
gameplay that only wants one should call PokemonData.first_evolution().

Forms keep their own suffix across the evolution when a file for it exists --
Alolan Vulpix -> Alolan Ninetales, Hisuian Zorua -> Hisuian Zoroark, sunglasses
Exeggcute -> sunglasses Exeggutor. Otherwise they fall back to the base form, so
Ash-cap Pikachu evolves into an ordinary Raichu.

Rewriting is idempotent: an existing `evolves_into` and the ext_resources that
only it referenced are stripped before the new one is written, so re-running
never leaves duplicates behind. Files that already have a link are skipped
unless --overwrite is passed. `mega_evolves_into` is never touched.

    python tools/link_evolutions.py             # plan: print what would change
    python tools/link_evolutions.py --apply     # write it
    python tools/link_evolutions.py --apply --overwrite   # redo existing links
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DATA_DIR = "data/pokemon"

# --- child dex : parent dex -------------------------------------------------
# From PokeAPI pokemon_species.csv. Babies are included (25:172 = Pikachu from
# Pichu), which is harmless: a parent with no file in the project is skipped.
_PAIRS = """
2:1 3:2 5:4 6:5 8:7 9:8 11:10 12:11 14:13 15:14 17:16 18:17 20:19 22:21 24:23
25:172 26:25 28:27 30:29 31:30 33:32 34:33 35:173 36:35 38:37 39:174 40:39
42:41 44:43 45:44 47:46 49:48 51:50 53:52 55:54 57:56 59:58 61:60 62:61 64:63
65:64 67:66 68:67 70:69 71:70 73:72 75:74 76:75 78:77 80:79 82:81 85:84 87:86
89:88 91:90 93:92 94:93 97:96 99:98 101:100 103:102 105:104 106:236 107:236
110:109 112:111 113:440 117:116 119:118 121:120 122:439 124:238 125:239 126:240
130:129 134:133 135:133 136:133 139:138 141:140 143:446 148:147 149:148 153:152
154:153 156:155 157:156 159:158 160:159 162:161 164:163 166:165 168:167 169:42
171:170 176:175 178:177 180:179 181:180 182:44 184:183 185:438 186:61 188:187
189:188 192:191 195:194 196:133 197:133 199:79 202:360 205:204 208:95 210:209
212:123 217:216 219:218 221:220 224:223 226:458 229:228 230:117 232:231 233:137
237:236 242:113 247:246 248:247 253:252 254:253 256:255 257:256 259:258 260:259
262:261 264:263 266:265 267:266 268:265 269:268 271:270 272:271 274:273 275:274
277:276 279:278 281:280 282:281 284:283 286:285 288:287 289:288 291:290 292:290
294:293 295:294 297:296 301:300 305:304 306:305 308:307 310:309 315:406 317:316
319:318 321:320 323:322 326:325 329:328 330:329 332:331 334:333 340:339 342:341
344:343 346:345 348:347 350:349 354:353 356:355 358:433 362:361 364:363 365:364
367:366 368:366 372:371 373:372 375:374 376:375 388:387 389:388 391:390 392:391
394:393 395:394 397:396 398:397 400:399 402:401 404:403 405:404 407:315 409:408
411:410 413:412 414:412 416:415 419:418 421:420 423:422 424:190 426:425 428:427
429:200 430:198 432:431 435:434 437:436 444:443 445:444 448:447 450:449 452:451
454:453 457:456 460:459 461:215 462:82 463:108 464:112 465:114 466:125 467:126
468:176 469:193 470:133 471:133 472:207 473:221 474:233 475:281 476:299 477:356
478:361 496:495 497:496 499:498 500:499 502:501 503:502 505:504 507:506 508:507
510:509 512:511 514:513 516:515 518:517 520:519 521:520 523:522 525:524 526:525
528:527 530:529 533:532 534:533 536:535 537:536 541:540 542:541 544:543 545:544
547:546 549:548 552:551 553:552 555:554 558:557 560:559 563:562 565:564 567:566
569:568 571:570 573:572 575:574 576:575 578:577 579:578 581:580 583:582 584:583
586:585 589:588 591:590 593:592 596:595 598:597 600:599 601:600 603:602 604:603
606:605 608:607 609:608 611:610 612:611 614:613 617:616 620:619 623:622 625:624
628:627 630:629 634:633 635:634 637:636 651:650 652:651 654:653 655:654 657:656
658:657 660:659 662:661 663:662 665:664 666:665 668:667 670:669 671:670 673:672
675:674 678:677 680:679 681:680 683:682 685:684 687:686 689:688 691:690 693:692
695:694 697:696 699:698 700:133 705:704 706:705 709:708 711:710 713:712 715:714
723:722 724:723 726:725 727:726 729:728 730:729 732:731 733:732 735:734 737:736
738:737 740:739 743:742 745:744 748:747 750:749 752:751 754:753 756:755 758:757
760:759 762:761 763:762 770:769 879:878 886:885 887:886 925:924 1000:999
"""

EVOLVES_FROM: dict[int, int] = {
    int(child): int(parent)
    for child, parent in (pair.split(":") for pair in _PAIRS.split())
}

# Links keyed on a specific file rather than a dex number. These win outright.
MANUAL_LINKS: dict[str, list[str]] = {
    # Paldean Wooper is its own species upstream, so the dex table can't see it.
    "0194_wooper_paldean": ["0980_clodsire"],
    # Base camp evolves Sandile straight into Krookodile for the demo. Skipping
    # Krokorok is deliberate -- drop this entry if you want the real line.
    "0551_sandile": ["0553_krookodile"],
}

TRES_HEADER = re.compile(
    r'^\[gd_resource type="Resource"(?P<mid>.*?)load_steps=(?P<steps>\d+)(?P<rest>.*)\]$'
)
EXT_RESOURCE = re.compile(r'^\[ext_resource .*? id="(?P<id>[^"]+)"\]$')
UID_IN_HEADER = re.compile(r'uid="(?P<uid>uid://[^"]+)"')
EVOLVES_LINE = re.compile(r"^evolves_into = .*$", re.M)


class Species:
    """One .tres on disk, parsed just enough to rewrite it."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.id = path.stem
        self.text = path.read_text(encoding="utf-8")
        self.dex = _leading_int(self.id)

    @property
    def uid(self) -> str | None:
        found = UID_IN_HEADER.search(self.text.splitlines()[0])
        return found.group("uid") if found else None

    @property
    def script_ext_id(self) -> str:
        """The ext_resource id of pokemon_data.gd, needed to type the array."""
        found = re.search(
            r'^\[ext_resource type="Script" .*?id="([^"]+)"\]$', self.text, re.M
        )
        if found is None:
            raise ValueError(f"{self.path.name}: no Script ext_resource")
        return found.group(1)

    @property
    def has_evolution(self) -> bool:
        return EVOLVES_LINE.search(self.text) is not None


def _leading_int(name: str) -> int:
    digits = ""
    for char in name:
        if not char.isdigit():
            break
        digits += char
    return int(digits) if digits else -1


def _suffix(species_id: str, base_id: str) -> str:
    """The part of an id that marks it as a form, e.g. "alolan". "" for a base."""
    if species_id == base_id:
        return ""
    return species_id[len(base_id):].lstrip("_")


def load_species(root: Path) -> dict[str, Species]:
    data_dir = root / DATA_DIR
    if not data_dir.is_dir():
        sys.exit(f"error: {DATA_DIR} not found -- run this from the project root")
    return {p.stem: Species(p) for p in sorted(data_dir.glob("*.tres"))}


def index_by_dex(species: dict[str, Species]) -> dict[int, list[str]]:
    """dex -> ids, base form first. Same shortest-id-wins rule as PokemonRegistry."""
    by_dex: dict[int, list[str]] = {}
    for sid, entry in species.items():
        by_dex.setdefault(entry.dex, []).append(sid)
    for ids in by_dex.values():
        ids.sort(key=lambda s: (len(s), s))
    return by_dex


def build_targets() -> dict[int, list[int]]:
    """parent dex -> every dex it can evolve into, ascending."""
    targets: dict[int, list[int]] = {}
    for child, parent in EVOLVES_FROM.items():
        targets.setdefault(parent, []).append(child)
    for children in targets.values():
        children.sort()
    return targets


def resolve(sid: str, species: dict[str, Species], by_dex: dict[int, list[str]],
            targets: dict[int, list[int]]) -> list[str]:
    """Every id `sid` should evolve into, in dex order."""
    if sid in MANUAL_LINKS:
        return [t for t in MANUAL_LINKS[sid] if t in species]

    entry = species[sid]
    base_here = by_dex[entry.dex][0]
    suffix = _suffix(sid, base_here)

    out: list[str] = []
    for target_dex in targets.get(entry.dex, []):
        candidates = by_dex.get(target_dex)
        if not candidates:
            continue  # no model for that evolution in this project
        chosen = candidates[0]
        if suffix:
            # Keep the form across the evolution when there is a file for it.
            for candidate in candidates:
                if _suffix(candidate, candidates[0]) == suffix:
                    chosen = candidate
                    break
        if chosen != sid and chosen not in out:
            out.append(chosen)
    return out


def strip_existing(lines: list[str]) -> list[str]:
    """Remove any evolves_into and the ext_resources only it referenced."""
    keep = [line for line in lines if not line.startswith("evolves_into = ")]
    if len(keep) == len(lines):
        return keep

    orphaned = set()
    for line in lines:
        if line.startswith("evolves_into = "):
            orphaned.update(re.findall(r'ExtResource\("([^"]+)"\)', line))
    still_used = set()
    for line in keep:
        if not EXT_RESOURCE.match(line):
            still_used.update(re.findall(r'ExtResource\("([^"]+)"\)', line))

    return [
        line for line in keep
        if not ((m := EXT_RESOURCE.match(line))
                and m.group("id") in orphaned - still_used)
    ]


def link(entry: Species, targets: list[Species]) -> str:
    """Return `entry`'s text with evolves_into pointing at `targets`."""
    lines = strip_existing(entry.text.splitlines())

    used_ids = [m.group("id") for line in lines if (m := EXT_RESOURCE.match(line))]
    next_index = max((_leading_int(i) for i in used_ids), default=0) + 1

    ext_ids = []
    new_lines = []
    for offset, target in enumerate(targets):
        ext_id = f"{next_index + offset}_evo"
        ext_ids.append(ext_id)
        uid_attr = f'uid="{target.uid}" ' if target.uid else ""
        new_lines.append(
            f'[ext_resource type="Resource" {uid_attr}'
            f'path="res://{DATA_DIR}/{target.id}.tres" id="{ext_id}"]'
        )

    last_ext = max(i for i, line in enumerate(lines) if EXT_RESOURCE.match(line))
    lines[last_ext + 1:last_ext + 1] = new_lines

    header = TRES_HEADER.match(lines[0])
    if header is None:
        raise ValueError(f"{entry.path.name}: unrecognised resource header")
    steps = sum(1 for line in lines if EXT_RESOURCE.match(line)) + 1
    lines[0] = (
        f'[gd_resource type="Resource"{header.group("mid")}'
        f'load_steps={steps}{header.group("rest")}]'
    )

    # Godot types an array of a script class by pointing at the script's own
    # ext_resource, so the property reads Array[ExtResource("3_script")]([...]).
    items = ", ".join(f'ExtResource("{i}")' for i in ext_ids)
    prop = f'evolves_into = Array[ExtResource("{entry.script_ext_id}")]([{items}])'

    # Sit next to model_scale, which is where the hand-written files keep it.
    # Godot reads properties by name, so this is purely for readable diffs.
    for i, line in enumerate(lines):
        if line.startswith("model_scale = "):
            lines.insert(i + 1, prop)
            break
    else:
        raise ValueError(f"{entry.path.name}: no model_scale line to anchor to")

    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="write the changes")
    parser.add_argument("--overwrite", action="store_true",
                        help="rewrite evolves_into where one is already set")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    species = load_species(root)
    by_dex = index_by_dex(species)
    targets = build_targets()

    planned: list[tuple[str, list[str]]] = []
    kept: list[str] = []

    for sid in sorted(species):
        if species[sid].has_evolution and not args.overwrite:
            kept.append(sid)
            continue
        found = resolve(sid, species, by_dex, targets)
        if found:
            planned.append((sid, found))

    branching = 0
    for sid, found in planned:
        marker = "  <- branches" if len(found) > 1 else ""
        branching += len(found) > 1
        print(f"  {sid:30s} -> {', '.join(found)}{marker}")

    print(f"\n{len(planned)} species to link "
          f"({branching} with more than one target), "
          f"{len(species) - len(planned) - len(kept)} with no target, "
          f"{len(kept)} already set (left alone)")

    if not args.apply:
        print("\ndry run -- pass --apply to write")
        return 0

    for sid, found in planned:
        entry = species[sid]
        entry.path.write_text(
            link(entry, [species[t] for t in found]), encoding="utf-8"
        )

    print(f"wrote {len(planned)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# Journey

A small Godot prototype for now: a title screen, one 3D camp scene, a mega evolution effect you can trigger (with spacebar) and replay, and procedural Pokémon Quest–style animation on every creature.

## Requirements

Godot 4.4 (Mobile renderer). No other dependencies.

## Running it

Open the project folder in Godot and press **F5**. It boots to the main menu — hit **Play**.

To look at the animations on their own, pick **ADMIN MENU** on the main menu, or open `game_scenes/admin_menu/admin_menu.tscn` and press **F6**. The `menu` button goes back.

## Controls

### Base camp

| Key | Action |
| --- | --- |
| `Space` | Mega evolve Sandile into Krookodile (press again to rewind) |

### Admin menu

Every species with a `PokemonData` is browsable here, alternate forms and costumes included, and you can retune any of them on the spot. Nothing is bound to the keyboard — every control is an on-screen button, so the same screen works under a mouse now and under a finger once there is a touch build.

The bar across the bottom:

| Button | What it does |
| --- | --- |
| `idle` `run` `attack` `hit` `spin` | Play that animation on everything on screen |
| `grid` | Three species side by side, animating together |
| `shiny` | Swap to the shiny material |
| `info` | The read-only half of a species — previews, typing, traits, base stats, quest stats, and every move it can learn |
| `revert` / `revert all` | Put the focused species, or every edited one, back to what is on disk |
| `save` | Write the edits into each edited species' own `.tres` |
| `menu` | Back to the main menu |
| `tuning` | Fold the second row away when even that is between you and the model |

The second row tunes the focused species, each field a `−` / `+` pair around its current value:

| Pair | Field | Range, by step |
| --- | --- | --- |
| `body` | `body_type` | cycles the enum; hover height follows the new body type |
| `speed` | `anim_speed_scale` | 0.25 – 3.00, by 0.05 |
| `amplitude` | `anim_amplitude` | 0.00 – 3.00, by 0.05 |
| `hover` | `hover_height` | 0.00 – 2.00, by 0.02 |
| `x5 steps` | — | multiplies every step above, and the level box, by five |

Hold a `−` or `+` down and it keeps firing, which is how you cross a whole range without tapping forty times.

Down the right-hand side:

| Control | What it does |
| --- | --- |
| search box, `×` | Filter by name or id — `0092`, `gastly` and `alolan` all match; `×` clears it |
| `\|«` `«25` `−` `+` `25»` `»\|` | First, back 25, one at a time, forward 25, last |
| the list | Tap a row: `#0001  Bulbasaur  QUADRUPED`, with a `*` while it has unsaved edits |
| `level` `−` box `+` | 1 – 100, the level `add to collection` would use |
| `add to collection` | Emits `add_to_collection(id, level)` and reports what it would have done — the collection itself is not wired up yet |

The `−` / `+` pairs edit the focused species' `PokemonData` in place — there is no preview multiplier in between, so what you see is what the game will play. In grid mode the focused species is the leftmost one. Values are clamped to the same ranges the inspector exports and snapped to the same steps.

Edits stay in memory until `save`, which writes them into the species' own `.tres` so the game uses them immediately — it needs the editor, since `res://` is read-only in an export. `revert` puts a species back to what is on disk, however many nudges ago that was, and the readout top left shows `(was …)` next to anything you have moved. `menu` asks twice when there are unsaved edits: the first press warns, the second leaves.

## Animation

The models are single static `.obj` meshes with no skeleton, so nothing can be keyframed. `PokemonAnimator` animates them the way Pokémon Quest does instead: position, rotation and volume-preserving squash-and-stretch on the whole body, computed every frame.

Each species declares a `body_type` on its `PokemonData`, which picks the idle and run style:

| Body type | Idle | Run |
| --- | --- | --- |
| `BIPED` | Breathes, sways on its feet | Rolls left/right over each planted foot |
| `QUADRUPED` | Shallower breath, wider stance | Rocks front-to-back, bounding |
| `HOVER` | Drifts, no squash, never lands | Leans into the drift and banks |
| `FLYER` | Slow bank over a fast wing beat | Hard forward lean, countable wing beat |
| `SERPENTINE` | Slow travelling S | Slithers, yaw leading roll |

Attack, hit and spin are one-shots that play over whichever loop is running and hand back to it cleanly. Driving it is deliberately blunt:

```gdscript
pokemon.animator.moving = true
pokemon.animator.attack()
pokemon.animator.take_hit()
pokemon.animator.spin(2)
await pokemon.animator.animation_finished
```

A `PokemonModel` keeps its animation on a dedicated pivot node, so gameplay can set `position` freely without the wobble stomping it, or vice versa:

```
PokemonModel       (Node3D)         <- gameplay moves this
├── AnimPivot      (Node3D)         <- owned by the animator
│   └── Model      (MeshInstance3D)
└── Animator       (PokemonAnimator)
```

### Species data

There is one `.tres` per folder in `assets/pokemons/`, alternate forms included — so `0025_pikachu`, `0025_pikachu_ash_cap` and `0025_pikachu_explorer` are three resources sharing dex 25. `PokemonRegistry` keys them by **id** (the filename) as well as by dex:

```gdscript
PokemonRegistry.get_pokemon(25)                        # base form
PokemonRegistry.get_pokemon_by_id("0025_pikachu_ash_cap")
PokemonRegistry.get_forms(25)                          # every id sharing the dex
PokemonRegistry.get_all_ids()                          # everything, dex order
```

### Portraits

Every species carries its own 2D art, so UI code never builds a `res://` path by hand:

```gdscript
var species := PokemonRegistry.get_pokemon(25)
species.icon                  # small square, for party slots and dex rows
species.get_preview(shiny)    # full render, shiny when there is one
species.has_shiny_preview()   # false for costume forms -- hide the toggle
```

Read the previews through `get_preview()` rather than touching `preview_shiny` directly. Only the standard forms were rendered shiny, so the costumes and the clones fall back to the ordinary preview instead of handing back a null that every call site would have to catch. 29 forms still have no icon or preview, and 37 have no shiny render.

### Evolution links

`evolves_into` is an `Array[PokemonData]`, because evolution branches — Eevee has eight targets, Clamperl two. The array is in dex order. Most code wants one of them and should say so:

```gdscript
eevee.can_evolve()                # true
eevee.has_branching_evolution()   # true -- the caller has to pick
eevee.first_evolution()           # Vaporeon, the lowest dex
eevee.evolves_into                # all eight, dex order
```

Forms keep their own suffix across the evolution when a file exists for it — Alolan Vulpix → Alolan Ninetales, Hisuian Zorua → Hisuian Zoroark, sunglasses Exeggcute → sunglasses Exeggutor. Otherwise they fall back to the base form, so Ash-cap Pikachu evolves into an ordinary Raichu.

A species whose evolution has no model in the project is left empty rather than pointed somewhere wrong — there is no Steelix here, so Onix has no link. Sandile → Krookodile is a deliberate deviation, skipping Krokorok so the base camp demo stays dramatic.

## Pokémon instances

`PokemonData` is the species. `PokemonInstance` is one you own — at a level, with a Power Charm full of stones and one or two moves. Everything here follows Pokémon Quest's rules, which are much smaller than the mainline's: two stats, no IVs, no natures, no EVs.

```gdscript
var dragonite := PokemonInstance.summon(
	PokemonRegistry.get_pokemon(149), Quest.Pot.GOLD, 100)

dragonite.stats().hp             # own HP + every stone
dragonite.auto_equip(stone)      # first slot that will take it
dragonite.learn(draco_meteor)    # first free move slot
dragonite.level += 1             # may open a charm slot
```

### The two stats

A Pokémon has an HP and an ATK, and that is all. Both come out of the same line:

```
stat = species base + level + summon roll
```

The **species base** is a flat number per species — Chansey 675 HP / 25 ATK, Dragonite 400 / 500, Gengar 150 / 650, always a multiple of 25. The real game hand-authored these and never published a formula, so `Quest.derive_base_stats()` reconstructs one from the mainline spread every `.tres` already carries: a budget of 1.55× the base stat total, split between bulk and offence by a logistic curve. Fitted against eight known species it reproduces Chansey, Snorlax, Gengar and Dragonite exactly and Onix, Machamp and Alakazam within 50. Mewtwo is 150 out, because a legendary bump is not something the mainline spread can predict. Set `quest_base_hp` / `quest_base_attack` on a species to pin it by hand — the derivation is a fallback, not a law.

The **level** contributes one point. Not one percent — one point. A level 100 Dragonite has 834 HP of which 100 came from levelling, against 4716 from its stones. That is the real game's design and not a placeholder: what levelling actually buys is charm slots, and a slot is worth ~900 points at the top end.

The **summon roll** is a one-off bonus from the pot, rolled separately for HP and ATK and then fixed for life. It is the whole of Quest's individuality system.

| Pot | Bonus |
| --- | --- |
| Brass | +0–10 |
| Bronze | +50–100 |
| Silver | +100–200 |
| Gold | +300–400 |

### The Power Charm

Nine slots, 3×3, and nearly all of a Pokémon's power. Three things gate a stone getting in:

- **Socket colour.** Every slot is HP-only, ATK-only or MULTI, rolled per individual from the species' `socket_chance_*` weights. Two Dragonites do not have the same charm, which is why one of them can complete a bingo and the other can't.
- **The unlock.** One slot at level 1, all nine by 100. `Quest.SLOT_UNLOCK_LEVELS` fixes *when*; the charm shuffles *which*.
- **The line.** Fill all three slots of a row or column and the species' `BingoBonus` for that line switches on. Diagonals are worth nothing — in the real game and here.

Stones are loot, so they are rolled rather than authored: `PowerStone.roll(kind, tier, power_level)`, where `power_level` is the strength of wherever it dropped. Tier decides how many percentage sub-stats come with it, from none on a grey stone to four on a platinum.

`PokemonInstance.stats()` folds all of it together in a fixed order — stones, then bingo bonuses, then the caps — and hands back a `PokemonStats` snapshot carrying the three panels of the in-game stat screen:

```gdscript
var s := dragonite.stats()
s.own_hp, s.own_attack         # "Pokémon's Strength"
s.stone_hp, s.stone_attack     # "Stones' Strength"
s.percent(Quest.Stat.CRIT_RATE)
s.type_attack(PokemonData.Type.DRAGON)
s.panel_rows()                 # every non-zero percentage, in the game's order
```

Capping happens once, at the end, so a Pokémon already at the 10% Hit Healing ceiling from stones gets nothing further from a bingo — rather than the two being capped separately and quietly stacking past it.

### Moves

One or two, each an `EquippedMove` holding a `MoveData` and optionally one of the six Move Stones in `data/move_stones/`. Every stone trades something away:

| Stone | Trade |
| --- | --- |
| Sharing | +40% chance buddies catch the effect |
| Scattershot | +2 hits, ×0.6 damage each |
| Broadburst | +1 lane, and only on a move that already spreads |
| Wait Less | ×0.8 wait |
| Stay Strong | ×1.5 effect duration |
| Whack-Whack | +1 hit, ×1.25 wait |

`EquippedMove` is the only place the modifier order is written down. A move's real wait is its printed wait, scaled by its stone, then by the Pokémon's Time to Recover, then by any type-specific bingo bonus — so Draco Meteor's 5.0s becomes 3.13s on the reference Dragonite once a Wait Less Stone is on it.

### Where the numbers came from

All of the above was checked against a level 100 gold-pot Dragonite: 834 / 990 own strength, +4716 / +3842 from nine stones, 5550 HP and 4832 ATK on the nameplate, three bingo bonuses lit. The species bases and the pot ranges come off Serebii's per-species Quest tables.

## What's in here

```
assets/            3D models and textures (maps, Pokémon, cooking pots)
data/              PokemonData + ItemData, and one .tres per species in pokemon/
data/move_stones/  the six Move Stones
game_scenes/       main_menu, base_camp, admin_menu
pokemon/           the shared Pokémon scene and registry, plus the Quest rules:
				   Quest, PokemonInstance, PowerCharm, PowerStone, PokemonStats
systems/vfx/       mega_evolution effect + energy shader
```

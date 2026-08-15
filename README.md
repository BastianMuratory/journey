# Journey

A small Godot prototype for now: a title screen, one 3D camp scene, a mega evolution effect you can trigger (with spacebar) and replay, and procedural Pokémon Quest–style animation on every creature.

## Requirements

Godot 4.4 (Mobile renderer). No other dependencies.

## Running it

Open the project folder in Godot and press **F5**. It boots to the main menu — hit **Play**.

To look at the animations on their own, pick **ANIMATION TEST** on the main menu, or open `game_scenes/animation_test/animation_test.tscn` and press **F6**. `Esc` goes back.

## Controls

### Base camp

| Key | Action |
| --- | --- |
| `Space` | Mega evolve Sandile into Krookodile (press again to rewind) |

### Animation test scene

Every species with a `PokemonData` is browsable here, alternate forms and costumes included, and you can reclassify any of them on the spot.

| Key | Action |
| --- | --- |
| `1`–`5` | Idle / run / attack / hit / spin |
| `←` `→` | Previous / next species |
| `PgUp` `PgDn` | Jump 25 at a time |
| `Home` `End` | First / last |
| `/` | Search by name or id |
| `B` / `Shift+B` | Cycle this species' body type |
| `Ctrl+S` | Save body type edits to disk |
| `↑` `↓` | Speed multiplier |
| `[` `]` | Amplitude multiplier |
| `G` | Grid mode — a row of species animating together |
| `S` | Toggle shiny |
| `R` | Reset the multipliers |
| `Esc` | Back to the main menu |

Speed and amplitude are viewing aids and are never saved. Body type edits are: `Ctrl+S` writes them into the species' own `.tres` so the game uses them immediately, and records them in `tools/body_type_overrides.json`, which `classify_body_types.py` reads as its highest-priority source — so a re-classify never undoes work you did by eye.

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

A `Pokemon` keeps its animation on a dedicated pivot node, so gameplay can set `position` freely without the wobble stomping it, or vice versa:

```
Pokemon            (Node3D)         <- gameplay moves this
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

Two scripts maintain that folder, both with a read-only `plan` and a dry-run `apply`:

- `tools/generate_pokemon_data.py` — creates a `.tres` for any asset folder that lacks one. Existing files are left alone by default, so hand-set evolution links survive; `--refresh-animation` updates only the animation fields.
- `tools/classify_body_types.py` — sets `body_type` and the animation tuning on every `.tres`.

Priority runs overrides file → the script's per-dex tables → body-type defaults. Anything you edit in the animation test scene lands in `tools/body_type_overrides.json` and wins, so hand-tuning and re-classifying don't fight.

## What's in here

```
assets/            3D models and textures (maps, Pokémon, cooking pots)
game_scenes/       main_menu, base_camp, animation_test, the shared pokemon scene
systems/animation/ PokemonAnimator
systems/vfx/       mega_evolution effect + energy shader
data_structures/   PokemonData + one .tres per species
tools/             asset import and classification scripts
```

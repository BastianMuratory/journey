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

Every species with a `PokemonData` is browsable here, alternate forms and costumes included, and you can retune any of them on the spot.

| Key | Action |
| --- | --- |
| `1`–`5` | Idle / run / attack / hit / spin |
| `←` `→` | Previous / next species |
| `PgUp` `PgDn` | Jump 25 at a time |
| `Home` `End` | First / last |
| `/` | Search by name or id |
| `B` / `Shift+B` | Cycle this species' body type |
| `↑` `↓` | Animation speed (`anim_speed_scale`) |
| `[` `]` | Animation amplitude (`anim_amplitude`) |
| `,` `.` | Hover height (`hover_height`) |
| `W` / `Shift+W` | Cycle which wing field `-` and `=` move |
| `-` `=` | Adjust that wing field |
| `Shift` | ×5 step, held with any of the tuning keys above |
| `R` / `Shift+R` | Revert this species / every edited one |
| `Ctrl+S` | Save edits to disk |
| `G` | Grid mode — a row of species animating together |
| `S` | Toggle shiny |
| `Esc` | Back to the main menu |

The tuning keys edit the focused species' `PokemonData` in place — there is no preview multiplier in between, so what you see is what the game will play. In grid mode the focused species is the leftmost one, the same one `B` applies to. Values are clamped to the same ranges the inspector exports and snapped to the same steps.

`W` cycles through the seven wing fields — mode, axis, angle, crease, twist, root, curve — and `-` / `=` move whichever one is in brackets in the info panel. `mode` and `axis` wrap rather than clamp. Winding `angle` up from zero gives wings to a species that has none; winding it back to zero takes them away.

Edits stay in memory until `Ctrl+S`, which writes them into the species' own `.tres` so the game uses them immediately, and records them in `data/body_type_overrides.json`, which `classify_body_types.py` and `detect_wings.py` both read as their highest-priority source — so a re-run never undoes work you did by eye. `R` puts a species back to what is on disk, however many nudges ago that was, and the info panel shows `(was …)` next to anything you have moved.

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

### Wings

The whole-body wobble above can suggest a wing beat but it cannot show one, so wings are bent in the vertex shader — `pokemon/wing_deform.gdshaderinc`, shared by `wing_flap.gdshader` and the additive `wing_flash.gdshader` that has to deform with it. Everything past a crease rotates about it by an angle scaled by how far past it sits, so the crease holds still and the far edge sweeps the arc, and the mesh never tears:

```
|<-- held -->|<----- folded ---->|
0          crease              extent
w = 0        w = 0               w = 1
```

`fold_axis` turns that crease, which is the only thing that decides what counts as a wing:

| Axis | Crease | What moves |
| --- | --- | --- |
| `X` | Front-to-back on each side, mirrored | The wings, up and down about Z — an ordinary beat |
| `Y` | Left-to-right at a height | Everything above it folds forward about X |
| `Z` | Left-to-right at a depth | Everything behind it folds up about X |

Only `X` is mirrored — it is the only axis whose split coordinate is `|x|`, so the only one with two halves to move in opposite directions.

`wing_motion` decides what it does with the beat: `FLAP` sweeps either side of rest, `FOLD` runs from open to shut and back, resting open. The rest of the fields are measurements — `wing_hinge` (where the crease sits along the axis), `wing_root_height` (where the crease line sits in the remaining direction), `flap_degrees`, `flap_twist_degrees`, `wing_curve` — all fractions of the mesh's own size, so they survive a change to `model_scale`. Twist is a second, smaller rotation about the fold axis itself; on `X` that is the wing feathering about its own span, which is most of what makes a beat read as a wing rather than a hinge.

`flap_degrees` is the switch: at 0 the species renders through its ordinary imported material with no shader and no per-frame work, and the animator goes back to faking the beat with whole-body squash. 36 of the 46 flyers currently flap on `X`; the rest have no wing the detector could find (Swablu's wings are cotton) or are only classified `FLYER` because they float.

The motion itself lives in `PokemonAnimator`: one integrated wing phase drives both the wings and the body's bob, so speeding up from idle to flight ramps the beat rather than jumping it, and the creature never bobs against its own stroke.


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

Four scripts maintain that folder, all with a read-only plan and an explicit `--apply`:

- `tools/generate_pokemon_data.py` — creates a `.tres` for any asset folder that lacks one. Existing files are left alone by default, so hand-set evolution links survive; `--refresh-animation` updates only the animation fields.
- `tools/classify_body_types.py` — sets `body_type` and the animation tuning on every `.tres`.
- `tools/detect_wings.py` — measures each flyer's mesh to find where its body ends and its wings start, and writes the wing fields. `plan` prints the measurements and says which species it could not find wings on. It only measures `X` creases; `wing_motion` and `fold_axis` are left to the animation test scene, so a species you have folded on `Y` stays folded on `Y` through a re-run.
- `tools/link_evolutions.py` — sets `evolves_into` on every `.tres` that has a target in the project.
- `tools/add_preview_textures.py` — points `icon`, `preview` and `preview_shiny` at the images in the asset folder. Run it after new art lands; it only fills in what is missing, so re-running is free.

Priority runs overrides file → the script's per-dex tables → body-type defaults (and, for the wings, → what was measured off the mesh). Anything you edit in the animation test scene lands in `data/body_type_overrides.json` and wins, so hand-tuning and re-classifying don't fight.

### Portraits

Every species carries its own 2D art, so UI code never builds a `res://` path by hand:

```gdscript
var species := PokemonRegistry.get_pokemon(25)
species.icon                  # small square, for party slots and dex rows
species.get_preview(shiny)    # full render, shiny when there is one
species.has_shiny_preview()   # false for costume forms -- hide the toggle
```

Read the previews through `get_preview()` rather than touching `preview_shiny` directly. Only the standard forms were rendered shiny, so the costumes and the clones fall back to the ordinary preview instead of handing back a null that every call site would have to catch. `tools/missing_art.md` lists what is still missing — 29 forms have no icon or preview, 37 have no shiny render.

### Evolution links

`evolves_into` is an `Array[PokemonData]`, because evolution branches — Eevee has eight targets, Clamperl two. The array is in dex order. Most code wants one of them and should say so:

```gdscript
eevee.can_evolve()                # true
eevee.has_branching_evolution()   # true -- the caller has to pick
eevee.first_evolution()           # Vaporeon, the lowest dex
eevee.evolves_into                # all eight, dex order
```

Forms keep their own suffix across the evolution when a file exists for it — Alolan Vulpix → Alolan Ninetales, Hisuian Zorua → Hisuian Zoroark, sunglasses Exeggcute → sunglasses Exeggutor. Otherwise they fall back to the base form, so Ash-cap Pikachu evolves into an ordinary Raichu.

A species whose evolution has no model in the project is left empty rather than pointed somewhere wrong — there is no Steelix here, so Onix has no link. Deliberate deviations live in `MANUAL_LINKS` at the top of the script; that is where Sandile → Krookodile is kept, skipping Krokorok so the base camp demo stays dramatic. Rewriting is idempotent, and files that already have a link are skipped unless you pass `--overwrite`.

## What's in here

```
assets/            3D models and textures (maps, Pokémon, cooking pots)
data/              PokemonData + ItemData, and one .tres per species in pokemon/
entities/pokemon/  the shared Pokémon scene, instanced by everything else
game_scenes/       main_menu, base_camp, animation_test
systems/animation/ PokemonAnimator
systems/vfx/       mega_evolution effect + energy shader
tools/             asset import, classification and evolution-linking scripts
```

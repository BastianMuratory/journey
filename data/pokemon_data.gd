class_name PokemonData
extends Resource

## Everything that makes one Pokémon species different from another.
##
## Pure data -- no position, no behaviour. One [code].tres[/code] file per
## species lives in [code]res://data/pokemon/[/code] and is looked
## up by dex number through the [code]PokemonRegistry[/code] autoload:
## [codeblock]
## var sandile := PokemonRegistry.get_pokemon(551)
## [/codeblock]

## How a species carries itself. Decides which idle and run animation the
## [PokemonAnimator] plays -- a Rattata should waddle front-to-back, a Charizard
## should beat its wings and never touch the floor.
enum BodyType {
	## Stands on two legs. Idle bobs, run rolls side to side.
	BIPED,
	## Walks on four legs (or is a low blob). Idle bobs, run pitches front to back.
	QUADRUPED,
	## Floats just off the ground, no wings -- Gastly, Magnemite, Koffing.
	## Drifts and sways, never bounces off the floor.
	HOVER,
	## Actively flies with wings. Same as HOVER but higher, faster, with a
	## wing-beat pulse and banking turns.
	FLYER,
	## Long and legless -- Ekans, Onix, Dratini. Slithers with a travelling
	## S-wave instead of a step cycle.
	SERPENTINE,
}

@export var dex_number: int = 0
@export var display_name: String = ""

@export_group("Model")
@export var mesh: Mesh
## Left null keeps the material the .obj imported from its .mtl, which is
## normally what you want. Only set this if you need to override it.
@export var albedo: Texture2D
## Used instead of [member albedo] when the Pokémon is spawned shiny.
@export var albedo_shiny: Texture2D
@export var model_scale: float = 1.0

@export_group("Animation")
## Drives which idle/run style [PokemonAnimator] uses. Set for every species by
## [code]tools/classify_body_types.py[/code]; override by hand if one looks off.
@export var body_type: BodyType = BodyType.QUADRUPED
## Multiplies every animation's tempo. Below 1.0 for something ponderous like
## Snorlax, above 1.0 for something twitchy like Pikachu.
@export_range(0.25, 3.0, 0.05) var anim_speed_scale: float = 1.0
## Multiplies how far every animation moves. Drop it for heavy species that
## should barely budge, raise it for rubbery ones.
@export_range(0.0, 3.0, 0.05) var anim_amplitude: float = 1.0
## Only used by HOVER and FLYER. How far off the ground the species floats, in
## multiples of its own height. 0 keeps it grounded.
@export_range(0.0, 2.0, 0.05) var hover_height: float = 0.0

@export_group("Evolution")
## Every species this one can evolve into, in dex order.
##
## An array because evolution branches: Eevee has eight targets, Kirlia has two,
## Poliwhirl has two. Most species have exactly one, and plenty have none -- so
## read it through [method first_evolution] unless you actually want to offer
## the player a choice.
@export var evolves_into: Array[PokemonData] = []

@export_group("MegaEvolution")
## Mega form, triggered by the MegaEvolution effect rather than by levelling.
@export var mega_evolves_into: PokemonData


## True when there is at least one normal evolution to evolve into.
func can_evolve() -> bool:
	return not evolves_into.is_empty()


## The default evolution -- the lowest dex number of the branches, which for a
## species with only one target is just that target. Null if it doesn't evolve.
## This is what gameplay wants when it isn't presenting a choice.
func first_evolution() -> PokemonData:
	return evolves_into[0] if not evolves_into.is_empty() else null


## True when evolution forks and the caller has to pick, e.g. Eevee or Kirlia.
func has_branching_evolution() -> bool:
	return evolves_into.size() > 1


## True when there is a mega form available.
func can_mega_evolve() -> bool:
	return mega_evolves_into != null


## True for species that never touch the ground, so the animator skips footfalls,
## landing squash and hop arcs entirely.
func is_airborne() -> bool:
	return body_type == BodyType.HOVER or body_type == BodyType.FLYER


## The resting altitude a body type gets when nothing overrides it, in multiples
## of the creature's own height.
##
## [b]Mirrored in tools/classify_body_types.py (DEFAULT_HOVER_HEIGHT).[/b] If you
## change a number here, change it there too, or a re-classify will silently
## disagree with what the editor hands out.
static func default_hover_height(type: BodyType) -> float:
	match type:
		BodyType.HOVER:
			return 0.18
		BodyType.FLYER:
			return 0.40
		_:
			return 0.0

class_name PokemonData
extends Resource


enum Type {
	NONE,
	NORMAL,
	FIGHTING,
	FLYING,
	POISON,
	GROUND,
	ROCK,
	BUG,
	GHOST,
	STEEL,
	FIRE,
	WATER,
	GRASS,
	ELECTRIC,
	PSYCHIC,
	ICE,
	DRAGON,
	DARK,
	FAIRY,
}

## Decides which idle and run animation the [PokemonAnimator] plays
enum BodyType {
	BIPED,
	QUADRUPED,
	HOVER,
	FLYER,
	SERPENTINE,
}

@export var dex_number: int = 0
@export var display_name: String = ""

@export_group("Model")
@export var mesh: Mesh
@export var albedo: Texture2D
@export var albedo_shiny: Texture2D
@export var model_scale: float = 1.0

@export_group("UI")
@export var icon: Texture2D
@export var preview: Texture2D
@export var preview_shiny: Texture2D

@export_group("Animation")
@export var body_type: BodyType = BodyType.QUADRUPED
@export_range(0.25, 3.0, 0.05) var anim_speed_scale: float = 1.0
@export_range(0.0, 3.0, 0.05) var anim_amplitude: float = 1.0
@export_range(0.0, 2.0, 0.05) var hover_height: float = 0.0

@export_group("Evolution")
@export var evolves_into: Array[PokemonData] = []

@export_group("MegaEvolution")
@export var mega_evolves_into: PokemonData

## Elemental typing. type2 stays NONE for the single-typed majority.
@export_group("Type")
@export var type1: Type = Type.NONE
@export var type2: Type = Type.NONE

@export_group("Stats")
@export var base_hp: int = 0
@export var base_attack: int = 0
@export var base_defense: int = 0
@export var base_special_attack: int = 0
@export var base_special_defense: int = 0
@export var base_speed: int = 0

func get_preview(shiny: bool = false) -> Texture2D:
	if shiny and preview_shiny != null:
		return preview_shiny
	return preview

func has_shiny_preview() -> bool:
	return preview_shiny != null

func has_second_type() -> bool:
	return type2 != Type.NONE

func has_type(wanted: Type) -> bool:
	return wanted != Type.NONE and (type1 == wanted or type2 == wanted)

## The typing as a list, one entry for single-typed species. Handy for damage
## code that wants to loop rather than branch on has_second_type().
func types() -> Array[Type]:
	var out: Array[Type] = []
	if type1 != Type.NONE:
		out.append(type1)
	if type2 != Type.NONE:
		out.append(type2)
	return out

## "Grass", "Fairy" -- for UI labels.
static func type_name(value: Type) -> String:
	return String(Type.keys()[value]).capitalize()

func has_icon() -> bool:
	return icon != null

func can_evolve() -> bool:
	return not evolves_into.is_empty()

func first_evolution() -> PokemonData:
	return evolves_into[0] if not evolves_into.is_empty() else null

## True when evolution forks and the caller has to pick, e.g. Eevee or Kirlia.
func has_branching_evolution() -> bool:
	return evolves_into.size() > 1

func can_mega_evolve() -> bool:
	return mega_evolves_into != null

func is_airborne() -> bool:
	return body_type == BodyType.HOVER or body_type == BodyType.FLYER


static func default_hover_height(type: BodyType) -> float:
	match type:
		BodyType.HOVER:
			return 0.18
		BodyType.FLYER:
			return 0.40
		_:
			return 0.0

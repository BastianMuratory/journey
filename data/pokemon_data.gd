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

## What the wings do with the beat.
enum WingMotion {
	## Sweeps either side of rest, down on the power stroke and back up. An
	## ordinary wing beat.
	FLAP,
	## Runs from open to shut and back, resting open. Wings closing rather than
	## beating -- shells, elytra, a bird settling.
	FOLD,
}

## Which way the crease runs. Only [constant FoldAxis.X] is mirrored, because it
## is the only one that splits the mesh into a left half and a right half.
enum FoldAxis {
	## Crease front-to-back on each side; the wings swing up and down.
	X,
	## Crease left-to-right at some height; everything above folds forward.
	Y,
	## Crease left-to-right at some depth; everything behind folds up.
	Z,
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

## Wings are bent by a vertex shader rather than a skeleton -- see
## [code]pokemon/wing_deform.gdshaderinc[/code]. Everything here is a fraction of
## the mesh's own size, so it survives a change to [member model_scale] and can be
## copied between two species built at different scales.
##
## [member flap_degrees] is the master switch: leave it at 0 and the species is
## drawn with the ordinary imported material, no shader, no per-frame work.
@export_group("Wings")
## Whether the wings beat or fold shut. See [enum WingMotion].
@export var wing_motion: WingMotion = WingMotion.FLAP
## Which way the crease runs. See [enum FoldAxis].
@export var fold_axis: FoldAxis = FoldAxis.X
## Where the crease sits along [member fold_axis], as a fraction of the mesh's
## size in that direction. On the X axis that is a fraction of the half-width, so
## 0.25 means the outer three quarters of each side is wing.
@export_range(0.0, 1.0, 0.01) var wing_hinge: float = 0.0
## How far the wings travel, in degrees: half the stroke when flapping, the whole
## closed angle when folding. Negative folds the other way. 0 turns wings off.
@export_range(-180.0, 180.0, 1.0) var flap_degrees: float = 0.0
## How far the wing feathers about the fold axis as it moves, in degrees.
@export_range(0.0, 45.0, 1.0) var flap_twist_degrees: float = 0.0
## Where the crease line sits in the remaining direction, as a fraction of the
## mesh's size there: the shoulder's height for an [constant FoldAxis.X] fold and
## for [constant FoldAxis.Z], its depth for [constant FoldAxis.Y].
@export_range(0.0, 1.0, 0.01) var wing_root_height: float = 0.5
## Bend distribution. 1.0 swings the wing rigidly from the crease, which is what
## a fold wants; higher values keep it straighter near the body and put the arc
## out in the tip, which is what a wing beat wants.
@export_range(0.5, 3.0, 0.1) var wing_curve: float = 1.5

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


## True when this species is set up for the wing shader. Species whose wings the
## detector could not find -- and anything hand-disabled by setting
## [member flap_degrees] to 0 -- fall back to the animator's whole-body wing beat.
func has_wings() -> bool:
	return absf(flap_degrees) > 0.0 and wing_hinge < 1.0


static func default_hover_height(type: BodyType) -> float:
	match type:
		BodyType.HOVER:
			return 0.18
		BodyType.FLYER:
			return 0.40
		_:
			return 0.0

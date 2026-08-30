class_name PokemonBaseData
extends Resource

@export var dex_number: int = 0
@export var display_name: String = ""

@export_group("Model")
## Where the 3D model lives. Stored as a path, not as a direct reference, so
## that loading a species for its name, icon or stats does not drag its mesh in
## with it — an [code]ExtResource[/code] is resolved eagerly when the .tres is
## parsed, a path is not. See [member mesh].
@export_file("*.obj") var mesh_path: String = ""

var _mesh: Mesh = null

## The model itself, loaded from [member mesh_path] the first time anything asks
## for it and cached on the resource from then on. Read-only: set [member
## mesh_path] instead.
var mesh: Mesh:
	get:
		if _mesh == null and not mesh_path.is_empty():
			_mesh = load(mesh_path) as Mesh
		return _mesh

@export var albedo: Texture2D
@export var albedo_shiny: Texture2D
@export var model_scale: float = 1.0

@export_group("UI")
@export var icon: Texture2D
@export var preview: Texture2D
@export var preview_shiny: Texture2D

@export_group("Animation")
@export var body_type: Enums.BodyType = Enums.BodyType.QUADRUPED
@export var anim_speed_scale: float = 1.0
@export var anim_amplitude: float = 1.0
@export var hover_height: float = 0.0
## What this Pokémon does between moves: melee closes to contact, ranged fires
## from where it stands.
@export var attack_style: Enums.AttackStyle = Enums.AttackStyle.MELEE

@export_group("Evolution")
@export var evolutions: Array[PokemonBaseData] = []

@export_group("MegaEvolution")
@export var mega_evolutions: PokemonBaseData

@export_group("Type")
@export var type1: Enums.TypeID = Enums.TypeID.NORMAL
@export var type2: Enums.TypeID = Enums.TypeID.NONE

# default stats
@export_group("Stats")
@export var base_hp: int = 100
@export var base_attack: int = 1
@export var base_defense: int = 1
@export var base_special_attack: int = 1
@export var base_special_defense: int = 1
@export var base_speed: int = 10

## Quest has only HP, ATK and SPEED
@export_group("Quest")
@export var quest_base_hp: int = 0
@export var quest_base_attack: int = 0
@export var quest_base_speed: int = 0

@export_subgroup("Loadout")
## Everything this species can learn.
@export var learnable_moves: Array[Enums.AttackID] = []

func get_preview(shiny: bool = false) -> Texture2D:
	if shiny and preview_shiny != null:
		return preview_shiny
	return preview

func has_shiny_preview() -> bool:
	return preview_shiny != null

func has_second_type() -> bool:
	return type2 != Enums.TypeID.NONE

func has_type(wanted: Enums.TypeID) -> bool:
	return wanted != Enums.TypeID.NONE and (type1 == wanted or type2 == wanted)

## The typing as a list, one entry for single-typed species. Handy for damage
## code that wants to loop rather than branch on has_second_type().
func types() -> Array[Enums.TypeID]:
	var out: Array[Enums.TypeID] = []
	if type1 != Enums.TypeID.NONE:
		out.append(type1)
	if type2 != Enums.TypeID.NONE:
		out.append(type2)
	return out

func has_icon() -> bool:
	return icon != null

func can_evolve() -> bool:
	return not evolutions.is_empty()

func first_evolution() -> PokemonBaseData:
	return evolutions[0] if not evolutions.is_empty() else null

## True when evolution forks and the caller has to pick, e.g. Eevee or Kirlia.
func has_branching_evolution() -> bool:
	return evolutions.size() > 1

func can_mega_evolve() -> bool:
	return mega_evolutions != null

func is_airborne() -> bool:
	return body_type == Enums.BodyType.HOVER or body_type == Enums.BodyType.FLYER

static func default_hover_height(type: Enums.BodyType) -> float:
	match type:
		Enums.BodyType.HOVER:
			return 0.18
		Enums.BodyType.FLYER:
			return 0.40
		_:
			return 0.0

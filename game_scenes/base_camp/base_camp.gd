extends Node3D

# For now this will be a very simple base camp
const POKEMON_MODEL_SCENE_PATH = "uid://6r1xtnwsp0sa"
const POKEMON_MODEL_SCENE := preload(POKEMON_MODEL_SCENE_PATH)

# this is for testing purposes
const CHARIZARD_DEX_NUMBER := 6
const BLASTOISE_DEX_NUMBER := 9
@onready var _spawn_point: Marker3D = $SpawnPoint
@onready var _spawn_point2: Marker3D = $SpawnPoint2

func _ready() -> void:
	_add_pokemon(CHARIZARD_DEX_NUMBER, _spawn_point)
	_add_pokemon(BLASTOISE_DEX_NUMBER, _spawn_point2)

# attach the pokemon to the 3D marker 
func spawn_pokemon(data: PokemonBaseData, marker: Marker3D, shiny := false) -> PokemonModel:
	var p: PokemonModel = POKEMON_MODEL_SCENE.instantiate()
	p.data = data
	p.shiny = shiny
	add_child(p)
	# Position and rotation only -- assigning the whole transform would
	# clobber the scale that model_scale just applied.
	p.position = marker.position
	p.rotation = marker.rotation
	return p

func _add_pokemon(dex: int, marker: Marker3D) -> void:
	var data := PokemonRegistry.get_pokemon(dex)
	if data == null:
		push_error("BaseCamp: no data for dex #%d" % dex)
		return
	spawn_pokemon(data, marker)

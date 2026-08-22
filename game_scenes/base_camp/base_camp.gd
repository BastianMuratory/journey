extends Node3D

## Base camp sandbox.
##
## Nothing is hardcoded in the scene any more -- the Pokémon is spawned at
## runtime from [code]PokemonRegistry[/code] onto the SpawnPoint marker, and
## the evolution target is read off its [PokemonBaseData]. Change [constant
## SANDILE_DEX_NUMBER] and the whole thing follows.
##
## Space bar evolves; space again rewinds so you can watch it a second time.

const POKEMON_MODEL_SCENE := preload("res://pokemon/pokemon_model.tscn")

## Which species the camp starts with. 551 = Sandile.
const CHARIZARD_DEX_NUMBER := 6
const BLASTOISE_DEX_NUMBER := 9

@onready var _spawn_point: Marker3D = $SpawnPoint
@onready var _spawn_point2: Marker3D = $SpawnPoint2

## One spawned Pokémon plus the effect bolted to it.
class Entry:
	var pokemon: PokemonModel
	var base_data: PokemonBaseData
	var evolved_data: PokemonBaseData
	var mega: MegaEvolution


var _entries: Array[Entry] = []

func _ready() -> void:
	_add_pokemon(CHARIZARD_DEX_NUMBER, _spawn_point)
	_add_pokemon(BLASTOISE_DEX_NUMBER, _spawn_point2)

## Instantiates the shared Pokémon scene as the given species. Reusable for
## anything else you want to drop into the camp.
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

	var e := Entry.new()
	e.base_data = data
	# Prefer the mega form, fall back to the normal evolution.
	e.evolved_data = data.mega_evolves_into if data.mega_evolves_into != null else data.first_evolution()
	e.pokemon = spawn_pokemon(data, marker)
	e.mega = _attach_mega(e)
	_entries.append(e)


func _attach_mega(e: Entry) -> MegaEvolution:
	if e.evolved_data == null:
		push_warning("%s has no evolution target, no effect attached" % e.base_data.display_name)
		return null

	var mega := MegaEvolution.new()
	mega.name = "MegaEvolution"
	mega.evolved_mesh = e.evolved_data.mesh
	mega.swap_mesh = false
	# Capture this entry, so the effect evolves its own Pokémon rather than
	# whichever one happens to be in a global.
	mega.evolved.connect(func() -> void: e.pokemon.set_species(e.evolved_data))
	# The effect rumbles the model itself, so park the idle wobble for the
	# duration -- two things shaking the same creature reads as neither.
	mega.charge_started.connect(func() -> void: e.pokemon.animator.stop())
	mega.finished.connect(func() -> void: e.pokemon.animator.resume())
	e.pokemon.add_child(mega)
	return mega


func _unhandled_input(event: InputEvent) -> void:
	if not _is_evolve_pressed(event):
		return
	get_viewport().set_input_as_handled()
	for e in _entries:
		_toggle(e)


func _toggle(e: Entry) -> void:
	if e.mega == null or e.mega.is_playing:
		return
	if e.pokemon.data != e.base_data:
		e.pokemon.set_species(e.base_data)   # already evolved -- rewind
		return
	e.mega.trigger()


## Prefers the "mega_evolve" input action (rebindable in Project Settings) and
## falls back to the raw space bar if the action was never defined.
func _is_evolve_pressed(event: InputEvent) -> bool:
	if InputMap.has_action(&"mega_evolve"):
		return event.is_action_pressed(&"mega_evolve")
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE

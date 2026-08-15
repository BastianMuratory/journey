class_name Pokemon
extends MeshInstance3D

## A Pokémon in the world. Reconfigures itself from whatever [PokemonData] it
## is given, so one scene covers every species:
## [codeblock]
## var p := POKEMON_SCENE.instantiate() as Pokemon
## p.data = PokemonRegistry.get_pokemon(551)
## add_child(p)
## [/codeblock]
##
## Runs in the editor too ([code]@tool[/code]), so dropping a different .tres
## into the data slot updates the viewport immediately.

## Emitted after the mesh and material have been swapped to a new species.
signal species_changed(new_data: PokemonData)

@export var data: PokemonData:
	set(value):
		data = value
		_apply()

@export var shiny: bool = false:
	set(value):
		shiny = value
		_apply()

## Cached so we aren't allocating a new StandardMaterial3D on every _apply().
var _shiny_material: StandardMaterial3D


## Convenience passthrough so callers don't have to null-check [member data].
var display_name: String:
	get: return data.display_name if data != null else ""


func _ready() -> void:
	_apply()


## Swaps this Pokémon to another species in place, keeping its transform.
## Used by the evolution effect.
func set_species(new_data: PokemonData) -> void:
	if new_data == null:
		return
	data = new_data

func _apply() -> void:
	if data == null:
		mesh = null
		return

	mesh = data.mesh
	scale = Vector3.ONE * data.model_scale
	_apply_material()
	species_changed.emit(data)


func _apply_material() -> void:
	# .obj files carry their own material via the .mtl, so the common case is
	# to leave it alone entirely.
	var override_texture: Texture2D = null
	if shiny and data.albedo_shiny != null:
		override_texture = data.albedo_shiny
	elif data.albedo != null:
		override_texture = data.albedo

	if override_texture == null:
		material_override = null
		return

	if _shiny_material == null:
		_shiny_material = StandardMaterial3D.new()
	_shiny_material.albedo_texture = override_texture
	material_override = _shiny_material

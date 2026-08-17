class_name PokemonModel
extends Node3D

## A Pokémon in the world. Reconfigures itself from whatever [PokemonBaseData] it
## is given, so one scene covers every species:
## [codeblock]
## var p := POKEMON_MODEL_SCENE.instantiate() as PokemonModel
## p.data = PokemonRegistry.get_pokemon(551)
## add_child(p)
## p.animator.moving = true
## [/codeblock]
##
## The node tree exists to keep three things from fighting over one transform:
## [codeblock]
## PokemonModel       (Node3D)         <- gameplay moves this, freely
## ├── AnimPivot      (Node3D)         <- owned by the animator, nothing else
## │   └── Model      (MeshInstance3D) <- the mesh, and model_scale
## └── Animator       (PokemonAnimator)
## [/codeblock]
## Because the animator has its own node, setting [member Node3D.position] on a
## Pokémon never gets stomped by the wobble, and the wobble never gets stomped
## by pathfinding.
##
## AnimPivot sits at the height the creature should rotate around -- its feet if
## it walks, its middle if it flies -- so leaning and spinning look right without
## any per-species setup.

## Emitted after the mesh and material have been swapped to a new species.
signal species_changed(new_data: PokemonBaseData)

@export var data: PokemonBaseData:
	set(value):
		data = value
		_apply()

@export var shiny: bool = false:
	set(value):
		shiny = value
		_apply()

@onready var model: MeshInstance3D = $AnimPivot/Model
@onready var anim_pivot: Node3D = $AnimPivot
@onready var animator: PokemonAnimator = $Animator

## Cached so we aren't allocating a new StandardMaterial3D on every _apply().
var _shiny_material: StandardMaterial3D


## Convenience passthrough so callers don't have to null-check [member data].
var display_name: String:
	get: return data.display_name if data != null else ""


## The mesh currently being displayed. Kept as a passthrough so callers (and the
## evolution VFX) don't need to know about the Model child.
var mesh: Mesh:
	get: return model.mesh if model != null else null
	set(value):
		if model != null:
			model.mesh = value


func _ready() -> void:
	animator.target = anim_pivot
	animator.flash_target = model
	_apply()


## Swaps this Pokémon to another species in place, keeping its transform.
## Used by the evolution effect.
func set_species(new_data: PokemonBaseData) -> void:
	if new_data == null:
		return
	data = new_data


## Re-reads the animation fields off [member data] without touching the mesh.
## Call this after editing [member PokemonBaseData.body_type] at runtime -- the pivot
## height depends on it, so simply setting the field is not enough.
func refresh_animation() -> void:
	if model == null or data == null:
		return
	_apply_pivot()


func _apply() -> void:
	# Exported setters fire before _ready, so bail until the children exist.
	if model == null:
		return

	if data == null:
		model.mesh = null
		return

	model.mesh = data.mesh
	model.scale = Vector3.ONE * data.model_scale
	_apply_material()
	_apply_pivot()
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
		model.material_override = null
		return

	if _shiny_material == null:
		_shiny_material = StandardMaterial3D.new()
	_shiny_material.albedo_texture = override_texture
	model.material_override = _shiny_material


## Measures the new mesh and points the animator at the right pivot height.
## Walkers rotate around their feet; anything airborne rotates around its middle,
## which is what stops a flying Pokémon from looking hinged to the floor.
func _apply_pivot() -> void:
	if data.mesh == null:
		return

	var aabb := data.mesh.get_aabb()
	var s := data.model_scale
	var world_height := maxf(aabb.size.y * s, 0.001)

	var pivot_y := aabb.position.y * s
	if data.is_airborne():
		pivot_y += aabb.size.y * 0.5 * s

	# The pivot lifts up and the model drops by the same amount, so the mesh
	# does not visibly move -- only the point everything rotates around does.
	anim_pivot.position.y = pivot_y
	model.position.y = -pivot_y

	animator.configure(data, world_height)
	animator.rest_position = Vector3(0.0, pivot_y, 0.0)

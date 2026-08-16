class_name PokemonModel
extends Node3D

## A Pokémon in the world. Reconfigures itself from whatever [PokemonData] it
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
signal species_changed(new_data: PokemonData)

@export var data: PokemonData:
	set(value):
		data = value
		_apply()

@export var shiny: bool = false:
	set(value):
		shiny = value
		_apply()

## Bends the wings in the vertex stage. Only species with wings pay for it.
const WING_SHADER := preload("res://pokemon/wing_flap.gdshader")
## The same bend again, for the additive pass the hit flash draws.
const WING_FLASH_SHADER := preload("res://pokemon/wing_flash.gdshader")

@onready var model: MeshInstance3D = $AnimPivot/Model
@onready var anim_pivot: Node3D = $AnimPivot
@onready var animator: PokemonAnimator = $Animator

## Cached so we aren't allocating a new StandardMaterial3D on every _apply().
var _shiny_material: StandardMaterial3D
## Cached for the same reason. One per instance rather than one per species,
## because each Pokémon beats its wings on its own phase.
var _wing_material: ShaderMaterial
var _wing_flash_material: ShaderMaterial


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
func set_species(new_data: PokemonData) -> void:
	if new_data == null:
		return
	data = new_data


## Re-reads the animation fields off [member data] without touching the mesh.
## Call this after editing [member PokemonData.body_type] or any of the wing
## fields at runtime -- the pivot height and the shader's hinge are both derived
## from them, so simply setting the field is not enough.
func refresh_animation() -> void:
	if model == null or data == null:
		return
	_apply_material()
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

	# The hinge is measured off the mesh, so a species without one cannot flap
	# whatever its data says.
	if data.has_wings() and data.mesh != null:
		_apply_wing_material(override_texture)
		return

	_clear_wings()
	if override_texture == null:
		model.material_override = null
		return

	if _shiny_material == null:
		_shiny_material = StandardMaterial3D.new()
	_shiny_material.albedo_texture = override_texture
	model.material_override = _shiny_material


## Winged species render through [constant WING_SHADER] instead of the material
## the .obj importer built, because a static mesh can only flap if something
## moves its vertices. The shader is a plain textured surface otherwise, and its
## uniforms are copied off the imported material, so the swap is invisible.
func _apply_wing_material(override_texture: Texture2D) -> void:
	if _wing_material == null:
		_wing_material = ShaderMaterial.new()
		_wing_material.shader = WING_SHADER
	if _wing_flash_material == null:
		_wing_flash_material = ShaderMaterial.new()
		_wing_flash_material.shader = WING_FLASH_SHADER

	var imported: StandardMaterial3D = null
	if data.mesh.get_surface_count() > 0:
		imported = data.mesh.surface_get_material(0) as StandardMaterial3D
	var texture := override_texture
	if texture == null and imported != null:
		texture = imported.albedo_texture

	_wing_material.set_shader_parameter("albedo_texture", texture)
	if imported != null:
		_wing_material.set_shader_parameter("albedo_color", imported.albedo_color)
		_wing_material.set_shader_parameter("roughness", imported.roughness)
		_wing_material.set_shader_parameter("metallic", imported.metallic)
		# BaseMaterial3D calls it metallic_specular -- there is no plain "specular".
		_wing_material.set_shader_parameter("specular", imported.metallic_specular)

	# The crease is stored as a fraction of the mesh's own size, so it survives a
	# change to model_scale and can be copied between species. The shader wants it
	# in the mesh's own units, which is what VERTEX is measured in.
	var aabb := data.mesh.get_aabb()
	var crease := 0.0
	var extent := 0.0
	var root := 0.0

	match data.fold_axis:
		PokemonData.FoldAxis.Y:
			# Splits high from low, so the crease is a height and the line it
			# turns about is placed front-to-back.
			extent = aabb.end.y
			crease = aabb.position.y + data.wing_hinge * aabb.size.y
			root = aabb.position.z + data.wing_root_height * aabb.size.z
		PokemonData.FoldAxis.Z:
			# Splits back from front: the crease is a depth, the line a height.
			extent = aabb.end.z
			crease = aabb.position.z + data.wing_hinge * aabb.size.z
			root = aabb.position.y + data.wing_root_height * aabb.size.y
		_:
			# Mirrored, so the extent is the half-width rather than the width --
			# both wings measure out from x = 0.
			extent = maxf(absf(aabb.position.x), absf(aabb.end.x))
			crease = data.wing_hinge * extent
			root = aabb.position.y + data.wing_root_height * aabb.size.y

	for material: ShaderMaterial in [_wing_material, _wing_flash_material]:
		material.set_shader_parameter("fold_axis", int(data.fold_axis))
		material.set_shader_parameter("extent", extent)
		material.set_shader_parameter("crease", crease)
		material.set_shader_parameter("root", root)
		material.set_shader_parameter("curve", data.wing_curve)

	model.material_override = _wing_material
	animator.wing_material = _wing_material
	animator.wing_flash_material = _wing_flash_material


## Back to a wingless species: drop the shader so the animator stops writing to
## it, and drop the flash overlay with it -- the ordinary StandardMaterial3D
## flash takes over.
func _clear_wings() -> void:
	if animator.wing_material == null:
		return
	animator.wing_material = null
	animator.wing_flash_material = null
	if model.material_overlay == _wing_flash_material:
		model.material_overlay = null


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

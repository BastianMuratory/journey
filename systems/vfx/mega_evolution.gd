class_name MegaEvolution
extends Node3D

## This file was made by AI as a Proof of concept 

## Drop-in mega evolution effect for any [MeshInstance3D].
##
## Builds its own energy sphere and light on ready, so the whole thing is one
## node with no children to wire up:
## [codeblock]
## Sandile              (MeshInstance3D)
## └── MegaEvolution    evolved_mesh = krookodile.obj
## [/codeblock]
## Then just call it:
## [codeblock]
## $Sandile/MegaEvolution.trigger()
## await $Sandile/MegaEvolution.finished
## [/codeblock]
##
## The sphere auto-sizes to whichever is bigger -- the current mesh or the
## evolved one -- so the swap always happens fully hidden inside the flash.

## Emitted the moment the sphere starts growing.
signal charge_started
## Emitted on the frame the mesh is actually swapped (inside the white flash).
signal evolved
## Emitted once the sphere has fully dissipated and the node is idle again.
signal finished

const SHADER := preload("res://systems/vfx/mega_evolution_energy.gdshader")

@export_group("Target")
## MeshInstance3D whose [code]mesh[/code] gets replaced. Empty = the parent node.
@export var target_path: NodePath
## Mesh swapped in at the peak of the burst.
@export var evolved_mesh: Mesh
## Optional material override for the evolved form. Null keeps the mesh's own
## imported material, which is what you want for .obj + .mtl models.
@export var evolved_material: Material
## Uniform scale applied to the target after evolving. Ripped models are usually
## already sized relative to each other, so 1.0 is normally right.
@export var evolved_scale := 1.0
## Set false to fire the effect without actually changing the mesh.
@export var swap_mesh := true

@export_group("Timing")
## Seconds the sphere spends growing and gathering energy.
@export_range(0.1, 10.0, 0.1) var charge_time := 2.6
## Seconds spent at the white peak. The mesh swap happens at the top of this.
@export_range(0.02, 1.0, 0.01) var flash_time := 0.2
## Seconds the sphere takes to expand away and fade out, revealing the new form.
@export_range(0.1, 5.0, 0.05) var dissipate_time := 0.75

@export_group("Look")
## Sphere radius as a multiple of the creature's largest half-extent.
@export_range(1.0, 3.0, 0.05) var radius_padding := 1.3
@export var color_a := Color(1.0, 0.18, 0.72)
@export var color_b := Color(0.16, 0.82, 1.0)
@export var color_core := Color(1.0, 0.96, 0.82)
## Peak brightness of the point light thrown onto the surrounding scene.
@export_range(0.0, 40.0, 0.5) var light_energy := 12.0
## Amplitude of the anticipation rumble on the creature, in local units.
@export_range(0.0, 0.5, 0.005) var shake_amount := 0.04

var _sphere: MeshInstance3D
var _light: OmniLight3D
var _material: ShaderMaterial
var _target: MeshInstance3D
var _target_rest := Transform3D.IDENTITY
var _radius := 1.0
var _shake := 0.0
var _playing := false

## True while the effect is running. [method trigger] is ignored in that state.
var is_playing: bool:
	get: return _playing


func _ready() -> void:
	_build_sphere()
	set_process(false)


func _process(delta: float) -> void:
	# Anticipation rumble, only while the sphere is charging.
	if _target == null or _shake <= 0.0:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var offset := Vector3(
		sin(t * 47.0) * _shake,
		sin(t * 61.0) * _shake * 0.5,
		cos(t * 53.0) * _shake,
	)
	_target.transform.origin = _target_rest.origin + offset


## Runs the full charge -> flash -> swap -> dissipate sequence. Does nothing if
## the effect is already playing.
func trigger() -> void:
	if _playing:
		return
	_target = _resolve_target()
	if _target == null:
		push_warning("MegaEvolution: no target MeshInstance3D found (set target_path).")
		return

	_playing = true
	_target_rest = _target.transform
	_fit_to_target()

	_sphere.visible = true
	_sphere.scale = Vector3.ONE * 0.001
	_light.light_energy = 0.0
	_light.visible = true
	_set_progress(0.0)
	_set_flash(0.0)
	_set_fade(1.0)
	set_process(true)
	charge_started.emit()

	# Sequential by default; parallel() joins a tweener onto the previous one.
	var tween := create_tween()

	# --- charge: sphere swells around the creature, rumble builds ---
	tween.tween_property(_sphere, "scale", Vector3.ONE * _radius, charge_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_method(_set_progress, 0.0, 1.0, charge_time)
	tween.parallel().tween_property(_light, "light_energy", light_energy, charge_time) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.parallel().tween_method(_set_shake, 0.0, shake_amount, charge_time) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)

	# --- flash: everything goes white, and the swap hides inside it ---
	tween.tween_method(_set_flash, 0.0, 1.0, flash_time * 0.4)
	tween.tween_callback(_do_swap)
	tween.tween_interval(flash_time * 0.6)

	# --- dissipate: shell blows outward and fades off the new form ---
	tween.tween_method(_set_fade, 1.0, 0.0, dissipate_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_method(_set_flash, 1.0, 0.0, dissipate_time * 0.5)
	tween.parallel().tween_property(_sphere, "scale", Vector3.ONE * _radius * 1.7, dissipate_time) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_light, "light_energy", 0.0, dissipate_time)

	tween.tween_callback(_finish)


func _build_sphere() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("color_a", color_a)
	_material.set_shader_parameter("color_b", color_b)
	_material.set_shader_parameter("color_core", color_core)

	_sphere = MeshInstance3D.new()
	_sphere.name = "EnergySphere"
	_sphere.mesh = sphere
	_sphere.material_override = _material
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shell is procedurally wobbled in the vertex shader and can wander well
	# outside its mesh AABB, so stop the culler from popping it.
	_sphere.extra_cull_margin = 4.0
	_sphere.visible = false
	add_child(_sphere)

	_light = OmniLight3D.new()
	_light.name = "EnergyLight"
	_light.light_color = color_b.lerp(color_a, 0.5)
	_light.light_energy = 0.0
	_light.omni_range = 14.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)


func _resolve_target() -> MeshInstance3D:
	if not target_path.is_empty():
		return get_node_or_null(target_path) as MeshInstance3D
	return get_parent() as MeshInstance3D


## Centres and sizes the sphere on the larger of the two forms, so the swap is
## never visible through the shell.
func _fit_to_target() -> void:
	var aabb := _target.get_aabb()
	if evolved_mesh != null:
		aabb = aabb.merge(evolved_mesh.get_aabb())

	var to_us := global_transform.affine_inverse() * _target.global_transform
	_sphere.position = to_us * aabb.get_center()
	_light.position = _sphere.position

	var world_scale := _target.global_transform.basis.get_scale()
	var half := aabb.size * 0.5 * maxf(world_scale.x, maxf(world_scale.y, world_scale.z))
	_radius = maxf(half.x, maxf(half.y, half.z)) * radius_padding
	_light.omni_range = _radius * 6.0


func _do_swap() -> void:
	# Rumble stops here -- the new form arrives settled, not still shaking.
	_shake = 0.0
	if _target != null:
		_target.transform.origin = _target_rest.origin
	if swap_mesh and evolved_mesh != null:
		_target.mesh = evolved_mesh
		if evolved_material != null:
			_target.material_override = evolved_material
		if not is_equal_approx(evolved_scale, 1.0):
			_target.scale = _target_rest.basis.get_scale() * evolved_scale
	evolved.emit()


func _finish() -> void:
	set_process(false)
	_shake = 0.0
	_sphere.visible = false
	_light.visible = false
	if _target != null:
		_target.transform.origin = _target_rest.origin
	_playing = false
	finished.emit()


func _set_progress(v: float) -> void:
	_material.set_shader_parameter("progress", v)


func _set_flash(v: float) -> void:
	_material.set_shader_parameter("flash", v)


func _set_fade(v: float) -> void:
	_material.set_shader_parameter("fade", v)


func _set_shake(v: float) -> void:
	_shake = v

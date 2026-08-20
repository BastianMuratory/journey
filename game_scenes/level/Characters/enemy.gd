extends CharacterBody3D

signal defeated(enemy: Node3D)

const ALLY_COLLISION_LAYER := 2
const ENEMY_COLLISION_LAYER := 4

@export var max_health: float = 100.0
@export var attack_range: float = 0.9
@export var attack_cooldown: float = 2.0
@export var visual_scale: float = 0.38
@export var visual_yaw: float = PI
@export var pokemon_data: PokemonBaseData:
	set(value):
		pokemon_data = value
		_apply_pokemon_visual()
@export var shiny: bool = false:
	set(value):
		shiny = value
		_apply_pokemon_visual()

@onready var visual = $Visual
@onready var health_bar: Node3D = $HealthBar
@onready var health_bar_fill: Node3D = $HealthBar/Fill
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var current_health: float = 100.0


func _ready() -> void:
	collision_layer = ENEMY_COLLISION_LAYER
	collision_mask = ALLY_COLLISION_LAYER | ENEMY_COLLISION_LAYER
	current_health = max_health
	_prepare_collision_shape()
	_apply_visual_transform()
	_apply_pokemon_visual()
	_apply_collision_shape()
	_build_animations()
	_update_health_bar()
	animation_player.play("idle")


func set_pokemon_data(data: PokemonBaseData, use_shiny: bool = false) -> void:
	pokemon_data = data
	shiny = use_shiny
	_apply_pokemon_visual()


func _apply_pokemon_visual() -> void:
	if visual == null:
		return
	if visual.has_method("set_species") and pokemon_data != null:
		visual.set_species(pokemon_data)
	visual.shiny = shiny
	_apply_collision_shape()


func _prepare_collision_shape() -> void:
	if collision_shape != null and collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()


func _apply_collision_shape() -> void:
	if collision_shape == null or pokemon_data == null or pokemon_data.mesh == null:
		return

	var aabb := pokemon_data.mesh.get_aabb()
	var scaled_size := aabb.size * pokemon_data.model_scale * visual_scale
	var diameter := maxf(maxf(scaled_size.x, scaled_size.z), 0.5)
	var height := maxf(scaled_size.y, 0.45)
	var box_shape := collision_shape.shape as BoxShape3D
	if box_shape != null:
		box_shape.size = Vector3(diameter, height, diameter)
	else:
		var sphere_shape := collision_shape.shape as SphereShape3D
		if sphere_shape != null:
			sphere_shape.radius = maxf(diameter, height) * 0.5

	collision_shape.position.y = height * 0.5
	health_bar.position.y = height + 0.45


func _apply_visual_transform() -> void:
	if visual == null:
		return
	visual.rotation.y = visual_yaw
	visual.scale = Vector3.ONE * visual_scale


func _visual_scale(scale: Vector3 = Vector3.ONE) -> Vector3:
	return scale * visual_scale


func take_damage(amount: float) -> void:
	current_health = clampf(current_health - amount, 0.0, max_health)
	_update_health_bar()
	if current_health <= 0.0:
		defeated.emit(self)


func attack(target, damage: float) -> void:
	if is_defeated() or target == null or not is_instance_valid(target) or target.is_defeated():
		return

	face_position(target.global_position)
	animation_player.play("attack")
	await animation_player.animation_finished
	if is_instance_valid(target) and not target.is_defeated() and not is_defeated():
		target.take_damage(damage)
	animation_player.play("idle")


func face_position(target_position: Vector3) -> void:
	var direction := global_position.direction_to(target_position)
	if direction.length() > 0.0:
		look_at(Vector3(target_position.x, global_position.y, target_position.z), Vector3.UP)


func is_defeated() -> bool:
	return current_health <= 0.0


func ground_position() -> Vector3:
	return Vector3(global_position.x, 0.0, global_position.z)


func collision_radius() -> float:
	if collision_shape == null or collision_shape.shape == null:
		return 0.0
	var box_shape := collision_shape.shape as BoxShape3D
	if box_shape != null:
		return maxf(box_shape.size.x, box_shape.size.z) * 0.5
	var sphere_shape := collision_shape.shape as SphereShape3D
	if sphere_shape != null:
		return sphere_shape.radius
	return 0.0


func _update_health_bar() -> void:
	var health_ratio := 0.0
	if max_health > 0.0:
		health_ratio = current_health / max_health
	health_bar_fill.scale.x = health_ratio
	health_bar_fill.position.x = -0.5 * (1.0 - health_ratio)


func _process(_delta: float) -> void:
	_face_health_bar_to_camera()


func _face_health_bar_to_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	health_bar.look_at(camera.global_position, Vector3.UP)
	health_bar.rotate_object_local(Vector3.RIGHT, -PI * 0.5)


func _build_animations() -> void:
	var library := AnimationLibrary.new()
	library.add_animation("idle", _create_idle_animation())
	library.add_animation("attack", _create_attack_animation())

	if animation_player.has_animation_library(""):
		animation_player.remove_animation_library("")
	animation_player.add_animation_library("", library)


func _create_idle_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 0.1

	var position_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(position_track, NodePath("Visual:position"))
	animation.track_insert_key(position_track, 0.0, Vector3(0.0, 0.4, 0.0))

	var scale_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(scale_track, NodePath("Visual:scale"))
	animation.track_insert_key(scale_track, 0.0, _visual_scale())

	return animation


func _create_attack_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 0.3

	var position_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(position_track, NodePath("Visual:position"))
	animation.track_insert_key(position_track, 0.0, Vector3(0.0, 0.4, 0.0))
	animation.track_insert_key(position_track, 0.1, Vector3(0.0, 0.5, -0.28))
	animation.track_insert_key(position_track, 0.22, Vector3(0.0, 0.4, 0.0))

	var scale_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(scale_track, NodePath("Visual:scale"))
	animation.track_insert_key(scale_track, 0.0, _visual_scale())
	animation.track_insert_key(scale_track, 0.1, _visual_scale(Vector3(1.15, 0.9, 1.15)))
	animation.track_insert_key(scale_track, 0.22, _visual_scale())

	return animation

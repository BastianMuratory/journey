extends CharacterBody3D

signal arrived
signal attack_finished
signal defeated(player: Node3D)

const ALLY_COLLISION_LAYER := 2
const ENEMY_COLLISION_LAYER := 4
const NAVIGATION_PATH_DESIRED_DISTANCE := 0.06
const NAVIGATION_TARGET_DESIRED_DISTANCE := 0.16

@export var move_speed: float = 3.0
@export var arrival_distance: float = 0.05
@export var attack_range: float = 1.0
@export var attack_cooldown: float = 2.0
@export var max_health: float = 100.0
@export var current_health: float = 100.0
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

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var visual = $Visual
@onready var health_bar: Node3D = $HealthBar
@onready var health_bar_fill: Node3D = $HealthBar/Fill
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var navigation_agent: NavigationAgent3D
var _target_position: Vector3
var _path: Array[Vector3] = []
var _has_target: bool = false
var _uses_navigation_agent: bool = false
var _safe_navigation_velocity := Vector3.ZERO


func _ready() -> void:
	collision_layer = ALLY_COLLISION_LAYER
	collision_mask = ENEMY_COLLISION_LAYER
	_target_position = global_position
	_setup_navigation_agent()
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


func display_name() -> String:
	return pokemon_data.display_name if pokemon_data != null else name


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
	if navigation_agent != null:
		navigation_agent.radius = maxf(collision_radius(), 0.35)


func _apply_visual_transform() -> void:
	if visual == null:
		return
	visual.rotation.y = visual_yaw
	visual.scale = Vector3.ONE * visual_scale


func _visual_scale(scale: Vector3 = Vector3.ONE) -> Vector3:
	return scale * visual_scale


func set_health(value: float) -> void:
	current_health = clampf(value, 0.0, max_health)
	_update_health_bar()
	if current_health <= 0.0:
		_defeat()


func take_damage(amount: float) -> void:
	set_health(current_health - amount)


func is_defeated() -> bool:
	return current_health <= 0.0


func move_along_path(path: Array[Vector3]) -> void:
	if is_defeated():
		return
	if navigation_agent != null and not path.is_empty():
		move_to_navigation_target(path[path.size() - 1])
		return

	_path = path.duplicate()
	_uses_navigation_agent = false
	if _path.is_empty():
		_has_target = false
		animation_player.play("idle")
		arrived.emit()
		return

	_set_next_path_target()
	_has_target = true
	if animation_player.current_animation != "hop_run":
		animation_player.play("hop_run")


func move_to_navigation_target(target_position: Vector3) -> void:
	if is_defeated():
		return
	if navigation_agent == null:
		move_along_path([target_position])
		return

	_path.clear()
	_target_position = Vector3(target_position.x, global_position.y, target_position.z)
	_safe_navigation_velocity = Vector3.ZERO
	navigation_agent.target_position = _target_position
	_has_target = true
	_uses_navigation_agent = true
	if animation_player.current_animation != "hop_run":
		animation_player.play("hop_run")


func face_position(target_position: Vector3) -> void:
	if is_defeated():
		return

	var direction := global_position.direction_to(target_position)
	if direction.length() > 0.0:
		look_at(Vector3(target_position.x, global_position.y, target_position.z), Vector3.UP)


func attack() -> void:
	if is_defeated():
		return

	_has_target = false
	animation_player.play("attack")
	await animation_player.animation_finished
	animation_player.play("idle")
	attack_finished.emit()


func is_moving() -> bool:
	return _has_target


func stop_moving() -> void:
	_has_target = false
	_uses_navigation_agent = false
	_path.clear()
	velocity = Vector3.ZERO
	_safe_navigation_velocity = Vector3.ZERO
	animation_player.play("idle")


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


func current_walk_target() -> Vector3:
	return _target_position


func current_walk_path() -> Array[Vector3]:
	if not _has_target:
		return []
	if _uses_navigation_agent:
		return [_target_position]

	var current_path: Array[Vector3] = [_target_position]
	current_path.append_array(_path)
	return current_path


func _defeat() -> void:
	_has_target = false
	_uses_navigation_agent = false
	velocity = Vector3.ZERO
	_safe_navigation_velocity = Vector3.ZERO
	visible = false
	collision_shape.set_deferred("disabled", true)
	defeated.emit(self)


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


func _physics_process(delta: float) -> void:
	if not _has_target:
		velocity = Vector3.ZERO
		if navigation_agent != null:
			navigation_agent.velocity = Vector3.ZERO
		return
	if _uses_navigation_agent:
		_follow_navigation_agent(delta)
		return

	var distance := global_position.distance_to(_target_position)
	if distance <= maxf(arrival_distance, move_speed * delta):
		global_position = _target_position
		_set_next_path_target()
		return

	var direction := global_position.direction_to(_target_position)
	velocity = Vector3(direction.x, 0.0, direction.z) * move_speed
	move_and_slide()


func _setup_navigation_agent() -> void:
	navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if navigation_agent == null:
		navigation_agent = NavigationAgent3D.new()
		navigation_agent.name = "NavigationAgent3D"
		add_child(navigation_agent)
	navigation_agent.path_desired_distance = NAVIGATION_PATH_DESIRED_DISTANCE
	navigation_agent.target_desired_distance = maxf(arrival_distance, NAVIGATION_TARGET_DESIRED_DISTANCE)
	navigation_agent.radius = maxf(collision_radius(), 0.35)
	navigation_agent.max_speed = move_speed
	navigation_agent.avoidance_enabled = true
	navigation_agent.neighbor_distance = 2.4
	navigation_agent.max_neighbors = 12
	navigation_agent.time_horizon_agents = 0.7
	if not navigation_agent.velocity_computed.is_connected(_on_navigation_velocity_computed):
		navigation_agent.velocity_computed.connect(_on_navigation_velocity_computed)


func _follow_navigation_agent(delta: float) -> void:
	if global_position.distance_to(_target_position) <= maxf(navigation_agent.target_desired_distance, move_speed * delta):
		velocity = Vector3.ZERO
		_safe_navigation_velocity = Vector3.ZERO
		_has_target = false
		_uses_navigation_agent = false
		animation_player.play("idle")
		arrived.emit()
		return
	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		_safe_navigation_velocity = Vector3.ZERO
		_has_target = false
		_uses_navigation_agent = false
		animation_player.play("idle")
		arrived.emit()
		return

	var next_position := navigation_agent.get_next_path_position()
	var direction := global_position.direction_to(next_position)
	if direction.length() <= 0.0:
		return

	var desired_velocity := Vector3(direction.x, 0.0, direction.z) * move_speed
	navigation_agent.velocity = desired_velocity
	velocity = _safe_navigation_velocity if _safe_navigation_velocity.length() > 0.0 else desired_velocity
	face_position(next_position)
	move_and_slide()


func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_navigation_velocity = Vector3(safe_velocity.x, 0.0, safe_velocity.z)


func _set_next_path_target() -> void:
	if _path.is_empty():
		velocity = Vector3.ZERO
		_has_target = false
		animation_player.play("idle")
		arrived.emit()
		return

	_target_position = _path.pop_front()
	_target_position.y = global_position.y
	face_position(_target_position)


func _build_animations() -> void:
	var library := AnimationLibrary.new()
	library.add_animation("idle", _create_idle_animation())
	library.add_animation("hop_run", _create_hop_run_animation())
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


func _create_hop_run_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 0.4
	animation.loop_mode = Animation.LOOP_LINEAR

	var position_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(position_track, NodePath("Visual:position"))
	animation.track_insert_key(position_track, 0.0, Vector3(0.0, 0.4, 0.0))
	animation.track_insert_key(position_track, 0.2, Vector3(0.0, 0.8, 0.0))
	animation.track_insert_key(position_track, 0.4, Vector3(0.0, 0.4, 0.0))

	var scale_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(scale_track, NodePath("Visual:scale"))
	animation.track_insert_key(scale_track, 0.0, _visual_scale(Vector3(1.08, 0.9, 1.08)))
	animation.track_insert_key(scale_track, 0.2, _visual_scale(Vector3(0.94, 1.12, 0.94)))
	animation.track_insert_key(scale_track, 0.4, _visual_scale(Vector3(1.08, 0.9, 1.08)))

	return animation


func _create_attack_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 0.35

	var position_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(position_track, NodePath("Visual:position"))
	animation.track_insert_key(position_track, 0.0, Vector3(0.0, 0.4, 0.0))
	animation.track_insert_key(position_track, 0.12, Vector3(0.0, 0.55, -0.35))
	animation.track_insert_key(position_track, 0.25, Vector3(0.0, 0.4, 0.0))

	var scale_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(scale_track, NodePath("Visual:scale"))
	animation.track_insert_key(scale_track, 0.0, _visual_scale())
	animation.track_insert_key(scale_track, 0.12, _visual_scale(Vector3(1.2, 0.85, 1.2)))
	animation.track_insert_key(scale_track, 0.25, _visual_scale())

	return animation

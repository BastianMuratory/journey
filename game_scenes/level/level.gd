extends Node3D

const PLAYER_SCENE := preload("res://game_scenes/level/Characters/MeleePlayer.tscn")
const RANGED_PLAYER_SCENE := preload("res://game_scenes/level/Characters/RangedPlayer.tscn")
const ENEMY_SCENE := preload("res://game_scenes/level/Characters/MeleeEnemy.tscn")
const RANGED_ENEMY_SCENE := preload("res://game_scenes/level/Characters/RangedEnemy.tscn")
const CAMERA_FOLLOW_SCRIPT := preload("res://game_scenes/level/Camera/camera_follow.gd")
const RANDOM_LEVEL_BUILDER_SCRIPT := preload("res://game_scenes/level/Generation/random_level_builder.gd")
const DEBUG_WALKING_LINES_SCRIPT := preload("res://game_scenes/level/Navigation/debug_walking_lines.gd")
const GRID_NAVIGATION_SCRIPT := preload("res://game_scenes/level/Navigation/grid_navigation.gd")
const LEVEL_NAVIGATION_REGION_SCRIPT := preload("res://game_scenes/level/Navigation/level_navigation_region.gd")
const LEVEL_PATHING_SCRIPT := preload("res://game_scenes/level/Navigation/level_pathing.gd")
const SKILL_EFFECTS_SCRIPT := preload("res://game_scenes/level/UI/skill_effects.gd")
const PLAYER_SCENES := [PLAYER_SCENE, RANGED_PLAYER_SCENE, RANGED_PLAYER_SCENE]
const PLAYER_SPAWN_SLOT_ORDER := [1, 0, 2]
const IDLE_RETARGET_INTERVAL := 0.25
const PLAYER_REPATH_INTERVAL := 0.22
const PLAYER_STUCK_DISTANCE := 0.04
const PLAYER_STUCK_REPATH_TIME := 0.45
const PLAYER_SLOT_REACHED_DISTANCE := 0.35
const SKILL_DAMAGE_MULTIPLIERS := [1.0, 1.75]
const AUTO_SKILL_INTERVAL := 0.35

@export var grid_half_extents: Vector2i = Vector2i(10, 10)
@export var cell_size: float = 1.0
@export var min_enemy_count: int = 1
@export var max_enemy_count: int = 5
@export var enemy_cluster_radius: int = 3
@export var minimum_actor_spacing: float = 1.1
@export var enemy_spawn_delay: float = 0.45
@export var enemy_height: float = 0.0
@export var player_attack_damage: float = 35.0
@export var enemy_attack_damage: float = 12.0
@export var enemy_aggro_range: float = 2.25
@export var skill_cooldown: float = 4.0
@export_range(0.0, 1.0) var ranged_enemy_chance: float = 0.35
@export var camera_follow_speed: float = 8.0
@export var camera_offset: Vector3 = Vector3(0.0, 9.0, 9.0)
@export var show_debug_walking_lines: bool = false
@export var ally_pokemon_paths: Array[String] = [
	"res://data/pokemon_base_data/0002_ivysaur.tres",
	"res://data/pokemon_base_data/0255_torchic.tres",
	"res://data/pokemon_base_data/0194_wooper.tres",
]
@export var melee_enemy_pokemon_paths: Array[String] = [
	"res://data/pokemon_base_data/0371_bagon.tres",
	"res://data/pokemon_base_data/0231_phanpy.tres",
	"res://data/pokemon_base_data/0372_shelgon.tres",
]
@export var ranged_enemy_pokemon_paths: Array[String] = [
	"res://data/pokemon_base_data/0044_gloom.tres",
	"res://data/pokemon_base_data/0069_bellsprout.tres",
]

@onready var players_root: Node3D = $Players
@onready var enemies_root: Node3D = $Enemies
@onready var camera: Camera3D = $Camera3D
@onready var floor: MeshInstance3D = $Floor
@onready var auto_button: Button = $HUD/BottomPanel/PanelRow/AutoButton
@onready var character_panel = $HUD/BottomPanel/PanelRow/CharacterPanel

var _rng := RandomNumberGenerator.new()
var _players: Array[Node3D] = []
var _enemies: Array[Node3D] = []
var _level_cells: Array[Vector2i] = []
var _player_targets: Dictionary = {}
var _player_attack_slots: Dictionary = {}
var _player_slot_targets: Dictionary = {}
var _attacking_players: Array[Node3D] = []
var _attacking_enemy_ids: Array[int] = []
var _next_player_attack_times: Dictionary = {}
var _queued_player_skills: Dictionary = {}
var _next_player_skill_times: Dictionary = {}
var _is_spawning_enemies: bool = false
var _has_spawned_enemy_group: bool = false
var _auto_skills_enabled: bool = false
var _auto_skill_timer: float = 0.0
var _grid_navigation
var _navigation_region: NavigationRegion3D
var _level_pathing
var _skill_effects
var _debug_walking_lines
var _idle_retarget_timer: float = 0.0
var _player_repath_timer: float = 0.0
var _player_last_repath_positions: Dictionary = {}
var _player_stuck_times: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	auto_button.pressed.connect(_on_auto_button_pressed)
	_update_auto_button()
	if character_panel.has_signal("skill_requested"):
		character_panel.skill_requested.connect(_on_skill_requested)
	var level_builder = RANDOM_LEVEL_BUILDER_SCRIPT.new()
	level_builder.generate(_rng)
	_level_cells = level_builder.cells.duplicate()
	grid_half_extents = level_builder.grid_half_extents()
	level_builder.build_floor(self, floor, cell_size)
	_navigation_region = LEVEL_NAVIGATION_REGION_SCRIPT.build(self, _level_cells, cell_size)
	_setup_debug_walking_lines()
	_grid_navigation = GRID_NAVIGATION_SCRIPT.new(grid_half_extents, cell_size, _level_cells)
	_level_pathing = LEVEL_PATHING_SCRIPT.new(_grid_navigation, cell_size, _navigation_region)
	_skill_effects = SKILL_EFFECTS_SCRIPT.new()
	NavigationServer3D.map_force_update(_navigation_region.get_navigation_map())
	await get_tree().physics_frame
	await get_tree().physics_frame
	_spawn_players()
	_spawn_enemy_group()
	_update_camera(1.0)


func _setup_debug_walking_lines() -> void:
	if not OS.is_debug_build() or not show_debug_walking_lines:
		return

	_debug_walking_lines = DEBUG_WALKING_LINES_SCRIPT.new(self)


func _process(delta: float) -> void:
	_update_enemy_group_attacks()
	_update_moving_player_attacks()
	_update_moving_player_repaths(delta)
	_update_auto_skills(delta)
	_update_skill_button_states()
	_update_idle_player_targets(delta)
	if _debug_walking_lines != null:
		_debug_walking_lines.update(_players)
	_update_camera(delta)


func _update_idle_player_targets(delta: float) -> void:
	_idle_retarget_timer -= delta
	if _idle_retarget_timer > 0.0:
		return

	_idle_retarget_timer = IDLE_RETARGET_INTERVAL
	for player in _players:
		if not is_instance_valid(player) or player.is_defeated() or player.is_moving() or player in _attacking_players:
			continue
		var target = _player_targets.get(player)
		if target == null or not is_instance_valid(target) or target.is_defeated() or not _is_target_in_player_range(player, target):
			_assign_player_target(player)
		elif _use_queued_player_skill(player):
			continue
		elif _is_player_attack_ready(player):
			_attack_player_target(player)
		elif not _is_player_at_attack_slot(player):
			_move_player_to_attack_slot(player, target)


func _update_moving_player_attacks() -> void:
	for player in _players:
		if not is_instance_valid(player) or player.is_defeated() or not player.is_moving() or player in _attacking_players:
			continue

		var target = _target_in_player_range(player)
		if target == null:
			if not _has_valid_player_target(player):
				_assign_player_target(player)
			continue
		_player_targets[player] = target

		if _queued_player_skills.has(player) and _is_player_skill_ready(player):
			_stop_player_movement(player)
			_use_queued_player_skill(player)
			continue
		if not _is_player_at_attack_slot(player) and not _is_player_attack_ready(player):
			continue

		_stop_player_movement(player)
		_attack_player_target(player)


func _stop_player_movement(player: Node3D) -> void:
	if player.has_method("stop_moving"):
		player.stop_moving()
	if _debug_walking_lines != null:
		_debug_walking_lines.clear(player)


func _update_moving_player_repaths(delta: float) -> void:
	_player_repath_timer -= delta
	if _player_repath_timer > 0.0:
		return

	_player_repath_timer = PLAYER_REPATH_INTERVAL
	for player in _players:
		if not is_instance_valid(player) or player.is_defeated() or not player.is_moving() or player in _attacking_players:
			continue

		var target = _target_in_player_range(player)
		if target != null:
			_player_targets[player] = target
			if _is_player_at_attack_slot(player):
				_clear_player_stuck_tracking(player)
				continue

			if _update_player_stuck_tracking(player):
				_stop_player_movement(player)
				_assign_player_target(player)
			continue

		var is_stuck := _update_player_stuck_tracking(player)
		target = _player_targets.get(player)
		if target == null or not is_instance_valid(target) or target.is_defeated():
			_assign_player_target(player)
			continue
		if not is_stuck:
			continue

		if player.has_method("stop_moving"):
			player.stop_moving()
		_assign_player_target(player)


func _spawn_players() -> void:
	for index in PLAYER_SCENES.size():
		var player: Node3D = PLAYER_SCENES[index].instantiate()
		if player.has_method("set_pokemon_data"):
			player.set_pokemon_data(_ally_pokemon_data(index))
		players_root.add_child(player)
		player.global_position = _player_spawn_position(index)
		player.arrived.connect(_on_player_arrived.bind(player))
		player.defeated.connect(_on_player_defeated)
		_players.append(player)

	if character_panel.has_method("set_players"):
		character_panel.set_players(_players)


func _ally_pokemon_data(index: int) -> PokemonBaseData:
	if index >= ally_pokemon_paths.size():
		return null

	return load(ally_pokemon_paths[index]) as PokemonBaseData


func _player_spawn_position(index: int) -> Vector3:
	if not _level_cells.is_empty():
		var spawn_cells := _level_cells.duplicate()
		spawn_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y == b.y:
				return a.x < b.x
			return a.y < b.y
		)
		var player_spawn_cells := spawn_cells.slice(0, mini(PLAYER_SCENES.size(), spawn_cells.size()))
		player_spawn_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x
		)
		var spawn_index := index
		if PLAYER_SCENES.size() == 3:
			spawn_index = PLAYER_SPAWN_SLOT_ORDER[index]
		var cell: Vector2i = player_spawn_cells[mini(spawn_index, player_spawn_cells.size() - 1)]
		return Vector3(float(cell.x) * cell_size, 0.0, float(cell.y) * cell_size)

	var spacing := 1.2
	var spawn_index := index
	if PLAYER_SCENES.size() == 3:
		spawn_index = PLAYER_SPAWN_SLOT_ORDER[index]
	var offset := float(spawn_index) - float(PLAYER_SCENES.size() - 1) * 0.5
	return Vector3(offset * spacing, 0.0, -float(grid_half_extents.y) * 0.5)


func _spawn_enemy_group() -> void:
	_is_spawning_enemies = false
	_player_targets.clear()
	_player_attack_slots.clear()
	_player_slot_targets.clear()
	_attacking_players.clear()
	_attacking_enemy_ids.clear()
	_next_player_attack_times.clear()
	_queued_player_skills.clear()
	_next_player_skill_times.clear()
	_clear_enemies()

	var enemy_count := _rng.randi_range(min_enemy_count, max_enemy_count)
	var cluster_center := _enemy_cluster_center()
	for index in enemy_count:
		var enemy: Node3D = _create_enemy(index)
		enemies_root.add_child(enemy)
		enemy.global_position = _random_cluster_position(cluster_center) + Vector3.UP * enemy_height
		enemy.defeated.connect(_on_enemy_defeated)
		_enemies.append(enemy)

	_has_spawned_enemy_group = true
	_assign_all_players()


func _clear_enemies() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()


func _enemy_cluster_center() -> Vector3:
	if not _has_spawned_enemy_group:
		return _first_enemy_cluster_center()
	return _grid_navigation.random_grid_position(_rng)


func _first_enemy_cluster_center() -> Vector3:
	if _level_cells.is_empty() or _players.is_empty():
		return _grid_navigation.random_grid_position(_rng)

	var player_center := Vector3.ZERO
	var living_player_count := 0
	for player in _players:
		if not is_instance_valid(player) or player.is_defeated():
			continue
		player_center += player.global_position
		living_player_count += 1

	if living_player_count <= 0:
		return _grid_navigation.random_grid_position(_rng)

	player_center /= float(living_player_count)
	var farthest_cell := _level_cells[0]
	var farthest_distance := -INF
	for cell in _level_cells:
		var distance: float = _grid_navigation.cell_to_world(cell).distance_squared_to(player_center)
		if distance > farthest_distance:
			farthest_distance = distance
			farthest_cell = cell

	return _grid_navigation.cell_to_world(farthest_cell)


func _random_cluster_position(cluster_center: Vector3) -> Vector3:
	var position := _random_position_near(cluster_center)
	var attempts := 0
	while _is_too_close_to_existing_actor(position) and attempts < 40:
		position = _random_position_near(cluster_center)
		attempts += 1
	return position


func _create_enemy(index: int) -> Node3D:
	var enemy: Node3D
	if index == 0 or _rng.randf() < ranged_enemy_chance:
		enemy = RANGED_ENEMY_SCENE.instantiate()
		_set_enemy_pokemon_data(enemy, ranged_enemy_pokemon_paths)
		return enemy

	enemy = ENEMY_SCENE.instantiate()
	_set_enemy_pokemon_data(enemy, melee_enemy_pokemon_paths)
	return enemy


func _set_enemy_pokemon_data(enemy: Node3D, pokemon_paths: Array[String]) -> void:
	if not enemy.has_method("set_pokemon_data") or pokemon_paths.is_empty():
		return

	var pokemon_data := load(pokemon_paths[_rng.randi_range(0, pokemon_paths.size() - 1)]) as PokemonBaseData
	enemy.set_pokemon_data(pokemon_data)


func _random_position_near(cluster_center: Vector3) -> Vector3:
	return _grid_navigation.random_position_near(cluster_center, _rng, enemy_cluster_radius)


func _is_too_close_to_existing_actor(position: Vector3) -> bool:
	for enemy in _enemies:
		if is_instance_valid(enemy) and enemy.ground_position().distance_to(position) < minimum_actor_spacing:
			return true

	for player in _players:
		if is_instance_valid(player) and player.global_position.distance_to(position) < minimum_actor_spacing:
			return true
	return false


func _assign_all_players() -> void:
	for player in _players:
		_assign_player_target(player)


func _assign_player_target(player: Node3D) -> void:
	if not is_instance_valid(player) or player.is_defeated():
		return
	if player in _attacking_players:
		return

	_release_player_attack_slot(player)
	_player_targets.erase(player)
	if _debug_walking_lines != null:
		_debug_walking_lines.clear(player)
	var targets := _living_enemies_by_distance(player.global_position)
	if targets.is_empty():
		_schedule_next_enemy_group()
		return

	for target in targets:
		if _is_target_in_player_range(player, target):
			_player_targets[player] = target
			if _is_player_attack_ready(player):
				_attack_player_target(player)
			else:
				_move_player_to_attack_slot(player, target)
			return

	for target in targets:
		_player_targets[player] = target
		if _move_player_to_attack_slot(player, target):
			return
		_player_targets.erase(player)
		_release_player_attack_slot(player)


func _target_in_player_range(player: Node3D):
	var current_target = _player_targets.get(player)
	if current_target != null and is_instance_valid(current_target) and not current_target.is_defeated() and _is_target_in_player_range(player, current_target):
		return current_target

	for target in _living_enemies_by_distance(player.global_position):
		if _is_target_in_player_range(player, target):
			return target
	return null


func _has_valid_player_target(player: Node3D) -> bool:
	var target = _player_targets.get(player)
	return target != null and is_instance_valid(target) and not target.is_defeated()


func _move_player_to_attack_slot(player: Node3D, target) -> bool:
	if not is_instance_valid(player) or player.is_defeated() or not is_instance_valid(target) or target.is_defeated():
		return false

	var path := _path_to_enemy(player, target)
	if path.is_empty():
		return false

	var slot_position: Vector3 = path[path.size() - 1]
	_reserve_player_attack_slot(player, target, slot_position)
	if _is_player_at_attack_slot(player):
		return true

	player.move_along_path(path)
	return true


func _reserve_player_attack_slot(player: Node3D, target: Node3D, slot_position: Vector3) -> void:
	_player_attack_slots[player] = slot_position
	_player_slot_targets[player] = target


func _release_player_attack_slot(player: Node3D) -> void:
	_player_attack_slots.erase(player)
	_player_slot_targets.erase(player)


func _is_player_at_attack_slot(player: Node3D) -> bool:
	if not _player_attack_slots.has(player):
		return true

	var slot_position: Vector3 = _player_attack_slots[player]
	return player.global_position.distance_to(slot_position) <= PLAYER_SLOT_REACHED_DISTANCE


func _claimed_attack_slots(player: Node3D) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	for other_player in _players:
		if other_player == player or not is_instance_valid(other_player) or other_player.is_defeated():
			continue

		var slot_target = _player_slot_targets.get(other_player)
		if _player_attack_slots.has(other_player) and slot_target != null and is_instance_valid(slot_target) and not slot_target.is_defeated():
			slots.append(_player_attack_slots[other_player])
			continue

		if other_player.is_moving() and other_player.has_method("current_walk_target"):
			slots.append(other_player.current_walk_target())
	return slots


func _update_player_stuck_tracking(player: Node3D) -> bool:
	var previous_position: Vector3 = _player_last_repath_positions.get(player, player.global_position)
	if previous_position.distance_to(player.global_position) <= PLAYER_STUCK_DISTANCE:
		_player_stuck_times[player] = float(_player_stuck_times.get(player, 0.0)) + PLAYER_REPATH_INTERVAL
	else:
		_player_stuck_times[player] = 0.0
	_player_last_repath_positions[player] = player.global_position
	return float(_player_stuck_times.get(player, 0.0)) >= PLAYER_STUCK_REPATH_TIME


func _clear_player_stuck_tracking(player: Node3D) -> void:
	_player_last_repath_positions.erase(player)
	_player_stuck_times.erase(player)


func _living_enemies_by_distance(from_position: Vector3) -> Array[Node3D]:
	var living_enemies: Array[Node3D] = []
	for enemy in _enemies:
		if is_instance_valid(enemy) and not enemy.is_defeated():
			living_enemies.append(enemy)

	living_enemies.sort_custom(func(a, b) -> bool:
		return from_position.distance_to(a.ground_position()) < from_position.distance_to(b.ground_position())
	)
	return living_enemies


func _on_player_arrived(player: Node3D) -> void:
	_clear_player_stuck_tracking(player)
	if _debug_walking_lines != null:
		_debug_walking_lines.clear(player)
	if _use_queued_player_skill(player):
		return
	_attack_player_target(player)


func _attack_player_target(player: Node3D) -> void:
	if player in _attacking_players:
		return
	if not is_instance_valid(player) or player.is_defeated():
		return
	if not _is_player_attack_ready(player):
		return

	var target = _player_targets.get(player)
	if target == null or not is_instance_valid(target) or target.is_defeated():
		_assign_player_target(player)
		return
	if not _is_target_in_player_range(player, target):
		_assign_player_target(player)
		return

	_attacking_players.append(player)
	player.face_position(target.ground_position())
	await player.attack()
	if not is_instance_valid(player) or player.is_defeated():
		_attacking_players.erase(player)
		return
	if not is_instance_valid(target) or target.is_defeated() or not _is_target_in_player_range(player, target):
		_start_player_attack_cooldown(player)
		_attacking_players.erase(player)
		if _use_queued_player_skill(player):
			return
		_assign_player_target(player)
		return

	target.take_damage(player_attack_damage)
	_start_player_attack_cooldown(player)
	if not is_instance_valid(target) or target.is_defeated():
		_attacking_players.erase(player)
		if _use_queued_player_skill(player):
			return
		_assign_player_target(player)
		return

	player.face_position(target.ground_position())
	_attacking_players.erase(player)
	if is_instance_valid(player) and not player.is_defeated():
		if _use_queued_player_skill(player):
			return
		_assign_player_target(player)


func _is_player_attack_ready(player: Node3D) -> bool:
	return Time.get_ticks_msec() >= int(_next_player_attack_times.get(player, 0))


func _start_player_attack_cooldown(player: Node3D) -> void:
	_next_player_attack_times[player] = Time.get_ticks_msec() + int(player.attack_cooldown * 1000.0)


func _on_skill_requested(player: Node3D, skill_index: int) -> void:
	if not is_instance_valid(player) or player.is_defeated():
		return
	if not _is_player_skill_ready(player):
		return

	_queued_player_skills[player] = skill_index
	if player in _attacking_players or player.is_moving():
		return

	_use_queued_player_skill(player)


func _use_queued_player_skill(player: Node3D) -> bool:
	if not is_instance_valid(player) or player.is_defeated() or not _queued_player_skills.has(player):
		return false

	var skill_index := int(_queued_player_skills[player])
	if not _start_player_skill(player, skill_index):
		return false

	_queued_player_skills.erase(player)
	return true


func _start_player_skill(player: Node3D, skill_index: int) -> bool:
	if not is_instance_valid(player) or player.is_defeated():
		return false
	if player in _attacking_players:
		return false
	if not _is_player_skill_ready(player):
		return false

	var target = _player_targets.get(player)
	if target == null or not is_instance_valid(target) or target.is_defeated():
		target = _nearest_living_enemy(player.global_position)
	if target == null:
		return false

	_player_targets[player] = target
	if not _is_target_in_player_range(player, target):
		_move_player_to_attack_slot(player, target)
		return false

	_stop_player_movement(player)
	_player_skill_loop(player, target, skill_index)
	return true


func _player_skill_loop(player: Node3D, target: Node3D, skill_index: int) -> void:
	_attacking_players.append(player)

	if not is_instance_valid(player) or player.is_defeated():
		_attacking_players.erase(player)
		return
	if not is_instance_valid(target) or target.is_defeated() or not _is_target_in_player_range(player, target):
		_attacking_players.erase(player)
		_assign_player_target(player)
		return

	_start_player_skill_cooldown(player)
	player.face_position(target.ground_position())
	await player.attack()
	await _skill_effects.play(self, player, target, skill_index)
	if is_instance_valid(target) and not target.is_defeated():
		target.take_damage(player_attack_damage * _skill_damage_multiplier(skill_index))

	_attacking_players.erase(player)
	if is_instance_valid(player) and not player.is_defeated():
		_assign_player_target(player)


func _skill_damage_multiplier(skill_index: int) -> float:
	return float(SKILL_DAMAGE_MULTIPLIERS[clampi(skill_index, 0, SKILL_DAMAGE_MULTIPLIERS.size() - 1)])


func _is_player_skill_ready(player: Node3D) -> bool:
	return Time.get_ticks_msec() >= int(_next_player_skill_times.get(player, 0))


func _start_player_skill_cooldown(player: Node3D) -> void:
	_next_player_skill_times[player] = Time.get_ticks_msec() + int(skill_cooldown * 1000.0)


func _on_auto_button_pressed() -> void:
	_auto_skills_enabled = not _auto_skills_enabled
	_auto_skill_timer = 0.0
	_update_auto_button()


func _update_auto_skills(delta: float) -> void:
	if not _auto_skills_enabled:
		return

	_auto_skill_timer -= delta
	if _auto_skill_timer > 0.0:
		return

	_auto_skill_timer = AUTO_SKILL_INTERVAL
	var ready_players := _ready_skill_players()
	if ready_players.is_empty():
		return

	var player: Node3D = ready_players[_rng.randi_range(0, ready_players.size() - 1)]
	var skill_index := _rng.randi_range(0, SKILL_DAMAGE_MULTIPLIERS.size() - 1)
	_queued_player_skills[player] = skill_index
	if not player in _attacking_players and not player.is_moving():
		_use_queued_player_skill(player)


func _ready_skill_players() -> Array[Node3D]:
	var ready_players: Array[Node3D] = []
	for player in _players:
		if not is_instance_valid(player) or player.is_defeated():
			continue
		if _is_player_skill_ready(player):
			ready_players.append(player)
	return ready_players


func _update_auto_button() -> void:
	auto_button.text = "AUTO\nON" if _auto_skills_enabled else "AUTO"
	auto_button.add_theme_font_size_override("font_size", 12)
	auto_button.add_theme_color_override("font_color", Color.WHITE)
	auto_button.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	auto_button.add_theme_constant_override("shadow_offset_x", 1)
	auto_button.add_theme_constant_override("shadow_offset_y", 1)
	auto_button.add_theme_stylebox_override("normal", _auto_button_style(_auto_skills_enabled))
	auto_button.add_theme_stylebox_override("hover", _auto_button_style(_auto_skills_enabled, 0.08))
	auto_button.add_theme_stylebox_override("pressed", _auto_button_style(_auto_skills_enabled, -0.12))


func _auto_button_style(active: bool, brightness_offset: float = 0.0) -> StyleBoxFlat:
	var color := Color(0.97, 0.57, 0.06, 0.96)
	if active:
		color = Color(0.18, 0.76, 0.22, 0.96)
	if brightness_offset > 0.0:
		color = color.lightened(brightness_offset)
	elif brightness_offset < 0.0:
		color = color.darkened(absf(brightness_offset))

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(1.0, 1.0, 1.0, 0.86)
	style.set_border_width_all(4)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.24)
	style.shadow_size = 3
	return style


func _update_skill_button_states() -> void:
	if not character_panel.has_method("set_player_skill_ready"):
		return

	for player in _players:
		if is_instance_valid(player):
			character_panel.set_player_skill_ready(player, _is_player_skill_ready(player))


func _is_target_in_player_range(player: Node3D, target) -> bool:
	return player.global_position.distance_to(target.ground_position()) <= player.attack_range + _collision_radius(player) + _collision_radius(target) + 0.05


func _nearest_living_enemy(from_position: Vector3):
	var nearest_enemy = null
	var nearest_distance := INF
	for enemy in _enemies:
		if not is_instance_valid(enemy) or enemy.is_defeated():
			continue

		var distance := from_position.distance_to(enemy.ground_position())
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_enemy = enemy
	return nearest_enemy


func _update_enemy_group_attacks() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy) and not enemy.is_defeated() and not enemy.get_instance_id() in _attacking_enemy_ids and _nearest_living_player_in_enemy_range(enemy) != null:
			_enemy_attack_loop(enemy)


func _enemy_attack_loop(enemy: Node3D) -> void:
	var enemy_id := enemy.get_instance_id()
	_attacking_enemy_ids.append(enemy_id)
	while is_instance_valid(enemy) and not enemy.is_defeated() and enemy in _enemies:
		var target = _nearest_living_player_in_enemy_range(enemy)
		if target == null:
			break

		await enemy.attack(target, enemy_attack_damage)
		if not is_instance_valid(enemy) or enemy.is_defeated():
			break

		await get_tree().create_timer(enemy.attack_cooldown).timeout

	_attacking_enemy_ids.erase(enemy_id)


func _nearest_living_player_in_enemy_range(enemy: Node3D):
	var nearest_player = null
	var nearest_distance := INF
	for player in _players:
		if not is_instance_valid(player) or player.is_defeated():
			continue
		if not _is_player_in_enemy_range(enemy, player):
			continue

		var distance: float = enemy.ground_position().distance_to(player.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_player = player
	return nearest_player


func _is_player_in_enemy_range(enemy: Node3D, player: Node3D) -> bool:
	var attack_circle_range: float = maxf(enemy.attack_range, enemy_aggro_range)
	return enemy.ground_position().distance_to(player.global_position) <= attack_circle_range + _collision_radius(enemy) + _collision_radius(player) + cell_size * 0.15


func _collision_radius(actor: Node3D) -> float:
	if actor.has_method("collision_radius"):
		return actor.collision_radius()
	return 0.0


func _on_player_defeated(player: Node3D) -> void:
	_players.erase(player)
	_attacking_players.erase(player)
	_player_targets.erase(player)
	_release_player_attack_slot(player)
	_next_player_attack_times.erase(player)
	_queued_player_skills.erase(player)
	_clear_player_stuck_tracking(player)
	if character_panel.has_method("set_players"):
		character_panel.set_players(_players)
	if _debug_walking_lines != null:
		_debug_walking_lines.clear(player)
	if _players.is_empty():
		return

	_assign_all_players()


func _on_enemy_defeated(enemy: Node3D) -> void:
	_enemies.erase(enemy)
	for player in _player_targets.keys():
		if _player_targets[player] == enemy:
			_player_targets.erase(player)
			_release_player_attack_slot(player)
	for player in _player_slot_targets.keys():
		if _player_slot_targets[player] == enemy:
			_release_player_attack_slot(player)

	enemy.queue_free()
	if _enemies.is_empty():
		_schedule_next_enemy_group()
	else:
		_assign_all_players()


func _schedule_next_enemy_group() -> void:
	if _is_spawning_enemies:
		return

	_is_spawning_enemies = true
	await get_tree().create_timer(enemy_spawn_delay).timeout
	_spawn_enemy_group()


func _path_to_enemy(player: Node3D, enemy) -> Array[Vector3]:
	return _level_pathing.path_to_enemy(player, enemy, _enemies, _players, _claimed_attack_slots(player))


func _update_camera(delta: float) -> void:
	CAMERA_FOLLOW_SCRIPT.update(camera, _players, camera_offset, camera_follow_speed, delta)

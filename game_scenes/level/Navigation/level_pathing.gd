extends RefCounted

const MOVE_COLLISION_RADIUS := 0.45
const MOVE_SEGMENT_SAMPLE_DISTANCE := 0.2
const ATTACK_SLOT_COUNT := 24
const ATTACK_SLOT_SEPARATION := 0.75
const ATTACK_SLOT_DEDUPLICATION_DISTANCE := 0.12

var grid_navigation
var cell_size: float
var navigation_region: NavigationRegion3D


func _init(initial_grid_navigation, initial_cell_size: float, initial_navigation_region: NavigationRegion3D = null) -> void:
	grid_navigation = initial_grid_navigation
	cell_size = initial_cell_size
	navigation_region = initial_navigation_region


func path_to_enemy(
	player: Node3D,
	enemy,
	enemies: Array[Node3D],
	players: Array[Node3D],
	claimed_positions: Array[Vector3] = []
) -> Array[Vector3]:
	if not is_instance_valid(player) or not is_instance_valid(enemy):
		return []
	if navigation_region != null:
		var navigation_destination: Variant = navigation_destination_to_enemy(player, enemy, claimed_positions)
		if navigation_destination != null:
			return [navigation_destination]

	var destination := attack_position_for(player.global_position, enemy.ground_position(), player.attack_range)
	var destination_cell: Vector2i = grid_navigation.world_to_cell(destination)
	var ally_blocked := ally_blocked_cells(player, players)
	var direct_path_safe := not destination_cell in ally_blocked and not is_position_claimed(destination, claimed_positions) and is_move_segment_safe(player.global_position, destination, player, players, enemies, enemy)
	if direct_path_safe:
		return [destination]

	var empty_blocked_cells: Array[Vector2i] = []
	var blocked_cells := ally_blocked.duplicate()
	for claimed_position in claimed_positions:
		var claimed_cell: Vector2i = grid_navigation.world_to_cell(claimed_position)
		if not claimed_cell in blocked_cells:
			blocked_cells.append(claimed_cell)
	var path: Array[Vector3] = grid_navigation.find_path_to_enemy(player, enemy, enemies, blocked_cells)
	if not path.is_empty():
		return path

	path = grid_navigation.find_path_to_enemy(player, enemy, enemies, empty_blocked_cells)
	if not path.is_empty() and not is_position_claimed(path[path.size() - 1], claimed_positions):
		return path

	if direct_path_safe:
		return [destination]
	return []


func navigation_destination_to_enemy(player: Node3D, enemy, claimed_positions: Array[Vector3] = []):
	return navigation_attack_position_for(player.global_position, enemy.ground_position(), player.attack_range, claimed_positions)


func navigation_attack_position_for(from_position: Vector3, target_position: Vector3, attack_range: float, claimed_positions: Array[Vector3] = []):
	var map := navigation_region.get_navigation_map()
	var target_ground_position := Vector3(target_position.x, 0.0, target_position.z)
	var candidates: Array[Vector3] = []
	for index in ATTACK_SLOT_COUNT:
		var angle := TAU * float(index) / float(ATTACK_SLOT_COUNT)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var desired_position := target_ground_position + direction * maxf(attack_range * 0.85, 0.35)
		var candidate := NavigationServer3D.map_get_closest_point(map, desired_position)
		candidate.y = 0.0
		if candidate.distance_to(target_ground_position) > attack_range + cell_size * 0.35:
			continue
		if is_position_claimed(candidate, claimed_positions):
			continue
		if not _has_nearby_position(candidate, candidates, ATTACK_SLOT_DEDUPLICATION_DISTANCE):
			candidates.append(candidate)

	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return from_position.distance_to(a) < from_position.distance_to(b)
	)
	for candidate in candidates:
		var path := NavigationServer3D.map_get_path(map, from_position, candidate, true)
		if path.size() > 1 and path[path.size() - 1].distance_to(candidate) <= cell_size * 0.5:
			return candidate
	return null


func is_position_claimed(position: Vector3, claimed_positions: Array[Vector3]) -> bool:
	var minimum_distance := maxf(MOVE_COLLISION_RADIUS * 2.35, cell_size * ATTACK_SLOT_SEPARATION)
	for claimed_position in claimed_positions:
		if Vector2(position.x, position.z).distance_to(Vector2(claimed_position.x, claimed_position.z)) < minimum_distance:
			return true
	return false


func _has_nearby_position(position: Vector3, positions: Array[Vector3], distance: float) -> bool:
	for existing_position in positions:
		if Vector2(position.x, position.z).distance_to(Vector2(existing_position.x, existing_position.z)) <= distance:
			return true
	return false


func attack_position_for(from_position: Vector3, target_position: Vector3, attack_range: float) -> Vector3:
	var target_ground_position := Vector3(target_position.x, 0.0, target_position.z)
	var from_ground_position := Vector3(from_position.x, 0.0, from_position.z)
	var direction := target_ground_position.direction_to(from_ground_position)
	if direction.length() <= 0.0:
		direction = Vector3.FORWARD

	var stop_distance := maxf(attack_range * 0.85, 0.2)
	return target_ground_position + direction * stop_distance


func is_move_segment_safe(from_position: Vector3, to_position: Vector3, moving_actor: Node3D, players: Array[Node3D], enemies: Array[Node3D], allowed_target: Node3D = null) -> bool:
	var from_ground_position := Vector3(from_position.x, 0.0, from_position.z)
	var to_ground_position := Vector3(to_position.x, 0.0, to_position.z)
	var distance := from_ground_position.distance_to(to_ground_position)
	var sample_count := maxi(1, ceili(distance / MOVE_SEGMENT_SAMPLE_DISTANCE))
	for sample_index in range(sample_count + 1):
		var ratio := float(sample_index) / float(sample_count)
		var position := from_ground_position.lerp(to_ground_position, ratio)
		if not is_position_on_floor(position):
			return false

	for blocker in movement_blockers(moving_actor, players, enemies, allowed_target):
		if distance_to_segment_2d(blocker.global_position, from_ground_position, to_ground_position) < MOVE_COLLISION_RADIUS * 2.0:
			return false
	return true


func is_position_on_floor(position: Vector3) -> bool:
	return grid_navigation.is_cell_inside_grid(grid_navigation.world_to_cell(position))


func movement_blockers(moving_actor: Node3D, players: Array[Node3D], enemies: Array[Node3D], allowed_target: Node3D = null) -> Array[Node3D]:
	var blockers: Array[Node3D] = []
	for player in players:
		if player == moving_actor or player == allowed_target or not is_instance_valid(player) or player.is_defeated():
			continue
		blockers.append(player)

	for enemy in enemies:
		if enemy == moving_actor or enemy == allowed_target or not is_instance_valid(enemy) or enemy.is_defeated():
			continue
		blockers.append(enemy)
	return blockers


func distance_to_segment_2d(position: Vector3, segment_start: Vector3, segment_end: Vector3) -> float:
	var point_2d := Vector2(position.x, position.z)
	var start_2d := Vector2(segment_start.x, segment_start.z)
	var end_2d := Vector2(segment_end.x, segment_end.z)
	var segment := end_2d - start_2d
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.0:
		return point_2d.distance_to(start_2d)

	var ratio := clampf((point_2d - start_2d).dot(segment) / segment_length_squared, 0.0, 1.0)
	return point_2d.distance_to(start_2d + segment * ratio)


func ally_blocked_cells(moving_player: Node3D, players: Array[Node3D]) -> Array[Vector2i]:
	var blocked_cells: Array[Vector2i] = []
	for player in players:
		if player == moving_player or not is_instance_valid(player) or player.is_defeated():
			continue
		var cell: Vector2i = grid_navigation.world_to_cell(player.global_position)
		if not cell in blocked_cells:
			blocked_cells.append(cell)
	return blocked_cells

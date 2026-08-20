extends RefCounted

var grid_half_extents: Vector2i
var cell_size: float
var allowed_cells: Array[Vector2i] = []


func _init(initial_grid_half_extents: Vector2i, initial_cell_size: float, initial_allowed_cells: Array[Vector2i] = []) -> void:
	grid_half_extents = initial_grid_half_extents
	cell_size = initial_cell_size
	allowed_cells = initial_allowed_cells.duplicate()


func random_grid_position(rng: RandomNumberGenerator) -> Vector3:
	if not allowed_cells.is_empty():
		return cell_to_world(allowed_cells[rng.randi_range(0, allowed_cells.size() - 1)])

	var x := rng.randi_range(-grid_half_extents.x, grid_half_extents.x) * cell_size
	var z := rng.randi_range(-grid_half_extents.y, grid_half_extents.y) * cell_size
	return Vector3(x, 0.0, z)


func random_position_near(cluster_center: Vector3, rng: RandomNumberGenerator, radius: int) -> Vector3:
	for attempt in 30:
		var offset_x := rng.randi_range(-radius, radius) * cell_size
		var offset_z := rng.randi_range(-radius, radius) * cell_size
		var x := clampf(cluster_center.x + offset_x, -grid_half_extents.x * cell_size, grid_half_extents.x * cell_size)
		var z := clampf(cluster_center.z + offset_z, -grid_half_extents.y * cell_size, grid_half_extents.y * cell_size)
		var position := Vector3(snappedf(x, cell_size), 0.0, snappedf(z, cell_size))
		if is_cell_inside_grid(world_to_cell(position)):
			return position

	return random_grid_position(rng)


func find_path_to_enemy(player: Node3D, enemy, enemies: Array[Node3D], extra_blocked_cells: Array[Vector2i] = []) -> Array[Vector3]:
	var start_cell := world_to_cell(player.global_position)
	var blocked_cells := _enemy_cells(enemies)
	for cell in extra_blocked_cells:
		if not cell in blocked_cells:
			blocked_cells.append(cell)
	var candidates := _attack_cells_for_enemy(enemy, player.attack_range)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return cell_to_world(a).distance_to(player.global_position) < cell_to_world(b).distance_to(player.global_position)
	)

	for candidate in candidates:
		if candidate in blocked_cells:
			continue

		var path_cells := _find_path_cells(start_cell, candidate, blocked_cells)
		if not path_cells.is_empty():
			return _cells_to_world_path(path_cells, blocked_cells)

	return []


func world_to_cell(position: Vector3) -> Vector2i:
	return Vector2i(roundi(position.x / cell_size), roundi(position.z / cell_size))


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * cell_size, 0.0, float(cell.y) * cell_size)


func is_cell_inside_grid(cell: Vector2i) -> bool:
	if not allowed_cells.is_empty():
		return cell in allowed_cells

	return abs(cell.x) <= grid_half_extents.x and abs(cell.y) <= grid_half_extents.y


func _attack_cells_for_enemy(enemy, attack_range: float) -> Array[Vector2i]:
	var enemy_cell := world_to_cell(enemy.ground_position())
	var effective_attack_range := maxf(attack_range, cell_size)
	return _cells_in_range(enemy_cell, enemy.ground_position(), effective_attack_range)


func _cells_in_range(center_cell: Vector2i, center_position: Vector3, range_distance: float) -> Array[Vector2i]:
	var effective_range := maxf(range_distance, cell_size)
	var cell_radius := ceili(effective_range / cell_size)
	var cells: Array[Vector2i] = []
	for x in range(center_cell.x - cell_radius, center_cell.x + cell_radius + 1):
		for y in range(center_cell.y - cell_radius, center_cell.y + cell_radius + 1):
			var cell := Vector2i(x, y)
			if cell == center_cell or not is_cell_inside_grid(cell):
				continue
			if cell_to_world(cell).distance_to(center_position) > effective_range:
				continue
			cells.append(cell)
	return cells


func _enemy_cells(enemies: Array[Node3D]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_defeated():
			cells.append(world_to_cell(enemy.ground_position()))
	return cells


func _find_path_cells(start_cell: Vector2i, goal_cell: Vector2i, blocked_cells: Array[Vector2i]) -> Array[Vector2i]:
	if not is_cell_inside_grid(start_cell) or not is_cell_inside_grid(goal_cell):
		return []
	if goal_cell in blocked_cells:
		return []

	var astar := _create_astar_grid(blocked_cells)
	astar.set_point_solid(start_cell, false)
	if astar.is_point_solid(start_cell) or astar.is_point_solid(goal_cell):
		return []

	var id_path := astar.get_id_path(start_cell, goal_cell)
	var path: Array[Vector2i] = []
	for point in id_path:
		path.append(point)
	return path


func _create_astar_grid(blocked_cells: Array[Vector2i]) -> AStarGrid2D:
	var astar := AStarGrid2D.new()
	astar.region = _path_region()
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()

	for x in range(astar.region.position.x, astar.region.end.x):
		for y in range(astar.region.position.y, astar.region.end.y):
			var cell := Vector2i(x, y)
			if not is_cell_inside_grid(cell) or cell in blocked_cells:
				astar.set_point_solid(cell, true)
	return astar


func _path_region() -> Rect2i:
	if allowed_cells.is_empty():
		return Rect2i(-grid_half_extents, grid_half_extents * 2 + Vector2i.ONE)

	var min_cell := allowed_cells[0]
	var max_cell := allowed_cells[0]
	for cell in allowed_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


func _cells_to_world_path(cells: Array[Vector2i], blocked_cells: Array[Vector2i] = []) -> Array[Vector3]:
	var path: Array[Vector3] = []
	for cell in cells:
		path.append(cell_to_world(cell))
	return _smooth_world_path(path, blocked_cells)


func _smooth_world_path(path: Array[Vector3], blocked_cells: Array[Vector2i]) -> Array[Vector3]:
	if path.size() <= 2:
		return path

	var smoothed_path: Array[Vector3] = [path[0]]
	var anchor_index := 0
	while anchor_index < path.size() - 1:
		var next_index := path.size() - 1
		while next_index > anchor_index + 1:
			if _is_walk_segment_on_floor(path[anchor_index], path[next_index], blocked_cells):
				break
			next_index -= 1

		smoothed_path.append(path[next_index])
		anchor_index = next_index

	return smoothed_path


func _is_walk_segment_on_floor(from_position: Vector3, to_position: Vector3, blocked_cells: Array[Vector2i]) -> bool:
	var distance := from_position.distance_to(to_position)
	if distance <= 0.0:
		var cell := world_to_cell(from_position)
		return is_cell_inside_grid(cell) and not cell in blocked_cells

	var sample_count := ceili(distance / (cell_size * 0.25))
	for sample_index in range(sample_count + 1):
		var ratio := float(sample_index) / float(sample_count)
		var position := from_position.lerp(to_position, ratio)
		var cell := world_to_cell(position)
		if not is_cell_inside_grid(cell) or cell in blocked_cells:
			return false
	return true

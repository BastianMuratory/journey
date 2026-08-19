extends RefCounted


static func build(parent: Node3D, grid_half_extents: Vector2i, cell_size: float, allowed_cells: Array[Vector2i] = []) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.24, 0.16, 0.55)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var line_y := 0.02

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	if allowed_cells.is_empty():
		_add_rectangular_grid(mesh, grid_half_extents, cell_size, line_y)
	else:
		_add_cell_outlines(mesh, allowed_cells, cell_size, line_y)
	mesh.surface_end()

	var grid_mesh_instance := MeshInstance3D.new()
	grid_mesh_instance.mesh = mesh
	parent.add_child(grid_mesh_instance)


static func _add_rectangular_grid(mesh: ImmediateMesh, grid_half_extents: Vector2i, cell_size: float, line_y: float) -> void:

	var min_x := -grid_half_extents.x * cell_size
	var max_x := grid_half_extents.x * cell_size
	var min_z := -grid_half_extents.y * cell_size
	var max_z := grid_half_extents.y * cell_size

	for x in range(-grid_half_extents.x, grid_half_extents.x + 1):
		var world_x: float = float(x) * cell_size
		mesh.surface_add_vertex(Vector3(world_x, line_y, min_z))
		mesh.surface_add_vertex(Vector3(world_x, line_y, max_z))

	for z in range(-grid_half_extents.y, grid_half_extents.y + 1):
		var world_z: float = float(z) * cell_size
		mesh.surface_add_vertex(Vector3(min_x, line_y, world_z))
		mesh.surface_add_vertex(Vector3(max_x, line_y, world_z))


static func _add_cell_outlines(mesh: ImmediateMesh, allowed_cells: Array[Vector2i], cell_size: float, line_y: float) -> void:
	for cell in allowed_cells:
		var min_x := (float(cell.x) - 0.5) * cell_size
		var max_x := (float(cell.x) + 0.5) * cell_size
		var min_z := (float(cell.y) - 0.5) * cell_size
		var max_z := (float(cell.y) + 0.5) * cell_size

		_add_line(mesh, Vector3(min_x, line_y, min_z), Vector3(max_x, line_y, min_z))
		_add_line(mesh, Vector3(max_x, line_y, min_z), Vector3(max_x, line_y, max_z))
		_add_line(mesh, Vector3(max_x, line_y, max_z), Vector3(min_x, line_y, max_z))
		_add_line(mesh, Vector3(min_x, line_y, max_z), Vector3(min_x, line_y, min_z))


static func _add_line(mesh: ImmediateMesh, from_position: Vector3, to_position: Vector3) -> void:
	mesh.surface_add_vertex(from_position)
	mesh.surface_add_vertex(to_position)

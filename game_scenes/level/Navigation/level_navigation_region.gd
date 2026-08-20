extends RefCounted

static func build(parent: Node3D, cells: Array[Vector2i], cell_size: float) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	region.navigation_mesh = _navigation_mesh_for_cells(cells, cell_size)
	parent.add_child(region)
	return region


static func _navigation_mesh_for_cells(cells: Array[Vector2i], cell_size: float) -> NavigationMesh:
	var navigation_mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	var vertex_indices := {}
	for cell in cells:
		var corners: Array[Vector2i] = [
			Vector2i(cell.x, cell.y),
			Vector2i(cell.x + 1, cell.y),
			Vector2i(cell.x + 1, cell.y + 1),
			Vector2i(cell.x, cell.y + 1),
		]
		var polygon := PackedInt32Array()
		for corner in corners:
			if not vertex_indices.has(corner):
				vertex_indices[corner] = vertices.size()
				vertices.append(Vector3(
					(float(corner.x) - 0.5) * cell_size,
					0.0,
					(float(corner.y) - 0.5) * cell_size
				))
			polygon.append(vertex_indices[corner])
		polygons.append(polygon)

	navigation_mesh.vertices = vertices
	for polygon in polygons:
		navigation_mesh.add_polygon(polygon)
	return navigation_mesh

extends RefCounted

var root: Node3D
var material: StandardMaterial3D


func _init(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "DebugWalkingLines"
	parent.add_child(root)

	material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.85, 0.12, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func update(players: Array[Node3D]) -> void:
	for player in players:
		if not is_instance_valid(player) or player.is_defeated() or not player.is_moving():
			clear(player)
			continue

		_show_line(player, player.current_walk_path())


func clear(player: Node3D) -> void:
	if root == null or not is_instance_valid(player):
		return

	var line_instance := root.get_node_or_null(str(player.get_instance_id())) as MeshInstance3D
	if line_instance != null:
		line_instance.queue_free()


func _show_line(player: Node3D, path: Array[Vector3]) -> void:
	if path.is_empty():
		clear(player)
		return

	var line_height := 0.4
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var previous_position := player.global_position + Vector3.UP * line_height
	for path_position in path:
		var next_position := Vector3(path_position.x, player.global_position.y + line_height, path_position.z)
		mesh.surface_add_vertex(previous_position)
		mesh.surface_add_vertex(next_position)
		previous_position = next_position
	mesh.surface_end()

	var line_instance := root.get_node_or_null(str(player.get_instance_id())) as MeshInstance3D
	if line_instance == null:
		line_instance = MeshInstance3D.new()
		line_instance.name = str(player.get_instance_id())
		root.add_child(line_instance)
	line_instance.mesh = mesh

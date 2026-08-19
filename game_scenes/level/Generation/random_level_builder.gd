extends RefCounted

const BLOCK_COUNT := 20
const BLOCK_MIN_SIZE := Vector2i(3, 3)
const BLOCK_MAX_SIZE := Vector2i(7, 6)

var blocks: Array[Rect2i] = []
var cells: Array[Vector2i] = []


func generate(rng: RandomNumberGenerator) -> void:
	blocks.clear()
	cells.clear()
	blocks.append(Rect2i(Vector2i(-3, -3), Vector2i(7, 7)))

	while blocks.size() < BLOCK_COUNT:
		var anchor := blocks[rng.randi_range(0, blocks.size() - 1)]
		blocks.append(_create_connected_block(anchor, rng))

	for block in blocks:
		for x in range(block.position.x, block.end.x):
			for y in range(block.position.y, block.end.y):
				var cell := Vector2i(x, y)
				if not cell in cells:
					cells.append(cell)


func grid_half_extents() -> Vector2i:
	var max_x := 0
	var max_y := 0
	for cell in cells:
		max_x = maxi(max_x, absi(cell.x))
		max_y = maxi(max_y, absi(cell.y))
	return Vector2i(max_x + 1, max_y + 1)


func build_floor(parent: Node3D, source_floor: MeshInstance3D, cell_size: float) -> void:
	var floor_material := source_floor.get_surface_override_material(0)
	source_floor.visible = false

	for block in blocks:
		var block_mesh := BoxMesh.new()
		block_mesh.size = Vector3(float(block.size.x) * cell_size, 0.2, float(block.size.y) * cell_size)

		var block_instance := MeshInstance3D.new()
		block_instance.name = "FloorBlock"
		block_instance.mesh = block_mesh
		block_instance.position = Vector3(
			(float(block.position.x) + float(block.size.x) * 0.5 - 0.5) * cell_size,
			-0.1,
			(float(block.position.y) + float(block.size.y) * 0.5 - 0.5) * cell_size
		)
		if floor_material != null:
			block_instance.set_surface_override_material(0, floor_material)
		parent.add_child(block_instance)


func _create_connected_block(anchor: Rect2i, rng: RandomNumberGenerator) -> Rect2i:
	var size := Vector2i(
		rng.randi_range(BLOCK_MIN_SIZE.x, BLOCK_MAX_SIZE.x),
		rng.randi_range(BLOCK_MIN_SIZE.y, BLOCK_MAX_SIZE.y)
	)
	var side := rng.randi_range(0, 3)
	var position := Vector2i.ZERO

	match side:
		0:
			position.x = anchor.position.x + rng.randi_range(-size.x + 1, anchor.size.x - 1)
			position.y = anchor.position.y - size.y + 1
		1:
			position.x = anchor.position.x + rng.randi_range(-size.x + 1, anchor.size.x - 1)
			position.y = anchor.end.y - 1
		2:
			position.x = anchor.position.x - size.x + 1
			position.y = anchor.position.y + rng.randi_range(-size.y + 1, anchor.size.y - 1)
		_:
			position.x = anchor.end.x - 1
			position.y = anchor.position.y + rng.randi_range(-size.y + 1, anchor.size.y - 1)

	return Rect2i(position, size)

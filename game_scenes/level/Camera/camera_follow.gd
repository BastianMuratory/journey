extends RefCounted


static func update(camera: Camera3D, players: Array[Node3D], offset: Vector3, follow_speed: float, delta: float) -> void:
	var center := party_center(players)
	var desired_position := center + offset
	camera.global_position = camera.global_position.lerp(desired_position, minf(follow_speed * delta, 1.0))
	camera.look_at(center, Vector3.UP)


static func party_center(players: Array[Node3D]) -> Vector3:
	if players.is_empty():
		return Vector3.ZERO

	var total := Vector3.ZERO
	var valid_count := 0
	for player in players:
		if is_instance_valid(player):
			total += player.global_position
			valid_count += 1

	if valid_count == 0:
		return Vector3.ZERO
	return total / float(valid_count)

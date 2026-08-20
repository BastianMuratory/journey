extends RefCounted

const SKILL_PROJECTILE_HEIGHT := 0.75


func play(host: Node3D, player: Node3D, target, skill_index: int) -> void:
	if not is_instance_valid(player) or not is_instance_valid(target):
		return

	if skill_index == 0:
		await _play_fast_skill_animation(host, player, target)
		return

	await _play_heavy_skill_animation(host, player, target)


func _play_fast_skill_animation(host: Node3D, player: Node3D, target) -> void:
	var projectile := MeshInstance3D.new()
	var projectile_mesh := SphereMesh.new()
	projectile_mesh.radius = 0.14
	projectile_mesh.height = 0.28
	projectile.mesh = projectile_mesh
	projectile.material_override = _skill_material(Color(0.35, 0.95, 1.0, 0.92))
	host.add_child(projectile)

	var start_position: Vector3 = player.global_position + Vector3.UP * SKILL_PROJECTILE_HEIGHT
	var end_position: Vector3 = target.ground_position() + Vector3.UP * 0.55
	projectile.global_position = start_position

	var tween := host.create_tween()
	tween.set_parallel(true)
	tween.tween_property(projectile, "global_position", end_position, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(projectile, "scale", Vector3(0.4, 0.4, 0.4), 0.18).from(Vector3.ONE)
	await tween.finished
	projectile.queue_free()
	await _play_impact_burst(host, end_position, Color(0.35, 0.95, 1.0, 0.85), 0.32)


func _play_heavy_skill_animation(host: Node3D, player: Node3D, target) -> void:
	var windup := MeshInstance3D.new()
	var windup_mesh := SphereMesh.new()
	windup_mesh.radius = 0.2
	windup_mesh.height = 0.4
	windup.mesh = windup_mesh
	windup.material_override = _skill_material(Color(1.0, 0.74, 0.22, 0.85))
	host.add_child(windup)
	windup.global_position = player.global_position + Vector3.UP * 0.7
	var impact_position: Vector3 = target.ground_position() + Vector3.UP * 0.62

	var windup_tween := host.create_tween()
	windup_tween.set_parallel(true)
	windup_tween.tween_property(windup, "scale", Vector3(2.1, 2.1, 2.1), 0.16).from(Vector3(0.25, 0.25, 0.25))
	windup_tween.tween_property(windup, "global_position", impact_position, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await windup_tween.finished
	windup.queue_free()

	await _play_impact_burst(host, impact_position - Vector3.UP * 0.17, Color(1.0, 0.46, 0.12, 0.9), 0.56)


func _play_impact_burst(host: Node3D, position: Vector3, color: Color, max_scale: float) -> void:
	var burst := MeshInstance3D.new()
	var burst_mesh := SphereMesh.new()
	burst_mesh.radius = 0.5
	burst_mesh.height = 1.0
	burst.mesh = burst_mesh
	burst.material_override = _skill_material(color)
	host.add_child(burst)
	burst.global_position = position
	burst.scale = Vector3(0.15, 0.15, 0.15)

	var tween := host.create_tween()
	tween.set_parallel(true)
	tween.tween_property(burst, "scale", Vector3(max_scale, max_scale, max_scale), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(burst, "transparency", 1.0, 0.16)
	await tween.finished
	burst.queue_free()


func _skill_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.4
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

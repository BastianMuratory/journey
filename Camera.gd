extends Camera3D

# Drag and drop your target MeshInstance3D into this slot in the Inspector
@export var target: Node3D

# The spatial distance offset you want to maintain from the mesh
@export var offset: Vector3 = Vector3(0, 5, 10)

# How smoothly the camera catches up (lower values = smoother/slower)
@export var smoothness: float = 5.0

func _physics_process(delta: float) -> void:
	if not target:
		return
		
	# Calculate where the camera wants to be in world space
	var target_destination: Vector3 = target.global_position + offset
	
	# Smoothly glide the current camera position to the destination position
	global_position = global_position.lerp(target_destination, smoothness * delta)
	
	# Force the camera to face the mesh's center
	look_at(target.global_position)

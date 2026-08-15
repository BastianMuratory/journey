extends Node3D

## Base camp sandbox. Space bar mega evolves Sandile into Krookodile.

## Held so the effect can be replayed -- see [method _reset].
@onready var _mega: MegaEvolution = $Sandile/MegaEvolution
@onready var _sandile: MeshInstance3D = $Sandile

var _original_mesh: Mesh


func _ready() -> void:
	_original_mesh = _sandile.mesh


func _unhandled_input(event: InputEvent) -> void:
	if not _is_evolve_pressed(event):
		return
	get_viewport().set_input_as_handled()

	if _mega.is_playing:
		return
	if _sandile.mesh != _original_mesh:
		# Already evolved -- space bar rewinds so you can watch it again.
		_reset()
		return
	_mega.trigger()


## Prefers the "mega_evolve" input action (rebindable in Project Settings) and
## falls back to the raw space bar if the action was never defined.
func _is_evolve_pressed(event: InputEvent) -> bool:
	if InputMap.has_action(&"mega_evolve"):
		return event.is_action_pressed(&"mega_evolve")
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE


func _reset() -> void:
	_sandile.mesh = _original_mesh
	_sandile.scale = Vector3.ONE

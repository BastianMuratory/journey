extends Node3D

## Base camp sandbox. Space bar mega evolves Sandile into Krookodile.

## Held so the effect can be replayed -- see [method _reset].
@onready var _mega: MegaEvolution = $Sandile/MegaEvolutionKrookodile
@onready var _sandile: MeshInstance3D = $Sandile

@onready var _mega2: MegaEvolution = $Caterpie/MegaEvolutionRayquaza
@onready var _caterpie: MeshInstance3D = $Caterpie

var _pairs: Array[Dictionary] = []

func _ready() -> void:
	for m in [_sandile, _caterpie]:
		_pairs.append({"node": m, "mega": m.get_node("MegaEvolution"), "mesh": m.mesh})

func _unhandled_input(event: InputEvent) -> void:
	if not _is_evolve_pressed(event): return
	
	get_viewport().set_input_as_handled()
	
	for p in _pairs:
		print(p)
		if p.mega.is_playing: continue
		if p.node.mesh != p.mesh:
			p.node.mesh = p.mesh          # rewind
			p.node.scale = Vector3.ONE
		else:
			p.mega.trigger()


## Prefers the "mega_evolve" input action (rebindable in Project Settings) and
## falls back to the raw space bar if the action was never defined.
func _is_evolve_pressed(event: InputEvent) -> bool:
	if InputMap.has_action(&"mega_evolve"):
		return event.is_action_pressed(&"mega_evolve")
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE


func _reset() -> void:
	_sandile.scale = Vector3.ONE

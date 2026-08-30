extends Node


const MOVE_DATA_DIR := "res://logic/pokemon_moves/moves/"

var _paths : Dictionary[int, String] = {} ## move_id -> ressource
var _cache : Dictionary[int, Move] = {} ## move_id -> loaded resource. Filled lazily by get_move.

var _all_move_ids : Array[int] = []

func _ready() -> void:
	_build_index()

## The move data for a move id (see Move.Attack)
func get_move(move_id: int) -> Move:
	if _cache.has(move_id):
		return _cache[move_id]

	if not _paths.has(move_id):
		push_warning("MoveRegistry: no data file for move #%d" % move_id)
		return null

	var res := load(_paths[move_id]) as Move
	if res != null:
		res.id = move_id
	_cache[move_id] = res
	return res

func get_all_move_ids() -> Array[int]:
	return _all_move_ids

func get_icon(move_id: int) -> Texture2D:
	var data : Move = get_move(move_id)
	if data != null && data.icon != null:
		return data.icon;
	push_warning("MoveRegistry: no icon for move #%d" % move_id)
	var errorIcon : Texture2D = preload("uid://cs1inf50u1m5e")
	return errorIcon

## Scans the data folder and maps each move id to its file.
func _build_index() -> void:
	_paths.clear()
	_cache.clear()

	var dir := DirAccess.open(MOVE_DATA_DIR)
	_all_move_ids.clear()

	for entry in dir.get_files():
		# Exported builds replace foo.tres with a foo.tres.remap redirect stub.
		var file_name := entry.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue

		var move_id := file_name.substr(0, 3).to_int()
		if move_id <= 0 or _paths.has(move_id):
			continue

		_paths[move_id] = MOVE_DATA_DIR + file_name
		_all_move_ids.append(move_id)
	_all_move_ids.sort()

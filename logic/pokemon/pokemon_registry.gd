extends Node

const POKEMON_BASE_DATA_DIR := "res://logic/pokemon/pokemon_base_data/"

var _paths : Dictionary[int, String] = {} ## dex_number -> ressource
var _cache : Dictionary[int, PokemonBaseData] = {} ## dex_number -> loaded resource. Filled lazily by get_pokemon.

var _all_dex_numbers : Array[int] = []

func _ready() -> void:
	_build_index()


## The base form for a dex number
func get_pokemon(dex_number: int) -> PokemonBaseData:
	if _cache.has(dex_number):
		return _cache[dex_number]

	var res := load(_paths[dex_number]) as PokemonBaseData
	_cache[dex_number] = res
	return res

func get_all_dex_numbers() -> Array[int]:
	return _all_dex_numbers

## The path a resource was loaded from. The admin menu needs this to
## write edits back to disk.
func get_path_for(dex_number: int) -> String:
	return _paths.get(dex_number, "")

func get_icon(dex_number: int) -> Texture2D:
	var data : PokemonBaseData = get_pokemon(dex_number)
	if data != null && data.has_icon():
		return data.icon;
	push_warning("PokemonRegistry: no data file for dex #%d" % dex_number)
	var errorIcon : Texture2D = preload("uid://cs1inf50u1m5e")
	return errorIcon


## Scans the data folder and maps each dex_number to its file.
func _build_index() -> void:
	_paths.clear()
	_cache.clear()
	
	var dir := DirAccess.open(POKEMON_BASE_DATA_DIR)
	
	_all_dex_numbers.clear()

	for entry in dir.get_files():
		# Exported builds rename resources to .remap / .res, so normalise back
		# to the .tres path that load() actually wants.
		var file_name := entry.trim_suffix(".remap")
		if file_name.ends_with(".res"):
			file_name = file_name.trim_suffix(".res") + ".tres"
		if not file_name.ends_with(".tres"):
			continue
		
		var dex := file_name.substr(0, 4).to_int()
		if dex <= 0 :
			continue
		
		_paths[dex] = POKEMON_BASE_DATA_DIR + file_name
		_all_dex_numbers.append(dex)
	_all_dex_numbers.sort()

extends Node

## Autoload. Looks up [PokemonData] by dex number.
##
## Registered in Project Settings -> Globals -> Autoload as [code]PokemonRegistry[/code],
## so it is reachable from anywhere without passing references around:
## [codeblock]
## var sandile := PokemonRegistry.get_pokemon(551)
## [/codeblock]
##
## On startup it indexes the data folder by filename -- it reads the directory
## listing only, so nothing is loaded off disk until you actually ask for a
## Pokémon. Meshes and textures come in one species at a time and stay cached.

const DIR := "res://data_structures/Pokemons/"

## dex number -> res:// path. Built once in _ready.
var _paths: Dictionary[int, String] = {}
## dex number -> loaded resource. Filled lazily by [method get_pokemon].
var _cache: Dictionary[int, PokemonData] = {}


func _ready() -> void:
	_build_index()


## Returns the data for a dex number, or null if there is no file for it.
func get_pokemon(dex: int) -> PokemonData:
	if _cache.has(dex):
		return _cache[dex]

	if not _paths.has(dex):
		push_warning("PokemonRegistry: no data file for dex #%d" % dex)
		return null

	var res := load(_paths[dex]) as PokemonData
	if res == null:
		push_warning("PokemonRegistry: %s is not a PokemonData" % _paths[dex])
		return null

	_cache[dex] = res
	return res


## Every dex number that has a data file, ascending.
func get_all_dex_numbers() -> Array[int]:
	var out: Array[int] = []
	for dex in _paths:
		out.append(dex)
	out.sort()
	return out


func has_pokemon(dex: int) -> bool:
	return _paths.has(dex)


## Scans the data folder and maps each dex number to its file. Filenames only
## need to *start* with the zero-padded number, so "0551_sandile.tres" and
## "0551.tres" both resolve for dex 551 -- which keeps the folder readable.
func _build_index() -> void:
	_paths.clear()

	var dir := DirAccess.open(DIR)
	if dir == null:
		push_error("PokemonRegistry: cannot open %s" % DIR)
		return

	for entry in dir.get_files():
		# Exported builds rename resources to .remap / .res, so normalise back
		# to the .tres path that load() actually wants.
		var file_name := entry.trim_suffix(".remap")
		if file_name.ends_with(".res"):
			file_name = file_name.trim_suffix(".res") + ".tres"
		if not file_name.ends_with(".tres"):
			continue

		var digits := ""
		for i in file_name.length():
			var c := file_name[i]
			if not c.is_valid_int():
				break
			digits += c

		if digits.is_empty():
			push_warning("PokemonRegistry: %s has no leading dex number, skipped" % file_name)
			continue

		var dex := digits.to_int()
		if _paths.has(dex):
			push_warning("PokemonRegistry: duplicate dex #%d (%s)" % [dex, file_name])
			continue

		_paths[dex] = DIR + file_name

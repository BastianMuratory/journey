extends Node

## this gets autoloaded. Looks up [PokemonBaseData] by dex number, or by id when you need a
## specific form.
##
## [codeblock]
## var sandile := PokemonRegistry.get_pokemon(551)
## var ash_cap := PokemonRegistry.get_pokemon_by_id("0025_pikachu_ash_cap")
## [/codeblock]
##
## An [b]id[/b] is just the filename without its extension -- "0025_pikachu",
## "0038_ninetales_alolan". Several files can share a dex number because
## alternate forms and costumes are separate resources, so ids are the only
## unique handle. [method get_pokemon] resolves a dex to that species' base
## form, which is what gameplay code almost always wants.
##
## On startup it indexes the data folder by filename -- it reads the directory
## listing only, so nothing is loaded off disk until you actually ask for a
## Pokémon. Meshes and textures come in one species at a time and stay cached.

const DIR := "res://data/pokemon_base_data/"

var _paths: Dictionary[String, String] = {} ## id -> res
var _base_form: Dictionary[int, String] = {} ## dex number -> the id of that species' base form.
var _forms: Dictionary[int, PackedStringArray] = {} ## dex number -> every id sharing it, base form first.
var _cache: Dictionary[String, PokemonBaseData] = {} ## id -> loaded resource. Filled lazily by [method get_pokemon_by_id].
var _sorted_ids: PackedStringArray = [] ## Every id, ascending. Cached because the animation browser pages through it.


func _ready() -> void:
	_build_index()


## The base form for a dex number, or null if there is no file for it.
func get_pokemon(dex: int) -> PokemonBaseData:
	if not _base_form.has(dex):
		push_warning("PokemonRegistry: no data file for dex #%d" % dex)
		return null
	return get_pokemon_by_id(_base_form[dex])


## A specific resource by id, e.g. "0025_pikachu_ash_cap". Null if unknown.
func get_pokemon_by_id(id: String) -> PokemonBaseData:
	if _cache.has(id):
		return _cache[id]

	if not _paths.has(id):
		push_warning("PokemonRegistry: no data file with id '%s'" % id)
		return null

	var res := load(_paths[id]) as PokemonBaseData
	if res == null:
		push_warning("PokemonRegistry: %s is not a PokemonBaseData" % _paths[id])
		return null

	_cache[id] = res
	return res


## Every dex number that has a data file, ascending.
func get_all_dex_numbers() -> Array[int]:
	var out: Array[int] = []
	for dex in _base_form:
		out.append(dex)
	out.sort()
	return out


## Every id, ascending -- which is dex order, with each species' forms grouped
## just after it. This is the list to page through when showing everything.
func get_all_ids() -> PackedStringArray:
	return _sorted_ids


## Every id sharing a dex number, base form first. Empty if the dex is unknown.
func get_forms(dex: int) -> PackedStringArray:
	return _forms.get(dex, PackedStringArray())


## The id of a dex number's base form, or "" if there is no file for it.
func get_base_form_id(dex: int) -> String:
	return _base_form.get(dex, "")


func has_pokemon(dex: int) -> bool:
	return _base_form.has(dex)


func has_id(id: String) -> bool:
	return _paths.has(id)


## The path a resource was loaded from. The animation test scene needs this to
## write edits back to disk.
func get_path_for(id: String) -> String:
	return _paths.get(id, "")


## Drops a cached resource so the next lookup re-reads it from disk. Used after
## something edits a .tres at runtime.
func reload(id: String) -> PokemonBaseData:
	_cache.erase(id)
	return get_pokemon_by_id(id)


## Scans the data folder and maps each id to its file. Filenames only need to
## [i]start[/i] with the zero-padded dex number, so "0551_sandile.tres" and
## "0551.tres" both resolve for dex 551 -- which keeps the folder readable.
##
## Several files may share a dex number. The shortest id wins the base-form slot,
## because form files are always the base name plus a suffix:
## "0025_pikachu" beats "0025_pikachu_ash_cap".
func _build_index() -> void:
	_paths.clear()
	_base_form.clear()
	_forms.clear()
	_cache.clear()

	var dir := DirAccess.open(DIR)
	if dir == null:
		push_error("PokemonRegistry: cannot open %s" % DIR)
		return

	var by_dex: Dictionary[int, PackedStringArray] = {}

	for entry in dir.get_files():
		# Exported builds rename resources to .remap / .res, so normalise back
		# to the .tres path that load() actually wants.
		var file_name := entry.trim_suffix(".remap")
		if file_name.ends_with(".res"):
			file_name = file_name.trim_suffix(".res") + ".tres"
		if not file_name.ends_with(".tres"):
			continue

		var id := file_name.trim_suffix(".tres")

		var digits := ""
		for i in id.length():
			var c := id[i]
			if not c.is_valid_int():
				break
			digits += c

		if digits.is_empty():
			push_warning("PokemonRegistry: %s has no leading dex number, skipped" % file_name)
			continue

		if _paths.has(id):
			push_warning("PokemonRegistry: duplicate id '%s'" % id)
			continue

		_paths[id] = DIR + file_name

		var dex := digits.to_int()
		var ids: PackedStringArray = by_dex.get(dex, PackedStringArray())
		ids.append(id)
		by_dex[dex] = ids

	for dex in by_dex:
		var ids := by_dex[dex]
		var as_array := Array(ids)
		# Shortest first picks the base form; the length tie-break keeps the rest
		# in a stable, readable order.
		as_array.sort_custom(func(a: String, b: String) -> bool:
			if a.length() != b.length():
				return a.length() < b.length()
			return a < b)
		var ordered := PackedStringArray(as_array)
		_forms[dex] = ordered
		_base_form[dex] = ordered[0]

	var all := PackedStringArray()
	var dex_numbers := get_all_dex_numbers()
	for dex in dex_numbers:
		all.append_array(_forms[dex])
	_sorted_ids = all

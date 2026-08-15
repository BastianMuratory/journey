@tool
extends EditorScript

## Normalises ripped Pokemon .mtl files so Godot's OBJ importer produces a
## plain, correctly lit material.
##
## To run: open this file in the script editor and hit [b]File > Run[/b]
## (Ctrl+Shift+X). Safe to run any time -- it only rewrites files that are
## actually wrong, and re-running on a clean project does nothing.
##
## Two fixes:
##
## [b]1. Zero the specular.[/b] Godot's OBJ importer maps the MTL [code]Ks[/code]
## (specular colour) onto [code]StandardMaterial3D.metallic[/code], and
## [code]Ns[/code] (shininess) feeds it too. A rip that declares
## [code]Ks 1 1 1[/code] therefore imports as metallic = 1.0. Fully metallic
## surfaces have no diffuse response at all -- they are lit purely by
## reflections -- so in a scene with flat ambient light and no reflection probe
## or sky they render as pure black silhouettes.
##
## [b]2. Repoint a broken map_Kd.[/b] Several rips keep the original internal
## texture name in the .mtl after the .png beside it has been renamed. Godot
## then finds no albedo texture and imports the model untextured white. Only
## rewritten when the named file genuinely isn't there; the replacement is
## picked from the same folder, matching shiny to shiny.
##
## Adding a species? Drop it in assets/pokemons/ and run this.

## Folder scanned, recursively.
const ROOT := "res://assets/pokemons"

## Target values, keyed by the MTL line prefix they replace. These mirror the
## "pq" family of rips (Sandile, Krookodile, Rayquaza), which import correctly.
const WANT := {
	"Ns ": "Ns 1000.000000",
	"Ks ": "Ks 0.000000 0.000000 0.000000",
	"illum ": "illum 1",
}


func _run() -> void:
	var materials := _find(ROOT, ".mtl")
	if materials.is_empty():
		push_warning("fix_pokemon_materials: no .mtl files under %s" % ROOT)
		return

	print("\n--- fix_pokemon_materials: %d material(s) under %s ---" % [materials.size(), ROOT])

	var touched_dirs := {}
	var fixed := 0
	for mtl in materials:
		var notes := _fix_material(mtl)
		if notes.is_empty():
			print("  ok     %s" % mtl.get_file())
		else:
			fixed += 1
			touched_dirs[mtl.get_base_dir()] = true
			print("  FIXED  %s   [%s]" % [mtl.get_file(), ", ".join(notes)])

	if fixed == 0:
		print("--- nothing to do, all %d already clean ---\n" % materials.size())
		return

	# Godot hashes the .obj to decide whether to reimport, and never looks at the
	# .mtl beside it -- so editing a material alone leaves the stale black mesh
	# in the import cache. Force the meshes in every touched folder to rebuild.
	var meshes := PackedStringArray()
	for dir in touched_dirs:
		for obj in _find(dir, ".obj"):
			meshes.append(obj)

	if meshes.is_empty():
		print("--- fixed %d material(s), but found no .obj to reimport ---\n" % fixed)
		return

	print("  reimporting %d mesh(es)..." % meshes.size())
	EditorInterface.get_resource_filesystem().reimport_files(meshes)
	print("--- fixed %d material(s), reimported %d mesh(es) ---\n" % [fixed, meshes.size()])


## Rewrites one .mtl in place. Returns a list of human-readable changes, empty
## if the file was already correct (in which case nothing is written).
func _fix_material(path: String) -> PackedStringArray:
	var notes := PackedStringArray()

	var reader := FileAccess.open(path, FileAccess.READ)
	if reader == null:
		push_error("fix_pokemon_materials: cannot read %s" % path)
		return notes
	var text := reader.get_as_text()
	reader.close()

	var lines := text.split("\n")
	for i in lines.size():
		var raw: String = lines[i]
		# These files are usually CRLF. Split on \n, keep the \r, put it back --
		# that way we never silently rewrite the whole file's line endings.
		var carriage := raw.ends_with("\r")
		var line := raw.substr(0, raw.length() - 1) if carriage else raw

		for prefix in WANT:
			var want: String = WANT[prefix]
			if line.begins_with(prefix) and line != want:
				notes.append("%s-> %s" % [prefix, want.split(" ")[1]])
				line = want

		if line.begins_with("map_Kd "):
			var named := line.substr(7).strip_edges()
			if not FileAccess.file_exists(path.get_base_dir().path_join(named)):
				var guess := _guess_texture(path)
				if guess.is_empty():
					push_warning("%s: map_Kd '%s' is missing and there is no .png beside it" % [path.get_file(), named])
				else:
					notes.append("map_Kd -> %s" % guess)
					line = "map_Kd " + guess

		lines[i] = (line + "\r") if carriage else line

	if notes.is_empty():
		return notes

	var writer := FileAccess.open(path, FileAccess.WRITE)
	if writer == null:
		push_error("fix_pokemon_materials: cannot write %s" % path)
		return PackedStringArray()
	writer.store_string("\n".join(lines))
	writer.close()
	return notes


## Picks the most plausible .png sitting next to a material whose map_Kd is
## broken. Shiny materials get the shiny texture; everything else gets the
## normal one.
func _guess_texture(mtl_path: String) -> String:
	var want_shiny := _is_shiny(mtl_path.get_file())
	var fallback := ""
	for png in _find(mtl_path.get_base_dir(), ".png"):
		var file_name := png.get_file()
		if _is_shiny(file_name) == want_shiny:
			return file_name
		if fallback.is_empty():
			fallback = file_name
	return fallback


## Both naming conventions in this project: "<name>_s.png" and "... - Shiny.png".
func _is_shiny(file_name: String) -> bool:
	var base := file_name.get_basename().to_lower()
	return base.contains("shiny") or base.ends_with("_s")


func _find(dir_path: String, suffix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("fix_pokemon_materials: cannot open %s" % dir_path)
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_find(full, suffix))
		elif entry.to_lower().ends_with(suffix):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out

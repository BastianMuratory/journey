extends Node3D

## Admin menu: an animation sandbox and tuning editor. Not part of the game

signal add_to_collection(id: String, level: int)

const GRID_COUNT := 3 ## to view a full evolution familly 
const GRID_SPACING := 1.6

## The fields SAVE writes, and the ones REVERT puts back. Kept in one place
## because the baseline snapshot and the revert must agree on them.
const TUNED_FIELDS := [
	"body_type", "anim_speed_scale", "anim_amplitude", "hover_height",
]

const POKEMON_MODEL_SCENE := preload("res://pokemon/pokemon_model.tscn")
const MAIN_MENU_SCENE := "res://game_scenes/main_menu/main_menu.tscn"

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: AdminMenuUI = $AdminMenuUI

## Every id the registry knows, ascending.
var _all_ids: PackedStringArray = []
## The subset currently listed, after the search filter. Navigation indexes this.
var _visible_ids: PackedStringArray = []
var _index := 0

## id -> {dex: int, name: String, body: int}.
##
## Read straight out of the .tres text rather than through the registry, because
## loading a PokemonBaseData pulls its mesh in with it -- and a 410-row list that
## loaded 410 models to draw itself would take seconds and hundreds of MB. The
## registry stays lazy; only the species actually on screen get loaded.
var _meta: Dictionary[String, Dictionary] = {}

var _shiny := false
var _grid := false

## id -> the [constant TUNED_FIELDS] values that species had on disk, snapshotted
## just before its first edit of the session.
##
## Being in here means "has unsaved edits" -- the current values are not copied,
## they live on the [PokemonBaseData] itself, which is what the spawned Pokémon and
## the save both read. Keeping only the baseline means REVERT can undo a whole run
## of nudges exactly, with no drift.
var _pending: Dictionary[String, Dictionary] = {}
## Set by the first MENU press when there are unsaved edits, so the second leaves.
var _exit_armed := false

var _spawned: Array[PokemonModel] = []


func _ready() -> void:
	_connect_ui()

	_all_ids = PokemonRegistry.get_all_ids()
	if _all_ids.is_empty():
		push_error("AdminMenu: PokemonRegistry has no species. Nothing to show.")
		_ui.set_readout("no species loaded")
		return

	_visible_ids = _all_ids
	_scan_metadata()
	_rebuild_list()
	_respawn()


## Every way the screen can ask for something. The screen never calls into here
## directly, which is what keeps it a screen rather than half the sandbox.
func _connect_ui() -> void:
	_ui.anim_requested.connect(_play)
	_ui.grid_toggled.connect(_set_grid)
	_ui.shiny_toggled.connect(_set_shiny)
	_ui.search_changed.connect(_on_search_changed)
	_ui.species_index_requested.connect(_jump_to)
	_ui.species_step_requested.connect(_step_species)
	_ui.nudge_requested.connect(_nudge)
	_ui.body_type_step_requested.connect(_cycle_body_type)
	_ui.revert_requested.connect(_revert_focused)
	_ui.revert_all_requested.connect(_revert_all)
	_ui.save_requested.connect(_save_edits)
	_ui.menu_requested.connect(_leave)
	_ui.add_to_collection.connect(_add_to_collection)


func _process(_delta: float) -> void:
	# The one-shot state changes on its own, so the status line polls instead of
	# waiting for a signal.
	_ui.set_status(_status_text())


# ---------------------------------------------------------------- metadata

## Pulls dex number, display name and body type out of every .tres as plain
## text. Cheap enough to do for all of them at startup, and it means the browser
## can label 410 rows without instantiating a single mesh.
func _scan_metadata() -> void:
	_meta.clear()

	# Compiled once, not once per file -- this runs 410 times.
	var dex_re := RegEx.create_from_string("(?m)^dex_number\\s*=\\s*(\\d+)")
	var body_re := RegEx.create_from_string("(?m)^body_type\\s*=\\s*(\\d+)")
	var name_re := RegEx.create_from_string('(?m)^display_name\\s*=\\s*"([^"]*)"')

	for id in _all_ids:
		var path := PokemonRegistry.get_path_for(id)
		var entry := {"dex": _dex_from_id(id), "name": _name_from_id(id), "body": -1}

		# Exported builds ship these as binary .res, which this cannot read.
		# The fallbacks above already give a usable row, so that is fine.
		if path.ends_with(".tres") and FileAccess.file_exists(path):
			var text := FileAccess.get_file_as_string(path)
			var dex_match := dex_re.search(text)
			if dex_match != null:
				entry["dex"] = dex_match.get_string(1).to_int()
			var body_match := body_re.search(text)
			if body_match != null:
				entry["body"] = body_match.get_string(1).to_int()
			var name_match := name_re.search(text)
			if name_match != null:
				entry["name"] = name_match.get_string(1)

		_meta[id] = entry


func _dex_from_id(id: String) -> int:
	var digits := ""
	for i in id.length():
		if not id[i].is_valid_int():
			break
		digits += id[i]
	return digits.to_int() if not digits.is_empty() else 0


func _name_from_id(id: String) -> String:
	return id.substr(id.find("_") + 1).capitalize() if "_" in id else id


func _meta_of(id: String) -> Dictionary:
	return _meta.get(id, {"dex": 0, "name": id, "body": -1})


## The species being edited, and the one every button on the bar applies to. In
## grid mode that is the leftmost one, so there is always exactly one.
func _focused_id() -> String:
	return _visible_ids[_index] if not _visible_ids.is_empty() else ""


## The focused species' data, or null when the filter matched nothing. Already
## loaded -- it is the same resource the model on screen is drawn from.
func _focused_data() -> PokemonBaseData:
	if _spawned.is_empty():
		return null
	return _spawned[0].data


# ----------------------------------------------------------------- spawning

func _respawn() -> void:
	for pokemon in _spawned:
		pokemon.queue_free()
	_spawned.clear()

	if _visible_ids.is_empty():
		_refresh_panels()
		return

	var count := GRID_COUNT if _grid else 1
	count = mini(count, _visible_ids.size())

	# Instance first, measure second: widths are only known once the data is in.
	var widths: Array[float] = []
	for i in count:
		var id := _visible_ids[(_index + i) % _visible_ids.size()]
		var pokemon := _spawn(id)
		if pokemon == null:
			continue
		_spawned.append(pokemon)
		widths.append(_footprint(pokemon))

	_lay_out(widths)
	_frame_camera()
	_refresh_panels()
	_ui.select_row(_index)


func _spawn(id: String) -> PokemonModel:
	var data := PokemonRegistry.get_pokemon_by_id(id)
	if data == null:
		return null

	var pokemon: PokemonModel = POKEMON_MODEL_SCENE.instantiate()
	pokemon.data = data
	pokemon.shiny = _shiny
	add_child(pokemon)
	return pokemon


## Places everything in a row centred on the origin, spaced by actual size so a
## Caterpie next to an Onix does not end up inside it.
func _lay_out(widths: Array[float]) -> void:
	if _spawned.size() <= 1:
		if _spawned.size() == 1:
			_spawned[0].position = Vector3.ZERO
		return

	var step := 0.0
	for w in widths:
		step = maxf(step, w)
	step *= GRID_SPACING

	var offset := -step * (_spawned.size() - 1) * 0.5
	for i in _spawned.size():
		_spawned[i].position = Vector3(offset + step * i, 0.0, 0.0)


## Widest horizontal extent, in world units.
func _footprint(pokemon: PokemonModel) -> float:
	var data := pokemon.data
	if data == null or data.mesh == null:
		return 1.0
	var size := data.mesh.get_aabb().size * data.model_scale
	return maxf(maxf(size.x, size.z), 0.1)


func _frame_camera() -> void:
	var tallest := 0.0
	var span := 0.0
	for pokemon in _spawned:
		var data := pokemon.data
		if data == null or data.mesh == null:
			continue
		tallest = maxf(tallest, data.mesh.get_aabb().size.y * data.model_scale)
		span = maxf(span, absf(pokemon.position.x) * 2.0 + _footprint(pokemon))

	tallest = maxf(tallest, 0.5)
	# Pull back far enough for the taller of "how big is it" and "how wide is the
	# row", with headroom for the hop and hover offsets.
	var distance := maxf(tallest * 3.2, span * 1.1) + 2.0
	_camera.position = Vector3(0.0, tallest * 1.1, distance)
	_camera.look_at(Vector3(0.0, tallest * 0.55, 0.0))


# ------------------------------------------------------------------- actions

## The second press of MENU with unsaved edits is the one that leaves. Losing a
## tuning session to a stray tap would be a miserable way to end it.
func _leave() -> void:
	if not _pending.is_empty() and not _exit_armed:
		_exit_armed = true
		_ui.show_message("%d species edited -- SAVE first, or MENU again to discard"
			% _pending.size())
		return
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _play(anim: PokemonAnimator.Anim) -> void:
	for pokemon in _spawned:
		var animator := pokemon.animator
		match anim:
			PokemonAnimator.Anim.IDLE: animator.play_idle()
			PokemonAnimator.Anim.RUN: animator.play_run()
			PokemonAnimator.Anim.ATTACK: animator.attack()
			PokemonAnimator.Anim.HIT: animator.take_hit()
			PokemonAnimator.Anim.SPIN: animator.spin()


func _step_species(direction: int) -> void:
	if _visible_ids.is_empty():
		return
	var stride := maxi(_spawned.size(), 1) if _grid else 1
	_jump_to(wrapi(_index + direction * stride, 0, _visible_ids.size()))


func _jump_to(index: int) -> void:
	if _visible_ids.is_empty():
		return
	_index = clampi(index, 0, _visible_ids.size() - 1)
	# Keep whatever loop was playing, so you can flick through species mid-run.
	var was_running := not _spawned.is_empty() and _spawned[0].animator.moving
	_respawn()
	if was_running:
		_play(PokemonAnimator.Anim.RUN)


func _set_grid(on: bool) -> void:
	_grid = on
	_respawn()


func _set_shiny(on: bool) -> void:
	_shiny = on
	_respawn()


# ----------------------------------------------------------- species editing

## Moves one float field on the focused species by [param amount], which the
## screen has already multiplied by its x5 toggle, clamped to the same range
## [PokemonBaseData] exports.
func _nudge(field: String, amount: float, step: float, low: float, high: float) -> void:
	var id := _focused_id()
	if id == "":
		return
	var data := PokemonRegistry.get_pokemon_by_id(id)
	if data == null:
		return

	_snapshot(id, data)
	# Snapped to the step, so a long run of presses lands on round numbers
	# instead of accumulating float error into the .tres.
	var moved := float(data.get(field)) + amount
	data.set(field, snappedf(clampf(moved, low, high), step))
	_after_edit(id)


func _cycle_body_type(step: int) -> void:
	var id := _focused_id()
	if id == "" or _spawned.is_empty():
		return
	var data := PokemonRegistry.get_pokemon_by_id(id)
	if data == null:
		return

	_snapshot(id, data)
	var count: int = PokemonBaseData.BodyType.keys().size()
	data.body_type = wrapi(int(data.body_type) + step, 0, count)
	# A species that just became a flier needs somewhere to fly. Body type and
	# resting altitude move together; tune the altitude with hover afterwards.
	data.hover_height = PokemonBaseData.default_hover_height(data.body_type)

	# The pivot height depends on body type, so the model has to be re-measured.
	_after_edit(id, true)


## Records what a species looked like on disk, once, before its first edit.
func _snapshot(id: String, data: PokemonBaseData) -> void:
	if _pending.has(id):
		return
	var baseline: Dictionary = {}
	for field: String in TUNED_FIELDS:
		baseline[field] = data.get(field)
	_pending[id] = baseline


## Everything that has to happen after any field on a species changes.
## [param reshape] re-measures the model, which only a body type change needs.
func _after_edit(id: String, reshape := false) -> void:
	_forget_if_unchanged(id)
	_exit_armed = false

	var entry := _meta_of(id)
	var data := PokemonRegistry.get_pokemon_by_id(id)
	if data != null:
		entry["body"] = int(data.body_type)
		_meta[id] = entry

	if reshape and not _spawned.is_empty():
		_spawned[0].refresh_animation()
	_sync_animators()

	# Not the info panel: it shows what a species is rather than how it moves,
	# and rebuilding it under a held-down + would cost more than it says.
	_ui.show_species(_focused_data())
	_ui.set_readout(_readout_text())
	_refresh_list_row(id)


## Pushes each spawned Pokémon's tuning back out of its [PokemonBaseData], which the
## edits above have already changed in place.
func _sync_animators() -> void:
	for pokemon in _spawned:
		var data := pokemon.data
		if data == null:
			continue
		pokemon.animator.speed_scale = data.anim_speed_scale
		pokemon.animator.amplitude = data.anim_amplitude
		pokemon.animator.hover_height = data.hover_height


## Drops a species from the pending set once it has been nudged back to exactly
## what is on disk, so the * marker and the unsaved count never overstate things.
func _forget_if_unchanged(id: String) -> void:
	var baseline: Dictionary = _pending.get(id, {})
	if baseline.is_empty():
		return
	var data := PokemonRegistry.get_pokemon_by_id(id)
	if data == null:
		return
	for field: String in baseline:
		if not is_equal_approx(float(data.get(field)), float(baseline[field])):
			return
	_pending.erase(id)


## Puts one species back to its snapshot and clears its pending mark.
func _revert(id: String) -> void:
	var baseline: Dictionary = _pending.get(id, {})
	if baseline.is_empty():
		return
	var data := PokemonRegistry.get_pokemon_by_id(id)
	if data != null:
		for field: String in baseline:
			data.set(field, baseline[field])
	_pending.erase(id)


func _revert_focused() -> void:
	var id := _focused_id()
	if not _pending.has(id):
		_ui.show_message("nothing to revert on this species")
		return
	_revert(id)
	_after_edit(id, true)
	_ui.show_message("reverted %s" % _meta_of(id)["name"])


func _revert_all() -> void:
	if _pending.is_empty():
		_ui.show_message("nothing to revert")
		return
	var count := _pending.size()
	# keys() is a snapshot, so erasing as we go is safe.
	for id: String in _pending.keys():
		_revert(id)
	_after_edit(_focused_id(), true)
	# This one touched rows all over the list, not just the focused one.
	_rebuild_list_labels()
	_ui.show_message("reverted %d species" % count)


func _save_edits() -> void:
	if _pending.is_empty():
		_ui.show_message("nothing to save")
		return

	if not OS.has_feature("editor"):
		_ui.show_message("saving needs the editor -- res:// is read-only in an export")
		return

	var saved := 0
	var failed := 0
	for id: String in _pending:
		var path := PokemonRegistry.get_path_for(id)
		var data := PokemonRegistry.get_pokemon_by_id(id)
		if path.is_empty() or data == null:
			failed += 1
			continue
		if not _patch_tres(path, data):
			failed += 1
			continue
		saved += 1

	_pending.clear()
	_exit_armed = false
	_rebuild_list_labels()
	_ui.set_readout(_readout_text())

	var note := "saved %d species" % saved
	if failed > 0:
		note += ", %d failed" % failed
	_ui.show_message(note)


## Writes this species' [constant TUNED_FIELDS] into its .tres by replacing those
## four lines and leaving every other byte alone. False, with a pushed error, if
## the file cannot be read, is missing one of the four fields, or cannot be
## written.
##
## Deliberately not [method ResourceSaver.save]. That rebuilds the whole file
## from the in-memory resource and drops the [code]uid="uid://..."[/code] off
## every ext_resource line on the way out, leaving the mesh, texture and script
## reachable only by their paths -- so a later asset move breaks the species
## silently instead of following it. Patching lines in place keeps the uids, the
## field order and the evolution links exactly as they are.
func _patch_tres(path: String, data: PokemonBaseData) -> bool:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("AdminMenu: could not read %s" % path)
		return false

	var wanted: Dictionary[String, String] = {}
	for field: String in TUNED_FIELDS:
		# var_to_str is what Godot writes .tres values with, so a float stays a
		# float -- "0.0", never "0", which would come back as an int.
		wanted[field] = "%s = %s" % [field, var_to_str(data.get(field))]

	var lines := text.split("\n")
	var written: Dictionary[String, bool] = {}
	var in_resource := false

	for i in lines.size():
		var line := lines[i]
		if line.begins_with("["):
			# These fields only ever live in [resource]. The ext_resource header
			# lines above it are the ones carrying the uids -- never touch them.
			in_resource = line.begins_with("[resource]")
			continue
		if not in_resource:
			continue
		var equals := line.find("=")
		if equals < 0:
			continue
		var field := line.substr(0, equals).strip_edges()
		if not wanted.has(field) or written.has(field):
			continue
		lines[i] = wanted[field]
		written[field] = true

	# A missing field means the file is not shaped the way we think it is, so
	# write nothing rather than a half-updated species.
	if written.size() != TUNED_FIELDS.size():
		var missing := PackedStringArray()
		for field: String in TUNED_FIELDS:
			if not written.has(field):
				missing.append(field)
		push_error("AdminMenu: %s has no line for %s -- left alone"
			% [path, ", ".join(missing)])
		return false

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("AdminMenu: could not open %s for writing" % path)
		return false
	file.store_string("\n".join(lines))
	return true


# -------------------------------------------------------------- collection

## The one place that has to know a collection exists.
##
## Everything above is already done by the time this runs: there is a focused
## species and [param level] is a number the screen has clamped into range.
## Replace the message with the real call -- something like
## [code]PlayerCollection.add(id, level)[/code] -- or leave it and listen for
## [signal add_to_collection] from wherever the collection lives.
func _add_to_collection(level: int) -> void:
	var id := _focused_id()
	if id == "":
		_ui.show_message("no species selected")
		return

	add_to_collection.emit(id, level)

	# TODO: wire the collection here.
	_ui.show_message("would add %s at level %d -- collection not wired yet"
		% [_meta_of(id)["name"], level])


# ----------------------------------------------------------------- searching

func _on_search_changed(text: String) -> void:
	var needle := text.strip_edges().to_lower()
	var keep := _focused_id()

	if needle.is_empty():
		_visible_ids = _all_ids
	else:
		var matches := PackedStringArray()
		for id in _all_ids:
			# The id carries the dex number and the slug, so "0092", "gastly"
			# and "alolan" all work. Names come from the metadata scan, so this
			# still loads nothing.
			var name_text: String = _meta_of(id)["name"]
			if needle in id.to_lower() or needle in name_text.to_lower():
				matches.append(id)
		_visible_ids = matches

	_rebuild_list()
	if _visible_ids.is_empty():
		_respawn()
		return

	# Stay on the same species if it survived the filter.
	var found := _visible_ids.find(keep)
	_index = found if found >= 0 else 0
	_respawn()


# ------------------------------------------------------------ what the screen shows

## The three panels that follow the focused species. The info panel is only
## marked dirty here, and not in [method _after_edit], because it shows what a
## species is rather than how it moves.
func _refresh_panels() -> void:
	_ui.show_species(_focused_data())
	_ui.set_readout(_readout_text())
	_ui.mark_info_dirty()


func _rebuild_list() -> void:
	_ui.set_rows(_list_labels())
	_ui.select_row(_index)


## Cheaper than a full rebuild when only the labels changed.
func _rebuild_list_labels() -> void:
	_ui.set_row_labels(_list_labels())


## Repaints a single row, which is all one edit can affect. Worth having as its
## own thing: the tuning buttons get pressed a lot, and relabelling 400 rows on
## every nudge is work nobody asked for.
func _refresh_list_row(id: String) -> void:
	var row := _visible_ids.find(id)
	if row >= 0:
		_ui.set_row_label(row, _list_label(id))


func _list_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for id in _visible_ids:
		labels.append(_list_label(id))
	return labels


func _list_label(id: String) -> String:
	var entry := _meta_of(id)
	var mark := " *" if _pending.has(id) else ""
	return "#%04d  %-20s %s%s" % [entry["dex"], entry["name"],
		AdminMenuUI.body_name(entry["body"]), mark]


## What you are looking at and how far each field has been moved. Written here
## rather than on the screen because every number in it -- the baselines, the
## unsaved count, how many models are up -- lives on this side.
func _readout_text() -> String:
	var data := _focused_data()
	if data == null:
		return "no match" if not _all_ids.is_empty() else "no species loaded"

	var filtered := ""
	if _visible_ids.size() != _all_ids.size():
		filtered = "  (filtered from %d)" % _all_ids.size()

	var baseline: Dictionary = _pending.get(_focused_id(), {})
	var lines := [
		"#%d  %s" % [data.dex_number, data.display_name],
		"%d of %d%s" % [_index + 1, _visible_ids.size(), filtered],
		"body type   %s%s" % [AdminMenuUI.body_name(data.body_type),
			_was(data, baseline, "body_type")],
		"speed       %.2f%s" % [data.anim_speed_scale,
			_was(data, baseline, "anim_speed_scale")],
		"amplitude   %.2f%s" % [data.anim_amplitude,
			_was(data, baseline, "anim_amplitude")],
		"hover       %.2f%s" % [data.hover_height,
			_was(data, baseline, "hover_height")],
	]
	if _grid:
		lines.append("grid        %d species" % _spawned.size())
	if not _pending.is_empty():
		lines.append("unsaved     %d species  (SAVE)" % _pending.size())
	return "\n".join(lines)


## "  (was 1.00)" for a field edited this session, "" for one still at its
## on-disk value -- so you can always see how far you have moved it, and back.
func _was(data: PokemonBaseData, baseline: Dictionary, field: String) -> String:
	if not baseline.has(field):
		return ""
	var before := float(baseline[field])
	if is_equal_approx(before, float(data.get(field))):
		return ""
	if field == "body_type":
		return "  (was %s)" % AdminMenuUI.body_name(int(before))
	return "  (was %.2f)" % before


func _status_text() -> String:
	if _spawned.is_empty():
		return ""
	var animator := _spawned[0].animator
	var loop_name: String = PokemonAnimator.Anim.keys()[animator.loop]
	if animator.is_one_shot_playing:
		var shot: String = PokemonAnimator.Anim.keys()[animator.current_one_shot]
		return "playing  %s  over  %s" % [shot, loop_name]
	return "playing  %s" % loop_name

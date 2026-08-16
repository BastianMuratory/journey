extends Node3D

## Animation sandbox and tuning editor. Not part of the game -- pick
## ANIMATION TEST on the main menu, or open this scene and press F6.
##
## Every species with a [PokemonData] shows up in the list on the right, forms
## and costumes included. Everything is on the keyboard so you can keep one hand
## on it and just watch:
## [codeblock]
## 1..5           idle / run / attack / hit / spin
## Left, Right    previous / next species
## PgUp, PgDn     jump 25 at a time
## Home, End      first / last
## /              search by name or id
## B, Shift+B     cycle this species' body type
## Up, Down       animation speed
## [ ]            animation amplitude
## , .            hover height
## Shift          x5 step on speed, amplitude and hover
## R, Shift+R     revert this species / every edited species
## Ctrl+S         save edits to disk
## G              grid mode -- a row of species, all animating together
## S              toggle shiny
## Esc            back to the main menu
## [/codeblock]
##
## The four tuning keys edit the focused species' [PokemonData] in place, so what
## you see is exactly what the game will play -- there is no preview multiplier
## sitting between the two. In grid mode the focused species is the leftmost one,
## the same one B applies to, so there is never any doubt what is being edited.
##
## Edits are held in memory until Ctrl+S, which writes them to two places: the
## species' own .tres so the game picks them up immediately, and
## data/body_type_overrides.json so that re-running
## tools/classify_body_types.py will not undo your work. R puts a species back to
## what is on disk, however many nudges ago that was.

## How many species stand side by side in grid mode.
const GRID_COUNT := 6
## Gap between them, as a multiple of the widest one.
const GRID_SPACING := 1.6
## How far PageUp and PageDown move through the list.
const PAGE_STRIDE := 25
## How long a status message stays on screen.
const MESSAGE_SECONDS := 4.0

## Nudge sizes, matching the @export_range steps on [PokemonData] so a value
## tuned here is one the inspector can also express.
const SPEED_STEP := 0.05
const AMPLITUDE_STEP := 0.05
const HOVER_STEP := 0.02
## What holding Shift multiplies a nudge by, for crossing the range quickly.
const COARSE_STEP := 5.0

## The fields Ctrl+S writes, and the ones R puts back. Kept in one place because
## the baseline snapshot, the revert and the overrides file must agree on them.
const TUNED_FIELDS := [
	"body_type", "anim_speed_scale", "anim_amplitude", "hover_height",
]

const POKEMON_SCENE := preload("res://entities/pokemon/pokemon.tscn")
const MAIN_MENU_SCENE := "res://game_scenes/main_menu/main_menu.tscn"
const DATA_DIR := "res://data/pokemon/"
## Read by tools/classify_body_types.py, which treats it as the highest-priority
## source for every field in [constant TUNED_FIELDS].
const OVERRIDES_PATH := "res://data/body_type_overrides.json"

@onready var _camera: Camera3D = $Camera3D

## Every id the registry knows, ascending.
var _all_ids: PackedStringArray = []
## The subset currently listed, after the search filter. Navigation indexes this.
var _visible_ids: PackedStringArray = []
var _index := 0

## id -> {dex: int, name: String, body: int}.
##
## Read straight out of the .tres text rather than through the registry, because
## loading a PokemonData pulls its mesh in with it -- and a 410-row list that
## loaded 410 models to draw itself would take seconds and hundreds of MB. The
## registry stays lazy; only the species actually on screen get loaded.
var _meta: Dictionary[String, Dictionary] = {}

var _shiny := false
var _grid := false

## id -> the [constant TUNED_FIELDS] values that species had on disk, snapshotted
## just before its first edit of the session.
##
## Being in here means "has unsaved edits" -- the current values are not copied,
## they live on the [PokemonData] itself, which is what the spawned Pokémon and
## the save both read. Keeping only the baseline means R can undo a whole run of
## nudges exactly, with no drift.
var _pending: Dictionary[String, Dictionary] = {}
## Set by the first Esc when there are unsaved edits, so the second one leaves.
var _exit_armed := false

var _spawned: Array[Pokemon] = []

var _info: Label
var _status: Label
var _message: Label
var _message_seconds := 0.0
var _list: ItemList
var _search: LineEdit


func _ready() -> void:
	_all_ids = PokemonRegistry.get_all_ids()
	if _all_ids.is_empty():
		push_error("AnimationTest: PokemonRegistry has no species. Nothing to show.")
		return

	_visible_ids = _all_ids
	_scan_metadata()
	_build_hud()
	_rebuild_list()
	_respawn()


func _process(delta: float) -> void:
	# The one-shot state changes on its own, so the status line polls instead of
	# waiting for a signal.
	if _status != null:
		_status.text = _status_text()

	if _message_seconds > 0.0:
		_message_seconds -= delta
		if _message_seconds <= 0.0 and _message != null:
			_message.text = ""


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


func _body_name(body: int) -> String:
	var names: Array = PokemonData.BodyType.keys()
	return names[body] if body >= 0 and body < names.size() else "?"


# ----------------------------------------------------------------- spawning

func _respawn() -> void:
	for pokemon in _spawned:
		pokemon.queue_free()
	_spawned.clear()

	if _visible_ids.is_empty():
		_refresh_info()
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
	_refresh_info()
	_sync_list_selection()


func _spawn(id: String) -> Pokemon:
	var data := PokemonRegistry.get_pokemon_by_id(id)
	if data == null:
		return null

	var pokemon: Pokemon = POKEMON_SCENE.instantiate()
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
func _footprint(pokemon: Pokemon) -> float:
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


# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	# While the search box has focus it owns the keyboard, apart from the two
	# keys that dismiss it.
	if _search != null and _search.has_focus():
		if key.keycode == KEY_ESCAPE or key.keycode == KEY_ENTER:
			_close_search()
			get_viewport().set_input_as_handled()
		return

	if key.ctrl_pressed and key.keycode == KEY_S:
		_save_edits()
		get_viewport().set_input_as_handled()
		return

	var handled := true
	match key.keycode:
		KEY_1: _play(PokemonAnimator.Anim.IDLE)
		KEY_2: _play(PokemonAnimator.Anim.RUN)
		KEY_3: _play(PokemonAnimator.Anim.ATTACK)
		KEY_4: _play(PokemonAnimator.Anim.HIT)
		KEY_5: _play(PokemonAnimator.Anim.SPIN)
		KEY_RIGHT: _step_species(1)
		KEY_LEFT: _step_species(-1)
		KEY_PAGEDOWN: _step_species(PAGE_STRIDE)
		KEY_PAGEUP: _step_species(-PAGE_STRIDE)
		KEY_HOME: _jump_to(0)
		KEY_END: _jump_to(_visible_ids.size() - 1)
		KEY_SLASH: _open_search()
		KEY_B: _cycle_body_type(-1 if key.shift_pressed else 1)
		KEY_UP: _nudge("anim_speed_scale", 1, SPEED_STEP, 0.25, 3.0, key.shift_pressed)
		KEY_DOWN: _nudge("anim_speed_scale", -1, SPEED_STEP, 0.25, 3.0, key.shift_pressed)
		KEY_BRACKETRIGHT: _nudge("anim_amplitude", 1, AMPLITUDE_STEP, 0.0, 3.0, key.shift_pressed)
		KEY_BRACKETLEFT: _nudge("anim_amplitude", -1, AMPLITUDE_STEP, 0.0, 3.0, key.shift_pressed)
		KEY_PERIOD: _nudge("hover_height", 1, HOVER_STEP, 0.0, 2.0, key.shift_pressed)
		KEY_COMMA: _nudge("hover_height", -1, HOVER_STEP, 0.0, 2.0, key.shift_pressed)
		KEY_G:
			_grid = not _grid
			_respawn()
		KEY_S:
			_shiny = not _shiny
			_respawn()
		KEY_R:
			if key.shift_pressed:
				_revert_all()
			else:
				_revert_focused()
		KEY_ESCAPE:
			_leave()
		_:
			handled = false

	if handled:
		get_viewport().set_input_as_handled()


## Esc with unsaved edits warns once and leaves on the second press. Losing a
## tuning session to a stray key would be a miserable way to end it.
func _leave() -> void:
	if not _pending.is_empty() and not _exit_armed:
		_exit_armed = true
		_show_message("%d species edited -- Ctrl+S to save, Esc again to discard"
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


# ----------------------------------------------------------- species editing

## The species being edited. In grid mode that is the leftmost one, so there is
## always exactly one thing the tuning keys apply to.
func _focused_id() -> String:
	return _visible_ids[_index] if not _visible_ids.is_empty() else ""


## Moves one float field on the focused species by [param direction] steps,
## clamped to the same range [PokemonData] exports.
func _nudge(field: String, direction: int, step: float, low: float, high: float,
		coarse: bool) -> void:
	var id := _focused_id()
	if id == "":
		return
	var data := PokemonRegistry.get_pokemon_by_id(id)
	if data == null:
		return

	_snapshot(id, data)
	var moved: float = float(data.get(field)) \
		+ step * direction * (COARSE_STEP if coarse else 1.0)
	# Snapped to the step, so a long run of presses lands on round numbers
	# instead of accumulating float error into the .tres.
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
	var count: int = PokemonData.BodyType.keys().size()
	data.body_type = wrapi(int(data.body_type) + step, 0, count)
	# A species that just became a flier needs somewhere to fly. Body type and
	# resting altitude move together; tune the altitude with , and . afterwards.
	data.hover_height = PokemonData.default_hover_height(data.body_type)

	# The pivot height depends on body type, so the model has to be re-measured.
	_after_edit(id, true)


## Records what a species looked like on disk, once, before its first edit.
func _snapshot(id: String, data: PokemonData) -> void:
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
	_refresh_info()
	_refresh_list_row(id)


## Pushes each spawned Pokémon's tuning back out of its [PokemonData], which the
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
		_show_message("nothing to revert on this species")
		return
	_revert(id)
	_after_edit(id, true)
	_show_message("reverted %s" % _meta_of(id)["name"])


func _revert_all() -> void:
	if _pending.is_empty():
		_show_message("nothing to revert")
		return
	var count := _pending.size()
	# keys() is a snapshot, so erasing as we go is safe.
	for id: String in _pending.keys():
		_revert(id)
	_after_edit(_focused_id(), true)
	# This one touched rows all over the list, not just the focused one.
	_rebuild_list_labels()
	_show_message("reverted %d species" % count)


func _save_edits() -> void:
	if _pending.is_empty():
		_show_message("nothing to save")
		return

	if not OS.has_feature("editor"):
		_show_message("saving needs the editor -- res:// is read-only in an export")
		return

	var saved := 0
	var failed := 0
	for id: String in _pending:
		var path := PokemonRegistry.get_path_for(id)
		var data := PokemonRegistry.get_pokemon_by_id(id)
		if path.is_empty() or data == null:
			failed += 1
			continue
		# Saving the resource rather than rewriting the text keeps every other
		# field -- evolution links included -- exactly as it was.
		if ResourceSaver.save(data, path) != OK:
			push_error("AnimationTest: could not write %s" % path)
			failed += 1
			continue
		saved += 1

	var wrote_overrides := _write_overrides()
	_pending.clear()
	_exit_armed = false
	_rebuild_list_labels()
	_refresh_info()

	var note := "saved %d species" % saved
	if failed > 0:
		note += ", %d failed" % failed
	if not wrote_overrides:
		note += " (overrides file not written)"
	_show_message(note)


## Merges this session's edits into the overrides file, so a later
## classify_body_types.py run keeps them instead of reverting them.
func _write_overrides() -> bool:
	var doc: Dictionary = {}
	if FileAccess.file_exists(OVERRIDES_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OVERRIDES_PATH))
		if parsed is Dictionary:
			doc = parsed

	var species: Dictionary = {}
	if doc.get("species") is Dictionary:
		species = doc["species"]

	for id: String in _pending:
		var data := PokemonRegistry.get_pokemon_by_id(id)
		if data == null:
			continue
		# All four fields go in, not just the ones that moved: the point of an
		# entry here is to pin down exactly what you saw on screen, and a partial
		# one would let the script's tables fill in the rest on the next run.
		species[id] = {
			"body_type": _body_name(data.body_type),
			"anim_speed_scale": data.anim_speed_scale,
			"anim_amplitude": data.anim_amplitude,
			"hover_height": data.hover_height,
		}

	doc["_comment"] = ("Hand edits from the animation test scene, keyed by species id. "
		+ "tools/classify_body_types.py reads this first and will not overwrite "
		+ "anything listed here.")
	doc["species"] = species

	var file := FileAccess.open(OVERRIDES_PATH, FileAccess.WRITE)
	if file == null:
		push_error("AnimationTest: could not open %s for writing" % OVERRIDES_PATH)
		return false
	file.store_string(JSON.stringify(doc, "  ") + "\n")
	return true


# ----------------------------------------------------------------- searching

func _open_search() -> void:
	if _search == null:
		return
	_search.visible = true
	_search.grab_focus()
	_search.select_all()


func _close_search() -> void:
	if _search == null:
		return
	_search.release_focus()
	if _search.text.strip_edges().is_empty():
		_search.visible = false


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


# ----------------------------------------------------------------------- hud

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	# --- left: what you are looking at, and what the keys do ---
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(380, 0)
	layer.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(_padded(column))

	_info = Label.new()
	column.add_child(_info)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	column.add_child(_status)

	_message = Label.new()
	_message.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	column.add_child(_message)

	var help := Label.new()
	help.text = """1-5  idle / run / attack / hit / spin
<- ->  species     PgUp/PgDn  x25     /  search
B / Shift+B  body type     up/dn  speed
[ ]  amplitude     , .  hover     Shift  x5 step
R  revert     Shift+R  revert all     Ctrl+S  save
G  grid     S  shiny     Esc  menu"""
	help.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	column.add_child(help)

	# --- right: the full species list ---
	var browser := PanelContainer.new()
	browser.anchor_left = 1.0
	browser.anchor_right = 1.0
	browser.anchor_bottom = 1.0
	browser.offset_left = -340.0
	browser.offset_right = -16.0
	browser.offset_top = 16.0
	browser.offset_bottom = -16.0
	layer.add_child(browser)

	var browser_column := VBoxContainer.new()
	browser_column.add_theme_constant_override("separation", 6)
	browser.add_child(_padded(browser_column))

	_search = LineEdit.new()
	_search.placeholder_text = "search name or id, Esc to close"
	_search.visible = false
	_search.text_changed.connect(_on_search_changed)
	browser_column.add_child(_search)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Never let the list take the keyboard -- every key belongs to the scene.
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_list_selected)
	browser_column.add_child(_list)


## Wraps a control in even padding, which PanelContainer does not add itself.
func _padded(inner: Control, amount := 12) -> MarginContainer:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, amount)
	margin.add_child(inner)
	return margin


func _rebuild_list() -> void:
	if _list == null:
		return
	_list.clear()
	for id in _visible_ids:
		_list.add_item(_list_label(id))
	_sync_list_selection()


## Cheaper than a full rebuild when only the labels changed.
func _rebuild_list_labels() -> void:
	if _list == null:
		return
	for i in mini(_visible_ids.size(), _list.item_count):
		_list.set_item_text(i, _list_label(_visible_ids[i]))


## Repaints a single row, which is all one edit can affect. Worth having as its
## own thing: the tuning keys get pressed a lot, and relabelling 400 rows on
## every nudge is work nobody asked for.
func _refresh_list_row(id: String) -> void:
	if _list == null:
		return
	var row := _visible_ids.find(id)
	if row >= 0 and row < _list.item_count:
		_list.set_item_text(row, _list_label(id))


func _list_label(id: String) -> String:
	var entry := _meta_of(id)
	var mark := " *" if _pending.has(id) else ""
	return "#%04d  %-20s %s%s" % [entry["dex"], entry["name"], _body_name(entry["body"]), mark]


func _sync_list_selection() -> void:
	if _list == null or _visible_ids.is_empty():
		return
	if _index < _list.item_count:
		_list.select(_index)
		_list.ensure_current_is_visible()


func _on_list_selected(index: int) -> void:
	_jump_to(index)


func _show_message(text: String) -> void:
	if _message == null:
		return
	_message.text = text
	_message_seconds = MESSAGE_SECONDS


func _refresh_info() -> void:
	if _info == null:
		return

	if _spawned.is_empty():
		_info.text = "no match" if not _all_ids.is_empty() else "no species loaded"
		return

	var data := _spawned[0].data
	var filtered := ""
	if _visible_ids.size() != _all_ids.size():
		filtered = "  (filtered from %d)" % _all_ids.size()

	var baseline: Dictionary = _pending.get(_focused_id(), {})
	var lines := [
		"#%d  %s" % [data.dex_number, data.display_name],
		"%d of %d%s" % [_index + 1, _visible_ids.size(), filtered],
		"body type   %s%s" % [_body_name(data.body_type),
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
		lines.append("unsaved     %d species  (Ctrl+S)" % _pending.size())
	_info.text = "\n".join(lines)


## "  (was 1.00)" for a field edited this session, "" for one still at its
## on-disk value -- so you can always see how far you have moved it, and back.
func _was(data: PokemonData, baseline: Dictionary, field: String) -> String:
	if not baseline.has(field):
		return ""
	var before := float(baseline[field])
	if is_equal_approx(before, float(data.get(field))):
		return ""
	if field == "body_type":
		return "  (was %s)" % _body_name(int(before))
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

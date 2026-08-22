extends Node3D

## Animation sandbox and tuning editor. Not part of the game -- pick
## ANIMATION TEST on the main menu, or open this scene and press F6.
##
## Every species with a [PokemonBaseData] shows up in the list on the right, forms
## and costumes included. Every control is an on-screen button and nothing is
## bound to the keyboard, so the same screen works under a mouse today and under
## a finger once there is a touch build -- there is no input layer left to port.
##
## The controls are split between two panels, which is mostly about keeping the
## model visible: the bar across the bottom is two rows tall and no more, and
## anything that could live beside the list instead does.
##
## [codeblock]
## bottom   idle / run / attack / hit / spin     grid, shiny, info
##          revert, revert all, save, menu, tuning
##          body type, speed, amplitude, hover -- each a - / + pair
##          x5, which makes every step five times bigger
## right    search, species navigation, the list itself,
##          level, and add to collection
## [/codeblock]
##
## TUNING folds the second row of the bar away when even that is in the way.
##
## Holding a - or + down repeats it, which is how you cross a whole range without
## tapping forty times. The step sizes match the @export_range steps on
## [PokemonBaseData], so a value tuned here is one the inspector can also express.
##
## Artwork comes from the species where the species has it: the icon sits beside
## the readout and the info title, and both previews sit at the top of the info
## panel. Type icons are the exception -- nothing carries one, so they are found
## on disk by name, see [constant TYPE_ICON_DIRS]. Anything missing is simply not
## drawn; no part of this screen needs a texture to work.
##
## INFO opens the read-only half of a species: previews, typing, base stats,
## quest stats and every move it can learn, each drawn with its own icon where
## the move has one.
##
## The four tuning fields are edited on the focused species' [PokemonBaseData] in
## place, so what you see is exactly what the game will play -- there is no
## preview multiplier sitting between the two. In grid mode the focused species is
## the leftmost one, so there is never any doubt what is being edited.
##
## Edits are held in memory until SAVE, which writes them into the species' own
## .tres -- the four tuned fields, plus [code]anim_tuned = true[/code], which is
## what stops tools/classify_body_types.py and tools/generate_pokemon_data.py from
## recomputing them on a later run. REVERT puts a species back to what is on disk,
## however many nudges ago that was.
##
## ADD TO COLLECTION is deliberately inert: it reads the level box, emits
## [signal collection_add_requested] and reports what it would have done. Wire the
## collection itself in [method _add_to_collection] -- that one function is the
## only place that has to know the collection exists.

## Emitted by ADD TO COLLECTION, carrying the focused species and the level in the
## box. Nothing in this scene listens; it is here so a collection can be hooked up
## from outside without editing this file.
signal collection_add_requested(id: String, level: int)

## How many species stand side by side in grid mode.
const GRID_COUNT := 6
## Gap between them, as a multiple of the widest one.
const GRID_SPACING := 1.6
## How far the -25 and +25 buttons move through the list.
const PAGE_STRIDE := 25
## How long a status message stays on screen.
const MESSAGE_SECONDS := 4.0

## Nudge sizes, matching the @export_range steps on [PokemonBaseData] so a value
## tuned here is one the inspector can also express.
const SPEED_STEP := 0.05
const AMPLITUDE_STEP := 0.05
const HOVER_STEP := 0.02
## What the x5 toggle multiplies a nudge by, for crossing the range quickly.
const COARSE_STEP := 5.0

## How long a - or + has to be held before it starts repeating, and how often it
## repeats after that. The delay is what keeps a single deliberate tap single.
const HOLD_DELAY := 0.4
const HOLD_RATE := 0.06
## The rate for steps that respawn the model rather than move a number. Each one
## is a mesh coming off disk, and sixteen of those a second is a slideshow.
const HOLD_RATE_HEAVY := 0.18

## Minimum side of anything meant to be tapped. Roughly a fingertip at the
## densities phones ship at, and the reason the bar is as tall as it is.
const TOUCH_SIZE := 44.0
## Width of the species browser down the right-hand side.
const BROWSER_WIDTH := 340.0
## Width of the info panel, and the height its scrolling body settles at.
const INFO_WIDTH := 560.0
const INFO_BODY_HEIGHT := 380.0
## Side of a chip icon, of the species icon beside the readout and the info
## title, and of a preview tile in the info panel.
const CHIP_ICON_SIZE := 26.0
const READOUT_ICON_SIZE := 52.0
const INFO_TITLE_ICON_SIZE := 40.0
const PREVIEW_SIZE := 150.0

## Where the type icons live. Unlike the species icon and previews, a type icon
## is not a field on anything -- there is nothing to read it off -- so it is
## found on disk by name instead: TYPE_ICON_DIRS crossed with
## TYPE_ICON_PATTERNS, with the type's own enum name lowercased into the %s
## ("fire", "water"). First file that exists wins, and a type with no file falls
## back to the plain coloured badge, so a wrong guess here costs nothing.
##
## Trim these two lists to the one directory and one pattern this project
## actually uses once you know which it is -- the misses are cached, but the
## list is still 20-odd lookups the first time a type is drawn.
const TYPE_ICON_DIRS := [
	"res://assets/ui/types/",
	"res://assets/ui/type_icons/",
	"res://assets/types/",
	"res://assets/icons/types/",
	"res://ui/types/",
]
const TYPE_ICON_PATTERNS := [
	"%s.png", "%s.svg", "%s.webp", "type_%s.png", "type_%s.svg",
]

## What a stat bar treats as full. Nothing in the data is near it, which is the
## point -- bars are comparable across species instead of being rescaled per row.
const STAT_BAR_MAX := 255.0

const LEVEL_MIN := 1
const LEVEL_MAX := 100
const LEVEL_DEFAULT := 5

## The fields SAVE writes, and the ones REVERT puts back. Kept in one place
## because the baseline snapshot and the revert must agree on them.
const TUNED_FIELDS := [
	"body_type", "anim_speed_scale", "anim_amplitude", "hover_height",
]
## Written alongside [constant TUNED_FIELDS] on save, and inserted if the file has
## no line for it yet. Mirrors PokemonBaseData.anim_tuned, and is read by
## tools/classify_body_types.py as its do-not-touch marker.
const TUNED_FLAG_FIELD := "anim_tuned"

const POKEMON_MODEL_SCENE := preload("res://pokemon/pokemon_model.tscn")
const MAIN_MENU_SCENE := "res://game_scenes/main_menu/main_menu.tscn"
const DATA_DIR := "res://data/pokemon_base_data/"

## One colour per [enum PokemonBaseData.Type], in the enum's own order, so a type
## can be looked up by its value. Written as components rather than hex strings
## because only the component form is a constant expression.
const TYPE_COLORS := [
	Color(0.45, 0.45, 0.50),  # NONE
	Color(0.659, 0.659, 0.471),  # NORMAL
	Color(0.753, 0.188, 0.157),  # FIGHTING
	Color(0.659, 0.565, 0.941),  # FLYING
	Color(0.627, 0.251, 0.627),  # POISON
	Color(0.878, 0.753, 0.408),  # GROUND
	Color(0.722, 0.627, 0.220),  # ROCK
	Color(0.659, 0.722, 0.125),  # BUG
	Color(0.439, 0.345, 0.596),  # GHOST
	Color(0.722, 0.722, 0.816),  # STEEL
	Color(0.941, 0.502, 0.188),  # FIRE
	Color(0.408, 0.565, 0.941),  # WATER
	Color(0.471, 0.784, 0.314),  # GRASS
	Color(0.973, 0.816, 0.188),  # ELECTRIC
	Color(0.973, 0.345, 0.533),  # PSYCHIC
	Color(0.596, 0.847, 0.847),  # ICE
	Color(0.439, 0.220, 0.973),  # DRAGON
	Color(0.439, 0.345, 0.282),  # DARK
	Color(0.933, 0.600, 0.675),  # FAIRY
]

## The Move class is not this scene's to know, so its fields are looked for by
## name and quietly skipped when absent -- a move with no icon still gets a chip,
## and adding an icon later needs no change here. First match wins.
const MOVE_NAME_FIELDS := ["display_name", "move_name", "name", "id"]
const MOVE_ICON_FIELDS := ["icon", "texture", "sprite"]
const MOVE_TYPE_FIELDS := ["type", "move_type", "element"]

const TEXT_DIM := Color(0.65, 0.65, 0.72)
const TEXT_STATUS := Color(0.55, 0.90, 1.00)
const TEXT_MESSAGE := Color(1.00, 0.85, 0.40)
const TEXT_ACCENT := Color(0.60, 1.00, 0.72)

@onready var _camera: Camera3D = $Camera3D

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
## Set by the x5 button. Stands in for the Shift key the tuning keys used to read.
var _coarse := false

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

## The - or + currently held down, and the countdown to its next repeat. An
## invalid Callable means nothing is held, which is the state between presses.
var _held := Callable()
var _hold_seconds := 0.0
var _hold_rate := HOLD_RATE

var _readout: Label
var _readout_icon: TextureRect
var _status: Label
var _message: Label
var _message_seconds := 0.0
var _list: ItemList
var _search: LineEdit

## Type -> its icon, or null when no file was found. Misses are cached too: a
## project with no type icons at all should not re-check the disk every rebuild.
var _type_icons: Dictionary[int, Texture2D] = {}

## The second row of the bar, which the TUNING button folds away.
var _tuning_row: HFlowContainer
## Field name -> the label between that field's - and + buttons.
var _value_labels: Dictionary[String, Label] = {}
var _level_edit: LineEdit

var _info_button: Button
var _info_panel: PanelContainer
var _info_icon: TextureRect
var _info_title: Label
var _info_body: VBoxContainer
## The panel is only rebuilt when it is open, so a species change while it is shut
## just leaves this set for the next time it opens.
var _info_dirty := true


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

	if _held.is_valid():
		_hold_seconds -= delta
		if _hold_seconds <= 0.0:
			_hold_seconds = _hold_rate
			_held.call()


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
	var names: Array = PokemonBaseData.BodyType.keys()
	return names[body] if body >= 0 and body < names.size() else "?"


func _type_name(type: int) -> String:
	var names: Array = PokemonBaseData.Type.keys()
	return names[type] if type >= 0 and type < names.size() else "?"


func _type_color(type: int) -> Color:
	if type >= 0 and type < TYPE_COLORS.size():
		return TYPE_COLORS[type]
	return TYPE_COLORS[0]


## This type's icon, or null if the project has none where it was looked for.
## Null is cached alongside the hits, so a miss costs one sweep of the candidate
## paths per type per session and nothing after that.
func _type_icon(type: int) -> Texture2D:
	if _type_icons.has(type):
		return _type_icons[type] as Texture2D

	var slug := _type_name(type).to_lower()
	var found: Texture2D = null
	for dir: String in TYPE_ICON_DIRS:
		for pattern: String in TYPE_ICON_PATTERNS:
			var path: String = dir + (pattern % slug)
			# ResourceLoader rather than FileAccess: an exported build has no
			# .png sitting at that path, only the imported resource it remaps to.
			if ResourceLoader.exists(path):
				found = load(path) as Texture2D
				break
		if found != null:
			break

	_type_icons[type] = found
	return found


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
		_refresh_readout()
		_refresh_controls()
		_mark_info_dirty()
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
	_refresh_readout()
	_refresh_controls()
	_mark_info_dirty()
	_sync_list_selection()


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
		_show_message("%d species edited -- SAVE first, or MENU again to discard"
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


func _jump_last() -> void:
	_jump_to(_visible_ids.size() - 1)


func _set_grid(on: bool) -> void:
	_grid = on
	_respawn()


func _set_shiny(on: bool) -> void:
	_shiny = on
	_respawn()


func _set_coarse(on: bool) -> void:
	_coarse = on


## Folds the tuning row away. The bar is two rows already; this is for when even
## the second one is between you and the model.
func _set_tuning_visible(on: bool) -> void:
	if _tuning_row != null:
		_tuning_row.visible = on


# ----------------------------------------------------------- species editing

## Moves one float field on the focused species by [param direction] steps,
## clamped to the same range [PokemonBaseData] exports.
func _nudge(field: String, direction: int, step: float, low: float, high: float) -> void:
	var id := _focused_id()
	if id == "":
		return
	var data := PokemonRegistry.get_pokemon_by_id(id)
	if data == null:
		return

	_snapshot(id, data)
	var moved: float = float(data.get(field)) \
		+ step * direction * (COARSE_STEP if _coarse else 1.0)
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
	_refresh_readout()
	_refresh_controls()
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
		if not _patch_tres(path, data):
			failed += 1
			continue
		saved += 1

	_pending.clear()
	_exit_armed = false
	_rebuild_list_labels()
	_refresh_readout()

	var note := "saved %d species" % saved
	if failed > 0:
		note += ", %d failed" % failed
	_show_message(note)


## Writes this species' [constant TUNED_FIELDS] into its .tres by replacing those
## four lines and leaving every other byte alone, then sets
## [constant TUNED_FLAG_FIELD] so the tools stop recomputing them. False, with a
## pushed error, if the file cannot be read, is missing one of the four fields, or
## cannot be written.
##
## The flag line is inserted when the file has none, which is the case for every
## species the first time it is tuned -- and again if Godot ever rewrites the file
## and drops the line for sitting at its default.
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
		push_error("AnimationTest: could not read %s" % path)
		return false

	var wanted: Dictionary[String, String] = {}
	for field: String in TUNED_FIELDS:
		# var_to_str is what Godot writes .tres values with, so a float stays a
		# float -- "0.0", never "0", which would come back as an int.
		wanted[field] = "%s = %s" % [field, var_to_str(data.get(field))]

	var lines := text.split("\n")
	var written: Dictionary[String, bool] = {}
	var in_resource := false
	## Where the flag already sits, and where to put it if it does not: straight
	## after the last of the four fields, keeping the group together.
	var flag_index := -1
	var last_field_index := -1

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
		if field == TUNED_FLAG_FIELD and flag_index < 0:
			flag_index = i
			continue
		if not wanted.has(field) or written.has(field):
			continue
		lines[i] = wanted[field]
		written[field] = true
		last_field_index = i

	# A missing field means the file is not shaped the way we think it is, so
	# write nothing rather than a half-updated species.
	if written.size() != TUNED_FIELDS.size():
		var missing := PackedStringArray()
		for field: String in TUNED_FIELDS:
			if not written.has(field):
				missing.append(field)
		push_error("AnimationTest: %s has no line for %s -- left alone"
			% [path, ", ".join(missing)])
		return false

	var flag_line := "%s = true" % TUNED_FLAG_FIELD
	if flag_index >= 0:
		lines[flag_index] = flag_line
	else:
		lines.insert(last_field_index + 1, flag_line)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("AnimationTest: could not open %s for writing" % path)
		return false
	file.store_string("\n".join(lines))
	return true


# -------------------------------------------------------------- collection

## Reads the level box, clamps it into range and writes the clamped value back,
## so what the box shows is always what a press would use.
func _commit_level() -> int:
	if _level_edit == null:
		return LEVEL_DEFAULT
	var level := clampi(_level_edit.text.to_int(), LEVEL_MIN, LEVEL_MAX)
	_level_edit.text = str(level)
	return level


func _step_level(direction: int) -> void:
	if _level_edit == null:
		return
	var step := int(COARSE_STEP) if _coarse else 1
	var level := clampi(_commit_level() + direction * step, LEVEL_MIN, LEVEL_MAX)
	_level_edit.text = str(level)


## Keeps the box to digits while it is being typed in. Assigning to text from
## code does not re-emit text_changed, so this cannot loop.
func _on_level_text_changed(text: String) -> void:
	var digits := ""
	for i in text.length():
		if text[i].is_valid_int():
			digits += text[i]
	if digits == text:
		return
	var caret := _level_edit.caret_column
	_level_edit.text = digits
	_level_edit.caret_column = mini(caret, digits.length())


func _on_level_submitted(_text: String) -> void:
	_commit_level()
	_level_edit.release_focus()


## The one place that has to know a collection exists.
##
## Everything above is already done by the time this runs: there is a focused
## species and the level is a number inside [constant LEVEL_MIN] and
## [constant LEVEL_MAX]. Replace the message with the real call -- something like
## [code]PlayerCollection.add(id, level)[/code] -- or leave it and listen for
## [signal collection_add_requested] from wherever the collection lives.
func _add_to_collection() -> void:
	var id := _focused_id()
	if id == "":
		_show_message("no species selected")
		return

	var level := _commit_level()
	collection_add_requested.emit(id, level)

	# TODO: wire the collection here.
	_show_message("would add %s at level %d -- collection not wired yet"
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


func _clear_search() -> void:
	if _search == null or _search.text.is_empty():
		return
	_search.text = ""
	# Assigning to text does not emit text_changed, so the filter is re-run here.
	_on_search_changed("")


# --------------------------------------------------------------- hud: pieces

## A button sized for a fingertip that never takes keyboard focus -- focus would
## put a ring on whatever was tapped last and let Space fire it again.
func _make_button(text: String, action: Callable, width := 0.0) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, TOUCH_SIZE)
	button.pressed.connect(action)
	return button


## The same, but held down it keeps firing. Only the - and + pairs get this:
## crossing speed's range one tap at a time is 55 taps, and nobody would.
func _make_step_button(text: String, action: Callable, rate := HOLD_RATE) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(TOUCH_SIZE, TOUCH_SIZE)
	button.add_theme_font_size_override("font_size", 20)
	button.button_down.connect(_begin_hold.bind(action, rate))
	button.button_up.connect(_end_hold)
	return button


func _make_toggle(text: String, on: bool, action: Callable, width := 0.0) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = on
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(width, TOUCH_SIZE)
	button.toggled.connect(action)
	return button


## Fires once immediately, then again on a timer until the button comes back up,
## which is what makes a tap a tap and a hold a slide.
func _begin_hold(action: Callable, rate := HOLD_RATE) -> void:
	action.call()
	_held = action
	_hold_rate = rate
	_hold_seconds = HOLD_DELAY


func _end_hold() -> void:
	_held = Callable()


func _caption(text: String, width := 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, TOUCH_SIZE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", TEXT_DIM)
	return label


## "title  [-]  value  [+]" -- the shape every tuned field takes. The value label
## is registered under [param key] so [method _refresh_controls] can find it.
func _make_stepper(key: String, title: String, width: float, down: Callable,
		up: Callable, rate := HOLD_RATE) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_caption(title))
	row.add_child(_make_step_button("−", down, rate))

	var value := Label.new()
	value.custom_minimum_size = Vector2(width, TOUCH_SIZE)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	_value_labels[key] = value

	row.add_child(_make_step_button("+", up, rate))
	return row


## Wraps a control in even padding, which PanelContainer does not add itself.
func _padded(inner: Control, amount := 12) -> MarginContainer:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, amount)
	margin.add_child(inner)
	return margin


# ---------------------------------------------------------------- hud: build

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	_build_readout(layer)
	_build_browser(layer)
	_build_controls(layer)
	_build_info_panel(layer)


## Top left: the species icon, what you are looking at, and how far each field
## has been moved.
func _build_readout(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(380, 0)
	layer.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(_padded(column))

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)

	_readout_icon = _texture_rect(null, READOUT_ICON_SIZE)
	# Top of the icon lines up with the first line of text rather than floating
	# in the middle of six of them.
	_readout_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.add_child(_readout_icon)

	_readout = Label.new()
	_readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_readout)

	_status = Label.new()
	_status.add_theme_color_override("font_color", TEXT_STATUS)
	column.add_child(_status)

	_message = Label.new()
	_message.add_theme_color_override("font_color", TEXT_MESSAGE)
	column.add_child(_message)


## Right: search, the species list, and everything that is about picking a
## species rather than animating one. Vertical room is free here -- the list is
## the only thing that gives any up -- so this is where the bar's rows went.
func _build_browser(layer: CanvasLayer) -> void:
	var browser := PanelContainer.new()
	browser.anchor_left = 1.0
	browser.anchor_right = 1.0
	browser.anchor_bottom = 1.0
	browser.offset_left = -(BROWSER_WIDTH + 16.0)
	browser.offset_right = -16.0
	browser.offset_top = 16.0
	browser.offset_bottom = -16.0
	layer.add_child(browser)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	browser.add_child(_padded(column, 10))

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 4)
	column.add_child(search_row)

	_search = LineEdit.new()
	_search.placeholder_text = "search name or id"
	_search.custom_minimum_size = Vector2(0, TOUCH_SIZE)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The built-in clear button is a few pixels across; the one next to it is not.
	_search.clear_button_enabled = false
	_search.text_changed.connect(_on_search_changed)
	search_row.add_child(_search)

	search_row.add_child(_make_button("×", _clear_search, TOUCH_SIZE))

	column.add_child(_build_nav_row())

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Rows are for tapping, not for tabbing to.
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_list_selected)
	column.add_child(_list)

	column.add_child(HSeparator.new())
	column.add_child(_build_level_row())

	var add := _make_button("add to collection", _add_to_collection)
	add.add_theme_color_override("font_color", TEXT_ACCENT)
	column.add_child(add)


## Bottom: what is left once the species controls moved to the browser -- the
## animations, the toggles, the file actions, and the four tuned fields. Two rows
## and about 110px tall, because anything taller sits on top of the model. Each
## row is an HFlowContainer, so a narrow window wraps a row instead of pushing
## buttons off the edge -- which is the whole reason it will survive a phone.
func _build_controls(layer: CanvasLayer) -> void:
	var bar := PanelContainer.new()
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 16.0
	bar.offset_right = -(BROWSER_WIDTH + 32.0)
	bar.offset_bottom = -16.0
	# Height comes from the contents; this is which way it grows to get it.
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(bar)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	bar.add_child(_padded(column, 8))

	column.add_child(_build_action_row())
	_tuning_row = _build_tuning_row()
	column.add_child(_tuning_row)


func _build_action_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)

	# The widths below are floors, not sizes -- a Button grows to fit its own
	# text, so these only stop the short labels from being narrower than a
	# fingertip. Keeping them tight is what holds this row to one line.
	row.add_child(_make_button("idle", _play.bind(PokemonAnimator.Anim.IDLE), 64))
	row.add_child(_make_button("run", _play.bind(PokemonAnimator.Anim.RUN), 64))
	row.add_child(_make_button("attack", _play.bind(PokemonAnimator.Anim.ATTACK), 64))
	row.add_child(_make_button("hit", _play.bind(PokemonAnimator.Anim.HIT), 64))
	row.add_child(_make_button("spin", _play.bind(PokemonAnimator.Anim.SPIN), 64))

	row.add_child(VSeparator.new())

	row.add_child(_make_toggle("grid", _grid, _set_grid, 64))
	row.add_child(_make_toggle("shiny", _shiny, _set_shiny, 64))
	_info_button = _make_toggle("info", false, _set_info_visible, 64)
	row.add_child(_info_button)

	row.add_child(VSeparator.new())

	row.add_child(_make_button("revert", _revert_focused, 64))
	row.add_child(_make_button("revert all", _revert_all, 64))
	row.add_child(_make_button("save", _save_edits, 64))
	row.add_child(_make_button("menu", _leave, 64))

	row.add_child(VSeparator.new())

	row.add_child(_make_toggle("tuning", true, _set_tuning_visible, 64))
	return row


## Six buttons sharing the width of the browser, directly above the list they
## move through. No name label: the readout says which species this is, and the
## list highlights it -- a third copy would just be a third thing to keep in sync.
func _build_nav_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var buttons: Array[Button] = [
		_make_button("|«", _jump_to.bind(0)),
		_make_button("«%d" % PAGE_STRIDE, _step_species.bind(-PAGE_STRIDE)),
		_make_step_button("−", _step_species.bind(-1), HOLD_RATE_HEAVY),
		_make_step_button("+", _step_species.bind(1), HOLD_RATE_HEAVY),
		_make_button("%d»" % PAGE_STRIDE, _step_species.bind(PAGE_STRIDE)),
		_make_button("»|", _jump_last),
	]
	for button in buttons:
		# Share the panel width evenly, which makes them wider than the 44 they
		# ask for rather than narrower.
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	return row


func _build_tuning_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 6)

	row.add_child(_make_stepper("body_type", "body", 116,
		_cycle_body_type.bind(-1), _cycle_body_type.bind(1), HOLD_RATE_HEAVY))
	row.add_child(_make_stepper("anim_speed_scale", "speed", 60,
		_nudge.bind("anim_speed_scale", -1, SPEED_STEP, 0.25, 3.0),
		_nudge.bind("anim_speed_scale", 1, SPEED_STEP, 0.25, 3.0)))
	row.add_child(_make_stepper("anim_amplitude", "amplitude", 60,
		_nudge.bind("anim_amplitude", -1, AMPLITUDE_STEP, 0.0, 3.0),
		_nudge.bind("anim_amplitude", 1, AMPLITUDE_STEP, 0.0, 3.0)))
	row.add_child(_make_stepper("hover_height", "hover", 60,
		_nudge.bind("hover_height", -1, HOVER_STEP, 0.0, 2.0),
		_nudge.bind("hover_height", 1, HOVER_STEP, 0.0, 2.0)))

	row.add_child(_make_toggle("x%d steps" % int(COARSE_STEP), _coarse, _set_coarse, 96))
	return row


## The level box and its pair, sized to the browser rather than the bar. The ADD
## button is a row of its own below the list, so it gets the full width.
func _build_level_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	row.add_child(_caption("level", 52))
	row.add_child(_make_step_button("−", _step_level.bind(-1)))

	_level_edit = LineEdit.new()
	_level_edit.text = str(LEVEL_DEFAULT)
	_level_edit.max_length = 3
	_level_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_edit.custom_minimum_size = Vector2(60, TOUCH_SIZE)
	_level_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Asks the on-screen keyboard for digits, on the platforms that have one.
	_level_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_level_edit.text_changed.connect(_on_level_text_changed)
	_level_edit.text_submitted.connect(_on_level_submitted)
	_level_edit.focus_exited.connect(_commit_level)
	row.add_child(_level_edit)

	row.add_child(_make_step_button("+", _step_level.bind(1)))
	return row


# ------------------------------------------------------------ hud: the list

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
## own thing: the tuning buttons get pressed a lot, and relabelling 400 rows on
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


# --------------------------------------------------------- hud: the readout

func _show_message(text: String) -> void:
	if _message == null:
		return
	_message.text = text
	_message_seconds = MESSAGE_SECONDS


func _refresh_readout() -> void:
	if _readout == null:
		return

	var data := _focused_data()
	if _readout_icon != null:
		var icon: Texture2D = null
		if data != null:
			icon = data.icon
		_readout_icon.texture = icon
		# Hidden rather than left blank, so the text is not indented past an
		# empty square on a species that has no icon yet.
		_readout_icon.visible = icon != null

	if data == null:
		_readout.text = "no match" if not _all_ids.is_empty() else "no species loaded"
		return

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
		lines.append("unsaved     %d species  (SAVE)" % _pending.size())
	_readout.text = "\n".join(lines)


## "  (was 1.00)" for a field edited this session, "" for one still at its
## on-disk value -- so you can always see how far you have moved it, and back.
func _was(data: PokemonBaseData, baseline: Dictionary, field: String) -> String:
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


## Puts the current values into the labels sitting between the - and + pairs.
func _refresh_controls() -> void:
	var data := _focused_data()
	for field: String in _value_labels:
		var label: Label = _value_labels[field]
		if data == null:
			label.text = "--"
		elif field == "body_type":
			label.text = _body_name(data.body_type)
		else:
			label.text = "%.2f" % float(data.get(field))


# ----------------------------------------------------------- hud: info panel

## The read-only half of a species: what it is, rather than how it moves. Floats
## over the middle of the view, clear of the readout and the browser both.
func _build_info_panel(layer: CanvasLayer) -> void:
	_info_panel = PanelContainer.new()
	_info_panel.anchor_left = 0.5
	_info_panel.anchor_right = 0.5
	_info_panel.anchor_top = 0.5
	_info_panel.anchor_bottom = 0.5
	# Anchored to the centre of the whole viewport, then shoved left by half the
	# browser so it sits in the middle of what is actually free.
	_info_panel.offset_left = -(BROWSER_WIDTH + 32.0) * 0.5
	_info_panel.offset_right = -(BROWSER_WIDTH + 32.0) * 0.5
	_info_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_info_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_info_panel.custom_minimum_size = Vector2(INFO_WIDTH, 0)
	_info_panel.visible = false
	layer.add_child(_info_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_info_panel.add_child(_padded(column, 16))

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)

	_info_icon = _texture_rect(null, INFO_TITLE_ICON_SIZE)
	header.add_child(_info_icon)

	_info_title = Label.new()
	_info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_title.add_theme_font_size_override("font_size", 20)
	header.add_child(_info_title)
	header.add_child(_make_button("close", _close_info, 80))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, INFO_BODY_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_info_body = VBoxContainer.new()
	_info_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_body.add_theme_constant_override("separation", 14)
	scroll.add_child(_info_body)


func _set_info_visible(on: bool) -> void:
	if _info_panel == null:
		return
	_info_panel.visible = on
	if on and _info_dirty:
		_rebuild_info_panel()


func _close_info() -> void:
	if _info_button != null:
		# Flipping the toggle back is what actually hides the panel; doing it
		# without the signal would leave the button lit next to a shut panel.
		_info_button.button_pressed = false
	else:
		_set_info_visible(false)


## Species changed. Rebuilding a shut panel would be work for nobody, so it waits
## until the panel is next opened.
func _mark_info_dirty() -> void:
	_info_dirty = true
	if _info_panel != null and _info_panel.visible:
		_rebuild_info_panel()


func _rebuild_info_panel() -> void:
	if _info_body == null:
		return
	_info_dirty = false

	for child in _info_body.get_children():
		_info_body.remove_child(child)
		child.queue_free()

	var data := _focused_data()
	if data == null:
		_info_title.text = "no species"
		if _info_icon != null:
			_info_icon.visible = false
		_info_body.add_child(_caption("nothing selected"))
		return

	_info_title.text = "#%04d  %s" % [data.dex_number, data.display_name]
	if _info_icon != null:
		_info_icon.texture = data.icon
		_info_icon.visible = data.has_icon()

	_info_body.add_child(_section("preview"))
	_info_body.add_child(_preview_block(data))

	_info_body.add_child(_section("type"))
	_info_body.add_child(_type_row(data))

	_info_body.add_child(_section("traits"))
	_info_body.add_child(_trait_block(data))

	_info_body.add_child(_section("base stats"))
	_info_body.add_child(_stat_block(data))

	_info_body.add_child(_section("quest stats"))
	_info_body.add_child(_quest_block(data))

	_info_body.add_child(_section("learnable moves  (%d)" % data.learnable_moves.size()))
	_info_body.add_child(_move_block(data))


func _section(title: String) -> Label:
	var label := Label.new()
	label.text = title.to_upper()
	label.add_theme_color_override("font_color", TEXT_STATUS)
	return label


## A texture at a fixed square size, never stretched out of shape and never
## dragging its own resolution into the layout.
func _texture_rect(texture: Texture2D, size: float) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.custom_minimum_size = Vector2(size, size)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return art


## A rounded, type-coloured badge. Used for both the typing and the moves, so a
## move's colour and its type's colour are the same colour.
func _chip(text: String, color: Color, icon: Texture2D = null,
		icon_size := CHIP_ICON_SIZE) -> PanelContainer:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.r, color.g, color.b, 0.28)
	box.border_color = color
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(6)

	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", box)
	chip.tooltip_text = text
	chip.mouse_filter = Control.MOUSE_FILTER_STOP

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)

	if icon != null:
		row.add_child(_texture_rect(icon, icon_size))

	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return chip


## Both previews side by side when the species has a shiny one, so the pair can
## be compared without toggling anything. The shiny toggle respawns the model,
## which rebuilds this panel anyway, but neither tile depends on it.
func _preview_block(data: PokemonBaseData) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var normal := data.get_preview(false)
	if normal == null:
		row.add_child(_caption("no preview on this species"))
		return row

	if not data.has_shiny_preview():
		row.add_child(_preview_tile("", normal))
		return row

	row.add_child(_preview_tile("normal", normal))
	row.add_child(_preview_tile("shiny", data.get_preview(true)))
	return row


func _preview_tile(title: String, texture: Texture2D) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.add_child(_texture_rect(texture, PREVIEW_SIZE))
	if title.is_empty():
		return column

	var caption := Label.new()
	caption.text = title
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", TEXT_DIM)
	column.add_child(caption)
	return column


func _type_row(data: PokemonBaseData) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)

	var types := data.types()
	if types.is_empty():
		row.add_child(_caption("no type set"))
		return row

	for type in types:
		row.add_child(_chip(_type_name(type), _type_color(type), _type_icon(type)))
	return row


## The things that are neither typing nor a number: how it moves, how it fights,
## and what it turns into.
func _trait_block(data: PokemonBaseData) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)

	var styles: Array = PokemonBaseData.AttackStyle.keys()
	var style: String = styles[data.attack_style] if data.attack_style < styles.size() else "?"
	column.add_child(_pair("body type", _body_name(data.body_type)))
	column.add_child(_pair("attack style", style))
	column.add_child(_pair("model scale", "%.2f" % data.model_scale))

	var evolutions := PackedStringArray()
	for next in data.evolves_into:
		if next != null:
			evolutions.append(next.display_name)
	column.add_child(_pair("evolves into",
		", ".join(evolutions) if not evolutions.is_empty() else "-"))

	if data.can_mega_evolve():
		column.add_child(_pair("mega", data.mega_evolves_into.display_name))
	return column


func _pair(title: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var caption := Label.new()
	caption.text = title
	caption.custom_minimum_size = Vector2(120, 0)
	caption.add_theme_color_override("font_color", TEXT_DIM)
	row.add_child(caption)

	var label := Label.new()
	label.text = value
	row.add_child(label)
	return row


func _stat_block(data: PokemonBaseData) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)

	var color := _type_color(data.type1)
	var rows := [
		["hp", data.base_hp],
		["attack", data.base_attack],
		["defense", data.base_defense],
		["sp. attack", data.base_special_attack],
		["sp. defense", data.base_special_defense],
		["speed", data.base_speed],
	]
	var total := 0
	for row: Array in rows:
		column.add_child(_stat_row(str(row[0]), int(row[1]), color))
		total += int(row[1])
	column.add_child(_pair("total", str(total)))
	return column


func _quest_block(data: PokemonBaseData) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)

	var color := _type_color(data.type2 if data.has_second_type() else data.type1)
	if data.quest_base_hp == 0 and data.quest_base_attack == 0 and data.quest_base_speed == 0:
		column.add_child(_caption("not filled in for this species"))
		return column

	column.add_child(_stat_row("hp", data.quest_base_hp, color))
	column.add_child(_stat_row("attack", data.quest_base_attack, color))
	column.add_child(_stat_row("speed", data.quest_base_speed, color))
	return column


## Name, number, and a bar against a fixed maximum so two species can be compared
## by eye without reading either number.
func _stat_row(title: String, value: int, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var caption := Label.new()
	caption.text = title
	caption.custom_minimum_size = Vector2(120, 0)
	caption.add_theme_color_override("font_color", TEXT_DIM)
	row.add_child(caption)

	var number := Label.new()
	number.text = str(value)
	number.custom_minimum_size = Vector2(44, 0)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(number)

	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)

	var bar := ProgressBar.new()
	bar.max_value = STAT_BAR_MAX
	bar.value = clampf(float(value), 0.0, STAT_BAR_MAX)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	return row


func _move_block(data: PokemonBaseData) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)

	var drawn := 0
	for entry in data.learnable_moves:
		var move := entry as Resource
		if move == null:
			continue
		row.add_child(_chip(_move_name(move), _type_color(_move_type(move)),
			_move_icon(move)))
		drawn += 1

	if drawn == 0:
		row.add_child(_caption("none listed on this species"))
	return row


## The first of [constant MOVE_NAME_FIELDS] the move actually has, falling back to
## the resource name and then the filename, so a chip always says something.
func _move_name(move: Resource) -> String:
	for field: String in MOVE_NAME_FIELDS:
		if field in move:
			var value: Variant = move.get(field)
			if value is String and not (value as String).is_empty():
				return value as String
	if not move.resource_name.is_empty():
		return move.resource_name
	if not move.resource_path.is_empty():
		return move.resource_path.get_file().get_basename()
	return "move"


func _move_icon(move: Resource) -> Texture2D:
	for field: String in MOVE_ICON_FIELDS:
		if field in move:
			var value: Variant = move.get(field)
			if value is Texture2D:
				return value as Texture2D
	return null


## Assumed to be a [enum PokemonBaseData.Type] when it is an int. A move whose
## type field means something else only costs a wrong chip colour.
func _move_type(move: Resource) -> int:
	for field: String in MOVE_TYPE_FIELDS:
		if field in move:
			var value: Variant = move.get(field)
			if value is int:
				return int(value)
	return PokemonBaseData.Type.NONE

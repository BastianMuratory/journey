extends Node3D

## Admin menu: let's put everything we need for debugging here

const GRID_COUNT := 3 ## to view a full evolution familly 
const GRID_SPACING := 1.6

const POKEMON_SCENE_PATH = "uid://6r1xtnwsp0sa"
const POKEMON_MODEL_SCENE := preload(POKEMON_SCENE_PATH)

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: AdminMenuUI = $AdminMenuUI

## Every id the registry knows, ascending.
var _all_dex_number = PackedInt32Array(PokemonRegistry.get_all_dex_numbers())
## The subset currently listed, after the search filter. Navigation indexes this.
var _visible_dex_numbers: PackedInt32Array = []
var _index := 0

## id -> {dex: int, name: String, body: int}.
##
## Read straight out of the .tres text rather than through the registry, because
## loading a PokemonBaseData pulls its mesh in with it -- and a 410-row list that
## loaded 410 models to draw itself would take seconds and hundreds of MB. The
## registry stays lazy; only the species actually on screen get loaded.
var _meta: Dictionary[int, Dictionary] = {}

var _shiny := false
var _grid := false

var _spawned: Array[PokemonModel] = []


func _ready() -> void:
	_connect_ui()

	if _all_dex_number.is_empty():
		push_error("AdminMenu: PokemonRegistry has no species. Nothing to show.")
		_ui.set_readout("no species loaded")
		return

	_visible_dex_numbers = _all_dex_number
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
	_ui.menu_requested.connect(SceneManager.go_back)
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
	var body_re := RegEx.create_from_string("(?m)^body_type\\s*=\\s*(\\d+)")
	var name_re := RegEx.create_from_string('(?m)^display_name\\s*=\\s*"([^"]*)"')

	for id in _all_dex_number:
		var path := PokemonRegistry.get_path_for(id)
		var entry := {"name": "Unknown", "body": -1}

		# Exported builds ship these as binary .res, which this cannot read.
		# The fallbacks above already give a usable row, so that is fine.
		if path.ends_with(".tres") and FileAccess.file_exists(path):
			var text := FileAccess.get_file_as_string(path)
			var body_match := body_re.search(text)
			if body_match != null:
				entry["body"] = body_match.get_string(1).to_int()
			var name_match := name_re.search(text)
			if name_match != null:
				entry["name"] = name_match.get_string(1)

		_meta[id] = entry


func _meta_of(id: int) -> Dictionary:
	return _meta.get(id, {"name": id, "body": -1})


## The species being edited, and the one every button on the bar applies to. In
## grid mode that is the leftmost one, so there is always exactly one.
func _focused_dex() -> int:
	return _visible_dex_numbers[_index] if not _visible_dex_numbers.is_empty() else -1


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

	if _visible_dex_numbers.is_empty():
		_refresh_panels()
		return

	var count := GRID_COUNT if _grid else 1
	count = mini(count, _visible_dex_numbers.size())

	# Instance first, measure second: widths are only known once the data is in.
	var widths: Array[float] = []
	for i in count:
		var id := _visible_dex_numbers[(_index + i) % _visible_dex_numbers.size()]
		var pokemon := _spawn(id)
		if pokemon == null:
			continue
		_spawned.append(pokemon)
		widths.append(_footprint(pokemon))

	_lay_out(widths)
	_frame_camera()
	_refresh_panels()
	_ui.select_row(_index)


func _spawn(id: int) -> PokemonModel:
	var data := PokemonRegistry.get_pokemon(id)
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
	if _visible_dex_numbers.is_empty():
		return
	var stride := maxi(_spawned.size(), 1) if _grid else 1
	_jump_to(wrapi(_index + direction * stride, 0, _visible_dex_numbers.size()))


func _jump_to(index: int) -> void:
	if _visible_dex_numbers.is_empty():
		return
	_index = clampi(index, 0, _visible_dex_numbers.size() - 1)
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

# -------------------------------------------------------------- collection

## The one place that has to know a collection exists.
##
## Everything above is already done by the time this runs: there is a focused
## species and [param level] is a number the screen has clamped into range.
## Replace the message with the real call -- something like
## [code]PlayerCollection.add(id, level)[/code] -- or leave it and listen for
## [signal add_to_collection] from wherever the collection lives.
func _add_to_collection(level: int) -> void:
	var dex_number := _focused_dex()
	if dex_number < 0:
		_ui.show_message("no species selected")
		return
	SignalBus.add_to_collection.emit(PokemonInstance.generate(dex_number, level, _shiny))

# ----------------------------------------------------------------- searching

func _on_search_changed(text: String) -> void:
	var needle := text.strip_edges().to_lower()
	var keep := _focused_dex()

	if needle.is_empty():
		_visible_dex_numbers = _all_dex_number
	else:
		var matches := PackedInt32Array()
		for id in _all_dex_number:
			# The id carries the dex number and the slug, so "0092", "gastly"
			# and "alolan" all work. Names come from the metadata scan, so this
			# still loads nothing.
			var name_text: String = _meta_of(id)["name"]
			if needle in ("%04d" % id) or needle in name_text.to_lower():
				matches.append(id)
		_visible_dex_numbers = matches

	_rebuild_list()
	if _visible_dex_numbers.is_empty():
		_respawn()
		return

	# Stay on the same species if it survived the filter.
	var found := _visible_dex_numbers.find(keep)
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

func _list_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for id in _visible_dex_numbers:
		labels.append(_list_label(id))
	return labels

func _list_label(id: int) -> String:
	var entry := _meta_of(id)
	return "#%04d  %-20s %s" % [id, entry["name"], AdminMenuUI.body_name(entry["body"])]

## What you are looking at and how far each field has been moved. Written here
## rather than on the screen because every number in it -- the baselines, the
## unsaved count, how many models are up -- lives on this side.
func _readout_text() -> String:
	var data := _focused_data()
	if data == null:
		return "no match" if not _all_dex_number.is_empty() else "no species loaded"

	var filtered := ""
	if _visible_dex_numbers.size() != _all_dex_number.size():
		filtered = "  (filtered from %d)" % _all_dex_number.size()

	var lines := [
		"#%d  %s" % [data.dex_number, data.display_name],
		"%d of %d%s" % [_index + 1, _visible_dex_numbers.size(), filtered],
		"body type   %s" % AdminMenuUI.body_name(data.body_type),
		"speed       %.2f" % data.anim_speed_scale,
		"amplitude   %.2f" % data.anim_amplitude,
		"hover       %.2f" % data.hover_height,
	]

	if _grid:
		lines.append("grid        %d species" % _spawned.size())
	return "\n".join(lines)

func _status_text() -> String:
	if _spawned.is_empty():
		return ""
	var animator := _spawned[0].animator
	var loop_name: String = PokemonAnimator.Anim.keys()[animator.loop]
	if animator.is_one_shot_playing:
		var shot: String = PokemonAnimator.Anim.keys()[animator.current_one_shot]
		return "playing  %s  over  %s" % [shot, loop_name]
	return "playing  %s" % loop_name

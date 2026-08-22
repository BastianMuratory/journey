class_name AdminMenuUI
extends CanvasLayer

## The admin menu's screen: every control, and nothing else.
##
## Split out of admin_menu.gd the same way [BaseCampUI] is split out of the
## base camp -- the sandbox owns the models, the camera and the species data,
## this owns the widgets. Nothing in here loads, edits or saves a species: a
## button emits a signal and the sandbox decides what that means.
##

## A play button. Which models it applies to is the sandbox's business.
signal anim_requested(anim: PokemonAnimator.Anim)
signal grid_toggled(on: bool)
signal shiny_toggled(on: bool)
signal search_changed(text: String)
signal species_index_requested(index: int)
signal species_step_requested(delta: int) # show the pokemon delta spaces after or before the current one 
## One tuned float moved. [param amount] already has the x5 multiplier in it;
## [param step] is the unmultiplied step, passed so the sandbox can snap the
## result to it, and [param low] and [param high] are the field's range.
signal nudge_requested(field: String, amount: float, step: float, low: float, high: float)
signal body_type_step_requested(step: int)
signal revert_requested
signal revert_all_requested
signal save_requested
signal menu_requested
## ADD TO COLLECTION, with the level box already clamped into range.
signal add_to_collection(level: int)

# ---------------------------------------------------------------- constants

# Used to tell how much an animation variable can changes afetr a button press
const NUDGE_FIELDS := {
	"anim_speed_scale": [0.05, 0.25, 3.0],
	"anim_amplitude": [0.05, 0.0, 3.0],
	"hover_height": [0.02, 0.0, 2.0],
}
## How far the «25 and 25» buttons move through the list. Their labels are in the
## scene, so change both or they will disagree.
const PAGE_STRIDE := 25

## How long a - or + has to be held before it starts repeating, and how often it
## repeats after that. The delay is what keeps a single deliberate tap single.
const HOLD_DELAY := 0.4
const HOLD_RATE := 0.06
## The rate for steps that respawn the model rather than move a number. Each one
## is a mesh coming off disk, and sixteen of those a second is a slideshow.
const HOLD_RATE_HEAVY := 0.18

## How long a status message stays on screen.
const MESSAGE_SECONDS := 4.0

const LEVEL_MIN := 1
const LEVEL_MAX := 100
const LEVEL_DEFAULT := 5

## Minimum side of anything meant to be tapped. The scene sizes its own buttons
## to it; what is left in code is the captions the info panel makes as it goes.
const TOUCH_SIZE := 44.0
## Side of a chip icon and of a preview tile in the info panel.
const CHIP_ICON_SIZE := 26.0
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

## The Move class is not this screen's to know, so its fields are looked for by
## name and quietly skipped when absent -- a move with no icon still gets a chip,
## and adding an icon later needs no change here. First match wins.
const MOVE_NAME_FIELDS := ["display_name", "move_name", "name", "id"]
const MOVE_ICON_FIELDS := ["icon", "texture", "sprite"]
const MOVE_TYPE_FIELDS := ["type", "move_type", "element"]

## Only the two the info panel paints as it builds itself. Everything else the
## screen is coloured with is set on the nodes in the scene.
const TEXT_DIM := Color(0.65, 0.65, 0.72)
const TEXT_STATUS := Color(0.55, 0.90, 1.00)

# ------------------------------------------------------------------- nodes

@onready var _readout: Label = %Readout
@onready var _readout_icon: TextureRect = %ReadoutIcon
@onready var _status: Label = %Status
@onready var _message: Label = %Message

@onready var _list: ItemList = %List
@onready var _search: LineEdit = %Search
@onready var _level_edit: LineEdit = %LevelEdit

## The second row of the bar, which the TUNING button folds away.
@onready var _tuning_row: HFlowContainer = %TuningRow
@onready var _info_button: Button = %InfoToggle

@onready var _info_panel: PanelContainer = %InfoPanel
@onready var _info_icon: TextureRect = %InfoIcon
@onready var _info_title: Label = %InfoTitle
@onready var _info_body: VBoxContainer = %InfoBody

# ------------------------------------------------------------------- state

## The species the readout, the tuning labels and the info panel are drawn from.
## Handed over by [method show_species]; never read from anywhere else.
var _focus: PokemonBaseData = null

## Set by the x5 button. Stands in for the Shift key the tuning keys used to
## read, and is applied here so the sandbox never has to know about it.
var _coarse := false

## The - or + currently held down, and the countdown to its next repeat. An
## invalid Callable means nothing is held, which is the state between presses.
var _held := Callable()
var _hold_seconds := 0.0
var _hold_rate := HOLD_RATE

var _message_seconds := 0.0

## The info panel's body is out of date. Set when the species changes under a
## shut panel, cleared when the panel is next rebuilt.
var _info_dirty := true

## Field name -> the label between that field's - and + buttons.
var _value_labels: Dictionary[String, Label] = {}

## Type -> its icon, or null when no file was found. Misses are cached too: a
## project with no type icons at all should not re-check the disk every rebuild.
var _type_icons: Dictionary[int, Texture2D] = {}


func _ready() -> void:
	_wire_bar()
	_wire_tuning()
	_wire_browser()
	_wire_info()


func _process(delta: float) -> void:
	if _message_seconds > 0.0:
		_message_seconds -= delta
		if _message_seconds <= 0.0:
			_message.text = ""

	if _held.is_valid():
		_hold_seconds -= delta
		if _hold_seconds <= 0.0:
			_hold_seconds = _hold_rate
			_held.call()


# -------------------------------------------------------------------- wiring

## A control in the scene, by unique name. Everything below goes through this
## rather than through a path, so the scene can be rearranged freely.
func _control(unique: String) -> Button:
	return get_node("%" + unique) as Button


## The - and + pairs, which fire once on press and then keep firing until the
## button comes back up. That is what makes a tap a tap and a hold a slide.
func _wire_hold(button: Button, action: Callable, rate := HOLD_RATE) -> void:
	button.button_down.connect(_begin_hold.bind(action, rate))
	button.button_up.connect(_end_hold)


func _wire_bar() -> void:
	_control("IdleButton").pressed.connect(_emit_anim.bind(PokemonAnimator.Anim.IDLE))
	_control("RunButton").pressed.connect(_emit_anim.bind(PokemonAnimator.Anim.RUN))
	_control("AttackButton").pressed.connect(_emit_anim.bind(PokemonAnimator.Anim.ATTACK))
	_control("HitButton").pressed.connect(_emit_anim.bind(PokemonAnimator.Anim.HIT))
	_control("SpinButton").pressed.connect(_emit_anim.bind(PokemonAnimator.Anim.SPIN))

	_control("GridToggle").toggled.connect(grid_toggled.emit)
	_control("ShinyToggle").toggled.connect(shiny_toggled.emit)
	_info_button.toggled.connect(_set_info_visible)

	_control("RevertButton").pressed.connect(revert_requested.emit)
	_control("RevertAllButton").pressed.connect(revert_all_requested.emit)
	_control("SaveButton").pressed.connect(save_requested.emit)
	_control("MenuButton").pressed.connect(menu_requested.emit)

	_control("TuningToggle").toggled.connect(_set_tuning_visible)


func _wire_tuning() -> void:
	_value_labels["body_type"] = %BodyValue as Label
	_value_labels["anim_speed_scale"] = %SpeedValue as Label
	_value_labels["anim_amplitude"] = %AmplitudeValue as Label
	_value_labels["hover_height"] = %HoverValue as Label

	# Body type respawns the model, so it repeats at the slower rate.
	_wire_hold(_control("BodyDown"), _emit_body_step.bind(-1), HOLD_RATE_HEAVY)
	_wire_hold(_control("BodyUp"), _emit_body_step.bind(1), HOLD_RATE_HEAVY)

	_wire_hold(_control("SpeedDown"), _emit_nudge.bind("anim_speed_scale", -1))
	_wire_hold(_control("SpeedUp"), _emit_nudge.bind("anim_speed_scale", 1))
	_wire_hold(_control("AmplitudeDown"), _emit_nudge.bind("anim_amplitude", -1))
	_wire_hold(_control("AmplitudeUp"), _emit_nudge.bind("anim_amplitude", 1))
	_wire_hold(_control("HoverDown"), _emit_nudge.bind("hover_height", -1))
	_wire_hold(_control("HoverUp"), _emit_nudge.bind("hover_height", 1))

	_control("CoarseToggle").toggled.connect(_set_coarse)


func _wire_browser() -> void:
	_search.text_changed.connect(search_changed.emit)
	_control("ClearButton").pressed.connect(_clear_search)

	_control("FirstButton").pressed.connect(_emit_index.bind(0))
	_control("PageBackButton").pressed.connect(_emit_step.bind(-PAGE_STRIDE))
	_control("PageForwardButton").pressed.connect(_emit_step.bind(PAGE_STRIDE))
	_control("LastButton").pressed.connect(_jump_last)
	# One species at a time is the pair worth holding down.
	_wire_hold(_control("StepBackButton"), _emit_step.bind(-1), HOLD_RATE_HEAVY)
	_wire_hold(_control("StepForwardButton"), _emit_step.bind(1), HOLD_RATE_HEAVY)

	_list.item_selected.connect(species_index_requested.emit)

	_wire_hold(_control("LevelDownButton"), _step_level.bind(-1))
	_wire_hold(_control("LevelUpButton"), _step_level.bind(1))
	_level_edit.text_changed.connect(_on_level_text_changed)
	_level_edit.text_submitted.connect(_on_level_submitted)
	_level_edit.focus_exited.connect(_commit_level)

	_control("AddButton").pressed.connect(_emit_add)


func _wire_info() -> void:
	_control("CloseButton").pressed.connect(_close_info)


# ------------------------------------------------------- the sandbox's side

## Fills the list from scratch. One label per visible species, already formatted
## -- what a row says is the sandbox's business, drawing it is this one's.
func set_rows(labels: PackedStringArray) -> void:
	_list.clear()
	for label in labels:
		_list.add_item(label)


## Relabels every row without rebuilding it. Cheaper than [method set_rows], and
## what a save or a revert-all wants.
func set_row_labels(labels: PackedStringArray) -> void:
	for i in mini(labels.size(), _list.item_count):
		_list.set_item_text(i, labels[i])


## Relabels one row, which is all a single edit can affect. Worth having: the
## tuning buttons get pressed a lot, and relabelling 400 rows on every nudge is
## work nobody asked for.
func set_row_label(row: int, label: String) -> void:
	if row < 0 or row >= _list.item_count:
		return
	_list.set_item_text(row, label)


func select_row(row: int) -> void:
	if row < 0 or row >= _list.item_count:
		return
	_list.select(row)
	_list.ensure_current_is_visible()


## The species every panel is now about, or null when the filter matched nothing.
## Sets the readout icon and the tuning labels; the info panel waits for
## [method mark_info_dirty], so a run of nudges does not rebuild it forty times.
func show_species(data: PokemonBaseData) -> void:
	_focus = data

	var icon: Texture2D = data.icon if data != null else null
	_readout_icon.texture = icon
	# Hidden rather than left blank, so the text is not indented past an empty
	# square on a species that has no icon yet.
	_readout_icon.visible = icon != null

	for field: String in _value_labels:
		var label: Label = _value_labels[field]
		if data == null:
			label.text = "--"
		elif field == "body_type":
			label.text = body_name(data.body_type)
		else:
			label.text = "%.2f" % float(data.get(field))


## Top left, under the icon: what you are looking at and how far each field has
## been moved. The sandbox writes the lines, since it is the one holding the
## baselines they are compared against.
func set_readout(text: String) -> void:
	_readout.text = text


## The line under the readout. Polled every frame by the sandbox, because the
## one-shot animation ends on its own with nothing to emit a signal.
func set_status(text: String) -> void:
	_status.text = text


## A line of feedback that fades after [constant MESSAGE_SECONDS].
func show_message(text: String) -> void:
	_message.text = text
	_message_seconds = MESSAGE_SECONDS


## The focused species changed. Rebuilding a shut panel would be work for nobody,
## so it waits until the panel is next opened.
func mark_info_dirty() -> void:
	_info_dirty = true
	if _info_panel.visible:
		_rebuild_info_panel()


## The level box, clamped into range and written back, so what the box shows is
## always what a press would use.
func level() -> int:
	return _commit_level()


# --------------------------------------------------------- what buttons do

## Every button that only has to tell the sandbox something ends up here, so the
## wiring above stays a list of names rather than a list of lambdas.

func _emit_anim(anim: PokemonAnimator.Anim) -> void:
	anim_requested.emit(anim)


func _emit_index(index: int) -> void:
	species_index_requested.emit(index)


func _emit_step(delta: int) -> void:
	species_step_requested.emit(delta)


func _jump_last() -> void:
	if _list.item_count > 0:
		species_index_requested.emit(_list.item_count - 1)


## The step, the range and the x5 multiplier are all applied here rather than at
## the far end, so the coarse toggle stays a fact about this screen and the
## buttons in the scene carry nothing but a field name and a direction.
func _emit_nudge(field: String, direction: int) -> void:
	var spec: Array = NUDGE_FIELDS[field]
	var step: float = spec[0]
	var amount := step * direction * 5 # multiply by 5 so it goes faster
	nudge_requested.emit(field, amount, step, float(spec[1]), float(spec[2]))


func _emit_body_step(step: int) -> void:
	body_type_step_requested.emit(step)


func _emit_add() -> void:
	add_to_collection.emit(_commit_level())


## Fires once immediately, then again on a timer until the button comes back up.
func _begin_hold(action: Callable, rate := HOLD_RATE) -> void:
	action.call()
	_held = action
	_hold_rate = rate
	_hold_seconds = HOLD_DELAY


func _end_hold() -> void:
	_held = Callable()


func _set_coarse(on: bool) -> void:
	_coarse = on


## Folds the tuning row away. The bar is two rows already; this is for when even
## the second one is between you and the model.
func _set_tuning_visible(on: bool) -> void:
	_tuning_row.visible = on


func _clear_search() -> void:
	if _search.text.is_empty():
		return
	_search.text = ""
	# Assigning to text does not emit text_changed, so the filter is re-run here.
	search_changed.emit("")


# -------------------------------------------------------------- the level box

## Reads the level box, clamps it into range and writes the clamped value back.
func _commit_level() -> int:
	var value := clampi(_level_edit.text.to_int(), LEVEL_MIN, LEVEL_MAX)
	_level_edit.text = str(value)
	return value


func _step_level(direction: int) -> void:
	var value := clampi(_commit_level() + direction * 5, LEVEL_MIN, LEVEL_MAX)
	_level_edit.text = str(value)


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


# ----------------------------------------------------------- the info panel

## The panel itself is in the scene; what is below its header is not, because
## every line of that comes off a species, and it is rebuilt only while the
## panel is open.
func _set_info_visible(on: bool) -> void:
	_info_panel.visible = on
	if on and _info_dirty:
		_rebuild_info_panel()


func _close_info() -> void:
	# Flipping the toggle back is what actually hides the panel; doing it without
	# the signal would leave the button lit next to a shut panel.
	_info_button.button_pressed = false


func _rebuild_info_panel() -> void:
	_info_dirty = false

	for child in _info_body.get_children():
		_info_body.remove_child(child)
		child.queue_free()

	if _focus == null:
		_info_title.text = "no species"
		_info_icon.visible = false
		_info_body.add_child(_caption("nothing selected"))
		return

	var data := _focus
	_info_title.text = "#%04d  %s" % [data.dex_number, data.display_name]
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


func _caption(text: String, width := 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, TOUCH_SIZE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", TEXT_DIM)
	return label


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
		row.add_child(_chip(type_name(type), type_color(type), _type_icon(type)))
	return row


## The things that are neither typing nor a number: how it moves, how it fights,
## and what it turns into.
func _trait_block(data: PokemonBaseData) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)

	var styles: Array = PokemonBaseData.AttackStyle.keys()
	var style: String = styles[data.attack_style] if data.attack_style < styles.size() else "?"
	column.add_child(_pair("body type", body_name(data.body_type)))
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

	var color := type_color(data.type1)
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

	var color := type_color(data.type2 if data.has_second_type() else data.type1)
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
		row.add_child(_chip(_move_name(move), type_color(_move_type(move)),
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


# ------------------------------------------------------------------- naming

## Static, because the sandbox needs the same names for its list rows and its
## readout, and one spelling of them beats two.

static func body_name(body: int) -> String:
	var names: Array = PokemonBaseData.BodyType.keys()
	return names[body] if body >= 0 and body < names.size() else "?"


static func type_name(type: int) -> String:
	var names: Array = PokemonBaseData.Type.keys()
	return names[type] if type >= 0 and type < names.size() else "?"


static func type_color(type: int) -> Color:
	if type >= 0 and type < TYPE_COLORS.size():
		return TYPE_COLORS[type]
	return TYPE_COLORS[0]


## This type's icon, or null if the project has none where it was looked for.
## Null is cached alongside the hits, so a miss costs one sweep of the candidate
## paths per type per session and nothing after that.
func _type_icon(type: int) -> Texture2D:
	if _type_icons.has(type):
		return _type_icons[type] as Texture2D

	var slug := type_name(type).to_lower()
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

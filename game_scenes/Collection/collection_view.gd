extends Control


const POKEMON_MODEL_SCENE := preload("uid://6r1xtnwsp0sa")
enum SortMode { LEVEL, DEX, NAME }
# dots for the box display
const DOT_ON  := preload("uid://dy5gcjqnt0x6y")
const DOT_OFF := preload("uid://dhruc58idforv")
const DOT_SIZE := Vector2(12, 12)

# box
@onready var _grid: GridContainer = %BoxGrid
@onready var _box_dots: HBoxContainer = %BoxDots
@onready var _previous_box_button: Button = %PreviousBoxButton
@onready var _next_box_button: Button = %NextBoxButton
@onready var _sort_button: Button = %SortButton
@onready var _back_button: Button = %BackButton
@onready var _collection_count: Label = %CollectionCount
@onready var _collection_capacity: Label = %CollectionCapacity

# pokemon detail
@onready var _detail_icon: TextureRect = %DetailIcon
@onready var _detail_name: Label = %DetailName
@onready var _detail_type1: TextureRect = %DetailType1
@onready var _detail_type2: TextureRect = %DetailType2
@onready var _detail_level: Label = %DetailLevel
@onready var _detail_hp: Label = %DetailHp
@onready var _detail_attack: Label = %DetailAttack

# current team
@onready var _team_slot1: Button = %TeamSlot1
@onready var _team_slot2: Button = %TeamSlot2
@onready var _team_slot3: Button = %TeamSlot3

@onready var _team_slot_icon1: TextureRect = %TeamSlotIcon1
@onready var _team_slot_icon2: TextureRect = %TeamSlotIcon2
@onready var _team_slot_icon3: TextureRect = %TeamSlotIcon3

@onready var _team_slot_level1: Label = %TeamSlotLevel1
@onready var _team_slot_level2: Label = %TeamSlotLevel2
@onready var _team_slot_level3: Label = %TeamSlotLevel3

## Where the preview models are parked, one per team slot. They live inside
## %TeamViewport, so their positions are in that viewport's own 3D space.
@onready var _team_marker1: Marker3D = %TeamMarker1
@onready var _team_marker2: Marker3D = %TeamMarker2
@onready var _team_marker3: Marker3D = %TeamMarker3

@onready var _team_viewport: SubViewport = %TeamViewport

var _team_slots: Array[Button] = []
var _team_slot_icons: Array[TextureRect] = []
var _team_slot_levels: Array[Label] = []
var _team_markers: Array[Marker3D] = []
var _entries: Array[CollectionEntry] = []
var _team_models: Array[PokemonModel] = []

var _uids: Array[int] = []
var _selected_uid: int = -1
var _box_size : int = 0
var _box_count : int = 0
var _page: int = 0

var _sort_mode: SortMode = SortMode.LEVEL


func _ready() -> void:
	# prepare the team preview
	_team_slots = [_team_slot1, _team_slot2, _team_slot3]
	_team_slot_icons = [_team_slot_icon1, _team_slot_icon2, _team_slot_icon3]
	_team_slot_levels = [_team_slot_level1, _team_slot_level2, _team_slot_level3]
	_team_markers = [_team_marker1, _team_marker2, _team_marker3]
	
	# buttons connections 
	_previous_box_button.pressed.connect(_previous_page)
	_next_box_button.pressed.connect(_next_page)
	_team_slot1.pressed.connect(_set_first_team_member)
	_team_slot2.pressed.connect(_set_second_team_member)
	_team_slot3.pressed.connect(_set_third_team_member)
	_back_button.pressed.connect(_go_back)
	_sort_button.pressed.connect(_sort_button_pressed)
	SignalBus.team_changed.connect(_update_team_display)
	SignalBus.collection_changed.connect(_on_collection_changed)

	# prepare the grid
	_entries.assign(_grid.get_children())
	for entry in _entries:
		entry.pressed_entry.connect(_pressed_entry)

	# prepare the boxes
	_box_size = maxi(1, _entries.size())
	_box_count = ceili(float(GlobalConstants.COLLECTION_CAPACITY) / _box_size)
	_collection_count.text = str(PokemonPlayer.collection.size())
	_collection_capacity.text = str(GlobalConstants.COLLECTION_CAPACITY)

	_rebuild_uids()
	_build_dots()
	_show_box(0)
	_update_team_display()

func _rebuild_uids() -> void:
	_uids = PokemonPlayer.collection.sorted_uids()

func _on_collection_changed() -> void:
	_rebuild_uids()
	_collection_count.text = str(PokemonPlayer.collection.size())
	_show_box(0)
	_update_team_display()

func _sort_button_pressed() -> void:
	SignalBus.team_changed.emit()

func _pressed_entry(uid : int) -> void:
	_selected_uid = uid
	_update_top_info(_selected_uid)

func _update_top_info(uid : int) -> void:
	var instance = PokemonPlayer.collection.get_pokemon(uid)
	var dex_number = instance.dex_number
	_detail_icon.texture = PokemonRegistry.get_icon(dex_number)
	_detail_name.text = instance.display_name
	# TODO _detail_type1.texture = 
	_detail_level.text = str(instance.level)
	_detail_hp.text = str(instance.actual_max_hp())
	_detail_attack.text = str(instance.actual_attack())
	
	return

func _update_team_display() -> void:
	for iter in range(GlobalConstants.TEAM_SIZE):
		var iter_uid : int = PokemonPlayer.team.pokemons[iter]
		if iter_uid != -1:
			var pokemon_dex_number = PokemonPlayer.collection.get_pokemon(iter_uid)
			_team_slot_icons[iter].show()
			_team_slot_levels[iter].show()
			_team_slot_icons[iter].texture = PokemonPlayer.collection.get_pokemon(iter_uid).base_data.icon
			_team_slot_levels[iter].text = str(PokemonPlayer.collection.get_pokemon(iter_uid).level)
			# spawn the pokemon on the marker 
			# _team_markers[iter].
		else:
			_team_slot_icons[iter].hide()
			_team_slot_levels[iter].hide()
		
		# Now the models
		for model in _team_models:
			_team_viewport.remove_child(model)
			model.queue_free()
		_team_models.clear()

		for slot in range(GlobalConstants.TEAM_SIZE):
			var uid: int = PokemonPlayer.team.pokemons[slot]
			if uid != -1:
				var instance: PokemonInstance = PokemonPlayer.collection.get_pokemon(uid)
				if instance == null or instance.base_data == null:
					continue

				var model: PokemonModel = POKEMON_MODEL_SCENE.instantiate()
				model.data = instance.base_data
				model.shiny = instance.shiny
				_team_viewport.add_child(model)
				# Position and rotation separately -- assigning the whole transform would
				# clobber the scale that model_scale just applied.
				model.position = _team_markers[slot].position
				model.rotation = _team_markers[slot].rotation
				_team_models.append(model)


func _show_box(box_number : int) -> void:
	_page = clampi(box_number, 0, _box_count - 1)
	var index := _page * _box_size
	for entry in _entries:
		if index < _uids.size():
			entry.bind(_uids[index])
		else:
			entry.clear()
		index += 1
	_update_dots()
	_previous_box_button.disabled = _page == 0
	_next_box_button.disabled = _page == _box_count - 1

func _previous_page() -> void: _show_box(_page - 1)
func _next_page() -> void:     _show_box(_page + 1)

func _go_back() -> void:
	SceneManager.go_back()

func _set_first_team_member() -> void:
	PokemonPlayer.team.set_slot(PokemonPlayer.team.TEAM.FIRST, _selected_uid)

func _set_second_team_member() -> void:
	PokemonPlayer.team.set_slot(PokemonPlayer.team.TEAM.SECOND, _selected_uid)

func _set_third_team_member() -> void:
	PokemonPlayer.team.set_slot(PokemonPlayer.team.TEAM.THIRD, _selected_uid)

func _build_dots() -> void:
	for child in _box_dots.get_children():
		child.queue_free()
	for i in _box_count:
		var dot := Panel.new()
		dot.custom_minimum_size = DOT_SIZE
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_box_dots.add_child(dot)

func _update_dots() -> void:
	for i in _box_dots.get_child_count():
		_box_dots.get_child(i).add_theme_stylebox_override(
			"panel", DOT_ON if i == _page else DOT_OFF)

extends Control

@onready var _grid: GridContainer = %PokedexGrid
@onready var _displayNumber: Label = %PokemonNumber
@onready var _displayIcon: TextureRect = %PokemonIcon
@onready var _displayPreview: TextureRect = %PokemonPreview
@onready var _displayName: Label = %PokemonName
@onready var _back_button: Button = %BackButton
@onready var _left_button: Button = %LeftButton
@onready var _right_button: Button = %RightButton
@onready var _displayed_current_page: Label = %CurrentPage

# progression 
@onready var _number_seen: Label = %PokemonSeen
@onready var _number_total: Label = %PokemonTotal

var _unknown_icon = load("uid://b8o5cgof5njom")
var _error_icon = load("uid://b8o5cgof5njom")
var _current_page = 0

const _pokedex_entry_scene = "uid://cvp2uti2xrarv"
const _pokemon_entry = preload(_pokedex_entry_scene) # pokedex_entry_scene
const _MAX_PAGE = 24
const _MIN_PAGE = 0

func _show_page(pageNumber : int) -> void:
	_displayed_current_page.text = str(pageNumber+1)
	var index_array = []
	var startIndex = pageNumber * 15
	
	for i in range(15):
		if startIndex + i < PokemonRegistry.get_all_dex_numbers().size():
			print(startIndex + i)
			print( PokemonRegistry.get_all_dex_numbers().size() -1)
			index_array.push_back(PokemonRegistry.get_all_dex_numbers()[startIndex + i])
	
	var id = 0
	for entry : PokedexEntry in _grid.get_children():
		if id < index_array.size() :
			entry.bind(index_array[id], Pokedex.is_seen(index_array[id]))
		else:
			entry.hide()
		
		id +=1
		


func _display_left(pokemon_index : int) -> void:
	_displayNumber.text = str(pokemon_index)
	var data : PokemonBaseData = PokemonRegistry.get_pokemon(pokemon_index)
	_displayName.text = str(data.display_name)
	_displayIcon.texture = data.icon if data.has_icon() else _unknown_icon
	_displayPreview.texture = data.preview
	return

func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_left_button.pressed.connect(_on_left_pressed)
	_right_button.pressed.connect(_on_right_pressed)
	_number_seen.text = str(Pokedex.get_progress())
	_number_total.text = str(PokemonRegistry.get_all_dex_numbers().size())
	

	for entry_index in range(15):
		print(entry_index)
		var entry : PokedexEntry = _pokemon_entry.instantiate()
		entry.pressed_entry.connect(_entry_pressed)
		_grid.add_child(entry)

	_display_left(3)
	_show_page(_current_page)

func _entry_pressed(id : int):
	_display_left(id)

# go back to previous scene
func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_right_pressed() -> void:
	_current_page = min(_MAX_PAGE, _current_page + 1)
	_show_page(_current_page)

func _on_left_pressed() -> void:
	_current_page = max(_MIN_PAGE, _current_page - 1)
	_show_page(_current_page)

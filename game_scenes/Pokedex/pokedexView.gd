extends Control

@onready var _grid: GridContainer = %PokedexGrid
@onready var _displayNumber: Label = %PokemonNumber
@onready var _displayIcon: TextureRect = %PokemonIcon
@onready var _displayPreview: TextureRect = %PokemonPreview
@onready var _displayName: Label = %PokemonName
@onready var _back_button: Button = %BackButton

var _unknown_icon = load("uid://b8o5cgof5njom")
var _error_icon = load("uid://b8o5cgof5njom")
var _current_page = 0

const _pokedex_entry_scene = "uid://cvp2uti2xrarv"
const _pokemon_entry = preload(_pokedex_entry_scene) # pokedex_entry_scene

func _show_page(pageNumber : int) -> void:
	var index_array = []
	var startIndex = pageNumber * 15 + 1
	for i in range(15):
		index_array.push_back(startIndex + i)
	var id = 0
	for entry in _grid.get_children():
		entry.bind(index_array[id], Pokedex.is_seen(index_array[id]))
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

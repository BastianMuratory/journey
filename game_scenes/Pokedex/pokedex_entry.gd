extends Button
class_name PokedexEntry

@onready var _pokemon_number : Label = %PokemonNumber
@onready var _pokemon_icon : TextureRect = %PokemonIcon
@onready var _pokemon_name : Label = %PokemonName

signal pressed_entry(dex : int)

const _unknown_icon : String = "uid://b8o5cgof5njom"
const _error_icon : String = "uid://cs1inf50u1m5e"

var dex_number : int = 0

func bind(pokedex_number : int, seen : bool) -> void:
	visible = true
	dex_number = pokedex_number
	_pokemon_number.text = String.num(pokedex_number,0)
	if seen:
		var data : PokemonBaseData = PokemonRegistry.get_pokemon(pokedex_number)
		_pokemon_icon.texture = data.icon if data.has_icon() else preload(_unknown_icon)
		_pokemon_name.text = data.display_name
	else:
		_pokemon_icon.texture = preload(_unknown_icon)
		_pokemon_name.text = ""
	
	
func _ready() -> void:
	pressed.connect(_entry_pressed)

func _entry_pressed() -> void:
	pressed_entry.emit(dex_number)
	

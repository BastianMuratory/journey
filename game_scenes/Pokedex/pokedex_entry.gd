extends Button
class_name PokedexEntry

@onready var _pokemon_number : Label = %PokemonNumber
@onready var _pokemon_icon : TextureRect = %PokemonIcon
@onready var _pokemon_name : Label = %PokemonName

signal pressed_entry(dex : int)

var dex_number : int = 0

func bind(pokedex_number : int, seen : bool) -> void:
	visible = true
	dex_number = pokedex_number
	_pokemon_number.text = String.num(pokedex_number,0)
	if seen:
		var data : PokemonBaseData = PokemonRegistry.get_pokemon(pokedex_number)
		_pokemon_icon.texture = data.icon if data.has_icon() else preload(GlobalConstants.UNKNOW_POKEMON_ICON)
		_pokemon_name.text = data.display_name
	else:
		_pokemon_icon.texture = preload(GlobalConstants.UNKNOW_POKEMON_ICON)
		_pokemon_name.text = ""
	
	
func _ready() -> void:
	pressed.connect(_entry_pressed)

func _entry_pressed() -> void:
	pressed_entry.emit(dex_number)
	

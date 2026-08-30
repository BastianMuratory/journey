extends Button
class_name CollectionEntry

@onready var _pokemon_level : Label = %PokemonLevel
@onready var _pokemon_icon : TextureRect = %PokemonIcon
@onready var _pokemon_name : Label = %PokemonName

signal pressed_entry(uid : int)

var uid : int = 0

func bind(pokemon_uid : int) -> void:
	visible = true
	uid = pokemon_uid
	var instance : PokemonInstance = PokemonPlayer.collection.get_pokemon(pokemon_uid)
	_pokemon_level.text = String.num(instance.level,0)
	var data : PokemonBaseData = instance.base_data
	_pokemon_icon.texture = data.icon if data.has_icon() else preload(GlobalConstants.UNKNOW_POKEMON_ICON)
	_pokemon_name.text = instance.display_name

func _ready() -> void:
	pressed.connect(_entry_pressed)

func _entry_pressed() -> void:
	pressed_entry.emit(uid)

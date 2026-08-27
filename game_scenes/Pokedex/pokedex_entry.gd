extends Button

@onready var _pokemon_number : Label = %PokemonNumber
@onready var _pokemon_icon : TextureRect = %PokemonIcon
@onready var _pokemon_name : Label = %PokemonName

func bind(pokedex_number : int, seen : bool):
	_pokemon_number.text = String.num(pokedex_number)
	if seen:
		_pokemon_icon.texture = PokemonRegistry.getIcon(pokedex_number)
	else:
		_pokemon_icon.texture = preload("uid://b8o5cgof5njom")

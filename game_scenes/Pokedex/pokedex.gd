extends Node

const _POKEDEX_SAVE_FILE_PATH = "user://pokedex.json"

# pokedex = [Dex_Number, stats]
# stats : 
# [Number_Seen,
#  Number_Caught,
#  Number_Defeated,
#  Max_Level,
#  Levels_Played, # Number of time thispokemon went on a mission 
#  Damage_Dealt # Ammount of damage dealt with this pokemon
#]
var _pokedex : Dictionary[int, Array]

enum PokedexStats {
	NUMBER_SEEN,
	NUMBER_CAUGHT,
	NUMBER_DEFEATED,
	MAX_LEVEL,
	LEVELS_PLAYED,
	DAMAGE_DEALT,
	SHINY_SEEN,
	SHINY_CAUGHT,
}

# signals
signal pokedex_see
signal pokedex_catch
signal pokedex_defeat
signal pokedex_max_level
signal pokedex_level_played
signal pokedex_damage_dealt

func _ready() -> void:
	_load_pokedex()
	pokedex_see.connect(see)
	pokedex_catch.connect(catch)
	pokedex_defeat.connect(defeat)
	pokedex_max_level.connect(update_max_level)
	pokedex_level_played.connect(start_level)
	pokedex_damage_dealt.connect(deal_damage)

func _load_pokedex() -> void :
	_pokedex = {}
	
	var pokedex_file : FileAccess
	if FileAccess.file_exists(_POKEDEX_SAVE_FILE_PATH):
		pokedex_file = FileAccess.open(_POKEDEX_SAVE_FILE_PATH, FileAccess.READ)
		var pokedex_saved_data = JSON.parse_string(pokedex_file.get_as_text()) # not sure if get_as_text is best solution
		# todo convert string into array for each key and assign it
		pokedex_file.close()
	else:
		
		print("banane")
		print(PokemonRegistry.all_dex_numbers)
		print("banane")
		for i in PokemonRegistry.all_dex_numbers:
			var stats : Array = [0, 0, 0, 0, 0, 0, 0, 0]
			_pokedex.set(i, stats)

func save_pokedex() -> void :
	_pokedex.sort()
	var pokedex_file : FileAccess = FileAccess.open(_POKEDEX_SAVE_FILE_PATH, FileAccess.WRITE)
	var pokedex_data = JSON.stringify(_pokedex)
	pokedex_file.store_string(pokedex_data)
	pokedex_file.close()


func see(id : int, number : int = 1, shiny : bool = false) -> void :
	_pokedex.get(id)[PokedexStats.NUMBER_SEEN] += number
	if shiny : 
		_pokedex.get(id)[PokedexStats.SHINY_SEEN] += number

func catch(id : int, number : int = 1, shiny : bool = false) -> void :
	_pokedex.get(id)[PokedexStats.NUMBER_CAUGHT] += number
	_pokedex.get(id)[PokedexStats.NUMBER_SEEN] += number
	if shiny : 
		_pokedex.get(id)[PokedexStats.SHINY_SEEN] += number
		_pokedex.get(id)[PokedexStats.SHINY_CAUGHT] += number

func defeat(id : int, number : int = 1) -> void :
	_pokedex.get(id)[PokedexStats.NUMBER_DEFEATED] += number

func update_max_level(id : int, level : int = 1) -> void :
	if level > _pokedex.get(id)[PokedexStats.MAX_LEVEL] :
		_pokedex.get(id)[PokedexStats.MAX_LEVEL] = level

func start_level(id : int, number : int = 1) -> void :
	_pokedex.get(id)[PokedexStats.LEVELS_PLAYED] += number

func deal_damage(id : int, number : int) -> void :
	_pokedex.get(id)[PokedexStats.DAMAGE_DEALT] += number

func is_seen(id : int) -> bool:
	print(id)
	return _pokedex.get(id)[PokedexStats.NUMBER_SEEN] > 0

func is_caught(id : int) -> bool:
	return _pokedex.get(id)[PokedexStats.NUMBER_CAUGHT] > 0

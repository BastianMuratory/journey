class_name PokemonInstance
extends Resource

@export_group("Info")
# Not sure if I keep a PokemonBaseData there or just the int dex_number
@export var base_data: PokemonBaseData
@export var nickname: String = ""
@export_range(1, 100, 1) var level: int = 1
@export var experience: int = 0
@export var shiny: bool = false

@export_group("Moves") # only one for now
@export var move: Enums.AttackID = Enums.AttackID.TACKLE
@export var move_cooldown: float = 0

var uid: int = -1 # assigned when joining the collection


static func generate(dex: Enums.PokemonID, lvl: int = 1, shy: bool = false) -> PokemonInstance:
	var instance := PokemonInstance.new()
	instance.base_data = PokemonRegistry.get_pokemon(dex)
	instance.level = lvl
	instance.shiny = shy
	instance.move = instance.base_data.learnable_moves[0]
	return instance

var display_name: String:
	get:
		if not nickname.is_empty():
			return nickname
		return base_data.display_name if base_data != null else ""

var dex_number: int:
	get: return base_data.dex_number if base_data != null else 0

func icon() -> Texture2D:
	return base_data.icon if base_data != null else null

func preview() -> Texture2D:
	return base_data.get_preview(shiny) if base_data != null else null

## The Pokémon's own HP
func actual_max_hp() -> int:
	return base_data.base_hp + level

func actual_attack() -> int:
	return base_data.base_attack + level

func actual_speed() -> int:
	return base_data.base_speed + level

## Advances every move's cooldown. Call it once per frame from whatever runs the
## battle.
func tick(delta: float) -> void:
	move_cooldown += delta

# --- evolution ---------------------------------------------------------------

func evolve(into: PokemonBaseData = null) -> bool:
	if not base_data.can_evolve():
		return false

	base_data = into
	return true

func to_dict() -> Dictionary:       # { uid, dex, nick, lvl, xp, shiny, move }
	var dict = {}
	dict["uid"] = int(uid)
	dict["dex"] = int(dex_number)
	dict["nick"] = nickname
	dict["lvl"] = int(level)
	dict["xp"] = int(experience)
	dict["shiny"] = shiny
	dict["move"] = int(move)
	return dict

static func from_dict(dict: Dictionary) -> PokemonInstance:
	var instance : PokemonInstance = PokemonInstance.new()
	instance.uid = int(dict["uid"])
	instance.base_data = PokemonRegistry.get_pokemon(int(dict["dex"]))
	instance.nickname = dict["nick"]
	instance.level = int(dict["lvl"])
	instance.experience = int(dict["xp"])
	instance.shiny = dict["shiny"]
	instance.move = int(dict["move"])
	return instance

func duplicate_instance() -> PokemonInstance:
	var copy := PokemonInstance.new()
	copy.base_data = base_data
	copy.nickname = nickname
	copy.level = level
	copy.experience = experience
	copy.shiny = shiny
	copy.move = move
	return copy

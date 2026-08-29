class_name Move
extends Resource

# Moves data
enum MoveCategory {
	PHYSICAL,
	SPECIAL,
	STATUS,
}

enum MoveStoneCategory {
	BROADBURST,
	SCATTERSHOT,
	SHARING,
	STAY_STRONG,
	WAIT_LESS,
	WHACK_WHACK,
}

@export var display_name: String = ""
## In-game flavour text, as it appears on the move's card.
@export_multiline var description: String = ""

@export_group("stats")
@export var type: PokemonBaseData.Type = PokemonBaseData.Type.NORMAL
@export var category: MoveCategory = MoveCategory.PHYSICAL
@export var power: int = 0
@export var wait_time: float = 5.0
@export var hit_repeat: int = 1 # number of times this move is used in a row
@export var spread: int = 0 # used for AOE attacks size multiplier
@export var effect_duration: float = 0.0 # used for stats up / down or movements
@export var cooldown: float = 10

@export_group("UI")
@export var icon: Texture2D
@export var model: String = "" # model used for the attack animation

func is_compatible_with_move_stone(move_stone_type: MoveStoneCategory) -> bool:
	match move_stone_type:
		MoveStoneCategory.BROADBURST:
			return category == MoveCategory.PHYSICAL
		MoveStoneCategory.SCATTERSHOT:
			return category == MoveCategory.SPECIAL
		MoveStoneCategory.SHARING:
			return category == MoveCategory.STATUS
		MoveStoneCategory.STAY_STRONG:
			return effect_duration > 0
		MoveStoneCategory.WAIT_LESS:
			return cooldown > 0
		MoveStoneCategory.WHACK_WHACK:
			return category != MoveCategory.SPECIAL
		_:
			return false

func summary() -> String:
	if power == 0:
		return "%d · %.1fs" % [PokemonBaseData.Type, wait_time]
	return "%d · %d power · %.1fs" % [PokemonBaseData.Type, power, wait_time]

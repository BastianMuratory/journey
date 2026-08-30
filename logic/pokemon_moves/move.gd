class_name Move
extends Resource


@export var id : Enums.AttackID = Enums.AttackID.TACKLE
@export var display_name: String = ""

@export_group("stats")
@export var type: Enums.TypeID = Enums.TypeID.NORMAL
@export var category: Enums.MoveCategory = Enums.MoveCategory.PHYSICAL
@export var power: int = 0
@export var cooldown: float = 5.0
@export var hit_repeat: int = 1 # number of times this move is used in a row
@export var spread: int = 0 # used for AOE attacks size multiplier
@export var effect_duration: float = 0.0 # used for stats up / down or movements

@export_group("UI")
@export var icon: Texture2D
@export var model: String = "" # model used for the attack animation
@export var area: BitMap = BitMap.new()
@export var area_diagonal: BitMap = BitMap.new()

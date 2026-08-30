extends Node
class_name Player

var collection := PokemonCollection.new()
# var inventory  — later
var team := Team.new()

func _ready() -> void:
	SignalBus.add_to_collection.connect(_add_to_collection)
	load_game()

func load_game() -> void:
	collection.load_collection()
	team.load_team()

func save_game() -> void:
	collection.save_collection()
	team.save_team()

func _add_to_collection(pokemon : PokemonInstance) -> void:
	collection.add(pokemon)

func _add_to_team(uid : int) -> void:
	team.add(uid)

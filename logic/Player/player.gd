extends Node
class_name Player

var collection := PokemonCollection.new()
# var inventory  — later
var team := Team.new()

func _ready() -> void:
	SignalBus.add_to_collection.connect(_add_to_collection)
	SignalBus.collection_changed.connect(save_collection)
	SignalBus.team_changed.connect(save_team)
	load_game()

func load_game() -> void:
	collection.load_collection()
	team.load_team()

func save_collection() -> void:
	collection.save_collection()
	
func save_team() -> void:
	team.save_team()

func _add_to_collection(pokemon : PokemonInstance) -> void:
	collection.add(pokemon)

func _add_to_team(uid : int) -> void:
	team.add(uid)

class_name Team extends Resource

const MAX_TEAM_SIZE = 3
const TEAM_SAVE_PATH = "user://team_save.json"
const TMP_TEAM_SAVE_PATH = "user://team_save.json.tmp"

enum TEAM{
	FIRST,
	SECOND,
	THIRD
}

@export var pokemons : Array[int] # The 3 Uids of the pokemons composing the team

func set_slot(index : TEAM, uid : int) -> void:
	if uid != -1:
		print("\nTeam before operation")
		print("Setting team member ", TEAM.find_key(index), " with ", PokemonPlayer.collection.get_pokemon(uid).display_name)
		for id in range(MAX_TEAM_SIZE):
			# Replace anything at the index with the selected pokemon
			if id == index:
				pokemons[index] = uid
			# Then, if specified uid was already assigned alsewhere, remove it
			elif pokemons[id] == uid: 
				pokemons[id] = -1
		SignalBus.team_changed.emit()

func clear_slot(index : int) -> void:
	pokemons[index] = -1
	SignalBus.team_changed.emit()

func has(uid) -> bool:
	for p_uid in pokemons:
		if p_uid == uid:
			return true
	return false

func remove(uid : int = -1) -> bool:
	if pokemons.size() > 0:
		var removed = false
		if uid == -1: # remove the last pokemon added
			pokemons.pop_back()
			removed = true
			SignalBus.team_changed.emit()
		else:
			for i in range(MAX_TEAM_SIZE):
				if pokemons[i] == uid:
					pokemons.pop_at(i)
					removed = true
					SignalBus.team_changed.emit()
		return removed
	return false

func save_team():
	print("Saving Team")
	var team_str : String  = JSON.stringify(pokemons)
	print("Team = ", team_str)
	var file := FileAccess.open(TMP_TEAM_SAVE_PATH, FileAccess.WRITE)

	file.store_string(team_str)
	file.close()
	DirAccess.rename_absolute(TMP_TEAM_SAVE_PATH, TEAM_SAVE_PATH)
	print("Saving Team Finished")


func load_team():
	print("Loading Team")
	pokemons.clear()
	var team_str : String
	var file := FileAccess.open(TEAM_SAVE_PATH, FileAccess.READ)

	if file != null:
		team_str = file.get_as_text()
		var team_uids = JSON.parse_string(team_str)
		for uid in team_uids:
			pokemons.push_back(int(uid))
	else : 
		pokemons = [-1, -1, -1]
	print("Team loaded = ", pokemons)
	print("Loading Team Finished")

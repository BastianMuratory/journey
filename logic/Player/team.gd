class_name Team extends Resource

const MAX_TEAM_SIZE = 3
const TEAM_SAVE_PATH = "user://team_save.json"
const TMP_TEAM_SAVE_PATH = "user://team_save.json.tmp"

@export var pokemons : Array[int] # The 3 Uids of the pokemons composing the team

func add(uid : int) -> bool:
	if pokemons.size() < MAX_TEAM_SIZE:
		pokemons.push_back(uid)
		SignalBus.team_changed.emit()
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
	var team_str : String  = JSON.stringify(pokemons)
	var file := FileAccess.open(TMP_TEAM_SAVE_PATH, FileAccess.WRITE)

	file.store_string(team_str)
	file.close()
	DirAccess.rename_absolute(TMP_TEAM_SAVE_PATH, TEAM_SAVE_PATH)


func load_team():
	pokemons.clear()
	var team_str : String
	var file := FileAccess.open(TEAM_SAVE_PATH, FileAccess.READ)

	if file != null:
		team_str = file.get_as_text()
		print(JSON.parse_string(team_str))
		# TODO

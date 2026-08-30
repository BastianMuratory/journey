extends Resource
class_name PokemonCollection


var _by_uid: Dictionary[int, PokemonInstance]
var _next_uid : int = 1

const DEFAULT_CAPACITY := 40
const VERSION := 1
const COLLECTION_SAVE_PATH = "user://collection_save.json"
const TMP_COLLECTION_SAVE_PATH = "user://collection_save.json.tmp"
const NEW_SAVE_DICT = {
	"version": VERSION,
	"next_uid": 1,
	"collection": {}
}

signal box_full()

func add(instance: PokemonInstance) -> int:
	if self.is_full():
		instance.uid = _next_uid
		_by_uid[_next_uid] = instance
		_next_uid += 1
		print("Added to collection: " , instance.to_dict())
		return instance.uid
		SignalBus.collection_changed.emit()
	
	box_full.emit()
	return -1

func remove(uid: int) -> PokemonInstance :
	var temp : PokemonInstance = null
	if _by_uid.has(uid):
		temp = _by_uid[uid]
		_by_uid.erase(uid)
		SignalBus.collection_changed.emit()
		if PokemonPlayer.team.remove(uid):
			SignalBus.team_changed.emit()
	return temp

	
func get_pokemon(uid: int) -> PokemonInstance:
	if _by_uid.has(uid):
		return _by_uid[uid]
	return null

func has(uid: int) -> bool:
	return _by_uid.has(uid)

func size() -> int:
	return _by_uid.size()

func is_full() -> bool:
	return _by_uid.size() >= DEFAULT_CAPACITY

func sorted_uids() -> Array[int]:
	var sorted_uids : Array[int] = Array(_by_uid.keys())
	sorted_uids.sort()
	return sorted_uids

func all() -> Array[PokemonInstance]:
	return _by_uid.values()

func of_species(dex: int) -> Array[PokemonInstance]:
	var array_of_species : Array[PokemonInstance] = []
	for pokemon : PokemonInstance in _by_uid.values():
		if pokemon.dex_number == dex:
			array_of_species.push_back(pokemon)
	return array_of_species

func to_dict() -> Dictionary:
	var dict : Dictionary
	dict["version"] = VERSION
	dict["next_uid"] = _next_uid
	var collection_dict : Dictionary = {}
	for uid in _by_uid.keys():
		collection_dict[uid] = _by_uid[uid].to_dict()
	dict["collection"] = collection_dict
	return dict

# parameter dict should be 
# {"version" : X,
#  "next_uid" : Y,
#  "collection" : {"uid_first_pokemon" : {Pokemon_base_data_disct},
#                  "uid_second_pokemon" ...}
func from_dict(dict : Dictionary) -> void:
	if dict["version"] != VERSION : 
		push_error("Warning, loading old version of collection")
	_next_uid = dict["next_uid"]
	_by_uid.clear()
	var pokemon_dict : Dictionary = dict["collection"]
	for k in pokemon_dict.keys():
		var uid = int(k)
		_by_uid[uid] = PokemonInstance.from_dict(pokemon_dict[k])
		
	return

func save_collection() -> void:
	var collection_str : String
	collection_str = JSON.stringify(self.to_dict())
	
	var file := FileAccess.open(TMP_COLLECTION_SAVE_PATH, FileAccess.WRITE)
	file.store_string(collection_str)
	file.close()
	DirAccess.rename_absolute(TMP_COLLECTION_SAVE_PATH, COLLECTION_SAVE_PATH)

func load_collection() -> void:
	var dict : Dictionary = NEW_SAVE_DICT
	var collection_str : String
	var file := FileAccess.open(COLLECTION_SAVE_PATH, FileAccess.READ)
	if file != null:
		collection_str = file.get_as_text()
		dict = JSON.parse_string(collection_str)
	print(dict)
	self.from_dict(dict)
	

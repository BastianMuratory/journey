extends Node

enum Scenes { NONE, MAIN_MENU, BASE_CAMP, LEVEL, ADMIN_MENU, POKEDEX, COLLECTION }

const PATHS := {
	Scenes.NONE:"",
	Scenes.MAIN_MENU: "uid://bw285vjy5x27t",
	Scenes.BASE_CAMP: "uid://hkbwr68qqvqe",
	Scenes.LEVEL: "uid://b012lxyyb4773",
	Scenes.ADMIN_MENU: "uid://dtjmal2xvccgp",
	Scenes.POKEDEX: "uid://btillhmlpwyi6",
	Scenes.COLLECTION: "uid://cxr8wjg3nokwv",
}

signal scene_entered(id: Scenes)
signal transition_started(id: Scenes)

var _scenes_stack: Array[Scenes] = []

func _ready() -> void:
	_scenes_stack.push_back(Scenes.MAIN_MENU)

func current_scene() -> Scenes:
	return _scenes_stack[-1]

func _change_scene(id: Scenes) -> void:
	transition_started.emit(id)
	# todo await _fade_out()
	print_verbose("Going to ", Scenes.keys()[id])
	get_tree().change_scene_to_file(PATHS[id])
	await get_tree().process_frame # wait for the new scene to be effectively started
	scene_entered.emit(id)
	# todo await _fade_in()

func go_to(scene: Scenes, params: Dictionary = {}) -> void:
	_scenes_stack.push_back(scene)
	await _change_scene(scene)

func go_back() -> void:
	print_verbose("Going Back")
	if _scenes_stack.size() > 1:
		_scenes_stack.pop_back()
		await _change_scene(_scenes_stack[-1])
	
func reload() -> void:
	print_verbose("Reloading")
	await _change_scene(_scenes_stack[-1])

# TODO  preload the base camp on the main menu to make sure it is ready 
#func on_scene_changed()-> void:
	#if scene is Scenes.MAIN_MENU
		#GAME_SCENE := preload("res://game_scenes/base_camp/base_camp.tscn")

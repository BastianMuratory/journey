extends Node2D

# Game scene might take time to load because of all the pokemon models, so preload it
const GAME_SCENE := preload("res://game_scenes/base_camp/base_camp.tscn")

const OPTION_SCENE := "res://game_scenes/base_camp/base_camp.tscn" # for now there aren't any options

# Small scene, and it loads its Pokémon lazily through the registry, so there is
# nothing to gain from preloading this one the way the camp does.
const ADMIN_MENU_SCENE := "res://game_scenes/admin_menu/admin_menu.tscn"

@onready var play_button: Button = $MarginContainer/MenuOptions/PlayButton
@onready var admin_menu_button: Button = $MarginContainer/MenuOptions/AdminMenuButton
@onready var quit_button: Button = $MarginContainer/MenuOptions/QuitButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	admin_menu_button.pressed.connect(_on_admin_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	play_button.grab_focus()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_packed(GAME_SCENE)

func _on_admin_menu_pressed() -> void:
	get_tree().change_scene_to_file(ADMIN_MENU_SCENE)

func _on_quit_pressed() -> void:
	get_tree().quit()

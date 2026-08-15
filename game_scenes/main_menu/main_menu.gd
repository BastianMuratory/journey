extends Node2D

# Game scene might take time to load because of all the pokemon models, so preload it
const GAME_SCENE := preload("res://game_scenes/base_camp/base_camp.tscn")

const OPTION_SCENE := "res://game_scenes/base_camp/base_camp.tscn" # for now there aren't any options

@onready var play_button: Button = $MarginContainer/MenuOptions/PlayButton
@onready var option_button: Button = $MarginContainer/MenuOptions/OptionButton
@onready var quit_button: Button = $MarginContainer/MenuOptions/QuitButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	option_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	play_button.grab_focus()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_packed(GAME_SCENE)

func _on_options_pressed() -> void:
	get_tree().change_scene_to_file(OPTION_SCENE)

func _on_quit_pressed() -> void:
	get_tree().quit()

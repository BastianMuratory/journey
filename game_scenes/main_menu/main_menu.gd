extends Node2D

# Game scene might take time to load because of all the pokemon models, so preload it
const GAME_SCENE := preload("res://game_scenes/base_camp/base_camp.tscn")

const OPTION_SCENE := "res://game_scenes/base_camp/base_camp.tscn" # for now there aren't any options

# Small scene, and it loads its Pokémon lazily through the registry, so there is
# nothing to gain from preloading this one the way the camp does.
const ANIMATION_TEST_SCENE := "res://game_scenes/animation_test/animation_test.tscn"

@onready var play_button: Button = $MarginContainer/MenuOptions/PlayButton
@onready var option_button: Button = $MarginContainer/MenuOptions/OptionButton
@onready var animation_test_button: Button = $MarginContainer/MenuOptions/AnimationTestButton
@onready var quit_button: Button = $MarginContainer/MenuOptions/QuitButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	animation_test_button.pressed.connect(_on_animation_test_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	play_button.grab_focus()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_packed(GAME_SCENE)

func _on_animation_test_pressed() -> void:
	get_tree().change_scene_to_file(ANIMATION_TEST_SCENE)

func _on_quit_pressed() -> void:
	get_tree().quit()

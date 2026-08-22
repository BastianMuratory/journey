class_name BaseCampUI
extends CanvasLayer

# Buttons signals
signal pokedex_button_pressed
signal quests_pressed
signal edit_team_pressed
signal party_slot_pressed(slot_index: int)

## For now, let's open the develloper menu
const OPTIONS_SCENE := "res://game_scenes/admin_menu/admin_menu.tscn"

## This one starts a level
const LEVEL_SCENE := "res://game_scenes/level/level.tscn"

## Title on top left.
@export var scene_title: String = "Base Camp"

@onready var options_button: Button = %OptionsButton
@onready var pokedex_button: Button = %PokedexButton
@onready var edit_team_button: Button = %EditTeamButton
@onready var start_button: Button = %StartButton


func _ready() -> void:
	options_button.pressed.connect(on_options_pressed)
	pokedex_button.pressed.connect(on_pokedex_pressed)
	edit_team_button.pressed.connect(on_edit_team_pressed)
	start_button.pressed.connect(on_start_pressed)

func on_pokedex_pressed() -> void:
	get_tree().change_scene_to_file(OPTIONS_SCENE)

func on_edit_team_pressed() -> void:
	return
	# For now don't do anything
	# get_tree().change_scene_to_file(OPTIONS_SCENE)

func on_options_pressed() -> void:
	get_tree().change_scene_to_file(OPTIONS_SCENE)


func on_start_pressed() -> void:
	get_tree().change_scene_to_file(LEVEL_SCENE)

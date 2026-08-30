class_name BaseCampUI
extends CanvasLayer


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
	SceneManager.go_to(SceneManager.Scenes.POKEDEX)
	return
	# For now don't do anything

func on_edit_team_pressed() -> void:
	SceneManager.go_to(SceneManager.Scenes.COLLECTION)

func on_options_pressed() -> void:
	SceneManager.go_to(SceneManager.Scenes.ADMIN_MENU)

func on_start_pressed() -> void:
	SceneManager.go_to(SceneManager.Scenes.LEVEL)

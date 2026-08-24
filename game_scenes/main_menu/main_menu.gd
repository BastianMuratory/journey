extends Node2D


@onready var play_button: Button = $MarginContainer/MenuOptions/PlayButton
@onready var admin_menu_button: Button = $MarginContainer/MenuOptions/AdminMenuButton
@onready var quit_button: Button = $MarginContainer/MenuOptions/QuitButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	admin_menu_button.pressed.connect(_on_admin_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	play_button.grab_focus()

func _on_play_pressed() -> void:
	SceneManager.go_to(SceneManager.Scenes.BASE_CAMP)

func _on_admin_menu_pressed() -> void:
	SceneManager.go_to(SceneManager.Scenes.ADMIN_MENU)

func _on_quit_pressed() -> void:
	get_tree().quit()

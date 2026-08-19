extends HBoxContainer

const CHARACTER_ICON_SCRIPT := preload("res://game_scenes/level/UI/character_icon.gd")

signal skill_requested(player: Node3D, skill_index: int)

const CARD_COLORS := [
	Color(0.16, 0.72, 0.26, 0.92),
	Color(0.88, 0.42, 0.12, 0.92),
	Color(0.08, 0.48, 0.86, 0.92),
]

var _skill_buttons_by_player: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)


func set_players(players: Array[Node3D]) -> void:
	_skill_buttons_by_player.clear()
	for child in get_children():
		child.queue_free()

	for index in players.size():
		var player: Node3D = players[index]
		add_child(_create_player_card(player, index))


func _create_player_card(player: Node3D, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(130.0, 86.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style(CARD_COLORS[index % CARD_COLORS.size()]))

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	card.add_child(content)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)
	content.add_child(top_row)

	var move_one := _create_move_button(_move_name(player, 0), _move_color(index, 0), player, 0)
	top_row.add_child(move_one)

	var identity := VBoxContainer.new()
	identity.custom_minimum_size = Vector2(40.0, 58.0)
	identity.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	identity.add_theme_constant_override("separation", 0)
	top_row.add_child(identity)

	var icon = CHARACTER_ICON_SCRIPT.new()
	icon.icon_color = _icon_color(player)
	icon.round_icon = _uses_round_icon(player)
	icon.texture = _pokemon_icon(player)
	identity.add_child(icon)

	var name_label := Label.new()
	name_label.text = _character_name(player, index)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	identity.add_child(name_label)

	var move_two := _create_move_button(_move_name(player, 1), _move_color(index, 1), player, 1)
	top_row.add_child(move_two)
	_skill_buttons_by_player[player] = [move_one, move_two]

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	content.add_child(footer)

	footer.add_child(_create_move_label(_move_name(player, 0)))
	footer.add_child(_create_move_label(_move_name(player, 1)))

	return card


func _create_move_button(move_name: String, color: Color, player: Node3D, skill_index: int) -> Button:
	var button := Button.new()
	button.text = _move_glyph(move_name)
	button.tooltip_text = move_name
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(34.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.45))
	button.add_theme_constant_override("shadow_offset_x", 1)
	button.add_theme_constant_override("shadow_offset_y", 1)
	button.add_theme_stylebox_override("normal", _button_style(color))
	button.add_theme_stylebox_override("hover", _button_style(color.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", _button_style(color.darkened(0.12)))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.18, 0.2, 0.22, 0.78)))
	button.pressed.connect(_on_move_button_pressed.bind(player, skill_index))
	return button


func _on_move_button_pressed(player: Node3D, skill_index: int) -> void:
	skill_requested.emit(player, skill_index)


func set_player_skill_ready(player: Node3D, is_ready: bool) -> void:
	if not _skill_buttons_by_player.has(player):
		return

	for button in _skill_buttons_by_player[player]:
		button.disabled = not is_ready


func _create_move_label(move_name: String) -> Label:
	var label := Label.new()
	label.text = move_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _card_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.08)
	style.border_color = Color(1.0, 1.0, 1.0, 0.86)
	style.set_border_width_all(4)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	style.shadow_size = 3
	style.set_content_margin(SIDE_LEFT, 6)
	style.set_content_margin(SIDE_RIGHT, 6)
	style.set_content_margin(SIDE_TOP, 6)
	style.set_content_margin(SIDE_BOTTOM, 4)
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(1.0, 1.0, 1.0, 0.36)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	style.shadow_size = 2
	return style


func _uses_round_icon(player: Node3D) -> bool:
	return player.attack_range > 1.5


func _icon_color(player: Node3D) -> Color:
	if _uses_round_icon(player):
		return Color(0.16, 0.72, 1.0, 1.0)
	return Color(0.25, 0.48, 0.92, 1.0)


func _pokemon_icon(player: Node3D) -> Texture2D:
	var data = player.get("pokemon_data")
	if data is PokemonBaseData:
		return data.icon
	return null


func _character_name(player: Node3D, index: int) -> String:
	if player.has_method("display_name"):
		return player.display_name()
	if _uses_round_icon(player):
		return "Ranged Ally"
	return "Ally %d" % (index + 1)


func _move_name(player: Node3D, move_index: int) -> String:
	if _uses_round_icon(player):
		if move_index == 0:
			return "Bubble"
		return "Splash"
	if move_index == 0:
		return "Tackle"
	return "Slam"


func _move_color(index: int, move_index: int) -> Color:
	var base_color: Color = CARD_COLORS[index % CARD_COLORS.size()]
	if move_index == 0:
		return base_color.lightened(0.08)
	return base_color.darkened(0.12)


func _move_glyph(move_name: String) -> String:
	match move_name:
		"Bubble":
			return "OO"
		"Splash":
			return "~~"
		"Slam":
			return "#"
		_:
			return "///"

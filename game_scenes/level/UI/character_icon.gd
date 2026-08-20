extends Control

@export var icon_color: Color = Color(0.25, 0.48, 0.92, 1.0)
@export var round_icon: bool = false
@export var texture: Texture2D


func _ready() -> void:
	custom_minimum_size = Vector2(36.0, 36.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var icon_size := minf(size.x, size.y)
	if texture != null:
		var sprite_bounds := Rect2(Vector2.ZERO, Vector2(icon_size, icon_size))
		sprite_bounds.position = (size - sprite_bounds.size) * 0.5
		draw_texture_rect(texture, sprite_bounds, false)
		return

	var actor_size := icon_size - 10.0
	if actor_size <= 0.0:
		return
	var bounds := Rect2((size - Vector2(actor_size, actor_size)) * 0.5, Vector2(actor_size, actor_size))
	var shadow_color := Color(0.0, 0.0, 0.0, 0.18)
	var dark_color := icon_color.darkened(0.22)
	var light_color := icon_color.lightened(0.35)

	if round_icon:
		var center := bounds.get_center()
		var radius := actor_size * 0.5
		draw_circle(center + Vector2(3.0, 4.0), radius, shadow_color)
		draw_circle(center, radius, dark_color)
		draw_circle(center + Vector2(-3.0, -3.0), radius * 0.85, icon_color)
		draw_circle(center + Vector2(-7.0, -8.0), radius * 0.25, light_color)
		return

	draw_rect(Rect2(bounds.position + Vector2(3.0, 4.0), bounds.size), shadow_color, true)
	draw_rect(bounds, dark_color, true)
	draw_rect(Rect2(bounds.position + Vector2(3.0, 3.0), bounds.size - Vector2(6.0, 6.0)), icon_color, true)
	draw_rect(Rect2(bounds.position + Vector2(7.0, 7.0), Vector2(9.0, 7.0)), light_color, true)

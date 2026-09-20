extends Node2D

var is_valid_target: bool = true
var pulse_time: float = 0.0

func _process(delta: float) -> void:
	if not visible:
		return
	global_position = get_viewport().get_mouse_position()
	pulse_time += delta * 5.0
	queue_redraw()

func _draw() -> void:
	var color := Color(0.2, 0.85, 1.0, 0.85) if is_valid_target else Color(1.0, 0.25, 0.25, 0.85)
	var radius := 16.0 + sin(pulse_time) * 2.0
	
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, color, 2.0, true)
	draw_circle(Vector2.ZERO, 3.0, color)
	draw_line(Vector2(-radius - 6, 0), Vector2(-radius + 2, 0), color, 2.0)
	draw_line(Vector2(radius - 2, 0), Vector2(radius + 6, 0), color, 2.0)
	draw_line(Vector2(0, -radius - 6), Vector2(0, -radius + 2), color, 2.0)
	draw_line(Vector2(0, radius - 2), Vector2(0, radius + 6), color, 2.0)

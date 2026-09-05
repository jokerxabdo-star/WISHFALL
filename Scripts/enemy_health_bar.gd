extends Node2D


@onready var health_bar: Sprite2D = $Health
@onready var default_width = health_bar.region_rect.size.x
@onready var default_height = health_bar.region_rect.size.y


func Update_health(new_health: int) -> void:
	#Resize the health bar
	var new_width = (new_health / 100.0) * default_width
	health_bar.region_rect = Rect2(0, 0, new_width, default_height)

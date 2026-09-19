extends Node

# Health
var max_health: int = 100
var health: int = 100

# Combat & Movement
var Strength: int = 20
var speed: float = 700

# Dash
var has_dash: bool = false
var dash_damage: int = 10
var dash_reload_cost: float = 0.35

# Teleport
var has_teleport: bool = false
var teleport_cooldown: float = 3.0
var tactical_zoom_factor: float = 0.8 ## Smaller number zooms out farther


func reset() -> void:
	max_health = 100
	health = max_health
	Strength = 20
	speed = 700
	
	has_dash = false
	dash_damage = 10
	dash_reload_cost = 0.35
	
	has_teleport = false
	teleport_cooldown = 3.0
	tactical_zoom_factor = 0.8

class_name ObjectiveBarrier
extends Node2D

@onready var solid_wall_shape: CollisionShape2D = $SolidWall/CollisionShape2D
@onready var trigger_zone: Area2D = $TriggerZone
@onready var prompt_label: Label = $PromptLabel

var prompt_tween: Tween = null
var is_barrier_open: bool = false


func _ready() -> void:
	# Add to group so Main.gd can notify it when enemies change
	add_to_group("ObjectiveBarriers")
	
	if trigger_zone:
		trigger_zone.body_entered.connect(_on_trigger_body_entered)


func _on_trigger_body_entered(body: Node2D) -> void:
	if is_barrier_open:
		return

	if body.name == "Player" or body.is_in_group("Player"):
		_show_prompt()


func _show_prompt() -> void:
	if prompt_tween and prompt_tween.is_valid():
		prompt_tween.kill()

	prompt_label.modulate.a = 0.0
	prompt_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	prompt_tween.tween_property(prompt_label, "modulate:a", 1.0, 0.15)
	prompt_tween.tween_interval(1.2)
	prompt_tween.tween_property(prompt_label, "modulate:a", 0.0, 0.4)


func open_barrier() -> void:
	if is_barrier_open:
		return
	is_barrier_open = true

	# Vanish the solid collision shape so the player can pass
	if is_instance_valid(solid_wall_shape):
		solid_wall_shape.set_deferred("disabled", true)

	# Hide prompt and fade out any visual sprite if you have one attached
	if prompt_tween and prompt_tween.is_valid():
		prompt_tween.kill()
	prompt_label.modulate.a = 0.0

	var fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await fade_tween.finished
	# Optionally free the barrier once cleared
	queue_free()

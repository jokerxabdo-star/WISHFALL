extends Area2D

@onready var pickup_sound: AudioStreamPlayer2D = get_node_or_null("PickupSound")
@onready var sprite: Sprite2D = $Sprite2D

var collected: bool = false

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if collected:
		return

	if body.name == "Player" or body.is_in_group("Player"):
		collected = true
		
		# Notify the level controller that the key was collected
		get_tree().call_group("LevelController", "on_key_collected")
		
		
		if is_instance_valid(pickup_sound) and pickup_sound.stream:
			pickup_sound.play()  # Play pickup sound
			
			# Hide visual sprite immediately
			if is_instance_valid(sprite):
				sprite.visible = false
			
			# Disable collision so it can't be triggered twice
			set_deferred("monitoring", false)
			set_deferred("monitorable", false)
			
			# Wait for the audio to finish playing before freeing the node
			await pickup_sound.finished
			queue_free()
		else:
			queue_free()

extends Node2D


func _on_exit_body_entered(body: Node2D) -> void:
	if body.name == "Player":
		$Exit.queue_free()

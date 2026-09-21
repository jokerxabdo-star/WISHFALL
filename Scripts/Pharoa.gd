class_name Pharoa
extends BaseEnemy

func _ready() -> void:
	drops_key = true
	super._ready()


func _die() -> void:
	is_alive = false
	is_performing_attack = false
	enemy_died.emit()
	target_player = null
	velocity = Vector2.ZERO
	knockback_velocity = Vector2.ZERO

	if is_instance_valid(shadow):
		var shadow_tween := create_tween()
		shadow_tween.tween_property(shadow, "modulate:a", 0.0, 0.2)

	if sprite and sprite.material is ShaderMaterial:
		(sprite.material as ShaderMaterial).set_shader_parameter("flash_white", false)
	if sprite:
		sprite.modulate = Color.WHITE

	if take_damage_sound:
		if death_sound:
			take_damage_sound.stream = death_sound
		take_damage_sound.pitch_scale = randf_range(0.85, 1.05)
		take_damage_sound.play()

	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if has_node("Sight/CollisionShape2D"):
		$Sight/CollisionShape2D.set_deferred("disabled", true)
	if has_node("HitBox/CollisionShape2D"):
		$HitBox/CollisionShape2D.set_deferred("disabled", true)

	# Drop the key and prevent hearts from dropping
	if drops_key:
		_spawn_key_drop()
	elif randf() <= drop_chance:
		drop_item()

	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(die_anim):
		sprite.play(die_anim)
		await sprite.animation_finished
	else:
		var death_tween := create_tween()
		death_tween.tween_property(self, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		await death_tween.finished

	queue_free()


func _spawn_key_drop() -> void:
	if not key_scene:
		printerr("[KEY ERROR] key_scene is null on ", name, "! Check inspector.")
		return

	var key_inst = key_scene.instantiate()
	var spawn_pos: Vector2 = global_position

	var target_parent: Node = get_parent()
	if not target_parent:
		target_parent = get_tree().current_scene

	target_parent.call_deferred("add_child", key_inst)
	key_inst.set_deferred("global_position", spawn_pos)
	key_inst.set_deferred("z_index", 10)

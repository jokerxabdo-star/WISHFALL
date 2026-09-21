class_name BaseEnemy
extends CharacterBody2D

signal enemy_died

@export_group("Key Drop Settings")
@export var drops_key: bool = false ## If true, drops the level key on death instead of hearts
@export var key_scene: PackedScene = preload("res://Scenes/key.tscn")

@export_group("Base Enemy Stats")
@export var max_health: int = 80
@export var move_speed: float = 130.0
@export var strength: int = 10
@export var knockback_force: float = 120.0
@export var drop_chance: float = 0.26
@export var attack_stop_distance: float = 65.0 ## Distance in pixels where enemy stops to attack

@export_group("Detection & Sight")
@export var lost_target_delay: float = 2.0 ## Seconds before dropping chase after player exits circle

@export_group("Animation Names")
@export var idle_anim: String = "Idle"
@export var run_anim: String = "Run"
@export var attack_anim: String = "Attack"
@export var die_anim: String = "Die"

@export_group("Audio Settings")
@export var step_interval: float = 0.36 ## Seconds between enemy footsteps while chasing
@export var footstep_sound: AudioStream = null ## Custom walking/stepping sound for this enemy
@export var hurt_sound: AudioStream = null     ## Sound played when taking damage
@export var death_sound: AudioStream = null    ## Sound played on death
@export var attack_sound: AudioStream = null   ## Optional swing/bite sound on attack

var health: int
var is_alive: bool = true
var target_player: CharacterBody2D = null

# Sight & Chase states
var is_chasing: bool = false
var player_in_sight: bool = false
var target_in_range: bool = false
var is_attacking_state: bool = false
var is_performing_attack: bool = false ## Locks state until the current attack cycle completes

# Footstep rhythm timer
var step_timer: float = 0.0

# Knockback vector tracked separately from chase velocity
var knockback_velocity: Vector2 = Vector2.ZERO

var health_pickup_scene = preload("res://Scenes/health_pickup.tscn")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var take_damage_sound: AudioStreamPlayer2D = get_node_or_null("TakeDamage")
@onready var enemy_health_bar: Control = get_node_or_null("Enemy_HealthBar")
@onready var sight_area: Area2D = get_node_or_null("Sight")
@onready var hitbox_area: Area2D = get_node_or_null("HitBox")
@onready var attack_timer: Timer = get_node_or_null("AttackTimer")
@onready var shadow: Sprite2D = get_node_or_null("Shadow")
@onready var footstep_audio: AudioStreamPlayer2D = get_node_or_null("FootstepAudio")
@onready var blood_spatter: CPUParticles2D = get_node_or_null("BloodSpatter")

var flash_tween: Tween = null


func _ready() -> void:
	add_to_group("Enemies")
	health = max_health
	
	_setup_audio_streams()
	
	call_deferred("_acquire_target")
	
	if is_instance_valid(enemy_health_bar) and enemy_health_bar.has_method("init_health"):
		enemy_health_bar.init_health(health)

	_setup_base_signals()


func _setup_audio_streams() -> void:
	if footstep_sound and is_instance_valid(footstep_audio):
		footstep_audio.stream = footstep_sound
		
	if hurt_sound and is_instance_valid(take_damage_sound):
		take_damage_sound.stream = hurt_sound


func _setup_base_signals() -> void:
	if sprite:
		if not sprite.animation_looped.is_connected(_on_animated_sprite_2d_animation_cycle_finished):
			sprite.animation_looped.connect(_on_animated_sprite_2d_animation_cycle_finished)
		if not sprite.animation_finished.is_connected(_on_animated_sprite_2d_animation_cycle_finished):
			sprite.animation_finished.connect(_on_animated_sprite_2d_animation_cycle_finished)

	if sight_area:
		if not sight_area.body_entered.is_connected(_on_sight_body_entered):
			sight_area.body_entered.connect(_on_sight_body_entered)
		if not sight_area.body_exited.is_connected(_on_sight_body_exited):
			sight_area.body_exited.connect(_on_sight_body_exited)

	if hitbox_area:
		if not hitbox_area.body_entered.is_connected(_on_hit_box_body_entered):
			hitbox_area.body_entered.connect(_on_hit_box_body_entered)
		if not hitbox_area.body_exited.is_connected(_on_hit_box_body_exited):
			hitbox_area.body_exited.connect(_on_hit_box_body_exited)

	if attack_timer:
		if not attack_timer.timeout.is_connected(_on_attack_timer_timeout):
			attack_timer.timeout.connect(_on_attack_timer_timeout)


func _physics_process(delta: float) -> void:
	if not is_alive:
		return
		
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 800.0 * delta)
	_process_base_chase()
	_enemy_logic(delta)
	
	velocity += knockback_velocity
	move_and_slide()
	_handle_footsteps(delta)


func _process_base_chase() -> void:
	if is_performing_attack:
		velocity = Vector2.ZERO
		return

	if not is_instance_valid(target_player) or not target_player.alive:
		_acquire_target()
		velocity = Vector2.ZERO
		is_attacking_state = false
		if attack_timer and not attack_timer.is_stopped():
			attack_timer.stop()
		play_anim(idle_anim)
		return

	if not is_chasing:
		velocity = Vector2.ZERO
		is_attacking_state = false
		if attack_timer and not attack_timer.is_stopped():
			attack_timer.stop()
		play_anim(idle_anim)
		return

	var dist_to_player: float = global_position.distance_to(target_player.global_position)
	var diff: Vector2 = target_player.global_position - global_position

	if abs(diff.x) > 6.0 and sprite:
		sprite.flip_h = diff.x < 0

	if dist_to_player <= attack_stop_distance:
		velocity = Vector2.ZERO
		is_attacking_state = true
		_start_attack()
	elif dist_to_player > attack_stop_distance + 20.0:
		is_attacking_state = false
		velocity = diff.normalized() * move_speed
		play_anim(run_anim)
		
		if attack_timer and not attack_timer.is_stopped():
			attack_timer.stop()
	else:
		if is_attacking_state:
			velocity = Vector2.ZERO
			_start_attack()
		else:
			velocity = diff.normalized() * move_speed
			play_anim(run_anim)


func _start_attack() -> void:
	if not is_performing_attack:
		is_performing_attack = true
		play_anim(attack_anim)
		
		if attack_sound and is_instance_valid(take_damage_sound):
			take_damage_sound.stream = attack_sound
			take_damage_sound.pitch_scale = randf_range(0.9, 1.1)
			take_damage_sound.play()
		
		if attack_timer and attack_timer.is_stopped():
			try_deal_damage()
			attack_timer.start()


func _on_animated_sprite_2d_animation_cycle_finished() -> void:
	if sprite and sprite.animation == attack_anim:
		is_performing_attack = false
		
		if is_instance_valid(target_player) and target_player.alive:
			var dist := global_position.distance_to(target_player.global_position)
			if dist <= attack_stop_distance + 20.0 or target_in_range:
				try_deal_damage()
				is_performing_attack = true


func _enemy_logic(_delta: float) -> void:
	pass


func _acquire_target() -> void:
	var player_node := get_tree().get_first_node_in_group("Player")
	if player_node is CharacterBody2D:
		target_player = player_node


func play_anim(anim_name: String) -> void:
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name:
			sprite.play(anim_name)


func try_deal_damage() -> void:
	if is_instance_valid(target_player) and target_player.alive:
		if target_player.has_method("take_damage"):
			target_player.take_damage(strength)


func _handle_footsteps(delta: float) -> void:
	if get_real_velocity().length_squared() > 100.0 and not is_performing_attack and is_alive and is_chasing:
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = step_interval
			_play_footstep()
	else:
		step_timer = 0.0


func _play_footstep() -> void:
	if is_instance_valid(footstep_audio) and footstep_audio.stream:
		footstep_audio.pitch_scale = randf_range(0.85, 1.15)
		footstep_audio.play()


# --- Sight & Chase Circle Handlers ---

func _on_sight_body_entered(body: Node2D) -> void:
	if body is Player or body.is_in_group("Player") or body.name == "Player":
		target_player = body as CharacterBody2D
		player_in_sight = true
		is_chasing = true


func _on_sight_body_exited(body: Node2D) -> void:
	if body is Player or body.is_in_group("Player") or body.name == "Player":
		player_in_sight = false
		await get_tree().create_timer(lost_target_delay).timeout
		if not is_alive or player_in_sight:
			return
		is_chasing = false


# --- Hitbox & Attack Handlers ---

func _on_hit_box_body_entered(body: Node2D) -> void:
	if (body is Player or body.is_in_group("Player") or body.name == "Player") and is_alive:
		target_player = body as CharacterBody2D
		target_in_range = true
		if attack_timer and attack_timer.is_stopped():
			attack_timer.start()


func _on_hit_box_body_exited(body: Node2D) -> void:
	if body is Player or body.is_in_group("Player") or body.name == "Player":
		target_in_range = false
		if not is_attacking_state and attack_timer:
			attack_timer.stop()


func _on_attack_timer_timeout() -> void:
	if not is_alive:
		if attack_timer:
			attack_timer.stop()
		return

	if is_instance_valid(target_player) and target_player.alive:
		var dist := global_position.distance_to(target_player.global_position)
		if dist <= attack_stop_distance + 20.0 or target_in_range:
			try_deal_damage()
			_start_attack()
		else:
			attack_timer.stop()
	elif attack_timer:
		attack_timer.stop()


func Take_damage(damage: int, attacker_position: Vector2 = Vector2.ZERO) -> void:
	if not is_alive:
		return

	health = maxi(0, health - damage)
	flash_hit()

	# Spawn independent world blood spatter scaled dynamically by damage amount
	if is_instance_valid(blood_spatter):
		var blood_copy := blood_spatter.duplicate() as CPUParticles2D
		get_tree().current_scene.add_child(blood_copy)
		blood_copy.global_position = global_position
		
		# Scale particle amount dynamically based on damage
		blood_copy.amount = clampi(int(damage * 1.5), 8, 50)
		
		blood_copy.modulate.a = 1.0
		blood_copy.restart()
		blood_copy.emitting = true
		
		# Smoothly fade out alpha and clean up when finished
		var fade_tween := create_tween()
		fade_tween.tween_interval(blood_copy.lifetime * 0.6)
		fade_tween.tween_property(blood_copy, "modulate:a", 0.0, blood_copy.lifetime * 0.4)
		fade_tween.tween_callback(blood_copy.queue_free)

	if attacker_position != Vector2.ZERO:
		var knock_dir := (global_position - attacker_position).normalized()
		knockback_velocity = knock_dir * (knockback_force * 3.5)

	if health <= 0:
		if is_instance_valid(enemy_health_bar) and enemy_health_bar.has_method("Update_health"):
			enemy_health_bar.Update_health(0)
		_die()
	else:
		if is_instance_valid(enemy_health_bar) and enemy_health_bar.has_method("Update_health"):
			enemy_health_bar.Update_health(health)
		if take_damage_sound:
			if hurt_sound:
				take_damage_sound.stream = hurt_sound
			take_damage_sound.pitch_scale = randf_range(1.0, 1.5)
			take_damage_sound.play()


func flash_hit() -> void:
	if not sprite:
		return
		
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()

	var mat := sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("flash_white", true)
		flash_tween = create_tween()
		flash_tween.tween_interval(0.15)
		flash_tween.tween_callback(func():
			if is_instance_valid(sprite) and sprite.material:
				(sprite.material as ShaderMaterial).set_shader_parameter("flash_white", false)
		)
	else:
		sprite.modulate = Color(10.0, 10.0, 10.0, 1.0)
		flash_tween = create_tween()
		flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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

	# --- DROP LOGIC ---
	# If this enemy carries the key, spawn it and guarantee NO hearts drop
	if drops_key:
		drop_key()
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


func drop_key() -> void:
	if not key_scene:
		printerr("[KEY ERROR] key_scene is not assigned in BaseEnemy!")
		return

	var key_inst = key_scene.instantiate()
	key_inst.position = global_position
	key_inst.z_index = 10

	var level_root = get_tree().root.find_child("LevelRoot", true, false)
	if level_root:
		var items_node = level_root.get_node_or_null("Items")
		if items_node:
			items_node.call_deferred("add_child", key_inst)
			return
		level_root.call_deferred("add_child", key_inst)
		return

	get_parent().call_deferred("add_child", key_inst)


func drop_item() -> void:
	if not health_pickup_scene:
		return
	var drop = health_pickup_scene.instantiate()
	drop.position = global_position
	var level_root = get_tree().root.find_child("LevelRoot", true, false)
	if level_root:
		var items_node = level_root.get_node_or_null("Items")
		if items_node:
			items_node.call_deferred("add_child", drop)
			return
		level_root.call_deferred("add_child", drop)
		return
	get_parent().call_deferred("add_child", drop)

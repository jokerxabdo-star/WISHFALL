class_name Player
extends CharacterBody2D

signal health_changed(new_health: int, max_health: int)
signal died

var SPEED: float = 700.0

@export_group("Tactical Mode Settings")
@export_range(0.1, 1.0, 0.05) var tactical_zoom_factor: float = 0.8
@export var slowmo_timescale: float = 0.1
@export var slowmo_pitch: float = 0.55
@export var teleport_ghost_spacing: float = 40.0
@export var teleport_cooldown: float = 3.0 ## Cooldown duration in seconds
@export var has_teleport: bool = false:
	set(value):
		has_teleport = value
		Player_stats.has_teleport = value
		if is_inside_tree():
			get_tree().call_group("HUD", "set_teleport_unlocked", has_teleport)

@export_group("Dash Settings")
@export var has_dash: bool = false:
	set(value):
		has_dash = value
		Player_stats.has_dash = value
		if is_inside_tree():
			get_tree().call_group("HUD", "set_dash_unlocked", has_dash)
@export var dash_speed: float = 1500.0
@export var dash_duration: float = 0.16
@export var dash_reload_cost: float = 0.35
@export var dash_damage: int = 10
@export var ghost_spawn_interval: float = 0.02
@export var ghost_scale: float = 4.0
@export var ghost_color: Color = Color(0.2, 0.75, 1.0, 0.65)
@export var dash_camera_shake: float = 5.0

@export_group("Upgrade Stat Caps & Limits")
@export var max_health_cap: int = 200
@export var max_strength_cap: int = 100
@export var max_speed_cap: float = 500.0
@export var max_dash_damage_cap: int = 150
@export var min_dash_cooldown_cap: float = 0.2
@export var min_teleport_cooldown_cap: float = 1.2
@export var min_tactical_zoom_cap: float = 0.5

@export_group("Audio Settings")
@export var step_interval: float = 0.30 ## Seconds between footsteps while running

var can_teleport: bool = true
var teleport_cooldown_timer: float = 0.0

var normal_zoom: Vector2 = Vector2(1.0, 1.0)
var is_targeting_teleport: bool = false
var camera_tween: Tween = null
var flash_tween: Tween = null

# Map Boundaries (Fallback if Camera2D limits are left at engine defaults)
const FALLBACK_MAP_MIN := Vector2(-1500.0, -1500.0)
const FALLBACK_MAP_MAX := Vector2(1500.0, 1500.0)

# Dash configuration
var can_dash: bool = true
var dash_timer: float = 0.0
var dash_reload_timer: float = 0.0
var ghost_spawn_timer: float = 0.0
var dash_dir: Vector2 = Vector2.ZERO
var enemies_hit_ids: Array[int] = []
var enemies_hit_during_attack: Array[int] = []

var Last_direction: Vector2 = Vector2.RIGHT
var Is_attacking: bool = false
var Hitbox_offset: Vector2
var alive: bool = true
var max_health: int
var health: int
var Strength: int = 20

# Footstep rhythm timer
var step_timer: float = 0.0

# Input lock flag for menus
var is_input_locked: bool = false

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var take_damage_sound: AudioStreamPlayer2D = $TakeDamage
@onready var swing_sword_sound: AudioStreamPlayer2D = $SwingSword
@onready var player_dash_sound: AudioStreamPlayer2D = $PlayerDash
@onready var slow_motion_sound: AudioStreamPlayer2D = $SlowMotion
@onready var hit_box: Area2D = $HitBox
@onready var damage_cool_down: Timer = $DamageCoolDown
@onready var camera_2d: Camera2D = $Camera2D
@onready var footstep_audio: AudioStreamPlayer2D = get_node_or_null("FootstepAudio")


func _ready() -> void:
	# Register to the Player group so enemies and HUD can find this node
	add_to_group("Player")

	# Sync inspector zoom directly into Player_stats
	Player_stats.tactical_zoom_factor = tactical_zoom_factor

	# Load all persistent stats from Player_stats
	max_health = Player_stats.max_health
	health = Player_stats.health
	Strength = Player_stats.Strength
	SPEED = Player_stats.speed
	dash_damage = Player_stats.dash_damage
	dash_reload_cost = Player_stats.dash_reload_cost
	teleport_cooldown = Player_stats.teleport_cooldown
	has_dash = Player_stats.has_dash
	has_teleport = Player_stats.has_teleport
	tactical_zoom_factor = Player_stats.tactical_zoom_factor

	Hitbox_offset = hit_box.position
	hit_box.monitoring = true
	if camera_2d:
		normal_zoom = camera_2d.zoom
			
	# Sync initial HUD visibility based on unlocked status
	get_tree().call_group("HUD", "set_teleport_unlocked", has_teleport)
	get_tree().call_group("HUD", "set_dash_unlocked", has_dash)
	
	# Initialize progress values to full
	get_tree().call_group("HUD", "update_teleport_cooldown", 1.0)
	get_tree().call_group("HUD", "update_dash_cooldown", 1.0)
	
	# Initialize HUD health bar with current and max values
	get_tree().call_group("HUD", "init_health", max_health)
	health_changed.emit(health, max_health)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	_reset_music_pitch()
		
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()
		
	get_tree().call_group("HUD", "reset_tactical_overlay")


func _reset_music_pitch() -> void:
	for music_player in get_tree().get_nodes_in_group("MusicPlayer"):
		if is_instance_valid(music_player) and "pitch_scale" in music_player:
			music_player.pitch_scale = 1.0


func lock_actions(locked: bool) -> void:
	is_input_locked = locked
	if is_input_locked:
		velocity = Vector2.ZERO
		if is_targeting_teleport:
			toggle_teleport_mode()


func _input(event: InputEvent) -> void:
	if not alive or is_input_locked:
		return
	
	if event.is_action_pressed("teleport_mode"):
		if has_teleport and (is_targeting_teleport or can_teleport):
			toggle_teleport_mode()
			get_viewport().set_input_as_handled()
		return
	
	if is_targeting_teleport:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			execute_teleport(get_global_mouse_position())
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if alive:
		if is_input_locked:
			velocity = Vector2.ZERO
			move_and_slide()
			Process_animation()
			return

		if not can_teleport and not is_targeting_teleport and has_teleport:
			teleport_cooldown_timer -= delta
			var progress_ratio := 1.0 - (teleport_cooldown_timer / teleport_cooldown)
			get_tree().call_group("HUD", "update_teleport_cooldown", progress_ratio)
			
			if teleport_cooldown_timer <= 0.0:
				teleport_cooldown_timer = 0.0
				can_teleport = true
				get_tree().call_group("HUD", "update_teleport_cooldown", 1.0)
		
		if is_targeting_teleport:
			velocity = Vector2.ZERO
			validate_and_notify_target_pos()
			move_and_slide()
			Process_animation()
			return
			
		dash_logic(delta)
		
		if dash_timer > 0.0:
			check_dash_collisions()
		else:
			if Input.is_action_just_pressed("Attack") and not Is_attacking:
				Attack()
			Process_movement()
		
		move_and_slide()
		
		# Check physical barrier collisions
		_check_barrier_bump()

		Process_animation()
		_handle_footsteps(delta)


func _check_barrier_bump() -> void:
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider:
			# 1. Exit Door / Key Barrier
			if collider.is_in_group("ExitBarrier") or collider.name == "Barrier" or collider.name == "Exit":
				get_tree().call_group("LevelController", "on_player_hit_locked_exit")
				break
			# 2. Kill Enemies First Gate
			elif collider.name == "EnemyGate" or collider.name == "EnemyBarrier" or collider.is_in_group("EnemyGates"):
				get_tree().call_group("LevelController", "on_player_hit_enemy_gate")
				break


############################Teleport_Mechanic############################
func toggle_teleport_mode() -> void:
	is_targeting_teleport = !is_targeting_teleport
	
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()
		
	camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	camera_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	
	get_tree().call_group("HUD", "set_tactical_mode", is_targeting_teleport, slowmo_timescale)
	
	if is_targeting_teleport:
		Engine.time_scale = slowmo_timescale
		slow_motion_sound.pitch_scale = randf_range(0.3, 0.5)
		slow_motion_sound.play()
		
		if camera_2d:
			camera_2d.top_level = false
			camera_2d.position = Vector2.ZERO
			var target_zoom := Vector2(tactical_zoom_factor, tactical_zoom_factor)
			camera_tween.tween_property(camera_2d, "zoom", target_zoom, 0.009 / slowmo_timescale)
			
		for music_player in get_tree().get_nodes_in_group("MusicPlayer"):
			if is_instance_valid(music_player) and "pitch_scale" in music_player:
				camera_tween.tween_property(music_player, "pitch_scale", slowmo_pitch, 0.01 / slowmo_timescale)
			
		animated_sprite_2d.modulate = Color(0.6, 0.8, 1.0, 0.85)
	else:
		Engine.time_scale = 1.0
		
		if camera_2d:
			camera_tween.tween_property(camera_2d, "zoom", normal_zoom, 0.18)
			
		for music_player in get_tree().get_nodes_in_group("MusicPlayer"):
			if is_instance_valid(music_player) and "pitch_scale" in music_player:
				camera_tween.tween_property(music_player, "pitch_scale", 1.0, 0.18)
			
		animated_sprite_2d.modulate = Color.WHITE


func validate_and_notify_target_pos() -> void:
	var mouse_pos := get_global_mouse_position()
	var bounds := get_valid_map_bounds()
	var margin := 24.0
	
	var is_in_bounds := (
		mouse_pos.x >= bounds.position.x + margin and mouse_pos.x <= bounds.end.x - margin and
		mouse_pos.y >= bounds.position.y + margin and mouse_pos.y <= bounds.end.y - margin
	)
	
	var is_valid := false
	if is_in_bounds:
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsPointQueryParameters2D.new()
		query.position = mouse_pos
		query.collision_mask = collision_mask
		query.exclude = [get_rid()]
		is_valid = space_state.intersect_point(query).size() == 0
		
	get_tree().call_group("HUD", "update_reticle_validity", is_valid)


func get_valid_map_bounds() -> Rect2:
	if camera_2d and (camera_2d.limit_left > -1000000 and camera_2d.limit_right < 1000000):
		var min_x := float(camera_2d.limit_left)
		var min_y := float(camera_2d.limit_top)
		var max_x := float(camera_2d.limit_right)
		var max_y := float(camera_2d.limit_bottom)
		return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
	
	return Rect2(FALLBACK_MAP_MIN, FALLBACK_MAP_MAX - FALLBACK_MAP_MIN)


func execute_teleport(target_world_pos: Vector2) -> void:
	var bounds := get_valid_map_bounds()
	var margin := 16.0
	
	var clamped_pos := Vector2(
		clamp(target_world_pos.x, bounds.position.x + margin, bounds.end.x - margin),
		clamp(target_world_pos.y, bounds.position.y + margin, bounds.end.y - margin)
	)
	
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = clamped_pos
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var excludes: Array[RID] = [get_rid()]
	if is_instance_valid(hit_box):
		excludes.append(hit_box.get_rid())
	query.exclude = excludes
	
	var collision_hits := space_state.intersect_point(query)
	if collision_hits.size() > 0:
		print("Teleport blocked by: ", collision_hits[0].collider.name, " (Type: ", collision_hits[0].collider.get_class(), ")")
		return

	var start_pos := global_position
	spawn_teleport_ghost_line(start_pos, clamped_pos)
	
	global_position = clamped_pos
	velocity = Vector2.ZERO
	spawn_ghost_trail()
	
	can_teleport = false
	teleport_cooldown_timer = teleport_cooldown
	get_tree().call_group("HUD", "update_teleport_cooldown", 0.0)
	
	is_targeting_teleport = false
	Engine.time_scale = 1.0
	
	get_tree().call_group("HUD", "set_tactical_mode", false, slowmo_timescale)
	
	if camera_tween and camera_tween.is_valid():
		camera_tween.kill()
	camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	if camera_2d:
		camera_tween.tween_property(camera_2d, "zoom", normal_zoom, 0.15)
		
	for music_player in get_tree().get_nodes_in_group("MusicPlayer"):
		if is_instance_valid(music_player) and "pitch_scale" in music_player:
			camera_tween.tween_property(music_player, "pitch_scale", 1.0, 0.15)
		
	animated_sprite_2d.modulate = Color.WHITE


func spawn_teleport_ghost_line(from_pos: Vector2, to_pos: Vector2) -> void:
	var dist := from_pos.distance_to(to_pos)
	var steps := int(dist / teleport_ghost_spacing)
	steps = clamp(steps, 2, 25)
	
	var current_anim: StringName = animated_sprite_2d.animation
	var current_frame: int = animated_sprite_2d.frame
	var frame_tex := animated_sprite_2d.sprite_frames.get_frame_texture(current_anim, current_frame)
	
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var spawn_pos: Vector2 = from_pos.lerp(to_pos, t)
		
		var ghost := Sprite2D.new()
		ghost.texture = frame_tex
		ghost.flip_h = animated_sprite_2d.flip_h
		ghost.scale = animated_sprite_2d.scale * ghost_scale
		ghost.global_position = spawn_pos
		ghost.z_index = z_index - 1
		
		ghost.modulate = Color(0.5, 0.4, 1.0, lerp(0.3, 0.7, t))
		get_parent().add_child(ghost)
		
		var tween := create_tween()
		tween.tween_property(ghost, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(ghost.queue_free)
############################Teleport_Mechanic############################


############################Dash_Logic############################
func dash_logic(delta: float) -> void:
	var move_input := Input.get_vector("Left", "Right", "Up", "Down")
	
	if has_dash and can_dash and Input.is_action_just_pressed("Dash") and not Is_attacking and move_input != Vector2.ZERO:
		can_dash = false
		dash_timer = dash_duration
		dash_reload_timer = dash_reload_cost
		ghost_spawn_timer = 0.0
		enemies_hit_ids.clear()
		
		get_tree().call_group("HUD", "update_dash_cooldown", 0.0)
		
		dash_dir = move_input.normalized()
		Last_direction = dash_dir
		velocity = dash_dir * dash_speed
		player_dash_sound.pitch_scale = randf_range(2.0, 3.3)
		player_dash_sound.play()
		
		apply_camera_shake(dash_camera_shake)
		trigger_dash_juice(dash_dir)
		spawn_ghost_trail()
		check_dash_collisions()
		return
	
	if dash_timer > 0.0:
		dash_timer -= delta
		
		var speed_factor: float = clampf(dash_timer / dash_duration, 0.0, 1.0)
		velocity = dash_dir * lerpf(SPEED, dash_speed, speed_factor)
		
		ghost_spawn_timer -= delta
		if ghost_spawn_timer <= 0.0:
			spawn_ghost_trail()
			ghost_spawn_timer = ghost_spawn_interval
		
		if dash_timer <= 0.0:
			dash_timer = 0.0
			enemies_hit_ids.clear()
			animated_sprite_2d.speed_scale = 1.0
			animated_sprite_2d.scale = Vector2.ONE
	else:
		if dash_reload_timer > 0.0:
			dash_reload_timer -= delta
			
			var progress_ratio := 1.0 - (dash_reload_timer / dash_reload_cost)
			get_tree().call_group("HUD", "update_dash_cooldown", progress_ratio)
			
			if dash_reload_timer <= 0.0:
				dash_reload_timer = 0.0
				can_dash = true
				get_tree().call_group("HUD", "update_dash_cooldown", 1.0)
############################Dash_Logic############################


func check_dash_collisions() -> void:
	var bodies := hit_box.get_overlapping_bodies()
	for body in bodies:
		if is_instance_valid(body) and body is BaseEnemy:
			var body_id := body.get_instance_id()
			if not enemies_hit_ids.has(body_id):
				enemies_hit_ids.append(body_id)
				if body.has_method("Take_damage"):
					body.Take_damage(dash_damage, position)
					apply_camera_shake(dash_camera_shake * 1.5)


func trigger_dash_juice(dir: Vector2) -> void:
	animated_sprite_2d.speed_scale = 2.4
	
	var tween := create_tween()
	var stretch_x: float = lerpf(0.7, 1.45, abs(dir.x))
	var stretch_y: float = lerpf(0.7, 1.45, abs(dir.y))
	var stretch := Vector2(stretch_x, stretch_y)
	
	tween.tween_property(animated_sprite_2d, "scale", stretch, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(animated_sprite_2d, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func apply_camera_shake(intensity: float) -> void:
	if not camera_2d:
		return
	var shake_tween := create_tween()
	var offset1 := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
	var offset2 := Vector2(randf_range(-intensity * 0.5, intensity * 0.5), randf_range(-intensity * 0.5, intensity * 0.5))
	
	shake_tween.tween_property(camera_2d, "offset", offset1, 0.03)
	shake_tween.tween_property(camera_2d, "offset", offset2, 0.04)
	shake_tween.tween_property(camera_2d, "offset", Vector2.ZERO, 0.04)


func spawn_ghost_trail() -> void:
	var ghost := Sprite2D.new()
	
	var current_anim: StringName = animated_sprite_2d.animation
	var current_frame: int = animated_sprite_2d.frame
	ghost.texture = animated_sprite_2d.sprite_frames.get_frame_texture(current_anim, current_frame)
	ghost.flip_h = animated_sprite_2d.flip_h
	
	ghost.scale = animated_sprite_2d.scale * ghost_scale
	ghost.global_position = animated_sprite_2d.global_position
	ghost.z_index = z_index - 1
	
	ghost.modulate = ghost_color
	get_parent().add_child(ghost)
	
	var tween := create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ghost.queue_free)


############################Player_Footsteps############################
func _handle_footsteps(delta: float) -> void:
	var actual_speed_sq := get_real_velocity().length_squared()
	
	if actual_speed_sq > 100.0 and dash_timer <= 0.0 and not Is_attacking and not is_targeting_teleport:
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = step_interval
			_play_footstep()
	else:
		step_timer = 0.0


func _play_footstep() -> void:
	if is_instance_valid(footstep_audio) and footstep_audio.stream:
		footstep_audio.pitch_scale = randf_range(0.92, 1.08)
		footstep_audio.play()
############################Player_Footsteps############################


############################Player_Movement############################
func Process_movement() -> void:
	var direction := Input.get_vector("Left", "Right", "Up", "Down")
	
	if direction != Vector2.ZERO:
		velocity = direction * SPEED
		Last_direction = direction
	else:
		velocity = Vector2.ZERO
############################Player_Movement############################


###########################Player_Animations###########################
func Process_animation() -> void:
	if Is_attacking:
		return

	var actual_speed_sq := get_real_velocity().length_squared()
	if actual_speed_sq > 100.0:
		Play_animation("Run", Last_direction)
	else:
		Play_animation("Idle", Last_direction)


func Play_animation(prefix: String, dir: Vector2) -> void:
	var x := Hitbox_offset.x
	var y := Hitbox_offset.y
	var anim_to_play := ""
	
	if abs(dir.x) >= abs(dir.y):
		anim_to_play = prefix + "_Right"
		if dir.x < 0:
			animated_sprite_2d.flip_h = true
			hit_box.position = Vector2(-x + 12, y)
		elif dir.x > 0:
			animated_sprite_2d.flip_h = false
			hit_box.position = Vector2(x, y)
	else:
		if dir.y > 0:
			anim_to_play = prefix + "_Down"
			hit_box.position = Vector2(-y, x - 13)
		elif dir.y < 0:
			anim_to_play = prefix + "_Up"
			hit_box.position = Vector2(-y, -x)

	if animated_sprite_2d.animation != anim_to_play or not animated_sprite_2d.is_playing():
		animated_sprite_2d.play(anim_to_play)


func _on_animated_sprite_2d_animation_finished() -> void:
	if Is_attacking:
		Is_attacking = false
		enemies_hit_during_attack.clear()
###########################Player_Animations###########################


#############################Player_Attack & Hitbox#############################
func Attack() -> void:
	Is_attacking = true
	enemies_hit_during_attack.clear()
	swing_sword_sound.pitch_scale = randf_range(2.0, 3.3)
	swing_sword_sound.play()
	Play_animation("Attack", Last_direction)
	check_attack_collisions()


func check_attack_collisions() -> void:
	var bodies := hit_box.get_overlapping_bodies()
	for body in bodies:
		damage_enemy_with_sword(body)


func damage_enemy_with_sword(body: Node2D) -> void:
	if not Is_attacking:
		return
	if is_instance_valid(body) and body is BaseEnemy:
		var body_id := body.get_instance_id()
		if not enemies_hit_during_attack.has(body_id):
			enemies_hit_during_attack.append(body_id)
			if body.has_method("Take_damage"):
				body.Take_damage(Strength, position)


func _on_hit_box_body_entered(body: Node2D) -> void:
	if not (is_instance_valid(body) and body is BaseEnemy):
		return
	
	if dash_timer > 0.0:
		var body_id := body.get_instance_id()
		if not enemies_hit_ids.has(body_id):
			enemies_hit_ids.append(body_id)
			if body.has_method("Take_damage"):
				body.Take_damage(dash_damage, position)
				apply_camera_shake(dash_camera_shake * 1.5)
	elif Is_attacking:
		damage_enemy_with_sword(body)
#############################Player_Attack & Hitbox#############################


#############################Player_Health#############################
func heal(amount: int) -> void:
	health = mini(max_health, health + amount)
	Player_stats.health = health
	health_changed.emit(health, max_health)


func take_damage(amount: int) -> void:
	if dash_timer > 0.0 or is_targeting_teleport:
		return
		
	if alive:
		if damage_cool_down.time_left > 0:
			return
		health = maxi(0, health - amount)
		take_damage_sound.pitch_scale = randf_range(0.9, 1.1)
		take_damage_sound.play()
		Player_stats.health = health
		health_changed.emit(health, max_health)
		
		flash_hit()
		
		if health <= 0:
			die()
		damage_cool_down.start()


func flash_hit() -> void:
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
		
	var mat := animated_sprite_2d.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("flash_red", true)
		flash_tween = create_tween()
		flash_tween.tween_interval(0.12)
		flash_tween.tween_callback(func():
			if is_instance_valid(animated_sprite_2d) and animated_sprite_2d.material:
				(animated_sprite_2d.material as ShaderMaterial).set_shader_parameter("flash_red", false)
		)
	else:
		animated_sprite_2d.modulate = Color(3.0, 0.3, 0.3, 1.0)
		flash_tween = create_tween()
		flash_tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
#############################Player_Health#############################


#############################Upgrade_Receiver#############################
func is_upgrade_maxed(upgrade_id: String) -> bool:
	match upgrade_id:
		"more_max_health":
			return max_health >= max_health_cap
		"player_strength":
			return Strength >= max_strength_cap
		"dash_strength":
			return dash_damage >= max_dash_damage_cap
		"increase_speed":
			return SPEED >= max_speed_cap
		"dash_cooldown":
			return dash_reload_cost <= min_dash_cooldown_cap
		"teleport_cooldown":
			return teleport_cooldown <= min_teleport_cooldown_cap
		"teleport_coverage":
			return tactical_zoom_factor <= min_tactical_zoom_cap
	return false


func apply_upgrade(upgrade: Dictionary) -> void:
	match upgrade.get("id", ""):
		"player_strength":
			Strength = mini(max_strength_cap, Strength + 10)
			Player_stats.Strength = Strength
			
		"more_max_health":
			max_health = mini(max_health_cap, max_health + 25)
			Player_stats.max_health = max_health
			get_tree().call_group("HUD", "init_health", max_health)
			heal(25)
			
		"dash_strength":
			dash_damage = mini(max_dash_damage_cap, dash_damage + 10)
			Player_stats.dash_damage = dash_damage
			
		"increase_speed":
			SPEED = minf(max_speed_cap, SPEED + 35.0)
			Player_stats.speed = SPEED
			
		"heal_50":
			heal(50)
			
		"get_dash":
			has_dash = true
			Player_stats.has_dash = true
			
		"get_teleport":
			has_teleport = true
			Player_stats.has_teleport = true
			
		"dash_cooldown":
			dash_reload_cost = maxf(min_dash_cooldown_cap, dash_reload_cost * 0.75)
			Player_stats.dash_reload_cost = dash_reload_cost
			
		"teleport_cooldown":
			teleport_cooldown = maxf(min_teleport_cooldown_cap, teleport_cooldown - 0.75)
			Player_stats.teleport_cooldown = teleport_cooldown
			
		"teleport_coverage":
			tactical_zoom_factor = maxf(min_tactical_zoom_cap, tactical_zoom_factor - 0.1)
			Player_stats.tactical_zoom_factor = tactical_zoom_factor
#############################Upgrade_Receiver#############################


#############################Player_Death#############################
func die() -> void:
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	if animated_sprite_2d.material is ShaderMaterial:
		(animated_sprite_2d.material as ShaderMaterial).set_shader_parameter("flash_red", false)
	animated_sprite_2d.modulate = Color.WHITE

	Engine.time_scale = 1.0
	get_tree().call_group("HUD", "set_tactical_mode", false, slowmo_timescale)
	_reset_music_pitch()
	animated_sprite_2d.play("Die")
	alive = false
	await animated_sprite_2d.animation_finished
	died.emit()
#############################Player_Death#############################

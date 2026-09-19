extends Node2D

@export var upgrade_popup_delay: float = 0.5

@export_group("Exit Visuals")
@export var exit_open_texture: Texture2D = preload("res://Assets/Images/Opened Door.png")

@onready var hud: CanvasLayer = $HUD
@onready var level_root: Node2D = $LevelRoot

var upgrade_menu_scene = preload("res://Scenes/upgrade_menu.tscn")
var upgrade_menu: CanvasLayer = null

var level: int = 2
var current_level_root: Node = null
var current_player: CharacterBody2D = null

var enemies_killed: int = 0
const KILLS_PER_UPGRADE: int = 2
var pending_upgrades: int = 0

# --- EXACT ENEMY TARGET TRACKING ---
var total_enemies: int = 0
var target_kills_to_open: int = 0
var current_kills: int = 0

# Exit references
var exit_node: Area2D = null
var exit_barrier_shape: CollisionShape2D = null
var exit_sprite: Sprite2D = null
var exit_prompt_label: Label = null
var prompt_tween: Tween = null

# Enemy-Gated Barrier references
var enemy_gate_node: Node2D = null
var enemy_gate_label: Label = null
var enemy_gate_tween: Tween = null

var has_collected_key: bool = false


func _ready() -> void:
	add_to_group("LevelController")

	upgrade_menu = upgrade_menu_scene.instantiate()
	add_child(upgrade_menu)
	upgrade_menu.upgrade_selected.connect(_on_upgrade_selected)
	upgrade_menu.menu_timed_out.connect(_on_upgrade_closed)

	current_level_root = get_node_or_null("LevelRoot")
	_load_level(level)
	await hud.fade(0.0)


#####################LEVEL MANAGEMENT#####################
func _load_level(level_number: int) -> void:
	if hud.has_method("reset_tactical_overlay"):
		hud.reset_tactical_overlay()
	
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# When player exceeds final level, trigger game over and return to Start Menu
	if level >= 3:
		var game_over_label = hud.get_node_or_null("GameOver")
		if game_over_label:
			var tween = create_tween()
			tween.tween_property(game_over_label, "visible_ratio", 1.0, 1.0)
			tween.tween_interval(1.5)
			tween.tween_property(game_over_label, "visible_ratio", 0.0, 1.0)
			await tween.finished
		
		# Fade out and return to the Start Menu scene
		await hud.fade(1.0)
		get_tree().change_scene_to_file("res://Scenes/start_menu.tscn")
		return
		
	if current_level_root:
		current_level_root.queue_free()
		current_level_root = null
		
	var file_path = "res://Scenes/folder levels/level_%s.tscn" % level_number
	current_level_root = load(file_path).instantiate()
	add_child(current_level_root)
	current_level_root.name = "LevelRoot"

	# Wait for physics and scene tree to fully register all children
	await get_tree().physics_frame
	await get_tree().process_frame
	
	_setup_level(current_level_root)
	await hud.fade(0.0)


func _setup_level(level_node: Node) -> void:
	has_collected_key = false
	current_kills = 0

	# 1. Setup Player
	current_player = level_node.find_child("Player", true, false) as CharacterBody2D
	if current_player:
		hud.set_player(current_player)
		if not current_player.died.is_connected(_on_player_died):
			current_player.died.connect(_on_player_died)
	
	# 2. Setup Audio
	_setup_level_music(level_node)

	# 3. Setup Exit Door
	exit_node = level_node.find_child("Exit", true, false) as Area2D
	if exit_node:
		if not exit_node.body_entered.is_connected(_on_exit_body_entered):
			exit_node.body_entered.connect(_on_exit_body_entered)
		
		exit_sprite = exit_node.get_node_or_null("Sprite2D")
		if not exit_sprite:
			exit_sprite = exit_node.find_child("*", true, false) as Sprite2D

		exit_prompt_label = exit_node.find_child("PromptLabel", true, false) as Label
		if not exit_prompt_label:
			exit_prompt_label = Label.new()
			exit_prompt_label.name = "PromptLabel"
			exit_prompt_label.text = "Needs a key"
			exit_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			exit_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			exit_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
			exit_prompt_label.add_theme_font_size_override("font_size", 16)
			exit_node.add_child(exit_prompt_label)

		exit_prompt_label.position = Vector2(-40, -45)
		exit_prompt_label.modulate.a = 0.0
		exit_prompt_label.z_index = 100

		exit_barrier_shape = null
		var barrier_node = exit_node.find_child("Barrier", true, false)
		if barrier_node:
			exit_barrier_shape = barrier_node.find_child("*", true, false) as CollisionShape2D
		
		# Connect TriggerZone signals for proximity text display when closed
		var trigger_zone = exit_node.find_child("TriggerZone", true, false) as Area2D
		if trigger_zone:
			if not trigger_zone.body_entered.is_connected(_on_exit_trigger_body_entered):
				trigger_zone.body_entered.connect(_on_exit_trigger_body_entered)
			if not trigger_zone.body_exited.is_connected(_on_exit_trigger_body_exited):
				trigger_zone.body_exited.connect(_on_exit_trigger_body_exited)

		_lock_exit()

	# 4. Automatically find the Enemy Barrier / Gate inside the level scene
	_setup_enemy_gate(level_node)
		
	# 5. Calculate total enemies and hook death signals
	_hook_level_enemies(level_node)

	# 6. Show the How-To-Play tutorial overlay at the start of the level
	_show_how_to_play_overlay()


func _show_how_to_play_overlay() -> void:
	var tutorial_layer = CanvasLayer.new()
	tutorial_layer.layer = 120
	add_child(tutorial_layer)

	var texture_rect = TextureRect.new()
	
	# Adjust this path if your controls/tutorial image is in a different folder
	var tut_texture = load("res://Assets/Images/UI/Tutorial.png")
	if tut_texture:
		texture_rect.texture = tut_texture
	
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_layer.add_child(texture_rect)

	# Start invisible, fade in, hold for 5 seconds, fade out, then queue_free
	texture_rect.modulate.a = 0.0

	var tween = create_tween()
	tween.tween_property(texture_rect, "modulate:a", 1.0, 0.6)
	tween.tween_interval(5.0)
	tween.tween_property(texture_rect, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func(): tutorial_layer.queue_free())


func _setup_enemy_gate(level_node: Node) -> void:
	enemy_gate_node = null
	enemy_gate_label = null

	for node_name in ["EnemyGate", "EnemyBarrier", "KillGate", "Barrier2", "ObjectiveGate", "Gate", "ObjectiveBarrier"]:
		var candidate = level_node.find_child(node_name, true, false)
		if candidate:
			enemy_gate_node = candidate as Node2D
			break

	if is_instance_valid(enemy_gate_node):
		print("[GATE ATTACHED] Found barrier node in level: ", enemy_gate_node.name)
		enemy_gate_label = enemy_gate_node.find_child("EnemyGatePrompt", true, false) as Label
		if not enemy_gate_label:
			enemy_gate_label = Label.new()
			enemy_gate_label.name = "EnemyGatePrompt"
			enemy_gate_label.text = "Kill the Enemies First"
			enemy_gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			enemy_gate_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			enemy_gate_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
			enemy_gate_label.add_theme_font_size_override("font_size", 16)
			enemy_gate_node.add_child(enemy_gate_label)

		enemy_gate_label.position = Vector2(-75, -45)
		enemy_gate_label.modulate.a = 0.0
		enemy_gate_label.z_index = 100
	else:
		printerr("[GATE WARNING] No gate found in level scene! Check your barrier node name.")


func _hook_level_enemies(root: Node) -> void:
	total_enemies = 0
	current_kills = 0

	var all_nodes = root.find_children("*", "", true, false)
	for node in all_nodes:
		if node is BaseEnemy or node.is_in_group("Enemies"):
			if node.has_signal("enemy_died"):
				total_enemies += 1
				if not node.enemy_died.is_connected(_on_enemy_killed):
					node.enemy_died.connect(_on_enemy_killed)

	target_kills_to_open = maxi(1, total_enemies - 1)

	print("====================================")
	print("LEVEL ENEMY SETUP COMPLETE")
	print("Total enemies counted: ", total_enemies)
	print("Kills required to destroy gate: ", target_kills_to_open)
	print("====================================")


func _setup_level_music(level_node: Node) -> void:
	var music_node: Node = level_node.find_child("BG Music", true, false)
	if not is_instance_valid(music_node):
		return

	music_node.add_to_group("MusicPlayer")

	if music_node is AudioStreamPlayer2D:
		music_node.max_distance = 0.0
		music_node.attenuation = 0.0

	var bus_name: String = music_node.bus if "bus" in music_node else "Master"
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		AudioServer.set_bus_mute(bus_idx, false)
		if AudioServer.get_bus_volume_db(bus_idx) <= -70.0:
			AudioServer.set_bus_volume_db(bus_idx, 0.0)

	if music_node.has_signal("finished"):
		music_node.finished.connect(func():
			if is_instance_valid(music_node) and "play" in music_node:
				music_node.play()
		)

	if "playing" in music_node and not music_node.playing:
		music_node.play()


func _lock_exit() -> void:
	if is_instance_valid(exit_node):
		exit_node.modulate = Color.WHITE

	if is_instance_valid(exit_barrier_shape):
		exit_barrier_shape.set_deferred("disabled", false)


func _unlock_exit() -> void:
	if is_instance_valid(exit_sprite) and exit_open_texture:
		exit_sprite.texture = exit_open_texture

	if is_instance_valid(exit_prompt_label):
		if prompt_tween and prompt_tween.is_valid():
			prompt_tween.kill()
		exit_prompt_label.modulate.a = 0.0

	if is_instance_valid(exit_barrier_shape):
		exit_barrier_shape.set_deferred("disabled", true)


func _show_enemy_gate_prompt() -> void:
	if not is_instance_valid(enemy_gate_label):
		return

	if enemy_gate_tween and enemy_gate_tween.is_valid():
		enemy_gate_tween.kill()

	enemy_gate_label.modulate.a = 0.0
	enemy_gate_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	enemy_gate_tween.tween_property(enemy_gate_label, "modulate:a", 1.0, 0.12)
	enemy_gate_tween.tween_interval(1.1)
	enemy_gate_tween.tween_property(enemy_gate_label, "modulate:a", 0.0, 0.35)


func _destroy_enemy_gate() -> void:
	if not is_instance_valid(enemy_gate_node):
		return

	print("[SUCCESS] Target reached! Destroying gate collider.")
	var gate_to_free = enemy_gate_node
	enemy_gate_node = null

	if gate_to_free is CollisionShape2D:
		gate_to_free.set_deferred("disabled", true)

	for shape in gate_to_free.find_children("*", "CollisionShape2D", true, false):
		if shape is CollisionShape2D:
			shape.set_deferred("disabled", true)

	if gate_to_free is CollisionObject2D:
		gate_to_free.set_deferred("collision_layer", 0)
		gate_to_free.set_deferred("collision_mask", 0)

	gate_to_free.queue_free()
#####################LEVEL MANAGEMENT#####################


######################SIGNAL HANDLER######################
func on_key_collected() -> void:
	has_collected_key = true
	_unlock_exit()


# TriggerZone proximity handlers for the closed door text
func _on_exit_trigger_body_entered(body: Node2D) -> void:
	if (body.name == "Player" or body.is_in_group("Player")) and not has_collected_key:
		if is_instance_valid(exit_prompt_label):
			if prompt_tween and prompt_tween.is_valid():
				prompt_tween.kill()
			prompt_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			prompt_tween.tween_property(exit_prompt_label, "modulate:a", 1.0, 0.15)


func _on_exit_trigger_body_exited(body: Node2D) -> void:
	if body.name == "Player" or body.is_in_group("Player"):
		if is_instance_valid(exit_prompt_label):
			if prompt_tween and prompt_tween.is_valid():
				prompt_tween.kill()
			prompt_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			prompt_tween.tween_property(exit_prompt_label, "modulate:a", 0.0, 0.15)


func on_player_hit_locked_exit() -> void:
	pass # Handled by TriggerZone proximity


func on_player_hit_enemy_gate() -> void:
	if current_kills < target_kills_to_open:
		_show_enemy_gate_prompt()


func _on_enemy_killed() -> void:
	if not is_instance_valid(current_player) or not current_player.alive:
		return

	current_kills += 1
	print("Kills progress: %s / %s" % [current_kills, target_kills_to_open])

	if current_kills >= target_kills_to_open:
		_destroy_enemy_gate()

	enemies_killed += 1
	if enemies_killed % KILLS_PER_UPGRADE == 0:
		pending_upgrades += 1
		
		if upgrade_menu and upgrade_menu.is_active:
			return

		await get_tree().create_timer(upgrade_popup_delay).timeout
		
		if is_instance_valid(current_player) and current_player.alive:
			_check_and_show_next_upgrade()


func _check_and_show_next_upgrade() -> void:
	if pending_upgrades <= 0:
		return
		
	if not is_instance_valid(current_player) or not current_player.alive:
		pending_upgrades = 0
		return

	if upgrade_menu and not upgrade_menu.is_active:
		pending_upgrades -= 1
		upgrade_menu.open_menu(current_player)


func _on_upgrade_selected(upgrade_data: Dictionary) -> void:
	if is_instance_valid(current_player) and current_player.has_method("apply_upgrade"):
		current_player.apply_upgrade(upgrade_data)
	_on_upgrade_closed()


func _on_upgrade_closed() -> void:
	if pending_upgrades > 0 and is_instance_valid(current_player) and current_player.alive:
		await get_tree().create_timer(0.2).timeout
		_check_and_show_next_upgrade()


func _on_exit_body_entered(body: Node2D) -> void:
	if body.name == "Player" or body.is_in_group("Player"):
		if not has_collected_key:
			return

		if upgrade_menu and upgrade_menu.is_active:
			upgrade_menu._close_menu()
			
		if "is_targeting_teleport" in body and body.is_targeting_teleport:
			body.toggle_teleport_mode()
			
		level += 1
		await hud.fade(1.0)
		call_deferred("_load_level", level)


func _on_player_died() -> void:
	pending_upgrades = 0
	if upgrade_menu:
		upgrade_menu._close_menu()
	
	Engine.time_scale = 1.0

	await get_tree().create_timer(1.0).timeout
	await hud.fade(1.0)
	enemies_killed = 0
	Player_stats.reset()
	_load_level(level)
	await hud.fade(0.0)
######################SIGNAL HANDLER######################

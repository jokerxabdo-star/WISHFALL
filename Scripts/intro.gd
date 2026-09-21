extends Control

@export_file("*.tscn") var main_menu_scene: String = "res://Scenes/start_menu.tscn"

@onready var team_logo: PanelContainer = $VBoxContainer/PanelContainer
@onready var represents_label: Label = $VBoxContainer/Represents
@onready var game_label: Label = $"VBoxContainer2/Game Label" 
@onready var created_for_label: Label = $VBoxContainer2/CreatedFor

# Audio nodes (Make sure you have two AudioStreamPlayer child nodes named LogoSound and LabelSound)
@onready var logo_sound: AudioStreamPlayer = $LogoSound
@onready var label_sound: AudioStreamPlayer = $LabelSound


func _ready() -> void:
	# Hide everything at startup
	if team_logo: team_logo.modulate.a = 0.0
	if represents_label: represents_label.modulate.a = 0.0
	
	if game_label:
		game_label.visible = false
		game_label.modulate.a = 0.0
		
	if created_for_label:
		created_for_label.visible = false
		created_for_label.modulate.a = 0.0
		
	play_intro_sequence()


func play_intro_sequence() -> void:
	# ==========================================
	# SECTION 1: Team Logo & Represents
	# ==========================================
	
	# Play the logo sound effect
	if logo_sound:
		logo_sound.play()
	
	# 1. Fade in Logo
	if team_logo:
		var t_logo = create_tween()
		t_logo.tween_property(team_logo, "modulate:a", 1.0, 1.0)
		await t_logo.finished
	
	# Short gap between logo and text
	await get_tree().create_timer(0.5).timeout
	
	# 2. Fade in "Represents..."
	if represents_label:
		var t_rep = create_tween()
		t_rep.tween_property(represents_label, "modulate:a", 1.0, 1.0)
		await t_rep.finished
	
	# 🌟 LINGER TIME: How long both stay visible before starting to fade out
	await get_tree().create_timer(3.0).timeout
	
	# 3. Fade out both together
	if team_logo and represents_label:
		var t_out1 = create_tween()
		t_out1.parallel().tween_property(team_logo, "modulate:a", 0.0, 1.0)
		t_out1.parallel().tween_property(represents_label, "modulate:a", 0.0, 1.0)
		await t_out1.finished
	
	# Pause between sections
	await get_tree().create_timer(0.3).timeout
	
	# ==========================================
	# SECTION 2: Game Label & Created For
	# ==========================================
	
	# Make Section 2 visible
	if game_label:
		game_label.visible = true
		game_label.modulate.a = 0.0
	if created_for_label:
		created_for_label.visible = true
		created_for_label.modulate.a = 0.0
	
	# Play the label/game sound effect
	if label_sound:
		label_sound.play()
	
	# 4. Fade in Game Label
	if game_label:
		var t_game = create_tween()
		t_game.tween_property(game_label, "modulate:a", 1.0, 1.0)
		await t_game.finished
	
	# Short gap between game label and credit
	await get_tree().create_timer(.8).timeout
	
	# 5. Fade in "Created for..."
	if created_for_label:
		var t_created = create_tween()
		t_created.tween_property(created_for_label, "modulate:a", 1.0, 1.0)
		await t_created.finished
	
	# 🌟 LINGER TIME: How long both stay visible before the final fade out
	await get_tree().create_timer(5.0).timeout
	
	# 6. Fade out both together
	if game_label and created_for_label:
		var t_out2 = create_tween()
		t_out2.parallel().tween_property(game_label, "modulate:a", 0.0, 1.0)
		t_out2.parallel().tween_property(created_for_label, "modulate:a", 0.0, 1.0)
		await t_out2.finished
		
	# --- TRANSITION TO MENU ---
	_on_intro_finished()


func _input(event: InputEvent) -> void:
	# Keyboard keys only (mouse clicks will not skip)
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_on_intro_finished()


func _on_intro_finished() -> void:
	get_tree().change_scene_to_file(main_menu_scene)

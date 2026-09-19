extends Control

@onready var play_button: Button = $TextureRect/VBoxContainer/PlayButton
@onready var developers_button: Button = $TextureRect/VBoxContainer/DevelopersButton
@onready var quit_button: Button = $TextureRect/VBoxContainer/QuitButton

# Backgrounds and UI containers
@onready var main_menu_bg: TextureRect = $TextureRect      # Main menu frame background
@onready var main_menu_buttons: VBoxContainer = $TextureRect/VBoxContainer # Main buttons container

@onready var developers_bg: TextureRect = $TextureRect2    # Developers background image
@onready var vbox_container: VBoxContainer = $TextureRect2/VBoxContainer
@onready var back_button: Button = $TextureRect2/BackButton

# Audio players
@onready var menu_audio: AudioStreamPlayer = $MenuAudio       # For UI click/hover sounds
@onready var bgm_player: AudioStreamPlayer = $BGMPlayer       # Dedicated audio player for background music

# Optional fade overlay (if you added a full-screen black ColorRect on top of your StartMenu scene)
@onready var fade_overlay: ColorRect = $FadeOverlay

# Load your sound effects and background music
var hover_sound = preload("res://Assets/Audios/UI Click.wav")
var click_sound = preload("res://Assets/Audios/UI Hover.wav")

var is_transitioning: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Ensure developers background and back button start hidden
	if is_instance_valid(developers_bg):
		developers_bg.modulate.a = 0.0
	if is_instance_valid(back_button):
		back_button.visible = false
		back_button.modulate.a = 0.0
		
	# Fade in the actual scene when it first loads up
	if is_instance_valid(fade_overlay):
		fade_overlay.visible = true
		fade_overlay.modulate.a = 1.0
		var intro_tween = create_tween()
		intro_tween.tween_property(fade_overlay, "modulate:a", 0.0, 0.8)
		await intro_tween.finished
		fade_overlay.visible = false
	
	# Connect buttons and sound triggers
	_setup_button_sounds(play_button)
	_setup_button_sounds(developers_button)
	_setup_button_sounds(quit_button)
	_setup_button_sounds(back_button)
	
	if play_button:
		play_button.pressed.connect(_on_play_pressed)
	if developers_button:
		developers_button.pressed.connect(_on_developers_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	# --- BACKGROUND MUSIC FADE IN ---
	if is_instance_valid(bgm_player) and bgm_player.stream:
		bgm_player.volume_db = -80.0 # Start completely silent
		bgm_player.play()
		
		var bgm_tween = create_tween()
		bgm_tween.tween_property(bgm_player, "volume_db", 0.0, 1.5)


# Helper function to automatically add hover and click sounds to any button
func _setup_button_sounds(button: Button) -> void:
	if not is_instance_valid(button):
		return
		
	button.mouse_entered.connect(func():
		if hover_sound and is_instance_valid(menu_audio):
			menu_audio.stream = hover_sound
			menu_audio.play()
	)
	
	button.pressed.connect(func():
		if click_sound and is_instance_valid(menu_audio):
			menu_audio.stream = click_sound
			menu_audio.play()
	)


func _on_play_pressed() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	
	# Fade out background music and screen fade-out simultaneously
	var fade_tween = create_tween().set_parallel(true)
	
	if is_instance_valid(bgm_player) and bgm_player.playing:
		fade_tween.tween_property(bgm_player, "volume_db", -80.0, 0.8)
		
	if is_instance_valid(fade_overlay):
		fade_overlay.visible = true
		fade_overlay.modulate.a = 0.0
		fade_tween.tween_property(fade_overlay, "modulate:a", 1.0, 0.8)
		
	await fade_tween.finished
	get_tree().change_scene_to_file("res://Scenes/main.tscn")


func _on_developers_pressed() -> void:
	if is_transitioning or not is_instance_valid(main_menu_bg) or not is_instance_valid(developers_bg):
		return
		
	is_transitioning = true
	
	if is_instance_valid(main_menu_buttons):
		main_menu_buttons.visible = false
	
	if is_instance_valid(vbox_container):
		vbox_container.visible = true
		vbox_container.modulate.a = 0.0
	
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(main_menu_bg, "modulate:a", 0.0, 0.6)
	tween.tween_property(developers_bg, "modulate:a", 1.0, 0.6)
	
	if is_instance_valid(vbox_container):
		tween.tween_property(vbox_container, "modulate:a", 1.0, 0.6)
	
	await tween.finished
	
	if is_instance_valid(back_button):
		back_button.visible = true
		var back_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		back_tween.tween_property(back_button, "modulate:a", 1.0, 0.3)
		
	is_transitioning = false


func _on_back_pressed() -> void:
	if is_transitioning or not is_instance_valid(main_menu_bg) or not is_instance_valid(developers_bg):
		return
		
	is_transitioning = true
	
	if is_instance_valid(vbox_container):
		vbox_container.visible = false
	
	if is_instance_valid(back_button):
		back_button.visible = false
		back_button.modulate.a = 0.0
	
	if is_instance_valid(main_menu_buttons):
		main_menu_buttons.visible = true
		main_menu_buttons.modulate.a = 0.0
	
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(main_menu_bg, "modulate:a", 1.0, 0.6)
	tween.tween_property(developers_bg, "modulate:a", 0.0, 0.6)
	
	if is_instance_valid(main_menu_buttons):
		tween.tween_property(main_menu_buttons, "modulate:a", 1.0, 0.6)
	
	await tween.finished
	is_transitioning = false


func _on_quit_pressed() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	
	var fade_tween = create_tween().set_parallel(true)
	if is_instance_valid(bgm_player) and bgm_player.playing:
		fade_tween.tween_property(bgm_player, "volume_db", -80.0, 0.5)
	if is_instance_valid(fade_overlay):
		fade_overlay.visible = true
		fade_overlay.modulate.a = 0.0
		fade_tween.tween_property(fade_overlay, "modulate:a", 1.0, 0.5)
		
	await fade_tween.finished
	get_tree().quit()

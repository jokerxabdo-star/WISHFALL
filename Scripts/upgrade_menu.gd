extends CanvasLayer

signal upgrade_selected(upgrade_data: Dictionary)
signal menu_timed_out

@export var decision_duration: float = 4.0
@export var slowmo_scale: float = 0.08
@export var music_slowmo_pitch: float = 0.55 ## Slow-motion pitch for the Music bus

@export_group("Card Dimensions & Layout")
@export var card_size: Vector2 = Vector2(220.0, 320.0) ## Dimensions of each card on screen

@export_group("Card Hover Juice")
@export var hover_scale: Vector2 = Vector2(1.08, 1.08) ## Scale factor on hover
@export var hover_lift_y: float = -14.0 ## Pixels the card lifts up
@export var hover_tilt_angle_deg: float = 2.5 ## Subtle tilt angle in degrees

# Preloaded Texture2D dictionary for instant, stutter-free display
var card_textures: Dictionary = {
	"player_strength": preload("res://Assets/Images/UI/Cards/Heavy_Blade.png"),
	"dash_strength": preload("res://Assets/Images/UI/Cards/Kinetic_Ram.png"),
	"increase_speed": preload("res://Assets/Images/UI/Cards/Hermes_Boost.png"),
	"more_max_health": preload("res://Assets/Images/UI/Cards/Heart_Vessel.png"),
	"heal_50": preload("res://Assets/Images/UI/Cards/Greater_Potion.png"),
	"get_dash": preload("res://Assets/Images/UI/Cards/Shadow_Dash.png"),
	"get_teleport": preload("res://Assets/Images/UI/Cards/Tactical_Wrap.png"),
	"dash_cooldown": preload("res://Assets/Images/UI/Cards/FeatherStep.png"),
	"teleport_cooldown": preload("res://Assets/Images/UI/Cards/Warp_Matrix.png"),
	"teleport_coverage": preload("res://Assets/Images/UI/Cards/Orbital_Scope.png")
}

@onready var card_container: HBoxContainer = $CardContainer
@onready var timer_bar: ProgressBar = get_node_or_null("ChoiceTimerBar")
@onready var card_hover_sound: AudioStreamPlayer = get_node_or_null("Card Hover")
@onready var card_pressed_sound: AudioStreamPlayer = get_node_or_null("Card Pressed")

var all_upgrades: Array[Dictionary] = [
	{"id": "player_strength", "title": "Heavy Blade", "desc": "+10 Melee Attack Damage"},
	{"id": "dash_strength", "title": "Kinetic Ram", "desc": "+10 Dash Collision Damage"},
	{"id": "increase_speed", "title": "Hermes Boots", "desc": "+35 Movement Speed"},
	{"id": "more_max_health", "title": "Heart Vessel", "desc": "+25 Max HP & heal 25 HP"},
	{"id": "heal_50", "title": "Greater Potion", "desc": "Instantly restore 50 HP"},
	{"id": "get_dash", "title": "Shadow Dash", "desc": "Unlock the Dash ability"},
	{"id": "get_teleport", "title": "Tactical Warp", "desc": "Unlock the Slow-Mo Teleport"},
	{"id": "dash_cooldown", "title": "Featherstep", "desc": "Dash cooldown recovers 25% faster"},
	{"id": "teleport_cooldown", "title": "Warp Matrix", "desc": "Reduce Teleport cooldown by 0.75s"},
	{"id": "teleport_coverage", "title": "Orbital Scope", "desc": "Expands Tactical Teleport camera view"}
]

var active_choices: Array[Dictionary] = []
var is_active: bool = false
var start_time_msec: int = 0
var duration_msec: float = 0.0

var current_player_ref: CharacterBody2D = null

var music_pitch_effect: AudioEffectPitchShift = null
var audio_tween: Tween = null
var card_tweens: Dictionary = {}


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if timer_bar:
		timer_bar.min_value = 0.0
		timer_bar.max_value = 1.0
		timer_bar.step = 0.0
		
	var music_bus_idx := AudioServer.get_bus_index("Music")
	if music_bus_idx != -1:
		for i in range(AudioServer.get_bus_effect_count(music_bus_idx)):
			var effect = AudioServer.get_bus_effect(music_bus_idx, i)
			if effect is AudioEffectPitchShift:
				music_pitch_effect = effect
				music_pitch_effect.pitch_scale = 1.0
				break
	
	var buttons = card_container.get_children()
	for i in range(buttons.size()):
		var btn = buttons[i]
		if btn is Control:
			# Center the transformation pivot so scale and tilt happen from the card's center
			btn.pivot_offset = card_size * 0.5
		if btn is BaseButton:
			btn.pressed.connect(_on_card_pressed.bind(i))
			btn.mouse_entered.connect(_on_card_hovered.bind(btn, i))
			btn.mouse_exited.connect(_on_card_unhovered.bind(btn))


func _process(_delta: float) -> void:
	if not is_active:
		return

	var elapsed_msec := Time.get_ticks_msec() - start_time_msec
	var remaining_ratio := 1.0 - (float(elapsed_msec) / duration_msec)

	if timer_bar:
		timer_bar.value = clampf(remaining_ratio, 0.0, 1.0)

	if remaining_ratio <= 0.0:
		_close_on_timeout()


func open_menu(player_ref: CharacterBody2D) -> void:
	current_player_ref = player_ref
	if is_instance_valid(current_player_ref) and current_player_ref.has_method("lock_actions"):
		current_player_ref.lock_actions(true)

	var available := all_upgrades.filter(func(item: Dictionary) -> bool:
		match item.get("id", ""):
			"get_dash":
				if player_ref.has_dash:
					return false
			"get_teleport":
				if player_ref.has_teleport:
					return false
			"heal_50":
				if player_ref.health >= player_ref.max_health:
					return false
			"dash_cooldown", "dash_strength":
				if not player_ref.has_dash:
					return false
			"teleport_cooldown", "teleport_coverage":
				if not player_ref.has_teleport:
					return false
		return true
	)

	available.shuffle()
	active_choices.clear()

	var count: int = mini(3, available.size())
	for i in range(count):
		active_choices.append(available[i])

	var buttons = card_container.get_children()
	for i in range(buttons.size()):
		var btn = buttons[i]
		if i < active_choices.size():
			var u: Dictionary = active_choices[i]
			var upgrade_id: String = u.get("id", "")
			var is_maxed: bool = player_ref.is_upgrade_maxed(upgrade_id)
			
			btn.visible = true
			
			var design_tex: Texture2D = card_textures.get(upgrade_id, null)
			
			if "text" in btn:
				btn.text = ""
			
			# Ensure proper layout bounding box and centered pivot
			if btn is Control:
				btn.custom_minimum_size = card_size
				btn.pivot_offset = card_size * 0.5
				btn.scale = Vector2.ONE
				btn.rotation = 0.0
				btn.position.y = 0.0
				btn.z_index = 0
			
			if btn is TextureButton:
				btn.texture_normal = design_tex
				btn.ignore_texture_size = true
				btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			elif btn is Button:
				btn.icon = design_tex
				btn.expand_icon = true
				btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			
			if is_maxed:
				btn.modulate = Color(0.35, 0.35, 0.35, 0.7)
				btn.disabled = true
			else:
				btn.modulate = Color.WHITE
				btn.disabled = false
		else:
			btn.visible = false

	duration_msec = decision_duration * 1000.0
	start_time_msec = Time.get_ticks_msec()
	if timer_bar:
		timer_bar.value = 1.0

	is_active = true
	visible = true
	Engine.time_scale = slowmo_scale
	_apply_music_slowmo(true)


func _on_card_hovered(btn: BaseButton, index: int) -> void:
	if not is_active or btn.disabled:
		return

	if card_hover_sound:
		card_hover_sound.pitch_scale = randf_range(1.1, 1.35)
		card_hover_sound.play()

	# Bring hovered card above adjacent cards
	btn.z_index = 10

	# Dynamic tilt: left tilts left, right tilts right, middle stays centered
	var tilt_dir := 0.0
	if index == 0:
		tilt_dir = -1.0
	elif index == 2:
		tilt_dir = 1.0
	var target_rotation := deg_to_rad(hover_tilt_angle_deg * tilt_dir)

	_kill_card_tween(btn)

	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(btn, "scale", hover_scale, 0.035)
	tween.tween_property(btn, "position:y", hover_lift_y, 0.035)
	tween.tween_property(btn, "rotation", target_rotation, 0.035)
	tween.tween_property(btn, "modulate", Color(1.15, 1.15, 1.15, 1.0), 0.035)
	card_tweens[btn] = tween


func _on_card_unhovered(btn: BaseButton) -> void:
	if not is_active or btn.disabled:
		return

	_kill_card_tween(btn)

	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(btn, "scale", Vector2.ONE, 0.03)
	tween.tween_property(btn, "position:y", 0.0, 0.03)
	tween.tween_property(btn, "rotation", 0.0, 0.03)
	tween.tween_property(btn, "modulate", Color.WHITE, 0.03)
	tween.chain().tween_callback(func():
		if is_instance_valid(btn):
			btn.z_index = 0
	)
	card_tweens[btn] = tween


func _kill_card_tween(btn: Object) -> void:
	if card_tweens.has(btn) and is_instance_valid(card_tweens[btn]):
		(card_tweens[btn] as Tween).kill()
	card_tweens.erase(btn)


func _on_card_pressed(index: int) -> void:
	if not is_active or index >= active_choices.size():
		return

	var chosen: Dictionary = active_choices[index]
	var btn = card_container.get_child(index)
	
	if card_pressed_sound:
		card_pressed_sound.pitch_scale = randf_range(1.0, 1.3)
		card_pressed_sound.play()

	# Ultra-fast micro squash on press
	if btn is Control:
		_kill_card_tween(btn)
		var click_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		click_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		click_tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.015)
		await click_tween.finished

	_close_menu()
	upgrade_selected.emit(chosen)


func _close_on_timeout() -> void:
	_close_menu()
	menu_timed_out.emit()


func _close_menu() -> void:
	is_active = false
	visible = false
	Engine.time_scale = 1.0
	
	if is_instance_valid(current_player_ref) and current_player_ref.has_method("lock_actions"):
		current_player_ref.lock_actions(false)
	current_player_ref = null

	for btn in card_container.get_children():
		_kill_card_tween(btn)
		if btn is Control:
			btn.scale = Vector2.ONE
			btn.position.y = 0.0
			btn.rotation = 0.0
			btn.z_index = 0
		if btn is BaseButton:
			btn.disabled = false
		btn.modulate = Color.WHITE
		
	_apply_music_slowmo(false)


func _apply_music_slowmo(enable: bool) -> void:
	if audio_tween and audio_tween.is_valid():
		audio_tween.kill()

	audio_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	audio_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	
	var target_pitch := music_slowmo_pitch if enable else 1.0

	if music_pitch_effect:
		audio_tween.tween_property(music_pitch_effect, "pitch_scale", target_pitch, 0.05)
	else:
		for player in get_tree().get_nodes_in_group("MusicPlayer"):
			if player is AudioStreamPlayer or player is AudioStreamPlayer2D:
				audio_tween.tween_property(player, "pitch_scale", target_pitch, 0.05)

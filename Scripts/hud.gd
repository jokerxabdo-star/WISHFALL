extends CanvasLayer

var player

@export_group("Tactical Overlay Styling")
@export var bar_height: float = 60.0 ## Height in pixels of the letterbox bars
@export var bar_color: Color = Color.BLACK ## Color of the top & bottom bars
@export var tint_color: Color = Color(0.08, 0.22, 0.45, 0.35) ## Full-screen overlay color & transparency

@onready var fade_overlay: ColorRect = $FadeOverlay
@onready var player_health_bar: Control = get_node_or_null("PlayerHealthBar")

@onready var tactical_overlay: Control = get_node_or_null("TacticalOverlay")
@onready var top_bar: ColorRect = get_node_or_null("TacticalOverlay/TopBar")
@onready var bottom_bar: ColorRect = get_node_or_null("TacticalOverlay/BottomBar")
@onready var screen_tint: ColorRect = get_node_or_null("TacticalOverlay/ScreenTint")
@onready var target_reticle: Node2D = get_node_or_null("TacticalOverlay/TargetReticle")

# Cooldown indicators
@onready var teleport_progress_bar: TextureProgressBar = get_node_or_null("TeleportOverlay/TeleportCooldownBar")
@onready var dash_progress_bar: TextureProgressBar = get_node_or_null("TeleportOverlay/DashCooldownBar")
@onready var cooldown_circle: Control = get_node_or_null("CooldownCircle")

var hud_tween: Tween = null
var is_teleport_unlocked: bool = false
var is_dash_unlocked: bool = false


func _ready() -> void:
	add_to_group("HUD")
	reset_tactical_overlay()
	
	if teleport_progress_bar:
		teleport_progress_bar.min_value = 0.0
		teleport_progress_bar.max_value = 1.0
		teleport_progress_bar.value = 1.0
		teleport_progress_bar.visible = is_teleport_unlocked

	if dash_progress_bar:
		dash_progress_bar.min_value = 0.0
		dash_progress_bar.max_value = 1.0
		dash_progress_bar.value = 1.0
		dash_progress_bar.visible = is_dash_unlocked

	if cooldown_circle:
		cooldown_circle.visible = is_teleport_unlocked


func reset_tactical_overlay() -> void:
	if hud_tween and hud_tween.is_valid():
		hud_tween.kill()
		
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if tactical_overlay:
		tactical_overlay.visible = false
	
	if top_bar:
		top_bar.anchor_left = 0.0
		top_bar.anchor_right = 1.0
		top_bar.anchor_top = 0.0
		top_bar.anchor_bottom = 0.0
		top_bar.offset_top = 0.0
		top_bar.offset_bottom = 0.0
		top_bar.color = bar_color
	
	if bottom_bar:
		bottom_bar.anchor_left = 0.0
		bottom_bar.anchor_right = 1.0
		bottom_bar.anchor_top = 1.0
		bottom_bar.anchor_bottom = 1.0
		bottom_bar.offset_top = 0.0
		bottom_bar.offset_bottom = 0.0
		bottom_bar.color = bar_color
		
	if screen_tint:
		screen_tint.color = tint_color
		screen_tint.modulate.a = 0.0
		
	if target_reticle:
		target_reticle.visible = false
		
	set_teleport_unlocked(is_teleport_unlocked)
	set_dash_unlocked(is_dash_unlocked)
	update_teleport_cooldown(1.0)
	update_dash_cooldown(1.0)


func set_player(p) -> void:
	player = p
	if player:
		if player.health_changed.is_connected(_update_health):
			player.health_changed.disconnect(_update_health)
			
		player.health_changed.connect(_update_health)
		
		init_health(player.max_health)
		_update_health(player.health, player.max_health)
		
		set_teleport_unlocked(player.has_teleport)
		set_dash_unlocked(player.has_dash)
		update_teleport_cooldown(1.0)
		update_dash_cooldown(1.0)


func init_health(max_hp: int) -> void:
	if not player_health_bar:
		return
		
	if player_health_bar.has_method("init_health"):
		player_health_bar.init_health(max_hp)
	elif "max_value" in player_health_bar:
		player_health_bar.max_value = float(max_hp)


func _update_health(new_health: int, max_hp: int = 0) -> void:
	if not player_health_bar:
		return

	var effective_max := max_hp
	if effective_max <= 0:
		effective_max = player.max_health if is_instance_valid(player) else 100

	var clamped_hp := clampi(new_health, 0, effective_max)
	var health_ratio := float(clamped_hp) / float(effective_max) if effective_max > 0 else 0.0

	if player_health_bar.has_method("Update_health"):
		player_health_bar.Update_health(clamped_hp, effective_max)
	elif player_health_bar.has_method("set_health_ratio"):
		player_health_bar.set_health_ratio(health_ratio)
	
	if "max_value" in player_health_bar and "value" in player_health_bar:
		player_health_bar.max_value = float(effective_max)
		player_health_bar.value = float(clamped_hp)


func fade(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade_overlay, "modulate:a", alpha, 1.0)
	await tween.finished


# Tactical Mode UI Control
func set_teleport_unlocked(unlocked: bool) -> void:
	is_teleport_unlocked = unlocked
	if teleport_progress_bar:
		teleport_progress_bar.visible = unlocked
	if cooldown_circle:
		cooldown_circle.visible = unlocked


func set_dash_unlocked(unlocked: bool) -> void:
	is_dash_unlocked = unlocked
	if dash_progress_bar:
		dash_progress_bar.visible = unlocked


func set_tactical_mode(active: bool, slowmo_factor: float) -> void:
	if hud_tween and hud_tween.is_valid():
		hud_tween.kill()
		
	hud_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hud_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	
	if active:
		if tactical_overlay:
			tactical_overlay.visible = true
		if target_reticle:
			target_reticle.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		
		var anim_dur := 0.01 / slowmo_factor
		if top_bar:
			hud_tween.tween_property(top_bar, "offset_bottom", bar_height, anim_dur)
		if bottom_bar:
			hud_tween.tween_property(bottom_bar, "offset_top", -bar_height, anim_dur)
		if screen_tint:
			hud_tween.tween_property(screen_tint, "modulate:a", 1.0, anim_dur)
	else:
		if target_reticle:
			target_reticle.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
		if top_bar:
			hud_tween.tween_property(top_bar, "offset_bottom", 0.0, 0.15)
		if bottom_bar:
			hud_tween.tween_property(bottom_bar, "offset_top", 0.0, 0.15)
		if screen_tint:
			hud_tween.tween_property(screen_tint, "modulate:a", 0.0, 0.15)
		
		if tactical_overlay:
			hud_tween.chain().tween_callback(func(): tactical_overlay.visible = false)


func update_reticle_validity(valid: bool) -> void:
	if target_reticle and target_reticle.visible:
		target_reticle.set("is_valid_target", valid)


# Cooldown Display
func update_teleport_cooldown(ratio: float) -> void:
	var clamped_ratio := clampf(ratio, 0.0, 1.0)
	
	if teleport_progress_bar:
		teleport_progress_bar.value = clamped_ratio
	elif cooldown_circle and cooldown_circle.has_method("set_progress"):
		cooldown_circle.set_progress(clamped_ratio)


func update_dash_cooldown(ratio: float) -> void:
	if dash_progress_bar:
		dash_progress_bar.value = clampf(ratio, 0.0, 1.0)

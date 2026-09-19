extends Control

@onready var health_bar: Sprite2D = $Health
@onready var damage_bar: Sprite2D = $DamageBar
@onready var timer: Timer = $Timer

var max_health: int = 100
var health: int = 100

var full_width: float = 0.0
var damage_tween: Tween = null


func _ready() -> void:
	timer.timeout.connect(_on_timer_timeout)
	_setup_white_shader()
	
	if health_bar and health_bar.texture:
		health_bar.region_enabled = true
		damage_bar.region_enabled = true
		
		# full_width is the EXACT pixel width of your UI frame texture
		full_width = float(health_bar.texture.get_width())
		
		var full_rect := Rect2(0.0, 0.0, full_width, float(health_bar.texture.get_height()))
		health_bar.region_rect = full_rect
		damage_bar.region_rect = full_rect


func _setup_white_shader() -> void:
	if not damage_bar:
		return
	
	var shader := Shader.new()
	shader.code = """
	shader_type canvas_item;
	void fragment() {
		vec4 tex = texture(TEXTURE, UV);
		COLOR = vec4(1.0, 1.0, 1.0, tex.a);
	}
	"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	damage_bar.material = mat


func init_health(_max_health: int) -> void:
	max_health = maxi(1, _max_health)
	health = max_health
	
	if full_width == 0.0 and health_bar and health_bar.texture:
		full_width = float(health_bar.texture.get_width())
		
	_set_bars_by_percentage(1.0, 1.0)


func Update_health(new_health: int, new_max_health: int = 0) -> void:
	var prev_health := health
	
	# Update the max health capacity if upgraded by cards
	if new_max_health > 0:
		max_health = new_max_health
		
	# Strict clamp: health can never exceed current max_health or drop below 0
	health = clampi(new_health, 0, max_health)
	
	# Compute pure percentage (0.0 to 1.0)
	var target_ratio: float = clampf(float(health) / float(max_health), 0.0, 1.0)
	var target_width: float = full_width * target_ratio
	
	# Green bar snaps immediately to the percentage
	if health_bar:
		health_bar.region_rect.size.x = target_width
	
	if health < prev_health:
		# Took damage: retain white under-bar, wait for timer
		timer.start()
	else:
		# Healed or Max HP increased: snap white bar directly to avoid overflow
		if damage_tween and damage_tween.is_valid():
			damage_tween.kill()
		if damage_bar:
			damage_bar.region_rect.size.x = target_width


func _on_timer_timeout() -> void:
	if not damage_bar or max_health <= 0:
		return
		
	var target_ratio: float = clampf(float(health) / float(max_health), 0.0, 1.0)
	var target_width: float = full_width * target_ratio
	
	if damage_tween and damage_tween.is_valid():
		damage_tween.kill()
		
	damage_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	damage_tween.tween_property(damage_bar, "region_rect:size:x", target_width, 0.25)


func _set_bars_by_percentage(front_ratio: float, back_ratio: float) -> void:
	if health_bar:
		health_bar.region_rect.size.x = full_width * clampf(front_ratio, 0.0, 1.0)
	if damage_bar:
		damage_bar.region_rect.size.x = full_width * clampf(back_ratio, 0.0, 1.0)

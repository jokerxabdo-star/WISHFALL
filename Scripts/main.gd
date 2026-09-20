extends Node2D

@export var upgrade_popup_delay: float = 0.5

@export_group("Exit Visuals")
@export var exit_open_texture: Texture2D = preload("res://Assets/Images/Opened Door.png")

@onready var hud: CanvasLayer = $HUD
@onready var level_root: Node2D = $LevelRoot
@onready var intro_music: AudioStreamPlayer = $Music

var upgrade_menu_scene = preload("res://Scenes/upgrade_menu.tscn")
var upgrade_menu: CanvasLayer = null

var level: int = 2 # Target level to load after intro
var current_level_root: Node = null
var current_player: CharacterBody2D = null

var enemies_killed: int = 0
const KILLS_PER_UPGRADE: int = 2
var pending_upgrades: int = 0

# Enemy target tracking
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
	
	# Start with a pitch black screen
	if hud.has_method("fade"):
		await hud.fade(1.0)
		
	# Fade in the intro music if available
	if is_instance_valid(intro_music):
		intro_music.volume_db = -80.0
		intro_music.play()
		var music_fade_in = create_tween()
		music_fade_in.tween_property(intro_music, "volume_db", 0.0, 1.5)
		
	# Display the bilingual scrolling prologue intro screen first
	await _show_intro_screen()
	
	# Fade out the intro music before loading Level 2
	if is_instance_valid(intro_music):
		var music_fade_out = create_tween()
		music_fade_out.tween_property(intro_music, "volume_db", -80.0, 1.0)
		await music_fade_out.finished
		intro_music.stop()
	
	# Load Level 2 once the player continues
	await _load_level(level)


# Bilingual scrolling prologue intro screen setup with text starting from the middle of the screen
func _show_intro_screen() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var intro_layer = CanvasLayer.new()
	intro_layer.layer = 130
	add_child(intro_layer)

	# Root control container for smooth fading
	var root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	intro_layer.add_child(root_control)

	var ui_audio = AudioStreamPlayer.new()
	root_control.add_child(ui_audio)
	var hover_sound = load("res://Assets/Audios/UI Hover.wav")
	var click_sound = load("res://Assets/Audios/UI Click.wav")

	# Rich dark slate/charcoal background fill
	var bg_rect = ColorRect.new()
	bg_rect.color = Color(0.06, 0.06, 0.08)
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(bg_rect)

	# SubViewportContainer to lock rendering to a crisp, uniform 1920x1080 design space
	var vp_container = SubViewportContainer.new()
	vp_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp_container.stretch = true
	root_control.add_child(vp_container)

	var viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = false
	vp_container.add_child(viewport)

	# Inner container inside the virtual 1080p viewport space
	var vp_content = Control.new()
	vp_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(vp_content)

	# Main container for the centered WishFall title
	var title_container = Control.new()
	title_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title_container.offset_top = 80
	title_container.custom_minimum_size = Vector2(0, 40)
	vp_content.add_child(title_container)

	var prologue_title = Label.new()
	prologue_title.text = "WishFall"
	prologue_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prologue_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prologue_title.offset_left = -60
	prologue_title.offset_right = -60
	prologue_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prologue_title.add_theme_font_size_override("font_size", 32)
	prologue_title.add_theme_color_override("font_color", Color.WHITE)
	title_container.add_child(prologue_title)

	# Main Margin Container for overall layout padding below the title
	var margin_container = MarginContainer.new()
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.offset_top = 160
	margin_container.offset_bottom = -100
	margin_container.add_theme_constant_override("margin_left", 140)
	margin_container.add_theme_constant_override("margin_right", 140)
	vp_content.add_child(margin_container)

	# Control container acting as a scroll mask
	var scroll_clip = Control.new()
	scroll_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_clip.clip_contents = true
	margin_container.add_child(scroll_clip)

	# Moving container that will scroll upward (starting at 450.0 places it right around the middle)
	var content_node = Control.new()
	content_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_node.position.y = 450.0
	scroll_clip.add_child(content_node)

	# Vertical stack of paired paragraphs so English and Arabic lines match up perfectly side-by-side
	var paragraphs_vbox = VBoxContainer.new()
	paragraphs_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paragraphs_vbox.add_theme_constant_override("separation", 50)
	content_node.add_child(paragraphs_vbox)

	var english_paragraphs = [
		"Long before the modern world forgot its history, there existed an ancient being—a master craftsman and sorcerer from a civilization lost to oblivion—who possessed an artifact of immense, reality-bending power: a unique, unfulfilled magical wish.",
		"Driven by a desire to escape his dying era—or perhaps to master immortality itself—he unleashed the wish through the artifact. Yet, great magic rarely respects simple boundaries; instead of merely traversing the years, the spell tore the fabric of time, creating a deep, gaping rift. Amidst a blinding flash of mysterious dark energy, he—along with a nightmarish army of primordial creatures from his own time and beyond—was ripped from the past and violently thrust into our present.",
		"The modern world has become a twisted battlefield; the facility has been overrun, its corridors teeming with anomalies from a forgotten millennium, and reality itself is fracturing at the seams.",
		"You take on the role of the lone survivor trapped in the midst of this catastrophe. To reset the timeline and erase this disastrous anomaly, there is only one path: track down the ancient creator amidst the ruins of the overrun facility, survive the hordes of his twisted, time-displaced monsters, and destroy him. His death alone can shatter the anchor of his magic, dispel the temporal distortion, and erase the lingering traces of that wish—restoring everything to the way it was before time itself was broken."
	]

	var arabic_paragraphs = [
		"قبل وقت طويل من نسيان العالم الحديث لتاريخه، وُجد كائنٌ قديم -كان حرفياً بارعاً وساحراً ينتمي لحضارة طواها النسيان وضاع اسمها في غياهب الزمن- امتلك أثراً ذا قوة هائلة قادرة على تطويع الواقع: أمنية سحرية فريدة لم تتحقق قط.",
		"ودفعه توقه للهروب من عصره الآفل -أو ربما السيطرة على الخلود ذاته- إلى إطلاق تلك الأمنية عبر ذلك الأثر. لكن السحر العظيم نادراً ما يتقيد بحدود بسيطة؛ فبدلاً من مجرد الانتقال عبر السنين، مزّق ذلك السحر نسيج الزمن محدثاً صدعاً غائراً فيه. ووسط وميضٍ ساطع من طاقة مظلمة غامضة، انتزع نفسه -ومعه جيشٌ من المخلوقات البدائية الكابوسية التي تنتمي لعصره ولغير عصره- من الماضي ليدفع بهم بعنفٍ وقوة إلى حاضرنا.",
		"أصبح العالم الحديث الآن ساحة معركة مشوهة؛ فقد اجتيحت المنشأة، وامتلأت أروقتها بظواهر شاذة تعود لألفية منسية، وبدأ الواقع يتصدع عند مفاصله.",
		"تتقمص أنت دور الناجي الوحيد العالق في خضم هذه الكارثة. ولإعادة ضبط المسار الزمني ومحو هذا التناقض الكارثي، لا يوجد سوى سبيل واحد: تعقّب ذلك الصانع القديم وسط أنقاض المنشأة المستباحة، والنجاة من حشود وحوشه المشوهة والمنقولة عبر الزمن، ثم القضاء عليه. فمقتله وحده كفيلٌ بتحطيم ركيزة سحره، وتبديد التشوه الزمني، ومحو الآثار المتبقية لتلك الأمنية، ليعود كل شيء إلى ما كان عليه قبل أن ينكسر الزمن ذاته."
	]

	for i in range(english_paragraphs.size()):
		var row_hbox = HBoxContainer.new()
		row_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_hbox.add_theme_constant_override("separation", 80)
		paragraphs_vbox.add_child(row_hbox)

		var eng_label = Label.new()
		eng_label.text = english_paragraphs[i]
		eng_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		eng_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		eng_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		eng_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eng_label.size_flags_stretch_ratio = 1.0
		eng_label.add_theme_font_size_override("font_size", 18)
		eng_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		row_hbox.add_child(eng_label)

		var arb_label = Label.new()
		arb_label.text = arabic_paragraphs[i]
		arb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		arb_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		arb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		arb_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		arb_label.size_flags_stretch_ratio = 1.0
		arb_label.add_theme_font_size_override("font_size", 18)
		arb_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		row_hbox.add_child(arb_label)

	# --- Cinematic Top and Bottom Fade Bars ---
	var top_fade_rect = TextureRect.new()
	top_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_fade_rect.offset_top = 160
	top_fade_rect.custom_minimum_size = Vector2(0, 80)
	top_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var t_grad = Gradient.new()
	t_grad.colors = PackedColorArray([Color(0.06, 0.06, 0.08, 1), Color(0.06, 0.06, 0.08, 0)])
	var t_texture = GradientTexture2D.new()
	t_texture.gradient = t_grad
	t_texture.fill_from = Vector2(0.5, 0.0)
	t_texture.fill_to = Vector2(0.5, 1.0)
	top_fade_rect.texture = t_texture
	top_fade_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root_control.add_child(top_fade_rect)

	var bottom_fade_rect = TextureRect.new()
	bottom_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_fade_rect.custom_minimum_size = Vector2(0, 100)
	bottom_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var b_grad = Gradient.new()
	b_grad.colors = PackedColorArray([Color(0.06, 0.06, 0.08, 0), Color(0.06, 0.06, 0.08, 1)])
	var b_texture = GradientTexture2D.new()
	b_texture.gradient = b_grad
	b_texture.fill_from = Vector2(0.5, 0.0)
	b_texture.fill_to = Vector2(0.5, 1.0)
	bottom_fade_rect.texture = b_texture
	bottom_fade_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root_control.add_child(bottom_fade_rect)

	# Dedicated UI Layer container for the Continue button pinned clearly at the bottom right
	var bottom_right_container = VBoxContainer.new()
	bottom_right_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_right_container.anchor_left = 1.0
	bottom_right_container.anchor_top = 1.0
	bottom_right_container.anchor_right = 1.0
	bottom_right_container.anchor_bottom = 1.0
	bottom_right_container.offset_left = -320
	bottom_right_container.offset_top = -90
	bottom_right_container.offset_right = -50
	bottom_right_container.offset_bottom = -30
	bottom_right_container.z_index = 200
	bottom_right_container.mouse_filter = Control.MOUSE_FILTER_PASS
	root_control.add_child(bottom_right_container)

	# Continue button with a clean white stroke border
	var continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(220, 45)
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	normal_style.border_color = Color.WHITE
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(6)
	continue_button.add_theme_stylebox_override("normal", normal_style)

	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(0.25, 0.25, 0.3, 0.95)
	continue_button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = Color(0.4, 0.4, 0.45, 0.95)
	continue_button.add_theme_stylebox_override("pressed", pressed_style)

	# Disabled style to make it gray out and ignore interactions completely when clicked
	var disabled_style = normal_style.duplicate()
	disabled_style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
	disabled_style.border_color = Color(0.4, 0.4, 0.45, 0.8)
	continue_button.add_theme_stylebox_override("disabled", disabled_style)
	continue_button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55, 1.0))

	continue_button.mouse_entered.connect(func():
		if continue_button.disabled:
			return
		if hover_sound and is_instance_valid(ui_audio):
			ui_audio.stream = hover_sound
			ui_audio.play()
	)
	
	bottom_right_container.add_child(continue_button)

	# Calculate scrolling distance based on total height of paragraphs
	await get_tree().process_frame
	var target_y_scroll = -paragraphs_vbox.size.y + 150
	if target_y_scroll > 0:
		target_y_scroll = -400

	# Smooth fade-in animation for the intro screen content
	root_control.modulate.a = 0.0
	var fade_in_tween = create_tween()
	fade_in_tween.tween_property(root_control, "modulate:a", 1.0, 0.8)

	# Continuous slow upward scroll animation
	var scroll_tween = create_tween()
	scroll_tween.tween_property(content_node, "position:y", target_y_scroll, 55.0).set_trans(Tween.TRANS_LINEAR)

	# Wait for player click or scroll finish with immediate gray-out, audio feedback, and clean transition fade
	var clicked = false
	continue_button.pressed.connect(func():
		if clicked:
			return
		clicked = true
		
		# Gray out and disable immediately so it can't be hovered or clicked again
		continue_button.disabled = true
		
		if scroll_tween.is_valid():
			scroll_tween.kill()
			
		if click_sound and is_instance_valid(ui_audio):
			ui_audio.stream = click_sound
			ui_audio.play()
	)

	while not clicked and scroll_tween.is_running():
		await get_tree().process_frame
	
	if scroll_tween.is_valid():
		scroll_tween.kill()

	continue_button.disabled = true

	# Smooth fade-out animation using the root_control before cleaning up and loading the next level
	var fade_out_tween = create_tween()
	fade_out_tween.tween_property(root_control, "modulate:a", 0.0, 0.5)
	await fade_out_tween.finished
	
	intro_layer.queue_free()


# Level management and transition sequence
func _load_level(level_number: int) -> void:
	var music_tween = null
	if current_level_root:
		var music_node = current_level_root.find_child("BG Music", true, false)
		if is_instance_valid(music_node) and "volume_db" in music_node:
			music_tween = create_tween()
			music_tween.tween_property(music_node, "volume_db", -80.0, 0.8)

	if hud.has_method("fade"):
		await hud.fade(1.0)

	if music_tween and music_tween.is_valid():
		await music_tween.finished

	if hud.has_method("reset_tactical_overlay"):
		hud.reset_tactical_overlay()
	
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if level >= 3:
		var game_over_sfx = AudioStreamPlayer.new()
		game_over_sfx.stream = preload("res://Assets/Audios/Game Over.wav")
		add_child(game_over_sfx)
		game_over_sfx.play()

		var game_over_label = hud.get_node_or_null("GameOver")
		if game_over_label:
			var tween = create_tween()
			tween.tween_property(game_over_label, "visible_ratio", 1.0, 1.0)
			tween.tween_interval(1.5)
			tween.tween_property(game_over_label, "visible_ratio", 0.0, 1.0)
			await tween.finished
		
		if hud.has_method("fade"):
			await hud.fade(1.0)
			
		game_over_sfx.queue_free()
		get_tree().change_scene_to_file("res://Scenes/start_menu.tscn")
		return
		
	if current_level_root:
		current_level_root.queue_free()
		current_level_root = null
		
	var file_path = "res://Scenes/folder levels/level_%s.tscn" % level_number
	var loaded_scene = load(file_path)
	if not loaded_scene:
		return
		
	current_level_root = loaded_scene.instantiate()
	add_child(current_level_root)
	current_level_root.name = "LevelRoot"

	await get_tree().physics_frame
	await get_tree().process_frame
	
	_setup_level(current_level_root)

	if hud.has_method("fade"):
		await hud.fade(0.0)


func _setup_level(level_node: Node) -> void:
	has_collected_key = false
	current_kills = 0

	current_player = level_node.find_child("Player", true, false) as CharacterBody2D
	if current_player:
		hud.set_player(current_player)
		if not current_player.died.is_connected(_on_player_died):
			current_player.died.connect(_on_player_died)
	
	_setup_level_music(level_node)

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
		
		var trigger_zone = exit_node.find_child("TriggerZone", true, false) as Area2D
		if trigger_zone:
			if not trigger_zone.body_entered.is_connected(_on_exit_trigger_body_entered):
				trigger_zone.body_entered.connect(_on_exit_trigger_body_entered)
			if not trigger_zone.body_exited.is_connected(_on_exit_trigger_body_exited):
				trigger_zone.body_exited.connect(_on_exit_trigger_body_exited)

		_lock_exit()

	_setup_enemy_gate(level_node)
	_hook_level_enemies(level_node)
	_show_how_to_play_overlay()


func _show_how_to_play_overlay() -> void:
	var tutorial_layer = CanvasLayer.new()
	tutorial_layer.layer = 120
	add_child(tutorial_layer)

	var texture_rect = TextureRect.new()
	var tut_texture = load("res://Assets/Images/UI/Tutorial.png")
	if tut_texture:
		texture_rect.texture = tut_texture
	
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_layer.add_child(texture_rect)

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


# Signal handlers for gameplay mechanics
func on_key_collected() -> void:
	has_collected_key = true
	_unlock_exit()


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
	pass


func on_player_hit_enemy_gate() -> void:
	if current_kills < target_kills_to_open:
		_show_enemy_gate_prompt()


func _on_enemy_killed() -> void:
	if not is_instance_valid(current_player) or not current_player.alive:
		return

	current_kills += 1

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
		await _load_level(level)


func _on_player_died() -> void:
	pending_upgrades = 0
	if upgrade_menu:
		upgrade_menu._close_menu()
	
	Engine.time_scale = 1.0

	await get_tree().create_timer(1.0).timeout
	enemies_killed = 0
	Player_stats.reset()
	await _load_level(level)

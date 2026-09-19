extends CanvasLayer

func _ready() -> void:
	# إيقاف اللعبة خلف الشاشة
	get_tree().paused = true
	# السماح لـ CanvasLayer باستقبال المدخلات أثناء الـ Pause
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	# إغلاق الشاشة وإعادة اللعبة عند الضغط على أي زر
	if event.is_pressed() and not event.is_echo():
		get_tree().paused = false
		queue_free()

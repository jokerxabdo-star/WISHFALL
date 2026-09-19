extends CharacterBody2D

const SPEED: int = 100
const Knockback_force: int = 100
const DROP_CHANCE: float = 1.0

var Is_alive: bool = true
var Health: int = 100
var strength: int = 10
var Target = null
var target_in_range: bool = false

var health_pickup_scene = preload("res://Scenes/health_pickup.tscn")

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var take_damage_sound: AudioStreamPlayer2D = $TakeDamage
@onready var enemy_health_bar: Node2D = $Enemy_HealthBar
@onready var attack_timer: Timer = $AttackTimer


#if the function starts with "_" that means that it can be used only in the same script otherwise i can call it from a different script
#***it`s just a design role and don`t affect the syntax***
func _physics_process(delta: float) -> void: 
	if Is_alive and Target:
		_attack(delta)
		animated_sprite_2d.play("Attack")
	
	


func _attack(delta: float) -> void:
	var direction = (Target.position - position).normalized()
	position += direction * SPEED * delta


func Take_damage(damage: int, attacker_position: Vector2) -> void:
	Health -= damage
	enemy_health_bar.Update_health(Health)
	if Health < 0:
		return
	elif Health == 0:
		#knock back
		var Knockback_direction = (position - attacker_position).normalized()
		var Target_position = position + Knockback_direction * Knockback_force
		
		var tween = create_tween() #for a smooth knock back
		tween.set_ease(tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(self, "position", Target_position, 0.2)
		_die()
	else:
		take_damage_sound.pitch_scale = randf_range(1.0, 1.5)
		take_damage_sound.play()
		#knock back
		var Knockback_direction = (position - attacker_position).normalized()
		var Target_position = position + Knockback_direction * Knockback_force
		
		var tween = create_tween() #for a smooth knock back
		tween.set_ease(tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(self, "position", Target_position, 0.2)
	
	

func _die() -> void:
	Is_alive = false
	animated_sprite_2d.play("Die")
	
	take_damage_sound.pitch_scale = randf_range(.5, .9)
	take_damage_sound.play()
	_on_hit_box_body_exited(Target)
	
	#Disable Collisions
	$CollisionShape2D.set_deferred("disabled", true) #making sure that it`s safe to disable thius physics
	$Sight/CollisionShape2D.set_deferred("disabled", true)
	$HitBox/CollisionShape2D.set_deferred("disabled", true)
	
	#drop health_pickup
	if randf() <= DROP_CHANCE:
		drop_item()



func _on_sight_body_entered(body: Node2D) -> void:
	if body.name == "Player":
		Target = body


func _on_sight_body_exited(body: Node2D) -> void:
	if body.name == "Player" and Is_alive:
		await get_tree().create_timer(2.0).timeout
		Target = null
		animated_sprite_2d.play("Idle")


func _on_hit_box_body_entered(body: Node2D) -> void:
	if body.name == "Player" and Is_alive and body.alive:
		target_in_range = true
		body.take_damage(strength)
		attack_timer.start()

func _on_hit_box_body_exited(body: Node2D) -> void:
	if body.name == "Player":
		target_in_range = false
		attack_timer.stop()

func _on_attack_timer_timeout() -> void:
	if Target and target_in_range:
		_on_hit_box_body_entered(Target)

func drop_item():
	var drop = health_pickup_scene.instantiate()
	drop.position = position
	var level_root = get_parent().get_parent()
	var items_node = level_root.get_node("Items")
	items_node.call_deferred("add_child", drop)

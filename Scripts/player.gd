extends CharacterBody2D


const SPEED = 300.0

var Last_direction: Vector2 = Vector2.RIGHT
var Is_attacking: bool = false
var Hitbox_offset: Vector2
var Strength: int = 20 #The damage player attacks with 

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var swing_sword: AudioStreamPlayer2D = $SwingSword
@onready var hit_box: Area2D = $HitBox


func _ready() -> void:
	
	#initialize hitbox offset
	Hitbox_offset = hit_box.position

func _physics_process(_delta: float) -> void:
	
	# Disable hitbox until an attack is triggered
	hit_box.monitoring = false
	
	if Input.is_action_just_pressed("Attack") and not Is_attacking:
		Attack()
	
	Process_movement()
	Process_animation()
	move_and_slide()


####################################Player#############################################
############################Player_Movement############################
func Process_movement() -> void:
	
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_vector("Left", "Right", "Up", "Down")
	
	if direction != Vector2.ZERO:
		velocity = direction * SPEED
		Last_direction = direction
		Update_hitbox_offset()
	else:
		velocity = Vector2.ZERO
############################Player_Movement############################




###########################Player_Animations###########################
func Process_animation() -> void:
	if Is_attacking:
		return
	if velocity != Vector2.ZERO:
		Play_animation("Run", Last_direction)
	else:
		Play_animation("Idle", Last_direction)


func Play_animation(prefix: String, dir: Vector2) -> void:
	if dir.x != 0:
		animated_sprite_2d.flip_h = dir.x < 0
		animated_sprite_2d.play(prefix + "_Right")
	elif dir.y > 0:
		animated_sprite_2d.play(prefix + "_Down")
	elif dir.y < 0:
		animated_sprite_2d.play(prefix + "_Up")


func _on_animated_sprite_2d_animation_finished() -> void:
	if Is_attacking:
		Is_attacking = false
###########################Player_Animations###########################




#############################Player_Attack#############################
func Attack() -> void:
	Is_attacking = true
	hit_box.monitoring = true
	swing_sword.pitch_scale = randf_range(2.0, 3.3)
	swing_sword.play()
	Play_animation("Attack", Last_direction)

#######################Hitbox#######################
func Update_hitbox_offset() -> void:
	var x := Hitbox_offset.x
	var y := Hitbox_offset.y
	
	match Last_direction:
		
		Vector2.RIGHT:
			hit_box.position = Vector2(x, y)
		Vector2.LEFT:
			hit_box.position = Vector2(-x + 5, y)
		Vector2.UP:
			hit_box.position = Vector2(-y - 3, -x)
		Vector2.DOWN:
			hit_box.position = Vector2(-y - 3, x)



func _on_hit_box_body_entered(body: Node2D) -> void:
	if Is_attacking and body.name.begins_with("Enemy_slime"): #don`t forget to make the collision mask of the enemy "2" to make this work
		body.Take_damage(Strength, position)

#######################Hitbox#######################
#############################Player_Attack#############################
####################################Player#############################################

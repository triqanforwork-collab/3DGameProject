extends CharacterBody3D

@export var move_speed: float = 5.0
@export var acceleration: float = 20.0
@export var turn_speed: float = 10.0

@onready var visual: Node3D = $Visual
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var gravity: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)


func _physics_process(delta: float) -> void:
	# Trọng lực khi không đứng trên sàn.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Đọc WASD: trái/phải tương ứng X, trước/sau tương ứng Z.
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var direction := Vector3(
		input_direction.x,
		0.0,
		input_direction.y
	)

	# Tăng tốc và giảm tốc.
	velocity.x = move_toward(
		velocity.x,
		direction.x * move_speed,
		acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		direction.z * move_speed,
		acceleration * delta
	)

	# Xoay hình ảnh nhân vật theo hướng di chuyển.
	# Đoạn này giả định mặt model hướng về +Z.
	if direction.length_squared() > 0.001:
		var target_angle := atan2(direction.x, direction.z)
		visual.rotation.y = lerp_angle(
			visual.rotation.y,
			target_angle,
			minf(turn_speed * delta, 1.0)
		)

	#Di chuyển và xử lý va chạm.
	move_and_slide()
	update_animation(direction.length_squared() > 0.001)
	
func update_animation(is_moving: bool) -> void:
	var animation_name: StringName = &"general/Idle_A"

	if is_moving:
		animation_name = &"movement/Running_A"

	if animation_player.current_animation != animation_name:
		animation_player.play(animation_name, 0.15)

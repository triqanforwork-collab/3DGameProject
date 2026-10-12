class_name PlayerInput
extends Node
## Đọc InputMap (bàn phím và joystick cảm ứng đều đi qua các action này)
## rồi ghi vào Fighter cha. Hướng di chuyển tính theo góc camera (cả camera trên cao lẫn sau lưng).

## Nhấn lao hơi sớm (đang hồi chiêu / chưa chạm sàn) vẫn được ghi nhận trong khoảng này.
@export var dash_buffer_time: float = 0.12

var _dash_buffer := 0.0

@onready var fighter: Fighter = get_parent()


func _ready() -> void:
	# Chạy trước Fighter trong cùng physics tick để input không trễ một frame.
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	if not fighter.controls_enabled:
		fighter.move_input = Vector3.ZERO
		_dash_buffer = 0.0
		return

	var v := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var dir := Vector3(v.x, 0.0, v.y)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var yaw := cam.global_rotation.y
		dir = dir.rotated(Vector3.UP, yaw)
	fighter.move_input = dir

	if Input.is_action_just_pressed(&"dash"):
		_dash_buffer = dash_buffer_time
	if _dash_buffer > 0.0:
		_dash_buffer -= delta
		var aim := dir
		# Camera sau lưng: đứng yên mà lao thì lao theo hướng camera (tâm ngắm giữa màn hình).
		var rig := cam as CameraRig
		if aim.length_squared() < 0.01 and rig and rig.mode == CameraRig.Mode.THIRD_PERSON:
			aim = rig.flat_forward()
		if fighter.try_dash(aim):
			_dash_buffer = 0.0

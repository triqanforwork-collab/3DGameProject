class_name CameraRig
extends Camera3D
## ORBIT: xoay vòng quanh sàn (menu). SHOWCASE: quay cận một nhân vật (chọn nhân vật).
## FOLLOW: nhìn chéo từ trên cao, bám nhẹ người chơi, tiến gần hơn khi sàn thu hẹp (mặc định).
## THIRD_PERSON: sau lưng người chơi; chuột (PC) hoặc kéo ngón tay (điện thoại) để xoay.

enum Mode { ORBIT, SHOWCASE, FOLLOW, THIRD_PERSON }

@export var pitch_deg: float = 50.0
@export var max_distance: float = 25.0
@export var min_distance: float = 15.0
## 0 = luôn nhìn tâm sàn, 1 = luôn nhìn người chơi.
@export_range(0.0, 1.0) var follow_weight: float = 0.35
@export var smoothing: float = 4.0
@export var orbit_speed: float = 0.12

@export_group("Cận cảnh (chọn nhân vật)")
@export var showcase_distance: float = 6.0
@export var showcase_pitch_deg: float = 14.0
## Camera lắc qua lại quanh mặt trước nhân vật (radian), không quay ra sau lưng.
@export var showcase_swing: float = 0.6
## Dời nhân vật sang trái khung hình để chừa chỗ cho bảng thông tin bên phải.
@export var showcase_side_offset: float = 1.6

@export_group("Sau lưng (góc nhìn thứ ba)")
@export var tps_distance: float = 6.0
## Độ cao điểm xoay (tính từ chân nhân vật).
@export var tps_height: float = 2.0
@export var tps_pitch_deg: float = 18.0
@export var tps_min_pitch_deg: float = 5.0
@export var tps_max_pitch_deg: float = 45.0
## Camera nhìn vào điểm phía trước nhân vật (m) => nhân vật nằm ở nửa dưới khung hình.
@export var tps_look_ahead: float = 4.0
## Radian mỗi pixel kéo chuột / ngón tay.
@export var look_sensitivity: float = 0.004

var arena: Arena
var mode: Mode = Mode.ORBIT
var target: Node3D

var _yaw := 0.0
var _pitch := deg_to_rad(50.0)
var _focus := Vector3.ZERO
var _distance := 25.0
var _shake := 0.0
var _tps_yaw := 0.0
var _tps_pitch := 0.0
var _tps_pivot := Vector3.ZERO


func set_mode(new_mode: Mode, new_target: Node3D = null) -> void:
	if new_mode == Mode.THIRD_PERSON and new_target:
		# Đặt camera ngay sau lưng theo hướng nhìn hiện tại của nhân vật.
		var f := new_target as Fighter
		var facing := f.facing if f else Vector3.FORWARD
		if mode != Mode.THIRD_PERSON or new_target != target:
			_tps_yaw = atan2(-facing.x, -facing.z)
			_tps_pitch = deg_to_rad(tps_pitch_deg)
			_tps_pivot = new_target.global_position + Vector3.UP * tps_height
	mode = new_mode
	target = new_target


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Xoay camera sau lưng theo độ dời (pixel) của chuột hoặc ngón tay.
func add_look(relative: Vector2) -> void:
	if mode != Mode.THIRD_PERSON:
		return
	_tps_yaw = wrapf(_tps_yaw - relative.x * look_sensitivity, -PI, PI)
	_tps_pitch = clampf(_tps_pitch + relative.y * look_sensitivity,
		deg_to_rad(tps_min_pitch_deg), deg_to_rad(tps_max_pitch_deg))


## Hướng camera đang nhìn trên mặt phẳng XZ (dùng để lao khi đứng yên ở chế độ sau lưng).
func flat_forward() -> Vector3:
	var fwd := -global_basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		add_look(event.relative)


func _process(delta: float) -> void:
	var k := 1.0 - exp(-smoothing * delta)
	var jitter := Vector3.ZERO
	if _shake > 0.0:
		jitter = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = maxf(_shake - delta * 2.5, 0.0)
	if mode == Mode.THIRD_PERSON:
		_process_third_person(delta, jitter * 0.4)
		return

	var desired_focus := Vector3.ZERO
	var desired_distance := max_distance
	var desired_pitch := deg_to_rad(pitch_deg)
	var has_target := target != null and is_instance_valid(target)

	match mode:
		Mode.ORBIT:
			_yaw = wrapf(_yaw + orbit_speed * delta, -PI, PI)
		Mode.SHOWCASE:
			_yaw = lerp_angle(_yaw, sin(Time.get_ticks_msec() * 0.0005) * showcase_swing, k)
			if has_target:
				desired_focus = target.global_position + Vector3.UP * 1.3 + global_basis.x * showcase_side_offset
			desired_distance = showcase_distance
			desired_pitch = deg_to_rad(showcase_pitch_deg)
		Mode.FOLLOW:
			_yaw = lerp_angle(_yaw, 0.0, k)
			var f: Fighter = target as Fighter if has_target else null
			if f and not f.is_eliminated:
				desired_focus = target.global_position * follow_weight
				desired_focus.y = 0.0
			if arena:
				var ratio := arena.get_current_radius() / arena.arena_radius
				desired_distance = lerpf(min_distance, max_distance, ratio)

	_focus = _focus.lerp(desired_focus, k)
	_distance = lerpf(_distance, desired_distance, k * 0.6)
	_pitch = lerpf(_pitch, desired_pitch, k)

	var offset := Vector3(0.0, sin(_pitch), cos(_pitch)) * _distance
	offset = offset.rotated(Vector3.UP, _yaw)
	global_position = _focus + offset + jitter
	look_at(_focus + Vector3.UP * 0.5 * float(mode != Mode.SHOWCASE) + jitter)


func _process_third_person(delta: float, jitter: Vector3) -> void:
	var f: Fighter = target as Fighter if target != null and is_instance_valid(target) else null
	# Người chơi đã rơi/bị loại: camera đứng yên nhìn theo.
	if f == null or f.is_eliminated or not f.visible:
		return
	_tps_pivot = _tps_pivot.lerp(f.global_position + Vector3.UP * tps_height, 1.0 - exp(-12.0 * delta))
	var back := Vector3(sin(_tps_yaw), 0.0, cos(_tps_yaw))
	global_position = _tps_pivot + back * cos(_tps_pitch) * tps_distance \
		+ Vector3.UP * sin(_tps_pitch) * tps_distance + jitter
	look_at(_tps_pivot - back * tps_look_ahead + jitter)

class_name WindGusts
extends Node3D
## Gió giật (Đấu Trường Mây): định kỳ báo trước (vệt gió bay + thông báo) rồi thổi theo một hướng
## ngẫu nhiên, đẩy mọi nhân vật đang trên sàn. Gió yếu hơn tốc độ chạy nên vẫn chống lại được.
## Chỉ chạy khi sàn đang đấu (arena.running); hết trận / chơi lại thì tự về trạng thái đầu.

@export var first_delay: float = 12.0
@export var interval: float = 11.0
@export var warning_time: float = 1.5
@export var gust_time: float = 3.0
## Tốc độ gió đẩy lúc mạnh nhất (m/s).
@export var strength: float = 1.8

## Hướng gió của đợt đang báo / đang thổi.
var direction := Vector3.FORWARD
var _calm_left := 0.0
var _warn_left := 0.0
var _gust_left := 0.0

@onready var arena: Arena = $"../Arena"
@onready var level: Level = get_parent()
@onready var streaks: CPUParticles3D = $Streaks


func _ready() -> void:
	add_to_group(&"hazards")
	process_physics_priority = -1  # đẩy trước khi Fighter di chuyển trong cùng tick
	_reset()


func _reset() -> void:
	_calm_left = first_delay
	_warn_left = 0.0
	_gust_left = 0.0
	streaks.emitting = false


func _physics_process(delta: float) -> void:
	if not arena.running:
		_reset()
		return
	if _gust_left > 0.0:
		var push := direction * strength * gust_amount()
		for node in get_tree().get_nodes_in_group(&"fighters"):
			var f := node as Fighter
			if f.is_active():
				f.push_velocity += push
		_gust_left -= delta
		if _gust_left <= 0.0:
			streaks.emitting = false
			_calm_left = interval
	elif _warn_left > 0.0:
		_warn_left -= delta
		if _warn_left <= 0.0:
			start_gust(direction)
	else:
		_calm_left -= delta
		if _calm_left <= 0.0:
			warn(Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU))


## Báo trước: vệt gió bay theo hướng `dir`, sau warning_time thì gió thổi thật.
func warn(dir: Vector3) -> void:
	_aim(dir)
	_warn_left = warning_time
	level.announced.emit("GIÓ GIẬT!")
	Sfx.play(&"dash", 0.05, 0.5)


func start_gust(dir: Vector3) -> void:
	_aim(dir)
	_warn_left = 0.0
	_gust_left = gust_time
	Sfx.play(&"dash", 0.05, 0.4)


## 0..1: mạnh dần lúc đầu đợt, yếu dần lúc cuối đợt.
func gust_amount() -> float:
	if _gust_left <= 0.0:
		return 0.0
	return clampf(minf(gust_time - _gust_left, _gust_left) / 0.4, 0.0, 1.0)


## Bot: chạy hơi ngược hướng gió khi gió sắp / đang thổi.
func bot_steer(_pos: Vector3) -> Vector3:
	return -direction * 0.8 if _gust_left > 0.0 or _warn_left > 0.0 else Vector3.ZERO


## Vệt gió xuất phát từ phía đầu gió, bay ngang qua sàn.
func _aim(dir: Vector3) -> void:
	dir.y = 0.0
	direction = dir.normalized()
	streaks.position = arena.position - direction * 11.0 + Vector3.UP * 1.5
	streaks.direction = direction
	streaks.emitting = true

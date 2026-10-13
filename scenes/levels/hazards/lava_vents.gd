class_name LavaVents
extends Node3D
## Miệng dung nham (Miệng Núi Lửa): định kỳ chọn vài điểm trên sàn, báo bằng vòng đỏ rồi phun,
## hất văng ai đứng trong bán kính. Điểm đầu tiên luôn nhắm gần một nhân vật để ép mọi người di chuyển.
## Chỉ chạy khi sàn đang đấu (arena.running); hết trận / chơi lại thì tự về trạng thái đầu.

@export var first_delay: float = 8.0
@export var interval: float = 6.5
@export var vents_per_wave: int = 2
@export var warning_time: float = 1.5
@export var radius: float = 1.6
@export var force: float = 5.5
@export var lift: float = 5.5

## Các điểm đang cảnh báo, sắp phun.
var pending: Array[Vector3] = []
var _calm_left := 0.0
var _warn_left := 0.0
var _announced := false

@onready var arena: Arena = $"../Arena"
@onready var level: Level = get_parent()


func _ready() -> void:
	add_to_group(&"hazards")
	_reset()


func _reset() -> void:
	_calm_left = first_delay
	_warn_left = 0.0
	pending.clear()
	_announced = false


func _physics_process(delta: float) -> void:
	if not arena.running:
		_reset()
		return
	if not pending.is_empty():
		_warn_left -= delta
		if _warn_left <= 0.0:
			_erupt()
	else:
		_calm_left -= delta
		if _calm_left <= 0.0:
			warn(_pick_points())


## Đánh dấu các điểm sắp phun; sau warning_time thì phun.
func warn(points: Array[Vector3]) -> void:
	pending = points
	_warn_left = warning_time
	for p in points:
		Effects.landing_marker(self, p, radius)
	Sfx.play(&"warn", 0.05, 0.7)
	if not _announced:
		_announced = true
		level.announced.emit("DUNG NHAM SẮP PHUN!")


func _erupt() -> void:
	for p in pending:
		Effects.lava_burst(self, p)
		for node in get_tree().get_nodes_in_group(&"fighters"):
			var f := node as Fighter
			var off := f.global_position - p
			if not f.is_active() or absf(off.y) > 1.5:
				continue
			off.y = 0.0
			var d := off.length()
			if d > radius:
				continue
			var dir := off / d if d > 0.05 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
			f.receive_hit(null, dir, force, lift)
	Sfx.play(&"drop", 0.1, 0.7)
	pending.clear()
	_calm_left = interval


## Bot: tránh xa các điểm đang cảnh báo.
func bot_steer(pos: Vector3) -> Vector3:
	var steer := Vector3.ZERO
	var reach := radius + 1.2
	for p in pending:
		var off := pos - p
		off.y = 0.0
		var d := off.length()
		if d < reach and d > 0.01:
			steer += off / d * 1.5 * (1.0 - d / reach)
	return steer


func _pick_points() -> Array[Vector3]:
	var center := arena.global_position + Vector3.UP * 0.05
	var r := maxf(arena.get_safe_radius() - 0.8, 0.5)
	var targets := get_tree().get_nodes_in_group(&"fighters").filter(func(f): return f.is_active())
	var points: Array[Vector3] = []
	for attempt in vents_per_wave * 6:
		if points.size() >= vents_per_wave:
			break
		var off := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		if points.is_empty() and not targets.is_empty():
			var t: Fighter = targets.pick_random()
			off = t.global_position - center + off * randf() * 1.2
		else:
			off *= r * sqrt(randf())
		off.y = 0.0
		var p := center + off.limit_length(r)
		if points.all(func(q: Vector3): return q.distance_to(p) > radius * 2.0):
			points.append(p)
	return points

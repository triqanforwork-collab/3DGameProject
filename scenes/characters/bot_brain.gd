class_name BotBrain
extends Node
## AI đơn giản cho bot: chọn mục tiêu, áp sát từ phía trong sàn, lao khi đủ gần,
## tránh mép và chạy về vùng an toàn khi sàn sắp thu hẹp.
## Quyết định được cập nhật theo chu kỳ think_interval, không phải mỗi frame.

@export var think_interval: float = 0.3
## Độ trễ từ lúc quyết định lao tới lúc lao thật (người chơi có thời gian né).
@export var reaction_time: float = 0.35
## Sai số hướng lao (độ).
@export var aim_error_deg: float = 15.0
@export var dash_range: float = 3.0
## Bot cố giữ cách mép an toàn ít nhất khoảng này.
@export var edge_margin: float = 1.6
## Xác suất lao khi có cơ hội (0..1).
@export_range(0.0, 1.0) var aggression: float = 0.55

var arena: Arena

var _think_left := 0.0
var _target: Fighter
var _move_dir := Vector3.ZERO
var _pending_dash_left := -1.0
var _pending_dash_dir := Vector3.ZERO

@onready var fighter: Fighter = get_parent()


func _ready() -> void:
	process_physics_priority = -1
	_think_left = randf() * think_interval


func _physics_process(delta: float) -> void:
	if not fighter.controls_enabled:
		fighter.move_input = Vector3.ZERO
		_pending_dash_left = -1.0
		return

	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = think_interval * randf_range(0.8, 1.2)
		_think()

	if _pending_dash_left >= 0.0:
		_pending_dash_left -= delta
		if _pending_dash_left < 0.0:
			fighter.try_dash(_pending_dash_dir)

	fighter.move_input = _move_dir


func _think() -> void:
	var pos := _flat(fighter.global_position)
	var safe_radius := arena.get_safe_radius() if arena else 10.0
	var limit := maxf(safe_radius - edge_margin, 0.5)

	if not _is_valid_target(_target) or randf() < 0.1:
		_target = _pick_target(pos)

	var desired := Vector3.ZERO
	if _target:
		var target_pos := _flat(_target.global_position)
		var to_target := target_pos - pos
		var dist := to_target.length()
		# Đứng phía trong (gần tâm hơn mục tiêu) để cú lao đẩy mục tiêu ra mép.
		var approach := target_pos
		if target_pos.length() > 1.0 and dist > 1.6:
			approach = target_pos - target_pos.normalized() * 1.4
		desired = (approach - pos).normalized()

		if dist < dash_range and _pending_dash_left < 0.0 and fighter.can_dash() \
				and randf() < aggression:
			var aim := to_target.normalized().rotated(Vector3.UP,
				deg_to_rad(randf_range(-aim_error_deg, aim_error_deg)))
			var landing := pos + aim * fighter.dash_speed * fighter.dash_duration
			# Không tự lao ra khỏi vùng an toàn (thỉnh thoảng vẫn liều).
			if landing.length() < safe_radius - 0.6 or randf() < 0.03:
				_pending_dash_dir = aim
				_pending_dash_left = reaction_time * randf_range(0.7, 1.3)

	# Tránh mép: càng gần/ra ngoài vùng an toàn càng kéo mạnh về tâm.
	var dist_center := pos.length()
	if dist_center > limit and dist_center > 0.01:
		var w := clampf((dist_center - limit) / edge_margin, 0.0, 1.0)
		desired = desired.lerp(-pos / dist_center, 0.4 + 0.6 * w)

	_move_dir = desired.limit_length(1.0)


func _pick_target(pos: Vector3) -> Fighter:
	# Chọn ngẫu nhiên một trong hai đối thủ gần nhất để bot không dồn hết vào một người.
	var best: Array[Fighter] = []
	var best_d: Array[float] = []
	for node in fighter.get_tree().get_nodes_in_group(&"fighters"):
		var f := node as Fighter
		if not _is_valid_target(f):
			continue
		var d := pos.distance_squared_to(_flat(f.global_position))
		var i := 0
		while i < best_d.size() and best_d[i] < d:
			i += 1
		best.insert(i, f)
		best_d.insert(i, d)
	if best.is_empty():
		return null
	return best[randi() % mini(2, best.size())]


func _is_valid_target(f: Fighter) -> bool:
	return f != null and is_instance_valid(f) and f != fighter and f.is_active()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

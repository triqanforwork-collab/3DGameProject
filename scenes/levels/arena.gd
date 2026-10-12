class_name Arena
extends Node3D
## Sàn đấu: node "Center" + các vòng trong "Rings" (Ring0 = ngoài cùng), đặt sẵn trong scene.
## Mỗi vòng là StaticBody3D có Mesh (surface 0 = mặt trên, 1 = thành gỗ), Collision, Rope.
## Script này chỉ lo đếm giờ, cảnh báo và thả vòng. Mesh/collision được bake sẵn bằng
## tools/bake_arena.gd (chạy lại khi đổi bán kính/độ sâu).

signal ring_warning(index: int)
signal ring_dropped(index: int)

@export_group("Kích thước (dùng khi bake)")
@export var arena_radius: float = 10.0
@export var center_radius: float = 3.5
@export var tower_depth: float = 30.0
@export_range(16, 96) var segments: int = 48

@export_group("Thu hẹp")
@export var first_drop_delay: float = 20.0
@export var drop_interval: float = 15.0
@export var warning_time: float = 4.0
@export var warning_color := Color(1.0, 0.25, 0.1)

var running := false
var _rings: Array[StaticBody3D] = []
var _next_ring := 0
var _time_to_drop := 0.0
var _warned := false
var _tweens: Array[Tween] = []

@onready var rings_root: Node3D = $Rings


func _ready() -> void:
	for child in rings_root.get_children():
		_rings.append(child as StaticBody3D)
	reset()


func ring_count() -> int:
	return _rings.size()


## Đưa mọi vòng về chỗ cũ, bật lại collision, reset timer (dùng khi bắt đầu / chơi lại).
func reset() -> void:
	running = false
	for t in _tweens:
		if t.is_valid():
			t.kill()
	_tweens.clear()
	for ring in _rings:
		ring.position.y = 0.0
		ring.show()
		ring.collision_layer = 1
		ring.get_node(^"Collision").disabled = false
		_top_material(ring).emission_enabled = false
	_next_ring = 0
	_warned = false
	_time_to_drop = first_drop_delay


func start() -> void:
	running = true


func stop() -> void:
	running = false


## Bán kính ngoài của vòng i (0 = ngoài cùng); i = số vòng trả về bán kính phần trung tâm.
func ring_outer_radius(i: int) -> float:
	var width := (arena_radius - center_radius) / ring_count()
	return arena_radius - i * width


func get_current_radius() -> float:
	return ring_outer_radius(_next_ring)


## Bán kính bot nên ở trong: nếu vòng ngoài đang cảnh báo thì không tính vòng đó.
func get_safe_radius() -> float:
	if is_warning():
		return ring_outer_radius(_next_ring + 1)
	return get_current_radius()


func is_warning() -> bool:
	return _next_ring < _rings.size() and _time_to_drop <= warning_time


func is_fully_shrunk() -> bool:
	return _next_ring >= _rings.size()


## Giây tới lần rơi vòng kế tiếp; -1 nếu đã chỉ còn phần trung tâm.
func get_time_to_drop() -> float:
	return -1.0 if is_fully_shrunk() else maxf(_time_to_drop, 0.0)


func _physics_process(delta: float) -> void:
	if not running or is_fully_shrunk():
		return
	_time_to_drop -= delta
	if is_warning():
		var mat := _top_material(_rings[_next_ring])
		if not _warned:
			_warned = true
			mat.emission_enabled = true
			mat.emission = warning_color
			ring_warning.emit(_next_ring)
		# Nhấp nháy nhanh dần khi sắp rơi.
		var t := 1.0 - _time_to_drop / warning_time
		mat.emission_energy_multiplier = (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * lerpf(6.0, 22.0, t))) * 1.2
	if _time_to_drop <= 0.0:
		_drop_ring(_next_ring)
		_next_ring += 1
		_warned = false
		_time_to_drop = drop_interval


func _drop_ring(i: int) -> void:
	var ring := _rings[i]
	# Tắt collision ngay trong physics tick này để người đứng trên vòng rơi theo.
	ring.collision_layer = 0
	ring.get_node(^"Collision").disabled = true
	_top_material(ring).emission_enabled = false
	Effects.dust_ring(self, global_position, ring_outer_radius(i + 1), ring_outer_radius(i))
	var tween := ring.create_tween()
	tween.tween_property(ring, ^"position:y", -tower_depth - 10.0, 2.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(ring.hide)
	_tweens.append(tween)
	ring_dropped.emit(i)


func _top_material(ring: Node) -> StandardMaterial3D:
	return (ring.get_node(^"Mesh") as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D

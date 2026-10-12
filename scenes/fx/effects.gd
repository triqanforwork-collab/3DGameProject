class_name Effects
extends RefCounted
## Tạo hiệu ứng tại chỗ trong lúc chơi. Hình dáng/màu/số hạt chỉnh trong các scene .tscn.

const HIT_BURST := preload("res://scenes/fx/hit_burst.tscn")
const DUST_RING := preload("res://scenes/fx/dust_ring.tscn")
const POPUP_TEXT := preload("res://scenes/fx/popup_text.tscn")
const LANDING_MARKER := preload("res://scenes/fx/landing_marker.tscn")


static func _spawn(scene: PackedScene, parent: Node, pos: Vector3) -> Node3D:
	var fx := scene.instantiate() as Node3D
	parent.add_child(fx)
	fx.global_position = pos
	return fx


## Tia sáng + vòng sóng xung kích khi lao trúng.
static func hit_burst(parent: Node, pos: Vector3) -> void:
	_spawn(HIT_BURST, parent, pos)


## Bụi bốc lên quanh một vành khi vòng sàn rơi.
static func dust_ring(parent: Node, center: Vector3, r_in: float, r_out: float) -> void:
	var p := _spawn(DUST_RING, parent, center).get_node(^"Particles") as CPUParticles3D
	p.emission_ring_inner_radius = r_in
	p.emission_ring_radius = r_out


## Chữ bay lên rồi mờ dần, ví dụ "+1" khi đẩy được đối thủ ra ngoài.
static func popup_text(parent: Node, pos: Vector3, text: String, color: Color) -> void:
	var label := _spawn(POPUP_TEXT, parent, pos).get_node(^"Label") as Label3D
	label.text = text
	label.modulate = color


## Vòng đỏ nhấp nháy trên sàn báo chỗ nhân vật hồi sinh sắp rơi xuống.
static func landing_marker(parent: Node, pos: Vector3) -> void:
	_spawn(LANDING_MARKER, parent, pos)

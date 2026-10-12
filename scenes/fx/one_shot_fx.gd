extends Node3D
## Gắn vào root của scene hiệu ứng (hit_burst.tscn, dust_ring.tscn, popup_text.tscn):
## khi xuất hiện thì bật mọi CPUParticles3D con (AnimationPlayer con tự autoplay),
## rồi tự xoá sau `lifetime` giây.

@export var lifetime: float = 1.0


func _ready() -> void:
	for p in find_children("*", "CPUParticles3D", true, false):
		(p as CPUParticles3D).restart()
	get_tree().create_timer(lifetime, false).timeout.connect(queue_free)

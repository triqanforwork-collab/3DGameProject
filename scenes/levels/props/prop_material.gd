extends Node3D
## Gán một material cho mọi mesh con: cột đá KayKit dùng chung model nhưng mỗi màn một chất liệu
## (đá phủ băng ở Đỉnh Băng, đá bazan nứt dung nham ở Núi Lửa).

@export var material: Material


func _ready() -> void:
	for m in find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = material

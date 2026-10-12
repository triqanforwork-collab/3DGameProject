@tool
extends EditorScript
## Bake lại mesh + collision cho sàn đấu của level đang mở.
## Cách dùng: mở level (vd. scenes/levels/sky_arena.tscn) -> mở file này trong Script editor
## -> File > Run (Ctrl+Shift+X) -> Ctrl+S để lưu scene.
## Kích thước lấy từ các thông số "Kích thước" của node Arena; số vòng = số node trong Arena/Rings
## (muốn thêm vòng: nhân bản một RingN rồi bake lại).


func _run() -> void:
	var scene := get_scene()
	var arena := scene.find_child("Arena", true, false) if scene.name != "Arena" else scene
	if arena == null:
		push_error("Không tìm thấy node Arena trong scene đang mở.")
		return
	var out_dir := "res://assets/arena/%s" % scene.scene_file_path.get_file().get_basename()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rings: Array = arena.get_node("Rings").get_children()
	ArenaMeshBuilder.bake_band(arena.get_node("Center"), 0.0, arena.center_radius, arena, out_dir, "center")
	for i in rings.size():
		var r := ArenaMeshBuilder.ring_radii(arena.arena_radius, arena.center_radius, rings.size(), i)
		ArenaMeshBuilder.bake_band(rings[i], r.x, r.y, arena, out_dir, "ring%d" % i)
	print("Đã bake %d vòng vào %s. Nhớ Ctrl+S để lưu scene." % [rings.size(), out_dir])


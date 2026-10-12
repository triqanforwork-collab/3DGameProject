class_name ArenaMeshBuilder
extends RefCounted
## Dựng mesh một "dải" sàn: mặt trên (đĩa hoặc vành khăn) + thành ngoài như thùng gỗ.
## Surface 0 = mặt trên (màu lấy từ material của từng vòng), surface 1 = thành gỗ.
## Chỉ dùng lúc bake (tools/bake_arena.gd), game không gọi tới.

const WOOD := Color(0.5, 0.33, 0.2)


static func ring_radii(arena_radius: float, center_radius: float, ring_count: int, i: int) -> Vector2:
	var width := (arena_radius - center_radius) / ring_count
	return Vector2(arena_radius - (i + 1) * width, arena_radius - i * width)


static func build(r_in: float, r_out: float, depth: float, segments: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(r_out * 1000.0)
	var step := TAU / segments
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)

	for s in segments:
		var d0 := Vector3(cos(s * step), 0.0, sin(s * step))
		var d1 := Vector3(cos((s + 1) * step), 0.0, sin((s + 1) * step))
		# Mặt trên: hệ số sáng/tối nhẹ mỗi lát cho cảm giác low-poly (Godot: mặt trước theo chiều kim đồng hồ).
		var shade := Color.WHITE.darkened(rng.randf_range(0.0, 0.07))
		if r_in <= 0.0:
			_tri(top, [Vector3.ZERO, d0 * r_out, d1 * r_out], Vector3.UP, shade)
		else:
			_tri(top, [d0 * r_in, d0 * r_out, d1 * r_out], Vector3.UP, shade)
			_tri(top, [d0 * r_in, d1 * r_out, d1 * r_in], Vector3.UP, shade)

		# Thành ngoài: viền sáng, ván xen kẽ, đai sắt tối.
		var normal := ((d0 + d1) * 0.5).normalized()
		var plank := WOOD.darkened(0.12) if s % 2 == 0 else WOOD
		var rows := [
			[0.0, -0.35, WOOD.lightened(0.25)],
			[-0.35, -6.0, plank],
			[-6.0, -6.7, Color(0.22, 0.17, 0.14)],
			[-6.7, -depth, plank.darkened(0.1)],
		]
		for row in rows:
			var y0 := Vector3(0, row[0], 0)
			var y1 := Vector3(0, row[1], 0)
			_tri(wall, [d0 * r_out + y0, d0 * r_out + y1, d1 * r_out + y0], normal, row[2])
			_tri(wall, [d1 * r_out + y0, d0 * r_out + y1, d1 * r_out + y1], normal, row[2])

	var mesh := top.commit()
	wall.commit(mesh)
	return mesh


## Collision chỉ cần mặt trên + thành ngoài, lấy thẳng từ mesh.
static func build_shape(mesh: ArrayMesh) -> ConcavePolygonShape3D:
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	return shape


## Dựng + lưu mesh/collision của một dải ra file .res rồi gán vào node (Mesh, Collision, Rope).
static func bake_band(band: Node, r_in: float, r_out: float, arena: Node, out_dir: String, file: String) -> void:
	var mesh := ArenaMeshBuilder.build(r_in, r_out, arena.tower_depth, arena.segments)
	var shape := ArenaMeshBuilder.build_shape(mesh)
	# take_over_path: thay luôn bản cũ đang được cache cùng đường dẫn.
	mesh.take_over_path("%s/%s_mesh.res" % [out_dir, file])
	shape.take_over_path("%s/%s_shape.res" % [out_dir, file])
	ResourceSaver.save(mesh)
	ResourceSaver.save(shape)
	(band.get_node("Mesh") as MeshInstance3D).mesh = mesh
	(band.get_node("Collision") as CollisionShape3D).shape = shape
	var rope := (band.get_node("Rope") as MeshInstance3D).mesh as TorusMesh
	rope.inner_radius = r_out - 0.14
	rope.outer_radius = r_out + 0.1


static func _tri(st: SurfaceTool, pts: Array, normal: Vector3, color: Color) -> void:
	for p in pts:
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(p)

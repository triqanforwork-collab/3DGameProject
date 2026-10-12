extends SceneTree
## Chụp ảnh màn hình vài thời điểm để kiểm tra hình ảnh (cần chạy có cửa sổ, không headless):
##   Godot --path . --resolution 1280x720 --script res://tests/capture.gd -- <thư_mục_ra>
## Kỷ lục ghi ra file riêng (user://capture_records.cfg), không đụng kỷ lục thật.

var out_dir := "user://captures"
var main: Node


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Records.path = "user://capture_records.cfg"
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## Thắng nhanh màn hiện tại để chuyển màn (cho mọi bot rơi khỏi sàn).
func _win_stage() -> void:
	while main.state != main.State.ENDED:
		for f: Fighter in main.fighters.slice(1):
			f.respawns_left = 0
			if f.is_active():
				f._fall_off()
		await physics_frame


func _run() -> void:
	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await _wait(1.0)
	main.ui.play_requested.emit()
	main.ui.select_confirmed.emit()
	await _wait(4.5)
	await _shot("01_stage1")
	await _win_stage()
	await _wait(0.5)
	await _shot("02_stage1_clear")
	main.ui.result_primary.emit()
	await _wait(4.5)
	await _shot("03_stage2_ice")
	await _win_stage()
	main.ui.result_primary.emit()
	await _wait(4.5)
	await _shot("04_stage3_volcano")
	# Hồi sinh: cho một bot rơi rồi chụp lúc đang rơi xuống + vòng đỏ.
	var bot: Fighter = main.fighters[1]
	bot.global_position = Vector3(30, -13, 0)
	await _wait(main.respawn_delay + 0.7)
	await _shot("05_respawn_falling")
	# Camera sau lưng: bật trong menu Tạm dừng.
	main.toggle_pause()
	main.ui.get_node("%TPSToggle").button_pressed = true
	await _shot("06_pause_tps_toggle")
	main.toggle_pause()
	await _wait(1.0)
	await _shot("07_third_person")
	main.camera.add_look(Vector2(-500, 40))
	await _wait(1.0)
	await _shot("08_third_person_turned")
	main.set_third_person(false)
	await _win_stage()
	await _wait(0.5)
	await _shot("09_clear_run")
	main.go_to_menu()
	main.ui.get_node("%RecordsButton").pressed.emit()
	await _wait(0.5)
	await _shot("10_records")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.path))
	main.queue_free()
	await process_frame
	quit()

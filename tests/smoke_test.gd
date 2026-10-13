extends SceneTree
## Kiểm thử tự động (headless). Chạy:
##   Godot --headless --path . --fixed-fps 60 --script res://tests/smoke_test.gd
## In "ALL TESTS PASSED" nếu mọi assert đều đúng, ngược lại thoát với mã 1.

const COUNTDOWN_FRAMES := 60 * 3 + 10

var main: Node3D
var sfx: Node  # autoload Sfx (script SceneTree không gọi trực tiếp được tên autoload)
var failures := 0
## Quãng trượt của người chơi khi bị hất ở màn 1, để so với sàn băng màn 2.
var slide_stage1 := 0.0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# Kỷ lục ghi ra file riêng để không đụng tới kỷ lục thật.
	Records.path = "user://test_records.cfg"
	sfx = root.get_node("Sfx")
	GameSettings.path = "user://test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.path))
	# Autoload Sfx đã nạp cài đặt thật của máy lúc khởi động: đưa âm lượng về mặc định.
	GameSettings.volumes = {&"Master": 1.0, &"Music": 0.7, &"SFX": 1.0}
	GameSettings.apply_audio()

	main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)

	print("[menu]")
	check(main.state == main.State.MENU and main.ui.menu.visible, "vào menu chính")
	check(main.roster.size() == 8, "roster có 8 nhân vật")
	check(main.stages.size() == 3, "có 3 màn")
	check(main.level.stage_name == "Đấu Trường Mây", "menu dùng sàn màn 1")
	check(main.ui.get_node_or_null("%CreditsButton") == null and main.ui.get_node_or_null("%Credits") == null, "menu chính không còn Credits")
	check(main.ui.get_node("%Subtitle").text == "Đấu trường sinh tồn — đẩy tất cả xuống vực!", "phụ đề mới")
	check(main.ui.get_node("%Guide").find_child("Body").text.contains("KayKit"), "nguồn tài nguyên nằm trong Hướng dẫn")
	var menu_music: AudioStream = sfx.current_music()
	check(menu_music != null and menu_music.resource_path.ends_with("goblins_den.wav"), "menu phát nhạc Goblins Den")

	await _test_characters()
	await _test_stage1_basics()
	await _test_lose_and_retry()
	await _test_progression_to_stage3()
	await _test_respawn()
	await _test_lava_vents()
	await _test_pause_restart_and_draw()
	await _test_clear_run_and_records()
	await _test_third_person()
	await _test_misc()
	await _test_settings()
	await _test_touch()

	print("")
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Records.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.path))
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)


# ---------------------------------------------------------------- nhân vật

func _test_characters() -> void:
	print("[8 nhân vật: scene, model, vũ khí, animation]")
	main.enter_select()
	var names := {}
	for i in main.roster.size():
		if i > 0:
			main.ui.select_changed.emit(1)
		await frames(2)
		var f: Fighter = main.fighters[0]
		check(main.fighters.size() == 1 and main.selected_index == i, "xem nhân vật %d: %s" % [i + 1, f.character_name])
		names[f.character_name] = true
		for anim in [Fighter.ANIM_IDLE, Fighter.ANIM_RUN, Fighter.ANIM_HIT, Fighter.ANIM_FALL, Fighter.ANIM_LAND]:
			if not f.animation_player.has_animation(anim):
				check(false, "%s thiếu animation %s" % [f.character_name, anim])
		var att := f.visual.get_node_or_null(^"RightHand") as BoneAttachment3D
		if att == null:
			att = f.visual.get_node_or_null(^"LeftHand") as BoneAttachment3D
		check(att != null and att.get_child_count() > 0 and att.global_position.y > 0.3, "  vũ khí gắn vào tay")
		check(main.ui.get_node("%CharName").text == f.character_name, "  UI hiện đúng tên")
	check(names.size() == 8, "8 tên nhân vật khác nhau")
	main.ui.select_changed.emit(1)
	check(main.selected_index == 0, "chọn vòng lại về đầu danh sách")


# ---------------------------------------------------------------- màn 1

func _test_stage1_basics() -> void:
	print("[bắt đầu lượt chơi: màn 1]")
	var chosen_name: String = main.fighters[0].character_name
	main.ui.select_confirmed.emit()
	await frames(5)
	check(main.stage_index == 0 and main.level.stage_name == "Đấu Trường Mây", "luôn bắt đầu từ màn 1")
	check(main.player.character_name == chosen_name, "vào trận bằng nhân vật đã chọn")
	check(main.fighters.size() == 8, "màn 1: 1 người chơi + 7 bot")
	_check_on_markers()
	check(main.state == main.State.COUNTDOWN and main.run_time == 0.0, "đang đếm ngược, đồng hồ chưa chạy")
	await frames(COUNTDOWN_FRAMES)
	check(main.state == main.State.PLAYING and main.arena.running, "bắt đầu trận sau đếm ngược")
	check(main.run_time > 0.0, "đồng hồ lượt chơi chạy khi đang đấu")
	check(main.ui.alive_label.text.begins_with("MÀN 1/3"), "HUD hiện màn 1/3")
	var view_w: float = main.ui.get_viewport().get_visible_rect().size.x
	var hud_ok := true
	for n in ["%PauseButton", "%TimerLabel", "%AliveLabel"]:
		var r: Rect2 = main.ui.get_node(n).get_global_rect()
		hud_ok = hud_ok and r.position.x >= 0.0 and r.end.x <= view_w
	check(hud_ok, "HUD nằm trong khung hình (không bị lề vùng an toàn đẩy ra ngoài)")
	check(sfx.current_music().resource_path.ends_with("stage1_workshop_breadboard.ogg") and sfx.get_node("Music").playing,
		"màn 1 phát nhạc Workshop BREADBOARD")

	print("[di chuyển + animation]")
	var p: Fighter = main.player
	var bots: Array = main.fighters.slice(1)
	_freeze_bots()
	_place(p, Vector3(-2, 0.05, 0))
	_place(bots[0], Vector3(0, 0.05, 0))
	for i in range(1, bots.size()):
		var ang := TAU * i / bots.size()
		_place(bots[i], Vector3(cos(ang) * 5.5, 0.05, sin(ang) * 5.5))
	await frames(10)
	Input.action_press(&"move_right")
	await frames(20)
	check(p.animation_player.current_animation == Fighter.ANIM_RUN, "chạy -> Running_A")
	Input.action_release(&"move_right")
	await frames(40)
	check(p.animation_player.current_animation == Fighter.ANIM_IDLE, "dừng -> Idle_A")

	print("[lao đẩy]")
	_place(p, Vector3(-1.6, 0.05, 0))
	p.face_direction(Vector3.RIGHT)
	await frames(5)
	var hits := {}
	var on_hit := func(_a, t, _pt): hits[t] = hits.get(t, 0) + 1
	p.hit_landed.connect(on_hit)
	var start_x: float = bots[0].global_position.x
	check(p.try_dash(), "lao khi sẵn sàng (đứng yên => theo hướng nhìn)")
	check(not p.try_dash(), "không spam: lao lần 2 bị từ chối khi đang hồi chiêu")
	await frames(30)
	check(hits.get(bots[0], 0) == 1, "trúng đúng 1 lần mỗi lần lao")
	check(bots[0].global_position.x - start_x > 2.0, "đối thủ bị hất văng theo hướng lao")
	p.hit_landed.disconnect(on_hit)
	await frames(int(60 * p.dash_cooldown) + 5)
	check(p.can_dash(), "hết hồi chiêu thì lao lại được")

	print("[knockback không bị ghi đè bởi input]")
	var victim: Fighter = bots[0]
	_place(victim, Vector3(0, 0.05, 0))
	victim.controls_enabled = true
	victim.move_input = Vector3.LEFT
	await frames(3)
	victim.receive_hit(p, Vector3.RIGHT, victim.knockback_force)
	await frames(15)
	check(victim.global_position.x > 1.5, "vẫn bị hất về +X dù input ngược")
	victim.controls_enabled = false
	victim.move_input = Vector3.ZERO

	print("[gió giật (màn 1)]")
	var wind = main.level.get_node("WindGusts")  # không khai kiểu: script dùng autoload Sfx
	check(wind.is_in_group(&"hazards") and main.level.stage_hint != "", "màn 1 có gió giật + câu giới thiệu")
	_park_bots()
	_place(p, Vector3(0, 0.05, 0))
	await frames(5)
	wind.warn(Vector3.RIGHT)
	check(wind.streaks.emitting and main.ui.announce_label.text == "GIÓ GIẬT!", "báo trước: vệt gió + thông báo")
	await frames(10)
	check(absf(p.global_position.x) < 0.05, "đang báo trước thì chưa bị đẩy")
	check(wind.bot_steer(Vector3.ZERO).dot(Vector3.RIGHT) < -0.5, "bot chạy ngược gió")
	await frames(int(60 * (wind.warning_time + wind.gust_time * 0.5)))
	check(p.global_position.x > 1.0, "gió đẩy người chơi đứng yên theo hướng gió (x=%.2f)" % p.global_position.x)
	await frames(int(60 * wind.gust_time))
	var x_after: float = p.global_position.x
	await frames(30)
	check(not wind.streaks.emitting and absf(p.global_position.x - x_after) < 0.05, "hết đợt gió: tắt vệt gió, hết bị đẩy")
	slide_stage1 = await _slide_distance(p)

	print("[rơi khỏi sàn -> bị loại đúng 1 lần (màn 1 không hồi sinh)]")
	var count := {"elim": 0, "fell": 0}
	victim.eliminated.connect(func(_f): count.elim += 1)
	victim.fell_out.connect(func(_f): count.fell += 1)
	_place(victim, Vector3(14, 0.5, 0))
	await frames(120)
	check(victim.is_eliminated and count.elim == 1 and count.fell == 0, "bị loại hẳn, signal phát đúng 1 lần")

	print("[vòng sàn rơi, không còn collision vô hình]")
	var arena: Arena = main.arena
	var on_ring: Fighter = bots[1]
	var r_mid := (arena.ring_outer_radius(0) + arena.ring_outer_radius(1)) * 0.5
	_place(on_ring, Vector3(r_mid, 0.05, 0))
	await frames(10)
	check(on_ring.is_on_floor() and _ray_hits(Vector3(r_mid, 2, 0.5)), "có sàn ở vòng ngoài trước khi rơi")
	arena._time_to_drop = arena.warning_time - 0.01
	await frames(2)
	check(arena.is_warning() and arena.get_safe_radius() < arena.get_current_radius(), "cảnh báo + bán kính an toàn thu nhỏ")
	arena._time_to_drop = 0.01
	await frames(2)
	check(not _ray_hits(Vector3(r_mid, 2, 0.5)), "không còn collision ở vòng đã rơi")
	check(_ray_hits(Vector3(arena.center_radius * 0.5, 2, 0)), "trung tâm vẫn còn collision")
	await frames(150)
	check(on_ring.is_eliminated, "người đứng trên vòng rơi bị loại")

	print("[pause: đồng hồ đứng yên]")
	main.toggle_pause()
	var t0: float = main.run_time
	var drop0 := arena.get_time_to_drop()
	await process_frame
	await process_frame
	check(paused and main.ui.pause_menu.visible, "pause")
	check(main.run_time == t0 and arena.get_time_to_drop() == drop0, "đồng hồ lượt chơi + timer sàn đứng yên khi pause")
	main.toggle_pause()
	check(not paused, "tiếp tục")


func _test_lose_and_retry() -> void:
	print("[thua -> thử lại màn này, đồng hồ cộng dồn]")
	var t_before: float = main.run_time
	main.player._fall_off()
	await frames(2)
	check(main.ui.result_title.text == "THẤT BẠI", "hiện THẤT BẠI")
	check(main.ui.get_node("%ResultRestartButton").text == "Thử lại màn này", "nút chính: Thử lại màn này")
	check(main.run_losses == 1, "đếm 1 lần thua")
	check(not main.arena.running and not main.fighters[1].controls_enabled, "dừng timer sàn và AI")
	main.ui.result_primary.emit()
	await frames(3)
	check(main.stage_index == 0 and main.state == main.State.COUNTDOWN, "chơi lại màn 1")
	check(main.run_time >= t_before, "đồng hồ không bị reset khi thử lại")
	check(main.fighters_root.get_child_count() == 8 and get_nodes_in_group(&"fighters").size() == 8, "không nhân đôi nhân vật")
	await frames(COUNTDOWN_FRAMES)


# ---------------------------------------------------------------- màn 2, 3

func _test_progression_to_stage3() -> void:
	print("[thắng màn 1 -> màn 2]")
	await _win_current_stage()
	check(main.ui.result_title.text == "HOÀN THÀNH MÀN 1!", "hiện HOÀN THÀNH MÀN 1")
	check(main.ui.get_node("%ResultRestartButton").text == "Màn tiếp theo", "nút chính: Màn tiếp theo")
	var chosen: String = main.player.character_name
	main.ui.result_primary.emit()
	await frames(3)
	check(main.stage_index == 1 and main.level.stage_name == "Đỉnh Băng", "vào màn 2: Đỉnh Băng")
	check(main.get_children().filter(func(n): return n is Level).size() == 1, "chỉ còn 1 level trong cây")
	check(main.fighters.size() == 10, "màn 2: 1 người chơi + 9 bot")
	check(main.player.character_name == chosen, "giữ nguyên nhân vật")
	check(is_equal_approx(main.arena.arena_radius, 11.0), "sàn màn 2 rộng 11 m")
	_check_on_markers()
	await frames(COUNTDOWN_FRAMES)
	check(main.ui.alive_label.text.begins_with("MÀN 2/3"), "HUD hiện màn 2/3")
	check(sfx.current_music().resource_path.ends_with("stage2_walking_dunes_unblinking_sun.ogg"), "màn 2 phát nhạc The Walking Dunes")

	print("[sàn băng trơn (màn 2)]")
	check(main.level.traction < 1.0 and main.level.stage_hint != "", "màn 2 có sàn trơn + câu giới thiệu")
	_freeze_bots()
	var slide_ice := await _slide_distance(main.player)
	check(slide_ice > slide_stage1 * 1.3, "bị hất trượt xa hơn màn 1 (%.1f m so với %.1f m)" % [slide_ice, slide_stage1])

	print("[thắng màn 2 -> màn 3]")
	await _win_current_stage()
	check(main.ui.result_title.text == "HOÀN THÀNH MÀN 2!", "hiện HOÀN THÀNH MÀN 2")
	main.ui.result_primary.emit()
	await frames(3)
	check(main.stage_index == 2 and main.level.stage_name == "Miệng Núi Lửa", "vào màn 3: Miệng Núi Lửa")
	check(sfx.current_music().resource_path.ends_with("stage3_alley_cat_dumpster_party.ogg"), "màn 3 phát nhạc Alley Cat")
	check((sfx.current_music() as AudioStreamOggVorbis).loop, "nhạc màn được đặt lặp lại")
	check(main.fighters.size() == 12, "màn 3: 1 người chơi + 11 bot")
	var all_one := true
	for b: Fighter in main.fighters.slice(1):
		all_one = all_one and b.respawns_left == 1
	check(all_one and main.player.respawns_left == 0, "mỗi bot có 1 lần hồi sinh, người chơi không có")
	_check_on_markers()
	# Tắt đợt phun tự động để các test màn 3 không bị phun ngẫu nhiên; test riêng gọi warn().
	main.level.get_node("LavaVents").first_delay = 1e9
	await frames(COUNTDOWN_FRAMES)


func _test_respawn() -> void:
	print("[hồi sinh ở màn 3]")
	_freeze_bots()
	var bot: Fighter = main.fighters[1]
	var count := {"elim": 0, "fell": 0, "back": 0}
	bot.eliminated.connect(func(_f): count.elim += 1)
	bot.fell_out.connect(func(_f): count.fell += 1)
	bot.respawned.connect(func(_f): count.back += 1)
	var alive_before: int = main.get_alive_count()
	_place(bot, Vector3(20, -13, 0))
	await frames(3)
	check(count.fell == 1 and count.elim == 0, "rơi lần 1: chưa bị loại, chờ hồi sinh")
	check(bot.is_respawning() and not bot.is_eliminated and not bot.is_in_group(&"fighters"), "đang chờ hồi sinh, bot khác không nhắm vào")
	check(main.get_alive_count() == alive_before, "vẫn tính là còn sống")
	await process_frame
	check(main.ui.alive_label.text.contains("sắp quay lại"), "HUD báo bot sắp quay lại")
	check(main.state == main.State.PLAYING, "trận tiếp tục")
	var waited := 0
	var saw_marker := false
	while count.back == 0 and waited < 400:
		await frames(1)
		waited += 1
		for n in main.get_children():
			if String(n.name).begins_with("LandingMarker"):
				saw_marker = true
	check(count.back == 1, "đã hồi sinh và đáp xuống sàn (sau %d frame)" % waited)
	check(saw_marker, "có vòng đỏ báo chỗ đáp")
	var flat := Vector2(bot.global_position.x, bot.global_position.z).length()
	check(bot.is_on_floor() and flat < main.arena.get_current_radius(), "đáp trong sàn (r=%.1f)" % flat)
	check(bot.is_spawn_protected(), "được bảo vệ ngay sau khi đáp")
	var kb_before: Vector3 = bot._knockback
	bot.receive_hit(main.player, Vector3.RIGHT, 20.0)
	check(bot._knockback == kb_before, "không bị đẩy trong lúc được bảo vệ")
	check(not bot.can_dash(), "không lao được trong lúc được bảo vệ")
	await frames(int(60 * bot.spawn_protect_time) + 5)
	check(not bot.is_spawn_protected() and bot.visual.visible, "hết bảo vệ, hiện bình thường")
	_place(bot, Vector3(20, -13, 0))
	await frames(3)
	check(count.elim == 1 and count.fell == 1 and bot.is_eliminated, "rơi lần 2: bị loại hẳn")
	check(main.get_alive_count() == alive_before - 1, "số người còn lại giảm 1")


func _test_lava_vents() -> void:
	print("[dung nham phun (màn 3)]")
	var vents = main.level.get_node("LavaVents")  # không khai kiểu: script dùng autoload Sfx
	check(vents.is_in_group(&"hazards") and main.level.stage_hint != "", "màn 3 có dung nham + câu giới thiệu")
	_freeze_bots()
	_park_bots()
	var p: Fighter = main.player
	var far: Fighter = main.fighters.slice(1).filter(func(b): return b.is_active())[0]
	_place(p, Vector3(0.6, 0.05, 0))
	await frames(5)
	var far_pos: Vector3 = far.global_position
	var vent_at: Array[Vector3] = [Vector3(0, 0.05, 0)]
	vents.warn(vent_at)
	await frames(2)
	check(vents.get_children().any(func(n): return String(n.name).begins_with("LandingMarker")), "vòng đỏ báo trước chỗ phun")
	check(main.ui.announce_label.text == "DUNG NHAM SẮP PHUN!", "thông báo lần phun đầu tiên")
	check(vents.bot_steer(Vector3(0.8, 0, 0)).x > 0.0, "bot né ra xa điểm sắp phun")
	check(absf(p.global_position.x - 0.6) < 0.05, "chưa phun thì chưa ai bị hất")
	await frames(int(60 * vents.warning_time) + 10)
	check(p.global_position.y > 0.4 and p.global_position.x > 1.0, "phun hất người đứng gần lên cao, ra xa tâm")
	check(vents.get_children().any(func(n): return String(n.name).begins_with("LavaBurst")), "có hiệu ứng phun")
	check(far.global_position.distance_to(far_pos) < 0.05 and vents.pending.is_empty(), "người đứng xa không sao, hết điểm cảnh báo")
	await frames(120)
	check(p.is_on_floor() and not p.is_eliminated, "đứng giữa sàn thì bị hất nhưng vẫn rơi lại trên sàn")


func _test_pause_restart_and_draw() -> void:
	print("[chơi lại màn từ menu Tạm dừng]")
	var losses: int = main.run_losses
	main.toggle_pause()
	main.ui.restart_requested.emit()
	await frames(3)
	check(not paused and main.stage_index == 2, "chơi lại màn 3, bỏ pause")
	check(main.run_losses == losses + 1, "bỏ cuộc giữa trận tính là 1 lần thua")
	check(main.fighters_root.get_child_count() == 12 and get_nodes_in_group(&"fighters").size() == 12, "không nhân đôi nhân vật")
	var rings_ok := true
	for ring: StaticBody3D in main.arena.rings_root.get_children():
		rings_ok = rings_ok and ring.visible and ring.position.y == 0.0 and not ring.get_node(^"Collision").disabled
	check(rings_ok and main.arena.get_time_to_drop() == main.arena.first_drop_delay, "sàn và timer khôi phục")
	await frames(COUNTDOWN_FRAMES)

	print("[hoà: người chơi và đối thủ cuối rơi cùng frame]")
	for f: Fighter in main.fighters:
		f.respawns_left = 0
	for f: Fighter in main.fighters.slice(2):
		f._fall_off()
	await frames(2)
	check(main.state == main.State.PLAYING, "còn 2 người, trận tiếp tục")
	main.fighters[0]._fall_off()
	main.fighters[1]._fall_off()
	await frames(2)
	check(main.ui.result_title.text == "HOÀ!", "hiện HOÀ")
	main.ui.result_primary.emit()
	await frames(COUNTDOWN_FRAMES + 3)


func _test_clear_run_and_records() -> void:
	print("[phá đảo màn 3 -> ghi kỷ lục]")
	check(main.stage_index == 2 and main.state == main.State.PLAYING, "đang đấu màn 3")
	# Hết bot thật sự: bot nào còn lượt hồi sinh thì phải rơi 2 lần.
	await _win_current_stage()
	check(main.ui.result_title.text == "PHÁ ĐẢO!", "hiện PHÁ ĐẢO")
	check(main.ui.result_detail.text.contains("KỶ LỤC MỚI!"), "lần phá đảo đầu tiên là kỷ lục mới")
	check(main.ui.get_node("%ResultRestartButton").text == "Chơi lại từ đầu", "nút chính: Chơi lại từ đầu")
	var runs := Records.load_runs()
	check(runs.size() == 1 and is_equal_approx(runs[0].time, main.run_time) and runs[0].losses == main.run_losses,
		"đã lưu kỷ lục (%s, %d lần thua)" % [Records.format_time(main.run_time), main.run_losses])
	check(runs[0].character == main.player.character_name, "kỷ lục ghi đúng nhân vật")
	check(Records.add_run(9999.0, "Test", 0) == 2, "lần chậm hơn xếp hạng 2")
	check(Records.add_run(1.0, "Test", 0) == 1 and Records.load_runs()[0].time == 1.0, "lần nhanh hơn lên hạng 1")
	for i in 12:
		Records.add_run(5000.0 + i, "Test", 0)
	check(Records.load_runs().size() == Records.MAX_ENTRIES, "chỉ giữ top %d" % Records.MAX_ENTRIES)
	check(Records.add_run(99999.0, "Test", 0) == 0, "lần quá chậm không lọt top")

	print("[chơi lại từ đầu sau khi phá đảo]")
	main.ui.result_primary.emit()
	await frames(3)
	check(main.stage_index == 0 and main.run_time == 0.0 and main.run_losses == 0, "lượt mới từ màn 1, đồng hồ về 0")
	check(main.level.stage_name == "Đấu Trường Mây" and main.fighters.size() == 8, "đúng màn 1")
	await frames(COUNTDOWN_FRAMES)


# ---------------------------------------------------------------- camera sau lưng

func _test_third_person() -> void:
	print("[camera sau lưng]")
	var cam: CameraRig = main.camera
	check(cam.mode == CameraRig.Mode.FOLLOW and not main.third_person, "mặc định camera Trên cao")
	main.toggle_pause()
	check(not main.ui.get_node("%TPSToggle").button_pressed, "công tắc trong menu Tạm dừng đang tắt")
	main.ui.get_node("%TPSToggle").button_pressed = true
	main.toggle_pause()
	await frames(5)
	check(main.third_person and cam.mode == CameraRig.Mode.THIRD_PERSON, "bật camera sau lưng từ menu Tạm dừng")
	check(main.ui.crosshair.visible, "hiện tâm ngắm")
	var any_label := false
	for f: Fighter in main.fighters:
		any_label = any_label or f.name_label.visible
	check(not any_label, "ẩn tên mọi nhân vật ở chế độ sau lưng")
	var p: Fighter = main.player
	_freeze_bots()
	_place(p, Vector3(0, 0.05, 0))
	await frames(20)
	var to_player: Vector3 = p.global_position - cam.global_position
	to_player.y = 0.0
	check(to_player.normalized().dot(cam.flat_forward()) > 0.9, "camera đứng sau lưng, nhìn cùng hướng người chơi")
	cam.add_look(Vector2(300, 0))  # xoay camera
	await frames(5)
	var fwd := cam.flat_forward()
	check(fwd.dot(p.facing) < 0.95, "chuột/ngón tay xoay được camera")
	Input.action_press(&"dash")
	await frames(2)
	Input.action_release(&"dash")
	check(p.is_dashing() and p._dash_dir.dot(fwd) > 0.98, "đứng yên mà lao => lao theo hướng camera (tâm ngắm)")
	await frames(20)
	Input.action_press(&"move_forward")
	await frames(20)
	Input.action_release(&"move_forward")
	var move := p._move_velocity
	move.y = 0.0
	check(move.length() > 1.0 and move.normalized().dot(cam.flat_forward()) > 0.9, "W đi theo hướng camera")
	main.toggle_pause()
	check(not main.ui.crosshair.visible and main.ui.get_node("%TPSToggle").button_pressed, "pause: ẩn tâm ngắm, công tắc đang bật")
	main.toggle_pause()
	main.ui.result_primary.emit()  # không có tác dụng khi đang đấu
	await frames(2)
	check(main.state == main.State.PLAYING and main.stage_index == 0, "nút kết quả không có tác dụng khi đang đấu")
	main.set_third_person(false)
	await frames(2)
	var all_labels := true
	for f: Fighter in main.fighters:
		all_labels = all_labels and f.name_label.visible
	check(cam.mode == CameraRig.Mode.FOLLOW and not main.ui.crosshair.visible and all_labels, "tắt: về camera Trên cao, hiện lại tên")
	main.set_third_person(true)
	main.go_to_menu()
	await frames(2)
	check(cam.mode == CameraRig.Mode.ORBIT and not main.ui.crosshair.visible, "về menu: camera xoay quanh, ẩn tâm ngắm")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "về menu: nhả chuột")


# ---------------------------------------------------------------- khác

func _test_misc() -> void:
	print("[bot_count vượt số điểm spawn]")
	main.ui.play_requested.emit()
	main.ui.select_confirmed.emit()
	await frames(2)
	main.level.bot_count = 15
	main.start_stage()
	await frames(2)
	check(main.fighters.size() == main.level.spawn_points.get_child_count(), "giới hạn bot theo số Marker3D")
	main.level.bot_count = 7

	print("[về menu giữa chừng => lượt mới phải từ màn 1]")
	main.go_to_menu()
	await frames(2)
	check(main.state == main.State.MENU and main.level.stage_name == "Đấu Trường Mây", "về menu, sàn màn 1")
	check(sfx.current_music().resource_path.ends_with("goblins_den.wav"), "về menu: đổi lại nhạc menu")
	main.ui.play_requested.emit()
	main.ui.select_confirmed.emit()
	await frames(2)
	check(main.stage_index == 0 and main.run_time == 0.0, "chơi lại từ màn 1")

	print("[bảng kỷ lục ở menu]")
	main.go_to_menu()
	main.ui.get_node("%RecordsButton").pressed.emit()
	await process_frame
	var body: RichTextLabel = main.ui.get_node("%RecordsBody")
	check(main.ui.records_panel.visible and body.text.contains("[table=5]"), "bảng kỷ lục hiện dạng bảng")
	check(body.get_parsed_text().contains("00:01.00"), "có lần phá đảo nhanh nhất 00:01.00")
	main.ui.get_node("%RecordsBackButton").pressed.emit()
	check(not main.ui.records_panel.visible and main.ui.get_node("%MenuButtons").visible, "quay lại menu")


func _test_touch() -> void:
	print("[cảm ứng đa điểm: joystick + nút lao + kéo camera]")
	main.ui.play_requested.emit()
	main.ui.select_confirmed.emit()
	await frames(5)
	main.set_third_person(true)
	var touch: TouchControls = main.ui.touch
	touch.show()
	await process_frame
	_touch(0, Vector2(touch.size.x * 0.2, touch.size.y * 0.7), true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = _to_window(Vector2(touch.size.x * 0.2 + 80, touch.size.y * 0.7))
	Input.parse_input_event(drag)
	_touch(1, touch._dash_center(), true)
	var yaw_before: float = main.camera._tps_yaw
	_touch(2, Vector2(touch.size.x * 0.7, touch.size.y * 0.4), true)
	var look := InputEventScreenDrag.new()
	look.index = 2
	look.position = _to_window(Vector2(touch.size.x * 0.7 + 60, touch.size.y * 0.4))
	look.relative = _to_window(Vector2(60, 0)) - _to_window(Vector2.ZERO)
	Input.parse_input_event(look)
	await process_frame
	check(Input.get_action_strength(&"move_right") > 0.5, "ngón 0 điều khiển joystick")
	check(Input.is_action_pressed(&"dash"), "ngón 1 nhấn nút lao")
	check(main.camera._tps_yaw != yaw_before, "ngón 2 kéo xoay camera")
	_touch(1, touch._dash_center(), false)
	await process_frame
	check(not Input.is_action_pressed(&"dash") and Input.get_action_strength(&"move_right") > 0.5, "thả ngón 1: nhả lao, joystick vẫn giữ")
	touch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(Input.get_action_strength(&"move_right") == 0.0 and touch._look_index == -1, "mất focus -> nhả hết input")
	main.set_third_person(false)


# ---------------------------------------------------------------- cài đặt

func _test_settings() -> void:
	print("[cài đặt: âm lượng riêng từng phần, rung, cảm ứng]")
	main.go_to_menu()
	await frames(2)
	var ui = main.ui  # không khai kiểu GameUI: ui.gd dùng autoload Sfx, chỉ biên dịch được sau khi game chạy
	check(ui.get_node_or_null("%SoundToggle") == null, "menu không còn công tắc Âm thanh chung")
	check(ui.get_node("%SettingsButton").get_parent() == ui.get_node("%MenuButtons"), "menu chính có nút Cài đặt")
	check(sfx.get_node("hit").bus == &"SFX" and sfx.get_node("Music").bus == &"Music", "hiệu ứng đi bus SFX, nhạc đi bus Music")
	ui.get_node("%SettingsButton").pressed.emit()
	check(ui.settings_panel.visible, "mở Cài đặt từ menu chính")
	var music_slider: HSlider = ui.get_node("%MusicSlider")
	var sfx_slider: HSlider = ui.get_node("%SFXSlider")
	var master_slider: HSlider = ui.get_node("%MasterSlider")
	music_slider.value = 40
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), linear_to_db(0.4)),
		"kéo Nhạc nền 40% => bus Music giảm đúng")
	check(ui.get_node("%MusicValue").text == "40%", "hiện 40%")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")), 0.0), "Hiệu ứng không bị ảnh hưởng")
	sfx_slider.value = 0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")),
		"Hiệu ứng 0% => tắt riêng hiệu ứng, nhạc vẫn phát")
	master_slider.value = 80
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.8)), "Âm lượng chung 80% => bus Master")
	ui.get_node("%VibrateToggle").button_pressed = false
	check(not GameSettings.vibration, "tắt rung")
	var touch_was: bool = ui.touch_enabled
	ui.get_node("%TouchToggle").button_pressed = not touch_was
	check(ui.touch_enabled != touch_was and GameSettings.touch_mode == int(not touch_was), "đổi điều khiển cảm ứng trong Cài đặt")
	ui.get_node("%TouchToggle").button_pressed = touch_was
	var esc := InputEventAction.new()
	esc.action = &"pause"
	esc.pressed = true
	Input.parse_input_event(esc)
	await process_frame  # sự kiện được xử lý ở đầu khung hình kế tiếp
	await process_frame
	check(not ui.settings_panel.visible and ui.menu.visible, "Esc đóng Cài đặt, về menu")
	check(FileAccess.file_exists(GameSettings.path), "đã lưu cài đặt ra file")
	GameSettings.volumes = {&"Master": 1.0, &"Music": 1.0, &"SFX": 1.0}
	GameSettings.vibration = true
	GameSettings.load_settings()
	check(is_equal_approx(GameSettings.volumes[&"Music"], 0.4) and GameSettings.volumes[&"SFX"] == 0.0
		and is_equal_approx(GameSettings.volumes[&"Master"], 0.8) and not GameSettings.vibration,
		"mở lại game: đọc đúng cài đặt đã lưu")

	print("[cài đặt trong lúc tạm dừng]")
	main.ui.play_requested.emit()
	main.ui.select_confirmed.emit()
	await frames(COUNTDOWN_FRAMES)
	main.toggle_pause()
	ui.get_node("%PauseSettingsButton").pressed.emit()
	check(paused and ui.settings_panel.visible, "mở Cài đặt từ menu Tạm dừng")
	music_slider.value = 70
	sfx_slider.value = 100
	master_slider.value = 100
	ui.get_node("%VibrateToggle").button_pressed = true
	ui.get_node("%SettingsCloseButton").pressed.emit()
	check(not ui.settings_panel.visible and ui.pause_menu.visible and paused, "Đóng => quay lại menu Tạm dừng, vẫn đang dừng")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "bật lại hiệu ứng")
	main.toggle_pause()
	check(not paused, "tiếp tục chơi")


# ---------------------------------------------------------------- helpers

## Thắng màn hiện tại: cho mọi bot rơi khỏi sàn (kể cả lần hồi sinh nếu có).
func _win_current_stage() -> void:
	for f: Fighter in main.fighters.slice(1):
		f.respawns_left = 0
		if f.is_active():
			f._fall_off()
	var waited := 0
	while main.state != main.State.ENDED and waited < 600:
		for f: Fighter in main.fighters.slice(1):
			if f.is_active():
				f._fall_off()
		await frames(1)
		waited += 1


func _freeze_bots() -> void:
	for b: Fighter in main.fighters.slice(1):
		b.controls_enabled = false
		b.move_input = Vector3.ZERO
	main.player.controls_enabled = true


## Dồn bot còn trên sàn về một hàng ở phía -X để người chơi bị đẩy về +X không vướng ai.
func _park_bots() -> void:
	var bots: Array = main.fighters.slice(1).filter(func(b): return b.is_active())
	for i in bots.size():
		_place(bots[i], Vector3(-4.5, 0.05, (i - (bots.size() - 1) * 0.5) * 1.15))


## Đứng giữa sàn, bị hất về +X với lực cố định; trả về quãng đã trượt khi dừng hẳn.
func _slide_distance(f: Fighter) -> float:
	_park_bots()
	_place(f, Vector3(0, 0.05, 0))
	await frames(5)
	f.receive_hit(null, Vector3.RIGHT, 9.0)
	await frames(120)
	return f.global_position.x


func _check_on_markers() -> void:
	var on_marker := 0
	for f: Fighter in main.fighters:
		for m: Node3D in main.level.spawn_points.get_children():
			if Vector2(f.global_position.x, f.global_position.z).distance_to(Vector2(m.global_position.x, m.global_position.z)) < 0.05:
				on_marker += 1
	check(on_marker == main.fighters.size(), "mọi nhân vật đứng đúng điểm spawn Marker3D (%d)" % on_marker)


func _place(f: Fighter, pos: Vector3) -> void:
	f.global_position = pos
	f.velocity = Vector3.ZERO
	f._knockback = Vector3.ZERO
	f._move_velocity = Vector3.ZERO


func _touch(index: int, viewport_pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = pressed
	e.position = _to_window(viewport_pos)
	Input.parse_input_event(e)
	return e


## Toạ độ viewport -> toạ độ cửa sổ (cửa sổ headless nhỏ hơn viewport do stretch).
func _to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _ray_hits(from: Vector3) -> bool:
	var space := main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 5.0, 1)
	return not space.intersect_ray(q).is_empty()

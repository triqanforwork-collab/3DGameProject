extends Node3D
## Quản lý lượt chơi: chọn nhân vật -> màn 1 -> màn 2 -> màn 3 -> phá đảo (ghi kỷ lục thời gian).
## Mỗi màn là một scene level (Level) trong `stages`; số bot, độ khó, hồi sinh đặt trên level đó.
## Luôn chơi từ màn đầu, không có chọn màn. Thua thì thử lại màn hiện tại, thời gian vẫn cộng dồn.

enum State { MENU, SELECT, COUNTDOWN, PLAYING, ENDED }
enum Result { WIN, LOSE, DRAW }
enum NextAction { NEXT_STAGE, RETRY_STAGE, NEW_RUN }

## Danh sách nhân vật chọn được (mỗi phần tử là một scene nhân vật, vd. knight.tscn).
@export var roster: Array[PackedScene] = []
## Các màn theo thứ tự chơi.
@export var stages: Array[PackedScene] = []
@export var countdown_seconds: int = 3

@export_group("Hồi sinh")
## Thời gian từ lúc rơi khỏi sàn tới lúc bắt đầu rơi từ trên trời xuống.
@export var respawn_delay: float = 1.2
@export var respawn_height: float = 12.0

var state: State = State.MENU
var fighters: Array[Fighter] = []
var player: Fighter
var selected_index := 0
var stage_index := 0
## Tổng thời gian thi đấu của lượt chơi (chỉ tính lúc đang đấu, cộng cả các lần thử lại).
var run_time := 0.0
var run_losses := 0
## Camera sau lưng: bật/tắt trong menu Tạm dừng. Mỗi lần mở game mặc định là Trên cao.
var third_person := false
var arena: Arena

var _countdown_left := 0.0
var _last_count_shown := -1
var _match_time := 0.0
var _result_pending := false
var _next_action := NextAction.RETRY_STAGE

@onready var level: Level = $Level
@onready var fighters_root: Node3D = $Fighters
@onready var camera: CameraRig = $Camera3D
@onready var ui: GameUI = $UI


func _ready() -> void:
	ui.play_requested.connect(enter_select)
	ui.select_changed.connect(_on_select_changed)
	ui.select_confirmed.connect(start_run)
	ui.select_back.connect(go_to_menu)
	ui.result_primary.connect(_on_result_primary)
	ui.restart_requested.connect(_retry_from_pause)
	ui.menu_requested.connect(go_to_menu)
	ui.pause_toggled.connect(toggle_pause)
	ui.third_person_toggled.connect(set_third_person)
	ui.touch.look_dragged.connect(camera.add_look)
	_bind_level()
	go_to_menu()


# --- Màn chơi (level) -------------------------------------------------------

## Thay level đang dùng bằng màn `index` (giữ nguyên nếu đã đúng màn).
func _load_stage(index: int) -> void:
	if stages.is_empty() or level.scene_file_path == stages[index].resource_path:
		return
	var old := level
	old.name = "OldLevel"
	remove_child(old)
	old.queue_free()
	level = stages[index].instantiate() as Level
	level.name = "Level"
	add_child(level)
	move_child(level, 0)
	_bind_level()


func _bind_level() -> void:
	arena = level.arena
	arena.ring_warning.connect(_on_ring_warning)
	arena.ring_dropped.connect(_on_ring_dropped)
	camera.arena = arena


# --- Luồng màn hình --------------------------------------------------------

## Menu chính: các nhân vật đứng trên sàn màn 1, camera xoay quanh. Huỷ lượt chơi đang dở.
func go_to_menu() -> void:
	get_tree().paused = false
	_load_stage(0)
	_clear_fighters()
	arena.reset()
	var points := level.spawn_points.get_children()
	for i in mini(roster.size(), points.size()):
		var f := _spawn(roster[i], points[i].global_position)
		f.setup_display(f.character_name, Color(1, 1, 1, 0.85), false, Color.WHITE)
	state = State.MENU
	camera.set_mode(CameraRig.Mode.ORBIT)
	_update_mouse_capture()
	Sfx.play_music()  # nhạc menu
	ui.show_menu()


## Màn chọn nhân vật: chỉ nhân vật đang chọn đứng ở Showcase, camera quay cận cảnh.
func enter_select() -> void:
	get_tree().paused = false
	_load_stage(0)
	arena.reset()
	state = State.SELECT
	_update_mouse_capture()
	ui.show_character_select()
	_show_preview()


func _on_select_changed(step: int) -> void:
	selected_index = wrapi(selected_index + step, 0, roster.size())
	_show_preview()


func _show_preview() -> void:
	_clear_fighters()
	var f := _spawn(roster[selected_index], level.showcase.global_position)
	f.face_direction(Vector3.BACK)  # nhìn về phía camera
	f.name_label.hide()
	camera.set_mode(CameraRig.Mode.SHOWCASE, f)
	ui.set_character_info(f, selected_index, roster.size())


## Bắt đầu lượt chơi mới từ màn 1.
func start_run() -> void:
	stage_index = 0
	run_time = 0.0
	run_losses = 0
	start_stage()


## Bắt đầu (hoặc chơi lại) màn hiện tại.
func start_stage() -> void:
	get_tree().paused = false
	_load_stage(stage_index)
	_setup_match()
	state = State.COUNTDOWN
	_countdown_left = countdown_seconds
	_last_count_shown = -1
	ui.show_hud()
	Sfx.play_music(level.music)
	ui.feed("MÀN %d/%d: %s" % [stage_index + 1, stage_count(), level.stage_name.to_upper()])
	_apply_camera_mode()


func stage_count() -> int:
	return maxi(stages.size(), 1)


## Đọc stage_name của màn `index` từ scene mà không cần tạo ra level.
func _stage_name(index: int) -> String:
	if index >= stages.size():
		return ""
	var st := stages[index].get_state()
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == &"stage_name":
			return st.get_node_property_value(0, i)
	return ""


## Đưa mọi trạng thái về ban đầu: xoá nhân vật cũ (kèm signal/controller/tween của chúng),
## đưa sàn và timer về như cũ, spawn lại từ scene nhân vật theo thông số của level.
func _setup_match() -> void:
	_clear_fighters()
	_match_time = 0.0
	_result_pending = false
	arena.reset()

	var points := level.spawn_points.get_children()
	var max_bots := points.size() - 1
	if level.bot_count > max_bots:
		push_warning("%s: bot_count = %d nhưng chỉ có %d điểm spawn; dùng %d bot." % [
			level.name, level.bot_count, points.size(), max_bots])
	var bots := mini(level.bot_count, max_bots)
	points.shuffle()

	# Bot lấy từ các nhân vật còn lại (xáo trộn), lặp lại nếu cần thêm.
	var others: Array[PackedScene] = roster.duplicate()
	others.remove_at(selected_index)
	others.shuffle()
	if others.is_empty():
		others.append(roster[selected_index])
	var name_count := {}

	player = _spawn(roster[selected_index], points[0].global_position)
	player.display_name = "Bạn"
	player.setup_display("BẠN", Color(1, 0.86, 0.25), true, Color(1, 0.86, 0.25))
	player.add_child(PlayerInput.new())

	for i in bots:
		var f := _spawn(others[i % others.size()], points[i + 1].global_position)
		name_count[f.character_name] = name_count.get(f.character_name, 0) + 1
		if name_count[f.character_name] > 1:
			f.display_name = "%s %d" % [f.character_name, name_count[f.character_name]]
		f.setup_display(f.display_name, Color(1, 1, 1, 0.85), false, Color.WHITE)
		f.respawns_left = level.bot_respawns
		var brain := BotBrain.new()
		brain.arena = arena
		brain.think_interval = level.bot_think_interval
		brain.reaction_time = level.bot_reaction_time
		brain.aim_error_deg = level.bot_aim_error_deg
		brain.aggression = level.bot_aggression
		f.add_child(brain)

	for f in fighters:
		f.dashed.connect(_on_fighter_dashed)
		f.hit_landed.connect(_on_hit_landed)
		f.eliminated.connect(_on_fighter_eliminated)
		f.fell_out.connect(_on_fighter_fell_out)
		f.respawned.connect(_on_fighter_respawned)


func _spawn(scene: PackedScene, pos: Vector3) -> Fighter:
	var f := scene.instantiate() as Fighter
	f.position = pos
	var to_center := Vector3(-pos.x, 0.0, -pos.z)
	f.face_direction(to_center if to_center.length_squared() > 0.01 else Vector3.BACK)
	f.display_name = f.character_name
	fighters_root.add_child(f)
	fighters.append(f)
	return f


func _clear_fighters() -> void:
	for f in fighters:
		if is_instance_valid(f):
			f.remove_from_group(&"fighters")
			f.process_mode = Node.PROCESS_MODE_DISABLED  # cả controller con cũng dừng ngay
			f.queue_free()
	fighters.clear()
	player = null


# --- Vòng lặp trận ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_countdown_left -= delta
			var shown := ceili(_countdown_left)
			if shown != _last_count_shown and shown > 0:
				_last_count_shown = shown
				ui.announce(str(shown), 0.8)
				Sfx.play(&"count", 0.0)
			if _countdown_left <= 0.0:
				state = State.PLAYING
				ui.announce("ĐẨY!", 1.0)
				Sfx.play(&"go", 0.0)
				arena.start()
				for f in fighters:
					f.controls_enabled = true
		State.PLAYING:
			_match_time += delta
			run_time += delta


func _process(_delta: float) -> void:
	if state == State.COUNTDOWN or state == State.PLAYING:
		var pending := 0
		for f in fighters:
			if f.is_respawning():
				pending += 1
		ui.update_hud("MÀN %d/%d · %s" % [stage_index + 1, stage_count(), Records.format_time(run_time)],
			get_alive_count(), fighters.size(), pending, arena.get_time_to_drop(),
			arena.is_warning(), player.get_dash_ready_ratio(), player.push_outs)


## Số người chưa bị loại hẳn (người đang chờ hồi sinh vẫn tính là còn).
func get_alive_count() -> int:
	var n := 0
	for f in fighters:
		if not f.is_eliminated:
			n += 1
	return n


func toggle_pause() -> void:
	if state != State.COUNTDOWN and state != State.PLAYING:
		return
	var paused := not get_tree().paused
	get_tree().paused = paused
	ui.show_pause(paused, third_person)
	_update_mouse_capture()


## Bấm "Chơi lại màn" trong menu Tạm dừng: tính là một lần thua (bỏ cuộc), thời gian vẫn cộng dồn.
func _retry_from_pause() -> void:
	if state == State.PLAYING:
		run_losses += 1
	start_stage()


func _notification(what: int) -> void:
	# Mất focus / app bị đưa xuống nền (Android) => tự pause, tránh nhân vật chạy một mình.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if (state == State.COUNTDOWN or state == State.PLAYING) and not get_tree().paused:
			toggle_pause()


# --- Camera ----------------------------------------------------------------

func set_third_person(on: bool) -> void:
	third_person = on
	_apply_camera_mode()


func _apply_camera_mode() -> void:
	if player == null:
		return
	if third_person:
		camera.set_mode(CameraRig.Mode.THIRD_PERSON, player)
	else:
		camera.set_mode(CameraRig.Mode.FOLLOW, player)
	# Camera sau lưng: ẩn tên mọi nhân vật để không che tầm nhìn.
	for f in fighters:
		f.name_label.visible = not third_person
	ui.set_crosshair_visible(third_person)
	ui.touch.look_enabled = third_person
	_update_mouse_capture()


## Khoá chuột vào cửa sổ để xoay camera sau lưng; nhả ra khi pause, kết thúc trận, ở menu.
func _update_mouse_capture() -> void:
	var capture := third_person and not ui.touch_enabled and not get_tree().paused \
		and (state == State.COUNTDOWN or state == State.PLAYING)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


# --- Sự kiện ---------------------------------------------------------------

func _on_fighter_dashed(f: Fighter) -> void:
	if f == player or f.global_position.distance_to(player.global_position) < 8.0:
		Sfx.play(&"dash")


func _on_hit_landed(attacker: Fighter, target: Fighter, point: Vector3) -> void:
	Effects.hit_burst(self, point)
	Sfx.play(&"hit")
	var involves_player := attacker == player or target == player
	camera.shake(0.35 if involves_player else 0.12)
	# Rung điện thoại: bị trúng rung mạnh hơn lao trúng (tắt được trong Cài đặt).
	if target == player:
		GameSettings.vibrate(90)
	elif attacker == player:
		GameSettings.vibrate(35)


func _on_fighter_fell_out(f: Fighter) -> void:
	Sfx.play(&"fall")
	_credit_popup(f)
	ui.feed("%s rơi! Sẽ quay lại..." % f.display_name)
	# Tween gắn với nhân vật: chơi lại / về menu xoá nhân vật thì tween cũng mất theo.
	var t := f.create_tween()
	t.tween_interval(respawn_delay)
	t.tween_callback(_respawn_fighter.bind(f))


func _respawn_fighter(f: Fighter) -> void:
	if state != State.PLAYING or not is_instance_valid(f):
		return
	var pos := _pick_landing_spot()
	Effects.landing_marker(self, pos)
	f.respawn_at(pos, respawn_height)


## Điểm đáp ngẫu nhiên trong vùng sàn an toàn, cách những người đang đứng trên sàn.
func _pick_landing_spot() -> Vector3:
	var center := arena.global_position + Vector3.UP * 0.05
	var radius := maxf(arena.get_safe_radius() - 1.2, 0.5)
	for attempt in 20:
		var p := center + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * radius * sqrt(randf())
		var free := true
		for f in fighters:
			if f.is_active() and Vector2(f.global_position.x - p.x, f.global_position.z - p.z).length() < 1.8:
				free = false
				break
		if free:
			return p
	return center


func _on_fighter_respawned(f: Fighter) -> void:
	Effects.dust_ring(self, f.global_position, 0.2, 1.3)
	Sfx.play(&"drop", 0.1)
	camera.shake(0.1)


func _on_fighter_eliminated(f: Fighter) -> void:
	Sfx.play(&"fall")
	_credit_popup(f)
	if f == player:
		ui.feed("Bạn đã rơi khỏi sàn!")
		GameSettings.vibrate(300)
	elif f.last_attacker == player:
		ui.feed("Bạn đẩy %s ra ngoài!" % f.display_name)
	else:
		ui.feed("%s đã bị loại!" % f.display_name)
	# Gom mọi lượt bị loại trong cùng physics frame rồi mới xét kết quả.
	if not _result_pending:
		_result_pending = true
		_evaluate_result.call_deferred()


func _credit_popup(f: Fighter) -> void:
	var by := f.last_attacker
	if by and by.is_active():
		Effects.popup_text(self, by.global_position + Vector3.UP * 3.2, "+1", Color(1, 0.4, 0.3))


func _evaluate_result() -> void:
	_result_pending = false
	if state != State.PLAYING and state != State.COUNTDOWN:
		return
	var alive := get_alive_count()
	if player.is_eliminated:
		# Người chơi rơi cùng frame với những đối thủ cuối cùng => hoà.
		_end_match(Result.DRAW if alive == 0 else Result.LOSE, alive + 1)
	elif alive <= 1:
		_end_match(Result.WIN, 1)


func _end_match(result: Result, rank: int) -> void:
	state = State.ENDED
	arena.stop()
	for f in fighters:
		f.controls_enabled = false
		f.move_input = Vector3.ZERO
	_update_mouse_capture()

	if result != Result.WIN:
		run_losses += 1
		_next_action = NextAction.RETRY_STAGE
		Sfx.play(&"lose", 0.0)
		ui.show_result("HOÀ!" if result == Result.DRAW else "THẤT BẠI",
			"Màn %d/%d · Hạng %d / %d\nĐẩy ra ngoài: %d\nTổng thời gian: %s\nSố lần thua: %d" % [
				stage_index + 1, stage_count(), rank, fighters.size(), player.push_outs,
				Records.format_time(run_time), run_losses],
			false, "Thử lại màn này")
		return

	Sfx.play(&"win", 0.0)
	if stage_index < stage_count() - 1:
		_next_action = NextAction.NEXT_STAGE
		var next_name := _stage_name(stage_index + 1)
		ui.show_result("HOÀN THÀNH MÀN %d!" % (stage_index + 1),
			"Đẩy ra ngoài: %d\nTổng thời gian: %s\nMàn tiếp theo: %s" % [
				player.push_outs, Records.format_time(run_time), next_name],
			true, "Màn tiếp theo")
		return

	# Phá đảo: ghi kỷ lục.
	_next_action = NextAction.NEW_RUN
	var record_rank := Records.add_run(run_time, player.character_name, run_losses)
	var record_text := "KỶ LỤC MỚI!" if record_rank == 1 else \
		("Hạng %d trong bảng kỷ lục" % record_rank if record_rank > 0 else "Chưa lọt top %d kỷ lục" % Records.MAX_ENTRIES)
	ui.show_result("PHÁ ĐẢO!", "Tổng thời gian: %s\nNhân vật: %s\nSố lần thua: %d\n%s" % [
		Records.format_time(run_time), player.character_name, run_losses, record_text],
		true, "Chơi lại từ đầu")


func _on_result_primary() -> void:
	if state != State.ENDED:
		return
	match _next_action:
		NextAction.NEXT_STAGE:
			stage_index += 1
			start_stage()
		NextAction.RETRY_STAGE:
			start_stage()
		NextAction.NEW_RUN:
			start_run()


func _on_ring_warning(_index: int) -> void:
	Sfx.play(&"warn", 0.0)
	ui.announce("VÒNG NGOÀI SẮP RƠI!", 1.5)


func _on_ring_dropped(_index: int) -> void:
	Sfx.play(&"drop", 0.0)
	camera.shake(0.4)
	if arena.is_fully_shrunk():
		ui.announce("VÒNG CUỐI!", 1.5)

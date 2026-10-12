class_name GameUI
extends CanvasLayer
## Toàn bộ giao diện: menu chính (Chơi / Kỷ lục / Hướng dẫn kèm nguồn tài nguyên), chọn nhân vật, HUD,
## tâm ngắm, tạm dừng (kèm công tắc camera sau lưng), cài đặt (âm lượng, rung, cảm ứng), kết quả.
## Chỉ phát signal; Main quyết định trạng thái trận.

signal play_requested
signal select_changed(step: int)
signal select_confirmed
signal select_back
signal restart_requested
## Nút chính của màn kết quả (Màn tiếp theo / Thử lại màn này / Chơi lại từ đầu).
signal result_primary
signal third_person_toggled(on: bool)
signal menu_requested
signal pause_toggled

## Bật joystick/nút cảm ứng trên PC để kiểm tra (chuột sẽ giả lập chạm).
@export var force_touch_controls: bool = false

var touch_enabled := false
var _crosshair_wanted := false
var _announce_tween: Tween
var _feed_tween: Tween

@onready var hud: Control = $HUD
@onready var timer_label: Label = %TimerLabel
@onready var alive_label: Label = %AliveLabel
@onready var announce_label: Label = %Announce
@onready var feed_label: Label = %Feed
@onready var dash_panel: Control = %DashPanel
@onready var dash_bar: ProgressBar = %DashBar
@onready var touch: TouchControls = $Touch
@onready var pause_menu: Control = $Pause
@onready var result_screen: Control = $Result
@onready var result_title: Label = %ResultTitle
@onready var result_detail: Label = %ResultDetail
@onready var menu: Control = $Menu
@onready var char_select: Control = $CharacterSelect
@onready var guide_panel: Control = %Guide
@onready var records_panel: Control = %Records
@onready var crosshair: Control = $Crosshair
@onready var touch_toggle: CheckButton = %TouchToggle
@onready var settings_panel: Control = $Settings


func _ready() -> void:
	%PauseButton.pressed.connect(func(): pause_toggled.emit())
	%ResumeButton.pressed.connect(func(): pause_toggled.emit())
	%PauseRestartButton.pressed.connect(func(): restart_requested.emit())
	%PauseMenuButton.pressed.connect(func(): menu_requested.emit())
	%ResultRestartButton.pressed.connect(func(): result_primary.emit())
	%TPSToggle.toggled.connect(func(on: bool): third_person_toggled.emit(on))
	%RecordsButton.pressed.connect(_show_records)
	%RecordsBackButton.pressed.connect(func(): _show_sub_panel(null))
	%ResultMenuButton.pressed.connect(func(): menu_requested.emit())
	%PlayButton.pressed.connect(func(): play_requested.emit())
	%GuideButton.pressed.connect(func(): _show_sub_panel(guide_panel))
	%GuideBackButton.pressed.connect(func(): _show_sub_panel(null))
	%QuitButton.pressed.connect(func(): get_tree().quit())
	%PrevButton.pressed.connect(func(): select_changed.emit(-1))
	%NextButton.pressed.connect(func(): select_changed.emit(1))
	%ConfirmButton.pressed.connect(func(): select_confirmed.emit())
	%SelectBackButton.pressed.connect(func(): select_back.emit())
	# Tiếng click cho mọi nút.
	for b in find_children("*", "BaseButton", true, false):
		(b as BaseButton).pressed.connect(Sfx.play.bind(&"click", 0.0))

	# Cảm ứng: theo lựa chọn đã lưu, chưa chọn bao giờ thì tự bật nếu máy có màn hình cảm ứng.
	var auto_touch := force_touch_controls or DisplayServer.is_touchscreen_available()
	_set_touch_enabled(auto_touch if GameSettings.touch_mode < 0 else GameSettings.touch_mode == 1)
	touch_toggle.button_pressed = touch_enabled
	touch_toggle.toggled.connect(func(on: bool):
		GameSettings.touch_mode = int(on)
		_set_touch_enabled(on))

	# Cài đặt
	%SettingsButton.pressed.connect(open_settings)
	%PauseSettingsButton.pressed.connect(open_settings)
	%SettingsCloseButton.pressed.connect(close_settings)
	for bus in [&"Master", &"Music", &"SFX"]:
		var slider: HSlider = get_node("%" + bus + "Slider")
		slider.value_changed.connect(_on_volume_changed.bind(bus))
		# Thả thanh hiệu ứng thì phát thử một tiếng để nghe mức âm lượng.
		if bus == &"SFX":
			slider.drag_ended.connect(func(_changed: bool): Sfx.play(&"hit", 0.0))
	%VibrateToggle.toggled.connect(func(on: bool):
		GameSettings.vibration = on
		GameSettings.vibrate(60))

	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _unhandled_input(event: InputEvent) -> void:
	if settings_panel.visible:
		if event.is_action_pressed(&"pause"):
			close_settings()
			get_viewport().set_input_as_handled()
		return
	if char_select.visible:
		if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"move_left"):
			select_changed.emit(-1)
		elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"move_right"):
			select_changed.emit(1)
		elif event.is_action_pressed(&"pause"):
			select_back.emit()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause"):
		if guide_panel.visible or records_panel.visible:
			_show_sub_panel(null)
		else:
			pause_toggled.emit()
		get_viewport().set_input_as_handled()


# --- Chuyển màn ------------------------------------------------------------

func show_menu() -> void:
	_hide_all()
	menu.show()
	_show_sub_panel(null)
	%PlayButton.grab_focus.call_deferred()


func show_character_select() -> void:
	_hide_all()
	char_select.show()
	%ConfirmButton.grab_focus.call_deferred()


## Hiện tên, mô tả và thanh chỉ số của nhân vật đang xem (chuẩn hoá về 0..1 cho thanh).
func set_character_info(f: Fighter, index: int, total: int) -> void:
	%CharName.text = f.character_name
	%CharDesc.text = f.description
	%CharIndex.text = "%d / %d" % [index + 1, total]
	%SpeedBar.value = inverse_lerp(3.5, 6.5, f.move_speed)
	%PowerBar.value = inverse_lerp(6.0, 12.0, f.knockback_force)
	%WeightBar.value = inverse_lerp(0.7, 1.4, f.weight)


func show_hud() -> void:
	_hide_all()
	hud.show()
	touch.visible = touch_enabled
	crosshair.visible = _crosshair_wanted
	announce_label.text = ""
	feed_label.text = ""


func show_pause(paused: bool, third_person: bool) -> void:
	pause_menu.visible = paused
	if not paused:
		settings_panel.hide()
	touch.visible = touch_enabled and not paused
	crosshair.visible = _crosshair_wanted and not paused
	%TPSToggle.set_pressed_no_signal(third_person)
	if paused:
		%ResumeButton.grab_focus.call_deferred()


func show_result(title: String, detail: String, win: bool, primary_text: String) -> void:
	touch.hide()
	pause_menu.hide()
	crosshair.hide()
	%ResultRestartButton.text = primary_text
	if _announce_tween:
		_announce_tween.kill()
	announce_label.text = ""
	result_screen.show()
	result_title.text = title
	result_title.add_theme_color_override(&"font_color",
		Color(1, 0.85, 0.3) if win else Color(1, 0.45, 0.4))
	result_detail.text = detail
	%ResultRestartButton.grab_focus.call_deferred()


func _hide_all() -> void:
	for c in [hud, touch, pause_menu, result_screen, menu, char_select, crosshair, settings_panel]:
		c.hide()


func _show_sub_panel(panel: Control) -> void:
	guide_panel.visible = panel == guide_panel
	records_panel.visible = panel == records_panel
	%MenuButtons.visible = panel == null
	# Ẩn logo khi mở bảng chữ để không tràn màn hình thấp.
	%Logo.visible = panel == null
	%Subtitle.visible = panel == null


# --- Cài đặt ---------------------------------------------------------------

func open_settings() -> void:
	for bus in [&"Master", &"Music", &"SFX"]:
		var slider: HSlider = get_node("%" + bus + "Slider")
		slider.set_value_no_signal(roundi(GameSettings.volumes[bus] * 100.0))
		_update_volume_label(bus)
	%VibrateToggle.set_pressed_no_signal(GameSettings.vibration)
	touch_toggle.set_pressed_no_signal(touch_enabled)
	settings_panel.show()
	%SettingsCloseButton.grab_focus.call_deferred()


func close_settings() -> void:
	settings_panel.hide()
	GameSettings.save_settings()
	if pause_menu.visible:
		%ResumeButton.grab_focus.call_deferred()
	elif menu.visible:
		%PlayButton.grab_focus.call_deferred()


func _on_volume_changed(value: float, bus: StringName) -> void:
	GameSettings.set_volume(bus, value / 100.0)
	_update_volume_label(bus)


func _update_volume_label(bus: StringName) -> void:
	(get_node("%" + bus + "Value") as Label).text = "%d%%" % roundi(GameSettings.volumes[bus] * 100.0)


# --- Kỷ lục ----------------------------------------------------------------

func _show_records() -> void:
	var runs := Records.load_runs()
	var body: RichTextLabel = %RecordsBody
	if runs.is_empty():
		body.text = "Chưa có lần phá đảo nào.\nThắng liền 3 màn để ghi tên vào bảng kỷ lục!"
	else:
		var t := "[table=5]"
		for h in ["#", "Thời gian", "Nhân vật", "Thua", "Ngày"]:
			t += "[cell][b]%s   [/b][/cell]" % h
		for i in runs.size():
			var r: Dictionary = runs[i]
			var d := str(r.get("date", "")).split("-")
			var date := "%s/%s/%s" % [d[2], d[1], d[0]] if d.size() == 3 else str(r.get("date", ""))
			t += "[cell]%d   [/cell][cell]%s   [/cell][cell]%s   [/cell][cell]%d   [/cell][cell]%s[/cell]" % [
				i + 1, Records.format_time(r.time), r.character, r.losses, date]
		body.text = t + "[/table]"
	_show_sub_panel(records_panel)


# --- HUD -------------------------------------------------------------------

## Tâm ngắm chỉ hiện khi đang đấu với camera sau lưng.
func set_crosshair_visible(on: bool) -> void:
	_crosshair_wanted = on
	crosshair.visible = on and hud.visible and not pause_menu.visible and not result_screen.visible


func update_hud(stage_text: String, alive: int, total: int, pending: int, time_to_drop: float,
		warning: bool, dash_ratio: float, push_outs: int) -> void:
	var alive_text := "%d / %d CÒN LẠI" % [alive, total]
	if pending > 0:
		alive_text += " (%d sắp quay lại)" % pending
	alive_label.text = "%s\n%s\nĐẨY RA: %d" % [stage_text, alive_text, push_outs]
	if time_to_drop < 0.0:
		timer_label.text = "VÒNG CUỐI"
		timer_label.modulate = Color.WHITE
	else:
		timer_label.text = "SÀN THU HẸP SAU  %02d" % ceili(time_to_drop)
		var blink := warning and int(Time.get_ticks_msec() / 250) % 2 == 0
		timer_label.modulate = Color(1, 0.4, 0.3) if blink else Color.WHITE
	dash_bar.value = dash_ratio
	touch.dash_ready_ratio = dash_ratio


func announce(text: String, duration: float) -> void:
	if _announce_tween:
		_announce_tween.kill()
	announce_label.text = text
	announce_label.modulate.a = 1.0
	announce_label.pivot_offset = announce_label.size * 0.5
	announce_label.scale = Vector2.ONE * 1.4
	_announce_tween = create_tween()
	_announce_tween.tween_property(announce_label, ^"scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announce_tween.tween_interval(duration)
	_announce_tween.tween_property(announce_label, ^"modulate:a", 0.0, 0.3)


func feed(text: String) -> void:
	if _feed_tween:
		_feed_tween.kill()
	feed_label.text = text
	feed_label.modulate.a = 1.0
	_feed_tween = create_tween()
	_feed_tween.tween_interval(2.0)
	_feed_tween.tween_property(feed_label, ^"modulate:a", 0.0, 0.5)


# --- Cảm ứng & màn hình ----------------------------------------------------

func _set_touch_enabled(on: bool) -> void:
	touch_enabled = on
	# Trên PC: cho chuột giả lập chạm để thử joystick/nút lao.
	Input.emulate_touch_from_mouse = on and not DisplayServer.is_touchscreen_available()
	dash_panel.visible = not on
	if hud.visible:
		touch.visible = on and not pause_menu.visible and not result_screen.visible


## Chừa lề cho tai thỏ / bo góc trên điện thoại.
func _apply_safe_area() -> void:
	var margin := hud as MarginContainer
	var base := 16
	var left := base
	var right := base
	var top := base
	# Chỉ điện thoại mới có tai thỏ / bo góc. Trên PC, vùng an toàn tính theo toạ độ toàn desktop
	# (màn hình phụ có thể bắt đầu ở x = 2880) nên không dùng để tránh đẩy HUD ra ngoài.
	if OS.has_feature("mobile"):
		var screen_pos := DisplayServer.screen_get_position()
		var screen := DisplayServer.screen_get_size()
		var safe := DisplayServer.get_display_safe_area()
		safe.position -= screen_pos
		var view := get_viewport().get_visible_rect().size
		if screen.x > 0 and screen.y > 0 and safe.size.x > 0:
			var sx := view.x / screen.x
			var sy := view.y / screen.y
			# Giới hạn lề tối đa 15% chiều rộng/cao phòng khi hệ điều hành trả số lạ.
			left += clampi(int(safe.position.x * sx), 0, int(view.x * 0.15))
			right += clampi(int((screen.x - safe.end.x) * sx), 0, int(view.x * 0.15))
			top += clampi(int(safe.position.y * sy), 0, int(view.y * 0.15))
	margin.add_theme_constant_override(&"margin_left", left)
	margin.add_theme_constant_override(&"margin_right", right)
	margin.add_theme_constant_override(&"margin_top", top)
	margin.add_theme_constant_override(&"margin_bottom", base)

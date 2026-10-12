class_name TouchControls
extends Control
## Joystick ảo (nửa trái màn hình, nổi tại vị trí chạm) + nút lao (phải)
## + vùng kéo xoay camera (nửa phải, chỉ khi bật camera sau lưng).
## Không điều khiển nhân vật trực tiếp: chỉ nhấn/nhả các action trong InputMap,
## nên bàn phím và cảm ứng đi chung một đường logic (PlayerInput).
## Mỗi ngón tay được theo dõi bằng index riêng => hỗ trợ đa điểm chạm.

@export var joystick_radius: float = 90.0
@export var knob_radius: float = 40.0
@export var dash_button_radius: float = 72.0
@export_range(0.0, 0.9) var deadzone: float = 0.15

## Kéo ngón tay ở nửa phải màn hình (độ dời theo pixel) để xoay camera sau lưng.
signal look_dragged(relative: Vector2)

## 0..1, do UI cập nhật để vẽ hồi chiêu trên nút lao.
var dash_ready_ratio: float = 1.0
## Bật khi dùng camera sau lưng.
var look_enabled := false

var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _dash_index := -1
var _look_index := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_on_visibility_changed)


func _ui_scale() -> float:
	return clampf(size.y / 720.0, 0.7, 1.8)


func _joy_home() -> Vector2:
	var s := _ui_scale()
	return Vector2(60.0 + joystick_radius * s * 1.3, size.y - 60.0 - joystick_radius * s * 1.3)


func _dash_center() -> Vector2:
	var s := _ui_scale()
	return Vector2(size.x - 60.0 - dash_button_radius * s * 1.4, size.y - 60.0 - dash_button_radius * s * 1.4)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var local: Vector2 = make_input_local(event).position
		if event.pressed:
			if _dash_index == -1 and local.distance_to(_dash_center()) <= dash_button_radius * _ui_scale() * 1.3:
				_dash_index = event.index
				Input.action_press(&"dash")
				get_viewport().set_input_as_handled()
			elif _joy_index == -1 and local.x < size.x * 0.5 and local.y > size.y * 0.25:
				_joy_index = event.index
				_joy_center = local
				_update_joystick(local)
				get_viewport().set_input_as_handled()
			elif look_enabled and _look_index == -1 and local.x >= size.x * 0.5 and local.y > size.y * 0.2:
				_look_index = event.index
				get_viewport().set_input_as_handled()
		else:
			if event.index == _joy_index:
				_release_joystick()
			elif event.index == _dash_index:
				_dash_index = -1
				Input.action_release(&"dash")
			elif event.index == _look_index:
				_look_index = -1
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _joy_index:
		_update_joystick(make_input_local(event).position)
		get_viewport().set_input_as_handled()
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _look_index:
		look_dragged.emit((make_input_local(event) as InputEventScreenDrag).relative)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _update_joystick(local: Vector2) -> void:
	var r := joystick_radius * _ui_scale()
	var offset := local - _joy_center
	if offset.length() > r:
		# Kéo tâm joystick theo ngón tay khi vượt bán kính.
		_joy_center = local - offset.normalized() * r
		offset = local - _joy_center
	_joy_vec = offset / r
	var v := _joy_vec if _joy_vec.length() > deadzone else Vector2.ZERO
	_set_axis(&"move_left", &"move_right", v.x)
	_set_axis(&"move_forward", &"move_back", v.y)


func _set_axis(negative: StringName, positive: StringName, value: float) -> void:
	if value > 0.0:
		Input.action_release(negative)
		Input.action_press(positive, value)
	elif value < 0.0:
		Input.action_release(positive)
		Input.action_press(negative, -value)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


func _release_joystick() -> void:
	_joy_index = -1
	_joy_vec = Vector2.ZERO
	for action in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(action)


## Nhả mọi ngón tay và action (khi ẩn, pause hoặc mất focus) để input không bị kẹt.
func reset_input() -> void:
	_look_index = -1
	if _joy_index != -1:
		_release_joystick()
	if _dash_index != -1:
		_dash_index = -1
		Input.action_release(&"dash")
	queue_redraw()


func _on_visibility_changed() -> void:
	if not visible:
		reset_input()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		reset_input()


func _draw() -> void:
	var s := _ui_scale()
	var r := joystick_radius * s
	var center := _joy_center if _joy_index != -1 else _joy_home()
	draw_circle(center, r, Color(0, 0, 0, 0.25))
	draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 3.0, true)
	draw_circle(center + _joy_vec * r, knob_radius * s, Color(1, 1, 1, 0.6))

	var dc := _dash_center()
	var dr := dash_button_radius * s
	var dash_ok := dash_ready_ratio >= 1.0
	var pressed := _dash_index != -1
	draw_circle(dc, dr, Color(0.85, 0.2, 0.15, 0.85 if dash_ok else 0.4).lightened(0.2 if pressed else 0.0))
	if not dash_ok:
		draw_arc(dc, dr - 4.0, -PI * 0.5, -PI * 0.5 + TAU * dash_ready_ratio, 48, Color(1, 1, 1, 0.8), 6.0, true)
	var font := get_theme_default_font()
	var font_size := int(28 * s)
	var text := "LAO"
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, dc + Vector2(-tw * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

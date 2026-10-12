class_name GameSettings
extends RefCounted
## Cài đặt người chơi: âm lượng 3 kênh (Master / Music / SFX), rung, điều khiển cảm ứng.
## Lưu bằng ConfigFile nên giữ lại sau khi tắt game.

## Đổi được (vd. khi chạy test) để không đụng tới cài đặt thật.
static var path := "user://settings.cfg"

## Âm lượng 0..1 theo tên bus trong default_bus_layout.tres.
static var volumes := {&"Master": 1.0, &"Music": 0.7, &"SFX": 1.0}
static var vibration := true
## -1 = tự nhận (bật nếu máy có màn hình cảm ứng), 0 = tắt, 1 = bật.
static var touch_mode := -1


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for bus in volumes:
		volumes[bus] = clampf(cfg.get_value("audio", String(bus), volumes[bus]), 0.0, 1.0)
	vibration = cfg.get_value("controls", "vibration", vibration)
	touch_mode = cfg.get_value("controls", "touch", touch_mode)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus in volumes:
		cfg.set_value("audio", String(bus), volumes[bus])
	cfg.set_value("controls", "vibration", vibration)
	cfg.set_value("controls", "touch", touch_mode)
	cfg.save(path)


static func set_volume(bus: StringName, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	apply_bus(bus)


static func apply_audio() -> void:
	for bus in volumes:
		apply_bus(bus)


## 0 = tắt hẳn kênh, 1 = 0 dB.
static func apply_bus(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var v: float = volumes[bus]
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


## Rung điện thoại (không có tác dụng trên PC).
static func vibrate(duration_ms: int) -> void:
	if vibration:
		Input.vibrate_handheld(duration_ms)

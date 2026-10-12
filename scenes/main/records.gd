class_name Records
extends RefCounted
## Bảng kỷ lục phá đảo: các lần phá đảo nhanh nhất, lưu bằng ConfigFile (giữ lại sau khi tắt game).

const MAX_ENTRIES := 10

## Đổi được (vd. khi chạy test) để không đụng tới kỷ lục thật.
static var path := "user://records.cfg"


## Danh sách lần phá đảo, nhanh nhất trước. Mỗi phần tử: {time, character, losses, date}.
static func load_runs() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return []
	return cfg.get_value("records", "runs", [])


## Ghi một lần phá đảo. Trả về hạng (1 = nhanh nhất) hoặc 0 nếu không lọt top.
static func add_run(time_sec: float, character: String, losses: int) -> int:
	var runs := load_runs()
	var entry := {
		"time": time_sec,
		"character": character,
		"losses": losses,
		"date": Time.get_date_string_from_system(),
	}
	runs.append(entry)
	runs.sort_custom(func(a, b): return a.time < b.time)
	var rank := 0
	for i in runs.size():
		if is_same(runs[i], entry):
			rank = i + 1
	runs.resize(mini(runs.size(), MAX_ENTRIES))
	var cfg := ConfigFile.new()
	cfg.set_value("records", "runs", runs)
	cfg.save(path)
	return rank if rank <= MAX_ENTRIES else 0


## 83.456 -> "01:23.46"
static func format_time(sec: float) -> String:
	return "%02d:%05.2f" % [int(sec) / 60, fmod(sec, 60.0)]

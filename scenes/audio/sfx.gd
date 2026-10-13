extends Node
## Autoload "Sfx" (scenes/audio/sfx.tscn). Mỗi hiệu ứng âm thanh là một AudioStreamPlayer con
## đặt tên theo âm (dash, hit, fall, ...), chỉnh âm lượng/file trong editor.
## "Music" phát nhạc nền: bài mặc định của node Music cho menu, mỗi màn có bài riêng (Level.music).
## Hiệu ứng đi qua bus "SFX", nhạc qua bus "Music" => chỉnh âm lượng riêng trong Cài đặt.

var _menu_music: AudioStream


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_music = $Music.stream
	GameSettings.load_settings()
	GameSettings.apply_audio()


## pitch < 1 = trầm hơn: dùng lại một file cho âm khác (vd. tiếng lao trầm làm tiếng gió).
func play(sound: StringName, pitch_jitter: float = 0.08, pitch: float = 1.0) -> void:
	var p := get_node_or_null(NodePath(sound)) as AudioStreamPlayer
	if p == null:
		push_warning("Không có âm thanh '%s' trong sfx.tscn" % sound)
		return
	p.pitch_scale = pitch + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Phát nhạc nền `stream` (để trống = nhạc menu). Đang phát đúng bài thì giữ nguyên, không phát lại từ đầu.
func play_music(stream: AudioStream = null) -> void:
	var music: AudioStreamPlayer = $Music
	var target := stream if stream else _menu_music
	if music.stream != target:
		music.stream = target
		music.play()
	elif not music.playing:
		music.play()


func current_music() -> AudioStream:
	return $Music.stream


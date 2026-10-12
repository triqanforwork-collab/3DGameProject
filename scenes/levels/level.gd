class_name Level
extends Node3D
## Gốc của mỗi màn (sky_arena.tscn, ice_peak.tscn, volcano.tscn). Thông số màn chỉnh trong Inspector.
## Cần các node con: Arena, SpawnPoints (các Marker3D, tối thiểu bot_count + 1), Showcase (Marker3D).

@export var stage_name: String = "Đấu Trường Mây"
@export_range(1, 15) var bot_count: int = 7
## Số lần mỗi bot được hồi sinh (rơi từ trên trời xuống lại sàn). Người chơi không hồi sinh.
@export_range(0, 3) var bot_respawns: int = 0
## Nhạc nền của màn (để trống = dùng nhạc menu).
@export var music: AudioStream

@export_group("Độ khó bot")
@export var bot_think_interval: float = 0.3
## Độ trễ trước khi lao (giây). Thấp = bot phản ứng nhanh hơn.
@export var bot_reaction_time: float = 0.4
## Sai số hướng lao (độ). Thấp = bot ngắm chuẩn hơn.
@export var bot_aim_error_deg: float = 15.0
@export_range(0.0, 1.0) var bot_aggression: float = 0.55

@onready var arena: Arena = $Arena
@onready var spawn_points: Node3D = $SpawnPoints
@onready var showcase: Node3D = $Showcase

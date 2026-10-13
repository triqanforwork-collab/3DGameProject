class_name Fighter
extends CharacterBody3D
## Chiến binh dùng chung cho người chơi và bot:
## di chuyển, lao đẩy, hất văng, animation và bị loại.
## Controller (PlayerInput / BotBrain) chỉ ghi move_input và gọi try_dash().
## Mỗi nhân vật là một scene riêng (barbarian.tscn, knight.tscn, ...) gắn script này,
## chỉ số được chỉnh trong Inspector của từng scene.

signal dashed(fighter: Fighter)
signal hit_landed(attacker: Fighter, target: Fighter, point: Vector3)
signal eliminated(fighter: Fighter)
## Rơi khỏi sàn nhưng còn lượt hồi sinh (chưa bị loại hẳn).
signal fell_out(fighter: Fighter)
## Hồi sinh xong: đã đáp xuống sàn.
signal respawned(fighter: Fighter)

const ANIM_IDLE := &"general/Idle_A"
const ANIM_RUN := &"movement/Running_A"
const ANIM_HIT := &"general/Hit_A"
const ANIM_FALL := &"movement/Jump_Idle"
const ANIM_LAND := &"general/Spawn_Air"
const PUSH_CREDIT_MSEC := 6000

@export_group("Nhân vật")
@export var character_name: String = "Chiến binh"
@export_multiline var description: String = ""
## Lực hất văng nhận vào được chia cho chỉ số này (nặng = khó bị đẩy).
@export_range(0.5, 2.0, 0.05) var weight: float = 1.0

@export_group("Di chuyển")
@export var move_speed: float = 5.0
@export var acceleration: float = 20.0
@export var turn_speed: float = 10.0

@export_group("Lao đẩy")
@export var dash_speed: float = 15.0
@export var dash_duration: float = 0.22
@export var dash_cooldown: float = 1.2
## Khoảng cách tâm-tâm (ngang) để tính là trúng khi đang lao.
@export var dash_hit_reach: float = 1.4
@export var knockback_force: float = 9.0
@export var knockback_lift: float = 1.5
## Thời gian người bị đẩy mất điều khiển.
@export var hitstun_time: float = 0.4

@export_group("Hất văng")
## Giảm tốc của vận tốc hất văng khi đứng trên sàn / khi đang bay (m/s²).
@export var knockback_ground_decay: float = 20.0
@export var knockback_air_decay: float = 3.0

@export_group("Khác")
@export var elimination_y: float = -12.0
## Thời gian không bị đẩy / không lao được sau khi hồi sinh đáp xuống sàn.
@export var spawn_protect_time: float = 1.0

var display_name: String = ""
## Hướng di chuyển mong muốn trên mặt phẳng XZ (độ dài 0..1), controller ghi vào.
var move_input: Vector3 = Vector3.ZERO
var controls_enabled: bool = false
var is_eliminated: bool = false
var push_outs: int = 0
## Hướng nhìn gần nhất (model KayKit nhìn về +Z).
var facing: Vector3 = Vector3.BACK
var last_attacker: Fighter
## Số lần còn được hồi sinh khi rơi khỏi sàn (Main đặt theo màn).
var respawns_left: int = 0
## Vận tốc môi trường đẩy trong tick này (vd. gió). Dùng xong là xoá, nên nguồn đẩy phải cộng lại mỗi tick.
var push_velocity: Vector3 = Vector3.ZERO

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

var _move_velocity := Vector3.ZERO
var _knockback := Vector3.ZERO
var _dash_dir := Vector3.ZERO
var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _stun_left := 0.0
var _air_time := 0.0
var _last_hit_msec := 0
var _hit_this_dash: Array[Fighter] = []
var _current_anim: StringName
var _waiting_respawn := false
var _respawn_falling := false
var _spawn_protect_left := 0.0

@onready var visual: Node3D = $Visual
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var marker: MeshInstance3D = $Marker
@onready var name_label: Label3D = $NameLabel
@onready var dash_dust: CPUParticles3D = $DashDust


func _ready() -> void:
	add_to_group(&"fighters")
	# Jump_Idle trong thư viện không lặp; dùng làm tư thế rơi nên bật lặp.
	var fall_anim := animation_player.get_animation(ANIM_FALL)
	if fall_anim:
		fall_anim.loop_mode = Animation.LOOP_LINEAR
	_play_anim(ANIM_IDLE)
	visual.rotation.y = atan2(facing.x, facing.z)


func setup_display(label_text: String, label_color: Color, show_marker: bool, marker_color: Color) -> void:
	name_label.text = label_text
	name_label.modulate = label_color
	marker.visible = show_marker
	if show_marker:
		var mat := marker.material_override.duplicate() as StandardMaterial3D
		mat.albedo_color = marker_color
		marker.material_override = mat


func face_direction(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		facing = dir.normalized()
		if is_node_ready():
			visual.rotation.y = atan2(facing.x, facing.z)


func _physics_process(delta: float) -> void:
	if is_eliminated:
		return
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	_stun_left = maxf(_stun_left - delta, 0.0)
	if _spawn_protect_left > 0.0:
		_spawn_protect_left = maxf(_spawn_protect_left - delta, 0.0)
		# Nhấp nháy khi đang được bảo vệ (chỉ ẩn/hiện Visual).
		visual.visible = _spawn_protect_left <= 0.0 or int(_spawn_protect_left * 12.0) % 2 == 0

	var vertical := velocity.y
	if is_on_floor():
		_air_time = 0.0
	else:
		vertical -= gravity * delta
		_air_time += delta

	var input_dir := Vector3(move_input.x, 0.0, move_input.z).limit_length(1.0)
	if not controls_enabled or _stun_left > 0.0 or _respawn_falling:
		input_dir = Vector3.ZERO

	# Vận tốc tự điều khiển (đi bộ hoặc lao) và vận tốc hất văng là hai phần riêng,
	# nên code di chuyển không bao giờ ghi đè hất văng.
	if _dash_time_left > 0.0:
		_dash_time_left -= delta
		_move_velocity = _dash_dir * (dash_speed if _dash_time_left > 0.0 else move_speed)
	else:
		_move_velocity = _move_velocity.move_toward(input_dir * move_speed, acceleration * delta)

	var decay := knockback_ground_decay if is_on_floor() else knockback_air_decay
	_knockback = _knockback.move_toward(Vector3.ZERO, decay * delta)

	velocity = _move_velocity + _knockback + push_velocity
	velocity.y = vertical
	push_velocity = Vector3.ZERO
	# move_and_slide quét hình dạng theo chuyển động nên không xuyên qua đối thủ
	# (bước lao ~0.25 m/tick < bán kính capsule 0.5 m).
	move_and_slide()

	if _dash_time_left > 0.0:
		_check_dash_hits()
	if _respawn_falling and is_on_floor():
		_land_after_respawn()

	_update_facing(input_dir, delta)
	_update_visual(delta)
	_update_animation()

	if global_position.y < elimination_y:
		_fall_off()


# --- Lao đẩy ---------------------------------------------------------------

func can_dash() -> bool:
	return controls_enabled and is_active() and is_on_floor() and _spawn_protect_left <= 0.0 \
		and _dash_cooldown_left <= 0.0 and _dash_time_left <= 0.0 and _stun_left <= 0.0


## Đang ở trên sàn và tham gia trận (không bị loại, không chờ / đang rơi hồi sinh).
func is_active() -> bool:
	return not is_eliminated and not _waiting_respawn and not _respawn_falling


## Đang chờ hoặc đang rơi xuống để hồi sinh.
func is_respawning() -> bool:
	return _waiting_respawn or _respawn_falling


func is_spawn_protected() -> bool:
	return _spawn_protect_left > 0.0 or _respawn_falling


func is_dashing() -> bool:
	return _dash_time_left > 0.0


## 0 = vừa dùng, 1 = sẵn sàng.
func get_dash_ready_ratio() -> float:
	return 1.0 - _dash_cooldown_left / dash_cooldown if dash_cooldown > 0.0 else 1.0


## Lao theo dir; nếu dir rỗng thì lao theo hướng nhìn gần nhất.
func try_dash(dir: Vector3 = Vector3.ZERO) -> bool:
	if not can_dash():
		return false
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = facing
	_dash_dir = dir.normalized()
	facing = _dash_dir
	_dash_time_left = dash_duration
	_dash_cooldown_left = dash_cooldown
	_hit_this_dash.clear()
	dashed.emit(self)
	return true


func _check_dash_hits() -> void:
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var other := node as Fighter
		if other == self or not other.is_active() or other.is_spawn_protected() or _hit_this_dash.has(other):
			continue
		if absf(other.global_position.y - global_position.y) > 1.5:
			continue
		var to_other := other.global_position - global_position
		to_other.y = 0.0
		var dist := to_other.length()
		if dist > dash_hit_reach:
			continue
		var to_dir := to_other / dist if dist > 0.001 else _dash_dir
		if _dash_dir.dot(to_dir) < 0.2:
			continue

		# Mỗi lần lao chỉ tác động một lần lên mỗi đối thủ.
		_hit_this_dash.append(other)
		var push_dir := (_dash_dir * 0.6 + to_dir * 0.4).normalized()
		var point := (global_position + other.global_position) * 0.5 + Vector3.UP
		var clash := other.is_dashing() and other._dash_dir.dot(-push_dir) > 0.5
		if clash:
			# Hai người lao vào nhau: cả hai bật ra, yếu hơn.
			other._hit_this_dash.append(self)
			other.receive_hit(self, push_dir, knockback_force * 0.6)
			receive_hit(other, -push_dir, knockback_force * 0.6)
		else:
			other.receive_hit(self, push_dir, knockback_force)
			_knockback -= push_dir * 2.0
			_dash_time_left = minf(_dash_time_left, 0.05)
		hit_landed.emit(self, other, point)


## attacker = null khi bị môi trường hất (vd. dung nham), lift < 0 = dùng knockback_lift.
func receive_hit(attacker: Fighter, dir: Vector3, force: float, lift: float = -1.0) -> void:
	if not is_active() or is_spawn_protected():
		return
	_dash_time_left = 0.0
	_move_velocity *= 0.2
	dir.y = 0.0
	_knockback = dir.normalized() * force / weight
	velocity.y = maxf(velocity.y, knockback_lift if lift < 0.0 else lift)
	_stun_left = hitstun_time
	last_attacker = attacker
	_last_hit_msec = Time.get_ticks_msec()
	_play_anim(ANIM_HIT, true)


# --- Bị loại ---------------------------------------------------------------

## Rơi dưới ngưỡng Y: còn lượt hồi sinh thì chờ Main gọi respawn_at(), hết lượt thì bị loại hẳn.
## Mỗi lần rơi chỉ xử lý đúng một lần.
func _fall_off() -> void:
	if not is_active():
		return
	if last_attacker and Time.get_ticks_msec() - _last_hit_msec < PUSH_CREDIT_MSEC:
		last_attacker.push_outs += 1
	else:
		last_attacker = null
	remove_from_group(&"fighters")
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	_dash_time_left = 0.0
	hide()
	set_physics_process(false)
	if respawns_left > 0:
		respawns_left -= 1
		_waiting_respawn = true
		fell_out.emit(self)
	else:
		is_eliminated = true
		controls_enabled = false
		eliminated.emit(self)


## Hồi sinh: xuất hiện ở độ cao drop_height phía trên pos rồi rơi xuống.
## Trong lúc rơi chỉ va chạm với sàn (không đẩy được ai, không bị đẩy).
func respawn_at(pos: Vector3, drop_height: float) -> void:
	if not _waiting_respawn:
		return
	_waiting_respawn = false
	_respawn_falling = true
	last_attacker = null
	global_position = pos + Vector3.UP * drop_height
	velocity = Vector3.ZERO
	_stun_left = 0.0
	collision_layer = 0
	collision_mask = 1
	add_to_group(&"fighters")
	show()
	set_physics_process(true)


func _land_after_respawn() -> void:
	_respawn_falling = false
	_spawn_protect_left = spawn_protect_time
	collision_layer = 2
	collision_mask = 3
	_play_anim(ANIM_LAND, true)
	respawned.emit(self)


# --- Hình ảnh & animation (chỉ tác động lên Visual, không lên node vật lý) --

func _update_facing(input_dir: Vector3, delta: float) -> void:
	var speed_mul := 1.0
	if _dash_time_left > 0.0:
		facing = _dash_dir
		speed_mul = 3.0
	elif input_dir.length_squared() > 0.01:
		facing = input_dir.normalized()
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z),
		minf(turn_speed * speed_mul * delta, 1.0))


func _update_visual(delta: float) -> void:
	var lean := 0.08 * (_move_velocity.length() / move_speed)
	if _dash_time_left > 0.0:
		lean = 0.4
	elif _stun_left > 0.0:
		lean = -0.3
	# Euler YXZ: rotation.x nghiêng theo hướng nhìn; dương = chúi về trước.
	visual.rotation.x = lerpf(visual.rotation.x, lean, minf(12.0 * delta, 1.0))
	dash_dust.emitting = _dash_time_left > 0.0


func _update_animation() -> void:
	var anim := ANIM_IDLE
	if _spawn_protect_left > 0.0 and _move_velocity.length() < 0.5:
		anim = ANIM_LAND  # tư thế đáp đất khi vừa hồi sinh
	elif _air_time > 0.3 or _respawn_falling:
		anim = ANIM_FALL
	elif _stun_left > 0.0:
		anim = ANIM_HIT
	elif _dash_time_left > 0.0 or _move_velocity.length() > 0.5:
		anim = ANIM_RUN
	animation_player.speed_scale = 1.8 if _dash_time_left > 0.0 else 1.0
	_play_anim(anim)


func _play_anim(anim: StringName, restart: bool = false) -> void:
	if anim == _current_anim and not restart:
		return
	_current_anim = anim
	if restart:
		animation_player.stop()
	animation_player.play(anim, 0.15)

class_name Wander
extends RefCounted
## 플레이어를 놓쳤을 때(연기 속 은신 = Player.hidden) 하는 배회·두리번거림.
## 놓친 순간 서 있던 자리(anchor) 주변의 빈 곳을 골라 평소보다 느리게 걸어가고, 도착하면 잠깐 서서
## 고개를 좌우로 돌리며 살핀다 (양 끝에서 잠깐 머무는 박자). 플레이어가 다시 보이면 곧바로 끝난다.
## Enemy 가 하나씩 갖고 매 물리 틱 update 한다. 기체 AI 는 on 일 때
##   move_dir() 쪽으로 (평소 속도 × SPEED_K) 움직이고, face_dir() 쪽을 보며, sway()·nod() 를 몸체 자세에 더한다.

const RADIUS := 3.2          # anchor 에서 이만큼 안쪽으로만 돌아다닌다
const ARRIVE := 0.45
const SPEED_K := 0.4         # 평소 이동 속도에 곱하는 배회 속도 배율
const WALK_MAX := 4.0        # 목적지에 못 닿아도 이 시간 뒤에는 멈춰 선다
const LOOK_ARC := 1.0        # 두리번거리는 좌우 폭 (rad)

var e: Enemy
var on := false
var anchor := Vector3.ZERO
var goal := Vector3.ZERO
var walking := false
var pause_t := 0.0
var walk_t := 0.0
var look_yaw := 0.0          # 멈춰 섰을 때의 정면 (이를 중심으로 두리번거린다)
var look_t := 0.0
var look_amp := 0.0          # 두리번거림 크기 0~1 (부드럽게 오르내린다)


## 지금 플레이어를 놓친 상태인가 (살아 있고 플레이 중인데 연기 속에 숨었다)
static func lost() -> bool:
	var m := Main.inst
	return m != null and m.player != null and m.player.alive and m.player.hidden and m.state == Main.State.PLAY


func update(dt: float) -> void:
	var now := lost()
	if now != on:
		on = now
		if on:
			_begin()
	if not on:
		walking = false
		look_amp = move_toward(look_amp, 0.0, dt * 3.0)
		return
	look_t += dt
	if walking:
		walk_t -= dt
		look_amp = move_toward(look_amp, 0.25, dt * 2.0)
		var d := goal - e.global_position
		d.y = 0
		if d.length() < ARRIVE or walk_t <= 0.0:
			_pause(randf_range(1.2, 2.6))
	else:
		pause_t -= dt
		look_amp = move_toward(look_amp, 1.0, dt * 2.0)
		if pause_t <= 0.0:
			_pick()


func _begin() -> void:
	anchor = e.global_position
	look_t = randf() * TAU         # 기체마다 두리번 박자가 엇갈리게
	# 놓친 자리에서 먼저 멈칫하고 두리번거린다
	_pause(randf_range(0.5, 1.1))


func _pause(dur: float) -> void:
	walking = false
	pause_t = dur
	look_yaw = e.rotation.y


## anchor 주변에서 벽에 막히지 않고 곧장 갈 수 있는 점을 고른다. 못 찾으면 조금 더 서 있는다.
func _pick() -> void:
	for i in 8:
		var a := randf() * TAU
		var c := anchor + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, RADIUS)
		c.y = e.global_position.y
		if (c - e.global_position).length() > 0.9 and _clear(e.global_position, c):
			goal = c
			walking = true
			walk_t = WALK_MAX
			return
	_pause(randf_range(0.6, 1.2))


func _clear(from: Vector3, to: Vector3) -> bool:
	var v := to - from
	v.y = 0
	var l := v.length()
	var d := v / maxf(l, 0.001)
	var s := 0.0
	while s < l + e.radius:
		if Main.inst.is_blocked(from + d * s):
			return false
		s += 0.35
	return true


## 걸어갈 방향 (멈춰 있으면 0)
func move_dir() -> Vector3:
	if not on or not walking:
		return Vector3.ZERO
	var d := goal - e.global_position
	d.y = 0
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


## 바라볼 방향: 걸을 때는 가는 쪽, 서 있을 때는 정면을 중심으로 좌우를 살핀다
func face_dir() -> Vector3:
	var m := move_dir()
	if m != Vector3.ZERO:
		return m
	var yaw := look_yaw + _scan() * LOOK_ARC * look_amp
	return Vector3(-sin(yaw), 0, -cos(yaw))


## 좌우 살피기 곡선 (-1~1): 양 끝에서 잠깐 머물고 가운데는 빨리 지나간다
func _scan() -> float:
	var s := sin(look_t * 1.25)
	return signf(s) * pow(absf(s), 0.45)


## 몸체 좌우 기울임 (살피는 쪽으로 갸웃)
func sway() -> float:
	return -_scan() * 0.13 * look_amp


## 몸체 앞뒤 끄덕임 (바닥을 내려다보며 살핀다)
func nod() -> float:
	return (0.07 + sin(look_t * 2.3) * 0.04) * look_amp

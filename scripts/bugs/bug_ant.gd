class_name BugAnt
extends BugEnemy
## 개미 병정 (ANT SOLDIER). 두 다리로 서서 다니는 적갈색 개미.
##  · 이동: 짧게 후다닥 달렸다 멈췄다를 되풀이하며 지그재그로 거리를 좁힌다 (멈출 때마다 더듬이로 주변을 더듬는다)
##  · 산 발사(중거리): 몸을 뒤로 젖히고 배를 다리 사이로 말아 앞으로 겨눈 뒤 산 덩어리 5발을 부채꼴로 뿜는다 · 눈이 붉게 달아오름
##  · 물기(근거리): 웅크려 큰턱을 활짝 벌렸다가 앞으로 튀어 나가 문다 — 금빛 예고가 뜨는 패링 가능 근접 공격
## 애니메이션은 AntRig. 이 파일은 상태·이동·판정만.

enum A { SKITTER, PAUSE, ACID_WIND, RECOVER, BITE_WIND, LUNGE }

const MODEL := "res://assets/models/bug_ant.glb"
const RUN_SPEED := 5.2
const DESIRED := 6.5
const ACID_WIND_T := 0.7
const ACID_SHOTS := 5
const ACID_SPREAD := 0.42
const ACID_SPEED := 6.8
const BITE_RANGE := 3.0
const BITE_WIND_T := 0.42
const LUNGE_T := 0.2
const LUNGE_SPEED := 13.0
const RECOVER_T := 0.55

var rig: AntRig
var state := A.PAUSE
var st_t := 0.0
var st_len := 0.4
var move_dir := Vector3.ZERO
var zig := 1.0
var cur_speed := 0.0
var attack_cd := 1.2
var bit := false
var turn_rate := 0.0


func _model_path() -> String:
	return MODEL


func _ready() -> void:
	super._ready()
	hp = 5
	radius = 0.55
	hp_bar_y = 2.0
	hp_bar_w = 1.0
	slice_size = Vector3(0.6, 1.2, 0.9)
	slice_color = Color("b04a2c")
	zig = 1.0 if randf() < 0.5 else -1.0
	attack_cd = randf_range(0.8, 1.8)


func _make_rig() -> void:
	rig = AntRig.new().setup(model)


func _set_emerge(k: float) -> void:
	if rig:
		rig.emerge_k = k


func _goo_height() -> float:
	return 0.85


func _flip_height() -> float:
	return 1.32


func _sever_node() -> Node3D:
	return rig.n.head as Node3D


func _rig_update(dt: float) -> void:
	rig.speed = cur_speed
	rig.turn = turn_rate
	if Main.inst and Main.inst.player:
		var l := global_basis.inverse() * _to_player()
		rig.look_yaw = atan2(-l.x, -l.z)
	rig.update(dt)
	if rig.clicked:
		rig.clicked = false
		if near_player(9.0):
			Sfx.play("bug_click", 0.2, -14.0)


func _rig_dead(dt: float, k: float) -> void:
	rig.dead_k = k
	rig.speed = 0.0
	rig.bite_k = move_toward(rig.bite_k, 0.0, dt * 4.0)
	rig.acid_k = move_toward(rig.acid_k, 0.0, dt * 4.0)
	rig.lunge_k = 0.0
	rig.kick_power = clampf(1.0 - death_t / FLIP_TIME, 0.15, 1.0)
	rig.update(dt)


func _ai(dt: float) -> void:
	var player := Main.inst.player
	var to_p := _to_player()
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var cm: StandardMaterial3D = j.core_mat
	st_t += dt
	attack_cd -= dt
	var active := player.alive and not player.hidden and Main.inst.state == Main.State.PLAY
	var want := 0.0
	match state:
		A.SKITTER:
			want = RUN_SPEED
			# 짧게 달린다: 출발은 확, 끝에 살짝 느려진다
			want *= clampf(st_t / 0.06, 0.0, 1.0) * (1.0 - smoothstep(st_len - 0.08, st_len, st_t) * 0.6)
			turn_rate = _face(move_dir, dt, 16.0)
			if st_t >= st_len:
				_go(A.PAUSE, randf_range(0.7, 1.4) if wander.on else randf_range(0.18, 0.5))
				rig.alarm = maxf(rig.alarm, 0.25)
		A.PAUSE:
			turn_rate = _face(dir, dt, 4.0 if wander.on else 9.0)
			# 놓쳤을 때: 배회가 멈춰 두리번거리는 동안은 제자리에서 고개만 돌린다
			if st_t >= st_len and not (wander.on and not wander.walking):
				if active and attack_cd <= 0.0 and dist < BITE_RANGE:
					_go(A.BITE_WIND, BITE_WIND_T)
					_warn(global_position + dir * 0.8, "melee")
					Sfx.play("charge", 0.1, -10.0)
				elif active and attack_cd <= 0.0 and dist > 3.4 and dist < 11.5:
					_go(A.ACID_WIND, ACID_WIND_T)
					Sfx.play("charge", 0.1, -12.0)
				else:
					_pick_skitter(dir, dist)
		A.ACID_WIND:
			turn_rate = _face(dir, dt, 10.0)
			var k := st_t / ACID_WIND_T
			rig.acid_k = smoothstep(0.0, 0.75, k)
			cm.emission_energy_multiplier = 3.5 * k
			punch = maxf(punch, 0.15 * k)
			if st_t >= ACID_WIND_T:
				_spit()
				_go(A.RECOVER, RECOVER_T)
		A.BITE_WIND:
			turn_rate = _face(dir, dt, 14.0)
			var k := st_t / BITE_WIND_T
			rig.bite_k = smoothstep(0.0, 0.85, k)
			cm.emission_energy_multiplier = 3.5 * k
			if st_t >= BITE_WIND_T:
				move_dir = -global_basis.z
				move_dir.y = 0
				move_dir = move_dir.normalized()
				bit = false
				_end_warn()
				_go(A.LUNGE, LUNGE_T)
				Sfx.play("dash", 0.1, -8.0)
		A.LUNGE:
			want = LUNGE_SPEED * (1.0 - st_t / LUNGE_T * 0.5)
			rig.bite_k = 0.0
			rig.lunge_k = 1.0
			cm.emission_energy_multiplier = 0.0
			if not bit and dist < radius + player.hit_radius + 0.55 and player.take_hit(global_position):
				bit = true
				player.velocity += move_dir * 7.0
				FX.sparks(player.global_position + Vector3(0, 0.8, 0), 10, [Color.WHITE, Color("ffd060")], 7.0, 0.25, -12.0, 0.06)
				Sfx.play("clank", 0.1, -2.0)
				Main.inst.shake(0.2)
			if st_t >= LUNGE_T:
				_go(A.RECOVER, RECOVER_T + 0.15)
		A.RECOVER:
			turn_rate = _face(dir, dt, 6.0)
			rig.acid_k = move_toward(rig.acid_k, 0.0, dt * 3.0)
			rig.lunge_k = move_toward(rig.lunge_k, 0.0, dt * 4.0)
			cm.emission_energy_multiplier = move_toward(cm.emission_energy_multiplier, 0.0, dt * 8.0)
			if st_t >= st_len:
				attack_cd = randf_range(1.6, 2.8)
				_pick_skitter(dir, dist)
	cur_speed = move_toward(cur_speed, want, dt * (60.0 if want > cur_speed else 30.0))
	var step := move_dir if state != A.PAUSE else Vector3.ZERO
	global_position += (step * cur_speed + _separation(1.6) * 2.0 + knock) * dt
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = Main.inst.push_out(global_position, radius)


## 다음 달리기 방향: 원하는 거리 쪽으로, 좌우로 번갈아 꺾어 지그재그
func _pick_skitter(dir: Vector3, dist: float) -> void:
	zig = -zig
	if wander.on:
		# 놓쳤을 때: 배회 목적지 쪽으로 짧게 종종걸음
		move_dir = dir.rotated(Vector3.UP, zig * randf_range(0.1, 0.4)).normalized()
		_go(A.SKITTER, randf_range(0.18, 0.32))
		return
	var to := dir
	if dist < DESIRED - 1.5:
		to = -dir
	elif absf(dist - DESIRED) <= 1.5:
		to = Vector3(-dir.z, 0, dir.x) * zig     # 거리가 맞으면 옆으로 돈다
	move_dir = to.rotated(Vector3.UP, zig * randf_range(0.45, 0.95)).normalized()
	_go(A.SKITTER, randf_range(0.28, 0.55))
	if near_player(10.0):
		Sfx.play("bug_skitter", 0.2, -12.0)


func _go(s: int, dur: float) -> void:
	state = s
	st_t = 0.0
	st_len = dur


## 산 발사: 배 끝에서 부채꼴 5발 (탄 높이는 다른 적과 같은 0.95m)
func _spit() -> void:
	var fwd := -global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var tip := model.find_child("pt_stinger", true, false) as Node3D
	var origin := tip.global_position if tip else global_position + fwd * 0.6
	origin.y = global_position.y + 0.95
	for i in ACID_SHOTS:
		var a := lerpf(-ACID_SPREAD, ACID_SPREAD, i / float(ACID_SHOTS - 1))
		var d := fwd.rotated(Vector3.UP, a)
		Main.inst.add_bullet(Bullet.make_enemy(origin + d * 0.25, d, ACID_SPEED * randf_range(0.92, 1.08), i == ACID_SHOTS / 2))
	FX.sparks(origin, 12, GOO, 6.0, 0.35, -10.0, 0.07)
	FX.flash(origin, Color(0.85, 1.0, 0.5), 0.7, 0.07)
	rig.fire_k = 1.0
	rig.acid_k = 0.7
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.0
	punch = 0.5
	Sfx.play("bug_hiss", 0.1, -3.0)
	Sfx.play("eshot", 0.08, -8.0)


## 물기(패링 공격)는 준비동작부터 돌진이 끝날 때까지 맞아도 끊기지 않는다
func parry_committed() -> bool:
	return state == A.BITE_WIND or state == A.LUNGE


func _charge_glow_k() -> float:
	return maxf(st_t / BITE_WIND_T, 0.01) if state == A.BITE_WIND else 0.0


## 피격·패링 경직: 하던 공격을 끊는다
func _on_stagger() -> void:
	if rig:
		rig.acid_k = 0.0
		rig.bite_k = 0.0
		rig.lunge_k = 0.0
		rig.alarm = 1.0
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.0
	cur_speed = 0.0
	_go(A.PAUSE, randf_range(0.2, 0.4))
	attack_cd = maxf(attack_cd, 0.6)

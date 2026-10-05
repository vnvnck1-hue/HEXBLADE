class_name BugGrub
extends BugEnemy
## 애벌레 (GRUB). 크림색 돔 몸통에 띠 두 개, 앞에 회색 머리와 갈색 더듬이 한 쌍 — 눈도 다리도 없는 가장 기본 몬스터.
##  · 몸 전체를 꼬리부터 머리로 수축·이완(연동 운동)하며 느릿느릿 기어 다닌다 (GrubRig)
##  · 서 있을 땐 앞몸을 들고 두리번거리며 더듬이로 바닥을 톡톡 두드린다
##  · 플레이어를 보면 앞몸을 번쩍 들고(알아챔) 기어서 다가온다
##  · 근접 공격: 몸을 꼬리 쪽으로 바짝 움츠려 앞몸을 쳐들고 더듬이를 활짝 벌려 떤다(금빛 예고 = 패링 가능)
##    → 몸을 앞으로 확 늘이며 덮쳐 더듬이로 덥석 → 천천히 몸을 추스른다
##  · 지나간 자리에 달팽이처럼 투명한 점액 흔적을 남긴다 (SlimeTrail, 몇 초 뒤 마름)

enum G { IDLE, WANDER, NOTICE, CHASE, WINDUP, LUNGE, RECOVER }

const MODEL := "res://assets/models/bug_grub.glb"
const GOO_W: Array[Color] = [Color("fffbea"), Color("efe6c8"), Color("d4c9a2"), Color("958b6a")]
const SIGHT := 13.0
const CRAWL_SPEED := 0.85
const WANDER_SPEED := 0.42
const BITE_RANGE := 2.0
const NOTICE_T := 0.7
const WINDUP_T := 0.75
const LUNGE_T := 0.3
const LUNGE_DIST := 1.5
const RECOVER_T := 1.0
const TURN_RATE := 3.2          ## 애벌레는 천천히 돈다

var rig: GrubRig
var trail: SlimeTrail
var state := G.IDLE
var st_t := 0.0
var st_len := 1.0
var cur_speed := 0.0
var turn_rate := 0.0
var move_dir := Vector3.FORWARD
var lunge_dir := Vector3.FORWARD
var noticed := false
var attack_cd := 1.0
var bit := false
var snapped := false


func _model_path() -> String:
	return MODEL


func _ready() -> void:
	super._ready()
	hp = 3
	radius = 0.55
	hp_bar_y = 0.95
	hp_bar_w = 0.85
	slice_size = Vector3(0.9, 0.5, 1.3)
	slice_color = Color("f2e3cd")
	goo = GOO_W
	splat_kind = 2
	shadow.queue_free()
	shadow = FX.blob_shadow(self, 1.5, 0.55)
	attack_cd = randf_range(0.8, 1.6)
	_go(G.IDLE, randf_range(0.5, 1.5))


func _make_rig() -> void:
	rig = GrubRig.new().setup(model)
	trail = SlimeTrail.make(0.6)


func _set_emerge(k: float) -> void:
	if rig:
		rig.emerge_k = k


func _goo_height() -> float:
	return 0.28


func _flip_height() -> float:
	return 0.5


func _sever_node() -> Node3D:
	return rig.head


func _rig_update(dt: float) -> void:
	var to_p := _to_player()
	rig.speed = cur_speed if state != G.LUNGE else 0.0
	rig.turn = turn_rate
	rig.look_yaw = wrapf(atan2(-to_p.x, -to_p.z) - rotation.y, -PI, PI) if to_p.length() < SIGHT else 0.0
	if stagger_t > 0.0:
		rig.dizzy = clampf(stagger_t / stagger_total * 1.6, 0.0, 1.0)
	else:
		rig.dizzy = move_toward(rig.dizzy, 0.0, dt * 2.5)
	rig.update(dt)
	if rig.pulsed and near_player(9.0):
		Sfx.play("bug_squelch", 0.25, -17.0)
	_feed_trail()


## 꼬리 끝이 지나간 자리에 점액을 남긴다
func _feed_trail() -> void:
	if not is_instance_valid(trail) or not landed:
		return
	trail.feed(model.global_transform * rig.tail_local(), -global_basis.z)


func _rig_dead(dt: float, k: float) -> void:
	rig.dead_k = k
	rig.speed = 0.0
	rig.windup = 0.0
	rig.lunge = 0.0
	rig.kick_power = 1.0 - clampf(death_t / FLIP_TIME, 0.0, 1.0) * 0.8
	rig.update(dt)


func die(dir := Vector3.ZERO, source := "bullet") -> void:
	super.die(dir, source)
	if is_instance_valid(trail):
		trail.release()


func _exit_tree() -> void:
	super._exit_tree()
	if is_instance_valid(trail):
		trail.release()


# ── 행동 ───────────────────────────────────────

func _ai(dt: float) -> void:
	var player := Main.inst.player
	var to_p := _to_player()
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var cm: StandardMaterial3D = j.core_mat
	var fwd := -global_basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	st_t += dt
	attack_cd -= dt
	var active := player.alive and not player.hidden and Main.inst.state == Main.State.PLAY
	var want := 0.0
	var step_dir := fwd
	match state:
		G.IDLE:
			turn_rate = 0.0
			if active and dist < SIGHT:
				_notice()
			elif st_t >= st_len:
				move_dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
				_go(G.WANDER, randf_range(2.0, 4.0))
		G.WANDER:
			want = WANDER_SPEED
			move_dir = move_dir.rotated(Vector3.UP, sin(t * 0.9) * 0.6 * dt)
			turn_rate = _face(move_dir, dt, TURN_RATE * 0.6)
			if active and dist < SIGHT:
				_notice()
			elif st_t >= st_len:
				_go(G.IDLE, randf_range(1.2, 2.8))
		G.NOTICE:
			turn_rate = _face(dir, dt, TURN_RATE)
			if st_t >= st_len:
				_go(G.CHASE, 99.0)
		G.CHASE:
			if not active:
				_go(G.IDLE, randf_range(0.8, 1.6))
			else:
				move_dir = dir
				# 몸을 돌리는 동안은 덜 나아간다 (옆으로 미끄러지지 않게)
				var align := clampf(fwd.dot(dir), 0.0, 1.0)
				want = CRAWL_SPEED * (0.25 + 0.75 * align * align)
				if dist < 1.2:
					want = 0.0
				turn_rate = _face(move_dir, dt, TURN_RATE)
				if attack_cd <= 0.0 and dist < BITE_RANGE and align > 0.8:
					_windup(dir)
		G.WINDUP:
			turn_rate = _face(dir, dt, TURN_RATE * 1.5)
			var k := st_t / WINDUP_T
			rig.windup = smoothstep(0.0, 0.7, k)
			cm.emission_energy_multiplier = 3.5 * k
			if st_t >= WINDUP_T:
				_end_warn()
				lunge_dir = fwd
				bit = false
				snapped = false
				_go(G.LUNGE, LUNGE_T)
				Sfx.play("dash", 0.15, -14.0)
		G.LUNGE:
			var k := st_t / LUNGE_T
			rig.windup = move_toward(rig.windup, 0.0, dt * 9.0)
			rig.lunge = minf(1.0, rig.lunge + dt * 12.0)
			cm.emission_energy_multiplier = 3.5 * (1.0 - k)
			want = LUNGE_DIST / LUNGE_T * (1.3 - k * 0.6)
			step_dir = lunge_dir
			if k > 0.45 and not snapped:
				snapped = true
				rig.bite = 1.0
				Sfx.play("bug_gnash", 0.15, -5.0)
			# 머리(몸 앞끝)가 닿는 범위: 몸 중심에서 앞으로 반 몸길이 + 늘어난 만큼
			var front := global_position + lunge_dir * 0.8
			var pd := player.global_position - front
			pd.y = 0.0
			if not bit and k > 0.3 and pd.length() < player.hit_radius + 0.55 and player.take_hit(global_position):
				bit = true
				player.velocity += lunge_dir * 5.0
				FX.sparks(player.global_position + Vector3(0, 0.6, 0), 8, [Color.WHITE, Color("f2e3cd")], 6.0, 0.25, -12.0, 0.06)
				Main.inst.shake(0.14)
			if st_t >= LUNGE_T:
				FX.puffs(global_position + fwd * 0.6 + Vector3(0, 0.05, 0), 2, DIRT, 0.3, 0.3, 0.4)
				BugEnemy.splat(global_position + fwd * 0.7, 0.75, splat_kind)
				if near_player(10.0):
					Sfx.play("bug_squish", 0.2, -12.0)
				_go(G.RECOVER, RECOVER_T)
		G.RECOVER:
			# 늘어난 몸을 천천히 추스른다 (꼬리를 끌어당기며 제자리에서 한 번 수축)
			turn_rate = _face(dir, dt, TURN_RATE * 0.5)
			rig.lunge = move_toward(rig.lunge, 0.0, dt * 1.6)
			cm.emission_energy_multiplier = move_toward(cm.emission_energy_multiplier, 0.0, dt * 10.0)
			want = 0.25 * (1.0 - st_t / RECOVER_T)
			if st_t >= st_len:
				attack_cd = randf_range(1.4, 2.4)
				_go(G.CHASE if active else G.IDLE, 99.0 if active else randf_range(0.5, 1.0))
	cur_speed = move_toward(cur_speed, want, dt * (4.0 if absf(want) > absf(cur_speed) else 5.0))
	if state == G.LUNGE:
		cur_speed = want
	global_position += (step_dir * cur_speed + _separation(1.3) * 2.0 + knock) * dt
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = Main.inst.push_out(global_position, radius)


func _notice() -> void:
	if noticed:
		_go(G.CHASE, 99.0)
		return
	noticed = true
	rig.startle = 1.0
	cur_speed = 0.0
	_go(G.NOTICE, NOTICE_T)
	if near_player(14.0):
		Sfx.play("bug_chitter", 0.2, -12.0)


func _windup(dir: Vector3) -> void:
	_go(G.WINDUP, WINDUP_T)
	_warn(global_position + dir * 0.9, "melee")
	cur_speed = 0.0
	Sfx.play("charge", 0.15, -14.0)
	if near_player(10.0):
		Sfx.play("bug_squelch", 0.1, -10.0)


func _go(s: int, dur: float) -> void:
	state = s
	st_t = 0.0
	st_len = dur


## 덮치는 중에는 피격 경직으로 끊지 않는다
func _can_hurt() -> bool:
	return state != G.LUNGE


## 덥석(패링 공격)은 움츠리기부터 덮치기가 끝날 때까지 맞아도 끊기지 않는다
func parry_committed() -> bool:
	return state == G.WINDUP or state == G.LUNGE


func _charge_glow_k() -> float:
	return maxf(st_t / WINDUP_T, 0.01) if state == G.WINDUP else 0.0


func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	super.take_hit(dmg, dir, pos, source)
	if alive and rig:
		rig.alarm = 1.0


## 피격·패링 경직: 하던 공격을 끊는다
func _on_stagger() -> void:
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.0
	if rig:
		rig.windup = 0.0
		rig.lunge = 0.0
		rig.alarm = 1.0
	cur_speed = 0.0
	attack_cd = maxf(attack_cd, 0.9)
	noticed = true
	_go(G.CHASE, 99.0)

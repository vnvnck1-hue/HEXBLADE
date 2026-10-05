class_name BugChomper
extends BugEnemy
## 촘퍼 (CHOMPER). 튜토리얼에 나오는 하찮은 우주 벌레 — 노란 갑각 · 청록 몸통 · 얼굴 전체가 입.
##  · 평소: 두리번거리며 헐떡이다 아무 데나 꼼지락꼼지락 돌아다닌다
##  · 플레이어를 보면 깜짝 놀라 콩 뛰고(끽!) 짧게 달렸다 멈췄다 하며 다가온다
##  · 물기: 뒤로 웅크려 입을 쩍 벌리고 판을 곤두세운다(정수리 구슬이 빛남 · 금빛 예고 = 패링 가능) → 콩 뛰어 덥석 → 우물우물 · 입가 핥기
##  · 맞으면 가끔 겁먹고 후다닥 도망쳤다 돌아온다. 패링 당하면 빙글빙글 어질어질.
##  · 돌아다니는 동안 배·꼬리·옆구리·입에서 노란 체액을 조금씩 떨어뜨린다 (방울 → 바닥 웅덩이 → 몇 초 뒤 마름)
## 애니메이션은 ChomperRig. 이 파일은 상태·이동·판정·체액만.

enum C { IDLE, WANDER, NOTICE, CHASE, PAUSE, WINDUP, LUNGE, RECOVER, SCARED }

const MODEL := "res://assets/models/bug_chomper.glb"
const GOO_Y: Array[Color] = [Color("fff6a0"), Color("ffd83a"), Color("f2b21c"), Color("b87a0c")]
const SIGHT := 12.0
const CRAWL_SPEED := 1.7
const WANDER_SPEED := 0.75
const SCARED_SPEED := 3.4
const BITE_RANGE := 2.3
const NOTICE_T := 0.8
const WINDUP_T := 0.62
const LUNGE_T := 0.34
const LUNGE_DIST := 2.3
const RECOVER_T := 0.9
const HOP := 0.32

var rig: ChomperRig
var state := C.IDLE
var st_t := 0.0
var st_len := 1.0
var cur_speed := 0.0
var turn_rate := 0.0
var move_dir := Vector3.FORWARD
var lunge_dir := Vector3.FORWARD
var weave := 0.0
var noticed := false
var attack_cd := 1.0
var bit := false
var snapped := false
var licked := false
var drip_pts: Array[Node3D] = []
var mouth_pt: Node3D
var _drip_t := 0.3
var _drool_t := 1.5

static var _drop_mesh: SphereMesh
static var _drop_mat: StandardMaterial3D
static var _pud_mesh: CylinderMesh
static var _pud_mat: StandardMaterial3D
static var _puddles: Array = []
static var _pud_i := 0
const MAX_PUDDLES := 70


func _model_path() -> String:
	return MODEL


func _ready() -> void:
	super._ready()
	hp = 2
	radius = 0.5
	hp_bar_y = 1.1
	hp_bar_w = 0.8
	slice_size = Vector3(0.9, 0.7, 0.9)
	slice_color = Color("f6bb3c")
	goo = GOO_Y
	splat_kind = 1
	shadow.queue_free()
	shadow = FX.blob_shadow(self, 1.35, 0.6)
	for k in ["pt_drip_belly", "pt_drip_tail", "pt_drip_l", "pt_drip_r", "pt_drip_mouth"]:
		var p := model.find_child(k, true, false) as Node3D
		if p:
			drip_pts.append(p)
	mouth_pt = model.find_child("pt_drip_mouth", true, false) as Node3D
	weave = randf() * TAU
	attack_cd = randf_range(0.8, 1.6)
	_go(C.IDLE, randf_range(0.5, 1.5))


func _make_rig() -> void:
	rig = ChomperRig.new().setup(model)


func _set_emerge(k: float) -> void:
	if rig:
		rig.emerge_k = k


func _goo_height() -> float:
	return 0.35


func _flip_height() -> float:
	return 0.72


func _sever_node() -> Node3D:
	return rig.n.head as Node3D


func _rig_update(dt: float) -> void:
	var to_p := _to_player()
	rig.speed = cur_speed if state != C.LUNGE else 0.0
	rig.turn = turn_rate
	rig.look_yaw = wrapf(atan2(-to_p.x, -to_p.z) - rotation.y, -PI, PI) if to_p.length() < SIGHT else 0.0
	if stagger_t > 0.0:
		rig.dizzy = clampf(stagger_t / stagger_total * 1.6, 0.0, 1.0)
	else:
		rig.dizzy = move_toward(rig.dizzy, 0.0, dt * 2.5)
	rig.update(dt)
	var near := near_player(9.0)
	if rig.stepped and near and randf() < 0.3:
		Sfx.play("bug_skitter", 0.25, -18.0)
	if rig.clacked and near:
		Sfx.play("bug_click", 0.3, -15.0)
	_drips(dt)


func _rig_dead(dt: float, k: float) -> void:
	rig.dead_k = k
	rig.speed = 0.0
	rig.windup = 0.0
	rig.lunge = 0.0
	rig.air = 0.0
	rig.kick_power = 1.0 - clampf(death_t / FLIP_TIME, 0.0, 1.0) * 0.8
	rig.update(dt)


# ── 체액 ───────────────────────────────────────

## 움직이는 동안 몸 여기저기서 노란 방울을 떨어뜨리고, 서 있을 땐 입에서 침처럼 흘린다
func _drips(dt: float) -> void:
	if drip_pts.is_empty() or not landed:
		return
	var moving := absf(cur_speed) > 0.3 or state == C.LUNGE
	_drip_t -= dt * (0.6 + absf(cur_speed) * 0.5 if moving else 0.0)
	if _drip_t <= 0.0:
		_drip_t = randf_range(0.22, 0.5)
		var p: Node3D = drip_pts[randi() % drip_pts.size()]
		var big := randf() < 0.18
		drip(p.global_position, Main.gy(p.global_position), 1.5 if big else 1.0, -global_basis.z * cur_speed * 0.3)
	_drool_t -= dt * (0.0 if moving else 1.0)
	if _drool_t <= 0.0 and mouth_pt:
		_drool_t = randf_range(1.2, 2.6)
		drip(mouth_pt.global_position, Main.gy(mouth_pt.global_position), 0.75)


## 체액 한 방울: 맺힘(늘어남) → 떨어짐(가속) → 바닥에 톡 · 작은 웅덩이 (BugLab 전시·캡처도 쓴다)
static func drip(from: Vector3, floor_y: float, size := 1.0, vel := Vector3.ZERO, sound := true) -> void:
	if FX.root == null:
		return
	_ensure_goo()
	var s := snappedf(size, 0.25)
	var d := MeshInstance3D.new()
	d.mesh = _drop_mesh
	d.material_override = _drop_mat
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	FX.root.add_child(d)
	d.global_position = from
	d.scale = Vector3.ONE * 0.2 * s
	var h := maxf(0.02, from.y - floor_y)
	var fall := sqrt(2.0 * h / 9.8)
	var land := Vector3(from.x + vel.x * fall, floor_y, from.z + vel.z * fall)
	var tw := d.create_tween()
	# 맺힘: 동그랗게 부풀며 아래로 늘어진다
	tw.tween_property(d, "scale", Vector3(0.8, 1.25, 0.8) * s, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(d, "global_position", land + Vector3(0, 0.02, 0), fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(d, "scale", Vector3(0.6, 1.8, 0.6) * s, fall)
	tw.tween_callback(func() -> void:
		puddle(land, 0.065 * s + randf() * 0.025)
		FX.sparks(land + Vector3(0, 0.03, 0), 1 + int(s), GOO_Y, 1.2, 0.2, -12.0, 0.025)
		if sound and Main.inst and Main.inst.player and Main.inst.player.global_position.distance_to(land) < 7.0 and randf() < 0.5:
			Sfx.play("bug_drip", 0.3, -20.0)
		d.queue_free())


## 바닥 웅덩이: 톡 퍼졌다가 몇 초 뒤 오그라들며 마른다. 너무 많으면 오래된 것부터 지운다.
static func puddle(at: Vector3, r: float) -> void:
	_ensure_goo()
	var mi := MeshInstance3D.new()
	mi.mesh = _pud_mesh
	mi.material_override = _pud_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	FX.root.add_child(mi)
	_pud_i = (_pud_i + 1) % 8
	mi.global_position = at + Vector3(0, 0.012 + _pud_i * 0.0012, 0)   # 겹친 웅덩이가 깜빡이지 않게 높이를 조금씩 다르게
	mi.rotation.y = randf() * TAU
	var e := randf_range(0.7, 1.0)
	var full := Vector3(r * 2.0, 1.0, r * 2.0 * e)
	mi.scale = full * 0.2
	_puddles.append(mi)
	while _puddles.size() > MAX_PUDDLES:
		var old: Variant = _puddles.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", full, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(randf_range(3.0, 4.5))
	tw.tween_property(mi, "scale", Vector3(0.02, 1.0, 0.02), 1.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_puddles.erase(mi)
		mi.queue_free())


static func _ensure_goo() -> void:
	if _drop_mesh != null:
		return
	_drop_mesh = SphereMesh.new()
	_drop_mesh.radius = 0.026
	_drop_mesh.height = 0.052
	_drop_mesh.radial_segments = 10
	_drop_mesh.rings = 5
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.albedo_color = Color("ffd23a")
	_drop_mat.roughness = 0.08
	_drop_mat.metallic_specular = 1.0
	_drop_mat.emission_enabled = true
	_drop_mat.emission = Color("ffb800")
	_drop_mat.emission_energy_multiplier = 0.25
	_drop_mat.set_meta("keep_mat", true)
	_pud_mesh = CylinderMesh.new()
	_pud_mesh.top_radius = 0.5
	_pud_mesh.bottom_radius = 0.5
	_pud_mesh.height = 0.006
	_pud_mesh.radial_segments = 16
	_pud_mesh.rings = 1
	_pud_mat = StandardMaterial3D.new()
	_pud_mat.albedo_color = Color("e2a812")
	_pud_mat.roughness = 0.06
	_pud_mat.metallic_specular = 1.0
	_pud_mat.emission_enabled = true
	_pud_mat.emission = Color("e09a00")
	_pud_mat.emission_energy_multiplier = 0.08


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
		C.IDLE:
			turn_rate = 0.0
			if active and dist < SIGHT:
				_notice()
			elif st_t >= st_len:
				move_dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
				_go(C.WANDER, randf_range(1.2, 2.6))
		C.WANDER:
			want = WANDER_SPEED
			move_dir = move_dir.rotated(Vector3.UP, sin(t * 1.7) * 1.2 * dt)
			turn_rate = _face(move_dir, dt, 4.0)
			if active and dist < SIGHT:
				_notice()
			elif st_t >= st_len:
				_go(C.IDLE, randf_range(0.8, 2.2))
		C.NOTICE:
			turn_rate = _face(dir, dt, 12.0)
			if st_t >= st_len:
				_go(C.CHASE, randf_range(0.6, 1.1))
		C.CHASE:
			if not active:
				_go(C.IDLE, randf_range(0.6, 1.2))
			else:
				weave += dt * 2.4
				move_dir = dir.rotated(Vector3.UP, sin(weave) * 0.4)
				if dist < 1.3:
					move_dir = Vector3(-dir.z, 0, dir.x)
				want = CRAWL_SPEED * clampf(st_t / 0.12, 0.0, 1.0)
				turn_rate = _face(move_dir, dt, 8.0)
				if attack_cd <= 0.0 and dist < BITE_RANGE:
					_windup(dir)
				elif st_t >= st_len:
					_go(C.PAUSE, randf_range(0.2, 0.55))
		C.PAUSE:
			turn_rate = _face(dir, dt, 9.0)
			if st_t >= st_len:
				if active and attack_cd <= 0.0 and dist < BITE_RANGE + 0.4:
					_windup(dir)
				else:
					_go(C.CHASE if active else C.IDLE, randf_range(0.7, 1.4))
		C.WINDUP:
			turn_rate = _face(dir, dt, 12.0)
			var k := st_t / WINDUP_T
			rig.windup = smoothstep(0.0, 0.75, k)
			cm.emission_energy_multiplier = 3.5 * k
			want = -0.45 * (1.0 - k)              # 반 발짝 뒷걸음질치며 힘을 모은다
			if st_t >= WINDUP_T:
				_end_warn()
				lunge_dir = fwd
				bit = false
				snapped = false
				_go(C.LUNGE, LUNGE_T)
				Sfx.play("dash", 0.15, -12.0)
				Sfx.play("bug_squeak", 0.2, -12.0)
		C.LUNGE:
			var k := st_t / LUNGE_T
			rig.windup = 0.0
			rig.lunge = 1.0 - k * 0.3
			rig.air = sin(k * PI)
			pose.position.y = sin(k * PI) * HOP
			cm.emission_energy_multiplier = 3.5 * (1.0 - k)
			want = LUNGE_DIST / LUNGE_T * (1.25 - k * 0.5)
			step_dir = lunge_dir
			if k > 0.5 and not snapped:
				snapped = true
				rig.snap = 1.0
				Sfx.play("bug_chomp", 0.15, -4.0)
			if not bit and k > 0.35 and dist < radius + player.hit_radius + 0.3 and player.take_hit(global_position):
				bit = true
				player.velocity += lunge_dir * 6.0
				FX.sparks(player.global_position + Vector3(0, 0.6, 0), 8, [Color.WHITE, Color("ffd060")], 6.0, 0.25, -12.0, 0.06)
				Main.inst.shake(0.15)
			if st_t >= LUNGE_T:
				pose.position.y = 0.0
				rig.air = 0.0
				rig._kick_squash(0.9)
				FX.puffs(global_position + Vector3(0, 0.05, 0), 2, DIRT, 0.3, 0.3, 0.4)
				for i in 2:
					var p: Node3D = drip_pts[randi() % drip_pts.size()]
					drip(p.global_position, Main.gy(p.global_position), 1.25)
				if near_player(10.0):
					Sfx.play("land", 0.2, -14.0)
				rig.chew = 1.0 if bit else 0.4
				licked = false
				_go(C.RECOVER, RECOVER_T)
		C.RECOVER:
			turn_rate = _face(dir, dt, 5.0)
			rig.lunge = move_toward(rig.lunge, 0.0, dt * 4.0)
			cm.emission_energy_multiplier = move_toward(cm.emission_energy_multiplier, 0.0, dt * 10.0)
			if st_t > 0.4 and not licked:
				licked = true
				rig.lick = 1.0
			if st_t >= st_len:
				attack_cd = randf_range(1.3, 2.3)
				_go(C.CHASE if active else C.IDLE, randf_range(0.5, 1.0))
		C.SCARED:
			move_dir = (-dir).rotated(Vector3.UP, sin(t * 6.0) * 0.5)
			want = SCARED_SPEED
			turn_rate = _face(move_dir, dt, 14.0)
			rig.alarm = maxf(rig.alarm, 0.35)
			if st_t >= st_len:
				_go(C.PAUSE, randf_range(0.3, 0.6))
	cur_speed = move_toward(cur_speed, want, dt * (14.0 if absf(want) > absf(cur_speed) else 10.0))
	if state == C.LUNGE:
		cur_speed = want
	global_position += (step_dir * cur_speed + _separation(1.2) * 2.0 + knock) * dt
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = Main.inst.push_out(global_position, radius)


func _notice() -> void:
	if noticed:
		_go(C.CHASE, randf_range(0.5, 1.0))
		return
	noticed = true
	rig.startle = 1.0
	cur_speed = 0.0
	_go(C.NOTICE, NOTICE_T)
	if near_player(14.0):
		Sfx.play("bug_squeak", 0.15, -8.0)


func _windup(dir: Vector3) -> void:
	_go(C.WINDUP, WINDUP_T)
	_warn(global_position + dir * 0.7, "melee")
	cur_speed = 0.0
	Sfx.play("charge", 0.15, -14.0)
	if near_player(10.0):
		Sfx.play("bug_hiss", 0.3, -16.0)


func _go(s: int, dur: float) -> void:
	state = s
	st_t = 0.0
	st_len = dur


## 공중 도약 중에는 피격 경직으로 끊지 않는다 (덥석이 허공에서 멈추면 어색하다)
func _can_hurt() -> bool:
	return state != C.LUNGE


## 덥석(패링 공격)은 준비동작부터 도약이 끝날 때까지 맞아도 끊기지 않는다
func parry_committed() -> bool:
	return state == C.WINDUP or state == C.LUNGE


func _charge_glow_k() -> float:
	return maxf(st_t / WINDUP_T, 0.01) if state == C.WINDUP else 0.0


func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	super.take_hit(dmg, dir, pos, source)
	if alive and rig:
		rig.alarm = 1.0
		for i in 2:
			var p: Node3D = drip_pts[randi() % drip_pts.size()]
			drip(p.global_position, Main.gy(p.global_position), 1.25, dir * 1.5)


## 피격·패링 경직: 하던 공격을 끊는다. 그냥 맞았으면 가끔 겁먹고 도망친다.
func _on_stagger() -> void:
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.0
	if pose:
		pose.position.y = 0.0
	if rig:
		rig.windup = 0.0
		rig.lunge = 0.0
		rig.air = 0.0
		rig.alarm = 1.0
	cur_speed = 0.0
	attack_cd = maxf(attack_cd, 0.8)
	noticed = true
	if stagger_t <= 0.0 and randf() < 0.45:
		_go(C.SCARED, randf_range(0.45, 0.8))
		if near_player(12.0):
			Sfx.play("bug_squeak", 0.25, -10.0)
	else:
		_go(C.PAUSE, randf_range(0.3, 0.5))

class_name Turret
extends Enemy
## 고정 포탑. 제자리에 앉아 포탑 머리를 느린 속도로 돌려 플레이어를 따라가고,
## 조준이 맞고 시야가 트이면 포신을 돌리며 조준선으로 예고한 뒤 위아래 두 포신을 번갈아 연사한다.
## 선회가 느려서 옆으로 돌아 들어가거나 엄폐물 뒤에 숨으면 피할 수 있다.
## 벽가·구석의 바닥 해치에 숨어 있다가, 경고등 → 덮개 열림 → 승강판으로 솟아올라 포신을 펴며 등장한다.

enum S { TRACK, WINDUP, FIRE }

const TURN := 2.3               # 머리 선회 속도 (rad/s)
const FIRE_CONE := 0.3          # 이 각도 안으로 조준이 맞아야 발사 준비
const RANGE := 17.0
const WINDUP := 0.6
const SHOTS := 8
const SHOT_GAP := 0.11
const SHOT_SPEED := 9.5
const RECOIL := 0.16
# 등장: 경고 → 덮개 열림 → 상승. 상승 전에는 기체 전체가 바닥 아래에 있다.
const WARN_T := 0.6
const OPEN_T := 0.25
const RISE_T := 0.75
const RISE_FROM := -1.15
const FOLD := 0.9               # 올라오는 동안 포신을 위로 접어 둔 각도
const PLATE := 0.03              # 승강판 윗면 높이 (받침이 그 위에 선다)

var state := S.TRACK
var windup_t := 0.0
var shots_left := 0
var shot_timer := 0.0
var barrel_i := 0
var spin := 0.0
var recoil: Array[float] = [0.0, 0.0]
var sight_len := 0.0
## 받침 정면 방향 (벽 반대쪽). 음수면 무작위.
var face_yaw := -1.0
var hatch: TurretHatch
var fold := 0.0
var _opened := false
var _rising := false


func _ready() -> void:
	super()
	hp = 9
	radius = 0.75
	fire_timer = randf_range(1.0, 1.8)
	slice_size = Vector3(0.62, 0.8, 0.56)
	slice_color = Pal.T_BLUE
	# 받침은 벽을 등지고 방 안쪽을 본다
	rotation.y = face_yaw if face_yaw >= 0.0 else randf() * TAU
	(j.body as Node3D).position.y = RISE_FROM
	(j.head as Node3D).rotation.x = FOLD
	shadow.visible = false   # 승강판 위에 서므로 원형 그림자는 쓰지 않는다


func _build(v: Node3D) -> Dictionary:
	return Build.turret(v)


## 바닥 해치에서 솟아오르는 등장. 이 동안은 landed 가 꺼져 있어 맞지 않는다.
func _update_entry(dt: float) -> void:
	var body: Node3D = j.body
	var gp := Vector3(global_position.x, 0, global_position.z)
	if hatch == null:
		hatch = TurretHatch.new()
		FX.root.add_child(hatch)
		hatch.global_position = gp
		Sfx.play("spawn", 0.1, -6.0)
	drop_t += dt
	var tt := drop_t
	if tt < WARN_T:
		hatch.warn(tt / WARN_T, dt)
		fx_t -= dt
		if fx_t <= 0.0:
			# 덮개 이음새에서 불똥과 김이 샌다
			fx_t = lerpf(0.16, 0.06, tt / WARN_T)
			var seam := gp + Vector3(randf_range(-0.05, 0.05), 0.08, randf_range(-1.0, 1.0) * TurretHatch.HALF)
			FX.sparks(seam, 3, [Color("fff0a0"), TurretHatch.WARN], 3.0, 0.25, -10.0, 0.05)
		return
	tt -= WARN_T
	if tt < OPEN_T:
		if not _opened:
			_opened = true
			Sfx.play("hatch", 0.05, -1.0)
			Main.inst.shake(0.12)
			FX.puffs(gp + Vector3(0, 0.1, 0), 7, [Color("8a88a0"), Color("6a6680"), Color("403c50"), Color("2c2a3a")], TurretHatch.HALF, 0.5, 0.6)
		hatch.open(1.0 - pow(1.0 - tt / OPEN_T, 2.0))
		return
	tt -= OPEN_T
	if not _rising:
		_rising = true
		hatch.open(1.0)
		Sfx.play("hrise", 0.03, -3.0)
	var k := clampf(tt / RISE_T, 0.0, 1.0)
	body.position.y = lerpf(RISE_FROM, 1.0 + PLATE, 1.0 - pow(1.0 - k, 3.0))
	hatch.lift(body.position.y - 1.0)
	if k >= 1.0:
		landed = true
		hatch.lock()
		fold = FOLD
		punch = 0.7
		FX.land_dust(gp)
		FX.puffs(gp, 5, [Color("8a88a0"), Color("6a6680"), Color("403c50"), Color("2c2a3a")], TurretHatch.HALF * 0.9, 0.35, 0.5)
		Main.inst.shake(0.15)
		Sfx.play("land", 0.05, -2.0)

func _ai(dt: float) -> void:
	var body: Node3D = j.body
	var head: Node3D = j.head
	var player := Main.inst.player
	var to_p := player.global_position - global_position
	to_p.y = 0
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var active := player.alive and Main.inst.state == Main.State.PLAY

	# 포탑은 밀려나지 않는다 (피격 반동은 흔들림으로만)
	knock = Vector3.ZERO

	# 머리 선회: 준비 중에는 거의 멈추고, 연사 중에는 느리게 따라간다
	var rate := TURN
	match state:
		S.WINDUP: rate = TURN * 0.25
		S.FIRE: rate = TURN * 0.4
	var aim_err := 0.0
	if player.alive:
		var target_yaw := atan2(-dir.x, -dir.z) - rotation.y
		var diff := wrapf(target_yaw - head.rotation.y, -PI, PI)
		head.rotation.y += clampf(diff, -rate * dt, rate * dt)
		aim_err = absf(diff)

	match state:
		S.TRACK:
			if active:
				fire_timer -= dt
				if fire_timer <= 0.0 and fold <= 0.0 and aim_err < FIRE_CONE and dist < RANGE and _clear_shot(dist):
					_begin_windup()
		S.WINDUP:
			windup_t += dt
			var k := clampf(windup_t / WINDUP, 0.0, 1.0)
			spin = lerpf(spin, 28.0, 1.0 - exp(-5.0 * dt))
			_windup_look(k)
			if not active:
				_end_attack(1.0)
			elif k >= 1.0:
				state = S.FIRE
				shots_left = SHOTS
				shot_timer = 0.0
		S.FIRE:
			spin = 34.0
			_update_sight(0.0)
			shot_timer -= dt
			if not active:
				_end_attack(1.2)
			elif shot_timer <= 0.0:
				shot_timer = SHOT_GAP
				shots_left -= 1
				_fire_barrel(barrel_i)
				barrel_i = 1 - barrel_i
				if shots_left <= 0:
					_end_attack(randf_range(1.5, 2.3))

	# 포신 회전·반동
	if state == S.TRACK:
		spin = move_toward(spin, 0.0, 40.0 * dt)
	for i in 2:
		var bp := j.barrels[i] as Node3D
		recoil[i] = move_toward(recoil[i], 0.0, dt * 6.0)
		bp.position.z = -0.28 + recoil[i] * RECOIL
		bp.rotation.z += spin * dt * (1.0 if i == 0 else -1.0)

	# 몸체: 바닥에 붙어 있고, 맞거나 쏘면 스프링처럼 흔들린다
	wob_v += (-wob * 260.0 - wob_v * 12.0) * dt
	wob += wob_v * dt
	body.position.y = 1.0 + PLATE
	body.rotation.x = wob.x * 0.35
	body.rotation.z = wob.y * 0.35
	# 올라온 직후 접어 둔 포신을 내려 수평으로 편다
	if fold > 0.0:
		fold = move_toward(fold, 0.0, dt * 3.2)
		if fold <= 0.0:
			wob_v.x -= 6.0
			Sfx.play("hatch", 0.1, -12.0)
	head.rotation.x = wob.x * 0.4 + fold


## 포구에서 플레이어까지 벽에 막히지 않았는지
func _clear_shot(dist: float) -> bool:
	var from := global_position
	var d := 0.8
	var fwd := -(j.head as Node3D).global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	while d < dist:
		if Main.inst.is_blocked(from + fwd * d):
			return false
		d += 0.4
	return true


func _begin_windup() -> void:
	state = S.WINDUP
	windup_t = 0.0
	(j.sight as MeshInstance3D).visible = true
	Sfx.play("twind", 0.05, -5.0)


## 발사 준비: 포신이 돌기 시작하고 포구·센서가 달아오르며, 포신 앞으로 붉은 조준선이 뻗어 깜빡인다
func _windup_look(k: float) -> void:
	var cm: StandardMaterial3D = j.core_mat
	cm.emission_energy_multiplier = 0.6 + k * 4.0
	(j.core as MeshInstance3D).scale = Vector3.ONE * (1.0 + k * 0.5)
	for b in j.bores:
		(b as MeshInstance3D).set_instance_shader_parameter("tint", Color("5a1418").lerp(Color("ffb040"), k))
		(b as MeshInstance3D).set_instance_shader_parameter("energy", 1.0 + k * 2.0)
	wob_v.x += 10.0 * k * get_physics_process_delta_time()
	_update_sight(k)


func _update_sight(k: float) -> void:
	var sight: MeshInstance3D = j.sight
	var head: Node3D = j.head
	# 가장 가까운 벽까지, 단 플레이어를 조금 지난 곳에서 끊는다 (화면을 가로지르지 않게)
	var fwd := -head.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var from := (j.muzzles[0] as Node3D).global_position
	var p := Main.inst.player.global_position
	var max_len := minf(RANGE, Vector2(p.x - from.x, p.z - from.z).length() + 2.0)
	sight_len = 0.0
	while sight_len < max_len:
		sight_len += 0.3
		if Main.inst.is_blocked(from + fwd * sight_len):
			break
	sight.scale = Vector3(1, 1, sight_len)
	sight.position = Vector3(-0.26, 0.4, -1.24 - sight_len * 0.5)
	var on := state == S.FIRE or k < 0.6 or fmod(windup_t, 0.08) < 0.05
	sight.set_instance_shader_parameter("energy", (0.8 + k * 1.4) if on else 0.25)


func _fire_barrel(i: int) -> void:
	var head: Node3D = j.head
	var muzzle := j.muzzles[i] as Node3D
	var origin := muzzle.global_position
	var fwd := -head.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized().rotated(Vector3.UP, randf_range(-0.035, 0.035))
	Main.inst.add_bullet(Bullet.make_enemy(origin, fwd, SHOT_SPEED))
	recoil[i] = 1.0
	GunFX.muzzle(origin, fwd, 1.25)
	wob_v.x -= 5.0
	Sfx.play("tshot", 0.1, -5.0)
	# 탄피: 오른쪽 위로 튀어나와 바닥에서 튕긴다
	var side := head.global_basis.x
	side.y = 0
	GunFX.eject(head.global_position + Vector3(0, 0.5, 0) + side.normalized() * 0.3, side.normalized(), fwd, 1.5)


func _end_attack(cd: float) -> void:
	state = S.TRACK
	fire_timer = cd
	(j.sight as MeshInstance3D).visible = false
	(j.core as MeshInstance3D).scale = Vector3.ONE
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.6
	for b in j.bores:
		(b as MeshInstance3D).set_instance_shader_parameter("tint", Color("5a1418"))
		(b as MeshInstance3D).set_instance_shader_parameter("energy", 1.0)


func die(dir := Vector3.ZERO, source := "bullet") -> void:
	if alive:
		(j.sight as MeshInstance3D).visible = false
		state = S.TRACK
		if is_instance_valid(hatch):
			hatch.shut_down()
	super(dir, source)


## 바닥에 박힌 기체라 튕겨 날아가거나 쓰러지는 연출은 쓰지 않는다
func _pick_death(source: String) -> int:
	if source == "slash" or source == "phantom":
		return Death.SLICED
	return Death.OVERLOAD if randf() < (0.6 if source == "laser" else 0.4) else Death.BURST


## 절단: 받침은 제자리에 남기고 포탑 머리만 두 동강 낸다
func _begin_slice() -> void:
	var base: Node3D = j.base
	var xf := base.global_transform
	base.get_parent().remove_child(base)
	add_child(base)
	base.global_transform = xf
	super()


func _update_slice(dt: float) -> void:
	super(dt)
	if is_queued_for_deletion() and is_instance_valid(j.base):
		var base: Node3D = j.base
		Debris.burst(base, base.global_position + Vector3(0, 0.2, 0), 2.0, 2.5)

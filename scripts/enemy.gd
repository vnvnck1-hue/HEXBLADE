class_name Enemy
extends Node3D
## 흰색 몸체·붉은 코어 적. 낙하 등장 → 거리 유지하며 선회 → 코어가 부풀면 발사.

enum Pattern { AIMED_BURST, FAN, RING }
## 죽음 연출: 즉시 폭발 / 과부하 팽창 후 폭발 / 튕겨 날아가 추락 폭발 / 전원 차단 후 쓰러져 붕괴
enum Death { BURST, OVERLOAD, SPINOUT, SHUTDOWN, SLICED }

var hp := 4
var alive := true
var landed := false
var radius := 0.62
var pattern := Pattern.AIMED_BURST
var j: Dictionary
var t := 0.0
var drop_t := 0.0
var fire_timer := 2.0
var burst_left := 0
var burst_timer := 0.0
var strafe := 1.0
var strafe_timer := 2.0
var desired := 7.0
var knock := Vector3.ZERO
var flash_t := 0.0
var punch := 0.0
var shadow: MeshInstance3D
var wob := Vector2.ZERO
var wob_v := Vector2.ZERO
var dying := false
var death := Death.BURST
var death_t := 0.0
var death_dir := Vector3.ZERO
var d_vel := Vector3.ZERO
var d_spin := Vector3.ZERO
var fx_t := 0.0
var forced_death := -1
var slash_yaw := 0.0
var halves: Array = []        # [node, vel, spin, glow_mesh]
var cut_frame: Basis
var visual: Node3D
var locked := false
var kill_source := ""
## 보스(와 그 피격 부위): 궁극기 미사일이 한 발이 아니라 남은 미사일을 모두 받는다 (player.gd 가 읽음)
var is_boss := false
## 판정만 빌려 쓰는 소품 (가스통 등): 처치 수·방 진행·소환 상한에 세지 않는다
var prop := false
var lock_marker: Node3D            # 락온 표식 (presentation/lock_marker.gd)
## 광선검 절단 조각의 크기(폭, 높이, 깊이)와 색. 몸체가 다른 기체는 덮어쓴다.
var slice_size := Vector3(0.78, 0.74, 0.78)
var slice_color := Pal.E_WHITE
## 패링: 경직 남은 시간 · 금빛 예고 발광 · 다음 공격이 패링 탄인가
var stagger_t := 0.0
var stagger_total := 1.0
var stun_halo: Node3D
var warn_glow := false
var orb_next := false
var orb_cd := 0.0
## 패링 공격 준비동작 진행도 (0~1). 몸체를 납작하게 웅크리는 데 쓴다
var windup_k := 0.0
## 패링 공격 알림 순간의 금빛 전신 섬광 남은 시간
var glow_t := 0.0
## 거리 벌리기 (뒷걸음질 · 이탈 대시 · 광선검 회피 반격). 확률은 기체마다 _ready 에서 정한다.
var evade := Evade.new()
## 피격 경직: 맞으면 하던 공격을 끊고 HURT_TIME 동안 맞은 방향으로 젖혀졌다 튕겨 돌아온다 (그동안 행동하지 않는다)
var hurt_t := 0.0
var hurt_age := 0.0
var hurt_axis := Vector3.RIGHT   # 몸체를 젖히는 회전축 (자기 좌표)
var hurt_amp := 0.4
const GLOW_TIME := 0.12
const HURT_TIME := 0.3
## 패링 탄을 쏠 확률 (기본 드론만 쓴다). 확인 모드에서는 1.
var orb_chance := 0.45
## 확인 모드: 패링 탄만 쏜다
var orb_only := false
## 체력바: 첫 프레임에 체력 배율을 적용하며 만든다. 보스처럼 자체 체력 게이지가 있는 기체는 이 경로를 타지 않는다.
var max_hp := 0
var hp_bar: MeshInstance3D
var hp_bar_y := 2.05          # 바 높이 (기체 원점 기준)
var hp_bar_w := 1.1
var _bar_chip := 1.0          # 깎인 뒤 천천히 따라 내려오는 잔상 비율
var _bar_hit := 0.0
var _bar_sent := Vector4(-1, -1, -1, -1)   # 마지막으로 셰이더에 보낸 체력바 값

## 일반 적 체력 배율 (기체마다 정한 기본 체력에 곱한다)
const HP_SCALE := 2.5
const DROP_TIME := 0.45

static var _bar_mat: ShaderMaterial
static var _bar_mesh: QuadMesh
static var _live: Array = []
static var _live_key := Vector2i(-1, -1)


## 지금 프레임의 "enemies" 그룹. 총알·적 분리처럼 물리 틱마다 여러 번 도는 곳에서 그룹 조회(배열 생성)를 한 번만 하게 한다.
## 같은 프레임 안에서 지워진 적이 섞일 수 있으니 쓰는 쪽에서 is_instance_valid 로 거른다.
static func live(tree: SceneTree) -> Array:
	var key := Vector2i(Engine.get_process_frames(), Engine.get_physics_frames())
	if key != _live_key:
		_live_key = key
		_live = tree.get_nodes_in_group("enemies")
	return _live
const TELEGRAPH := 0.5
const ORB_CD := 3.2
## 패링 탄 준비동작 길이: 크게 뒤로 젖혀 웅크리며 코어를 부풀린다. 끝나는 순간 알림과 함께 발사.
const ORB_WINDUP := 0.8


func _ready() -> void:
	add_to_group("enemies")
	visual = Node3D.new()
	add_child(visual)
	j = _build(visual)
	shadow = FX.blob_shadow(self, 2.1, 0.7)
	t = randf() * 10.0
	strafe = 1.0 if randf() < 0.5 else -1.0
	fire_timer = randf_range(1.2, 2.0)
	match pattern:
		Pattern.AIMED_BURST: desired = 6.0
		Pattern.FAN: desired = 5.0
		Pattern.RING: desired = 4.2
	j.body.position.y = 7.0
	# 기본형 드론: 주로 뒷걸음질, 가끔 이탈 대시, 광선검은 가끔 피한다
	evade.e = self
	evade.chance = 0.4
	evade.back_w = 0.75


func _physics_process(dt: float) -> void:
	if dying:
		_update_death(dt)
		return
	if not alive:
		return
	if max_hp == 0:
		_init_hp()
	t += dt
	_update_hp_bar(dt)
	var body: Node3D = j.body
	if not landed:
		_update_entry(dt)
		return
	if stagger_t > 0.0:
		_update_stagger(dt)
	elif hurt_t > 0.0:
		_update_hurt(dt)
	else:
		_ai(dt)
		evade.update(dt)
	# 피격 반응
	punch = move_toward(punch, 0.0, dt * 6.0)
	body.scale = Vector3(1.0 + punch * 0.22, 1.0 - punch * 0.16, 1.0 + punch * 0.22)
	if windup_k > 0.0:
		# 준비동작: 스프링처럼 납작하게 눌러 힘을 모은다
		var sq := smoothstep(0.05, 0.8, windup_k)
		body.scale *= Vector3(1.0 + sq * 0.3, 1.0 - sq * 0.36, 1.0 + sq * 0.3)
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0:
			_set_flash(false)
	if glow_t > 0.0:
		glow_t -= dt
		if glow_t <= 0.0:
			_set_flash(flash_t > 0.0)


## 등장 연출: 기본은 하늘에서 떨어져 착지한다. 끝나면 landed 를 켠다 (그 전에는 맞지 않는다).
func _update_entry(dt: float) -> void:
	var body: Node3D = j.body
	drop_t += dt
	var k: float = clamp(drop_t / DROP_TIME, 0.0, 1.0)
	body.position.y = lerp(7.0, 1.0, k * k)
	shadow.scale = Vector3.ONE * lerp(0.4, 1.0, k)
	if k >= 1.0:
		landed = true
		punch = 1.0
		FX.land_dust(global_position)
		Main.inst.shake(0.12)


## 몸체 메시 조립. 하위 기체는 body / core / core_mat / cube 를 가진 딕셔너리를 돌려준다.
func _build(v: Node3D) -> Dictionary:
	return Build.drone(v)


## 착지 후 매 프레임 이동·조준·공격
func _ai(dt: float) -> void:
	var body: Node3D = j.body
	var player := Main.inst.player
	var to_p := player.global_position - global_position
	to_p.y = 0
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)

	# 이동: 거리 유지 + 선회 + 서로 밀어내기
	strafe_timer -= dt
	if strafe_timer <= 0.0:
		strafe_timer = randf_range(1.5, 3.0)
		strafe = -strafe
	var move := Vector3.ZERO
	if dist > desired + 0.8:
		move += dir
	elif dist < desired - 0.8:
		move -= dir
	move += Vector3(-dir.z, 0, dir.x) * strafe * 0.6
	for o in live(get_tree()):
		if o == self or not is_instance_valid(o):
			continue
		var d: Vector3 = global_position - (o as Node3D).global_position
		d.y = 0
		var l := d.length()
		if l < 2.2 and l > 0.001:
			move += d / l * (2.2 - l)
	var winding := orb_next and fire_timer <= ORB_WINDUP
	var speed := 2.0 if burst_left == 0 and fire_timer > TELEGRAPH and not winding else 0.6
	if winding:
		# 준비동작 초반에 크게 물러서며 뒤로 빠진다
		move = -dir * (1.0 - windup_k)
		speed = 2.6
	global_position += (move.limit_length(1.0) * speed + knock) * dt
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = Main.inst.push_out(global_position, radius)

	# 방향: 플레이어를 바라본다
	if player.alive:
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-6.0 * dt))

	# 공중 부유
	body.position.y = 1.0 + sin(t * 2.4) * 0.1
	wob_v += (-wob * 220.0 - wob_v * 11.0) * dt
	wob += wob_v * dt

	# 발사 예고: 코어 팽창·밝아짐
	var core: MeshInstance3D = j.core
	var cm: StandardMaterial3D = j.core_mat
	orb_cd -= dt
	if player.alive and not player.hidden and Main.inst.state == Main.State.PLAY:
		var was := fire_timer
		fire_timer -= dt
		# 준비동작 길이만큼 앞서 다음 공격을 정한다: 패링 탄이면 과장된 준비동작에 들어간다 (알림은 준비동작 끝에)
		if was > ORB_WINDUP and fire_timer <= ORB_WINDUP:
			orb_next = orb_cd <= 0.0 and randf() < orb_chance and get_tree().get_nodes_in_group("parry_orbs").size() < 2 or orb_only
	if orb_next and fire_timer <= ORB_WINDUP:
		_orb_windup(dt, clampf(1.0 - fire_timer / ORB_WINDUP, 0.0, 1.0))
	else:
		windup_k = 0.0
		var tele: float = clamp(1.0 - fire_timer / TELEGRAPH, 0.0, 1.0)
		core.scale = Vector3.ONE * (1.0 + tele * 0.6 + sin(t * 40.0) * 0.06 * tele)
		# 예고 중에는 뒤로 젖혀 힘을 모은다
		body.rotation.x = wob.x + tele * 0.22
		body.rotation.z = sin(t * 1.7) * 0.06 + wob.y + sin(t * 45.0) * 0.03 * tele
		cm.emission_energy_multiplier = 0.6 + tele * 3.0
	if fire_timer <= 0.0:
		if orb_next:
			_shoot_orb()
		else:
			_begin_attack()
	if burst_left > 0:
		burst_timer -= dt
		if burst_timer <= 0.0:
			burst_timer = 0.13
			burst_left -= 1
			_shoot([0.0], 7.5)


# ── 거리 벌리기 (Evade 가 부른다) ───────────────────────

## 지금 거리 벌리기를 해도 되는가: 공격 준비·연사 중이 아닐 때만
func _can_evade() -> bool:
	return not orb_next and burst_left == 0 and fire_timer > TELEGRAPH


func evading() -> bool:
	return evade.active()


func _face_player() -> void:
	var d := Main.inst.player.global_position - global_position
	d.y = 0
	if d.length() > 0.05:
		rotation.y = atan2(-d.x, -d.z)


## 이탈 대시 뒤 무작위 공격: 조준 연사 · 부채꼴 · 원형탄 중 하나
func _evade_attack() -> void:
	_face_player()
	var keep := pattern
	pattern = [Pattern.AIMED_BURST, Pattern.FAN, Pattern.RING][randi() % 3]
	_begin_attack()
	pattern = keep



func _begin_attack() -> void:
	fire_timer = randf_range(1.9, 2.8)
	match pattern:
		Pattern.AIMED_BURST:
			burst_left = 3
			burst_timer = 0.0
		Pattern.FAN:
			_shoot([-0.5, -0.25, 0.0, 0.25, 0.5], 6.0)
		Pattern.RING:
			var a: Array[float] = []
			var off := randf() * 0.3
			for i in 12:
				a.append(TAU * i / 12.0 + off)
			_shoot(a, 5.0, true)


func _shoot(angles: Array, speed: float, big := false) -> void:
	var core: MeshInstance3D = j.core
	var origin := core.global_position
	origin.y = global_position.y + 0.95
	var fwd := -global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	for a in angles:
		var d := fwd.rotated(Vector3.UP, a)
		Main.inst.add_bullet(Bullet.make_enemy(origin + d * 0.2, d, speed, big))
	FX.flash(origin, Color("ff8a40"), 0.55, 0.07)
	wob_v.x -= 7.0
	Sfx.play("eshot", 0.08, -4.0)
	punch = 0.5


## 패링 탄 준비동작 (k: 0→1). 몸을 크게 뒤로 젖히고 들어 올리며 웅크리고, 코어가 금빛으로 한껏 부푼다.
## 마지막 구간은 그 자세로 부들부들 떨며 버틴다. 알림은 이 동작이 끝나고 발사할 때 뜬다.
func _orb_windup(dt: float, k: float) -> void:
	windup_k = k
	var body: Node3D = j.body
	var core: MeshInstance3D = j.core
	var cm: StandardMaterial3D = j.core_mat
	var rear := smoothstep(0.0, 0.75, k)
	var shiver := smoothstep(0.55, 1.0, k)
	body.rotation.x = wob.x + rear * 1.0 + sin(t * 70.0) * 0.05 * shiver
	body.rotation.z = wob.y + sin(t * 63.0) * 0.1 * shiver
	body.position.y += rear * 0.55 + sin(t * 80.0) * 0.04 * shiver
	core.scale = Vector3.ONE * (1.0 + rear * 0.9 + sin(t * 60.0) * 0.12 * shiver)
	cm.albedo_color = Pal.E_RED.lerp(ParryFX.GOLD, rear)
	cm.emission = Pal.E_RED.lerp(ParryFX.GOLD, rear)
	cm.emission_energy_multiplier = 0.6 + rear * 2.2
	# 코어로 빨려 드는 금빛 불티: 끝으로 갈수록 잦아진다
	fx_t -= dt
	if fx_t <= 0.0:
		fx_t = lerpf(0.09, 0.025, k)
		var off := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.6), randf_range(-1.0, 1.0)) * lerpf(1.1, 0.6, k)
		FX.flash(core.global_position + off, ParryFX.GOLD, 0.18, 0.1)


## 패링 탄 발사: 준비동작을 마친 순간 알림(십자 별빛)과 함께 금빛 에너지 구체를 플레이어에게 쏜다
func _shoot_orb() -> void:
	orb_next = false
	windup_k = 0.0
	orb_cd = ORB_CD
	fire_timer = randf_range(2.2, 3.0)
	_end_warn()
	var core: MeshInstance3D = j.core
	var cm: StandardMaterial3D = j.core_mat
	cm.albedo_color = Pal.E_RED
	cm.emission = Pal.E_RED
	var origin := core.global_position
	origin.y = global_position.y + 0.95
	var to := Main.inst.player.global_position - global_position
	to.y = 0
	var d := to.normalized() if to.length() > 0.01 else -global_basis.z
	Main.inst.bullets.add_child(ParryOrb.make(origin + d * 0.4, d, self))
	ParryFX.warn(origin, "ranged")
	parry_flash()
	FX.flash(origin, ParryFX.HOT, 0.9, 0.08)
	# 젖혔던 몸을 앞으로 내던지듯 튕긴다
	wob_v.x -= 30.0
	punch = 1.0
	Sfx.play("eshot", 0.04, 0.0)


## 패링 공격 예고: 몸체에 금빛을 덮고 별 섬광을 터뜨린다
func _warn(at: Vector3, kind := "ranged") -> void:
	warn_glow = true
	ParryFX.warn(at, kind)
	parry_flash()


## 패링 공격 알림: 기체 전체가 아주 잠깐 금백색으로 번쩍인다
func parry_flash() -> void:
	glow_t = GLOW_TIME
	punch = maxf(punch, 0.7)
	_set_flash(flash_t > 0.0)


func _end_warn() -> void:
	if warn_glow:
		warn_glow = false
		_set_flash(flash_t > 0.0)


## 근접 패링을 당해 경직: 크게 튕겨 나가 비틀거리고, 그동안 행동하지 못하며 받는 피해가 두 배다
func stagger(dir: Vector3, dur: float) -> void:
	if not alive:
		return
	stagger_t = dur
	stagger_total = dur
	burst_left = 0
	orb_next = false
	windup_k = 0.0
	_end_warn()
	_on_stagger()
	var d := Vector3(dir.x, 0, dir.z).normalized()
	knock = d * 16.0
	var l := global_basis.inverse() * d
	wob_v += Vector2(l.z, -l.x) * 30.0
	punch = 1.0
	flash_t = 0.1
	_set_flash(true)
	if not is_instance_valid(stun_halo):
		stun_halo = ParryFX.stun_halo(visual)
		stun_halo.position = Vector3(0, 1.85, 0)
	FX.sparks((j.body as Node3D).global_position, 26, [Color.WHITE, ParryFX.HOT, ParryFX.GOLD], 9.0, 0.45, -12.0, 0.08)
	Sfx.play("clank", 0.05, 2.0)


## 하위 기체가 경직될 때 진행 중이던 공격을 정리한다
func _on_stagger() -> void:
	pass


func _update_stagger(dt: float) -> void:
	stagger_t -= dt
	var body: Node3D = j.body
	var k := clampf(stagger_t / stagger_total, 0.0, 1.0)
	global_position += knock * dt
	knock = knock.move_toward(Vector3.ZERO, 26.0 * dt)
	global_position = Main.inst.push_out(global_position, radius)
	wob_v += (-wob * 120.0 - wob_v * 6.0) * dt
	wob += wob_v * dt
	# 뒤로 젖혀진 채 어지럽게 흔들린다
	body.position.y = 1.0 - 0.18 * k + sin(t * 7.0) * 0.05
	body.rotation.x = -0.45 * k + wob.x * 0.4
	body.rotation.z = sin(t * 9.0) * 0.35 * k + wob.y * 0.4
	if is_instance_valid(stun_halo):
		stun_halo.rotation.y += dt * 9.0
		stun_halo.scale = Vector3.ONE * (0.6 + 0.4 * minf(1.0, k * 4.0))
	fx_t -= dt
	if fx_t <= 0.0:
		fx_t = randf_range(0.08, 0.16)
		FX.sparks(body.global_position + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3)), 3, [Color.WHITE, ParryFX.GOLD], 4.0, 0.25, -10.0, 0.05)
	if stagger_t <= 0.0:
		stagger_t = 0.0
		if is_instance_valid(stun_halo):
			stun_halo.queue_free()
		stun_halo = null
		body.rotation = Vector3.ZERO
		body.position.y = 1.0


func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if not alive:
		return
	if max_hp == 0:
		_init_hp()
	if stagger_t > 0.0:
		dmg *= 2
	_hit_spark(dmg, dir, pos, source)
	hp -= dmg
	_bar_hit = 1.0
	knock += Vector3(dir.x, 0, dir.z) * (3.0 + dmg)
	var l := global_basis.inverse() * Vector3(dir.x, 0, dir.z)
	wob_v += Vector2(l.z, -l.x) * (8.0 + dmg * 2.0)
	punch = 1.0
	flash_t = 0.06
	_set_flash(true)
	Sfx.play("hit", 0.15, -6.0)
	if hp <= 0:
		die(dir, source)
	else:
		_hurt(dir, dmg)


# ── 피격 경직 ───────────────────────────────────────────

## 피격 섬광 (기본총 예광탄과 같은 납작한 방추 모양). 무거운 공격일수록 크다.
func _hit_spark(dmg: int, dir: Vector3, pos: Vector3, source: String) -> void:
	if not is_inside_tree():
		return
	var c := (j.body as Node3D).global_position
	var at := c
	var flat := Vector3(pos.x - c.x, 0, pos.z - c.z)
	if pos != Vector3.ZERO and flat.length() < 2.5:
		at = c.lerp(Vector3(pos.x, c.y, pos.z), 0.6)
	var k := 1.0
	match source:
		"slash", "phantom": k = 1.8
		"missile": k = 1.5
		"parry": k = 2.0
		"laser": k = 0.8
	HitSpark.spawn(at, dir, maxf(k, 1.0 + dmg * 0.08), self)


## 지금 피격 경직에 들어갈 수 있는가 (하위 기체가 덮어써 공중 도약 등을 뺀다)
func _can_hurt() -> bool:
	return true


## 맞음: 하던 공격을 끊고 맞은 방향으로 젖혀진다. 패링 경직·빠른 회피 이동 중에는 걸리지 않는다.
func _hurt(dir: Vector3, dmg: int) -> void:
	if not landed or not is_inside_tree() or stagger_t > 0.0 or evade.moving() or not _can_hurt():
		return
	evade.cancel()
	_interrupt()
	hurt_t = HURT_TIME
	hurt_age = 0.0
	var l := global_basis.inverse() * Vector3(dir.x, 0, dir.z)
	l.y = 0
	hurt_axis = Vector3.UP.cross(l.normalized()) if l.length() > 0.01 else Vector3.RIGHT
	hurt_amp = clampf(0.38 + dmg * 0.06, 0.38, 0.75)


## 진행 중이던 공격을 끊는다. 경직이 풀린 뒤에도 곧바로 쏘지 않도록 예고부터 다시 시작한다.
func _interrupt() -> void:
	burst_left = 0
	if orb_next:
		orb_next = false
		var cm: StandardMaterial3D = j.core_mat
		cm.albedo_color = Pal.E_RED
		cm.emission = Pal.E_RED
	windup_k = 0.0
	_end_warn()
	fire_timer = maxf(fire_timer, TELEGRAPH + 0.35)
	_on_hurt()


## 하위 기체가 맞았을 때 진행 중이던 공격을 정리한다 (기본은 패링 경직과 같은 정리)
func _on_hurt() -> void:
	_on_stagger()


## 젖힘 곡선: 2프레임 만에 확 젖혀졌다가 스프링처럼 흔들리며 돌아온다
func _hurt_curve() -> float:
	return smoothstep(0.0, 0.035, hurt_age) * exp(-hurt_age * 8.0) * cos(hurt_age * 16.0)


func _update_hurt(dt: float) -> void:
	_hurt_tick(dt)
	global_position += knock * dt
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = Main.inst.push_out(global_position, radius)
	_hurt_pose(j.body)


func _hurt_tick(dt: float) -> void:
	hurt_t -= dt
	hurt_age += dt
	wob_v += (-wob * 220.0 - wob_v * 11.0) * dt
	wob += wob_v * dt


## 몸체를 맞은 방향으로 젖히고 잘게 떤다. 경직이 끝나면 제자리로 돌려놓는다.
func _hurt_pose(body: Node3D) -> void:
	if hurt_t <= 0.0:
		hurt_t = 0.0
		body.position.x = 0.0
		body.position.z = 0.0
		body.rotation = Vector3.ZERO
		return
	var shake := exp(-hurt_age * 14.0) * 0.07
	body.position.x = randf_range(-1.0, 1.0) * shake
	body.position.z = randf_range(-1.0, 1.0) * shake
	body.basis = Basis(hurt_axis, _hurt_curve() * hurt_amp) * Basis.from_euler(Vector3(wob.x * 0.4, randf_range(-1.0, 1.0) * shake, wob.y * 0.4))


func die(dir := Vector3.ZERO, source := "bullet") -> void:
	if not alive:
		return
	alive = false
	dying = true
	death_t = 0.0
	remove_from_group("enemies")
	death_dir = Vector3(dir.x, 0, dir.z)
	if death_dir.length() < 0.01:
		death_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	death_dir = death_dir.normalized()
	kill_source = source
	locked = false
	warn_glow = false
	if is_instance_valid(hp_bar):
		hp_bar.queue_free()
	if is_instance_valid(stun_halo):
		stun_halo.queue_free()
	death = _pick_death(source) if (forced_death < 0 or source == "slash" or source == "phantom") else forced_death
	_set_flash(false)
	Main.inst.on_enemy_killed(self)
	var body: Node3D = j.body
	match death:
		Death.BURST:
			_explode(1.0, 7.0, 6.0, death_dir * 3.0)
		Death.OVERLOAD:
			Sfx.play("overload", 0.05, -2.0)
			FX.flash(body.global_position, Color.WHITE, 1.2, 0.08)
		Death.SPINOUT:
			d_vel = death_dir * 7.5 + Vector3(0, 8.0, 0)
			d_spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(14.0, 22.0)
			FX.flash(body.global_position, Color.WHITE, 1.0, 0.08)
			FX.sparks(body.global_position, 12, [Color.WHITE, Color("ff9a40")], 7.0, 0.35, -10.0, 0.08)
			Sfx.play("roll", 0.1, -2.0)
		Death.SLICED:
			_begin_slice()
		Death.SHUTDOWN:
			var cm: StandardMaterial3D = j.core_mat
			cm.emission_energy_multiplier = 0.0
			cm.albedo_color = Color(0.22, 0.18, 0.24)
			d_vel = death_dir * 2.0
			FX.sparks(body.global_position, 10, [Color("fff0a0"), Color("ffffff")], 5.0, 0.3, -12.0, 0.06)
			Sfx.play("powerdown", 0.05, -2.0)


func _pick_death(source: String) -> int:
	var r := randf()
	match source:
		"laser":
			return Death.OVERLOAD if r < 0.55 else (Death.BURST if r < 0.8 else Death.SHUTDOWN)
		"slash", "phantom":
			return Death.SLICED
		"parry":
			return Death.OVERLOAD if r < 0.5 else Death.BURST
	return [Death.BURST, Death.OVERLOAD, Death.SPINOUT, Death.SHUTDOWN][randi() % 4]


func _update_death(dt: float) -> void:
	death_t += dt
	var body: Node3D = j.body
	var core: MeshInstance3D = j.core
	var cm: StandardMaterial3D = j.core_mat
	fx_t -= dt
	match death:
		Death.SLICED:
			_update_slice(dt)
		Death.OVERLOAD:
			# 부들부들 떨며 부풀고 코어가 폭주하듯 깜빡인 뒤 크게 터진다
			var k := clampf(death_t / 0.5, 0.0, 1.0)
			var jit := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.09 * k
			body.position = Vector3(0, 1.0 + k * 0.35, 0) + jit
			body.rotation = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.08 * k
			body.scale = Vector3.ONE * (1.0 + 0.45 * k * k)
			core.scale = Vector3.ONE * (1.0 + 1.2 * k)
			cm.emission_energy_multiplier = 2.0 + 12.0 * k
			_set_flash(k > 0.25 and fmod(death_t, 0.09) < 0.045)
			if fx_t <= 0.0:
				fx_t = 0.05
				FX.sparks(core.global_position, 3, [Color.WHITE, Pal.E_RED], 6.0, 0.25, -6.0, 0.06)
			if k >= 1.0:
				_set_flash(false)
				Main.inst.shake(0.45)
				Main.inst.hitstop(0.04)
				_explode(1.7, 11.0, 8.0, Vector3.ZERO)
		Death.SPINOUT:
			# 맞은 방향으로 튕겨 날아가 빙글빙글 돌며 연기를 뿜다 바닥에 처박힌다
			d_vel.y -= 24.0 * dt
			global_position += Vector3(d_vel.x, 0, d_vel.z) * dt
			global_position = Main.inst.push_out(global_position, 0.4)
			body.position.y += d_vel.y * dt
			if d_spin.length() > 0.01:
				body.rotate(d_spin.normalized(), d_spin.length() * dt)
			shadow.scale = Vector3.ONE * clampf(1.4 - body.position.y * 0.25, 0.3, 1.0)
			if fx_t <= 0.0:
				fx_t = 0.035
				FX.smoke(body.global_position)
			if (body.position.y <= 0.45 and d_vel.y < 0.0) or death_t > 1.6:
				Main.inst.shake(0.35)
				FX.shockwave(global_position, Color("ff8a50"), 2.6, 0.3)
				_explode(1.15, 8.0, 5.0, Vector3(d_vel.x, 0, d_vel.z) * 0.5)
		Death.SHUTDOWN:
			# 전원이 꺼져 툭 떨어지고, 한 번 튕긴 뒤 옆으로 쓰러져 지직거리다 무너진다
			d_vel.y -= 26.0 * dt
			body.position.y += d_vel.y * dt
			global_position += Vector3(d_vel.x, 0, d_vel.z) * dt
			d_vel.x *= 0.92
			d_vel.z *= 0.92
			if body.position.y < 0.37:
				body.position.y = 0.37
				if d_vel.y < -2.0:
					d_vel.y = -d_vel.y * 0.3
					FX.land_dust(global_position)
					Sfx.play("land", 0.1, -4.0)
				else:
					d_vel.y = 0.0
			body.rotation.z = lerpf(body.rotation.z, 0.42 * signf(death_dir.x + 0.01), 1.0 - exp(-6.0 * dt))
			body.rotation.x = lerpf(body.rotation.x, 0.25, 1.0 - exp(-6.0 * dt))
			shadow.scale = Vector3.ONE * 0.9
			if fx_t <= 0.0:
				fx_t = randf_range(0.08, 0.2)
				FX.sparks(core.global_position, 4, [Color("fff0a0"), Color.WHITE], 4.0, 0.2, -12.0, 0.05)
				cm.emission_energy_multiplier = 2.0 if randf() < 0.3 else 0.0
			if death_t > 1.05:
				FX.puffs(body.global_position, 5, [Color("6a6680"), Color("8a88a0"), Color("403c50"), Color("2c2a3a")], 0.6, 0.6, 0.6)
				FX.shockwave(global_position, Color("8a88a0"), 1.8, 0.25, 0.05)
				Sfx.play("boom", 0.2, -8.0)
				Debris.burst(body, body.global_position + Vector3(0, 0.25, 0), 2.2, 3.0)
				dying = false
				queue_free()


## 광선검 절단: 몸체를 비스듬한 절단면으로 두 조각 낸다
func _begin_slice() -> void:
	var body: Node3D = j.body
	var center := body.global_position
	# 절단면: 휘두른 방향(수평 호)을 따라 약간 기울어진 평면
	var tilt := randf_range(-0.35, 0.35)
	cut_frame = Basis(Vector3.UP, slash_yaw) * Basis(Vector3.FORWARD, tilt)
	var cube_w := slice_size.x
	var cube_d := slice_size.z
	var half_h := slice_size.y * 0.5
	var hot := Color(1.0, 0.97, 0.85)
	for side in [1, -1]:
		var piece := Node3D.new()
		FX.root.add_child(piece)
		piece.global_transform = Transform3D(cut_frame, center)
		var bm := BoxMesh.new()
		bm.size = Vector3(cube_w, half_h, cube_d)
		var box := MeshInstance3D.new()
		box.mesh = bm
		box.material_override = Pal.lit(slice_color)
		box.position = Vector3(0, half_h * 0.5 * side, 0)
		piece.add_child(box)
		# 달아오른 절단면
		var gm := BoxMesh.new()
		gm.size = Vector3(cube_w * 0.96, 0.025, cube_d * 0.96)
		var glow := Pal.flat_mesh(gm, hot, 2.4)
		glow.position = Vector3(0, 0.012 * side, 0)
		piece.add_child(glow)
		if side < 0:
			# 코어는 아래쪽 조각에 붙어 있다
			var core := MeshInstance3D.new()
			core.mesh = (j.core as MeshInstance3D).mesh
			core.material_override = Pal.lit(Color("7a1a30"))
			piece.add_child(core)
			core.global_transform = (j.core as MeshInstance3D).global_transform
		var tangent := cut_frame.x * (1.0 if randf() < 0.5 else -1.0)
		var v := Vector3.ZERO
		var spin := Vector3.ZERO
		if side > 0:
			# 윗조각: 절단면을 따라 미끄러져 떨어진다
			v = tangent * 2.2 + death_dir * 1.6 + Vector3(0, 2.0, 0)
			spin = cut_frame.z * randf_range(2.5, 4.0) * signf(tangent.dot(cut_frame.x))
		else:
			v = -tangent * 0.4 + death_dir * 0.4
			spin = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.8
		halves.append([piece, v, spin, glow, side])
	body.visible = false
	# 절단 순간: 가로로 긋는 섬광 + 불꽃
	var slash_line := BoxMesh.new()
	slash_line.size = Vector3(2.6, 0.04, 0.1)
	var sl := Pal.flat_mesh(slash_line, Color(1.0, 0.8, 0.7), 3.0)
	FX.root.add_child(sl)
	sl.global_transform = Transform3D(cut_frame * Basis(Vector3.UP, PI * 0.5), center)
	var tw := sl.create_tween()
	tw.tween_property(sl, "scale", Vector3(1.4, 0.2, 0.2), 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_callback(sl.queue_free)
	FX.flash(center, Color(1.0, 0.7, 0.6), 1.3, 0.08)
	FX.sparks(center, 22, [Color.WHITE, Color("ffd060"), Color("ff7a30")], 9.0, 0.45, -14.0, 0.07)
	FX.sparks(center, 10, [Pal.BLADE, Color.WHITE], 6.0, 0.3, -6.0, 0.06)
	Sfx.play("slash", 0.0, 2.0)
	Sfx.play("hit", 0.1, 0.0)


func _update_slice(dt: float) -> void:
	var cool := clampf(death_t / 1.0, 0.0, 1.0)
	var glow_c := Color(1.0, 0.97, 0.85).lerp(Color(1.0, 0.45, 0.1), smoothstep(0.0, 0.35, cool)).lerp(Color(0.35, 0.05, 0.05), smoothstep(0.35, 1.0, cool))
	for h in halves:
		var piece := h[0] as Node3D
		var v: Vector3 = h[1]
		var spin: Vector3 = h[2]
		var glow := h[3] as MeshInstance3D
		var side: int = h[4]
		# 처음 0.08초는 잘린 채 그대로 멈춰 있다가 떨어진다 (베인 느낌)
		if death_t > 0.08:
			v.y -= 20.0 * dt
			var pos := piece.global_position + v * dt
			var floor_y := (0.19 if side > 0 else 0.2) + Main.gy(pos)
			if pos.y < floor_y:
				pos.y = floor_y
				if v.y < -2.0:
					v.y = -v.y * 0.25
					FX.land_dust(pos)
				else:
					v.y = 0.0
				v.x *= 0.8
				v.z *= 0.8
				spin *= 0.85
			piece.global_position = pos
			if spin.length() > 0.01:
				piece.rotate(spin.normalized(), spin.length() * dt)
			h[1] = v
			h[2] = spin
		glow.set_instance_shader_parameter("tint", glow_c)
		glow.set_instance_shader_parameter("energy", lerpf(2.6, 1.0, cool))
	# 절단면에서 불똥이 떨어지고 연기가 난다
	if fx_t <= 0.0:
		fx_t = 0.05
		var h0: Array = halves[randi() % halves.size()]
		var pp := (h0[0] as Node3D).global_position
		FX.sparks(pp, 3, [Color("ffd060"), Color("ff6a20")], 2.5, 0.4, -9.0, 0.05)
		if randf() < 0.4:
			FX.smoke(pp + Vector3(0, 0.2, 0))
	if death_t > 1.25:
		for h in halves:
			var piece := h[0] as Node3D
			Debris.burst(piece, piece.global_position + Vector3(0, -0.3, 0), 1.4, 2.0)
			FX.puffs(piece.global_position, 2, [Color("6a6680"), Color("8a88a0"), Color("403c50"), Color("2c2a3a")], 0.3, 0.4, 0.4)
			piece.queue_free()
		halves.clear()
		dying = false
		queue_free()


func _explode(scale_k: float, power: float, lift: float, push: Vector3) -> void:
	var body: Node3D = j.body
	var p := body.global_position
	FX.enemy_explosion(p, scale_k)
	Debris.burst(body, p - Vector3(0, 0.35, 0), power, lift, push)
	Sfx.play("boom", 0.1)
	dying = false
	queue_free()


func _set_flash(on: bool) -> void:
	var rest: Material = Pal.lock_hatch() if locked else (Pal.parry_glow() if warn_glow else null)
	if glow_t > 0.0:
		rest = Pal.parry_flash()
	var m: Material = Pal.flash() if on else rest
	for mi: MeshInstance3D in FX.mesh_parts(j.body as Node3D):
		mi.material_overlay = m


## 궁극기 락온: 몸체 전체에 붉은 빗금을 덮는다
func set_locked(on: bool) -> void:
	if locked == on or not is_instance_valid(j.body):
		return
	locked = on
	_set_flash(flash_t > 0.0)
	if is_instance_valid(lock_marker):
		lock_marker.queue_free()
	lock_marker = null
	if on:
		punch = 0.6
		FX.flash((j.body as Node3D).global_position, Color(1, 0.2, 0.25), 1.1, 0.1)
		lock_marker = LockMarker.attach(self, radius, hp_bar_y)


# ── 체력바 ──────────────────────────────────────────────

func _init_hp() -> void:
	# 확인 모드의 불사(999 이상)는 그대로 둔다
	if hp < 900:
		hp = maxi(1, int(round(hp * HP_SCALE)))
	max_hp = maxi(hp, 1)
	_bar_chip = 1.0
	if _bar_mat == null:
		var sh := Shader.new()
		sh.code = HP_BAR_SHADER % FX.BILLBOARD
		_bar_mat = ShaderMaterial.new()
		_bar_mat.shader = sh
		_bar_mat.render_priority = 10
		_bar_mesh = QuadMesh.new()
	hp_bar = MeshInstance3D.new()
	hp_bar.mesh = _bar_mesh
	hp_bar.material_override = _bar_mat
	hp_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hp_bar.scale = Vector3(hp_bar_w, hp_bar_w * 0.1, 1.0)
	hp_bar.position = Vector3(0, hp_bar_y, 0)
	hp_bar.set_instance_shader_parameter("fill", 1.0)
	hp_bar.set_instance_shader_parameter("chip", 1.0)
	hp_bar.set_instance_shader_parameter("ticks", float(max_hp) / 5.0)
	hp_bar.visible = false
	add_child(hp_bar)


func _update_hp_bar(dt: float) -> void:
	if not is_instance_valid(hp_bar):
		return
	var k := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	# 깎인 부분은 흰 잔상으로 잠깐 남았다가 따라 내려온다
	if _bar_chip > k:
		_bar_chip = move_toward(_bar_chip, k, dt * (0.25 if _bar_hit > 0.6 else 1.6))
	else:
		_bar_chip = k
	_bar_hit = maxf(0.0, _bar_hit - dt * 2.5)
	hp_bar.visible = landed
	# 바뀐 값만 렌더링 서버로 보낸다 (적마다 물리 틱마다 불린다)
	var v := Vector4(k, _bar_chip, _bar_hit, 1.0 if k >= 0.999 else 0.0)
	if v == _bar_sent:
		return
	_bar_sent = v
	hp_bar.set_instance_shader_parameter("fill", v.x)
	hp_bar.set_instance_shader_parameter("chip", v.y)
	hp_bar.set_instance_shader_parameter("hit", v.z)
	hp_bar.set_instance_shader_parameter("full", v.w)


const HP_BAR_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;
instance uniform float fill = 1.0;
instance uniform float chip = 1.0;
instance uniform float hit = 0.0;
instance uniform float full = 1.0;
instance uniform float ticks = 2.0;
void vertex() {
%s
}
void fragment() {
	vec2 uv = UV;
	// 테두리(검정) · 안쪽 칸
	float bx = 0.018, by = 0.18;
	bool inner = uv.x > bx && uv.x < 1.0 - bx && uv.y > by && uv.y < 1.0 - by;
	vec3 col = vec3(0.03, 0.02, 0.05);
	if (inner) {
		float x = (uv.x - bx) / (1.0 - bx * 2.0);
		float y = (uv.y - by) / (1.0 - by * 2.0);
		col = vec3(0.16, 0.05, 0.08);
		if (x < chip) col = vec3(1.0, 0.92, 0.8);
		if (x < fill) {
			// 체력이 줄수록 붉은색 → 짙은 진홍, 위쪽에 밝은 줄
			vec3 hi = mix(vec3(1.0, 0.28, 0.2), vec3(1.0, 0.55, 0.25), fill);
			col = mix(hi, hi * 0.55, smoothstep(0.35, 1.0, y));
			col += vec3(0.35) * (1.0 - smoothstep(0.0, 0.3, y));
			col += vec3(1.0) * hit * 0.6;
		}
		// 5칸 단위 눈금
		float tk = fract(x * ticks);
		float tw = 0.006 * ticks;
		if (ticks > 1.0 && x < fill && tk < tw && x > tw) col *= 0.45;
	}
	ALBEDO = col;
	// 다치지 않은 적은 흐리게, 맞은 적은 또렷하게
	ALPHA = 0.9 * mix(1.0, 0.5, full);
}
"""

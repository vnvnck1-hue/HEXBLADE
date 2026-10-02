class_name GasCanister
extends Enemy
## 가스통: 탄·검·레이저·미사일·다른 폭발에 맞으면 체력이 깎이고, 다 깎이면 짧은 도화선 뒤 폭발한다.
## 폭발은 BLAST_R 안의 플레이어(1 피해 + 밀침) · 적(거리별 피해) · 다른 가스통(연쇄 점화)에 닿는다.
## 터진 자리에는 BlastScorch(사방으로 뻗은 그을음 + 일렁이는 불)가 남는다.
## 판정 경로를 그대로 쓰려고 Enemy 를 상속해 "enemies" 그룹에 들어가지만 prop 이라 처치 수·방 진행·소환 상한에는 세지 않는다.

const HP := 5
const BLAST_R := 3.6
const BLAST_DMG := 9            # 중심 피해 (가장자리는 절반)
const FUSE := 0.32
const CHAIN := Vector2(0.12, 0.26)
const GRAVITY := 30.0

static var _tank: CylinderMesh
static var _band: CylinderMesh
static var _cap: SphereMesh
static var _valve: CylinderMesh
static var _gauge: SphereMesh

var drop_h := 0.0               # 0 보다 크면 그 높이에서 떨어지며 등장한다
var fuse := -1.0
var _fall_v := 0.0
var _wob := Vector2.ZERO
var _wob_v := Vector2.ZERO
var _leak_t := 0.0
var _blink := 0.0
var _fuse_snd: AudioStreamPlayer


func _ready() -> void:
	prop = true
	super._ready()
	add_to_group("gas_canisters")
	hp = HP
	max_hp = HP
	radius = 0.5
	slice_color = Color("ff9a40")
	(j.body as Node3D).position.y = drop_h
	landed = drop_h <= 0.0
	shadow.scale = Vector3.ONE * 0.55


func _build(v: Node3D) -> Dictionary:
	if _tank == null:
		_tank = CylinderMesh.new()
		_tank.top_radius = 0.36
		_tank.bottom_radius = 0.36
		_tank.height = 0.92
		_tank.radial_segments = 16
		_band = CylinderMesh.new()
		_band.top_radius = 0.372
		_band.bottom_radius = 0.372
		_band.height = 0.07
		_band.radial_segments = 16
		_cap = SphereMesh.new()
		_cap.radius = 0.36
		_cap.height = 0.36
		_cap.radial_segments = 16
		_cap.rings = 6
		_valve = CylinderMesh.new()
		_valve.top_radius = 0.06
		_valve.bottom_radius = 0.08
		_valve.height = 0.16
		_gauge = SphereMesh.new()
		_gauge.radius = 0.06
		_gauge.height = 0.12
	var jj := {}
	var body := Build.pivot(v, Vector3.ZERO, "Body")
	jj.body = body
	var tank := _mi(body, _tank, Pal.lit(Color("d24a32")), Vector3(0, 0.56, 0))
	jj.cube = tank
	_mi(body, _cap, Pal.lit(Color("d24a32")), Vector3(0, 1.02, 0))
	_mi(body, _band, Pal.lit(Color("ffd23a")), Vector3(0, 0.34, 0))
	_mi(body, _band, Pal.lit(Color("ffd23a")), Vector3(0, 0.8, 0))
	_mi(body, _band, Pal.lit(Color("2a2630")), Vector3(0, 0.1, 0)).scale = Vector3(1.04, 2.2, 1.04)
	_mi(body, _valve, Pal.lit(Color("8a8c98")), Vector3(0, 1.22, 0))
	Build.box(body, Vector3(0.26, 0.04, 0.05), Vector3(0, 1.31, 0), Color("4a4c58"))
	# 인화성 표식: 흰 판 위 붉은 마름모
	Build.box(body, Vector3(0.26, 0.24, 0.03), Vector3(0, 0.57, -0.36), Color("f4f0e8"))
	Build.box(body, Vector3(0.13, 0.13, 0.035), Vector3(0, 0.57, -0.366), Color("e03a2a"), Vector3(0, 0, 45))
	var core := MeshInstance3D.new()
	core.mesh = _gauge
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color("ffb040")
	cm.emission_enabled = true
	cm.emission = Color("ffb040")
	cm.emission_energy_multiplier = 0.8
	core.material_override = cm
	core.position = Vector3(0.2, 1.1, -0.2)
	body.add_child(core)
	jj.core = core
	jj.core_mat = cm
	return jj


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _physics_process(dt: float) -> void:
	if not alive:
		return
	t += dt
	var body: Node3D = j.body
	if not landed:
		# 하늘에서 떨어지는 등장: 쿵 하고 튀었다가 선다
		_fall_v += GRAVITY * dt
		body.position.y = maxf(0.0, body.position.y - _fall_v * dt)
		shadow.scale = Vector3.ONE * lerpf(0.25, 0.55, 1.0 - body.position.y / maxf(drop_h, 0.01))
		if body.position.y <= 0.0:
			landed = true
			punch = 1.0
			_wob_v += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0
			FX.land_dust(global_position)
			Sfx.play("clank", 0.1, -4.0)
			Main.inst.shake(0.15)
		return
	# 흔들림 스프링 (맞으면 기우뚱)
	_wob_v += (-_wob * 160.0 - _wob_v * 9.0) * dt
	_wob += _wob_v * dt
	punch = move_toward(punch, 0.0, dt * 6.0)
	var sq := punch * 0.18
	var hot := 1.0 - float(hp) / HP
	if fuse >= 0.0:
		# 도화선: 미친 듯이 떨며 하얗게 달아오른다
		fuse -= dt
		hot = 1.0
		body.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.05
		sq = 0.12 + sin(t * 70.0) * 0.06
		if randf() < 0.6:
			FX.sparks(body.global_position + Vector3(0, 1.2, 0), 2, [Color.WHITE, Color("ffd060")], 5.0, 0.25, -10.0, 0.05)
		if fuse <= 0.0:
			_detonate()
			return
	body.scale = Vector3(1.0 + sq, 1.0 - sq * 1.2, 1.0 + sq)
	body.rotation = Vector3(_wob.x, 0, _wob.y)
	# 금이 간 통: 체력이 절반 아래면 가스가 새고 경고등이 빨리 깜빡인다
	var cm: StandardMaterial3D = j.core_mat
	_blink += dt * lerpf(2.0, 14.0, hot)
	var on := fmod(_blink, 1.0) < 0.5
	cm.emission = Color("ff3a20") if hot > 0.4 else Color("ffb040")
	cm.emission_energy_multiplier = (0.4 if not on else 1.0 + hot * 3.0) + (6.0 if fuse >= 0.0 else 0.0)
	if hp <= HP / 2 and fuse < 0.0:
		_leak_t -= dt
		if _leak_t <= 0.0:
			_leak_t = randf_range(0.12, 0.3)
			var a := randf() * TAU
			var side := Vector3(sin(a), 0, cos(a))
			FX.puffs(body.global_position + side * 0.38 + Vector3(0, randf_range(0.4, 1.0), 0), 1,
				[Color("e8eef8"), Color("c8d2e0"), Color("8890a0"), Color("707888")], 0.25, 0.32, 0.5)
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0:
			_set_flash(false)


func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if not alive or not landed:
		return
	_hit_spark(dmg, dir, pos, source)
	punch = 1.0
	var l := global_basis.inverse() * Vector3(dir.x, 0, dir.z)
	_wob_v += Vector2(l.z, -l.x) * (6.0 + dmg * 2.0)
	flash_t = 0.06
	_set_flash(true)
	Sfx.play("clank", 0.15, -10.0)
	if fuse >= 0.0:
		return
	hp -= dmg
	FX.sparks(pos if pos != Vector3.ZERO else (j.body as Node3D).global_position + Vector3(0, 0.6, 0), 4,
		[Color.WHITE, Color("ffd060")], 5.0, 0.25, -12.0, 0.05)
	if hp <= 0:
		ignite(FUSE if source != "blast" else randf_range(CHAIN.x, CHAIN.y))


func die(_dir := Vector3.ZERO, _source := "bullet") -> void:
	ignite(0.05)


func stagger(_dir: Vector3, _dur: float) -> void:
	pass


## 점화: delay 초 뒤 터진다 (연쇄 폭발은 짧게 엇갈린다)
func ignite(delay := FUSE) -> void:
	if not alive or fuse >= 0.0:
		return
	fuse = delay
	_fuse_snd = Sfx.play("twind", 0.05, -6.0)
	if _fuse_snd:
		_fuse_snd.pitch_scale = 1.8
	FX.flash((j.body as Node3D).global_position + Vector3(0, 0.6, 0), Color("ffe0a0"), 1.0, 0.06)


func _detonate() -> void:
	alive = false
	remove_from_group("enemies")
	locked = false
	if is_instance_valid(lock_marker):
		lock_marker.queue_free()
	var c := global_position + Vector3(0, 0.6, 0)
	var main := Main.inst
	FX.fire_explosion(c, 1.45)
	FX.shockwave(Vector3(c.x, Main.gy(c) + 0.05, c.z), Color("ffb060"), BLAST_R * 1.1, 0.4, 0.12)
	FX.sparks(c, 26, [Color.WHITE, Color("ffd060"), Color("ff7a30")], 12.0, 0.6, -14.0, 0.08)
	Sfx.play("boom", 0.08, 2.0)
	main.shake(0.7)
	main.hitstop(0.05)
	if is_instance_valid(main.camera):
		main.camera.fov_punch(2.5)
	# 찢어진 철판 조각
	var mat := Pal.lit(Color("d24a32"))
	for i in 7:
		var a := TAU * i / 7.0 + randf() * 0.5
		var out := Vector3(sin(a), 0, cos(a))
		var xf := Transform3D(Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, 0)), c + out * 0.3)
		Debris.toss(Build.bevel_mesh(Vector3(0.28, 0.06, 0.22), 0.02), mat, xf, out * randf_range(6.0, 10.0) + Vector3(0, randf_range(6.0, 11.0), 0), 1.4)
	BlastScorch.spawn(main.world, Vector3(global_position.x, Main.gy(global_position), global_position.z))
	_blast_hit(c)
	queue_free()


func _blast_hit(c: Vector3) -> void:
	var main := Main.inst
	var p := main.player
	if is_instance_valid(p) and p.alive:
		var d := p.global_position - global_position
		d.y = 0
		if d.length() < BLAST_R + p.hit_radius and absf(p.global_position.y - global_position.y) < 2.0:
			if p.take_hit(global_position):
				p.shove(d.normalized() if d.length() > 0.05 else Vector3.BACK, 11.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not is_instance_valid(e):
			continue
		var en := e as Enemy
		if en == null or not en.alive or not en.landed:
			continue
		var d := en.global_position - global_position
		d.y = 0
		var l := d.length()
		if l > BLAST_R + en.radius:
			continue
		var dir := d / maxf(l, 0.001)
		if en is GasCanister:
			(en as GasCanister).ignite(randf_range(CHAIN.x, CHAIN.y))
			continue
		var k := 1.0 - clampf(l / (BLAST_R + en.radius), 0.0, 1.0) * 0.5
		en.take_hit(maxi(1, roundi(BLAST_DMG * k)), dir, en.global_position + Vector3(0, 1.0, 0), "blast")

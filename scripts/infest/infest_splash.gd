class_name InfestSplash
extends Node3D
## 끈적한 체액 튐. 포낭이 터지거나 맞을 때 한 번 만들고 다 끝나면 스스로 사라진다 (판정 없음, 연출 전용).
##  방울    크고 느린 덩어리 몇 개 + 작고 빠른 방울 여럿. 날아가는 방향으로 늘어나고, 떨어지면 철퍽 얼룩이 된다.
##  끈적 줄 큰 덩어리 몇 개는 터진 자리와 끈적한 줄로 이어져 날아가다 너무 늘어나면 툭 끊긴다 (끊긴 줄은 방울로 떨어짐).
##  벽에 맞은 방울은 벽면 얼룩이 되고, 몇 개는 벽을 타고 흘러내린다.
##  얼룩은 BugEnemy.SPLAT_GROUP 이라 청소 질주(FloorVac)가 빨아들인다. 아니면 몇 초 뒤 오그라들어 사라진다.

const GRAVITY := 17.0
const DRAG := 1.1
const SPLAT_LIFE := Vector2(7.0, 10.0)
const SPLAT_MAX := 180            ## 동시에 남는 얼룩 상한 (넘으면 오래된 것부터 지운다)
const DROP_MAX := 70

static var _splats: Array = []
## 한 물리 프레임에 새로 만드는 방울·얼룩 노드 상한. 작은 혹이 연쇄로 한꺼번에 터지면 한 프레임에 노드 500여 개가 생겨 끊겼다.
## 넘는 몫은 그냥 생략한다 (큰 덩어리·왕관 시트는 먼저 만들어지므로 모양은 그대로 읽힌다)
const FRAME_DROPS := 90
const FRAME_SPLATS := 36
static var _frame := -1
static var _frame_drops := 0
static var _frame_splats := 0


static func _budget(splat: bool) -> bool:
	var f := Engine.get_physics_frames()
	if f != _frame:
		_frame = f
		_frame_drops = 0
		_frame_splats = 0
	if splat:
		_frame_splats += 1
		return _frame_splats <= FRAME_SPLATS
	_frame_drops += 1
	return _frame_drops <= FRAME_DROPS

var drops: Array = []             ## {n, v, r, strand, anchor, snap}
var drips: Array = []             ## 벽을 타고 흐르는 방울 {n, v, life, floor}
var age := 0.0


## at: 터진 자리 · normal: 튀어 나가는 바깥 방향 (바닥이면 위, 벽에 붙은 포낭이면 벽 법선) · size: 0.2(작은 혹) ~ 1.2(큰 포낭)
static func burst(at: Vector3, normal: Vector3, size: float, strands := true) -> InfestSplash:
	if FX.root == null:
		return null
	var s := InfestSplash.new()
	FX.root.add_child(s)
	s.global_position = at
	s._emit(normal.normalized(), size, strands)
	return s


## 맞았을 때 조금 튀는 것 (터지지 않음)
static func spray(at: Vector3, dir: Vector3, size: float) -> void:
	if FX.root == null:
		return
	var s := InfestSplash.new()
	FX.root.add_child(s)
	s.global_position = at
	var n := 3 + int(size * 4.0)
	for i in n:
		var d := (dir.normalized() * 0.7 + Vector3.UP * 0.8 + _rand_dir() * 0.6).normalized()
		s._drop(d * randf_range(1.8, 4.0), randf_range(0.018, 0.035) * (0.7 + size * 0.5))


static func _rand_dir() -> Vector3:
	var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	return v.normalized() if v.length() > 0.01 else Vector3.UP


func _emit(normal: Vector3, size: float, strands: bool) -> void:
	var k := clampf(size, 0.15, 1.4)
	# 카툰 액체 시트 (왕관 · 날아가는 막 · 덩어리 → 철퍽). 3D 방울은 그 사이를 채우는 작은 것만
	LiquidFX.burst(global_position, normal, k, "wine")
	# 큰 덩어리 (끈적 줄 달림)
	var big := 1 + int(k * 2.5)
	for i in big:
		var d := (normal * 1.1 + _rand_dir() * 0.85).normalized()
		if d.dot(normal) < 0.1:
			d = (d + normal).normalized()
		var r := randf_range(0.07, 0.13) * (0.6 + k * 0.6)
		var dr := _drop(d * randf_range(2.2, 4.4) * (0.75 + k * 0.4), r)
		if strands and i < 2 + int(k * 3.0) and dr:
			_strand(dr, randf_range(0.5, 1.1) * (0.6 + k * 0.6))
	# 작고 빠른 방울
	var small := 8 + int(k * 16.0)
	for i in small:
		var d := (normal * 0.75 + _rand_dir()).normalized()
		if d.dot(normal) < -0.05:
			d = (d + normal * 0.8).normalized()
		_drop(d * randf_range(3.5, 8.5) * (0.7 + k * 0.45), randf_range(0.025, 0.06) * (0.7 + k * 0.4))
	# 낮게 퍼지는 왕관 방울 (바닥 쪽으로 납작하게)
	var crown := 5 + int(k * 6.0)
	var side := normal.cross(Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var side2 := normal.cross(side)
	for i in crown:
		var a := TAU * i / crown + randf() * 0.4
		var d := (side * cos(a) + side2 * sin(a)) * 1.0 + normal * 0.35
		_drop(d.normalized() * randf_range(2.5, 4.5) * (0.7 + k * 0.4), randf_range(0.035, 0.07) * (0.7 + k * 0.4))
	# 터지는 순간: 짧은 분홍 섬광 · 찢어진 껍질 조각
	var c := global_position
	FX.flash(c, Color("ff7ac0"), 0.35 + k * 0.4, 0.06)
	_flaps(normal, k)
	if k > 0.75:
		FX.shockwave(Vector3(c.x, Main.gy(c) + 0.04, c.z), Color("c0508f"), 0.6 + k * 0.6, 0.18, 0.04)


static var _flap_mat: StandardMaterial3D

## 찢어진 포낭 껍질: 연보라·포도주 납작한 조각이 빙글 돌며 날아가 떨어진다
func _flaps(normal: Vector3, k: float) -> void:
	if _flap_mat == null:
		_flap_mat = StandardMaterial3D.new()
		_flap_mat.albedo_color = Color("7a3a6c")
		_flap_mat.roughness = 0.35
		_flap_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 2 + int(k * 4.0):
		var d := (normal + _rand_dir() * 0.9).normalized()
		var s := randf_range(0.6, 1.0) * (0.12 + k * 0.12)
		var b := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, 0)).scaled(Vector3(s, s, s * 0.8))
		Debris.toss(InfestMesh.splat(i), _flap_mat, Transform3D(b, global_position + d * 0.05), d * randf_range(3.0, 6.0) + Vector3.UP * 2.0, 1.2)


func _drop(v: Vector3, r: float) -> Dictionary:
	if drops.size() >= DROP_MAX or not _budget(false):
		return {}
	var mi := MeshInstance3D.new()
	mi.mesh = InfestMesh.drop_mesh()
	mi.material_override = InfestMesh.goo_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = global_position
	var d := {"n": mi, "v": v, "r": r, "strand": null, "anchor": global_position, "snap": 0.0, "len": 0.0}
	drops.append(d)
	return d


func _strand(d: Dictionary, snap: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = InfestMesh.strand_mesh()
	mi.material_override = InfestMesh.goo_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	d.strand = mi
	d.snap = snap
	# 큰 덩어리는 줄에 끌려 조금 느리다
	d.v *= 0.82


func _physics_process(dt: float) -> void:
	age += dt
	var main := Main.inst
	var i := drops.size() - 1
	while i >= 0:
		var d: Dictionary = drops[i]
		var n: MeshInstance3D = d.n
		var v: Vector3 = d.v
		v.y -= GRAVITY * dt
		v *= 1.0 - DRAG * dt
		var p := n.global_position + v * dt
		d.v = v
		var gone := false
		if main and main.map:
			var fl := main.floor_at(p)
			if p.y <= fl + 0.01 and v.y < 0.0:
				_splat(Vector3(p.x, fl, p.z), Vector3.UP, d.r, v)
				gone = true
			elif main.is_blocked(p) and p.y > fl + 0.05:
				_wall_hit(n.global_position, v, d.r)
				gone = true
		elif p.y <= 0.0:
			_splat(Vector3(p.x, 0, p.z), Vector3.UP, d.r, v)
			gone = true
		if age > 3.0:
			gone = true
		if gone:
			_cut_strand(d, true)
			n.queue_free()
			drops.remove_at(i)
			i -= 1
			continue
		n.global_position = p
		# 날아가는 방향으로 늘어난다
		var sp := v.length()
		if sp > 0.3:
			n.basis = _along(v.normalized())
			var st := 1.0 + minf(sp * 0.09, 1.4)
			n.scale = Vector3(d.r * 2.0 / sqrt(st), d.r * 2.0 * st, d.r * 2.0 / sqrt(st))
		_update_strand(d, dt)
		i -= 1
	i = drips.size() - 1
	while i >= 0:
		var dr: Dictionary = drips[i]
		var n: MeshInstance3D = dr.n
		dr.life -= dt
		var p := n.global_position + Vector3.DOWN * float(dr.v) * dt
		dr.v = minf(float(dr.v) + dt * 0.6, 0.9)
		n.global_position = p
		n.scale.y = minf(n.scale.y + dt * 0.16, 0.22)
		if p.y <= float(dr.floor) + 0.02 or dr.life <= 0.0:
			_splat(Vector3(p.x, float(dr.floor), p.z), Vector3.UP, 0.035, Vector3.ZERO)
			n.queue_free()
			drips.remove_at(i)
		i -= 1
	if drops.is_empty() and drips.is_empty() and age > 0.2:
		queue_free()


## y 축을 dir 에 맞춘 기저 (방울을 진행 방향으로 늘이려고)
static func _along(dir: Vector3) -> Basis:
	var x := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, dir, x.cross(dir).normalized())


func _update_strand(d: Dictionary, _dt: float) -> void:
	var s: MeshInstance3D = d.strand
	if s == null or not is_instance_valid(s):
		return
	var a: Vector3 = d.anchor
	var b: Vector3 = (d.n as Node3D).global_position
	var l := a.distance_to(b)
	if l > float(d.snap):
		_cut_strand(d, false)
		return
	# 늘어날수록 가늘어지고 가운데가 처진다 (두 토막으로 그려 처짐을 보인다)
	var mid := (a + b) * 0.5 + Vector3.DOWN * l * 0.12
	var th := float(d.r) * 0.55 * clampf(0.3 / maxf(l, 0.05), 0.18, 1.0)
	s.global_transform = _seg_xf(a, mid, th)
	if not d.has("s2"):
		var s2 := MeshInstance3D.new()
		s2.mesh = InfestMesh.strand_mesh()
		s2.material_override = InfestMesh.goo_mat()
		s2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s2.top_level = true
		add_child(s2)
		d.s2 = s2
	(d.s2 as MeshInstance3D).global_transform = _seg_xf(mid, b, th * 0.8)


static func _seg_xf(a: Vector3, b: Vector3, th: float) -> Transform3D:
	var dv := b - a
	var l := maxf(dv.length(), 0.001)
	var bas := _along(dv / l)
	return Transform3D(Basis(bas.x * th * 2.0, bas.y * l, bas.z * th * 2.0), (a + b) * 0.5)


## 끈적 줄 끊김: 줄이 짧은 방울 몇 개가 되어 떨어진다 (landed = 덩어리가 이미 떨어져 같이 사라질 때)
func _cut_strand(d: Dictionary, landed: bool) -> void:
	var s = d.strand
	if s == null or not is_instance_valid(s):
		return
	var a: Vector3 = d.anchor
	var b: Vector3 = (d.n as Node3D).global_position
	(s as Node3D).queue_free()
	if d.has("s2") and is_instance_valid(d.s2):
		(d.s2 as Node3D).queue_free()
	d.strand = null
	if landed:
		return
	if randf() < 0.5:
		Sfx.play("infest_drip", 0.2, -16.0)
	for k in 3:
		var p := a.lerp(b, randf_range(0.2, 0.8))
		var dd := _drop(Vector3(randf_range(-0.5, 0.5), randf_range(-0.2, 0.6), randf_range(-0.5, 0.5)), float(d.r) * 0.45)
		if not dd.is_empty():
			(dd.n as Node3D).global_position = p


func _wall_hit(at: Vector3, v: Vector3, r: float) -> void:
	var main := Main.inst
	# 들어간 쪽 축으로 벽 법선을 잡는다
	var flat := Vector3(v.x, 0, v.z)
	var nrm := Vector3(-signf(flat.x), 0, 0) if absf(flat.x) > absf(flat.z) else Vector3(0, 0, -signf(flat.z))
	if nrm == Vector3.ZERO:
		nrm = Vector3.BACK
	var c := main.map.cell_of(at)
	var cell_c := main.map.world_of(c)
	# 칸 경계면 (방울이 있던 칸의 벽 쪽 면)
	var face := at
	if nrm.x != 0.0:
		face.x = cell_c.x - nrm.x * 0.5 + nrm.x * 0.006
	else:
		face.z = cell_c.z - nrm.z * 0.5 + nrm.z * 0.006
	_splat(face, nrm, r, v)
	if randf() < 0.45 and drips.size() < 12:
		var mi := MeshInstance3D.new()
		mi.mesh = InfestMesh.drop_mesh()
		mi.material_override = InfestMesh.goo_mat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = face + nrm * 0.01
		mi.scale = Vector3(r * 1.1, r * 1.4, r * 1.1)
		drips.append({"n": mi, "v": 0.08, "life": 2.2, "floor": main.floor_at(face + nrm * 0.3)})


## 얼룩: normal 면에 납작하게 붙는다. 속도가 빠를수록 진행 방향으로 길쭉하다
func _splat(at: Vector3, normal: Vector3, r: float, v: Vector3) -> void:
	if FX.root == null or not _budget(true):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = InfestMesh.splat(randi())
	mi.material_override = InfestMesh.goo_mat(true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group(BugEnemy.SPLAT_GROUP)
	FX.root.add_child(mi)
	var up := normal.normalized()
	var flat := v - up * v.dot(up)
	var fwd := flat.normalized() if flat.length() > 0.2 else up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized().rotated(up, randf() * TAU)
	var x := up.cross(fwd).normalized()
	var stretch := 1.0 + minf(flat.length() * 0.12, 0.9)
	var s := snappedf(clampf(r * 9.0, 0.15, 1.1), 0.05)
	mi.global_transform = Transform3D(Basis(x, up, fwd), at + up * 0.012)
	var target := Vector3(s, s * 0.9, s * stretch)
	mi.scale = target * 0.25
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", target, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(randf_range(SPLAT_LIFE.x, SPLAT_LIFE.y))
	tw.tween_property(mi, "scale", Vector3(target.x * 0.05, target.y * 0.2, target.z * 0.05), 1.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	_splats.append(mi)
	while _splats.size() > SPLAT_MAX:
		var old = _splats.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	if s > 0.4 and randf() < 0.35:
		Sfx.play("infest_drip", 0.25, -18.0)

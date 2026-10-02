extends Node3D
## B안(궤도 파손과 전복) 전용 VFX: 강철이 도로에 갈리며 쏟아지는 불꽃 · 도로에 붙어 흐르는 긁힘 자국 · 부품 조각.
## 불꽃은 MultiMesh 하나로 수백 개를 한 번에 그린다 (가산 혼합 + HDR 로 글로우가 번진다).
## 모두 이 노드 아래에 있어 씬을 떠나면 함께 사라진다. 판정과 무관.

const BossTank := preload("res://scripts/boss_tank.gd")
const Stage := preload("res://scripts/boss_stage.gd")

const MAX_SPARKS := 1100
const MAX_MARKS := 360
const GRAVITY := 20.0

var stage: Stage
var budget := 1.0                  # 1 기본, 0.5 낮음

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _p := PackedVector3Array()
var _v := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _len := PackedFloat32Array()
var _heat := PackedFloat32Array()  # 1 = 흰빛 불꽃, 0 = 주황 불씨
var _roll_i := 0

var _mark_mesh: BoxMesh
## [mi, a_road, b_road, age, life, width]
var _marks: Array = []
var _mark_i := 0

const HOT := Color(1.0, 0.95, 0.8)
const MID := Color(1.0, 0.62, 0.2)
const EMBER := Color(1.0, 0.25, 0.06)
const SCORCH := Color("24181c")

const SPARK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
varying float energy;
void vertex() { energy = INSTANCE_CUSTOM.x; }
void fragment() { ALBEDO = COLOR.rgb * energy; }
"""


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	var sh := Shader.new()
	sh.code = SPARK_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	box.material = m
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = box
	_mm.instance_count = MAX_SPARKS
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 16384.0
	add_child(_mmi)
	_mark_mesh = BoxMesh.new()
	_mark_mesh.size = Vector3(1.0, 0.02, 1.0)
	for i in MAX_MARKS:
		var mi := Pal.flat_mesh(_mark_mesh, MID, 2.0)
		mi.visible = false
		add_child(mi)
		_marks.append([mi, Vector3.ZERO, Vector3.ZERO, 0.0, 0.0, 0.2])


func spark_count() -> int:
	return _p.size()


func _process(dt: float) -> void:
	var road := stage.speed if stage else 0.0
	var i := _p.size() - 1
	while i >= 0:
		_age[i] += dt
		if _age[i] >= _life[i]:
			_kill(i)
			i -= 1
			continue
		var v := _v[i]
		var p := _p[i]
		v.y -= GRAVITY * dt
		v *= 1.0 - 0.8 * dt
		p += v * dt
		if p.y < 0.04 and v.y < 0.0:
			# 바닥에 튀면 다시 튀어 오르며 도로 속도로 끌려간다
			p.y = 0.04
			v.y = -v.y * 0.42
			v.z = lerpf(v.z, road, 0.6)
			v.x *= 0.75
		_p[i] = p
		_v[i] = v
		i -= 1
	var n := _p.size()
	for k in n:
		var v := _v[k]
		var spd := v.length()
		var u := _age[k] / _life[k]
		var len := clampf(spd * 0.05, 0.12, 3.2) * _len[k] * (1.0 - u * 0.5)
		var w := 0.075 * (1.0 - u * 0.55) * (0.7 + 0.5 * _heat[k])
		var dir := v / spd if spd > 0.05 else Vector3.UP
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		var b := Basis.looking_at(dir, up)
		b.x *= w
		b.y *= w
		b.z *= len
		_mm.set_instance_transform(k, Transform3D(b, _p[k] - dir * len * 0.5))
		var hot := _heat[k]
		var c: Color = HOT.lerp(MID, clampf(u * 1.8 - hot * 0.4, 0.0, 1.0)).lerp(EMBER, clampf(u * 2.0 - 1.0, 0.0, 1.0))
		_mm.set_instance_color(k, c)
		_mm.set_instance_custom_data(k, Color(lerpf(6.0, 1.6, u) * (0.6 + 0.4 * hot), 0, 0, 0))
	_mm.visible_instance_count = n
	# 불꽃도 긁힘 자국도 다 사라지면 쉰다 (spark · scratch 가 다시 깨운다)
	if not _update_marks(dt) and n == 0:
		set_process(false)


func _kill(i: int) -> void:
	var last := _p.size() - 1
	if i != last:
		_p[i] = _p[last]
		_v[i] = _v[last]
		_age[i] = _age[last]
		_life[i] = _life[last]
		_len[i] = _len[last]
		_heat[i] = _heat[last]
	_p.resize(last)
	_v.resize(last)
	_age.resize(last)
	_life.resize(last)
	_len.resize(last)
	_heat.resize(last)


## 한 줄기 불꽃. vel 은 월드 속도(m/s), heat 1 은 흰빛, 0 은 주황 불씨
func spark(pos: Vector3, vel: Vector3, life := 0.35, len_k := 1.0, heat := 1.0) -> void:
	if budget < 1.0 and randf() > budget:
		return
	set_process(true)
	if _p.size() >= MAX_SPARKS:
		# 가득 차면 오래된 자리부터 덮어쓴다
		_roll_i = (_roll_i + 1) % MAX_SPARKS
		_p[_roll_i] = pos
		_v[_roll_i] = vel
		_age[_roll_i] = 0.0
		_life[_roll_i] = life
		_len[_roll_i] = len_k
		_heat[_roll_i] = heat
		return
	_p.append(pos)
	_v.append(vel)
	_age.append(0.0)
	_life.append(life)
	_len.append(len_k)
	_heat.append(heat)


## 부채꼴로 튀는 불꽃 다발. out = 퍼지는 수평 방향
func spark_fan(pos: Vector3, count: int, out: Vector3, road: float, power := 1.0, spread := 1.0) -> void:
	for i in count:
		var side := out * randf_range(2.0, 14.0) * power
		var along := Vector3(0, 0, road * randf_range(0.35, 1.05) + randf_range(-4.0, 4.0))
		var lat := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 6.0 * spread
		var up := Vector3(0, randf_range(1.5, 11.0) * power, 0)
		spark(pos + Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.3), randf_range(-0.6, 0.6)), side + along + lat + up, randf_range(0.2, 0.7), randf_range(0.8, 1.5), randf())


## 사방으로 터지는 불꽃 (부품이 뜯겨 나가는 순간)
func spark_burst(pos: Vector3, count: int, speed: float, road: float) -> void:
	for i in count:
		var d := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1)).normalized()
		spark(pos, d * speed * randf_range(0.3, 1.0) + Vector3(0, 2.0, road * 0.3), randf_range(0.25, 0.8), randf_range(0.8, 1.4), randf())


## 보이는 긁힘 자국이 남아 있으면 true
func _update_marks(dt: float) -> bool:
	# 긁힘 자국: 도로 좌표(z - scroll)에 붙여 도로와 함께 흐르게 한다
	var scroll := stage.scroll if stage else 0.0
	var any := false
	for m in _marks:
		var mi: MeshInstance3D = m[0]
		if not mi.visible:
			continue
		m[3] += dt
		var u: float = m[3] / m[4]
		if u >= 1.0:
			mi.visible = false
			continue
		any = true
		var a: Vector3 = m[1] + Vector3(0, 0, scroll)
		var b: Vector3 = m[2] + Vector3(0, 0, scroll)
		var d := b - a
		var l := d.length()
		if l < 0.01:
			continue
		var w: float = m[5] * (1.0 - u * u)
		mi.global_transform = Transform3D(Basis.looking_at(d / l, Vector3.UP), (a + b) * 0.5)
		mi.scale = Vector3(w, 1.0, l + w)
		# 막 긁힌 부분은 흰빛 → 주황, 곧 검게 그을린 자국으로 식는다
		var hot := clampf(m[3] / 0.2, 0.0, 1.0)
		mi.set_instance_shader_parameter("tint", HOT.lerp(MID, hot * 0.6).lerp(SCORCH, clampf((m[3] - 0.14) / 0.35, 0.0, 1.0)))
		mi.set_instance_shader_parameter("energy", lerpf(4.0, 1.0, hot))
	return any


## 도로에 긁힌 자국 한 토막 (월드 좌표 두 점)
func scratch(a: Vector3, b: Vector3, width := 0.22, life := 0.9) -> void:
	var scroll := stage.scroll if stage else 0.0
	var m: Array = _marks[_mark_i]
	_mark_i = (_mark_i + 1) % MAX_MARKS
	m[1] = Vector3(a.x, 0.03, a.z - scroll)
	m[2] = Vector3(b.x, 0.03, b.z - scroll)
	m[3] = 0.0
	m[4] = life
	m[5] = width
	(m[0] as MeshInstance3D).visible = true
	set_process(true)


## 떨어져 나가는 궤도 덩어리: 벨트 한 토막 + 바퀴 하나. 도로에 튕기며 뒤로 흘러간다
func tread_chunk(xf: Transform3D, vel: Vector3) -> Node3D:
	var n := Node3D.new()
	stage.add_child(n)
	BossTank.rbox(n, Vector3(1.8, 1.7, 2.3), 0.7, Vector3.ZERO, BossTank.TREAD)
	for k in 3:
		BossTank.rbox(n, Vector3(1.92, 0.24, 0.46), 0.1, Vector3(0, 0.86, -0.7 + k * 0.7), BossTank.CLEAT)
	BossTank.cyl(n, 0.7, 0.7, 0.2, Vector3(0.95, 0, 0), BossTank.STEEL_DEEP, Vector3(0, 0, 90))
	BossTank.ball(n, 0.5, Vector3(1.02, 0, 0), BossTank.HUB, Vector3(0.35, 1, 1))
	BossTank.glow(n, Vector3(1.4, 0.12, 0.12), Vector3(0, -0.2, 1.15), Color("ff6a20"), 2.4)
	n.global_transform = xf
	stage.drift(n, vel, Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)).normalized() * randf_range(8, 13), true, 4.5)
	return n


## 궤도 벨트 조각 (돌기 판)
func cleat(pos: Vector3, vel: Vector3) -> void:
	var holder := Node3D.new()
	stage.add_child(holder)
	BossTank.rbox(holder, Vector3(1.9, 0.26, 0.5), 0.1, Vector3.ZERO, BossTank.CLEAT if randf() < 0.5 else BossTank.TREAD)
	holder.global_position = pos
	stage.drift(holder, vel, Vector3(randf(), randf(), randf()).normalized() * randf_range(8, 16), true, 3.0)


## 작은 장갑·돌기 조각
func chunk(pos: Vector3, vel: Vector3, big := false) -> void:
	var c: Color = [BossTank.STEEL, BossTank.STEEL_MID, BossTank.STEEL_DARK, BossTank.CLEAT][randi() % 4]
	var holder := Node3D.new()
	stage.add_child(holder)
	var k := 1.7 if big else 1.0
	# 크기는 격자에 맞춘다 (BossTank 메시 캐시가 끝없이 늘지 않게)
	var sz := BossTank.snap_size(Vector3(randf_range(0.4, 1.1), randf_range(0.2, 0.5), randf_range(0.4, 1.1)) * k)
	BossTank.rbox(holder, sz, 0.1, Vector3.ZERO, c)
	holder.global_position = pos
	stage.drift(holder, vel, Vector3(randf(), randf(), randf()).normalized() * randf_range(6, 14), true, 3.5)


## 따뜻한 순간 광원 하나. 호출한 쪽이 에너지를 갱신한다
func make_light(c: Color, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.omni_range = rng
	l.light_energy = 0.0
	l.shadow_enabled = false
	add_child(l)
	return l

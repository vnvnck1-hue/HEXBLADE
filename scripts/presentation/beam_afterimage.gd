class_name BeamAfterimage
extends Node3D
## 빔 몸통이 사라진 자리에 남는 잔상. 판정과 무관.
## 흐름: 가는 선으로 남음 → 총구 쪽부터 파도처럼 일렁임 → 조각으로 끊겨 지글거리며
## 흩어짐 → 점으로 부서지며 사라짐. 끝나면 스스로 해제된다.
## 사용: BeamAfterimage.spawn(origin, dir, length, width, color, delay)

const STEP := 0.14          # 선을 이루는 점 간격
const HOLD := 0.04          # 곧은 선으로 버티는 시간
const WAVE_TIME := 0.09     # 파동이 총구에서 끝까지 번지는 시간
const BREAK_AT := 0.18      # 조각으로 끊기는 시점
const SETTLE_TIME := 0.3    # 끊긴 조각이 줄어들고 지글거리기 시작하는 시간
const AMP := 0.55           # 파동 진폭
const WAVELEN := 3.2        # 파동 파장
const JITTER_HZ := 25.0     # 부서진 조각의 지글거림 갱신 빈도

var color := Color("1ff0ff")
var width := 0.11
var delay := 0.0
var origin := Vector3.ZERO
var dir := Vector3.FORWARD
var length := 10.0

var t := 0.0
var side := Vector3.RIGHT
var base: PackedVector3Array = []   # 점 원위치
var wave_ph := Vector2.ZERO
var wmul: PackedFloat32Array = []    # 점별 굵기 배율 (뭉친 덩어리 느낌)
var segs: Array = []                 # 끊긴 뒤 조각들 (Dictionary)
var broken := false
var _mesh := ArrayMesh.new()
var _mi := MeshInstance3D.new()
var _jit_t := 0.0
var _jit_seed := 0
var _verts: PackedVector3Array = []
var _cols: PackedColorArray = []
# 매 프레임 다시 쓰는 작업용 배열 (새로 만들지 않는다)
var _rng := RandomNumberGenerator.new()
var _line: PackedVector3Array = []
var _ws: PackedFloat32Array = []
var _live := PackedByteArray()
var _arrays := []

static var _shader: Shader


static func spawn(o: Vector3, d: Vector3, len: float, w: float, col: Color, wait := 0.0) -> BeamAfterimage:
	var a := BeamAfterimage.new()
	a.origin = o
	a.dir = d.normalized()
	a.length = len
	a.width = w
	a.color = col
	a.delay = wait
	FX.root.add_child(a)
	return a


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float energy = 1.6;
void fragment() {
	ALBEDO = COLOR.rgb * energy;
	ALPHA = COLOR.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader
	_mi.mesh = _mesh
	_mi.material_override = m
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	side = Vector3.UP.cross(dir).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	var n := maxi(2, int(ceil(length / STEP)) + 1)
	for i in n:
		base.append(origin + dir * minf(length, i * STEP))
		wmul.append(randf_range(0.7, 1.0) if randf() > 0.12 else randf_range(1.4, 2.0))
	wave_ph = Vector2(randf() * TAU, randf() * TAU)


## 파동 모양: 두 사인파 합. 총구에서 번져 나가는 파면 뒤쪽만 흔들린다
func _wave(i: int, age: float) -> Vector3:
	var s := minf(length, i * STEP)
	var front := clampf((age - HOLD) / WAVE_TIME, 0.0, 1.0) * length * 1.15
	var grow := clampf((front - s) / 1.5, 0.0, 1.0)
	if grow <= 0.0:
		return base[i]
	var k := TAU / WAVELEN
	var travel := age * 7.0
	var y := sin(s * k - travel + wave_ph.x) * 0.65 + sin(s * k * 2.3 - travel * 1.4 + wave_ph.y) * 0.35
	var off := side * y * AMP * grow + Vector3.UP * y * AMP * 0.55 * grow
	return base[i] + off


## 곧은/일렁이는 선을 조각으로 나눈다. 짧은 조각은 점이 되고, 일부만 살아남는다
func _break() -> void:
	broken = true
	var n := base.size()
	var i := 0
	while i < n:
		var big := randf() < 0.3
		var cnt := randi_range(8, 18) if big else randi_range(1, 3)
		cnt = mini(cnt, n - i)
		var keep := randf() < (0.75 if big else 0.4)
		if keep:
			var pts: PackedVector3Array = []
			for k in cnt:
				pts.append(_wave(i + k, BREAK_AT))
			var c := Vector3.ZERO
			for p in pts:
				c += p
			c /= float(cnt)
			var deaths: PackedFloat32Array = []
			var ws: PackedFloat32Array = []
			for k in cnt:
				deaths.append(randf_range(0.35, 1.0))
				ws.append(wmul[i + k] * 1.3)
			segs.append({
				"pts": pts, "c": c, "deaths": deaths, "ws": ws,
				"squash": randf_range(0.6, 0.9) if big else 1.0,
				"vel": Vector3(randf_range(-0.5, 0.5), randf_range(0.15, 0.7), randf_range(-0.5, 0.5)),
				"life": randf_range(0.75, 1.0) if big else randf_range(0.2, 0.55),
				"big": big,
			})
		i += cnt


func _process(dt: float) -> void:
	t += dt
	var age := t - delay
	if age < 0.0:
		return
	if not broken and age >= BREAK_AT:
		_break()
	_jit_t -= dt
	if _jit_t <= 0.0:
		_jit_t = 1.0 / JITTER_HZ
		_jit_seed = randi()
	var cam := get_viewport().get_camera_3d()
	var view := (cam.global_transform.basis.z if cam else Vector3(0, 0.77, 0.64)).normalized()
	_mesh.clear_surfaces()
	_verts.clear()
	_cols.clear()
	if not broken:
		var n := base.size()
		_line.resize(n)
		_ws.resize(n)
		_live.clear()
		var wk := clampf((age - HOLD) / WAVE_TIME, 0.0, 1.0)
		for i in n:
			_line[i] = _wave(i, age)
			_ws[i] = lerpf(1.0, wmul[i], wk)
		_ribbon(_line, _ws, _live, 1.0, view)
	else:
		var st := age - BREAK_AT
		var rng := _rng
		rng.seed = _jit_seed
		var alive := 0
		for sg in segs:
			var life: float = sg.life
			if st > life:
				continue
			alive += 1
			var f := st / life
			var r := smoothstep(0.0, 1.0, clampf(st / SETTLE_TIME, 0.0, 1.0))
			var sq: float = lerpf(1.0, sg.squash, r)
			var drift: Vector3 = sg.vel * (st - st * st * 0.6)
			var c: Vector3 = sg.c
			var pts: PackedVector3Array = sg.pts
			var deaths: PackedFloat32Array = sg.deaths
			var n := pts.size()
			_line.resize(n)
			_live.resize(n)
			for k in n:
				var local := (pts[k] - c) * sq
				# 부서지는 조각의 지글거림 (저프레임으로 튄다)
				var jit := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.035 * r
				_line[k] = c + local + drift + jit
				_live[k] = 1 if f < deaths[k] else 0
			var a := 1.0 - smoothstep(0.7, 1.0, f)
			_ribbon(_line, sg.ws, _live, a, view)
		if alive == 0:
			queue_free()
			return
	if _verts.is_empty():
		return
	# 정점·색 배열을 한 번에 넘긴다 (정점마다 부르는 ImmediateMesh 보다 싸다)
	if _arrays.is_empty():
		_arrays.resize(Mesh.ARRAY_MAX)
	_arrays[Mesh.ARRAY_VERTEX] = _verts
	_arrays[Mesh.ARRAY_COLOR] = _cols
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)


## 카메라를 향한 띠. live 가 비면 전부 이어 그리고, 끊긴 점은 작은 사각 점으로 남긴다
func _ribbon(line: PackedVector3Array, ws: PackedFloat32Array, live: PackedByteArray, a: float, view: Vector3) -> void:
	var n := line.size()
	var c := Color(color.r, color.g, color.b, a)
	for k in n:
		if not live.is_empty() and live[k] == 0:
			continue
		var has_next := k + 1 < n and (live.is_empty() or live[k + 1] == 1)
		var has_prev := k > 0 and (live.is_empty() or live[k - 1] == 1)
		var hw := width * ws[k] * 0.5
		if has_next:
			var hw2 := width * ws[k + 1] * 0.5
			var tan := line[k + 1] - line[k]
			var sd := tan.cross(view).normalized()
			if sd.length() < 0.5:
				sd = side
			_quad(line[k] - sd * hw, line[k] + sd * hw, line[k + 1] - sd * hw2, line[k + 1] + sd * hw2, c)
		elif not has_prev:
			# 홀로 남은 점: 카메라를 향한 작은 사각형
			var up := Vector3.UP.cross(view).cross(view).normalized() * -1.0
			var rt := up.cross(view).normalized()
			var s := hw * 1.3
			_quad(line[k] - rt * s - up * s, line[k] + rt * s - up * s, line[k] - rt * s + up * s, line[k] + rt * s + up * s, c)


func _quad(l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, c: Color) -> void:
	_verts.append(l0); _verts.append(r0); _verts.append(r1)
	_verts.append(l0); _verts.append(r1); _verts.append(l1)
	for i in 6:
		_cols.append(c)

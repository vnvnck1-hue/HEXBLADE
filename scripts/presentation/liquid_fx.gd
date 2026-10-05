class_name LiquidFX
extends Node3D
## 카툰 액체 튐: 코드로 만든 시트 애니메이션(tools/fx/liquid_sheets.py → assets/vfx/liquid/)을 3D 판 메시에 입혀 흩뿌린다.
## 시트는 색을 굽지 않은 채널 장(R 두께 · G 명암 · B 하이라이트)이라 팔레트만 바꿔 감염 체액·벌레 체액에 함께 쓴다.
## 셰이더가 이웃 두 프레임의 두께를 섞은 뒤 문턱으로 잘라 내므로 16프레임이어도 모양이 매끈하게 변형된다.
##
##  CROWN 부채꼴 왕관  위로 벌어지는 원뿔 벽 조각(부채꼴) 몇 장을 터진 자리에 둘러 세운다. 테가 솟고 손가락 끝이 방울로 떨어진다.
##  SHEET 날아가는 막  볼록한 타원 판. 카메라 쪽을 보며 날아가고, 막에 구멍이 뚫려 찢어진다.
##  GLOB  길쭉한 덩어리 진행 방향으로 늘인 볼록한 판 (진행 축은 고정한 채 카메라 쪽으로 돈다). 꼬리가 끊겨 방울로.
##  SPLAT 바닥 철퍽   바닥(또는 벽)에 붙은 판. 덩어리가 떨어진 자리에서 별 모양으로 퍼진다.
## 판정 없음. 게임 시간으로 흐른다 (히트스탑·슬로우모션에 같이 멈춤). 판 수 상한 MAX.

enum Kind { CROWN, SHEET, GLOB, SPLAT }

const MAX := 90
const GRAVITY := 15.0
const KIND_FILES := ["crown", "sheet", "glob", "splat"]

## 팔레트: 그림자 · 중간 · 밝은 · 하이라이트 · 얇은 막
const WINE := [Color8(58, 16, 52), Color8(126, 36, 98), Color8(184, 70, 128), Color8(255, 160, 210), Color8(64, 22, 58)]
const YELLOW := [Color8(150, 92, 10), Color8(205, 184, 22), Color8(236, 236, 92), Color8(252, 252, 190), Color8(98, 78, 22)]

static var inst: LiquidFX
static var _tex := {}
static var _mats := {}            ## "종류:팔레트 이름" → ShaderMaterial (팔레트는 이름 있는 상수만 — 캐시가 늘지 않게)
static var _fan: ArrayMesh
static var _cap: ArrayMesh
static var _flat: QuadMesh
static var _shader: Shader

var cards: Array = []             ## {n, kind, age, life, v, spin, size, axis, ground, splat_on_land, pal}


static func ensure(parent: Node) -> LiquidFX:
	if is_instance_valid(inst):
		return inst
	var l := LiquidFX.new()
	l.name = "LiquidFX"
	parent.add_child(l)
	return l


func _ready() -> void:
	inst = self


func _exit_tree() -> void:
	if inst == self:
		inst = null


# ── 재질 · 메시 ─────────────────────────────────────────

static func material(kind: int, pal_name: String) -> ShaderMaterial:
	var key := "%d:%s" % [kind, pal_name]
	if _mats.has(key):
		return _mats[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var file: String = KIND_FILES[kind]
	if not _tex.has(file):
		_tex[file] = load("res://assets/vfx/liquid/liquid_%s.png" % file)
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("sheet", _tex[file])
	var pal: Array = WINE if pal_name == "wine" else YELLOW
	for i in 5:
		m.set_shader_parameter(["c_shadow", "c_mid", "c_light", "c_hi", "c_mem"][i], pal[i])
	_mats[key] = m
	return m


## 부채꼴 왕관 벽: 각도 span 의 원뿔 조각. 아래(v=0) 반지름 r0 → 위(v=1) 반지름 r1, 높이 1. UV (u 각도, v 높이)
static func fan_mesh() -> ArrayMesh:
	if _fan:
		return _fan
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 10
	var rows := 6
	var span := deg_to_rad(110.0)
	var r0 := 0.12
	var r1 := 0.75
	for j in rows + 1:
		var v := float(j) / rows
		# 위로 갈수록 바깥으로 벌어지며 살짝 말린다
		var r := lerpf(r0, r1, v) + 0.12 * v * v
		var y := v * (1.0 - 0.15 * v * v)
		for i in seg + 1:
			var u := float(i) / seg
			var a := (u - 0.5) * span
			st.set_uv(Vector2(u, 1.0 - v))
			st.set_normal(Vector3(sin(a), 0.3, cos(a)).normalized())
			st.add_vertex(Vector3(sin(a) * r, y, cos(a) * r))
	for j in rows:
		for i in seg:
			var a := j * (seg + 1) + i
			var b := a + 1
			var c := a + seg + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	_fan = st.commit()
	return _fan


## 볼록한 판: -0.5~0.5 사각형, 가운데가 +z 로 0.18 솟는 돔 (빌보드로 돌려도 입체감이 남게). UV 0~1
static func cap_mesh() -> ArrayMesh:
	if _cap:
		return _cap
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 8
	for j in n + 1:
		for i in n + 1:
			var x := float(i) / n - 0.5
			var y := float(j) / n - 0.5
			var r2 := (x * x + y * y) * 4.0
			var z := 0.18 * maxf(0.0, 1.0 - r2)
			st.set_uv(Vector2(float(i) / n, 1.0 - float(j) / n))
			st.set_normal(Vector3(x * 0.7, y * 0.7, 1.0).normalized())
			st.add_vertex(Vector3(x, y, z))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	_cap = st.commit()
	return _cap


static func flat_mesh() -> QuadMesh:
	if _flat == null:
		_flat = QuadMesh.new()
		_flat.orientation = PlaneMesh.FACE_Y
	return _flat


# ── 내보내기 ───────────────────────────────────────────

## 터짐 한 번: 왕관 · 날아가는 막 · 덩어리 (덩어리는 떨어진 자리에 철퍽)
## at 터진 자리 · normal 바깥 방향 · size 0.2~1.4 · pal "wine"/"yellow"
static func burst(at: Vector3, normal: Vector3, size: float, pal := "wine") -> void:
	if FX.root == null:
		return
	var l := ensure(FX.root)
	var k := clampf(size, 0.2, 1.4)
	var up := normal.normalized()
	# 왕관: 터진 방향을 축으로 부채꼴 2~3장을 둘러 세운다
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var n_fan := 2
	var a0 := randf() * TAU
	for i in n_fan:
		var a := a0 + TAU * i / n_fan + randf_range(-0.3, 0.3)
		var fwd := side.rotated(up, a)
		var b := Basis(up.cross(fwd).normalized(), up, fwd).orthonormalized()
		var s := (0.55 + 0.75 * k) * randf_range(0.85, 1.15)
		l._card(Kind.CROWN, pal, Transform3D(_sb(b, Vector3(s, s * randf_range(0.8, 1.1), s)), at - up * 0.04), randf_range(0.42, 0.55) * (0.8 + k * 0.3), Vector3.ZERO)
	# 가운데 덩어리: 제자리에서 둥글게 퍼지며 구멍 뚫려 찢어지는 막 (터지는 첫 순간의 질량감)
	var core := l._card(Kind.SHEET, pal, Transform3D(Basis(), at + up * 0.12), 0.42 + k * 0.1, up * 0.6)
	if core:
		core.size = 0.6 + 0.7 * k
		core.spin = randf_range(-1.5, 1.5)
		core.grav = 0.2
	# 날아가는 막
	for i in 1 + int(k * 2.0):
		var d := (up * 1.0 + _rand_dir() * 0.9).normalized()
		if d.dot(up) < 0.15:
			d = (d + up * 0.8).normalized()
		var v := d * randf_range(2.5, 4.8) * (0.7 + k * 0.4)
		var c := l._card(Kind.SHEET, pal, Transform3D(Basis(), at + d * 0.1), randf_range(0.45, 0.65), v)
		if c:
			c.size = (0.35 + 0.5 * k) * randf_range(0.8, 1.2)
			c.spin = randf_range(-6.0, 6.0)
	# 길쭉한 덩어리 (떨어지면 철퍽)
	for i in 2 + int(k * 3.0):
		var d := (up * 0.8 + _rand_dir()).normalized()
		if d.dot(up) < 0.0:
			d = (d + up).normalized()
		var v := d * randf_range(3.5, 7.0) * (0.7 + k * 0.4)
		var c := l._card(Kind.GLOB, pal, Transform3D(Basis(), at + d * 0.08), randf_range(0.5, 0.8), v)
		if c:
			c.size = (0.22 + 0.3 * k) * randf_range(0.8, 1.2)
			c.splat_on_land = true


## 바닥(normal 면)에 철퍽 퍼지는 판 한 장
static func splat(at: Vector3, normal: Vector3, size: float, pal := "wine") -> void:
	if FX.root == null:
		return
	var l := ensure(FX.root)
	var up := normal.normalized()
	var fwd := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized().rotated(up, randf() * TAU)
	var b := Basis(up.cross(fwd).normalized(), up, fwd).orthonormalized()
	var s := clampf(size, 0.15, 1.6)
	l._card(Kind.SPLAT, pal, Transform3D(_sb(b, Vector3(s, 1, s)), at + up * 0.015), randf_range(0.5, 0.7), Vector3.ZERO)


## 기저 각 축에 배율 (자기 축 기준)
static func _sb(b: Basis, v: Vector3) -> Basis:
	return Basis(b.x * v.x, b.y * v.y, b.z * v.z)


static func _rand_dir() -> Vector3:
	var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	return v.normalized() if v.length() > 0.01 else Vector3.UP


func _card(kind: int, pal: String, xf: Transform3D, life: float, v: Vector3) -> Dictionary:
	if cards.size() >= MAX:
		var old: Dictionary = cards.pop_front()
		if is_instance_valid(old.n):
			(old.n as Node).queue_free()
	var mi := MeshInstance3D.new()
	match kind:
		Kind.CROWN: mi.mesh = fan_mesh()
		Kind.SPLAT: mi.mesh = flat_mesh()
		_: mi.mesh = cap_mesh()
	mi.material_override = material(kind, pal)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("k", 0.0)
	mi.set_instance_shader_parameter("flip", 1.0 if randf() < 0.5 else 0.0)
	add_child(mi)
	mi.global_transform = xf
	var c := {"n": mi, "kind": kind, "age": 0.0, "life": life, "v": v, "spin": 0.0, "roll": randf() * TAU,
		"size": 1.0, "splat_on_land": false, "pal": pal}
	cards.append(c)
	return c


func _physics_process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var main := Main.inst
	var i := cards.size() - 1
	while i >= 0:
		var c: Dictionary = cards[i]
		var n: MeshInstance3D = c.n
		if not is_instance_valid(n):
			cards.remove_at(i)
			i -= 1
			continue
		c.age += dt
		var k := clampf(float(c.age) / float(c.life), 0.0, 1.0)
		n.set_instance_shader_parameter("k", k)
		var kind: int = c.kind
		if kind == Kind.SHEET or kind == Kind.GLOB:
			var v: Vector3 = c.v
			v.y -= GRAVITY * float(c.get("grav", 1.0)) * dt
			v *= 1.0 - 1.4 * dt
			c.v = v
			var p := n.global_position + v * dt
			var landed := false
			if main and main.map:
				var fl := main.floor_at(p)
				if p.y <= fl + 0.02 and v.y < 0.0:
					p.y = fl + 0.02
					landed = true
			elif p.y <= 0.02 and v.y < 0.0:
				p.y = 0.02
				landed = true
			n.global_transform = _facing(kind, c, p, v, cam, dt)
			if landed:
				if c.splat_on_land:
					LiquidFX.splat(Vector3(p.x, p.y - 0.02, p.z), Vector3.UP, float(c.size) * 2.2, c.pal)
				n.queue_free()
				cards.remove_at(i)
				i -= 1
				continue
		if k >= 1.0:
			n.queue_free()
			cards.remove_at(i)
		i -= 1


## 막·덩어리 판의 방향: 막은 카메라를 보며 돈다 · 덩어리는 진행 축(+x)을 고정한 채 카메라 쪽으로 돈다
func _facing(kind: int, c: Dictionary, p: Vector3, v: Vector3, cam: Camera3D, dt: float) -> Transform3D:
	var to_cam := (cam.global_position - p).normalized() if cam else Vector3.BACK
	var s: float = c.size
	if kind == Kind.SHEET:
		c.roll = float(c.roll) + float(c.spin) * dt
		var z := to_cam
		var x := Vector3.UP.cross(z).normalized()
		if x.length() < 0.1:
			x = Vector3.RIGHT
		var y := z.cross(x)
		var b := Basis(x, y, z).rotated(z, float(c.roll))
		return Transform3D(_sb(b, Vector3(s, s * 0.85, s)), p)
	var ax := v.normalized() if v.length() > 0.2 else Vector3.RIGHT
	var z2 := (to_cam - ax * to_cam.dot(ax)).normalized()
	if z2.length() < 0.1:
		z2 = Vector3.UP
	var y2 := z2.cross(ax).normalized()
	var stretch := 1.0 + minf(v.length() * 0.06, 0.6)
	return Transform3D(Basis(ax * s * 1.6 * stretch, y2 * s * 0.8, z2 * s), p)


## 시트 칠: 이웃 두 프레임 두께를 섞어 자르고(매끈한 변형), 명암 3단 + 얇은 막 반투명 + 젖은 하이라이트.
## 장면 조명에 묻히도록 해의 밝기만큼은 따라간다 (light 함수에서 해 방향 무관, 세기만 · 레이저 암전 때 같이 어두워짐)
const SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded, shadows_disabled;
uniform sampler2D sheet : filter_linear, repeat_disable;     // 채널 데이터 (sRGB 변환 없이)
uniform vec3 c_shadow : source_color;
uniform vec3 c_mid : source_color;
uniform vec3 c_light : source_color;
uniform vec3 c_hi : source_color;
uniform vec3 c_mem : source_color;
uniform float cut = 0.035;
uniform float lum = 0.95;
instance uniform float k = 0.0;
instance uniform float flip = 0.0;
vec4 frame_at(vec2 uv, float f) {
	vec2 cell = vec2(mod(f, 4.0), floor(f / 4.0));
	vec2 p = (cell + clamp(uv, vec2(0.008), vec2(0.992))) / 4.0;
	return texture(sheet, p);
}
void fragment() {
	vec2 uv = UV;
	if (flip > 0.5) uv.x = 1.0 - uv.x;
	float f = clamp(k, 0.0, 1.0) * 15.0;
	float f0 = floor(f);
	float w = f - f0;
	vec4 a = frame_at(uv, f0);
	vec4 b = frame_at(uv, min(f0 + 1.0, 15.0));
	vec4 s = mix(a, b, w);
	float th = s.r;
	if (th < cut) discard;
	float g = s.g;
	vec3 col = g < 0.32 ? c_shadow : (g < 0.74 ? c_mid : c_light);
	float mem = 1.0 - smoothstep(0.06, 0.11, th);
	col = mix(col, c_mem, mem);
	col = mix(col, c_hi, smoothstep(0.35, 0.6, s.b));
	ALBEDO = col * lum;
	ALPHA = 1.0 - mem * 0.35;
}
"""

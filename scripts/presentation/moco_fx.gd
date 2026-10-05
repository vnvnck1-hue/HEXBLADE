class_name MocoFX
extends MeshInstance3D
## mo.co 무드 타격 연출 (docs/moco-vfx-claude-handoff.md · 적용 기록 docs/moco-vfx-claude.md). 판정과 무관한 연출 전용.
##  - 타격 버스트: 비대칭 별 심지(흰) + 마젠타 쐐기 + 짙은 마젠타 뒷면 + 작은 민트 마름모 / 강타는 8각 별·노란 주가시·파편.
##    모든 버스트를 이 노드의 ImmediateMesh 하나에 매 프레임 다시 그린다 (노드·머티리얼이 타격마다 생기지 않고 정적 캐시도 없다).
##    카메라를 향한 판이지만 위치는 실제 접촉점 (카메라 쪽으로 PULL 만큼만 당김). 깊이 검사 유지, 그림자 없음, 조명 노드 없음.
##  - 피해 숫자 · 상태 텍스트: 땅굴크루 드릴 데미지 로그 방식 (DamageLog, docs/damage-log.md). 맞을 때마다 맞은 자리에서
##    위로 튀어 포물선으로 떨어지는 ARCO 숫자, 화면 전체 최대 20개. 같은 대상의 0.06초 안 연타는 한 숫자로 합산
##    (원본이 드릴 피해를 0.06초씩 모아 한 숫자로 띄우던 것과 같은 간격).
## 씬마다 ToonGunFX 아래에 하나 생긴다 (MocoFX.get_inst). 실행 인자 --vfx=old 면 예전 연출(HitSpark 방추)·숫자 없음.

static var on := not OS.get_cmdline_user_args().has("--vfx=old")

# ── 색 (정확한 sRGB HEX, palette_and_presets.json). 꼭짓점 색은 변환 없이 쓰이므로 선형으로 한 번만 바꿔 둔다 ──
const CORE := Color("ffffff")
const ATTACK := Color("ff3cbd")
const SHADE := Color("b72c8f")
const CRIT_ACCENT := Color("ffe45a")
const SUPPORT := Color("35eed7")
const SOFT := Color("bfffF0")
const INK := Color("25104d")
const DANGER := Color("ff5268")

# ── 시간 (초) ──
const N_CORE := 0.07
const N_SHAPE := 0.15
const N_END := 0.22
const H_CORE := 0.07
const H_SHAPE := 0.16
const H_END := 0.30
const PULL := 0.25            # 카메라 쪽으로 당기는 거리 (예전 HitSpark 0.7 → 벽 너머로 튀어나오지 않게. 0.18 은 몸에 가려짐)
const SURFACE := 0.4          # 몸 중심 쪽 접촉점을 공격이 온 쪽 표면으로 옮기는 비율 (대상 폭 × 이 값)
const MAX_BURSTS := 24        # 동시 타격 묶음 예산. 넘으면 오래된 것부터 지운다
const HDR := 1.3              # 흰 심지만 살짝 HDR (glow 문턱 1.1 을 조금 넘김)

# ── 숫자 ──
const NUM_MAX := DamageLog.MAX
const MERGE := 0.06           # 원본 drillHitInt

var _im: ImmediateMesh
var _bursts: Array = []       # Dictionary 목록
var _layer: CanvasLayer
var _log: DamageLog
var _last_hit := {}           # 대상 id → 마지막 버스트 시각 (같은 적 연사 간격)
var _cam_right := Vector3.RIGHT
var _cam_up := Vector3.UP
var _cam_pos := Vector3.ZERO

static var _shader: Shader


static func lin(c: Color) -> Color:
	return c.srgb_to_linear()


## 이 씬의 MocoFX (없으면 ToonGunFX 아래에 만든다). 연출 노드가 없는 씬이면 null
static func get_inst() -> MocoFX:
	var g := ToonGunFX.inst
	if g == null or not is_instance_valid(g) or not g.is_inside_tree():
		return null
	var n := g.get_node_or_null("MocoFX") as MocoFX
	if n == null:
		n = MocoFX.new()
		n.name = "MocoFX"
		g.add_child(n)
	return n


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_im = ImmediateMesh.new()
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0       # 판 위치가 매 프레임 바뀌므로 컬링하지 않는다 (그리는 게 없으면 표면도 없다)
	material_override = vc_material()
	_setup_layer()


static var _vc_mat: ShaderMaterial


## 꼭짓점 색(선형) · 알파로 칠하는 공용 효과 재질 (하나만 만든다). 드론 연결선·볼텍스도 쓴다
static func vc_material() -> ShaderMaterial:
	if _vc_mat == null:
		_vc_mat = ShaderMaterial.new()
		_vc_mat.shader = _vc_shader()
		_vc_mat.set_shader_parameter("hdr", HDR)
		_vc_mat.render_priority = 6
	return _vc_mat


static func _vc_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;
uniform float hdr = 1.3;
void fragment() {
	vec3 c = COLOR.rgb;
	// 흰 심지(세 채널 모두 1)만 제한된 HDR 강조. 마젠타·민트 넓은 면은 1 이하
	float w = step(0.985, min(c.r, min(c.g, c.b)));
	ALBEDO = c * mix(1.0, hdr, w);
	ALPHA = COLOR.a;
}
"""
	return _shader


func _setup_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "MocoNumbers"
	_layer.layer = 5
	add_child(_layer)
	_log = DamageLog.new()
	_log.name = "DamageLog"
	_layer.add_child(_log)


# ═══════════════════════════════════════════════════
#  타격 버스트
# ═══════════════════════════════════════════════════

## pos: 접촉점 · dir: 맞은 방향 · width: 대상 몸체 폭(m) · heavy: 강타 · k: 세기(1 이상, 크기 범위 안에서만 반영)
func hit(pos: Vector3, dir: Vector3, width: float, heavy: bool, k := 1.0, key: Object = null) -> void:
	var now := Time.get_ticks_msec() * 0.001
	if key != null:
		var id := key.get_instance_id()
		if now - float(_last_hit.get(id, -1.0)) < 0.045:
			return
		_last_hit[id] = now
		if _last_hit.size() > 64:
			_last_hit.clear()
	if _bursts.size() >= MAX_BURSTS:
		_bursts.pop_front()
	var w := clampf(width, 0.8, 2.2)       # 큰 보스도 무제한 커지지 않게
	var kk := clampf((k - 1.0) / 0.8, 0.0, 1.0)
	var dia := w * (lerpf(1.2, 1.6, kk) if heavy else lerpf(0.75, 0.9, kk))
	# 일반 적의 판정점은 몸 안쪽이라 깊이 검사에 가려진다 → 공격이 온 쪽(−dir) 표면으로 (보스는 fx_point 가 이미 겉면)
	var fd := Vector3(dir.x, 0, dir.z)
	if fd.length() > 0.01 and not (key is Enemy and (key as Enemy).is_boss):
		pos -= fd.normalized() * minf(width, 2.4) * SURFACE
	var b := {
		"pos": pos, "dir": dir, "r": dia * 0.5, "age": 0.0, "heavy": heavy,
		"core": H_CORE if heavy else N_CORE, "shape": H_SHAPE if heavy else N_SHAPE, "end": H_END if heavy else N_END,
		"spin": randf_range(-0.25, 0.25),
	}
	# 쐐기: 첫째는 맞은 방향으로 길게, 나머지는 옆·뒤로 짧게
	var wedges: Array = [[0.0, 1.0, 0.2]]
	var n_w := 4 if heavy else 3
	for i in range(1, n_w):
		var a := (TAU / n_w) * i + randf_range(-0.35, 0.35)
		wedges.append([a, randf_range(0.55, 0.78), randf_range(0.15, 0.2)])
	b.wedges = wedges
	# 별 심지: 바깥 꼭짓점 중 한두 개만 길게
	var pts := 8 if heavy else 6
	var star: Array = []
	for i in pts:
		star.append(randf_range(0.9, 1.1))
	star[0] = 1.7
	if heavy:
		star[pts >> 1] = 1.35
	b.star = star
	# 강타의 노란 주가시 1~2개
	var spikes: Array = []
	if heavy:
		spikes.append([0.0 + randf_range(-0.1, 0.1), 1.3])
		if randf() < 0.6:
			spikes.append([PI + randf_range(-0.5, 0.5), 0.85])
	b.spikes = spikes
	# 작은 조각: 일반 = 민트 마름모 3~4, 강타 = 마젠타·노랑 파편 4~6
	var bits: Array = []
	var n_b := randi_range(4, 6) if heavy else randi_range(3, 4)
	for i in n_b:
		var a := randf_range(-1.4, 1.4) if i % 2 == 0 else randf() * TAU
		var c: Color = SUPPORT
		if heavy:
			c = CRIT_ACCENT if i % 3 == 0 else ATTACK
		bits.append([a, randf_range(0.8, 1.35), randf_range(0.07, 0.1), lin(c)])
	b.bits = bits
	_bursts.append(b)


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		_cam_right = cam.global_basis.x
		_cam_up = cam.global_basis.y
		_cam_pos = cam.global_position
	_draw_bursts(dt)


func _draw_bursts(dt: float) -> void:
	_im.clear_surfaces()
	var i := 0
	while i < _bursts.size():
		var b: Dictionary = _bursts[i]
		b.age = float(b.age) + dt
		if float(b.age) >= float(b.end):
			_bursts.remove_at(i)
		else:
			i += 1
	if _bursts.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Dictionary in _bursts:
		_emit_burst(b)
	_im.surface_end()


## 화면 판 좌표(x 오른쪽, y 위, 단위 m) → 월드
func _w(c: Vector3, x: float, y: float) -> Vector3:
	return c + _cam_right * x + _cam_up * y


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	_im.surface_set_color(col)
	_im.surface_add_vertex(a)
	_im.surface_set_color(col)
	_im.surface_add_vertex(b)
	_im.surface_set_color(col)
	_im.surface_add_vertex(c)


func _emit_burst(b: Dictionary) -> void:
	var age: float = b.age
	var r: float = b.r
	var p: Vector3 = b.pos
	var c := p + (_cam_pos - p).normalized() * PULL
	# 맞은 방향을 화면 판에 투영한 각도 (카메라 쪽/반대쪽으로만 맞으면 옆으로)
	var d: Vector3 = b.dir
	var sx := d.dot(_cam_right)
	var sy := d.dot(_cam_up)
	# 긴 가시는 표면 밖(공격이 온 쪽)으로 튄다 — 진행 방향(몸 속)으로 뻗으면 깊이 검사에 가려져 안 보인다
	var th := (atan2(sy, sx) + PI) if absf(sx) + absf(sy) > 0.05 else 0.0
	th += float(b.spin)
	var shape_t: float = b.shape
	var end_t: float = b.end
	var core_t: float = b.core
	# 펼침: 50ms 안에 다 펴지고, 큰 면 시간이 지나면 가늘어지며 사라진다
	var grow := 1.0 - pow(1.0 - minf(age / 0.05, 1.0), 3.0)
	var thin := 1.0 if age < shape_t else clampf(1.0 - (age - shape_t) / (end_t - shape_t), 0.0, 1.0)
	var fade := thin
	# 1) 짙은 마젠타 뒷면 쐐기 → 2) 마젠타 쐐기
	for layer in 2:
		var col := lin(SHADE) if layer == 0 else lin(ATTACK)
		var lk := 1.18 if layer == 0 else 1.0
		col.a = (0.9 if layer == 0 else 1.0) * fade
		for wv: Array in b.wedges:
			var a: float = th + float(wv[0])
			var L: float = r * float(wv[1]) * grow * lk * lerpf(0.75, 1.0, thin)
			var hw: float = r * float(wv[2]) * lk * thin
			var base := r * 0.12
			var ca := cos(a)
			var sa := sin(a)
			var tip := _w(c, ca * L, sa * L)
			var l0 := _w(c, ca * base - sa * hw, sa * base + ca * hw)
			var r0 := _w(c, ca * base + sa * hw, sa * base - ca * hw)
			var back := _w(c, -ca * base * 0.5, -sa * base * 0.5)
			_tri(back, l0, tip, col)
			_tri(back, tip, r0, col)
	# 3) 강타 노란 주가시
	for sp: Array in b.spikes:
		var a: float = th + float(sp[0])
		var L: float = r * float(sp[1]) * grow * lerpf(0.8, 1.0, thin)
		var hw := r * 0.07 * thin
		var col := lin(CRIT_ACCENT)
		col.a = fade
		var ca := cos(a)
		var sa := sin(a)
		_tri(_w(c, -ca * r * 0.05 - sa * hw, -sa * r * 0.05 + ca * hw), _w(c, ca * L, sa * L), _w(c, -ca * r * 0.05 + sa * hw, -sa * r * 0.05 - ca * hw), col)
	# 4) 흰 별 심지: 20ms 에 톡 커졌다가 심지 시간에 줄어 사라짐 (전체 면적의 20~30% 이하)
	if age < core_t:
		var ck := minf(age / 0.02, 1.0) * (1.0 - smoothstep(core_t * 0.45, core_t, age))
		var outer := r * (0.36 if b.heavy else 0.3) * ck
		var inner := outer * 0.42
		var st: Array = b.star
		var n := st.size()
		var cw := lin(CORE)
		for k in n:
			var a0 := th + TAU * k / n
			var a1 := th + TAU * (k + 0.5) / n
			var a2 := th + TAU * (k + 1) / n
			var ro := outer * float(st[k])
			var tip := _w(c, cos(a0) * ro, sin(a0) * ro)
			var m1 := _w(c, cos(a1) * inner, sin(a1) * inner)
			var m0 := _w(c, cos(a0 - PI / n) * inner, sin(a0 - PI / n) * inner)
			_tri(c, m0, tip, cw)
			_tri(c, tip, m1, cw)
	# 5) 작은 조각: 바깥으로 튀며 작아진다
	var fly := 1.0 - pow(1.0 - clampf(age / end_t, 0.0, 1.0), 2.0)
	for bt: Array in b.bits:
		var a: float = th + float(bt[0])
		var dist: float = r * (0.35 + float(bt[1]) * fly)
		var s: float = r * float(bt[2]) * (1.0 - fly * 0.6)
		var col: Color = bt[3]
		col.a = clampf(1.0 - fly * fly, 0.0, 1.0)
		var ca := cos(a)
		var sa := sin(a)
		var m := _w(c, ca * dist, sa * dist)
		# 날아가는 방향으로 늘어난 마름모
		var f := _cam_right * ca + _cam_up * sa
		var sd := _cam_right * -sa + _cam_up * ca
		_tri(m + f * s * 1.6, m + sd * s * 0.7, m - f * s * 1.0, col)
		_tri(m + f * s * 1.6, m - f * s * 1.0, m - sd * s * 0.7, col)


# ═══════════════════════════════════════════════════
#  피해 숫자 · 상태 텍스트
# ═══════════════════════════════════════════════════

## 확정된 피해 표시 (적·보스의 피해 확정 경로에서 한 번만 부른다). 예전 연출이면 아무것도 안 한다
static func report(target: Node3D, amount: int, heavy: bool, at := Vector3.ZERO) -> void:
	ComboMeter.hit(amount, heavy)     # 타격 콤보 (화면 왼쪽) — 예전 연출이어도 센다
	if not on:
		return
	var m := get_inst()
	if m:
		m.damage(target, amount, heavy, at)


## 확정된 피해 하나 (Enemy.take_hit 등에서 한 번만). heavy = 강타 분류(노란 큰 숫자)
func damage(target: Node3D, amount: int, heavy: bool, at := Vector3.ZERO) -> void:
	if amount <= 0 or not is_instance_valid(target):
		return
	var now := Time.get_ticks_msec() * 0.001
	# 합산: 같은 대상에 방금(0.06초 안) 띄운 숫자가 있으면 거기에 더한다 (한 프레임 산탄·지속 레이저가 숫자를 도배하지 않게)
	for e: Dictionary in _log.entries:
		if not e.status and e.target != null and e.target.get_ref() == target and now - float(e.born) < MERGE:
			e.value = int(e.value) + amount
			e.text = str(e.value)
			_log.bump(e)
			if heavy and not e.big:
				e.big = true
				e.col = DamageLog.heat_color(maxf(float(e.heat), DamageLog.HEAT_BIG_MIN))
				e.pop = minf(DamageLog.POP_BIG + DamageLog.HEAT_POP * float(e.heat), DamageLog.POP_MAX)
				e.life = DamageLog.LIFE_BIG + DamageLog.HEAT_LIFE * float(e.heat)
			return
	_log.spawn(_anchor(target, at), amount, heavy, target)


## 실제 상태 변화 진입 때 한 번 (예: 경직 진입 STUN!)
func status(target: Node3D, text: String) -> void:
	if not is_instance_valid(target):
		return
	_log.spawn_status(_anchor(target, Vector3.ZERO), text, SUPPORT, target)


## 숫자가 생기는 월드 점: 대상 머리 위(체력바 높이). 맞은 자리가 있으면 그 좌우 위치를 따른다.
## 몸 높이에서 띄우면 피격 섬광·버스트에 묻혀서 머리 위에서 띄운다 (docs/damage-log.md)
func _anchor(target: Node3D, at: Vector3) -> Vector3:
	var base := target.global_position
	var top := 2.0
	if target is Enemy:
		var en := target as Enemy
		top = en.hp_bar_y
		if en.is_boss and at != Vector3.ZERO:
			return at + Vector3(0, 1.4, 0)        # 큰 보스는 맞은 자리 위
	if at != Vector3.ZERO and Vector2(at.x - base.x, at.z - base.z).length() < 2.0:
		base = Vector3(lerpf(base.x, at.x, 0.5), base.y, lerpf(base.z, at.z, 0.5))
	return base + Vector3(0, top, 0)


## 검사용: 지금 그려지는 버스트 수 · 보이는 숫자 수
func burst_count() -> int:
	return _bursts.size()


func live_numbers() -> Array:
	var out: Array = []
	for e: Dictionary in _log.entries:
		out.append({"kind": "status" if e.status else ("heavy" if e.big else "normal"), "text": e.text})
	return out

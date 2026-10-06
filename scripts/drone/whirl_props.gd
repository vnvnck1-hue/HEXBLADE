class_name WhirlProps
extends Node3D
## Q 합체 휠윈드 + 민트 메이드: 컷인에 나온 메이드 소품(찻잔 · 주전자 · 케이크 · 마카롱 …)이 회오리에 휘말려
## 몸 둘레를 빙글빙글 돌다가 사방으로 내팽개쳐진다 — 캐릭터성을 살린 유머 연출 (판정 없음, 연출 전용).
## 한 소품의 일생: 회오리 안쪽에서 뿅 튀어나옴 → 나선을 그리며 바깥으로 돌며 떠오름(ORBIT) → 접선 방향으로 휙 날아감(FLING) →
##   바닥에 통 · 통 튀며(찌그러짐 · 도자기 '팅' 소리) 데굴데굴 → 잠깐 누워 있다 → 금빛 별 뿅과 함께 쏙 사라짐.
## 금빛 별(가산 혼합)도 회오리 둘레에 흩날린다. 모양은 카메라를 보는 판(빌보드) + 판 안 회전(roll)이라 빙글빙글 구른다.
## 2차(사용자): 개수 · 크기 절반, 수명 30%, 소품마다 바닥 그림자(그림 모양 그대로 눕힘), 반투명 판이 깊이를 써서 기체가 네모로
##   뚫려 보이던 버그 수정(depth_draw_never), 별 후광 좁게.
## 휠윈드가 끝나도 남은 소품은 제 일생을 마치고 사라지며, 모두 사라지면 노드도 지운다.

const PROP_WORLD := 3.0          ## 컷인 소품 크기(×side) → 월드 m 배율: 0.14~0.26 → 0.42~0.78m (2차: 사용자 요청으로 절반, 메카 1.8m)
const EMIT_EVERY := 0.14         ## 소품 내보내는 간격 (초, 휠윈드 2초 동안 약 14개 — 2차: 절반)
const STAR_EVERY := 0.035
const MAX_PROPS := 20
const ORBIT_T := Vector2(0.07, 0.18)     ## 2차: 수명 30% (예전 0.22~0.6)
const ORBIT_W := Vector2(1.5, 2.6)        ## 회전 (바퀴/초)
const ORBIT_R := Vector2(2.0, 3.3)        ## 회오리 이펙트 바깥쪽을 돈다
const GRAVITY := 30.0                    ## 짧게 날고 떨어지게 (수명 30%)
const BOUNCE := 0.5
const REST := Vector2(0.08, 0.2)          ## 바닥에 멈춘 뒤 누워 있는 시간
const LIFE_MAX := 0.95                   ## 이보다 오래 날면 그 자리에서 쏙 (예전 3.2)

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D tex : source_color, filter_linear_mipmap;
instance uniform float roll = 0.0;
instance uniform vec2 sc = vec2(1.0);
void vertex() {
	vec2 p = VERTEX.xy * sc;
	float c = cos(roll);
	float s = sin(roll);
	VERTEX = vec3(c * p.x - s * p.y, s * p.x + c * p.y, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb;
	ALPHA = smoothstep(0.35, 0.6, t.a);
}
"""

## 바닥 그림자: 소품 그림 모양(알파)을 바닥에 눕혀 짙은 남보라로 — 높이 뜰수록 옅고 크게, 해 반대(오른쪽 아래)로 밀림
const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D tex : source_color, filter_linear_mipmap;
instance uniform float roll = 0.0;
instance uniform vec2 sc = vec2(1.0);
instance uniform float dark = 0.4;
void vertex() {
	vec2 p = VERTEX.xy * sc;
	float c = cos(roll);
	float s = sin(roll);
	VERTEX = vec3(c * p.x - s * p.y, 0.0, -(s * p.x + c * p.y));
}
void fragment() {
	ALBEDO = vec3(0.05, 0.04, 0.12);
	ALPHA = smoothstep(0.3, 0.6, texture(tex, UV).a) * dark;
}
"""

## 가산 별: 넓은 금빛 후광 + 가운데 별 그림(뜨겁게) — 에디티브라 겹칠수록 번쩍인다
const STAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform sampler2D tex : source_color, filter_linear_mipmap;
instance uniform float roll = 0.0;
instance uniform float size = 1.0;
instance uniform float glow = 1.0;
void vertex() {
	vec2 p = VERTEX.xy * size;
	float c = cos(roll);
	float s = sin(roll);
	VERTEX = vec3(c * p.x - s * p.y, s * p.x + c * p.y, 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 q = UV - 0.5;
	float halo = exp(-dot(q, q) * 55.0);
	vec4 st = texture(tex, clamp(q * 1.45 + 0.5, 0.0, 1.0));
	vec3 col = vec3(1.0, 0.78, 0.3) * halo * 0.55 + mix(st.rgb, vec3(1.0, 0.97, 0.82), 0.45) * st.a * 1.35;
	ALBEDO = col * glow;
	ALPHA = 1.0;
}
"""

static var _quad: QuadMesh
static var _shader: Shader
static var _star_shader: Shader
static var _shadow_shader: Shader
static var _mats := {}            ## 텍스처 → 재질 (소품 10종 + 별 1종이라 유한)

var player: Node3D
var cfgs: Array = []
var star_tex: Texture2D
var dur := 2.0
var t := 0.0
var _emit := 0.0
var _star := 0.0
var _ang := 0.0
var items: Array = []
var stars: Array = []
var emitted := 0                 ## 확인용
var flung := 0
var bounced := 0
var max_dist := 0.0              ## 확인용: 소품이 플레이어에서 가장 멀리 간 거리 (m)
var _tink_cd := 0.0
var shadowed := 0               ## 확인용: 그림자를 가진 소품 수 (최대)


static func attach(scene: Node, who: Node3D, prop_cfgs: Array, sparkle: Texture2D, duration: float) -> WhirlProps:
	if prop_cfgs.is_empty():
		return null
	var w := WhirlProps.new()
	w.player = who
	w.cfgs = prop_cfgs
	w.star_tex = sparkle
	w.dur = duration
	w.top_level = true
	scene.add_child(w)
	return w


func _ready() -> void:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
		_shader = Shader.new()
		_shader.code = SHADER
		_star_shader = Shader.new()
		_star_shader.code = STAR_SHADER
		_shadow_shader = Shader.new()
		_shadow_shader.code = SHADOW_SHADER
	_ang = randf() * TAU
	# 첫 순간: 한꺼번에 여럿 튀어나오며 시작 (와르르)
	for i in 3:
		_spawn(true)


## kind: 0 소품 · 1 가산 별 · 2 바닥 그림자
func _mat(tex: Texture2D, kind := 0) -> ShaderMaterial:
	var key: String = tex.resource_path + ["", "#star", "#shadow"][kind]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = [_shader, _star_shader, _shadow_shader][kind]
		m.set_shader_parameter("tex", tex)
		m.render_priority = [11, 12, 10][kind]   # 회오리 고리(반투명) 위에 그려 가려지지 않게 · 그림자는 그 아래
		_mats[key] = m
	return _mats[key]


func _mesh(mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _center() -> Vector3:
	if is_instance_valid(player):
		return player.global_position
	return global_position


func _spawn(burst := false) -> void:
	if items.size() >= MAX_PROPS:
		return
	var pd: Dictionary = cfgs[randi() % cfgs.size()]
	var tex: Texture2D = pd.tex
	var side := float(pd.size) * PROP_WORLD * float(tex.get_width()) / float(pd.dim)   ## 판 한 변 (그림 긴 변이 size·PROP_WORLD m)
	var mi := _mesh(_mat(tex))
	var sh := _mesh(_mat(tex, 2))
	mi.visible = false          # 첫 _step 에서 자리를 잡은 뒤 보인다 (원점에 한 프레임 보이지 않게)
	sh.visible = false
	var a := _ang + randf_range(-0.6, 0.6) + (randf() * TAU if burst else 0.0)
	var it := {
		"node": mi, "shadow": sh, "side": side, "phase": 0, "age": 0.0,
		"a": a, "r": randf_range(0.8, 1.3), "h": randf_range(0.6, 1.3),
		"w": TAU * randf_range(ORBIT_W.x, ORBIT_W.y), "r_to": randf_range(ORBIT_R.x, ORBIT_R.y),
		"orbit": randf_range(ORBIT_T.x, ORBIT_T.y) * (0.6 if burst else 1.0),
		"pos": Vector3.ZERO, "vel": Vector3.ZERO,
		"roll": randf() * TAU, "roll_v": randf_range(6.0, 14.0) * (1.0 if randf() < 0.7 else -1.0),
		"sq": 0.0, "pop": 0.0, "rest": randf_range(REST.x, REST.y), "hops": 0,
		"wob": randf() * TAU,
	}
	items.append(it)
	emitted += 1
	_place(it)


func _place(it: Dictionary) -> void:
	var c := _center()
	it.pos = c + Vector3(cos(float(it.a)) * float(it.r), float(it.h), sin(float(it.a)) * float(it.r))


func _process(dt: float) -> void:
	if dt <= 0.0:
		return
	t += dt
	_tink_cd -= dt
	var whirling := t < dur
	if whirling:
		_ang += dt * TAU * 3.0
		_emit += dt
		while _emit >= EMIT_EVERY:
			_emit -= EMIT_EVERY
			_spawn()
		_star += dt
		while _star >= STAR_EVERY:
			_star -= STAR_EVERY
			_new_star(_center() + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.8, 2.6) + Vector3(0, randf_range(0.4, 2.0), 0),
				Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)) * 0.8)
	var c := _center()
	var i := items.size() - 1
	while i >= 0:
		var it: Dictionary = items[i]
		if not _step(it, dt, c, whirling):
			(it.node as Node).queue_free()
			(it.shadow as Node).queue_free()
			items.remove_at(i)
		i -= 1
	_update_stars(dt)
	if not whirling and items.is_empty() and stars.is_empty():
		queue_free()


## 소품 한 개 한 틱. false 면 끝
func _step(it: Dictionary, dt: float, c: Vector3, whirling: bool) -> bool:
	it.age = float(it.age) + dt
	var ph := int(it.phase)
	var pos: Vector3 = it.pos
	if ph == 0:
		# ORBIT: 나선을 그리며 바깥 · 위로. 휠윈드가 끝나면 바로 내팽개침
		var k := clampf(float(it.age) / float(it.orbit), 0.0, 1.0)
		it.a = float(it.a) + float(it.w) * dt
		it.r = lerpf(float(it.r), float(it.r_to), minf(1.0, dt * 6.0))
		it.h = float(it.h) + dt * 1.6
		var bob := sin(float(it.age) * 9.0 + float(it.wob)) * 0.12
		pos = c + Vector3(cos(float(it.a)) * float(it.r), float(it.h) + bob, sin(float(it.a)) * float(it.r))
		if k >= 1.0 or not whirling:
			# FLING: 접선(회전 방향) + 바깥 + 위
			var out := Vector3(cos(float(it.a)), 0, sin(float(it.a)))
			var tg := Vector3(-sin(float(it.a)), 0, cos(float(it.a)))
			var sp := minf(float(it.w) * float(it.r) * 0.3, 4.5)
			it.vel = tg * sp + out * randf_range(1.2, 3.2) + Vector3(0, randf_range(4.5, 7.5), 0)
			it.roll_v = float(it.roll_v) * 1.6
			it.phase = 1
			flung += 1
	elif ph == 1:
		# 날아감 · 튐
		var v: Vector3 = it.vel
		v.y -= GRAVITY * dt
		v.x *= exp(-0.8 * dt)
		v.z *= exp(-0.8 * dt)
		pos += v * dt
		var rad := float(it.side) * 0.3
		var gy := Main.gy(pos) + rad
		if pos.y < gy and v.y < 0.0:
			pos.y = gy
			it.hops = int(it.hops) + 1
			bounced += 1
			it.sq = 1.0
			if absf(v.y) < 3.0 or int(it.hops) >= 3:
				v = Vector3.ZERO
				it.phase = 2
				it.age = 0.0
			else:
				v.y = -v.y * BOUNCE
				v.x *= 0.7
				v.z *= 0.7
				it.roll_v = -float(it.roll_v) * randf_range(0.5, 0.9)   # 툭 부딪히면 반대로 구른다
			if _tink_cd <= 0.0:
				_tink_cd = 0.06
				var snd := Sfx.play("tink", 0.0, -14.0)
				if snd:
					snd.pitch_scale = randf_range(0.8, 1.6)
		it.vel = v
		it.roll_v = float(it.roll_v) * exp(-0.6 * dt)
	else:
		# 누워 있다가 쏙
		it.roll_v = float(it.roll_v) * exp(-6.0 * dt)
		if float(it.age) > float(it.rest):
			it.pop = float(it.pop) + dt / 0.08
			if float(it.pop) >= 1.0:
				_new_star(pos + Vector3(0, 0.15, 0), Vector3(0, 1.4, 0), 0.8)
				return false
	if float(it.age) > LIFE_MAX and ph < 2:
		it.phase = 2
		it.age = 0.0
		it.rest = 0.0          # 너무 오래 날면 그 자리에서 바로 쏙
	it.pos = pos
	max_dist = maxf(max_dist, Vector2(pos.x - c.x, pos.z - c.z).length())
	it.roll = float(it.roll) + float(it.roll_v) * dt
	it.sq = maxf(0.0, float(it.sq) - dt * 6.0)
	# 크기: 뿅 커져 나옴(넘침) · 튈 때 납작 · 사라질 때 살짝 부풀었다 쏙
	var grow := _back_out(clampf(float(it.age) / 0.14, 0.0, 1.0)) if ph == 0 else 1.0
	var pk := float(it.pop)
	var vanish := 1.0 + 0.25 * sin(pk * PI) - pk if pk > 0.0 else 1.0
	var sq := float(it.sq)
	var s := float(it.side) * maxf(grow, 0.0) * maxf(vanish, 0.0)
	var mi: MeshInstance3D = it.node
	mi.global_position = pos
	mi.set_instance_shader_parameter("roll", it.roll)
	mi.set_instance_shader_parameter("sc", Vector2(s * (1.0 + 0.3 * sq), s * (1.0 - 0.28 * sq)))
	# 바닥 그림자: 바로 아래 바닥에 같은 모양 — 높이 뜰수록 옅어지고 조금 커지며 오른쪽 아래로 밀린다, 닿으면 짙고 또렷
	var g := Main.gy(pos)
	var hgt := maxf(pos.y - g, 0.0)
	var shn: MeshInstance3D = it.shadow
	shn.global_position = Vector3(pos.x + hgt * 0.3, g + 0.03, pos.z + hgt * 0.15)
	var ss := s * (1.0 + hgt * 0.12)
	shn.set_instance_shader_parameter("roll", it.roll)
	shn.set_instance_shader_parameter("sc", Vector2(ss * (1.0 + 0.3 * sq), ss * (1.0 - 0.28 * sq)))
	mi.visible = true
	shn.visible = true
	shn.set_instance_shader_parameter("dark", 0.5 * clampf(1.0 - hgt / 4.5, 0.2, 1.0))
	shadowed = maxi(shadowed, items.size())
	return true


static func _back_out(x: float, k := 2.4) -> float:
	var v := x - 1.0
	return 1.0 + (k + 1.0) * v * v * v + k * v * v


func _new_star(pos: Vector3, vel: Vector3, big := 1.0) -> void:
	if star_tex == null or stars.size() >= 60:
		return
	var mi := _mesh(_mat(star_tex, 1))
	stars.append({"node": mi, "pos": pos, "vel": vel, "age": 0.0, "life": randf_range(0.6, 1.0),
		"size": randf_range(0.7, 1.15) * big, "roll": randf() * TAU, "spin": randf_range(-1.5, 1.5),
		"tw": randf_range(8.0, 13.0), "ph": randf() * TAU})


func _update_stars(dt: float) -> void:
	var i := stars.size() - 1
	while i >= 0:
		var s: Dictionary = stars[i]
		s.age = float(s.age) + dt
		var k := float(s.age) / float(s.life)
		if k >= 1.0:
			(s.node as Node).queue_free()
			stars.remove_at(i)
			i -= 1
			continue
		s.vel = Vector3(s.vel) * exp(-2.5 * dt)
		s.pos = Vector3(s.pos) + Vector3(s.vel) * dt
		var grow := maxf(_back_out(clampf(float(s.age) / 0.12, 0.0, 1.0)), 0.0) * (1.0 - smoothstep(0.65, 1.0, k))
		var tw := 0.5 + 0.5 * sin(float(s.age) * float(s.tw) + float(s.ph))
		var mi: MeshInstance3D = s.node
		mi.global_position = s.pos
		mi.set_instance_shader_parameter("roll", float(s.roll) + float(s.spin) * float(s.age))
		mi.set_instance_shader_parameter("size", float(s.size) * grow)
		mi.set_instance_shader_parameter("glow", 1.0 + 0.6 * tw + 1.2 * pow(tw, 10.0))
		i -= 1

class_name LancasterFX
extends RefCounted
## LANCASTER 보스 전용 시각 효과와 투사체. 컨셉 시트(PURGE FIRE · CLOSE PURGE · AREA LOCKDOWN · THREAT & MOTION)의
## 노란 예광탄 · 붉은 표적 원 · 주황 경고 화살표 · 증기 · 먼지 고리를 코드로 만든다.
##
##  Tracer        개틀링 예광탄 (노란 심 + 주황 꼬리, 벽에 튀는 불꽃). 플레이어에 닿으면 1 피해 (대시 무적이면 그냥 지나간다)
##  Mortar        보안 포드 박격탄: 포물선으로 날아가 표적 원에 떨어져 폭발 (원 안 1 피해)
##  warn_disc     바닥 경고 원 (채워지는 진행도 · 회전 빗금 · 바깥 테). 붉은 위험 / 주황 예고
##  warn_fan      부채꼴 경고 (휩쓸기 사격 예고)
##  arc_lines     광폭화 전류 (짧게 번쩍이는 지그재그 선)
##  sight         조준 레이저 (붉은 가는 선, 끝에 점)

const TRACER_CORE := Color(1.0, 0.9, 0.45)
const TRACER_TAIL := Color(1.0, 0.5, 0.12)
const DANGER := Color(1.0, 0.18, 0.12)
const HAZARD := Color(1.0, 0.55, 0.12)

static var _tracer_mesh: BoxMesh
static var _shell_mesh: CapsuleMesh
static var _disc_mesh: QuadMesh
static var _disc_mat: ShaderMaterial
static var _fan_mat: ShaderMaterial
static var _line_mat: StandardMaterial3D
static var _smear_mat: ShaderMaterial


static func _shared() -> void:
	if _tracer_mesh:
		return
	_tracer_mesh = BoxMesh.new()
	_tracer_mesh.size = Vector3.ONE
	_shell_mesh = CapsuleMesh.new()
	_shell_mesh.radius = 0.5
	_shell_mesh.height = 2.2
	_shell_mesh.radial_segments = 8
	_shell_mesh.rings = 2
	_disc_mesh = QuadMesh.new()
	_disc_mesh.size = Vector2.ONE
	_disc_mesh.orientation = PlaneMesh.FACE_Y
	var sh := Shader.new()
	sh.code = DISC_SHADER
	_disc_mat = ShaderMaterial.new()
	_disc_mat.shader = sh
	var fs := Shader.new()
	fs.code = FAN_SHADER
	_fan_mat = ShaderMaterial.new()
	_fan_mat.shader = fs
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_line_mat.no_depth_test = false
	_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


# ── 바닥 경고 ───────────────────────────────────────────

## 바닥 경고 원. progress 0→1 로 안쪽이 차오르고 1 에 가까울수록 깜빡인다
static func warn_disc(pos: Vector3, r: float, c := DANGER) -> MeshInstance3D:
	_shared()
	var mi := MeshInstance3D.new()
	mi.mesh = _disc_mesh
	mi.material_override = _disc_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("progress", 0.0)
	FX.root.add_child(mi)
	mi.global_position = Vector3(pos.x, Main.gy(pos) + 0.06, pos.z)
	mi.scale = Vector3(r * 2.0, 1, r * 2.0)
	return mi


static func set_warn(mi: MeshInstance3D, k: float) -> void:
	if is_instance_valid(mi):
		mi.set_instance_shader_parameter("progress", clampf(k, 0.0, 1.0))


## 부채꼴 경고: pos 에서 yaw 방향(0 = -Z)으로 반각 half, 길이 r
static func warn_fan(pos: Vector3, yaw: float, half: float, r: float) -> MeshInstance3D:
	_shared()
	var mi := MeshInstance3D.new()
	mi.mesh = _disc_mesh
	mi.material_override = _fan_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("half", half)
	mi.set_instance_shader_parameter("progress", 0.0)
	FX.root.add_child(mi)
	mi.global_position = Vector3(pos.x, Main.gy(pos) + 0.07, pos.z)
	mi.rotation.y = yaw
	mi.scale = Vector3(r * 2.0, 1, r * 2.0)
	return mi


## 사라지며 지우기 (짧게 하얗게 번쩍인 뒤 옅어진다)
static func clear_warn(mi: MeshInstance3D, flash := true) -> void:
	if not is_instance_valid(mi):
		return
	if flash:
		mi.set_instance_shader_parameter("progress", 1.0)
		mi.set_instance_shader_parameter("fade", 1.0)
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, 0.22)
		tw.tween_callback(mi.queue_free)
	else:
		mi.queue_free()


# ── 조준 레이저 ─────────────────────────────────────────

static func sight() -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 1.0)
	var mi := Pal.flat_mesh(bm, Color(1.0, 0.16, 0.12), 2.4)
	mi.visible = false
	return mi


static func aim_sight(mi: MeshInstance3D, from: Vector3, to: Vector3, k: float) -> void:
	if not is_instance_valid(mi):
		return
	var d := to - from
	var l := d.length()
	if l < 0.2 or k <= 0.0:
		mi.visible = false
		return
	mi.visible = true
	mi.global_transform = Transform3D(Basis.looking_at(d / l, Vector3.UP) * Basis.from_scale(Vector3(0.6 + 0.8 * k, 0.6 + 0.8 * k, l)), from + d * 0.5)


# ── 연기 · 증기 · 먼지 ─────────────────────────────────

## FX.puffs 색 4개 = 밝은 둘(시작) + 어두운 둘(사라질 때)
const STEAM_C: Array[Color] = [Color(0.97, 0.98, 1.0), Color(0.88, 0.9, 0.96), Color(0.72, 0.74, 0.82), Color(0.62, 0.64, 0.74)]
const SMOKE_C: Array[Color] = [Color(0.5, 0.48, 0.54), Color(0.4, 0.38, 0.44), Color(0.24, 0.22, 0.27), Color(0.18, 0.17, 0.21)]
const DUST_C: Array[Color] = [Color(0.86, 0.84, 0.9), Color(0.74, 0.72, 0.8), Color(0.55, 0.53, 0.62), Color(0.48, 0.46, 0.55)]


static func steam(pos: Vector3, k := 1.0) -> void:
	FX.puffs(pos, int(2 + 3 * k), STEAM_C, 0.35 * k, 0.55 * k, 1.1)


static func smoke(pos: Vector3, k := 1.0) -> void:
	FX.puffs(pos, int(2 + 2 * k), SMOKE_C, 0.3 * k, 0.6 * k, 1.4)


## 발밑 먼지 고리 (디딤 · 착지 · 밟기)
static func dust_ring(pos: Vector3, r: float, n: int) -> void:
	for i in n:
		var a := TAU * i / n + randf() * 0.3
		var d := Vector3(cos(a), 0, sin(a))
		FX.puffs(pos + d * r + Vector3(0, 0.15, 0), 1, DUST_C, 0.25, 0.5 + minf(r, 4.0) * 0.12, 0.7)


## 광폭화 전류: 몸 둘레에 짧게 번쩍이는 지그재그 선
static func arc_lines(center: Vector3, r: float, count: int, c := Color(1.0, 0.55, 0.2)) -> void:
	_shared()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	for k in count:
		var a := randf() * TAU
		var p := center + Vector3(cos(a) * r, randf_range(-0.8, 0.9) * r, sin(a) * r)
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var segs := 5
		for s in segs:
			var q := p + dir * 0.18 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.12
			im.surface_set_color(c * 2.4)
			im.surface_add_vertex(p)
			im.surface_set_color(Color(1, 0.95, 0.8) * 2.0)
			im.surface_add_vertex(q)
			p = q
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	FX.root.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_interval(0.07)
	tw.tween_callback(mi.queue_free)


## 임팩트 스윙의 금빛 잔상 호: 광선검 콤보의 초승달 섬광과 같은 메시 · 셰이더를 금빛으로. swing 초 만에 그어지고 life 초 안에 사라진다.
## 호는 b 의 XZ 평면에 놓이고 정면(-Z)을 가운데로 150° 펼쳐진다 (반지름 2.7 × scale)
static func smear(pos: Vector3, b: Basis, scale: float, swing := 0.05, life := 0.14) -> void:
	if FX._slash_mesh == null:
		return
	if _smear_mat == null:
		# mo.co 무드면 검 궤적 셰이더가 자체 색(분홍)을 쓴다 → 사본에서 끄고 deep/light 금빛을 쓴다
		_smear_mat = FX._slash_mat.duplicate() as ShaderMaterial
		_smear_mat.set_shader_parameter("moco", false)
	var mi := MeshInstance3D.new()
	mi.mesh = FX._slash_mesh
	mi.material_override = _smear_mat
	mi.set_instance_shader_parameter("progress", 0.0)
	mi.set_instance_shader_parameter("heavy", 1.0)
	mi.set_instance_shader_parameter("deep", Vector3(1.0, 0.42, 0.08))
	mi.set_instance_shader_parameter("light", Vector3(1.0, 0.95, 0.72))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	FX.root.add_child(mi)
	mi.global_position = pos
	mi.basis = b.scaled(Vector3.ONE * scale)
	var set_p := func(v: float): mi.set_instance_shader_parameter("progress", v)
	var tw := mi.create_tween()
	tw.tween_method(set_p, 0.0, 0.72, swing).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_method(set_p, 0.72, 1.0, life).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## 찌르기의 일직선 섬광: 집게 끝에서 앞으로 뻗었다 가늘어진다
static func thrust_line(from: Vector3, dir: Vector3, length: float) -> void:
	_shared()
	for i in 2:
		var mi := Pal.flat_mesh(_tracer_mesh, Color(1.0, 0.95, 0.75) if i == 0 else Color(1.0, 0.55, 0.15), 3.0 if i == 0 else 2.0)
		FX.root.add_child(mi)
		var w := 0.12 if i == 0 else 0.3
		mi.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(w, w, length)), from + dir * length * 0.5)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(0.0, 0.0, length * 1.15), 0.12).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)


## 큰 임팩트 별 (컨셉 시트의 주황 · 흰 톱니 섬광)
static func impact_star(pos: Vector3, size: float) -> void:
	FX.flash(pos, Color(1.0, 0.95, 0.8), size, 0.06)
	FX.flash(pos, Color(1.0, 0.55, 0.12), size * 1.6, 0.12)
	ParryFX.glint(pos, size * 2.2, Color(1.0, 0.7, 0.25), 0.18)
	FX.sparks(pos, 18, [Color.WHITE, Color(1.0, 0.75, 0.3), Color(1.0, 0.45, 0.12)], 9.0, 0.35, -14.0, 0.07)


## 분사 소리 한 번. Sfx 의 "boost" 는 플레이어 부스터용 반복(loop) 소리라 그냥 틀면 멈추지 않는다
## → 짧게 틀고 dur 초 동안 줄였다 끈다 (그사이 다른 소리가 그 재생기를 가져갔으면 건드리지 않는다)
static func jet_burst(vol := -6.0, pitch := 0.75, dur := 0.35) -> void:
	var s := Sfx.play("boost", 0.05, vol)
	if s == null:
		return
	s.pitch_scale = pitch
	var stream := s.stream
	var tw := s.create_tween()
	var fade := func(v: float) -> void:
		if is_instance_valid(s) and s.stream == stream:
			s.volume_db = v
	tw.tween_method(fade, vol, vol - 30.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(s) and s.stream == stream:
			s.stop())


# ── 투사체 ──────────────────────────────────────────────

static func tracer(pos: Vector3, dir: Vector3, speed: float, target: Node3D = null) -> void:
	_shared()
	var tr := Tracer.new()
	tr.vel = dir.normalized() * speed
	tr.position = pos
	tr.target = target
	Main.inst.bullets.add_child(tr)


static func mortar(from: Vector3, to: Vector3, flight: float, radius: float, warn: MeshInstance3D) -> Mortar:
	_shared()
	var m := Mortar.new()
	m.from = from
	m.to = to
	m.flight = flight
	m.radius = radius
	m.warn = warn
	m.position = from
	Main.inst.bullets.add_child(m)
	return m


## 개틀링 예광탄: 노란 심이 진행 방향으로 길게 늘어난 막대 + 주황 꼬리
class Tracer extends Node3D:
	const LIFE := 1.3
	const HIT_R := 0.14
	var vel := Vector3.ZERO
	var age := 0.0
	var core: MeshInstance3D
	var tail: MeshInstance3D
	var target: Node3D            ## 연출용 표적 (등장 연출의 벌레 — cine_hit 을 부른다)

	func _ready() -> void:
		core = Pal.flat_mesh(LancasterFX._tracer_mesh, LancasterFX.TRACER_CORE, 3.2)
		core.scale = Vector3(0.07, 0.07, 0.95)
		add_child(core)
		tail = Pal.flat_mesh(LancasterFX._tracer_mesh, LancasterFX.TRACER_TAIL, 2.0)
		tail.scale = Vector3(0.12, 0.12, 0.6)
		tail.position = Vector3(0, 0, 0.6)
		add_child(tail)
		basis = Basis.looking_at(vel.normalized(), Vector3.UP)

	func _physics_process(dt: float) -> void:
		age += dt
		var prev := position
		position += vel * dt
		var main := Main.inst
		if age > LIFE or main == null:
			queue_free()
			return
		var fwd := vel.normalized()
		if main.is_blocked(position):
			var wn := Bullet._wall_normal(position, fwd)
			GunFX.impact_wall(position - fwd * 0.15, wn, fwd, 0.45)
			queue_free()
			return
		if target != null:
			if not is_instance_valid(target) or not target.get("alive"):
				target = null
			else:
				var tc := target.global_position + Vector3(0, 0.7, 0)
				var sg := position - prev
				var k := clampf((tc - prev).dot(sg) / maxf(sg.length_squared(), 0.0001), 0.0, 1.0)
				var cl := prev + sg * k
				if cl.distance_to(tc) < 0.8:
					target.call("cine_hit", fwd, cl)
					queue_free()
					return
		var p := main.player
		if p.alive:
			var chest := p.global_position + Vector3(0, 0.95, 0)
			var seg := position - prev
			var tt := clampf((chest - prev).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
			var close := prev + seg * tt
			var flat := Vector2(close.x - chest.x, close.z - chest.z).length()
			if flat < p.hit_radius + HIT_R and absf(close.y - chest.y) < 0.9:
				if p.take_hit(close):
					FX.sparks(close, 8, [Color.WHITE, LancasterFX.TRACER_CORE], 6.0, 0.25, -12.0, 0.05)
					queue_free()
					return
		# 처음엔 짧게 뻗어 나오며 늘어난다
		var s := clampf(age * 14.0, 0.25, 1.0)
		core.scale.z = 0.95 * s
		tail.scale.z = 0.6 * s


## 보안 포드 박격탄: 위로 치솟았다 표적 원에 내리꽂힌다
class Mortar extends Node3D:
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var flight := 1.0
	var radius := 1.6
	var warn: MeshInstance3D
	var age := 0.0
	var body: MeshInstance3D
	var glow: MeshInstance3D
	var _puff := 0.0
	var _prev := Vector3.ZERO

	func _ready() -> void:
		body = Pal.flat_mesh(LancasterFX._shell_mesh, Color(0.16, 0.15, 0.2), 1.0)
		body.scale = Vector3.ONE * 0.16
		add_child(body)
		glow = Pal.flat_mesh(LancasterFX._shell_mesh, Color(1.0, 0.6, 0.18), 3.0)
		glow.scale = Vector3(0.1, 0.1, 0.1)
		glow.position = Vector3(0, 0, 0)
		add_child(glow)
		_prev = from

	func _pos(k: float) -> Vector3:
		var p := from.lerp(to, k)
		var h := maxf(4.5, from.distance_to(to) * 0.45)
		p.y += sin(PI * k) * h
		return p

	func _physics_process(dt: float) -> void:
		age += dt
		var k := clampf(age / flight, 0.0, 1.0)
		position = _pos(k)
		var d := position - _prev
		if d.length() > 0.001:
			basis = Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.FORWARD) * Basis(Vector3.RIGHT, -PI * 0.5)
		_prev = position
		_puff -= dt
		if _puff <= 0.0:
			_puff = 0.035
			FX.puffs(position, 1, LancasterFX.SMOKE_C, 0.05, 0.28, 0.5)
			FX.flash(position, Color(1.0, 0.7, 0.3), 0.3, 0.05)
		LancasterFX.set_warn(warn, k)
		if k >= 1.0:
			_explode()

	func _explode() -> void:
		var at := Vector3(to.x, Main.gy(to), to.z)
		FX.fire_explosion(at + Vector3(0, 0.3, 0), 0.75 + radius * 0.15)
		FX.shockwave(at + Vector3(0, 0.08, 0), Color(1.0, 0.6, 0.3), radius * 1.6, 0.3, 0.07)
		FX.sparks(at + Vector3(0, 0.3, 0), 14, [Color.WHITE, Color(1.0, 0.7, 0.3), Color(0.4, 0.38, 0.44)], 8.0, 0.45, -16.0, 0.08)
		LancasterFX.smoke(at + Vector3(0, 0.4, 0), 1.2)
		GroundBreak.burst(at, 0.42, Vector3.ZERO)
		Sfx.play("boom", 0.1, -6.0)
		Main.inst.shake(0.22)
		LancasterFX.clear_warn(warn)
		var p := Main.inst.player
		if p.alive:
			var flat := Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length()
			if flat < radius + p.hit_radius * 0.5 and p.global_position.y - Main.gy(p.global_position) < 1.4:
				p.take_hit(at)
		queue_free()

	func _exit_tree() -> void:
		if is_instance_valid(warn) and age < flight:
			warn.queue_free()


const DISC_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;
instance uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.1, 1.0);
instance uniform float progress = 0.0;
instance uniform float fade = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float edge = smoothstep(0.9, 0.96, r) * (1.0 - smoothstep(0.985, 1.0, r));
	float fill = step(r, progress) * 0.22;
	float front = smoothstep(progress - 0.06, progress, r) * (1.0 - step(progress, r)) * 0.9;
	float ang = atan(p.y, p.x);
	float hatch = step(0.5, fract((ang + TIME * 1.4) * 4.0 / 3.14159)) * smoothstep(0.78, 0.86, r) * (1.0 - smoothstep(0.88, 0.9, r)) * 0.5;
	float blink = 0.75 + 0.25 * sin(TIME * mix(10.0, 34.0, progress));
	float base = 0.06 * (1.0 - r * 0.4);
	float a = (edge * 0.95 + fill + front + hatch + base) * blink * fade;
	ALBEDO = tint.rgb * 2.2 * a;
}
"""

const FAN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;
instance uniform float half = 0.8;
instance uniform float progress = 0.0;
instance uniform float fade = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float ang = atan(p.x, -p.y);
	if (abs(ang) > half) discard;
	float side = 1.0 - smoothstep(0.0, 0.04, half - abs(ang));
	float edge = smoothstep(0.93, 0.98, r);
	float sweep = smoothstep(0.08, 0.0, abs(ang / half - (progress * 2.0 - 1.0))) * 0.8;
	float stripes = step(0.5, fract(r * 9.0 - TIME * 3.0)) * 0.12;
	float a = (side * 0.8 + edge * 0.7 + sweep + stripes + 0.05) * fade * (0.8 + 0.2 * sin(TIME * 24.0));
	ALBEDO = vec3(1.0, 0.32, 0.14) * 2.0 * a * (1.0 - r * 0.35);
}
"""

extends Node
## 섹터 런 진행 상태 (오토로드 "Run"). 씬이 바뀌어도 남는다.
## 섹터 지도 · 현재 칸 · 지나온 길 · 체력/코인/점수를 들고, 포탈 워프 전환과 보스전 결과(승리 → 다음 섹터, 패배 → 런 종료)를 처리한다.
## run.tscn(RunMain) 이 방 하나를 맡고, 보스 칸은 기존 boss.tscn / forge.tscn 을 그대로 띄운다.

const G := preload("res://scripts/sector_graph.gd")
const RUN_SCENE := "res://scenes/run.tscn"
const SECTORS := [
	{"name": "도시 외곽", "boss": "MAMMOTH", "scene": "res://scenes/boss.tscn"},
	{"name": "제철소", "boss": "VULCAN", "scene": "res://scenes/forge.tscn"},
]
const SECTOR_HEAL := 2

var active := false
var run_seed := 0
var sector := 0
var nodes: Array = []
var cur := 0
var path: Array = []
var hp := 5
var energy := Player.ENERGY_MAX
var missiles := Player.MISSILE_START
var coins := 0
var score := 0
var kills := 0
var best_combo := 0
var run_time := 0.0
var over := false          # 런 종료 (패배 또는 완주): R 로 새 런
var expected_scene := ""
var _last_scene: Node
var _end_handled := false
var _warping := false

var layer: CanvasLayer
var map_view: SectorMapView
var warp_rect: ColorRect
var warp_mat: ShaderMaterial
## 워프 단계: 0 없음 · 1 덮기 · 2 최고 속도 유지 후 씬 교체 · 3 새 씬이 안정될 때까지 대기 · 4 걷기
enum Warp { NONE, OUT, SWAP, WAIT, IN }
var _warp := Warp.NONE
var _warp_t := 0.0
var _warp_scene := ""
var _warp_phase := 0.0
var _warp_speed := 0.0
var _warp_stable := 0
var _warp_last_us := 0
const WARP_OUT := 0.5          # 덮는 시간
const WARP_SWAP := 0.12        # 완전히 덮인 뒤 교체 전까지 최고 속도로 달리는 시간
const WARP_MIN_HOLD := 0.3     # 새 씬 시작 뒤 최소 유지 시간
const WARP_MAX_HOLD := 1.4
const WARP_IN := 0.6           # 걷히는 시간

## 포탈 워프: 육각 터널을 빛보다 빠르게 빠져나가는 느낌.
## 조각난 육각 판들이 화면 가장자리로 쉴 새 없이 스쳐 지나가고(ring 마다 칸이 무작위로 비어 있다),
## 긴 속도선 · 비틀림 · 색수차가 속도(speed)에 따라 강해진다.
## 시간(phase)은 셰이더 TIME 이 아니라 스크립트가 넘긴다: 씬 로딩으로 한 프레임이 길어져도 터널이 튀지 않고 이어진다.
const WARP_SHADER := """
shader_type canvas_item;
uniform float cover = 0.0;
uniform float phase = 0.0;
uniform float speed = 0.0;
uniform vec4 tint : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float aspect = 1.6;
float hexd(vec2 p) { p = abs(p); return max(p.x * 0.866025 + p.y * 0.5, p.y); }
float h1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 tunnel(vec2 p) {
	// 터널이 천천히 비틀리며 돈다
	float ang0 = atan(p.y, p.x);
	float r0 = length(p);
	float tw = phase * 0.05 + 0.25 / (r0 + 0.3) * speed;
	p = vec2(cos(ang0 + tw), sin(ang0 + tw)) * r0;
	float d = hexd(p);
	float z = 1.0 / (d + 0.03);
	float ang = atan(p.y, p.x) / 6.28318 + 0.5;
	vec3 col = vec3(0.0);
	// 육각 판: 깊이 방향 두 겹 (촘촘한 겹 + 굵은 겹). 속도가 붙을수록 판이 깊이 방향으로 늘어나 번진다.
	for (int L = 0; L < 2; L++) {
		float fl = float(L);
		float dens = mix(0.55, 0.23, fl);
		float rz = z * dens - phase * mix(1.0, 0.72, fl) + fl * 0.37;
		float ring = floor(rz);
		float f = fract(rz);
		float segs = mix(36.0, 18.0, fl);
		float seg = floor(ang * segs + h1(ring + fl * 13.0) * segs);
		float on = step(mix(0.38, 0.55, fl), h2(vec2(ring, seg + fl * 50.0)));
		float bright = 0.45 + 0.55 * h2(vec2(seg, ring * 1.7));
		float sharp = mix(18.0, 9.0, speed);
		float plate = pow(1.0 - abs(f * 2.0 - 1.0), sharp);
		// 판 가장자리(칸 사이 틈)
		float sf = fract(ang * segs + h1(ring + fl * 13.0) * segs);
		float gap = smoothstep(0.0, 0.06, sf) * smoothstep(1.0, 0.94, sf);
		vec3 c = mix(tint.rgb, vec3(1.0), h2(vec2(seg * 3.1, ring)) > 0.86 ? 0.8 : 0.1);
		col += c * plate * on * gap * bright * mix(1.1, 0.7, fl);
		// 굵은 겹에는 끊기지 않은 육각 테두리를 그어 육각형 모양이 또렷이 스쳐 가게 한다
		float rim_l = smoothstep(0.045, 0.0, abs(f - 0.5)) * fl * step(0.4, h1(ring * 3.3));
		col += mix(tint.rgb, vec3(1.0), 0.5) * rim_l * 0.9;
	}
	// 속도선: 가느다란 빛줄기가 중심에서 바깥으로 빠르게 뻗어 나간다
	float sa = floor(ang * 160.0);
	float lane = step(0.72, h1(sa));
	float sz = fract(z * 0.09 - phase * 1.9 + h1(sa + 7.0));
	float streak = lane * pow(sz, mix(18.0, 5.0, speed)) * speed;
	col += mix(tint.rgb, vec3(1.0), 0.6) * streak * 1.6;
	// 가까울수록(가장자리) 밝고, 소실점 쪽은 빛 속으로 녹아든다
	col *= smoothstep(0.015, 0.22, d);
	vec3 bg = mix(vec3(0.01, 0.01, 0.04), tint.rgb * 0.22, smoothstep(0.9, 0.0, d));
	vec3 core = mix(tint.rgb, vec3(1.0), 0.7) * smoothstep(0.2, 0.0, d) * (0.45 + speed * 0.9);
	return bg + col + core;
}
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	// 색수차: 속도가 빠를수록 채널이 바깥쪽으로 벌어진다
	float ca = 0.018 * speed;
	vec3 col;
	col.r = tunnel(p * (1.0 - ca)).r;
	col.g = tunnel(p).g;
	col.b = tunnel(p * (1.0 + ca)).b;
	float d = hexd(p);
	col += vec3(1.0) * smoothstep(0.09, 0.0, d) * cover;
	// 화면 가장자리 어둡게 → 안쪽 터널에 시선이 모인다
	col *= 1.0 - smoothstep(0.55, 1.05, d) * 0.35;
	// 가장자리부터 안쪽으로 덮는다
	float edge = mix(1.25, -0.1, cover);
	float a = smoothstep(edge, edge + 0.12, d);
	COLOR = vec4(col, max(a, step(0.999, cover)));
}
"""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	map_view = SectorMapView.new()
	layer.add_child(map_view)
	var wl := CanvasLayer.new()
	wl.layer = 60
	add_child(wl)
	warp_rect = ColorRect.new()
	warp_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	warp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warp_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WARP_SHADER
	warp_mat.shader = sh
	warp_rect.material = warp_mat
	warp_rect.visible = false
	wl.add_child(warp_rect)


# ── 런 시작 · 조회 ──────────────────────────────────────

func begin(seed_value: int) -> void:
	active = true
	over = false
	run_seed = seed_value
	sector = 0
	hp = Player.MAX_HP
	energy = Player.ENERGY_MAX
	missiles = Player.MISSILE_START
	coins = 0
	score = 0
	kills = 0
	best_combo = 0
	run_time = 0.0
	_start_sector()
	print("RUN_BEGIN seed=%d" % run_seed)


func _start_sector() -> void:
	nodes = G.build(run_seed * 7 + sector * 1013, sector)
	cur = 0
	path = [0]
	expected_scene = RUN_SCENE
	_end_handled = false


func node() -> Dictionary:
	return nodes[cur]


func cur_level() -> int:
	return nodes[cur].level


func sector_name() -> String:
	return SECTORS[sector].name


func boss_name() -> String:
	return SECTORS[sector].boss


func next_nodes() -> Array:
	var out: Array = []
	for id in nodes[cur].links:
		out.append(nodes[id])
	# 지도 위→아래 순서 = 방 안 왼쪽→오른쪽 순서
	out.sort_custom(func(a, b): return a.row < b.row)
	return out


## 포탈 위에 띄울 제목과 설명
func describe(nd: Dictionary) -> Array:
	match nd.kind:
		G.Kind.COMBAT: return ["전투", "적 소탕 · 코인 +%d" % nd.coins]
		G.Kind.ELITE: return ["정예", "강적 · 코인 +%d" % nd.coins]
		G.Kind.REST: return ["정비", "장갑 수리 +3"]
		G.Kind.BOSS: return ["BOSS  " + boss_name(), "섹터 %d 최종 목표" % (sector + 1)]
	return ["?", ""]


# ── 진행 ────────────────────────────────────────────────

## 현재 씬의 성과를 런에 쌓는다 (방·보스전을 떠날 때 한 번)
func bank_scene() -> void:
	var m := Main.inst
	if m == null or not is_instance_valid(m):
		return
	score += m.score
	kills += m.kills
	best_combo = maxi(best_combo, m.best_combo)
	run_time += m.time
	if m.player:
		hp = m.player.hp
		energy = m.player.energy
		missiles = m.player.missiles


## 포탈로 다음 칸에 들어간다
func enter_node(id: int) -> void:
	if _warping:
		return
	bank_scene()
	cur = id
	path.append(id)
	var nd: Dictionary = nodes[id]
	print("RUN_ENTER sector=%d level=%d kind=%s id=%d hp=%d" % [sector, nd.level, G.KIND_NAMES[nd.kind], id, hp])
	var scene: String = SECTORS[sector].scene if nd.kind == G.Kind.BOSS else RUN_SCENE
	warp_to(scene, G.KIND_COLORS[nd.kind])


func warp_to(scene: String, tint: Color) -> void:
	_warping = true
	expected_scene = scene
	map_view.want = false
	warp_mat.set_shader_parameter("tint", tint)
	warp_mat.set_shader_parameter("aspect", float(get_viewport().size.x) / maxf(get_viewport().size.y, 1.0))
	warp_mat.set_shader_parameter("cover", 0.0)
	warp_rect.visible = true
	_warp = Warp.OUT
	_warp_t = 0.0
	_warp_scene = scene
	_warp_speed = 0.0
	_warp_last_us = Time.get_ticks_usec()
	Sfx.play("dash", 0.0, 0.0)
	Sfx.play("slowin", 0.0, -3.0)


## 새 씬이 시작됐다: 첫 프레임들이 매끄럽게 돌 때까지 터널을 유지한 뒤 걷어 낸다
func _warp_in() -> void:
	if not warp_rect.visible:
		return
	_warp = Warp.WAIT
	_warp_t = 0.0
	_warp_stable = 0


## 워프 진행. 실제 시간 기준이며, 한 프레임 진행량을 1/30초로 제한해 로딩 멈춤 뒤에도 터널이 끊김 없이 이어진다.
func _update_warp() -> void:
	var now := Time.get_ticks_usec()
	var raw := (now - _warp_last_us) / 1000000.0
	_warp_last_us = now
	if _warp == Warp.NONE:
		return
	var dt := minf(raw, 1.0 / 30.0)
	_warp_t += dt
	var cover := 1.0
	match _warp:
		Warp.OUT:
			var k := clampf(_warp_t / WARP_OUT, 0.0, 1.0)
			cover = k * k
			_warp_speed = k
			if k >= 1.0:
				_warp = Warp.SWAP
				_warp_t = 0.0
		Warp.SWAP:
			_warp_speed = 1.0
			if _warp_t >= WARP_SWAP:
				_warp = Warp.WAIT
				_warp_t = 0.0
				_warp_stable = 0
				Engine.time_scale = 1.0
				Engine.physics_ticks_per_second = 60
				get_tree().change_scene_to_file(_warp_scene)
		Warp.WAIT:
			_warp_speed = 1.0
			# 셰이더 컴파일 등으로 튀는 프레임이 지나갈 때까지 기다린다
			_warp_stable = _warp_stable + 1 if raw < 0.03 else 0
			if (_warp_t >= WARP_MIN_HOLD and _warp_stable >= 6) or _warp_t >= WARP_MAX_HOLD:
				_warp = Warp.IN
				_warp_t = 0.0
				Sfx.play("dash", 0.0, -6.0)
		Warp.IN:
			var k := clampf(_warp_t / WARP_IN, 0.0, 1.0)
			cover = pow(1.0 - k, 2.0)
			_warp_speed = lerpf(1.0, 0.35, k)
			if k >= 1.0:
				_warp = Warp.NONE
				warp_rect.visible = false
				_warping = false
				return
	# 속도가 붙을수록 판이 더 빨리 스쳐 간다 (최고 속도에서 초당 육각 링 약 11개)
	_warp_phase += dt * lerpf(1.6, 11.0, _warp_speed * _warp_speed)
	warp_mat.set_shader_parameter("phase", _warp_phase)
	warp_mat.set_shader_parameter("speed", _warp_speed)
	warp_mat.set_shader_parameter("cover", cover)


func new_run() -> void:
	map_view.want = false
	begin(randi())
	warp_to(RUN_SCENE, G.KIND_COLORS[G.Kind.START])


# ── 씬 감시: 보스전 결과 · 패배 ─────────────────────────

func _process(_dt: float) -> void:
	_update_warp()
	var cs := get_tree().current_scene
	if cs != _last_scene and cs != null:
		_last_scene = cs
		_on_scene_started(cs)
	if not active or over or _end_handled:
		return
	var m := Main.inst
	if m == null or not is_instance_valid(m) or m != cs:
		return
	if m.state == Main.State.LOSE:
		_end_handled = true
		get_tree().create_timer(1.4, true, false, true).timeout.connect(_run_failed)
	elif m.state == Main.State.WIN and node().kind == G.Kind.BOSS:
		_end_handled = true
		get_tree().create_timer(3.2, true, false, true).timeout.connect(_boss_cleared)


func _on_scene_started(cs: Node) -> void:
	_warp_in()
	if not active:
		return
	if cs.scene_file_path != expected_scene:
		# 디버그 전환(B 키 등)으로 런 밖으로 나갔다
		active = false
		map_view.want = false
		print("RUN_ABORT scene=%s" % cs.scene_file_path)
		return
	_end_handled = false
	if cs is Main and not (cs is RunMain):
		# 보스전: 런의 체력을 이어받는다
		(cs as Main).player.hp = hp
		(cs as Main).player.energy = energy
		(cs as Main).player.missiles = missiles
		(cs as Main).hud.banner("SECTOR %d  ·  %s" % [sector + 1, boss_name()], G.KIND_COLORS[G.Kind.BOSS], "섹터의 끝 · 격파하면 다음 섹터로")


func _boss_cleared() -> void:
	bank_scene()
	var m := Main.inst
	print("RUN_BOSS_CLEAR sector=%d score=%d" % [sector, score])
	if sector + 1 >= SECTORS.size():
		over = true
		active = true
		m.hud.message("RUN COMPLETE", "섹터 %d곳 돌파 · 적 %d기 · 점수 %d · 최대 %d 콤보 · %.0f초 · 코인 %d  ·  R 키로 새 런" % [SECTORS.size(), kills, score, best_combo, run_time, coins], Color("7cf5ff"))
		print("RUN_COMPLETE score=%d kills=%d t=%.1f" % [score, kills, run_time])
		return
	m.hud.message("SECTOR %d CLEAR" % (sector + 1), "다음 섹터: %s  ·  장갑 +%d" % [SECTORS[sector + 1].name, SECTOR_HEAL], Color("7cf5ff"))
	get_tree().create_timer(2.4, true, false, true).timeout.connect(func():
		sector += 1
		hp = mini(Player.MAX_HP, hp + SECTOR_HEAL)
		_start_sector()
		warp_to(RUN_SCENE, G.KIND_COLORS[G.Kind.START]))


func _run_failed() -> void:
	bank_scene()
	over = true
	var m := Main.inst
	print("RUN_FAILED sector=%d level=%d score=%d" % [sector, cur_level(), score])
	if m and is_instance_valid(m):
		m.hud.message("RUN FAILED", "섹터 %d · 단계 %d 에서 격추 · 적 %d기 · 점수 %d · 최대 %d 콤보  ·  R 키로 새 런" % [sector + 1, cur_level(), kills, score, best_combo], Color("ff4a8a"))


# ── 입력: 지도 · 재시작 ─────────────────────────────────

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_F11:
		# 전체 화면 ↔ 창 모드 (런 여부와 상관없이 모든 씬에서)
		var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	if key == KEY_TAB:
		map_view.want = not map_view.want
		get_viewport().set_input_as_handled()
	elif key == KEY_F5 or (key == KEY_R and over):
		# 런 중의 재시작은 새 런
		get_viewport().set_input_as_handled()
		if not _warping:
			new_run()
	elif key == KEY_R and Main.inst and is_instance_valid(Main.inst) and Main.inst.state != Main.State.PLAY:
		# 보스 격파 뒤 다음 섹터로 넘어가는 중에는 씬 재시작을 막는다
		get_viewport().set_input_as_handled()

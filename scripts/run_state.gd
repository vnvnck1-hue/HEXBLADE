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

const WARP_SHADER := """
shader_type canvas_item;
uniform float cover = 0.0;
uniform vec4 tint : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float aspect = 1.6;
float hexd(vec2 p) { p = abs(p); return max(p.x * 0.866025 + p.y * 0.5, p.y); }
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float d = hexd(p);
	float z = 1.0 / (d + 0.04);
	float band = fract(z * 0.35 - TIME * 2.6);
	float line = pow(1.0 - abs(band * 2.0 - 1.0), 10.0);
	float spokes = pow(abs(sin(atan(p.y, p.x) * 3.0)), 40.0) * 0.5;
	vec3 bg = mix(vec3(0.01, 0.01, 0.04), tint.rgb * 0.18, smoothstep(0.8, 0.0, d));
	vec3 col = bg + tint.rgb * (line * 0.9 + spokes * line) * smoothstep(0.02, 0.25, d);
	col += vec3(1.0) * smoothstep(0.09, 0.0, d) * cover;
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
	Sfx.play("dash", 0.0, 0.0)
	Sfx.play("slowin", 0.0, -3.0)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(func(v): warp_mat.set_shader_parameter("cover", v), 0.0, 1.0, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		Engine.time_scale = 1.0
		Engine.physics_ticks_per_second = 60
		get_tree().change_scene_to_file(scene))


func _warp_in() -> void:
	if not warp_rect.visible:
		return
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.15)
	tw.tween_method(func(v): warp_mat.set_shader_parameter("cover", v), 1.0, 0.0, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		warp_rect.visible = false
		_warping = false)


func new_run() -> void:
	map_view.want = false
	begin(randi())
	warp_to(RUN_SCENE, G.KIND_COLORS[G.Kind.START])


# ── 씬 감시: 보스전 결과 · 패배 ─────────────────────────

func _process(_dt: float) -> void:
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
	if not active or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode
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

class_name ClaudeBgMain
extends TrainingMain
## 배경 첫 제작 시험장 (Claude 판). docs/background-first-pass-claude.md
## 8×8m 바닥(F01 16장) + ㄱ자 벽(W01: 뒤 4장 · 왼쪽 4장) + 작업대 A01 + 수납장 A02 를 실제 GLB 로 깔고,
## 전투 테스트장(TrainingMain)의 허수아비·무기·카메라를 그대로 써서 플레이어·적·공격 표시가 배경에 묻히는지 본다.
## 본편 아레나·조명은 바꾸지 않는다. 조명은 기본이 현재 전투 환경 그대로이고, 9 키로 시험 조정판과 번갈아 본다.
##
## 숫자 키: TrainingMain 의 1~8 그대로 + 9 조명(기준 ↔ 조정) + 0 진짜 적 3기 소환 (드론 · 돌격기)
## 확인용 실행 인자: --bglight=1 (조정 조명으로 시작) --bgfoes (적 소환 상태로 시작) --bgview=N (고정 시점 캡처용)

const ROOM := 8
const GLB := {
	"f01": "res://assets/models/bg_claude_f01.glb",
	"w01": "res://assets/models/bg_claude_w01.glb",
	"a01": "res://assets/models/bg_claude_a01.glb",
	"a02": "res://assets/models/bg_claude_a02.glb",
}
const FLOOR_SHADER := preload("res://scripts/claude_background/bg_floor.gdshader")
const BENCH_X := -2.0       # 작업대 중심 X (뒤 벽 앞, 칸 -3~-1)
const LOCKER_X := 2.5       # 수납장 중심 X (뒤 벽 앞, 칸 2~3)
const WALL_GAP := 0.05      # 프랍 뒷면과 벽 사이

var origin := Vector3(-ROOM * 0.5, 0, -ROOM * 0.5)   # 바닥 왼쪽 앞(-X, -Z) 모서리
var bg: Node3D
var floor_mat: ShaderMaterial
var light_mode := 0
var _base_light := {}
var view_fixed := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bglight="):
			light_mode = int(a.substr(10))
		elif a.begins_with("--bgview="):
			view_fixed = int(a.substr(9))
	super._ready()
	_base_light = {
		"amb": env.ambient_light_color, "amb_e": env.ambient_light_energy, "sun_e": sun.light_energy,
		"sun_c": sun.light_color, "ssao": env.ssao_intensity,
	}
	_apply_light()
	player.global_position = Vector3(0, 0, 1.5)
	camera.snap(player.global_position)
	if Main.cmd_args.has("--bgfoes"):
		_spawn_foes()
	hud.banner("BACKGROUND · CLAUDE", Color(0.85, 0.8, 1.0), "배경 첫 제작 시험장 · 9 조명 · 0 적 소환 · Esc 로비")


## 8×8m 방 하나. 바닥·벽·프랍은 GLB, 판정은 ArenaMap 칸(1m)을 그대로 쓴다 (프랍 칸은 막힘).
func _build_arena() -> void:
	map = ArenaMap.new()
	world.add_child(map)
	map.terrain = false
	map.generate_single(7, ArenaMap.Shape.RECT, false, Vector2i(ROOM, ROOM))
	# 프랍이 서는 칸 막기 (총알·이동 판정 공통)
	for c in _prop_cells():
		map.grid[map._idx(map.cell_of(c))] = ArenaMap.LOW
	map._build_minimap()
	bg = Node3D.new()
	bg.name = "ClaudeBackground"
	world.add_child(bg)
	_build_floor()
	_build_walls()
	_build_props()


func _prop_cells() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for x in [BENCH_X - 0.5, BENCH_X + 0.5]:
		out.append(Vector3(x, 0, origin.z + 0.5))
	for x in [LOCKER_X - 0.5, LOCKER_X + 0.5]:
		out.append(Vector3(x, 0, origin.z + 0.5))
	return out


func _inst(key: String) -> Node3D:
	var n := (load(GLB[key]) as PackedScene).instantiate() as Node3D
	n.set_meta("claude_bg", key)      # BrawlLook 이 W01 을 벽 역할로 칠한다 (본편 ClaudeBgDress 와 같은 메타)
	bg.add_child(n)
	return n


static func meshes(n: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if n is MeshInstance3D:
		out.append(n)
	for k in n.get_children():
		meshes(k, out)
	return out


## F01 16장. 모든 타일이 같은 셰이더 재질 하나를 공유하고, 4m 그림을 월드 좌표로 읽어 이음 위상을 잇는다.
func _build_floor() -> void:
	for j in ROOM / 2:
		for i in ROOM / 2:
			var t := _inst("f01")
			t.name = "F01_%d_%d" % [i, j]
			t.position = origin + Vector3(2 * i, 0, 2 * j)
			for mi in meshes(t, []):
				if floor_mat == null:
					var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
					floor_mat = ShaderMaterial.new()
					floor_mat.shader = FLOOR_SHADER
					floor_mat.set_shader_parameter("albedo_tex", src.albedo_texture if src else null)
					ClaudeBgDress.BLUE_PAINT.configure(floor_mat, false)
				mi.material_override = floor_mat
				mi.layers = 1 | MechDecals.RECEIVER
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## ㄱ자 벽: 뒤 벽(-Z)이 모서리 0.25×0.25 를 가진다 → x -4.25~3.75, 왼쪽 벽(-X)은 z -4~4.
func _build_walls() -> void:
	var body := StaticBody3D.new()
	bg.add_child(body)
	for k in ROOM / 2:
		var w := _inst("w01")
		w.name = "W01_back_%d" % k
		w.rotation_degrees.y = 180.0                       # 정면(-Z)이 방 안(+Z)을 본다
		w.position = Vector3(origin.x - 0.25 + 2.0 * (k + 1), 0, origin.z)
	for k in ROOM / 2:
		var w := _inst("w01")
		w.name = "W01_left_%d" % k
		w.rotation_degrees.y = -90.0                       # 정면이 +X, 로컬 X 가 +Z
		w.position = Vector3(origin.x, 0, origin.z + 2.0 * k)
	_box(body, Vector3(origin.x - 0.25, 0, origin.z - 0.25), Vector3(origin.x + ROOM - 0.25, 3.0, origin.z))
	_box(body, Vector3(origin.x - 0.25, 0, origin.z), Vector3(origin.x, 3.0, origin.z + ROOM))


func _build_props() -> void:
	var body := StaticBody3D.new()
	bg.add_child(body)
	var bench := _inst("a01")
	bench.name = "A01"
	bench.rotation_degrees.y = 180.0
	bench.position = Vector3(BENCH_X, 0, origin.z + WALL_GAP + 0.375)
	_box(body, bench.position - Vector3(1.0, 0, 0.375), bench.position + Vector3(1.0, 1.0, 0.375))
	var locker := _inst("a02")
	locker.name = "A02"
	locker.rotation_degrees.y = 180.0
	locker.position = Vector3(LOCKER_X, 0, origin.z + WALL_GAP + 0.25)
	_box(body, locker.position - Vector3(0.5, 0, 0.25), locker.position + Vector3(0.5, 2.0, 0.25))


func _box(body: StaticBody3D, mn: Vector3, mx: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = mx - mn
	cs.shape = bs
	cs.position = (mn + mx) * 0.5
	body.add_child(cs)


# ── 허수아비 자리: 8×8 방 안쪽 ─────────────────────────

func _spots() -> Array[Vector3]:
	match layout:
		0:
			return [Vector3(0, 0, -1.0)]
		2:
			var out: Array[Vector3] = []
			for i in 6:
				var a := TAU * i / 6.0
				out.append(Vector3(0, 0, -0.5) + Vector3(cos(a), 0, sin(a)) * 2.4)
			return out
		3:
			return [Vector3(2.8, 0, -2.2)]
	return [Vector3(-2.2, 0, -1.6), Vector3(0.4, 0, -2.0), Vector3(2.6, 0, -1.2)]


# ── 조명: 0 = 현재 전투 환경 그대로(기준), 1 = 시험 조정 ─────

func _apply_light() -> void:
	if _base_light.is_empty():
		return
	if light_mode == 0:
		env.ambient_light_color = _base_light.amb
		env.ambient_light_energy = _base_light.amb_e
		sun.light_energy = _base_light.sun_e
		sun.light_color = _base_light.sun_c
		env.ssao_intensity = _base_light.ssao
	else:
		# 칠한 명암이 조명에 덮이지 않게: 그림자 쪽을 조금 밝히고 해를 살짝 따뜻하게
		env.ambient_light_color = Color(0.62, 0.58, 0.86)
		env.ambient_light_energy = 0.62
		sun.light_energy = 1.05
		sun.light_color = Color(1.0, 0.95, 0.9)
		env.ssao_intensity = 1.0


func _spawn_foes() -> void:
	var spots := [Vector3(-2.5, 0, 0.5), Vector3(2.5, 0, 0.0), Vector3(0.0, 0, -2.6)]
	for i in spots.size():
		var e: Enemy = Striker.new() if i == 2 else Enemy.new()
		world.add_child(e)
		e.global_position = spots[i]


func _panel_text() -> String:
	return super._panel_text() + "\n\n[ 배경 시험 · Claude ]\n9  조명            %s\n0  진짜 적 3기 소환" % ("조정" if light_mode == 1 else "기준 (현재 전투 환경)")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_9:
			light_mode = 1 - light_mode
			_apply_light()
			hud.banner("조명  %s" % ("조정" if light_mode == 1 else "기준"), Color(0.85, 0.8, 1.0), "")
			get_viewport().set_input_as_handled()
			return
		if k == KEY_0:
			_spawn_foes()
			hud.banner("적 소환", Color(1.0, 0.6, 0.6), "드론 2 · 돌격기 1")
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


# ── 고정 시점 (캡처 비교용): 0 전체 · 1 바닥 이음 근접 · 2 프랍 근접 · 3 벽 모서리 ──

func _update_camera(dt: float) -> void:
	if view_fixed < 0:
		super._update_camera(dt)
		return
	var views := [
		[Vector3(0, 13.5, 9.5), Vector3(0, 0, -0.6), 40.0],
		[Vector3(0.6, 3.2, 2.6), Vector3(0.0, 0, -0.2), 45.0],
		[Vector3(0.3, 3.0, 1.6), Vector3(0.3, 0.8, -3.6), 45.0],
		[Vector3(-1.2, 3.4, 0.2), Vector3(-4.0, 1.4, -4.0), 50.0],
	]
	var v: Array = views[clampi(view_fixed, 0, views.size() - 1)]
	camera.global_position = v[0]
	camera.fov = v[2]
	camera.look_at(v[1], Vector3.UP)

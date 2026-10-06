class_name GhostPool
extends Node3D
## 잔상(FX.afterimage) 풀. 예전에는 잔상 한 번마다 홀더 노드 + 파츠 수(메카 약 30)만큼의 MeshInstance3D + 머티리얼 복제 + 트윈을
## 만들고 지웠다 (대시·돌진·휠윈드 중 초당 수백~천여 개의 노드 생성·삭제). 이제 MeshInstance3D 를 재사용하고,
## 머티리얼은 하나를 같이 쓰며 색은 인스턴스 셰이더 값(tint), 흐려짐은 전역 시계(ghost_clock)와 (태어난 시각, 수명)으로 GPU 가 계산한다.
## 시계는 예전 트윈처럼 게임 시간(time_scale)을 따른다.

const SHADER := """shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
global uniform float ghost_clock;
instance uniform vec4 tint : source_color = vec4(0.45, 0.55, 1.0, 0.28);
instance uniform vec2 span = vec2(0.0, 1.0);   // (태어난 시각, 수명) — 흐려지는 계산은 GPU 가 한다
void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a * clamp(1.0 - (ghost_clock - span.x) / span.y, 0.0, 1.0);
}
"""
## 동시에 보일 잔상 파츠 상한. 넘으면 가장 오래된 잔상을 먼저 거둔다
const MAX_PARTS := 900

static var _mat: ShaderMaterial
static var _inst: GhostPool
## 잔상 시계 (게임 시간). 전역 셰이더 값 ghost_clock 으로 한 번만 넘긴다 — 파츠마다 매 프레임 값을 넣지 않는다
static var clock := 0.0

var _free: Array[MeshInstance3D] = []
var _live: Array = []          ## [parts: Array[MeshInstance3D], 끝나는 시각] — 시작 순서대로
var _count := 0


static func material() -> ShaderMaterial:
	if _mat == null:
		# ghost_clock 은 project.godot [shader_globals] 에 선언돼 있다
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat


static func get_pool() -> GhostPool:
	if is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	if FX.root == null or not is_instance_valid(FX.root):
		return null
	_inst = GhostPool.new()
	_inst.name = "GhostPool"
	FX.root.add_child(_inst)
	return _inst


func _exit_tree() -> void:
	if _inst == self:
		_inst = null


## visual 아래 보이는 메시 파츠를 지금 자세 그대로 반투명하게 복제한다
func spawn(visual: Node3D, tint: Color, life: float) -> void:
	var parts: Array[MeshInstance3D] = []
	for m: MeshInstance3D in FX.mesh_parts(visual):
		if not is_instance_valid(m) or not m.is_visible_in_tree() or m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var g := _take()
		g.mesh = m.mesh
		g.global_transform = m.global_transform
		g.set_instance_shader_parameter("tint", tint)
		g.set_instance_shader_parameter("span", Vector2(clock, life))
		g.visible = true
		parts.append(g)
	if parts.is_empty():
		return
	_count += parts.size()
	_live.append([parts, clock + maxf(life, 0.001)])
	while _count > MAX_PARTS and _live.size() > 1:
		_retire(0)
	set_process(true)


func _take() -> MeshInstance3D:
	if not _free.is_empty():
		return _free.pop_back()
	var g := MeshInstance3D.new()
	g.material_override = material()
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.top_level = true
	add_child(g)
	return g


func _retire(i: int) -> void:
	var parts: Array = _live[i][0]
	for g: MeshInstance3D in parts:
		g.visible = false
		_free.append(g)
	_count -= parts.size()
	_live.remove_at(i)


func _process(dt: float) -> void:
	clock += dt
	RenderingServer.global_shader_parameter_set(&"ghost_clock", clock)
	# 수명이 다한 것만 거둔다 (오래된 것이 앞에 있다)
	while not _live.is_empty() and float(_live[0][1]) <= clock:
		_retire(0)
	if _live.is_empty():
		set_process(false)

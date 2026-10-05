class_name InfestRemains
extends DroneMess
## 다 터진 감염 오염물의 잔해 = 청소 대상 (DroneMess 의 체액 GOO 종류).
## 쭈그러든 포낭 껍질·시든 연결막(원래 노드를 그대로 넘겨받음)이 조각(chunks)이 되어 청소할수록 하나씩 흡입구로 빨려 들어가고,
## 바닥의 끈적한 체액 웅덩이(blobs)는 점점 작아진다. 드론 자동 청소 · Z 직접 청소 · Space 청소 질주 모두 그대로 닿는다.
## 웅덩이 위에 서 있으면 끈적해서 살짝 느려진다 (DroneMess.covers).

const COL := Color(0.6, 0.18, 0.44)

var _parts: Array = []
var _rad := 1.0


## parts: 넘겨받을 3D 노드 (전역 위치를 유지한 채 이 잔해 밑으로 옮긴다) · rad: 잔해가 덮는 반지름
static func make(parent: Node, pos: Vector3, parts: Array, rad: float) -> InfestRemains:
	var all := parent.get_tree().get_nodes_in_group(GROUP)
	if all.size() >= MAX:
		(all[0] as DroneMess).dissolve()
	var m := InfestRemains.new()
	m.kind = Kind.GOO
	m.goo_col = COL
	m._rad = rad
	m.size_k = clampf(rad / 0.75, 0.8, 2.4)
	parent.add_child(m)
	m.global_position = pos
	m._adopt(parts)
	return m


func _ready() -> void:
	add_to_group(GROUP)
	rng.randomize()
	DroneMess._meshes()
	radius = _rad
	work_max = 1.5 * size_k
	work = work_max
	value = clampf(14.0 * size_k, 12.0, 34.0)
	# 끈적한 웅덩이: 껍질들 밑에 몇 장
	var n := 3 + int(size_k * 2.0)
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = InfestMesh.splat(i)
		mi.material_override = InfestMesh.goo_mat(true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := rng.randf() * TAU
		var r := (0.0 if i == 0 else rng.randf_range(0.2, 0.75)) * _rad
		var s := snappedf((rng.randf_range(0.9, 1.3) if i == 0 else rng.randf_range(0.45, 0.8)) * _rad, 0.05)
		var base := Vector3(s, 1.0, s * rng.randf_range(0.8, 1.0))
		mi.position = Vector3(cos(a) * r, 0.006, sin(a) * r)
		mi.rotation.y = rng.randf() * TAU
		mi.scale = base
		add_child(mi)
		blobs.append([mi, base])     # 크기는 DroneMess._process 가 매 프레임 (출렁임 · 청소 진행만큼 줄어듦)


func _adopt(parts: Array) -> void:
	var live: Array = []
	for p in parts:
		if p is Node3D and is_instance_valid(p):
			(p as Node3D).reparent(self, true)
			live.append(p)
	live.shuffle()
	for i in live.size():
		chunks.append([live[i], float(i + 1) / float(live.size() + 1), false])


## 웅덩이 위에서 느려지는 범위는 잔해 반지름의 70% 까지
func covers(p: Vector3) -> bool:
	return not done and Vector2(p.x - global_position.x, p.z - global_position.z).length() < radius * 0.7 * (1.0 - progress() * 0.7)

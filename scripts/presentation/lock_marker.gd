class_name LockMarker
extends Node3D
## 궁극기 락온 표식 (판정과 무관, Enemy.set_locked 가 붙이고 뗀다).
## 발밑에서 조여 드는 붉은 이중 고리 + 머리 위에서 내리꽂히듯 까딱이는 역삼각 화살표 + 몸을 관통하는 가는 빛기둥.
## 락온은 슬로우모션 중에 일어나므로 모든 움직임은 실제 시간(ms)으로 돈다.

const RED := Color(1.0, 0.16, 0.2)
const HOT := Color(1.0, 0.85, 0.8)

static var _torus: TorusMesh
static var _tri: PrismMesh
static var _pillar: CylinderMesh

var radius := 0.62
var height := 2.05
var _t0 := 0
var _ring_a: MeshInstance3D
var _ring_b: MeshInstance3D
var _arrows: Array[MeshInstance3D] = []
var _beam: MeshInstance3D


static func attach(en: Node3D, r: float, h: float) -> LockMarker:
	var m := LockMarker.new()
	m.radius = r
	m.height = h
	en.add_child(m)
	return m


func _ready() -> void:
	if _torus == null:
		_torus = TorusMesh.new()
		_torus.inner_radius = 0.9
		_torus.outer_radius = 1.0
		_torus.rings = 40
		_torus.ring_segments = 4
		_tri = PrismMesh.new()
		_tri.size = Vector3(0.34, 0.3, 0.08)
		_pillar = CylinderMesh.new()
		_pillar.top_radius = 1.0
		_pillar.bottom_radius = 1.0
		_pillar.height = 1.0
		_pillar.radial_segments = 8
		_pillar.rings = 1
	top_level = true
	_t0 = Time.get_ticks_msec()
	var r := radius * 1.55 + 0.35
	_ring_a = Pal.flat_mesh(_torus, RED, 2.2)
	_ring_a.scale = Vector3(r, 0.05, r)
	add_child(_ring_a)
	_ring_b = Pal.flat_mesh(_torus, HOT, 1.8)
	_ring_b.scale = Vector3(r * 0.72, 0.04, r * 0.72)
	add_child(_ring_b)
	for i in 3:
		var a := Pal.flat_mesh(_tri, RED if i > 0 else HOT, 2.4)
		a.rotation.z = PI          # 꼭짓점이 아래로
		add_child(a)
		_arrows.append(a)
	_beam = Pal.flat_mesh(_pillar, RED, 1.4)
	add_child(_beam)
	_process(0.0)


func _process(_dt: float) -> void:
	var par := get_parent() as Node3D
	if par == null:
		return
	if par.get("alive") == false:
		queue_free()
		return
	var age := (Time.get_ticks_msec() - _t0) / 1000.0
	var base := par.global_position
	base.y = Main.gy(base) + 0.06
	global_position = base
	global_rotation = Vector3.ZERO
	# 나타날 때: 크게 펼쳐졌다 0.16초 만에 조여 든다
	var k := clampf(age / 0.16, 0.0, 1.0)
	var pop := lerpf(2.4, 1.0, 1.0 - pow(1.0 - k, 3.0))
	var pulse := 1.0 + sin(age * 14.0) * 0.06
	var r := (radius * 1.55 + 0.35) * pop * pulse
	_ring_a.scale = Vector3(r, 0.05, r)
	_ring_a.rotation.y = age * 2.4
	_ring_b.scale = Vector3(r * 0.72, 0.04, r * 0.72)
	_ring_b.position.y = 0.02 + absf(sin(age * 7.0)) * 0.05
	# 머리 위 화살표 셋: 세로로 겹쳐 아래로 흐르며 까딱인다
	var top := height + 0.55 + (1.0 - k) * 1.2
	for i in _arrows.size():
		var a := _arrows[i]
		var ph := fmod(age * 2.6 + i / 3.0, 1.0)
		a.position = Vector3(0, top + (1.0 - ph) * 0.55, 0)
		var s := (0.55 + ph * 0.6) * sqrt(maxf(radius / 0.62, 1.0))
		a.scale = Vector3(s, s, s)
		a.rotation.y = age * 3.0
		a.set_instance_shader_parameter("energy", 0.6 + ph * 2.2)
	# 빛기둥: 생길 때 굵게 번쩍였다 가늘어진다
	var w := lerpf(0.5, 0.035, k) * (1.0 + sin(age * 30.0) * 0.15)
	_beam.scale = Vector3(w, top, w)
	_beam.position.y = top * 0.5
	_beam.set_instance_shader_parameter("tint", HOT.lerp(RED, k))

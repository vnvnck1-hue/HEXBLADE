class_name JumpFX
extends Node3D
## 점프 연출: Space 를 누르고 있는 동안 발밑에서 조여드는 충전 링 · 도약 충격파 · 착지 먼지.
## 플레이어를 따라가되 top_level 이라 점프해도 링은 지면에 남는다.

const COL := Color(0.3, 0.95, 1.0)

var _ring: MeshInstance3D      # 바깥에서 안쪽 목표 링으로 조여드는 링
var _goal: MeshInstance3D      # 안쪽 목표 링 (다 조여들면 점프)


func _ready() -> void:
	top_level = true
	var tor := TorusMesh.new()
	tor.inner_radius = 0.9
	tor.outer_radius = 1.0
	tor.rings = 40
	tor.ring_segments = 4
	_ring = Pal.flat_mesh(tor, COL, 1.8)
	_ring.scale = Vector3(1, 0.04, 1)
	_ring.visible = false
	add_child(_ring)
	var g := TorusMesh.new()
	g.inner_radius = 0.5
	g.outer_radius = 0.56
	g.rings = 32
	g.ring_segments = 4
	_goal = Pal.flat_mesh(g, Color(0.8, 1.0, 1.0), 1.2)
	_goal.scale = Vector3(1, 0.04, 1)
	_goal.visible = false
	add_child(_goal)


## 매 프레임: 플레이어 xz 와 지면 높이로 옮긴다
func follow(p: Vector3, ground: float) -> void:
	global_position = Vector3(p.x, ground + 0.04, p.z)


## 충전 진행 k (0 → 1). 링이 1.9배에서 목표 링까지 조여들고, 가까울수록 밝아진다.
func charge(k: float) -> void:
	_ring.visible = true
	_goal.visible = true
	var s := lerpf(1.9, 0.56, ease(k, 0.6))
	_ring.scale = Vector3(s, 0.04, s)
	_ring.set_instance_shader_parameter("energy", lerpf(1.0, 3.0, k))
	_goal.set_instance_shader_parameter("energy", 0.8 + k * 1.4)


func stop_charge() -> void:
	_ring.visible = false
	_goal.visible = false


func launch(pos: Vector3) -> void:
	stop_charge()
	FX.shockwave(pos, COL, 2.3, 0.28, 0.06)
	FX.sparks(pos + Vector3(0, 0.1, 0), 12, [Color("9a9ad8"), COL, Color.WHITE], 5.5, 0.3, -9.0, 0.07)
	FX.flash(pos + Vector3(0, 0.2, 0), Color(0.7, 1.0, 1.0), 0.8, 0.06)
	Sfx.play("dash", 0.05, -3.0)
	var ping := Sfx.play("ready", 0.0, -8.0)
	if ping:
		ping.pitch_scale = 0.7


## 착지: 떨어진 속도(fall, 양수)가 클수록 크게
func land(pos: Vector3, fall: float) -> void:
	var k := clampf(fall / 12.0, 0.25, 1.2)
	FX.land_dust(pos)
	FX.shockwave(pos, Color("8a8ae0"), 1.4 + k * 1.4, 0.25, 0.05)
	if k > 0.6:
		FX.sparks(pos + Vector3(0, 0.1, 0), 8, [Color("8a8ac8"), COL], 4.0, 0.3, -8.0, 0.07)
	Sfx.play("land", 0.1, lerpf(-12.0, -4.0, k))


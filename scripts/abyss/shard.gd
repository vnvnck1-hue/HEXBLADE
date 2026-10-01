extends Node3D
## 공명 결정 (킬 나이트의 피 보석): 적이 죽은 자리에서 튀어나온 청록 결정.
## 잠깐 바닥에 튄 뒤 가까운 플레이어에게 빨려 들어가고, 먹으면 공명(점수 배율 단계)이 오른다.

const COL := Color(0.3, 1.0, 0.72)
const MAGNET := 4.2
const LIFE := 9.0

static var _mesh: Mesh

var vel := Vector3.ZERO
var age := 0.0
var value := 1
var mi: MeshInstance3D


func _ready() -> void:
	if _mesh == null:
		var p := PrismMesh.new()
		p.size = Vector3(0.22, 0.34, 0.22)
		_mesh = p
	mi = Pal.flat_mesh(_mesh, COL, 2.6)
	add_child(mi)
	var lower := Pal.flat_mesh(_mesh, COL, 2.6)
	lower.rotation.x = PI
	lower.position.y = -0.17
	mi.add_child(lower)
	mi.position.y = 0.17
	vel = Vector3(randf_range(-3, 3), randf_range(4, 6.5), randf_range(-3, 3))


func _physics_process(dt: float) -> void:
	age += dt
	var p := Main.inst.player
	var to := p.global_position + Vector3(0, 0.8, 0) - global_position
	var d := to.length()
	if age > 0.35 and p.alive and d < MAGNET:
		# 빨려 들어간다 (가까울수록 빠르게)
		vel = vel.lerp(to.normalized() * lerpf(16.0, 6.0, d / MAGNET), 1.0 - exp(-10.0 * dt))
	else:
		vel.y -= 16.0 * dt
		vel.x *= 0.98
		vel.z *= 0.98
	global_position += vel * dt
	if global_position.y < 0.25 and d >= MAGNET:
		global_position.y = 0.25
		vel.y = absf(vel.y) * 0.35
	mi.rotation.y += dt * 5.0
	mi.position.y = 0.17 + sin(age * 6.0) * 0.05
	if age > 0.35 and d < 0.7:
		if Main.inst.has_method("on_shard"):
			Main.inst.call("on_shard", value)
		FX.flash(global_position, Color(0.7, 1.0, 0.9), 0.35, 0.06)
		queue_free()
		return
	if age > LIFE:
		queue_free()
	elif age > LIFE - 2.0:
		visible = fmod(age, 0.2) < 0.12

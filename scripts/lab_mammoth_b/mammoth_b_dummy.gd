extends Node3D
## 연출 테스트 전용 맘모스 더미. 공격·판정 없이 boss_tank.gd 모델로 달아나는 모습만 흉내 낸다.
## driving 이 false 가 되면 visual 의 transform 은 죽음 연출(mammoth_b_director.gd)이 소유한다.

const BossTank := preload("res://scripts/boss_tank.gd")
const Stage := preload("res://scripts/boss_stage.gd")

const BASE_Z := -10.5

var stage: Stage
var visual: Node3D
var model: Node3D
var tank: Dictionary
var shadow: MeshInstance3D
var driving := true
var t := 0.0
var fx_cd := 0.0
var wob := Vector2.ZERO
var wob_v := Vector2.ZERO


func _ready() -> void:
	visual = Node3D.new()
	add_child(visual)
	model = Node3D.new()
	model.rotation.y = PI           # 정면(포구)이 플레이어 쪽(+Z)
	visual.add_child(model)
	tank = BossTank.build(model)
	shadow = FX.blob_shadow(self, 9.5, 0.8)
	position = Vector3(0, 0, BASE_Z)


func _physics_process(dt: float) -> void:
	t += dt
	if not driving:
		return
	# 좌우로 천천히 흔들리며 달아난다 (본선 보스와 같은 리듬)
	var nx := sin(t * 0.33) * 3.2 + sin(t * 0.81) * 0.9
	var vx := (nx - position.x) / maxf(dt, 0.0001)
	position.x = nx
	position.z = BASE_Z + sin(t * 0.55) * 1.0
	wob_v.y += -vx * 0.02 * dt * 60.0
	wob_v += (-wob * 60.0 - wob_v * 7.0) * dt
	wob += wob_v * dt
	var rumble := sin(t * 37.0) * 0.012 + sin(t * 23.0) * 0.01
	visual.position.y = absf(sin(t * 18.0)) * 0.05
	visual.rotation = Vector3(wob.x + rumble, 0, wob.y + rumble * 0.6)
	var core := tank.core as MeshInstance3D
	core.set_instance_shader_parameter("tint", Pal.E_RED)
	core.set_instance_shader_parameter("energy", 1.6 + sin(t * 9.0) * 0.5)
	# 배기 연기와 궤도 흙먼지
	fx_cd -= dt
	if fx_cd <= 0.0 and stage:
		fx_cd = 0.06
		for side in [-1, 1]:
			stage.puff(model.to_global(Vector3(0.7 * side, 3.8, 2.95)), Color(0.75, 0.72, 0.85, 0.35), 1.3, 0.5, 0.5)
			var tr := model.to_global(Vector3(2.6 * side, 0.15, -3.2 + randf() * 0.4))
			stage.puff(tr, Color(0.55, 0.5, 0.6, 0.3), 1.2, 0.3, 0.95)
			if randf() < 0.25:
				FX.sparks(tr, 3, [Color("ffd060"), Color("ff7a30")], 4.0, 0.25, -6.0, 0.05)

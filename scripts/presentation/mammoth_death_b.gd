extends Node3D
## B storyboard presentation, currently instantiated only by mammoth_death_lab.tscn.
## Owns models/camera/effects, never invokes BossEnemy, Main, damage, defeated, or WIN.

const Tank := preload("res://scripts/boss_tank.gd")
const Road := preload("res://scripts/boss_stage.gd")
const LabFX := preload("res://scripts/presentation/mammoth_death_lab_fx.gd")
const DURATION := 5.20
const CUT_STARTS := [0.0, 0.20, 1.00, 2.00, 2.85, 3.60]
const CUT_NAMES := ["궤도 파손", "옆으로 미끄러짐", "무게 중심 붕괴", "차체 전복", "충돌과 2차 폭발", "잔해 통과"]

@export_range(0.5, 2.5, 0.1) var skid_distance := 2.0
@export_range(0.0, 1.0, 0.05) var shake_strength := 1.0
@export_range(0.0, 1.0, 0.05) var flash_strength := 1.0
@export var fixed_camera := false
@export var seed_value := 42

signal finished

var stage: Road
var camera: Camera3D
var effects: LabFX
var boss_root: Node3D
var roll_pivot: Node3D
var model: Node3D
var robot: Node3D
var robot_j: Dictionary
var tank: Dictionary
var time := 0.0
var completed := false
var cue_counts: Dictionary = {}
var flash_alpha := 0.0
var roll_degrees := 0.0
var _scrape_cd := 0.0
var _smoke_cd := 0.0
var _seeking := false


func _ready() -> void:
	stage = Road.new()
	stage.name = "PreviewRoad"
	add_child(stage)
	stage.set_process(false)
	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.near = 0.1
	camera.far = 160.0
	camera.current = true
	add_child(camera)
	effects = LabFX.new()
	effects.name = "PreviewEffects"
	add_child(effects)
	reset()


func reset() -> void:
	effects.reset(seed_value)
	if is_instance_valid(boss_root):
		boss_root.free()
	if is_instance_valid(robot):
		robot.free()
	boss_root = Node3D.new()
	boss_root.name = "MammothVisual"
	add_child(boss_root)
	roll_pivot = Node3D.new()
	roll_pivot.name = "GroundEdgeRollPivot"
	roll_pivot.position.x = 3.0
	boss_root.add_child(roll_pivot)
	model = Node3D.new()
	model.name = "TankModel"
	model.position.x = -3.0
	model.rotation.y = PI
	roll_pivot.add_child(model)
	tank = Tank.build(model)
	robot = Node3D.new()
	robot.name = "PlayerVisualOnly"
	add_child(robot)
	robot_j = Build.robot(robot)
	for key in ["jet_l", "jet_r"]:
		var jet: Node3D = robot_j[key]
		jet.visible = true
		jet.scale = Vector3(1.0, 2.0, 1.0)
	time = 0.0
	completed = false
	cue_counts.clear()
	_scrape_cd = 0.0
	_smoke_cd = 0.0
	stage.t = 0.0
	stage.scroll = 0.0
	stage.speed = 56.0
	stage.floor_mat.set_shader_parameter("scroll", 0.0)
	for i in stage.segments.size():
		stage.segments[i].position.z = Road.NEAR_Z - (i + 1) * Road.SEG_LEN
	_apply_pose()
	_camera_pose()


func advance(delta: float) -> void:
	if completed:
		return
	var remaining := minf(maxf(delta, 0.0), DURATION - time)
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / 120.0)
		time = minf(DURATION, time + step)
		remaining -= step
		_apply_pose()
		_cues()
		var simulation_step := 0.0 if time < 0.09 or (time >= 2.70 and time < 2.80) else step
		stage.speed = lerpf(56.0, 42.0, _ease(0.20, 2.70)) if time < 2.70 else lerpf(42.0, 10.0, _ease(2.70, DURATION))
		stage._process(simulation_step)
		_emit_continuous(simulation_step)
		effects.advance(simulation_step, stage.speed, stage.scroll)
	_camera_pose()
	if time >= DURATION - 0.00001:
		time = DURATION
		completed = true
		finished.emit()


func seek(target: float) -> void:
	_seeking = true
	reset()
	advance(clampf(target, 0.0, DURATION))
	_seeking = false
	effects.stop_audio()


func cut_index() -> int:
	var result := 0
	for i in CUT_STARTS.size():
		if time >= CUT_STARTS[i]:
			result = i
	return result


func _apply_pose() -> void:
	var skid := _ease(0.20, 1.00)
	boss_root.position = Vector3(skid_distance * skid, 0, -8.0 + maxf(0.0, time - 2.85) * 2.0)
	boss_root.rotation.y = deg_to_rad(20.0 * skid)
	if time < 1.0:
		roll_degrees = 0.0
	elif time < 2.0:
		roll_degrees = 35.0 * _ease(1.0, 2.0)
	elif time < 2.7:
		roll_degrees = lerpf(35.0, 90.0, pow(_range(2.0, 2.7), 1.6))
	else:
		roll_degrees = 90.0
	roll_pivot.rotation.z = -deg_to_rad(roll_degrees)
	if tank.turret.get_parent() == tank.hull:
		(tank.turret as Node3D).rotation.z = deg_to_rad(roll_degrees * 0.12 * (1.0 - _ease(2.0, 2.7)))
	for cannon in tank.cannons:
		var n: Node3D = cannon.pivot
		if model.is_ancestor_of(n):
			n.rotation.x = deg_to_rad(-12.0 * _ease(0.2, 2.0))
	var floor_min := LabFX.min_height(model)
	# Re-seat the hull after the turret detaches as well as during the roll.
	# Only pushing upward would leave the remaining wreck floating above the road.
	boss_root.position.y += 0.02 - floor_min
	if time >= 2.80 and time < 3.10:
		boss_root.position.y += sin(PI * _range(2.80, 3.10)) * 0.14
	var core: MeshInstance3D = tank.core
	core.set_instance_shader_parameter("energy", 2.4 * (1.0 - _ease(2.85, 3.6)))
	core.set_instance_shader_parameter("tint", Color("ff4a30"))
	robot.position = Vector3(-4.5 - 0.8 * _ease(0.2, 1.0), 0.42 + sin(time * 12) * 0.035, lerpf(4.5, -6.0, _ease(3.6, DURATION)))
	robot.rotation = Vector3(deg_to_rad(12), 0, deg_to_rad(3.0 * sin(time * 2.0)))
	(robot_j.hip_l as Node3D).rotation.x = -0.48
	(robot_j.hip_r as Node3D).rotation.x = -0.40
	(robot_j.knee_l as Node3D).rotation.x = 0.70
	(robot_j.knee_r as Node3D).rotation.x = 0.64
	flash_alpha = flash_strength * (_flash(0.0, 0.15, 0.28) + _flash(2.70, 0.12, 0.38) + _flash(2.85, 0.16, 0.45))


func _cues() -> void:
	if _cue("hit", 0.0):
		effects.burst((tank.core as Node3D).global_position, 28, Vector3(0, 0, 3), 9.0)
		if not _seeking:
			effects.one_shot("hit", 0.0, 0.7)
	if _cue("track", 0.10):
		# Model faces +Z, so the model's negative-X tread is on world right.
		var tread: Node3D = tank.treads[0]
		effects.burst(tread.global_position + Vector3(0, 1, 0), 28, Vector3(3, 2, 7), 8.0)
		effects.detach(tread, Vector3(5, 4.5, 8), Vector3(1.8, 1.0, -1.0))
		if not _seeking:
			effects.one_shot("clank", 2.0, 0.65)
	if _cue("impact", 2.70):
		effects.burst(boss_root.position + Vector3(3.3, 0.25, 0), 45, Vector3(0, 1, 10), 12.0)
		if not _seeking:
			effects.one_shot("launch", 3.0, 0.6)
			effects.one_shot("clank", 1.0, 0.45)
	if _cue("blast", 2.85):
		var pos := (tank.turret as Node3D).global_position
		effects.blast(pos + Vector3(0, 0.6, 0), seed_value)
		effects.detach(tank.turret, Vector3(-4.0, 7.0, 10.0), Vector3(1.2, 1.6, -2.5))
		if not _seeking:
			effects.one_shot("boom", 4.0, 0.85)


func _cue(key: String, at: float) -> bool:
	if time + 0.000001 < at or cue_counts.has(key):
		return false
	cue_counts[key] = 1
	return true


func _emit_continuous(dt: float) -> void:
	if dt <= 0:
		return
	_scrape_cd -= dt
	_smoke_cd -= dt
	if time >= 0.2 and time < 3.4 and _scrape_cd <= 0.0:
		_scrape_cd += 0.055
		var p := boss_root.position + Vector3(3.4, 0.14, 1.0)
		effects.scrape(p, 1.7 if time > 2.0 else 1.0)
		if time < 2.7:
			for side in [-0.25, 0.0, 0.25]:
				effects.skid_mark(p + Vector3(side, 0, 0), stage.scroll)
	if _smoke_cd <= 0.0:
		_smoke_cd += 0.10
		if time > 2.85:
			effects.puff(boss_root.position + Vector3(3.5, 1.6, 0), false)
		else:
			effects.puff(boss_root.position + Vector3(-0.7, 3.0, -2.8), false)


func _camera_pose() -> void:
	var eyes := [Vector3(0, 20, 12), Vector3(9, 4.4, 8), Vector3(10.5, 5.5, 11), Vector3(10.5, 2.6, 10), Vector3(9.5, 9.5, 16.5), Vector3(0, 20, 12)]
	var targets := [Vector3(0, 1.2, -4.0), Vector3(0.8, 2.0, -8), Vector3(2.3, 2.5, -8), Vector3(4.0, 2.0, -7.5), Vector3(3.5, 2.3, -6.5), Vector3(-1.5, 0.8, -3.0)]
	var fovs := [50.0, 48.0, 52.0, 52.0, 56.0, 50.0]
	var idx := cut_index()
	var previous := maxi(0, idx - 1)
	var blend_end: float = minf(DURATION, CUT_STARTS[idx] + (0.70 if idx in [1, 5] else 0.35))
	var weight := _ease(CUT_STARTS[idx], blend_end) if idx > 0 else 0.0
	var eye: Vector3 = eyes[previous].lerp(eyes[idx], weight)
	var target: Vector3 = targets[previous].lerp(targets[idx], weight)
	var fov_value: float = lerpf(fovs[previous], fovs[idx], weight)
	if time >= 2.70 and time < 2.85:
		# Pull back before the blast; do not start moving only once the flash hides it.
		var k := _ease(2.70, 2.85)
		eye = eyes[3].lerp(eyes[4], k)
		target = targets[3].lerp(targets[4], k)
		fov_value = lerpf(52.0, 56.0, k)
	if idx == 4:
		eye = eyes[4]
		target = targets[4]
		fov_value = 56.0
	if fixed_camera:
		eye = eyes[0]
		target = Vector3(1.0, 0.8, -3.0)
		fov_value = 50.0
	camera.position = eye
	camera.look_at(target, Vector3.UP)
	camera.fov = fov_value
	var impact := _flash(2.70, 0.3, 1.0) + _flash(2.85, 0.35, 0.9)
	if not fixed_camera and shake_strength > 0:
		var amplitude := impact * 0.16 * shake_strength
		camera.position += camera.basis.x * sin(time * 105.0) * amplitude + camera.basis.y * sin(time * 87.0 + 1.0) * amplitude * 0.65
		camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(4.0 * _ease(1.0, 2.0) * (1.0 - _ease(2.70, 3.6))) * shake_strength)


func refresh_options() -> void:
	_apply_pose()
	_camera_pose()


func _range(start: float, end: float) -> float:
	return clampf((time - start) / maxf(end - start, 0.001), 0.0, 1.0)


func _ease(start: float, end: float) -> float:
	var k := _range(start, end)
	return k * k * (3.0 - 2.0 * k)


func _flash(start: float, length: float, strength: float) -> float:
	return strength * pow(1.0 - clampf((time - start) / length, 0.0, 1.0), 2) if time >= start and time < start + length else 0.0


func snapshot() -> Dictionary:
	return {"time": time, "completed": completed, "cut": cut_index(), "roll": roll_degrees, "cues": cue_counts.duplicate(), "floor_min": LabFX.min_height(model), "position": boss_root.position, "sparks": effects.sparks.size(), "smoke": effects.smoke.size(), "pieces": effects.pieces.size(), "blasts": effects.blasts.size(), "fov": camera.fov}

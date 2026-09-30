extends SceneTree
## Run with: Godot --headless --path . -s tests/mammoth_death_lab_check.gd
## Checks presentation behavior, transport/UI, lobby routing, and gameplay isolation.

const LabScene := preload("res://scenes/mammoth_death_lab.tscn")
const LabFX := preload("res://scripts/presentation/mammoth_death_lab_fx.gd")
var completions := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lab = LabScene.instantiate()
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.presentation.effects.sound_enabled = false
	var p = lab.presentation
	p.finished.connect(func(): completions += 1)
	var run = root.get_node("Run")
	var before = [run.active, run.hp, run.score, run.coins, run.kills, run.sector, run.cur]
	var final_positions: Array[Vector3] = []
	lab._process(0.01)
	assert(lab.flash.color.a == 0.0, "Warmup must not hold the death flash")
	for fps in [30, 60, 144]:
		p.reset()
		while not p.completed:
			p.advance(1.0 / fps)
			assert(LabFX.min_height(p.model) >= -0.001, "Tank penetrated the road")
			assert(p.effects.sparks.size() <= LabFX.SPARK_LIMIT)
			assert(p.effects.smoke.size() <= LabFX.SMOKE_LIMIT)
			assert(p.camera.position.x < 12.0, "Camera entered highway wall")
		assert(is_equal_approx(p.time, 5.2))
		assert(is_equal_approx(p.roll_degrees, 90.0))
		assert(absf(LabFX.min_height(p.model) - 0.02) < 0.005, "Final wreck must rest on the road")
		assert(p.cue_counts == {"hit": 1, "track": 1, "impact": 1, "blast": 1})
		assert(p.effects.blasts.size() <= 1)
		assert(not p.model.is_ancestor_of(p.tank.treads[0]) if is_instance_valid(p.tank.treads[0]) else true)
		assert(not p.model.is_ancestor_of(p.tank.turret))
		final_positions.append(p.boss_root.position)
		p.advance(2.0)
	assert(completions == 3, "Completion must fire once per play")
	assert(final_positions[0].distance_to(final_positions[1]) < 0.01)
	assert(final_positions[0].distance_to(final_positions[2]) < 0.01)

	for cycle in 10:
		p.seek(2.72)
		assert(is_equal_approx(p.roll_degrees, 90.0))
		assert(p.cue_counts.has("impact") and not p.cue_counts.has("blast"))
		assert(p.effects.blasts.is_empty())
		p.seek(3.00)
		assert(p.effects.blasts.size() == 1)
		assert(p.get_child_count() == 5, "Reset leaked scene children")

	lab._seek(2.30)
	assert(not lab.playing)
	var paused_time: float = p.time
	var paused_position: Vector3 = p.boss_root.position
	lab._process(0.20)
	assert(is_equal_approx(p.time, paused_time) and p.boss_root.position == paused_position)
	lab._toggle_play()
	lab.rate = 0.5
	lab._process(0.2)
	assert(absf(p.time - paused_time - 0.1) < 0.0001)
	lab._seek(5.2)
	lab._process(3.0)
	assert(p.completed and not lab.playing, "Seeking to the end must hold the end frame")
	p.shake_strength = 0
	p.flash_strength = 0
	p.fixed_camera = true
	p.seek(2.90)
	assert(p.flash_alpha == 0.0)
	assert(p.camera.position == Vector3(0, 20, 12))
	assert(p.camera.projection == Camera3D.PROJECTION_PERSPECTIVE)
	assert(Engine.time_scale == 1.0 and Engine.physics_ticks_per_second == 60)
	assert(Main.inst == null, "The lab must not create a gameplay Main")
	assert([run.active, run.hp, run.score, run.coins, run.kills, run.sector, run.cur] == before)
	assert(Lobby.DEATH_TEST_SCENE == "res://scenes/mammoth_death_lab.tscn")
	lab._back()
	await process_frame
	await process_frame
	assert(current_scene is Lobby, "Esc/back must return to the real lobby")
	var found := false
	for child in current_scene.find_children("*", "Button", true, false):
		if child.text.begins_with("연출 테스트"):
			found = true
			child.pressed.emit()
			break
	assert(found, "Lobby has no direct presentation button")
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == Lobby.DEATH_TEST_SCENE, "Lobby button did not open the lab")
	current_scene.set_process(false)
	print("MAMMOTH_DEATH_LAB_CHECK_OK: 30/60/144fps, 10 resets and seeks, floor contact, cue/completion once, pause/rate, reduced motion, unchanged run, real lobby button and return")
	quit()

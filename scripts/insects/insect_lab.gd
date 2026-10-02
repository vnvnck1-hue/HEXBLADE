class_name InsectLab
extends Main
## Standalone combat / animation studio. 1 reset, 2 studio, 3 next pose, 4 swarm.
## --insectstudio runs an action reel through the same runtime animation driver.

var insects: Array[InsectEnemy] = []
var center := Vector3.ZERO
var studio := false
var pose_index := 0
var pose_time := 0.0
var panel: Label
var respawn_t := 0.0
var swarm := false


func _ready() -> void:
	super._ready()
	center = map.room_center_world(map.start_room)
	player.global_position = center+Vector3(0,0,4)
	camera.snap(player.global_position)
	studio = OS.get_cmdline_user_args().has("--insectstudio")
	panel = Label.new()
	panel.add_theme_font_size_override("font_size",16)
	panel.add_theme_color_override("font_color",Color("ffe5ba"))
	panel.add_theme_constant_override("outline_size",5)
	panel.add_theme_color_override("font_outline_color",Color("17131e"))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(22,-145)
	var overlay := CanvasLayer.new()
	overlay.layer = 12
	add_child(overlay)
	overlay.add_child(panel)
	_place()
	hud.banner("INSECT LAB",Color("e8bd81"),"붉은 개미 척후병 · 아이보리 굼벵이 · 2 키 애니메이션 스튜디오")
	print("INSECT_LAB ready ant+grub studio=%s" % studio)


func _build_arena() -> void:
	map = ArenaMap.new()
	world.add_child(map)
	map.terrain = false
	map.generate_single(map_seed if map_seed >= 0 else 31,ArenaMap.Shape.RECT,false,Vector2i(26,20))
	map.build()


func combat_rooms() -> int:
	return 0


func _place() -> void:
	for e in insects:
		if is_instance_valid(e):
			e.queue_free()
	insects.clear()
	pose_time = 0.0
	for i in (6 if swarm and not studio else 2):
		var e := InsectEnemy.new()
		e.kind = i%2 as InsectEnemy.Kind
		e.passive = studio
		e.log_actions = capture_mode and not studio
		e.position = center+Vector3(-2.0 if i%2 == 0 else 2.0,0,-float(i/2)*2.4)
		world.add_child(e)
		e.rotation.y = PI if studio else 0.0
		if studio:
			e.landed = true
			e.motion.reset_feet()
			var tag := Label3D.new()
			tag.text = "EMBER MANT" if e.kind == InsectEnemy.Kind.ANT else "IVORY GRUB"
			tag.font_size = 36
			tag.pixel_size = 0.006
			tag.modulate = Color("ffb07a") if e.kind == InsectEnemy.Kind.ANT else Color("fff0ca")
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.position.y = e.hp_bar_y+0.2
			e.add_child(tag)
		insects.append(e)
	respawn_t = 2.0


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	player.visible = not studio
	hud.visible = not studio
	player.invuln = maxf(player.invuln,0.1)
	player.hp = Player.MAX_HP
	if studio:
		pose_time += dt
		var mode_name: String = InsectMotion.MODES[pose_index]
		if capture_mode and pose_time > 2.6:
			pose_time = 0.0
			pose_index = (pose_index+1)%InsectMotion.MODES.size()
			mode_name = InsectMotion.MODES[pose_index]
			print("INSECT_POSE "+mode_name)
		for e in insects:
			if is_instance_valid(e):
				e.preview_mode = mode_name
				e.preview_k = fmod(pose_time,2.6)/2.6
		panel.text = "[ 벌레 애니메이션 스튜디오 ]\n%s\n1 다시 배치   2 전투 / 스튜디오   3 다음 동작   4 무리 전투\nEsc 로비" % mode_name.to_upper()
	else:
		panel.text = "[ 벌레 전투 시험장 · 플레이어 무적 ]\n개미: 빠른 추적 / 턱 돌진   굼벵이: 몸마디 수축 / 육중한 덮치기\n1 다시 배치   2 애니메이션 스튜디오   4 무리 전투   Esc 로비"
		respawn_t -= dt
		var living := 0
		for e in insects:
			if is_instance_valid(e) and e.alive:
				living += 1
		if living == 0 and respawn_t <= 0.0:
			_place()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				_place()
				return
			KEY_2:
				studio = not studio
				player.global_position = center+Vector3(0,0,4)
				_place()
				return
			KEY_3:
				pose_index = (pose_index+1)%InsectMotion.MODES.size()
				pose_time = 0.0
				return
			KEY_4:
				swarm = not swarm
				studio = false
				_place()
				return
	super._unhandled_input(event)


func _update_camera(_dt: float) -> void:
	if studio:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 8.2
		camera.global_position = center+Vector3(4,5,8)
		camera.look_at(center+Vector3(0,0.75,0),Vector3.UP)
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		super._update_camera(_dt)


func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO,"aim": p.global_position+Vector3(0,0.95,-3),"fire": false,"slash": false,"dash": false,"charge": false,"boost": false,"jump": false}
	if studio:
		return out
	var best: InsectEnemy
	var distance := INF
	for e in insects:
		if not is_instance_valid(e) or not e.alive or not e.landed:
			continue
		var d := e.global_position.distance_to(p.global_position)
		if d < distance:
			distance = d
			best = e
	if best:
		out.aim = best.global_position+Vector3(0,0.95,0)
		var dir := best.global_position-p.global_position
		dir.y = 0.0
		out.move = Vector3.ZERO if fmod(time,14.0) < 5.0 else Vector3(-dir.z,0,dir.x).normalized()*0.65
		# Wait first to exercise both species' full attack / parry cycle.
		out.fire = fmod(time,14.0) > 6.0
		out.slash = distance < 2.1 and fmod(time,14.0) > 8.0
		out.dash = fmod(time,14.0) >= 5.0 and Parry.inst != null and Parry.inst.best_threat() != null
	return out

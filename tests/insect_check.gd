extends SceneTree
## Import / grounded IK / antenna motion / attack interruption / parry / deaths / spawn queues.
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, title: String) -> void:
	print(("PASS " if ok else "FAIL ")+title)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var lab := (load("res://scenes/insects.tscn") as PackedScene).instantiate() as InsectLab
	root.add_child(lab)
	current_scene = lab
	lab.player.invuln = 9999.0
	for e in lab.insects:
		e.passive = true
	await _frames(55)
	_check(lab.insects.size() == 2,"two reusable enemy variants in lab")
	for e in lab.insects:
		e.set_physics_process(false)
		var title := "ANT" if e.kind == InsectEnemy.Kind.ANT else "GRUB"
		_check(e.landed and e.motion.legs.size() == 6,title+" emerge + six articulated legs")
		_check(e.mouth_point.global_position.y > e.global_position.y,title+" mouth attachment above ground")
		for side in ["l","r"]:
			var a := e.asset.find_child("antenna_"+side+"_0",true,false)
			_check(a != null and a.find_child("antenna_"+side+"_2",true,false) != null,title+" articulated antenna "+side)
		e.motion.reset_feet()
		var antenna: Node3D = e.motion.joints.antenna_l_2
		e.motion.pose("idle",0.0,0.0,0.01)
		var first := antenna.transform
		e.motion.pose("idle",0.0,0.0,0.25)
		_check(not first.is_equal_approx(antenna.transform),title+" antenna searches at rest")
		var body_rest := e.motion.thorax.transform
		e.motion.pose("windup",1.0,0.0,0.01)
		_check(not body_rest.is_equal_approx(e.motion.thorax.transform),title+" attack anticipation changes thorax")
		e.motion.pose("idle",0.0,0.0,0.01)
		e.motion.reset_feet()
		var max_ground_error := 0.0
		var max_slip := 0.0
		var lifts := 0
		var max_lift := 0.0
		for i in 180:
			e.position.z -= 0.007 if e.kind == InsectEnemy.Kind.ANT else 0.003
			var anchors: Array[Vector3] = []
			for l in e.motion.legs:
				anchors.append((l.tip as Node3D).global_position)
			e.motion.pose("walk",0.0,0.42 if e.kind == InsectEnemy.Kind.ANT else 0.18,1.0/60.0)
			for index in e.motion.legs.size():
				var l: Dictionary = e.motion.legs[index]
				var at := (l.tip as Node3D).global_position
				if l.swing:
					max_lift = maxf(max_lift,at.y)
					if at.y > 0.01:
						lifts += 1
				else:
					max_ground_error = maxf(max_ground_error,absf(at.y-Main.gy(at)))
					if i > 0:
						max_slip = maxf(max_slip,Vector2(at.x-anchors[index].x,at.z-anchors[index].z).length())
		_check(max_ground_error < 0.055,title+" stance feet touch ground error=%.5f" % max_ground_error)
		_check(lifts > 5,title+" swing feet lift off ground")
		print("IK %s max_stance_transition=%.4f max_lift=%.5f lifts=%d" % [title,max_slip,max_lift,lifts])
		for action in InsectMotion.MODES:
			var finite := true
			for sample in 15:
				e.motion.pose(action,float(sample)/14.0,1.5,1.0/60.0)
				finite = finite and e.motion.body.transform.is_finite() and e.motion.head.transform.is_finite()
			_check(finite,title+" finite "+action)
		e.motion.pose("idle",0.0,0.0,0.01)
		e.hp = 100
		e.max_hp = 100
		e.act = InsectEnemy.Act.WINDUP
		e.warn_glow = true
		Parry.inst.register(e)
		e.take_hit(1,Vector3.RIGHT,e.global_position+Vector3.UP)
		_check(e.act == InsectEnemy.Act.RECOVER and e.hurt_t > 0.0 and not e.warn_glow and not Parry.inst.threats.has(e),title+" hurt interrupts attack and unregisters parry")
		e.stagger(Vector3.RIGHT,1.2)
		_check(e.stagger_t > 0.0 and e.act == InsectEnemy.Act.RECOVER,title+" parry stagger stops attack")
		e.hurt_t = 0.0
		e.stagger_t = 0.0
		var before_hp := lab.player.hp
		e.act = InsectEnemy.Act.ATTACK
		e.act_t = 0.1
		e.passive = false
		if e._target_has_hidden:
			lab.player.set("hidden",true)
		else:
			lab.player.set_meta("insect_hidden",true)
		e._ai(0.02)
		_check(e.act == InsectEnemy.Act.RECOVER and lab.player.hp == before_hp,title+" hidden target cancels active attack")
		if e._target_has_hidden:
			lab.player.set("hidden",false)
		else:
			lab.player.remove_meta("insect_hidden")
		e.passive = true
		e.set_locked(true)
		var kills_before := lab.kills
		e.die(Vector3.RIGHT,"slash")
		e.die(Vector3.RIGHT,"slash")
		_check(not e.alive and e.dying and not e.is_in_group("enemies") and lab.kills == kills_before+1,title+" death reports exactly one kill")
		e.set_physics_process(true)
	lab.respawn_t = 999.0
	await _frames(150)
	var gone := true
	for e in lab.insects:
		gone = gone and not is_instance_valid(e)
	_check(gone,"organic death animation removes both enemies")
	# Inherited queue is also used by the live sector-run scenes.
	var counts := {Main.INSECT_ANT:0,Main.INSECT_GRUB:0}
	for n in 20:
		lab._fill_queue(10,2)
		_check(lab.spawn_queue.size() == 10,"queue count preserved "+str(n))
		for code in lab.spawn_queue:
			if counts.has(code):
				counts[code] += 1
	_check(counts[Main.INSECT_ANT] == 24 and counts[Main.INSECT_GRUB] == 20,"main queue: ant 12% / grub 10%")
	for kind_name in ["ant","grub"]:
		var reusable := (load("res://scenes/enemies/insect_"+kind_name+".tscn") as PackedScene).instantiate() as InsectEnemy
		reusable.passive = true
		lab.world.add_child(reusable)
		_check(reusable.kind == (InsectEnemy.Kind.ANT if kind_name == "ant" else InsectEnemy.Kind.GRUB),"reusable "+kind_name+" scene chooses correct model")
		reusable.queue_free()
	lab.spawn_queue.clear()
	lab.active_room = lab.map.start_room
	lab._spawn(Main.INSECT_ANT)
	lab._spawn(Main.INSECT_GRUB)
	await _frames(50)
	var actual_kinds := {}
	for spawned in get_nodes_in_group("enemies"):
		if spawned is InsectEnemy:
			actual_kinds[(spawned as InsectEnemy).kind] = true
	_check(actual_kinds.has(InsectEnemy.Kind.ANT) and actual_kinds.has(InsectEnemy.Kind.GRUB),"main deferred spawn factory creates both real variants")
	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED",fails])
	lab.queue_free()
	await process_frame
	quit(1 if fails else 0)

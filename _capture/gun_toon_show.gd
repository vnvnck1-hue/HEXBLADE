extends SceneTree
## 손그림 플립북 총기 연출(ToonGunFX) 시연: 어두운 격자 바닥 위에서 연사 → 예광 → 착탄.
## godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie DIR/f.png -s _capture/gun_toon_show.gd

const SPEED := 60.0

var world: Node3D
var fx: ToonGunFX
var cam: Camera3D
var shots: Array = []   # {node, dir, dist, max}


func _initialize() -> void:
	world = Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.012, 0.014)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.34)
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	# 격자 바닥
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wp.xz / 2.0) - 0.5);
	float l = smoothstep(0.485, 0.5, max(g.x, g.y));
	ALBEDO = mix(vec3(0.018), vec3(0.06), l);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	floor.material_override = m
	world.add_child(floor)
	fx = ToonGunFX.new()
	world.add_child(fx)
	cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 38
	cam.look_at_from_position(Vector3(0, 13.0, 11.0), Vector3(0, 0, -1.0))
	_run.call_deferred()


func _run() -> void:
	await create_timer(0.1).timeout
	var gun := Vector3(-7.5, 0.95, 3.2)
	var target := Vector3(3.0, 0.95, -2.5)
	for i in 14:
		var aim := (target + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)) - gun)
		aim.y = 0
		var d := aim.normalized()
		ToonGunFX.muzzle(gun, d, 1.0)
		var n := Node3D.new()
		world.add_child(n)
		n.global_position = gun + d * 0.2
		n.add_child(ToonGunFX.tracer().setup(d))
		shots.append({"node": n, "dir": d, "dist": 0.0, "max": aim.length()})
		for f in (5 if i < 13 else 1):
			await physics_frame
	await create_timer(1.2).timeout
	quit()



func _physics_process(dt: float) -> bool:
	var i := shots.size() - 1
	while i >= 0:
		var s: Dictionary = shots[i]
		var n: Node3D = s.node
		s.dist += SPEED * dt
		if s.dist >= s.max:
			n.global_position += s.dir * (s.max - (s.dist - SPEED * dt))
			ToonGunFX.impact(n.global_position, -s.dir, 1.0)
			n.queue_free()
			shots.remove_at(i)
		else:
			n.global_position += s.dir * SPEED * dt
		i -= 1
	return false

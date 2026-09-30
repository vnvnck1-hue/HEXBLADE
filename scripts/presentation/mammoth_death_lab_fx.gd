extends Node3D
## Test-scene-only effects. Every simulation uses the lab clock, including pause/seek.
## No damage, Main singleton, score, run state, or scene transition calls.

const Explosion := preload("res://scripts/explosion_fx.gd")
const SPARK_LIMIT := 160
const SMOKE_LIMIT := 48
const COLORS := [Color("ffecc0"), Color("ffb840"), Color("ff6c20")]

var rng := RandomNumberGenerator.new()
var sparks: Array[Dictionary] = []
var smoke: Array[Dictionary] = []
var pieces: Array[Dictionary] = []
var blasts: Array[Node3D] = []
var rings: Array[Dictionary] = []
var marks: Array[Dictionary] = []
var spark_mm: MultiMesh
var smoke_mm: MultiMesh
var engine_voice: AudioStreamPlayer
var scrape_voice: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var sound_bank: Dictionary = {}
var sound_enabled := true

const SMOKE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_never;
void fragment() {
	float edge = pow(max(dot(NORMAL, VIEW), 0.0), 0.65);
	ALBEDO = COLOR.rgb * (0.65 + 0.35 * max(NORMAL.y, 0.0));
	ALPHA = COLOR.a * edge;
}
"""


func _ready() -> void:
	spark_mm = MultiMesh.new()
	spark_mm.transform_format = MultiMesh.TRANSFORM_3D
	spark_mm.use_colors = true
	spark_mm.instance_count = SPARK_LIMIT
	spark_mm.visible_instance_count = 0
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.055, 0.055, 0.22)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.4, 0.8, 0.3)
	spark_mesh.material = spark_mat
	spark_mm.mesh = spark_mesh
	var spark_node := MultiMeshInstance3D.new()
	spark_node.multimesh = spark_mm
	spark_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spark_node.custom_aabb = AABB(Vector3(-35, -5, -45), Vector3(70, 40, 110))
	add_child(spark_node)

	smoke_mm = MultiMesh.new()
	smoke_mm.transform_format = MultiMesh.TRANSFORM_3D
	smoke_mm.use_colors = true
	smoke_mm.instance_count = SMOKE_LIMIT
	smoke_mm.visible_instance_count = 0
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.5
	smoke_mesh.height = 1.0
	smoke_mesh.radial_segments = 12
	smoke_mesh.rings = 6
	var shader := Shader.new()
	shader.code = SMOKE_SHADER
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = shader
	smoke_mesh.material = smoke_mat
	smoke_mm.mesh = smoke_mesh
	var smoke_node := MultiMeshInstance3D.new()
	smoke_node.multimesh = smoke_mm
	smoke_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke_node.custom_aabb = spark_node.custom_aabb
	add_child(smoke_node)


func bind_audio(bank: Dictionary) -> void:
	sound_bank = bank
	engine_voice = AudioStreamPlayer.new()
	engine_voice.stream = bank.get("boost")
	add_child(engine_voice)
	scrape_voice = AudioStreamPlayer.new()
	scrape_voice.stream = _scrape_stream()
	add_child(scrape_voice)
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)


func reset(seed_value: int) -> void:
	rng.seed = seed_value
	sparks.clear()
	smoke.clear()
	for p in pieces:
		if is_instance_valid(p.node):
			p.node.free()
	pieces.clear()
	for b in blasts:
		if is_instance_valid(b):
			b.free()
	blasts.clear()
	for r in rings:
		if is_instance_valid(r.node):
			r.node.free()
	rings.clear()
	for mark in marks:
		if is_instance_valid(mark.node):
			mark.node.free()
	marks.clear()
	spark_mm.visible_instance_count = 0
	smoke_mm.visible_instance_count = 0
	stop_audio()


func burst(pos: Vector3, count: int, bias := Vector3.ZERO, power := 8.0) -> void:
	for i in mini(count, SPARK_LIMIT - sparks.size()):
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(power * 0.4, power)
		sparks.append({"pos": pos, "vel": v + bias, "age": 0.0, "life": rng.randf_range(0.2, 0.55), "color": COLORS[rng.randi_range(0, 2)]})


func scrape(pos: Vector3, strength := 1.0) -> void:
	burst(pos, int(5 * strength), Vector3(-1.0, 0.5, 13.0), 7.0)
	if smoke.size() < SMOKE_LIMIT:
		smoke.append({"pos": pos + Vector3(0, 0.2, 0), "vel": Vector3(0.0, 1.0, 7.0), "age": 0.0, "life": 0.7, "size": rng.randf_range(0.6, 1.1), "color": Color(0.32, 0.29, 0.35, 0.35)})


func puff(pos: Vector3, hot := false) -> void:
	if smoke.size() >= SMOKE_LIMIT:
		return
	smoke.append({"pos": pos, "vel": Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(1.0, 2.5), 3.0), "age": 0.0, "life": rng.randf_range(0.8, 1.5), "size": rng.randf_range(1.2, 2.0), "color": Color(0.17, 0.14, 0.18, 0.52) if not hot else Color(1.0, 0.3, 0.08, 0.5)})


func detach(node: Node3D, velocity: Vector3, spin: Vector3) -> void:
	if not is_instance_valid(node) or node.get_parent() == self:
		return
	node.reparent(self, true)
	pieces.append({"node": node, "vel": velocity, "spin": spin, "age": 0.0, "life": 5.0, "grounded": false})


func blast(pos: Vector3, seed_value: int) -> void:
	var e := Explosion.spawn(self, pos, 2.5, 0.0, seed_value)
	e.set_process(false)
	blasts.append(e)
	burst(pos, 55, Vector3(0, 2, 4), 12.0)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.85
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 8
	var ring_node := MeshInstance3D.new()
	ring_node.mesh = ring_mesh
	ring_node.material_override = Pal.lit(Color("ffc87a"), 2.0)
	ring_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_node.position = Vector3(pos.x, 0.12, pos.z)
	add_child(ring_node)
	rings.append({"node": ring_node, "age": 0.0, "life": 0.45})
	for i in 12:
		var chunk := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(rng.randf_range(0.25, 0.8), rng.randf_range(0.2, 0.45), rng.randf_range(0.3, 0.9))
		chunk.mesh = mesh
		chunk.material_override = Pal.lit(Color("595a70"))
		add_child(chunk)
		chunk.global_position = pos + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.8), rng.randf_range(-1, 1))
		pieces.append({"node": chunk, "vel": Vector3(rng.randf_range(-6, 6), rng.randf_range(5, 11), rng.randf_range(3, 10)), "spin": Vector3(rng.randf_range(-3, 3), rng.randf_range(-4, 4), 3.0), "age": 0.0, "life": 3.0, "grounded": false})


func skid_mark(pos: Vector3, scroll: float) -> void:
	if marks.size() >= 28:
		return
	var n := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.17, 2.2)
	n.mesh = mesh
	n.material_override = Pal.lit(Color("16111a"))
	n.position = Vector3(pos.x, 0.018, pos.z)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	marks.append({"node": n, "z": pos.z, "scroll": scroll, "age": 0.0})


func advance(dt: float, road_speed: float, road_scroll: float) -> void:
	for i in range(sparks.size() - 1, -1, -1):
		var s: Dictionary = sparks[i]
		s.age += dt
		if s.age >= s.life:
			sparks.remove_at(i)
			continue
		s.vel.y -= 17.0 * dt
		s.pos += s.vel * dt
		if s.pos.y < 0.05:
			s.pos.y = 0.05
			s.vel.y = absf(s.vel.y) * 0.2
	for i in sparks.size():
		var s: Dictionary = sparks[i]
		var v: Vector3 = s.vel
		var basis := Basis.looking_at(v.normalized() if v.length_squared() > 0.001 else Vector3.FORWARD)
		basis = basis.scaled(Vector3.ONE * maxf(0.05, 1.0 - float(s.age) / float(s.life)))
		spark_mm.set_instance_transform(i, Transform3D(basis, s.pos))
		spark_mm.set_instance_color(i, s.color)
	spark_mm.visible_instance_count = sparks.size()
	for i in range(smoke.size() - 1, -1, -1):
		var s: Dictionary = smoke[i]
		s.age += dt
		if s.age >= s.life:
			smoke.remove_at(i)
			continue
		s.pos += s.vel * dt
	for i in smoke.size():
		var s: Dictionary = smoke[i]
		var k := float(s.age) / float(s.life)
		var col: Color = s.color
		col.a *= sin(PI * k)
		smoke_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(s.size) * (0.7 + k)), s.pos))
		smoke_mm.set_instance_color(i, col)
	smoke_mm.visible_instance_count = smoke.size()
	for i in range(pieces.size() - 1, -1, -1):
		var p: Dictionary = pieces[i]
		var n: Node3D = p.node
		p.age += dt
		if p.age >= p.life or n.global_position.z > 45:
			n.free()
			pieces.remove_at(i)
			continue
		p.vel.y -= 22.0 * dt
		n.global_position += p.vel * dt
		var spin: Vector3 = p.spin
		if spin.length_squared() > 0.001:
			n.rotate(spin.normalized(), spin.length() * dt)
		var bottom := min_height(n)
		if bottom < 0.03:
			n.global_position.y += 0.03 - bottom
			p.vel.y = absf(p.vel.y) * 0.22 if p.vel.y < -3.0 else 0.0
			p.vel.x *= exp(-4.0 * dt)
			p.vel.z = lerpf(float(p.vel.z), road_speed * 0.35, 1.0 - exp(-3.0 * dt))
			p.spin *= exp(-4.0 * dt)
			if not p.grounded:
				p.grounded = true
				burst(n.global_position, 8, Vector3(0, 0, 4), 4.0)
	for i in range(blasts.size() - 1, -1, -1):
		var e: Node3D = blasts[i]
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			blasts.remove_at(i)
			continue
		e.position.z += road_speed * 0.06 * dt
		e._process(dt)
	for i in range(rings.size() - 1, -1, -1):
		var r: Dictionary = rings[i]
		r.age += dt
		if r.age >= r.life:
			r.node.free()
			rings.remove_at(i)
			continue
		var k := float(r.age) / float(r.life)
		r.node.scale = Vector3(1, 0.06, 1) * (0.8 + 5.2 * (1.0 - pow(1.0 - k, 3)))
	for i in range(marks.size() - 1, -1, -1):
		var m: Dictionary = marks[i]
		m.age += dt
		m.node.position.z = float(m.z) + road_scroll - float(m.scroll)
		if m.age > 2.0 or m.node.position.z > 38:
			m.node.free()
			marks.remove_at(i)


static func min_height(node: Node3D) -> float:
	var lowest := INF
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for item in meshes:
		var mi := item as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var bounds := mi.mesh.get_aabb()
		for corner in 8:
			var p := bounds.position + Vector3(bounds.size.x if corner & 1 else 0.0, bounds.size.y if corner & 2 else 0.0, bounds.size.z if corner & 4 else 0.0)
			lowest = minf(lowest, (mi.global_transform * p).y)
	return lowest if lowest != INF else node.global_position.y


func one_shot(id: String, volume := 0.0, pitch := 1.0) -> void:
	if not sound_enabled or not sound_bank.has(id):
		return
	for p in voices:
		if not p.playing:
			p.stream = sound_bank[id]
			p.pitch_scale = pitch
			p.volume_db = volume
			p.play()
			return


func update_audio(time: float, rate: float, playing: bool) -> void:
	if engine_voice == null:
		return
	var audible := playing and sound_enabled
	engine_voice.stream_paused = not audible
	scrape_voice.stream_paused = not audible
	if audible and not engine_voice.playing and time < 3.6:
		engine_voice.play()
	engine_voice.pitch_scale = clampf((0.6 + 0.4 * (1.0 - time / 5.2)) * rate, 0.3, 1.8)
	engine_voice.volume_db = -22.0 - 22.0 * clampf((time - 2.7) / 1.1, 0, 1)
	if audible and time > 0.2 and time < 3.45:
		if not scrape_voice.playing:
			scrape_voice.play()
		scrape_voice.pitch_scale = clampf(rate * 0.85, 0.3, 1.8)
		scrape_voice.volume_db = -14.0 + 5.0 * clampf((time - 1.0) / 1.7, 0, 1)
	else:
		scrape_voice.stop()
	if time >= 3.6:
		engine_voice.stop()
	for p in voices:
		p.stream_paused = not audible


func stop_audio() -> void:
	if engine_voice:
		engine_voice.stop()
		scrape_voice.stop()
	for p in voices:
		p.stop()


func _scrape_stream() -> AudioStreamWAV:
	var source := RandomNumberGenerator.new()
	source.seed = 73
	var samples := 11025
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var filtered := 0.0
	for i in samples:
		var t := float(i) / 22050.0
		filtered = lerpf(filtered, source.randf_range(-1, 1), 0.38)
		var sample := filtered * 0.65 + sin(TAU * 173 * t) * 0.10 + sin(TAU * 611 * t) * 0.05
		bytes.encode_s16(i * 2, int(clampf(sample, -1, 1) * 24000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = samples
	return stream

extends "res://scripts/texture_diorama.gd"
## Selected cream/lavender art, sampled directly on private mesh UVs.
## User-requested low saturation/value correction; original paint and UVs preserved.
const FLOOR_ART := preload("res://assets/textures/painted_room/floor_room.png")
const PANEL_ART := preload("res://assets/textures/painted_room/wall_panel.png")
const FRAME_ART := preload("res://assets/textures/painted_room/wall_frame.png")
const PALETTE_SHADER := preload("res://scripts/presentation/painted_room_palette.gdshader")
const MUTED_SATURATION := 0.18
const MUTED_BRIGHTNESS := 0.22
const STUDY_OUTPUT := "res://output/painted-room-muted-20261012"

var study_enabled := [true, true]
var study_meshes: Dictionary = {}
var study_materials: Array[ShaderMaterial] = []
var unlit_shader: Shader
var raw_color := false
var _built := false

func _ready() -> void:
	super._ready()
	unlit_shader = Shader.new()
	unlit_shader.code = PALETTE_SHADER.code.replace("diffuse_burley, specular_disabled", "unshaded")
	study_materials.assign([_material(FLOOR_ART), _material(PANEL_ART), _material(FRAME_ART)])
	for entry in surfaces:
		if entry.group > 1:
			continue
		var mi: MeshInstance3D = entry.mesh
		if study_meshes.has(mi.get_instance_id()):
			continue
		study_meshes[mi.get_instance_id()] = {"node": mi, "original": mi.mesh, "painted": _remap(mi, entry.group)}
	_built = true
	var panel_box: VBoxContainer = category_select.get_parent()
	(panel_box.get_parent() as PanelContainer).offset_top = 90
	_button(panel_box, "3안 바닥·벽 다시 보기", restore_study)
	_button(panel_box, "보정색 ↔ 조명 받기", toggle_raw_color)
	_button(panel_box, "가구·설비 보기 / 숨기기", toggle_props)
	for label in ui.find_children("*", "Label", true, false):
		if label.text == "HEXBLADE  /  MATERIAL LAB":
			label.text = "HEXBLADE  /  HAND-PAINTED ROOM"
		elif label.text.begins_with("텍스처링 디오라마"):
			label.text = "선택 원화 3안  ·  바닥 / 벽 저채도·저명도 보정"
	apply_materials()
	print("PAINTED_ROOM_READY private_meshes=%d textures=3" % study_meshes.size())

func _material(texture_: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PALETTE_SHADER
	mat.set_shader_parameter("artwork", texture_)
	mat.set_shader_parameter("saturation", MUTED_SATURATION)
	mat.set_shader_parameter("brightness", MUTED_BRIGHTNESS)
	return mat

func set_palette(saturation_: float, brightness_: float) -> void:
	for mat in study_materials:
		mat.set_shader_parameter("saturation", clampf(saturation_, 0.0, 1.0))
		mat.set_shader_parameter("brightness", clampf(brightness_, 0.0, 1.0))

func set_light(index: int) -> void:
	super.set_light(index)
	# This inherited lab has no sky resource. Use the explicit color fill used by
	# Main, so changing sun direction does not turn painted panels black.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

func apply_materials() -> void:
	# Restore the one-surface source before the base lab applies its overrides.
	for record in study_meshes.values():
		var mi: MeshInstance3D = record.node
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, null)
		mi.mesh = record.original
	super.apply_materials()
	if not _built or reference:
		return
	for entry in surfaces:
		if entry.group > 1 or not study_enabled[entry.group] or settings[entry.group].texture != null:
			continue
		var mi: MeshInstance3D = entry.mesh
		var mesh_: ArrayMesh = study_meshes[mi.get_instance_id()].painted
		mi.mesh = mesh_
		for i in mesh_.get_surface_count():
			var role: int = mesh_.get_meta("roles")[i]
			mi.set_surface_override_material(i, study_materials[role])
	_update_status()

func reset_category() -> void:
	if selected < 2:
		study_enabled[selected] = false
	super.reset_category()

func restore_study() -> void:
	study_enabled = [true, true]
	for i in 2:
		settings[i].texture = null
	reference = false
	apply_materials()

func toggle_raw_color() -> void:
	raw_color = not raw_color
	for mat in study_materials:
		mat.shader = unlit_shader if raw_color else PALETTE_SHADER
	_update_status()

func toggle_props() -> void:
	var props: Node3D = get_node("Diorama/Props")
	props.visible = not props.visible
	(get_node("Diorama/Machinery") as Node3D).visible = props.visible

func _update_status() -> void:
	super._update_status()
	if _built and not reference and selected < 2 and study_enabled[selected] and settings[selected].texture == null:
		source_label.text = ("방 전체 바닥 원화 PNG" if selected == 0 else "크림 패널 + 보라 프레임 PNG") + "\n저채도·저명도 / " + ("보정색 확인" if raw_color else "실제 조명 적용")
		status.text = "%s 시점 / %s / 저채도·저명도 원화" % [VIEW_NAMES[view_mode], ["중립 조명", "본편 조명", "측광"][light_mode]]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F12:
		save_capture(STUDY_OUTPUT + "/preview.png")
		return
	super._unhandled_input(event)

# Separate the disconnected modeled parts using welded position keys. UV seams
# duplicate vertices in glTF, so index adjacency alone would fragment a panel.
func _root_of(parents: PackedInt32Array, i: int) -> int:
	while parents[i] != i:
		parents[i] = parents[parents[i]]
		i = parents[i]
	return i

func floor_uv(world: Vector3) -> Vector2:
	# Align the generated painting's drawn joints to the existing 2m slabs.
	# Only UV placement changes; PNG pixels and all source geometry stay intact.
	return Vector2(_axis_uv((world.x + 4.0) / 2.0, [0.0, 0.284, 0.5, 0.715, 1.0]), _axis_uv((world.z + 3.0) / 2.0, [0.0, 0.214, 0.515, 1.0]))

func _axis_uv(t: float, joints: Array) -> float:
	var i := clampi(int(floor(t)), 0, joints.size() - 2)
	return lerpf(joints[i], joints[i + 1], clampf(t - i, 0.0, 1.0))

func _remap(mi: MeshInstance3D, group: int) -> ArrayMesh:
	var result := ArrayMesh.new()
	var bins := [{"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array()}, {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array()}]
	var panel_count := 0
	for surface in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		var parents := PackedInt32Array()
		parents.resize(vertices.size())
		var welded := {}
		for i in vertices.size():
			parents[i] = i
			var p := vertices[i]
			var key := Vector3i(roundi(p.x * 100000), roundi(p.y * 100000), roundi(p.z * 100000))
			if welded.has(key):
				parents[i] = welded[key]
			else:
				welded[key] = i
		for j in range(0, indices.size(), 3):
			var a := _root_of(parents, indices[j])
			for k in range(1, 3):
				var b := _root_of(parents, indices[j + k])
				parents[b] = a
		var bounds := {}
		for i in vertices.size():
			var key := _root_of(parents, i)
			if not bounds.has(key):
				bounds[key] = AABB(vertices[i], Vector3.ZERO)
			else:
				bounds[key] = (bounds[key] as AABB).expand(vertices[i])
		var panels := {}
		if group == 1:
			for key in bounds:
				var box: AABB = bounds[key]
				var dimensions := [box.size.x, box.size.y, box.size.z]
				dimensions.sort()
				# Actual thin inset panels; not source texture brightness guessing.
				if dimensions[0] < 0.081 and dimensions[1] > 0.25 and dimensions[2] > 0.35 and box.position.y > 0.09:
					panels[key] = true
					panel_count += 1
		for j in range(0, indices.size(), 3):
			var key := _root_of(parents, indices[j])
			var box: AABB = bounds[key]
			var n := (normals[indices[j]] + normals[indices[j + 1]] + normals[indices[j + 2]]).normalized()
			var first_role := group == 0 and mi.name != "ServiceDeck" and n.y > 0.5
			first_role = first_role or (group == 1 and panels.has(key))
			var bin: Dictionary = bins[0 if first_role else 1]
			for k in 3:
				var i := indices[j + k]
				var p := vertices[i]
				var uv: Vector2
				if group == 0 and first_role:
					var world := mi.global_transform * p
					uv = floor_uv(world)
				elif group == 1 and first_role:
					if box.size.z < box.size.x:
						uv = Vector2((p.x - box.position.x) / box.size.x, 1.0 - (p.y - box.position.y) / box.size.y)
					else:
						uv = Vector2((p.z - box.position.z) / box.size.z, 1.0 - (p.y - box.position.y) / box.size.y)
				else:
					var an := n.abs()
					uv = Vector2(p.x, p.z) if an.y >= maxf(an.x, an.z) else (Vector2(p.z, -p.y) if an.x > an.z else Vector2(p.x, -p.y))
					# Whole component shares a broad portion of the artwork, including bevels.
					uv = uv / 3.0 + Vector2(0.35, 0.65)
				bin.v.append(p)
				bin.n.append(normals[i])
				bin.uv.append(uv.clamp(Vector2.ZERO, Vector2.ONE))
	var roles: Array[int] = []
	for i in 2:
		if bins[i].v.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bins[i].v
		arrays[Mesh.ARRAY_NORMAL] = bins[i].n
		arrays[Mesh.ARRAY_TEX_UV] = bins[i].uv
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		roles.append((0 if group == 0 else 1) if i == 0 else 2)
	result.set_meta("roles", roles)
	result.set_meta("panel_count", panel_count)
	return result

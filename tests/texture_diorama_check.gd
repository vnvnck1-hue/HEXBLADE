extends SceneTree
## Real geometry coverage, shared-resource isolation and working material controls.
const SCENE := preload("res://scenes/texture_diorama.tscn")
var fails := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + title)

func bounds(node: Node3D) -> AABB:
	var first := true
	var result := AABB()
	var children: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		children.append(node)
	for mi: MeshInstance3D in children:
		var box := mi.global_transform * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _run() -> void:
	var studio = SCENE.instantiate()
	root.add_child(studio)
	await process_frame
	var floors := studio.get_node("Diorama/Floors")
	check(floors.get_child_count() == 13, "12 actual F01 floor modules plus lower service deck")
	var area := 0.0
	var tiles: Array[AABB] = []
	for node: Node3D in floors.get_children():
		if node.name == "ServiceDeck":
			continue
		var box := bounds(node)
		area += box.size.x * box.size.z
		tiles.append(box)
	var overlap := false
	for i in tiles.size():
		for j in range(i + 1, tiles.size()):
			var intersection := tiles[i].intersection(tiles[j])
			overlap = overlap or (intersection.size.x > 0.001 and intersection.size.z > 0.001)
	check(absf(area - 48) < 0.01 and not overlap, "8 x 6m main floor covered once without overlap")
	check(absf(bounds(floors.get_node("ServiceDeck")).end.y + 0.8) < 0.0001, "service floor is 0.8m lower")
	check(studio.get_node("Diorama/Walls").get_child_count() == 11, "L wall plus real cover, pillar and low wall samples")
	check(studio.get_node("Diorama/Props").get_child_count() == 4 and studio.get_node("Diorama/Machinery").get_child_count() == 6, "workbench / locker / wall props and all five machinery types")
	var bench := bounds(studio.get_node("Diorama/Props/Workbench"))
	var locker := bounds(studio.get_node("Diorama/Props/Locker"))
	check(bench.intersection(locker).get_volume() < 0.0001 and bench.position.z > -3 and locker.position.z > -3, "bench and locker have wall clearance and do not overlap")
	var pipe := studio.get_node("Diorama/Machinery/StraightPipe")
	var elbow := studio.get_node("Diorama/Machinery/ElbowPipe")
	check(pipe.find_child("pt_end_b", true, false).global_position.is_equal_approx(elbow.find_child("pt_end_b", true, false).global_position), "actual pipe attachment ends coincide")
	var supported := true
	for machine: Node3D in studio.get_node("Diorama/Machinery").get_children():
		var box := bounds(machine)
		supported = supported and box.position.x >= -4.01 and box.end.x <= 4.01 and box.position.z >= 2.99 and box.end.z <= 5.01 and absf(box.position.y + 0.8) < 0.01
	check(supported, "all machinery rests on the lower deck within its footprint")
	var snapshots: Array = []
	var complete := true
	for entry in studio.surfaces:
		var mi: MeshInstance3D = entry.mesh
		snapshots.append({"mesh": mi.mesh, "source": mi.mesh.surface_get_material(entry.surface), "transform": mi.transform})
		complete = complete and mi.get_active_material(entry.surface) == entry.original
	check(complete and studio.surfaces.size() >= 30, "all imported mesh surfaces start with local game material copies")
	var phased := true
	for entry in studio.surfaces:
		if entry.group == 0 and entry.mesh.name != "ServiceDeck":
			phased = phased and entry.original.get_shader_parameter("offset") == Vector2(0, 1)
	check(phased, "original floor grout phase follows the saved 2m module boundaries")
	var tex: Texture2D = studio.checker_texture()
	studio.set_texture(1, tex, "test")
	var scoped := true
	for entry in studio.surfaces:
		var mi: MeshInstance3D = entry.mesh
		var actual := mi.get_active_material(entry.surface)
		scoped = scoped and (actual == entry.preview if entry.group == 1 else actual == entry.original)
	check(scoped, "wall replacement does not touch floor, props or machinery")
	studio.settings[1].repeat = 2.0
	studio.settings[1].rough = 0.35
	studio.settings[1].metal = 0.6
	studio.apply_materials()
	var projected := true
	for entry in studio.surfaces:
		if entry.group == 1:
			var mat: StandardMaterial3D = entry.preview
			projected = projected and mat.uv1_world_triplanar and mat.uv1_scale == Vector3(2, 2, 2) and is_equal_approx(mat.roughness, 0.35) and is_equal_approx(mat.metallic, 0.6)
	check(projected and tex.get_image().has_mipmaps(), "world projection / repeat / PBR controls and real mipmapped texture")
	studio.toggle_reference()
	var restored := true
	for entry in studio.surfaces:
		restored = restored and entry.mesh.get_active_material(entry.surface) == entry.original
	check(restored, "B comparison restores original materials while keeping preview settings")
	studio.toggle_reference()
	studio.settings[1].world = false
	studio.apply_materials()
	var uv_mode := true
	for entry in studio.surfaces:
		if entry.group == 1:
			uv_mode = uv_mode and not entry.preview.uv1_triplanar
	check(uv_mode, "original model UV mode works independently of world projection")
	studio.file_category = 0
	check(studio.load_texture_file(ProjectSettings.globalize_path("res://assets/textures/handpaint_blue/floor_hearthstone.png")), "image file loads through the same path as the open dialog")
	studio.selected = 0
	studio.reset_category()
	check(studio.settings[0].texture == null and studio.settings[1].texture == tex, "R resets only the selected category")
	var untouched := true
	for i in studio.surfaces.size():
		var entry: Dictionary = studio.surfaces[i]
		var mi: MeshInstance3D = entry.mesh
		untouched = untouched and mi.mesh == snapshots[i].mesh and mi.mesh.surface_get_material(entry.surface) == snapshots[i].source and mi.transform == snapshots[i].transform
	check(untouched, "texture edits preserve shared mesh, source materials and model transforms")
	for index in 5:
		studio.set_view(index)
		check(studio.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and studio.camera.position.distance_to(studio.target) > 10, "view %d has a usable camera" % (index + 1))
	studio.set_light(1)
	check(studio.sun.light_color == BrawlLook.SUN_COLOR and studio.environment.ambient_light_color == BrawlLook.AMBIENT, "game lighting matches current game constants")
	studio.set_light(0)
	check(studio.sun.light_color == Color.WHITE and studio.environment.ambient_light_color == Color.WHITE, "neutral lighting removes colored illumination")
	check(Lobby.TEST_SCENES.any(func(entry: Dictionary): return entry.scene == "res://scenes/texture_diorama.tscn"), "scene is reachable from the lobby")
	# Simulate a source material already dressed by a previous main-game visit.
	var shared_cached: ShaderMaterial
	for entry in studio.surfaces:
		if entry.group == 1:
			shared_cached = BrawlLook.material_for(entry.mesh.mesh.surface_get_material(entry.surface), BrawlLook.R_WALL)
			break
	var pool_count := BrawlLook._pool_mats.size()
	var floor_cache_count := BrawlLook._floor_mats.size()
	studio.queue_free()
	await process_frame
	for repeat_index in 2:
		studio = SCENE.instantiate()
		root.add_child(studio)
		await process_frame
		check(BrawlLook._pool_mats.size() == pool_count and BrawlLook._floor_mats.size() == floor_cache_count and BrawlLook._pool_mats.has(shared_cached.get_instance_id()), "reload %d preserves existing game cache and does not grow static registries" % (repeat_index + 1))
		studio.queue_free()
		await process_frame
	print("TEXTURE_DIORAMA_CHECK %d checks %d fails" % [checks, fails])
	quit(1 if fails else 0)

extends SceneTree
const SCENE := preload("res://scenes/painted_room_study.tscn")
const BASE := preload("res://scenes/texture_diorama.tscn")
var checks := 0
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	fails += 0 if ok else 1
	print(("PASS " if ok else "FAIL ") + message)

func _run() -> void:
	var baseline = BASE.instantiate()
	root.add_child(baseline)
	await process_frame
	var original_meshes := {}
	for entry in baseline.surfaces:
		original_meshes[baseline.get_path_to(entry.mesh)] = entry.mesh.mesh
	baseline.queue_free()
	await process_frame
	var studio = SCENE.instantiate()
	root.add_child(studio)
	await process_frame
	check(studio.study_meshes.size() == 24, "12 floor modules / service deck / 11 wall meshes have private UV meshes")
	for mat in studio.study_materials:
		check(mat.get_shader_parameter("artwork") != null and is_equal_approx(mat.get_shader_parameter("saturation"), 0.18) and is_equal_approx(mat.get_shader_parameter("brightness"), 0.22), "original PNG receives requested low saturation/value correction")
		check(mat.get_shader_parameter("artwork").get_image().has_mipmaps(), "painted PNG has imported mipmaps")
	var preserved := true
	var panels := true
	var coords := true
	for entry in studio.surfaces:
		var mi: MeshInstance3D = entry.mesh
		var original: Mesh = original_meshes[studio.get_path_to(mi)]
		if entry.group <= 1:
			var record: Dictionary = studio.study_meshes[mi.get_instance_id()]
			preserved = preserved and record.original == original and mi.mesh != original and mi.mesh.get_aabb().is_equal_approx(original.get_aabb())
			if entry.group == 1 and mi.mesh.get_aabb().size.y > 2.9:
				panels = panels and mi.mesh.get_meta("panel_count") == 1 and mi.mesh.get_surface_count() == 2
			for s in mi.mesh.get_surface_count():
				for uv in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]:
					coords = coords and uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1
		else:
			preserved = preserved and mi.mesh == original and mi.get_active_material(entry.surface) == entry.original
	check(preserved, "source geometry/materials and furniture/machinery remain unchanged")
	check(panels, "all seven W01 walls identify the real cream infill as one part")
	check(coords, "painted UVs remain within each PNG")
	check(studio.floor_uv(Vector3(-4, 0, -3)).is_equal_approx(Vector2.ZERO) and studio.floor_uv(Vector3(4, 0, 3)).is_equal_approx(Vector2.ONE), "full room artwork covers exact 8x6m floor")
	check(studio.floor_uv(Vector3(-2, 0, -1)).is_equal_approx(Vector2(0.284, 0.214)) and studio.floor_uv(Vector3(2, 0, 1)).is_equal_approx(Vector2(0.715, 0.515)), "painted joints align with the 2m model seams")
	studio.toggle_reference()
	var restored := true
	for entry in studio.surfaces:
		restored = restored and entry.mesh.mesh == original_meshes[studio.get_path_to(entry.mesh)] and entry.mesh.get_active_material(entry.surface) == entry.original
	check(restored, "B restores original geometry AND original materials")
	studio.toggle_reference()
	studio.toggle_raw_color()
	check(studio.study_materials.all(func(m): return m.shader == studio.unlit_shader and is_equal_approx(m.get_shader_parameter("brightness"), 0.22)), "unlit mode preserves the low-value correction")
	studio.toggle_raw_color()
	check(studio.study_materials.all(func(m): return m.shader == studio.PALETTE_SHADER), "lit mode restores real lighting")
	studio.set_texture(1, studio.checker_texture(), "checker")
	var scoped := true
	for entry in studio.surfaces:
		if entry.group == 1:
			scoped = scoped and entry.mesh.mesh == original_meshes[studio.get_path_to(entry.mesh)] and entry.mesh.get_active_material(entry.surface) == entry.preview
	check(scoped, "manual wall replacement returns to original UV geometry without touching painted floor")
	studio.restore_study()
	studio.selected = 0
	studio.reset_category()
	check(not studio.study_enabled[0] and studio.study_enabled[1], "R restores only selected category")
	studio.restore_study()
	check(studio.study_enabled == [true, true] and studio.settings[0].texture == null and studio.settings[1].texture == null, "restore button brings both painted presets back")
	studio.toggle_props()
	check(not studio.get_node("Diorama/Props").visible and not studio.get_node("Diorama/Machinery").visible and studio.study_enabled == [true, true], "furniture hide control leaves painted floor and walls active")
	studio.toggle_props()
	check(studio.get_node("Diorama/Props").visible and studio.get_node("Diorama/Machinery").visible, "furniture visibility restores")
	check(studio.environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "painted lab uses real color ambient fill rather than a missing sky")
	check(Lobby.TEST_SCENES.any(func(e): return e.scene == "res://scenes/painted_room_study.tscn"), "new study is reachable from lobby")
	var cache_size := BrawlLook._pool_mats.size()
	studio.queue_free()
	await process_frame
	for i in 2:
		studio = SCENE.instantiate()
		root.add_child(studio)
		await process_frame
		check(BrawlLook._pool_mats.size() == cache_size and studio.study_meshes.size() == 24, "reload %d keeps global caches stable" % (i + 1))
		studio.queue_free()
		await process_frame
	print("PAINTED_ROOM_CHECK %d checks %d fails" % [checks, fails])
	quit(1 if fails else 0)

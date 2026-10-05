extends SceneTree
## Imported GLB geometry/materials + assembled instance/collision checks.
const KIT := preload("res://scripts/codex_background/background_kit.gd")
var fails := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + label)

func meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(meshes(c))
	return out

func bounds(n: Node3D) -> AABB:
	var pts: Array[Vector3] = []
	for m in meshes(n):
		for s in m.mesh.get_surface_count():
			for p: Vector3 in m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				pts.append(n.global_transform.affine_inverse() * (m.global_transform * p))
	var bb := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		bb = bb.expand(p)
	return bb

func _run() -> void:
	var sizes := {"F01": Vector3(2, .2, 2), "W01": Vector3(2, 3, .25), "A01": Vector3(2, 1, .75), "A02": Vector3(1, 2, .5)}
	for id: String in KIT.MODELS:
		var ps := load(KIT.MODELS[id]) as PackedScene
		check(ps != null, id + " actual GLB loads")
		var n := ps.instantiate() as Node3D
		root.add_child(n)
		var bb := bounds(n)
		check((bb.size - sizes[id]).length() < .0002, id + " metric bounds " + str(bb.size))
		var origin := Vector3(0, -.2, 0) if id == "F01" else (Vector3.ZERO if id == "W01" else Vector3(-sizes[id].x/2, 0, -sizes[id].z/2))
		check((bb.position-origin).length() < .0002, id + " ground/pivot/axes " + str(bb.position))
		var all_uv := true
		var all_normals := true
		var all_textures := true
		var all_nonzero := true
		for m in meshes(n):
			check(m.position.length() < .00001 and m.scale.is_equal_approx(Vector3.ONE), id + " mesh origin/scale " + m.name)
			for s in m.mesh.get_surface_count():
				var a := m.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
				all_uv = all_uv and uvs.size() == verts.size()
				for v in uvs:
					all_uv = all_uv and is_finite(v.x) and is_finite(v.y) and v.x >= -.001 and v.x <= 1.001 and v.y >= -.001 and v.y <= 1.001
				for v: Vector3 in a[Mesh.ARRAY_NORMAL]:
					all_normals = all_normals and absf(v.length()-1) < .002
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				for j in range(0, idx.size(), 3):
					all_nonzero = all_nonzero and (verts[idx[j+1]]-verts[idx[j]]).cross(verts[idx[j+2]]-verts[idx[j]]).length() > 1e-9
				var mat := m.mesh.surface_get_material(s) as StandardMaterial3D
				all_textures = all_textures and mat != null and mat.albedo_texture != null
		check(all_uv, id + " complete finite UVs inside atlas")
		check(all_normals and all_nonzero, id + " normalized normals / no degenerate triangles")
		check(all_textures, id + " real GLB texture connection (not flat color)")
		n.free()
	for key in ["base", "trim", "prop"]:
		var tex := load(KIT.TEXTURES % key) as Texture2D
		check(tex.get_size() == Vector2(2048, 2048), key + " 2048 texture")
		check(tex.get_image().has_mipmaps(), key + " imported mip chain")
	var source := (load(KIT.TEXTURES % "base") as Texture2D).get_image()
	var edge_error := 0.0
	for k in 2048:
		var u := source.get_pixel(0, k) - source.get_pixel(2047, k)
		var v := source.get_pixel(k, 0) - source.get_pixel(k, 2047)
		edge_error = maxf(edge_error, maxf(Vector3(u.r,u.g,u.b).length(), Vector3(v.r,v.g,v.b).length()))
	check(edge_error < .008, "BASE periodic edges " + str(edge_error))
	var kit := KIT.new()
	root.add_child(kit)
	kit.build()
	check(kit.floors.size() == 16 and kit.walls.size() == 8 and kit.props.size() == 2, "8x8 / sixteen floors / L walls / two props")
	check(kit.floor_materials.size() == 4 and kit.materials.size() == 3, "shared atlases / only four phase materials")
	for z in 4:
		for x in 4:
			var f: Node3D = kit.floors[z*4+x]
			var m := meshes(f)[0].material_override as StandardMaterial3D
			check(f.position == Vector3(-4+x*2,0,-4+z*2) and m == kit.floor_materials[(z%2)*2+x%2], "tile position & world UV phase %d,%d" % [x,z])
	check(absf(KIT.BENCH.z - .375 + 4 - .05) < .00001, "bench rear .05m wall clearance")
	check(absf(KIT.LOCKER.z - .25 + 4 - .05) < .00001, "locker rear .05m wall clearance")
	check(kit.get_node("FloorCollision/CollisionShape3D").shape.size == Vector3(8,.2,8), "single flat floor collider")
	for entry in [[Vector3(-1.55,0,-3.5), Vector3(2,0,1)], [Vector3(1.2,0,-3.6), Vector3(5,0,0)]]:
		check(kit.blocked(entry[0]) and not kit.blocked(Vector3.ZERO), "prop/bounds blocked, central combat floor open")
		var pushed := kit.push_circle(entry[0], .42)
		check(kit.clearance(pushed) >= .4199, "inside prop recovery maintains radius")
	check(kit.push_circle(Vector3(-5,0,0),.42).is_equal_approx(Vector3(-3.58,0,0)), "west boundary circle radius")
	for p in [Vector3(-1.55,0,-3.94), Vector3(1.2,0,-3.96), Vector3(-2.5,0,-3.92)]:
		check(kit.clearance(kit.push_circle(p,.42)) >= .4199, "wall/prop tight-gap recovery " + str(p))
	kit.free()
	print("CODEX_BACKGROUND_CHECK %d checks %d fails" % [checks, fails])
	quit(1 if fails else 0)

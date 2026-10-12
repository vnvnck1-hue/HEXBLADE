extends SceneTree

func _initialize() -> void:
	for name_ in ["w01", "block_wall", "block_cover", "block_pillar", "f01"]:
		var node = load("res://assets/models/bg_claude_%s.glb" % name_).instantiate()
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			print("MODEL ", name_, " node=", mi.name, " transform=", mi.transform, " bounds=", mi.mesh.get_aabb())
			for i in mi.mesh.get_surface_count():
				var a = mi.mesh.surface_get_arrays(i)
				var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
				var layers := {}
				for j in range(0, indices.size(), 3):
					var p: Vector3 = (vertices[indices[j]] + vertices[indices[j + 1]] + vertices[indices[j + 2]]) / 3.0
					var n: Vector3 = normals[indices[j]]
					if abs(n.z) > 0.99:
						var key = snappedf(p.z, 0.005)
						layers[key] = layers.get(key, 0) + 1
				print("ARRAY vertices=", vertices.size(), " indices=", indices.size(), " planar_z=", layers)
			node.free()
	quit()

extends SceneTree
func _init():
	FX.setup(Node3D.new())
	var m: ArrayMesh = FX._slash_mesh
	print("surfaces ", m.get_surface_count(), " aabb ", m.get_aabb())
	var arr = m.surface_get_arrays(0)
	print("verts ", arr[Mesh.ARRAY_VERTEX].size(), " uv ", arr[Mesh.ARRAY_TEX_UV] != null)
	print(arr[Mesh.ARRAY_TEX_UV].slice(0, 6))
	quit()

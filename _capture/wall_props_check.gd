extends SceneTree

func _initialize() -> void:
	var total := 0
	for shape in 8:
		for seed_value in [7,42,123]:
			var map := ArenaMap.new()
			map.generate_single(seed_value, shape, true)
			var before := map.grid.duplicate()
			var cells := WallProps.dress(map)
			assert(before == map.grid, "Dressing must not change gameplay grid")
			for cell in cells:
				assert(map.cell_type(cell) == ArenaMap.VOID, "Prop overlaps walkable space")
			for prop in map.get_node("WallProps").get_children():
				var c := map.cell_of(prop.position)
				for dx in range(-1,2):
					assert(map.cell_type(c+Vector2i(dx,1)) == ArenaMap.FLOOR)
				for mesh in prop.get_children():
					if mesh is MeshInstance3D:
						var bounds: AABB = mesh.mesh.get_aabb()
						assert(bounds.position.x >= -1.501 and bounds.end.x <= 1.501)
						assert(bounds.position.z >= -0.501 and bounds.end.z <= 0.501)
				total += 1
			map.free()
	print("WALL_KIT_CHECK_OK: 24 shape/seed combinations; ",total," instances; unchanged grid; solid-wall footprints")
	quit()

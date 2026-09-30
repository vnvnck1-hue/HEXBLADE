class_name WallProps
extends RefCounted
## Reference-inspired industrial wall kit. Front = +Z; footprint stays inside three solid wall cells.
## Geometry is baked per material and shared by every instance of each variant.

const GRAPHITE := Color("30383e")
const EDGE := Color("535f64")
const ARMOR := Color("aab6b4")
const LIGHT := Color("d2d9cd")
const MINT := Color("77a89e")
const BLACK := Color("1d282e")
const AMBER := Color("d3a65b")
const RED := Color("bd6463")
static var _cache: Dictionary = {}

static func create(kind: int) -> Node3D:
	var root := Node3D.new()
	root.name = ["CoolantManifold", "PowerDistribution", "ServiceLocker"][kind]
	if not _cache.has(kind):
		_chassis(root)
		match kind:
			0: _coolant(root)
			1: _power(root)
			2: _locker(root)
		var groups: Dictionary = {}
		for part in root.get_children():
			var mi := part as MeshInstance3D
			var mat: Material = mi.material_override
			if not groups.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[mat] = st
			# Primitive meshes are indexed; custom chamfers are not. Normalize before merging.
			var source := SurfaceTool.new()
			source.create_from(mi.mesh, 0)
			source.deindex()
			groups[mat].append_from(source.commit(), 0, mi.transform)
		var baked: Array = []
		for mat in groups:
			var mesh: ArrayMesh = groups[mat].commit()
			mesh.surface_set_material(0, mat)
			baked.append(mesh)
		_cache[kind] = baked
		for part in root.get_children():
			part.free()
	for mesh in _cache[kind]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		root.add_child(mi)
	_text(root, ["01 / COOLANT", "02 / POWER", "03 / SERVICE"][kind], Vector3(0, 2.82, 0.255), 0.0036)
	_text(root, ["C-07", "HIGH VOLTAGE", "ACCESS / 09"][kind], Vector3(0.0, 0.48, 0.375), 0.0027)
	return root

static func dress(map: Node3D) -> Dictionary:
	var kit := Node3D.new()
	kit.name = "WallProps"
	map.add_child(kit)
	var occupied: Dictionary = {}
	var count := 0
	# Only rear-facing walls: tall set dressing cannot obscure foreground combat.
	for room in map.rooms:
		var placed := 0
		for c in room.cells:
			if placed >= 6:
				break
			var valid := true
			for dx in range(-2, 3):
				var floor_cell: Vector2i = c + Vector2i(dx, 0)
				var back_cell: Vector2i = floor_cell + Vector2i(0, -1)
				if map.cell_type(floor_cell) != 1 or map.cell_type(back_cell) != 0 or occupied.has(back_cell):
					valid = false
				if map.gate_of[map._idx(floor_cell)] >= 0:
					valid = false
				# 고저차 지형: 바닥층(높이 0) 앞 벽에만 세운다
				if absf(map.cell_h(floor_cell)) > 0.01:
					valid = false
			if not valid:
				continue
			var prop := create(count % 3)
			kit.add_child(prop)
			prop.position = map.world_of(c + Vector2i(0, -1))
			prop.set_meta("variant", count % 3)
			for dx in range(-1, 2):
				occupied[c + Vector2i(dx, -1)] = true
			count += 1
			placed += 1
	return occupied

static func _box(p: Node3D, size: Vector3, at: Vector3, color: Color, rot := Vector3.ZERO, emission := 0.0) -> void:
	Build.box(p, size, at, color, rot, emission)

static func _panel(p: Node3D, size: Vector3, at: Vector3, color: Color, cut := 0.1) -> void:
	# Clipped corners plus a real chamfer around the front face.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := size.x * 0.5
	var y := size.y * 0.5
	var ring: Array[Vector2] = [Vector2(-x+cut,-y),Vector2(x-cut,-y),Vector2(x,-y+cut),Vector2(x,y-cut),Vector2(x-cut,y),Vector2(-x+cut,y),Vector2(-x,y-cut),Vector2(-x,-y+cut)]
	var bevel := minf(0.04, minf(size.x, size.y) * 0.12)
	for i in 8:
		var a := ring[i]
		var b := ring[(i+1)%8]
		var ai := a * Vector2((x-bevel)/x, (y-bevel)/y)
		var bi := b * Vector2((x-bevel)/x, (y-bevel)/y)
		_tri(st, Vector3(0,0,size.z/2), Vector3(bi.x,bi.y,size.z/2), Vector3(ai.x,ai.y,size.z/2))
		_quad(st, Vector3(ai.x,ai.y,size.z/2), Vector3(bi.x,bi.y,size.z/2), Vector3(b.x,b.y,size.z/2-bevel), Vector3(a.x,a.y,size.z/2-bevel))
		_quad(st, Vector3(a.x,a.y,size.z/2-bevel), Vector3(b.x,b.y,size.z/2-bevel), Vector3(b.x,b.y,-size.z/2), Vector3(a.x,a.y,-size.z/2))
		_tri(st, Vector3(0,0,-size.z/2), Vector3(a.x,a.y,-size.z/2), Vector3(b.x,b.y,-size.z/2))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Pal.lit(color)
	mi.position = at
	p.add_child(mi)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_normal((c-a).cross(b-a).normalized())
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st,a,b,c)
	_tri(st,a,c,d)

static func _cyl(p: Node3D, at: Vector3, radius: float, length: float, color: Color, axis := Vector3.UP) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Pal.lit(color)
	mi.position = at
	if axis == Vector3.RIGHT:
		mi.rotation.z = PI/2
	elif axis == Vector3.BACK:
		mi.rotation.x = PI/2
	p.add_child(mi)

static func _chassis(p: Node3D) -> void:
	_box(p,Vector3(3.0,0.12,0.95),Vector3(0,0.06,0),GRAPHITE)
	_panel(p,Vector3(2.74,3.15,0.38),Vector3(0,1.575,-0.22),GRAPHITE,0.19)
	for side in [-1,1]:
		_panel(p,Vector3(0.21,2.85,0.35),Vector3(side*1.24,1.55,-0.01),EDGE,0.07)
		_panel(p,Vector3(0.48,0.35,0.83),Vector3(side*0.96,0.18,0.02),GRAPHITE,0.08)
		_box(p,Vector3(0.16,0.05,0.04),Vector3(side*0.96,0.23,0.45),RED)
	_panel(p,Vector3(2.83,0.3,0.62),Vector3(0,3.05,-0.06),EDGE,0.09)
	_panel(p,Vector3(2.35,0.43,0.28),Vector3(0,2.77,0.08),ARMOR,0.08)
	_box(p,Vector3(1.65,0.065,0.035),Vector3(0,2.98,0.265),LIGHT,Vector3.ZERO,0.45)
	_panel(p,Vector3(1.86,0.33,0.44),Vector3(0,0.47,0.1),ARMOR,0.07)
	for side in [-1,1]:
		for y in [0.5,2.76]:
			_box(p,Vector3(0.13,0.23,0.12),Vector3(side*0.95,y,0.24),GRAPHITE)
			_box(p,Vector3(0.065,0.105,0.03),Vector3(side*0.95,y+0.03,0.315),LIGHT)
		for y in [0.83,2.5]:
			_cyl(p,Vector3(side*1.24,y,0.19),0.045,0.03,BLACK,Vector3.BACK)
	for i in 7:
		_box(p,Vector3(0.12,0.03,0.28),Vector3(-0.48+i*0.16,3.215,-0.07),BLACK)

static func _coolant(p: Node3D) -> void:
	_panel(p,Vector3(2.26,1.65,0.14),Vector3(0,1.55,0.03),ARMOR)
	_cyl(p,Vector3(0,2.24,0.17),0.22,2.1,MINT,Vector3.RIGHT)
	for x in [-0.94,-0.64,0.64,0.94]:
		_cyl(p,Vector3(x,2.24,0.17),0.25,0.08,GRAPHITE,Vector3.RIGHT)
	for side in [-1,1]:
		var x: float = side*0.67
		_cyl(p,Vector3(x,1.14,0.12),0.23,0.79,MINT)
		for y in [0.77,1.13,1.51]:
			_cyl(p,Vector3(x,y,0.12),0.25,0.085,GRAPHITE)
		_cyl(p,Vector3(x,1.72,0.14),0.075,0.3,EDGE)
		_box(p,Vector3(0.12,0.3,0.11),Vector3(side*1.04,1.92,0.14),BLACK)
	_panel(p,Vector3(0.53,0.86,0.23),Vector3(0,1.29,0.15),GRAPHITE,0.06)
	_panel(p,Vector3(0.39,0.4,0.04),Vector3(0,1.46,0.29),MINT,0.035)
	for i in 3:
		_box(p,Vector3(0.24,0.025,0.02),Vector3(0,1.36+i*0.09,0.32),LIGHT,Vector3.ZERO,0.25)
	_box(p,Vector3(0.12,0.055,0.035),Vector3(0,1.03,0.3),RED)
	_cyl(p,Vector3(0,0.75,0.17),0.07,0.65,EDGE,Vector3.RIGHT)

static func _power(p: Node3D) -> void:
	for side in [-1,1]:
		_panel(p,Vector3(1.04,0.86,0.24),Vector3(side*0.57,2.04,0.07),LIGHT,0.12)
		_box(p,Vector3(0.83,0.1,0.035),Vector3(side*0.57,1.89,0.207),MINT)
	_panel(p,Vector3(1.24,0.79,0.25),Vector3(-0.43,1.02,0.09),ARMOR,0.1)
	_panel(p,Vector3(0.72,0.79,0.25),Vector3(0.66,1.02,0.09),EDGE,0.08)
	for i in 5:
		_box(p,Vector3(0.45,0.055,0.04),Vector3(0.66,0.77+i*0.12,0.235),BLACK)
	for x in [-0.83,-0.57,-0.31]:
		_cyl(p,Vector3(x,1.5,0.16),0.055,0.36,GRAPHITE)
		_cyl(p,Vector3(x,1.52,0.16),0.09,0.11,EDGE)
	_box(p,Vector3(0.5,0.16,0.16),Vector3(0.64,1.5,0.16),GRAPHITE)
	for i in 3:
		_box(p,Vector3(0.06,0.07,0.02),Vector3(0.5+i*0.14,1.51,0.25),MINT if i<2 else AMBER,Vector3.ZERO,0.3)
	# Inlaid warning chevrons and panel handles.
	for i in 3:
		_box(p,Vector3(0.09,0.21,0.025),Vector3(-0.72+i*0.16,1.01,0.23),AMBER,Vector3(0,0,-28))
	for x in [-0.57,0.57]:
		_box(p,Vector3(0.27,0.06,0.08),Vector3(x,2.19,0.23),GRAPHITE)

static func _locker(p: Node3D) -> void:
	for side in [-1,1]:
		_panel(p,Vector3(1.02,1.84,0.27),Vector3(side*0.56,1.61,0.065),ARMOR if side<0 else LIGHT,0.13)
		_panel(p,Vector3(0.78,0.44,0.035),Vector3(side*0.56,2.14,0.215),MINT,0.06)
		for y in [0.84,2.34]:
			_box(p,Vector3(0.14,0.2,0.16),Vector3(side*0.94,y,0.24),GRAPHITE)
			_box(p,Vector3(0.06,0.12,0.04),Vector3(side*0.94,y,0.34),EDGE)
		_box(p,Vector3(0.075,0.42,0.12),Vector3(side*0.17,1.55,0.27),GRAPHITE)
		for i in 4:
			_box(p,Vector3(0.53,0.028,0.03),Vector3(side*0.56,0.93+i*0.1,0.22),EDGE)
	_cyl(p,Vector3(0,0.71,0.21),0.1,1.53,EDGE,Vector3.RIGHT)
	for x in [-0.71,0.71]:
		_cyl(p,Vector3(x,0.71,0.21),0.13,0.11,GRAPHITE,Vector3.RIGHT)
	_box(p,Vector3(0.08,0.08,0.05),Vector3(0,2.61,0.15),MINT,Vector3.ZERO,0.5)

static func _text(p: Node3D, value: String, at: Vector3, pixel: float) -> void:
	var label := Label3D.new()
	label.text = value
	label.font_size = 48
	label.pixel_size = pixel
	label.position = at
	label.modulate = GRAPHITE
	label.outline_size = 0
	label.no_depth_test = false
	p.add_child(label)

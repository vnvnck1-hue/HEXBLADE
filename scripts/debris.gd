class_name Debris
extends Node3D
## 파괴된 몸체 조각. 간단한 자체 물리로 튀고, 바닥에서 튕기며 구르다 사라진다.
## 흐르는 씬(WorldFlow)에서는 바닥 마찰이 흐르는 도로 기준이라, 떨어진 조각이 도로에 끌려 화면 아래로 흘러간다.

const GRAVITY := 22.0
const MAX_PIECES := 220

static var inst: Debris
static var _sub_boxes := {}

var pieces: Array = []   # {node, vel, ang, half, life, max_life}


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _ready() -> void:
	inst = self


## 몸체의 파츠를 조각으로 만든다. 큰 상자는 2×2×2 로 쪼갠다.
## center: 폭발 중심, power: 퍼지는 세기, lift: 위로 튀는 세기, push: 추가 방향
static func burst(body: Node3D, center: Vector3, power: float, lift: float, push := Vector3.ZERO) -> void:
	if inst == null:
		return
	for n in body.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if not m.is_visible_in_tree():
			continue
		var mat := m.material_override
		if mat == Pal.flat():
			continue   # 발광 단색 메시(절단면·조명부)는 파편으로 만들지 않는다
		var xf := m.global_transform
		var box := m.mesh as BoxMesh
		if box and box.size.x > 0.5:
			# 큰 몸체 → 8조각
			var half_size := box.size * 0.5
			var sub := _sub_box(half_size)
			for ix in [-1, 1]:
				for iy in [-1, 1]:
					for iz in [-1, 1]:
						var local := Vector3(ix, iy, iz) * half_size * 0.5
						var gx := Transform3D(xf.basis, xf * local)
						inst._add_piece(sub, mat, gx, center, power, lift, push, half_size.length() * 0.35)
		else:
			var half := 0.15
			if box:
				half = box.size.length() * 0.3
			elif m.has_meta("keep_mat"):
				half = m.get_aabb().size.length() * 0.3
			else:
				# 코어 같은 발광 파츠는 꺼진 색으로
				mat = Pal.lit(Color("5a1428"))
			var nx := Transform3D(xf.basis.orthonormalized(), xf.origin)
			inst._add_piece(m.mesh, mat, nx, center, power * 1.2, lift, push, half)


## 탄피처럼 정해진 속도로 튀어 나가는 작은 조각 하나
static func toss(mesh: Mesh, mat: Material, xf: Transform3D, vel: Vector3, life := 1.1) -> void:
	if inst == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.add_child(mi)
	mi.global_transform = xf
	var ang := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * randf_range(10.0, 18.0)
	inst.pieces.append({"node": mi, "vel": vel, "ang": ang, "half": 0.05, "life": life, "max": life})
	while inst.pieces.size() > MAX_PIECES:
		var old: Dictionary = inst.pieces.pop_front()
		(old.node as Node).queue_free()


static func _sub_box(half_size: Vector3) -> BoxMesh:
	var key := str(half_size)
	if not _sub_boxes.has(key):
		var b := BoxMesh.new()
		b.size = half_size * 0.96
		_sub_boxes[key] = b
	return _sub_boxes[key]


func _add_piece(mesh: Mesh, mat: Material, xf: Transform3D, center: Vector3, power: float, lift: float, push: Vector3, half: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # 최대 220조각: 그림자 패스 부담을 피한다
	add_child(mi)
	mi.global_transform = xf
	var out := xf.origin - center
	out.y = 0
	var dir := out.normalized() if out.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	dir = dir.rotated(Vector3.UP, randf_range(-0.5, 0.5))
	var vel := dir * power * randf_range(0.5, 1.2) + Vector3(0, lift * randf_range(0.6, 1.3), 0) + push * randf_range(0.6, 1.2)
	var ang := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * randf_range(8.0, 20.0)
	var life := randf_range(1.6, 2.5)
	pieces.append({"node": mi, "vel": vel, "ang": ang, "half": clampf(half, 0.06, 0.3), "life": life, "max": life})
	while pieces.size() > MAX_PIECES:
		var old: Dictionary = pieces.pop_front()
		(old.node as Node).queue_free()


func _physics_process(dt: float) -> void:
	var road := WorldFlow.road_v()
	var i := pieces.size() - 1
	while i >= 0:
		var pc: Dictionary = pieces[i]
		var mi := pc.node as MeshInstance3D
		pc.life -= dt
		if pc.life <= 0.0:
			mi.queue_free()
			pieces.remove_at(i)
			i -= 1
			continue
		var v: Vector3 = pc.vel
		v.y -= GRAVITY * dt
		var pos := mi.global_position + v * dt
		var half: float = pc.half
		var ang: Vector3 = pc.ang
		var g := Main.gy(pos)
		if pos.y < g + half:
			pos.y = g + half
			if v.y < -1.5:
				v.y = -v.y * 0.38        # 튕김
				ang *= 0.6
			else:
				v.y = 0.0
			v.x *= 0.72                  # 바닥 마찰 (흐르는 씬에서는 도로 기준)
			v.z = road + (v.z - road) * 0.72
			ang *= 0.8
		var old := mi.global_position
		# 낮게 날면 벽에, 높이와 상관없이 솟은 절벽 면에 튕긴다
		var qx := Vector3(pos.x, pos.y, old.z)
		if (pos.y - g < 1.2 and Main.inst.is_blocked(qx)) or Main.gy(qx) > pos.y:
			pos.x = old.x
			v.x = -v.x * 0.4
		var qz := Vector3(pos.x, pos.y, pos.z)
		if road <= 0.0 and ((pos.y - g < 1.2 and Main.inst.is_blocked(qz)) or Main.gy(qz) > pos.y):
			pos.z = old.z
			v.z = -v.z * 0.4
		if WorldFlow.gone(pos):
			mi.queue_free()
			pieces.remove_at(i)
			i -= 1
			continue
		mi.global_position = pos
		if ang.length() > 0.05:
			mi.rotate(ang.normalized(), ang.length() * dt)
		pc.vel = v
		pc.ang = ang
		# 마지막 0.4초 동안 줄어들며 사라짐
		if pc.life < 0.4:
			mi.scale = Vector3.ONE * maxf(0.01, pc.life / 0.4)
		i -= 1

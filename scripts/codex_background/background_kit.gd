class_name CodexBackgroundKit
extends Node3D
## Codex 전용 4종. 기존 Main/훈련장/본편은 수정하지 않는다.

const MODELS := {
	"F01": "res://assets/models/bg_codex_floor_f01.glb",
	"W01": "res://assets/models/bg_codex_wall_w01.glb",
	"A01": "res://assets/models/bg_codex_workbench_a01.glb",
	"A02": "res://assets/models/bg_codex_locker_a02.glb",
}
const TEXTURES := "res://assets/textures/codex_background/bg_codex_%s.png"
const BENCH := Vector3(-1.55, 0, -3.575)
const LOCKER := Vector3(1.2, 0, -3.7)

var floors: Array[Node3D] = []
var walls: Array[Node3D] = []
var props: Array[Node3D] = []
var materials: Dictionary = {}
var floor_materials: Array[StandardMaterial3D] = []
var obstacles: Array[Rect2] = [Rect2(-2.55, -3.95, 2, .75), Rect2(.7, -3.95, 1, .5)]

func build() -> void:
	for key in ["base", "trim", "prop"]:
		var m := StandardMaterial3D.new()
		m.resource_name = "bg_codex_" + key
		m.albedo_texture = load(TEXTURES % key)
		m.roughness = .86
		m.metallic = 0.0
		m.metallic_specular = .18
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		materials[key] = m
	# Four phases, not 16 duplicate materials. Exported glTF flips Blender V.
	for z in 2:
		for x in 2:
			var phase := (materials.base as StandardMaterial3D).duplicate() as StandardMaterial3D
			phase.uv1_offset = Vector3(x * .5, -z * .5, 0)
			phase.resource_name = "bg_codex_phase_%d_%d" % [x, z]
			floor_materials.append(phase)
	for z in 4:
		for x in 4:
			var floor_model := spawn("F01", Vector3(-4 + x * 2, 0, -4 + z * 2))
			floor_model.name = "F01_%d_%d" % [x, z]
			floor_model.set_meta("tile", Vector2i(x, z))
			_assign(floor_model, floor_materials[(z % 2) * 2 + x % 2])
			floors.append(floor_model)
	# North faces +Z; west faces +X. Solids touch only at the inner corner.
	for i in 4:
		var north := spawn("W01", Vector3(-2 + i * 2, 0, -4), PI)
		north.name = "W01_N_%d" % i
		walls.append(north)
		var west := spawn("W01", Vector3(-4, 0, -4 + i * 2), -PI / 2)
		west.name = "W01_W_%d" % i
		walls.append(west)
	props.append(spawn("A01", BENCH, PI))
	props.append(spawn("A02", LOCKER, PI))
	_box_collision("FloorCollision", Vector3(8, .2, 8), Vector3(0, -.1, 0))
	_box_collision("NorthCollision", Vector3(8, 3, .25), Vector3(0, 1.5, -4.125))
	_box_collision("WestCollision", Vector3(.25, 3, 8), Vector3(-4.125, 1.5, 0))
	# Open viewing edges still constrain the test area; no extra visible parts.
	_box_collision("EastBoundary", Vector3(.25, 3, 8), Vector3(4.125, 1.5, 0))
	_box_collision("SouthBoundary", Vector3(8, 3, .25), Vector3(0, 1.5, 4.125))
	_box_collision("BenchCollision", Vector3(2, 1, .75), BENCH + Vector3(0, .5, 0))
	_box_collision("LockerCollision", Vector3(1, 2, .5), LOCKER + Vector3(0, 1, 0))

func spawn(id: String, at: Vector3, yaw := 0.0) -> Node3D:
	var n := (load(MODELS[id]) as PackedScene).instantiate() as Node3D
	add_child(n)
	n.position = at
	n.rotation.y = yaw
	n.set_meta("part_id", id)
	_assign(n, materials.base if id == "F01" else (materials.trim if id == "W01" else materials.prop))
	return n

func _assign(n: Node, mat: StandardMaterial3D) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
		(n as MeshInstance3D).layers = 1 | MechDecals.RECEIVER
	for c in n.get_children():
		_assign(c, mat)

func _box_collision(label: String, size_m: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = label
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size_m
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.position = at

func blocked(p: Vector3) -> bool:
	if absf(p.x) >= 4 or absf(p.z) >= 4:
		return true
	for r in obstacles:
		if r.has_point(Vector2(p.x, p.z)):
			return true
	return false

func clearance(p: Vector3) -> float:
	var dist := minf(4 - absf(p.x), 4 - absf(p.z))
	for r in obstacles:
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.z, r.position.y, r.end.y))
		dist = minf(dist, Vector2(p.x, p.z).distance_to(q))
	return dist

func push_circle(p: Vector3, radius: float) -> Vector3:
	p.x = clampf(p.x, -4 + radius, 4 - radius)
	p.z = clampf(p.z, -4 + radius, 4 - radius)
	for _pass in 3:
		for r in obstacles:
			var v := Vector2(p.x, p.z)
			var q := Vector2(clampf(v.x, r.position.x, r.end.x), clampf(v.y, r.position.y, r.end.y))
			var d := v - q
			if d.length() < radius:
				var candidate := q + d.normalized() * radius if d.length() > .00001 else v
				if d.length() < .00001 or absf(candidate.x) > 4-radius or absf(candidate.y) > 4-radius:
					# A rear exit in the 5cm wall gap cannot hold the player's capsule.
					# Choose the closest feasible side, not an exit through the outer wall.
					var exits := [Vector2(r.position.x-radius, v.y), Vector2(r.end.x+radius, v.y), Vector2(v.x, r.position.y-radius), Vector2(v.x, r.end.y+radius)]
					var nearest := INF
					for exit: Vector2 in exits:
						if absf(exit.x) > 4-radius or absf(exit.y) > 4-radius:
							continue
						var distance := exit.distance_squared_to(v)
						if distance < nearest:
							nearest = distance
							candidate = exit
				v = candidate
				p.x = v.x
				p.z = v.y
		p.x = clampf(p.x, -4 + radius, 4 - radius)
		p.z = clampf(p.z, -4 + radius, 4 - radius)
	return p

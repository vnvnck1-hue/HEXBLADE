"""hb — small modeling helpers for HEXBLADE model scripts (Blender 5.2, bpy).

Conventions (match Godot after glTF export):
  * 1 unit = 1 m. Blender is Z-up; the glTF exporter turns it into Godot's Y-up.
  * The model FACES +Y in Blender  ->  -Z in Godot (Godot's forward). +X stays right.
  * Origin = the point Godot will place on the ground / pivot. Feet at z = 0.
  * Empties named "pt_<name>" are attachment points (muzzle, socket...). They export as Node3D,
    so Godot code can find them with  model.find_child("pt_muzzle").  ('@' is not allowed in Godot node names.)
  * Objects with the same `part=` are joined into one mesh named after the part when build.py
    finishes, so a model ends up as a few named parts (body, turret, leg_l ...) that code can animate.

Every shape function takes  loc=(x,y,z), rot=(deg,deg,deg), mat=<material or name>, parent=<object>,
bevel=<width m>, part=<name>  and returns the new object.
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

_DEG = math.pi / 180.0
_mats: dict = {}


# ---------------------------------------------------------------- scene

def reset():
	"""Empty the scene and orphan data (the build starts from --factory-startup)."""
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o, do_unlink=True)
	for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.cameras, bpy.data.lights, bpy.data.images):
		for d in list(coll):
			if d.users == 0:
				coll.remove(d)
	_mats.clear()


def collection():
	return bpy.context.scene.collection


# ---------------------------------------------------------------- materials

def mat(name, color=(0.8, 0.8, 0.8), metal=0.0, rough=0.6, emit=None, emit_power=3.0, alpha=1.0):
	"""Principled BSDF material, cached by name. color/emit are sRGB 0..1 tuples or '#rrggbb'."""
	if name in _mats:
		return _mats[name]
	m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	m.use_nodes = True
	b = m.node_tree.nodes.get("Principled BSDF")
	c = _lin(color)
	b.inputs["Base Color"].default_value = (*c, 1.0)
	b.inputs["Metallic"].default_value = metal
	b.inputs["Roughness"].default_value = rough
	if emit is not None:
		b.inputs["Emission Color"].default_value = (*_lin(emit), 1.0)
		b.inputs["Emission Strength"].default_value = emit_power
	if alpha < 1.0:
		b.inputs["Alpha"].default_value = alpha
		m.surface_render_method = "BLENDED"
	m.diffuse_color = (*c, alpha)  # what the Workbench preview shows
	_mats[name] = m
	return m


def _lin(c):
	if isinstance(c, str):
		h = c.lstrip("#")
		c = tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
	return tuple(((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in c[:3])


def _resolve(m):
	if m is None or isinstance(m, bpy.types.Material):
		return m
	return _mats.get(m) or mat(m)


# ---------------------------------------------------------------- core

def _finish(o, name, loc, rot, m, parent, bevel, seg, part, smooth):
	o.name = name
	o.data.name = name
	o.location = Vector(loc)
	o.rotation_euler = tuple(a * _DEG for a in rot)
	m = _resolve(m)
	if m is not None:
		o.data.materials.clear()
		o.data.materials.append(m)
	if parent is not None:
		o.parent = parent
	if bevel:
		add_bevel(o, bevel, seg)
	if smooth:
		shade_smooth(o, smooth if isinstance(smooth, (int, float)) and smooth is not True else 35)
	if part:
		o["hb_part"] = part
	return o


def _from_bmesh(name, bm):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	o = bpy.data.objects.new(name, me)
	collection().objects.link(o)
	return o


def box(name, size=(1, 1, 1), loc=(0, 0, 0), rot=(0, 0, 0), mat=None, parent=None, bevel=0.0, seg=2,
		part=None, smooth=False, taper=None, taper_axis="Z"):
	"""Box of full size (x, y, z) centered at loc. taper=(a, b) scales the +taper_axis face by a, b on the
	other two axes in xyz order (wedges, armor plates; taper_axis="Y" for a limb plate narrowing toward +Y)."""
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
	if taper:
		i = "XYZ".index(taper_axis)
		others = [k for k in range(3) if k != i]
		for v in bm.verts:
			if v.co[i] > 0:
				v.co[others[0]] *= taper[0]
				v.co[others[1]] *= taper[1]
	return _finish(_from_bmesh(name, bm), name, loc, rot, mat, parent, bevel, seg, part, smooth)


def deform(o, fn):
	"""Move every vertex: fn(world Vector) -> world Vector (before modifiers, so bevels follow)."""
	bpy.context.view_layer.update()
	mw = o.matrix_world
	inv = mw.inverted()
	for v in o.data.vertices:
		v.co = inv @ Vector(fn(mw @ v.co))
	o.data.update()
	return o


def cyl(name, r=0.5, depth=1.0, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, parent=None, verts=24, r2=None,
		bevel=0.0, seg=2, part=None, smooth=True, cap=True):
	"""Cylinder along local Z (rot=(90,0,0) lays it along Y). r2 = top radius (cone / frustum)."""
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=cap, segments=verts, radius1=r, radius2=r if r2 is None else r2, depth=depth)
	return _finish(_from_bmesh(name, bm), name, loc, rot, mat, parent, bevel, seg, part, smooth)


def sphere(name, r=0.5, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, parent=None, scale=(1, 1, 1), seg=24, rings=12,
		   part=None, smooth=True):
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
	bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
	return _finish(_from_bmesh(name, bm), name, loc, rot, mat, parent, 0, 0, part, smooth)


def torus(name, r=0.5, thick=0.1, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, parent=None, seg=32, ring=10,
		  part=None, smooth=True):
	bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=thick, major_segments=seg, minor_segments=ring)
	o = bpy.context.active_object
	return _finish(o, name, loc, rot, mat, parent, 0, 0, part, smooth)


def prism(name, points, depth=0.2, loc=(0, 0, 0), rot=(0, 0, 0), mat=None, parent=None, bevel=0.0, seg=2,
		  part=None, axis="X", cuts=0):
	"""Extrude a 2D outline (list of (u, v)) by depth, centered. axis X: outline in YZ plane (side profile,
	u = forward Y, v = up Z) extruded along X — the usual way to cut a silhouette from a side view.
	cuts = extra outline rings across the depth, so hb.deform can bend the plate (e.g. sloped shoulders)."""
	bm = bmesh.new()
	h = depth / 2.0
	def p3(u, v, w):
		if axis == "X":
			return (w, u, v)
		if axis == "Y":
			return (u, w, v)
		return (u, v, w)
	rings = [[bm.verts.new(p3(u, v, -h + depth * k / (cuts + 1))) for u, v in points] for k in range(cuts + 2)]
	bm.faces.new(rings[0][::-1])
	bm.faces.new(rings[-1])
	n = len(points)
	for a, b in zip(rings, rings[1:]):
		for i in range(n):
			j = (i + 1) % n
			bm.faces.new((a[i], a[j], b[j], b[i]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return _finish(_from_bmesh(name, bm), name, loc, rot, mat, parent, bevel, seg, part, False)


def tube(name, pts, r=0.05, mat=None, parent=None, verts=10, part=None):
	"""Pipe / cable through 3D points (bevelled curve, converted to mesh)."""
	cu = bpy.data.curves.new(name, "CURVE")
	cu.dimensions = "3D"
	cu.bevel_depth = r
	cu.bevel_resolution = max(1, verts // 4)
	cu.use_fill_caps = True
	sp = cu.splines.new("POLY")
	sp.points.add(len(pts) - 1)
	for p, c in zip(sp.points, pts):
		p.co = (*c, 1.0)
	o = bpy.data.objects.new(name, cu)
	collection().objects.link(o)
	o = to_mesh(o)
	return _finish(o, name, (0, 0, 0), (0, 0, 0), mat, parent, 0, 0, part, True)


def empty(name, loc=(0, 0, 0), rot=(0, 0, 0), parent=None, size=0.2):
	"""Attachment point. Name it "pt_muzzle" etc. Exports as a Node3D. loc/rot are WORLD values even with a parent."""
	o = bpy.data.objects.new(name, None)
	o.empty_display_type = "ARROWS"
	o.empty_display_size = size
	o.location = Vector(loc)
	o.rotation_euler = tuple(a * _DEG for a in rot)
	collection().objects.link(o)
	if parent is not None:
		attach(o, parent)
	return o


def attach(child, parent):
	"""Parent child to parent keeping child's world transform (for the part hierarchy Godot will animate)."""
	bpy.context.view_layer.update()
	mw = child.matrix_world.copy()
	child.parent = parent
	child.matrix_parent_inverse.identity()
	child.matrix_world = mw
	return child


def get(name):
	return bpy.data.objects[name]


# ---------------------------------------------------------------- modifiers / ops

def add_bevel(o, width=0.03, seg=2, angle=40):
	m = o.modifiers.new("bevel", "BEVEL")
	m.width = width
	m.segments = seg
	m.limit_method = "ANGLE"
	m.angle_limit = angle * _DEG
	m.harden_normals = True
	return m


def shade_smooth(o, angle=35):
	for p in o.data.polygons:
		p.use_smooth = True
	try:
		o.data.set_sharp_from_angle(angle=angle * _DEG)
	except AttributeError:
		pass


def mirror(o, axis="X", merge=True):
	"""Mirror modifier across the object's local origin (use for symmetric parts built on one side)."""
	m = o.modifiers.new("mirror", "MIRROR")
	m.use_axis = (axis == "X", axis == "Y", axis == "Z")
	m.use_clip = merge
	return m


def mirror_copy(o, axis="X", suffix=("_l", "_r")):
	"""Separate mirrored copy (left/right legs that must animate on their own). Returns the copy."""
	c = o.copy()
	c.data = o.data.copy()
	collection().objects.link(c)
	i = "XYZ".index(axis)
	c.location[i] = -c.location[i]
	s = [1, 1, 1]
	s[i] = -1
	c.data.transform(Matrix.Diagonal((*s, 1)))
	c.data.flip_normals()
	r = list(c.rotation_euler)
	for k in range(3):
		if k != i:
			r[k] = -r[k]
	c.rotation_euler = r
	if o.name.endswith(suffix[0]):
		c.name = o.name[: -len(suffix[0])] + suffix[1]
	else:
		c.name = o.name + ".mirror"
	if "hb_part" in o and o["hb_part"].endswith(suffix[0]):
		c["hb_part"] = o["hb_part"][: -len(suffix[0])] + suffix[1]
	return c


def array(o, count=3, offset=(1, 0, 0)):
	m = o.modifiers.new("array", "ARRAY")
	m.count = count
	m.use_relative_offset = False
	m.use_constant_offset = True
	m.constant_offset_displace = offset
	return m


def boolean(o, cutter, op="DIFFERENCE", keep=False):
	"""Cut / union with another object; applies immediately. The cutter is deleted unless keep."""
	m = o.modifiers.new("bool", "BOOLEAN")
	m.operation = op
	m.object = cutter
	m.solver = "EXACT"
	apply_mods(o)
	if not keep:
		bpy.data.objects.remove(cutter, do_unlink=True)
	return o


def apply_mods(o):
	_select(o)
	for m in list(o.modifiers):
		bpy.ops.object.modifier_apply(modifier=m.name)
	return o


def to_mesh(o):
	_select(o)
	bpy.ops.object.convert(target="MESH")
	return bpy.context.active_object


def join(objs, name):
	objs = [o for o in objs if o is not None]
	for o in objs:
		apply_mods(o)
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.join()
	o = bpy.context.active_object
	o.name = name
	o.data.name = name
	return o


def set_origin(o, point):
	"""Move o's origin to a world point without moving its geometry (pivot for animated parts)."""
	p = Vector(point)
	inv = o.matrix_world.inverted()
	local = inv @ p
	o.data.transform(Matrix.Translation(-local))
	o.matrix_world = o.matrix_world @ Matrix.Translation(local)
	return o


def frame(origin, fwd, up=(0, 0, 1)):
	"""4x4 matrix: origin, local +Y along fwd, local +Z as close to up as possible (segment frames for limbs)."""
	y = Vector(fwd).normalized()
	z = Vector(up) - y * Vector(up).dot(y)
	if z.length < 1e-4:
		z = Vector((0, 0, 1)) if abs(y.z) < 0.95 else Vector((0, -1, 0))
	z.normalize()
	x = y.cross(z)
	m = Matrix((x, y, z)).transposed().to_4x4()
	m.translation = Vector(origin)
	return m


def rebase(o, matrix):
	"""Give o a new object transform (pivot + axes) without moving its geometry; clears its parent."""
	bpy.context.view_layer.update()
	mw = o.matrix_world.copy()
	o.parent = None
	o.data.transform(matrix.inverted() @ mw)
	o.matrix_world = matrix
	return o


def _select(o):
	bpy.ops.object.select_all(action="DESELECT")
	o.select_set(True)
	bpy.context.view_layer.objects.active = o


# ---------------------------------------------------------------- info

def stats():
	"""Bounding box / triangle counts of every mesh in the scene (printed by build.py)."""
	dg = bpy.context.evaluated_depsgraph_get()
	lo = Vector((1e9, 1e9, 1e9))
	hi = -lo
	tris = 0
	parts = []
	for o in bpy.context.scene.objects:
		if o.type != "MESH":
			continue
		e = o.evaluated_get(dg)
		me = e.to_mesh()
		me.calc_loop_triangles()
		t = len(me.loop_triangles)
		tris += t
		for v in me.vertices:
			w = e.matrix_world @ v.co
			lo = Vector(map(min, lo, w))
			hi = Vector(map(max, hi, w))
		parts.append((o.name, t))
		e.to_mesh_clear()
	return {"min": tuple(lo), "max": tuple(hi), "size": tuple(hi - lo), "tris": tris, "parts": parts}

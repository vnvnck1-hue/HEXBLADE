"""Headless model build. Run through:  tools\\blender.ps1 model models\\src\\<name>.py [options]

  --no-export     skip assets/models/<name>.glb
  --no-preview    skip the preview sheet
  --engine=E      preview renderer: workbench (default, fast, flat colors + outline) or eevee (lit)
  --size=N        preview tile size in px (default 512)
  --compare[=flat] also render against the concept sheet (models/ref/<name>.json, see tools/blender/compare.py)

Outputs
  assets/models/<name>.glb                    glTF binary for Godot (Y-up, modifiers applied)
  output/models/<name>/<name>.blend           the built scene, open it in Blender to look around
  output/models/<name>/preview.png            2x2 sheet: front | right side / 3-4 front | 3-4 back
  output/models/<name>/view_<v>.png           each tile
  output/models/<name>/stats.txt              size, triangle count, parts, attachment points

A model script is plain Python run with `hb` (tools/blender/hb.py), `bpy`, `math`, `Vector` already imported.
It may set META = {"name": "...", "export": True}; otherwise the file name is the model name.
Shapes tagged part="x" are joined into one mesh "x" first; then after_join() runs if the script defines it
(set pivots with hb.set_origin, build the hierarchy with hb.attach, add "pt_" attachment points with hb.empty).
"""

import math
import os
import runpy
import sys
import traceback

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import hb  # noqa: E402

VIEWS = [  # name, direction from target to camera (Blender axes; model faces +Y), ortho
	("front", (0, 1, 0), True),
	("right", (1, 0, 0), True),
	("front34", (0.75, 1.0, 0.55), False),
	("back34", (-0.8, -1.0, 0.6), False),
]


def parse(argv):
	argv = argv[argv.index("--") + 1:] if "--" in argv else []
	opt = {"script": None, "export": True, "preview": True, "engine": "workbench", "size": 512, "compare": False}
	for a in argv:
		if a == "--no-export":
			opt["export"] = False
		elif a == "--no-preview":
			opt["preview"] = False
		elif a == "--compare" or a.startswith("--compare="):
			opt["compare"] = (a.split("=", 1)[1].upper() if "=" in a else "STUDIO")
		elif a.startswith("--engine="):
			opt["engine"] = a.split("=", 1)[1]
		elif a.startswith("--size="):
			opt["size"] = int(a.split("=", 1)[1])
		elif not a.startswith("--"):
			opt["script"] = a
	if not opt["script"]:
		raise SystemExit("usage: tools\\blender.ps1 model models\\src\\<name>.py [--no-export] [--no-preview] [--engine=eevee]")
	return opt


def join_parts():
	"""Join every object tagged hb_part=<p> into one mesh named <p>; children keep their world transform."""
	groups = {}
	for o in list(bpy.context.scene.objects):
		if o.type == "MESH" and "hb_part" in o:
			groups.setdefault(o["hb_part"], []).append(o)
	for part, objs in groups.items():
		keep = objs[0]
		members = set(objs)
		orphans = [(c, c.matrix_world.copy()) for o in objs[1:] for c in o.children if c not in members]
		parent = keep.parent
		out = hb.join(objs, part)
		out.parent = parent
		if "hb_part" in out:
			del out["hb_part"]
		for c, mw in orphans:
			c.parent = out
			c.matrix_world = mw


def export_glb(name):
	path = os.path.join(ROOT, "assets", "models", name + ".glb")
	os.makedirs(os.path.dirname(path), exist_ok=True)
	bpy.ops.object.select_all(action="DESELECT")
	bpy.ops.export_scene.gltf(
		filepath=path, export_format="GLB", export_apply=True, export_yup=True,
		export_cameras=False, export_lights=False, export_extras=True, export_animations=True,
	)
	return path


def setup_preview(engine, size):
	sc = bpy.context.scene
	sc.render.resolution_x = sc.render.resolution_y = size
	sc.render.resolution_percentage = 100
	sc.render.image_settings.file_format = "PNG"
	sc.render.film_transparent = False
	world = bpy.data.worlds.get("preview") or bpy.data.worlds.new("preview")
	sc.world = world
	world.color = (0.23, 0.25, 0.29)
	if engine == "eevee":
		sc.render.engine = "BLENDER_EEVEE"
		world.use_nodes = True
		bg = world.node_tree.nodes.get("Background")
		bg.inputs["Color"].default_value = (0.23, 0.25, 0.29, 1)
		bg.inputs["Strength"].default_value = 0.8
		sun = bpy.data.objects.new("_sun", bpy.data.lights.new("_sun", "SUN"))
		sun.data.energy = 3.5
		sun.rotation_euler = (math.radians(50), 0, math.radians(35))
		sc.collection.objects.link(sun)
	else:
		sc.render.engine = "BLENDER_WORKBENCH"
		sh = sc.display.shading
		sh.light = "STUDIO"
		sh.color_type = "MATERIAL"
		sh.show_cavity = True
		sh.cavity_type = "BOTH"
		sh.show_object_outline = True
		sh.object_outline_color = (0.02, 0.02, 0.03)
		sh.show_shadows = True
		sh.background_type = "WORLD"
		sc.display.light_direction = (-0.45, -0.35, 0.82)
	# ground grid: 1 m squares so the scale is readable in every view
	hb.box("_ground", (40, 40, 0.01), (0, 0, -0.006), mat=hb.mat("_ground", (0.36, 0.38, 0.42)))
	cu = bpy.data.curves.new("_grid", "CURVE")
	cu.dimensions = "3D"
	cu.bevel_depth = 0.008
	for i in range(-20, 21):
		for p0, p1 in (((i, -20), (i, 20)), ((-20, i), (20, i))):
			sp = cu.splines.new("POLY")
			sp.points.add(1)
			sp.points[0].co = (*p0, 0.001, 1)
			sp.points[1].co = (*p1, 0.001, 1)
	cu.materials.append(hb.mat("_gridline", (0.27, 0.29, 0.33)))
	sc.collection.objects.link(bpy.data.objects.new("_grid", cu))


def render_views(name, st, size):
	out = os.path.join(ROOT, "output", "models", name)
	os.makedirs(out, exist_ok=True)
	sc = bpy.context.scene
	lo, hi = Vector(st["min"]), Vector(st["max"])
	center = (lo + hi) / 2
	size_v = hi - lo
	radius = max(size_v.length / 2, 0.2)
	cam = bpy.data.objects.new("_cam", bpy.data.cameras.new("_cam"))
	sc.collection.objects.link(cam)
	sc.camera = cam
	files = []
	for vname, d, ortho in VIEWS:
		d = Vector(d).normalized()
		cam.data.type = "ORTHO" if ortho else "PERSP"
		# ortho: fit the silhouette seen from this axis; persp: fit the bounding sphere
		span = max(size_v.y if d.x else size_v.x, size_v.z)
		cam.data.ortho_scale = max(span, 0.2) * 1.2
		cam.data.lens = 50
		dist = radius * 2.6 if not ortho else radius * 6
		cam.location = center + d * dist
		cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
		cam.data.clip_end = dist * 4
		f = os.path.join(out, "view_%s.png" % vname)
		sc.render.filepath = f
		bpy.ops.render.render(write_still=True)
		files.append(f)
	sheet = os.path.join(out, "preview.png")
	compose(files, sheet, size)
	return sheet


def compose(files, path, size):
	import numpy as np
	tiles = []
	for f in files:
		im = bpy.data.images.load(f)
		a = np.empty(size * size * 4, dtype=np.float32)
		im.pixels.foreach_get(a)
		tiles.append(a.reshape(size, size, 4))
		bpy.data.images.remove(im)
	# Blender pixel rows start at the bottom: top row of the sheet = tiles 0,1
	top = np.concatenate([tiles[0], tiles[1]], axis=1)
	bot = np.concatenate([tiles[2], tiles[3]], axis=1)
	full = np.concatenate([bot, top], axis=0)
	full[:, size - 1:size + 1, :3] = 0.08
	full[size - 1:size + 1, :, :3] = 0.08
	img = bpy.data.images.new("_sheet", size * 2, size * 2, alpha=True)
	img.pixels.foreach_set(full.ravel())
	img.filepath_raw = path
	img.file_format = "PNG"
	img.save()


def write_stats(name, st, glb, out_dir):
	lines = ["model: %s" % name]
	lines.append("size (m)  x %.3f  y(fwd) %.3f  z(up) %.3f" % st["size"])
	lines.append("bounds    min (%.3f, %.3f, %.3f)  max (%.3f, %.3f, %.3f)" % (*st["min"], *st["max"]))
	lines.append("triangles %d" % st["tris"])
	lines.append("parts:")
	for n, t in st["parts"]:
		o = bpy.data.objects[n]
		lines.append("  %-24s %6d tris  parent=%s  origin=(%.2f, %.2f, %.2f)" % (
			n, t, o.parent.name if o.parent else "-", *o.matrix_world.translation))
	pts = [o for o in bpy.context.scene.objects if o.type == "EMPTY" and o.name.startswith("pt_")]
	if pts:
		lines.append("attachment points:")
		for o in pts:
			lines.append("  %-24s (%.2f, %.2f, %.2f)  parent=%s" % (o.name, *o.matrix_world.translation, o.parent.name if o.parent else "-"))
	if glb:
		lines.append("glb: %s" % os.path.relpath(glb, ROOT))
	text = "\n".join(lines)
	os.makedirs(out_dir, exist_ok=True)
	with open(os.path.join(out_dir, "stats.txt"), "w", encoding="utf-8") as fh:
		fh.write(text + "\n")
	return text


def main():
	opt = parse(sys.argv)
	script = os.path.abspath(opt["script"] if os.path.isabs(opt["script"]) else os.path.join(ROOT, opt["script"]))
	name = os.path.splitext(os.path.basename(script))[0]
	hb.reset()
	g = runpy.run_path(script, init_globals={"hb": hb, "bpy": bpy, "math": math, "Vector": Vector}, run_name="__hb_model__")
	meta = g.get("META", {})
	name = meta.get("name", name)
	join_parts()
	if callable(g.get("after_join")):
		g["after_join"]()  # pivots (hb.set_origin), hierarchy (hb.attach), attachment points (hb.empty)
	bpy.context.view_layer.update()
	st = hb.stats()
	out_dir = os.path.join(ROOT, "output", "models", name)
	glb = export_glb(name) if opt["export"] and meta.get("export", True) else None
	os.makedirs(out_dir, exist_ok=True)
	bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backup next to the rebuilt file
	bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, name + ".blend"), compress=True)
	print(write_stats(name, st, glb, out_dir))
	if opt["compare"]:
		import compare
		compare.run(name, ROOT, opt["compare"])
	if opt["preview"]:
		setup_preview(opt["engine"], opt["size"])
		print("preview: %s" % os.path.relpath(render_views(name, st, opt["size"]), ROOT))


try:
	main()
except SystemExit:
	raise
except Exception:
	traceback.print_exc()
	sys.exit(1)

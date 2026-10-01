"""Compare a built model with its concept sheet (build.py --compare).

Needs models/ref/<name>.json (per-view crop, scale, origin, camera) and the masks made by
tools/blender/ref_masks.py. For each view it renders the model with an orthographic camera that maps
world metres onto the reference crop's pixels, then writes

  output/models/<name>/compare.png      rows per view: concept | model (flat toon) | silhouette overlay
                                        overlay: white = both, red = only concept, cyan = only model
  output/models/<name>/compare.txt      silhouette IoU per view (1.0 = identical outline)

Camera kinds (Blender axes, the model faces +Y):
  front  looks from +Y toward -Y   image right = -X (model's left)
  left   looks from -X toward +X   image right = -Y (front of the model on the image left)
  right  looks from +X toward -X   image right = +Y
  top    looks down -Z             image right = -X, image up = -Y (front of the model at the image bottom)
"""

import json
import os

import bpy
import numpy as np
from mathutils import Matrix, Vector

CAMS = {
	"front": ((-1, 0, 0), (0, 0, 1)),
	"left": ((0, -1, 0), (0, 0, 1)),
	"right": ((0, 1, 0), (0, 0, 1)),
	"top": ((-1, 0, 0), (0, -1, 0)),
}
SS = 2  # supersampling of the model render


def _load(path):
	im = bpy.data.images.load(path, check_existing=False)
	w, h = im.size
	a = np.empty(w * h * 4, dtype=np.float32)
	im.pixels.foreach_get(a)
	bpy.data.images.remove(im)
	return a.reshape(h, w, 4)[::-1]  # top row first


def _save(arr, path):
	h, w = arr.shape[:2]
	img = bpy.data.images.new("_cmp", w, h, alpha=True)
	img.pixels.foreach_set(np.ascontiguousarray(arr[::-1], dtype=np.float32).ravel())
	img.filepath_raw = path
	img.file_format = "PNG"
	img.save()
	bpy.data.images.remove(img)


def _resize(a, h, w):
	ys = (np.arange(h) * a.shape[0] / h).astype(int)
	xs = (np.arange(w) * a.shape[1] / w).astype(int)
	return a[ys][:, xs]


def _classes(rgb, mask):
	"""Colour family per pixel, robust to lighting: 0 background, 1 blue armour, 2 dark frame, 3 light grey/steel,
	4 cyan glow. Works for both the painted concept and the shaded render."""
	r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
	mx = rgb.max(axis=2)
	c = np.full(r.shape, 3, dtype=np.int8)
	c[mx < 0.47] = 2
	c[(b - r > 0.14) & (b > 0.3)] = 1
	c[(g > 0.55) & (b > 0.55) & (r < 0.62) & (g - r > 0.2)] = 4
	c[~mask] = 0
	return c


def _agreement(ref, rend, mask, mod, k=4):
	"""Share of the union where the colour family matches, at 1/k resolution (tolerates small offsets)."""
	h, w = mask.shape
	h2, w2 = h // k * k, w // k * k
	def down(a):
		return a[:h2, :w2].reshape(h2 // k, k, w2 // k, k, *a.shape[2:]).mean(axis=(1, 3))
	cr = _classes(down(ref[..., :3]), down(mask.astype(np.float32)) > 0.5)
	cm = _classes(down(rend[..., :3]), down(mod.astype(np.float32)) > 0.5)
	u = (cr > 0) | (cm > 0)
	_agreement.last = (cr, cm)
	return float((cr[u] == cm[u]).mean()) if u.any() else 0.0


PALETTE = np.array([[0.1, 0.1, 0.1], [0.3, 0.55, 0.95], [0.35, 0.35, 0.38], [0.85, 0.85, 0.85], [0.3, 1.0, 0.95]], dtype=np.float32)


def _setup_render(sc, light="STUDIO"):
	sc.render.engine = "BLENDER_WORKBENCH"
	sc.render.film_transparent = True
	sc.render.resolution_percentage = 100
	sc.render.image_settings.file_format = "PNG"
	sc.render.image_settings.color_mode = "RGBA"
	sh = sc.display.shading
	sh.light = light
	sh.color_type = "MATERIAL"
	sh.show_cavity = True
	sh.cavity_type = "BOTH"
	sh.show_object_outline = True
	sh.object_outline_color = (0.03, 0.03, 0.05)
	sh.show_shadows = False
	sh.show_specular_highlight = True
	sc.display.render_aa = "8"


def run(name, root, light="STUDIO"):
	"""light: STUDIO (shaded, shows form) or FLAT (base colours only, closer to a cel-shaded concept)."""
	cfg_path = os.path.join(root, "models", "ref", name + ".json")
	if not os.path.exists(cfg_path):
		print("compare: no %s" % os.path.relpath(cfg_path, root))
		return None
	cfg = json.load(open(cfg_path, encoding="utf-8"))
	out = os.path.join(root, "output", "models", name)
	ref_dir = os.path.join(out, "ref")
	sc = bpy.context.scene
	_setup_render(sc, light)
	hidden = [o for o in sc.objects if o.name.startswith("_")]
	for o in hidden:
		o.hide_render = True
	cam = bpy.data.objects.new("_cmpcam", bpy.data.cameras.new("_cmpcam"))
	sc.collection.objects.link(cam)
	sc.camera = cam
	cam.data.type = "ORTHO"
	rows, lines, class_rows = [], [], []
	for view, v in cfg["views"].items():
		x0, y0, x1, y1 = v["crop"]
		w, h = x1 - x0, y1 - y0
		sx = v["px_per_m"]
		sy = v.get("py_per_m", sx)
		ox, oy = v["origin"]
		right, up = (Vector(t) for t in CAMS[v["camera"]])
		back = right.cross(up)
		cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
		center = right * ((cx - ox) / sx) + up * ((oy - cy) / sy)
		m = Matrix((right, up, back)).transposed().to_4x4()
		m.translation = center + back * 200.0
		cam.matrix_world = m
		cam.data.clip_end = 400.0
		# uniform render scale = sx; the vertical stretch of a squashed view (sy != sx) is applied afterwards
		hh = int(round(h * sx / sy))
		sc.render.resolution_x, sc.render.resolution_y = w * SS, hh * SS
		cam.data.sensor_fit = "HORIZONTAL" if w >= hh else "VERTICAL"
		cam.data.ortho_scale = (w if w >= hh else hh) / sx
		f = os.path.join(out, "cmp_%s.png" % view)
		sc.render.filepath = f
		bpy.ops.render.render(write_still=True)
		rend = _resize(_load(f), h, w)
		os.remove(f)
		ref = _load(os.path.join(ref_dir, view + ".png"))
		mask = _load(os.path.join(ref_dir, view + "_mask.png"))[..., 0] > 0.5
		mod = rend[..., 3] > 0.5
		inter = np.logical_and(mask, mod).sum()
		union = np.logical_or(mask, mod).sum()
		iou = inter / max(union, 1)
		miss = np.logical_and(mask, ~mod).sum() / max(mask.sum(), 1)
		extra = np.logical_and(mod, ~mask).sum() / max(mask.sum(), 1)
		agree = _agreement(ref, rend, mask, mod)
		cr, cm = _agreement.last
		crow = np.concatenate([PALETTE[cr], np.zeros((cr.shape[0], 2, 3), np.float32), PALETTE[cm]], axis=1)
		class_rows.append(np.concatenate([crow, np.ones(crow.shape[:2] + (1,), np.float32)], axis=2))
		lines.append("%-6s IoU %.3f   colour %.3f   concept-only %.1f%%   model-only %.1f%%" % (view, iou, agree, miss * 100, extra * 100))
		bg = np.ones((h, w, 4), dtype=np.float32)
		bg[..., :3] = 0.93
		a = rend[..., 3:4]
		model_img = bg.copy()
		model_img[..., :3] = rend[..., :3] * a + bg[..., :3] * (1 - a)
		ov = np.zeros((h, w, 4), dtype=np.float32)
		ov[..., 3] = 1
		ov[..., :3] = 0.12
		ov[mask & mod, :3] = (0.85, 0.85, 0.85)
		ov[mask & ~mod, :3] = (0.95, 0.2, 0.2)
		ov[mod & ~mask, :3] = (0.1, 0.85, 0.95)
		# faint concept lines on the overlay so features can be matched, not just the outline
		lum = ref[..., :3].mean(axis=2, keepdims=True)
		ov[..., :3] = ov[..., :3] * (0.65 + 0.35 * lum)
		sep = np.zeros((h, 4, 4), dtype=np.float32)
		sep[..., 3] = 1
		rows.append(np.concatenate([ref, sep, model_img, sep, ov], axis=1))
	W = max(r.shape[1] for r in rows)
	rows = [np.pad(r, ((0, 6), (0, W - r.shape[1]), (0, 0)), constant_values=0) for r in rows]
	sheet = np.concatenate(rows, axis=0)
	sheet[..., 3] = 1
	_save(sheet, os.path.join(out, "compare.png"))
	CW = max(r.shape[1] for r in class_rows)
	cls = np.concatenate([np.pad(r, ((0, 2), (0, CW - r.shape[1]), (0, 0))) for r in class_rows], axis=0)
	cls[..., 3] = 1
	_save(cls, os.path.join(out, "compare_colour.png"))  # colour families: concept | model (1/4 scale)
	text = "\n".join(lines)
	with open(os.path.join(out, "compare.txt"), "w", encoding="utf-8") as fh:
		fh.write(text + "\n")
	bpy.data.objects.remove(cam, do_unlink=True)
	for o in hidden:
		o.hide_render = False
	print(text)
	print("compare: %s" % os.path.relpath(os.path.join(out, "compare.png"), root))
	return lines

"""Cut a multi-view concept sheet into per-view reference crops + silhouette masks (system Python + Pillow).

	python tools/blender/ref_masks.py models/ref/<name>.json

Writes output/models/<name>/ref/<view>.png (crop) and <view>_mask.png (white = object), which
build.py --compare uses to score and overlay the model renders.
"""

import json
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def silhouette(crop):
	rgb = crop.convert("RGB")
	r, g, b = rgb.split()
	mn = ImageChops.darker(ImageChops.darker(r, g), b)
	mx = ImageChops.lighter(ImageChops.lighter(r, g), b)
	sat = ImageChops.subtract(mx, mn)
	# object = dark ink / shaded paint, or clearly saturated (blue armor, cyan glow); thin pale guide lines are dropped
	dark = mn.point(lambda v: 255 if v < 185 else 0)
	colored = sat.point(lambda v: 255 if v > 40 else 0)
	m = ImageChops.lighter(dark, colored)
	m = m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))   # remove 1-2 px lines (guides, dashes)
	m = m.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))   # close gaps in the outline
	# fill holes: flood the outside from the border; enclosed background is filled only when it is small
	# (paint gaps inside the body), while big enclosed gaps (a cable looping back to an arm) stay background
	w, h = m.size
	pad = Image.new("L", (w + 2, h + 2), 0)
	pad.paste(m, (1, 1))
	ImageDraw.floodfill(pad, (0, 0), 128)
	px = pad.load()
	limit = max_hole * w * h
	for y in range(h + 2):
		for x in range(w + 2):
			if px[x, y] == 0:
				ImageDraw.floodfill(pad, (x, y), 60)
				area = int((np.asarray(pad) == 60).sum())
				ImageDraw.floodfill(pad, (x, y), 255 if area < limit else 128)
	return pad.point(lambda v: 0 if v == 128 else 255).crop((1, 1, w + 1, h + 1))


max_hole = 0.0015  # fraction of the crop: holes smaller than this count as object


def main():
	cfg_path = sys.argv[1]
	name = os.path.splitext(os.path.basename(cfg_path))[0]
	cfg = json.load(open(cfg_path, encoding="utf-8"))
	im = Image.open(os.path.join(ROOT, cfg["image"]))
	out = os.path.join(ROOT, "output", "models", name, "ref")
	os.makedirs(out, exist_ok=True)
	for view, v in cfg["views"].items():
		crop = im.crop(tuple(v["crop"])).convert("RGB")
		crop.save(os.path.join(out, view + ".png"))
		m = silhouette(crop)
		m.save(os.path.join(out, view + "_mask.png"))
		print("%s: %dx%d, object %.1f%%" % (view, crop.width, crop.height,
			100.0 * sum(1 for p in m.get_flattened_data() if p) / (crop.width * crop.height)))


main()

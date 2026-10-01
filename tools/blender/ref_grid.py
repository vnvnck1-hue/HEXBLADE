"""Draw a metre grid (model coordinates) over each reference crop so dimensions can be read off the concept.

	python tools/blender/ref_grid.py models/ref/<name>.json [scale]

Writes output/models/<name>/ref/<view>_grid.png. Labels: front X / Z, side Y / Z, top X / Y (model axes).
"""

import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AXES = {"front": ("X", -1, "Z"), "left": ("Y", -1, "Z"), "right": ("Y", 1, "Z"), "top": ("X", -1, "Y")}

cfg_path = sys.argv[1]
k = int(sys.argv[2]) if len(sys.argv) > 2 else 2
name = os.path.splitext(os.path.basename(cfg_path))[0]
cfg = json.load(open(cfg_path, encoding="utf-8"))
im = Image.open(os.path.join(ROOT, cfg["image"])).convert("RGB")
out = os.path.join(ROOT, "output", "models", name, "ref")
os.makedirs(out, exist_ok=True)
for view, v in cfg["views"].items():
	x0, y0, x1, y1 = v["crop"]
	sx = v["px_per_m"]
	sy = v.get("py_per_m", sx)
	ox, oy = v["origin"]
	ha, hs, va = AXES[v["camera"]]
	vs = -1 if v["camera"] == "top" else 1   # top view: image down = +Y (front)
	c = im.crop((x0, y0, x1, y1)).resize(((x1 - x0) * k, (y1 - y0) * k), Image.LANCZOS)
	d = ImageDraw.Draw(c, "RGBA")
	# horizontal axis value at px:  hs * (px - ox) / sx ; vertical: (oy - py) / sy * vs
	m = -20.0
	while m <= 20.0:
		px = ox + hs * m * sx
		if x0 <= px <= x1:
			X = (px - x0) * k
			major = abs(m - round(m)) < 1e-6
			d.line([(X, 0), (X, c.height)], fill=(255, 0, 80, 150 if major else 60), width=1)
			if major:
				d.text((X + 2, 2), "%s%+d" % (ha, m), fill=(220, 0, 60, 255))
		py = oy - m * sy * vs
		if y0 <= py <= y1:
			Y = (py - y0) * k
			major = abs(m - round(m)) < 1e-6
			d.line([(0, Y), (c.width, Y)], fill=(0, 120, 255, 150 if major else 60), width=1)
			if major:
				d.text((2, Y + 2), "%s%+d" % (va, m), fill=(0, 80, 220, 255))
		m += 0.5
	c.save(os.path.join(out, view + "_grid.png"))
	print(view, c.size)

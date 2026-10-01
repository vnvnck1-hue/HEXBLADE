"""Side-by-side zoom of one region of a compare.png row: concept | model.

	python tools/blender/zoom_compare.py <name> <view> x0 y0 x1 y1 [k]

Coordinates are pixels of the view's reference crop. Writes output/models/<name>/zoom_<view>.png.
"""
import json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
name, view = sys.argv[1], sys.argv[2]
x0, y0, x1, y1 = (int(v) for v in sys.argv[3:7])
k = int(sys.argv[7]) if len(sys.argv) > 7 else 2
cfg = json.load(open(os.path.join(ROOT, "models", "ref", name + ".json"), encoding="utf-8"))
views = list(cfg["views"].keys())
sheet = Image.open(os.path.join(ROOT, "output", "models", name, "compare.png")).convert("RGB")
# rows are stacked in config order: height of each crop + 6 px gap; panels: ref | 4 | model | 4 | overlay
top = 0
for v in views:
	c = cfg["views"][v]["crop"]
	h = c[3] - c[1]
	if v == view:
		w = c[2] - c[0]
		ref = sheet.crop((x0, top + y0, x1, top + y1))
		mod = sheet.crop((w + 4 + x0, top + y0, w + 4 + x1, top + y1))
		break
	top += h + 6
W, H = (x1 - x0) * k, (y1 - y0) * k
out = Image.new("RGB", (W * 2 + 6, H), (0, 0, 0))
out.paste(ref.resize((W, H), Image.LANCZOS), (0, 0))
out.paste(mod.resize((W, H), Image.LANCZOS), (W + 6, 0))
p = os.path.join(ROOT, "output", "models", name, "zoom_%s.png" % view)
out.save(p)
print(p)

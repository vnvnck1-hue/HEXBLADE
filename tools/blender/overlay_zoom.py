"""Enlarge the overlay panel of one view from compare.png:  python tools/blender/overlay_zoom.py <name> <view> [k]"""
import json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
name, view = sys.argv[1], sys.argv[2]
k = int(sys.argv[3]) if len(sys.argv) > 3 else 2
cfg = json.load(open(os.path.join(ROOT, "models", "ref", name + ".json"), encoding="utf-8"))
s = Image.open(os.path.join(ROOT, "output", "models", name, "compare.png")).convert("RGB")
top = 0
for v, c in cfg["views"].items():
	w, h = c["crop"][2] - c["crop"][0], c["crop"][3] - c["crop"][1]
	if v == view:
		s.crop((2 * (w + 4), top, 2 * (w + 4) + w, top + h)).resize((w * k, h * k)).save(
			os.path.join(ROOT, "output", "models", name, "overlay_%s.png" % view))
		break
	top += h + 6

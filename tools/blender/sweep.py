"""Coordinate-descent search of a model script's override parameters against the concept (system Python).

	python tools/blender/sweep.py models/src/spider_boss.py [rounds]

Each evaluation builds the model with HB_OVERRIDE (JSON) and --compare, then scores the silhouette IoU:
score = front + side + 0.5 * top. Results are appended to output/models/<name>/sweep.log; the best
parameter set is written to output/models/<name>/sweep_best.json.
The parameter space below is specific to spider_boss (legs · knees · ankles · gatling · arm poses).
"""

import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PS = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), r"System32\WindowsPowerShell\v1.0\powershell.exe")
WEIGHTS = {"front": 1.0, "side": 1.0, "top": 0.5}

# name: (start, step)
SPACE = {
	"f_ank_y": (3.5, 0.25), "b_ank_y": (-3.6, 0.25),
	"f_knee_z": (4.75, 0.15), "b_knee_z": (4.4, 0.15),
	"knee_x": (4.55, 0.12), "ank_x": (5.75, 0.12),
	"f_knee_y": (2.75, 0.2), "b_knee_y": (-2.1, 0.2),
	"GZ": (2.05, 0.1),
	"weld_z": (0.0, 0.25), "weld_y": (0.0, 0.25),
	"saw_z": (0.0, 0.2), "saw_x": (0.0, 0.15),
	"roll_y": (0.8, 0.1),
	# 덩어리 비율 (PART_T): 배율은 1 기준, 이동은 m
	"head_sx": (1.0, 0.05), "head_sz": (1.0, 0.05), "head_dz": (0.0, 0.1), "head_dy": (0.0, 0.1),
	"abd_sx": (1.0, 0.05), "abd_sz": (1.0, 0.04), "abd_dy": (0.0, 0.1),
	"tib_w": (1.0, 0.08), "tib_t": (1.0, 0.1), "foot_s": (1.0, 0.08),
}


def override(p):
	f_hip, b_hip = (4.1, 2.4, 3.45), (4.1, -1.9, 3.3)
	legs = {
		"f": (f_hip, (p["knee_x"], p["f_knee_y"], p["f_knee_z"]), (p["ank_x"], p["f_ank_y"], 0.9),
			  (p["ank_x"] + 0.1, p["f_ank_y"] + 0.1, 0.0)),
		"b": (b_hip, (p["knee_x"], p["b_knee_y"], p["b_knee_z"]), (p["ank_x"], p["b_ank_y"], 0.95),
			  (p["ank_x"] + 0.1, p["b_ank_y"] - 0.35, 0.0)),
	}
	wz, wy = p["weld_z"], p["weld_y"]
	arm_w = ((3.0, 4.0, 3.95), (3.15, 5.6 + wy * 0.5, 3.6 + wz * 0.5), (3.4, 6.55 + wy, 2.65 + wz), (3.55, 7.45 + wy, 1.0 + wz))
	sz, sx = p["saw_z"], p["saw_x"]
	arm_s = ((-2.9, 4.0, 3.6), (-2.95 - sx * 0.5, 4.6, 2.35 + sz * 0.5), (-3.15 - sx, 5.05, 1.6 + sz), (-3.75 - sx, 5.5, 0.98 + sz))
	r = max(0.0, min(1.0, p["roll_y"]))
	part_t = {
		"head": (p["head_sx"], 1.0, p["head_sz"], 0.0, p["head_dy"], p["head_dz"]),
		"abdomen": (p["abd_sx"], 1.0, p["abd_sz"], 0.0, p["abd_dy"], 0.0),
		"tibia": (p["tib_t"], 1.0, p["tib_w"], 0.0, 0.0, 0.0),
		"foot": (p["foot_s"], p["foot_s"], p["foot_s"], 0.0, 0.0, 0.0),
	}
	return {"LEGS": legs, "GZ": p["GZ"], "ARM_W": arm_w, "ARM_S": arm_s, "ROLL": (round((1 - r * r) ** 0.5, 3), r), "PART_T": part_t}


def evaluate(script, p, log):
	env = dict(os.environ, HB_OVERRIDE=json.dumps(override(p)))
	out = subprocess.run([PS, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", os.path.join(ROOT, "tools", "blender.ps1"),
						  "model", script, "--compare", "--no-preview", "--no-export"],
						 cwd=ROOT, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
	iou = {m.group(1): float(m.group(2)) for m in re.finditer(r"^(\w+)\s+IoU ([0-9.]+)", out, re.M)}
	if len(iou) < 3:
		log.write("FAILED %s\n%s\n" % (json.dumps(p), out[-2000:]))
		log.flush()
		return -1.0, iou
	score = sum(WEIGHTS[k] * v for k, v in iou.items())
	log.write("%.4f %s %s\n" % (score, json.dumps(iou), json.dumps(p)))
	log.flush()
	return score, iou


def main():
	script = sys.argv[1]
	rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 2
	name = os.path.splitext(os.path.basename(script))[0]
	out_dir = os.path.join(ROOT, "output", "models", name)
	best_path = os.path.join(out_dir, "sweep_best.json")
	p = {k: v[0] for k, v in SPACE.items()}
	if os.path.exists(best_path):
		p.update(json.load(open(best_path))["params"])
	step = {k: v[1] for k, v in SPACE.items()}
	with open(os.path.join(out_dir, "sweep.log"), "a", encoding="utf-8") as log:
		best, iou = evaluate(script, p, log)
		print("start %.4f %s" % (best, iou), flush=True)
		for r in range(rounds):
			improved = False
			for k in SPACE:
				for sgn in (1, -1):
					q = dict(p)
					q[k] = round(p[k] + sgn * step[k], 4)
					sc, qi = evaluate(script, q, log)
					if sc > best + 1e-4:
						best, p, iou, improved = sc, q, qi, True
						json.dump({"score": best, "iou": iou, "params": p, "override": override(p)}, open(best_path, "w"), indent=1)
						print("round %d  %s %+g -> %.4f %s" % (r, k, sgn * step[k], best, iou), flush=True)
						break
			if not improved:
				for k in step:
					step[k] /= 2
				print("round %d: no gain, halving steps" % r, flush=True)
	print("best %.4f %s\n%s" % (best, iou, json.dumps(p)), flush=True)


main()

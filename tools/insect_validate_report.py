"""Save evidence from the pinned Blender/Godot validation logs for handoff."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / "output/insects-20261002"
names = {"import":"insect_import", "insect_test":"insect_check_final", "regression":"insect_regression",
         "studio_24s":"insect_studio", "combat_30s":"insect_combat", "main_bot_60s":"insect_main_bot"}
report = {"date":"2026-10-02", "blender":(root/"blender-version.txt").read_text().strip(),
          "godot":(root/"godot-version.txt").read_text().strip(), "checks":{}, "models":{},
          "animation_tool":"Godot procedural driver; no baked clips in GLB/Blender source"}
for name, stem in names.items():
    log = (root/"_capture"/(stem+".log")).read_text(encoding="utf-8-sig", errors="replace")
    errors = [s for s in log.splitlines() if re.match(r"\s*(SCRIPT ERROR|ERROR:|FAIL\b|FAILED:)", s)]
    warnings = [s for s in log.splitlines() if s.startswith("WARNING:")]
    item = {"errors":errors, "warnings":warnings, "log":stem+".log"}
    if name == "regression":
        item["summary"] = re.findall(r"ALL \d+ TESTS PASSED", log)
    if name == "combat_30s":
        item["ant_attack_completions"] = log.count("INSECT ANT ATTACK")
        item["grub_attack_completions"] = log.count("INSECT GRUB ATTACK")
        item["successful_parries"] = log.count("PARRY melee")
    if name == "insect_test":
        item["summary"] = re.findall(r"RESULT .+",log)
    report["checks"][name] = item
    (out/(stem+".log")).write_text(log,encoding="utf-8")
for kind in ("ant","grub"):
    stats = (root/"output/models"/("insect_"+kind)/"stats.txt").read_text()
    report["models"][kind] = {"triangles":int(re.search(r"triangles (\d+)",stats)[1]),
                             "glb_bytes":(root/"assets/models"/("insect_"+kind+".glb")).stat().st_size}
assert all(not item["errors"] for item in report["checks"].values()), report
assert report["checks"]["regression"]["summary"]
assert report["checks"]["combat_30s"]["ant_attack_completions"] > 0
assert report["checks"]["combat_30s"]["grub_attack_completions"] > 0
(out/"validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("insect validation saved: all runtime ERROR/SCRIPT ERROR counts are zero")

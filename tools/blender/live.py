"""Live bridge for an open Blender window:  tools\\blender.ps1 live [file.blend]

The window polls .tools/blender_live/inbox/ and runs every <id>.py dropped there (tools\\blender.ps1 send <file.py>)
inside the running session, with hb / bpy / math / Vector / snap preloaded, then writes outbox/<id>.txt:
first line "OK" or "ERROR", then everything the code printed (and the traceback).
So an agent can model in the same scene the user is watching, and the user can keep editing by hand.

  snap(path=None)  saves a screenshot of the largest 3D viewport (default .tools/blender_live/snap.png)
                   and prints the path; the agent reads the image to see the result.
"""

import contextlib
import io
import math
import os
import sys
import traceback

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import hb  # noqa: E402

BOX = os.path.join(ROOT, ".tools", "blender_live")
INBOX = os.path.join(BOX, "inbox")
OUTBOX = os.path.join(BOX, "outbox")
_ns = {}


def snap(path=None):
	path = path or os.path.join(BOX, "snap.png")
	best = None
	for win in bpy.context.window_manager.windows:
		for area in win.screen.areas:
			if area.type == "VIEW_3D" and (best is None or area.width * area.height > best[1].width * best[1].height):
				best = (win, area)
	if best is None:
		raise RuntimeError("no 3D viewport open")
	win, area = best
	region = next(r for r in area.regions if r.type == "WINDOW")
	with bpy.context.temp_override(window=win, area=area, region=region):
		bpy.ops.screen.screenshot_area(filepath=path)
	print("snap: " + path)
	return path


def _namespace():
	if not _ns:
		_ns.update({"hb": hb, "bpy": bpy, "math": math, "Vector": Vector, "snap": snap, "__name__": "__hb_live__"})
	return _ns


def _run(path):
	job = os.path.splitext(os.path.basename(path))[0]
	buf = io.StringIO()
	status = "OK"
	try:
		with open(path, encoding="utf-8") as fh:
			code = fh.read()
		with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
			exec(compile(code, path, "exec"), _namespace())
	except Exception:
		status = "ERROR"
		buf.write(traceback.format_exc())
	finally:
		with contextlib.suppress(OSError):
			os.remove(path)
	tmp = os.path.join(OUTBOX, job + ".tmp")
	with open(tmp, "w", encoding="utf-8") as fh:
		fh.write(status + "\n" + buf.getvalue())
	os.replace(tmp, os.path.join(OUTBOX, job + ".txt"))
	for area in (a for w in bpy.context.window_manager.windows for a in w.screen.areas):
		area.tag_redraw()


def _poll():
	try:
		for f in sorted(os.listdir(INBOX)):
			if f.endswith(".py"):
				_run(os.path.join(INBOX, f))
	except Exception:
		traceback.print_exc()
	return 0.25


os.makedirs(INBOX, exist_ok=True)
os.makedirs(OUTBOX, exist_ok=True)
with open(os.path.join(BOX, "alive.txt"), "w", encoding="utf-8") as fh:
	fh.write(str(os.getpid()))
bpy.app.timers.register(_poll, first_interval=0.5, persistent=True)
print("[hb live] watching " + INBOX)

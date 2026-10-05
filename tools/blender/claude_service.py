"""claude_service — 1번 설비실 합성안 프랍 5종(S01~S05, Claude)의 공용 재질·형상.

docs/service-machinery-claude-handoff.md · docs/service-machinery-claude.md 참고. models/src/bg_claude_service_*.py 가 부른다.

  mats()                      공유 칠 재질 사전 (navy · steel · slate · teal · cream · dark · lamp)
  sweep_arc(...)              90도 꺾인 원통(배관 꺾임·밴드)을 bmesh 로 정확히 만든다 (단면이 항상 중심선에 수직)
  pipe_y()                    배관 중심 높이 (밴드 외경 0.60 이 바닥에 닿음) = 0.30

배관 규격 (S02 포트 · S03 · S04 공통): 몸통 외경 0.50 · 밴드 외경 0.60 · 중심 높이 0.30 · 끝단은 축에 수직인 평면.
좌표는 Blender (정면 +Y = Godot -Z, z 위).
"""

import math

import bmesh
import bpy
from mathutils import Vector

import hb
import claude_background_bake as cbb

PIPE_R = 0.25        # 몸통 외경 0.50
BAND_R = 0.30        # 밴드 외경 0.60
PIPE_Y = 0.30        # 중심 높이
BAND_W = 0.12        # 밴드 폭


def finish(part):
	"""after_join 공통: 피벗을 바닥 원점에 두고 오브젝트 회전·배율을 메시에 굽는다 (합친 메시가 첫 도형의 회전을 물려받아
	GLB 노드에 회전이 남으면 게임의 MultiMesh(메시만 꺼냄)에서 축이 틀어진다)."""
	o = hb.get(part)
	hb.set_origin(o, (0, 0, 0))
	bpy.ops.object.select_all(action="DESELECT")
	o.select_set(True)
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
	return o


def pipe_y():
	return PIPE_Y


def mats():
	"""둥근 면(원통)은 면 방향으로 베벨을 잡는 칠이 몸통 전체에 번지므로 bevel_hi 를 낮춘 *_r 재질을 따로 둔다."""
	return {
		"navy": cbb.paint_mat("svc_navy", "navy", hi="#55628F", lo="#191D33", wear="#6B76A0", wear_amt=0.25, grad_h=1.6),
		"navy_r": cbb.paint_mat("svc_navy_r", "navy", hi="#55628F", lo="#191D33", bevel_hi=0.12, grad_h=1.6),
		"steel": cbb.paint_mat("svc_steel", "steel", hi="#7C96C2", lo="#1F2D48", wear="#8EA4C8", wear_amt=0.3, grad_h=1.0, hgrad=0.12),
		"slate": cbb.paint_mat("svc_slate", "slate", hi="#7476A0", lo="#202138", wear="#8587AE", wear_amt=0.3, grad_h=1.6, hgrad=0.12),
		"teal_r": cbb.paint_mat("svc_teal_r", "teal", hi="#5FA3A6", lo="#173B44", bevel_hi=0.12, grad_h=1.65, hgrad=0.16),
		"cream_r": cbb.paint_mat("svc_cream_r", "cream", hi="#E2DAC4", lo="#6A6252", bevel_hi=0.15, grad_h=0.6, hgrad=0.0),
		"dark": cbb.paint_mat("svc_dark", "deep", hi="#3A4166", lo="#0F1222", grad_h=1.6, hgrad=0.0, bevel_hi=0.4),
		"hole": cbb.paint_mat("svc_hole", "void", hi="#141729", lo="#0A0C16", bevel_hi=0.0, ao=0.0, hgrad=0.0),
		"lamp": cbb.paint_mat("svc_lamp", "lamp", hi="#FFF6D6", lo="#C9B47A", bevel_hi=0.3, ao=0.0, hgrad=0.0),
	}


LAMP = "svc_lamp"      # bake_model(emit=(LAMP,)) 에 넘기는 발광 재질 이름


def sweep_arc(name, center, R, r, a0, a1, z, mat, part, steps=12, verts=24, cap0=False, cap1=False):
	"""XY 평면의 원호 중심선(center, 반지름 R, 각도 a0→a1 도)을 따라 반지름 r 의 원통을 만든다. z = 중심 높이.
	단면 원은 항상 중심선 접선에 수직 → 끝단이 직선 배관 끝단과 정확히 맞는다."""
	bm = bmesh.new()
	rings = []
	for k in range(steps + 1):
		t = math.radians(a0 + (a1 - a0) * k / steps)
		u = Vector((math.cos(t), math.sin(t), 0.0))          # 원호 바깥 방향
		w = Vector((0.0, 0.0, 1.0))
		p = Vector((center[0], center[1], z)) + u * R
		rings.append([bm.verts.new(p + (u * math.cos(f) + w * math.sin(f)) * r)
					  for f in (2 * math.pi * i / verts for i in range(verts))])
	for a, b in zip(rings, rings[1:]):
		for i in range(verts):
			j = (i + 1) % verts
			bm.faces.new((a[i], a[j], b[j], b[i]))
	if cap0:
		bm.faces.new(rings[0])
	if cap1:
		bm.faces.new(rings[-1])
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	for f in bm.faces:
		f.smooth = len(f.verts) == 4
	return hb._finish(hb._from_bmesh(name, bm), name, (0, 0, 0), (0, 0, 0), mat, None, 0, 0, part, False)


def pipe_end(name, x, axis, sign, M, part):
	"""직선 축(axis 'X'/'Y')의 끝단 좌표 x 에 끝 테 + 짙은 속(구멍) — 배관 끝이 열려 보이게. sign = 바깥 방향."""
	rot = (0, 90, 0) if axis == "X" else (90, 0, 0)

	def at(d):
		v = x + sign * d
		return (v, 0, PIPE_Y) if axis == "X" else (0, v, PIPE_Y)
	hb.cyl(name + "_lip", r=PIPE_R + 0.012, depth=0.03, loc=at(-0.015), rot=rot, verts=24, mat=M["navy_r"], part=part)
	hb.cyl(name + "_hole", r=PIPE_R - 0.06, depth=0.004, loc=at(0.001), rot=rot, verts=20, mat=M["hole"], part=part)

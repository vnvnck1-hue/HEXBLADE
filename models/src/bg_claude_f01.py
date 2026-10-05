# F01 기본 바닥 (Claude 배경 첫 제작) — 2 x 2 x 0.2 m. 기준: output/background-modular-kit-20261003/sheets/F01.png
# 빌드:  powershell -File tools\blender.ps1 model models\src\bg_claude_f01.py --engine=eevee
# 피벗 = 좌측 앞 윗모서리. Godot X 0~2, Z 0~2, Y -0.2~0  →  Blender x 0~2, y -2~0, z -0.2~0.
# 모서리 8mm 베벨로 줄눈을 표현한다 (판을 줄여 틈을 뚫지 않음).
#
# 텍스처: 2048px = 4m 반복(claude_background_paint.floor_4m). 2m 타일 네 장의 줄눈·베벨 칠·선택 마모가 그려져 있다.
# UV 는 월드 위치와 같은 위상 — Godot UV = (X/4, Z/4). 이 GLB 하나만 쓰면 언제나 4m 그림의 왼쪽 위 1/4(1024px)이 보이고,
# 시험 씬은 같은 텍스처를 월드 좌표로 읽는 셰이더(scripts/claude_background/bg_floor.gdshader)를 씌워 4m 주기를 잇는다.

import os

import claude_background_bake as cbb

img = bpy.data.images.load(cbb.floor_texture())
img.name = "bg_claude_floor_4m"
m = bpy.data.materials.new("bg_claude_f01")
m.use_nodes = True
b = m.node_tree.nodes.get("Principled BSDF")
t = m.node_tree.nodes.new("ShaderNodeTexImage")
t.image = img
m.node_tree.links.new(t.outputs["Color"], b.inputs["Base Color"])
b.inputs["Metallic"].default_value = 0.0
b.inputs["Roughness"].default_value = 0.85
b.inputs["Specular IOR Level"].default_value = 0.25
m.diffuse_color = (0.09, 0.06, 0.25, 1)

hb.box("floor", (2.0, 2.0, 0.2), loc=(1.0, -1.0, -0.1), mat=m, bevel=0.008, seg=2)


def after_join():
	o = hb.get("floor")
	hb.apply_mods(o)
	hb.set_origin(o, (0, 0, 0))
	me = o.data
	for l in list(me.uv_layers):
		me.uv_layers.remove(l)
	uvl = me.uv_layers.new(name="UVMap").data
	for p in me.polygons:
		n = p.normal
		for li in p.loop_indices:
			v = me.vertices[me.loops[li].vertex_index].co
			if abs(n.x) > 0.6:          # 옆면 X: (Y, Z) 투영
				u, w = -v.y, v.z
			elif abs(n.y) > 0.6:        # 옆면 Y: (X, Z) 투영
				u, w = v.x, v.z
			else:                       # 윗면·아랫면·베벨: 월드 XZ 와 같은 위상
				u, w = v.x, v.y
			uvl[li].uv = (u / 4.0, 1.0 + w / 4.0)

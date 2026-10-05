"""Render the actual model at measured 64/96/128 pixel projected heights.
No geometry simplification, pasted concept art or upscaled preview is used.
"""
import os
import json
import sys
import bpy
from mathutils import Vector, Matrix

ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT=os.path.join(ROOT,"output","models","tutorial_alien_b")
suffix="_lod" if "--lod" in sys.argv else ""
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT,"tutorial_alien_b"+suffix+"_toon_studio.blend"))
sc=bpy.context.scene; cam=sc.camera
cam.data.type="ORTHO"; cam.data.sensor_fit="HORIZONTAL"; cam.data.ortho_scale=.90
cam.location=Vector((.35,.55,1.1)).normalized()*2
cam.rotation_euler=(-cam.location).to_track_quat("-Z","Y").to_euler()
quat=cam.rotation_euler.to_quaternion()
right=quat@Vector((1,0,0)); up=quat@Vector((0,1,0))
meshes=[o for o in sc.objects if o.type=="MESH" and not o.name.startswith("STUDIO_")]
points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
lo=min(p.dot(up) for p in points); hi=max(p.dot(up) for p in points)
center_up=(lo+hi)/2
center_right=(min(p.dot(right) for p in points)+max(p.dot(right) for p in points))/2
sc.render.resolution_x=768; sc.render.resolution_y=320; sc.render.resolution_percentage=100
for o in list(sc.objects):
    if o.type=="MESH": o.hide_render=True
sc.world.node_tree.nodes.get("Background").inputs["Color"].default_value=(.43,.405,.36,1)
sc.world.node_tree.nodes.get("Background").inputs["Strength"].default_value=1
font_material=bpy.data.materials.new("SIZE_REVIEW_label"); font_material.use_nodes=True
nt=font_material.node_tree; nt.nodes.clear()
out=nt.nodes.new("ShaderNodeOutputMaterial"); emit=nt.nodes.new("ShaderNodeEmission")
emit.inputs["Color"].default_value=(.12,.10,.08,1); nt.links.new(emit.outputs[0],out.inputs[0])
rows=[]
for column,pixels in enumerate((64,96,128)):
    scale=pixels/(768/.90)/(hi-lo)
    offset=right*((column-1)*.28-center_right*scale)-up*center_up*scale
    transform=Matrix.Translation(offset)@Matrix.Scale(scale,4)
    for original in meshes:
        clone=original.copy(); clone.data=original.data
        sc.collection.objects.link(clone); clone.parent=None
        clone.matrix_world=transform@original.matrix_world
        clone.hide_render=False; clone.hide_set(False)
    bpy.ops.object.text_add(location=right*((column-1)*.28)+up*.11)
    label=bpy.context.object; label.rotation_euler=cam.rotation_euler
    label.data.body=str(pixels)+" px"; label.data.align_x="CENTER"; label.data.size=.019
    label.data.materials.append(font_material)
    rows.append({"projected_height_px":pixels,"uniform_scale":scale})
sc.render.filepath=os.path.join(OUT,"small_screen_review"+suffix+".png")
bpy.ops.render.render(write_still=True)
with open(os.path.join(OUT,"small_screen_review"+suffix+".json"),"w",encoding="utf-8") as f:
    json.dump({"type":"Blender top-game-view projection, not a Godot gameplay screenshot","columns":rows,"file":"small_screen_review"+suffix+".png"},f,indent=2)
print("SMALL_SCREEN_REVIEW_OK")

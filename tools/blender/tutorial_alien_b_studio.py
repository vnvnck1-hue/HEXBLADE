"""Reproducible EEVEE toon studio, renders the actual low-poly Blender geometry."""
import os
import math
import json
import bpy
import numpy as np
from mathutils import Vector

ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT=os.path.join(ROOT,"output","models","tutorial_alien_b")
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT,"tutorial_alien_b.blend"))
sc=bpy.context.scene
sc.render.engine="BLENDER_EEVEE"
sc.eevee.taa_render_samples=64
sc.render.resolution_x=768; sc.render.resolution_y=768; sc.render.resolution_percentage=100
sc.render.image_settings.file_format="PNG"
sc.view_settings.view_transform="Standard"
sc.view_settings.look="None"
sc.view_settings.exposure=0
world=bpy.data.worlds.new("Cartoon warm studio"); sc.world=world; world.use_nodes=True
world.node_tree.nodes.get("Background").inputs["Color"].default_value=(.52,.49,.43,1)
world.node_tree.nodes.get("Background").inputs["Strength"].default_value=.25

# Convert the export-safe image texture material to a true EEVEE stepped diffuse shader.
m=bpy.data.materials.get("B_cartoon_atlas"); nt=m.node_tree
nt.nodes.clear()
out=nt.nodes.new("ShaderNodeOutputMaterial")
tex=nt.nodes.new("ShaderNodeTexImage"); tex.name="Painted_Atlas"; tex.image=bpy.data.images.get("B_painted_atlas_512x256")
diff=nt.nodes.new("ShaderNodeBsdfDiffuse"); diff.inputs["Color"].default_value=(1,1,1,1)
rgb=nt.nodes.new("ShaderNodeShaderToRGB")
normalize=nt.nodes.new("ShaderNodeMath"); normalize.operation="MULTIPLY"
normalize.name="Diffuse_range_0_to_3"; normalize.inputs[1].default_value=1/3
ramp=nt.nodes.new("ShaderNodeValToRGB"); ramp.name="Three_tone_cel_ramp"
ramp.color_ramp.interpolation="EASE"
# Saved-studio probe measured diffuse 10/50/90 percentiles .32/1.29/2.65.
# The old .65 bright threshold clipped most surfaces to one flat highlight.
ramp.color_ramp.elements[0].position=.16/3; ramp.color_ramp.elements[0].color=(.52,.42,.35,1)
ramp.color_ramp.elements[1].position=2.65/3; ramp.color_ramp.elements[1].color=(1,1,1,1)
mid=ramp.color_ramp.elements.new(.95/3); mid.color=(.83,.76,.64,1)
cool=nt.nodes.new("ShaderNodeValToRGB"); cool.name="Teal_three_tone_ramp"
cool.color_ramp.interpolation="EASE"
cool.color_ramp.elements[0].position=.16/3; cool.color_ramp.elements[0].color=(.62,.67,.65,1)
cool.color_ramp.elements[1].position=2.65/3; cool.color_ramp.elements[1].color=(1,1,1,1)
cool_mid=cool.color_ramp.elements.new(.95/3); cool_mid.color=(.96,.98,.96,1)
channels=nt.nodes.new("ShaderNodeSeparateColor"); channels.name="Atlas_color_family"
teal=nt.nodes.new("ShaderNodeMath"); teal.operation="GREATER_THAN"; teal.name="Teal_mask_G_gt_R"
tone=nt.nodes.new("ShaderNodeMixRGB"); tone.blend_type="MIX"; tone.name="Warm_shell_cool_skin"
ivory=nt.nodes.new("ShaderNodeValToRGB"); ivory.name="Ivory_three_tone_ramp"
ivory.color_ramp.interpolation="EASE"
ivory.color_ramp.elements[0].position=.16/3; ivory.color_ramp.elements[0].color=(.80,.74,.62,1)
ivory.color_ramp.elements[1].position=2.65/3; ivory.color_ramp.elements[1].color=(1,1,1,1)
ivory_mid=ivory.color_ramp.elements.new(.95/3); ivory_mid.color=(.97,.93,.85,1)
ivory_red=nt.nodes.new("ShaderNodeMath"); ivory_red.operation="GREATER_THAN"; ivory_red.inputs[1].default_value=.75
ivory_blue=nt.nodes.new("ShaderNodeMath"); ivory_blue.operation="GREATER_THAN"; ivory_blue.inputs[1].default_value=.40
ivory_mask=nt.nodes.new("ShaderNodeMath"); ivory_mask.operation="MULTIPLY"; ivory_mask.name="Ivory_mask"
final_tone=nt.nodes.new("ShaderNodeMixRGB"); final_tone.name="Keep_teeth_light_cream"
mul=nt.nodes.new("ShaderNodeMixRGB"); mul.blend_type="MULTIPLY"; mul.inputs[0].default_value=1
emit=nt.nodes.new("ShaderNodeEmission"); emit.inputs["Strength"].default_value=1
nt.links.new(diff.outputs[0],rgb.inputs[0]); nt.links.new(rgb.outputs[0],normalize.inputs[0]); nt.links.new(normalize.outputs[0],ramp.inputs[0])
nt.links.new(normalize.outputs[0],cool.inputs[0]); nt.links.new(tex.outputs["Color"],channels.inputs[0])
nt.links.new(channels.outputs["Green"],teal.inputs[0]); nt.links.new(channels.outputs["Red"],teal.inputs[1])
nt.links.new(teal.outputs[0],tone.inputs[0]); nt.links.new(ramp.outputs[0],tone.inputs[1]); nt.links.new(cool.outputs[0],tone.inputs[2])
nt.links.new(normalize.outputs[0],ivory.inputs[0])
nt.links.new(channels.outputs["Red"],ivory_red.inputs[0]); nt.links.new(channels.outputs["Blue"],ivory_blue.inputs[0])
nt.links.new(ivory_red.outputs[0],ivory_mask.inputs[0]); nt.links.new(ivory_blue.outputs[0],ivory_mask.inputs[1])
nt.links.new(ivory_mask.outputs[0],final_tone.inputs[0]); nt.links.new(tone.outputs[0],final_tone.inputs[1]); nt.links.new(ivory.outputs[0],final_tone.inputs[2])
nt.links.new(tex.outputs["Color"],mul.inputs[1]); nt.links.new(final_tone.outputs[0],mul.inputs[2])
nt.links.new(mul.outputs[0],emit.inputs[0]); nt.links.new(emit.outputs[0],out.inputs[0])
for node,pos in ((tex,(-620,180)),(diff,(-620,-100)),(rgb,(-410,-100)),(ramp,(-210,-100)),(mul,(30,130)),(emit,(240,130)),(out,(440,130))):
    node.location=pos
normalize.location=(-330,-290); cool.location=(-210,-410)
channels.location=(-620,390); teal.location=(-400,390); tone.location=(20,-140)
ivory.location=(-210,-710); ivory_red.location=(-400,660); ivory_blue.location=(-400,810)
ivory_mask.location=(-170,660); final_tone.location=(240,-160)

def light(name,loc,energy,size,color):
    data=bpy.data.lights.new(name,"AREA"); data.energy=energy; data.shape="DISK"; data.size=size; data.color=color
    ob=bpy.data.objects.new(name,data); sc.collection.objects.link(ob); ob.location=loc
    ob.rotation_euler=(Vector((0,0,.16))-ob.location).to_track_quat("-Z","Y").to_euler()
    return ob
light("Key_warm",(-.7,.8,1.15),45,.75,(1,.90,.75))
light("Fill_cool",(.7,.2,.6),10,1,(.79,.93,1))
light("Rim_soft",(.1,-.7,.9),22,.7,(1,.92,.78))

# Screen-space outline via compositor normal/depth edges: no outline mesh triangles.
sc.view_layers[0].use_pass_normal=True
nt=bpy.data.node_groups.new("Cartoon outline compositor","CompositorNodeTree")
sc.compositing_node_group=nt
nt.interface.new_socket(name="Image",in_out="OUTPUT",socket_type="NodeSocketColor")
rl=nt.nodes.new("CompositorNodeRLayers")
edge=nt.nodes.new("CompositorNodeFilter"); edge.inputs["Type"].default_value="Sobel"
nt.links.new(rl.outputs["Normal"],edge.inputs["Image"])
gray=nt.nodes.new("CompositorNodeRGBToBW"); nt.links.new(edge.outputs[0],gray.inputs[0])
dilate=nt.nodes.new("CompositorNodeDilateErode"); dilate.inputs["Size"].default_value=1
nt.links.new(gray.outputs[0],dilate.inputs["Mask"])
cr=nt.nodes.new("ShaderNodeValToRGB"); cr.color_ramp.elements[0].position=.30
cr.color_ramp.elements[0].color=(1,1,1,1); cr.color_ramp.elements[1].position=.90
cr.color_ramp.elements[1].color=(.27,.24,.20,1)
nt.links.new(dilate.outputs[0],cr.inputs[0])
mix=nt.nodes.new("ShaderNodeMix"); mix.data_type="RGBA"; mix.blend_type="MULTIPLY"; mix.inputs[0].default_value=.85
nt.links.new(rl.outputs["Image"],mix.inputs[6]); nt.links.new(cr.outputs[0],mix.inputs[7])
co=nt.nodes.new("NodeGroupOutput"); nt.links.new(mix.outputs[2],co.inputs["Image"])

gm=bpy.data.materials.new("Warm_gray_floor"); gm.use_nodes=True
gm.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value=(.36,.34,.30,1)
gm.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value=1
gn=gm.node_tree.nodes; gn.clear()
go=gn.new("ShaderNodeOutputMaterial"); ge=gn.new("ShaderNodeEmission")
ge.inputs["Color"].default_value=(.43,.405,.36,1)
gm.node_tree.links.new(ge.outputs[0],go.inputs[0])
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.001))
floor=bpy.context.object; floor.name="STUDIO_floor"; floor.data.materials.append(gm)
# Simple flattened shadow graphic reinforces the cartoon turnaround grounding.
shadow=bpy.data.materials.new("Soft_oval_contact_shadow"); shadow.use_nodes=True
shadow.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value=(.23,.215,.18,1)
sn=shadow.node_tree.nodes; sn.clear()
so=sn.new("ShaderNodeOutputMaterial"); se=sn.new("ShaderNodeEmission")
se.inputs["Color"].default_value=(.34,.32,.28,1)
shadow.node_tree.links.new(se.outputs[0],so.inputs[0])
bpy.ops.mesh.primitive_circle_add(vertices=48,radius=1,fill_type="NGON",location=(0,0,.0001))
oval=bpy.context.object; oval.name="STUDIO_contact_shadow"; oval.scale=(.24,.235,1); oval.data.materials.append(shadow)

cam=bpy.data.objects.new("STUDIO_camera",bpy.data.cameras.new("STUDIO_camera")); sc.collection.objects.link(cam); sc.camera=cam
cam.data.type="ORTHO"; cam.data.ortho_scale=.60; cam.data.clip_start=.001
target=Vector((0,0,.177))
views=[("front",(0,1,0)),("right",(-1,0,0)),("back",(0,-1,0)),("beauty",(.72,1,.30)),("top_game",(.35,.55,1.1))]
files=[]
for name,vec in views:
    cam.location=target+Vector(vec).normalized()*2
    cam.rotation_euler=(target-cam.location).to_track_quat("-Z","Y").to_euler()
    sc.render.filepath=os.path.join(OUT,"toon_"+name+".png")
    bpy.ops.render.render(write_still=True); files.append(sc.render.filepath)
# Pack a three-view comparison and a four-view render sheet.
def sheet(paths,path,nx):
    tiles=[]
    for p in paths:
        im=bpy.data.images.load(p,check_existing=False)
        data=np.empty(768*768*4,dtype=np.float32); im.pixels.foreach_get(data)
        tiles.append(data.reshape(768,768,4)); bpy.data.images.remove(im)
    rows=[np.concatenate(tiles[i:i+nx],axis=1) for i in range(0,len(tiles),nx)]
    a=np.concatenate(rows[::-1],axis=0)
    im=bpy.data.images.new("Render_sheet",a.shape[1],a.shape[0],alpha=True)
    im.pixels.foreach_set(a.ravel()); im.filepath_raw=path; im.file_format="PNG"; im.save()
sheet(files[:3],os.path.join(OUT,"model_three_views.png"),3)
sheet([files[0],files[1],files[3],files[4]],os.path.join(OUT,"preview.png"),2)
cam.location=target+Vector((.72,1,.30)).normalized()*2
cam.rotation_euler=(target-cam.location).to_track_quat("-Z","Y").to_euler()
sc.render.filepath=os.path.join(OUT,"toon_beauty.png")
# Hide studio props in solid mode but retain them in render.
for ob in (floor,oval): ob.hide_set(True)
for area in bpy.context.screen.areas:
    if area.type=="VIEW_3D":
        area.spaces.active.region_3d.view_perspective="CAMERA"
        area.spaces.active.shading.type="MATERIAL"
        area.spaces.active.shading.use_scene_lights=True
        area.spaces.active.shading.use_scene_world=True
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,"tutorial_alien_b_toon_studio.blend"),compress=True)
print("TOON_STUDIO_OK",OUT)

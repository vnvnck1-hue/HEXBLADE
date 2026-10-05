"""Measure the saved studio diffuse values to calibrate the toon ramp."""
import os
import bpy
import numpy as np
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT=os.path.join(ROOT,"output","models","tutorial_alien_b")
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT,"tutorial_alien_b_toon_studio.blend"))
sc=bpy.context.scene
sc.compositing_node_group=None
sc.render.resolution_x=sc.render.resolution_y=256
sc.render.film_transparent=True
for o in sc.objects:
    if o.name.startswith("STUDIO_") and o.type=="MESH": o.hide_render=True
nt=bpy.data.materials["B_cartoon_atlas"].node_tree
rgb=next(n for n in nt.nodes if n.bl_idname=="ShaderNodeShaderToRGB")
em=next(n for n in nt.nodes if n.bl_idname=="ShaderNodeEmission")
nt.links.new(rgb.outputs[0],em.inputs[0])
sc.render.image_settings.file_format="OPEN_EXR"
sc.render.image_settings.color_depth="32"
sc.render.filepath=os.path.join(OUT,"diffuse_probe.exr")
bpy.ops.render.render(write_still=True)
im=bpy.data.images.load(sc.render.filepath,check_existing=False)
a=np.empty(256*256*4,dtype=np.float32); im.pixels.foreach_get(a); a=a.reshape(-1,4)
print("DIFFUSE_QUANTILES",np.quantile(a[a[:,3]>.9,:3].mean(1),[0,.1,.25,.5,.75,.9,1]).tolist())

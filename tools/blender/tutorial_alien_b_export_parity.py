"""Render a freshly imported GLB under the saved Blender toon studio.
This checks export shape/normals/UV, not Godot toon shader parity.
"""
import os
import sys
import json
import bpy
import numpy as np

root=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out=os.path.join(root,"output","models","tutorial_alien_b")
suffix="_lod" if "--lod" in sys.argv else ""
bpy.ops.wm.open_mainfile(filepath=os.path.join(out,"tutorial_alien_b"+suffix+"_toon_studio.blend"))
sc=bpy.context.scene
toon=bpy.data.materials["B_cartoon_atlas"]
toon.use_fake_user=True
for ob in list(sc.objects):
    if not ob.name.startswith("STUDIO_") and ob.type!="LIGHT":
        bpy.data.objects.remove(ob,do_unlink=True)
before=set(sc.objects)
bpy.ops.import_scene.gltf(filepath=os.path.join(root,"assets","models","tutorial_alien_b"+suffix+".glb"))
embedded_image=None
for ob in set(sc.objects)-before:
    if ob.type=="MESH":
        if embedded_image is None:
            imported_material=ob.data.materials[0]
            embedded_image=next(n.image for n in imported_material.node_tree.nodes if n.bl_idname=="ShaderNodeTexImage" and n.image is not None)
        ob.data.materials.clear(); ob.data.materials.append(toon)
        for p in ob.data.polygons:
            p.material_index=0
if embedded_image is None:
    raise AssertionError("GLB embedded image missing")
toon.node_tree.nodes["Painted_Atlas"].image=embedded_image
render=os.path.join(out,"glb_toon_parity"+suffix+".png")
sc.render.filepath=render
bpy.ops.render.render(write_still=True)

def load(path):
    im=bpy.data.images.load(path,check_existing=False)
    a=np.empty(im.size[0]*im.size[1]*4,dtype=np.float32)
    im.pixels.foreach_get(a)
    bpy.data.images.remove(im)
    return a.reshape(-1,4)[:,:3]
ref=load(os.path.join(out,"toon_beauty"+suffix+".png"))
actual=load(render)
delta=np.abs(ref-actual)
report={"glb": "tutorial_alien_b"+suffix+".glb",
        "comparison": "Same camera/lights/Blender toon shader; fresh GLB geometry/normals/UV/embedded texture",
        "mean_absolute_rgb_difference":float(delta.mean()),
        "fraction_pixels_over_0_05_rgb_difference":float((delta.max(axis=1)>.05).mean()),
        "is_godot_toon_validation":False}
report["pass"]=report["mean_absolute_rgb_difference"]<.003 and report["fraction_pixels_over_0_05_rgb_difference"]<.01
with open(os.path.join(out,"export_parity"+suffix+".json"),"w",encoding="utf-8") as f:
    json.dump(report,f,ensure_ascii=False,indent=2)
print("EXPORT_RENDER_PARITY",json.dumps(report))
if not report["pass"]:
    raise AssertionError("Export render differs; inspect images before accepting")

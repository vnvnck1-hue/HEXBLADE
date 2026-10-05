"""Generate an optional game-size LOD, without replacing the reference model.
Transfer the original curved normals back after reduction; UV/material/parts stay.
"""
import os
import json
import bpy
from mathutils import Vector

ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT=os.path.join(ROOT,"output","models","tutorial_alien_b")
LOD_BLEND=os.path.join(OUT,"tutorial_alien_b_lod.blend")
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT,"tutorial_alien_b.blend"))
sc=bpy.context.scene
meshes=[o for o in sc.objects if o.type=="MESH"]
references={}; ratios={"body":.40,"shell":.42,"brow":.48,"jaw":.48}
report={"parts":{}}
def bounds(objects):
    points=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
    return (Vector(tuple(min(p[a] for p in points) for a in range(3))),
            Vector(tuple(max(p[a] for p in points) for a in range(3))))
base_lo,base_hi=bounds(meshes)
for ob in meshes:
    source=ob.copy(); source.data=ob.data.copy(); source.parent=None
    source.matrix_world=ob.matrix_world.copy(); source.name="NORMAL_REFERENCE_"+ob.name
    sc.collection.objects.link(source); source.hide_render=True
    references[ob.name]=source
    ob.data.calc_loop_triangles(); before=len(ob.data.loop_triangles)
    bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True); bpy.context.view_layer.objects.active=ob
    modifier=ob.modifiers.new("Game_size_reduction","DECIMATE")
    modifier.ratio=ratios.get(ob.name,.60); modifier.use_collapse_triangulate=True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    ob.data.calc_loop_triangles()
    report["parts"][ob.name]={"before":before,"after":len(ob.data.loop_triangles)}

# Keep the original overall size after decimation and settle each small foot.
lod_lo,lod_hi=bounds(meshes)
factor=Vector(tuple((base_hi[a]-base_lo[a])/(lod_hi[a]-lod_lo[a]) for a in range(3)))
for ob in meshes:
    inv=ob.matrix_world.inverted()
    for v in ob.data.vertices:
        p=ob.matrix_world@v.co
        v.co=inv@Vector(tuple(base_lo[a]+(p[a]-lod_lo[a])*factor[a] for a in range(3)))
    if ob.name.startswith("leg_"):
        low=min((ob.matrix_world@v.co).z for v in ob.data.vertices)
        delta=ob.matrix_world.inverted().to_3x3()@Vector((0,0,low))
        for v in ob.data.vertices: v.co-=delta
    ob.data.update()
    bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True); bpy.context.view_layer.objects.active=ob
    transfer=ob.modifiers.new("Original_curved_normals","DATA_TRANSFER")
    transfer.object=references[ob.name]; transfer.use_loop_data=True
    transfer.data_types_loops={"CUSTOM_NORMAL"}; transfer.loop_mapping="POLYINTERP_NEAREST"
    bpy.ops.object.modifier_apply(modifier=transfer.name)
for source in references.values():
    data=source.data; bpy.data.objects.remove(source,do_unlink=True); bpy.data.meshes.remove(data)
sc["lod_source"]="tutorial_alien_b.blend"
sc["lod_source_revision"]=sc.get("revision","unknown")
report["source_revision"]=sc["lod_source_revision"]
sc["lod_note"]="Optional reduced mesh; visual comparison required before game use"
bpy.ops.wm.save_as_mainfile(filepath=LOD_BLEND,compress=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT,"assets","models","tutorial_alien_b_lod.glb"),
    export_format="GLB",export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
report["triangles"]=sum(p["after"] for p in report["parts"].values())
report["bounds_scale_correction"]=list(factor)

# The actual reduced mesh gets the same saved toon shader and lights for review.
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT,"tutorial_alien_b_toon_studio.blend"))
sc=bpy.context.scene; material=bpy.data.materials.get("B_cartoon_atlas")
with bpy.data.libraries.load(LOD_BLEND,link=False) as (src,dst):
    dst.meshes=[name for name in src.meshes if name in report["parts"]]
for data in dst.meshes:
    ob=bpy.data.objects.get(data.name.split(".")[0])
    if ob is None: raise RuntimeError("Missing LOD part "+data.name)
    ob.data=data; data.materials.clear(); data.materials.append(material)
    for polygon in data.polygons: polygon.material_index=0
sc.render.filepath=os.path.join(OUT,"toon_beauty_lod.png")
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,"tutorial_alien_b_lod_toon_studio.blend"),compress=True)
with open(os.path.join(OUT,"lod_build.json"),"w",encoding="utf-8") as f: json.dump(report,f,indent=2)
print("ALIEN_B_LOD_OK",report["triangles"])

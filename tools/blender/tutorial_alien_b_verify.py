"""Validate saved/exported assets, not an in-memory model recipe."""
import os
import json
import sys
import bpy
from mathutils import Vector

ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT=os.path.join(ROOT,"output","models","tutorial_alien_b")
report={"checks":{}}
suffix="_lod" if "--lod" in sys.argv else ""

def check(key,ok):
    report["checks"][key]=bool(ok)
    print(("PASS " if ok else "FAIL ")+key)
    if not ok: raise AssertionError(key)

bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT,"tutorial_alien_b"+suffix+"_toon_studio.blend"))
sc=bpy.context.scene
m=bpy.data.materials.get("B_cartoon_atlas")
check("saved_eevee_studio",sc.render.engine=="BLENDER_EEVEE")
check("toon_shader_saved",any(n.bl_idname=="ShaderNodeShaderToRGB" for n in m.node_tree.nodes))
check("three_tone_ramp",len(m.node_tree.nodes["Three_tone_cel_ramp"].color_ramp.elements)==3)
normalizer=m.node_tree.nodes.get("Diffuse_range_0_to_3")
check("diffuse_range_normalized",normalizer is not None and normalizer.operation=="MULTIPLY" and abs(normalizer.inputs[1].default_value-1/3)<1e-6)
positions=sorted(e.position for e in m.node_tree.nodes["Three_tone_cel_ramp"].color_ramp.elements)
check("toon_ramp_thresholds_saved",all(abs(a-b)<1e-6 for a,b in zip(positions,(.16/3,.95/3,2.65/3))))
cool=m.node_tree.nodes.get("Teal_three_tone_ramp")
check("separate_teal_tones_saved",cool is not None and len(cool.color_ramp.elements)==3 and m.node_tree.nodes.get("Warm_shell_cool_skin") is not None)
ivory=m.node_tree.nodes.get("Ivory_three_tone_ramp")
check("light_cream_teeth_tones_saved",ivory is not None and len(ivory.color_ramp.elements)==3 and m.node_tree.nodes.get("Ivory_mask") is not None and m.node_tree.nodes.get("Keep_teeth_light_cream") is not None)
check("three_studio_lights",sum(o.type=="LIGHT" for o in sc.objects)==3)
check("outline_compositor_saved",sc.compositing_node_group is not None)
im=bpy.data.images.get("B_painted_atlas_512x256")
check("packed_512x256_texture",im is not None and tuple(im.size)==(512,256) and im.packed_file is not None)
check("turnaround_saved_first",os.path.getmtime(os.path.join(ROOT,"output","concepts","tutorial_alien_b_turnaround.png"))<os.path.getmtime(os.path.join(OUT,"tutorial_alien_b.blend")))
render_paths=("toon_beauty_lod.png",) if suffix else ("preview.png","model_three_views.png","toon_beauty.png")
check("render_deliverables",all(os.path.getsize(os.path.join(OUT,p))>1000 for p in render_paths))

# Re-import the final GLB into a clean scene and count what was actually exported.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT,"assets","models","tutorial_alien_b"+suffix+".glb"))
obs=[o for o in bpy.context.scene.objects if o.type=="MESH"]
names={o.name for o in obs}
check("six_distinct_legs",all("leg_%d_%s"%(i,k) in names for i in range(3) for k in ("l","r")))
check("separate_jaws",all(n in names for n in ("brow","jaw","body","shell")))
tri=0; degenerate=0; mats=set(); points=[]
for o in obs:
    o.data.calc_loop_triangles(); tri+=len(o.data.loop_triangles)
    degenerate+=sum(t.area<1e-10 for t in o.data.loop_triangles)
    points.extend(o.matrix_world@v.co for v in o.data.vertices)
    mats.update(m.name for m in o.data.materials)
    check("uv_"+o.name,len(o.data.uv_layers)==1)
report["triangles"]=tri; report["material_count"]=len(mats)
lo=Vector(tuple(min(p[i] for p in points) for i in range(3)))
hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
report["reimported_blender_dimensions_xyz_m"]=list(hi-lo)
report["glb_size_bytes"]=os.path.getsize(os.path.join(ROOT,"assets","models","tutorial_alien_b"+suffix+".glb"))
check("under_4000_triangle_budget",0<tri<=4000)
if suffix: check("under_2000_triangles_lod",0<tri<2000)
check("one_shared_material",len(mats)==1)
check("no_degenerate_triangles",degenerate==0)
check("35_6_cm_high",abs((hi-lo).z-.356)<.0001)
check("feet_on_floor",abs(lo.z)<1e-6)
check("foot_markers",sum(o.name.startswith("pt_foot_") for o in bpy.context.scene.objects)==6)
report["fidelity_status"]="in_progress; structural checks do not establish reference likeness"
with open(os.path.join(OUT,"validation"+suffix+".json"),"w",encoding="utf-8") as f:
    json.dump(report,f,ensure_ascii=False,indent=2)
print("ALIEN_B_VALIDATION_OK",tri)

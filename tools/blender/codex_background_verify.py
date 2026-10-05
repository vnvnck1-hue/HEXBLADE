"""Re-import all four actual GLBs, validate solids/UV/density; render F/R/top.
Only Codex-owned outputs. Run with pinned tools/blender.ps1 wait.
"""
from pathlib import Path
import sys, json, math, ast, types
import bpy, bmesh
import numpy as np
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/blender'))
import hb
# Stock build.py executes main at import. Reuse its functions without that entrypoint.
pipeline=types.ModuleType('codex_preview_helpers')
pipeline.__file__=str(ROOT/'tools/blender/build.py')
tree=ast.parse((ROOT/'tools/blender/build.py').read_text(encoding='utf8'))
tree.body=[n for n in tree.body if not isinstance(n,(ast.Try,ast.If))]
exec(compile(tree,pipeline.__file__,'exec'),pipeline.__dict__)
OUT=ROOT/'output/codex-background-first-pass'
PARTS={'floor_f01':(2,2,.2),'wall_w01':(2,.25,3),'workbench_a01':(2,.75,1),'locker_a02':(1,.5,2)}
PATCHES=[(32,32,1024,1024),(32,1120,1024,512),(1120,32,896,896),(1120,1000,896,1016)]
report={};failures=[]
render='--render' in sys.argv
for suffix,expected in PARTS.items():
    name='bg_codex_'+suffix
    hb.reset()
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/models'/f'{name}.glb'))
    obs=[o for o in bpy.context.scene.objects if o.type=='MESH']
    pts=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
    lo=Vector(tuple(min(v[i] for v in pts) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in pts) for i in range(3)))
    issues=[];triangles=0;density=[];surface_bad=0;edge_bad=0;negative=0
    for o in obs:
        me=o.data;me.calc_loop_triangles();triangles+=len(me.loop_triangles)
        bm=bmesh.new();bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
        edge_bad+=sum(not e.is_manifold for e in bm.edges)
        # Components may intersect by design, but each shell must be closed/outward.
        if bm.calc_volume(signed=True)<=0:negative+=1
        bm.free()
        uv=me.uv_layers.active
        if uv is None:issues.append('missing_uv');continue
        texture_nodes=[n for m in me.materials for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image]
        if not texture_nodes:issues.append('missing_texture')
        for tri in me.loop_triangles:
            vs=[me.vertices[i].co for i in tri.vertices]
            uvv=[uv.data[i].uv for i in tri.loops]
            area=(vs[1]-vs[0]).cross(vs[2]-vs[0]).length/2
            if area<1e-12:issues.append('degenerate');continue
            u1,u2=uvv[1]-uvv[0],uvv[2]-uvv[0]
            ua=abs(u1.x*u2.y-u1.y*u2.x)/2
            density.append(math.sqrt(ua/area)*2048)
            if suffix in ('workbench_a01','locker_a02'):
                # glTF importer restores Blender V; metric patch bounds are original.
                good=any(all(x/2048-1e-5<=q.x<=(x+w)/2048+1e-5 and y/2048-1e-5<=q.y<=(y+h)/2048+1e-5 for q in uvv) for x,y,w,h in PATCHES)
                if not good:surface_bad+=1
    if edge_bad:issues.append(f'open/nonmanifold_edges:{edge_bad}')
    if negative:issues.append(f'negative_volume_meshes:{negative}')
    if surface_bad:issues.append(f'atlas_outside_patch_triangles:{surface_bad}')
    if (hi-lo-Vector(expected)).length>2e-4:issues.append('dimensions')
    if density and (max(density)>513 or min(density)<299):issues.append('UV_density')
    # Also open the deliverable .blend, not just the GLB, and confirm packed images.
    item={'size_blender_m':list(hi-lo),'bounds':[list(lo),list(hi)],'triangles':triangles,'meshes':len(obs),'uv_density_minmax': [min(density),max(density)],'issues':issues}
    if render:
        pipeline.setup_preview('eevee',512)
        bpy.context.scene.view_settings.view_transform='Standard'
        bpy.context.scene.view_settings.look='Medium High Contrast' if 'Medium High Contrast' in [] else 'None'
        sun=bpy.data.objects.get('_sun')
        sun.rotation_euler=(math.radians(-38),0,math.radians(-25))
        sun.data.energy=2.2
        # Include the top view absent from the stock 2x2 pipeline.
        pipeline.VIEWS=[('front',(0,1,0),True),('right',(1,0,0),True),('top',(0,0,1),True),('front34',(.8,1,.8),False)]
        st={'min':list(lo),'max':list(hi)}
        pipeline.render_views(name,st,512)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/'output/models'/name/f'{name}.blend'))
    packed=[im for im in bpy.data.images if im.source=='FILE' and im.packed_file]
    item['editable_blend_packed_images']=len(packed)
    if not packed:issues.append('unpacked_blend')
    report[name]=item
    if issues:failures.append(name)
(OUT/'model_validation.json').write_text(json.dumps({'ok':not failures,'models':report},indent=2)+'\n',encoding='utf8')
print('CODEX_BACKGROUND_MODEL_'+('OK' if not failures else 'FAILED'),json.dumps(report))
if failures:raise RuntimeError(str(failures))

"""Verify exterior fidelity against source and show a rigid-joint pose trial."""
import bpy,sys,math,json
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
import numpy as np
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/models/mech_volume_preserved'
sys.path.insert(0,str(ROOT/'tools/blender'));import hb
bpy.ops.wm.open_mainfile(filepath=str(OUT/'mech_volume_preserved.blend'))
bpy.context.preferences.filepaths.file_preview_type='NONE'
nodes={o.name:o for o in bpy.context.scene.objects};parts=[o for o in nodes.values() if o.type=='MESH']
rest={n:o.matrix_basis.copy() for n,o in nodes.items()};world_rest={n:o.matrix_world.copy() for n,o in nodes.items()}
sc=bpy.context.scene;sc.render.engine='BLENDER_EEVEE';sc.eevee.taa_render_samples=32
sc.render.resolution_x=sc.render.resolution_y=720;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG'
sc.world=bpy.data.worlds.new('ReviewWorld');sc.world.use_nodes=True
sc.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.065,.082,.11,1);sc.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.8
sc.view_settings.view_transform='Standard'
for name,loc,power,size in [('Key',(3,4,5),800,4),('Fill',(-4,2,3),600,4),('Rim',(0,-4,4),900,3)]:
    o=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'));sc.collection.objects.link(o)
    o.location=loc;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,1))-o.location).to_track_quat('-Z','Y').to_euler()
cam=bpy.data.objects.new('ReviewCamera',bpy.data.cameras.new('ReviewCamera'));sc.collection.objects.link(cam);sc.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=3.0
def camera(d=(.85,1.5,.8)):
    c=Vector((0,0,.87));cam.location=c+Vector(d).normalized()*7;cam.rotation_euler=(c-cam.location).to_track_quat('-Z','Y').to_euler()
def render(name,d=(.85,1.5,.8)):
    camera(d);sc.render.filepath=str(OUT/('view_'+name+'.png'));bpy.ops.render.render(write_still=True)
def sheet(names,name,cols=2):
    tiles=[]
    for n in names:
        im=bpy.data.images.load(str(OUT/('view_'+n+'.png')),check_existing=False);w,h=im.size
        tiles.append(np.array(im.pixels[:],dtype=np.float32).reshape(h,w,4));bpy.data.images.remove(im)
    rows=(len(tiles)+cols-1)//cols;arr=np.zeros((rows*h,cols*w,4),np.float32);arr[:,:,3]=1
    for i,t in enumerate(tiles):r=rows-1-i//cols;c=i%cols;arr[r*h:(r+1)*h,c*w:(c+1)*w]=t
    im=bpy.data.images.new(name,width=cols*w,height=rows*h);im.pixels.foreach_set(arr.ravel());im.filepath_raw=str(OUT/(name+'.png'));im.file_format='PNG';im.save();bpy.data.images.remove(im)
def reset():
    for n,o in nodes.items():o.rotation_mode='XYZ';o.matrix_basis=rest[n].copy()
    bpy.context.view_layer.update()
def rotate(n,v):nodes[n].rotation_euler=[math.radians(x) for x in v]
def crouch(drop):
    shift=Vector((0,0,-drop));nodes['pelvis'].location=rest['pelvis'].translation+shift
    for side in ['hand','gun']:
        hip,knee,ankle=[nodes[p+'_'+side] for p in ['hip','knee','ankle']]
        a,b,c=[world_rest[o.name].translation for o in [hip,knee,ankle]]
        ha=a+shift;hc=c;direction=(hc-ha).normalized();dist=(hc-ha).length;l1=(b-a).length;l2=(c-b).length
        x=(l1*l1-l2*l2+dist*dist)/(2*dist);h=math.sqrt(max(0,l1*l1-x*x))
        pole=b-a;pole=(pole-direction*direction.dot(pole)).normalized();kb=ha+direction*x+pole*h
        hip.rotation_mode='QUATERNION';hip.rotation_quaternion=(b-a).rotation_difference(kb-ha)
        knee.rotation_mode='QUATERNION';knee.rotation_quaternion=hip.rotation_quaternion.inverted()@(c-b).rotation_difference(hc-kb)
        ankle.rotation_mode='QUATERNION';ankle.rotation_quaternion=(hip.rotation_quaternion@knee.rotation_quaternion).inverted()
    bpy.context.view_layer.update()
ANGLES={
    'neutral':{},
    'aim':{'arm_gun_upper':(30,0,-8),'arm_gun_fore':(50,0,0),'gun_mount':(-10,0,0),'head':(0,0,-8),'arm_hand_upper':(12,0,5)},
    'arm_lift':{'shoulder_hand':(0,-8,12),'arm_hand_upper':(65,0,0),'arm_hand_fore':(-25,0,0),'hand':(0,0,-12),'body':(0,0,8)},
    'crouch':{'arm_hand_upper':(20,0,-10),'arm_hand_fore':(-20,0,0),'arm_gun_upper':(10,0,5)},
}
KEYS=[(1,'neutral'),(40,'aim'),(80,'arm_lift'),(120,'crouch'),(160,'neutral')]
def blend(a,b,t):
    reset()
    for n in set(ANGLES[a])|set(ANGLES[b]):rotate(n,Vector(ANGLES[a].get(n,(0,0,0))).lerp(Vector(ANGLES[b].get(n,(0,0,0))),t))
    amount=(1-t if a=='crouch' else 0)+(t if b=='crouch' else 0);crouch(.11*amount);bpy.context.view_layer.update()
def at(frame):
    for (fa,a),(fb,b) in zip(KEYS,KEYS[1:]):
        if fa<=frame<=fb:t=(frame-fa)/(fb-fa);blend(a,b,t*t*(3-2*t));return

# Compare actual retained surfaces with the original file in world coordinates.
bpy.ops.import_scene.gltf(filepath=str(ROOT/'models/source/mech_user/original.glb'))
sources=[o for o in bpy.context.scene.objects if o not in nodes.values() and o.type=='MESH']
removed={1,2,14,8,15};source_map={}
for o in sources:
    index=int(o.name.rsplit('_',1)[1]);o.hide_render=True
    if index in removed:continue
    source_map[index]=o
    o.matrix_world=Matrix.Diagonal((-2.35,-2.35,2.35,1))@o.matrix_world
bpy.context.view_layer.update()
def surface(objects,original=False):
    vv=[];ff=[];samples=[]
    for o in objects:
        m=o.data;m.calc_loop_triangles();off=len(vv);pts=[o.matrix_world@v.co for v in m.vertices];vv.extend(pts)
        for t in m.loop_triangles:
            if not original and m.polygons[t.polygon_index].material_index==1:continue
            ff.append(tuple(off+i for i in t.vertices));samples.extend([pts[i] for i in t.vertices]);samples.append(sum((pts[i] for i in t.vertices),Vector())/3)
    return BVHTree.FromPolygons(vv,ff),samples
fidelity=[]
for index,src in source_map.items():
    actual=[o for o in parts if o['source_part']==index]
    a,aa=surface([src],True);b,bb=surface(actual)
    forward=max(b.find_nearest(p)[3] for p in aa);back=max(a.find_nearest(p)[3] for p in bb)
    # BVH nearest-triangle distance loses precision on tiny/sliver triangles.
    # Independently require every original vertex to remain at its exact position.
    actual_vertices=[o.matrix_world@v.co for o in actual for v in o.data.vertices]
    kd=KDTree(len(actual_vertices))
    for j,p in enumerate(actual_vertices):kd.insert(p,j)
    kd.balance()
    vertex_error=max(kd.find(src.matrix_world@v.co)[2] for v in src.data.vertices)
    assert vertex_error<2e-6,(index,vertex_error)
    assert max(forward,back)<.001,(index,forward,back)
    # Triangle provenance checks plane membership and area for every source face,
    # not only representative samples. No absolute volume claim on open meshes.
    sm=src.data;sm.calc_loop_triangles();area_total={};plane_max=0;uv_max=0
    source_tris=[]
    for tri in sm.loop_triangles:
        pp=[src.matrix_world@sm.vertices[v].co for v in tri.vertices]
        tt=[Vector(sm.uv_layers.active.data[l].uv) for l in tri.loops]
        source_tris.append((pp,tt))
    for o in actual:
        for face in o.data.polygons:
            tid=o.data.attributes['source_triangle'].data[face.index].value
            if tid<0:continue
            pp,tt=source_tris[tid];a0,b0,c0=pp;e0=b0-a0;e1=c0-a0;normal=e0.cross(e1)
            dd=normal.length_squared
            p=[o.matrix_world@o.data.vertices[v].co for v in face.vertices]
            area_total[tid]=area_total.get(tid,0)+(p[1]-p[0]).cross(p[2]-p[0]).length*.5
            for v,l in zip(p,face.loop_indices):
                plane_max=max(plane_max,abs((v-a0).dot(normal))/max(normal.length,1e-15))
                if dd>1e-14:
                    b=(v-a0).cross(e1).dot(normal)/dd;c=e0.cross(v-a0).dot(normal)/dd
                    uv=tt[0]*(1-b-c)+tt[1]*b+tt[2]*c
                    uv_max=max(uv_max,(uv-o.data.uv_layers.active.data[l].uv).length)
    area_abs=max(abs(area_total.get(i,0)-(p[1]-p[0]).cross(p[2]-p[0]).length*.5) for i,(p,_) in enumerate(source_tris))
    assert plane_max<2e-6 and area_abs<2e-6,(index,plane_max,area_abs)
    assert uv_max<.003,(index,uv_max)
    fidelity.append({'part':index,'original_vertex_max_error_m':vertex_error,'source_triangle_plane_max_error_m':plane_max,'source_triangle_area_max_error_m2':area_abs,'uv_max_error':uv_max,'source_to_result_bvh_max_distance_m':forward,'result_to_source_bvh_max_distance_m':back,'samples':len(aa)+len(bb)})
render('result')
for o in parts:o.hide_render=True
for o in source_map.values():o.hide_render=False
render('source')
for o in parts:o.hide_render=False
for o in sources:o.hide_render=True
sheet(['source','result'],'preservation_compare')
for o in sources:bpy.data.objects.remove(o,do_unlink=True)
for o in list(sc.objects):
    if o.name.startswith('RootNode'):bpy.data.objects.remove(o,do_unlink=True)

metrics={'fidelity':fidelity,'poses':{}}
for name in ANGLES:
    blend(name,name,0);render(name)
    metrics['poses'][name]={'feet_z':{s:nodes['pt_foot_'+s].matrix_world.translation.z for s in ['hand','gun']},'grip':list(nodes['pt_grip'].matrix_world.translation),'muzzle':list(nodes['pt_muzzle'].matrix_world.translation)}
reset();render('back',(-.8,-1.4,.8));render('high',(.55,.8,1.5))
sheet(['neutral','aim','arm_lift','crouch'],'pose_review')
sheet(['neutral','back','high','crouch'],'preview')
# A separated view makes the original bulky individual shells easy to inspect.
for o in parts:
    center=sum((o.matrix_world@Vector(v) for v in o.bound_box),Vector())/8
    o.location+=(center-Vector((0,0,.8)))*.22
cam.data.ortho_scale=3.5;render('exploded');reset();cam.data.ortho_scale=3.0

max_foot_error=0
for frame in range(1,161):
    sc.frame_set(frame);at(frame)
    for o in nodes.values():
        if o.type!='EMPTY':continue
        o.rotation_mode='QUATERNION';o.keyframe_insert('rotation_quaternion',frame=frame);o.keyframe_insert('location',frame=frame)
    max_foot_error=max(max_foot_error,max(abs(nodes['pt_foot_'+s].matrix_world.translation.z) for s in ['hand','gun']))
assert max_foot_error<1e-5,max_foot_error
sc.frame_start=1;sc.frame_end=160;sc.render.fps=30;sc.frame_set(1);camera()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'pose_trial.blend'),compress=True)
bpy.ops.wm.open_mainfile(filepath=str(OUT/'pose_trial.blend'))
for frame,name in KEYS:
    bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
    for marker,key in [('pt_grip','grip'),('pt_muzzle','muzzle')]:
        assert (bpy.data.objects[marker].matrix_world.translation-Vector(metrics['poses'][name][key])).length<1e-5
metrics['motion']={'frames':160,'foot_marker_max_error_m':max_foot_error,'saved_reopened':True,'overlap_policy':'Allowed. Not optimized or asserted away.'}
(OUT/'review_metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
if '--video' in sys.argv:
    sc=bpy.context.scene;sc.render.resolution_x=sc.render.resolution_y=480;sc.eevee.taa_render_samples=16
    sc.render.image_settings.media_type='VIDEO';sc.render.image_settings.file_format='FFMPEG';sc.render.ffmpeg.format='MPEG4';sc.render.ffmpeg.codec='H264'
    sc.render.filepath=str(OUT/'pose_trial.mp4');bpy.ops.render.render(animation=True)
print('MECH_REVIEW_OK',flush=True)

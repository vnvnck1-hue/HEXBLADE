"""Render and save an editable pose trial for tripo_mecha_proto, using pinned Blender."""
import bpy, math, sys, json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/models/tripo_mecha_proto'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'tripo_mecha_proto.blend'))
bpy.context.preferences.filepaths.file_preview_type='NONE'
sys.path.insert(0,str(ROOT/'tools/blender'))
import hb
nodes={o.name:o for o in bpy.context.scene.objects}
rest={o.name:o.matrix_basis.copy() for o in nodes.values()}
rest_world={o.name:o.matrix_world.copy() for o in nodes.values()}
sc=bpy.context.scene
sc.render.engine='BLENDER_EEVEE'; sc.eevee.taa_render_samples=32
sc.render.resolution_x=sc.render.resolution_y=800; sc.render.resolution_percentage=100
sc.render.image_settings.file_format='PNG'; sc.render.film_transparent=False
sc.world=bpy.data.worlds.new('ReviewWorld'); sc.world.use_nodes=True
sc.world.node_tree.nodes['Background'].inputs['Color'].default_value=(0.065,0.082,0.11,1)
sc.world.node_tree.nodes['Background'].inputs['Strength'].default_value=0.65
sc.view_settings.view_transform='Standard'
for name,loc,power,size in [('Key',(3,4,5),650,4),('Fill',(-4,2,3),440,4),('Rim',(0,-4,4),900,3)]:
    o=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA')); sc.collection.objects.link(o)
    o.location=loc; o.data.energy=power; o.data.shape='DISK'; o.data.size=size
    o.rotation_euler=(Vector((0,0,0.9))-o.location).to_track_quat('-Z','Y').to_euler()
ground=hb.box('ReviewGround',(200,200,0.02),loc=(0,0,-0.025),mat=hb.mat('ReviewFloor','#303a48',rough=1))
cam=bpy.data.objects.new('ReviewCamera',bpy.data.cameras.new('ReviewCamera')); sc.collection.objects.link(cam); sc.camera=cam
cam.data.type='ORTHO'; cam.data.ortho_scale=3.3
def camera(direction=(0.85,1.5,0.8),target=(0,0,0.8)):
    target=Vector(target); cam.location=target+Vector(direction).normalized()*7
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
camera()

grip=nodes['pt_grip']
gun=hb.box('TrialGun',(0.085,0.32,0.095),loc=(0,0.16,0),mat=hb.mat('TrialSteel','#384954',metal=0.5),parent=grip,bevel=0.01)
sword=hb.box('TrialBlade',(0.038,0.90,0.018),loc=(0,0.45,0),mat=hb.mat('TrialCyan','#70dae3',emit='#70dae3',emit_power=1.1),parent=grip,bevel=0.008)

def reset():
    for name,o in nodes.items():
        o.rotation_mode='XYZ'; o.matrix_basis=rest[name].copy()
    gun.hide_render=gun.hide_viewport=True
    sword.hide_render=sword.hide_viewport=True
    bpy.context.view_layer.update()

def rotate(name,xyz):
    nodes[name].rotation_euler=tuple(math.radians(v) for v in xyz)

def crouch(drop=0.11):
    shift=Vector((0,0,-drop))
    nodes['body'].location=rest['body'].translation+shift
    for side in ['gun','hand']:
        hip,knee,ankle=[nodes[p+'_'+side] for p in ['hip','knee','ankle']]
        a,b,c=[rest_world[o.name].translation for o in [hip,knee,ankle]]
        ha=a+shift; hc=c; direction=(hc-ha).normalized(); dist=(hc-ha).length
        l1=(b-a).length; l2=(c-b).length
        x=(l1*l1-l2*l2+dist*dist)/(2*dist)
        h=math.sqrt(max(0,l1*l1-x*x)); pole=b-a
        pole=(pole-direction*direction.dot(pole)).normalized()
        kb=ha+direction*x+pole*h
        hip.location=rest[hip.name].translation+shift; hip.rotation_mode='QUATERNION'
        hip.rotation_quaternion=(b-a).rotation_difference(kb-ha)
        knee.rotation_mode='QUATERNION'
        knee.rotation_quaternion=hip.rotation_quaternion.inverted()@(c-b).rotation_difference(hc-kb)
        ankle.rotation_mode='QUATERNION'
        ankle.rotation_quaternion=(hip.rotation_quaternion@knee.rotation_quaternion).inverted()
    bpy.context.view_layer.update()

ANGLES={
    'neutral':{},
    'shoot':{'shoulder_hand':(0,0,10),'arm_hand_upper':(27,0,0),'arm_hand_fore':(-20,0,0)},
    'slash':{'shoulder_hand':(0,-12,25),'arm_hand_upper':(85,0,0),'arm_hand_fore':(-40,0,-18),'hand':(0,0,-15)},
    'crouch':{'arm_hand_upper':(25,0,-12),'arm_hand_fore':(-25,0,0)},
}
KEYS=[(1,'neutral'),(40,'shoot'),(80,'slash'),(120,'crouch'),(160,'neutral')]
def blended_pose(a,b,t):
    reset()
    for joint in ['shoulder_hand','arm_hand_upper','arm_hand_fore','hand']:
        av=Vector(ANGLES[a].get(joint,(0,0,0)));bv=Vector(ANGLES[b].get(joint,(0,0,0)))
        rotate(joint,av.lerp(bv,t))
    amount=(1-t if a=='crouch' else 0)+(t if b=='crouch' else 0)
    crouch(0.11*amount)
    visible=a if t<0.5 else b
    gun.hide_render=gun.hide_viewport=(visible!='shoot')
    sword.hide_render=sword.hide_viewport=(visible!='slash')
    bpy.context.view_layer.update()

def pose(name):
    blended_pose(name,name,0)

def pose_at(frame):
    for (fa,a),(fb,b) in zip(KEYS,KEYS[1:]):
        if fa<=frame<=fb:
            t=(frame-fa)/(fb-fa); blended_pose(a,b,t*t*(3-2*t)); return

BODY_PARTS=['torso_fixed_gun','pelvis_shell','pelvis_guard']
MOVING_PARTS=['hand_shell','forearm_shell','upper_arm_shell','shoulder_armor',
              'thigh_hand','thigh_gun','shin_hand','shin_gun','knee_guard_hand','knee_guard_gun']
def tree(names):
    verts=[];faces=[]; dg=bpy.context.evaluated_depsgraph_get()
    for name in names:
        obj=nodes[name].evaluated_get(dg); mesh=obj.to_mesh(); offset=len(verts)
        verts.extend(obj.matrix_world@v.co for v in mesh.vertices)
        faces.extend([offset+i for i in p.vertices] for p in mesh.polygons)
        obj.to_mesh_clear()
    return BVHTree.FromPolygons(verts,faces)

def crossings():
    body=tree(BODY_PARTS)
    return {part:len(body.overlap(tree([part]))) for part in MOVING_PARTS}

metrics={}
for name in ['neutral','shoot','slash','crouch']:
    pose(name); camera()
    sc.render.filepath=str(OUT/('view_'+name+'.png')); bpy.ops.render.render(write_still=True)
    foot_heights={side:round(nodes['pt_foot_'+side].matrix_world.translation.z,6) for side in ['gun','hand']}
    feet_min={side:min((nodes['foot_'+side].matrix_world@v.co).z for v in nodes['foot_'+side].data.vertices) for side in ['gun','hand']}
    metrics[name]={'foot_markers_z':foot_heights,'foot_mesh_min_z':feet_min,'torso_surface_crossings':crossings(),'grip':list(grip.matrix_world.translation)}
    if name=='crouch': assert all(abs(h)<0.001 for h in foot_heights.values()),foot_heights

pose('neutral'); camera((-0.8,-1.4,0.8))
sc.render.filepath=str(OUT/'view_back.png'); bpy.ops.render.render(write_still=True)
pose('neutral'); camera((0.55,0.8,1.5))
sc.render.filepath=str(OUT/'view_high.png'); bpy.ops.render.render(write_still=True)

def sheet(names,path):
    tiles=[]
    for name in names:
        im=bpy.data.images.load(str(OUT/('view_'+name+'.png')))
        a=np.empty(800*800*4,dtype=np.float32); im.pixels.foreach_get(a)
        tiles.append(a.reshape(800,800,4)); bpy.data.images.remove(im)
    arr=np.concatenate([np.concatenate(tiles[2:],axis=1),np.concatenate(tiles[:2],axis=1)],axis=0)
    arr[799:801,:,:3]=0.03; arr[:,799:801,:3]=0.03
    im=bpy.data.images.new('ReviewSheet',1600,1600,alpha=True); im.pixels.foreach_set(arr.ravel())
    im.filepath_raw=str(OUT/path); im.file_format='PNG'; im.save()
sheet(['neutral','shoot','slash','crouch'],'pose_review.png')
sheet(['neutral','back','high','crouch'],'preview.png')

# Bake the IK every frame so feet also stay planted between the key poses.
for frame in range(1,161):
    sc.frame_set(frame); pose_at(frame)
    for o in nodes.values():
        if o.type!='EMPTY': continue
        o.rotation_mode='QUATERNION'
        o.keyframe_insert(data_path='location',frame=frame)
        o.keyframe_insert(data_path='rotation_quaternion',frame=frame)
    for prop in [gun,sword]:
        prop.keyframe_insert(data_path='hide_render',frame=frame)
        prop.keyframe_insert(data_path='hide_viewport',frame=frame)
for frame,name in KEYS:
    sc.timeline_markers.new(name,frame=frame)
sc.frame_start=1; sc.frame_end=160; sc.render.fps=30; sc.frame_set(1); camera()
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.overlay.show_overlays=False
            area.spaces.active.shading.type='MATERIAL'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'pose_trial.blend'),compress=True)
# Re-open the actual delivery file and verify its saved key poses, not just RAM.
bpy.ops.wm.open_mainfile(filepath=str(OUT/'pose_trial.blend'))
for frame,name in [(1,'neutral'),(40,'shoot'),(80,'slash'),(120,'crouch')]:
    bpy.context.scene.frame_set(frame); bpy.context.view_layer.update()
    actual=bpy.data.objects['pt_grip'].matrix_world.translation
    assert (actual-Vector(metrics[name]['grip'])).length<1e-4,(frame,actual,metrics[name]['grip'])
metrics['saved_keyframes_verified']=True
nodes={name:bpy.data.objects[name] for name in nodes}
sweep={'frames':160,'max_foot_marker_error':0.0,'body_crossings':{},'shell_crossings':{}}
pair_names=['shoulder_armor','upper_arm_shell','forearm_shell','hand_shell',
            'thigh_hand','shin_hand','knee_guard_hand','foot_hand',
            'thigh_gun','shin_gun','knee_guard_gun','foot_gun']
for frame in range(1,161):
    bpy.context.scene.frame_set(frame); bpy.context.view_layer.update()
    err=max(abs(nodes['pt_foot_'+side].matrix_world.translation.z) for side in ['gun','hand'])
    sweep['max_foot_marker_error']=max(sweep['max_foot_marker_error'],err)
    body_hits={k:v for k,v in crossings().items() if v}
    if body_hits:sweep['body_crossings'][frame]=body_hits
    trees={n:tree([n]) for n in pair_names}
    hits={}
    for i,a in enumerate(pair_names):
        for b in pair_names[i+1:]:
            if nodes[a].parent==nodes[b].parent:continue
            n=len(trees[a].overlap(trees[b]))
            if n:hits[a+'/'+b]=n
    if hits:sweep['shell_crossings'][frame]=hits
metrics['motion_sweep']=sweep
metrics['validation_scope']={'body':BODY_PARTS,'moving_vs_body':MOVING_PARTS,'moving_shell_pairs':pair_names,
    'excluded':'Internal bearing/frame overlaps and meshes on the same rigid joint are intentional and excluded.',
    'source_crouch_depth_m':0.11,'method':'Evaluated bevel meshes; BVH surface intersections at each saved integer frame, not continuous collision detection.'}
(OUT/'pose_metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
assert not sweep['body_crossings'],sweep['body_crossings']
assert not sweep['shell_crossings'],sweep['shell_crossings']
assert sweep['max_foot_marker_error']<1e-5,sweep['max_foot_marker_error']
print('POSE_REVIEW_OK',json.dumps({'body_crossing_frames':len(sweep['body_crossings']),'shell_crossing_frames':len(sweep['shell_crossings']),'max_foot_marker_error':sweep['max_foot_marker_error']}),flush=True)
if '--video' in sys.argv:
    sc=bpy.context.scene;sc.render.resolution_x=sc.render.resolution_y=480
    sc.eevee.taa_render_samples=16
    sc.render.image_settings.media_type='VIDEO';sc.render.image_settings.file_format='FFMPEG'
    sc.render.ffmpeg.format='MPEG4';sc.render.ffmpeg.codec='H264';sc.render.ffmpeg.constant_rate_factor='MEDIUM'
    sc.render.filepath=str(OUT/'pose_trial.mp4');bpy.ops.render.render(animation=True)
    print('POSE_VIDEO_OK',flush=True)

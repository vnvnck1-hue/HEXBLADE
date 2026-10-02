"""Independent exported-GLB preservation and silhouette audit."""
import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.kdtree import KDTree
import numpy as np
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'output/models/mech_volume_preserved'
SOURCE=ROOT/'models/source/mech_user/original.glb';ASSET=ROOT/'assets/models/mech_volume_preserved.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ASSET))
actual=[o for o in bpy.context.scene.objects if o.type=='MESH']
assert all('source_part' in o for o in actual)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
source=[o for o in bpy.context.scene.objects if o.type=='MESH' and o not in actual]
retained=[];by_part={};removed={1,2,14,8,15}
for o in source:
    index=int(o.name.rsplit('_',1)[1]);o.hide_render=index in removed
    if index in removed:continue
    retained.append(o);by_part[index]=o
    o.matrix_world=Matrix.Diagonal((-2.35,-2.35,2.35,1))@o.matrix_world
bpy.context.view_layer.update()
results=[]
for index,src in by_part.items():
    vv=[o.matrix_world@v.co for o in actual if o['source_part']==index for v in o.data.vertices]
    kd=KDTree(len(vv))
    for i,p in enumerate(vv):kd.insert(p,i)
    kd.balance();err=max(kd.find(src.matrix_world@v.co)[2] for v in src.data.vertices)
    assert err<3e-6,(index,err)
    results.append({'source_part':index,'exported_glb_source_vertex_max_error_m':err})
sc=bpy.context.scene;sc.render.engine='BLENDER_WORKBENCH';sc.render.resolution_x=sc.render.resolution_y=512
sc.render.resolution_percentage=100;sc.render.film_transparent=True;sc.render.image_settings.file_format='PNG'
sc.world=bpy.data.worlds.new('MaskWorld');sc.world.color=(0,0,0)
sh=sc.display.shading;sh.light='FLAT';sh.color_type='SINGLE';sh.single_color=(1,1,1)
sh.show_shadows=False;sh.show_cavity=False;sh.show_object_outline=False;sh.background_type='WORLD'
cam=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));sc.collection.objects.link(cam);sc.camera=cam
cam.data.type='ORTHO';cam.data.ortho_scale=2.7
silhouettes=[]
for name,d in [('front',(0,1,0)),('side',(1,0,0)),('back',(0,-1,0)),('quarter',(.8,1.2,.65))]:
    c=Vector((0,0,.9));cam.location=c+Vector(d).normalized()*7;cam.rotation_euler=(c-cam.location).to_track_quat('-Z','Y').to_euler()
    masks=[]
    for label,show,hide in [('source',retained,actual),('result',actual,retained)]:
        for o in show:o.hide_render=False
        for o in hide:o.hide_render=True
        path=OUT/('view_mask_'+name+'_'+label+'.png');sc.render.filepath=str(path);bpy.ops.render.render(write_still=True)
        im=bpy.data.images.load(str(path),check_existing=False);a=np.array(im.pixels[:]).reshape(512,512,4);bpy.data.images.remove(im);masks.append(a[:,:,3]>.5)
    a,b=masks;intersection=np.logical_and(a,b).sum();union=np.logical_or(a,b).sum()
    coverage=float(intersection/a.sum());iou=float(intersection/union)
    assert coverage>=.9995,(name,coverage)
    silhouettes.append({'view':name,'original_silhouette_retained_ratio':coverage,'silhouette_iou_including_added_bearings':iou,'source_pixels':int(a.sum()),'result_pixels':int(b.sum())})
movie=bpy.data.movieclips.load(str(OUT/'pose_trial.mp4'))
assert movie.frame_duration==160 and tuple(movie.size)==(480,480)
source_hash=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
assert source_hash==hashlib.sha256(Path('C:/Users/Loadcomplete/Downloads/mech suit 3d model.glb').read_bytes()).hexdigest()
out={'source_sha256':source_hash,'asset_sha256':hashlib.sha256(ASSET.read_bytes()).hexdigest(),
     'roundtrip_vertices':results,'silhouettes':silhouettes,'video':{'frames':160,'size':[480,480]},
     'scope':'Retained source body, uniformly scaled 2.35 and rotated to engine forward. Excludes deleted ornaments and puddles. Actual exported GLB reimported for audit.'}
(OUT/'export_verification.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print('EXPORTED_VOLUME_PRESERVATION_OK',json.dumps(silhouettes),flush=True)

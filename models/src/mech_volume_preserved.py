"""Rigid articulation of the user's segmented GLB, preserving original surfaces.

No decimation, shrinking, remeshing, vertex relaxation, or clearance fitting.
Only plane intersections create new surface vertices; UVs and normals interpolate.
Original triangle provenance and area are retained for an independent audit.
"""
from pathlib import Path
import hashlib, json
from collections import defaultdict
from mathutils.geometry import tessellate_polygon

META={'name':'mech_volume_preserved'}
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/models/mech_volume_preserved';OUT.mkdir(parents=True,exist_ok=True)
SOURCE=ROOT/'models/source/mech_user/original.glb'
SOURCE_HASH='a3f3197a004c23281769d53fac7fd82988a8bd33ef65d10c0c2920d5af93d259'
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_HASH
SCALE=2.35
bpy.context.preferences.filepaths.file_preview_type='NONE'
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
source_objects={int(o.name.rsplit('_',1)[1]):o for o in bpy.context.scene.objects if o.type=='MESH'}
removed={1:'tall back ornament',2:'tall back ornament',14:'figure inside back ornament',8:'ground puddle',15:'ground droplet'}
dark=hb.mat('CutInterior','#30372b',metal=.1,rough=.85)
source_areas={}; output_areas=defaultdict(float); parts=[];cap_warnings=[]

def area(v):
    return sum((v[i][0]-v[0][0]).cross(v[i+1][0]-v[0][0]).length*.5 for i in range(1,len(v)-1))

def read(o,index):
    m=o.data;m.calc_loop_triangles();uv=m.uv_layers.active
    polygons=[]
    for i,t in enumerate(m.loop_triangles):
        corners=[(o.matrix_world@m.vertices[m.loops[l].vertex_index].co,
                  Vector(uv.data[l].uv),(o.matrix_world.to_3x3().inverted().transposed()@m.corner_normals[l].vector).normalized()) for l in t.loops]
        polygons.append((corners,i,False))
        source_areas[(index,i)]=area(corners)
    return polygons

def clip(poly,p,n,positive):
    result=[];corners=poly[0]
    for i,a in enumerate(corners):
        b=corners[(i+1)%len(corners)];da=(a[0]-p).dot(n);db=(b[0]-p).dot(n)
        ina=da>=0 if positive else da<=0;inb=db>=0 if positive else db<=0
        if ina:result.append(a)
        if ina!=inb:
            t=da/(da-db)
            result.append(tuple(a[k].lerp(b[k],t) for k in range(3)))
    if len(result)<3 or area(result)<1e-14:return None
    return (result,poly[1],poly[2])

def caps(polys,p,n,positive,label):
    # Join cut segments by position, without welding or moving source surfaces.
    points={};edges=set()
    def key(v):return tuple(round(c,7) for c in v)
    for v,_,_ in polys:
        for i,a in enumerate(v):
            b=v[(i+1)%len(v)]
            if abs((a[0]-p).dot(n))<2e-7 and abs((b[0]-p).dot(n))<2e-7:
                ka,kb=key(a[0]),key(b[0])
                if ka!=kb:
                    points[ka]=a[0];points[kb]=b[0];edges.add(tuple(sorted((ka,kb))))
    adj=defaultdict(set)
    for a,b in edges:adj[a].add(b);adj[b].add(a)
    seen=set();out=[];normal=-n if positive else n
    for start in adj:
        if start in seen:continue
        group=set();stack=[start]
        while stack:
            k=stack.pop()
            if k in group:continue
            group.add(k);stack.extend(adj[k]-group)
        seen.update(group)
        if any(len(adj[k])!=2 for k in group):
            cap_warnings.append({'cut':label,'vertices':len(group),'reason':'source opening or branching at cut; left unchanged'})
            continue
        loop=[start];prev=None;cur=start
        while True:
            nxt=next(k for k in adj[cur] if k!=prev)
            if nxt==start:break
            loop.append(nxt);prev,cur=cur,nxt
        vv=[points[k] for k in loop]
        for tri in tessellate_polygon([vv]):
            a,b,c=[vv[t] if isinstance(t,int) else t for t in tri]
            if (b-a).cross(c-a).dot(normal)<0:b,c=c,b
            out.append(([(v.copy(),Vector((0,0)),normal.copy()) for v in [a,b,c]],-1,True))
    return out

def split(polys,point,normal,label):
    p=Vector(point);n=Vector(normal).normalized();sides=[]
    for positive in [False,True]:
        output=[q for poly in polys if (q:=clip(poly,p,n,positive)) is not None]
        output.extend(caps(output,p,n,positive,label));sides.append(output)
    return sides

def world(p):return Vector((-p[0]*SCALE,-p[1]*SCALE,p[2]*SCALE))
rig=hb.empty('MechRoot');rig['source_sha256']=SOURCE_HASH
rig['policy']='Preserve original exterior. Intentional overlap is allowed; never shrink armor for clearance.'
nodes={}
def pivot(name,p,parent):
    o=hb.empty(name);o.parent=parent;o.location=world(p)-parent.matrix_world.translation
    bpy.context.view_layer.update();o['source_pivot']=list(p);nodes[name]=o;return o

pelvis=pivot('pelvis',(0,.12,.285),rig)
body=pivot('body',(0,.10,.33),pelvis)
head=pivot('head',(0,.025,.435),body)
for side,x in [('hand',1),('gun',-1)]:
    sh=pivot('shoulder_'+side,(x*.215,.08,.515 if x>0 else .49),body)
    ua=pivot('arm_'+side+'_upper',(x*.24,.07,.485 if x>0 else .46),sh)
    fore=pivot('arm_'+side+'_fore',(x*.278,.025,.405) if x>0 else (-.235,.08,.36),ua)
    wrist=pivot('hand' if x>0 else 'gun_mount',(.318,-.15,.408) if x>0 else (-.27,.045,.285),fore)
    hip=pivot('hip_'+side,(x*.135,.13,.29),pelvis)
    knee=pivot('knee_'+side,(x*.175,.115,.163),hip)
    ankle=pivot('ankle_'+side,(x*.185,.10,.065),knee)
    pivot('pt_foot_'+side,(x*.185,.09,0),ankle)
pivot('pt_grip',(.385,-.215,.425),nodes['hand'])
pivot('pt_muzzle',(-.36,-.065,.15),nodes['gun_mount'])
for side,x in [('hand',1),('gun',-1)]:pivot('pt_booster_'+side,(x*.1,.30,.46),body)

def piece(name,polys,index,parent):
    vertices=[];faces=[];uvs=[];normals=[];ids=[];cap_flags=[]
    for corners,tid,is_cap in polys:
        for j in range(1,len(corners)-1):
            tri=[corners[0],corners[j],corners[j+1]]
            if area(tri)<1e-14:continue
            faces.append(tuple(range(len(vertices),len(vertices)+3)))
            for p,uv,n in tri:
                vertices.append(world(p)-parent.matrix_world.translation)
                uvs.append(uv);normals.append(Vector((-n.x,-n.y,n.z)).normalized())
            ids.append(tid);cap_flags.append(is_cap)
            if not is_cap:output_areas[(index,tid)]+=area(tri)
    if not faces:return
    me=bpy.data.meshes.new(name);me.from_pydata(vertices,[],faces)
    me.materials.append(source_objects[index].data.materials[0]);me.materials.append(dark)
    layer=me.uv_layers.new(name='UVMap')
    for i,uv in enumerate(uvs):layer.data[i].uv=uv
    attr=me.attributes.new('source_triangle','INT','FACE')
    for i,poly in enumerate(me.polygons):
        poly.material_index=int(cap_flags[i]);poly.use_smooth=not cap_flags[i];attr.data[i].value=ids[i]
    me.normals_split_custom_set(normals)
    obj=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(obj);obj.parent=parent
    obj['source_part']=index;obj['preservation']='Unmoved source surface; interpolated plane cut; internal caps only'
    parts.append({'object':name,'source_part':index,'parent':parent.name,'surface_triangles':sum(not f for f in cap_flags),'cap_triangles':sum(cap_flags)})

for index,o in source_objects.items():
    if index in removed:continue
    poly=read(o,index)
    if index==0:
        lower,upper=split(poly,(0,0,.33),(0,0,1),'waist')
        piece('pelvis_original',lower,index,pelvis);piece('torso_original',upper,index,body)
    elif index in [3,5]:
        side='hand' if index==3 else 'gun'
        lower,thigh=split(poly,(0,0,.163),(0,0,1),'knee_'+side)
        foot,shin=split(lower,(0,0,.065),(0,0,1),'ankle_'+side)
        for name,chunk,parent in [('thigh',thigh,'hip'),('shin',shin,'knee'),('foot',foot,'ankle')]:
            piece(name+'_'+side+'_original',chunk,index,nodes[parent+'_'+side])
    elif index==6:
        lower,shoulder=split(poly,(0,0,.505),(0,0,1),'shoulder_hand')
        upper,fore=split(lower,(.278,.025,.405),(0,-.8,-.6),'elbow_hand')
        hand,forearm=split(fore,(0,-.15,0),(0,1,0),'wrist_hand')
        for name,chunk,parent in [('shoulder_hand_original',shoulder,'shoulder_hand'),('upper_arm_hand_original',upper,'arm_hand_upper'),('forearm_hand_original',forearm,'arm_hand_fore'),('palm_original',hand,'hand')]:piece(name,chunk,index,nodes[parent])
    elif index==7:
        lower,shoulder=split(poly,(0,0,.47),(0,0,1),'shoulder_gun')
        fore,upper=split(lower,(0,0,.36),(0,0,1),'elbow_gun')
        for name,chunk,parent in [('shoulder_gun_original',shoulder,'shoulder_gun'),('upper_arm_gun_original',upper,'arm_gun_upper'),('forearm_gun_original',fore,'arm_gun_fore')]:piece(name,chunk,index,nodes[parent])
    else:
        name,parent={4:('gun_original',nodes['gun_mount']),9:('face_original',head),10:('fingers_original',nodes['hand']),
            11:('hip_armor_hand_original',nodes['hip_hand']),12:('groin_original',pelvis),13:('hip_armor_gun_original',nodes['hip_gun']),
            16:('pelvis_detail_16',pelvis),17:('pelvis_detail_17',pelvis),18:('pelvis_detail_18',pelvis),
            19:('face_detail_original',head),20:('pelvis_detail_20',pelvis),21:('pelvis_detail_21',pelvis)}[index]
        piece(name,poly,index,parent)

# Inset mechanical bearings cover the newly exposed inside of bends.
# They add internal material; they never replace or push in an original shell.
for side in ['hand','gun']:
    for joint,radius in [('knee_'+side,.044),('ankle_'+side,.030)]:
        o=hb.sphere('inner_'+joint,radius*SCALE,mat=dark,parent=nodes[joint],seg=16,rings=8)
        o['source_part']=-1;o['preservation']='Added inset bearing, no original surface removed'

audit=[]
for index in sorted(set(i for i,_ in source_areas)):
    keys=[k for k in source_areas if k[0]==index]
    maximum=max(abs(output_areas[k]-source_areas[k])/max(source_areas[k],1e-12) for k in keys)
    lost=sum(source_areas[k] for k in keys if output_areas[k]==0)
    assert maximum<.002 and lost==0,(index,maximum,lost)
    audit.append({'source_part':index,'source_surface_area':sum(source_areas[k] for k in keys),'result_surface_area':sum(output_areas[k] for k in keys),'max_per_triangle_relative_error':maximum,'lost_surface_area':lost})
for o in list(source_objects.values()):bpy.data.objects.remove(o,do_unlink=True)
oldroot=bpy.data.objects.get('RootNode')
if oldroot:bpy.data.objects.remove(oldroot,do_unlink=True)
(OUT/'build_audit.json').write_text(json.dumps({'source_sha256':SOURCE_HASH,'uniform_scale':SCALE,'removed_source_parts':removed,
    'policy':'No original retained surface discarded, shrunk, moved or simplified. Original pose preserved. No collision-clearance optimization.',
    'surface_area_audit':audit,'parts':parts,'cap_warnings':cap_warnings},indent=2),encoding='utf-8')

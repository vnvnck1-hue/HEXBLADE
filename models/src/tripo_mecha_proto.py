"""Tripo rigid-joint feasibility prototype. Build with tools/blender.ps1 model.

The source is preserved verbatim under models/source/tripo_mecha (Godot ignored).
Cuts are authored in original Blender coordinates; output faces +Y at ~1.7 m.
This is a fit/pose prototype, not a replacement for the production player.
"""
from pathlib import Path
import bmesh

META = {"name": "tripo_mecha_proto"}
bpy.context.preferences.filepaths.file_preview_type='NONE'
ROOT = Path(__file__).resolve().parents[2]
SCALE = 2.35
SOURCE = ROOT / 'models/source/tripo_mecha/original.glb'
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
src = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
paint = src.data.materials[0]
paint.name = 'TripoOriginalPaint'
paint.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=0.72
dark = hb.mat('JointGraphite', '#252b27', metal=0.35, rough=0.6)
olive = hb.mat('RepairOlive', '#465036', metal=0.0, rough=0.85)
bm = bmesh.new(); bm.from_mesh(src.data)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
# Loose puddle geometry is not part of the character.
remaining = set(bm.verts)
while remaining:
    v = remaining.pop(); stack = [v]; component = [v]
    while stack:
        v = stack.pop()
        for edge in v.link_edges:
            other = edge.other_vert(v)
            if other in remaining:
                remaining.remove(other); stack.append(other); component.append(other)
    if max(v.co.z for v in component) < 0.03:
        bmesh.ops.delete(bm, geom=component, context='VERTS')


def half(mesh, point, normal, positive=False, cap_index=1):
    """Retain one halfspace, interpolate UVs, and cap only newly cut boundaries."""
    out = mesh.copy(); p, n = Vector(point), Vector(normal).normalized()
    bmesh.ops.bisect_plane(out, geom=list(out.verts)+list(out.edges)+list(out.faces),
        dist=1e-7, plane_co=p, plane_no=n, clear_inner=positive, clear_outer=not positive)
    cut = [e for e in out.edges if e.is_boundary and all(abs((v.co-p).dot(n))<2e-6 for v in e.verts)]
    if cut:
        new = bmesh.ops.holes_fill(out, edges=cut, sides=0)
        for face in new.get('faces', []):
            face.material_index=cap_index; face.smooth=False
    return out


def split(mesh, point, normal):
    return half(mesh,point,normal), half(mesh,point,normal,True)


# Remove trophy roots and wires to a closed deck. Rebuild short exhausts later,
# avoiding slivers of the original connected trophy mesh on the backpack.
clean=half(bm,(0,0,0.64),(0,0,1),cap_index=2); bm.free()
def append_mesh(target,other):
    data=bpy.data.meshes.new('_append')
    other.to_mesh(data); other.free(); target.from_mesh(data); bpy.data.meshes.remove(data)

# Upper torso and pelvis remain one rigid unit for the first movement test.
lower, upper = split(clean,(0,0,0.305),(0,0,1)); clean.free()
# The fixed gun hangs below the waist: do not accidentally attach it to a thigh.
low_gun, legs_only = split(lower,(-0.285,0,0),(1,0,0)); lower.free()
# Rear dangling hose crosses the future hip motion; remove it from this trial.
lower = half(legs_only,(0,0.245,0),(0,1,0)); legs_only.free()
# Isolate the open-hand arm, preserving the original fixed gun arm.
torso, hand_arm = split(upper,(0.205,0,0),(1,0,0)); upper.free()
append_mesh(torso,low_gun)
# Discard the fused pelvis/codpiece; rebuild a compact articulated pelvis below.
low_bottom,low_top=split(lower,(0,0,0.22),(0,0,1)); lower.free()
leg_tops,pelvis_back=split(low_top,(0,0.12,0),(0,1,0)); low_top.free()
pelvis_back.free(); append_mesh(low_bottom,leg_tops); lower=low_bottom
outer_left,center_right=split(lower,(-0.075,0,0),(1,0,0)); lower.free()
center,outer_right=split(center_right,(0.075,0,0),(1,0,0)); center_right.free()
center_bottom,codpiece=split(center,(0,0,0.18),(0,0,1)); center.free()
codpiece.free(); append_mesh(outer_left,center_bottom); append_mesh(outer_left,outer_right); lower=outer_left
# Tilt the shoulder boundary outward, keeping raised fingertips on the hand.
arm_low,shoulder=split(hand_arm,(0.29,0,0.49),(-1.5,0,2)); hand_arm.free()
fore,upper_arm=split(arm_low,(0,-0.035,0),(0,1,0)); arm_low.free()
hand, forearm = split(fore,(0,-0.165,0),(0,1,0)); fore.free()
leg_gun, leg_hand = split(lower,(0,0,0),(1,0,0)); lower.free()

rig = hb.empty('PrototypeRoot')
rig['prototype_stage'] = 'revision 2: rebuilt pelvis and quad armor; articulated hand arm and legs; fixed gun arm'
rig['source_sha256'] = '8cff56cfbd2994d404a76fac9c06a8d63d5ab5d322a54f92e8ebbbac317be501'
rig['tall_back_ornaments_removed'] = True
nodes={}


def world(p):
    return Vector((-p[0]*SCALE,-p[1]*SCALE,p[2]*SCALE))


def pivot(name, point, parent):
    obj=hb.empty(name); obj.parent=parent
    obj.location=world(point)-parent.matrix_world.translation
    bpy.context.view_layer.update(); nodes[name]=obj
    obj['source_pivot']=list(point)
    return obj


def piece(name, mesh, parent):
    # Remove isolated cut residue, but keep original intentionally detached details.
    if len(mesh.verts):
        unseen=set(mesh.verts)
        while unseen:
            v=unseen.pop(); stack=[v]; component=[v]
            while stack:
                v=stack.pop()
                for edge in v.link_edges:
                    other=edge.other_vert(v)
                    if other in unseen:
                        unseen.remove(other); component.append(other); stack.append(other)
            faces=set(f for v in component for f in v.link_faces)
            residue=(name!='torso_fixed_gun' or (max(v.co.z for v in component)<0.36 and max(abs(v.co.x) for v in component)<0.32))
            if len(faces)<36 and residue:
                bmesh.ops.delete(mesh,geom=component,context='VERTS')
    # Preserve original face winding: global recalc on disconnected open armor
    # islands can invert thin plates after cutting.
    origin=parent.matrix_world.translation.copy()
    for v in mesh.verts: v.co=world(v.co)-origin
    data=bpy.data.meshes.new(name); mesh.to_mesh(data); mesh.free()
    data.materials.append(paint); data.materials.append(dark); data.materials.append(olive)
    obj=bpy.data.objects.new(name,data); bpy.context.scene.collection.objects.link(obj)
    obj.parent=parent
    for p in data.polygons:
        if p.material_index==0: p.use_smooth=True
    return obj


body=pivot('body',(0,0,0.305),rig)
piece('torso_fixed_gun',torso,body)
sh=pivot('shoulder_hand',(0.258,0.025,0.53),body)
shoulder.free()
hb.box('shoulder_armor',(0.125*SCALE,0.135*SCALE,0.085*SCALE),loc=(0,0,0.060*SCALE),mat=olive,parent=sh,bevel=0.024*SCALE)
ua=pivot('arm_hand_upper',(0.28,0.018,0.478),sh)
upper_arm.free()
fa=pivot('arm_hand_fore',(0.327,0.002,0.419),ua)
forearm.free()
ha=pivot('hand',(0.38,-0.165,0.422),fa)
piece('hand_shell',hand,ha)

for label, side, mesh in [('gun',-1,leg_gun),('hand',1,leg_hand)]:
    shin,thigh=split(mesh,(0,0,0.166),(0,0,1)); mesh.free()
    foot,shin_shell=split(shin,(0,0,0.062),(0,0,1)); shin.free()
    hip=pivot('hip_'+label,(side*0.145,0.055,0.285),rig)
    thigh.free()
    knee=pivot('knee_'+label,(side*0.17,-0.008,0.166),hip)
    shin_shell.free()
    ankle=pivot('ankle_'+label,(side*0.18,0.006,0.062),knee)
    piece('foot_'+label,foot,ankle)
    pivot('pt_foot_'+label,(side*0.18,-0.025,0.0),ankle)


def joint(name,parent,radius):
    hb.sphere(name,radius*SCALE,loc=(0,0,0),mat=dark,parent=parent,seg=16,rings=8)


joint('shoulder_bearing',ua,0.051)
joint('elbow_bearing',fa,0.045)
joint('wrist_bearing',ha,0.028)
for label in ['gun','hand']:
    joint('hip_bearing_'+label,nodes['hip_'+label],0.044)
    joint('knee_bearing_'+label,nodes['knee_'+label],0.037)
    joint('ankle_bearing_'+label,nodes['ankle_'+label],0.03)


def link_core(name,parent,child,radius):
    end=child.location.copy(); length=end.length
    core=hb.cyl(name,radius*SCALE,length,loc=end*0.5,mat=dark,parent=parent,seg=12)
    core.rotation_euler=Vector((0,0,1)).rotation_difference(end).to_euler()


def armor(name,parent,child,rings,width,depth):
    """Closed eight-sided quad cage, with rings inset from the moving joint.

    Width/depth are in original model units, rings are (bone fraction, profile).
    The deliberately small end rings leave a real folding gap at each joint.
    """
    axis=child.location.normalized(); length=child.location.length
    lateral=Vector((1,0,0)); lateral=(lateral-axis*axis.dot(lateral)).normalized()
    forward=axis.cross(lateral).normalized()
    if forward.y<0: forward=-forward
    profile=[(-0.65,-1),(0.65,-1),(1,-0.65),(1,0.65),(0.65,1),(-0.65,1),(-1,0.65),(-1,-0.65)]
    verts=[]
    for t,k in rings:
        for x,y in profile:
            verts.append(axis*(t*length)+lateral*(x*width*SCALE*k)+forward*(y*depth*SCALE*k))
    faces=[tuple(reversed(range(8)))]
    for r in range(len(rings)-1):
        for i in range(8): faces.append((r*8+i,r*8+(i+1)%8,(r+1)*8+(i+1)%8,(r+1)*8+i))
    faces.append(tuple(range((len(rings)-1)*8,len(rings)*8)))
    data=bpy.data.meshes.new(name); data.from_pydata(verts,[],faces); data.materials.append(olive)
    obj=bpy.data.objects.new(name,data); bpy.context.scene.collection.objects.link(obj); obj.parent=parent
    bm2=bmesh.new(); bm2.from_mesh(data); bmesh.ops.recalc_face_normals(bm2,faces=list(bm2.faces))
    assert all(e.is_manifold for e in bm2.edges),name
    assert all(f.calc_area()>1e-8 for f in bm2.faces),name
    bm2.to_mesh(data); bm2.free()
    obj['retopology']='closed quad cage with joint clearance'
    return obj


armor('upper_arm_shell',ua,fa,[(0.25,0.6),(0.38,1),(0.7,1),(0.82,0.72)],0.042,0.037)
armor('forearm_shell',fa,ha,[(0.16,0.75),(0.28,1),(0.66,1.05),(0.80,0.58)],0.050,0.046)
pelvis_center=world((0,0.065,0.302))-body.matrix_world.translation
hb.box('pelvis_shell',(0.20*SCALE,0.17*SCALE,0.09*SCALE),loc=pelvis_center,mat=dark,parent=body,bevel=0.025*SCALE)
hb.box('pelvis_guard',(0.075*SCALE,0.035*SCALE,0.095*SCALE),loc=world((0,-0.043,0.278))-body.matrix_world.translation,mat=olive,parent=body,bevel=0.014*SCALE)


link_core('upper_arm_frame',ua,fa,0.028)
link_core('forearm_frame',fa,ha,0.035)
for label in ['gun','hand']:
    armor('thigh_'+label,nodes['hip_'+label],nodes['knee_'+label],[(0.22,0.72),(0.35,1),(0.57,1),(0.74,0.40)],0.058,0.047)
    armor('shin_'+label,nodes['knee_'+label],nodes['ankle_'+label],[(0.28,0.4),(0.42,1),(0.61,0.88),(0.76,0.4)],0.052,0.046)
    link_core('thigh_frame_'+label,nodes['hip_'+label],nodes['knee_'+label],0.03)
    link_core('shin_frame_'+label,nodes['knee_'+label],nodes['ankle_'+label],0.032)
    hb.box('knee_guard_'+label,(0.086*SCALE,0.027*SCALE,0.049*SCALE),loc=(0,0.046*SCALE,0),mat=olive,parent=nodes['knee_'+label],bevel=0.010*SCALE)

# Replace removed rod roots with low, simple, closed armored service covers.
for side in [-1,1]:
    p=world((side*0.108,0.035,0.635))-body.matrix_world.translation
    hb.sphere('deck_cap_'+str(side),1.0,scale=(0.086*SCALE,0.10*SCALE,0.018*SCALE),loc=p,mat=olive,parent=body,seg=20,rings=8)
for x,z in [(-0.067,0.669),(0,0.682),(0.067,0.669)]:
    p=world((x,0.245,z))-body.matrix_world.translation
    hb.cyl('backpack_exhaust',0.024*SCALE,0.07*SCALE,loc=p,mat=olive,parent=body,seg=16)
    hb.cyl('exhaust_inset',0.017*SCALE,0.002*SCALE,loc=p+Vector((0,0,0.035*SCALE)),mat=dark,parent=body,seg=16)

pivot('pt_grip',(0.405,-0.213,0.407),ha)
pivot('pt_muzzle',(-0.39,-0.30,0.215),body)
for side,label in [(-1,'gun'),(1,'hand')]:
    pivot('pt_booster_'+label,(side*0.09,0.32,0.46),body)

# Small lateral shoulder clearance, bridged by the internal bearing. No change
# to trial angles or squat depth is used to hide geometry collisions.
sh.location.x-=0.045*SCALE

for obj in list(bpy.context.scene.objects):
    if obj==src or (obj.type=='EMPTY' and obj.name=='RootNode'):
        bpy.data.objects.remove(obj,do_unlink=True)


def after_join():
    bpy.context.view_layer.update()
    # Assert the cleanup in the neutral pose, including all remaining source mesh.
    peak=max((o.matrix_world@v.co).z for o in bpy.context.scene.objects if o.type=='MESH' for v in o.data.vertices)
    assert peak < 0.75*SCALE, peak
    assert all(n in nodes for n in ['arm_hand_fore','hand','knee_hand','knee_gun','pt_grip'])

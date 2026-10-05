"""Four metric hand-painted environment assets, exclusively bg_codex_*.
Called from models/src wrappers using the existing hb/model pipeline.
"""
from pathlib import Path
import math
import bpy
import bmesh
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
TEXTURES=ROOT/'assets/textures/codex_background'
PATCHES={'violet':(32,32,1024,1024),'coral':(32,1120,1024,512),
         'dark':(1120,32,896,896),'lavender':(1120,1000,896,1016)}

def image_material(name,texture,rough=.86):
    m=bpy.data.materials.new('bg_codex_'+name)
    m.use_nodes=True
    b=m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Metallic'].default_value=0
    b.inputs['Roughness'].default_value=rough
    b.inputs['Specular IOR Level'].default_value=.18
    t=m.node_tree.nodes.new('ShaderNodeTexImage')
    t.image=bpy.data.images.load(str(TEXTURES/('bg_codex_'+texture+'.png')),check_existing=True)
    t.interpolation='Linear';t.extension='REPEAT'
    m.node_tree.links.new(t.outputs['Color'],b.inputs['Base Color'])
    m['codex_texture']=texture
    m.diffuse_color=(.27,.18,.40,1)
    return m

def apply_mods(obj):
    bpy.context.view_layer.objects.active=obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bm=bmesh.new();bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(obj.data);bm.free()
    obj.data.update()

def uv(obj,style,material,trim=False,floor=False):
    apply_mods(obj)
    me=obj.data
    layer=me.uv_layers.new(name='MetricPaint') if not me.uv_layers else me.uv_layers.active
    obj.data.materials.clear();obj.data.materials.append(material)
    for poly in me.polygons:
        coords=[me.vertices[me.loops[i].vertex_index].co.copy() for i in poly.loop_indices]
        axis=max(range(3),key=lambda i:abs(poly.normal[i]))
        axes=[i for i in range(3) if i!=axis]
        mn=[min(v[a] for v in coords) for a in axes]
        mx=[max(v[a] for v in coords) for a in axes]
        if floor:
            for li,v in zip(poly.loop_indices,coords):
                # Blender +Y front => Godot -Z. Local floor X0..2 / Y-2..0.
                layer.data[li].uv=(v.x/4,-v.y/4) if axis==2 else ((v[axes[0]]-mn[0])/4,(v[axes[1]]-mn[1])/4)
            continue
        if trim:
            spans=[mx[i]-mn[i] for i in range(2)]
            if spans[0]>spans[1]:axes.reverse();mn.reverse();mx.reverse();spans.reverse()
            if style=='coral': x0,x1=0,128
            elif style=='dark':x0,x1=128,384
            elif style=='violet':x0,x1=384,512
            elif spans[0]<=.98:x0,x1=512,1024
            else:x0,x1=1024,2048
            # A trim face width must fit the actual allocated physical band.
            if spans[0]>(x1-x0)/512-.004:
                x0,x1=1024,2048
            for li,v in zip(poly.loop_indices,coords):
                layer.data[li].uv=((x0+2+(v[axes[0]]-mn[0])*512)/2048,(v[axes[1]]-mn[1])/4)
        else:
            x,y,w,h=PATCHES[style]
            spans=[mx[i]-mn[i] for i in range(2)]
            # Orient the face to fit the metric rectangular patch.
            if (spans[0]*512>w+.1 or spans[1]*512>h+.1) and spans[1]*512<=w+.1 and spans[0]*512<=h+.1:
                axes.reverse();mn.reverse();mx.reverse()
            for li,v in zip(poly.loop_indices,coords):
                layer.data[li].uv=((x+(v[axes[0]]-mn[0])*512)/2048,(y+(v[axes[1]]-mn[1])*512)/2048)
    obj['bg_uv_density']=512

def extruded_front(hb,name,points,y0,y1,part,style,materials):
    # points are X/Z positions, extrusion along Blender Y.
    verts=[(x,y,z) for y in (y0,y1) for x,z in points]
    n=len(points)
    faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(me);bm.free();me.update()
    o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o)
    o['hb_part']=part
    hb.add_bevel(o,.012,1)
    uv(o,style,materials['trim'],trim=True)
    return o

def build(kind,hb):
    mats={k:image_material(k,k) for k in ('base','trim','prop')}
    objects=[]
    def box(name,size,loc,style='violet',part='body',bevel=.018,trim=False):
        o=hb.box(name,size,loc=loc,bevel=bevel,seg=1,part=part)
        uv(o,style,mats['trim' if trim else 'prop'],trim=trim)
        objects.append(o);return o
    def bolt(name,loc,r=.045,depth=.025,part='body',trim=False):
        o=hb.cyl(name,r,depth,loc=loc,rot=(90,0,0),verts=8,bevel=.004,seg=1,part=part,smooth=False)
        uv(o,'dark',mats['trim' if trim else 'prop'],trim=trim);objects.append(o)
    if kind=='floor':
        o=hb.box('floor_slab',(2,2,.2),loc=(1,-1,-.1),bevel=.008,seg=1,part='floor')
        # hb shape uses mesh-local dimensions; bake location before absolute UV projection.
        bpy.context.view_layer.objects.active=o;o.select_set(True)
        bpy.ops.object.transform_apply(location=True,rotation=False,scale=False)
        uv(o,'violet',mats['base'],floor=True)
        objects.append(o)
    elif kind=='wall':
        box('rear_shell',(2,.19,3),(1,-.155,1.5),'lavender','wall',.018,True)
        pts=[(.20,.18),(1.80,.18),(1.86,.25),(1.86,2.72),(1.72,2.86),(.28,2.86),(.14,2.72),(.14,.25)]
        objects.append(extruded_front(hb,'recessed_face',pts,-.065,-.025,'wall','lavender',mats))
        for x in (.065,1.935):
            for j,(z,h) in enumerate(((.24,.48),(1.01,1.04),(1.90,.68),(2.61,.78))):
                box('frame_%s_%s'%(x,j),(.13,.06,h),(x,-.03,z),'violet','wall',.014,True)
        for z in (.065,2.935):box('cap_%s'%z,(1.78,.06,.13),(1,-.03,z),'violet','wall',.012,True)
        for x in (.16,1.84):
            for z in (.17,1.45,2.83):
                box('bolt_pad',(.20,.048,.20),(x,-.024,z),'violet','wall',.018,True)
                bolt('octagonal_bolt',(x,-.010,z),r=.053,depth=.020,part='wall',trim=True)
    elif kind=='workbench':
        box('countertop',(2,.75,.15),(0,0,.925),'coral','countertop',.025)
        box('underbeam',(1.74,.57,.08),(0,-.045,.82),'dark','frame',.012)
        for side in (-1,1):
            x=.655*side
            box('drawer_shell_%d'%side,(.62,.64,.76),(x,-.02,.45),'violet','frame',.018)
            for z in (.255,.605):
                box('drawer_face',( .55,.045,.30),(x,.320,z),'violet','drawers',.018)
                box('handle_socket',(.32,.014,.09),(x,.348,z+.01),'dark','drawers',.009)
                box('coral_handle',(.28,.04,.063),(x,.355,z+.015),'coral','drawers',.01)
            for y in (-.25,.25):
                box('foot',(.14,.13,.065),(x+.19*side,y,.0325),'dark','frame',.008)
        for x in (-.91,.91):
            for y in (-.285,.285):box('corner_cap',(.08,.11,.15),(x,y,.925),'coral','countertop',.014)
    elif kind=='locker':
        box('case',(1,.42,1.92),(0,-.04,1.04),'violet','case',.025)
        # Panels stay inside overall 0.5m depth, including the handles.
        for z,h in ((1.28,1.19),(.39,.46)):
            box('door_shadow',(.81,.018,h+.045),(0,.177,z),'dark','case',.018)
            box('door',(.76,.04,h),(0,.201,z),'lavender','doors',.025)
            box('handle_socket',(.083,.014,.245),(.27,.226,z-.025),'dark','doors',.012)
            box('handle',(.057,.021,.21),(.27,.2395,z-.025),'coral','doors',.013)
            for zz in (z-h*.32,z+h*.32):
                box('hinge',(.05,.035,.115),(-.414,.215,zz),'violet','doors',.008)
        for x in (-.38,.38):
            for y in (-.16,.13):box('foot',(.13,.13,.08),(x,y,.04),'dark','case',.012)
        for x in (-.42,.42):
            for z in (.16,1.92):bolt('case_bolt',(x,.174,z),r=.025,depth=.018,part='case')
    else:raise ValueError(kind)
    # Record contract on objects; no modifier-only or Blender-only shader dependencies.
    for o in objects:
        o['bg_codex_part']=kind
        o['bg_codex_owner']='Codex'
    return objects

def pivots(hb):
    for o in list(bpy.context.scene.objects):
        if o.type=='MESH':hb.set_origin(o,(0,0,0))
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath:im.pack()

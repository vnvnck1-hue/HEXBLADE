"""Same-scale ortho reference comparisons, with measured silhouette overlap.
This is a review aid, not proof of shape/material identity.
"""
import os
import sys
import json
import bpy
import numpy as np
from mathutils import Vector

if "--inspect" in sys.argv:
    t=bpy.data.node_groups.new("inspect","CompositorNodeTree")
    for kind in ("CompositorNodeDilateErode","ShaderNodeMath"):
        n=t.nodes.new(kind)
        print(kind,[(x.name,str(x.default_value) if hasattr(x,"default_value") else "") for x in n.inputs])
        print("PROPS",[p.identifier for p in n.bl_rna.properties])
    raise SystemExit(0)

ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT=os.path.join(ROOT,"output","models","tutorial_alien_b")
BASE=os.path.join(ROOT,"output","models","tutorial_alien_b_v1")
def load(p):
    im=bpy.data.images.load(p,check_existing=False); w,h=im.size
    a=np.empty(w*h*4,dtype=np.float32); im.pixels.foreach_get(a); bpy.data.images.remove(im)
    return a.reshape(h,w,4)[::-1]
def save(a,p):
    h,w=a.shape[:2]; im=bpy.data.images.new("comparison",w,h,alpha=True)
    im.pixels.foreach_set(np.ascontiguousarray(a[::-1]).ravel()); im.filepath_raw=p; im.file_format="PNG"; im.save()
    bpy.data.images.remove(im)

reference=load(os.path.join(ROOT,"output","concepts","tutorial_alien_b_turnaround.png"))
views=[("front",(30,200,590,670),(310,642),(0,1,0)),
       ("side",(600,200,1160,670),(898,642),(-1,0,0)),
       ("back",(1210,200,1770,670),(1464,642),(0,-1,0))]
scale=1205
rows=[]; metrics={}
for variant,path in (("v10",OUT),):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(path,"tutorial_alien_b_toon_studio.blend"))
    sc=bpy.context.scene; sc.render.resolution_x=560; sc.render.resolution_y=470
    sc.render.film_transparent=True
    for ob in sc.objects:
        if ob.name in ("STUDIO_floor","STUDIO_contact_shadow"): ob.hide_render=True
    cam=sc.camera; cam.data.type="ORTHO"; cam.data.sensor_fit="HORIZONTAL"; cam.data.ortho_scale=560/scale
    variant_metrics={}
    for name,(x0,y0,x1,y1),(ox,oy),direction in views:
        d=Vector(direction); right=-d.cross(Vector((0,0,1)))
        target=right*((x0+x1-2*ox)/2/scale)+Vector((0,0,(oy-(y0+y1)/2)/scale))
        cam.location=target+d*2
        cam.rotation_euler=(target-cam.location).to_track_quat("-Z","Y").to_euler()
        p=os.path.join(OUT,"compare_"+variant+"_"+name+".png")
        sc.render.filepath=p; bpy.ops.render.render(write_still=True)
        model=load(p); ref=reference[y0:y1,x0:x1]
        rgb=ref[:,:,:3]; mx=rgb.max(2); mn=rgb.min(2)
        mask=((mx-mn)>.11)|(mx<.43)
        mask[oy-y0+4:]=False # Ignore cast shadow below reference ground contact.
        mod=model[:,:,3]>.5
        iou=float((mask&mod).sum()/max((mask|mod).sum(),1))
        variant_metrics[name]={"silhouette_iou":round(iou,4),"reference_pixels":int(mask.sum()),"model_pixels":int(mod.sum())}
        if variant=="v10":
            bg=np.ones_like(model); bg[:,:,:3]=(.63,.61,.56)
            alpha=model[:,:,3:4]
            bg[:,:,:3]=model[:,:,:3]*alpha+bg[:,:,:3]*(1-alpha)
            overlay=np.ones_like(model); overlay[:,:,:3]=.14
            overlay[mask&mod,:3]=(.88,.88,.83)
            overlay[mask&~mod,:3]=(.95,.24,.18)
            overlay[mod&~mask,:3]=(.13,.78,.89)
            gap=np.ones((470,8,4),dtype=np.float32); gap[:,:,:3]=.1
            rows.append(np.concatenate([ref,gap,bg,gap,overlay],axis=1))
    metrics[variant]=variant_metrics
save(np.concatenate(rows,axis=0),os.path.join(OUT,"reference_compare.png"))
with open(os.path.join(OUT,"reference_compare.json"),"w",encoding="utf-8") as f: json.dump(metrics,f,indent=2)
print("REFERENCE_COMPARE",json.dumps(metrics))

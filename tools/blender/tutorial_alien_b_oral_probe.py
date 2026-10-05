"""Read-only camera ray inspection of the far oral corner in the saved studio."""
import os
import json
import sys
import bpy
from mathutils import Vector

root=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out=os.path.join(root,"output","models","tutorial_alien_b")
suffix="_lod" if "--lod" in sys.argv else ""
bpy.ops.wm.open_mainfile(filepath=os.path.join(out,"tutorial_alien_b"+suffix+"_toon_studio.blend"))
sc=bpy.context.scene
cam=sc.camera
dg=bpy.context.evaluated_depsgraph_get()
right=cam.matrix_world.to_3x3()@Vector((1,0,0))
up=cam.matrix_world.to_3x3()@Vector((0,1,0))
direction=cam.matrix_world.to_3x3()@Vector((0,0,-1))
report=[]
for x,y in ((566,419),(566,433),(575,449),(579,433),(565,449)):
    origin=cam.location+right*((x+.5)/768-.5)*cam.data.ortho_scale+up*(.5-(y+.5)/768)*cam.data.ortho_scale
    skipped=[]
    for _ in range(32):
        hit,point,normal,face,ob,matrix=sc.ray_cast(dg,origin,direction)
        if not hit:
            break
        material=ob.data.materials[ob.data.polygons[face].material_index]
        if material.use_backface_culling and normal.dot(direction)>=0:
            skipped.append(ob.name)
            origin=point+direction*.00001
            continue
        break
    record={"pixel":[x,y],"hit":hit,"object":ob.name if hit else None}
    record["culled_backfaces_skipped"]=skipped
    if hit:
        record["world_position"]=list(point)
        record["polygon_index"]=face
        record["material"]=ob.data.materials[ob.data.polygons[face].material_index].name
    report.append(record)
with open(os.path.join(out,"oral_corner_probe"+suffix+".json"),"w",encoding="utf-8") as f:
    json.dump(report,f,ensure_ascii=False,indent=2)
print("ORAL_CORNER_PROBE",json.dumps(report))

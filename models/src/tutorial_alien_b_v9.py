"""Reference-shaped rebuild. Front +Y, meters, no subdivision modifiers.
Build through tools/blender.ps1 model models/src/tutorial_alien_b_v9.py --no-preview.
"""
import os
import random
import bmesh
import numpy as np
from mathutils import Matrix

META={"name":"tutorial_alien_b"}
ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT=os.path.join(ROOT,"output","models","tutorial_alien_b")
os.makedirs(OUT,exist_ok=True)
COLORS=["#ffca50","#49aaa5","#963e49","#f4776c","#fff1d1","#726d62","#60cbc3","#f3d184"]
W,H=512,256
arr=np.ones((H,W,4),dtype=np.float32)
yy,xx=np.mgrid[0:128,0:128]/127
for k,col in enumerate(COLORS):
    rgb=np.array([int(col[i:i+2],16)/255 for i in (1,3,5)])
    tile=np.clip(rgb[None,None,:]*(.85+.15*yy[...,None]),0,1)*np.ones((128,128,1))
    if k==0:
        # Broad brush colors and ochre freckles; no extra surface geometry.
        tile=np.broadcast_to(rgb,(128,128,3)).copy()
        tile*=((.86+.14*yy)+.045*np.exp(-((xx-.40)/.3)**2))[...,None]
        edge=(yy<.05)|(xx<.03)|(xx>.97)
        tile[edge]*=np.array([.83,.72,.59])
        # A broad curved brush stroke, not a mechanically straight repeated band.
        brush_y=.87+.028*np.sin(math.pi*xx)+.007*np.sin(3*math.pi*xx)
        brush_w=.030+.009*np.sin(math.pi*xx)**2
        band=(abs(yy-brush_y)<brush_w)&(xx>.06)&(xx<.94)
        tile[band]=.6*tile[band]+.4*np.array([1,.90,.55])
        rng=random.Random(167)
        for _ in range(12):
            x,y=rng.uniform(.12,.9),rng.uniform(.13,.80)
            rx,ry=rng.uniform(.024,.055),rng.uniform(.03,.067)
            d=((xx-x)/rx)**2+((yy-y)/ry)**2
            f=np.clip((1.05-d)/.16,0,1)[...,None]*.27
            tile=tile*(1-f)+np.array([.89,.54,.12])*f
    if k==2:
        # Warm reflected color in the lower mouth, burgundy towards the throat.
        tile=np.array([.66,.26,.29])[None,None,:]*(1-yy[...,None])+np.array([.47,.17,.23])*yy[...,None]
        tile=np.broadcast_to(tile,(128,128,3)).copy()
    if k==1:
        # Broad painted belly ribs, not extra geometry or noisy skin detail.
        for edge in (.20+.06*yy,.80-.06*yy):
            stroke=np.exp(-((xx-edge)/.010)**2)*.30
            tile*=1-stroke[...,None]
        curve=.12+.12*(2*xx-1)**2
        stroke=np.exp(-((yy-curve)/.011)**2)*.25
        tile*=1-stroke[...,None]
    if k==3:
        tile=np.broadcast_to(rgb,(128,128,3)).copy()*(.88+.12*yy[...,None])
        # The two rounded lobes form one real center crease; no duplicated painted grooves.
    if k==5:
        spot=np.exp(-(((xx-.33)/.11)**2+((yy-.71)/.18)**2))
        tile+=spot[...,None]*.16
    if k==6:
        distance=((xx-.34)/.15)**2+((yy-.77)/.085)**2
        spot=np.clip((1-distance)/.18,0,1)*.80
        tile=tile*(1-spot[...,None])+np.array([.87,1,.94])*spot[...,None]
    arr[(k//4)*128:(k//4+1)*128,(k%4)*128:(k%4+1)*128,:3]=np.clip(tile,0,1)
im=bpy.data.images.new("B_painted_atlas_512x256",W,H,alpha=True)
im.colorspace_settings.name="sRGB"
im.pixels.foreach_set(arr.ravel()); im.filepath_raw=os.path.join(ROOT,"assets","models","tutorial_alien_b_atlas.png")
im.file_format="PNG"; im.save(); im.pack()
MAT=hb.mat("B_cartoon_atlas","#ffffff",rough=1)
MAT.use_backface_culling=True
tx=MAT.node_tree.nodes.new("ShaderNodeTexImage"); tx.name="Painted_Atlas"; tx.image=im
MAT.node_tree.links.new(tx.outputs["Color"],MAT.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])

def uv_tile(k,u,v):
    return ((k%4+.035+.93*u)/4,(k//4+.035+.93*v)/2)

def mesh(name,vs,fs,k,uv=None,part=None,normals=None,face_tiles=None):
    me=bpy.data.meshes.new(name); me.from_pydata(vs,[],fs); me.update()
    bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    if normals is not None:
        # Open oral/shell surfaces have a deliberate visible side. Preserve it
        # so back-face culling hides the near cheek and reveals the far inside.
        bm.verts.ensure_lookup_table(); bm.verts.index_update()
        for face in bm.faces:
            desired=sum((Vector(normals[v.index]) for v in face.verts),Vector((0,0,0)))
            if face.normal.dot(desired)<0: face.normal_flip()
    bm.to_mesh(me); bm.free()
    ob=bpy.data.objects.new(name,me); hb.collection().objects.link(ob); me.materials.append(MAT)
    if uv is None:
        a=np.array(vs); lo=a.min(0); span=np.maximum(a.max(0)-lo,.00001)
        uv=[((p[0]-lo[0])/span[0],(p[2]-lo[2])/span[2]) for p in vs]
    layer=me.uv_layers.new(name="PaintedAtlas")
    for p in me.polygons:
        p.use_smooth=True
        for li in p.loop_indices:
            idx=me.loops[li].vertex_index
            layer.data[li].uv=uv_tile(face_tiles[p.index] if face_tiles else k,*uv[idx])
    if normals is not None:
        me.normals_split_custom_set_from_vertices(normals)
    ob["hb_part"]=part or name
    return ob

def blob(name,c,r,k,n=10,rings=5,part=None,clamp=None,rotation=None,latitudes=None):
    vs=[(0,0,-r[2])]
    for j in range(1,rings):
        a=math.radians(latitudes[j-1]) if latitudes else -math.pi/2+math.pi*j/rings
        for i in range(n):
            t=2*math.pi*i/n
            vs.append((r[0]*math.cos(a)*math.cos(t),r[1]*math.cos(a)*math.sin(t),r[2]*math.sin(a)))
    vs.append((0,0,r[2])); fs=[(0,1+(i+1)%n,1+i) for i in range(n)]
    for j in range(rings-2):
        for i in range(n):
            a=1+j*n+i; b=1+j*n+(i+1)%n; fs.append((a,b,b+n,a+n))
    last=1+(rings-2)*n
    fs += [(last+i,last+(i+1)%n,len(vs)-1) for i in range(n)]
    rot=rotation or Matrix.Identity(3)
    ns=[tuple(rot@Vector((p[0]/r[0]**2,p[1]/r[1]**2,p[2]/r[2]**2)).normalized()) for p in vs]
    uv=[(.5+p[0]/r[0]*.5,.5+p[2]/r[2]*.5) for p in vs]
    verts=[tuple(rot@Vector(p)+Vector(c)) for p in vs]
    if clamp is not None: verts=[(p[0],min(p[1],clamp+max(0,.12-p[2])*.9),p[2]) for p in verts]
    return mesh(name,verts,fs,k,uv,part,ns)

# Evenly distributed triangles give these small round contours better latitude
# coverage than the old coarse rings, at only 80 triangles before buried culling.
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1)
ico_ob=bpy.context.object
pole=max(ico_ob.data.vertices,key=lambda v:v.co.z).co.normalized()
ICO_ROT=pole.rotation_difference(Vector((0,0,1))).to_matrix()
ICO_VERTS=[ICO_ROT@v.co for v in ico_ob.data.vertices]
ICO_FACES=[tuple(f.vertices) for f in ico_ob.data.polygons]
ico_mesh=ico_ob.data; bpy.data.objects.remove(ico_ob,do_unlink=True); bpy.data.meshes.remove(ico_mesh)

def pebble(name,c,r,k,part=None,rotation=None,taper=0,bend=0,round_contour=False):
    rot=rotation or Matrix.Identity(3)
    vs=[]; ns=[]; uv=[]
    units=ICO_VERTS; faces=ICO_FACES
    if round_contour:
        # Twelve evenly spaced points on the widest contour are more useful
        # for these prominent feet/teeth than geodesic directions that miss it.
        units=[Vector((0,0,-1))]
        for latitude in (-60,-30,0,30,60):
            a=math.radians(latitude)
            units.extend(Vector((math.cos(a)*math.cos(i*math.tau/12),math.cos(a)*math.sin(i*math.tau/12),math.sin(a))) for i in range(12))
        units.append(Vector((0,0,1)))
        faces=[(0,1+(i+1)%12,1+i) for i in range(12)]
        for j in range(4):
            for i in range(12):
                a=1+j*12+i; b=1+j*12+(i+1)%12
                faces.append((a,b,b+12,a+12))
        faces.extend((49+i,49+(i+1)%12,61) for i in range(12))
    for unit in units:
        scale=1+taper*unit.z
        p=Vector((unit.x*r[0]*scale,unit.y*r[1]*scale+bend*unit.z,unit.z*r[2]))
        # Inverse transpose of the tapered ellipsoid Jacobian, for smooth light.
        nz=unit.z/r[2]-taper*(unit.x*unit.x+unit.y*unit.y)/(scale*r[2])-bend*unit.y/(r[1]*scale*r[2])
        normal=Vector((unit.x/(r[0]*scale),unit.y/(r[1]*scale),nz)).normalized()
        vs.append(tuple(rot@p+Vector(c))); ns.append(tuple(rot@normal))
        uv.append((.5+.47*unit.x,.5+.47*unit.z))
    return mesh(name,vs,faces,k,uv,part,ns)

def shell(name,profile):
    # Convex longitudinal curvature + curved scalloped edges. Not a rectangular bent strip.
    nx,ny=(12 if name=="plate_rear" else 14),6; vs=[]; uv=[]; normals=[]; lower_normals=[]; lower=[]
    def point(u,v):
        # Round the four patch corners without subdivision or extra rings.
        a,b=2*u-1,2*v-1
        u=(a*math.sqrt(1-.25*b*b)+1)/2
        v=(b*math.sqrt(1-.25*a*a)+1)/2
        t=(u-.5)*2.8
        f=min(v*(len(profile)-1),len(profile)-1.000001); j=int(f); f-=j
        # Cubic Hermite interpolation follows the drawn convex side silhouette.
        a=Vector(profile[j]); b=Vector(profile[j+1])
        ma=(b-Vector(profile[max(0,j-1)]))*.5
        mb=(Vector(profile[min(len(profile)-1,j+2)])-a)*.5
        p=(2*f**3-3*f*f+1)*a+(f**3-2*f*f+f)*ma+(-2*f**3+3*f*f)*b+(f**3-f*f)*mb
        yc,zc,ye,ze,w=p
        x=w*math.sin(t)
        y=ye+(yc-ye)*math.cos(t)
        z=ze+(zc-ze)*math.cos(t)
        return Vector((x,y,z))
    for j in range(ny+1):
        for i in range(nx+1):
            u,v=i/nx,j/ny; vs.append(tuple(point(u,v))); uv.append((u,1-v))
            du=point(min(1,u+.001),v)-point(max(0,u-.001),v)
            dv=point(u,min(1,v+.001))-point(u,max(0,v-.001))
            normal=du.cross(dv).normalized()
            if normal.z<0: normal=-normal
            # Rounded, thick lip normals. The old duplicate upper normals made
            # the side walls shade like paper, even though a rim existed.
            outward=Vector((0,0,0))
            if i in (0,nx): outward+=du.normalized()*(-1 if i==0 else 1)
            if j in (0,ny): outward+=dv.normalized()*(-1 if j==0 else 1)
            if outward.length:
                outward=(outward-normal*outward.dot(normal)).normalized()
                normals.append(tuple((normal*.78+outward*.35).normalized()))
                lower_normals.append(tuple((outward*.9-Vector((0,0,.3))).normalized()))
                lower.append(tuple(point(u,v)-outward*.005-Vector((0,0,.020))))
            else:
                normals.append(tuple(normal)); lower_normals.append(tuple(-normal))
                lower.append(tuple(point(u,v)-Vector((0,0,.020))))
    half=len(vs)
    # Thick rim only; hidden central underside omitted.
    vs += lower; uv += uv.copy()
    normals += lower_normals
    fs=[]; row=nx+1
    for j in range(ny):
        for i in range(nx):
            a=j*row+i; fs.append((a,a+1,a+1+row,a+row))
    for i in range(nx):
        for j in (0,ny):
            a=j*row+i; fs.append((a,a+half,a+half+1,a+1))
    for j in range(ny):
        for i in (0,nx):
            a=j*row+i; fs.append((a,a+row,a+row+half,a+half))
    if name=="plate_front":
        # Close the visible space above the visor with a low-cost underside fan.
        edge=list(range(row))+[j*row+nx for j in range(1,ny+1)]+list(range(ny*row+nx-1,ny*row-1,-1))+[j*row for j in range(ny-1,0,-1)]
        center=sum((Vector(vs[i+half]) for i in edge),Vector((0,0,0)))/len(edge)
        ci=len(vs); vs.append(tuple(center)); uv.append((.5,.5)); normals.append((0,0,-1))
        fs.extend((i+half,edge[(q+1)%len(edge)]+half,ci) for q,i in enumerate(edge))
    return mesh(name,vs,fs,0,uv,part="shell",normals=normals)

# A closed, puffy transverse shield, not a thin patch with a dangling rim.
PLATE_PROXIES=[]
def puffy_shell(name,width,zbase,zarch,ybase,yarch,ry0,ry1,rz0,rz1,slope,nx=14,cross=10,bow=0):
    vs=[]; uv=[]; ns=[]
    def point(t,a):
        cs=math.cos(t)
        depth=(ry0+ry1*cs)*math.cos(a)
        return Vector((width*math.sin(t)+.008*math.sin(t)*math.sin(a),
                       ybase+yarch*cs+bow*cs*(1-cs)+depth,
                       zbase+zarch*cs+(rz0+rz1*cs)*math.sin(a)+slope*depth))
    for j in range(nx+1):
        t=-1.40+2.80*j/nx
        for q in range(cross):
            a=2*math.pi*q/cross
            p=point(t,a); dt=point(t+.001,a)-point(t-.001,a)
            da=point(t,a+.001)-point(t,a-.001)
            normal=da.cross(dt).normalized()
            if normal.dot(Vector((0,math.cos(a),math.sin(a))))<0: normal=-normal
            vs.append(tuple(p)); uv.append((j/nx,(1+math.sin(a))/2)); ns.append(tuple(normal))
    fs=[]
    for j in range(nx):
        for q in range(cross):
            a=j*cross+q; b=j*cross+(q+1)%cross
            fs.append((a,b,b+cross,a+cross))
    for j,sign in ((0,-1),(nx,1)):
        t=-1.40+2.80*j/nx; ci=len(vs)
        p=sum((Vector(vs[j*cross+q]) for q in range(cross)),Vector((0,0,0)))/cross
        p.x+=sign*.006
        vs.append(tuple(p)); uv.append((j/nx,.5)); ns.append((sign,0,0))
        fs.extend((j*cross+q,j*cross+(q+1)%cross,ci) for q in range(cross))
    ob=mesh(name,vs,fs,0,uv,part="shell",normals=ns)
    cached={tuple(v.co):ns[v.index] for v in ob.data.vertices}
    bm=bmesh.new(); bm.from_mesh(ob.data)
    # q<.75 is safely inside the inscribed volume of the coarse convex body,
    # not merely inside its smooth mathematical ellipsoid.
    hidden=[f for f in bm.faces if all((v.co.x/.162)**2+((v.co.y+.055)/.120)**2+((v.co.z-.140)/.108)**2<.75 for v in f.verts)]
    bmesh.ops.delete(bm,geom=hidden,context="FACES"); bm.to_mesh(ob.data); bm.free(); ob.data.update()
    ob.data.normals_split_custom_set_from_vertices([cached[tuple(v.co)] for v in ob.data.vertices])
    ob["buried_body_faces_removed"]=len(hidden)
    PLATE_PROXIES.append((width,zbase,zarch,ybase,yarch,ry0,ry1,rz0,rz1,slope,bow))
    return ob

def trim_buried_nub(ob,center,radii):
    def inside(p,proxy):
        width,zb,za,yb,ya,ry0,ry1,rz0,rz1,slope,bow=proxy
        if abs(p.x)>.92*width: return False
        cs=math.cos(math.asin(p.x/width))
        dy=p.y-yb-ya*cs-bow*cs*(1-cs)
        dz=p.z-zb-za*cs-slope*dy
        # The sweep's small X offset is deliberately guarded by a deep inset.
        return (dy/(ry0+ry1*cs))**2+(dz/(rz0+rz1*cs))**2<.65
    bm=bmesh.new(); bm.from_mesh(ob.data)
    hidden=[f for f in bm.faces if any(all(inside(v.co,p) for v in f.verts) for p in PLATE_PROXIES)]
    bmesh.ops.delete(bm,geom=hidden,context="FACES"); bm.to_mesh(ob.data); bm.free(); ob.data.update()
    ob.data.normals_split_custom_set_from_vertices([tuple(Vector(tuple((v.co[a]-center[a])/radii[a]**2 for a in range(3))).normalized()) for v in ob.data.vertices])

# Full rounded shoulders stay behind the oral pocket. No planar chest clamp
# or exposed cut-out boundary is needed.
body=blob("body",(0,-.055,.140),(.162,.120,.108),1,n=16,rings=6)
belly_center=Vector((0,.020,.061)); belly_radii=Vector((.112,.130,.042))
belly=blob("belly",tuple(belly_center),tuple(belly_radii),1,n=12,rings=4,part="body")
bm=bmesh.new(); bm.from_mesh(belly.data)
hidden=[f for f in bm.faces if all((v.co.x/.162)**2+((v.co.y+.055)/.120)**2+((v.co.z-.140)/.108)**2<.90 for v in f.verts)]
bmesh.ops.delete(bm,geom=hidden,context="FACES"); bm.to_mesh(belly.data); bm.free(); belly.data.update()
belly.data.normals_split_custom_set_from_vertices([tuple(Vector(tuple((v.co[a]-belly_center[a])/belly_radii[a]**2 for a in range(3))).normalized()) for v in belly.data.vertices])
puffy_shell("plate_rear",.127,.112,.058,-.140,-.009,.013,.040,.018,.028,.50,nx=12,cross=8,bow=-.01)
puffy_shell("plate_middle",.185,.145,.090,.000,-.075,.020,.080,.020,.028,.45,nx=12,cross=10,bow=-.025)
puffy_shell("plate_front",.154,.172,.120,.005,.070,.015,.057,.021,.020,-.35,nx=14,cross=10,bow=.05)

# Closed swept oval brow. Its side silhouette is an oval, not a flat wedge.
nx,cross=12,12; vs=[]; uv=[]; ns=[]
def brow_point(t,a):
    cs=math.cos(t); radial=Vector((math.sin(t),0,cs))
    center=Vector((.143*math.sin(t),.017+.138*cs**1.4,.136+.124*cs))
    depth=(.020+.042*cs**2)*math.cos(a)
    return center+radial*((.020+.014*cs)*math.sin(a))+Vector((0,depth,-.12*depth))
for j in range(nx+1):
    t=-1.41+2.82*j/nx
    for q in range(cross):
        a=2*math.pi*q/cross; p=brow_point(t,a)
        dt=brow_point(t+.001,a)-brow_point(t-.001,a)
        da=brow_point(t,a+.001)-brow_point(t,a-.001)
        normal=da.cross(dt).normalized()
        outward=Vector((math.sin(t)*math.sin(a),math.cos(a),math.cos(t)*math.sin(a)))
        if normal.dot(outward)<0: normal=-normal
        vs.append(tuple(p)); ns.append(tuple(normal)); uv.append((j/nx,(math.sin(a)+1)/2))
fs=[]
for j in range(nx):
    for q in range(cross):
        a=j*cross+q; b=j*cross+(q+1)%cross; fs.append((a,b,b+cross,a+cross))
fs += [tuple(range(cross-1,-1,-1)),tuple(range(nx*cross,nx*cross+cross))]
mesh("brow",vs,fs,0,uv,normals=ns)

# A rounded center crest with bulging cheeks rather than a triangular prism.
vs=[]; uv=[]; ns=[]; n=8
for j,(z,y,rx,ry) in enumerate(((.288,.130,.029,.037),(.309,.107,.030,.045),(.334,.075,.024,.040),(.351,.041,.012,.023),(.356,.018,.003,.008))):
    for i in range(n):
        t=2*math.pi*i/n
        vs.append((rx*math.cos(t),y+ry*math.sin(t),z)); uv.append((.5+.25*math.cos(t),.91+.05*j/4))
        ns.append(tuple(Vector((math.cos(t),math.sin(t),j/4)).normalized()))
fs=[]
for j in range(4):
    for i in range(n):
        a=j*n+i; b=j*n+(i+1)%n; fs.append((a,b,b+n,a+n))
fs += [tuple(range(n-1,-1,-1)),tuple(range(4*n,5*n))]
mesh("crest",vs,fs,0,uv,part="shell",normals=ns)
for s in (-1,1):
    for name,c,r,n in (("nub_front",(s*.108,.0755,.287),(.025,.025,.020),12),
                       ("nub_middle",(s*.155,-.036,.225),(.024,.024,.023),10)):
        ob=pebble(name,c,r,6,part="shell"); trim_buried_nub(ob,c,r)
c=(0,-.161,.225); r=(.024,.018,.022)
ob=pebble("nub_back",c,r,6,part="shell"); trim_buried_nub(ob,c,r)

# Mouth bowl sits inside the golden rim; corners tuck back towards the cheeks.
n=20; vs=[]; uv=[]
for radius,dep in ((1,.0),(.70,-.042),(.30,-.073)):
    for i in range(n):
        t=2*math.pi*i/n; ct=math.cos(t); st=math.sin(t)
        x=.136*radius*math.copysign(abs(ct)**.65,ct)
        z=.159+.073*radius*st+.012*radius*max(0,st)
        y=.198-.150*abs(ct)**1.2*radius-.028*max(0,-st)*radius+dep
        vs.append((x,y,z)); uv.append((.5+.47*radius*math.cos(t),.5+.47*radius*math.sin(t)))
vs.append((0,.084,.144)); uv.append((.5,.5)); fs=[]
for j in range(2):
    for i in range(n):
        a=j*n+i; b=j*n+(i+1)%n; fs.append((a,b,b+n,a+n))
fs += [(2*n+i,2*n+(i+1)%n,3*n) for i in range(n)]
mouth_normals=[tuple(Vector((-x/.118,1.6,-(z-.159)/.073)).normalized()) for x,y,z in vs]
mesh("mouth_bowl",vs,fs,2,uv,part="body",normals=mouth_normals)

# A closed, inward-facing pocket replaces two open cheek fans. The near wall
# is culled; the far inside remains visible rather than exposing the studio.
oral_center=Vector((0,.065,.150)); oral_radii=Vector((.141,.097,.083))
pocket=blob("oral_pocket",tuple(oral_center),tuple(oral_radii),2,n=12,rings=4,part="body")
bm=bmesh.new(); bm.from_mesh(pocket.data)
bmesh.ops.reverse_faces(bm,faces=list(bm.faces)); bm.to_mesh(pocket.data); bm.free()
pocket.data.update()
pocket.data.normals_split_custom_set_from_vertices([tuple(-Vector(tuple((v.co[a]-oral_center[a])/oral_radii[a]**2 for a in range(3))).normalized()) for v in pocket.data.vertices])

# Golden lower jaw, a full-volume bowl-shaped U. Broad chin visible in profile.
n=14; cross=12; vs=[]; uv=[]; ns=[]
def jaw_center(t):
    return Vector((.140*math.cos(t),.067+.112*max(0,-math.sin(t))**1.3,.165+.107*math.sin(t)))
for j in range(n+1):
    t=math.pi+.10+(math.pi-.20)*j/n; center=jaw_center(t)
    radial=Vector((math.cos(t),0,math.sin(t)))
    depth=Vector((0,1,0))
    for q in range(cross):
        a=2*math.pi*q/cross
        radius=.014+.010*max(0,-math.sin(t))
        depth_radius=.012+.028*max(0,-math.sin(t))
        p=center+radial*(radius*math.cos(a))+depth*(depth_radius*math.sin(a))
        vs.append(tuple(p)); uv.append((j/n,(math.cos(a)+1)/2))
        ns.append(tuple((radial*(math.cos(a)/radius)+depth*(math.sin(a)/depth_radius)).normalized()))
fs=[]
for j in range(n):
    for q in range(cross):
        a=j*cross+q; b=j*cross+(q+1)%cross; fs.append((a,b,b+cross,a+cross))
fs += [tuple(range(cross-1,-1,-1)),tuple(range(n*cross,n*cross+cross))]
mesh("jaw",vs,fs,7,uv,normals=ns)
tongue=blob("tongue",(0,.150,.103),(.105,.045,.050),3,n=20,rings=6,part="jaw",latitudes=(-60,-20,20,50,75))
tongue_normals=[]
for vert in tongue.data.vertices:
    # One continuous tongue with a subtle central notch, not two disconnected buns.
    x,y,z=vert.co; e=math.exp(-(x/.020)**2); height=max(0,(z-.103)/.050)
    nz=(z-.103)/.050**2
    dz_dz=1-.014/.050*e if z>.103 else 1
    dz_dx=.028*x/.020**2*e*height
    tongue_normals.append(tuple(Vector((x/.105**2-dz_dx*nz/dz_dz,(y-.150)/.045**2,nz/dz_dz)).normalized()))
    vert.co.z-=.014*e*height
tongue.data.update(); tongue.data.normals_split_custom_set_from_vertices(tongue_normals)

def tooth(name,x,upper):
    c=(x,.146,.206) if upper else (x,.190,.103)
    r=(.024,.018,.030) if upper else (.025,.018,.026)
    return pebble(name,c,r,4,part="brow" if upper else "jaw",taper=.32 if upper else -.30,bend=-.011 if upper else .004,round_contour=True)
for s in (-1,1):
    tooth("tooth_top",s*.070,True); tooth("tooth_bottom",s*.069,False)

# One continuous organic bent leg per side/pair, colored across its length.
# Caps are rounded and shaded with custom normals, not faceted primitive boots.
PIVOTS={}; FEET={}
for i,(y,hipx,footx,dy) in enumerate(((.092,.134,.151,.020),(-.038,.146,.191,.005),(-.152,.113,.106,-.010))):
    for side,key in ((-1,"l"),(1,"r")):
        name="leg_%d_%s"%(i,key); hip=Vector((side*hipx,y,.098 if i==0 else .108)); end=Vector((side*footx,y+dy,.032))
        d=end-hip; axis=d.normalized(); right=Vector((0,1,0)).cross(axis).normalized(); other=axis.cross(right).normalized()
        rot=Vector((0,0,1)).rotation_difference(axis).to_matrix()
        joint=blob(name+"_joint",tuple(hip),(.029,.028,.030),6,n=8,rings=3,part=name)
        # Discard joint triangles entirely buried in the body, retaining the
        # visible eight-sided joint contour rather than reducing its sides.
        bm=bmesh.new(); bm.from_mesh(joint.data)
        def buried(p):
            return (p.x/.162)**2+((p.y+.055)/.120)**2+((p.z-.140)/.108)**2<.98
        hidden=[f for f in bm.faces if all(buried(v.co) for v in f.verts)]
        bmesh.ops.delete(bm,geom=hidden,context="FACES")
        bm.to_mesh(joint.data); bm.free(); joint.data.update()
        joint.data.normals_split_custom_set_from_vertices([tuple(Vector(((v.co.x-hip.x)/.029**2,(v.co.y-hip.y)/.028**2,(v.co.z-hip.z)/.030**2)).normalized()) for v in joint.data.vertices])
        sleeve=blob(name+"_sleeve",tuple(hip+d*.46),(.034,.032,.046),0,n=12,rings=4,part=name,rotation=rot)
        for loop in sleeve.data.uv_layers.active.data:
            u,v=loop.uv
            loop.uv=(u,.47+.014*(v*2)) # clean gold sleeve, no freckle pattern
        foot=pebble(name+"_foot",tuple(end),(.035,.032,.035),5,part=name,rotation=rot,round_contour=True)
        # Remove only fully occluded faces. Whole-face containment is conservative:
        # no visible contour is simplified and partial intersections stay intact.
        proxies=[(joint,hip,Vector((.029,.028,.030)),Matrix.Identity(3)),
                 (sleeve,hip+d*.46,Vector((.034,.032,.046)),rot),
                 (foot,end,Vector((.035,.032,.035)),rot),
                 (body,Vector((0,-.055,.140)),Vector((.162,.120,.108)),Matrix.Identity(3))]
        for ob,center,radii,rotation in proxies[:3]:
            def inside(p,other_center,other_radii,other_rotation):
                q=other_rotation.inverted()@(p-other_center)
                return sum((q[a]/other_radii[a])**2 for a in range(3))<.90
            bm=bmesh.new(); bm.from_mesh(ob.data)
            hidden=[f for f in bm.faces if any(other is not ob and all(inside(v.co,c,r,rot2) for v in f.verts) for other,c,r,rot2 in proxies)]
            bmesh.ops.delete(bm,geom=hidden,context="FACES")
            bm.to_mesh(ob.data); bm.free(); ob.data.update()
            normals=[]
            for vertex in ob.data.vertices:
                local=rotation.inverted()@(vertex.co-center)
                normals.append(tuple((rotation@Vector(tuple(local[a]/radii[a]**2 for a in range(3)))).normalized()))
            ob.data.normals_split_custom_set_from_vertices(normals)
        low=min(v.co.z for v in foot.data.vertices)
        # The whole assembled foot rests on the reference ground plane.
        for ob in (joint,sleeve,foot):
            for vert in ob.data.vertices: vert.co.z-=low
        PIVOTS[name]=tuple(hip); FEET[name]=(end.x,end.y,0)

def after_join():
    for p,pt in PIVOTS.items():
        hb.set_origin(hb.get(p),pt); hb.attach(hb.get(p),hb.get("body"))
        hb.empty("pt_foot_"+p[4:],FEET[p],parent=hb.get(p))
    for p in ("shell","brow","jaw"):
        hb.set_origin(hb.get(p),(0,.055 if p!="shell" else -.03,.157)); hb.attach(hb.get(p),hb.get("body"))
    hb.empty("pt_mouth",(0,.24,.151),parent=hb.get("body"))
    for o in bpy.context.scene.objects:
        if o.type=="MESH":
            o.data.materials.clear(); o.data.materials.append(MAT)
            for p in o.data.polygons: p.material_index=0
    bpy.context.scene["reference"]="output/concepts/tutorial_alien_b_turnaround.png"
    bpy.context.scene["revision"]="v9: bowed shell profiles, connected U-mouth rim, outside oral front-leg roots, contour-focused tongue latitude sampling"





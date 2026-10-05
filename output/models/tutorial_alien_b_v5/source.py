"""Reference-shaped rebuild. Front +Y, meters, no subdivision modifiers.
Build through tools/blender.ps1 model models/src/tutorial_alien_b_v5.py --no-preview.
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
        band=(yy>.85)&(yy<.92)&(xx>.06)&(xx<.94)
        tile[band]=.6*tile[band]+.4*np.array([1,.87,.48])
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
    if k==3:
        tile=np.broadcast_to(rgb,(128,128,3)).copy()*(.88+.12*yy[...,None])
        # The two rounded lobes form one real center crease; no duplicated painted grooves.
    if k==5:
        spot=np.exp(-(((xx-.33)/.11)**2+((yy-.71)/.18)**2))
        tile+=spot[...,None]*.16
    if k==6:
        spot=np.exp(-(((xx-.36)/.16)**2+((yy-.78)/.11)**2))
        tile=tile*(1-.55*spot[...,None])+np.array([.77,.97,.89])*(.55*spot[...,None])
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

def blob(name,c,r,k,n=10,rings=5,part=None,clamp=None,rotation=None):
    vs=[(0,0,-r[2])]
    for j in range(1,rings):
        a=-math.pi/2+math.pi*j/rings
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
def puffy_shell(name,width,zbase,zarch,ybase,yarch,ry0,ry1,rz0,rz1,slope,nx=14,cross=10):
    vs=[]; uv=[]; ns=[]
    def point(t,a):
        cs=math.cos(t)
        depth=(ry0+ry1*cs)*math.cos(a)
        return Vector((width*math.sin(t)+.008*math.sin(t)*math.sin(a),
                       ybase+yarch*cs+depth,
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
    return mesh(name,vs,fs,0,uv,part="shell",normals=ns)

# Full rounded shoulders stay behind the oral pocket. No planar chest clamp
# or exposed cut-out boundary is needed.
body=blob("body",(0,-.055,.140),(.162,.120,.108),1,n=16,rings=6)
puffy_shell("plate_rear",.125,.120,.030,-.171,.019,.010,.040,.012,.016,.90,nx=12,cross=8)
puffy_shell("plate_middle",.190,.105,.120,-.030,-.080,.020,.055,.015,.033,.55,nx=12,cross=10)
puffy_shell("plate_front",.162,.170,.131,-.020,.055,.020,.070,.018,.015,-.10,nx=14,cross=10)

# Closed swept oval brow. Its side silhouette is an oval, not a flat wedge.
nx,cross=12,16; vs=[]; uv=[]; ns=[]
def brow_point(t,a):
    cs=math.cos(t); radial=Vector((math.sin(t),0,cs))
    center=Vector((.143*math.sin(t),.010+.125*cs**2.4,.130+.115*cs))
    depth=(.014+.079*cs**2)*math.cos(a)
    return center+radial*((.012+.010*cs)*math.sin(a))+Vector((0,depth,-.25*depth))
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
for j,(z,y,rx,ry) in enumerate(((.277,.090,.027,.038),(.299,.073,.028,.036),(.329,.040,.020,.034),(.348,.021,.010,.023),(.356,.010,.002,.006))):
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
    blob("nub_front",(s*.108,.044,.302),(.025,.025,.020),6,n=12,rings=4,part="shell")
    blob("nub_middle",(s*.157,-.030,.215),(.024,.024,.023),6,n=10,rings=4,part="shell")
blob("nub_back",(0,-.200,.202),(.024,.016,.022),6,n=12,rings=4,part="shell")

# Mouth bowl sits inside the golden rim; corners tuck back towards the cheeks.
n=20; vs=[]; uv=[]
for radius,dep in ((1,.0),(.70,-.042),(.30,-.073)):
    for i in range(n):
        t=2*math.pi*i/n; ct=math.cos(t); st=math.sin(t)
        x=.136*radius*math.copysign(abs(ct)**.65,ct)
        z=.146+.077*radius*st
        y=.198-.100*ct**2*radius+.002*max(0,-st)*radius+dep
        vs.append((x,y,z)); uv.append((.5+.47*radius*math.cos(t),.5+.47*radius*math.sin(t)))
vs.append((0,.084,.144)); uv.append((.5,.5)); fs=[]
for j in range(2):
    for i in range(n):
        a=j*n+i; b=j*n+(i+1)%n; fs.append((a,b,b+n,a+n))
fs += [(2*n+i,2*n+(i+1)%n,3*n) for i in range(n)]
mouth_normals=[tuple(Vector((-x/.118,1.6,-(z-.144)/.074)).normalized()) for x,y,z in vs]
mesh("mouth_bowl",vs,fs,2,uv,part="body",normals=mouth_normals)

# Curved inner cheek walls close the lateral oral pocket. A front-only bowl
# left a see-through gray gap in profile, unlike the closed mouth in the art.
oral=[(.055,.146,.126),(.070,.169,.119),(.122,.193,.103),(.151,.196,.079),
      (.179,.151,.078),(.170,.113,.080),(.125,.103,.108),(.072,.129,.126)]
for side in (-1,1):
    vs=[(side*x,y,z) for y,z,x in oral]+[(side*.120,.118,.151)]
    fs=[(i,(i+1)%8,8) for i in range(8)]
    uv=[((y-.055)/.141,(z-.103)/.103) for x,y,z in vs]
    ns=[tuple(Vector((-side,-.33,0)).normalized())]*len(vs)
    mesh("inner_cheek",vs,fs,2,uv,part="body",normals=ns)

# Golden lower jaw, a full-volume bowl-shaped U. Broad chin visible in profile.
n=14; cross=12; vs=[]; uv=[]; ns=[]
def jaw_center(t):
    return Vector((.126*math.cos(t),.055+.125*max(0,-math.sin(t))**1.3,.145+.086*math.sin(t)))
for j in range(n+1):
    t=math.pi+.10+(math.pi-.20)*j/n; center=jaw_center(t)
    radial=Vector((math.cos(t),0,math.sin(t)))
    depth=Vector((0,1,0))
    for q in range(cross):
        a=2*math.pi*q/cross
        radius=.014+.012*max(0,-math.sin(t))
        p=center+radial*(radius*math.cos(a))+depth*(.032*math.sin(a))
        vs.append(tuple(p)); uv.append((j/n,(math.cos(a)+1)/2))
        ns.append(tuple((radial*(math.cos(a)/radius)+depth*(math.sin(a)/.032)).normalized()))
fs=[]
for j in range(n):
    for q in range(cross):
        a=j*cross+q; b=j*cross+(q+1)%cross; fs.append((a,b,b+cross,a+cross))
fs += [tuple(range(cross-1,-1,-1)),tuple(range(n*cross,n*cross+cross))]
mesh("jaw",vs,fs,7,uv,normals=ns)
tongue=blob("tongue",(0,.134,.099),(.100,.046,.041),3,n=16,rings=5,part="jaw")
for vert in tongue.data.vertices:
    # One continuous tongue with a subtle central notch, not two disconnected buns.
    vert.co.z-=.010*math.exp(-(vert.co.x/.020)**2)*max(0,(vert.co.z-.099)/.041)

def tooth(name,x,upper):
    z=[.216,.202,.179,.167,.160] if upper else [.075,.087,.111,.122,.127]
    rad=[.019,.023,.021,.012,.004] if upper else [.020,.026,.024,.014,.004]
    depth=[.118,.130,.152,.160,.162] if upper else [.172,.173,.174,.175,.176]
    vs=[]; uv=[]; ns=[]; n=12
    for j in range(5):
        for i in range(n):
            t=2*math.pi*i/n
            vs.append((x+rad[j]*math.cos(t),depth[j]+rad[j]*.66*math.sin(t),z[j]))
            uv.append((.5+.45*math.cos(t),j/4))
            before=max(0,j-1); after=min(4,j+1)
            slope=-(rad[after]-rad[before])/(z[after]-z[before])
            ns.append(tuple(Vector((math.cos(t),math.sin(t)/.66,slope)).normalized()))
    fs=[]
    for j in range(4):
        for i in range(n):
            a=j*n+i; b=j*n+(i+1)%n; fs.append((a,b,b+n,a+n))
    fs += [tuple(range(n-1,-1,-1)),tuple(range(4*n,5*n))]
    mesh(name,vs,fs,4,uv,part="brow" if upper else "jaw",normals=ns)
for s in (-1,1):
    tooth("tooth_top",s*.070,True); tooth("tooth_bottom",s*.069,False)

# One continuous organic bent leg per side/pair, colored across its length.
# Caps are rounded and shaded with custom normals, not faceted primitive boots.
PIVOTS={}; FEET={}
for i,(y,hipx,footx,dy) in enumerate(((.092,.122,.151,.020),(-.038,.146,.191,.005),(-.152,.113,.106,-.010))):
    for side,key in ((-1,"l"),(1,"r")):
        name="leg_%d_%s"%(i,key); hip=Vector((side*hipx,y,.108)); end=Vector((side*footx,y+dy,.032))
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
        foot=blob(name+"_foot",tuple(end),(.032,.031,.037),5,n=12,rings=5,part=name,rotation=rot)
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
    bpy.context.scene["revision"]="v5: reference-landmarked dorsal plate overlap, lower rounded chin and cheek-connected oral pocket"





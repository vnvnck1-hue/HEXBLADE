"""Reference-shaped rebuild. Front +Y, meters, no subdivision modifiers.
Build through tools/blender.ps1 model models/src/tutorial_alien_b_v2.py --no-preview.
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
        groove=np.exp(-((xx-.5)/.025)**2)*np.clip((yy-.25)*2,0,.7)
        tile*=1-.16*groove[...,None]
    if k==5:
        spot=np.exp(-(((xx-.33)/.11)**2+((yy-.71)/.18)**2))
        tile+=spot[...,None]*.16
    if k==6:
        spot=np.exp(-(((xx-.36)/.16)**2+((yy-.78)/.11)**2))
        tile=tile*(1-.55*spot[...,None])+np.array([.77,.97,.89])*(.55*spot[...,None])
    arr[(k//4)*128:(k//4+1)*128,(k%4)*128:(k%4+1)*128,:3]=np.clip(tile,0,1)
im=bpy.data.images.new("B_painted_atlas_512x256",W,H,alpha=True)
im.pixels.foreach_set(arr.ravel()); im.filepath_raw=os.path.join(ROOT,"assets","models","tutorial_alien_b_atlas.png")
im.file_format="PNG"; im.save(); im.pack()
MAT=hb.mat("B_cartoon_atlas","#ffffff",rough=1)
tx=MAT.node_tree.nodes.new("ShaderNodeTexImage"); tx.name="Painted_Atlas"; tx.image=im
MAT.node_tree.links.new(tx.outputs["Color"],MAT.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])

def uv_tile(k,u,v):
    return ((k%4+.035+.93*u)/4,(k//4+.035+.93*v)/2)

def mesh(name,vs,fs,k,uv=None,part=None,normals=None,face_tiles=None):
    me=bpy.data.meshes.new(name); me.from_pydata(vs,[],fs); me.update()
    bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(me); bm.free()
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
    nx,ny=12,6; vs=[]; uv=[]; normals=[]
    def point(u,v):
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
            normals.append(tuple(normal))
    half=len(vs)
    # Thick rim only; hidden central underside omitted.
    vs += [(x,y,z-.012) for x,y,z in vs]; uv += uv.copy()
    normals += normals.copy()
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
    return mesh(name,vs,fs,0,uv,part="shell",normals=normals)

blob("body",(0,-.035,.140),(.162,.120,.108),1,n=12,rings=5,clamp=.026)
shell("plate_rear",[(-.195,.105,-.200,.101,.122),(-.182,.164,-.185,.105,.145),(-.139,.215,-.140,.108,.155),(-.102,.225,-.080,.111,.155)])
shell("plate_middle",[(-.155,.220,-.127,.110,.150),(-.110,.260,-.095,.119,.183),(-.075,.300,-.040,.145,.199),(.030,.290,.060,.163,.191)])
shell("plate_front",[(-.018,.300,-.070,.203,.143),(.000,.340,-.044,.166,.158),(.050,.316,.000,.169,.170),(.090,.270,.015,.165,.160)])

# Broad thick brow: top surface, curved front fascia, inner surface and closed sides.
nx,ny=12,3; vs=[]; uv=[]
for inner in (False,True):
    for j in range(ny+1):
        v=j/ny
        for i in range(nx+1):
            u=i/nx; t=(u-.5)*2.82; cs=math.cos(t)
            width=.156 if not inner else .142
            x=width*math.sin(t)
            y=.041+v*(.090+.095*cs)
            rise=(.130-.031*v+.021*math.sin(v*math.pi)) if not inner else (.100-.020*v+.010*math.sin(v*math.pi))
            z=.141+rise*cs
            vs.append((x,y,z)); uv.append((u,1-v))
row=nx+1; half=row*(ny+1); fs=[]
for j in range(ny):
    for i in range(nx):
        a=j*row+i; fs.append((a,a+1,a+1+row,a+row)); fs.append((a+half+row,a+half+row+1,a+half+1,a+half))
for j in (0,ny):
    for i in range(nx):
        a=j*row+i; fs.append((a,a+half,a+half+1,a+1))
for i in (0,nx):
    for j in range(ny):
        a=j*row+i; fs.append((a,a+row,a+row+half,a+half))
mesh("brow",vs,fs,0,uv)

# A rounded center crest with bulging cheeks rather than a triangular prism.
blob("crest",(0,.043,.316),(.031,.044,.040),0,n=10,rings=6,part="shell")
for s in (-1,1):
    blob("nub_front",(s*.108,.020,.290),(.025,.025,.020),6,n=8,rings=4,part="shell")
    blob("nub_middle",(s*.160,-.015,.196),(.022,.024,.019),6,n=10,rings=4,part="shell")
blob("nub_back",(0,-.153,.187),(.024,.016,.022),6,n=12,rings=4,part="shell")

# Mouth bowl sits inside the golden rim; corners tuck back towards the cheeks.
n=16; vs=[]; uv=[]
for radius,dep in ((1,.0),(.70,-.080),(.30,-.126)):
    for i in range(n):
        t=2*math.pi*i/n; x=.136*radius*math.cos(t); z=.151+.078*radius*math.sin(t)
        y=.210-.025*math.sin(t)-.065*abs(math.cos(t))*radius+dep
        vs.append((x,y,z)); uv.append((.5+.47*radius*math.cos(t),.5+.47*radius*math.sin(t)))
vs.append((0,.067,.151)); uv.append((.5,.5)); fs=[]
for j in range(2):
    for i in range(n):
        a=j*n+i; b=j*n+(i+1)%n; fs.append((a,b,b+n,a+n))
fs += [(2*n+i,2*n+(i+1)%n,3*n) for i in range(n)]
mouth_normals=[tuple(Vector((-x/.136,1.6,-(z-.151)/.078)).normalized()) for x,y,z in vs]
mesh("mouth_bowl",vs,fs,2,uv,part="body",normals=mouth_normals)

# Golden lower jaw, a full-volume bowl-shaped U. Broad chin visible in profile.
n=16; cross=8; vs=[]; uv=[]; ns=[]
for j in range(n+1):
    t=math.pi+math.pi*j/n; radial=Vector((math.cos(t),0,math.sin(t)))
    center=Vector((.138*math.cos(t),.080+.111*max(0,-math.sin(t)),.145+.087*math.sin(t)))
    for q in range(cross):
        a=2*math.pi*q/cross
        p=center+radial*(.021*math.cos(a))+Vector((0,.043*math.sin(a),0))
        vs.append(tuple(p)); uv.append((j/n,(math.cos(a)+1)/2))
        ns.append(tuple((radial*math.cos(a)+Vector((0,math.sin(a),0))).normalized()))
fs=[]
for j in range(n):
    for q in range(cross):
        a=j*cross+q; b=j*cross+(q+1)%cross; fs.append((a,b,b+cross,a+cross))
fs += [tuple(range(cross-1,-1,-1)),tuple(range(n*cross,n*cross+cross))]
mesh("jaw",vs,fs,7,uv,normals=ns)
blob("tongue",(0,.164,.102),(.101,.063,.043),3,n=12,rings=5,part="jaw")

def tooth(name,x,upper):
    z=[.221,.210,.184,.173] if upper else [.069,.082,.105,.116]
    rad=[.019,.023,.019,.007] if upper else [.020,.026,.022,.008]
    vs=[]; uv=[]; ns=[]; n=12
    for j in range(4):
        for i in range(n):
            t=2*math.pi*i/n
            vs.append((x+rad[j]*math.cos(t),(.228 if upper else .226)+.004*j+rad[j]*.66*math.sin(t),z[j]))
            uv.append((.5+.45*math.cos(t),j/3))
            ns.append(tuple(Vector((math.cos(t),math.sin(t)/.66,(-1 if upper else 1)*j/3*.8)).normalized()))
    fs=[]
    for j in range(3):
        for i in range(n):
            a=j*n+i; b=j*n+(i+1)%n; fs.append((a,b,b+n,a+n))
    fs += [tuple(range(n-1,-1,-1)),tuple(range(3*n,4*n))]
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
        sleeve=blob(name+"_sleeve",tuple(hip+d*.46),(.034,.032,.046),0,n=8,rings=4,part=name,rotation=rot)
        foot=blob(name+"_foot",tuple(end),(.028,.027,.034),5,n=12,rings=4,part=name,rotation=rot)
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
    bpy.context.scene["revision"]="v2: reference-shaped volumetric shell, curved thick jaw, bent organic legs"

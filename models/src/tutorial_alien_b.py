"""Tiny six-legged tutorial alien B, from the saved cartoon turnaround.

Build: tools/blender.ps1 model models/src/tutorial_alien_b.py --no-preview
Studio: tools/blender.ps1 wait -b --python tools/blender/tutorial_alien_b_studio.py
Units: meters; front +Y. No subdivision, bevel, displacement or baked animation.
"""
import os
import random
import bmesh
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "output", "models", "tutorial_alien_b")
os.makedirs(OUT, exist_ok=True)
TEX = os.path.join(ROOT, "assets", "models", "tutorial_alien_b_atlas.png")
PALETTE = ["#ffc448", "#48aaa7", "#8d3444", "#ef7065",
           "#fff0c7", "#69655e", "#60cbc0", "#eec579"]


def atlas():
    """Eight padded painted tiles, 128px each; spots cost zero polygons."""
    a = np.ones((256, 512, 4), dtype=np.float32)
    yy, xx = np.mgrid[0:128, 0:128] / 127.0
    rng = random.Random(83)
    for k, col in enumerate(PALETTE):
        rgb = np.array([int(col[j:j + 2], 16) / 255.0 for j in (1, 3, 5)])
        shade = (0.90 + 0.12 * yy)[:, :, None]
        tile = np.clip(rgb * shade, 0, 1)
        if k == 0:
            # Thick ochre lower borders, yellow upper brush edge, scattered soft spots.
            edge = (yy < .07) | (xx < .035) | (xx > .965)
            tile[edge] *= np.array([.81, .70, .58])
            tile[(yy > .91) & (yy < .96)] = np.array([1., .85, .40])
            for _ in range(18):
                cx, cy = rng.uniform(.09, .91), rng.uniform(.13, .86)
                rx, ry = rng.uniform(.018, .052), rng.uniform(.025, .062)
                mask = ((xx-cx)/rx)**2 + ((yy-cy)/ry)**2 < 1
                tile[mask] = .65*tile[mask]+.35*np.array([.90, .57, .14])
        if k == 1:
            tile[(yy < .10) | (xx < .035) | (xx > .965)] *= .85
        if k == 5:
            mask = ((xx-.35)/.10)**2 + ((yy-.70)/.16)**2 < 1
            tile[mask] = .60*tile[mask] + .40*np.array([.65,.63,.57])
        if k == 6:
            mask = ((xx-.35)/.14)**2 + ((yy-.73)/.10)**2 < 1
            tile[mask] = np.array([.74, .95, .86])
        x, y = (k % 4)*128, (k//4)*128
        a[y:y+128,x:x+128,:3] = tile
    im = bpy.data.images.new("B_painted_atlas_512x256", 512, 256, alpha=True)
    im.pixels.foreach_set(a.ravel())
    im.filepath_raw = TEX
    im.file_format = "PNG"
    im.save()
    im.pack()
    return im


IMAGE = atlas()
MAT = hb.mat("B_cartoon_atlas", "#ffffff", rough=.95)
nt = MAT.node_tree
tex = nt.nodes.new("ShaderNodeTexImage")
tex.name = "Painted_Atlas"
tex.image = IMAGE
tex.interpolation = "Linear"
nt.links.new(tex.outputs["Color"], nt.nodes.get("Principled BSDF").inputs["Base Color"])


def tile_uv(k, u, v):
    return ((k % 4 + .035 + .93*u)/4, (k//4 + .035 + .93*v)/2)


def mesh(name, vs, fs, color, uv=None, part=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(vs, [], fs)
    me.update()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    hb.collection().objects.link(o)
    me.materials.append(MAT)
    layer = me.uv_layers.new(name="PaintedAtlas")
    if uv is None:
        lo = np.min(np.array(vs), axis=0)
        hi = np.max(np.array(vs), axis=0)
        uv = [((p[0]-lo[0])/max(hi[0]-lo[0],.0001),
               (p[2]-lo[2])/max(hi[2]-lo[2],.0001)) for p in vs]
    for p in me.polygons:
        p.use_smooth = True
        for li in p.loop_indices:
            layer.data[li].uv = tile_uv(color, *uv[me.loops[li].vertex_index])
    o["hb_part"] = part or name
    return o


def blob(name, c, r, color, n=8, rings=4, part=None, clamp_y=None):
    # Shared poles, no degenerate triangles or hidden subdivision modifiers.
    vs = [(c[0], c[1], c[2]-r[2])]
    for j in range(1, rings):
        a = -math.pi/2 + math.pi*j/rings
        for i in range(n):
            t = 2*math.pi*i/n
            y = c[1]+r[1]*math.cos(a)*math.sin(t)
            if clamp_y is not None:
                y = min(y, clamp_y)
            vs.append((c[0]+r[0]*math.cos(a)*math.cos(t), y, c[2]+r[2]*math.sin(a)))
    vs.append((c[0],c[1],c[2]+r[2]))
    fs = [(0,1+(i+1)%n,1+i) for i in range(n)]
    for j in range(rings-2):
        for i in range(n):
            a=1+j*n+i; b=1+j*n+(i+1)%n
            fs.append((a,b,b+n,a+n))
    top=len(vs)-1; row=1+(rings-2)*n
    fs += [(row+i,row+(i+1)%n,top) for i in range(n)]
    return mesh(name,vs,fs,color,part=part)


def plate(name, y0, y1, width, base, rise, lift=0, part="shell"):
    # A closed 10-sided scalloped arch; only 3 length spans.
    nx, ny=8,2
    vs=[]; uv=[]
    for inner in (False,True):
        for j in range(ny+1):
            v=j/ny
            for i in range(nx+1):
                u=i/nx; t=(u-.5)*2.65
                w=width*(.90+.10*math.sin(v*math.pi))
                x=w*math.sin(t)
                y=y0+(y1-y0)*v+.016*abs(math.sin(t))
                z=base+rise*math.cos(t)+lift*(1-v)+.012*math.sin(v*math.pi)-(.025 if inner else 0)
                vs.append((x,y,z)); uv.append((u,v))
    row=nx+1; half=row*(ny+1); fs=[]
    for j in range(ny):
        for i in range(nx):
            a=j*row+i
            fs.append((a,a+1,a+1+row,a+row))
            # Back-plate undersides are hidden inside the body; keep only the exposed brow underside.
            if part == "brow":
                fs.append((a+half+row,a+half+1+row,a+half+1,a+half))
    for j in range(ny):
        for i in (0,nx):
            a=j*row+i; fs.append((a,a+row,a+row+half,a+half))
    for j in (0,ny):
        for i in range(nx):
            a=j*row+i; fs.append((a,a+half,a+1+half,a+1))
    return mesh(name,vs,fs,0,uv,part=part)


# Turquoise body ends behind the mouth so it never fills the open cavity.
blob("body",(0,-.052,.150),(.157,.160,.129),1,n=10,rings=4,clamp_y=.035)
plate("shell_rear",-.213,-.078,.158,.135,.133,lift=-.011)
plate("shell_middle",-.128,.008,.171,.165,.137,lift=-.014)
plate("shell_front",-.025,.104,.169,.176,.138,lift=.008)
plate("brow",.066,.228,.174,.161,.128,lift=.018,part="brow")
# Rear/front bumps are sensory shell decorations, never eyes.
for s in (-1,1):
    blob("bump_front",(s*.124,.055,.276),(.025,.026,.018),6,n=8,rings=3,part="shell")
    blob("bump_middle",(s*.133,-.09,.258),(.021,.022,.015),6,n=6,rings=3,part="shell")
blob("bump_rear",(0,-.202,.202),(.023,.018,.020),6,n=6,rings=3,part="shell")
# Tiny center crest: 12 triangles, broad toy-like taper, no spiky horns.
mesh("crest",[(-.021,.014,.297),(.021,.014,.297),(-.019,.079,.286),(.019,.079,.286),
              (-.009,.035,.356),(.009,.035,.356),(-.010,.067,.333),(.010,.067,.333)],
     [(0,2,3,1),(0,1,5,4),(4,5,7,6),(2,6,7,3),(0,4,6,2),(1,3,7,5)],0,part="shell")

# Deep burgundy bowl, simple coral tongue, four isolated blunt teeth.
N=16; vs=[]; uv=[]
for r,y in ((1,.207),(.67,.068)):
    for i in range(N):
        t=2*math.pi*i/N
        vs.append((.139*r*math.cos(t),y,.155+.087*r*math.sin(t)))
        uv.append((.5+.48*r*math.cos(t),.5+.48*r*math.sin(t)))
vs.append((0,.04,.155)); uv.append((.5,.5))
fs=[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
fs += [(N+i,N+(i+1)%N,2*N) for i in range(N)]
mesh("mouth",vs,fs,2,uv,part="body")

# Lower golden jaw rim, an open U with a square section instead of a heavy torus.
vs=[]; uv=[]; steps=10
for j in range(steps+1):
    t=math.pi+math.pi*j/steps
    center=Vector((.143*math.cos(t),.208+.011*(-math.sin(t)),.153+.090*math.sin(t)))
    radial=Vector((math.cos(t),0,math.sin(t)))
    for k in range(4):
        a=2*math.pi*k/4+math.pi/4
        p=center+radial*(.019*math.cos(a))+Vector((0,.017*math.sin(a),0))
        vs.append(tuple(p)); uv.append((j/steps,k/3))
fs=[]
for j in range(steps):
    for k in range(4):
        a=j*4+k; b=j*4+(k+1)%4
        fs.append((a,b,b+4,a+4))
fs += [(3,2,1,0),tuple(range(steps*4,steps*4+4))]
mesh("jaw",vs,fs,7)
blob("tongue",(0,.147,.099),(.083,.068,.025),3,n=8,rings=4,part="jaw")
for s in (-1,1):
    blob("tooth_upper",(s*.077,.197,.219),(.026,.019,.034),4,n=6,rings=4,part="brow")
    blob("tooth_lower",(s*.076,.210,.101),(.026,.019,.030),4,n=6,rings=4,part="jaw")

PIVOTS={}
for i,y in enumerate((.102,-.019,-.143)):
    for s,k in ((-1,"l"),(1,"r")):
        p="leg_%d_%s"%(i,k)
        offset=(i-1)*.023
        hip=(s*(.133+offset),y,.101)
        blob(p+"_joint",hip,(.027,.031,.032),6,n=6,rings=3,part=p)
        blob(p+"_sleeve",(s*(.175+offset),y+.017,.070),(.036,.040,.059),0,n=8,rings=3,part=p)
        blob(p+"_foot",(s*(.199+offset),y+.032,.032),(.026,.039,.032),5,n=8,rings=4,part=p)
        PIVOTS[p]=hip


def after_join():
    # Shared one-atlas material after part joining; preserve positions while parenting.
    for p,pt in PIVOTS.items():
        hb.set_origin(hb.get(p),pt)
        hb.attach(hb.get(p),hb.get("body"))
        foot=hb.get(p).matrix_world.translation.copy()
        hb.empty("pt_foot_"+p[4:],(foot.x+( .066 if foot.x>0 else -.066),foot.y+.032,0),parent=hb.get(p))
    for p in ("shell","brow","jaw"):
        hb.set_origin(hb.get(p),(0,.055 if p!="shell" else -.03,.157))
        hb.attach(hb.get(p),hb.get("body"))
    hb.empty("pt_mouth",(0,.224,.155),parent=hb.get("body"))
    for o in list(bpy.context.scene.objects):
        if o.type=="MESH":
            o.data.materials.clear(); o.data.materials.append(MAT)
            for poly in o.data.polygons: poly.material_index=0
    bpy.context.scene["reference"]="output/concepts/tutorial_alien_b_turnaround.png"
    bpy.context.scene["dimensions_note"]="0.356m high, 6 legs, 4 blunt teeth, no eyes"


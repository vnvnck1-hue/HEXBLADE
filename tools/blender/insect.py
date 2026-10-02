"""Reproducible reference-inspired insect meshes. No downloaded meshes/textures.
All articulation uses identity-axis empties; keep named pivots for Godot IK.
"""
import math
from mathutils import Vector


def build(hb, bpy, kind):
    ant = kind == "ant"
    shell = hb.mat("chitin", "#b44a27" if ant else "#ead6af", rough=0.32)
    light = hb.mat("chitin_edge", "#e77d42" if ant else "#fff0d0", rough=0.4)
    dark = hb.mat("joint", "#4b201e" if ant else "#756457", rough=0.75)
    belly = hb.mat("belly", "#733025" if ant else "#b5a18d", rough=0.65)
    black = hb.mat("jaw", "#231b1a", rough=0.34)
    eye = hb.mat("eyes", "#160f11", rough=0.13)
    gleam = hb.mat("eye_gleam", "#fff6d1", rough=0.2)
    amber = hb.mat("sense_tip", "#ffc178" if ant else "#8ebaa4", rough=0.35)
    root = hb.empty("body")
    joints = {}
    parts = {}

    def joint(name, pos, parent=root):
        o = hb.empty(name, pos, parent=parent, size=0.075)
        joints[name] = o
        return o

    def sphere(name, pos, scale, material, parent, seg=16, rings=8):
        o = hb.sphere(name, r=1, loc=pos, scale=scale, mat=material, seg=seg, rings=rings, part=parent.name+"_mesh")
        parts[parent.name+"_mesh"] = parent
        return o

    def tube(name, points, radius, material, parent):
        o = hb.tube(name, points, r=radius, mat=material, verts=6, part=parent.name+"_mesh")
        parts[parent.name+"_mesh"] = parent
        return o

    def spindle(name, a, b, radius, material, parent, width=1.0):
        a, b = Vector(a), Vector(b)
        o = sphere(name, (a+b)/2, (radius*width, radius, (b-a).length/2+radius*0.2), material, parent, 12, 8)
        o.rotation_euler = (b-a).to_track_quat("Z", "Y").to_euler()
        return o

    if ant:
        thorax = joint("thorax", (0, 0, 0.96))
        sphere("thorax_core", (0, 0, 1.02), (.31,.35,.46), belly, thorax)
        sphere("breastplate", (0,.17,1.13), (.28,.25,.38), shell, thorax)
        for side in (-1,1):
            sphere("breast_edge", (side*.19,.33,1.17), (.045,.032,.22), light, thorax,12,6)
        # Waist and a pointed, striped gaster tilted above the ground.
        joint("abdomen_0", (0,-.32,1.0), thorax)
        for i in range(4):
            p = (0,-.44-i*.22,1.01+i*.09)
            n = joint("abdomen_%d" % (i+1), p, joints["abdomen_0"])
            r = [.28,.36,.31,.17][i]
            sphere("gaster_seam", p, (r,.22,r*.88), dark, n)
            sphere("gaster_plate", (0,p[1]-.027,p[2]+.02), (r*.98,.184,r*.90), shell, n)
            for side in (-1,1):
                sphere("gaster_glint", (side*r*.57,p[1]+.03,p[2]+r*.65), (.032,.1,.026), light,n,12,6)
        tube("sting", [(0,-1.14,1.29),(0,-1.38,1.43),(0,-1.47,1.58)], .045, black,joints["abdomen_4"])
        head_pos = (0,.40,1.47)
        head = joint("head", head_pos, thorax)
        sphere("head_chitin", head_pos, (.46,.44,.31),shell,head,24,12)
        sphere("forehead", (0,.48,1.66), (.32,.28,.1),light,head)
        sphere("clypeus", (0,.76,1.35), (.30,.12,.13),dark,head)
        eyes_y, eyes_z = .61,1.54
        jaw_y, jaw_z = .75,1.32
        antenna_base = (.21,.42,1.68)
        antenna_pts = [(.21,.42,1.68),(.31,.68,1.99),(.51,.92,2.23),(.62,1.08,2.32)]
        for row, y in enumerate((.22,-.04,-.28)):
            for side in (-1,1):
                k = "%s%d" % ("l" if side < 0 else "r", row)
                a=(side*.23,y,.90)
                b=(side*.59,y+(.10 if row==0 else -.08),.40)
                c=(side*.67,y+(.39 if row==0 else -.38 if row==2 else -.02),.045)
                h=joint("leg_%s_hip"%k,a,thorax)
                kne=joint("leg_%s_knee"%k,b,h)
                ft=joint("leg_%s_foot"%k,c,kne)
                sphere("coxa",a,(.1,.12,.12),dark,h)
                spindle("femur",a,b,.088,shell,h,1.28)
                sphere("knee",b,(.09,.095,.09),dark,kne)
                spindle("tibia",b,c,.058,shell,kne)
                tip=(c[0],c[1]+.14,.027)
                spindle("claw",c,tip,.04,black,ft)
                hb.empty("pt_foot_%s"%k,(tip[0],tip[1],0),parent=ft,size=.05)
    else:
        thorax=joint("thorax",(0,0,.52))
        # Independent fat rings: long flexible belly, raised rump and small head.
        for i in range(6):
            y=.55-i*.32
            z=.55+math.sin(i/5*math.pi)*.16
            r=[.39,.51,.61,.64,.59,.44][i]
            n=joint("abdomen_%d"%i,(0,y,z),thorax)
            sphere("soft_ring",(0,y,z),(r,.28,r*.86),belly,n,20,12)
            sphere("ivory_plate",(0,y-.01,z+.065),(r*.995,.235,r*.86),shell,n,20,12)
            # Sculpted ridge, side speckles and cream crest read well at game scale.
            sphere("dorsal_ridge",(0,y,z+r*.79),(.22,.145,.055),light,n)
            for side in (-1,1):
                sphere("side_patch",(side*r*.92,y+.04,z),(.045,.125,.12),dark,n)
                sphere("spiracle",(side*r*.98,y+.03,z-.06),(.02,.034,.048),black,n,12,6)
                sphere("edge_glint",(side*r*.68,y+.02,z+r*.56),(.045,.13,.04),light,n,12,6)
        head_pos=(0,.90,.55)
        head=joint("head",head_pos,thorax)
        sphere("head_chitin",head_pos,(.36,.31,.29),shell,head,24,12)
        sphere("clypeus",(0,1.13,.42),(.26,.13,.15),dark,head)
        eyes_y,eyes_z=1.055,.64
        jaw_y,jaw_z=1.13,.39
        antenna_base=(.17,1.00,.77)
        antenna_pts=[(.17,1.00,.77),(.34,1.23,.91),(.51,1.46,1.00),(.62,1.62,1.06)]
        for row,y in enumerate((.49,.04,-.47)):
            for side in (-1,1):
                k="%s%d"%("l" if side<0 else "r",row)
                a=(side*[.30,.41,.48][row],y,.51)
                b=(side*[.50,.62,.68][row],y+.05,.22)
                c=(side*[.54,.65,.73][row],y+.15,.045)
                h=joint("leg_%s_hip"%k,a,joints["abdomen_%d"%row])
                kne=joint("leg_%s_knee"%k,b,h)
                ft=joint("leg_%s_foot"%k,c,kne)
                sphere("coxa",a,(.12,.12,.12),dark,h)
                spindle("femur",a,b,.1,shell,h,1.3)
                spindle("tibia",b,c,.063,dark,kne)
                spindle("claw",c,(c[0],c[1]+.10,.03),.05,black,ft)
                hb.empty("pt_foot_%s"%k,(c[0],c[1]+.10,0),parent=ft,size=.05)

    for side in (-1,1):
        s="l" if side<0 else "r"
        ex=side*(.35 if ant else .26)
        sphere("compound_eye",(ex,eyes_y,eyes_z),(.12,.11,.115) if ant else (.067,.064,.078),eye,head,16,10)
        sphere("eye_highlight",(ex-side*.027,eyes_y+.087,eyes_z+.055),(.025,.017,.026),gleam,head,12,6)
        # Crescent mandibles, independent hinges with a tooth at the tip.
        jaw=joint("jaw_"+s,(side*.18,jaw_y,jaw_z),head)
        pts=[(side*.18,jaw_y,jaw_z),(side*.25,jaw_y+.17,jaw_z-.08),(side*.14,jaw_y+.31,jaw_z-.12),(side*.035,jaw_y+.30,jaw_z-.075)]
        tube("mandible",pts,.07 if ant else .065,black,jaw)
        spindle("jaw_tooth",pts[-2],(side*.05,jaw_y+.23,jaw_z+.03),.036,light,jaw)
        # Three articulated lengths, bend at both base and distal joint.
        pts=[(p[0]*side,p[1],p[2]) for p in antenna_pts]
        par=head
        for i in range(3):
            a=joint("antenna_%s_%d"%(s,i),pts[i],par)
            spindle("feelers",pts[i],pts[i+1],.040-i*.008,shell if i%2==0 else dark,a)
            sphere("antenna_knuckle",pts[i],(.049,.049,.049),dark,a,12,6)
            par=a
        sphere("sensor_tip",pts[-1],(.059,.077,.060),amber,par,12,8)
    hb.empty("pt_mouth",(0,jaw_y+.30,jaw_z),parent=head,size=.06)
    hb.empty("pt_target",(0,0,.95),parent=root,size=.1)

    def finish():
        # Bake all mesh axes to identity before attaching; only empties animate.
        from mathutils import Matrix
        for name,parent in parts.items():
            obj=hb.get(name)
            hb.rebase(obj,Matrix.Translation(parent.matrix_world.translation))
            hb.attach(obj,parent)
        root["concept"]="Ember Mant" if ant else "Ivory Grub"
        root["animation_driver"]="res://scripts/insects/insect_motion.gd"
        root["units"]="meters; feet at Z=0; forward +Y"
    return finish

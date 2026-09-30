extends RefCounted
## Reference reconstruction. Front = -Z; Y up. All parts are real exportable meshes.
## Rear chassis is inferred; visible front shapes follow the supplied turnaround.

var mats: Dictionary = {}
var meshes := 0
var triangles := 0

func _init() -> void:
	for item in [["Ivory", "eee7ca", 0.12, 0.68], ["Inset", "c7c5b6", 0.20, 0.73], ["Edge", "89887c", 0.45, 0.48], ["Steel", "66665f", 0.65, 0.42], ["Graphite", "303330", 0.38, 0.67], ["Recess", "111713", 0.05, 0.85], ["Yellow", "f6dc28", 0.1, 0.35]]:
		var m := StandardMaterial3D.new()
		m.resource_name = item[0]
		m.albedo_color = Color(item[1])
		m.metallic = item[2]
		m.roughness = item[3]
		if item[0] == "Yellow":
			m.emission_enabled = true
			m.emission = Color("f9d931")
			m.emission_energy_multiplier = 0.6
		mats[item[0]] = m

func node(parent: Node3D, title: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = title
	n.position = pos
	n.rotation_degrees = rot
	parent.add_child(n)
	return n

func attach(parent: Node3D, title: String, mesh: Mesh, mat: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = title
	n.mesh = mesh
	n.material_override = mats[mat]
	n.position = pos
	n.rotation_degrees = rot
	parent.add_child(n)
	meshes += 1
	for surf in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(surf)
		triangles += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null and a[Mesh.ARRAY_INDEX].size() > 0 else a[Mesh.ARRAY_VERTEX].size()) / 3
	return n

func face(st: SurfaceTool, pts: Array, outward: Vector3) -> void:
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	if n.dot(outward) < 0:
		pts.reverse()
		n = -n
	for i in range(1, pts.size() - 1):
		for v in [pts[0], pts[i + 1], pts[i]]:
			st.set_normal(n)
			st.add_vertex(v)

func panel(parent: Node3D, title: String, outline: Array, depth: float, bevel: float, mat: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector2.ZERO
	for p in outline:
		center += p
	center /= outline.size()
	var rings: Array = []
	for k in 4:
		var ring: Array = []
		for p in outline:
			var q: Vector2 = p
			if k == 0 or k == 3:
				q = p.move_toward(center, bevel)
			var z: float = [-depth * 0.5, -depth * 0.5 + bevel, depth * 0.5 - bevel, depth * 0.5][k]
			ring.append(Vector3(q.x, q.y, z))
		rings.append(ring)
	face(st, rings[0].duplicate(), Vector3.FORWARD)
	face(st, rings[3].duplicate(), Vector3.BACK)
	for k in 3:
		for i in outline.size():
			var j: int = (i + 1) % outline.size()
			var out := Vector3((outline[i].x + outline[j].x) * 0.5 - center.x, (outline[i].y + outline[j].y) * 0.5 - center.y, 0)
			face(st, [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]], out)
	return attach(parent, title, st.commit(), mat, pos, rot)

func plate(parent: Node3D, title: String, size: Vector3, pos: Vector3, mat := "Ivory", cut := 0.055, rot := Vector3.ZERO) -> MeshInstance3D:
	var x := size.x / 2
	var y := size.y / 2
	var c := minf(cut, minf(x, y) * 0.65)
	return panel(parent, title, [Vector2(-x+c,y),Vector2(x-c,y),Vector2(x,y-c),Vector2(x,-y+c),Vector2(x-c,-y),Vector2(-x+c,-y),Vector2(-x,-y+c),Vector2(-x,y-c)], size.z, minf(cut * 0.4, size.z * 0.24), mat, pos, rot)

func lathe(parent: Node3D, title: String, profile: Array, mat: String, pos := Vector3.ZERO, rot := Vector3.ZERO, segs := 64) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(profile.size()-1):
		var a: Vector2 = profile[k]
		var b: Vector2 = profile[k+1]
		var slope := Vector2(b.y-a.y, a.x-b.x).normalized()
		var na := slope
		var nb := slope
		if k > 0:
			var prev: Vector2 = profile[k-1]
			var pn := Vector2(a.y-prev.y,prev.x-a.x).normalized()
			if pn.dot(slope) > 0.75:
				na = (pn+slope).normalized()
		if k+2 < profile.size():
			var next: Vector2 = profile[k+2]
			var nn := Vector2(next.y-b.y,b.x-next.x).normalized()
			if nn.dot(slope) > 0.75:
				nb = (nn+slope).normalized()
		for i in segs:
			var t0 := TAU * i / segs
			var t1 := TAU * (i+1) / segs
			var vs := [Vector3(a.x*cos(t0),a.y,a.x*sin(t0)),Vector3(a.x*cos(t1),a.y,a.x*sin(t1)),Vector3(b.x*cos(t1),b.y,b.x*sin(t1)),Vector3(b.x*cos(t0),b.y,b.x*sin(t0))]
			for ix in [0,1,2,0,2,3]:
				var t := t0 if ix == 0 or ix == 3 else t1
				var ns := na if ix < 2 else nb
				st.set_normal(Vector3(ns.x*cos(t),ns.y,ns.x*sin(t)))
				st.add_vertex(vs[ix])
	return attach(parent, title, st.commit(), mat, pos, rot)

func cylinder(parent: Node3D, title: String, r: float, length: float, pos: Vector3, mat := "Steel", rot := Vector3.ZERO) -> MeshInstance3D:
	var h := length*0.5
	var b := minf(0.016, length*0.16)
	return lathe(parent,title,[Vector2(0,-h),Vector2(r-b,-h),Vector2(r,-h+b),Vector2(r,h-b),Vector2(r-b,h),Vector2(0,h)],mat,pos,rot)

func ring(parent: Node3D, title: String, r: float, inner: float, length: float, pos: Vector3, mat := "Ivory", rot := Vector3.ZERO) -> MeshInstance3D:
	var h := length/2
	var b := minf(0.012,length*0.2)
	return lathe(parent,title,[Vector2(inner,-h),Vector2(r-b,-h),Vector2(r,-h+b),Vector2(r,h-b),Vector2(r-b,h),Vector2(inner,h),Vector2(inner,-h)],mat,pos,rot)

func bolt(parent: Node3D, pos: Vector3, r := 0.022, rot := Vector3(90,0,0)) -> void:
	cylinder(parent,"Flush_fastener",r,0.01,pos,"Edge",rot)
	plate(parent,"Screw_slot",Vector3(r*1.1,0.004,0.003),pos+Vector3(0,0,-0.008),"Graphite",0.001)

func tube(parent: Node3D, title: String, pts: Array, radius: float, mat: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var normals: Array = []
	for i in pts.size():
		var tangent: Vector3 = (pts[mini(i+1,pts.size()-1)]-pts[maxi(0,i-1)]).normalized()
		var u := tangent.cross(Vector3.FORWARD).normalized()
		var v := tangent.cross(u).normalized()
		var rr: Array = []
		var nn: Array = []
		for k in 32:
			var n := u*cos(TAU*k/32)+v*sin(TAU*k/32)
			rr.append(pts[i]+n*radius)
			nn.append(n)
		rings.append(rr)
		normals.append(nn)
	for i in range(pts.size()-1):
		for k in 32:
			var j := (k+1)%32
			var ids := [Vector2i(i,k),Vector2i(i,j),Vector2i(i+1,j),Vector2i(i+1,k)]
			var p0: Vector3 = rings[i][k]
			var p1: Vector3 = rings[i][j]
			var p2: Vector3 = rings[i+1][j]
			var order := [0,2,1,0,3,2] if (p1-p0).cross(p2-p0).dot(normals[i][k]) > 0 else [0,1,2,0,2,3]
			for ix in order:
				var id: Vector2i = ids[ix]
				st.set_normal(normals[id.x][id.y])
				st.add_vertex(rings[id.x][id.y])
	attach(parent,title,st.commit(),mat)

func build() -> Node3D:
	var root := Node3D.new()
	root.name = "ReferenceMech"
	var torso := node(root,"Torso")
	plate(torso,"Inner_chassis",Vector3(1.47,1.06,0.94),Vector3(0,2.35,0.08),"Graphite",0.16)
	plate(torso,"Upper_hull",Vector3(1.27,0.73,0.97),Vector3(0,2.70,0.01),"Ivory",0.16)
	# Open face assembly, independent brow, gasket, inset black lens and rim.
	var visor_shape := [Vector2(-0.46,0.12),Vector2(0.46,0.12),Vector2(0.49,0.065),Vector2(0.37,-0.13),Vector2(-0.37,-0.13),Vector2(-0.49,0.065)]
	panel(torso,"Visor_gasket",visor_shape,0.11,0.018,"Edge",Vector3(0,2.69,-0.524))
	var lens_shape: Array = []
	for p in visor_shape:
		lens_shape.append(p*0.88)
	panel(torso,"Recessed_black_visor",lens_shape,0.034,0.005,"Recess",Vector3(0,2.69,-0.59))
	plate(torso,"Heavy_brow",Vector3(1.13,0.23,0.43),Vector3(0,2.91,-0.47),"Ivory",0.065)
	plate(torso,"Brow_front_lip",Vector3(0.97,0.035,0.035),Vector3(0,2.805,-0.685),"Inset",0.009)
	panel(torso,"Cheek_lower_bridge",[Vector2(-0.47,0.1),Vector2(-0.34,-0.035),Vector2(0.34,-0.035),Vector2(0.47,0.1),Vector2(0.46,-0.12),Vector2(-0.46,-0.12)],0.19,0.012,"Ivory",Vector3(0,2.48,-0.49))
	for s in [-1,1]:
		plate(torso,"Yellow_eye",Vector3(0.046,0.105,0.018),Vector3(s*0.15,2.706,-0.614),"Yellow",0.02,Vector3(0,0,s*10))
		plate(torso,"Brow_latch",Vector3(0.055,0.024,0.082),Vector3(s*0.4,3.027,-0.52),"Steel",0.009)
		plate(torso,"Cheek",Vector3(0.17,0.39,0.24),Vector3(s*0.52,2.45,-0.41),"Ivory",0.043,Vector3(0,0,-s*14))
		ring(torso,"Cheek_socket_rim",0.078,0.054,0.027,Vector3(s*0.465,2.365,-0.555),"Inset",Vector3(90,0,0))
		cylinder(torso,"Cheek_socket_dark",0.052,0.014,Vector3(s*0.465,2.365,-0.558),"Recess",Vector3(90,0,0))
		for y in [2.08,2.48]:
			cylinder(torso,"Side_joint",0.185,0.29,Vector3(s*0.63,y,0),"Graphite",Vector3(0,0,90))
			ring(torso,"Joint_band",0.19,0.157,0.04,Vector3(s*0.715,y,0),"Steel",Vector3(0,0,90))
	# Long front apron: slightly asymmetrical cut corners, inset surrounded by a narrow gasket.
	var shield := node(torso,"Front_apron",Vector3(0,1.79,-0.59),Vector3(-4,0,0))
	var sh := [Vector2(-0.46,0.6),Vector2(0.40,0.6),Vector2(0.51,0.48),Vector2(0.48,-0.61),Vector2(0.36,-0.68),Vector2(-0.39,-0.65),Vector2(-0.5,-0.53),Vector2(-0.51,0.48)]
	panel(shield,"Shield_shell",sh,0.22,0.032,"Ivory")
	panel(shield,"Panel_seam",[Vector2(-.39,.49),Vector2(.34,.49),Vector2(.40,.40),Vector2(.37,-.43),Vector2(.28,-.50),Vector2(-.32,-.49),Vector2(-.40,-.39)],0.016,0.003,"Graphite",Vector3(0,0,-.117))
	panel(shield,"Inset_face",[Vector2(-.37,.47),Vector2(.32,.47),Vector2(.38,.38),Vector2(.35,-.41),Vector2(.26,-.48),Vector2(-.30,-.47),Vector2(-.38,-.37)],0.022,0.007,"Inset",Vector3(0,0,-.129))
	plate(shield,"Lower_notch",Vector3(.13,.019,.012),Vector3(0,-.562,-.12),"Recess",.005)
	for s in [-1,1]:
		bolt(shield,Vector3(s*.425,.48,-.124),.014)
	# Pelvis and simple conservative rear panels.
	cylinder(torso,"Waist_bearing",.36,.32,Vector3(0,1.80,.08),"Graphite")
	plate(torso,"Pelvis",Vector3(.94,.34,.66),Vector3(0,1.58,.06),"Steel",.09)
	plate(torso,"Back_armor",Vector3(1.28,.84,.15),Vector3(0,2.39,.60),"Inset",.13)
	plate(torso,"Rear_spine",Vector3(.62,.37,.08),Vector3(0,2.71,.679),"Ivory",.04)
	plate(torso,"Rear_pelvis_cover",Vector3(.76,.46,.14),Vector3(0,1.65,.43),"Ivory",.10)
	for s in [-1,1]:
		cylinder(torso,"Rear_fastener",.045,.014,Vector3(s*.45,2.23,.66),"Edge",Vector3(90,0,0))
	plate(torso,"Rear_pelvis_seam",Vector3(.22,.015,.014),Vector3(0,1.51,.509),"Graphite",.003)
	_build_backpack(torso)
	for s in [-1,1]:
		_build_shoulder(torso,s)
		_build_arm(root,s)
		_build_leg(root,s)
	root.set_meta("mesh_count",meshes)
	root.set_meta("triangle_count",triangles)
	root.set_meta("design_note","Front reconstructed from supplied concept and turnaround. Hidden rear mounts inferred.")
	return root

func _build_backpack(parent: Node3D) -> void:
	var pack := node(parent,"Backpack")
	plate(pack,"Backpack_support",Vector3(.92,.92,.38),Vector3(0,2.99,.62),"Graphite",.09)
	plate(pack,"Rear_mount_shroud",Vector3(.76,.82,.10),Vector3(0,3.015,.838),"Ivory",.07)
	plate(pack,"Rear_mount_lower_panel",Vector3(.50,.28,.022),Vector3(0,2.81,.896),"Inset",.03)
	var middle := node(pack,"Central_high_plate",Vector3(0,3.83,.59),Vector3(20,0,0))
	panel(middle,"Central_housing",[Vector2(-.43,-.60),Vector2(.43,-.60),Vector2(.47,.42),Vector2(.27,.60),Vector2(-.25,.60),Vector2(-.46,.40)],.30,.034,"Ivory")
	plate(middle,"Central_inset",Vector3(.69,.96,.023),Vector3(0,-.025,-.163),"Inset",.08)
	plate(middle,"Central_front_face",Vector3(.655,.93,.028),Vector3(0,-.02,-.178),"Ivory",.075)
	for k in 3:
		plate(middle,"Top_vent",Vector3(.21-k*.04,.02,.014),Vector3(-.09,.41+k*.05,-.19),"Recess",.008)
		plate(middle,"Back_vent",Vector3(.24-k*.035,.02,.014),Vector3(-.04,.42+k*.045,.156),"Recess",.006)
	plate(middle,"Bottom_slot",Vector3(.33,.023,.015),Vector3(0,-.45,-.198),"Graphite",.005)
	cylinder(pack,"Transverse_mount",.22,1.52,Vector3(0,3.10,.40),"Steel",Vector3(0,0,90))
	plate(pack,"Crossbar_shroud",Vector3(.66,.37,.50),Vector3(0,3.11,.39),"Ivory",.06)
	for s in [-1,1]:
		var points: Array = []
		for k in 21:
			var t := float(k)/20
			points.append(Vector3(s*(.47+.50*sin(t*PI/2)),3.10+.25*(1-cos(t*PI/2)),.40+.09*t))
		tube(pack,"Curved_pod_coupling",points,.23,"Inset")
		for x in [.48,.57,.68]:
			ring(pack,"Coupling_gasket",.241,.214,.036,Vector3(s*x,3.102,.412),"Graphite",Vector3(0,0,90))
		var pod := node(pack,"Pod_L" if s < 0 else "Pod_R",Vector3(s*.99,3.30,.50),Vector3(16,0,-s*10))
		# Lathed rounded caps, broad uninterrupted shell, concentric open bottom socket.
		lathe(pod,"Pod_outer_shell",[Vector2(.34,-.05),Vector2(.43,-.05),Vector2(.49,.02),Vector2(.51,.10),Vector2(.51,1.08),Vector2(.503,1.16),Vector2(.478,1.22),Vector2(.43,1.27),Vector2(.35,1.31),Vector2(.23,1.34),Vector2(0,1.355)],"Ivory")
		ring(pod,"Lower_socket_lip",.494,.362,.055,Vector3(0,.014,0),"Ivory")
		ring(pod,"Socket_dark_annulus",.369,.288,.08,Vector3(0,-.045,0),"Graphite")
		ring(pod,"Socket_inner_sleeve",.296,.245,.12,Vector3(0,-.094,0),"Steel")
		cylinder(pod,"Coupling_ball",.246,.25,Vector3(0,-.055,0),"Inset")
		ring(pod,"Top_seam",.509,.500,.008,Vector3(0,1.11,0),"Edge")
		ring(pod,"Lower_shell_seam",.512,.501,.008,Vector3(0,.29,0),"Edge")
		plate(pod,"Service_hatch_gasket",Vector3(.021,.17,.17),Vector3(s*.506,.48,0),"Edge",.024)
		plate(pod,"Service_hatch",Vector3(.024,.143,.143),Vector3(s*.519,.48,0),"Ivory",.022)
		plate(pod,"Hatch_handle",Vector3(.009,.043,.023),Vector3(s*.535,.47,-.035),"Graphite",.003)

func _build_shoulder(parent: Node3D, s: int) -> void:
	var shoulder := node(parent,"Shoulder_armor_L" if s<0 else "Shoulder_armor_R",Vector3(s*.94,2.52,-.02),Vector3(0,0,s*11))
	plate(shoulder,"Shoulder_inner",Vector3(.60,.85,.64),Vector3.ZERO,"Graphite",.10)
	panel(shoulder,"Broad_shoulder_shell",[Vector2(-.31,.48),Vector2(.29,.48),Vector2(.38,.33),Vector2(.34,-.37),Vector2(.19,-.46),Vector2(-.29,-.43),Vector2(-.35,-.23)],.75,.04,"Ivory")
	plate(shoulder,"Shoulder_upper_panel",Vector3(.58,.34,.035),Vector3(0,.265,-.405),"Inset",.035)
	plate(shoulder,"Upper_panel_face",Vector3(.55,.30,.022),Vector3(0,.27,-.431),"Ivory",.03)
	plate(shoulder,"Panel_split",Vector3(.59,.018,.016),Vector3(0,.065,-.415),"Graphite",.003)
	plate(shoulder,"Shoulder_lower_inset",Vector3(.56,.43,.025),Vector3(0,-.18,-.397),"Inset",.05)
	plate(shoulder,"Top_bracket",Vector3(.49,.065,.75),Vector3(0,.51,.015),"Ivory",.025)
	plate(shoulder,"Top_recess",Vector3(.34,.023,.40),Vector3(0,.548,.03),"Recess",.03)
	plate(shoulder,"Top_rail",Vector3(.39,.04,.08),Vector3(0,.565,-.19),"Inset",.014)
	for x in [-.22,.22]:
		bolt(shoulder,Vector3(x,.43,-.413),.017)
	bolt(shoulder,Vector3(s*.18,-.30,-.421),.042)
	plate(shoulder,"Rear_shoulder_plate",Vector3(.53,.65,.045),Vector3(0,-.04,.393),"Ivory",.085)

func _build_arm(parent: Node3D, s: int) -> void:
	var arm := node(parent,"Arm_L" if s<0 else "Arm_R",Vector3(s*1.32,2.58,.05),Vector3(0,0,s*20))
	cylinder(arm,"Shoulder_axle",.218,.31,Vector3.ZERO,"Graphite",Vector3(0,0,90))
	cylinder(arm,"Shoulder_cap",.205,.045,Vector3(s*.18,0,0),"Ivory",Vector3(0,0,90))
	ring(arm,"Shoulder_cap_seam",.177,.168,.006,Vector3(s*.207,0,0),"Edge",Vector3(0,0,90))
	plate(arm,"Upper_arm_strut",Vector3(.19,.39,.23),Vector3(0,-.30,0),"Steel",.035)
	plate(arm,"Bicep_plate",Vector3(.27,.27,.30),Vector3(0,-.24,-.006),"Ivory",.05,Vector3(-9,0,0))
	plate(arm,"Bicep_recess",Vector3(.115,.21,.025),Vector3(0,-.31,-.166),"Graphite",.025)
	cylinder(arm,"Elbow_hinge",.145,.30,Vector3(0,-.48,0),"Graphite",Vector3(0,0,90))
	cylinder(arm,"Elbow_outer_cap",.118,.04,Vector3(s*.17,-.48,0),"Inset",Vector3(0,0,90))
	var fore := node(arm,"Forearm",Vector3(0,-.48,0),Vector3(-7,0,0))
	fore.scale.y = 0.91
	panel(fore,"Forearm_armor",[Vector2(-.17,-.10),Vector2(.13,-.10),Vector2(.22,-.23),Vector2(.16,-.86),Vector2(-.11,-.91),Vector2(-.21,-.79),Vector2(-.22,-.23)],.34,.029,"Ivory",Vector3(0,0,-.045))
	plate(fore,"Forearm_inner_frame",Vector3(.20,.72,.18),Vector3(0,-.52,.15),"Steel",.035)
	plate(fore,"Long_dark_inset",Vector3(.083,.49,.026),Vector3(.02,-.48,-.224),"Graphite",.023)
	plate(fore,"Inset_inner",Vector3(.044,.40,.012),Vector3(.02,-.48,-.241),"Recess",.01)
	plate(fore,"Wrist_armor_band",Vector3(.29,.13,.385),Vector3(0,-.80,-.027),"Inset",.018)
	plate(fore,"Wrist_band_face",Vector3(.245,.105,.025),Vector3(0,-.80,-.23),"Ivory",.02)
	bolt(fore,Vector3(-.08,-.16,-.225),.016)
	cylinder(fore,"Wrist_shaft",.074,.17,Vector3(0,-.97,.0),"Steel")
	_build_hand(fore,Vector3(0,-1.06,-.02))

func _build_hand(parent: Node3D, pos: Vector3) -> void:
	var hand := node(parent,"Three_finger_claw",pos)
	plate(hand,"Palm",Vector3(.26,.19,.18),Vector3(0,-.065,0),"Steel",.047)
	cylinder(hand,"Palm_front_pivot",.108,.055,Vector3(0,-.064,-.109),"Graphite",Vector3(90,0,0))
	cylinder(hand,"Palm_pivot_face",.082,.016,Vector3(0,-.064,-.144),"Inset",Vector3(90,0,0))
	for s in [-1,1]:
		var finger := node(hand,"Finger_L" if s<0 else "Finger_R",Vector3(s*.122,-.12,-.015),Vector3(0,0,s*23))
		cylinder(finger,"Knuckle",.046,.091,Vector3.ZERO,"Graphite",Vector3(90,0,0))
		cylinder(finger,"Knuckle_cap",.034,.012,Vector3(0,0,-.052),"Inset",Vector3(90,0,0))
		plate(finger,"Finger_link",Vector3(.075,.18,.08),Vector3(0,-.105,0),"Steel",.016)
		cylinder(finger,"Finger_hinge",.036,.084,Vector3(0,-.20,0),"Graphite",Vector3(90,0,0))
		var tip := node(finger,"Finger_tip",Vector3(0,-.20,0),Vector3(0,0,-s*46))
		plate(tip,"Tapered_claw_tip",Vector3(.05,.17,.064),Vector3(0,-.085,0),"Steel",.015)
		plate(tip,"Grip_pad",Vector3(.016,.068,.058),Vector3(-s*.023,-.125,-.002),"Graphite",.007)
	var thumb := node(hand,"Opposed_thumb",Vector3(0,-.08,.102),Vector3(-35,0,0))
	plate(thumb,"Thumb_link",Vector3(.073,.17,.075),Vector3(0,-.085,0),"Steel",.019)
	cylinder(thumb,"Thumb_hinge",.034,.08,Vector3(0,-.18,0),"Edge",Vector3(0,0,90))
	plate(thumb,"Thumb_tip",Vector3(.065,.145,.06),Vector3(0,-.235,-.034),"Steel",.015,Vector3(36,0,0))

func _build_leg(parent: Node3D, s: int) -> void:
	var leg := node(parent,"Leg_L" if s<0 else "Leg_R",Vector3(s*.69,1.64,.06),Vector3(0,0,s*7))
	cylinder(leg,"Hip_axle",.224,.40,Vector3.ZERO,"Graphite",Vector3(0,0,90))
	ring(leg,"Hip_bearing",.228,.161,.04,Vector3(s*.24,0,0),"Inset",Vector3(0,0,90))
	cylinder(leg,"Hip_cap",.146,.035,Vector3(s*.26,0,0),"Steel",Vector3(0,0,90))
	plate(leg,"Thigh_inner",Vector3(.37,.53,.42),Vector3(0,-.28,0),"Graphite",.055)
	plate(leg,"Thigh_front",Vector3(.59,.48,.20),Vector3(0,-.23,-.25),"Ivory",.073,Vector3(-9,0,0))
	plate(leg,"Thigh_side",Vector3(.09,.43,.47),Vector3(s*.27,-.26,.005),"Inset",.032)
	plate(leg,"Thigh_back",Vector3(.46,.40,.095),Vector3(0,-.25,.263),"Ivory",.046)
	for x in [-.16,.16]:
		plate(leg,"Hip_bracket",Vector3(.095,.10,.13),Vector3(x,.015,-.15),"Steel",.02)
	var knee := node(leg,"Knee",Vector3(0,-.59,-.025),Vector3(-7,0,-s*7))
	cylinder(knee,"Knee_axle",.18,.59,Vector3.ZERO,"Graphite",Vector3(0,0,90))
	cylinder(knee,"Knee_cap",.152,.055,Vector3(s*.32,0,0),"Ivory",Vector3(0,0,90))
	ring(knee,"Knee_seam",.131,.124,.009,Vector3(s*.353,0,0),"Edge",Vector3(0,0,90))
	plate(knee,"Shin_inner",Vector3(.42,.59,.46),Vector3(0,-.34,.015),"Graphite",.06)
	panel(knee,"Shin_front",[Vector2(-.29,-.055),Vector2(.26,-.055),Vector2(.31,-.17),Vector2(.30,-.65),Vector2(-.31,-.65),Vector2(-.33,-.16)],.27,.035,"Ivory",Vector3(0,0,-.225))
	plate(knee,"Shin_side",Vector3(.10,.56,.47),Vector3(s*.30,-.36,.045),"Inset",.035)
	plate(knee,"Shin_side_panel",Vector3(.035,.41,.33),Vector3(s*.367,-.34,.025),"Ivory",.03)
	plate(knee,"Shin_back",Vector3(.48,.53,.10),Vector3(0,-.34,.295),"Ivory",.04)
	plate(knee,"Shin_horizontal_band",Vector3(.69,.19,.74),Vector3(0,-.57,-.014),"Ivory",.024)
	plate(knee,"Band_seam",Vector3(.63,.012,.015),Vector3(0,-.473,-.389),"Graphite",.003)
	plate(knee,"Band_front",Vector3(.59,.145,.016),Vector3(0,-.575,-.391),"Inset",.015)
	var foot := node(knee,"Foot",Vector3(0,-.84,-.095),Vector3(7,0,0))
	cylinder(foot,"Ankle_hinge",.14,.47,Vector3(0,.045,.12),"Graphite",Vector3(0,0,90))
	plate(foot,"Foot_sole",Vector3(.65,.11,.77),Vector3(0,-.035,-.025),"Graphite",.055)
	panel(foot,"Foot_armor",[Vector2(-.28,.12),Vector2(.28,.12),Vector2(.31,.035),Vector2(.29,-.065),Vector2(-.29,-.065),Vector2(-.31,.035)],.70,.025,"Inset",Vector3(0,.03,-.04))
	plate(foot,"Instep",Vector3(.47,.22,.40),Vector3(0,.155,.03),"Ivory",.06,Vector3(-16,0,0))
	plate(foot,"Toe_cap",Vector3(.56,.125,.13),Vector3(0,.003,-.391),"Steel",.03)
	for x in [-.18,.18]:
		plate(foot,"Toe_groove",Vector3(.012,.09,.013),Vector3(x,.01,-.46),"Recess",.003)

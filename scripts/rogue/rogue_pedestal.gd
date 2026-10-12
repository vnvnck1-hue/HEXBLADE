class_name RoguePedestal
extends Node3D
## 아이템 받침대. 무료 · 상점(동전) · 악마 거래(빨간 그릇) 가격을 받는다.
## 같은 group 의 받침대는 하나를 가지면 나머지가 사라진다 (선택지 아이템방 · 천사방 · 서재).

static var _box: BoxMesh
static var _gem: PrismMesh
static var _ring: TorusMesh

var item_id := ""
var price := 0
var heart_price := 0
var group := -1
var taken := false
var blind := false
var gem: Node3D
var gem_mi: MeshInstance3D
var name_label: Label3D
var price_label: Label3D
var age := 0.0
var _cool := 0.0


static func _m() -> void:
	if _box:
		return
	_box = BoxMesh.new()
	_gem = PrismMesh.new()
	_ring = TorusMesh.new()
	_ring.inner_radius = 0.42
	_ring.outer_radius = 0.5


func _ready() -> void:
	_m()
	add_to_group("rogue_pedestals")
	var stand := MeshInstance3D.new()
	stand.mesh = _box
	stand.material_override = Pal.lit(Color("4a4a66"))
	stand.scale = Vector3(0.8, 0.6, 0.8)
	stand.position.y = 0.3
	add_child(stand)
	var top := MeshInstance3D.new()
	top.mesh = _box
	top.material_override = Pal.lit(Color("6a6a8a"))
	top.scale = Vector3(0.95, 0.1, 0.95)
	top.position.y = 0.62
	add_child(top)
	gem = Node3D.new()
	gem.position.y = 1.35
	add_child(gem)
	name_label = Label3D.new()
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 44
	name_label.outline_size = 12
	name_label.pixel_size = 0.01
	name_label.no_depth_test = true
	name_label.position.y = 2.15
	add_child(name_label)
	price_label = Label3D.new()
	price_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	price_label.font_size = 52
	price_label.outline_size = 14
	price_label.pixel_size = 0.01
	price_label.no_depth_test = true
	price_label.position = Vector3(0, 0.25, -0.75)
	add_child(price_label)
	refresh()


func set_item(id: String) -> void:
	item_id = id
	taken = id == ""
	refresh()


func refresh() -> void:
	if gem == null:
		return
	for c in gem.get_children():
		c.queue_free()
	if item_id == "":
		name_label.text = ""
		price_label.text = ""
		return
	var it := RogueItems.get_item(item_id)
	var c := RogueItems.color_of(item_id)
	var mesh: Mesh = _gem
	var s := Vector3(0.55, 0.7, 0.55)
	match it.type:
		RogueItems.T.ACTIVE:
			mesh = _box
			s = Vector3(0.5, 0.5, 0.5)
		RogueItems.T.TRINKET:
			mesh = _ring
			s = Vector3(0.6, 0.6, 0.6)
	gem_mi = Pal.flat_mesh(mesh, c, 1.8)
	gem_mi.scale = s
	gem.add_child(gem_mi)
	var inner := Pal.flat_mesh(_box, Color.WHITE, 2.4)
	inner.scale = Vector3.ONE * 0.16
	gem.add_child(inner)
	var halo := Pal.flat_mesh(_ring, c, 1.2)
	halo.scale = Vector3(1.1, 0.4, 1.1)
	halo.position.y = -0.55
	gem.add_child(halo)
	name_label.text = "???" if blind else it.name
	name_label.modulate = c.lerp(Color.WHITE, 0.5)
	if heart_price > 0:
		price_label.text = "♥ ×%d" % heart_price
		price_label.modulate = Color("ff4a5a")
	elif price > 0:
		price_label.text = "%d¢" % price
		price_label.modulate = Color("ffe070")
	else:
		price_label.text = ""


func _physics_process(dt: float) -> void:
	age += dt
	_cool -= dt
	if gem:
		gem.rotation.y += dt * 1.6
		gem.position.y = 1.35 + sin(age * 2.4) * 0.12
	if taken or item_id == "":
		return
	var main := Main.inst
	if main == null or not is_instance_valid(main.player) or _cool > 0.0:
		return
	var to := main.player.global_position - global_position
	to.y = 0
	if to.length() < 1.15:
		_cool = 1.0
		if main.has_method("take_pedestal"):
			main.take_pedestal(self)

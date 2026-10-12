class_name RogueBomb
extends Node3D
## 설치 폭탄 (X). 1.5초 도화선 뒤 폭발: 적 · 상자(틴티드 포함) · 금 간 벽 · 플레이어(폭파광이면 면역).
## mine 이면 대시 기뢰: 플레이어는 다치지 않고, 적이 가까이 오면 바로 터진다.

const FUSE := 1.5
const RADIUS := 2.7
const DMG := 30.0

static var _ball: SphereMesh

var mine := false
var fuse := FUSE
var vel := Vector3.ZERO
var core: MeshInstance3D
var spark: MeshInstance3D
var t := 0.0


static func spawn(main, pos: Vector3, is_mine := false, v := Vector3.ZERO) -> RogueBomb:
	var b := RogueBomb.new()
	b.mine = is_mine
	b.vel = v
	if is_mine:
		b.fuse = 2.5
	main.world.add_child(b)
	b.global_position = Vector3(pos.x, Main.gy(pos) + 0.35, pos.z)
	return b


func _ready() -> void:
	if _ball == null:
		_ball = SphereMesh.new()
		_ball.radius = 0.5
		_ball.height = 1.0
	core = Pal.flat_mesh(_ball, Color("ff5a3a") if mine else Color("2a2a38"), 1.0)
	core.scale = Vector3.ONE * (0.4 if mine else 0.62)
	add_child(core)
	spark = Pal.flat_mesh(_ball, Color("ffd060"), 2.8)
	spark.scale = Vector3.ONE * 0.14
	spark.position.y = 0.38
	add_child(spark)
	FX.blob_shadow(self, 1.0, 0.5)
	Sfx.play("lock", 0.1, -6.0)


func _physics_process(dt: float) -> void:
	t += dt
	fuse -= dt
	if vel.length() > 0.1:
		var np := global_position + vel * dt
		if Main.inst.is_blocked(np):
			vel = -vel * 0.4
		else:
			global_position = np
		vel = vel.move_toward(Vector3.ZERO, 6.0 * dt)
	var blink := fmod(t * (4.0 + (FUSE - fuse) * 8.0), 1.0) < 0.5
	core.set_instance_shader_parameter("energy", 2.4 if blink else 1.0)
	core.scale = Vector3.ONE * (0.4 if mine else 0.62) * (1.0 + (0.12 if blink else 0.0))
	spark.visible = fmod(t * 20.0, 1.0) < 0.6
	if mine and t > 0.4:
		for e in Enemy.live(get_tree()):
			if not e.get("prop") and e.landed and e.global_position.distance_to(global_position) < 1.6:
				fuse = 0.0
	if fuse <= 0.0:
		var b := RogueBuild.inst
		var big := b != null and b.f("bomb_big") > 0
		var r := RADIUS * (1.35 if big else 1.0) * (0.8 if mine else 1.0)
		var d := DMG * (2.0 if big else 1.0) * (0.6 if mine else 1.0)
		RogueEffects.explosion(global_position, r, d, not mine, "bomb")
		queue_free()

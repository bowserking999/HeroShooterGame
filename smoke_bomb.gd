extends Node3D

const SmokeGroundVfxScene := preload("res://assets/BinbunVFX/smoke_effects/effects/smoke/smoke_vfx_01.tscn")

const FLIGHT_GRAVITY: float = 28.0
const MAX_FLIGHT_SEC: float = 10.0
const GROUND_SMOKE_DURATION_SEC: float = 6.0
const BOUNCE_DAMPING: float = 0.72
const ENEMY_KNOCKBACK_STRENGTH: float = 12.0
const GROUND_DOT_THRESHOLD: float = 0.62
const PLAYER_LAYER: int = 2
const SMOKE_AMBIENT_STREAM_PATH := "res://assets/sounds/effects/snipersmoke.wav"
const SMOKE_AMBIENT_TARGET_DB := -4.0
const SMOKE_AMBIENT_FADE_IN_SEC := 0.22
const SMOKE_AMBIENT_FADE_OUT_SEC := 0.48
## Hit any static geometry (imported maps may use non-default layers).
const COLLISION_MASK_FLIGHT: int = 0xFFFFFFFF

@onready var _trail: Node3D = $TrailVFX
@onready var _mesh: MeshInstance3D = $MeshInstance3D

var shooter_peer_id: int = -1
var shooter_node: Node = null
var shooter_team_id: int = -1
var velocity: Vector3 = Vector3.ZERO
var _stuck: bool = false
var _flight_age: float = 0.0


func _ready() -> void:
	if _trail != null and _trail.get("emitting") != null:
		_trail.emitting = true


func setup(peer_id: int, initial_velocity: Vector3) -> void:
	shooter_peer_id = peer_id
	shooter_node = get_parent().get_node_or_null(str(peer_id))
	shooter_team_id = -1
	if shooter_node != null:
		var tv: Variant = shooter_node.get("team_id")
		if typeof(tv) == TYPE_INT:
			shooter_team_id = int(tv)
	velocity = initial_velocity
	_flight_age = 0.0
	_stuck = false
	visible = true
	if _mesh != null:
		_mesh.visible = true
	if _trail != null and _trail.get("emitting") != null:
		_trail.emitting = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _stuck:
		return
	_flight_age += delta
	if _flight_age >= MAX_FLIGHT_SEC:
		queue_free()
		return
	velocity.y -= FLIGHT_GRAVITY * delta
	var w3d: World3D = get_world_3d()
	if w3d == null:
		return
	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	var space: PhysicsDirectSpaceState3D = w3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = COLLISION_MASK_FLIGHT
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if shooter_node != null and is_instance_valid(shooter_node):
		query.exclude = [shooter_node]
	else:
		query.exclude = []
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		global_position = to
		return
	var collider: Object = result.get("collider")
	var hit_pos: Vector3 = result.position as Vector3
	var nvar: Variant = result.get("normal", Vector3.UP)
	var n: Vector3 = (nvar as Vector3).normalized()

	if collider is CharacterBody3D and collider.has_method("receive_damage"):
		if collider.get("is_dead") == true:
			global_position = to
			return
		var tid_v: Variant = collider.get("team_id")
		var is_enemy: bool = (
			typeof(tid_v) == TYPE_INT
			and shooter_team_id >= 0
			and int(tid_v) != shooter_team_id
		)
		if not is_enemy:
			global_position = to
			return
		velocity = velocity.bounce(n) * BOUNCE_DAMPING
		global_position = hit_pos + n * 0.14
		if HeroNet.is_shooter_peer(shooter_peer_id):
			HeroNet.apply_explosion_knockback_on_victim(collider as Node, hit_pos, ENEMY_KNOCKBACK_STRENGTH)
		return

	if collider != null and collider.has_method("try_block_projectile"):
		velocity = velocity.bounce(n) * BOUNCE_DAMPING
		global_position = hit_pos + n * 0.1
		return

	if n.dot(Vector3.UP) >= GROUND_DOT_THRESHOLD:
		_stick_and_spawn_smoke(hit_pos, n)
		return

	velocity = velocity.bounce(n) * BOUNCE_DAMPING
	global_position = hit_pos + n * 0.08


func _basis_with_y_up(up: Vector3) -> Basis:
	var y_axis: Vector3 = up.normalized()
	if y_axis.length_squared() < 1e-8:
		y_axis = Vector3.UP
	var x_axis: Vector3 = Vector3.FORWARD.cross(y_axis)
	if x_axis.length_squared() < 1e-8:
		x_axis = Vector3.RIGHT.cross(y_axis)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = y_axis.cross(x_axis).normalized()
	x_axis = z_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _stick_and_spawn_smoke(hit_pos: Vector3, ground_n: Vector3) -> void:
	_stuck = true
	set_physics_process(false)
	if _mesh != null:
		_mesh.visible = false
	if _trail != null and _trail.get("emitting") != null:
		_trail.emitting = false
	var w: Node = get_parent()
	if w == null:
		queue_free()
		return
	var vfx: Node = SmokeGroundVfxScene.instantiate()
	w.add_child(vfx)
	vfx.global_position = hit_pos + ground_n * 0.06
	vfx.global_transform = Transform3D(_basis_with_y_up(ground_n), vfx.global_position)
	if vfx.get("emitting") != null:
		vfx.emitting = true
	var tree: SceneTree = get_tree()
	var amb_ap: AudioStreamPlayer3D = null
	if tree != null:
		var amb_res: Resource = load(SMOKE_AMBIENT_STREAM_PATH)
		if amb_res is AudioStream:
			var amb_stream: AudioStream = (amb_res as AudioStream).duplicate()
			if amb_stream is AudioStreamWAV:
				(amb_stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			amb_ap = AudioStreamPlayer3D.new()
			amb_ap.stream = amb_stream
			amb_ap.bus = "Master"
			amb_ap.max_distance = 48.0
			amb_ap.unit_size = 4.0
			amb_ap.volume_db = -80.0
			w.add_child(amb_ap)
			amb_ap.global_position = hit_pos + ground_n * 0.2
			amb_ap.play()
			var tw_in := amb_ap.create_tween()
			tw_in.tween_property(amb_ap, "volume_db", SMOKE_AMBIENT_TARGET_DB, SMOKE_AMBIENT_FADE_IN_SEC).from(-80.0)
		tree.create_timer(GROUND_SMOKE_DURATION_SEC).timeout.connect(
			func() -> void:
				if is_instance_valid(vfx) and vfx.get("emitting") != null:
					vfx.emitting = false
				if is_instance_valid(amb_ap):
					var tw_out := amb_ap.create_tween()
					tw_out.tween_property(amb_ap, "volume_db", -80.0, SMOKE_AMBIENT_FADE_OUT_SEC)
					tw_out.finished.connect(func() -> void:
						if is_instance_valid(amb_ap):
							amb_ap.queue_free()
					)
		)
		tree.create_timer(GROUND_SMOKE_DURATION_SEC + 2.5).timeout.connect(
			func() -> void:
				if is_instance_valid(vfx):
					vfx.queue_free()
		)
	queue_free()

extends Node3D

@export var speed: float = 40.0
@export var lifetime_sec: float = 5.0

const ExplosionPlaceholderScene = preload("res://explosion_placeholder.tscn")

var shooter_peer_id: int = -1
var shooter_node: Node = null
var velocity: Vector3 = Vector3.ZERO
var elapsed: float = 0.0
var _impacted: bool = false

func setup(_shooter_peer_id: int, _velocity: Vector3) -> void:
	shooter_peer_id = _shooter_peer_id
	shooter_node = get_parent().get_node_or_null(str(shooter_peer_id))
	velocity = _velocity
	elapsed = 0.0

func _physics_process(delta: float) -> void:
	if _impacted:
		return
	elapsed += delta
	if elapsed >= lifetime_sec:
		queue_free()
		return

	var from := global_position
	var to := from + velocity * delta

	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	if shooter_node != null:
		query.exclude = [self, shooter_node]
	else:
		query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		global_position = to
		return

	# One impact only — queue_free() is deferred, so physics can run again otherwise.
	_impacted = true
	set_physics_process(false)
	global_position = result.position
	_spawn_explosion(global_position)
	queue_free()

func _spawn_explosion(pos: Vector3) -> void:
	if _is_explosive_tank():
		var w := get_parent()
		if w == null:
			return
		# Offline: one local spawn. Online: each peer simulates this round, so only the shooter
		# fires one RPC; call_local runs the effect once on every machine.
		if multiplayer.multiplayer_peer == null:
			if w.has_method("spawn_tank_explosion_vfx_at"):
				w.spawn_tank_explosion_vfx_at(pos)
		elif multiplayer.get_unique_id() == shooter_peer_id:
			if w.has_method("sync_tank_explosion_vfx"):
				w.sync_tank_explosion_vfx.rpc(pos)
	else:
		var expl := ExplosionPlaceholderScene.instantiate()
		expl.global_position = pos
		get_parent().add_child(expl)

func _is_explosive_tank() -> bool:
	if shooter_node == null:
		return false
	return str(shooter_node.get("hero_id")) == "tank_explosive"


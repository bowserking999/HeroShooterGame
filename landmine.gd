extends Node3D

const ExplosionPlaceholderScene = preload("res://explosion_placeholder.tscn")

const LANDMINE_SPEED: float = 34.0
const LANDMINE_DAMAGE: int = 50
const TRIGGER_RADIUS: float = 2.25
const DAMAGE_RADIUS: float = TRIGGER_RADIUS
const MAX_MINES_PER_SHOOTER: int = 3
const FLY_LIFETIME_SEC: float = 12.0

## Seconds after sticking to terrain before proximity detonation is active.
const ARM_DELAY_AFTER_STICK_SEC: float = 2.0
## Total time from spawn until the mine despawns (arming + idle + flight age).
const MAX_PLANTED_LIFETIME_SEC: float = 120.0

const PLAYER_LAYER: int = 2
## Matches player `gravity` arc while the mine is in flight before it sticks.
const FLIGHT_GRAVITY: float = 28.0

## Viewer-relative tint (local ally vs enemy).
const COLOR_ALLY_ALBEDO := Color(0.22, 0.52, 1.0, 1.0)
const COLOR_ALLY_EMISSION := Color(0.12, 0.38, 1.0, 1.0)
const COLOR_ENEMY_ALBEDO := Color(1.0, 0.45, 0.08, 1.0)
const COLOR_ENEMY_EMISSION := Color(1.0, 0.35, 0.02, 1.0)

static var _mines_by_shooter: Dictionary = {} # peer_id -> Array[Node]

var shooter_peer_id: int = -1
var shooter_node: Node = null
var velocity: Vector3 = Vector3.ZERO
var fly_elapsed: float = 0.0
var _stuck: bool = false
var _triggered: bool = false
var _age_since_spawn: float = 0.0
var _age_since_stuck: float = 0.0

var _mesh_instances: Array[MeshInstance3D] = []
var _viewer_tint_retries_left: int = 45


func _ready() -> void:
	add_to_group("landmine")
	_collect_visual_meshes()
	call_deferred("_apply_viewer_team_tint")


func _exit_tree() -> void:
	if shooter_peer_id < 0:
		return
	if not _mines_by_shooter.has(shooter_peer_id):
		return
	var arr: Array = _mines_by_shooter[shooter_peer_id]
	var i := arr.find(self)
	if i >= 0:
		arr.remove_at(i)


func setup(_shooter_peer_id: int, _velocity: Vector3) -> void:
	shooter_peer_id = _shooter_peer_id
	shooter_node = get_parent().get_node_or_null(str(shooter_peer_id))
	velocity = _velocity
	fly_elapsed = 0.0
	_age_since_spawn = 0.0
	_age_since_stuck = 0.0
	_register_mine_cap()
	_apply_viewer_team_tint()


func _register_mine_cap() -> void:
	if not _mines_by_shooter.has(shooter_peer_id):
		_mines_by_shooter[shooter_peer_id] = []
	var arr: Array = _mines_by_shooter[shooter_peer_id]
	arr.append(self)
	while arr.size() > MAX_MINES_PER_SHOOTER:
		var oldest: Node = arr.pop_front()
		if oldest != null and is_instance_valid(oldest) and oldest != self:
			oldest.queue_free()


func _append_tracking_only() -> void:
	if shooter_peer_id < 0:
		return
	if not _mines_by_shooter.has(shooter_peer_id):
		_mines_by_shooter[shooter_peer_id] = []
	var arr: Array = _mines_by_shooter[shooter_peer_id]
	if arr.find(self) >= 0:
		return
	arr.append(self)


func get_network_snapshot() -> Dictionary:
	var bx: Vector3 = global_transform.basis.x
	var by: Vector3 = global_transform.basis.y
	var bz: Vector3 = global_transform.basis.z
	return {
		"shooter_peer_id": shooter_peer_id,
		"stuck": _stuck,
		"pos": global_position,
		"bx": bx,
		"by": by,
		"bz": bz,
		"vel": velocity,
		"age": _age_since_spawn,
		"stuck_age": _age_since_stuck,
		"fly_elapsed": fly_elapsed,
	}


func apply_network_snapshot(d: Variant) -> void:
	var dict: Dictionary = d as Dictionary
	shooter_peer_id = int(dict.get("shooter_peer_id", -1))
	_stuck = bool(dict.get("stuck", false))
	velocity = dict.get("vel", Vector3.ZERO) as Vector3
	global_position = dict.get("pos", Vector3.ZERO) as Vector3
	fly_elapsed = float(dict.get("fly_elapsed", 0.0))
	_age_since_spawn = float(dict.get("age", 0.0))
	_age_since_stuck = float(dict.get("stuck_age", 0.0))

	var by: Vector3 = dict.get("by", Vector3.UP) as Vector3
	if by.length_squared() < 1e-8:
		by = Vector3.UP
	global_transform = Transform3D(_basis_with_y_up(by.normalized()), global_position)

	shooter_node = get_parent().get_node_or_null(str(shooter_peer_id))
	_triggered = false
	set_physics_process(true)
	_append_tracking_only()
	_apply_viewer_team_tint()


func _physics_process(delta: float) -> void:
	if _triggered:
		return

	_age_since_spawn += delta
	if _age_since_spawn >= MAX_PLANTED_LIFETIME_SEC:
		queue_free()
		return

	if _stuck:
		_age_since_stuck += delta
		if _age_since_stuck >= ARM_DELAY_AFTER_STICK_SEC:
			_scan_detonate()
		return

	fly_elapsed += delta
	if fly_elapsed >= FLY_LIFETIME_SEC:
		queue_free()
		return

	velocity.y -= FLIGHT_GRAVITY * delta

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
	query.collision_mask = _terrain_ray_collision_mask()

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		global_position = to
		return

	var collider: Object = result.get("collider", null)
	if collider is CharacterBody3D:
		global_position = to
		return

	_stuck = true
	set_physics_process(true)
	var n: Vector3 = Vector3.UP
	if result.has("normal"):
		n = (result.normal as Vector3).normalized()
	else:
		n = Vector3.UP
	global_position = result.position + n * 0.06
	global_transform = Transform3D(_basis_with_y_up(n), global_position)
	_age_since_stuck = 0.0


func _terrain_ray_collision_mask() -> int:
	var exclude_player_bit: int = 1 << (PLAYER_LAYER - 1)
	return 0xFFFFFFFF ^ exclude_player_bit


func _scan_detonate() -> void:
	if shooter_node == null or not is_instance_valid(shooter_node):
		var w := get_parent()
		if w != null:
			shooter_node = w.get_node_or_null(str(shooter_peer_id))
	if shooter_node == null:
		return
	var shooter_team: int = int(shooter_node.team_id)
	var candidates: Array = SplashOverlap.character_bodies_in_sphere(
		get_world_3d(),
		global_position,
		TRIGGER_RADIUS,
		PLAYER_LAYER,
		[]
	)
	for body in candidates:
		if body.get("is_dead") == true:
			continue
		if int(body.team_id) == shooter_team:
			continue
		_triggered = true
		set_physics_process(false)
		_detonate()
		return


func _detonate() -> void:
	var n: Vector3 = global_transform.basis.y.normalized()
	if n.length_squared() < 1e-8:
		n = Vector3.UP
	var pos := global_position
	# Damage + Binbun explosion broadcast: authoritative shooter only (matches tank shell sync).
	if _is_explosive_tank() and HeroNet.is_shooter_peer(shooter_peer_id):
		_apply_damage_at(pos)
		_spawn_explosion_networked(pos, n)
	queue_free()


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


func _apply_damage_at(pos: Vector3) -> void:
	var w := get_parent()
	if w == null:
		return
	var shooter := shooter_node
	if shooter == null or not is_instance_valid(shooter):
		shooter = w.get_node_or_null(str(shooter_peer_id))
	if shooter == null:
		return
	var shooter_team: int = int(shooter.team_id)
	var candidates: Array = SplashOverlap.character_bodies_in_sphere(
		get_world_3d(),
		pos,
		DAMAGE_RADIUS,
		PLAYER_LAYER,
		[]
	)
	for body in candidates:
		if body.get("is_dead") == true:
			continue
		if int(body.team_id) == shooter_team:
			continue
		HeroNet.apply_damage_on_victim(body, LANDMINE_DAMAGE, shooter_peer_id)
		if w.has_method("record_damaged_by_me"):
			w.record_damaged_by_me(body.name.to_int())


func _spawn_explosion_networked(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	const LANDMINE_VFX_SCALE := 0.5
	if _is_explosive_tank():
		var w := get_parent()
		if w == null:
			return
		if not HeroNet.has_multiplayer_session():
			if w.has_method("spawn_tank_landmine_impact_vfx_at"):
				w.spawn_tank_landmine_impact_vfx_at(pos, normal, LANDMINE_VFX_SCALE)
		elif HeroNet.is_shooter_peer(shooter_peer_id):
			if HeroNet.is_gdsync() and w.has_method("_spawn_tank_landmine_impact_binbun_at"):
				GDSync.call_func_all(
					Callable(w, "_spawn_tank_landmine_impact_binbun_at"),
					[pos, normal, LANDMINE_VFX_SCALE]
				)
			elif w.has_method("sync_tank_landmine_impact_vfx"):
				w.sync_tank_landmine_impact_vfx.rpc(pos, normal, LANDMINE_VFX_SCALE)
	else:
		var expl := ExplosionPlaceholderScene.instantiate()
		expl.global_position = pos
		get_parent().add_child(expl)


func _is_explosive_tank() -> bool:
	var sn := shooter_node
	if sn == null or not is_instance_valid(sn):
		var w := get_parent()
		if w != null:
			sn = w.get_node_or_null(str(shooter_peer_id))
	if sn == null:
		return false
	return str(sn.get("hero_id")) == "tank_explosive"


func _get_local_player_node() -> Node:
	var w := get_parent()
	if w == null:
		return null
	return w.get_node_or_null(str(HeroNet.my_id()))


func _mine_is_hostile_to_local_viewer() -> bool:
	var me := _get_local_player_node()
	if me == null or shooter_node == null:
		return false
	return int(me.get("team_id")) != int(shooter_node.get("team_id"))


## Imported landmine.blend ships its own materials/texture; team color identification is handled
## elsewhere (overhead bar, kill feed). Keeping the function as a no-op so callers stay valid.
func _apply_viewer_team_tint() -> void:
	return


func _collect_visual_meshes() -> void:
	_mesh_instances.clear()
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst != null:
			_mesh_instances.append(mesh_inst)

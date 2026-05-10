extends Node3D

## 0 = primary shell, 1 = secondary (knockback, larger splash, different VFX).
enum ShellKind { PRIMARY = 0, SECONDARY_KNOCKBACK = 1 }

@export var speed: float = 40.0
@export var lifetime_sec: float = 5.0

const ExplosionPlaceholderScene = preload("res://explosion_placeholder.tscn")
const TankSecondarySfx: AudioStream = preload("res://assets/sounds/effects/tanksecondary.wav")

const SPLASH_DAMAGE_PRIMARY: int = 30
const SPLASH_DAMAGE_SECONDARY: int = 35
## Secondary splash radius multiplier vs primary (hitbox slightly larger).
const SECONDARY_SPLASH_RADIUS_MULT: float = 1.52
const PRIMARY_SPLASH_RADIUS: float = 1.5
## Original kit was ~14; keep that baseline × 1.3 for this shell.
const KNOCKBACK_HORIZONTAL_STRENGTH: float = 14.0 * 1.3
const TANK_SECONDARY_SFX_DB: float = -2.5

## Enemies within splash radius take splash damage.
@export var splash_radius: float = PRIMARY_SPLASH_RADIUS

var shooter_peer_id: int = -1
var shooter_node: Node = null
var velocity: Vector3 = Vector3.ZERO
var elapsed: float = 0.0
var _impacted: bool = false
var shell_kind: int = ShellKind.PRIMARY
var _visual: Node3D = null


func setup(_shooter_peer_id: int, _velocity: Vector3, _shell_kind: int = ShellKind.PRIMARY) -> void:
	shooter_peer_id = _shooter_peer_id
	shooter_node = get_parent().get_node_or_null(str(shooter_peer_id))
	velocity = _velocity
	elapsed = 0.0
	shell_kind = _shell_kind
	_visual = get_node_or_null("Visual") as Node3D
	if shell_kind == ShellKind.SECONDARY_KNOCKBACK:
		splash_radius = PRIMARY_SPLASH_RADIUS * SECONDARY_SPLASH_RADIUS_MULT
		if _visual != null:
			_visual.scale = Vector3(1.5, 1.5, 1.5)
	_face_velocity()


func _face_velocity() -> void:
	if velocity.length_squared() < 1e-8:
		return
	var up_axis: Vector3 = velocity.normalized()
	var side_axis: Vector3 = Vector3.FORWARD.cross(up_axis)
	if side_axis.length_squared() < 1e-8:
		side_axis = Vector3.RIGHT.cross(up_axis)
	side_axis = side_axis.normalized()
	var fwd_axis: Vector3 = side_axis.cross(up_axis).normalized()
	global_basis = Basis(side_axis, up_axis, fwd_axis)


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
		_face_velocity()
		return

	_impacted = true
	set_physics_process(false)
	global_position = result.position
	var blocker: Variant = result.get("collider")
	if blocker != null and blocker.has_method("try_block_projectile"):
		var shooter_team: int = -1
		if shooter_node != null and is_instance_valid(shooter_node):
			shooter_team = int(shooter_node.get("team_id"))
		if bool(blocker.call("try_block_projectile", shooter_team, _splash_damage_amount())):
			queue_free()
			return
	var impact_normal: Vector3 = Vector3.UP
	if result.has("normal"):
		impact_normal = (result.normal as Vector3).normalized()
	if _is_explosive_tank() and HeroNet.is_shooter_peer(shooter_peer_id):
		_apply_explosive_splash_at(global_position)
	_spawn_explosion(global_position, impact_normal)
	queue_free()


func _splash_damage_amount() -> int:
	if shell_kind == ShellKind.SECONDARY_KNOCKBACK:
		return SPLASH_DAMAGE_SECONDARY
	return SPLASH_DAMAGE_PRIMARY


func _spawn_explosion(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	if shell_kind == ShellKind.SECONDARY_KNOCKBACK:
		_play_tank_secondary_explosion_sfx(pos)
	if _is_explosive_tank():
		var w := get_parent()
		if w == null:
			return
		if not HeroNet.has_multiplayer_session():
			if shell_kind == ShellKind.SECONDARY_KNOCKBACK:
				if w.has_method("spawn_tank_secondary_explosion_vfx_at"):
					w.spawn_tank_secondary_explosion_vfx_at(pos, normal)
			else:
				if w.has_method("spawn_tank_explosion_vfx_at"):
					w.spawn_tank_explosion_vfx_at(pos, normal)
		elif HeroNet.is_shooter_peer(shooter_peer_id):
			if shell_kind == ShellKind.SECONDARY_KNOCKBACK:
				if HeroNet.is_gdsync() and w.has_method("_spawn_tank_secondary_explosion_binbun_at"):
					GDSync.call_func_all(Callable(w, "_spawn_tank_secondary_explosion_binbun_at"), [pos, normal])
				elif w.has_method("sync_tank_secondary_explosion_vfx"):
					w.sync_tank_secondary_explosion_vfx.rpc(pos, normal)
			else:
				if HeroNet.is_gdsync() and w.has_method("_spawn_tank_binbun_explosion_at"):
					GDSync.call_func_all(Callable(w, "_spawn_tank_binbun_explosion_at"), [pos, normal])
				elif w.has_method("sync_tank_explosion_vfx"):
					w.sync_tank_explosion_vfx.rpc(pos, normal)
	else:
		var expl := ExplosionPlaceholderScene.instantiate()
		expl.global_position = pos
		get_parent().add_child(expl)


func _play_tank_secondary_explosion_sfx(pos: Vector3) -> void:
	if TankSecondarySfx == null:
		return
	var w: Node = get_parent()
	if w == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = TankSecondarySfx
	p.bus = "Master"
	p.max_distance = 40.0
	p.unit_size = 5.0
	p.volume_db = TANK_SECONDARY_SFX_DB
	p.global_position = pos
	w.add_child(p)
	p.play()
	var life_sec: float = maxf(0.4, TankSecondarySfx.get_length() + 0.2)
	get_tree().create_timer(life_sec).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)


func _is_explosive_tank() -> bool:
	var sn := shooter_node
	if sn == null or not is_instance_valid(sn):
		var w := get_parent()
		if w != null:
			sn = w.get_node_or_null(str(shooter_peer_id))
	if sn == null:
		return false
	return str(sn.get("hero_id")) == "tank_explosive"


func _apply_explosive_splash_at(pos: Vector3) -> void:
	var w := get_parent()
	if w == null:
		return
	var shooter := shooter_node
	if shooter == null or not is_instance_valid(shooter):
		shooter = w.get_node_or_null(str(shooter_peer_id))
	if shooter == null:
		return
	var shooter_team: int = int(shooter.team_id)
	const PLAYER_LAYER := 2
	var dmg: int = _splash_damage_amount()
	var candidates: Array = SplashOverlap.character_bodies_in_sphere(
		get_world_3d(),
		pos,
		splash_radius,
		PLAYER_LAYER,
		[]
	)
	for body in candidates:
		if body.get("is_dead") == true:
			continue
		if int(body.team_id) == shooter_team:
			continue
		HeroNet.apply_damage_on_victim(body, dmg, shooter_peer_id)
		if w.has_method("record_damaged_by_me"):
			w.record_damaged_by_me(body.name.to_int())
		if shell_kind == ShellKind.SECONDARY_KNOCKBACK:
			HeroNet.apply_explosion_knockback_on_victim(body, pos, KNOCKBACK_HORIZONTAL_STRENGTH)

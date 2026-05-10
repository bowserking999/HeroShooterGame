extends Node3D

@export var speed: float = 42.0
@export var lifetime_sec: float = 5.0
@export var splash_radius: float = 0.5

const BURST_DAMAGE: int = 20
const PLAYER_LAYER: int = 2
const BURST_PRIMARY := Color(0.82, 0.2, 1.0, 1.0)
const BURST_SECONDARY := Color(0.62, 0.12, 0.95, 1.0)
const BURST_TERTIARY := Color(0.32, 0.04, 0.74, 1.0)

@onready var _burst_vfx: Node3D = $BurstVFX

var shooter_peer_id: int = -1
var shooter_node: Node = null
var velocity: Vector3 = Vector3.ZERO
var elapsed: float = 0.0
var _impacted: bool = false


func _ready() -> void:
	_tint_flight_vfx()


func setup(_shooter_peer_id: int, _velocity: Vector3) -> void:
	shooter_peer_id = _shooter_peer_id
	shooter_node = get_parent().get_node_or_null(str(shooter_peer_id))
	velocity = _velocity
	elapsed = 0.0
	_look_in_velocity_direction()


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
		_look_in_velocity_direction()
		return
	_impacted = true
	set_physics_process(false)
	global_position = result.position
	var blocker: Variant = result.get("collider")
	if blocker != null and blocker.has_method("try_block_projectile"):
		var shooter_team: int = -1
		if shooter_node != null and is_instance_valid(shooter_node):
			shooter_team = int(shooter_node.get("team_id"))
		if bool(blocker.call("try_block_projectile", shooter_team, BURST_DAMAGE)):
			queue_free()
			return
	var impact_normal: Vector3 = Vector3.UP
	if result.has("normal"):
		impact_normal = (result.normal as Vector3).normalized()
	if HeroNet.is_shooter_peer(shooter_peer_id):
		_apply_splash_damage(global_position)
	_spawn_impact_vfx(global_position, impact_normal)
	queue_free()


func _apply_splash_damage(pos: Vector3) -> void:
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
		splash_radius,
		PLAYER_LAYER,
		[]
	)
	for body in candidates:
		if body.get("is_dead") == true:
			continue
		var body_team: Variant = body.get("team_id")
		if typeof(body_team) != TYPE_INT or int(body_team) == shooter_team:
			continue
		HeroNet.apply_damage_on_victim(body, BURST_DAMAGE, shooter_peer_id)
		if w.has_method("record_damaged_by_me"):
			w.record_damaged_by_me(body.name.to_int())


func _spawn_impact_vfx(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	var w := get_parent()
	if w == null:
		return
	# Online, every peer simulates this projectile. Only the shooter emits one world RPC
	# so the impact VFX appears exactly once per machine.
	if not HeroNet.has_multiplayer_session():
		if w.has_method("spawn_medic_burst_impact_vfx_at"):
			w.spawn_medic_burst_impact_vfx_at(pos, normal)
	elif HeroNet.is_shooter_peer(shooter_peer_id):
		if HeroNet.is_gdsync() and w.has_method("_spawn_medic_burst_impact_vfx_at"):
			GDSync.call_func_all(Callable(w, "_spawn_medic_burst_impact_vfx_at"), [pos, normal])
		elif w.has_method("sync_medic_burst_impact_vfx"):
			w.sync_medic_burst_impact_vfx.rpc(pos, normal)


func _tint_flight_vfx() -> void:
	if _burst_vfx == null:
		return
	_burst_vfx.set("autoplay", true)
	_burst_vfx.set("one_shot", false)
	_burst_vfx.set("primary_color", BURST_PRIMARY)
	_burst_vfx.set("secondary_color", BURST_SECONDARY)
	_burst_vfx.set("tertiary_color", BURST_TERTIARY)
	_burst_vfx.set("light_color", BURST_PRIMARY)
	_force_tint_recursive(_burst_vfx)


func _look_in_velocity_direction() -> void:
	if velocity.length_squared() < 1e-8:
		return
	look_at(global_position + velocity.normalized(), Vector3.UP)


func _force_tint_recursive(root: Node) -> void:
	for c in root.get_children():
		_force_tint_recursive(c)
	if root is OmniLight3D:
		(root as OmniLight3D).light_color = BURST_PRIMARY
		return
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var mat := mi.material_override
		if mat is StandardMaterial3D:
			var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			sm.albedo_color = BURST_PRIMARY
			sm.emission_enabled = true
			sm.emission = BURST_PRIMARY
			mi.material_override = sm
		elif mat is ShaderMaterial:
			var sh := (mat as ShaderMaterial).duplicate() as ShaderMaterial
			if sh.get_shader_parameter("primary_color") != null:
				sh.set_shader_parameter("primary_color", BURST_PRIMARY)
			if sh.get_shader_parameter("secondary_color") != null:
				sh.set_shader_parameter("secondary_color", BURST_SECONDARY)
			if sh.get_shader_parameter("tertiary_color") != null:
				sh.set_shader_parameter("tertiary_color", BURST_TERTIARY)
			mi.material_override = sh
		return
	if root is GPUParticles3D:
		var gp := root as GPUParticles3D
		var pmat := gp.material_override
		if pmat is ShaderMaterial:
			var psh := (pmat as ShaderMaterial).duplicate() as ShaderMaterial
			if psh.get_shader_parameter("primary_color") != null:
				psh.set_shader_parameter("primary_color", BURST_PRIMARY)
			if psh.get_shader_parameter("secondary_color") != null:
				psh.set_shader_parameter("secondary_color", BURST_SECONDARY)
			if psh.get_shader_parameter("tertiary_color") != null:
				psh.set_shader_parameter("tertiary_color", BURST_TERTIARY)
			gp.material_override = psh

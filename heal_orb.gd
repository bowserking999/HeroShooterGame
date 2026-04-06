extends Node3D

# Healer projectile: allies heal only from the moving aura (no burst on pass-through).
# Networking: every peer simulates motion; only the shooter applies heal RPCs.
# Orbs from enemies use red VFX for the local viewer (same idea as ally/enemy health bar colors).

const MagicOrbFlareVfxScene := preload("res://assets/BinbunVFX/magic_orbs/effects/magic_orb_flare/magic_orb_flare_vfx_04.tscn")
const MagicOrbHugeVfxScene := preload("res://assets/BinbunVFX/magic_orbs/effects/magic_orb_huge/magic_orb_huge_vfx_01.tscn")
const MAGIC_ORB_VFX_SCALE := 0.42
const AURA_RADIUS := 4.75
const AURA_HEAL_INTERVAL := 0.25
const AURA_HEAL_AMOUNT := 5
const ALLY_IN_AURA_SPEED_MULT := 0.25
const PLAYER_COLLISION_MASK := 2
const MAX_ORBS_ALIVE := 5
## Emission / light scaling (reverted from the extra “super dim” pass).
const HUGE_AURA_EMISSION_MULT := 0.45
const HUGE_AURA_LIGHT_MULT := 0.4
## 75% transparent → multiply shader alpha by remaining opacity (25%).
const HUGE_AURA_ALPHA_OPAQUE := 0.25
## Enemy-orb palette centered on #f55b38.
const HOSTILE_PRIMARY := Color(245.0 / 255.0, 91.0 / 255.0, 56.0 / 255.0, 1)
const HOSTILE_SECONDARY := Color(0.48, 0.14, 0.09, 1)
const HOSTILE_TERTIARY := Color(0.32, 0.09, 0.06, 1)

static var _active_orbs: Array[Node] = []

@export var lifetime_sec: float = 5.0
@export var bounce_energy: float = 0.85

var shooter_peer_id: int = -1
var shooter_node: Node = null
var velocity: Vector3 = Vector3.ZERO
var elapsed: float = 0.0

var _flare_vfx: Node3D
var _huge_vfx: Node3D
var _aura_area: Area3D
var _aura_tick_accum: float = 0.0


func _ready() -> void:
	_enforce_orb_cap()
	_setup_magic_orb_flare_visual()
	_setup_magic_orb_huge_visual()
	_setup_aura_area()


func _exit_tree() -> void:
	var i := _active_orbs.find(self)
	if i >= 0:
		_active_orbs.remove_at(i)


func _enforce_orb_cap() -> void:
	_active_orbs.append(self)
	while _active_orbs.size() > MAX_ORBS_ALIVE:
		var oldest: Node = _active_orbs.pop_front()
		if oldest != null and is_instance_valid(oldest) and oldest != self:
			oldest.queue_free()


func _setup_magic_orb_flare_visual() -> void:
	var mesh_inst := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_inst:
		mesh_inst.visible = false
	var vfx_root := MagicOrbFlareVfxScene.instantiate() as Node3D
	vfx_root.name = "MagicOrbFlareV04"
	vfx_root.scale = Vector3.ONE * MAGIC_ORB_VFX_SCALE
	vfx_root.set_script(null)
	_flare_vfx = vfx_root
	add_child(vfx_root)
	_start_looped_main_animation(vfx_root)


func _setup_magic_orb_huge_visual() -> void:
	var vfx_root := MagicOrbHugeVfxScene.instantiate() as Node3D
	vfx_root.name = "MagicOrbHugeVFX01"
	var vfx_scale := AURA_RADIUS / 2.0
	vfx_root.scale = Vector3.ONE * vfx_scale
	vfx_root.set_script(null)
	_huge_vfx = vfx_root
	add_child(vfx_root)
	_start_looped_main_animation(vfx_root)
	_dim_huge_aura_visual(vfx_root)


func _dim_huge_aura_visual(root: Node) -> void:
	for c in root.get_children():
		_dim_huge_aura_visual(c)
	if root is OmniLight3D:
		var lit := root as OmniLight3D
		lit.light_energy *= HUGE_AURA_LIGHT_MULT
		return
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var mat: Material = mi.material_override
		if mat is ShaderMaterial:
			var sm := (mat as ShaderMaterial).duplicate() as ShaderMaterial
			var a: Variant = sm.get_shader_parameter("alpha_multiplier")
			if a != null:
				sm.set_shader_parameter("alpha_multiplier", float(a) * HUGE_AURA_ALPHA_OPAQUE)
			var e: Variant = sm.get_shader_parameter("emission_strength")
			if e != null:
				sm.set_shader_parameter("emission_strength", float(e) * HUGE_AURA_EMISSION_MULT)
			mi.material_override = sm


func _start_looped_main_animation(vfx_root: Node) -> void:
	var ap := vfx_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	for lib_name in ap.get_animation_library_list():
		var lib: AnimationLibrary = ap.get_animation_library(lib_name)
		if not lib.has_animation("main"):
			continue
		var base: Animation = lib.get_animation("main")
		var looped: Animation = base.duplicate()
		looped.loop_mode = Animation.LOOP_LINEAR
		lib.remove_animation("main")
		lib.add_animation("main", looped)
		break
	ap.play("main")


func _setup_aura_area() -> void:
	_aura_area = Area3D.new()
	_aura_area.name = "HealAura"
	_aura_area.collision_layer = 0
	_aura_area.collision_mask = PLAYER_COLLISION_MASK
	_aura_area.monitoring = true
	_aura_area.monitorable = false
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = AURA_RADIUS
	col.shape = sphere
	_aura_area.add_child(col)
	add_child(_aura_area)


func setup(_shooter_peer_id: int, _velocity: Vector3) -> void:
	shooter_peer_id = _shooter_peer_id
	shooter_node = get_parent().get_node_or_null(str(shooter_peer_id))
	velocity = _velocity
	elapsed = 0.0
	_aura_tick_accum = 0.0
	_apply_viewer_team_visuals()


func _get_local_player_node() -> Node:
	var w := get_parent()
	if w == null:
		return null
	return w.get_node_or_null(str(multiplayer.get_unique_id()))


func _is_orb_hostile_to_local_viewer() -> bool:
	var me := _get_local_player_node()
	if me == null or shooter_node == null:
		return false
	return int(me.get("team_id")) != int(shooter_node.get("team_id"))


func _apply_viewer_team_visuals() -> void:
	if not _is_orb_hostile_to_local_viewer():
		return
	if _flare_vfx != null:
		_tint_vfx_hostile(_flare_vfx)
	if _huge_vfx != null:
		_tint_vfx_hostile(_huge_vfx)


func _tint_vfx_hostile(root: Node) -> void:
	for c in root.get_children():
		_tint_vfx_hostile(c)
	if root is OmniLight3D:
		var lit := root as OmniLight3D
		lit.light_color = HOSTILE_PRIMARY
		return
	if root is GPUParticles3D:
		var gp := root as GPUParticles3D
		var mat: Material = gp.material_override
		if mat is ShaderMaterial:
			gp.material_override = _hostile_duplicate_shader(mat as ShaderMaterial)
		return
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var mat := mi.material_override
		if mat is ShaderMaterial:
			mi.material_override = _hostile_duplicate_shader(mat as ShaderMaterial)


func _hostile_duplicate_shader(src: ShaderMaterial) -> ShaderMaterial:
	var sm := src.duplicate() as ShaderMaterial
	if sm.get_shader_parameter("primary_color") != null:
		sm.set_shader_parameter("primary_color", HOSTILE_PRIMARY)
	if sm.get_shader_parameter("secondary_color") != null:
		sm.set_shader_parameter("secondary_color", HOSTILE_SECONDARY)
	if sm.get_shader_parameter("tertiary_color") != null:
		sm.set_shader_parameter("tertiary_color", HOSTILE_TERTIARY)
	return sm


func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed >= lifetime_sec:
		queue_free()
		return

	var from := global_position
	var move_mult := 1.0
	if shooter_node != null and _aura_area != null and not _gather_aura_allies_for_slow().is_empty():
		move_mult = ALLY_IN_AURA_SPEED_MULT
	var to := from + velocity * delta * move_mult

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
	else:
		global_position = result.position

		var normal: Vector3 = result.normal
		var collider: Object = result.collider

		var should_bounce := true
		if collider is Node:
			var n := collider as Node
			if n.has_method("receive_damage") or n.has_method("heal_damage"):
				should_bounce = false

		if not should_bounce:
			var forward := velocity.normalized()
			global_position += forward * 0.05
		else:
			velocity = velocity.bounce(normal) * bounce_energy

	if multiplayer.get_unique_id() == shooter_peer_id:
		_tick_aura_heal(delta)


func _tick_aura_heal(delta: float) -> void:
	if shooter_node == null or _aura_area == null:
		return
	_aura_tick_accum += delta
	while _aura_tick_accum >= AURA_HEAL_INTERVAL:
		_aura_tick_accum -= AURA_HEAL_INTERVAL
		_apply_aura_heals_once()


func _ally_filter_base(n: Node) -> bool:
	if not n.has_method("heal_damage"):
		return false
	if shooter_node == null:
		return false
	var shooter_team := int(shooter_node.get("team_id"))
	if int(n.get("team_id")) != shooter_team:
		return false
	if n.get("is_dead") == true:
		return false
	return true


func _gather_aura_allies_for_slow() -> Array[Node]:
	var allies: Array[Node] = []
	if _aura_area == null:
		return allies
	for body in _aura_area.get_overlapping_bodies():
		if not (body is Node):
			continue
		var n := body as Node
		if not _ally_filter_base(n):
			continue
		if n.name.to_int() == shooter_peer_id:
			continue
		allies.append(n)
	return allies


func _gather_aura_allies() -> Array[Node]:
	var allies: Array[Node] = []
	if _aura_area == null or shooter_node == null:
		return allies
	for body in _aura_area.get_overlapping_bodies():
		if not (body is Node):
			continue
		var n := body as Node
		if not _ally_filter_base(n):
			continue
		allies.append(n)
	return allies


func _apply_aura_heals_once() -> void:
	for n in _gather_aura_allies():
		n.heal_damage.rpc_id(n.get_multiplayer_authority(), AURA_HEAL_AMOUNT)

extends Node3D

# Orb projectile: moving aura heals allies and damages enemies (no burst on pass-through).
# Networking: every peer simulates motion; only the shooter applies heal/damage RPCs.
# Orbs from enemies use red VFX for the local viewer (same idea as ally/enemy health bar colors).

const MagicOrbFlareVfxScene := preload("res://assets/BinbunVFX/magic_orbs/effects/magic_orb_flare/magic_orb_flare_vfx_04.tscn")
const MagicOrbHugeVfxScene := preload("res://assets/BinbunVFX/magic_orbs/effects/magic_orb_huge/magic_orb_huge_vfx_01.tscn")
const MAGIC_ORB_VFX_SCALE := 0.42
const AURA_RADIUS := 4.75
const AURA_HEAL_INTERVAL := 0.25
const AURA_HEAL_AMOUNT := 10
## Spinning ult orbs: slightly lower ally heal per tick than primary orb aura.
const ORBIT_ULT_AURA_HEAL_MULT := 0.82
const AURA_DAMAGE_AMOUNT := 4
const ALLY_IN_AURA_SPEED_MULT := 0.25
const ENEMY_IN_AURA_SPEED_MULT := 0.25
const PLAYER_COLLISION_MASK := 2
const MAX_ORBS_ALIVE := 3
## Emission / light scaling (reverted from the extra “super dim” pass).
const HUGE_AURA_EMISSION_MULT := 0.45
const HUGE_AURA_LIGHT_MULT := 0.4
## 75% transparent → multiply shader alpha by remaining opacity (25%).
const HUGE_AURA_ALPHA_OPAQUE := 0.25
## After lifetime: aura off + no combat; core VFX shrinks while physics keeps running.
const DESPAWN_SHRINK_DURATION_SEC: float = 0.35
## Enemy-orb palette centered on #f55b38.
const HOSTILE_PRIMARY := Color(245.0 / 255.0, 91.0 / 255.0, 56.0 / 255.0, 1)
const HOSTILE_SECONDARY := Color(0.48, 0.14, 0.09, 1)
const HOSTILE_TERTIARY := Color(0.32, 0.09, 0.06, 1)
const ORB_BOUNCE_SFX_PATH := "res://assets/sounds/effects/orbshoot.wav"
const ORB_BOUNCE_VOLUME_DB := -2.0

static var _active_orbs: Array[Node] = []

## Ultimate-launched orbs: skip global orb cap (only despawn from lifetime / shrink end).
var _exempt_from_orb_cap: bool = false

@export var lifetime_sec: float = 5.0

var shooter_peer_id: int = -1
var shooter_node: Node = null
var velocity: Vector3 = Vector3.ZERO
## Wall bounces reflect direction only; magnitude stays at spawn speed (no per-bounce damping).
var _travel_speed: float = 25.0
var elapsed: float = 0.0
var _visual_only_mode: bool = false
## Orb healer ultimate: position comes from the player each frame; aura heal/damage matches normal orbs.
var _orbit_ultimate_follow: bool = false

var _flare_vfx: Node3D
var _huge_vfx: Node3D
var _aura_area: Area3D
var _aura_tick_accum: float = 0.0
var _despawning: bool = false
var _despawn_elapsed: float = 0.0
## Billboard flare meshes ignore parent scale; we shrink QuadMesh/SphereMesh sizes instead.
var _flare_quad_base_size: Vector2 = Vector2.ONE
var _glow_quad_base_size: Vector2 = Vector2.ONE
var _inner_sphere_radius_base: float = 0.3
var _inner_sphere_height_base: float = 0.6
var _despawn_mesh_bases_ready: bool = false
var _bounce_audio: AudioStreamPlayer3D = null
var _bounce_stream: AudioStream = null


func set_exempt_from_orb_cap(exempt: bool = true) -> void:
	_exempt_from_orb_cap = exempt


func _ready() -> void:
	if not _visual_only_mode and not _exempt_from_orb_cap:
		_enforce_orb_cap()
	_setup_magic_orb_flare_visual()
	# Ult orbit placeholders: flare only (no huge aura ring — matches "no ring outlines" during ult).
	if not _visual_only_mode:
		_setup_magic_orb_huge_visual()
	if not _visual_only_mode:
		_setup_aura_area()
	if shooter_peer_id >= 0 and shooter_node == null and get_parent() != null:
		shooter_node = get_parent().get_node_or_null(str(shooter_peer_id))
	_apply_viewer_team_visuals()
	_setup_orb_bounce_audio()


func _setup_orb_bounce_audio() -> void:
	var res: Resource = load(ORB_BOUNCE_SFX_PATH)
	if res is AudioStream:
		_bounce_stream = res as AudioStream
	elif not ResourceLoader.exists(ORB_BOUNCE_SFX_PATH):
		push_warning("Orb bounce/shoot WAV missing: %s" % ORB_BOUNCE_SFX_PATH)
	else:
		push_warning("Orb bounce SFX failed to load (reimport in editor): %s" % ORB_BOUNCE_SFX_PATH)
	var p := AudioStreamPlayer3D.new()
	p.name = "OrbBounceSfx"
	p.bus = "Master"
	p.max_distance = 36.0
	p.unit_size = 5.5
	p.max_polyphony = 8
	p.attenuation_filter_cutoff_hz = 20500.0
	p.attenuation_filter_db = 0.0
	add_child(p)
	_bounce_audio = p


func _play_orb_bounce_sfx() -> void:
	if _bounce_audio == null or _bounce_stream == null:
		return
	_bounce_audio.stream = _bounce_stream
	_bounce_audio.volume_db = ORB_BOUNCE_VOLUME_DB
	_bounce_audio.pitch_scale = randf_range(0.94, 1.07)
	_bounce_audio.play()


func _exit_tree() -> void:
	var i := _active_orbs.find(self)
	if i >= 0:
		_active_orbs.remove_at(i)


func _enforce_orb_cap() -> void:
	_active_orbs.append(self)
	while _active_orbs.size() > MAX_ORBS_ALIVE:
		var oldest: Node = _active_orbs.pop_front()
		if oldest != null and is_instance_valid(oldest) and oldest != self:
			if oldest.has_method("begin_forced_despawn"):
				oldest.call("begin_forced_despawn")
			else:
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
	_disable_orb_vfx_lights(vfx_root)


func _setup_magic_orb_huge_visual() -> void:
	var vfx_root := MagicOrbHugeVfxScene.instantiate() as Node3D
	vfx_root.name = "MagicOrbHugeVFX01"
	var vfx_scale := AURA_RADIUS / 2.0
	vfx_root.scale = Vector3.ONE * vfx_scale
	vfx_root.set_script(null)
	_huge_vfx = vfx_root
	add_child(vfx_root)
	# huge_vfx "main" animation keys alpha_multiplier to 1.0 every loop — strip those tracks so _dim_huge_aura_visual sticks.
	_start_looped_main_animation_huge(vfx_root)
	_dim_huge_aura_visual(vfx_root)
	_disable_orb_vfx_lights(vfx_root)


func _disable_orb_vfx_lights(root: Node) -> void:
	for c in root.get_children():
		_disable_orb_vfx_lights(c)
	if root is Light3D:
		var l := root as Light3D
		l.visible = false
		l.light_energy = 0.0
		l.shadow_enabled = false


func _strip_alpha_multiplier_tracks(anim: Animation) -> void:
	var i := anim.get_track_count() - 1
	while i >= 0:
		var path_str := str(anim.track_get_path(i))
		if path_str.contains("shader_parameter/alpha_multiplier"):
			anim.remove_track(i)
		i -= 1


func _start_looped_main_animation_huge(vfx_root: Node) -> void:
	var ap := vfx_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	for lib_name in ap.get_animation_library_list():
		var lib: AnimationLibrary = ap.get_animation_library(lib_name)
		if not lib.has_animation("main"):
			continue
		var base: Animation = lib.get_animation("main")
		var looped: Animation = base.duplicate()
		_strip_alpha_multiplier_tracks(looped)
		looped.loop_mode = Animation.LOOP_LINEAR
		lib.remove_animation("main")
		lib.add_animation("main", looped)
		break
	ap.play("main")


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
	_travel_speed = maxf(_velocity.length(), 0.01)
	elapsed = 0.0
	_aura_tick_accum = 0.0
	_apply_viewer_team_visuals()


func _get_local_player_node() -> Node:
	var w := get_parent()
	if w == null:
		return null
	return w.get_node_or_null(str(HeroNet.my_id()))


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
	if _visual_only_mode:
		return

	if _orbit_ultimate_follow:
		if shooter_peer_id >= 0 and (shooter_node == null or not is_instance_valid(shooter_node)) and get_parent() != null:
			shooter_node = get_parent().get_node_or_null(str(shooter_peer_id))
		if HeroNet.my_id() == shooter_peer_id:
			_tick_aura_combat(delta)
		return

	elapsed += delta
	if elapsed >= lifetime_sec and not _despawning:
		_begin_despawn()

	if _despawning:
		_despawn_elapsed += delta
		var t: float = clampf(_despawn_elapsed / DESPAWN_SHRINK_DURATION_SEC, 0.0, 1.0)
		# Ease-out shrink; billboard ring/ball meshes need explicit mesh size (see _prepare_despawn_mesh_bases).
		var shrink: float = 1.0 - t * t
		_apply_despawn_visual_shrink(shrink)
		_step_orb_movement(delta, 1.0)
		if _despawn_elapsed >= DESPAWN_SHRINK_DURATION_SEC:
			queue_free()
		return

	var move_mult := 1.0
	if shooter_node != null and _aura_area != null and _aura_area.monitoring:
		if not _gather_aura_allies_for_slow().is_empty():
			move_mult = ALLY_IN_AURA_SPEED_MULT
		elif not _gather_aura_enemies_for_slow().is_empty():
			move_mult = ENEMY_IN_AURA_SPEED_MULT
	_step_orb_movement(delta, move_mult)

	if HeroNet.my_id() == shooter_peer_id:
		_tick_aura_combat(delta)


func begin_forced_despawn() -> void:
	if _visual_only_mode:
		queue_free()
		return
	if _despawning:
		return
	_begin_despawn()


func _prepare_despawn_mesh_bases() -> void:
	if _despawn_mesh_bases_ready:
		return
	_despawn_mesh_bases_ready = true
	if _flare_vfx != null and is_instance_valid(_flare_vfx):
		var flare_mi := _flare_vfx.get_node_or_null("Flare") as MeshInstance3D
		if flare_mi != null and flare_mi.mesh != null:
			flare_mi.mesh = flare_mi.mesh.duplicate()
			if flare_mi.mesh is QuadMesh:
				_flare_quad_base_size = (flare_mi.mesh as QuadMesh).size
		var glow_mi := _flare_vfx.get_node_or_null("Glow") as MeshInstance3D
		if glow_mi != null and glow_mi.mesh != null:
			glow_mi.mesh = glow_mi.mesh.duplicate()
			if glow_mi.mesh is QuadMesh:
				_glow_quad_base_size = (glow_mi.mesh as QuadMesh).size
		var inner_mi := _flare_vfx.get_node_or_null("Inner") as MeshInstance3D
		if inner_mi != null and inner_mi.mesh != null:
			inner_mi.mesh = inner_mi.mesh.duplicate()
			if inner_mi.mesh is SphereMesh:
				var sm := inner_mi.mesh as SphereMesh
				_inner_sphere_radius_base = sm.radius
				_inner_sphere_height_base = sm.height


func _apply_despawn_visual_shrink(shrink: float) -> void:
	shrink = maxf(shrink, 0.001)
	if _flare_vfx != null and is_instance_valid(_flare_vfx):
		var flare_mi := _flare_vfx.get_node_or_null("Flare") as MeshInstance3D
		if flare_mi != null and flare_mi.mesh is QuadMesh:
			(flare_mi.mesh as QuadMesh).size = _flare_quad_base_size * shrink
		var glow_mi := _flare_vfx.get_node_or_null("Glow") as MeshInstance3D
		if glow_mi != null and glow_mi.mesh is QuadMesh:
			(glow_mi.mesh as QuadMesh).size = _glow_quad_base_size * shrink
		var inner_mi := _flare_vfx.get_node_or_null("Inner") as MeshInstance3D
		if inner_mi != null and inner_mi.mesh is SphereMesh:
			var sm := inner_mi.mesh as SphereMesh
			sm.radius = maxf(0.001, _inner_sphere_radius_base * shrink)
			sm.height = maxf(0.001, _inner_sphere_height_base * shrink)
	scale = Vector3.ONE


func _begin_despawn() -> void:
	_despawning = true
	_despawn_elapsed = 0.0
	_prepare_despawn_mesh_bases()
	if _huge_vfx != null and is_instance_valid(_huge_vfx):
		_huge_vfx.visible = false
	if _aura_area != null and is_instance_valid(_aura_area):
		_aura_area.monitoring = false
		for c in _aura_area.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = true


func _step_orb_movement(delta: float, move_mult: float) -> void:
	var from := global_position
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
			var bounced: Vector3 = velocity.bounce(normal)
			if bounced.length_squared() > 1e-10:
				velocity = bounced.normalized() * _travel_speed
				_play_orb_bounce_sfx()


func _tick_aura_combat(delta: float) -> void:
	if _despawning:
		return
	if shooter_node == null or _aura_area == null or not _aura_area.monitoring:
		return
	_aura_tick_accum += delta
	while _aura_tick_accum >= AURA_HEAL_INTERVAL:
		_aura_tick_accum -= AURA_HEAL_INTERVAL
		_apply_aura_heals_once()
		_apply_aura_damage_once()


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


func _enemy_filter_damage(n: Node) -> bool:
	if not n.has_method("receive_damage"):
		return false
	if shooter_node == null:
		return false
	if int(n.get("team_id")) == int(shooter_node.get("team_id")):
		return false
	if n.get("is_dead") == true:
		return false
	return true


func _gather_aura_enemies_for_slow() -> Array[Node]:
	var enemies: Array[Node] = []
	if _aura_area == null:
		return enemies
	for body in _aura_area.get_overlapping_bodies():
		if not (body is Node):
			continue
		var n := body as Node
		if not _enemy_filter_damage(n):
			continue
		enemies.append(n)
	return enemies


func _gather_aura_enemies() -> Array[Node]:
	return _gather_aura_enemies_for_slow()


func _aura_heal_amount_this_tick() -> int:
	if _orbit_ultimate_follow:
		return maxi(1, int(round(float(AURA_HEAL_AMOUNT) * ORBIT_ULT_AURA_HEAL_MULT)))
	return AURA_HEAL_AMOUNT


func _apply_aura_heals_once() -> void:
	var amt: int = _aura_heal_amount_this_tick()
	for n in _gather_aura_allies():
		HeroNet.apply_heal_on_target(n, amt, shooter_peer_id, _exempt_from_orb_cap)


func _apply_aura_damage_once() -> void:
	var w: Node = get_parent()
	for n in _gather_aura_enemies():
		HeroNet.apply_damage_on_victim(n, AURA_DAMAGE_AMOUNT, shooter_peer_id, _exempt_from_orb_cap)
		if w != null and w.has_method("record_damaged_by_me"):
			w.record_damaged_by_me(n.name.to_int())


func set_visual_only_mode(shooter_id: int = -1) -> void:
	_visual_only_mode = true
	if shooter_id >= 0:
		shooter_peer_id = shooter_id


func configure_orb_ultimate_orbit_spin(shooter_id: int) -> void:
	shooter_peer_id = shooter_id
	_visual_only_mode = false
	_orbit_ultimate_follow = true
	set_exempt_from_orb_cap(true)

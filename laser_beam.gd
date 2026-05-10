extends Node3D

## Muzzle-anchored beam: base cylinder + Binbun laser_vfx_02. Default = ally blue; enemy shooter's beam reads #ff1414 for the local viewer.

const LAZER_HOSTILE_PRIMARY := Color(1.0, 20.0 / 255.0, 20.0 / 255.0, 1)
const LAZER_HOSTILE_SECONDARY := Color(0.78, 0.12, 0.1, 1)
const LAZER_HOSTILE_TERTIARY := Color(0.52, 0.06, 0.08, 1)

@onready var _mesh_inst: MeshInstance3D = $MeshInstance3D
@onready var _end_target: Node3D = $BeamEndTarget
@onready var _vfx: Node3D = $LaserVFX_02

var _shooter_peer_id: int = -1
var _ally_cylinder_mat: StandardMaterial3D
## When true (other players’ beams over RPC/GD-Sync), lerp muzzle/hit toward network targets each physics frame.
var _beam_net_interpolated: bool = false
var _target_start: Vector3 = Vector3.ZERO
var _target_end: Vector3 = Vector3.ZERO
var _smoothed_start: Vector3 = Vector3.ZERO
var _smoothed_end: Vector3 = Vector3.ZERO
var _have_smoothed_state: bool = false
const BEAM_NET_SMOOTH_SPEED := 24.0
const BEAM_NET_SNAP_DIST2 := 100.0 # 10m jump → snap (teleport / first spawn)


func _ready() -> void:
	if _vfx != null and _end_target != null:
		_vfx.end_point = _end_target
	if _mesh_inst != null:
		var m := _mesh_inst.get_surface_override_material(0)
		if m is StandardMaterial3D:
			_ally_cylinder_mat = (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			_mesh_inst.set_surface_override_material(0, _ally_cylinder_mat.duplicate())
	set_physics_process(false)


func set_beam_net_interpolated(enabled: bool) -> void:
	_beam_net_interpolated = enabled
	if not enabled:
		_have_smoothed_state = false
		set_physics_process(false)


func set_shooter_peer_id(peer_id: int) -> void:
	_shooter_peer_id = peer_id
	_apply_viewer_laser_tint()


func _get_local_player_node() -> Node:
	var w: Node = get_parent()
	if w == null:
		return null
	return w.get_node_or_null(str(HeroNet.my_id()))


func _is_laser_hostile_to_local_viewer() -> bool:
	var me := _get_local_player_node()
	var shooter := get_parent().get_node_or_null(str(_shooter_peer_id)) if _shooter_peer_id >= 0 else null
	if me == null or shooter == null:
		return false
	return int(me.get("team_id")) != int(shooter.get("team_id"))


func _apply_viewer_laser_tint() -> void:
	if _is_laser_hostile_to_local_viewer():
		_apply_hostile_laser_look()
	else:
		_apply_ally_laser_look()


func _apply_ally_laser_look() -> void:
	if _mesh_inst != null and _ally_cylinder_mat != null:
		_mesh_inst.set_surface_override_material(0, _ally_cylinder_mat.duplicate())


func _apply_hostile_laser_look() -> void:
	if _mesh_inst != null and _ally_cylinder_mat != null:
		var m := _ally_cylinder_mat.duplicate() as StandardMaterial3D
		m.albedo_color = Color(LAZER_HOSTILE_PRIMARY.r, LAZER_HOSTILE_PRIMARY.g, LAZER_HOSTILE_PRIMARY.b, 0.35)
		m.emission = Color(LAZER_HOSTILE_PRIMARY.r * 0.95, LAZER_HOSTILE_PRIMARY.g, LAZER_HOSTILE_PRIMARY.b, 1.0)
		m.emission_energy_multiplier = _ally_cylinder_mat.emission_energy_multiplier
		_mesh_inst.set_surface_override_material(0, m)
	if _vfx != null:
		_tint_laser_vfx_hostile(_vfx)


func _tint_laser_vfx_hostile(root: Node) -> void:
	for c in root.get_children():
		_tint_laser_vfx_hostile(c)
	if root is OmniLight3D:
		(root as OmniLight3D).light_color = LAZER_HOSTILE_PRIMARY
		return
	if root is GPUParticles3D:
		var gp := root as GPUParticles3D
		var mat: Material = gp.material_override
		if mat is ShaderMaterial:
			gp.material_override = _duplicate_shader_hostile(mat as ShaderMaterial)
		return
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var mat := mi.material_override
		if mat is ShaderMaterial:
			mi.material_override = _duplicate_shader_hostile(mat as ShaderMaterial)


func _duplicate_shader_hostile(src: ShaderMaterial) -> ShaderMaterial:
	var sm := src.duplicate() as ShaderMaterial
	if sm.get_shader_parameter("primary_color") != null:
		sm.set_shader_parameter("primary_color", LAZER_HOSTILE_PRIMARY)
	if sm.get_shader_parameter("secondary_color") != null:
		sm.set_shader_parameter("secondary_color", LAZER_HOSTILE_SECONDARY)
	if sm.get_shader_parameter("tertiary_color") != null:
		sm.set_shader_parameter("tertiary_color", LAZER_HOSTILE_TERTIARY)
	return sm


func update_beam(start_global: Vector3, end_global: Vector3) -> void:
	var dir: Vector3 = end_global - start_global
	var length: float = dir.length()
	if length < 0.02:
		visible = false
		_have_smoothed_state = false
		set_physics_process(false)
		return
	if _beam_net_interpolated:
		_target_start = start_global
		_target_end = end_global
		if not _have_smoothed_state:
			_smoothed_start = start_global
			_smoothed_end = end_global
			_have_smoothed_state = true
			_apply_beam_geometry(_smoothed_start, _smoothed_end)
		elif _smoothed_start.distance_squared_to(_target_start) > BEAM_NET_SNAP_DIST2 \
			or _smoothed_end.distance_squared_to(_target_end) > BEAM_NET_SNAP_DIST2:
			_smoothed_start = _target_start
			_smoothed_end = _target_end
			_apply_beam_geometry(_smoothed_start, _smoothed_end)
		set_physics_process(true)
		return
	set_physics_process(false)
	_apply_beam_geometry(start_global, end_global)


func _physics_process(delta: float) -> void:
	if not _beam_net_interpolated or not _have_smoothed_state:
		return
	var k: float = 1.0 - exp(-BEAM_NET_SMOOTH_SPEED * delta)
	_smoothed_start = _smoothed_start.lerp(_target_start, k)
	_smoothed_end = _smoothed_end.lerp(_target_end, k)
	_apply_beam_geometry(_smoothed_start, _smoothed_end)


func _apply_beam_geometry(start_global: Vector3, end_global: Vector3) -> void:
	var dir: Vector3 = end_global - start_global
	var length: float = dir.length()
	if length < 0.02:
		visible = false
		return
	visible = true
	global_position = start_global
	var up: Vector3 = Vector3.UP
	var dir_n: Vector3 = dir / length
	if absf(dir_n.dot(Vector3.UP)) > 0.98:
		up = Vector3.RIGHT
	look_at(end_global, up)
	_end_target.position = Vector3(0.0, 0.0, -length)
	if _mesh_inst:
		_mesh_inst.position = Vector3(0.0, 0.0, -length * 0.5)
		_mesh_inst.scale = Vector3(1.0, length, 1.0)
	if _vfx != null and _vfx.has_method("follow_node"):
		_vfx.follow_node()

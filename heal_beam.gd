extends Node3D

## TF2-style medigun beam: rigid straight section along gun/view forward, then cubic swoop to ally.
## Lateral: ally forward-right (NE) arcs left to meet their left flank; forward-left (NW) arcs right.
## Smoothing avoids snap when crossing center; extra tip length keeps final approach straight.

const RINGS_ALONG: int = 56
const RADIAL_SEGMENTS: int = 10
const TUBE_RADIUS: float = 0.092
const BEAM_SHADER: Shader = preload("res://heal_beam.gdshader")
const MUZZLE_WAVE_SCALE: float = 0.42
## Wave meshes sit on local -X; basis.x must be -view_forward so pulses run out of the barrel, not into it.
const MUZZLE_WAVE_OUTSET: float = 0.08
## Ally / local-friendly medic beam & muzzle wave (enemy team sees hostile red).
const HEAL_BEAM_RGB_ALLY := Color(0.2, 0.92, 0.48, 1.0)
const HEAL_BEAM_RGB_ENEMY := Color(212.0 / 255.0, 5.0 / 255.0, 2.0 / 255.0, 1.0)
const HEAL_BEAM_ALPHA := 0.26
## Same-team viewers: only draw a prefix of the same Bezier (after full curve setup) so the shape matches the long beam.
const ALLY_BEAM_CURVE_U_MIN: float = 0.88
## Keep a small consistent tail gap from target for ally view (instead of fixed-distance cap from muzzle).
const ALLY_BEAM_TARGET_GAP_M: float = 1.2
## Other players’ medic beams: smooth network pose to reduce 20Hz snap / jitter.
const REMOTE_BEAM_SMOOTH_SPEED: float = 16.0

## Tint + alpha stored per-vertex each frame (shader reads COLOR) — reliable on gl_compatibility.
var _albedo: Color = Color(HEAL_BEAM_RGB_ALLY.r, HEAL_BEAM_RGB_ALLY.g, HEAL_BEAM_RGB_ALLY.b, HEAL_BEAM_ALPHA)
var _emission: Color = Color(0.18, 0.9, 0.42, 1.0)
var _emission_energy: float = 0.0

@export var albedo: Color:
	get:
		return _albedo
	set(v):
		_albedo = Color(v.r, v.g, v.b, HEAL_BEAM_ALPHA)
		_beam_display_color = _albedo

@export var emission: Color:
	get:
		return _emission
	set(v):
		_emission = v

@export var emission_energy: float:
	get:
		return _emission_energy
	set(v):
		_emission_energy = v

@onready var _muzzle_wave: Node3D = $MuzzleWave

var _mesh_inst: MeshInstance3D
var _array_mesh: ArrayMesh
var _shooter_peer_id: int = -1
var _remote_pose_init: bool = false
var _filt_start: Vector3 = Vector3.ZERO
var _filt_end: Vector3 = Vector3.ZERO
var _filt_fwd: Vector3 = Vector3(0, 0, -1)
var _smooth_lateral: float = 0.0
var _smooth_up_lift: float = 0.0
var _mat: ShaderMaterial
var _beam_display_color: Color = Color(HEAL_BEAM_RGB_ALLY.r, HEAL_BEAM_RGB_ALLY.g, HEAL_BEAM_RGB_ALLY.b, HEAL_BEAM_ALPHA)


func _ready() -> void:
	_array_mesh = ArrayMesh.new()
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.mesh = _array_mesh
	_mat = ShaderMaterial.new()
	_mat.shader = BEAM_SHADER
	_mat.render_priority = 1
	# mesh has no surfaces until update_beam(); use instance override instead of surface 0.
	_mesh_inst.material_override = _mat
	add_child(_mesh_inst)
	if _muzzle_wave != null:
		_muzzle_wave.set("one_shot", false)


func set_shooter_peer_id(peer_id: int) -> void:
	_shooter_peer_id = peer_id
	_update_beam_colors_for_local_viewer()


func _get_local_player_node() -> Node:
	var w := get_parent()
	if w == null:
		return null
	return w.get_node_or_null(str(HeroNet.my_id()))


func _is_heal_beam_hostile_to_local_viewer() -> bool:
	var me := _get_local_player_node()
	var shooter := get_parent().get_node_or_null(str(_shooter_peer_id)) if _shooter_peer_id >= 0 else null
	if me == null or shooter == null:
		return false
	return int(me.get("team_id")) != int(shooter.get("team_id"))


func _update_beam_colors_for_local_viewer() -> void:
	var rgb: Color = HEAL_BEAM_RGB_ENEMY if _is_heal_beam_hostile_to_local_viewer() else HEAL_BEAM_RGB_ALLY
	_beam_display_color = Color(rgb.r, rgb.g, rgb.b, HEAL_BEAM_ALPHA)
	_albedo = _beam_display_color


func update_beam(start_global: Vector3, end_global: Vector3, view_forward: Vector3 = Vector3(0, 0, -1), delta: float = -1.0) -> void:
	var dt: float = delta
	if dt < 0.0:
		dt = 1.0 / 60.0
	dt = clampf(dt, 0.0, 0.05)

	_update_beam_colors_for_local_viewer()

	var target_fwd: Vector3 = view_forward
	if target_fwd.length_squared() < 1e-8:
		target_fwd = Vector3(0, 0, -1)
	else:
		target_fwd = target_fwd.normalized()

	var target_start: Vector3 = start_global
	var target_end: Vector3 = end_global

	var start_draw: Vector3 = target_start
	var end_draw: Vector3 = target_end
	var fwd_cam: Vector3 = target_fwd
	var remote_observer: bool = _shooter_peer_id >= 0 and _shooter_peer_id != HeroNet.my_id()
	if remote_observer:
		if not _remote_pose_init:
			_filt_start = target_start
			_filt_end = target_end
			_filt_fwd = target_fwd
			_remote_pose_init = true
		var a: float = 1.0 - exp(-REMOTE_BEAM_SMOOTH_SPEED * dt)
		_filt_start = _filt_start.lerp(target_start, a)
		_filt_end = _filt_end.lerp(target_end, a)
		_filt_fwd = _filt_fwd.lerp(target_fwd, a).normalized()
		start_draw = _filt_start
		end_draw = _filt_end
		fwd_cam = _filt_fwd
	else:
		_remote_pose_init = false

	var chord: Vector3 = end_draw - start_draw
	var dist: float = chord.length()
	if dist < 0.08:
		visible = false
		_smooth_lateral = 0.0
		_smooth_up_lift = 0.0
		_remote_pose_init = false
		return
	visible = true

	var chord_n: Vector3 = chord / dist
	if fwd_cam.length_squared() < 1e-8:
		fwd_cam = Vector3(0, 0, -1)
	else:
		fwd_cam = fwd_cam.normalized()
	# Horizontal projection for NE/NW lateral logic (same idea as before).
	var fwd_h: Vector3 = fwd_cam
	fwd_h.y = 0.0
	if fwd_h.length_squared() < 1e-8:
		fwd_h = Vector3(0, 0, -1)
	else:
		fwd_h = fwd_h.normalized()

	var right_h: Vector3 = fwd_h.cross(Vector3.UP)
	if right_h.length_squared() < 1e-8:
		right_h = Vector3.RIGHT
	else:
		right_h = right_h.normalized()

	var chord_h: Vector3 = chord
	chord_h.y = 0.0
	var chord_h_len: float = chord_h.length()
	var chord_h_n: Vector3
	if chord_h_len > 1e-5:
		chord_h_n = chord_h / chord_h_len
	else:
		chord_h_n = fwd_h

	# +1 when ally is on camera-right in the horizontal plane — arc should bend left (-right_h).
	var lateral_unit: float = clampf(right_h.dot(chord_h_n), -1.0, 1.0)
	var turn: Vector3 = fwd_h.cross(chord_h_n)
	var turn_sign: float = 0.0
	if turn.length_squared() > 1e-8:
		turn_sign = signf(turn.dot(Vector3.UP))
	var lateral_mag: float = absf(lateral_unit)
	# Ease lateral influence: dead-ahead / centered → no sideways bend.
	var bend_gate: float = smoothstep(0.03, 0.12, lateral_mag)
	var aim_align: float = absf(fwd_h.dot(chord_h_n))
	var ahead_gate: float = 1.0 - smoothstep(0.88, 0.998, aim_align)
	var target_lateral: float = -lateral_unit * bend_gate * ahead_gate
	if lateral_mag < 0.07:
		# Blend turning from forward vs chord when lateral is ambiguous.
		var amb: float = smoothstep(0.02, 0.07, lateral_mag)
		target_lateral = lerpf(turn_sign * ahead_gate, target_lateral, amb)
	var smooth_k: float = 1.0 - exp(-14.0 * dt)
	_smooth_lateral = lerpf(_smooth_lateral, clampf(target_lateral, -1.0, 1.0), smooth_k)

	var dy: float = end_draw.y - start_draw.y
	var chord_up: float = chord_n.y
	# Stronger lift when line-of-sight aims upward (fixes lopsided arcs above you).
	var up_gate: float = smoothstep(0.06, 0.42, chord_up) * smoothstep(0.0, 0.25, maxf(0.0, dy))
	var target_up: float = clampf(dy * 0.52, 0.0, 2.8) * (0.35 + 0.65 * up_gate)
	_smooth_up_lift = lerpf(_smooth_up_lift, target_up, smooth_k)

	var lateral_fade_vs_pitch: float = 1.0 - smoothstep(0.12, 0.82, absf(chord_n.y))
	var arch: float = clampf(dist * 0.68, 0.65, 9.0) * lateral_fade_vs_pitch

	var up_reference: Vector3 = chord_n.cross(right_h)
	if up_reference.length_squared() < 1e-10:
		up_reference = Vector3.UP
	else:
		up_reference = up_reference.normalized()
	var up_offset: Vector3 = up_reference * _smooth_up_lift * 2.15 + Vector3.UP * (_smooth_up_lift * 0.5)

	# Straight ≈ ¼ of the previous step again (was dist*0.08 → now dist*0.02). Full camera forward (pitch included).
	var straight_run: float = clampf(dist * 0.02, 0.06, 0.4)
	straight_run = minf(straight_run, maxf(0.0, dist - 0.2))
	var bend_start: Vector3 = start_draw + fwd_cam * straight_run
	var chord_r: Vector3 = end_draw - bend_start
	var dist_r: float = chord_r.length()
	if dist_r < 0.07:
		straight_run = maxf(0.0, dist - 0.12)
		bend_start = start_draw + fwd_cam * straight_run
		chord_r = end_draw - bend_start
		dist_r = chord_r.length()

	var cn_r: Vector3 = chord_r / dist_r if dist_r > 1e-6 else chord_n
	# Lateral arc in the plane (cam_forward × to_ally), not flat right_h — stops backward hooks for W/SW/E.
	var n_bend_plane: Vector3 = fwd_cam.cross(cn_r)
	var side_basis: Vector3
	if n_bend_plane.length_squared() < 1e-14:
		side_basis = right_h
	else:
		n_bend_plane = n_bend_plane.normalized()
		side_basis = n_bend_plane.cross(fwd_cam).normalized()
		if side_basis.dot(right_h) < 0.0:
			side_basis = -side_basis
	var u_forward_dot: float = fwd_cam.dot(cn_r)
	var arch_turn: float = lerpf(0.38, 1.0, smoothstep(-0.08, 0.42, u_forward_dot))
	var side_offset: Vector3 = side_basis * (_smooth_lateral * arch * arch_turn)
	var up_for_p2: Vector3 = up_offset
	var up_bk: float = up_for_p2.dot(fwd_cam)
	if up_bk < 0.0:
		up_for_p2 = up_for_p2 - fwd_cam * up_bk

	var taper: float = clampf(straight_run * 0.42, 0.14, dist_r * 0.55)
	var kick_in_r: float = clampf(dist_r * 0.38, 0.1, dist_r * 0.62)

	var p0b: Vector3 = bend_start
	var p1b: Vector3 = bend_start + fwd_cam * taper
	var p3b: Vector3 = end_draw
	var p2b: Vector3 = p3b - cn_r * kick_in_r + side_offset + up_for_p2
	var p2_rel: Vector3 = p2b - bend_start
	var p2_fwd: float = p2_rel.dot(fwd_cam)
	if p2_fwd < 0.07:
		p2b = p2b + fwd_cam * (0.07 - p2_fwd)

	var len_curve_est: float = maxf(dist_r * 1.08, 0.05)
	var weight_straight: float = straight_run / (straight_run + len_curve_est)
	var n_straight: int = clampi(int(round(weight_straight * float(RINGS_ALONG))), 0, RINGS_ALONG - 6)
	if straight_run > 0.12 and n_straight < 2:
		n_straight = 2
	if n_straight == 1:
		n_straight = 0
	if n_straight > 0 and RINGS_ALONG - n_straight < 6:
		n_straight = max(0, RINGS_ALONG - 6)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var inds := PackedInt32Array()
	verts.resize(RINGS_ALONG * RADIAL_SEGMENTS)
	norms.resize(RINGS_ALONG * RADIAL_SEGMENTS)
	uvs.resize(RINGS_ALONG * RADIAL_SEGMENTS)
	cols.resize(RINGS_ALONG * RADIAL_SEGMENTS)

	var ally_soft_cam: bool = not _is_heal_beam_hostile_to_local_viewer()
	var curve_u_max: float = 1.0
	if ally_soft_cam:
		# Distance-scaled trim: far targets keep endpoint close to target; near targets keep a softer shortened look.
		curve_u_max = clampf(1.0 - (ALLY_BEAM_TARGET_GAP_M / maxf(dist, 1e-4)), ALLY_BEAM_CURVE_U_MIN, 1.0)

	var prev_n: Vector3 = Vector3.ZERO
	for i in RINGS_ALONG:
		var t_uv: float = float(i) / float(RINGS_ALONG - 1)
		var pos: Vector3
		var tan: Vector3
		if n_straight >= 2 and i < n_straight:
			var u_s: float = float(i) / float(n_straight - 1)
			pos = start_draw + fwd_cam * (u_s * straight_run)
			tan = fwd_cam
		else:
			var i_c: int = i - n_straight
			var n_c: int = RINGS_ALONG - n_straight
			var t_c: float = float(i_c) / float(max(1, n_c - 1))
			# Pow > 1: more vertices in the low-t side of the Bezier (still nearly straight) → smooth bend out of the gun line.
			# Allies: multiply max parameter so we trim along the already-built curve (keeps arc shape vs shortening chord first).
			var t_eval: float = pow(t_c, 1.06) * curve_u_max
			pos = _cubic_bezier(p0b, p1b, p2b, p3b, t_eval)
			tan = _cubic_bezier_deriv(p0b, p1b, p2b, p3b, t_eval)
			if tan.length_squared() < 1e-10:
				tan = cn_r
			else:
				tan = tan.normalized()

		var ring_n: Vector3
		if i == 0:
			var ref_ax: Vector3 = Vector3.UP if absf(tan.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
			ring_n = ref_ax.cross(tan).normalized()
		else:
			ring_n = prev_n - tan * prev_n.dot(tan)
			if ring_n.length_squared() < 1e-10:
				ring_n = Vector3.UP.cross(tan).normalized()
			else:
				ring_n = ring_n.normalized()
		prev_n = ring_n
		var ring_b: Vector3 = tan.cross(ring_n).normalized()

		for j in RADIAL_SEGMENTS:
			var ang: float = TAU * float(j) / float(RADIAL_SEGMENTS)
			var radial: Vector3 = ring_n * cos(ang) + ring_b * sin(ang)
			var vi: int = i * RADIAL_SEGMENTS + j
			verts[vi] = pos + radial * TUBE_RADIUS
			norms[vi] = radial
			uvs[vi] = Vector2(float(j) / float(RADIAL_SEGMENTS), t_uv)
			cols[vi] = _beam_display_color

	for i in RINGS_ALONG - 1:
		for j in RADIAL_SEGMENTS:
			var jn: int = (j + 1) % RADIAL_SEGMENTS
			var v00: int = i * RADIAL_SEGMENTS + j
			var v01: int = i * RADIAL_SEGMENTS + jn
			var v10: int = (i + 1) * RADIAL_SEGMENTS + j
			var v11: int = (i + 1) * RADIAL_SEGMENTS + jn
			inds.append_array([v00, v10, v01, v01, v10, v11])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = inds

	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_orient_muzzle_wave_at_muzzle(start_draw + fwd_cam * MUZZLE_WAVE_OUTSET, fwd_cam)


func _orient_muzzle_wave_at_muzzle(origin: Vector3, dir_fwd: Vector3) -> void:
	if _muzzle_wave == null:
		return
	# Binbun mprojectile_wave geometry uses negative local X. With basis.x = -dir_fwd, -X World = +forward (out of gun).
	var x: Vector3 = -dir_fwd
	var y: Vector3 = Vector3.UP.cross(x)
	if y.length_squared() < 1e-12:
		y = Vector3(0.0, 0.0, 1.0).cross(x)
	y = y.normalized()
	var z: Vector3 = x.cross(y)
	var b: Basis = Basis(x, y, z).scaled(Vector3(MUZZLE_WAVE_SCALE, MUZZLE_WAVE_SCALE, MUZZLE_WAVE_SCALE))
	_muzzle_wave.global_transform = Transform3D(b, origin)
	var em := Color(_beam_display_color.r, _beam_display_color.g, _beam_display_color.b, 1.0)
	_muzzle_wave.set("primary_color", em.lightened(0.08))
	_muzzle_wave.set("secondary_color", em)
	_muzzle_wave.set("tertiary_color", em.darkened(0.18))
	_muzzle_wave.set("light_color", em)


func _cubic_bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return u * u * u * a + 3.0 * u * u * t * b + 3.0 * u * t * t * c + t * t * t * d


func _cubic_bezier_deriv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return 3.0 * u * u * (b - a) + 6.0 * u * t * (c - b) + 3.0 * t * t * (d - c)

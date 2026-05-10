extends Node3D

## World-space Binbun beam_vfx_08 for sniper ultimate: bright red (ally/self view), dark red (enemy shooter).

const ALLY_PRIMARY := Color(1.0, 0.18, 0.12, 1.0)
const ALLY_SECONDARY := Color(1.0, 0.42, 0.28, 1.0)
const ALLY_TERTIARY := Color(0.92, 0.22, 0.18, 1.0)

const ENEMY_PRIMARY := Color(0.42, 0.04, 0.04, 1.0)
const ENEMY_SECONDARY := Color(0.28, 0.03, 0.03, 1.0)
const ENEMY_TERTIARY := Color(0.14, 0.02, 0.03, 1.0)

@onready var _beam_end: Marker3D = $BeamEndTarget
@onready var _vfx: Node3D = $BeamVFX_08

var _shooter_peer_id: int = -1
var _pulse_elapsed: float = 0.0
## Matches `beam_vfx_08` defaults — thick / “normal” profile.
const _THICK_BEAM_RADIUS: float = 0.25
const _THIN_BEAM_RADIUS: float = 0.055
const _THICK_START_RADIUS: float = 0.35
const _THIN_START_RADIUS: float = 0.09
var _display_duration: float = 0.65


func _ready() -> void:
	set_process(false)
	if _vfx != null and _beam_end != null:
		_vfx.end_point = _beam_end
		if _vfx.has_method("follow_node"):
			_vfx.follow_node()


func set_shooter_peer_id(peer_id: int) -> void:
	_shooter_peer_id = peer_id
	_apply_viewer_tint()


func _get_local_player_node() -> Node:
	var w: Node = get_parent()
	if w == null:
		return null
	return w.get_node_or_null(str(HeroNet.my_id()))


func _is_beam_hostile_to_local_viewer() -> bool:
	var me := _get_local_player_node()
	var shooter := get_parent().get_node_or_null(str(_shooter_peer_id)) if _shooter_peer_id >= 0 else null
	if me == null or shooter == null:
		return false
	return int(me.get("team_id")) != int(shooter.get("team_id"))


func _apply_viewer_tint() -> void:
	if _vfx == null:
		return
	if _is_beam_hostile_to_local_viewer():
		_vfx.primary_color = ENEMY_PRIMARY
		_vfx.secondary_color = ENEMY_SECONDARY
		_vfx.tertiary_color = ENEMY_TERTIARY
	else:
		_vfx.primary_color = ALLY_PRIMARY
		_vfx.secondary_color = ALLY_SECONDARY
		_vfx.tertiary_color = ALLY_TERTIARY


func _process(_delta: float) -> void:
	if _vfx == null:
		return
	_pulse_elapsed += _delta
	var dur: float = maxf(_display_duration, 0.05)
	# Fast thicken → hold thick → fast thin (linear ramps).
	var t_up: float = minf(0.05, dur * 0.11)
	var t_dn: float = minf(0.05, dur * 0.11)
	if t_up + t_dn > dur * 0.92:
		t_up = dur * 0.2
		t_dn = dur * 0.2
	var t_hold: float = maxf(dur - t_up - t_dn, 0.0)
	var e: float = _pulse_elapsed
	var w: float = 0.0
	if e < t_up:
		w = lerpf(0.0, 1.0, e / maxf(t_up, 1e-6))
	elif e < t_up + t_hold:
		w = 1.0
	elif e < dur:
		var te: float = e - t_up - t_hold
		w = lerpf(1.0, 0.0, te / maxf(t_dn, 1e-6))
	else:
		w = 0.0
	_vfx.beam_radius = lerpf(_THIN_BEAM_RADIUS, _THICK_BEAM_RADIUS, w)
	_vfx.start_radius = lerpf(_THIN_START_RADIUS, _THICK_START_RADIUS, w)


func setup_world(start: Vector3, end: Vector3, shooter_peer_id: int, duration_sec: float = 0.65) -> void:
	_shooter_peer_id = shooter_peer_id
	global_position = start
	var dir: Vector3 = end - start
	var len: float = dir.length()
	if len < 0.02:
		visible = false
		queue_free()
		return
	var up: Vector3 = Vector3.UP
	var dir_n: Vector3 = dir / len
	if absf(dir_n.dot(Vector3.UP)) > 0.98:
		up = Vector3.RIGHT
	look_at(end, up)
	_display_duration = duration_sec
	if _beam_end != null:
		_beam_end.global_position = end
	if _vfx != null:
		_vfx.end_point = _beam_end
		_vfx.open_amount = 1.0
		_vfx.beam_radius = _THIN_BEAM_RADIUS
		_vfx.start_radius = _THIN_START_RADIUS
		_vfx.start_emitting = true
		_vfx.end_emitting = true
		_apply_viewer_tint()
		if _vfx.has_method("follow_node"):
			_vfx.follow_node()
	_pulse_elapsed = 0.0
	set_process(true)
	var mid_gp: Vector3 = global_position + dir_n * (len * 0.5)
	_setup_sniper_ult_beam_audio(mid_gp, duration_sec)
	if duration_sec > 0.0 and is_inside_tree():
		get_tree().create_timer(duration_sec).timeout.connect(
			func() -> void:
				if is_instance_valid(self):
					queue_free()
		)


func _setup_sniper_ult_beam_audio(origin_global: Vector3, duration_sec: float) -> void:
	const PEAK_DB := -5.0
	const SILENT_DB := -80.0
	var w: Node = get_parent()
	if w == null:
		return
	var res: Resource = load("res://assets/sounds/effects/sniper ult.mp3")
	if res == null or not (res is AudioStream):
		return
	var stream: AudioStream = (res as AudioStream).duplicate()
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	var ap := AudioStreamPlayer3D.new()
	ap.stream = stream
	ap.bus = "Master"
	ap.max_distance = 120.0
	ap.unit_size = 12.0
	ap.volume_db = SILENT_DB
	w.add_child(ap)
	ap.global_position = origin_global
	ap.play()
	var dur: float = maxf(duration_sec, 0.08)
	var fi: float = clampf(dur * 0.18, 0.02, 0.14)
	var fo: float = clampf(dur * 0.28, 0.03, 0.18)
	var hold: float = maxf(dur - fi - fo, 0.0)
	var tw := ap.create_tween()
	tw.tween_property(ap, "volume_db", PEAK_DB, fi).from(SILENT_DB).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if hold > 0.001:
		tw.tween_interval(hold)
	tw.tween_property(ap, "volume_db", SILENT_DB, fo).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.finished.connect(func() -> void:
		if is_instance_valid(ap):
			ap.queue_free()
	)

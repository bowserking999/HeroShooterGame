extends Node3D

## Horizontal radius of the capture cylinder (tune with visuals later).
@export var capture_radius: float = 6.0
## Vertical extent of the capture cylinder (Y-aligned, centered on this node).
@export var capture_height: float = 10.0
## Speed the capture ring moves toward full when one team holds uncontested.
@export var capture_move_speed: float = 0.12
## Time in seconds for a team’s mission bar to go from 0% → 100% while they hold scoring rights.
@export var mission_bar_fill_duration_sec: float = 80.0

const COLOR_ALLY := Color(0.160784, 0.705882, 1.0, 1.0) # blue — allies (viewer-relative)
const COLOR_ENEMY_CAPTURE := Color(0.86, 0.32, 0.26, 1.0) # red — enemies on ring / objective
const NEUTRAL_PRIMARY := Color(0.92, 0.93, 0.95, 1.0)
const NEUTRAL_SECONDARY := Color(0.75, 0.78, 0.82, 1.0)
const NEUTRAL_LIGHT := Color(0.88, 0.9, 0.93, 1.0)
const COLOR_CONTEST_FLASH := Color(0.988235, 0.980392, 0.305882, 1.0)
## Each step of the 3-beat pattern (yellow → base → base); larger = slower.
const CONTEST_FLASH_STEP_MS := 500

## Progress 0 = fully B, 0.5 = neutral, 1 = fully A.
const FULL_OWNER_A := 0.995
const FULL_OWNER_B := 0.005

const SYNC_INTERVAL_SEC := 0.05

@onready var rim: VFXController = $RimAreaVFX_02

## 0 = fully team B, 0.5 = neutral, 1 = fully team A (team_id 0 / 1).
var capture_progress: float = 0.5
## Mission totals 0–100.
var mission_team_a: float = 0.0
var mission_team_b: float = 0.0
var players_team_a_on_point: int = 0
var players_team_b_on_point: int = 0
## After the first full capture this match, HUD uses the dual blue/orange full-ring readout.
var captured_fully_once: bool = false
## Who earns mission %: last team to **fully** hold; unchanged through neutral/partial until the other team fully caps.
var mission_beneficiary: int = -1

var _rpc_sync_accum: float = 0.0


func _physics_process(delta: float) -> void:
	if rim == null:
		return
	var world := get_parent() as Node
	if world == null:
		return

	if _is_simulation_authority():
		var counts: Vector2i = _count_players_in_volume(world)
		var ca: int = counts.x
		var cb: int = counts.y
		var frozen: bool = world.has_method("is_capture_simulation_frozen") and world.is_capture_simulation_frozen()
		if not frozen:
			_step_capture_simulation(delta, ca, cb)
			if world.has_method("try_authoritative_match_win_check"):
				world.try_authoritative_match_win_check()
		players_team_a_on_point = ca
		players_team_b_on_point = cb
		_rpc_sync_accum += delta
		if _rpc_sync_accum >= SYNC_INTERVAL_SEC:
			_rpc_sync_accum = 0.0
			if HeroNet.is_gdsync():
				GDSync.call_func_unreliable(
					Callable(self, "gdsync_apply_capture_state"),
					[
						capture_progress,
						mission_team_a,
						mission_team_b,
						ca,
						cb,
						captured_fully_once,
						mission_beneficiary,
					]
				)
			elif multiplayer.multiplayer_peer != null:
				sync_capture_state.rpc(
					capture_progress,
					mission_team_a,
					mission_team_b,
					ca,
					cb,
					captured_fully_once,
					mission_beneficiary,
				)

	var local_id: int = HeroNet.my_id()
	var me := world.get_node_or_null(str(local_id)) as Node
	var my_team: int = 0
	if me != null and me.get("team_id") is int:
		my_team = me.team_id
	_apply_rim(my_team)


func _is_simulation_authority() -> bool:
	if HeroNet.is_gdsync():
		return HeroNet.is_host_logic()
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func gdsync_apply_capture_state(
	cp: float,
	ma: float,
	mb: float,
	ca: int,
	cb: int,
	full_cap_happened: bool,
	beneficiary: int,
) -> void:
	if HeroNet.is_gdsync() and GDSync.is_host():
		return
	capture_progress = clampf(cp, 0.0, 1.0)
	mission_team_a = clampf(ma, 0.0, 100.0)
	mission_team_b = clampf(mb, 0.0, 100.0)
	players_team_a_on_point = ca
	players_team_b_on_point = cb
	captured_fully_once = captured_fully_once or full_cap_happened
	mission_beneficiary = clampi(beneficiary, -1, 1)


@rpc("any_peer", "unreliable")
func sync_capture_state(
	cp: float,
	ma: float,
	mb: float,
	ca: int,
	cb: int,
	full_cap_happened: bool,
	beneficiary: int,
) -> void:
	if HeroNet.is_gdsync():
		return
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	capture_progress = clampf(cp, 0.0, 1.0)
	mission_team_a = clampf(ma, 0.0, 100.0)
	mission_team_b = clampf(mb, 0.0, 100.0)
	players_team_a_on_point = ca
	players_team_b_on_point = cb
	captured_fully_once = captured_fully_once or full_cap_happened
	mission_beneficiary = clampi(beneficiary, -1, 1)


func _count_players_in_volume(world: Node) -> Vector2i:
	var ca := 0
	var cb := 0
	for child in world.get_children():
		if not (child is CharacterBody3D):
			continue
		if not child.has_method("receive_damage"):
			continue
		if child.get("is_dead") == true:
			continue
		if not _is_inside_capture_volume((child as Node3D).global_position):
			continue
		var t: int = child.team_id
		if t == 0:
			ca += 1
		else:
			cb += 1
	return Vector2i(ca, cb)


func _owner_team() -> int:
	if capture_progress >= FULL_OWNER_A:
		return 0
	if capture_progress <= FULL_OWNER_B:
		return 1
	return -1


func _step_capture_simulation(delta: float, count_a: int, count_b: int) -> void:
	var contested: bool = count_a > 0 and count_b > 0
	if not contested:
		var cs: float = capture_move_speed
		if count_a > 0 and count_b == 0:
			capture_progress = move_toward(capture_progress, 1.0, delta * cs)
		elif count_b > 0 and count_a == 0:
			capture_progress = move_toward(capture_progress, 0.0, delta * cs)
		# Empty: hold capture_progress (no decay).

	var fo := _owner_team()
	if not captured_fully_once and fo >= 0:
		captured_fully_once = true

	if fo == 0:
		mission_beneficiary = 0
	elif fo == 1:
		mission_beneficiary = 1

	var mission_rate: float = 100.0 / maxf(mission_bar_fill_duration_sec, 0.01)
	if mission_beneficiary == 0:
		mission_team_a = move_toward(mission_team_a, 100.0, delta * mission_rate)
	elif mission_beneficiary == 1:
		mission_team_b = move_toward(mission_team_b, 100.0, delta * mission_rate)


## Uses node transforms, not physics overlap — avoids 1–2 frame lag after CharacterBody3D teleport/respawn.
func _is_inside_capture_volume(global_pos: Vector3) -> bool:
	var local: Vector3 = to_local(global_pos)
	var half_h: float = capture_height * 0.5
	if absf(local.y) > half_h:
		return false
	var r2: float = capture_radius * capture_radius
	return local.x * local.x + local.z * local.z <= r2


func _ally_progress_for_viewer(team_id: int) -> float:
	return capture_progress if team_id == 0 else 1.0 - capture_progress


func _world_team_for_ground_tint(owner: int) -> int:
	if owner >= 0:
		return owner
	if mission_beneficiary >= 0:
		return mission_beneficiary
	return -1


## Pattern: yellow, base, base, yellow, base, base, … (one yellow per three beats).
func _contest_flash_is_yellow_beat() -> bool:
	var beat: int = Time.get_ticks_msec() / CONTEST_FLASH_STEP_MS
	return (beat % 3) == 0


func _apply_rim(my_team: int) -> void:
	var owner := _owner_team()
	var ca := players_team_a_on_point
	var cb := players_team_b_on_point
	var contested: bool = ca > 0 and cb > 0
	var wt: int = _world_team_for_ground_tint(owner)
	var yellow_beat: bool = _contest_flash_is_yellow_beat()

	var primary: Color
	var secondary: Color
	var tertiary: Color
	var light: Color

	if contested and wt >= 0:
		var base: Color = COLOR_ALLY if wt == my_team else COLOR_ENEMY_CAPTURE
		if yellow_beat:
			primary = COLOR_CONTEST_FLASH
			secondary = _dim(COLOR_CONTEST_FLASH, 0.65)
			tertiary = _dim(COLOR_CONTEST_FLASH, 0.45)
			light = COLOR_CONTEST_FLASH
		else:
			primary = base
			secondary = _dim(base, 0.55)
			tertiary = _dim(base, 0.38)
			light = base
	elif contested and wt < 0:
		if yellow_beat:
			primary = COLOR_CONTEST_FLASH
			secondary = _dim(COLOR_CONTEST_FLASH, 0.65)
			tertiary = _dim(COLOR_CONTEST_FLASH, 0.45)
			light = COLOR_CONTEST_FLASH
		else:
			primary = NEUTRAL_PRIMARY
			secondary = NEUTRAL_SECONDARY
			tertiary = _dim(NEUTRAL_SECONDARY, 0.5)
			light = NEUTRAL_LIGHT
	elif wt < 0:
		# Match opening only — no team has fully held yet.
		primary = NEUTRAL_PRIMARY
		secondary = NEUTRAL_SECONDARY
		tertiary = _dim(NEUTRAL_SECONDARY, 0.5)
		light = NEUTRAL_LIGHT
	elif wt == my_team:
		primary = COLOR_ALLY
		secondary = _dim(COLOR_ALLY, 0.55)
		tertiary = _dim(COLOR_ALLY, 0.38)
		light = COLOR_ALLY
	else:
		primary = COLOR_ENEMY_CAPTURE
		secondary = _dim(COLOR_ENEMY_CAPTURE, 0.55)
		tertiary = _dim(COLOR_ENEMY_CAPTURE, 0.38)
		light = COLOR_ENEMY_CAPTURE
	rim.primary_color = primary
	rim.secondary_color = secondary
	rim.tertiary_color = tertiary
	rim.light_color = light


func _dim(c: Color, factor: float) -> Color:
	return Color(c.r * factor, c.g * factor, c.b * factor, c.a)


func reset_match_capture_state() -> void:
	capture_progress = 0.5
	mission_team_a = 0.0
	mission_team_b = 0.0
	players_team_a_on_point = 0
	players_team_b_on_point = 0
	captured_fully_once = false
	mission_beneficiary = -1


## HUD: ally/enemy like health — left bar ally (blue), right enemy (orange), always.
## Ring: ally_progress 0 = full enemy, 0.5 = neutral, 1 = full ally (viewer-relative).
func get_hud_capture_state(local_team_id: int, local_player_global_pos: Vector3) -> Dictionary:
	var ca := players_team_a_on_point
	var cb := players_team_b_on_point
	var ap: float = _ally_progress_for_viewer(local_team_id)
	var owner := _owner_team()
	var i_am_on_point: bool = _is_inside_capture_volume(local_player_global_pos)
	var contesting_enemy_owned: bool = i_am_on_point and owner >= 0 and owner != local_team_id
	var both_teams_on_point: bool = ca > 0 and cb > 0
	var ally_mission: float = mission_team_a if local_team_id == 0 else mission_team_b
	var enemy_mission: float = mission_team_b if local_team_id == 0 else mission_team_a
	var allies_on: int = ca if local_team_id == 0 else cb
	var enemies_on: int = cb if local_team_id == 0 else ca
	return {
		"ally_mission": ally_mission,
		"enemy_mission": enemy_mission,
		"ally_progress": ap,
		"captured_fully_once": captured_fully_once,
		"mission_beneficiary": mission_beneficiary,
		"allies_on_point": mini(allies_on, 3),
		"enemies_on_point": mini(enemies_on, 3),
		"owner_team": owner,
		"contesting_enemy_owned": contesting_enemy_owned,
		"both_teams_on_point": both_teams_on_point,
	}

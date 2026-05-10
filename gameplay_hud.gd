class_name GameplayHUD
extends Control

const _FALLBACK_ABILITY_TEX: Texture2D = preload("res://icon.svg")
## Mission center icon art set: `Skillicon{7|13|4}_{stage}.png` under stages/neutral|team|enemy.
## Change this and the three `preload` paths below when switching stage art (e.g. `_40` icons).
const CAPTURE_STAGE_ID := "32"
const _CAPTURE_TEX_NEUTRAL: Texture2D = preload("res://assets/icons/stages/neutral/Skillicon7_32.png")
const _CAPTURE_TEX_TEAM: Texture2D = preload("res://assets/icons/stages/team/Skillicon13_32.png")
const _CAPTURE_TEX_ENEMY: Texture2D = preload("res://assets/icons/stages/enemy/Skillicon4_32.png")
const CAPTURE_MISSION_ICON_SCALE := 1.0
## Fraction of width/height to shave off each side for ultimate icons (decorative frame).
const ULTIMATE_ICON_BORDER_FRAC: float = 0.12

const REFERENCE_HEIGHT := 1080.0
const FULLSCREEN_MIN_SCALE := 1.25
const FULLSCREEN_MAX_SCALE := 1.8
const KILLFEED_MAX_LINES := 6
const KILLFEED_VISIBLE_SEC := 6.0
const KILLFEED_FADE_SEC := 1.0
const FEED_COLOR_ALLY := "8ecbff"
const FEED_COLOR_ENEMY := "ff9a9a"

@onready var crosshair: Control = $Crosshair
@onready var capture_panel: Control = $CapturePanel
@onready var match_status_strip: Control = $MatchStatusStrip
@onready var overtime_banner: Control = $MatchStatusStrip/OvertimeBanner
@onready var overtime_label: Label = $MatchStatusStrip/OvertimeBanner/OvertimeLabel
@onready var match_start_timer_banner: Control = $MatchStatusStrip/MatchStartTimerBanner
@onready var match_start_timer_label: Label = $MatchStatusStrip/MatchStartTimerBanner/MatchStartTimerLabel
@onready var killfeed_panel: Control = $KillfeedPanel
@onready var ammo_panel: Control = $AmmoPanel
@onready var abilities_row: Control = $AbilitiesRow
@onready var bottom_stack: Control = $BottomStack

@onready var health_bar: ProgressBar = $BottomStack/HealthBar
@onready var health_current_label: Label = $BottomStack/HealthNumbers/HBox/CurrentLabel
@onready var health_max_label: Label = $BottomStack/HealthNumbers/HBox/MaxLabel
@onready var ultimate_key_label: Label = $BottomStack/UltimateRow/UltimateKeyLabel
@onready var ultimate_ring: Control = $BottomStack/UltimateRow/UltimateMeter/RingMeter
@onready var ultimate_icon: TextureRect = $BottomStack/UltimateRow/UltimateMeter/UltimateIcon
@onready var ultimate_charge_dim: Control = $BottomStack/UltimateRow/UltimateMeter/UltimateChargeDim
@onready var ultimate_pct: Label = $BottomStack/UltimateRow/UltimateMeter/PctLabel
@onready var ammo_label: Label = $AmmoPanel/MarginContainer/AmmoLabel
@onready var killfeed_lines: VBoxContainer = $KillfeedPanel/MarginContainer/KillfeedLines
@onready var ability_slots: Array[Control] = [
	$AbilitiesRow/Slot0,
	$AbilitiesRow/Slot1,
	$AbilitiesRow/Slot2,
]
@onready var ability_labels: Array[Label] = [
	$AbilitiesRow/Slot0/BindLabel,
	$AbilitiesRow/Slot1/BindLabel,
	$AbilitiesRow/Slot2/BindLabel,
]
@onready var ability_icons: Array[TextureRect] = [
	$AbilitiesRow/Slot0/IconFrame/Icon,
	$AbilitiesRow/Slot1/IconFrame/Icon,
	$AbilitiesRow/Slot2/IconFrame/Icon,
]
@onready var ability_cooldown_dims: Array[ColorRect] = [
	$AbilitiesRow/Slot0/IconFrame/CooldownDim,
	$AbilitiesRow/Slot1/IconFrame/CooldownDim,
	$AbilitiesRow/Slot2/IconFrame/CooldownDim,
]
@onready var ability_cooldown_labels: Array[Label] = [
	$AbilitiesRow/Slot0/IconFrame/CooldownLabel,
	$AbilitiesRow/Slot1/IconFrame/CooldownLabel,
	$AbilitiesRow/Slot2/IconFrame/CooldownLabel,
]

@onready var cap_my_bar: ProgressBar = $CapturePanel/MarginContainer/CaptureHBox/LeftCol/TeamBar
@onready var cap_enemy_bar: ProgressBar = $CapturePanel/MarginContainer/CaptureHBox/RightCol/TeamBar
@onready var cap_my_pct: Label = $CapturePanel/MarginContainer/CaptureHBox/LeftCol/BarPercent
@onready var cap_enemy_pct: Label = $CapturePanel/MarginContainer/CaptureHBox/RightCol/BarPercent
@onready var cap_ring: Control = $CapturePanel/MarginContainer/CaptureHBox/CenterBlock/CaptureRing
@onready var cap_icon: TextureRect = $CapturePanel/MarginContainer/CaptureHBox/CenterBlock/CaptureIcon

@onready var presence_my: Array[TextureRect] = [
	$CapturePanel/MarginContainer/CaptureHBox/LeftCol/PresenceRow/Dot0,
	$CapturePanel/MarginContainer/CaptureHBox/LeftCol/PresenceRow/Dot1,
	$CapturePanel/MarginContainer/CaptureHBox/LeftCol/PresenceRow/Dot2,
]
@onready var presence_enemy: Array[TextureRect] = [
	$CapturePanel/MarginContainer/CaptureHBox/RightCol/PresenceRow/Dot0,
	$CapturePanel/MarginContainer/CaptureHBox/RightCol/PresenceRow/Dot1,
	$CapturePanel/MarginContainer/CaptureHBox/RightCol/PresenceRow/Dot2,
]
const COLOR_BAR_BLUE: Color = Color(0.160784, 0.705882, 1.0, 1.0)
const COLOR_BAR_ORANGE: Color = Color(0.96, 0.55, 0.18, 1.0)
const COLOR_BAR_WHITE: Color = Color(0.92, 0.93, 0.94, 1.0)
const COLOR_CAPTURE_RING_YELLOW: Color = Color(0.988235, 0.980392, 0.305882, 0.95)
const COLOR_ULTIMATE_ACTIVE_BLUE: Color = Color(0.20, 0.72, 1.0, 0.98)
const COLOR_ULTIMATE_CHARGED_GOLD: Color = Color(0.82, 0.72, 0.18, 0.95)
var _last_window_mode: int = -1
var _last_viewport_size: Vector2 = Vector2(-1.0, -1.0)
var _health_bar_base_min_size: Vector2 = Vector2.ZERO
var _ultimate_icon_cache_stamp: String = ""
var _ammo_reload_dots_phase_accum: float = 0.0
var _capture_owner_last: int = -2


func _ready() -> void:
	_sync_default_ability_labels_only()
	if ultimate_key_label != null:
		ultimate_key_label.text = _action_display("ultimate")
	_apply_ultimate_icon(null)
	_health_bar_base_min_size = health_bar.custom_minimum_size
	_apply_fullscreen_scale()
	# Mission bars: always ally blue (left), enemy orange (right) — Marvel Rivals–style.
	_apply_progress_bar_fill_color(cap_my_bar, COLOR_BAR_BLUE)
	_apply_progress_bar_fill_color(cap_enemy_bar, COLOR_BAR_ORANGE)
	_setup_capture_mission_icon()


func _setup_capture_mission_icon() -> void:
	if cap_icon == null:
		return
	cap_icon.texture = _CAPTURE_TEX_NEUTRAL
	cap_icon.modulate = Color.WHITE
	cap_icon.scale = Vector2(CAPTURE_MISSION_ICON_SCALE, CAPTURE_MISSION_ICON_SCALE)
	cap_icon.resized.connect(_refresh_capture_mission_icon_pivot)
	call_deferred("_refresh_capture_mission_icon_pivot")


func _refresh_capture_mission_icon_pivot() -> void:
	if cap_icon != null:
		cap_icon.pivot_offset = cap_icon.size * 0.5


func _capture_texture_for_point_owner(owner_team: int, local_team_id: int) -> Texture2D:
	if owner_team < 0:
		return _CAPTURE_TEX_NEUTRAL
	if owner_team == local_team_id:
		return _CAPTURE_TEX_TEAM
	return _CAPTURE_TEX_ENEMY


## Mission tick uses `mission_beneficiary` on CapturePoint (who earns % toward 100), including during contests.
func _capture_icon_modulate_for_mission_gain(mission_beneficiary: int, local_team_id: int) -> Color:
	if mission_beneficiary < 0:
		return Color.WHITE
	if mission_beneficiary == local_team_id:
		return COLOR_BAR_BLUE
	return COLOR_BAR_ORANGE


## InputMap actions for the three HUD slots (left → right) when the hero does not override them.
func _default_hud_ability_actions() -> PackedStringArray:
	return PackedStringArray(["weapon1", "weapon2", "secondary"])


func _process(delta: float) -> void:
	_apply_fullscreen_scale()
	var world := get_parent().get_parent() as Node
	if world == null:
		return
	_update_match_top_status(world)
	if not HeroNet.has_multiplayer_session():
		return

	var local_id: int = HeroNet.my_id()
	var player := world.get_node_or_null(str(local_id)) as Node
	if player == null:
		return

	_update_health_rich(int(player.get("health")), int(player.get("max_health")))
	_update_ultimate(player)
	_update_mmo(player, delta)
	_update_capture(world, player)
	_sync_ability_row(player)
	_update_ability_cooldown_overlays(player)


func _sync_default_ability_labels_only() -> void:
	if ability_labels.size() < 3:
		return
	var defaults := _default_hud_ability_actions()
	for i in range(3):
		ability_labels[i].text = _action_display(defaults[i])


func _resolved_hud_actions(hero: HeroResource) -> PackedStringArray:
	if hero == null or hero.hud_ability_actions.is_empty():
		return _default_hud_ability_actions()
	var out := PackedStringArray()
	var custom: PackedStringArray = hero.hud_ability_actions
	for i in range(3):
		out.append(custom[i] if i < custom.size() else "")
	return out


func _resolved_ability_icon_texture(hero: HeroResource, slot_idx: int) -> Texture2D:
	if hero != null and slot_idx < hero.hud_ability_icon_paths.size():
		var p: String = str(hero.hud_ability_icon_paths[slot_idx]).strip_edges()
		if p != "" and ResourceLoader.exists(p):
			var loaded: Resource = load(p)
			if loaded is Texture2D:
				return loaded as Texture2D
	return _FALLBACK_ABILITY_TEX


func _action_display(action: String) -> String:
	var events := InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode != KEY_NONE:
			return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			match int(mb.button_index):
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_LEFT:
					return "LMB"
				_:
					return "M%d" % mb.button_index
	return "—"


func _apply_fullscreen_scale() -> void:
	var mode := DisplayServer.window_get_mode()
	var viewport_size := get_viewport_rect().size
	if mode == _last_window_mode and viewport_size == _last_viewport_size:
		return
	_last_window_mode = mode
	_last_viewport_size = viewport_size

	var fullscreen := (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	var scale_factor := 1.0
	if fullscreen:
		var by_height := viewport_size.y / REFERENCE_HEIGHT
		scale_factor = clampf(maxf(FULLSCREEN_MIN_SCALE, by_height * 0.92), FULLSCREEN_MIN_SCALE, FULLSCREEN_MAX_SCALE)

	_set_scaled_control(crosshair, scale_factor, Vector2(0.5, 0.5))
	_set_scaled_control(capture_panel, scale_factor, Vector2(0.5, 0.0))
	if match_status_strip != null:
		_set_scaled_control(match_status_strip, scale_factor, Vector2(0.5, 0.0))
	_set_scaled_control(killfeed_panel, scale_factor, Vector2(1.0, 0.0))
	_set_scaled_control(ammo_panel, scale_factor, Vector2(0.0, 1.0))
	_set_scaled_control(abilities_row, scale_factor, Vector2(1.0, 1.0))
	_set_scaled_control(bottom_stack, scale_factor, Vector2(0.5, 1.0))
	# Keep health bar slightly less tall in fullscreen while preserving windowed look.
	if _health_bar_base_min_size != Vector2.ZERO:
		health_bar.custom_minimum_size = (
			Vector2(_health_bar_base_min_size.x, _health_bar_base_min_size.y * 0.88)
			if fullscreen else _health_bar_base_min_size
		)


func _set_scaled_control(node: Control, scale_factor: float, pivot_normalized: Vector2) -> void:
	if node == null:
		return
	node.scale = Vector2.ONE * scale_factor
	node.pivot_offset = node.size * pivot_normalized


func set_crosshair_visible(is_visible: bool) -> void:
	if crosshair != null:
		crosshair.visible = is_visible


func _update_health_rich(cur: int, mx: int) -> void:
	health_current_label.text = str(cur)
	health_max_label.text = "/%d" % mx


func _update_ultimate(player: Node) -> void:
	var u: float = float(player.get("ultimate_charge"))
	var cost: float = maxf(1.0, float(player.get("ultimate_cost")))
	var pct: float = clampf((u / cost) * 100.0, 0.0, 100.0)
	var active: bool = bool(player.get("ultimate_active"))
	var active_total: float = maxf(0.0, float(player.get("ultimate_duration_sec")))
	var active_remaining: float = maxf(0.0, float(player.get("ultimate_remaining_sec")))
	var hero_id: String = str(player.get("hero_id"))
	var ready: bool = (u + 0.001 >= cost) and not active
	var r: float = clampf(u / cost, 0.0, 1.0)
	var sniper_windup_hud: bool = (hero_id == "dps_sniper" and active)
	if sniper_windup_hud:
		r = 1.0
	elif active and active_total > 0.001:
		r = clampf(active_remaining / active_total, 0.0, 1.0)
	if ultimate_ring is RingMeter:
		var rm := ultimate_ring as RingMeter
		rm.fill_ratio = r
		rm.fill_color = COLOR_ULTIMATE_ACTIVE_BLUE if active else COLOR_ULTIMATE_CHARGED_GOLD

	if ultimate_key_label != null:
		ultimate_key_label.text = _action_display("ultimate")
		ultimate_key_label.visible = ready and not active
	if ultimate_pct != null:
		if sniper_windup_hud:
			ultimate_pct.visible = false
		else:
			ultimate_pct.visible = (not ready) or active
			if active:
				ultimate_pct.text = "%.1fs" % active_remaining
			elif not ready:
				ultimate_pct.text = "%d%%" % int(floor(pct))
	if ultimate_charge_dim != null:
		ultimate_charge_dim.visible = (not ready) and not active
	if ultimate_icon != null:
		ultimate_icon.modulate = COLOR_ULTIMATE_ACTIVE_BLUE if active else Color.WHITE


func _update_mmo(player: Node, delta: float) -> void:
	var mag: int = int(player.get("magazine_current"))
	var hero_id: String = str(player.get("hero_id"))
	var wn: int = int(player.get("weaponNum"))
	var ult_active: bool = bool(player.get("ultimate_active"))
	if hero_id == "tank_explosive" and ult_active:
		ammo_label.text = "∞"
		_ammo_reload_dots_phase_accum = 0.0
		return
	if mag < 0 or (hero_id == "dps_missile" and wn != 1) or (hero_id == "dps_sniper" and wn != 1):
		ammo_label.text = "∞"
		_ammo_reload_dots_phase_accum = 0.0
		return
	var reloading := false
	if player.has_method(&"is_primary_magazine_reloading"):
		reloading = player.call(&"is_primary_magazine_reloading") as bool
	if reloading:
		_ammo_reload_dots_phase_accum += delta
		const DOT_STEP_SEC := 0.48
		var phase: int = int(_ammo_reload_dots_phase_accum / DOT_STEP_SEC) % 3
		match phase:
			0:
				ammo_label.text = "."
			1:
				ammo_label.text = ".."
			_:
				ammo_label.text = "..."
		return
	_ammo_reload_dots_phase_accum = 0.0
	ammo_label.text = str(mag)


func _update_match_top_status(world: Node) -> void:
	if match_status_strip == null or match_start_timer_banner == null:
		return
	if world.has_method("should_hud_show_overtime") and world.should_hud_show_overtime():
		if overtime_banner != null:
			overtime_banner.visible = true
		if overtime_label != null:
			overtime_label.text = "OVERTIME"
	else:
		if overtime_banner != null:
			overtime_banner.visible = false
	if world.has_method("should_hud_show_match_countdown") and world.should_hud_show_match_countdown():
		match_start_timer_banner.visible = true
		var sec: int = 0
		if world.has_method("get_match_countdown_seconds_remaining"):
			sec = int(world.get_match_countdown_seconds_remaining())
		if match_start_timer_label != null:
			match_start_timer_label.text = "%d:%02d" % [sec / 60, sec % 60]
	else:
		match_start_timer_banner.visible = false


func _update_capture(world: Node, player: Node) -> void:
	var cp := world.get_node_or_null("CapturePoint")
	if cp == null or not cp.has_method("get_hud_capture_state"):
		return
	var pos := Vector3.ZERO
	if player is Node3D:
		pos = (player as Node3D).global_position
	var st: Dictionary = cp.get_hud_capture_state(int(player.get("team_id")), pos)
	var local_tid: int = int(player.get("team_id"))
	var ally_pts: float = float(st.get("ally_mission", 0.0))
	var enemy_pts: float = float(st.get("enemy_mission", 0.0))
	cap_my_bar.value = ally_pts
	cap_enemy_bar.value = enemy_pts
	cap_my_pct.text = "%d%%" % int(round(ally_pts))
	cap_enemy_pct.text = "%d%%" % int(round(enemy_pts))

	var owner_tid: int = int(st.get("owner_team", -1))
	_maybe_push_capture_feed_line(owner_tid, local_tid)
	var mission_tex: Texture2D = _capture_texture_for_point_owner(owner_tid, local_tid)
	if cap_icon.texture != mission_tex:
		cap_icon.texture = mission_tex
		call_deferred("_refresh_capture_mission_icon_pivot")

	var mb: int = int(st.get("mission_beneficiary", -1))
	var gain_col: Color = _capture_icon_modulate_for_mission_gain(mb, local_tid)
	if cap_icon.modulate != gain_col:
		cap_icon.modulate = gain_col

	if cap_ring is RingMeter:
		var rm: RingMeter = cap_ring as RingMeter
		var ap_ring: float = float(st.get("ally_progress", 0.5))
		if bool(st.get("contesting_enemy_owned", false)) and not bool(st.get("both_teams_on_point", false)):
			rm.dual_tone_capture = false
			rm.fill_ratio = 1.0
			rm.fill_clockwise = true
			rm.fill_color = COLOR_CAPTURE_RING_YELLOW
		elif not bool(st.get("captured_fully_once", false)):
			# Opening phase: empty white ring at neutral; wedge blue/orange while capping.
			rm.dual_tone_capture = false
			rm.fill_ratio = absf(ap_ring - 0.5) * 2.0
			rm.fill_clockwise = ap_ring >= 0.5
			if absf(ap_ring - 0.5) <= 0.003:
				rm.fill_color = COLOR_BAR_WHITE
			elif ap_ring > 0.5:
				rm.fill_color = COLOR_BAR_BLUE
			else:
				rm.fill_color = COLOR_BAR_ORANGE
		else:
			rm.dual_tone_capture = true
			rm.ally_arc_fraction = ap_ring
			rm.ally_arc_color = COLOR_BAR_BLUE
			rm.enemy_arc_color = COLOR_BAR_ORANGE

	for i in range(3):
		var na := int(st.get("allies_on_point", 0))
		var nb := int(st.get("enemies_on_point", 0))
		presence_my[i].visible = (2 - i) < na
		presence_enemy[i].visible = i < nb


func _maybe_push_capture_feed_line(owner_tid: int, local_tid: int) -> void:
	# First observation seeds state; subsequent ownership changes generate feed lines.
	if _capture_owner_last == -2:
		_capture_owner_last = owner_tid
		return
	if owner_tid == _capture_owner_last:
		return
	var prev_owner: int = _capture_owner_last
	_capture_owner_last = owner_tid
	# Only announce transitions into a concrete owner (ignore neutralization spam).
	if owner_tid < 0:
		return
	if prev_owner == owner_tid:
		return
	if owner_tid == local_tid:
		push_feed_line("[color=#%s]Your team captured the point![/color]" % FEED_COLOR_ALLY)
	else:
		push_feed_line("[color=#%s]The enemies captured the point[/color]" % FEED_COLOR_ENEMY)


func _apply_progress_bar_fill_color(bar: ProgressBar, c: Color) -> void:
	var sb: StyleBox = bar.get_theme_stylebox("fill")
	if sb == null:
		return
	var dup := sb.duplicate()
	if dup is StyleBoxFlat:
		(dup as StyleBoxFlat).bg_color = c
	bar.add_theme_stylebox_override("fill", dup)


func _sync_ability_row(player: Node) -> void:
	var hero: HeroResource = HeroesRegistry.get_hero(str(player.get("hero_id")))
	_apply_ultimate_icon(hero)
	var actions: PackedStringArray = _resolved_hud_actions(hero)
	for i in range(mini(3, ability_slots.size())):
		var act: String = str(actions[i]) if i < actions.size() else ""
		if act.is_empty():
			ability_slots[i].visible = false
			continue
		ability_slots[i].visible = true
		ability_labels[i].text = _action_display(act)
		ability_icons[i].texture = _resolved_ability_icon_texture(hero, i)


func _update_ability_cooldown_overlays(player: Node) -> void:
	var cds: Variant = player.get("hud_ability_cd_remaining")
	var hero_id: String = str(player.get("hero_id"))
	var missile_targeting_ui_active: bool = bool(player.get("missile_targeting_ui_active"))
	var shield_up: bool = bool(player.get("tank_laser_shield_ui_active"))
	var shield_pct: float = clampf(float(player.get("tank_laser_shield_health_pct")), 0.0, 100.0)
	for i in range(mini(3, ability_cooldown_dims.size())):
		if i < ability_slots.size() and not ability_slots[i].visible:
			ability_cooldown_dims[i].visible = false
			ability_cooldown_labels[i].visible = false
			ability_icons[i].modulate = Color.WHITE
			continue
		var rem: float = 0.0
		if cds is Array and i < (cds as Array).size():
			var v: Variant = (cds as Array)[i]
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				rem = float(v)
		var on_cd: bool = rem > 0.05
		if i < ability_cooldown_dims.size():
			ability_cooldown_dims[i].visible = on_cd
		if i < ability_cooldown_labels.size():
			ability_cooldown_labels[i].visible = on_cd
			ability_cooldown_labels[i].text = "%.1f" % rem if on_cd else ""
			ability_cooldown_labels[i].add_theme_color_override("font_color", Color.WHITE)
			ability_cooldown_labels[i].add_theme_color_override("font_outline_color", Color.BLACK)
		if i < ability_icons.size():
			ability_icons[i].modulate = Color.WHITE
		if hero_id == "dps_missile" and i == 2 and missile_targeting_ui_active:
			if i < ability_cooldown_dims.size():
				ability_cooldown_dims[i].visible = false
			if i < ability_cooldown_labels.size():
				ability_cooldown_labels[i].visible = false
			if i < ability_icons.size():
				ability_icons[i].modulate = Color(0.45, 0.78, 1.0, 1.0)
		if hero_id == "tank_laser" and i == 0 and shield_up:
			if i < ability_cooldown_dims.size():
				ability_cooldown_dims[i].visible = false
			if i < ability_cooldown_labels.size():
				ability_cooldown_labels[i].visible = true
				ability_cooldown_labels[i].text = "%d%%" % int(round(shield_pct))
				ability_cooldown_labels[i].add_theme_color_override("font_color", Color.BLACK)
				ability_cooldown_labels[i].add_theme_color_override("font_outline_color", Color(0.86, 0.94, 1.0, 0.95))
			if i < ability_icons.size():
				ability_icons[i].modulate = Color(0.45, 0.78, 1.0, 1.0)


func _make_cropped_ultimate_display_texture(src: Texture2D) -> Texture2D:
	if src == null:
		return null
	var w: float = float(src.get_width())
	var h: float = float(src.get_height())
	if w < 4.0 or h < 4.0:
		return src
	var mx: float = w * ULTIMATE_ICON_BORDER_FRAC
	var my: float = h * ULTIMATE_ICON_BORDER_FRAC
	var cw: float = w - 2.0 * mx
	var ch: float = h - 2.0 * my
	if cw < 2.0 or ch < 2.0:
		return src
	var atlas := AtlasTexture.new()
	atlas.atlas = src
	atlas.filter_clip = true
	atlas.region = Rect2i(int(mx), int(my), int(cw), int(ch))
	return atlas


func _apply_ultimate_icon(hero: HeroResource) -> void:
	if ultimate_icon == null:
		return
	var src: Texture2D = null
	if hero != null and hero.ultimate_icon != null:
		src = hero.ultimate_icon
	else:
		src = preload("res://icon.svg") as Texture2D
	var stamp: String = "%s:%s" % [str(src.get_rid()), str(ULTIMATE_ICON_BORDER_FRAC)]
	if stamp == _ultimate_icon_cache_stamp and ultimate_icon.texture != null:
		return
	_ultimate_icon_cache_stamp = stamp
	var cropped: Texture2D = _make_cropped_ultimate_display_texture(src)
	ultimate_icon.texture = cropped if cropped != null else src


## Optional hook for later when elimination feed exists.
func push_feed_line(bbcode_text: String) -> void:
	var lbl := RichTextLabel.new()
	lbl.fit_content = true
	lbl.bbcode_enabled = true
	lbl.scroll_active = false
	lbl.add_theme_font_size_override("normal_font_size", 18)
	lbl.text = bbcode_text
	killfeed_lines.add_child(lbl)
	_schedule_killfeed_fade(lbl)
	while killfeed_lines.get_child_count() > KILLFEED_MAX_LINES:
		var oldest: Node = killfeed_lines.get_child(0)
		killfeed_lines.remove_child(oldest)
		oldest.queue_free()


func _schedule_killfeed_fade(lbl: RichTextLabel) -> void:
	if lbl == null or not is_instance_valid(lbl):
		return
	var tw: Tween = create_tween()
	tw.tween_interval(KILLFEED_VISIBLE_SEC)
	tw.tween_property(lbl, "modulate:a", 0.0, KILLFEED_FADE_SEC)
	tw.tween_callback(func() -> void:
		if lbl != null and is_instance_valid(lbl):
			lbl.queue_free()
	)

class_name PrematchCharacterSelect
extends Control
## Full-screen pick at match start (actual rules). Tank / Damage / Healer columns; team roster row; synced timer ring.
## Also reused as an in-match hot-swap menu (toggled via the `toggle_hero_select` action — bound to B).

## Must match `HeroWorld.MATCH_PREGAME_SEC` (used for ring vs `_match_go_live_at_msec`).
const PREGAME_TOTAL_MS := 20_000
## Always-on roster slot count so the bar layout stays identical for 1/2/3-player teams (excess slots show as "Empty").
const ROSTER_SLOT_COUNT: int = 3

const COLOR_TANK_TAB := Color(0.18, 0.72, 0.88, 1.0)
const COLOR_DAMAGE_TAB := Color(0.9, 0.26, 0.22, 1.0)
const COLOR_HEALER_TAB := Color(0.22, 0.82, 0.38, 1.0)
const UI_NO_PATH := "res://assets/sounds/ui/uino.wav"

## Roster-cell mugshot art keyed by hero id (matches `assets/mugshots/<name>.png`).
## Heroes without an art file (e.g. `dps_spring`) fall through to no mugshot.
const MUGSHOT_TEXTURES: Dictionary = {
	"tank_explosive": preload("res://assets/mugshots/explosive.png"),
	"tank_laser": preload("res://assets/mugshots/laser.png"),
	"dps_missile": preload("res://assets/mugshots/missile.png"),
	"dps_sniper": preload("res://assets/mugshots/sniper.png"),
	"healer_medic": preload("res://assets/mugshots/medic.png"),
	"healer_orb": preload("res://assets/mugshots/orb.png"),
}
const MUGSHOT_CELL_HEIGHT_PX: float = 140.0

var _world: Node = null
var _hero_at_session_start: String = ""
var _locked_hero_id: String = ""
var _ui_built: bool = false
var _ring: RingMeter = null
var _time_center: Label = null
var _title_label: Label = null
var _roster_title_label: Label = null
var _timer_row: HBoxContainer = null
var _hero_buttons: Dictionary = {} # hero_id -> Button
var _roster_by_peer: Dictionary = {} # peer_id -> cell widget refs (see _make_roster_cell_widgets)
var _roster_cells_by_index: Array = [] # index 0..ROSTER_SLOT_COUNT-1 -> cell widget refs
var _hint_label: Label = null
var _active: bool = false
var _shown_pick_required_hint: bool = false
var _roster_rebuild_sig: String = ""
var _timer_close_done: bool = false
## When true, the menu was opened via B during the live match for a hot character swap.
## Hides the timer ring, skips prematch lock RPCs, and uses real `peer_heroes` instead of prematch-lock map.
var _in_match_swap_mode: bool = false
var _ui_sfx: AudioStreamPlayer = null
var _ui_no_stream: AudioStream = null
var _ui_no_load_attempted: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	z_as_relative = false
	clip_contents = true
	set_process(false)


## Auto-open match-start prematch only — does NOT report true for in-match swap (so role-conflict
## checks fall back to live `peer_heroes` and the B-toggle still works elsewhere in `world.gd`).
func is_prematch_open() -> bool:
	return _active and visible and not _in_match_swap_mode


func is_match_swap_open() -> bool:
	return _active and visible and _in_match_swap_mode


func is_open() -> bool:
	return _active and visible


func begin(world: Node, in_match_swap: bool = false) -> void:
	_world = world
	_in_match_swap_mode = in_match_swap
	_hero_at_session_start = str(world.get("local_hero_id"))
	# Pre-select the player's current hero so the swap menu visually shows what they're on.
	_locked_hero_id = _hero_at_session_start if in_match_swap else ""
	_active = true
	_timer_close_done = false
	_shown_pick_required_hint = false
	_roster_rebuild_sig = ""
	if _ui_built and _roster_row_container != null:
		for c in _roster_row_container.get_children():
			c.queue_free()
		_roster_by_peer.clear()
		_roster_cells_by_index.clear()
	_ensure_ui()
	_apply_mode_chrome()
	if _hint_label != null:
		_hint_label.visible = false
	_apply_button_styles()
	_refresh_team_buttons()
	_refresh_roster()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)


func _apply_mode_chrome() -> void:
	if _title_label != null:
		_title_label.text = "Switch character:" if _in_match_swap_mode else "Select your character:"
	if _roster_title_label != null:
		_roster_title_label.text = "Your team"
	if _timer_row != null:
		_timer_row.visible = not _in_match_swap_mode


func notify_pick_rejected_ui_only() -> void:
	_locked_hero_id = ""
	if _world != null and _world.has_method("request_prematch_role_lock_sync"):
		_world.request_prematch_role_lock_sync("")
	_apply_button_styles()
	_refresh_roster()
	_refresh_team_buttons()
	if _hint_label != null:
		_hint_label.text = "That role is taken on your team."
		_hint_label.visible = true


func _ensure_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.09, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 26)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)
	_title_label = Label.new()
	_title_label.text = "Select your character:"
	_title_label.add_theme_font_size_override("font_size", 40)
	root.add_child(_title_label)
	_hint_label = Label.new()
	_hint_label.visible = false
	_hint_label.add_theme_font_size_override("font_size", 26)
	_hint_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	root.add_child(_hint_label)
	_timer_row = HBoxContainer.new()
	_timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_timer_row.add_theme_constant_override("separation", 28)
	root.add_child(_timer_row)
	var ring_host := Control.new()
	ring_host.custom_minimum_size = Vector2(240, 240)
	_timer_row.add_child(ring_host)
	_ring = RingMeter.new()
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.fill_clockwise = false
	_ring.fill_color = Color(0.55, 0.42, 0.95, 1.0)
	_ring.track_color = Color(0.14, 0.14, 0.16, 1.0)
	_ring.outline_color = Color(0.45, 0.46, 0.52, 1.0)
	_ring.pie_width_pixels = 10.0
	_ring.fill_ratio = 1.0
	ring_host.add_child(_ring)
	_time_center = Label.new()
	_time_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_time_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_center.add_theme_font_size_override("font_size", 38)
	ring_host.add_child(_time_center)
	## Pushes the role columns lower (shares flex space with `mid_spacer`; higher ratio = more gap above columns).
	var layout_spacer_top := Control.new()
	layout_spacer_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout_spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_spacer_top.size_flags_stretch_ratio = 1.45
	root.add_child(layout_spacer_top)
	var columns_wrap := CenterContainer.new()
	columns_wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(columns_wrap)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 48)
	columns_wrap.add_child(columns)
	var col_titles: PackedStringArray = PackedStringArray(["Tank", "Damage", "Healer"])
	var col_colors: Array[Color] = [COLOR_TANK_TAB, COLOR_DAMAGE_TAB, COLOR_HEALER_TAB]
	var hero_cols: Array = HeroesRegistry.get_character_select_columns(false)
	for col_i in range(mini(hero_cols.size(), 3)):
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 18)
		v.custom_minimum_size.x = 380.0
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(v)
		var hdr := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = col_colors[col_i]
		st.set_corner_radius_all(10)
		st.content_margin_left = 10
		st.content_margin_right = 10
		st.content_margin_top = 10
		st.content_margin_bottom = 10
		hdr.add_theme_stylebox_override("panel", st)
		var hl := Label.new()
		hl.text = col_titles[col_i]
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hl.add_theme_font_size_override("font_size", 38)
		hl.add_theme_color_override("font_color", Color(0.04, 0.04, 0.05, 1.0))
		hdr.add_child(hl)
		v.add_child(hdr)
		for hid in hero_cols[col_i]:
			var hero: HeroResource = HeroesRegistry.get_hero(str(hid))
			var btn := Button.new()
			btn.text = hero.display_name if hero else str(hid)
			btn.add_theme_font_size_override("font_size", 34)
			btn.custom_minimum_size = Vector2(0, 92)
			btn.pressed.connect(_on_hero_button_pressed.bind(str(hid)))
			v.add_child(btn)
			_hero_buttons[str(hid)] = btn
	var mid_spacer := Control.new()
	mid_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_spacer.size_flags_stretch_ratio = 1.0
	mid_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mid_spacer)
	_roster_title_label = Label.new()
	_roster_title_label.text = "Your team"
	_roster_title_label.add_theme_font_size_override("font_size", 30)
	root.add_child(_roster_title_label)
	var roster_row := HBoxContainer.new()
	roster_row.add_theme_constant_override("separation", 20)
	roster_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	roster_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(roster_row)
	_roster_row_container = roster_row


var _roster_row_container: HBoxContainer = null


func _on_hero_button_pressed(hero_id: String) -> void:
	if _world == null:
		return
	if _in_match_swap_mode:
		# In-match hot swap: skip prematch lock/visibility RPCs, just retarget the local hero.
		if _is_role_blocked_for_me(hero_id):
			if _hint_label != null:
				_hint_label.text = "That role is taken on your team."
				_hint_label.visible = true
			return
		var current_hero: String = str(_world.get("local_hero_id"))
		if hero_id != current_hero and _world.has_method("set_local_player_hero"):
			_world.set_local_player_hero(hero_id)
		close_match_swap()
		return
	if _locked_hero_id == hero_id:
		_locked_hero_id = ""
		if _world.has_method("request_prematch_role_lock_sync"):
			_world.request_prematch_role_lock_sync("")
		if _world.has_method("request_prematch_pick_visibility"):
			_world.request_prematch_pick_visibility(false)
		if _world.has_method("set_local_player_hero"):
			_world.set_local_player_hero(_hero_at_session_start)
		_apply_button_styles()
		_refresh_roster()
		_refresh_team_buttons()
		return
	if _is_role_blocked_for_me(hero_id):
		return
	if _locked_hero_id != "" and _locked_hero_id != hero_id:
		_locked_hero_id = ""
	_locked_hero_id = hero_id
	if _world.has_method("set_local_player_hero"):
		_world.set_local_player_hero(hero_id)
	if _world.has_method("request_prematch_role_lock_sync"):
		_world.request_prematch_role_lock_sync(hero_id)
	_apply_button_styles()
	_refresh_roster()
	_refresh_team_buttons()
	if _hint_label != null:
		_hint_label.visible = false


func _my_team_peer_ids() -> Array[int]:
	var out: Array[int] = []
	if _world == null:
		return out
	var peer_teams: Variant = _world.get("peer_teams")
	if typeof(peer_teams) != TYPE_DICTIONARY:
		return out
	var my_team: int = int(_world.get("local_team_id"))
	var my_id: int = int(HeroNet.my_id())
	for k in peer_teams.keys():
		if int(peer_teams[k]) != my_team:
			continue
		out.append(int(k))
	out.sort()
	if out.has(my_id):
		out.erase(my_id)
		out.insert(0, my_id)
	else:
		out.insert(0, my_id)
	return out


func _is_role_blocked_for_me(hero_id: String) -> bool:
	var slot: int = HeroesRegistry.hero_role_slot(hero_id)
	if slot < 0:
		return true
	if _world == null:
		return false
	var my_id: int = int(HeroNet.my_id())
	var my_team: int = int(_world.get("local_team_id"))
	var peer_teams: Dictionary = _world.get("peer_teams") as Dictionary
	for pid_raw in peer_teams.keys():
		var pid: int = int(pid_raw)
		if pid == my_id:
			continue
		if int(peer_teams[pid_raw]) != my_team:
			continue
		var hid: String = ""
		if _world.has_method("peer_hero_id_for_team_role_slot_conflict"):
			hid = _world.peer_hero_id_for_team_role_slot_conflict(pid)
		else:
			hid = str((_world.get("peer_heroes") as Dictionary).get(pid, ""))
		if hid.is_empty():
			continue
		if HeroesRegistry.hero_role_slot(hid) == slot:
			return true
	return false


func _refresh_team_buttons() -> void:
	for hid in _hero_buttons.keys():
		var btn: Button = _hero_buttons[hid] as Button
		if btn == null:
			continue
		var blocked: bool = _is_role_blocked_for_me(str(hid)) and str(hid) != _locked_hero_id
		btn.disabled = blocked


func _apply_button_styles() -> void:
	for hid in _hero_buttons.keys():
		var btn: Button = _hero_buttons[hid] as Button
		if btn == null:
			continue
		var hstr: String = str(hid)
		if hstr == _locked_hero_id:
			btn.modulate = Color(0.75, 0.95, 0.78)
		else:
			btn.modulate = Color.WHITE


func _roster_peer_signature(ids: Array[int]) -> String:
	var s: String = ""
	for id in ids:
		s += str(id) + "|"
	return s


func _make_roster_cell_widgets() -> Dictionary:
	var slot := VBoxContainer.new()
	slot.add_theme_constant_override("separation", 10)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Mugshot sits above the username header. We keep `visible = true` and a fixed
	# `custom_minimum_size` so the slot layout never shifts when a hero is picked /
	# unpicked — when no portrait is set, `texture = null` just renders nothing in
	# the reserved area instead of collapsing it.
	var mugshot := TextureRect.new()
	mugshot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mugshot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mugshot.custom_minimum_size = Vector2(0, MUGSHOT_CELL_HEIGHT_PX)
	mugshot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mugshot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mugshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(mugshot)
	var header_pc := PanelContainer.new()
	header_pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hdr_sb := StyleBoxFlat.new()
	hdr_sb.bg_color = Color(0.22, 0.9, 0.44)
	hdr_sb.content_margin_left = 14
	hdr_sb.content_margin_right = 14
	hdr_sb.content_margin_top = 12
	hdr_sb.content_margin_bottom = 12
	hdr_sb.set_corner_radius_all(6)
	header_pc.add_theme_stylebox_override("panel", hdr_sb)
	var hdr_lab := Label.new()
	hdr_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr_lab.add_theme_font_size_override("font_size", 24)
	hdr_lab.add_theme_color_override("font_color", Color(0.04, 0.05, 0.07, 1.0))
	header_pc.add_child(hdr_lab)
	slot.add_child(header_pc)
	var pair := HBoxContainer.new()
	pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pair.add_theme_constant_override("separation", 12)
	var role_pc := PanelContainer.new()
	role_pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var role_box := StyleBoxFlat.new()
	role_box.bg_color = Color(0.98, 0.98, 0.995, 1.0)
	role_box.border_color = Color(0.72, 0.74, 0.8, 1.0)
	role_box.set_border_width_all(2)
	role_box.content_margin_left = 12
	role_box.content_margin_right = 12
	role_box.content_margin_top = 10
	role_box.content_margin_bottom = 10
	role_box.set_corner_radius_all(4)
	role_pc.add_theme_stylebox_override("panel", role_box)
	var role_v := VBoxContainer.new()
	role_v.add_theme_constant_override("separation", 4)
	var role_title := Label.new()
	role_title.text = "Role"
	role_title.add_theme_font_size_override("font_size", 17)
	role_title.add_theme_color_override("font_color", Color(0.38, 0.4, 0.45, 1.0))
	var role_val := Label.new()
	role_val.add_theme_font_size_override("font_size", 22)
	role_val.add_theme_color_override("font_color", Color(0.06, 0.07, 0.09, 1.0))
	role_val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role_v.add_child(role_title)
	role_v.add_child(role_val)
	role_pc.add_child(role_v)
	pair.add_child(role_pc)
	var char_pc := PanelContainer.new()
	char_pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var char_box := StyleBoxFlat.new()
	char_box.bg_color = Color(0.98, 0.98, 0.995, 1.0)
	char_box.border_color = Color(0.72, 0.74, 0.8, 1.0)
	char_box.set_border_width_all(2)
	char_box.content_margin_left = 12
	char_box.content_margin_right = 12
	char_box.content_margin_top = 10
	char_box.content_margin_bottom = 10
	char_box.set_corner_radius_all(4)
	char_pc.add_theme_stylebox_override("panel", char_box)
	var char_v := VBoxContainer.new()
	char_v.add_theme_constant_override("separation", 4)
	var char_title := Label.new()
	char_title.text = "Character"
	char_title.add_theme_font_size_override("font_size", 17)
	char_title.add_theme_color_override("font_color", Color(0.38, 0.4, 0.45, 1.0))
	var char_val := Label.new()
	char_val.add_theme_font_size_override("font_size", 22)
	char_val.add_theme_color_override("font_color", Color(0.06, 0.07, 0.09, 1.0))
	char_val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	char_v.add_child(char_title)
	char_v.add_child(char_val)
	char_pc.add_child(char_v)
	pair.add_child(char_pc)
	slot.add_child(pair)
	return {
		"slot": slot,
		"mugshot": mugshot,
		"header_style": hdr_sb,
		"header_label": hdr_lab,
		"role_val": role_val,
		"char_val": char_val,
	}


func _ensure_roster_cells() -> void:
	if _roster_row_container == null or _world == null:
		return
	var ids := _my_team_peer_ids()
	var sig: String = _roster_peer_signature(ids)
	# Always render exactly ROSTER_SLOT_COUNT cells so the bar layout stays identical
	# regardless of how many players are on the team (1/2/3) — empty slots show as "Empty".
	if sig == _roster_rebuild_sig and _roster_row_container.get_child_count() == ROSTER_SLOT_COUNT:
		return
	_roster_rebuild_sig = sig
	for c in _roster_row_container.get_children():
		c.queue_free()
	_roster_by_peer.clear()
	_roster_cells_by_index.clear()
	for i in range(ROSTER_SLOT_COUNT):
		var parts: Dictionary = _make_roster_cell_widgets()
		_roster_row_container.add_child(parts["slot"] as Node)
		_roster_cells_by_index.append(parts)
		if i < ids.size():
			_roster_by_peer[int(ids[i])] = parts


func _role_label_for_hero(hero_id: String) -> String:
	var s: int = HeroesRegistry.hero_role_slot(hero_id)
	match s:
		0:
			return "Tank"
		1:
			return "Damage"
		2:
			return "Healer"
		_:
			return "—"


func _refresh_roster() -> void:
	if _world == null or _roster_row_container == null:
		return
	_ensure_roster_cells()
	var ids := _my_team_peer_ids()
	var peer_usernames: Dictionary = _world.get("peer_usernames") as Dictionary
	var locked_map: Dictionary = _world.get("peer_prematch_locked_hero_id") as Dictionary
	var live_heroes_map: Dictionary = _world.get("peer_heroes") as Dictionary
	var my_id: int = int(HeroNet.my_id())
	for i in range(ROSTER_SLOT_COUNT):
		if i >= _roster_cells_by_index.size():
			break
		var d: Dictionary = _roster_cells_by_index[i] as Dictionary
		if d.is_empty():
			continue
		var hdr: Label = d["header_label"] as Label
		var hdr_st: StyleBoxFlat = d["header_style"] as StyleBoxFlat
		var role_l: Label = d["role_val"] as Label
		var char_l: Label = d["char_val"] as Label
		var mugshot: TextureRect = d.get("mugshot") as TextureRect
		if i >= ids.size():
			# Placeholder for absent teammate slot (keeps visual layout consistent for sub-3-player teams).
			hdr.text = "Empty"
			hdr_st.bg_color = Color(0.32, 0.34, 0.4, 1.0)
			role_l.text = "—"
			char_l.text = "—"
			if mugshot != null:
				# Keep the reserved mugshot area present (just blank) so empty slots match the height of filled ones.
				mugshot.texture = null
			continue
		var pid: int = ids[i]
		if pid == my_id:
			hdr.text = "You"
			hdr_st.bg_color = Color(0.2, 0.88, 0.42, 1.0)
		else:
			var uname: String = str(peer_usernames.get(pid, "Player %d" % pid)).strip_edges()
			if uname.is_empty():
				uname = "Player %d" % pid
			hdr.text = uname
			hdr_st.bg_color = Color(0.45, 0.82, 0.96, 1.0)
		# In-match swap mode reads live `peer_heroes` (no prematch lock semantics);
		# match-start prematch reads the lock map (which only fills as players lock in).
		var hid: String = ""
		if _in_match_swap_mode:
			hid = str(live_heroes_map.get(pid, "")).strip_edges()
		else:
			hid = str(locked_map.get(pid, "")).strip_edges()
		if hid.is_empty():
			role_l.text = "—"
			char_l.text = "—"
		else:
			var hero: HeroResource = HeroesRegistry.get_hero(hid)
			var disp: String = hero.display_name if hero else hid
			role_l.text = _role_label_for_hero(hid)
			char_l.text = disp
		if mugshot != null:
			# Texture toggles in/out without visibility changes, so the cell height
			# stays fixed and downstream content (name + role/character row) doesn't shift.
			mugshot.texture = MUGSHOT_TEXTURES.get(hid, null) as Texture2D


func _process(_delta: float) -> void:
	if not _active:
		return
	if _world == null:
		return
	# In-match hot-swap has no countdown / auto-close; just keep roster + button states fresh.
	if _in_match_swap_mode:
		_refresh_roster()
		_refresh_team_buttons()
		return
	if _ring == null or _time_center == null:
		return
	var deadline: int = int(_world.get("_match_go_live_at_msec"))
	var now: int = Time.get_ticks_msec()
	var left_ms: int = deadline - now
	_refresh_roster()
	_refresh_team_buttons()
	if left_ms > 0:
		var t: float = clampf(float(left_ms) / float(PREGAME_TOTAL_MS), 0.0, 1.0)
		_ring.fill_ratio = t
		var sec_left: int = maxi(0, ceili(float(left_ms) / 1000.0))
		_time_center.text = "%d:%02d" % [sec_left / 60, sec_left % 60]
		_shown_pick_required_hint = false
	else:
		_ring.fill_ratio = 0.0
		if not _locked_hero_id.is_empty():
			if not _timer_close_done:
				_timer_close_done = true
				_time_center.text = "0:00"
				_close_prematch()
				return
		else:
			var overdue_ms: int = maxi(0, now - deadline)
			var up_sec: int = maxi(1, (overdue_ms + 999) / 1000)
			_time_center.text = "+%d:%02d" % [up_sec / 60, up_sec % 60]
			if _hint_label != null and not _shown_pick_required_hint:
				_hint_label.text = "Time is up — pick a character to continue."
				_hint_label.visible = true
				_shown_pick_required_hint = true


func _close_prematch() -> void:
	if not _active:
		return
	if _world != null and _world.has_method("on_prematch_overlay_closed"):
		_world.on_prematch_overlay_closed()
	_active = false
	_in_match_swap_mode = false
	set_process(false)
	visible = false
	_locked_hero_id = ""
	if _world != null and _world.get("main_menu") != null:
		var mm: Control = _world.get("main_menu") as Control
		if mm != null and not mm.visible:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Closes the in-match hot-swap menu without invoking match-start cleanup
## (`on_prematch_overlay_closed` opens spawn doors / starts the post-prematch countdown,
## which must NOT fire mid-match).
func close_match_swap() -> void:
	if not _active or not _in_match_swap_mode:
		return
	_active = false
	_in_match_swap_mode = false
	set_process(false)
	visible = false
	_locked_hero_id = ""
	if _world != null and _world.get("main_menu") != null:
		var mm: Control = _world.get("main_menu") as Control
		if mm != null and not mm.visible:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _ensure_ui_sfx_player() -> void:
	if _ui_sfx != null and is_instance_valid(_ui_sfx):
		return
	_ui_sfx = AudioStreamPlayer.new()
	_ui_sfx.bus = GameSettings.NEW_SOUND_AUDIO_BUS
	add_child(_ui_sfx)


func _no_stream() -> AudioStream:
	if _ui_no_load_attempted:
		return _ui_no_stream
	_ui_no_load_attempted = true
	var r: Resource = ResourceLoader.load(UI_NO_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	_ui_no_stream = r as AudioStream
	if _ui_no_stream == null:
		push_warning("PrematchCharacterSelect: could not load %s (re-import audio in the Godot editor)." % UI_NO_PATH)
	return _ui_no_stream


func play_cancel_sfx() -> void:
	_ensure_ui_sfx_player()
	if _ui_sfx == null:
		return
	var st: AudioStream = _no_stream()
	if st == null:
		return
	_ui_sfx.stream = st
	_ui_sfx.play()


func _exit_tree() -> void:
	_active = false
	set_process(false)

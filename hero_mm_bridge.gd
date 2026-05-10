extends Node
## Routes `gdsync_mm_execute_transition` when players are still on `main_menu.tscn`, and runs
## GD-Sync queue matchmaking from the main menu (no `world.tscn` loaded yet).

const PORT := 9999
const ONLINE_LOBBY_MAX_PLAYERS := 8
const MATCHMAKING_CAP_MIN := 2
const MATCHMAKING_CAP_MAX := 6
const MM_AFTER_LEAVE_DELAY_SEC := 0.15
const MM_SIGNAL_WAIT_SEC := 10.0
const MM_JOIN_ATTEMPT_ROUNDS := 18
const MM_JOIN_RETRY_DELAY_SEC := 0.2
const MM_JOIN_RESULT_OK := -1
const MM_JOIN_RESULT_TIMEOUT := -2
const MM_CREATE_SIGNAL_TIMEOUT := -400
const MM_PLAYER_DATA_SEARCHING := "hs_mm_search"
const MM_PLAYER_DATA_IN_MATCH := "hs_in_match"
const MAP_ID_MAP1 := "map1"
const QUEUETIME_PATH := "res://assets/sounds/ui/queuetime.wav"

var _menu_mm_active: bool = false
var _menu_mm_queue_sfx: AudioStreamPlayer
var _queuetime_stream: AudioStream
var _queuetime_load_attempted: bool = false
var _menu_mm_search_start_msec: int = 0
var _menu_mm_start_committed: bool = false
var _menu_mm_locked_cap: int = 6
var _menu_username: String = ""
var _menu_play_button: Button
var _menu_timer_label: Label
var _menu_root: Control = null
var _menu_mm_ui_joining_locked: bool = false


func _ready() -> void:
	_menu_mm_queue_sfx = AudioStreamPlayer.new()
	_menu_mm_queue_sfx.bus = GameSettings.NEW_SOUND_AUDIO_BUS
	add_child(_menu_mm_queue_sfx)
	GDSync.expose_func(Callable(self, "gdsync_mm_execute_transition"))
	GDSync.expose_func(Callable(self, "gdsync_mm_bridge_apply_match_session"))
	GDSync.expose_func(Callable(self, "gdsync_mm_bridge_report_pregame_ready"))
	GDSync.expose_func(Callable(self, "gdsync_mm_bridge_hero_pick_rejected"))
	GDSync.expose_func(Callable(self, "gdsync_mm_bridge_request_prematch_pick_revealed"))


## Clients call on the host so the RPC targets `/root/HeroMmBridge` (stable path).
func gdsync_mm_bridge_report_pregame_ready(client_id: int) -> void:
	if not GDSync.is_host():
		return
	var w: Node = get_tree().current_scene
	if w == null or not w.has_method("gdsync_mm_pregame_client_ready"):
		return
	Callable(w, "gdsync_mm_pregame_client_ready").call(int(client_id))


func gdsync_mm_bridge_hero_pick_rejected(keep_hero_id: String) -> void:
	var w: Node = get_tree().current_scene
	if w == null or not w.has_method("apply_rejected_hero_pick"):
		return
	w.apply_rejected_hero_pick(str(keep_hero_id))


func gdsync_mm_bridge_apply_match_session(actual: bool, pregame_remaining_ms: int) -> void:
	var w: Node = get_tree().current_scene
	if w == null or not w.has_method("gdsync_apply_match_session"):
		return
	Callable(w, "gdsync_apply_match_session").call(bool(actual), int(pregame_remaining_ms))


func gdsync_mm_bridge_request_prematch_pick_revealed(client_id: int, revealed: bool) -> void:
	if not GDSync.is_host():
		return
	var w: Node = get_tree().current_scene
	if w == null or not w.has_method("gdsync_net_set_prematch_pick_revealed"):
		return
	GDSync.call_func_all(Callable(w, "gdsync_net_set_prematch_pick_revealed"), [int(client_id), bool(revealed)])


func _process(_delta: float) -> void:
	if not _menu_mm_active or not is_instance_valid(_menu_timer_label):
		return
	var elapsed_ms: int = Time.get_ticks_msec() - _menu_mm_search_start_msec
	var sec: int = elapsed_ms / 1000
	var m: int = sec / 60
	var s: int = sec % 60
	var cur: int = _menu_mm_current_players_for_display()
	var lim: int = _menu_mm_effective_cap_for_display()
	_menu_timer_label.text = "%d:%02d (%d/%d)" % [m, s, cur, lim]
	var should_lock: bool = (lim > 0 and cur >= lim) or _menu_mm_start_committed
	if should_lock and not _menu_mm_ui_joining_locked:
		_menu_mm_apply_joining_now_lock()


func _current_scene_is_world() -> bool:
	var cs: Node = get_tree().current_scene
	if cs == null:
		return false
	if str(cs.scene_file_path) == "res://world.tscn":
		return true
	var sc: Script = cs.get_script() as Script
	return sc != null and str(sc.resource_path) == "res://world.gd"


func gdsync_mm_execute_transition() -> void:
	var cs: Node = get_tree().current_scene
	## `is HeroWorld` is unreliable on some builds; scene path is authoritative.
	if _current_scene_is_world():
		await cs.gdsync_mm_execute_transition()
		return
	GameSettings.queued_player_username = _menu_username
	clear_menu_matchmaking_session_for_transition()
	GameSettings.debug_world_boot = false
	GameSettings.mm_pending_execute_after_world_load = true
	get_tree().change_scene_to_file("res://world.tscn")


func clear_menu_matchmaking_session_for_transition() -> void:
	_menu_mm_clear_joining_now_lock()
	_menu_mm_active = false
	_menu_mm_start_committed = false
	GameSettings.mm_from_main_menu = false
	_menu_disconnect_signals()
	_mm_set_lobby_player_searching(false)
	if is_instance_valid(_menu_play_button):
		_menu_play_button.text = "Play"
	if is_instance_valid(_menu_timer_label):
		_menu_timer_label.text = "0:00"
	_menu_play_button = null
	_menu_timer_label = null
	_menu_root = null
	set_process(false)


func cancel_menu_search_if_any() -> void:
	## Stop waiting for GDSync even if `_menu_mm_active` is still false (connect in flight after Play).
	if GDSync.connected.is_connected(_menu_mm_after_gdsync_connected):
		GDSync.connected.disconnect(_menu_mm_after_gdsync_connected)
	if GDSync.connection_failed.is_connected(_menu_mm_gdsync_connection_failed):
		GDSync.connection_failed.disconnect(_menu_mm_gdsync_connection_failed)
	if not _menu_mm_active:
		return
	_menu_mm_cancel()


func start_menu_matchmaking(username: String, player_cap: int, play_btn: Button, timer_lbl: Label, menu_root: Control = null) -> void:
	_menu_mm_clear_joining_now_lock()
	GameSettings.debug_world_boot = false
	GameSettings.mm_pending_execute_after_world_load = false
	_menu_play_button = play_btn
	_menu_timer_label = timer_lbl
	_menu_root = menu_root
	_menu_username = _sanitize_username_input(username)
	_menu_mm_locked_cap = clampi(player_cap, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	_on_menu_mm_button_pressed()


func _on_menu_mm_button_pressed() -> void:
	if _menu_mm_active:
		if _menu_mm_ui_joining_locked:
			return
		_menu_mm_cancel()
		return
	if not GDSync.is_active():
		if not GDSync.connected.is_connected(_menu_mm_after_gdsync_connected):
			GDSync.connected.connect(_menu_mm_after_gdsync_connected, CONNECT_ONE_SHOT)
		if not GDSync.connection_failed.is_connected(_menu_mm_gdsync_connection_failed):
			GDSync.connection_failed.connect(_menu_mm_gdsync_connection_failed, CONNECT_ONE_SHOT)
		GDSync.start_multiplayer()
		return
	_menu_mm_begin_after_connected()


func _menu_mm_after_gdsync_connected() -> void:
	_menu_mm_begin_after_connected()


func _menu_mm_gdsync_connection_failed(_err: int) -> void:
	push_error("GD-Sync connection failed — cannot use matchmaking (configure keys under Project → GD-Sync).")


func _enet_match_server() -> String:
	return str(ProjectSettings.get_setting("hero_shooter/enet_match_server", "")).strip_edges()


func _get_queuetime_stream() -> AudioStream:
	if _queuetime_load_attempted:
		return _queuetime_stream
	_queuetime_load_attempted = true
	var r: Resource = ResourceLoader.load(QUEUETIME_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	_queuetime_stream = r as AudioStream
	if _queuetime_stream == null:
		push_warning("HeroMmBridge: could not load %s (open this project in the Godot editor to re-import audio)." % QUEUETIME_PATH)
	return _queuetime_stream


func _menu_mm_begin_after_connected() -> void:
	GameSettings.mm_from_main_menu = true
	if not _menu_username.is_empty():
		GDSync.player_set_username(_menu_username)
	_menu_mm_search_start_msec = Time.get_ticks_msec()
	_menu_mm_active = true
	if _menu_mm_queue_sfx != null and is_instance_valid(_menu_mm_queue_sfx):
		var qst: AudioStream = _get_queuetime_stream()
		if qst != null:
			_menu_mm_queue_sfx.stream = qst
			_menu_mm_queue_sfx.play()
	_menu_mm_start_committed = false
	if is_instance_valid(_menu_play_button):
		_menu_play_button.text = "Cancel search"
	set_process(true)
	_menu_connect_signals()
	await _menu_mm_run_queue_pipeline()


func _mm_set_lobby_player_searching(searching: bool) -> void:
	if not GDSync.is_active():
		return
	if searching:
		GDSync.player_set_data(MM_PLAYER_DATA_SEARCHING, "1")
	else:
		GDSync.player_erase_data(MM_PLAYER_DATA_SEARCHING)


func _mm_set_lobby_player_in_match(in_match: bool) -> void:
	if not GDSync.is_active():
		return
	if in_match:
		GDSync.player_set_data(MM_PLAYER_DATA_IN_MATCH, "1")
	else:
		GDSync.player_erase_data(MM_PLAYER_DATA_IN_MATCH)


func _menu_mm_lobby_name_from_cap(cap: int) -> String:
	var c: int = clampi(cap, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	return "HeroMM%d" % c


func _menu_mm_effective_cap_for_display() -> int:
	if GDSync.is_active():
		var tr: String = str(GDSync.lobby_get_tag("mm_required", "")).strip_edges()
		if tr.is_valid_int():
			return clampi(int(tr), MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
		var lim: int = GDSync.lobby_get_player_limit()
		if lim > 0:
			return lim
	if _menu_mm_active:
		return clampi(_menu_mm_locked_cap, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	return clampi(_menu_mm_locked_cap, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)


func _menu_mm_cap_from_lobby_get_name() -> int:
	var n: String = str(GDSync.lobby_get_name()).strip_edges()
	if not n.begins_with("HeroMM") or n.length() <= 6:
		return -1
	var tail: String = n.substr(6)
	if tail.is_valid_int():
		return clampi(int(tail), MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	return -1


func _menu_mm_required_players_for_host() -> int:
	var tr: String = str(GDSync.lobby_get_tag("mm_required", "")).strip_edges()
	if tr.is_valid_int():
		return clampi(int(tr), MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	var from_nm: int = _menu_mm_cap_from_lobby_get_name()
	if from_nm >= MATCHMAKING_CAP_MIN:
		return from_nm
	return clampi(_menu_mm_locked_cap, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)


func _menu_mm_current_players_for_display() -> int:
	if not GDSync.is_active():
		return 0
	## Player-data "searching" can replicate a frame late; lobby client list is authoritative for headcount.
	var seen: Dictionary = {}
	var unique_in_lobby: int = 0
	var n_searching: int = 0
	for cid_raw in GDSync.lobby_get_all_clients():
		var cid: int = int(cid_raw)
		if seen.has(cid):
			continue
		seen[cid] = true
		unique_in_lobby += 1
		if str(GDSync.player_get_data(cid, MM_PLAYER_DATA_SEARCHING, "")).strip_edges() == "1":
			n_searching += 1
	return maxi(n_searching, unique_in_lobby)


func _menu_mm_join_once(lobby_nm: String) -> int:
	var box: Dictionary = {"done": false, "ok": false, "err": OK}
	var fn_ok := func(_n: String):
		if not box["done"]:
			box["ok"] = true
			box["done"] = true
	var fn_fail := func(_n: String, e: int):
		if not box["done"]:
			box["err"] = e
			box["done"] = true
	GDSync.lobby_joined.connect(fn_ok, CONNECT_ONE_SHOT)
	GDSync.lobby_join_failed.connect(fn_fail, CONNECT_ONE_SHOT)
	GDSync.lobby_join(lobby_nm, "")
	var deadline_ms: int = Time.get_ticks_msec() + int(MM_SIGNAL_WAIT_SEC * 1000.0)
	while not box["done"] and Time.get_ticks_msec() < deadline_ms:
		if not _menu_mm_active:
			return MM_JOIN_RESULT_TIMEOUT
		await get_tree().process_frame
	if not box["done"]:
		return MM_JOIN_RESULT_TIMEOUT
	if box["ok"]:
		return MM_JOIN_RESULT_OK
	return int(box["err"])


func _menu_mm_create_once(lobby_nm: String, tags: Dictionary) -> Variant:
	var box: Dictionary = {"done": false, "name": "", "err": OK}
	var fn_created := func(n: String):
		if not box["done"]:
			box["name"] = n
			box["done"] = true
	var fn_fail := func(_n: String, e: int):
		if not box["done"]:
			box["err"] = e
			box["done"] = true
	GDSync.lobby_created.connect(fn_created, CONNECT_ONE_SHOT)
	GDSync.lobby_creation_failed.connect(fn_fail, CONNECT_ONE_SHOT)
	GDSync.lobby_create(lobby_nm, "", true, ONLINE_LOBBY_MAX_PLAYERS, tags)
	var deadline_ms: int = Time.get_ticks_msec() + int(MM_SIGNAL_WAIT_SEC * 1000.0)
	while not box["done"] and Time.get_ticks_msec() < deadline_ms:
		if not _menu_mm_active:
			return MM_CREATE_SIGNAL_TIMEOUT
		await get_tree().process_frame
	if not box["done"]:
		return MM_CREATE_SIGNAL_TIMEOUT
	var nm: String = str(box["name"]).strip_edges()
	if not nm.is_empty():
		return nm
	return int(box["err"])


func _menu_mm_run_queue_pipeline() -> void:
	var lobby_nm: String = _menu_mm_lobby_name_from_cap(_menu_mm_locked_cap)
	GDSync.lobby_leave()
	await get_tree().create_timer(MM_AFTER_LEAVE_DELAY_SEC).timeout
	if not _menu_mm_active:
		return
	var round_i: int = 0
	while round_i < MM_JOIN_ATTEMPT_ROUNDS and _menu_mm_active:
		var jr: int = await _menu_mm_join_once(lobby_nm)
		if not _menu_mm_active:
			return
		if jr == MM_JOIN_RESULT_OK:
			await get_tree().process_frame
			await get_tree().process_frame
			if str(GDSync.lobby_get_tag("match_session_live", "")).strip_edges() == "1":
				GDSync.lobby_leave()
				await get_tree().create_timer(MM_AFTER_LEAVE_DELAY_SEC).timeout
				round_i += 1
				await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
				continue
			_menu_mm_queue_joined(lobby_nm)
			return
		if jr == MM_JOIN_RESULT_TIMEOUT:
			round_i += 1
			await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
			continue
		if jr == int(ENUMS.LOBBY_JOIN_ERROR.LOBBY_DOES_NOT_EXIST):
			break
		if jr == int(ENUMS.LOBBY_JOIN_ERROR.LOBBY_IS_FULL):
			round_i += 1
			await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
			continue
		if jr == int(ENUMS.LOBBY_JOIN_ERROR.DUPLICATE_USERNAME):
			_menu_mm_cancel()
			push_error("GD-Sync: duplicate username — set a unique username and try matchmaking again.")
			return
		round_i += 1
		await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
	if not _menu_mm_active:
		return
	var cap: int = clampi(_menu_mm_locked_cap, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	var tags: Dictionary = {
		"game": "HeroShooter",
		"mode": "matchmaking",
		"cap": str(cap),
		"mm_required": str(cap),
	}
	var created: Variant = await _menu_mm_create_once(lobby_nm, tags)
	if typeof(created) == TYPE_STRING:
		await _menu_mm_enter_created_lobby(str(created))
		return
	var ce: int = int(created)
	if ce == MM_CREATE_SIGNAL_TIMEOUT:
		if _menu_mm_active:
			_menu_mm_cancel()
			push_error("GD-Sync: lobby_create did not respond in time — check connection.")
		return
	if ce == int(ENUMS.LOBBY_CREATION_ERROR.LOBBY_ALREADY_EXISTS):
		for _j in range(MM_JOIN_ATTEMPT_ROUNDS):
			if not _menu_mm_active:
				return
			var jr2: int = await _menu_mm_join_once(lobby_nm)
			if not _menu_mm_active:
				return
			if jr2 == MM_JOIN_RESULT_OK:
				await get_tree().process_frame
				if str(GDSync.lobby_get_tag("match_session_live", "")).strip_edges() == "1":
					GDSync.lobby_leave()
					await get_tree().create_timer(MM_AFTER_LEAVE_DELAY_SEC).timeout
					await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
					continue
				_menu_mm_queue_joined(lobby_nm)
				return
			await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
		_menu_mm_cancel()
		push_warning("Matchmaking: queue lobby exists but join did not succeed — try again in a moment.")
		return
	_menu_mm_cancel()
	push_error("GD-Sync: matchmaking lobby_create failed (error %d)." % ce)


func _menu_mm_enter_created_lobby(lobby_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _menu_mm_enter_queue_if_already_joined(lobby_name):
		return
	for _k in range(MM_JOIN_ATTEMPT_ROUNDS):
		if not _menu_mm_active:
			return
		var jr: int = await _menu_mm_join_once(lobby_name)
		if not _menu_mm_active:
			return
		if jr == MM_JOIN_RESULT_OK:
			await get_tree().process_frame
			if str(GDSync.lobby_get_tag("match_session_live", "")).strip_edges() == "1":
				await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
				continue
			_menu_mm_queue_joined(lobby_name)
			return
		if _menu_mm_enter_queue_if_already_joined(lobby_name):
			return
		await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
	_menu_mm_cancel()
	push_error("GD-Sync: could not enter matchmaking lobby after create.")


func _menu_mm_enter_queue_if_already_joined(lobby_name: String) -> bool:
	var want: String = lobby_name.strip_edges()
	if want.is_empty():
		return false
	if str(GDSync.lobby_get_tag("match_session_live", "")).strip_edges() == "1":
		return false
	if str(GDSync.lobby_get_name()).strip_edges() != want:
		return false
	if GDSync.lobby_get_player_limit() <= 0:
		return false
	_menu_mm_queue_joined(want)
	return true


func _menu_mm_queue_joined(_lobby_name: String) -> void:
	if not _menu_mm_active:
		return
	_mm_set_lobby_player_searching(true)
	if GDSync.is_host():
		call_deferred("_menu_mm_host_try_start")


func _menu_connect_signals() -> void:
	if not GDSync.client_joined.is_connected(_menu_mm_on_client_joined):
		GDSync.client_joined.connect(_menu_mm_on_client_joined)


func _menu_disconnect_signals() -> void:
	if GDSync.client_joined.is_connected(_menu_mm_on_client_joined):
		GDSync.client_joined.disconnect(_menu_mm_on_client_joined)


func _menu_mm_on_client_joined(_client_id: int) -> void:
	if not _menu_mm_active:
		return
	if GDSync.is_host():
		call_deferred("_menu_mm_host_try_start")


func _menu_mm_host_try_start() -> void:
	if not _menu_mm_active or _menu_mm_start_committed:
		return
	if not GDSync.is_host():
		return
	var raw_clients: Array = GDSync.lobby_get_all_clients()
	var seen_ids: Dictionary = {}
	var clients: Array[int] = []
	for x in raw_clients:
		var ix: int = int(x)
		if seen_ids.has(ix):
			continue
		seen_ids[ix] = true
		clients.append(ix)
	var required: int = _menu_mm_required_players_for_host()
	if clients.size() < required:
		return
	_menu_mm_start_committed = true
	var ids: Array = []
	for cid in clients:
		ids.append(cid)
	ids.shuffle()
	var n: int = ids.size()
	var team_a_size: int = n / 2
	var assign: Dictionary = {}
	for i in range(n):
		var cid: int = int(ids[i])
		var tid: int = 0 if i < team_a_size else 1
		assign[str(cid)] = tid
	GDSync.lobby_set_tag("mm_team_assign", JSON.stringify(assign))
	GDSync.lobby_set_tag("map_id", MAP_ID_MAP1)
	GDSync.lobby_set_tag("match_actual", "1")
	var dedicated: String = _enet_match_server()
	if not dedicated.is_empty():
		GDSync.lobby_set_tag("enet_mode", "dedicated")
		GDSync.lobby_set_tag("enet_host", dedicated)
		GDSync.lobby_set_tag("enet_port", str(PORT))
		GDSync.lobby_erase_tag("gameplay")
	else:
		GDSync.lobby_erase_tag("enet_mode")
		GDSync.lobby_erase_tag("enet_host")
		GDSync.lobby_erase_tag("enet_port")
		GDSync.lobby_set_tag("gameplay", "gdsync_cloud")
	GDSync.lobby_set_tag("match_session_live", "1")
	print("Matchmaking: %d players — assigning teams and starting match." % n)
	GDSync.call_func_all(Callable(self, "gdsync_mm_execute_transition"), [])


func _menu_mm_stop_ui() -> void:
	_menu_mm_clear_joining_now_lock()
	_menu_mm_active = false
	_menu_mm_start_committed = false
	GameSettings.mm_from_main_menu = false
	_mm_set_lobby_player_searching(false)
	if is_instance_valid(_menu_play_button):
		_menu_play_button.text = "Play"
	if is_instance_valid(_menu_timer_label):
		_menu_timer_label.text = "0:00"
	_menu_play_button = null
	_menu_timer_label = null
	_menu_root = null
	set_process(false)


func _menu_mm_apply_joining_now_lock() -> void:
	if _menu_mm_ui_joining_locked:
		return
	_menu_mm_ui_joining_locked = true
	if is_instance_valid(_menu_play_button):
		_menu_play_button.text = "Joining Now..."
	if is_instance_valid(_menu_root):
		_menu_root.process_mode = Node.PROCESS_MODE_DISABLED


func _menu_mm_clear_joining_now_lock() -> void:
	if not _menu_mm_ui_joining_locked:
		return
	_menu_mm_ui_joining_locked = false
	if is_instance_valid(_menu_root):
		_menu_root.process_mode = Node.PROCESS_MODE_INHERIT


func _menu_mm_cancel() -> void:
	_menu_mm_clear_joining_now_lock()
	_menu_disconnect_signals()
	_menu_mm_start_committed = false
	_menu_mm_active = false
	GameSettings.mm_from_main_menu = false
	_mm_set_lobby_player_searching(false)
	if is_instance_valid(_menu_play_button):
		_menu_play_button.text = "Play"
	if is_instance_valid(_menu_timer_label):
		_menu_timer_label.text = "0:00"
	_menu_play_button = null
	_menu_timer_label = null
	_menu_root = null
	if GDSync.is_active():
		GDSync.lobby_leave()
	set_process(false)


func _sanitize_username_input(raw: String) -> String:
	var s: String = raw.strip_edges()
	if s.length() > 20:
		s = s.substr(0, 20)
	return s

extends Node
class_name HeroWorld

## Map-center objective; tint and overlap radius live on `CapturePoint` (`capture_point.gd`).
##
## **Queue matchmaking:** Join `HeroMM{n}` (n = 2…6 from slider); when full, host shuffles teams (balanced split)
## then starts actual-match rules via GD-Sync cloud or dedicated ENet when `hero_shooter/enet_match_server` is set.
##
## **Online matchmaking:** GD-Sync cloud lobbies (`lobby_create` / `lobby_join`). If Project Settings
## `hero_shooter/enet_match_server` is set, gameplay uses **ENet** to that host (dedicated listen server).
## If it is **empty**, gameplay runs over **GD-Sync** (`HeroNet` + `GDSync.call_func*`) so players on different
## networks do not need UDP port forwarding. LAN **Host** / **Join** still use raw ENet only.
@onready var capture_point: Node3D = $CapturePoint

@onready var main_menu = $CanvasLayer/MainMenu
@onready var address_entry = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/AddressEntry
@onready var online_lobby_field: LineEdit = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/OnlineLobbyField
@onready var team_option = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/TeamOption
@onready var username_entry: LineEdit = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/UsernameEntry
@onready var hero_option = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/HeroOption
@onready var hud = $CanvasLayer/HUD
@onready var health_bar = $CanvasLayer/HUD/BottomStack/HealthBar
@onready var death_overlay = $CanvasLayer/DeathOverlay
@onready var respawn_countdown = $CanvasLayer/DeathOverlay/CenterContainer/VBoxContainer/RespawnCountdown
@onready var pause_menu: Control = $CanvasLayer/PauseMenu
@onready var pause_resume_button: Button = $CanvasLayer/PauseMenu/Layout/LeftColumn/ResumeButton
@onready var pause_respawn_button: Button = $CanvasLayer/PauseMenu/Layout/LeftColumn/RespawnButton
@onready var pause_main_menu_button: Button = $CanvasLayer/PauseMenu/Layout/LeftColumn/MainMenuButton
@onready var pause_master_slider: HSlider = $CanvasLayer/PauseMenu/Layout/OptionsPanel/OptionsVBox/MasterVolumeSlider
@onready var pause_sfx_slider: HSlider = $CanvasLayer/PauseMenu/Layout/OptionsPanel/OptionsVBox/SfxVolumeSlider
@onready var pause_voice_slider: HSlider = $CanvasLayer/PauseMenu/Layout/OptionsPanel/OptionsVBox/VoiceVolumeSlider
@onready var pause_music_slider: HSlider = $CanvasLayer/PauseMenu/Layout/OptionsPanel/OptionsVBox/MusicVolumeSlider
@onready var pause_missile_fly_slider: HSlider = $CanvasLayer/PauseMenu/Layout/OptionsPanel/OptionsVBox/MissileFlyVolumeSlider
@onready var pause_missile_ult_slider: HSlider = $CanvasLayer/PauseMenu/Layout/OptionsPanel/OptionsVBox/MissileUltVolumeSlider
@onready var pause_missile_shot_slider: HSlider = $CanvasLayer/PauseMenu/Layout/OptionsPanel/OptionsVBox/MissileShotVolumeSlider
@onready var character_select: Control = $CanvasLayer/CharacterSelectMenu
@onready var prematch_character_select: PrematchCharacterSelect = $CanvasLayer/PrematchCharacterSelect
@onready var debug_readout: Label = $CanvasLayer/DebugReadout
@onready var fps_readout: Label = $CanvasLayer/FpsReadout
@onready var public_lobbies_list: ItemList = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/PublicLobbiesList
@onready var refresh_public_lobbies_button: Button = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/RefreshPublicLobbiesButton
@onready var join_selected_lobby_button: Button = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/JoinSelectedLobbyButton
@onready var mouse_sensitivity_slider: HSlider = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/MouseSensitivityHBox/MouseSensitivitySlider
@onready var mouse_sensitivity_value: Label = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/MouseSensitivityHBox/MouseSensitivityValue
@onready var map_option: OptionButton = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/MapOption
@onready var match_mode_actual_check: CheckButton = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/MatchModeActualCheck
@onready var matchmaking_button: Button = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/MatchmakingHBox/MatchmakingButton
@onready var matchmaking_timer_label: Label = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/MatchmakingHBox/MatchmakingTimerLabel
@onready var matchmaking_cap_slider: HSlider = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/MatchmakingCapHBox/MatchmakingCapSlider
@onready var matchmaking_cap_value_label: Label = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/MatchmakingCapHBox/MatchmakingCapValue
@onready var match_result_overlay: Control = $CanvasLayer/MatchResultOverlay
@onready var match_result_label: Label = $CanvasLayer/MatchResultOverlay/CenterContainer/ResultLabel
@onready var _hero_mm_bridge: Node = get_tree().root.get_node("HeroMmBridge")

const MAP_ID_MAP1 := "map1"
const MAP_ID_MAP2 := "map2"
const MAP_ID_MAP3 := "map3"
const MAP_ID_MAP4 := "map4"
const MAP_ID_MAP5 := "map5"
const MAP_ID_CLASSIC := "classic"
const MAP2_DEFAULT_ALBEDO_TEXTURE: Texture2D = preload("res://addons/kenney_prototype_textures/dark/texture_01.png")
const MAP_SCENE_PATHS: Dictionary = {
	MAP_ID_MAP1: "res://environment.tscn",
	MAP_ID_MAP2: "res://environment_map2.tscn",
	MAP_ID_MAP3: "res://environment_map3.tscn",
	MAP_ID_MAP4: "res://environment_map4.tscn",
	MAP_ID_MAP5: "res://environment_map5.tscn",
	MAP_ID_CLASSIC: "res://environment_classic.tscn",
}

const Player = preload("res://player.tscn")
const LandmineScene = preload("res://landmine.tscn")
const SmokeBombScene = preload("res://smoke_bomb.tscn")
const TankExplosionVfxScene = preload("res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_06.tscn")
const TankSecondaryExplosionVfxScene = preload("res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_05.tscn")
const TankLandmineImpactVfxScene = preload("res://assets/BinbunVFX/impact_explosions/effects/impact/vfx_impact_02.tscn")
const PlayerDeathExplosionVfxScene = preload("res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_01.tscn")
const Explosion1Sfx: AudioStream = preload("res://assets/sounds/effects/explosion_1.mp3")
const Explosion4Sfx: AudioStream = preload("res://assets/sounds/effects/explosion_4.wav")
const POST_PREMATCH_TICK_PATH := "res://assets/sounds/ui/uiyes.wav"
const EXPLOSION1_MAX_DB: float = -16.0 # heavily reduced explosion_1 baseline
const EXPLOSION_DEATH_SELF_QUIET_DB: float = -24.0
const EXPLOSION_SFX_MAX_DISTANCE: float = 28.0
const EXPLOSION_SFX_UNIT_SIZE: float = 4.0
const EXPLOSION1_SFX_MAX_DISTANCE: float = 42.0
const EXPLOSION1_SFX_UNIT_SIZE: float = 9.5
const MedicBurstImpactVfxScene = preload("res://assets/BinbunVFX/poison_effects/effects/poison_bubble/poison_bubble_vfx_03.tscn")
const MedicUltFootRippleVfxScene = preload("res://assets/BinbunVFX/magic_areas/effects/ripple_area/ripple_area_vfx_03.tscn")
const TANK_EXPLOSION_VFX_CLEANUP_SEC := 3.5
const TANK_SECONDARY_EXPLOSION_VFX_CLEANUP_SEC := 3.5
const TANK_LANDMINE_IMPACT_VFX_CLEANUP_SEC := 3.0
const PLAYER_DEATH_EXPLOSION_VFX_CLEANUP_SEC := 3.5
const MEDIC_BURST_IMPACT_VFX_CLEANUP_SEC := 2.0
const HEAVY_VFX_LIGHT_ENERGY_MULT := 0.35
const HEAVY_VFX_LIGHT_RANGE_MULT := 0.7
const HEAVY_VFX_MAX_LIGHTS_PER_EFFECT := 1
const HEAVY_VFX_LIGHT_SPECULAR_MAX := 0.2
const VFX_BEHIND_CAMERA_CULL_DOT := -0.3
const VFX_BEHIND_CAMERA_CULL_MIN_DISTANCE := 6.0
const MEDIC_BURST_PRIMARY := Color(0.82, 0.2, 1.0, 1.0)
const MEDIC_BURST_SECONDARY := Color(0.62, 0.12, 0.95, 1.0)
const MEDIC_BURST_TERTIARY := Color(0.32, 0.04, 0.74, 1.0)
## Medic ultimate: global team regen (authoritative ticks on host only).
## Allies: flat/sec + 5% of each ally’s max health per sec. Medic (healer_medic): flat/sec only.
const MEDIC_GLOBAL_ULT_DURATION_SEC := 13.0
const MEDIC_GLOBAL_ULT_FLAT_HEAL_PER_SEC := 20.0
const MEDIC_GLOBAL_ULT_MAX_HP_FRACTION_PER_SEC := 0.05
const MEDIC_GLOBAL_ULT_TICK_SEC := 0.15
const HEALER_MEDIC_HERO_ID := "healer_medic"
## Match tank laser ult style: attach to player and offset slightly upward from origin.
const MEDIC_ULT_FOOT_VFX_Y_OFF: float = 0.22
const MEDIC_ULT_FX_ALLY_PRIMARY: Color = Color(0.18, 0.95, 0.42, 1.0)
const MEDIC_ULT_FX_ALLY_SECONDARY: Color = Color(0.08, 0.5, 0.28, 1.0)
const MEDIC_ULT_FX_ENEMY_PRIMARY: Color = Color(0.95, 0.16, 0.12, 1.0)
const MEDIC_ULT_FX_ENEMY_SECONDARY: Color = Color(0.55, 0.1, 0.08, 1.0)
const PORT = 9999
## GD-Sync Indie (and below) lobby size cap; matches max players you want in one ENet game.
const ONLINE_LOBBY_MAX_PLAYERS := 8
## Matchmaking lobby names `HeroMM2` … `HeroMM6` — one queue per selected player cap.
const MATCHMAKING_CAP_MIN := 2
const MATCHMAKING_CAP_MAX := 6
## Deterministic queue connect: awaited signals + retries (no fragile one-shot chains).
const MM_AFTER_LEAVE_DELAY_SEC := 0.15
const MM_SIGNAL_WAIT_SEC := 10.0
const MM_JOIN_ATTEMPT_ROUNDS := 18
const MM_JOIN_RETRY_DELAY_SEC := 0.2
const MM_JOIN_RESULT_OK := -1
const MM_JOIN_RESULT_TIMEOUT := -2
const MM_CREATE_SIGNAL_TIMEOUT := -400
## GD-Sync lobby player_data: only clients actively in MM queue (not in a live match).
const MM_PLAYER_DATA_SEARCHING := "hs_mm_search"
## Set while in cloud/lobby match so MM UI does not count you as "searching".
const MM_PLAYER_DATA_IN_MATCH := "hs_in_match"
var _gdsync_online_intent: String = "" # "host" | "join"
var _gdsync_lobby_name: String = ""
const TEAM_A_SPAWN_CENTER := Vector3(90, 1, 0)
const TEAM_B_SPAWN_CENTER := Vector3(-90, 1, 0)
const MAP2_TEAM_A_SPAWN_CENTER := Vector3(45, 4, 0)
const MAP2_TEAM_B_SPAWN_CENTER := Vector3(-45, 4, 0)
const MAP3_TEAM_A_SPAWN_CENTER := Vector3(90, 3.1, 0)
const MAP3_TEAM_B_SPAWN_CENTER := Vector3(-90, 3.1, 0)
const MAP4_TEAM_A_SPAWN_CENTER := Vector3(90, 3.1, 0)
const MAP4_TEAM_B_SPAWN_CENTER := Vector3(-90, 3.1, 0)
const MAP5_TEAM_A_SPAWN_CENTER := Vector3(90, 3.1, 0)
const MAP5_TEAM_B_SPAWN_CENTER := Vector3(-90, 3.1, 0)
## Objective sits at world origin on XZ; blend arenas (Map 3–5) floors sit higher — lift the capture volume slightly.
const CAPTURE_POINT_DEFAULT_Y := 0.0
const CAPTURE_POINT_EXTRA_Y_BLEND_ARENAS := 2.0
## Team A (+X) / Team B (−X) spawn volumes: damage immunity + passive heal while inside (disabled on Map 2).
const SPAWN_ROOM_TEAM_A_X_MIN := 83.6
const SPAWN_ROOM_TEAM_A_X_MAX := 97.0
const SPAWN_ROOM_TEAM_B_X_MIN := -97.0
const SPAWN_ROOM_TEAM_B_X_MAX := -83.6
const SPAWN_ROOM_Z_MIN := -8.2
const SPAWN_ROOM_Z_MAX := 8.2
const SPAWN_ROOM_Y_MIN := 0.0
const SPAWN_ROOM_Y_MAX := 6.0
## One-way glass walls at map X; removed after prematch (actual) or shortly after go-live (practice).
const SPAWN_DOOR_TEAM_A_X0 := 82.4
const SPAWN_DOOR_TEAM_A_X1 := 82.9
const SPAWN_DOOR_TEAM_B_X0 := -82.9
const SPAWN_DOOR_TEAM_B_X1 := -82.4
const SPAWN_DOOR_Y_MIN := 0.0
const SPAWN_DOOR_Y_MAX := 9.0
const SPAWN_DOOR_Z_MIN := -10.0
const SPAWN_DOOR_Z_MAX := 10.0
const SPAWN_DOOR_OPEN_DELAY_ACTUAL_MS := 20_000
const SPAWN_DOOR_OPEN_DELAY_PRACTICE_MS := 2_000
const POST_PREMATCH_COUNTDOWN_SEC := 20
## First teammate at team center; next at +Z / -Z; extras step along +X so nobody overlaps.
const TEAM_SPAWN_MATE_Z_OFFSET := 4.0
const TEAM_SPAWN_X_STEP := 3.5
const TEAM_A_YAW := PI / 2.0
const TEAM_B_YAW := -PI / 2.0
const FEED_COLOR_SELF := "ffe066" # warm yellow
const FEED_COLOR_ALLY := "8ecbff" # light blue
const FEED_COLOR_ENEMY := "ff9a9a" # light red
var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var local_team_id: int = 0 # 0 = Team A, 1 = Team B
var local_hero_id: String = "dps_missile"
var local_requested_username: String = ""
var peer_teams: Dictionary = {} # peer_id -> team_id
var peer_heroes: Dictionary = {} # peer_id -> hero_id
var peer_usernames: Dictionary = {} # peer_id -> username
var recently_damaged_by_me: Dictionary = {} # peer_id -> timestamp (for enemy health bar visibility)
const DAMAGED_VISIBLE_MS := 5000
var respawn_end_ms: int = 0
var _medic_global_ult_end_msec: Dictionary = {} # team_id -> end Time.get_ticks_msec()
var _medic_global_ult_tick_accum: Dictionary = {} # team_id -> float
## "team_id:peer_id" -> fractional heal carry (per player; rates differ by hero + max health).
var _medic_global_ult_player_carry: Dictionary = {}
var _medic_ult_foot_vfx: Dictionary = {} # peer_id -> Node3D (ult HoT target rings; tinted by viewer’s team)
## Active level; host picks before start, joiners mirror via ENet RPC or GD-Sync lobby tag `map_id`.
var match_map_id: String = MAP_ID_MAP1
## Synced from host: 100% mission ends match; pregame countdown disables combat.
var match_rules_actual: bool = false
## Local Time.get_ticks_msec() deadline for combat go-live (each peer applies host-sent *remaining* ms).
var _match_go_live_at_msec: int = 0
var _match_end_screen_until_msec: int = 0
var _match_winner_team_id: int = -1
var _match_pending_return_to_menu: bool = false
const MATCH_PREGAME_SEC := 20
const MATCH_END_SCREEN_MS := 3800
var _matchmaking_active: bool = false
var _matchmaking_search_start_msec: int = 0
var _mm_start_committed: bool = false
var _matchmaking_used_for_current_game: bool = false
## Snapshot of queue-size slider when search starts (slider is disabled while searching).
var _matchmaking_locked_cap: int = 6
## Boot Play → world: hide debug UI until `gdsync_mm_execute_transition` finishes (avoids one-frame flash).
var _mm_hide_debug_ui_boot: bool = false
## GD-Sync actual match: host waits for this roster set before broadcasting pregame timer so all peers share one start time.
var _mm_pregame_barrier_active: bool = false
var _mm_pregame_pending_ids: Dictionary = {}
## Host: readies received before `_mm_init_pregame_ready_barrier_host` runs (fast clients vs slow host).
var _mm_pregame_early_ready_ids: Dictionary = {}
## Local: true after world load until host sends `gdsync_apply_match_session` (locks combat / HUD countdown).
var _mm_pregame_local_waiting: bool = false
## Actual-match prematch: pawns hidden until each peer confirms a pick; cleared when overlay closes.
var _prematch_hide_pawns_phase: bool = false
var peer_prematch_pick_revealed: Dictionary = {} # peer_id -> true
## During prematch overlay only: heroes whose roles are reserved by a lock click (cleared on unlock).
var peer_prematch_locked_hero_id: Dictionary = {} # peer_id -> hero_id
var _pause_audio_bus_by_key: Dictionary = {} # "master" | "sfx" | "voice" | "music" -> bus index
var _explosion_audio_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spawn_doors_root: Node3D = null
var _spawn_door_mesh_team0: MeshInstance3D = null
var _spawn_door_mesh_team1: MeshInstance3D = null
## Wall removal at `Time.get_ticks_msec()`; -1 = inactive.
var _spawn_door_hide_at_msec: int = -1
var _post_prematch_countdown_label: RichTextLabel = null
var _post_prematch_tick_player: AudioStreamPlayer = null
var _post_prematch_tick_stream: AudioStream = null
var _post_prematch_tick_stream_load_attempted: bool = false
var _post_prematch_prev_secs_left: int = -1
## `Time.get_ticks_msec()` when post-prematch UI countdown ends; -1 = inactive.
var _post_prematch_countdown_end_msec: int = -1

func _ready() -> void:
	_explosion_audio_rng.randomize()
	if team_option:
		team_option.clear()
		team_option.add_item("Team A", 0)
		team_option.add_item("Team B", 1)
		team_option.selected = 0
		local_team_id = team_option.selected
		team_option.item_selected.connect(_on_team_option_item_selected)
	if hero_option:
		hero_option.clear()
		for hid in HeroesRegistry.get_world_menu_hero_ids(GameSettings.debug_world_boot):
			var hero: HeroResource = HeroesRegistry.get_hero(hid)
			hero_option.add_item(hero.display_name if hero else hid, hero_option.item_count)
			hero_option.set_item_metadata(hero_option.item_count - 1, hid)
		hero_option.item_selected.connect(_on_hero_option_item_selected)
		_sync_hero_option_to_id("dps_missile")
	if username_entry:
		username_entry.max_length = 20
		username_entry.placeholder_text = "Enter username (optional)"
		username_entry.text = ""
	var quser: String = GameSettings.take_queued_player_username()
	if username_entry and not quser.is_empty():
		username_entry.text = quser
	if character_select:
		character_select.hide()
		character_select.hero_selected.connect(_on_character_select_hero_chosen)
	if pause_menu != null:
		pause_menu.hide()
	if pause_resume_button != null and not pause_resume_button.pressed.is_connected(_on_pause_resume_button_pressed):
		pause_resume_button.pressed.connect(_on_pause_resume_button_pressed)
	if pause_respawn_button != null and not pause_respawn_button.pressed.is_connected(_on_pause_respawn_button_pressed):
		pause_respawn_button.pressed.connect(_on_pause_respawn_button_pressed)
	if pause_main_menu_button != null and not pause_main_menu_button.pressed.is_connected(_on_pause_main_menu_button_pressed):
		pause_main_menu_button.pressed.connect(_on_pause_main_menu_button_pressed)
	_init_pause_audio_controls()
	if map_option:
		map_option.clear()
		map_option.add_item("Arena (Map 1)", 0)
		map_option.set_item_metadata(0, MAP_ID_MAP1)
		map_option.add_item("Arena (Map 4)", 1)
		map_option.set_item_metadata(1, MAP_ID_MAP4)
		map_option.add_item("Arena (Map 5)", 2)
		map_option.set_item_metadata(2, MAP_ID_MAP5)
		map_option.add_item("Classic arena", 3)
		map_option.set_item_metadata(3, MAP_ID_CLASSIC)
		map_option.select(0)
	_sync_mouse_sensitivity_ui()
	if matchmaking_cap_slider != null:
		matchmaking_cap_slider.min_value = MATCHMAKING_CAP_MIN
		matchmaking_cap_slider.max_value = MATCHMAKING_CAP_MAX
		matchmaking_cap_slider.step = 1
		matchmaking_cap_slider.value = 6
		if not matchmaking_cap_slider.value_changed.is_connected(_on_matchmaking_cap_slider_value_changed):
			matchmaking_cap_slider.value_changed.connect(_on_matchmaking_cap_slider_value_changed)
		_on_matchmaking_cap_slider_value_changed(matchmaking_cap_slider.value)
	if not GDSync.lobbies_received.is_connected(_on_public_lobbies_received):
		GDSync.lobbies_received.connect(_on_public_lobbies_received)
	_ensure_post_prematch_countdown_label()
	HeroEffectsPreload.warm_always(self)
	HeroEffectsPreload.warm_all_registered_heroes(self)
	if _is_dedicated_server_process():
		main_menu.hide()
		hud.show()
		_start_enet_host_game()
	if GameSettings.mm_pending_execute_after_world_load:
		_mm_hide_debug_ui_boot = true
		if main_menu != null:
			main_menu.hide()
		if debug_readout != null:
			debug_readout.hide()
	call_deferred("_ensure_environment_collisions")
	call_deferred("_strip_imported_environment_directional_lights")
	call_deferred("_maybe_mm_execute_after_menu_bridge")


func _maybe_mm_execute_after_menu_bridge() -> void:
	if _is_dedicated_server_process():
		return
	if not GameSettings.take_mm_pending_execute_after_world_load():
		return
	await gdsync_mm_execute_transition()


func _set_map_selector_enabled(enabled: bool) -> void:
	if map_option != null:
		map_option.disabled = not enabled


func _normalize_map_id(raw: String) -> String:
	var s: String = raw.strip_edges()
	if MAP_SCENE_PATHS.has(s):
		return s
	return MAP_ID_MAP1


func _map_id_from_ui() -> String:
	if map_option == null or map_option.item_count <= 0:
		return MAP_ID_MAP1
	var meta: Variant = map_option.get_item_metadata(map_option.selected)
	if meta != null:
		return _normalize_map_id(str(meta))
	return MAP_ID_MAP1


func _swap_match_environment(map_id: String) -> void:
	var mid: String = _normalize_map_id(map_id)
	var path: String = str(MAP_SCENE_PATHS[mid])
	if not ResourceLoader.exists(path):
		push_warning("Map scene missing: %s — falling back to map1." % path)
		mid = MAP_ID_MAP1
		path = str(MAP_SCENE_PATHS[mid])
	var prev: Node = get_node_or_null("Environment")
	var prev_tf: Transform3D = Transform3D(
		Vector3(2, 0, 0),
		Vector3(0, 1, 0),
		Vector3(0, 0, 1),
		Vector3.ZERO,
	)
	if prev != null:
		prev_tf = (prev as Node3D).transform
		remove_child(prev)
		prev.free()
	var packed: PackedScene = load(path) as PackedScene
	var inst: Node = packed.instantiate()
	add_child(inst)
	inst.name = "Environment"
	move_child(inst, mini(2, get_child_count() - 1))
	if inst is Node3D:
		(inst as Node3D).transform = prev_tf
	match_map_id = mid
	_apply_capture_point_height_for_map()
	_ensure_spawn_door_walls()
	call_deferred("_ensure_environment_collisions")
	call_deferred("_strip_imported_environment_directional_lights")
	call_deferred("_apply_map2_preview_materials")


func _apply_capture_point_height_for_map() -> void:
	if capture_point == null:
		return
	var y: float = CAPTURE_POINT_DEFAULT_Y
	if match_map_id == MAP_ID_MAP3 or match_map_id == MAP_ID_MAP4 or match_map_id == MAP_ID_MAP5:
		y += CAPTURE_POINT_EXTRA_Y_BLEND_ARENAS
	var p: Vector3 = capture_point.position
	capture_point.position = Vector3(p.x, y, p.z)


func _ensure_environment_collisions() -> void:
	var env_node: Node = get_node_or_null("Environment")
	if env_node == null:
		return
	for mesh_node in env_node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh_node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# Skip meshes that already have collision under them.
		if not mi.find_children("*", "StaticBody3D", true, false).is_empty():
			continue
		var shape: Shape3D = mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "AutoCollision"
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		mi.add_child(body)


func _strip_imported_environment_directional_lights() -> void:
	## `world.tscn` already has a main `DirectionalLight3D`; `Environment.blend` often ships another → two “suns”.
	var env_node: Node = get_node_or_null("Environment")
	if env_node == null:
		return
	for n in env_node.find_children("*", "DirectionalLight3D", true, false):
		n.queue_free()


func _apply_map2_preview_materials() -> void:
	if match_map_id != MAP_ID_MAP2:
		return
	var env_node: Node = get_node_or_null("Environment")
	if env_node == null:
		return
	var shared_mat := StandardMaterial3D.new()
	shared_mat.albedo_texture = MAP2_DEFAULT_ALBEDO_TEXTURE
	shared_mat.roughness = 0.92
	shared_mat.uv1_scale = Vector3(3.0, 3.0, 1.0)
	for mesh_node in env_node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh_node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var surface_count: int = mi.mesh.get_surface_count()
		for surf_i in range(surface_count):
			mi.set_surface_override_material(surf_i, shared_mat)
	for csg_node in env_node.find_children("*", "CSGShape3D", true, false):
		var csg: CSGShape3D = csg_node as CSGShape3D
		if csg == null:
			continue
		csg.material = shared_mat


func _is_dedicated_server_process() -> bool:
	return "--dedicated-server" in OS.get_cmdline_args()


## Public ENet host (VPS). When set, online host/join skip listen-server and UPnP; see class doc above.
func _enet_match_server() -> String:
	return str(ProjectSettings.get_setting("hero_shooter/enet_match_server", "")).strip_edges()


func _on_hero_option_item_selected(index: int) -> void:
	var meta: Variant = hero_option.get_item_metadata(index)
	if meta != null:
		local_hero_id = str(meta)

func _sync_hero_option_to_id(hero_id: String) -> void:
	if hero_option == null:
		return
	for i in hero_option.item_count:
		if str(hero_option.get_item_metadata(i)) == hero_id:
			hero_option.select(i)
			local_hero_id = hero_id
			return
	if hero_option.item_count > 0:
		hero_option.select(0)
		local_hero_id = str(hero_option.get_item_metadata(0))


func _sync_mouse_sensitivity_ui() -> void:
	if mouse_sensitivity_slider == null:
		return
	mouse_sensitivity_slider.set_value_no_signal(float(GameSettings.mouse_sensitivity_slider))
	_update_mouse_sensitivity_label()


func _update_mouse_sensitivity_label() -> void:
	if mouse_sensitivity_value:
		mouse_sensitivity_value.text = str(GameSettings.mouse_sensitivity_slider)


func _on_mouse_sensitivity_slider_value_changed(value: float) -> void:
	GameSettings.set_mouse_sensitivity_slider(int(round(value)))
	_update_mouse_sensitivity_label()


func apply_local_hero_from_authority(hero_id: String) -> void:
	if HeroesRegistry.get_hero(hero_id) == null:
		return
	local_hero_id = str(hero_id)
	_sync_hero_option_to_id(local_hero_id)
	var p: CharacterBody3D = get_node_or_null(str(HeroNet.my_id())) as CharacterBody3D
	if p != null and HeroNet.controls_local_pawn(p):
		p.hero_id = local_hero_id
		p._apply_hero_stats()


func apply_rejected_hero_pick(keep_hero_id: String) -> void:
	apply_local_hero_from_authority(str(keep_hero_id))
	if prematch_character_select != null:
		prematch_character_select.notify_pick_rejected_ui_only()


func set_local_player_hero(hero_id: String) -> void:
	if HeroesRegistry.get_hero(hero_id) == null:
		return
	local_hero_id = hero_id
	_sync_hero_option_to_id(hero_id)
	var p: CharacterBody3D = get_node_or_null(str(HeroNet.my_id())) as CharacterBody3D
	if p != null and HeroNet.controls_local_pawn(p):
		p.hero_id = hero_id
		p._apply_hero_stats()
	if not HeroNet.has_multiplayer_session():
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_on(GDSync.get_host(), Callable(self, "gdsync_net_request_hero"), [GDSync.get_client_id(), hero_id])
		return
	if multiplayer.is_server():
		peer_heroes[multiplayer.get_unique_id()] = hero_id
	else:
		request_hero.rpc_id(1, hero_id)

func _local_player_is_dead() -> bool:
	var p: Node = get_node_or_null(str(HeroNet.my_id()))
	return p != null and p.get("is_dead") == true

func is_character_select_open() -> bool:
	if character_select != null and character_select.visible:
		return true
	if prematch_character_select == null:
		return false
	return prematch_character_select.is_open()

## Opens the new full-screen `PrematchCharacterSelect` in in-match swap mode (B-key entrypoint).
## The legacy `CharacterSelectMenu` is no longer surfaced via B.
func _open_character_select() -> void:
	if prematch_character_select == null:
		return
	if prematch_character_select.is_prematch_open():
		# Match-start prematch is already showing; never replace it with a swap session.
		return
	if prematch_character_select.is_match_swap_open():
		return
	if match_rules_actual:
		var p_sel: CharacterBody3D = get_node_or_null(str(HeroNet.my_id())) as CharacterBody3D
		if p_sel == null or not is_player_in_own_spawn_room(p_sel):
			return
	if main_menu.visible or _local_player_is_dead():
		return
	prematch_character_select.begin(self, true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_character_select(play_cancel_sfx: bool = false) -> void:
	# Legacy menu (kept around for compatibility) — hide it if it ever became visible.
	if character_select != null and character_select.visible:
		if play_cancel_sfx and character_select.has_method("play_cancel_sfx"):
			character_select.play_cancel_sfx()
		character_select.hide()
	if prematch_character_select != null and prematch_character_select.is_match_swap_open():
		if play_cancel_sfx and prematch_character_select.has_method("play_cancel_sfx"):
			prematch_character_select.play_cancel_sfx()
		prematch_character_select.close_match_swap()
	var p: CharacterBody3D = get_node_or_null(str(HeroNet.my_id())) as CharacterBody3D
	if p != null and HeroNet.controls_local_pawn(p):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_character_select_hero_chosen(hero_id: String) -> void:
	set_local_player_hero(hero_id)
	_close_character_select()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _is_pause_menu_open():
			_set_pause_menu_open(false)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel") and (
		(character_select != null and character_select.visible)
		or (prematch_character_select != null and prematch_character_select.is_match_swap_open())
	):
		_close_character_select(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if main_menu != null and main_menu.visible:
			return
		if match_result_overlay != null and match_result_overlay.visible:
			return
		_set_pause_menu_open(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_hero_select") and not main_menu.visible:
		if prematch_character_select != null and prematch_character_select.is_prematch_open():
			# Match-start prematch is locked open until the timer / pick handler closes it.
			get_viewport().set_input_as_handled()
			return
		if match_rules_actual:
			var p_b: CharacterBody3D = get_node_or_null(str(HeroNet.my_id())) as CharacterBody3D
			if p_b == null or not is_player_in_own_spawn_room(p_b):
				get_viewport().set_input_as_handled()
				return
		if prematch_character_select != null and prematch_character_select.is_match_swap_open():
			_close_character_select(true)
		else:
			_open_character_select()
		get_viewport().set_input_as_handled()

func _on_team_option_item_selected(index: int) -> void:
	local_team_id = clampi(index, 0, 1)


func _on_host_button_pressed() -> void:
	_start_enet_host_game()


func _on_host_online_button_pressed() -> void:
	var name: String = _sanitize_online_lobby_name(online_lobby_field.text)
	if name.length() < 3:
		push_warning("Lobby name must be at least 3 characters (GD-Sync).")
		return
	local_requested_username = _sanitize_username_input(username_entry.text if username_entry else "")
	_gdsync_lobby_name = name
	_gdsync_online_intent = "host"
	_begin_gdsync_for_online()


func _on_join_online_button_pressed() -> void:
	var name: String = _sanitize_online_lobby_name(online_lobby_field.text)
	if name.length() < 3:
		push_warning("Lobby name must be at least 3 characters (GD-Sync).")
		return
	local_requested_username = _sanitize_username_input(username_entry.text if username_entry else "")
	_gdsync_lobby_name = name
	_gdsync_online_intent = "join"
	_begin_gdsync_for_online()


func _sanitize_online_lobby_name(raw: String) -> String:
	var s: String = raw.strip_edges()
	if s.length() > 32:
		s = s.substr(0, 32)
	return s


func _begin_gdsync_for_online() -> void:
	if GDSync.is_active():
		_on_gdsync_ready_for_online()
		return
	if not GDSync.connected.is_connected(_on_gdsync_ready_for_online):
		GDSync.connected.connect(_on_gdsync_ready_for_online, CONNECT_ONE_SHOT)
	if not GDSync.connection_failed.is_connected(_on_gdsync_online_connection_failed):
		GDSync.connection_failed.connect(_on_gdsync_online_connection_failed, CONNECT_ONE_SHOT)
	GDSync.start_multiplayer()


func _on_gdsync_online_connection_failed(_err: int) -> void:
	_gdsync_online_intent = ""
	_set_map_selector_enabled(true)
	push_error("GD-Sync connection failed — set public/private keys in the GD-Sync editor menu (Project → GD-Sync).")


func _on_gdsync_ready_for_online() -> void:
	match _gdsync_online_intent:
		"host":
			_gdsync_run_host_lobby_flow()
		"join":
			_gdsync_run_join_lobby_flow()
		_:
			pass


func _gdsync_run_host_lobby_flow() -> void:
	GDSync.lobby_leave()
	GDSync.lobby_created.connect(_on_gdsync_lobby_created_for_host, CONNECT_ONE_SHOT)
	GDSync.lobby_creation_failed.connect(_on_gdsync_lobby_creation_failed_for_host, CONNECT_ONE_SHOT)
	GDSync.lobby_create(_gdsync_lobby_name, "", true, ONLINE_LOBBY_MAX_PLAYERS, {"game": "HeroShooter"})


func _on_gdsync_lobby_created_for_host(lobby_name: String) -> void:
	GDSync.lobby_joined.connect(_on_gdsync_lobby_joined_for_host, CONNECT_ONE_SHOT)
	GDSync.lobby_join_failed.connect(_on_gdsync_lobby_join_failed_generic, CONNECT_ONE_SHOT)
	GDSync.lobby_join(lobby_name, "")


func _on_gdsync_lobby_joined_for_host(_lobby_name: String) -> void:
	var name_shown: String = _gdsync_lobby_name
	_gdsync_online_intent = ""
	GDSync.lobby_set_tag("map_id", _map_id_from_ui())
	GDSync.lobby_set_tag("match_actual", "1" if _match_rules_actual_from_menu() else "0")
	var dedicated: String = _enet_match_server()
	if not dedicated.is_empty():
		GDSync.lobby_set_tag("enet_mode", "dedicated")
		GDSync.lobby_set_tag("enet_host", dedicated)
		GDSync.lobby_set_tag("enet_port", str(PORT))
		print("GD-Sync lobby \"%s\" — dedicated ENet server %s:%d (you connect as client too)" % [name_shown, dedicated, PORT])
		_join_to_address(dedicated, PORT)
		return
	GDSync.lobby_set_tag("gameplay", "gdsync_cloud")
	print("GD-Sync lobby \"%s\" — cloud gameplay (GD-Sync relay, no ENet)." % name_shown)
	await _start_gdsync_cloud_gameplay()


func _on_gdsync_lobby_creation_failed_for_host(lobby_name: String, err: int) -> void:
	_gdsync_online_intent = ""
	_set_map_selector_enabled(true)
	push_error("GD-Sync: lobby_create failed for \"%s\" (error %d). Name may be taken or invalid." % [lobby_name, err])


func _gdsync_run_join_lobby_flow() -> void:
	_set_map_selector_enabled(false)
	GDSync.lobby_leave()
	GDSync.lobby_joined.connect(_on_gdsync_lobby_joined_for_client, CONNECT_ONE_SHOT)
	GDSync.lobby_join_failed.connect(_on_gdsync_lobby_join_failed_generic, CONNECT_ONE_SHOT)
	GDSync.lobby_join(_gdsync_lobby_name, "")


func _on_gdsync_lobby_joined_for_client(_lobby_name: String) -> void:
	_gdsync_online_intent = ""
	var dedicated: String = _enet_match_server()
	if not dedicated.is_empty():
		await _join_enet_after_lobby_tags()
		return
	for _i in 40:
		await get_tree().create_timer(0.1).timeout
		var mode: String = str(GDSync.lobby_get_tag("gameplay", "")).strip_edges()
		if mode == "gdsync_cloud":
			await _start_gdsync_cloud_gameplay()
			return
		var ip: String = str(GDSync.lobby_get_tag("enet_host", "")).strip_edges()
		if not ip.is_empty():
			await _join_enet_after_lobby_tags()
			return
	push_error("Lobby tags never arrived (gameplay / enet_host). Try again or check GD-Sync connection.")
	GDSync.lobby_leave()


func _join_enet_after_lobby_tags() -> void:
	var dedicated: String = _enet_match_server()
	if not dedicated.is_empty():
		print("Joining dedicated ENet server ", dedicated, ":", PORT)
		_join_to_address(dedicated, PORT)
		return
	var ip: String = ""
	var join_port: int = PORT
	for _i in 40:
		await get_tree().create_timer(0.1).timeout
		ip = str(GDSync.lobby_get_tag("enet_host", "")).strip_edges()
		if ip.is_empty():
			ip = str(GDSync.lobby_get_tag("enet_host_lan", "")).strip_edges()
		var ps: String = str(GDSync.lobby_get_tag("enet_port", str(PORT)))
		if ps.is_valid_int():
			join_port = int(ps)
		if not ip.is_empty():
			break
	if ip.is_empty():
		push_error("No ENet address in lobby yet. Wait for the host to finish starting, or check lobby name.")
		GDSync.lobby_leave()
		return
	print("Joining ENet at ", ip, ":", join_port)
	_join_to_address(ip, join_port)


func _on_gdsync_lobby_join_failed_generic(lobby_name: String, err: int) -> void:
	_gdsync_online_intent = ""
	_set_map_selector_enabled(true)
	push_error("GD-Sync: could not join lobby \"%s\" (error %d)." % [lobby_name, err])


func _on_matchmaking_button_pressed() -> void:
	if _matchmaking_active:
		_matchmaking_cancel()
		return
	if not GDSync.is_active():
		if not GDSync.connected.is_connected(_matchmaking_after_gdsync_connected):
			GDSync.connected.connect(_matchmaking_after_gdsync_connected, CONNECT_ONE_SHOT)
		if not GDSync.connection_failed.is_connected(_matchmaking_gdsync_connection_failed):
			GDSync.connection_failed.connect(_matchmaking_gdsync_connection_failed, CONNECT_ONE_SHOT)
		GDSync.start_multiplayer()
		return
	_matchmaking_begin_after_connected()


func _matchmaking_after_gdsync_connected() -> void:
	_matchmaking_begin_after_connected()


func _matchmaking_gdsync_connection_failed(_err: int) -> void:
	push_error("GD-Sync connection failed — cannot use matchmaking (configure keys under Project → GD-Sync).")


func _matchmaking_player_cap_from_ui() -> int:
	if GameSettings.matchmaking_cap_override >= MATCHMAKING_CAP_MIN:
		var co: int = clampi(GameSettings.matchmaking_cap_override, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
		GameSettings.matchmaking_cap_override = -1
		return co
	if matchmaking_cap_slider == null:
		return 6
	return clampi(int(round(matchmaking_cap_slider.value)), MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)


func _matchmaking_lobby_name_from_cap(cap: int) -> String:
	var c: int = clampi(cap, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	return "HeroMM%d" % c


func _on_matchmaking_cap_slider_value_changed(value: float) -> void:
	if matchmaking_cap_value_label != null:
		matchmaking_cap_value_label.text = str(int(round(value)))


func _matchmaking_set_cap_controls_enabled(enabled: bool) -> void:
	if matchmaking_cap_slider != null:
		matchmaking_cap_slider.editable = enabled


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


func _matchmaking_effective_cap_for_display() -> int:
	if GDSync.is_active():
		var tr: String = str(GDSync.lobby_get_tag("mm_required", "")).strip_edges()
		if tr.is_valid_int():
			return clampi(int(tr), MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
		var lim: int = GDSync.lobby_get_player_limit()
		if lim > 0:
			return lim
	if _matchmaking_active:
		return clampi(_matchmaking_locked_cap, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	return _matchmaking_player_cap_from_ui()


func _matchmaking_cap_from_lobby_get_name() -> int:
	var n: String = str(GDSync.lobby_get_name()).strip_edges()
	if not n.begins_with("HeroMM") or n.length() <= 6:
		return -1
	var tail: String = n.substr(6)
	if tail.is_valid_int():
		return clampi(int(tail), MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	return -1


func _matchmaking_required_players_for_host() -> int:
	var tr: String = str(GDSync.lobby_get_tag("mm_required", "")).strip_edges()
	if tr.is_valid_int():
		return clampi(int(tr), MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	var from_nm: int = _matchmaking_cap_from_lobby_get_name()
	if from_nm >= MATCHMAKING_CAP_MIN:
		return from_nm
	return clampi(_matchmaking_locked_cap, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)


func _matchmaking_current_players_for_display() -> int:
	if not GDSync.is_active():
		return 0
	var n: int = 0
	for cid_raw in GDSync.lobby_get_all_clients():
		var cid: int = int(cid_raw)
		if str(GDSync.player_get_data(cid, MM_PLAYER_DATA_SEARCHING, "")).strip_edges() == "1":
			n += 1
	return n


func _matchmaking_begin_after_connected() -> void:
	GameSettings.mm_from_main_menu = false
	local_requested_username = _sanitize_username_input(username_entry.text if username_entry else "")
	_matchmaking_locked_cap = _matchmaking_player_cap_from_ui()
	_matchmaking_search_start_msec = Time.get_ticks_msec()
	_matchmaking_active = true
	_mm_start_committed = false
	if matchmaking_button:
		matchmaking_button.text = "Cancel search"
	_matchmaking_set_cap_controls_enabled(false)
	_matchmaking_connect_signals()
	await _matchmaking_run_queue_pipeline()


## Single outcome from one [method GDSync.lobby_join]: MM_JOIN_RESULT_OK, MM_JOIN_RESULT_TIMEOUT, or a LOBBY_JOIN_ERROR code.
func _mm_join_once(lobby_nm: String) -> int:
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
		if not _matchmaking_active:
			return MM_JOIN_RESULT_TIMEOUT
		await get_tree().process_frame
	if not box["done"]:
		return MM_JOIN_RESULT_TIMEOUT
	if box["ok"]:
		return MM_JOIN_RESULT_OK
	return int(box["err"])


## Returns lobby name [String] on success, or LOBBY_CREATION_ERROR [int] on failure / timeout.
func _mm_create_once(lobby_nm: String, tags: Dictionary) -> Variant:
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
		if not _matchmaking_active:
			return MM_CREATE_SIGNAL_TIMEOUT
		await get_tree().process_frame
	if not box["done"]:
		return MM_CREATE_SIGNAL_TIMEOUT
	var nm: String = str(box["name"]).strip_edges()
	if not nm.is_empty():
		return nm
	return int(box["err"])


func _matchmaking_run_queue_pipeline() -> void:
	var lobby_nm: String = _matchmaking_lobby_name_from_cap(_matchmaking_locked_cap)
	GDSync.lobby_leave()
	await get_tree().create_timer(MM_AFTER_LEAVE_DELAY_SEC).timeout
	if not _matchmaking_active:
		return
	var round_i: int = 0
	while round_i < MM_JOIN_ATTEMPT_ROUNDS and _matchmaking_active:
		var jr: int = await _mm_join_once(lobby_nm)
		if not _matchmaking_active:
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
			_matchmaking_queue_joined(lobby_nm)
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
			_matchmaking_cancel()
			push_error("GD-Sync: duplicate username — set a unique username and try matchmaking again.")
			return
		round_i += 1
		await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
	if not _matchmaking_active:
		return
	var cap: int = clampi(_matchmaking_locked_cap, MATCHMAKING_CAP_MIN, MATCHMAKING_CAP_MAX)
	var tags: Dictionary = {
		"game": "HeroShooter",
		"mode": "matchmaking",
		"cap": str(cap),
		"mm_required": str(cap),
	}
	var created: Variant = await _mm_create_once(lobby_nm, tags)
	if typeof(created) == TYPE_STRING:
		await _matchmaking_enter_created_lobby(str(created))
		return
	var ce: int = int(created)
	if ce == MM_CREATE_SIGNAL_TIMEOUT:
		if _matchmaking_active:
			_matchmaking_cancel()
			push_error("GD-Sync: lobby_create did not respond in time — check connection.")
		return
	if ce == int(ENUMS.LOBBY_CREATION_ERROR.LOBBY_ALREADY_EXISTS):
		for _j in range(MM_JOIN_ATTEMPT_ROUNDS):
			if not _matchmaking_active:
				return
			var jr2: int = await _mm_join_once(lobby_nm)
			if not _matchmaking_active:
				return
			if jr2 == MM_JOIN_RESULT_OK:
				await get_tree().process_frame
				if str(GDSync.lobby_get_tag("match_session_live", "")).strip_edges() == "1":
					GDSync.lobby_leave()
					await get_tree().create_timer(MM_AFTER_LEAVE_DELAY_SEC).timeout
					await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
					continue
				_matchmaking_queue_joined(lobby_nm)
				return
			await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
		_matchmaking_cancel()
		push_warning("Matchmaking: queue lobby exists but join did not succeed — try again in a moment.")
		return
	_matchmaking_cancel()
	push_error("GD-Sync: matchmaking lobby_create failed (error %d)." % ce)


func _matchmaking_enter_created_lobby(lobby_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _matchmaking_enter_queue_if_already_joined(lobby_name):
		return
	for _k in range(MM_JOIN_ATTEMPT_ROUNDS):
		if not _matchmaking_active:
			return
		var jr: int = await _mm_join_once(lobby_name)
		if not _matchmaking_active:
			return
		if jr == MM_JOIN_RESULT_OK:
			await get_tree().process_frame
			if str(GDSync.lobby_get_tag("match_session_live", "")).strip_edges() == "1":
				await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
				continue
			_matchmaking_queue_joined(lobby_name)
			return
		if _matchmaking_enter_queue_if_already_joined(lobby_name):
			return
		await get_tree().create_timer(MM_JOIN_RETRY_DELAY_SEC).timeout
	_matchmaking_cancel()
	push_error("GD-Sync: could not enter matchmaking lobby after create.")


func _matchmaking_enter_queue_if_already_joined(lobby_name: String) -> bool:
	var want: String = lobby_name.strip_edges()
	if want.is_empty():
		return false
	if str(GDSync.lobby_get_tag("match_session_live", "")).strip_edges() == "1":
		return false
	if str(GDSync.lobby_get_name()).strip_edges() != want:
		return false
	# lobby_join() sets name before the server ack — require synced lobby data from the server.
	if GDSync.lobby_get_player_limit() <= 0:
		return false
	_matchmaking_queue_joined(want)
	return true


func _matchmaking_queue_joined(_lobby_name: String) -> void:
	if not _matchmaking_active:
		return
	_mm_set_lobby_player_searching(true)
	if GDSync.is_host():
		call_deferred("_matchmaking_host_try_start")


func _matchmaking_connect_signals() -> void:
	if not GDSync.client_joined.is_connected(_matchmaking_on_client_joined):
		GDSync.client_joined.connect(_matchmaking_on_client_joined)


func _matchmaking_disconnect_signals() -> void:
	if GDSync.client_joined.is_connected(_matchmaking_on_client_joined):
		GDSync.client_joined.disconnect(_matchmaking_on_client_joined)


func _matchmaking_on_client_joined(_client_id: int) -> void:
	if not _matchmaking_active:
		return
	if not (GameSettings.mm_from_main_menu or (main_menu != null and main_menu.visible)):
		return
	if GDSync.is_host():
		call_deferred("_matchmaking_host_try_start")


func _matchmaking_host_try_start() -> void:
	if not _matchmaking_active or _mm_start_committed:
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
	var required: int = _matchmaking_required_players_for_host()
	if clients.size() < required:
		return
	_mm_start_committed = true
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
	GDSync.lobby_set_tag("map_id", _map_id_from_ui())
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
	GDSync.call_func_all(Callable(_hero_mm_bridge, "gdsync_mm_execute_transition"), [])


func gdsync_mm_execute_transition() -> void:
	if not is_inside_tree():
		return
	if main_menu != null:
		main_menu.hide()
	if debug_readout != null:
		debug_readout.hide()
	_hero_mm_bridge.clear_menu_matchmaking_session_for_transition()
	_matchmaking_disconnect_signals()
	_matchmaking_stop_ui()
	_matchmaking_used_for_current_game = true
	await _matchmaking_apply_teams_from_lobby_tags()
	var dedicated: String = _enet_match_server()
	if not dedicated.is_empty():
		_join_to_address(dedicated, PORT)
		_mm_hide_debug_ui_boot = false
		return
	await _start_gdsync_cloud_gameplay()
	_mm_hide_debug_ui_boot = false


func _matchmaking_apply_teams_from_lobby_tags() -> void:
	var raw: String = ""
	for _i in 50:
		raw = str(GDSync.lobby_get_tag("mm_team_assign", "")).strip_edges()
		if not raw.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
	peer_teams.clear()
	if not raw.is_empty():
		var data: Variant = JSON.parse_string(raw)
		if typeof(data) == TYPE_DICTIONARY:
			for k in data.keys():
				peer_teams[int(k)] = int(data[k])
	var my_id: int = GDSync.get_client_id()
	if peer_teams.has(my_id):
		local_team_id = int(peer_teams[my_id])
		if team_option:
			team_option.select(local_team_id)


func _matchmaking_stop_ui() -> void:
	_matchmaking_active = false
	_matchmaking_locked_cap = 6
	_mm_set_lobby_player_searching(false)
	_matchmaking_set_cap_controls_enabled(true)
	if matchmaking_button:
		matchmaking_button.text = "Start Matchmaking"
	if matchmaking_timer_label:
		matchmaking_timer_label.text = ""


func _matchmaking_cancel() -> void:
	_matchmaking_disconnect_signals()
	_mm_start_committed = false
	_matchmaking_active = false
	_matchmaking_locked_cap = 6
	_mm_set_lobby_player_searching(false)
	_matchmaking_set_cap_controls_enabled(true)
	if matchmaking_button:
		matchmaking_button.text = "Start Matchmaking"
	if matchmaking_timer_label:
		matchmaking_timer_label.text = ""
	if GDSync.is_active():
		GDSync.lobby_leave()


func _matchmaking_update_timer_display() -> void:
	if matchmaking_timer_label == null or not _matchmaking_active:
		return
	var elapsed_ms: int = Time.get_ticks_msec() - _matchmaking_search_start_msec
	var sec: int = elapsed_ms / 1000
	var m: int = sec / 60
	var s: int = sec % 60
	var cur: int = _matchmaking_current_players_for_display()
	var lim: int = _matchmaking_effective_cap_for_display()
	matchmaking_timer_label.text = "%d:%02d (%d/%d)" % [m, s, cur, lim]


func _on_refresh_public_lobbies_pressed() -> void:
	if not GDSync.is_active():
		if not GDSync.connected.is_connected(_on_gdsync_connected_then_refresh_lobbies):
			GDSync.connected.connect(_on_gdsync_connected_then_refresh_lobbies, CONNECT_ONE_SHOT)
		GDSync.start_multiplayer()
		return
	GDSync.get_public_lobbies()


func _on_gdsync_connected_then_refresh_lobbies() -> void:
	GDSync.get_public_lobbies()


func _on_public_lobbies_received(lobbies: Array) -> void:
	if public_lobbies_list == null:
		return
	public_lobbies_list.clear()
	for entry: Variant in lobbies:
		if entry is Dictionary:
			var d: Dictionary = entry
			var n: String = str(d.get("Name", "")).strip_edges()
			if n.is_empty():
				continue
			var count: Variant = d.get("PlayerCount", d.get("Clients", "?"))
			public_lobbies_list.add_item("%s  (%s)" % [n, str(count)])
			public_lobbies_list.set_item_metadata(public_lobbies_list.item_count - 1, n)


func _on_join_selected_public_lobby_pressed() -> void:
	if public_lobbies_list == null or public_lobbies_list.item_count <= 0:
		push_warning("Refresh public lobbies and select a row first.")
		return
	var sel: PackedInt32Array = public_lobbies_list.get_selected_items()
	if sel.is_empty():
		push_warning("Select a lobby in the list.")
		return
	var meta: Variant = public_lobbies_list.get_item_metadata(sel[0])
	if meta == null:
		return
	var lobby_name: String = str(meta).strip_edges()
	if lobby_name.length() < 3:
		return
	if online_lobby_field:
		online_lobby_field.text = lobby_name
	local_requested_username = _sanitize_username_input(username_entry.text if username_entry else "")
	_gdsync_lobby_name = lobby_name
	_gdsync_online_intent = "join"
	_begin_gdsync_for_online()


func _register_gdsync_world_session() -> void:
	GDSync.expose_func(Callable(self, "gdsync_net_add_player"))
	GDSync.expose_func(Callable(self, "gdsync_net_remove_player"))
	GDSync.expose_func(Callable(self, "gdsync_apply_player_state"))
	GDSync.expose_func(Callable(self, "gdsync_apply_player_combat_state"))
	GDSync.expose_func(Callable(self, "gdsync_net_request_team"))
	GDSync.expose_func(Callable(self, "gdsync_net_request_hero"))
	GDSync.expose_func(Callable(self, "gdsync_net_request_username"))
	GDSync.expose_func(Callable(self, "gdsync_net_apply_team_everywhere"))
	GDSync.expose_func(Callable(self, "gdsync_net_apply_hero_everywhere"))
	GDSync.expose_func(Callable(self, "gdsync_net_apply_username_everywhere"))
	GDSync.expose_func(Callable(self, "gdsync_net_apply_landmine_snapshots"))
	GDSync.expose_func(Callable(self, "_spawn_tank_binbun_explosion_at"))
	GDSync.expose_func(Callable(self, "_spawn_tank_secondary_explosion_binbun_at"))
	GDSync.expose_func(Callable(self, "_spawn_tank_landmine_impact_binbun_at"))
	GDSync.expose_func(Callable(self, "_spawn_player_death_explosion_binbun_at"))
	GDSync.expose_func(Callable(self, "_spawn_medic_burst_impact_vfx_at"))
	GDSync.expose_func(Callable(self, "sync_medic_global_ultimate"))
	GDSync.expose_func(Callable(self, "spawn_smoke_bomb_at"))
	GDSync.expose_func(Callable(self, "gdsync_push_killfeed_line"))
	GDSync.expose_func(Callable(self, "gdsync_show_match_end"))
	GDSync.expose_func(Callable(self, "gdsync_net_set_prematch_pick_revealed"))
	GDSync.expose_func(Callable(self, "gdsync_net_request_prematch_role_lock"))
	GDSync.expose_func(Callable(self, "gdsync_net_apply_prematch_role_lock_everywhere"))
	if capture_point != null:
		GDSync.expose_node(capture_point)


func _start_gdsync_cloud_gameplay() -> void:
	HeroNet.kind = HeroNet.Kind.GDSYNC_CLOUD
	main_menu.hide()
	hud.hide()
	_register_gdsync_world_session()
	if not GDSync.client_joined.is_connected(_on_gdsync_client_joined):
		GDSync.client_joined.connect(_on_gdsync_client_joined)
	if not GDSync.client_left.is_connected(_on_gdsync_client_left):
		GDSync.client_left.connect(_on_gdsync_client_left)
	await get_tree().create_timer(0.2).timeout
	var tag_map: String = str(GDSync.lobby_get_tag("map_id", MAP_ID_MAP1)).strip_edges()
	if not GDSync.is_host():
		for _wait in 30:
			tag_map = str(GDSync.lobby_get_tag("map_id", "")).strip_edges()
			if not tag_map.is_empty():
				break
			await get_tree().create_timer(0.05).timeout
	if tag_map.is_empty():
		tag_map = MAP_ID_MAP1
	var resolved_map: String = _normalize_map_id(tag_map)
	_swap_match_environment(resolved_map)
	var tag_actual: String = str(GDSync.lobby_get_tag("match_actual", "0")).strip_edges()
	match_rules_actual = tag_actual == "1" or tag_actual.to_lower() == "true"
	if not match_rules_actual:
		hud.show()
	else:
		_prematch_hide_pawns_phase = true
		peer_prematch_pick_revealed.clear()
	_set_map_selector_enabled(false)
	if GDSync.is_host():
		if match_rules_actual:
			_mm_init_pregame_ready_barrier_host()
		else:
			_host_begin_match_timing_gdsync()
	## Spawn every roster client from `mm_team_assign` / `peer_teams` first — `lobby_get_all_clients()` can
	## briefly omit a peer during scene transition, which used to start the match without their pawn.
	for pid_raw in peer_teams.keys():
		gdsync_net_add_player(int(pid_raw))
	for cid_raw: Variant in GDSync.lobby_get_all_clients():
		var cid: int = int(cid_raw)
		if peer_teams.has(cid):
			continue
		gdsync_net_add_player(cid)
	_gdsync_send_picks_to_host()
	_mm_set_lobby_player_in_match(true)
	if HeroNet.is_gdsync() and match_rules_actual:
		_mm_pregame_local_waiting = true
		await get_tree().process_frame
		await get_tree().process_frame
		var hid: int = GDSync.get_host()
		var my_id: int = GDSync.get_client_id()
		if my_id == hid:
			gdsync_mm_pregame_client_ready(my_id)
		else:
			GDSync.call_func_on(hid, Callable(_hero_mm_bridge, "gdsync_mm_bridge_report_pregame_ready"), [my_id])


func _mm_init_pregame_ready_barrier_host() -> void:
	if not HeroNet.is_gdsync() or not GDSync.is_host():
		return
	_mm_pregame_pending_ids.clear()
	for pid_raw in peer_teams.keys():
		_mm_pregame_pending_ids[int(pid_raw)] = true
	if _mm_pregame_pending_ids.is_empty():
		var assign_raw: String = str(GDSync.lobby_get_tag("mm_team_assign", "")).strip_edges()
		if not assign_raw.is_empty():
			var parsed: Variant = JSON.parse_string(assign_raw)
			if typeof(parsed) == TYPE_DICTIONARY:
				for k in parsed.keys():
					_mm_pregame_pending_ids[int(k)] = true
	if _mm_pregame_pending_ids.is_empty():
		for x in GDSync.lobby_get_all_clients():
			_mm_pregame_pending_ids[int(x)] = true
	if _mm_pregame_pending_ids.is_empty():
		_mm_pregame_pending_ids[GDSync.get_client_id()] = true
	_mm_pregame_barrier_active = true
	for early_raw in _mm_pregame_early_ready_ids.keys():
		_mm_pregame_pending_ids.erase(int(early_raw))
	_mm_pregame_early_ready_ids.clear()
	if _mm_pregame_pending_ids.is_empty():
		_mm_pregame_barrier_active = false
		_host_begin_match_timing_gdsync()


func gdsync_mm_pregame_client_ready(reported_client_id: int) -> void:
	if not HeroNet.is_gdsync() or not GDSync.is_host():
		return
	var cid: int = int(reported_client_id)
	if not _mm_pregame_barrier_active:
		_mm_pregame_early_ready_ids[cid] = true
		return
	_mm_pregame_pending_ids.erase(cid)
	if _mm_pregame_pending_ids.is_empty():
		_mm_pregame_barrier_active = false
		_host_begin_match_timing_gdsync()


func _on_gdsync_client_joined(client_id: int) -> void:
	if not HeroNet.is_gdsync():
		return
	gdsync_net_add_player(client_id)
	if GDSync.is_host():
		_gdsync_sync_roster_to_client(client_id)
		var rem_ms: int = 0
		if match_rules_actual:
			rem_ms = maxi(0, _match_go_live_at_msec - Time.get_ticks_msec())
		GDSync.call_func_on(client_id, Callable(_hero_mm_bridge, "gdsync_mm_bridge_apply_match_session"), [match_rules_actual, rem_ms])
		call_deferred("_landmines_resync_to_peer", client_id)


func _gdsync_sync_roster_to_client(client_id: int) -> void:
	for pid_raw in peer_teams.keys():
		var pid: int = int(pid_raw)
		GDSync.call_func_on(client_id, Callable(self, "gdsync_net_apply_team_everywhere"), [pid, int(peer_teams[pid_raw])])
	for pid_raw in peer_heroes.keys():
		var pid: int = int(pid_raw)
		GDSync.call_func_on(client_id, Callable(self, "gdsync_net_apply_hero_everywhere"), [pid, str(peer_heroes[pid_raw])])
	for pid_raw in peer_usernames.keys():
		var pid: int = int(pid_raw)
		GDSync.call_func_on(client_id, Callable(self, "gdsync_net_apply_username_everywhere"), [pid, str(peer_usernames[pid_raw])])


func _on_gdsync_client_left(client_id: int) -> void:
	if not HeroNet.is_gdsync():
		return
	gdsync_net_remove_player(client_id)


func _gdsync_send_picks_to_host() -> void:
	if not HeroNet.is_gdsync():
		return
	var hid: int = GDSync.get_host()
	if not _matchmaking_used_for_current_game:
		GDSync.call_func_on(hid, Callable(self, "gdsync_net_request_team"), [GDSync.get_client_id(), local_team_id])
	GDSync.call_func_on(hid, Callable(self, "gdsync_net_request_hero"), [GDSync.get_client_id(), local_hero_id])
	GDSync.call_func_on(hid, Callable(self, "gdsync_net_request_username"), [GDSync.get_client_id(), local_requested_username])


func gdsync_net_add_player(peer_id: int) -> void:
	if get_node_or_null(str(peer_id)) != null:
		return
	var player: CharacterBody3D = Player.instantiate() as CharacterBody3D
	player.name = str(peer_id)
	if peer_teams.has(peer_id):
		player.team_id = int(peer_teams[peer_id])
	if peer_heroes.has(peer_id):
		player.hero_id = str(peer_heroes[peer_id])
	if peer_usernames.has(peer_id):
		player.player_username = str(peer_usernames[peer_id])
	add_child(player)
	GDSync.expose_node(player)
	respawn_player(player)
	_apply_prematch_visibility_to_single_player(int(peer_id), player)
	if HeroNet.controls_local_pawn(player):
		player.health_changed.connect(update_health_bar)
		_connect_local_death_signals(player)


func gdsync_net_remove_player(peer_id: int) -> void:
	peer_teams.erase(peer_id)
	peer_heroes.erase(peer_id)
	peer_usernames.erase(peer_id)
	peer_prematch_pick_revealed.erase(peer_id)
	peer_prematch_locked_hero_id.erase(peer_id)
	call_deferred("_deferred_free_peer_player_node", peer_id)


func _deferred_free_peer_player_node(peer_id: int) -> void:
	var pl: Node = get_node_or_null(str(peer_id))
	if pl != null and is_instance_valid(pl):
		pl.queue_free()


func gdsync_apply_player_state(sender_id: int, pos: Vector3, rot_y: float, pitch_x: float, vel: Vector3) -> void:
	if not HeroNet.is_gdsync():
		return
	if sender_id == GDSync.get_client_id():
		return
	var p: CharacterBody3D = get_node_or_null(str(sender_id)) as CharacterBody3D
	if p == null or not is_instance_valid(p):
		return
	if p.has_method("gdsync_receive_remote_snapshot"):
		p.gdsync_receive_remote_snapshot(pos, rot_y, pitch_x, vel)
	else:
		p.global_position = pos
		p.rotation.y = rot_y
		p.velocity = vel
		var cam: Node3D = p.get_node_or_null("Camera3D") as Node3D
		if cam != null:
			cam.rotation.x = clampf(pitch_x, -PI * 0.5, PI * 0.5)


## Called on every client via GD-Sync / RPC so non-authoritative copies get health + death visuals.
func gdsync_apply_player_combat_state(peer_id: int, health_val: int, dead: bool) -> void:
	_apply_player_combat_state_to_remote_puppet(peer_id, health_val, dead)


func broadcast_player_combat_replicate(peer_id: int, health_val: int, dead: bool) -> void:
	if not HeroNet.has_multiplayer_session():
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "gdsync_apply_player_combat_state"), [peer_id, health_val, dead])
		return
	if get_multiplayer().multiplayer_peer == null:
		return
	net_apply_player_combat_state.rpc(peer_id, health_val, dead)


func _apply_player_combat_state_to_remote_puppet(peer_id: int, health_val: int, dead: bool) -> void:
	var p: CharacterBody3D = get_node_or_null(str(peer_id)) as CharacterBody3D
	if p == null or not is_instance_valid(p):
		return
	if HeroNet.controls_local_pawn(p):
		return
	if p.has_method("apply_remote_combat_snapshot"):
		p.apply_remote_combat_snapshot(health_val, dead)


func _username_for_peer(peer_id: int) -> String:
	var from_map: String = str(peer_usernames.get(peer_id, "")).strip_edges()
	if not from_map.is_empty():
		return from_map
	var p: Node = get_node_or_null(str(peer_id))
	if p != null:
		var via_player: String = str(p.get("player_username") if p.get("player_username") != null else "").strip_edges()
		if not via_player.is_empty():
			return via_player
	return "Player"


func _killfeed_message_for(killer_peer_id: int, victim_peer_id: int) -> String:
	var killer_name: String
	if killer_peer_id > 0:
		killer_name = _username_for_peer(killer_peer_id)
	elif killer_peer_id < 0:
		killer_name = "The void"
	else:
		killer_name = "Unknown"
	var victim_name: String = _username_for_peer(victim_peer_id) if victim_peer_id > 0 else "Unknown"
	var killer_col: String = _feed_color_for_peer(killer_peer_id)
	var victim_col: String = _feed_color_for_peer(victim_peer_id)
	return "[color=#%s]%s[/color] killed [color=#%s]%s[/color]" % [killer_col, killer_name, victim_col, victim_name]


func _team_for_peer(peer_id: int) -> int:
	if peer_teams.has(peer_id):
		return int(peer_teams[peer_id])
	var p: Node = get_node_or_null(str(peer_id))
	if p != null and p.get("team_id") != null:
		return int(p.get("team_id"))
	return -1


func _feed_color_for_peer(peer_id: int) -> String:
	if peer_id <= 0:
		return FEED_COLOR_ENEMY
	var my_id: int = HeroNet.my_id()
	if peer_id == my_id:
		return FEED_COLOR_SELF
	var local_team: int = _team_for_peer(my_id)
	var target_team: int = _team_for_peer(peer_id)
	if local_team >= 0 and target_team >= 0 and local_team == target_team:
		return FEED_COLOR_ALLY
	return FEED_COLOR_ENEMY


func _push_killfeed_line_local(killer_peer_id: int, victim_peer_id: int) -> void:
	if hud == null or not hud.has_method("push_feed_line"):
		return
	hud.push_feed_line(_killfeed_message_for(killer_peer_id, victim_peer_id))


func broadcast_killfeed_line(killer_peer_id: int, victim_peer_id: int) -> void:
	if not HeroNet.has_multiplayer_session():
		_push_killfeed_line_local(killer_peer_id, victim_peer_id)
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "gdsync_push_killfeed_line"), [killer_peer_id, victim_peer_id])
		return
	net_push_killfeed_line.rpc(killer_peer_id, victim_peer_id)


func gdsync_push_killfeed_line(killer_peer_id: int, victim_peer_id: int) -> void:
	_push_killfeed_line_local(killer_peer_id, victim_peer_id)


@rpc("any_peer", "call_local", "reliable")
func net_push_killfeed_line(killer_peer_id: int, victim_peer_id: int) -> void:
	if HeroNet.is_gdsync():
		return
	_push_killfeed_line_local(killer_peer_id, victim_peer_id)


@rpc("any_peer", "call_local", "reliable")
func net_apply_player_combat_state(peer_id: int, health_val: int, dead: bool) -> void:
	if HeroNet.is_gdsync():
		return
	_apply_player_combat_state_to_remote_puppet(peer_id, health_val, dead)


func gdsync_net_request_team(client_id: int, team_id: int) -> void:
	if not GDSync.is_host():
		return
	if _matchmaking_used_for_current_game:
		return
	var requested: int = clampi(team_id, 0, 1)
	GDSync.call_func_all(Callable(self, "gdsync_net_apply_team_everywhere"), [client_id, requested])


func gdsync_net_apply_team_everywhere(client_id: int, team_id: int) -> void:
	var t: int = clampi(team_id, 0, 1)
	peer_teams[client_id] = t
	var p: CharacterBody3D = get_node_or_null(str(client_id)) as CharacterBody3D
	if p:
		p.team_id = t
		respawn_player(p)


func gdsync_net_request_hero(client_id: int, hero_id: String) -> void:
	if not GDSync.is_host():
		return
	if HeroesRegistry.get_hero(hero_id) == null:
		return
	if match_rules_actual and _gdsync_team_has_role_conflict(client_id, hero_id):
		var keep: String = str(peer_heroes.get(client_id, ""))
		if keep.is_empty():
			var pp: Node = get_node_or_null(str(client_id))
			if pp != null and pp.get("hero_id") != null:
				keep = str(pp.hero_id)
		if keep.is_empty():
			keep = "dps_missile"
		GDSync.call_func_on(client_id, Callable(_hero_mm_bridge, "gdsync_mm_bridge_hero_pick_rejected"), [keep])
		return
	GDSync.call_func_all(Callable(self, "gdsync_net_apply_hero_everywhere"), [client_id, hero_id])


func peer_hero_id_for_team_role_slot_conflict(teammate_peer_id: int) -> String:
	if match_rules_actual and prematch_character_select != null and prematch_character_select.is_prematch_open():
		return str(peer_prematch_locked_hero_id.get(teammate_peer_id, "")).strip_edges()
	return str(peer_heroes.get(teammate_peer_id, "")).strip_edges()


func _gdsync_team_has_role_conflict(client_id: int, hero_id: String) -> bool:
	var slot: int = HeroesRegistry.hero_role_slot(hero_id)
	if slot < 0:
		return true
	var team_id: int = int(peer_teams.get(client_id, 0))
	for pid_raw in peer_teams.keys():
		var pid: int = int(pid_raw)
		if pid == client_id:
			continue
		if int(peer_teams[pid_raw]) != team_id:
			continue
		var other: String = peer_hero_id_for_team_role_slot_conflict(pid)
		if other.is_empty():
			continue
		if HeroesRegistry.hero_role_slot(other) == slot:
			return true
	return false


func gdsync_net_apply_hero_everywhere(client_id: int, hero_id: String) -> void:
	if HeroesRegistry.get_hero(hero_id) == null:
		return
	peer_heroes[client_id] = hero_id
	var p: CharacterBody3D = get_node_or_null(str(client_id)) as CharacterBody3D
	if p:
		p.hero_id = hero_id
		p._apply_hero_stats()


func gdsync_net_request_username(client_id: int, requested_username: String) -> void:
	if not GDSync.is_host():
		return
	var resolved: String = _allocate_unique_username(requested_username, client_id)
	GDSync.call_func_all(Callable(self, "gdsync_net_apply_username_everywhere"), [client_id, resolved])


func gdsync_net_apply_username_everywhere(client_id: int, username: String) -> void:
	peer_usernames[client_id] = username
	var p: CharacterBody3D = get_node_or_null(str(client_id)) as CharacterBody3D
	if p:
		p.player_username = username
	if HeroNet.my_id() == client_id:
		local_requested_username = username
		if username_entry:
			username_entry.text = username


func _pick_lan_ipv4_for_clients() -> String:
	var candidates: Array[String] = []
	for a in IP.get_local_addresses():
		if a.contains(":"):
			continue
		if a.begins_with("127."):
			continue
		if a.begins_with("169.254."):
			continue
		candidates.append(a)
	for a in candidates:
		if a.begins_with("192.168."):
			return a
	for a in candidates:
		if a.begins_with("10."):
			return a
	if candidates.size() > 0:
		return candidates[0]
	return "127.0.0.1"


## Try to open `local_udp_port` UDP on the router (UPnP IGD) and learn our public IPv4.
func _try_upnp_map_udp(local_udp_port: int) -> Dictionary:
	var out: Dictionary = { "ok": false, "external_ip": "" }
	var u: UPNP = UPNP.new()
	var d: int = u.discover(2000, 2, "0.0.0.0")
	if d != UPNP.UPNP_RESULT_SUCCESS:
		return out
	var gw = u.get_gateway()
	if gw == null or not gw.is_valid_gateway():
		return out
	var ext: String = u.query_external_address()
	if ext.strip_edges().is_empty():
		return out
	var map_err: int = u.add_port_mapping(local_udp_port, local_udp_port, "HeroShooterGame", "UDP", 0)
	if map_err != UPNP.UPNP_RESULT_SUCCESS:
		return out
	out.ok = true
	out.external_ip = ext
	return out


func _start_enet_host_game() -> void:
	HeroNet.kind = HeroNet.Kind.ENET
	local_requested_username = _sanitize_username_input(username_entry.text if username_entry else "")
	main_menu.hide()
	var err: Error = enet_peer.create_server(PORT)
	if err != OK:
		push_error("ENet create_server failed: %s" % error_string(err))
		main_menu.show()
		hud.hide()
		_set_map_selector_enabled(true)
		return
	match_map_id = _normalize_map_id(_map_id_from_ui())
	_swap_match_environment(match_map_id)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(_enet_host_peer_connected_with_landmine_sync)
	multiplayer.peer_disconnected.connect(remove_player)

	if _is_dedicated_server_process():
		match_rules_actual = false
	else:
		match_rules_actual = _match_rules_actual_from_menu()
	var pre_ms: int = MATCH_PREGAME_SEC * 1000 if match_rules_actual else 0

	if match_rules_actual:
		_prematch_hide_pawns_phase = true
		peer_prematch_pick_revealed.clear()
		if hud != null:
			hud.hide()
	else:
		_prematch_hide_pawns_phase = false
		if hud != null:
			hud.show()

	peer_teams[multiplayer.get_unique_id()] = local_team_id
	peer_heroes[multiplayer.get_unique_id()] = local_hero_id
	peer_usernames[multiplayer.get_unique_id()] = _allocate_unique_username(local_requested_username, multiplayer.get_unique_id())
	add_player(multiplayer.get_unique_id())
	net_apply_username.rpc(multiplayer.get_unique_id(), str(peer_usernames[multiplayer.get_unique_id()]))
	net_apply_match_session.rpc(match_rules_actual, pre_ms)
	_set_map_selector_enabled(false)

	#upnp_setup()


func _on_join_button_pressed() -> void:
	_join_to_address(address_entry.text.strip_edges(), PORT)

func _on_join_local_button_pressed() -> void:
	# Localhost join for another instance on the same machine.
	_join_to_address("127.0.0.1", PORT)

func _join_to_address(ip: String, use_port: int = PORT) -> void:
	if ip.is_empty():
		push_warning("Enter an address to join.")
		return
	_set_map_selector_enabled(false)
	main_menu.hide()
	hud.show()
	local_requested_username = _sanitize_username_input(username_entry.text if username_entry else "")
	var err: Error = enet_peer.create_client(ip.strip_edges(), use_port)
	if err != OK:
		push_error("ENet create_client failed: %s" % error_string(err))
		main_menu.show()
		hud.hide()
		_set_map_selector_enabled(true)
		return
	multiplayer.multiplayer_peer = enet_peer
	HeroNet.kind = HeroNet.Kind.ENET
	multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)

func _on_connected_to_server() -> void:
	# ENet: server is peer_id 1
	request_team.rpc_id(1, local_team_id)
	request_hero.rpc_id(1, local_hero_id)
	request_username.rpc_id(1, local_requested_username)


@rpc("authority", "reliable")
func net_apply_match_map(map_id: String) -> void:
	if HeroNet.is_gdsync():
		return
	var mid: String = _normalize_map_id(map_id)
	if mid == match_map_id and get_node_or_null("Environment") != null:
		return
	_swap_match_environment(mid)


@rpc("authority", "call_local", "reliable")
## [param pregame_remaining_ms] Milliseconds of pre-match lockout remaining from when this RPC is applied (each peer uses local clock).
func net_apply_match_session(actual: bool, pregame_remaining_ms: int) -> void:
	if HeroNet.is_gdsync():
		return
	match_rules_actual = bool(actual)
	if match_rules_actual:
		_match_go_live_at_msec = Time.get_ticks_msec() + maxi(0, int(pregame_remaining_ms))
		_prematch_hide_pawns_phase = true
		peer_prematch_pick_revealed.clear()
		peer_prematch_locked_hero_id.clear()
		_apply_prematch_pawn_visibility_all()
		if hud != null:
			hud.hide()
		if prematch_character_select != null:
			prematch_character_select.begin(self)
	else:
		_match_go_live_at_msec = 0
		_prematch_hide_pawns_phase = false
		if hud != null and not main_menu.visible:
			hud.show()
		if spawn_rooms_volumes_enabled():
			_schedule_spawn_door_open(SPAWN_DOOR_OPEN_DELAY_PRACTICE_MS)


@rpc("authority", "call_local", "reliable")
func net_show_match_end(winner_team_id: int) -> void:
	if HeroNet.is_gdsync():
		return
	_show_match_end_ui_local(int(winner_team_id))


func add_player(peer_id: int) -> void:
	var player: CharacterBody3D = Player.instantiate() as CharacterBody3D
	player.name = str(peer_id)
	if peer_teams.has(peer_id):
		player.team_id = int(peer_teams[peer_id])
	if peer_heroes.has(peer_id):
		player.hero_id = str(peer_heroes[peer_id])
	if peer_usernames.has(peer_id):
		player.player_username = str(peer_usernames[peer_id])
	add_child(player)
	respawn_player(player)
	_apply_prematch_visibility_to_single_player(int(peer_id), player)
	if HeroNet.controls_local_pawn(player):
		player.health_changed.connect(update_health_bar)
		_connect_local_death_signals(player)

func remove_player(peer_id: int) -> void:
	peer_teams.erase(peer_id)
	peer_heroes.erase(peer_id)
	peer_usernames.erase(peer_id)
	peer_prematch_pick_revealed.erase(peer_id)
	peer_prematch_locked_hero_id.erase(peer_id)
	var player: Node = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()


func _enet_host_peer_connected_with_landmine_sync(peer_id: int) -> void:
	if multiplayer.is_server():
		net_apply_match_map.rpc_id(peer_id, match_map_id)
	call_deferred("_enet_host_finish_peer_setup", peer_id)


func _enet_host_finish_peer_setup(peer_id: int) -> void:
	add_player(peer_id)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		var rem_ms: int = 0
		if match_rules_actual:
			rem_ms = maxi(0, _match_go_live_at_msec - Time.get_ticks_msec())
		net_apply_match_session.rpc_id(peer_id, match_rules_actual, rem_ms)
		call_deferred("_landmines_resync_to_peer", peer_id)


func _landmines_resync_to_peer(peer_id: int) -> void:
	var snaps: Array = []
	for n in get_tree().get_nodes_in_group("landmine"):
		if n.has_method("get_network_snapshot"):
			snaps.append(n.get_network_snapshot())
	if snaps.is_empty():
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_on(peer_id, Callable(self, "gdsync_net_apply_landmine_snapshots"), [snaps])
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		net_apply_landmine_snapshots.rpc_id(peer_id, snaps)


func gdsync_net_apply_landmine_snapshots(snaps: Array) -> void:
	_apply_landmine_snapshots_internal(snaps)


@rpc("authority", "reliable")
func net_apply_landmine_snapshots(snaps: Array) -> void:
	_apply_landmine_snapshots_internal(snaps)


func _apply_landmine_snapshots_internal(snaps: Array) -> void:
	for raw in snaps:
		var lm: Node3D = LandmineScene.instantiate() as Node3D
		add_child(lm)
		if lm.has_method("apply_network_snapshot"):
			lm.apply_network_snapshot(raw)


func update_health_bar(health_value: Variant) -> void:
	var p: CharacterBody3D = get_node_or_null(str(HeroNet.my_id())) as CharacterBody3D
	if p != null and p.get("max_health") != null:
		health_bar.max_value = float(p.max_health)
	health_bar.value = float(health_value) if health_value != null else 0.0

func record_damaged_by_me(peer_id: int) -> void:
	recently_damaged_by_me[peer_id] = Time.get_ticks_msec()

func was_damaged_by_me_recently(peer_id: int) -> bool:
	if not recently_damaged_by_me.has(peer_id):
		return false
	var t: int = recently_damaged_by_me[peer_id]
	if Time.get_ticks_msec() - t > DAMAGED_VISIBLE_MS:
		recently_damaged_by_me.erase(peer_id)
		return false
	return true

func _process(delta: float) -> void:
	_update_medic_global_ultimate_heals(delta)
	_update_medic_ult_foot_vfx(delta)
	_process_spawn_door_timer_and_visuals()
	_update_post_prematch_countdown_ui()
	# Prune old entries
	var now: int = Time.get_ticks_msec()
	for pid in recently_damaged_by_me.keys():
		if now - recently_damaged_by_me[pid] > DAMAGED_VISIBLE_MS:
			recently_damaged_by_me.erase(pid)

	# Update death countdown
	if death_overlay and death_overlay.visible:
		var ms_left: int = maxi(respawn_end_ms - Time.get_ticks_msec(), 0)
		var secs_left: int = int(ceil(float(ms_left) / 1000.0))
		if respawn_countdown:
			respawn_countdown.text = "Respawning in %d..." % secs_left

	_update_debug_readout()
	_match_process_return_after_end_screen()
	_matchmaking_update_timer_display()

func _update_debug_readout() -> void:
	if debug_readout == null:
		return
	if _mm_hide_debug_ui_boot:
		debug_readout.visible = false
		if fps_readout != null:
			fps_readout.visible = false
		return
	if main_menu.visible:
		debug_readout.visible = false
		if fps_readout != null:
			fps_readout.visible = false
		return
	debug_readout.visible = true
	if fps_readout != null:
		fps_readout.visible = true
	var pos: Vector3 = Vector3.ZERO
	var p: Node3D = get_node_or_null(str(HeroNet.my_id())) as Node3D
	if p != null:
		pos = p.global_position
	var hero: HeroResource = HeroesRegistry.get_hero(local_hero_id)
	var label: String = hero.display_name if hero else local_hero_id
	debug_readout.text = "X:%.1f Y:%.1f Z:%.1f  |  %s (%s)" % [pos.x, pos.y, pos.z, label, local_hero_id]
	if fps_readout != null:
		var fps: int = Engine.get_frames_per_second()
		fps_readout.text = "FPS: %d" % fps
		var fps_color: Color = Color(0.25, 0.93, 0.38, 0.95) if fps >= 60 else (Color(0.95, 0.62, 0.2, 0.95) if fps >= 29 else Color(0.95, 0.22, 0.22, 0.95))
		fps_readout.add_theme_color_override("font_color", fps_color)


func _update_medic_global_ultimate_heals(delta: float) -> void:
	if not HeroNet.is_host_logic():
		return
	var now: int = Time.get_ticks_msec()
	for tid_raw in _medic_global_ult_end_msec.keys().duplicate():
		var tid: int = int(tid_raw)
		if now >= int(_medic_global_ult_end_msec[tid]):
			_medic_global_ult_end_msec.erase(tid)
			_medic_global_ult_tick_accum.erase(tid)
			_medic_ult_clear_player_carry_for_team(tid)
			continue
		var acc: float = float(_medic_global_ult_tick_accum.get(tid, 0.0)) + delta
		while acc >= MEDIC_GLOBAL_ULT_TICK_SEC:
			acc -= MEDIC_GLOBAL_ULT_TICK_SEC
			_medic_apply_global_ult_heal_tick(tid)
		_medic_global_ult_tick_accum[tid] = acc


func _medic_ult_clear_player_carry_for_team(tid: int) -> void:
	var prefix: String = str(tid) + ":"
	for k in _medic_global_ult_player_carry.keys().duplicate():
		if str(k).begins_with(prefix):
			_medic_global_ult_player_carry.erase(k)


func _medic_apply_global_ult_heal_tick(team_id: int) -> void:
	var tick: float = MEDIC_GLOBAL_ULT_TICK_SEC
	for child in get_children():
		if not (child is CharacterBody3D):
			continue
		if child.get("team_id") == null or int(child.team_id) != team_id:
			continue
		if child.get("is_dead") == true:
			continue
		var peer_id: int = int(str(child.name))
		var ckey: String = "%d:%d" % [team_id, peer_id]
		var max_h: int = int(child.get("max_health")) if child.get("max_health") != null else 250
		var hid: String = str(child.get("hero_id")) if child.get("hero_id") != null else ""
		var raw: float
		if hid == HEALER_MEDIC_HERO_ID:
			raw = MEDIC_GLOBAL_ULT_FLAT_HEAL_PER_SEC * tick
		else:
			raw = MEDIC_GLOBAL_ULT_FLAT_HEAL_PER_SEC * tick + float(max_h) * MEDIC_GLOBAL_ULT_MAX_HP_FRACTION_PER_SEC * tick
		var carry: float = float(_medic_global_ult_player_carry.get(ckey, 0.0)) + raw
		var heal_i: int = int(floor(carry))
		carry -= float(heal_i)
		_medic_global_ult_player_carry[ckey] = carry
		if heal_i > 0:
			HeroNet.apply_heal_on_target(child, heal_i, -1, true)


## Starts / extends the global team heal window for one team (all peers store end time; host applies ticks).
@rpc("any_peer", "call_local", "reliable")
func sync_medic_global_ultimate(team_id: int) -> void:
	var tid: int = clampi(team_id, 0, 1)
	var now: int = Time.get_ticks_msec()
	var end: int = now + int(MEDIC_GLOBAL_ULT_DURATION_SEC * 1000.0)
	var prev: int = int(_medic_global_ult_end_msec.get(tid, 0))
	if end > prev:
		_medic_global_ult_end_msec[tid] = end


func _viewer_team_id() -> int:
	var p: Node = get_node_or_null(str(HeroNet.my_id()))
	if p != null and p.get("team_id") != null:
		return int(p.team_id)
	return local_team_id


func _medic_ult_active_for_team(team_id: int) -> bool:
	return Time.get_ticks_msec() < int(_medic_global_ult_end_msec.get(team_id, 0))


func _tint_medic_ult_foot_vfx(vfx: Node3D, ally_to_viewer: bool) -> void:
	if ally_to_viewer:
		vfx.set("primary_color", MEDIC_ULT_FX_ALLY_PRIMARY)
		vfx.set("secondary_color", MEDIC_ULT_FX_ALLY_SECONDARY)
		vfx.set("tertiary_color", MEDIC_ULT_FX_ALLY_SECONDARY)
		vfx.set("light_color", MEDIC_ULT_FX_ALLY_PRIMARY)
	else:
		vfx.set("primary_color", MEDIC_ULT_FX_ENEMY_PRIMARY)
		vfx.set("secondary_color", MEDIC_ULT_FX_ENEMY_SECONDARY)
		vfx.set("tertiary_color", MEDIC_ULT_FX_ENEMY_SECONDARY)
		vfx.set("light_color", MEDIC_ULT_FX_ENEMY_PRIMARY)


func _update_medic_ult_foot_vfx(_delta: float) -> void:
	if _is_dedicated_server_process():
		return
	if main_menu != null and main_menu.visible:
		_medic_ult_foot_vfx_clear_all()
		return
	var view_team: int = _viewer_team_id()
	var want: Dictionary = {}
	for child in get_children():
		if not (child is CharacterBody3D):
			continue
		var pl: CharacterBody3D = child as CharacterBody3D
		if pl.get("team_id") == null:
			continue
		var tid: int = int(pl.team_id)
		if not _medic_ult_active_for_team(tid):
			continue
		if pl.get("is_dead") == true:
			continue
		var pid: int = int(str(pl.name))
		want[pid] = true
		var vfx: Node3D = _medic_ult_foot_vfx.get(pid) as Node3D
		if vfx == null or not is_instance_valid(vfx):
			vfx = MedicUltFootRippleVfxScene.instantiate() as Node3D
			pl.add_child(vfx)
			_medic_ult_foot_vfx[pid] = vfx
			vfx.set("autoplay", true)
			vfx.set("one_shot", false)
			_tint_medic_ult_foot_vfx(vfx, tid == view_team)
			vfx.position = Vector3(0.0, MEDIC_ULT_FOOT_VFX_Y_OFF, 0.0)
			if vfx.has_method("play"):
				vfx.play()
		else:
			_tint_medic_ult_foot_vfx(vfx, tid == view_team)
			if vfx.get_parent() != pl:
				if vfx.get_parent() != null:
					vfx.get_parent().remove_child(vfx)
				pl.add_child(vfx)
		vfx.position = Vector3(0.0, MEDIC_ULT_FOOT_VFX_Y_OFF, 0.0)
	for k in _medic_ult_foot_vfx.keys().duplicate():
		if want.has(int(k)):
			continue
		var v2: Node3D = _medic_ult_foot_vfx[k] as Node3D
		if v2 != null and is_instance_valid(v2):
			v2.queue_free()
		_medic_ult_foot_vfx.erase(k)


func _medic_ult_foot_vfx_clear_all() -> void:
	for k in _medic_ult_foot_vfx.keys().duplicate():
		var v2: Node3D = _medic_ult_foot_vfx[k] as Node3D
		if v2 != null and is_instance_valid(v2):
			v2.queue_free()
		_medic_ult_foot_vfx.erase(k)


func _on_multiplayer_spawner_spawned(node):
	if HeroNet.controls_local_pawn(node):
		node.health_changed.connect(update_health_bar)
		node.team_id = local_team_id
		node.hero_id = local_hero_id
		node._apply_hero_stats()
		_connect_local_death_signals(node)
		# Position/rotation are owned by this peer's authority — must apply here.
		respawn_player(node)

@rpc("any_peer", "reliable")
func request_team(team_id: int) -> void:
	if HeroNet.is_gdsync():
		return
	# Client tells server which team they picked.
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var requested: int = clampi(team_id, 0, 1)
	peer_teams[sender] = requested
	var player: CharacterBody3D = get_node_or_null(str(sender)) as CharacterBody3D
	if player:
		player.team_id = requested
		respawn_player(player)
	# Tell that client to apply spawn on their authoritative copy.
	client_respawn_at_team_spawn.rpc_id(sender)

@rpc("any_peer", "reliable")
func client_respawn_at_team_spawn() -> void:
	if HeroNet.is_gdsync():
		return
	var me: int = multiplayer.get_unique_id()
	var p: CharacterBody3D = get_node_or_null(str(me)) as CharacterBody3D
	if p != null and p.is_multiplayer_authority():
		respawn_player(p)

@rpc("any_peer", "reliable")
func request_hero(hero_id: String) -> void:
	if HeroNet.is_gdsync():
		return
	if not multiplayer.is_server():
		return
	if HeroesRegistry.get_hero(hero_id) == null:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if match_rules_actual and _enet_team_has_role_conflict(sender, hero_id):
		return
	peer_heroes[sender] = hero_id


func _enet_team_has_role_conflict(sender_id: int, hero_id: String) -> bool:
	var slot: int = HeroesRegistry.hero_role_slot(hero_id)
	if slot < 0:
		return true
	var team_id: int = int(peer_teams.get(sender_id, 0))
	for pid_raw in peer_teams.keys():
		var pid: int = int(pid_raw)
		if pid == sender_id:
			continue
		if int(peer_teams[pid_raw]) != team_id:
			continue
		var other: String = peer_hero_id_for_team_role_slot_conflict(pid)
		if other.is_empty():
			continue
		if HeroesRegistry.hero_role_slot(other) == slot:
			return true
	return false


func gdsync_net_request_prematch_role_lock(client_id: int, hero_id: String) -> void:
	if not GDSync.is_host():
		return
	GDSync.call_func_all(Callable(self, "gdsync_net_apply_prematch_role_lock_everywhere"), [int(client_id), str(hero_id)])


func gdsync_net_apply_prematch_role_lock_everywhere(client_id: int, hero_id: String) -> void:
	var hid: String = str(hero_id).strip_edges()
	if hid.is_empty():
		peer_prematch_locked_hero_id.erase(int(client_id))
		return
	if HeroesRegistry.get_hero(hid) == null:
		return
	peer_prematch_locked_hero_id[int(client_id)] = hid


func request_prematch_role_lock_sync(hero_id: String) -> void:
	if not match_rules_actual:
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_on(GDSync.get_host(), Callable(self, "gdsync_net_request_prematch_role_lock"), [HeroNet.my_id(), hero_id])
	elif HeroNet.kind == HeroNet.Kind.ENET and multiplayer.multiplayer_peer != null:
		if multiplayer.is_server():
			net_apply_prematch_role_lock.rpc(multiplayer.get_unique_id(), hero_id)
		else:
			net_request_prematch_role_lock.rpc_id(1, hero_id)


@rpc("any_peer", "reliable")
func net_request_prematch_role_lock(hero_id: String) -> void:
	if HeroNet.is_gdsync():
		return
	if not multiplayer.is_server():
		return
	if not match_rules_actual:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	net_apply_prematch_role_lock.rpc(sender, hero_id)


@rpc("authority", "call_local", "reliable")
func net_apply_prematch_role_lock(peer_id: int, hero_id: String) -> void:
	if HeroNet.is_gdsync():
		return
	gdsync_net_apply_prematch_role_lock_everywhere(int(peer_id), str(hero_id))

@rpc("any_peer", "reliable")
func request_username(requested_username: String) -> void:
	if HeroNet.is_gdsync():
		return
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var resolved: String = _allocate_unique_username(requested_username, sender)
	net_apply_username.rpc(sender, resolved)


@rpc("authority", "call_local", "reliable")
func net_apply_username(peer_id: int, username: String) -> void:
	if HeroNet.is_gdsync():
		return
	peer_usernames[peer_id] = username
	var player: CharacterBody3D = get_node_or_null(str(peer_id)) as CharacterBody3D
	if player:
		player.player_username = username
	if HeroNet.my_id() == peer_id:
		local_requested_username = username
		if username_entry:
			username_entry.text = username


@rpc("any_peer", "reliable")
func net_request_prematch_pick_revealed(revealed: bool) -> void:
	if HeroNet.is_gdsync():
		return
	if not multiplayer.is_server():
		return
	if not match_rules_actual:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	net_apply_prematch_pick_revealed.rpc(sender, revealed)


@rpc("authority", "call_local", "reliable")
func net_apply_prematch_pick_revealed(peer_id: int, revealed: bool) -> void:
	if HeroNet.is_gdsync():
		return
	_apply_prematch_pick_revealed_core(int(peer_id), bool(revealed))


func _sanitize_username_input(raw: String) -> String:
	var s: String = raw.strip_edges()
	if s.length() > 20:
		s = s.substr(0, 20)
	return s


func _username_taken(candidate: String, exclude_peer_id: int = -1) -> bool:
	var needle: String = candidate.to_lower()
	for pid in peer_usernames.keys():
		if int(pid) == exclude_peer_id:
			continue
		if str(peer_usernames[pid]).to_lower() == needle:
			return true
	return false


func _allocate_unique_username(requested_raw: String, peer_id: int) -> String:
	var requested: String = _sanitize_username_input(requested_raw)
	if requested.is_empty():
		var player_index: int = 1
		var candidate_player: String = "Player%d" % player_index
		while _username_taken(candidate_player, peer_id):
			player_index += 1
			candidate_player = "Player%d" % player_index
		return candidate_player
	if not _username_taken(requested, peer_id):
		return requested
	var i: int = 1
	var candidate: String = "%s%d" % [requested, i]
	while _username_taken(candidate, peer_id):
		i += 1
		candidate = "%s%d" % [requested, i]
	return candidate

func _connect_local_death_signals(player: Node) -> void:
	if not player:
		return
	if player.player_died.is_connected(_on_local_player_died) == false:
		player.player_died.connect(_on_local_player_died)
	if player.player_respawned.is_connected(_on_local_player_respawned) == false:
		player.player_respawned.connect(_on_local_player_respawned)

func _on_local_player_died() -> void:
	# Hide HUD (includes health bar) and show overlay
	if hud:
		hud.hide()
	if death_overlay:
		death_overlay.show()
	# 5 second respawn timer (matches Player.RESPAWN_DELAY)
	respawn_end_ms = Time.get_ticks_msec() + 5000

func _on_local_player_respawned() -> void:
	if death_overlay:
		death_overlay.hide()
	if hud:
		hud.show()


func _team_spawn_center(team_id: int) -> Vector3:
	if match_map_id == MAP_ID_MAP2:
		return MAP2_TEAM_A_SPAWN_CENTER if team_id == 0 else MAP2_TEAM_B_SPAWN_CENTER
	if match_map_id == MAP_ID_MAP3:
		return MAP3_TEAM_A_SPAWN_CENTER if team_id == 0 else MAP3_TEAM_B_SPAWN_CENTER
	if match_map_id == MAP_ID_MAP4:
		return MAP4_TEAM_A_SPAWN_CENTER if team_id == 0 else MAP4_TEAM_B_SPAWN_CENTER
	if match_map_id == MAP_ID_MAP5:
		return MAP5_TEAM_A_SPAWN_CENTER if team_id == 0 else MAP5_TEAM_B_SPAWN_CENTER
	return TEAM_A_SPAWN_CENTER if team_id == 0 else TEAM_B_SPAWN_CENTER


## Map 2 uses different layout; spawn-room AABBs are authored for the ±90 arena maps.
func spawn_rooms_volumes_enabled() -> bool:
	return match_map_id != MAP_ID_MAP2


func is_position_in_team_spawn_room(pos: Vector3, team_id: int) -> bool:
	if not spawn_rooms_volumes_enabled():
		return false
	var tid: int = clampi(team_id, 0, 1)
	var x0: float
	var x1: float
	if tid == 0:
		x0 = SPAWN_ROOM_TEAM_A_X_MIN
		x1 = SPAWN_ROOM_TEAM_A_X_MAX
	else:
		x0 = SPAWN_ROOM_TEAM_B_X_MIN
		x1 = SPAWN_ROOM_TEAM_B_X_MAX
	return pos.x >= x0 and pos.x <= x1 and pos.z >= SPAWN_ROOM_Z_MIN and pos.z <= SPAWN_ROOM_Z_MAX and pos.y >= SPAWN_ROOM_Y_MIN and pos.y <= SPAWN_ROOM_Y_MAX


func is_player_in_own_spawn_room(player: Node3D) -> bool:
	if player == null or not spawn_rooms_volumes_enabled():
		return false
	var tv: Variant = player.get("team_id")
	if typeof(tv) != TYPE_INT:
		return false
	var tid: int = clampi(int(tv), 0, 1)
	return is_position_in_team_spawn_room(player.global_position, tid)


func _remove_spawn_door_walls_if_any() -> void:
	_spawn_door_hide_at_msec = -1
	if _spawn_doors_root != null and is_instance_valid(_spawn_doors_root):
		_spawn_doors_root.queue_free()
	_spawn_doors_root = null
	_spawn_door_mesh_team0 = null
	_spawn_door_mesh_team1 = null


func _schedule_spawn_door_open(delay_ms: int) -> void:
	if not spawn_rooms_volumes_enabled():
		return
	if _spawn_doors_root == null or not is_instance_valid(_spawn_doors_root):
		return
	_spawn_door_hide_at_msec = Time.get_ticks_msec() + maxi(0, delay_ms)


func _process_spawn_door_timer_and_visuals() -> void:
	if _spawn_door_hide_at_msec >= 0 and Time.get_ticks_msec() >= _spawn_door_hide_at_msec:
		_spawn_door_hide_at_msec = -1
		_remove_spawn_door_walls_if_any()
	if _spawn_doors_root != null and is_instance_valid(_spawn_doors_root):
		_update_spawn_door_wall_colors()


func _update_spawn_door_wall_colors() -> void:
	if _spawn_door_mesh_team0 == null or _spawn_door_mesh_team1 == null:
		return
	var own0: bool = local_team_id == 0
	var mat0 := _spawn_door_mesh_team0.get_surface_override_material(0) as StandardMaterial3D
	if mat0 != null:
		mat0.albedo_color = Color(0.22, 0.62, 1.0, 0.42) if own0 else Color(1.0, 0.22, 0.2, 0.42)
	var own1: bool = local_team_id == 1
	var mat1 := _spawn_door_mesh_team1.get_surface_override_material(0) as StandardMaterial3D
	if mat1 != null:
		mat1.albedo_color = Color(0.22, 0.62, 1.0, 0.42) if own1 else Color(1.0, 0.22, 0.2, 0.42)


func _build_spawn_door_wall(center: Vector3, half_extents: Vector3, wall_team: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "SpawnDoorWallTeam%d" % wall_team
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = half_extents * 2.0
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.metallic = 0.0
	mat.roughness = 0.45
	mat.albedo_color = Color(0.5, 0.5, 1.0, 0.4)
	mi.set_surface_override_material(0, mat)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = half_extents * 2.0
	col.shape = shape
	body.add_child(col)
	return body


func _ensure_spawn_door_walls() -> void:
	_remove_spawn_door_walls_if_any()
	if not spawn_rooms_volumes_enabled():
		return
	var root := Node3D.new()
	root.name = "SpawnDoors"
	add_child(root)
	var env_node: Node = get_node_or_null("Environment")
	if env_node != null:
		move_child(root, mini(env_node.get_index() + 1, get_child_count() - 1))
	var hx: float = (SPAWN_DOOR_TEAM_A_X1 - SPAWN_DOOR_TEAM_A_X0) * 0.5
	var hy: float = (SPAWN_DOOR_Y_MAX - SPAWN_DOOR_Y_MIN) * 0.5
	var hz: float = (SPAWN_DOOR_Z_MAX - SPAWN_DOOR_Z_MIN) * 0.5
	var cx_a: float = (SPAWN_DOOR_TEAM_A_X0 + SPAWN_DOOR_TEAM_A_X1) * 0.5
	var cx_b: float = (SPAWN_DOOR_TEAM_B_X0 + SPAWN_DOOR_TEAM_B_X1) * 0.5
	var cy: float = (SPAWN_DOOR_Y_MIN + SPAWN_DOOR_Y_MAX) * 0.5
	var cz: float = (SPAWN_DOOR_Z_MIN + SPAWN_DOOR_Z_MAX) * 0.5
	var half := Vector3(hx, hy, hz)
	var b0 := _build_spawn_door_wall(Vector3(cx_a, cy, cz), half, 0)
	var b1 := _build_spawn_door_wall(Vector3(cx_b, cy, cz), half, 1)
	root.add_child(b0)
	root.add_child(b1)
	_spawn_doors_root = root
	_spawn_door_mesh_team0 = b0.get_child(0) as MeshInstance3D
	_spawn_door_mesh_team1 = b1.get_child(0) as MeshInstance3D


func _spawn_lane_offset_for_slot(slot_index: int) -> Vector3:
	if slot_index <= 0:
		return Vector3.ZERO
	match slot_index:
		1:
			return Vector3(0, 0, TEAM_SPAWN_MATE_Z_OFFSET)
		2:
			return Vector3(0, 0, -TEAM_SPAWN_MATE_Z_OFFSET)
		_:
			var e: int = slot_index - 3
			var col: int = e / 2
			var x_shift: float = float(col + 1) * TEAM_SPAWN_X_STEP
			var z_off: float = TEAM_SPAWN_MATE_Z_OFFSET if (e % 2) == 0 else -TEAM_SPAWN_MATE_Z_OFFSET
			return Vector3(x_shift, 0, z_off)


func _spawn_position_for_peer(peer_id: int, team_id: int) -> Vector3:
	var center: Vector3 = _team_spawn_center(team_id)
	var team_peers: Array[int] = []
	for pid_raw: Variant in peer_teams.keys():
		var pid: int = int(pid_raw)
		if int(peer_teams[pid_raw]) == team_id:
			team_peers.append(pid)
	if peer_id > 0 and not team_peers.has(peer_id):
		team_peers.append(peer_id)
	for child in get_children():
		if not (child is CharacterBody3D):
			continue
		var nm: String = str(child.name)
		if not nm.is_valid_int():
			continue
		var opid: int = int(nm)
		if opid <= 0:
			continue
		if child.get("team_id") == null:
			continue
		if int(child.team_id) != team_id:
			continue
		if not team_peers.has(opid):
			team_peers.append(opid)
	if team_peers.is_empty():
		return center
	team_peers.sort()
	var slot_index: int = maxi(team_peers.find(peer_id), 0)
	return center + _spawn_lane_offset_for_slot(slot_index)


func respawn_player(player: Node3D) -> void:
	if not player:
		return
	var team_id: int = clampi(int(player.team_id), 0, 1)
	var pid: int = -1
	var pid_text: String = str(player.name)
	if pid_text.is_valid_int():
		pid = int(pid_text)
	player.position = _spawn_position_for_peer(pid, team_id)
	if team_id == 0:
		player.rotation.y = TEAM_A_YAW
	else:
		player.rotation.y = TEAM_B_YAW


func spawn_smoke_bomb_at(origin: Vector3, velocity: Vector3, shooter_peer_id: int) -> void:
	var sb: Node3D = SmokeBombScene.instantiate() as Node3D
	add_child(sb)
	var fwd: Vector3 = velocity.normalized()
	if fwd.length_squared() < 1e-12:
		fwd = Vector3(0.0, 0.0, -1.0)
	sb.global_position = origin + fwd * 0.38
	if sb.has_method("setup"):
		sb.setup(shooter_peer_id, velocity)


func spawn_tank_explosion_vfx_at(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_spawn_tank_binbun_explosion_at(pos, normal)

func spawn_tank_secondary_explosion_vfx_at(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_spawn_tank_secondary_explosion_binbun_at(pos, normal)

func spawn_tank_landmine_impact_vfx_at(pos: Vector3, normal: Vector3 = Vector3.UP, uniform_scale: float = 0.5) -> void:
	_spawn_tank_landmine_impact_binbun_at(pos, normal, uniform_scale)

func spawn_player_death_explosion_vfx_at(pos: Vector3, normal: Vector3 = Vector3.UP, victim_peer_id: int = -1) -> void:
	_spawn_player_death_explosion_binbun_at(pos, normal, victim_peer_id)

## One RPC for all peers (call_local) so explosive tank VFX is not spawned once per simulating client.
@rpc("any_peer", "call_local", "reliable")
func sync_tank_explosion_vfx(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_spawn_tank_binbun_explosion_at(pos, normal)

## Secondary (right-click) knockback shell — `vfx_explosion_05`.
@rpc("any_peer", "call_local", "reliable")
func sync_tank_secondary_explosion_vfx(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_spawn_tank_secondary_explosion_binbun_at(pos, normal)

## Landmine detonation — `vfx_impact_02` (typically half scale).
@rpc("any_peer", "call_local", "reliable")
func sync_tank_landmine_impact_vfx(pos: Vector3, normal: Vector3 = Vector3.UP, uniform_scale: float = 0.5) -> void:
	_spawn_tank_landmine_impact_binbun_at(pos, normal, uniform_scale)

## Global: any player death — `vfx_explosion_01` at torso height.
@rpc("any_peer", "call_local", "reliable")
func sync_player_death_explosion_vfx(pos: Vector3, normal: Vector3 = Vector3.UP, victim_peer_id: int = -1) -> void:
	_spawn_player_death_explosion_binbun_at(pos, normal, victim_peer_id)

func _spawn_tank_binbun_explosion_at(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_play_explosion_sound_3d(
		pos,
		Explosion1Sfx,
		GameSettings.slider_to_db(GameSettings.explosion_1_volume_slider) + EXPLOSION1_MAX_DB,
		EXPLOSION1_SFX_MAX_DISTANCE,
		EXPLOSION1_SFX_UNIT_SIZE
	)
	if _should_cull_vfx_behind_view(pos):
		return
	var vfx: Node3D = TankExplosionVfxScene.instantiate() as Node3D
	vfx.autoplay = false
	vfx.one_shot = true
	add_child(vfx)
	vfx.global_position = pos
	vfx.global_basis = _basis_with_up(normal)
	_disable_vfx_lights(vfx)
	if vfx.has_method("play"):
		vfx.play()
	get_tree().create_timer(TANK_EXPLOSION_VFX_CLEANUP_SEC).timeout.connect(func () -> void:
		if is_instance_valid(vfx):
			vfx.queue_free()
	)


func _spawn_tank_secondary_explosion_binbun_at(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	if _should_cull_vfx_behind_view(pos):
		return
	const SECONDARY_SHELL_VFX_SCALE := 2.6
	var vfx: Node3D = TankSecondaryExplosionVfxScene.instantiate() as Node3D
	vfx.autoplay = false
	vfx.one_shot = true
	add_child(vfx)
	vfx.global_position = pos
	vfx.global_basis = _basis_with_up(normal)
	vfx.scale = Vector3.ONE * SECONDARY_SHELL_VFX_SCALE
	_disable_vfx_lights(vfx)
	if vfx.has_method("play"):
		vfx.play()
	get_tree().create_timer(TANK_SECONDARY_EXPLOSION_VFX_CLEANUP_SEC).timeout.connect(func () -> void:
		if is_instance_valid(vfx):
			vfx.queue_free()
	)


func _spawn_tank_landmine_impact_binbun_at(pos: Vector3, normal: Vector3 = Vector3.UP, uniform_scale: float = 0.5) -> void:
	_play_explosion_sound_3d(
		pos,
		Explosion1Sfx,
		GameSettings.slider_to_db(GameSettings.explosion_1_volume_slider) + EXPLOSION1_MAX_DB,
		EXPLOSION1_SFX_MAX_DISTANCE,
		EXPLOSION1_SFX_UNIT_SIZE
	)
	if _should_cull_vfx_behind_view(pos):
		return
	var vfx: Node3D = TankLandmineImpactVfxScene.instantiate() as Node3D
	vfx.autoplay = false
	vfx.one_shot = true
	add_child(vfx)
	vfx.global_position = pos
	vfx.global_basis = _basis_with_up(normal)
	vfx.scale = Vector3.ONE * uniform_scale
	_reduce_heavy_vfx_lights(vfx)
	if vfx.has_method("play"):
		vfx.play()
	get_tree().create_timer(TANK_LANDMINE_IMPACT_VFX_CLEANUP_SEC).timeout.connect(func () -> void:
		if is_instance_valid(vfx):
			vfx.queue_free()
	)


func _spawn_player_death_explosion_binbun_at(pos: Vector3, normal: Vector3 = Vector3.UP, victim_peer_id: int = -1) -> void:
	var vol_db: float = GameSettings.slider_to_db(GameSettings.explosion_4_volume_slider)
	if victim_peer_id > 0 and victim_peer_id == HeroNet.my_id():
		vol_db += EXPLOSION_DEATH_SELF_QUIET_DB
	_play_explosion_sound_3d(pos, Explosion4Sfx, vol_db)
	if _should_cull_vfx_behind_view(pos):
		return
	var vfx: Node3D = PlayerDeathExplosionVfxScene.instantiate() as Node3D
	vfx.autoplay = false
	vfx.one_shot = true
	add_child(vfx)
	vfx.global_position = pos
	vfx.global_basis = _basis_with_up(normal)
	_disable_vfx_lights(vfx)
	if vfx.has_method("play"):
		vfx.play()
	get_tree().create_timer(PLAYER_DEATH_EXPLOSION_VFX_CLEANUP_SEC).timeout.connect(func () -> void:
		if is_instance_valid(vfx):
			vfx.queue_free()
	)

func spawn_medic_burst_impact_vfx_at(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_spawn_medic_burst_impact_vfx_at(pos, normal)

## One RPC for all peers (call_local) so medic burst impact VFX does not double-spawn.
@rpc("any_peer", "call_local", "reliable")
func sync_medic_burst_impact_vfx(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_spawn_medic_burst_impact_vfx_at(pos, normal)

func _spawn_medic_burst_impact_vfx_at(pos: Vector3, normal: Vector3 = Vector3.UP) -> void:
	if _should_cull_vfx_behind_view(pos):
		return
	var vfx: Node3D = MedicBurstImpactVfxScene.instantiate() as Node3D
	vfx.set("autoplay", false)
	vfx.set("one_shot", true)
	vfx.set("primary_color", MEDIC_BURST_PRIMARY)
	vfx.set("secondary_color", MEDIC_BURST_SECONDARY)
	vfx.set("tertiary_color", MEDIC_BURST_TERTIARY)
	vfx.set("light_color", MEDIC_BURST_PRIMARY)
	add_child(vfx)
	vfx.global_position = pos
	vfx.global_basis = _basis_with_up(normal)
	_force_tint_recursive(vfx)
	_reduce_heavy_vfx_lights(vfx)
	if vfx.has_method("play"):
		vfx.play()
	get_tree().create_timer(MEDIC_BURST_IMPACT_VFX_CLEANUP_SEC).timeout.connect(func () -> void:
		if is_instance_valid(vfx):
			vfx.queue_free()
	)

func _force_tint_recursive(root: Node) -> void:
	for c in root.get_children():
		_force_tint_recursive(c)
	if root is OmniLight3D:
		(root as OmniLight3D).light_color = MEDIC_BURST_PRIMARY
		return
	if root is MeshInstance3D:
		var mi: MeshInstance3D = root as MeshInstance3D
		var mat: Material = mi.material_override
		if mat is StandardMaterial3D:
			var sm: StandardMaterial3D = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			sm.albedo_color = MEDIC_BURST_PRIMARY
			sm.emission_enabled = true
			sm.emission = MEDIC_BURST_PRIMARY
			mi.material_override = sm
		elif mat is ShaderMaterial:
			var sh: ShaderMaterial = (mat as ShaderMaterial).duplicate() as ShaderMaterial
			if sh.get_shader_parameter("primary_color") != null:
				sh.set_shader_parameter("primary_color", MEDIC_BURST_PRIMARY)
			if sh.get_shader_parameter("secondary_color") != null:
				sh.set_shader_parameter("secondary_color", MEDIC_BURST_SECONDARY)
			if sh.get_shader_parameter("tertiary_color") != null:
				sh.set_shader_parameter("tertiary_color", MEDIC_BURST_TERTIARY)
			mi.material_override = sh
		return
	if root is GPUParticles3D:
		var gp: GPUParticles3D = root as GPUParticles3D
		var pmat: Material = gp.material_override
		if pmat is ShaderMaterial:
			var psh: ShaderMaterial = (pmat as ShaderMaterial).duplicate() as ShaderMaterial
			if psh.get_shader_parameter("primary_color") != null:
				psh.set_shader_parameter("primary_color", MEDIC_BURST_PRIMARY)
			if psh.get_shader_parameter("secondary_color") != null:
				psh.set_shader_parameter("secondary_color", MEDIC_BURST_SECONDARY)
			if psh.get_shader_parameter("tertiary_color") != null:
				psh.set_shader_parameter("tertiary_color", MEDIC_BURST_TERTIARY)
			gp.material_override = psh


func _reduce_heavy_vfx_lights(root: Node, enabled_light_count: int = 0) -> int:
	for c in root.get_children():
		enabled_light_count = _reduce_heavy_vfx_lights(c, enabled_light_count)
	if root is Light3D:
		var l := root as Light3D
		if enabled_light_count >= HEAVY_VFX_MAX_LIGHTS_PER_EFFECT:
			l.visible = false
			l.light_energy = 0.0
			l.shadow_enabled = false
			return enabled_light_count
		enabled_light_count += 1
		l.light_energy *= HEAVY_VFX_LIGHT_ENERGY_MULT
		l.light_specular = minf(l.light_specular, HEAVY_VFX_LIGHT_SPECULAR_MAX)
		l.shadow_enabled = false
		if l is OmniLight3D:
			var omni := l as OmniLight3D
			omni.omni_range *= HEAVY_VFX_LIGHT_RANGE_MULT
		elif l is SpotLight3D:
			var spot := l as SpotLight3D
			spot.spot_range *= HEAVY_VFX_LIGHT_RANGE_MULT
	return enabled_light_count


func _disable_vfx_lights(root: Node) -> void:
	for c in root.get_children():
		_disable_vfx_lights(c)
	if root is Light3D:
		var l := root as Light3D
		l.visible = false
		l.light_energy = 0.0
		l.shadow_enabled = false


func _should_cull_vfx_behind_view(pos: Vector3) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return false
	var to_vfx: Vector3 = pos - cam.global_position
	var dist_sq: float = to_vfx.length_squared()
	if dist_sq <= VFX_BEHIND_CAMERA_CULL_MIN_DISTANCE * VFX_BEHIND_CAMERA_CULL_MIN_DISTANCE:
		return false
	if dist_sq < 1e-8:
		return false
	var view_fwd: Vector3 = (-cam.global_basis.z).normalized()
	var dot: float = view_fwd.dot(to_vfx.normalized())
	return dot <= VFX_BEHIND_CAMERA_CULL_DOT

func _match_rules_actual_from_menu() -> bool:
	if match_mode_actual_check == null:
		return false
	return match_mode_actual_check.button_pressed


func _host_begin_match_timing_gdsync() -> void:
	if not GDSync.is_host():
		return
	var pre_ms: int = MATCH_PREGAME_SEC * 1000 if match_rules_actual else 0
	if match_rules_actual:
		_match_go_live_at_msec = Time.get_ticks_msec() + pre_ms
	else:
		_match_go_live_at_msec = 0
	GDSync.call_func_all(Callable(_hero_mm_bridge, "gdsync_mm_bridge_apply_match_session"), [match_rules_actual, pre_ms])


func gdsync_apply_match_session(actual: bool, pregame_remaining_ms: int) -> void:
	_mm_pregame_local_waiting = false
	match_rules_actual = bool(actual)
	if match_rules_actual:
		_match_go_live_at_msec = Time.get_ticks_msec() + maxi(0, int(pregame_remaining_ms))
		_prematch_hide_pawns_phase = true
		peer_prematch_pick_revealed.clear()
		peer_prematch_locked_hero_id.clear()
		_apply_prematch_pawn_visibility_all()
		if hud != null:
			hud.hide()
		if prematch_character_select != null:
			prematch_character_select.begin(self)
	else:
		_match_go_live_at_msec = 0
		_prematch_hide_pawns_phase = false
		if spawn_rooms_volumes_enabled():
			_schedule_spawn_door_open(SPAWN_DOOR_OPEN_DELAY_PRACTICE_MS)


func on_prematch_overlay_closed() -> void:
	_prematch_hide_pawns_phase = false
	peer_prematch_pick_revealed.clear()
	peer_prematch_locked_hero_id.clear()
	for c in get_children():
		if c is CharacterBody3D:
			(c as Node3D).visible = true
	_orient_all_players_yaw_toward_capture()
	if hud != null and not main_menu.visible:
		hud.show()
	if spawn_rooms_volumes_enabled() and match_rules_actual:
		_schedule_spawn_door_open(SPAWN_DOOR_OPEN_DELAY_ACTUAL_MS)
	if match_rules_actual:
		_start_post_prematch_countdown_ui()


func _ensure_post_prematch_countdown_label() -> void:
	if _post_prematch_countdown_label != null and is_instance_valid(_post_prematch_countdown_label):
		if _post_prematch_countdown_label is RichTextLabel:
			return
		_post_prematch_countdown_label.queue_free()
		_post_prematch_countdown_label = null
	if hud == null:
		return
	var rtl := RichTextLabel.new()
	rtl.name = "PostPrematchCountdown"
	rtl.visible = false
	rtl.bbcode_enabled = true
	rtl.scroll_active = false
	rtl.fit_content = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rtl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rtl.add_theme_font_size_override("normal_font_size", 52)
	rtl.add_theme_color_override("default_color", Color(0.92, 0.94, 1.0, 0.95))
	rtl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.88))
	rtl.add_theme_constant_override("outline_size", 5)
	hud.add_child(rtl)
	rtl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	rtl.offset_top = 72.0
	rtl.offset_bottom = 168.0
	_post_prematch_countdown_label = rtl


func _ensure_post_prematch_tick_player() -> void:
	if _post_prematch_tick_player != null and is_instance_valid(_post_prematch_tick_player):
		return
	var tick_st: AudioStream = _post_prematch_tick_stream_load()
	if tick_st == null:
		return
	var parent_c: Node = hud.get_parent() if hud != null else self
	var ap := AudioStreamPlayer.new()
	ap.name = "PostPrematchTickSfx"
	ap.stream = tick_st
	ap.bus = "Master"
	ap.volume_db = -8.0
	parent_c.add_child(ap)
	_post_prematch_tick_player = ap


func _post_prematch_tick_stream_load() -> AudioStream:
	if _post_prematch_tick_stream_load_attempted:
		return _post_prematch_tick_stream
	_post_prematch_tick_stream_load_attempted = true
	var r: Resource = ResourceLoader.load(POST_PREMATCH_TICK_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	_post_prematch_tick_stream = r as AudioStream
	if _post_prematch_tick_stream == null:
		push_warning("HeroWorld: could not load %s (open this project in the Godot editor to re-import audio)." % POST_PREMATCH_TICK_PATH)
	return _post_prematch_tick_stream


func _play_post_prematch_tick_sound(seconds_marker: int) -> void:
	_ensure_post_prematch_tick_player()
	if _post_prematch_tick_player == null:
		return
	## 3 → 2 → 1: pitch rises each beep.
	var step: int = clampi(4 - seconds_marker, 1, 3)
	_post_prematch_tick_player.pitch_scale = 0.92 + float(step - 1) * 0.16
	_post_prematch_tick_player.play()


func _start_post_prematch_countdown_ui() -> void:
	_ensure_post_prematch_countdown_label()
	_post_prematch_countdown_end_msec = Time.get_ticks_msec() + POST_PREMATCH_COUNTDOWN_SEC * 1000
	_post_prematch_prev_secs_left = -1
	if _post_prematch_countdown_label != null:
		_post_prematch_countdown_label.visible = true


func _reset_post_prematch_countdown_ui() -> void:
	_post_prematch_countdown_end_msec = -1
	_post_prematch_prev_secs_left = -1
	if _post_prematch_countdown_label != null and is_instance_valid(_post_prematch_countdown_label):
		_post_prematch_countdown_label.visible = false


func _update_post_prematch_countdown_ui() -> void:
	if _post_prematch_countdown_end_msec < 0:
		return
	if _post_prematch_countdown_label == null or not is_instance_valid(_post_prematch_countdown_label):
		return
	var now_c: int = Time.get_ticks_msec()
	if now_c >= _post_prematch_countdown_end_msec:
		_reset_post_prematch_countdown_ui()
		return
	var secs_left: int = maxi(1, ceili(float(_post_prematch_countdown_end_msec - now_c) / 1000.0))
	var prev_sl: int = _post_prematch_prev_secs_left
	_post_prematch_prev_secs_left = secs_left
	if secs_left <= 3 and secs_left >= 1 and prev_sl != secs_left and (prev_sl > secs_left or prev_sl < 0):
		_play_post_prematch_tick_sound(secs_left)
	if secs_left <= 5:
		_post_prematch_countdown_label.text = (
			"[center][font_size=46]Match starts in [/font_size][font_size=96]%d[/font_size][font_size=46]…[/font_size][/center]" % secs_left
		)
	else:
		_post_prematch_countdown_label.text = (
			"[center][font_size=56]Match starts in %d…[/font_size][/center]" % secs_left
		)


func _orient_all_players_yaw_toward_capture() -> void:
	if capture_point == null:
		for c in get_children():
			if c is CharacterBody3D:
				var p0: CharacterBody3D = c as CharacterBody3D
				var t0: int = clampi(int(p0.team_id), 0, 1)
				p0.rotation.y = TEAM_A_YAW if t0 == 0 else TEAM_B_YAW
		return
	var cp: Vector3 = capture_point.global_position
	for c in get_children():
		if c is CharacterBody3D:
			var p: CharacterBody3D = c as CharacterBody3D
			var pos: Vector3 = p.global_position
			var target: Vector3 = Vector3(cp.x, pos.y, cp.z)
			var to_pt: Vector3 = target - pos
			to_pt.y = 0.0
			if to_pt.length_squared() < 1e-6:
				var tid: int = clampi(int(p.team_id), 0, 1)
				p.rotation.y = TEAM_A_YAW if tid == 0 else TEAM_B_YAW
				continue
			p.look_at(target, Vector3.UP)
			p.rotation.x = 0.0
			p.rotation.z = 0.0


func _apply_prematch_pawn_visibility_all() -> void:
	for c in get_children():
		if c is CharacterBody3D:
			var pid: int = int(str(c.name))
			(c as Node3D).visible = (not _prematch_hide_pawns_phase) or bool(peer_prematch_pick_revealed.get(pid, false))


func _apply_prematch_visibility_to_single_player(peer_id: int, player: CharacterBody3D) -> void:
	if _prematch_hide_pawns_phase:
		player.visible = bool(peer_prematch_pick_revealed.get(peer_id, false))
	else:
		player.visible = true


func request_prematch_pick_visibility(revealed: bool) -> void:
	if not match_rules_actual:
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_on(GDSync.get_host(), Callable(_hero_mm_bridge, "gdsync_mm_bridge_request_prematch_pick_revealed"), [HeroNet.my_id(), revealed])
	elif HeroNet.kind == HeroNet.Kind.ENET and multiplayer.multiplayer_peer != null:
		net_request_prematch_pick_revealed.rpc_id(1, revealed)


func gdsync_net_set_prematch_pick_revealed(peer_id: int, revealed: bool) -> void:
	_apply_prematch_pick_revealed_core(int(peer_id), bool(revealed))


func _apply_prematch_pick_revealed_core(peer_id: int, revealed: bool) -> void:
	if not match_rules_actual:
		return
	if revealed:
		peer_prematch_pick_revealed[peer_id] = true
	else:
		peer_prematch_pick_revealed.erase(peer_id)
	if not _prematch_hide_pawns_phase:
		return
	var p: Node3D = get_node_or_null(str(peer_id)) as Node3D
	if p != null:
		p.visible = revealed


func gdsync_show_match_end(winner_team_id: int) -> void:
	_show_match_end_ui_local(int(winner_team_id))


func is_match_input_locked() -> bool:
	if main_menu != null and main_menu.visible:
		return false
	if _is_pause_menu_open():
		return true
	if _mm_pregame_local_waiting:
		return true
	if _match_pending_return_to_menu and Time.get_ticks_msec() <= _match_end_screen_until_msec:
		return true
	if not match_rules_actual:
		return false
	return Time.get_ticks_msec() < _match_go_live_at_msec


func _is_pause_menu_open() -> bool:
	return pause_menu != null and pause_menu.visible


func _set_pause_menu_open(opened: bool) -> void:
	if pause_menu == null:
		return
	if opened and main_menu != null and main_menu.visible:
		return
	pause_menu.visible = opened
	if opened:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	_restore_mouse_mode_after_pause_close()


func _restore_mouse_mode_after_pause_close() -> void:
	if main_menu != null and main_menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if death_overlay != null and death_overlay.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if match_result_overlay != null and match_result_overlay.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if is_character_select_open():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var p: CharacterBody3D = get_node_or_null(str(HeroNet.my_id())) as CharacterBody3D
	if p != null and HeroNet.controls_local_pawn(p) and p.get("is_dead") != true:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_pause_resume_button_pressed() -> void:
	_set_pause_menu_open(false)


func _on_pause_respawn_button_pressed() -> void:
	_set_pause_menu_open(false)
	var p: CharacterBody3D = get_node_or_null(str(HeroNet.my_id())) as CharacterBody3D
	if p == null or not HeroNet.controls_local_pawn(p):
		return
	if p.get("is_dead") == true:
		return
	var max_hp: int = int(p.get("max_health")) if p.get("max_health") != null else 250
	p.receive_damage(max_hp + 9999, -1)
	if hud != null and hud.has_method("push_feed_line"):
		hud.push_feed_line("Player respawned")


func _on_pause_main_menu_button_pressed() -> void:
	if hud != null and hud.has_method("push_feed_line"):
		hud.push_feed_line("Player disconnected")
	_set_pause_menu_open(false)
	_on_return_to_main_menu_button_pressed()


func _init_pause_audio_controls() -> void:
	_pause_audio_bus_by_key.clear()
	_pause_audio_bus_by_key["master"] = _find_audio_bus_index(["Master"])
	_pause_audio_bus_by_key["sfx"] = _find_audio_bus_index(["SFX", "Sfx", "Effects"])
	_pause_audio_bus_by_key["voice"] = _find_audio_bus_index(["VO", "Voice", "Voices"])
	_pause_audio_bus_by_key["music"] = _find_audio_bus_index(["Music"])
	_setup_pause_slider(pause_master_slider, "master", Callable(self, "_on_pause_master_slider_value_changed"))
	_setup_pause_slider(pause_sfx_slider, "sfx", Callable(self, "_on_pause_sfx_slider_value_changed"))
	_setup_pause_slider(pause_voice_slider, "voice", Callable(self, "_on_pause_voice_slider_value_changed"))
	_setup_pause_slider(pause_music_slider, "music", Callable(self, "_on_pause_music_slider_value_changed"))
	_setup_pause_missile_slider(
		pause_missile_fly_slider,
		GameSettings.explosion_1_volume_slider,
		Callable(self, "_on_pause_missile_fly_slider_value_changed")
	)
	_setup_pause_missile_slider(
		pause_missile_ult_slider,
		GameSettings.explosion_missile_volume_slider,
		Callable(self, "_on_pause_missile_ult_slider_value_changed")
	)
	_setup_pause_missile_slider(
		pause_missile_shot_slider,
		GameSettings.explosion_4_volume_slider,
		Callable(self, "_on_pause_missile_shot_slider_value_changed")
	)


func _setup_pause_slider(slider: HSlider, bus_key: String, changed_callable: Callable) -> void:
	if slider == null:
		return
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	var bus_idx: int = int(_pause_audio_bus_by_key.get(bus_key, -1))
	if bus_idx < 0:
		slider.set_value_no_signal(100.0)
		slider.editable = false
		return
	slider.editable = true
	slider.set_value_no_signal(_bus_db_to_slider_value(AudioServer.get_bus_volume_db(bus_idx)))
	if not slider.value_changed.is_connected(changed_callable):
		slider.value_changed.connect(changed_callable)


func _setup_pause_missile_slider(slider: HSlider, setting_value: int, changed_callable: Callable) -> void:
	if slider == null:
		return
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.editable = true
	slider.set_value_no_signal(float(clampi(setting_value, 0, 100)))
	if not slider.value_changed.is_connected(changed_callable):
		slider.value_changed.connect(changed_callable)


func _find_audio_bus_index(candidates: Array[String]) -> int:
	var bus_count: int = AudioServer.get_bus_count()
	for wanted in candidates:
		for i in range(bus_count):
			if AudioServer.get_bus_name(i).to_lower() == wanted.to_lower():
				return i
	return -1


func _bus_db_to_slider_value(db: float) -> float:
	if db <= -79.0:
		return 0.0
	return clampf(db_to_linear(db) * 100.0, 0.0, 100.0)


func _slider_value_to_bus_db(value: float) -> float:
	var v: float = clampf(value, 0.0, 100.0) / 100.0
	if v <= 0.0001:
		return -80.0
	return linear_to_db(v)


func _set_pause_bus_volume(bus_key: String, value: float) -> void:
	var bus_idx: int = int(_pause_audio_bus_by_key.get(bus_key, -1))
	if bus_idx < 0:
		return
	AudioServer.set_bus_volume_db(bus_idx, _slider_value_to_bus_db(value))


func _on_pause_master_slider_value_changed(value: float) -> void:
	_set_pause_bus_volume("master", value)


func _on_pause_sfx_slider_value_changed(value: float) -> void:
	_set_pause_bus_volume("sfx", value)


func _on_pause_voice_slider_value_changed(value: float) -> void:
	_set_pause_bus_volume("voice", value)


func _on_pause_music_slider_value_changed(value: float) -> void:
	_set_pause_bus_volume("music", value)


func _on_pause_missile_fly_slider_value_changed(value: float) -> void:
	GameSettings.set_explosion_1_volume_slider(int(round(value)))
	if pause_missile_fly_slider != null:
		pause_missile_fly_slider.set_value_no_signal(float(GameSettings.explosion_1_volume_slider))


func _on_pause_missile_ult_slider_value_changed(value: float) -> void:
	GameSettings.set_explosion_missile_volume_slider(int(round(value)))
	if pause_missile_ult_slider != null:
		pause_missile_ult_slider.set_value_no_signal(float(GameSettings.explosion_missile_volume_slider))


func _on_pause_missile_shot_slider_value_changed(value: float) -> void:
	GameSettings.set_explosion_4_volume_slider(int(round(value)))
	if pause_missile_shot_slider != null:
		pause_missile_shot_slider.set_value_no_signal(float(GameSettings.explosion_4_volume_slider))


func _play_explosion_sound_3d(
	pos: Vector3,
	stream: AudioStream,
	volume_db: float,
	max_distance: float = EXPLOSION_SFX_MAX_DISTANCE,
	unit_size: float = EXPLOSION_SFX_UNIT_SIZE
) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "Master"
	p.max_distance = max_distance
	p.unit_size = unit_size
	p.attenuation_filter_cutoff_hz = 20500.0
	p.attenuation_filter_db = 0.0
	p.volume_db = volume_db
	p.global_position = pos
	add_child(p)
	p.play()
	var life_sec: float = maxf(0.35, stream.get_length() + 0.2)
	get_tree().create_timer(life_sec).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)


func is_capture_simulation_frozen() -> bool:
	return is_match_input_locked()


func should_hud_show_match_countdown() -> bool:
	if main_menu != null and main_menu.visible:
		return false
	if _mm_pregame_local_waiting:
		return false
	if not match_rules_actual:
		return false
	return Time.get_ticks_msec() < _match_go_live_at_msec


func get_match_countdown_seconds_remaining() -> int:
	var ms_left: int = _match_go_live_at_msec - Time.get_ticks_msec()
	return maxi(0, ceili(float(ms_left) / 1000.0))


func should_hud_show_overtime() -> bool:
	return false


func try_authoritative_match_win_check() -> void:
	if not match_rules_actual:
		return
	if not HeroNet.is_host_logic():
		return
	if _match_pending_return_to_menu:
		return
	if capture_point == null:
		return
	var ma: float = float(capture_point.mission_team_a)
	var mb: float = float(capture_point.mission_team_b)
	if ma >= 99.99:
		_host_trigger_match_end(0)
	elif mb >= 99.99:
		_host_trigger_match_end(1)


func _host_trigger_match_end(winning_team_id: int) -> void:
	if not HeroNet.is_host_logic():
		return
	if _match_pending_return_to_menu:
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "gdsync_show_match_end"), [winning_team_id])
	else:
		if multiplayer.multiplayer_peer != null:
			net_show_match_end.rpc(winning_team_id)
		else:
			_show_match_end_ui_local(winning_team_id)


func _show_match_end_ui_local(winner_team_id: int) -> void:
	_match_winner_team_id = int(winner_team_id)
	_match_end_screen_until_msec = Time.get_ticks_msec() + MATCH_END_SCREEN_MS
	_match_pending_return_to_menu = true
	if hud != null:
		hud.hide()
	if match_result_label != null:
		var me: Node = get_node_or_null(str(HeroNet.my_id()))
		var my_team: int = int(me.team_id) if me != null and me.get("team_id") is int else 0
		if winner_team_id == my_team:
			match_result_label.text = "You win!"
		else:
			match_result_label.text = "You lost!"
	if match_result_overlay != null:
		match_result_overlay.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _match_process_return_after_end_screen() -> void:
	if not _match_pending_return_to_menu:
		return
	if Time.get_ticks_msec() <= _match_end_screen_until_msec:
		return
	_finalize_match_return_to_menu()


func _finalize_match_return_to_menu() -> void:
	_remove_spawn_door_walls_if_any()
	_reset_post_prematch_countdown_ui()
	_hero_mm_bridge.cancel_menu_search_if_any()
	_match_pending_return_to_menu = false
	_match_end_screen_until_msec = 0
	_match_winner_team_id = -1
	if match_result_overlay != null:
		match_result_overlay.hide()
	if capture_point != null and capture_point.has_method("reset_match_capture_state"):
		capture_point.reset_match_capture_state()
	for child in get_children():
		if child is CharacterBody3D and child.has_method("receive_damage"):
			child.queue_free()
	peer_teams.clear()
	peer_heroes.clear()
	peer_usernames.clear()
	peer_prematch_locked_hero_id.clear()
	recently_damaged_by_me.clear()
	if HeroNet.is_gdsync() and GDSync.is_active():
		_mm_set_lobby_player_in_match(false)
		if GDSync.is_host():
			GDSync.lobby_erase_tag("match_session_live")
			GDSync.lobby_erase_tag("mm_team_assign")
		GDSync.lobby_leave()
	_matchmaking_used_for_current_game = false
	var mp := get_multiplayer()
	if mp != null and mp.multiplayer_peer != null:
		mp.multiplayer_peer.close()
		mp.multiplayer_peer = null
	HeroNet.kind = HeroNet.Kind.OFFLINE
	_set_map_selector_enabled(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _is_dedicated_server_process():
		return
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _cleanup_network_for_boot_menu() -> void:
	_hero_mm_bridge.cancel_menu_search_if_any()
	if _matchmaking_active:
		_matchmaking_cancel()
	if HeroNet.is_gdsync() and GDSync.is_active():
		_mm_set_lobby_player_in_match(false)
		GDSync.lobby_leave()
	var mp := get_multiplayer()
	if mp != null and mp.multiplayer_peer != null:
		mp.multiplayer_peer.close()
		mp.multiplayer_peer = null
	HeroNet.kind = HeroNet.Kind.OFFLINE


func _on_return_to_main_menu_button_pressed() -> void:
	if _is_dedicated_server_process():
		return
	_cleanup_network_for_boot_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _basis_with_up(up: Vector3) -> Basis:
	var y_axis: Vector3 = up.normalized()
	if y_axis.length_squared() < 1e-8:
		y_axis = Vector3.UP
	var x_axis: Vector3 = Vector3.FORWARD.cross(y_axis)
	if x_axis.length_squared() < 1e-8:
		x_axis = Vector3.RIGHT.cross(y_axis)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = y_axis.cross(x_axis).normalized()
	x_axis = z_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)

# (Optional) UPnP setup – keep disabled until needed.
# func upnp_setup():
# 	var upnp = UPNP.new()
# 	var discover_result = upnp.discover()
# 	assert(discover_result == UPNP.UPNP_RESULT_SUCCESS, \
# 		"UPNP Discover Failed! Error %s" % discover_result)
# 	assert(upnp.get_gateway() and upnp.get_gateway().is_vaild_gateway(), \
# 		"UPNP Invalid gateway")
# 	var map_result = upnp.add_port_mapping(PORT)
# 	assert(map_result == UPNP.UPNP_RESULT_SUCCESS, \
# 	"UPNP Port Mapping Failed! Error %s" % map_result)
# 	print("Success! Join Address: %s" % upnp.query_external_address())

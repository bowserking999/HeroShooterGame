extends Control
## Boot menu: Play queues matchmaking (lobby fills to this count before transition).

const MATCHMAKING_CAP_MAIN_MENU := 6

@onready var _username: LineEdit = $MarginRoot/MainColumn/BodyRow/RightColumn/PlayAlignCenter/PlayStack/UsernameEntry
@onready var _play_button: Button = $MarginRoot/MainColumn/BodyRow/RightColumn/PlayAlignCenter/PlayStack/PlayButton
@onready var _play_timer_hint: Label = $MarginRoot/MainColumn/BodyRow/RightColumn/PlayAlignCenter/PlayStack/PlayTimerHint
@onready var _mouse_slider: HSlider = $MarginRoot/MainColumn/BottomBar/SensitivityBlock/SensitivityHBox/MouseSensitivitySlider
@onready var _mouse_value: Label = $MarginRoot/MainColumn/BottomBar/SensitivityBlock/SensitivityHBox/MouseSensitivityValue
@onready var _debug_menu_button: Button = $MarginRoot/MainColumn/BottomBar/DebugMenuCenter/DebugMenuButton


func _ready() -> void:
	GameSettings.debug_world_boot = false
	if _debug_menu_button and not _debug_menu_button.pressed.is_connected(_on_debug_menu_pressed):
		_debug_menu_button.pressed.connect(_on_debug_menu_pressed)
	_sync_mouse_ui_from_settings()
	if _play_timer_hint:
		_play_timer_hint.text = "0:00"


func _exit_tree() -> void:
	HeroMmBridge.cancel_menu_search_if_any()


func _sync_mouse_ui_from_settings() -> void:
	if _mouse_slider:
		_mouse_slider.set_value_no_signal(float(GameSettings.mouse_sensitivity_slider))
	if _mouse_value:
		_mouse_value.text = str(GameSettings.mouse_sensitivity_slider)


func _on_mouse_sensitivity_slider_value_changed(value: float) -> void:
	GameSettings.set_mouse_sensitivity_slider(int(round(value)))
	_sync_mouse_ui_from_settings()


func _on_play_pressed() -> void:
	HeroMmBridge.start_menu_matchmaking(_username.text, MATCHMAKING_CAP_MAIN_MENU, _play_button, _play_timer_hint, self)


func _on_debug_menu_pressed() -> void:
	HeroMmBridge.cancel_menu_search_if_any()
	GameSettings.mm_pending_execute_after_world_load = false
	GameSettings.debug_world_boot = true
	GameSettings.queued_player_username = _username.text.strip_edges()
	GameSettings.matchmaking_cap_override = -1
	call_deferred("_deferred_open_debug_world")


func _deferred_open_debug_world() -> void:
	## Do not `preload("res://world.tscn")` here — `world.gd` preloads `main_menu.tscn`, which breaks PackedScene.
	get_tree().change_scene_to_file("res://world.tscn")


func _on_quit_pressed() -> void:
	HeroMmBridge.cancel_menu_search_if_any()
	get_tree().quit()


func _on_host_lobby_pressed() -> void:
	pass


func _on_find_lobbies_pressed() -> void:
	pass

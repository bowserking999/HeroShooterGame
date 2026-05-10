extends Node
## Persisted gameplay settings (mouse sensitivity, etc.).

## Route new `AudioStreamPlayer*` nodes to this bus for ~50% linear gain vs `Master` (see `default_bus_layout.tres`).
const NEW_SOUND_AUDIO_BUS := "SFX"

const CONFIG_PATH := "user://hero_shooter_settings.cfg"
const SECTION := "input"
const SECTION_AUDIO := "audio"
const KEY_MOUSE_SENS := "mouse_sensitivity_slider"
const KEY_EXPLOSION_1_VOL := "explosion_1_volume_slider"
const KEY_EXPLOSION_MISSILE_VOL := "explosion_missile_volume_slider"
const KEY_EXPLOSION_4_VOL := "explosion_4_volume_slider"

## 0–100 UI range; 50 matches the historical look scale (0.005 rad per pixel).
var mouse_sensitivity_slider: int = 50
var explosion_1_volume_slider: int = 100
var explosion_missile_volume_slider: int = 100
var explosion_4_volume_slider: int = 100

const _MOUSE_LOOK_REF := 0.005
const _SLIDER_REF := 50.0
## At slider 0, keep a small nonzero scale so the camera still responds.
const _MOUSE_SENS_MIN_REL := 0.12

## Applied to the world debug menu username field when switching from the main menu.
var queued_player_username: String = ""
## Next matchmaking uses this player cap (2–6). -1 = use debug menu slider instead.
var matchmaking_cap_override: int = -1
## True while main-menu-only GD-Sync queue search is active (see `hero_mm_bridge.gd`).
var mm_from_main_menu: bool = false
## After menu matchmaking fills, load `world.tscn` then run `gdsync_mm_execute_transition` once.
var mm_pending_execute_after_world_load: bool = false
## True only when `world.tscn` is opened from the main menu **Debug** path (Spring appears in hero pickers).
var debug_world_boot: bool = false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(CONFIG_PATH) == OK:
		mouse_sensitivity_slider = int(cf.get_value(SECTION, KEY_MOUSE_SENS, 50))
		explosion_1_volume_slider = int(cf.get_value(SECTION_AUDIO, KEY_EXPLOSION_1_VOL, 100))
		explosion_missile_volume_slider = int(cf.get_value(SECTION_AUDIO, KEY_EXPLOSION_MISSILE_VOL, 100))
		explosion_4_volume_slider = int(cf.get_value(SECTION_AUDIO, KEY_EXPLOSION_4_VOL, 100))
	mouse_sensitivity_slider = clampi(mouse_sensitivity_slider, 0, 100)
	explosion_1_volume_slider = clampi(explosion_1_volume_slider, 0, 100)
	explosion_missile_volume_slider = clampi(explosion_missile_volume_slider, 0, 100)
	explosion_4_volume_slider = clampi(explosion_4_volume_slider, 0, 100)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(CONFIG_PATH)
	cf.set_value(SECTION, KEY_MOUSE_SENS, mouse_sensitivity_slider)
	cf.set_value(SECTION_AUDIO, KEY_EXPLOSION_1_VOL, explosion_1_volume_slider)
	cf.set_value(SECTION_AUDIO, KEY_EXPLOSION_MISSILE_VOL, explosion_missile_volume_slider)
	cf.set_value(SECTION_AUDIO, KEY_EXPLOSION_4_VOL, explosion_4_volume_slider)
	cf.save(CONFIG_PATH)


func set_mouse_sensitivity_slider(v: int) -> void:
	mouse_sensitivity_slider = clampi(v, 0, 100)
	save_settings()


func set_explosion_1_volume_slider(v: int) -> void:
	explosion_1_volume_slider = clampi(v, 0, 100)
	save_settings()


func set_explosion_missile_volume_slider(v: int) -> void:
	explosion_missile_volume_slider = clampi(v, 0, 100)
	save_settings()


func set_explosion_4_volume_slider(v: int) -> void:
	explosion_4_volume_slider = clampi(v, 0, 100)
	save_settings()


## Scale applied to mouse relative deltas for yaw/pitch (matches previous fixed 0.005 at slider 50).
func get_mouse_look_scale() -> float:
	var rel: float = float(mouse_sensitivity_slider) / _SLIDER_REF
	rel = maxf(_MOUSE_SENS_MIN_REL, rel)
	return _MOUSE_LOOK_REF * rel


## Map 0..100 slider to linear loudness multiplier.
## 100 always means "use tuned baseline as-is"; lower values only scale down from that baseline.
func slider_to_db(v: int) -> float:
	var t: float = clampf(float(v) / 100.0, 0.0, 1.0)
	if t <= 0.0001:
		return -80.0
	return linear_to_db(t)


func take_queued_player_username() -> String:
	var s: String = queued_player_username.strip_edges()
	queued_player_username = ""
	return s


func take_mm_pending_execute_after_world_load() -> bool:
	var v: bool = mm_pending_execute_after_world_load
	mm_pending_execute_after_world_load = false
	return v

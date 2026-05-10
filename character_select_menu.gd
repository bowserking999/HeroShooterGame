extends Control
## Character preview on the left; role columns and hero buttons on the right.

signal hero_selected(hero_id: String)

const COLUMN_TITLES: PackedStringArray = ["Tank", "DPS", "Healing"]
const UI_YES_PATH := "res://assets/sounds/ui/uiyes.wav"
const UI_NO_PATH := "res://assets/sounds/ui/uino.wav"

var _ui_sfx: AudioStreamPlayer
var _ui_yes_stream: AudioStream
var _ui_no_stream: AudioStream
var _ui_yes_load_attempted: bool = false
var _ui_no_load_attempted: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()
	_ensure_ui_sfx_player()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.1, 0.88)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 48)
	root.add_theme_constant_override("margin_top", 40)
	root.add_theme_constant_override("margin_right", 48)
	root.add_theme_constant_override("margin_bottom", 40)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 48)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)
	# Left: character preview (placeholder)
	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(780, 620)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(preview_panel)
	var preview := Label.new()
	preview.text = "Character preview\n(coming soon)"
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_theme_font_size_override("font_size", 28)
	preview_panel.add_child(preview)
	# Right: hero buttons in three columns
	var columns_row := HBoxContainer.new()
	columns_row.add_theme_constant_override("separation", 28)
	columns_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns_row.custom_minimum_size.x = 820.0
	main.add_child(columns_row)
	var columns: Array = HeroesRegistry.get_character_select_columns(GameSettings.debug_world_boot)
	for col_i in range(columns.size()):
		var col_ids: Variant = columns[col_i]
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 14)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns_row.add_child(v)
		var title := Label.new()
		title.text = COLUMN_TITLES[col_i] if col_i < COLUMN_TITLES.size() else "—"
		title.add_theme_font_size_override("font_size", 30)
		v.add_child(title)
		for hid in col_ids:
			var hero: HeroResource = HeroesRegistry.get_hero(str(hid))
			var btn := Button.new()
			btn.text = hero.display_name if hero else str(hid)
			btn.custom_minimum_size = Vector2(260, 56)
			btn.add_theme_font_size_override("font_size", 22)
			btn.pressed.connect(_on_hero_pressed.bind(str(hid)))
			v.add_child(btn)

func _ensure_ui_sfx_player() -> void:
	if _ui_sfx != null and is_instance_valid(_ui_sfx):
		return
	_ui_sfx = AudioStreamPlayer.new()
	_ui_sfx.bus = GameSettings.NEW_SOUND_AUDIO_BUS
	add_child(_ui_sfx)


func _yes_stream() -> AudioStream:
	if _ui_yes_load_attempted:
		return _ui_yes_stream
	_ui_yes_load_attempted = true
	var r: Resource = ResourceLoader.load(UI_YES_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	_ui_yes_stream = r as AudioStream
	if _ui_yes_stream == null:
		push_warning("CharacterSelectMenu: could not load %s (open this project in the Godot editor to re-import audio)." % UI_YES_PATH)
	return _ui_yes_stream


func _no_stream() -> AudioStream:
	if _ui_no_load_attempted:
		return _ui_no_stream
	_ui_no_load_attempted = true
	var r: Resource = ResourceLoader.load(UI_NO_PATH, "", ResourceLoader.CACHE_MODE_REUSE)
	_ui_no_stream = r as AudioStream
	if _ui_no_stream == null:
		push_warning("CharacterSelectMenu: could not load %s (open this project in the Godot editor to re-import audio)." % UI_NO_PATH)
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


func _on_hero_pressed(hero_id: String) -> void:
	_ensure_ui_sfx_player()
	if _ui_sfx != null:
		var st: AudioStream = _yes_stream()
		if st != null:
			_ui_sfx.stream = st
			_ui_sfx.play()
	hero_selected.emit(hero_id)

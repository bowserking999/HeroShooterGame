extends Control
## Character preview on the left; role columns and hero buttons on the right.

signal hero_selected(hero_id: String)

const COLUMN_TITLES: PackedStringArray = ["Tank", "DPS", "Healing"]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()

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
	var columns: Array = HeroesRegistry.get_character_select_columns()
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

func _on_hero_pressed(hero_id: String) -> void:
	hero_selected.emit(hero_id)

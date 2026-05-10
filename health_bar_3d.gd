extends Node3D

## Overhead health bar above player heads.
## Blue for allies, red for enemies. Enemy bars only visible after local player damages them.
## Obstructed by terrain (depth test enabled).

const DAMAGED_VISIBLE_MS := 5000
const COLOR_ALLY := Color(0.2, 0.4, 0.9)
const COLOR_ENEMY := Color(0.9, 0.25, 0.2)
const COLOR_BG := Color(0.15, 0.15, 0.2)
const COLOR_USERNAME := Color(0, 0, 0)
const HEIGHT_ABOVE_PLAYER := 2.38
const HUD_RENDER_PRIORITY := 120

@onready var fill: MeshInstance3D = $Fill
@onready var background: MeshInstance3D = $Background
@onready var username_label: Label3D = $UsernameLabel
var fill_mat: StandardMaterial3D
var bg_mat: StandardMaterial3D

func _ready() -> void:
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var existing_fill = fill.get_surface_override_material(0)
	if existing_fill:
		fill_mat = existing_fill.duplicate() as StandardMaterial3D
	else:
		fill_mat = StandardMaterial3D.new()
		fill_mat.albedo_color = COLOR_ALLY
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.render_priority = HUD_RENDER_PRIORITY
	fill.set_surface_override_material(0, fill_mat)

	var existing_bg = background.get_surface_override_material(0)
	if existing_bg:
		bg_mat = existing_bg.duplicate() as StandardMaterial3D
	else:
		bg_mat = StandardMaterial3D.new()
		bg_mat.albedo_color = COLOR_BG
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.render_priority = HUD_RENDER_PRIORITY
	background.set_surface_override_material(0, bg_mat)
	if username_label:
		username_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		username_label.font_size = 28
		username_label.pixel_size = 0.0018
		username_label.outline_size = 4
		username_label.modulate = COLOR_USERNAME

func _process(_delta: float) -> void:
	var player: Node = get_parent()
	if not player or not "health" in player or not "team_id" in player:
		return

	if player.get("is_dead") == true:
		visible = false
		return

	var local_player: Node = _get_local_player()
	if local_player == null:
		visible = false
		return

	# Don't show overhead bar for our own player (HUD shows it)
	if player == local_player:
		visible = false
		return

	var local_team: int = int(local_player.get("team_id")) if local_player.get("team_id") != null else 0
	var target_team: int = int(player.get("team_id")) if player.get("team_id") != null else 0
	var is_ally := target_team == local_team

	# Enemy bars: only show when local player has recently damaged them
	if not is_ally:
		var world: Node = _get_world()
		if world == null or not world.has_method("was_damaged_by_me_recently"):
			visible = false
			return
		if not world.was_damaged_by_me_recently(int(player.name)):
			visible = false
			return

	visible = true

	var cam: Camera3D = get_viewport().get_camera_3d()
	var p: Node3D = player as Node3D
	if cam != null and p != null:
		var world_pos: Vector3 = p.global_position + p.global_transform.basis * Vector3(0.0, HEIGHT_ABOVE_PLAYER, 0.0)
		global_position = world_pos
		## Face camera; use camera up (not world UP) so the plane stays screen-parallel without folding edge-on.
		look_at(cam.global_position, cam.global_transform.basis.y)
		rotate_object_local(Vector3.UP, PI)

	# Color: blue for allies, red for enemies
	if fill_mat:
		fill_mat.albedo_color = COLOR_ALLY if is_ally else COLOR_ENEMY

	# Fill scale based on health
	var h: float = float(player.get("health"))
	var mx: float = float(player.get("max_health")) if "max_health" in player else 250.0
	var ratio := clampf(h / mx, 0.0, 1.0)
	fill.scale.x = ratio
	fill.position.x = -0.5 * (1.0 - ratio)
	_update_username_label(player, target_team)


func _update_username_label(player: Node, _target_team: int) -> void:
	if username_label == null:
		return
	var raw_username: String = str(player.get("player_username") if player.get("player_username") != null else "").strip_edges()
	if raw_username.is_empty():
		raw_username = "Player"
	username_label.text = raw_username
	username_label.modulate = COLOR_USERNAME

func _get_local_player() -> Node:
	var world := _get_world()
	if world == null:
		return null
	var my_id := str(HeroNet.my_id())
	return world.get_node_or_null(my_id)

func _get_world() -> Node:
	var p := get_parent()
	if p:
		p = p.get_parent()
	return p if p and p.has_method("record_damaged_by_me") else null

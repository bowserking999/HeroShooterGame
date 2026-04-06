extends Node3D

## Overhead health bar above player heads.
## Blue for allies, red for enemies. Enemy bars only visible after local player damages them.
## Obstructed by terrain (depth test enabled).

const DAMAGED_VISIBLE_MS := 5000
const COLOR_ALLY := Color(0.2, 0.4, 0.9)
const COLOR_ENEMY := Color(0.9, 0.25, 0.2)
const COLOR_BG := Color(0.15, 0.15, 0.2)

@onready var fill: MeshInstance3D = $Fill
var fill_mat: StandardMaterial3D

func _ready() -> void:
	var existing = fill.get_surface_override_material(0)
	if existing:
		fill_mat = existing.duplicate() as StandardMaterial3D
	else:
		fill_mat = StandardMaterial3D.new()
		fill_mat.albedo_color = COLOR_ALLY
	fill.set_surface_override_material(0, fill_mat)

func _process(_delta: float) -> void:
	var player: Node = get_parent()
	if not player or not "health" in player or not "team_id" in player:
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

	# Billboard: face camera (rotate 180 so plane front faces camera, not back)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		look_at(cam.global_position, Vector3.UP)
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

func _get_local_player() -> Node:
	var world := _get_world()
	if world == null:
		return null
	var my_id := str(multiplayer.get_unique_id())
	return world.get_node_or_null(my_id)

func _get_world() -> Node:
	var p := get_parent()
	if p:
		p = p.get_parent()
	return p if p and p.has_method("record_damaged_by_me") else null

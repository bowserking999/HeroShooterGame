class_name LaserShield
extends StaticBody3D

signal shield_broken

@export var max_health: int = 100
@export var owner_team_id: int = -1

var current_health: int = 100
var _active: bool = false
var _hostile_view: bool = false
@onready var _mesh: MeshInstance3D = $MeshInstance3D

const _ALLY_ALBEDO := Color(0.2, 0.62, 1.0, 0.28)
const _ALLY_EMISSION := Color(0.22, 0.76, 1.0, 1.0)
const _HOSTILE_ALBEDO := Color(1.0, 0.42, 0.42, 0.28)
const _HOSTILE_EMISSION := Color(1.0, 0.5, 0.5, 1.0)
const _SHIELD_COLLISION_LAYER_BIT := 1 << 3 # layer 4
const _LOW_HP_FADE_START_RATIO := 0.35
const _MIN_ALPHA_MULT := 0.16


func _ready() -> void:
	current_health = max_health
	_set_visuals(_active)


func set_owner_team(team_id: int) -> void:
	owner_team_id = team_id


func set_hostile_view(hostile: bool) -> void:
	_hostile_view = hostile
	_apply_color()


func set_active_shield(enabled: bool) -> void:
	_active = enabled
	_set_visuals(enabled)
	if enabled and current_health <= 0:
		current_health = max_health


func is_active_shield() -> bool:
	return _active


func reset_health() -> void:
	current_health = max_health
	_apply_color()


func set_health_value(new_health: int) -> void:
	current_health = clampi(new_health, 0, max_health)
	_apply_color()


func try_block_projectile(shooter_team: int, damage_amount: int) -> bool:
	if not _active:
		return false
	if owner_team_id >= 0 and shooter_team == owner_team_id:
		return false
	var dmg := maxi(1, damage_amount)
	current_health = maxi(0, current_health - dmg)
	_apply_color()
	if current_health <= 0:
		_active = false
		_set_visuals(false)
		shield_broken.emit()
	return true


func _set_visuals(enabled: bool) -> void:
	visible = enabled
	collision_layer = _SHIELD_COLLISION_LAYER_BIT if enabled else 0
	collision_mask = 0


func _apply_color() -> void:
	if _mesh == null:
		return
	var mat_src: Material = _mesh.get_surface_override_material(0)
	if not (mat_src is StandardMaterial3D):
		return
	var mat := (mat_src as StandardMaterial3D).duplicate() as StandardMaterial3D
	var hp_ratio: float = 1.0
	if max_health > 0:
		hp_ratio = clampf(float(current_health) / float(max_health), 0.0, 1.0)
	var alpha_mult: float = 1.0
	if hp_ratio < _LOW_HP_FADE_START_RATIO:
		var t := hp_ratio / _LOW_HP_FADE_START_RATIO
		alpha_mult = lerpf(_MIN_ALPHA_MULT, 1.0, clampf(t, 0.0, 1.0))
	if _hostile_view:
		mat.albedo_color = Color(_HOSTILE_ALBEDO.r, _HOSTILE_ALBEDO.g, _HOSTILE_ALBEDO.b, _HOSTILE_ALBEDO.a * alpha_mult)
		mat.emission = _HOSTILE_EMISSION
	else:
		mat.albedo_color = Color(_ALLY_ALBEDO.r, _ALLY_ALBEDO.g, _ALLY_ALBEDO.b, _ALLY_ALBEDO.a * alpha_mult)
		mat.emission = _ALLY_EMISSION
	_mesh.set_surface_override_material(0, mat)

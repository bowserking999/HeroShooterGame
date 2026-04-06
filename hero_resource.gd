class_name HeroResource
extends Resource
## Data for one playable hero. Add new heroes by creating a .tres in res://heroes/
## and registering its id in HeroesRegistry.

@export var hero_id: String = ""
@export var display_name: String = ""
## Kit: "striker" (hitscan DPS), "tank" (explosive shell), "support" (Orb heals), "medic" (ray heal). Empty = same as hero_id.
@export var archetype_id: String = ""
@export var run_speed: float = 10.0
@export var jump_velocity: float = 10.0
## 1 = damage weapon, 2 = heal weapon (default weapon when spawning)
@export var default_weapon: int = 1
@export var max_health: int = 250
## Optional: path to hero model scene for future (e.g. "res://heroes/models/striker.tscn")
@export var model_scene_path: String = ""
## Body color for the character (used until custom model is set)
@export var body_color: Color = Color.WHITE

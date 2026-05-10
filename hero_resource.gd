class_name HeroResource
extends Resource
## Data for one playable hero. Add new heroes by creating a .tres in res://heroes/
## and registering its id in HeroesRegistry.

@export var hero_id: String = ""
@export var display_name: String = ""
## Kit: "striker" (hitscan DPS), "tank" (explosive shell), "support" (Orb heals), "medic" (ray heal). Empty = same as hero_id.
@export var archetype_id: String = ""
@export var run_speed: float = 8.0
@export var jump_velocity: float = 9.0
## 1 = damage weapon, 2 = heal weapon (default weapon when spawning)
@export var default_weapon: int = 1
@export var max_health: int = 250
## Optional: imported character scene (.blend / .glb / .tscn). Instanced under Player/CharacterModel; hides the capsule when set and valid.
@export var model_scene_path: String = ""
## Optional scene whose AnimationPlayer libraries are copied onto this hero's imported rig (same skeleton). Use when the mesh `.glb` has no clips but shares the rig with another asset (e.g. sniper mesh + missile animations).
@export var body_anim_library_source_path: String = ""
## If set (e.g. `dps_missile`), libraries are copied from that hero's `model_scene_path` so they stay in sync. Takes precedence over `body_anim_library_source_path` when the reference resolves.
@export var body_anim_library_source_hero_id: String = ""
## Clip name → `res://…/*.res` paths for external `Animation` resources (same workflow as GLTF “save to file” under `assets/animations/` for missile). Merged onto the body `AnimationPlayer` after library injection so tracks override embedded clips.
@export var body_anim_external_resources: Dictionary = {}
## Body skeleton clips to play when the root pistol AnimationPlayer plays idle / move / shoot (Blender imports often use names like "Armature|walk").
@export var body_anim_idle: String = "idle"
@export var body_anim_move: String = "move"
@export var body_anim_shoot: String = "shoot"
## Optional full-body jump clips on imported rigs (empty = skip keyword resolve per clip).
@export var body_anim_jump_start: String = ""
@export var body_anim_jump_loop: String = ""
@export var body_anim_jump_land: String = ""
## First-person mesh under the player camera (often arms-only). Leave empty for weapon-only FP. Use a different .glb than `model_scene_path` when you want Overwatch-style FP vs TP rigs.
@export var fp_model_scene_path: String = ""
## Skeleton clip names for the FP rig when it differs from third person. Empty = use the same names as `body_anim_*` on the FP model’s AnimationPlayer.
@export var fp_body_anim_idle: String = ""
@export var fp_body_anim_move: String = ""
@export var fp_body_anim_shoot: String = ""
## Body color for the character (used until custom model is set)
@export var body_color: Color = Color.WHITE
## If >= 0, primary weapon uses a magazine of this size (reload with `reload` action). -1 = infinite ammo display.
@export var magazine_size: int = -1
## If >= 0, reload action fills the magazine after this delay (seconds). Used by explosive tank primary.
@export var magazine_reload_seconds: float = -1.0
## Shown in the center of the ultimate radial HUD.
@export var ultimate_icon: Texture2D
## Total points required to fully charge ultimate. HUD percent is `ultimate_charge / ultimate_cost`.
@export var ultimate_cost: float = 2000.0

@export_group("HUD abilities")
## Slot order is left → right (Slot0 … Slot2). Empty string hides that slot.
## If this array is empty, the HUD uses `weapon1`, `weapon2`, `secondary`.
@export var hud_ability_actions: PackedStringArray = PackedStringArray()
## Optional `res://…` texture paths per slot (same length / indices as custom actions).
@export var hud_ability_icon_paths: PackedStringArray = PackedStringArray()
## Cooldown duration in seconds per slot (same indices as `hud_ability_actions`). Use 0 for no cooldown.
@export var hud_ability_cooldown_seconds: PackedFloat32Array = PackedFloat32Array()

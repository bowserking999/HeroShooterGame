extends CharacterBody3D

signal health_changed(health_value)
signal player_died
signal player_respawned

const RESPAWN_DELAY := 5.0
## World-space Y below this is lethal void (checked on local pawn authority).
const VOID_KILL_WORLD_Y := -30.0
const SPAWN_ROOM_HEAL_PER_SEC := 50.0

@onready var camera: Camera3D = $Camera3D
@onready var third_person_camera: Camera3D = $ThirdPersonCamera
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var character_model_root: Node3D = $CharacterModel
@onready var body_mesh_placeholder: MeshInstance3D = $MeshInstance3D
@onready var muzzle_flash: Node = $Camera3D/Pistol/MuzzleFlash
## Under Camera3D (not Pistol) so the Binbun flash does not follow pistol recoil / shoot animation.
@onready var big_muzzle_flash: Node3D = $Camera3D/BigMuzzleFlash
@onready var big_muzzle_flash_sniper: Node3D = $Camera3D/BigMuzzleFlashSniper
@onready var raycast: RayCast3D = $Camera3D/RayCast3D
@onready var pistol_node: Node3D = $Camera3D/Pistol
## Skeleton drives third-person mesh (others see it; owner’s camera culls mesh via render layer, not visibility).
var _hero_body_anim_world: AnimationPlayer = null
## When set, drives `_hero_body_anim_world` with locomotion + filtered upper-body OneShot (walk continues while shooting).
var _hero_body_anim_tree: AnimationTree = null
var _hero_body_uses_layered_anim: bool = false
## Owner-only duplicate of the hero scene: plays the same clips on layer 1 as SHADOWS_ONLY so your ground shadow matches the real mesh.
var _hero_shadow_anim: AnimationPlayer = null
var _hero_shadow_anim_tree: AnimationTree = null
var _hero_shadow_uses_layered_anim: bool = false
## First Skeleton3D under imported hero — additive head/neck pitch toward aim (camera / pistol forward).
var _hero_body_skeleton: Skeleton3D = null
## Owner-only shadows-only duplicate uses the same clips but a separate skeleton; mirror head pose here too.
var _hero_shadow_skeleton: Skeleton3D = null
var _hero_head_bone_idx: int = -1
var _hero_neck_bone_idx: int = -1
## Right shoulder — additive pitch matching head (camera look).
var _hero_right_shoulder_bone_idx: int = -1
## TP: bind muzzle / weapon VFX to this body skeleton bone (e.g. soldier `LowerArm.R.001`).
var _hero_tp_weapon_bone_idx: int = -1
## Third person: parent for muzzle flash + big flashes — pose copied from weapon bone each frame (local authority).
var _tp_muzzle_effects_anchor: Node3D = null
## Previous tick’s neck/head look quaternions — stripped before re-applying when the pose still carries last tick’s additive.
var _hl_neck_q_body: Quaternion = Quaternion.IDENTITY
var _hl_head_q_body: Quaternion = Quaternion.IDENTITY
var _hl_neck_q_shadow: Quaternion = Quaternion.IDENTITY
var _hl_head_q_shadow: Quaternion = Quaternion.IDENTITY
var _hl_have_neck_saved_body: bool = false
var _hl_have_head_saved_body: bool = false
var _hl_have_neck_saved_shadow: bool = false
var _hl_have_head_saved_shadow: bool = false
var _hl_last_neck_pose_after_body: Quaternion = Quaternion.IDENTITY
var _hl_last_head_pose_after_body: Quaternion = Quaternion.IDENTITY
var _hl_last_neck_pose_after_shadow: Quaternion = Quaternion.IDENTITY
var _hl_last_head_pose_after_shadow: Quaternion = Quaternion.IDENTITY
var _hl_rarm_q_body: Quaternion = Quaternion.IDENTITY
var _hl_have_rarm_saved_body: bool = false
var _hl_last_rarm_pose_after_body: Quaternion = Quaternion.IDENTITY
var _hl_rarm_q_shadow: Quaternion = Quaternion.IDENTITY
var _hl_have_rarm_saved_shadow: bool = false
var _hl_last_rarm_pose_after_shadow: Quaternion = Quaternion.IDENTITY
## Third-person body meshes use this layer so the owning player’s camera can skip drawing them while keeping shadows.
const RENDER_LAYER_WORLD_BODY_OWNER_OCCLUDED: int = 20
var _default_camera_cull_mask: int = 0xFFFFF
const THIRD_PERSON_CAMERA_HEIGHT: float = 2.05
const THIRD_PERSON_CAMERA_DISTANCE: float = 4.4
const THIRD_PERSON_CAMERA_CLEARANCE: float = 0.24
const THIRD_PERSON_CAMERA_COLLISION_MASK: int = 0xFFFFFFFD
## TP only: maps anchor (muzzle effects) into weapon bone space. Tune per rig if barrel axis differs.
const TP_THIRD_PERSON_PISTOL_BIND_OFFSET := Transform3D.IDENTITY
const CAMERA_PITCH_LIMIT_RAD: float = deg_to_rad(80.0)
## Imported rig: additive pitch on neck/head so the body faces camera look up/down (bone rest X = nod axis).
const HEAD_LOOK_CAMERA_MULT: float = 0.92
## Aim contribution clamp (matches camera feel; joint caps below are the hard stops).
const HEAD_LOOK_CAM_PITCH_MAX_RAD: float = deg_to_rad(52.0)
## Hard per-joint limits (reference ~45–55° combined in screenshots).
const HEAD_LOOK_NECK_PITCH_MAX_RAD: float = deg_to_rad(20.0)
const HEAD_LOOK_HEAD_PITCH_MAX_RAD: float = deg_to_rad(38.0)
const HEAD_LOOK_NECK_FRACTION: float = 0.38
## Lower than Player (0) so AnimationMixer applies before `_apply_imported_head_look_from_camera` reads poses.
const BODY_ANIM_TREE_PROCESS_PRIORITY: int = -100
## Ignore tiny pitch noise when aim is level so head/neck stay still when the camera is still.
const HEAD_LOOK_FORWARD_DEADZONE_RAD: float = deg_to_rad(0.12)
var _third_person_enabled: bool = false

const HealOrbScene = preload("res://heal_orb.tscn")
const TankRoundScene = preload("res://tank_round.tscn")
const LandmineScene = preload("res://landmine.tscn")
const MissileAbilityRocketScene = preload("res://assets/models/rocket.blend")
const MedicBurstScene = preload("res://medic_burst.tscn")
const LaserBeamScene = preload("res://laser_beam.tscn")
const SniperUltBeamScene = preload("res://sniper_ult_beam.tscn")
const HealBeamScene = preload("res://heal_beam.tscn")
const LaserShieldScene = preload("res://laser_shield.tscn")
const TankLaserPulseAreaVfxScene = preload("res://assets/BinbunVFX/magic_areas/effects/pulse_area/pulse_area_vfx_02.tscn")
const MissileAbilityTargetVfxScene = preload("res://assets/BinbunVFX/magic_areas/effects/pulse_area/pulse_area_vfx_03.tscn")
const MissileAbilityImpactVfxScene = preload("res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_01.tscn")

const HEAL_ORB_SPEED: float = 25.0
const TANK_ROUND_SPEED: float = 50.0
const TANK_SECONDARY_ROUND_SPEED: float = 37.0
const TANK_SECONDARY_RECOIL_HORIZONTAL: float = 9.5
const TANK_SECONDARY_RECOIL_UPWARD: float = 3.8
const LANDMINE_THROW_SPEED: float = 34.0
const SMOKE_BOMB_THROW_SPEED: float = 30.0
const MEDIC_BURST_SPEED: float = 42.0
const LASER_MAX_RANGE: float = 200.0
const LASER_NET_SYNC_INTERVAL: float = 0.05
## ~60 DPS sustained at LASER_TICK_INTERVAL (tune together).
const LASER_TICK_DAMAGE: int = 6
const LASER_TICK_INTERVAL: float = 0.1
const LASER_ONCE_STREAM_PATH := "res://assets/sounds/effects/laseronce.wav"
## Starts slightly low; ramps toward normal while primary beam is held (see `_tank_laser_pitch_hold_sec`).
const LASER_ONCE_PITCH_MIN := 0.88
const LASER_ONCE_PITCH_MAX := 1.0
const LASER_ONCE_PITCH_RAMP_SEC := 15.0
const LASER_ONCE_SFX_DB := -34.0
const LASER_RELEASE_COOLDOWN_SEC: float = 0.125
const LASER_SPLASH_RADIUS: float = 0.5
## Looping aura while shield or laser ultimate bubble is active (asset is `.mp3` in-repo).
const LASER_SHIELD_AURA_STREAM_PATH := "res://assets/sounds/effects/lasersheildaura.mp3"
const LASER_SHIELD_AURA_DB := -10.0
const LASER_SHIELD_AURA_ULT_EXTRA_DB := 6.0
const MEDIC_BEAM_MAX_RANGE: float = 28.0
const MEDIC_BEAM_NET_SYNC_INTERVAL: float = 0.05
const MEDIC_BEAM_HEAL_INTERVAL: float = 0.25
const MEDIC_GLOBAL_ULT_DURATION_SEC: float = 13.0
const MEDIC_BEAM_ALLY_HEAL_PER_TICK: int = 7
const MEDIC_BEAM_SELF_HEAL_PER_TICK: int = 2
## Lock point height above player origin (torso / medigun attach).
const MEDIC_BEAM_TARGET_Y_OFFSET: float = 1.15
## Player CharacterBody3D collision layer (splash queries use shapes, not node origin).
const PLAYER_PHYSICS_LAYER: int = 2
## Spring: charge primary — blue cylinder hitbox; longer hold = longer reach on release.
const SPRING_PUNCH_MAX_LENGTH: float = 16.0
const SPRING_PUNCH_MIN_LENGTH: float = 3.0
const SPRING_PUNCH_MAX_CHARGE_SEC: float = 1.15
const SPRING_PUNCH_ROUNDS_PER_MINUTE: float = 85.0
const SPRING_PUNCH_MIN_INTERVAL_SEC: float = 60.0 / SPRING_PUNCH_ROUNDS_PER_MINUTE
const SPRING_PUNCH_RADIUS: float = 0.48
const SPRING_PUNCH_DAMAGE: int = 50
const SPRING_PUNCH_VFX_DURATION: float = 0.25
## Push punch origin forward along facing so the volume starts at the front of the body, not the capsule center.
const SPRING_PUNCH_SURFACE_FORWARD_OFFSET: float = 0.52
## Ray for wall clip: hit everything except `PLAYER_PHYSICS_LAYER` so other players are ignored.
const SPRING_PUNCH_WALL_STOP_EPSILON: float = 0.04
## Begin wall ray behind the punch start so traces still hit when hugging a wall (start can sit past the plane).
const SPRING_PUNCH_TERRAIN_RAY_BACKTRACE: float = 0.65
## Air control: steer perpendicular to jump trajectory only; can't exceed horizontal speed from takeoff.
const AIR_PERP_ACCEL: float = 8.0
const AIR_PERP_ACCEL_SPRING: float = 14.0
## Slow down along jump-forward when holding input opposite that axis (slight braking).
const AIR_PARALLEL_BRAKE: float = 10.0
## Mouse look scale is divided by this while crosshair is on an enemy (multiplicative slowdown).
const CROSSHAIR_AIM_SLOW_ENEMY_DIVISOR: float = 1.75

const EnemyOutlineShaderMaterial: ShaderMaterial = preload("res://materials/enemy_outline_material.tres")
## Spring charged jump: same max charge window as punch; ground move speed while charging jump.
const SPRING_JUMP_CHARGE_MOVE_MULT: float = 0.5
const SPRING_JUMP_VEL_MIN_MULT: float = 0.72
const SPRING_JUMP_VEL_MAX_MULT: float = 1.38
const HITSCAN_DAMAGE: int = 50
const SNIPER_DAMAGE: int = 25
const SNIPER_ROUNDS_PER_MINUTE: float = 185.0
const SNIPER_FIRE_PERIOD_SEC: float = 60.0 / SNIPER_ROUNDS_PER_MINUTE
const SNIPER_RELOAD_SEC: float = 3.0
const SNIPER_ULT_MAX_RANGE: float = 100.0
const SNIPER_ULT_WINDUP_SEC: float = 0.25
const SNIPER_ULT_LINGER_SEC: float = 0.12
const SNIPER_ULT_BEAM_VFX_SEC: float = 0.65
const SNIPER_ULT_PRIMARY_LOCK_SEC: float = 0.3
const SNIPER_ULT_BURST_DAMAGE: int = 120
const SNIPER_ULT_LINGER_DAMAGE: int = 100
const SNIPER_ULT_BEAM_RADIUS: float = 0.28
const SNIPER_SHOT_STREAM_PATH := "res://assets/sounds/effects/snipershot.wav"
const SNIPER_SMOKE_PRIME_STREAM_PATH := "res://assets/sounds/effects/snipersmokebombprime.wav"
const SNIPER_ULT_HIT_STREAM_PATH := "res://assets/sounds/effects/sniper ult.mp3"
const SNIPER_SHOT_SFX_DB := -26.0
const SNIPER_SMOKE_PRIME_SFX_DB := -6.0
const SNIPER_ULT_HIT_SFX_DB := -12.0
const MISSILE_HITSCAN_DAMAGE: int = 25
const HITSCAN_HEAL: int = 50
const MISSILE_ROUNDS_PER_SEC: float = 9.0
const MISSILE_ABILITY_COOLDOWN_SEC: float = 2.25
const MISSILE_ABILITY_MIN_FLIGHT_SEC: float = 0.8
const MISSILE_ABILITY_MAX_FLIGHT_SEC: float = 1.4
const MISSILE_ABILITY_TIMEOUT_SEC: float = 12.0
const MISSILE_ABILITY_ARC_HEIGHT: float = 11.0
const MISSILE_ABILITY_DAMAGE: int = 100
const MISSILE_ABILITY_DAMAGE_RADIUS: float = 2.35
const MISSILE_ABILITY_MARKER_Y_OFFSET: float = 0.04
const MISSILE_ABILITY_VFX_CLEANUP_SEC: float = 3.0
const MISSILE_IMPACT_BEHIND_CAMERA_CULL_DOT: float = -0.3
const MISSILE_IMPACT_BEHIND_CAMERA_CULL_MIN_DISTANCE: float = 6.0
const MISSILE_ABILITY_WINDUP_SEC: float = 2.0
const MISSILE_ABILITY_POST_WINDUP_SHOOT_LOCK_SEC: float = 0.5
const MISSILE_ABILITY_MAX_TARGET_RANGE: float = 30.0
const MISSILE_ULT_DURATION_SEC: float = 5.0
const MISSILE_ULT_HOVER_HEIGHT_DELTA: float = 8.5
const MISSILE_ULT_HOVER_FOLLOW_SPEED: float = 5.5
const MISSILE_ULT_SIDE_OFFSET_M: float = 2.4
const MISSILE_ULT_ARM_DELAY_SEC: float = 0.5
const MISSILE_ULT_END_AFTER_FIRE_SEC: float = 0.5
const MISSILE_ULT_CENTER_FLIGHT_SPEED_MULT: float = 1.08
const MISSILE_ULT_PREVIEW_NET_SYNC_INTERVAL: float = 0.05
const MISSILE_ULT_LOOK_SENS_MULT: float = 0.2
const ORB_DASH_COOLDOWN_SEC: float = 6.0
const ORB_DASH_DURATION_SEC: float = 0.16
const ORB_DASH_DISTANCE_M: float = 5.0
const ORB_ULT_DURATION_SEC: float = 8.0
const ORB_ULT_MOVE_MULT: float = 0.6
const ORB_ULT_ORBIT_COUNT: int = 5
const ORB_ULT_ORBIT_RADIUS: float = 1.9
const ORB_ULT_ORBIT_HEIGHT: float = 1.15
const ORB_ULT_ORBIT_ANGULAR_SPEED: float = TAU * 0.65
## Baseline ~5 orbs/s (~0.2s). Primary is **half that fire rate** (double spacing) → ~1.25/s.
const ORB_PRIMARY_REFERENCE_SHOT_PERIOD_SEC: float = 0.2
const ORB_PRIMARY_MIN_FIRE_INTERVAL_SEC: float = ORB_PRIMARY_REFERENCE_SHOT_PERIOD_SEC * 4.0
const SPRING_ULT_DURATION_SEC: float = 3.0
const SPRING_ULT_HOVER_HEIGHT_DELTA: float = 8.0
const SPRING_ULT_HOVER_FOLLOW_SPEED: float = 4.8
const SPRING_ULT_LAUNCH_DURATION_SEC: float = 0.45
const SPRING_ULT_AIR_TOP_SPEED: float = 1.0
const SPRING_ULT_SHOCKWAVE_RADIUS: float = 5.0
const SPRING_ULT_SHOCKWAVE_PUSH_STRENGTH: float = 16.0
const SPRING_ULT_SLAM_DAMAGE: int = 120
const SPRING_ULT_SHOCKWAVE_GROW_SEC: float = 0.22
const SPRING_ULT_SHOCKWAVE_SHRINK_SEC: float = 0.2
const SPRING_ULT_SHOCKWAVE_SCALE_MULT: float = 2.0
const COLLISION_MASK_WORLD_ONLY: int = 0b0001
const COLLISION_MASK_WORLD_PLAYER_SHIELD: int = 0b1011 # layers 1 (world), 2 (players), 4 (laser shield)
const TANK_LASER_SHIELD_MAX_HEALTH: int = 100
const TANK_LASER_SHIELD_BREAK_COOLDOWN_SEC: float = 2.0
const TANK_LASER_SHIELD_FORWARD_OFFSET: float = 1.35
const TANK_LASER_SHIELD_HEIGHT_OFFSET: float = 0.8
const TANK_LASER_SHIELD_WIDTH_SCALE_MULT: float = 2.35
const TANK_LASER_SHIELD_HEIGHT_SCALE_MULT: float = 1.2
const TANK_LASER_SHIELD_MOVE_MULT_WHILE_UP: float = 0.7
const TANK_LASER_ULT_DURATION_SEC: float = 6.0
const TANK_LASER_ULT_PUSH_RADIUS: float = 5.0
const TANK_LASER_ULT_PUSH_INTERVAL: float = 0.2
const TANK_LASER_ULT_PUSH_STRENGTH: float = 14.0
const TANK_LASER_ULT_PUSH_DAMAGE: int = 10
const TANK_LASER_ULT_VFX_Y_OFFSET: float = 0.22
const TANK_LASER_ULT_SCALE_MULT: float = 2.0
const TANK_LASER_ULT_VFX_SCALE_IN_SEC: float = 0.38
const TANK_LASER_ULT_VFX_SCALE_OUT_SEC: float = 0.32
const TANK_LASER_ULT_MOVE_MULT: float = 0.5
const TANK_EXPLOSIVE_ULT_DURATION_SEC: float = 12.0
const TANK_EXPLOSIVE_ULT_DAMAGE_MULT: float = 0.5
const DEFAULT_ULTIMATE_COST: float = 2000.0
const ULTIMATE_PASSIVE_FRACTION_PER_SEC: float = 0.005 # 1% every 2 seconds
## Camera ray length when picking a world aim point for projectiles (muzzle → crosshair line).
const PROJECTILE_AIM_MAX_RANGE: float = 512.0
const FOOTSTEP_SFX_DIR := "res://assets/sounds/effects"
const FOOTSTEP_MIN_MOVE_SPEED: float = 0.9
const FOOTSTEP_INTERVAL_SLOW: float = 0.82
const FOOTSTEP_INTERVAL_WALK: float = 0.58
const FOOTSTEP_INTERVAL_RUN: float = 0.4
const FOOTSTEP_SPEED_REF: float = 10.0
const FOOTSTEP_MOVEMENT_PREROLL_SEC: float = 0.14
const BODY_SHOOT_HOLD_SEC: float = 0.16
const REMOTE_MOVE_ENTER_SPEED: float = 0.75
const REMOTE_MOVE_EXIT_SPEED: float = 0.52
const REMOTE_MOVE_HOLD_SEC: float = 0.055
const REMOTE_MOVE_SPEED_SMOOTH: float = 18.0
const BODY_MOVE_ANIM_SPEED_MULT: float = 2.0
const _JUMP_BODY_PHASE_NONE := 0
const _JUMP_BODY_PHASE_START := 1
const _JUMP_BODY_PHASE_CYCLE := 2
const _JUMP_BODY_PHASE_LANDING := 3
const _JUMP_TAKEOFF_VY_THRESHOLD := 0.35
const MISSILE_FLY_STREAM_PATHS: PackedStringArray = [
	"res://assets/sounds/effects/missilefly_1.wav",
	"res://assets/sounds/effects/missilefly_2.wav",
]
const MEDIC_HEALGUN_STREAM_PATH := "res://assets/sounds/effects/medicsound_2.wav"
const MEDIC_PULSE_FIRE_STREAM_PATH := "res://assets/sounds/effects/medicpulsefire.wav"
const HEALING_RECEIVED_STREAM_PATH := "res://assets/sounds/effects/healing.wav"
const MISSILE_ULT_STREAM_PATH := "res://assets/sounds/effects/missileult.wav"
const MISSILE_SINGLE_SHOT_STREAM_PATH := "res://assets/sounds/effects/missilesingleshot.wav"
const TANK_ULT_STREAM_PATH := "res://assets/sounds/effects/tankult.wav"
const MISSILE_FLY_BASE_DB: float = -10.0
const MISSILE_ULT_BASE_DB: float = 0.0
const MISSILE_PRIMARY_SFX_HALF_DB: float = -14.5
const MISSILE_PRIMARY_LOCAL_EXTRA_HALF_DB: float = -14.0
const TANK_ULT_SFX_DB: float = -2.5
const Explosion2Sfx: AudioStream = preload("res://assets/sounds/effects/explosion_2.wav")
const Explosion3Sfx: AudioStream = preload("res://assets/sounds/effects/explosion_3.wav")
const HEALING_RECEIVED_GAP_RESET_SEC: float = 2.0
const HEALING_RECEIVED_SOUND_COOLDOWN_SEC: float = 5.0
const HEALING_RECEIVED_SFX_DB: float = -12.0
const MEDIC_HEALGUN_SFX_DB: float = -14.0
const MEDIC_PULSE_FIRE_SFX_DB: float = -24.0
const ORB_SHOOT_STREAM_PATH := "res://assets/sounds/effects/orbshoot.wav"
const ORB_ULT_STREAM_PATH := "res://assets/sounds/effects/orbult.wav"
## ~50% linear amplitude (−6 dB); kept slightly hotter so it reads in mix after 3D falloff.
const ORB_SHOOT_SFX_DB: float = 0.0
const ORB_ULT_SFX_DB: float = -6.02
const ORB_ULT_FADE_OUT_SEC: float = 0.45
const RELOAD_MISSILE_STREAM_PATH := "res://assets/sounds/effects/reload2.wav"
const RELOAD_SNIPER_STREAM_PATH := "res://assets/sounds/effects/reload.wav"
const RELOAD_EXPLOSIVE_STREAM_PATH := "res://assets/sounds/effects/reloadheavy.wav"
const RELOAD_SFX_DB: float = -18.0

var move_speed: float = 10.0
var jump_velocity: float = 9.0
var gravity: float = 28.0
@export var max_health: int = 250
var health: int = 250
## -1 means infinite (no magazine). Otherwise current rounds in primary clip when using a hero with `magazine_size` >= 0.
var magazine_current: int = -1
var magazine_max_clip: int = 0
## Current ultimate charge points; percent is computed from `ultimate_cost`.
var ultimate_charge: float = 0.0
var ultimate_cost: float = DEFAULT_ULTIMATE_COST
var ultimate_active: bool = false
var ultimate_duration_sec: float = 0.0
var ultimate_remaining_sec: float = 0.0
## Indices match HUD slots left → right (same order as each hero’s `hud_ability_*` arrays).
var hud_ability_cd_remaining: Array[float] = [0.0, 0.0, 0.0]
var weaponNum: int = 1
@export var team_id: int = 0 # 0 = Team A, 1 = Team B
@export var hero_id: String = "dps_missile"
@export var player_username: String = ""
var is_dead: bool = false
## Fractional carry for spawn-room passive heal (authority only).
var _spawn_room_heal_carry: float = 0.0
var _footstep_player: AudioStreamPlayer3D = null
var _footstep_streams: Array[AudioStream] = []
var _footstep_cooldown_left: float = 0.0
var _footstep_move_hold_sec: float = 0.0
var _footstep_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _body_shoot_hold_left: float = 0.0
var _remote_prev_anim_pos: Vector3 = Vector3.ZERO
var _remote_anim_pos_valid: bool = false
var _remote_anim_speed_smooth: float = 0.0
var _remote_anim_move_hold_left: float = 0.0
var _remote_anim_is_moving: bool = false
var _missile_fly_player: AudioStreamPlayer3D = null
var _missile_ult_player: AudioStreamPlayer3D = null
var _missile_single_shot_player: AudioStreamPlayer3D = null
var _missile_fly_streams: Array[AudioStream] = []
var _missile_ult_stream: AudioStream = null
var _missile_single_shot_stream: AudioStream = null
var _tank_ult_stream: AudioStream = null
var _missile_explosion_sfx_pool: Array[AudioStream] = [Explosion2Sfx, Explosion3Sfx]
var _tank_ult_player: AudioStreamPlayer3D = null
var _medic_healgun_player: AudioStreamPlayer3D = null
var _medic_pulse_fire_player: AudioStreamPlayer3D = null
var _medic_healgun_stream: AudioStream = null
var _medic_pulse_fire_stream: AudioStream = null
var _healing_received_player: AudioStreamPlayer = null
var _healing_received_stream: AudioStream = null
var _healing_received_last_event_sec: float = -99999.0
var _healing_received_last_sound_sec: float = -99999.0
var _orb_shoot_player: AudioStreamPlayer3D = null
var _orb_ult_player: AudioStreamPlayer3D = null
var _orb_shoot_stream: AudioStream = null
var _orb_ult_stream: AudioStream = null
var _orb_ult_fade_tween: Tween = null

var _continuous_laser: Node3D = null
var _laser_shield: LaserShield = null
var _continuous_heal_beam: Node3D = null
var _tank_laser_fire_active: bool = false
var _tank_laser_shield_up: bool = false
var tank_laser_shield_health_pct: float = 100.0
var tank_laser_shield_ui_active: bool = false
var _tank_laser_ult_push_accum: float = 0.0
var _tank_laser_ult_vfx: Node3D = null
var _tank_laser_ult_vfx_scale_tween: Tween = null
var _tank_laser_ult_vfx_shrink_out_active: bool = false
var _medic_beam_fire_active: bool = false
var _medic_beam_toggle_want: bool = false
var _medic_beam_heal_tick_accum: float = 0.0
var _medic_beam_net_sync_accum: float = 0.0
## Latest net snapshot for this pawn’s heal beam (other clients): refreshed ~20Hz, drawn every physics frame.
var _net_medic_beam_replica_active: bool = false
var _net_medic_beam_snap_start: Vector3 = Vector3.ZERO
var _net_medic_beam_snap_end: Vector3 = Vector3.ZERO
var _net_medic_beam_snap_fwd: Vector3 = Vector3(0, 0, -1)
var _laser_net_sync_accum: float = 0.0
var _laser_tick_accum: float = 0.0
var _tank_laser_release_cooldown_left: float = 0.0
var _tank_laser_pitch_hold_sec: float = 0.0
var _laser_once_stream: AudioStream = null
var _laser_damage_tick_player: AudioStreamPlayer3D = null
var _laser_shield_aura_player: AudioStreamPlayer3D = null
var _laser_shield_aura_stream: AudioStream = null
var _last_hero_id_for_stats: String = ""
var _missile_fire_cooldown: float = 0.0
var _missile_ability_cooldown_left: float = 0.0
var _missile_targeting_hold_active: bool = false
var _missile_targeting_preview: Node3D = null
var _missile_windup_active: bool = false
var _missile_windup_marker: Node3D = null
var _missile_shoot_lock_left: float = 0.0
var missile_targeting_ui_active: bool = false
var _missile_ult_hover_active: bool = false
var _missile_ult_hover_target_y: float = 0.0
var _missile_ult_arm_delay_left: float = 0.0
var _missile_ult_has_fired: bool = false
var _missile_ult_preview_markers: Array[Node3D] = []
var _missile_ult_preview_net_sync_accum: float = 0.0
var _sniper_fire_cooldown: float = 0.0
var _sniper_reload_left: float = 0.0
var _sniper_is_reloading: bool = false
var _sniper_ult_windup_left: float = 0.0
var _sniper_ult_primary_lock_left: float = 0.0
var _sniper_ult_linger_left: float = 0.0
var _sniper_ult_linger_xf: Transform3D = Transform3D.IDENTITY
var _sniper_ult_linger_len: float = 0.0
var _sniper_ult_linger_burst_ids: Dictionary = {}
var _sniper_ult_linger_done_ids: Dictionary = {}
var _sniper_shot_stream: AudioStream = null
var _sniper_shot_player: AudioStreamPlayer3D = null
var _sniper_smoke_prime_stream: AudioStream = null
var _sniper_smoke_prime_player: AudioStreamPlayer3D = null
var _reload_missile_stream: AudioStream = null
var _reload_sniper_stream: AudioStream = null
var _reload_explosive_stream: AudioStream = null
var _reload_player: AudioStreamPlayer3D = null
var _sniper_ult_hit_stream: AudioStream = null
var _sniper_ult_hit_player: AudioStreamPlayer = null
var _spring_is_charging: bool = false
var _spring_charge_sec: float = 0.0
var _spring_jump_charging: bool = false
var _spring_jump_charge_sec: float = 0.0
var _spring_punch_cooldown_left: float = 0.0
var _spring_ult_hover_active: bool = false
var _spring_ult_hover_target_y: float = 0.0
var _spring_ult_target_preview: Node3D = null
var _spring_ult_target_point: Vector3 = Vector3.ZERO
var _spring_ult_target_normal: Vector3 = Vector3.UP
var _spring_ult_last_valid_target_data: Dictionary = {}
var _spring_ult_launch_active: bool = false
var _spring_ult_has_launched: bool = false
var _orb_dash_active: bool = false
var _orb_dash_time_left: float = 0.0
var _orb_dash_velocity_xz: Vector3 = Vector3.ZERO
var _orb_primary_fire_cooldown_left: float = 0.0
var _orb_ult_orbit_active: bool = false
var _orb_ult_orbit_angle: float = 0.0
var _orb_ult_base_dirs: Array[Vector3] = []
var _orb_ult_visual_orbs: Array[Node3D] = []
var _respawn_invulnerable_until_msec: int = 0
## Heroes with `magazine_reload_seconds` >= 0 (timed magazine refill; see `_try_reload_magazine`).
var _timed_mag_reload_remaining: float = 0.0
var _timed_mag_reload_active: bool = false
## First airborne frame after leaving ground: snapshot horizontal speed cap and jump-forward (XZ).
var _air_momentum_floor_prev: bool = true
var _jump_takeoff_h_cap: float = 0.0
var _jump_takeoff_forward_xz: Vector3 = Vector3.FORWARD
var _jump_body_phase: int = _JUMP_BODY_PHASE_NONE
var _jump_slide_was_on_floor: bool = true
var _jump_trees_suppressed_for_body_anim: bool = false
var _jump_fallback_id: int = 0
## Lower-body jump clips in-tree; upper body stays on walk pose while airborne (shoot OneShot still stacks).
var _layered_jump_anim_node_body: AnimationNodeAnimation = null
var _layered_jump_anim_node_shadow: AnimationNodeAnimation = null
var _gdsync_transform_accum: float = 0.0
## Max rate we *consider* sending (actual sends may be less if idle).
const GDSYNC_TRANSFORM_INTERVAL := 1.0 / 24.0
## Always send at least this often so remotes don’t stall when standing still.
const GDSYNC_SEND_FORCE_INTERVAL := 0.18
const GDSYNC_SEND_POS_EPSILON2 := 0.035 * 0.035
const GDSYNC_SEND_ROT_EPSILON := 0.04
const GDSYNC_SEND_PITCH_EPSILON := 0.04
const GDSYNC_SEND_VEL_EPSILON2 := 0.35 * 0.35
var _gdsync_last_sent_pos: Vector3 = Vector3.ZERO
var _gdsync_last_sent_rot_y: float = 0.0
var _gdsync_last_sent_pitch_x: float = 0.0
var _gdsync_last_sent_vel: Vector3 = Vector3.ZERO
var _gdsync_has_sent_pose: bool = false
var _gdsync_time_since_send: float = 0.0
## Remote copies: follow network targets with exponential smoothing (reduces cloud relay jitter).
var _gdsync_remote_has_snapshot: bool = false
var _gdsync_remote_target_pos: Vector3 = Vector3.ZERO
var _gdsync_remote_target_rot_y: float = 0.0
var _gdsync_remote_target_pitch_x: float = 0.0
var _gdsync_remote_target_vel: Vector3 = Vector3.ZERO
const GDSYNC_REMOTE_SMOOTH_SPEED := 15.0
const GDSYNC_SNAP_TELEPORT_DIST2 := 20.0 # 4.5m+ → snap (respawn / big correction)

func _local_authority() -> bool:
	if HeroNet.is_gdsync():
		return HeroNet.controls_local_pawn(self)
	if multiplayer.multiplayer_peer == null:
		return true
	return is_multiplayer_authority()

func _rpc_play_shoot_effects_for_all() -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "play_shoot_effects"), [])
	else:
		play_shoot_effects.rpc()


func _broadcast_jump_body_takeoff_for_all() -> void:
	if not _local_authority():
		return
	if not _player_has_full_jump_body_clip_set():
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_apply_jump_body_takeoff_visual"), [])
	else:
		_net_apply_jump_body_takeoff.rpc()


func _broadcast_jump_body_landing_for_all() -> void:
	if not _local_authority():
		return
	if not _player_has_full_jump_body_clip_set():
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_apply_jump_body_landing_visual"), [])
	else:
		_net_apply_jump_body_landing.rpc()


@rpc("call_local")
func _net_apply_jump_body_takeoff() -> void:
	_apply_jump_body_takeoff_visual()


@rpc("call_local")
func _net_apply_jump_body_landing() -> void:
	_apply_jump_body_landing_visual()


func _rpc_spawn_heal_orb_all(origin: Vector3, direction: Vector3, shooter_peer_id: int, exempt_from_orb_cap: bool = false) -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_spawn_heal_orb"), [origin, direction, shooter_peer_id, exempt_from_orb_cap])
	else:
		_spawn_heal_orb.rpc(origin, direction, shooter_peer_id, exempt_from_orb_cap)

func _rpc_spawn_tank_round_all(origin: Vector3, direction: Vector3, shooter_peer_id: int, shell_kind: int = 0) -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_spawn_tank_round"), [origin, direction, shooter_peer_id, shell_kind])
	else:
		_spawn_tank_round.rpc(origin, direction, shooter_peer_id, shell_kind)


func _rpc_spawn_landmine_all(origin: Vector3, direction: Vector3, shooter_peer_id: int) -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_spawn_landmine"), [origin, direction, shooter_peer_id])
	else:
		_spawn_landmine.rpc(origin, direction, shooter_peer_id)


func _rpc_spawn_smoke_bomb_all(origin: Vector3, velocity: Vector3, shooter_peer_id: int) -> void:
	var w: Node = get_parent()
	if w == null:
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(w, "spawn_smoke_bomb_at"), [origin, velocity, shooter_peer_id])
	elif multiplayer.multiplayer_peer == null:
		if w.has_method("spawn_smoke_bomb_at"):
			w.spawn_smoke_bomb_at(origin, velocity, shooter_peer_id)
	else:
		_net_spawn_smoke_bomb_world.rpc(origin, velocity, shooter_peer_id)

func _rpc_spawn_medic_burst_all(origin: Vector3, direction: Vector3, shooter_peer_id: int) -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_spawn_medic_burst"), [origin, direction, shooter_peer_id])
	else:
		_spawn_medic_burst.rpc(origin, direction, shooter_peer_id)

func _maybe_push_gdsync_transform(delta: float) -> void:
	if not HeroNet.is_gdsync():
		return
	if not _local_authority() or is_dead:
		return
	_gdsync_transform_accum += delta
	_gdsync_time_since_send += delta
	if _gdsync_transform_accum < GDSYNC_TRANSFORM_INTERVAL:
		return
	_gdsync_transform_accum -= GDSYNC_TRANSFORM_INTERVAL
	var w: Node = get_parent()
	if w == null or not w.has_method("gdsync_apply_player_state"):
		return
	var pos: Vector3 = global_position
	var rot_y: float = rotation.y
	var pitch_x: float = camera.rotation.x
	var vel: Vector3 = velocity
	var should_send: bool = not _gdsync_has_sent_pose
	if not should_send:
		if pos.distance_squared_to(_gdsync_last_sent_pos) > GDSYNC_SEND_POS_EPSILON2:
			should_send = true
		if absf(angle_difference(_gdsync_last_sent_rot_y, rot_y)) > GDSYNC_SEND_ROT_EPSILON:
			should_send = true
		if absf(_gdsync_last_sent_pitch_x - pitch_x) > GDSYNC_SEND_PITCH_EPSILON:
			should_send = true
		if vel.distance_squared_to(_gdsync_last_sent_vel) > GDSYNC_SEND_VEL_EPSILON2:
			should_send = true
	if not should_send and _gdsync_time_since_send < GDSYNC_SEND_FORCE_INTERVAL:
		return
	_gdsync_last_sent_pos = pos
	_gdsync_last_sent_rot_y = rot_y
	_gdsync_last_sent_pitch_x = pitch_x
	_gdsync_last_sent_vel = vel
	_gdsync_has_sent_pose = true
	_gdsync_time_since_send = 0.0
	GDSync.call_func_unreliable(Callable(w, "gdsync_apply_player_state"), [HeroNet.my_id(), pos, rot_y, pitch_x, vel])


func gdsync_receive_remote_snapshot(pos: Vector3, rot_y: float, pitch_x: float, vel: Vector3) -> void:
	if _local_authority():
		return
	var pitch_clamped: float = clampf(pitch_x, -PI * 0.5, PI * 0.5)
	var d2: float = global_position.distance_squared_to(pos)
	if not _gdsync_remote_has_snapshot or d2 > GDSYNC_SNAP_TELEPORT_DIST2:
		global_position = pos
		rotation.y = rot_y
		camera.rotation.x = pitch_clamped
		velocity = vel
	_gdsync_remote_target_pos = pos
	_gdsync_remote_target_rot_y = rot_y
	_gdsync_remote_target_pitch_x = pitch_clamped
	_gdsync_remote_target_vel = vel
	_gdsync_remote_has_snapshot = true


func _gdsync_smooth_remote_motion(delta: float) -> void:
	if not _gdsync_remote_has_snapshot:
		return
	var k: float = 1.0 - exp(-GDSYNC_REMOTE_SMOOTH_SPEED * delta)
	global_position = global_position.lerp(_gdsync_remote_target_pos, k)
	rotation.y = lerp_angle(rotation.y, _gdsync_remote_target_rot_y, k)
	camera.rotation.x = lerp_angle(camera.rotation.x, _gdsync_remote_target_pitch_x, k)
	velocity = velocity.lerp(_gdsync_remote_target_vel, k)

func _enter_tree():
	if not HeroNet.is_gdsync():
		set_multiplayer_authority(str(name).to_int())

func _ready():
	_default_camera_cull_mask = camera.cull_mask
	_tp_muzzle_effects_anchor = Node3D.new()
	_tp_muzzle_effects_anchor.name = "TPMuzzleEffectsAnchor"
	add_child(_tp_muzzle_effects_anchor)
	_apply_hero_stats()
	_footstep_rng.randomize()
	_init_footstep_audio()
	_init_missile_audio()
	_init_tank_audio()
	_init_medic_audio()
	_init_healing_received_audio()
	_init_orb_audio()
	_init_laser_once_audio()
	_init_laser_shield_aura_audio()
	_init_sniper_audio()
	_init_reload_audio()
	if not _local_authority():
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true
	if third_person_camera != null:
		third_person_camera.current = false
		third_person_camera.fov = camera.fov
		third_person_camera.near = 0.05
	_sync_camera_mode_from_game_state()
	_update_camera_mode_visuals()
	if raycast != null:
		raycast.collision_mask = COLLISION_MASK_WORLD_PLAYER_SHIELD


func _process(_delta: float) -> void:
	## Waist twist + head look after AnimationMixer (`call_deferred` keeps pose read/write order stable).
	call_deferred(&"_apply_imported_character_visual_offsets")
	if _local_authority():
		return
	_apply_enemy_outline_overlay()


func _enemy_outline_should_show() -> bool:
	if is_dead:
		return false
	var world: Node = get_parent()
	if world == null:
		return false
	return int(team_id) != int(world.local_team_id)


func _enemy_outline_collect_mesh_instances(out: Array[MeshInstance3D]) -> void:
	out.clear()
	if body_mesh_placeholder != null:
		out.append(body_mesh_placeholder)
	if character_model_root != null:
		for mi in character_model_root.find_children("*", "MeshInstance3D", true, false):
			out.append(mi)


func _apply_enemy_outline_overlay() -> void:
	var show_outline: bool = _enemy_outline_should_show()
	var mat: Material = EnemyOutlineShaderMaterial if show_outline else null
	var meshes: Array[MeshInstance3D] = []
	_enemy_outline_collect_mesh_instances(meshes)
	for mi in meshes:
		mi.material_overlay = mat


func _spring_punch_facing_dir() -> Vector3:
	return _medic_beam_view_forward()


func _spring_punch_start_pos(facing_dir: Vector3) -> Vector3:
	var d: Vector3 = facing_dir.normalized()
	return global_position + Vector3(0.0, MEDIC_BEAM_TARGET_Y_OFFSET, 0.0) + d * SPRING_PUNCH_SURFACE_FORWARD_OFFSET


func _spring_punch_length_from_charge_sec(charge_sec: float) -> float:
	var t: float = clampf(charge_sec / SPRING_PUNCH_MAX_CHARGE_SEC, 0.0, 1.0)
	return lerpf(SPRING_PUNCH_MIN_LENGTH, SPRING_PUNCH_MAX_LENGTH, t)


func _spring_cylinder_transform(start: Vector3, aim_dir: Vector3, length: float) -> Transform3D:
	var d: Vector3 = aim_dir.normalized()
	var x_axis: Vector3 = Vector3.UP.cross(d)
	if x_axis.length_squared() < 1e-8:
		x_axis = Vector3.RIGHT.cross(d)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(d).normalized()
	var center: Vector3 = start + d * (length * 0.5)
	return Transform3D(Basis(x_axis, d, z_axis), center)


func _spring_punch_clamp_length_to_terrain(start: Vector3, aim_dir: Vector3, max_length: float) -> float:
	if max_length <= 0.001:
		return max_length
	var d: Vector3 = aim_dir.normalized()
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	# Trace from inside/near the body through the punch so the first solid hit is found even when
	# `start` is flush with or slightly past the wall.
	var ray_from: Vector3 = start - d * SPRING_PUNCH_TERRAIN_RAY_BACKTRACE
	var ray_to: Vector3 = start + d * max_length
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	# All physics layers except characters (punch passes through players).
	query.collision_mask = 0xFFFFFFFF & ~PLAYER_PHYSICS_LAYER
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return max_length
	var hit_pos: Vector3 = hit["position"] as Vector3
	# Signed distance along punch from `start` to the wall contact (negative if hit is behind start).
	var along: float = (hit_pos - start).dot(d)
	# Pull the axis back so the cylinder radius does not stick through the plane (uses face normal).
	var nvar: Variant = hit.get("normal", Vector3.ZERO)
	if nvar is Vector3:
		var hn: Vector3 = (nvar as Vector3).normalized()
		var nd: float = absf(hn.dot(d))
		var radius_pull: float = SPRING_PUNCH_RADIUS / maxf(nd, 0.22)
		along -= radius_pull
	along -= SPRING_PUNCH_WALL_STOP_EPSILON
	return clampf(along, 0.02, max_length)


func _spring_cancel_charge() -> void:
	_spring_is_charging = false
	_spring_charge_sec = 0.0


func _spring_cancel_jump_charge() -> void:
	_spring_jump_charging = false
	_spring_jump_charge_sec = 0.0


func _spring_begin_jump_charge() -> void:
	if hero_id != "dps_spring":
		return
	if is_dead or _pawn_soft_lock() or not is_on_floor():
		return
	_spring_jump_charging = true
	_spring_jump_charge_sec = 0.0


func _spring_jump_velocity_from_charge_sec(charge_sec: float) -> float:
	var t: float = clampf(charge_sec / SPRING_PUNCH_MAX_CHARGE_SEC, 0.0, 1.0)
	var mult: float = lerpf(SPRING_JUMP_VEL_MIN_MULT, SPRING_JUMP_VEL_MAX_MULT, t)
	return jump_velocity * mult


func _jump_air_begin_takeoff_snapshot(eff_move_speed_ref: float) -> void:
	var hx: float = velocity.x
	var hz: float = velocity.z
	var sp: float = hx * hx + hz * hz
	_jump_takeoff_h_cap = sqrt(sp)
	if _jump_takeoff_h_cap > 1e-4:
		_jump_takeoff_forward_xz = Vector3(hx, 0.0, hz) / _jump_takeoff_h_cap
	else:
		var bf := Vector3(-transform.basis.z.x, 0.0, -transform.basis.z.z)
		if bf.length_squared() > 1e-8:
			_jump_takeoff_forward_xz = bf.normalized()
		else:
			_jump_takeoff_forward_xz = Vector3.FORWARD
		_jump_takeoff_h_cap = clampf(eff_move_speed_ref * 0.22, 0.4, eff_move_speed_ref)


func _spring_update_jump_charge(delta: float) -> void:
	if not _local_authority():
		return
	if hero_id != "dps_spring":
		if _spring_jump_charging:
			_spring_cancel_jump_charge()
		return
	if is_dead or _pawn_soft_lock():
		if _spring_jump_charging:
			_spring_cancel_jump_charge()
		return
	if not _spring_jump_charging:
		return
	if not is_on_floor():
		_spring_cancel_jump_charge()
		return
	_spring_jump_charge_sec = minf(_spring_jump_charge_sec + delta, SPRING_PUNCH_MAX_CHARGE_SEC)
	if Input.is_action_just_released("jump"):
		velocity.y = _spring_jump_velocity_from_charge_sec(_spring_jump_charge_sec)
		_spring_cancel_jump_charge()


func _spring_try_begin_charge() -> void:
	if hero_id != "dps_spring" or weaponNum != 1:
		return
	if is_dead or _pawn_soft_lock():
		return
	# Cooldown only blocks firing on release — you may still charge during the wait.
	_spring_is_charging = true
	_spring_charge_sec = 0.0


func _spring_update_punch_charge(delta: float) -> void:
	if not _local_authority():
		return
	if hero_id != "dps_spring" or weaponNum != 1:
		if _spring_is_charging:
			_spring_cancel_charge()
		_spring_punch_cooldown_left = 0.0
		return
	if is_dead or _pawn_soft_lock():
		if _spring_is_charging:
			_spring_cancel_charge()
		return
	if ultimate_active:
		if _spring_is_charging:
			_spring_cancel_charge()
		return
	_spring_punch_cooldown_left = maxf(0.0, _spring_punch_cooldown_left - delta)
	if not _spring_is_charging:
		return
	_spring_charge_sec = minf(_spring_charge_sec + delta, SPRING_PUNCH_MAX_CHARGE_SEC)
	if Input.is_action_just_released("shoot"):
		if _spring_punch_cooldown_left <= 0.0:
			var plen: float = _spring_punch_length_from_charge_sec(_spring_charge_sec)
			_spring_release_punch(plen)
			_spring_punch_cooldown_left = SPRING_PUNCH_MIN_INTERVAL_SEC
		_spring_cancel_charge()


func _spring_release_punch(length: float) -> void:
	var dir: Vector3 = _spring_punch_facing_dir()
	var start: Vector3 = _spring_punch_start_pos(dir)
	var use_len: float = _spring_punch_clamp_length_to_terrain(start, dir, length)
	var xf: Transform3D = _spring_cylinder_transform(start, dir, use_len)
	var bodies: Array = SplashOverlap.character_bodies_in_cylinder(
		get_world_3d(),
		xf,
		use_len,
		SPRING_PUNCH_RADIUS,
		PLAYER_PHYSICS_LAYER,
		[get_rid()]
	)
	var w: Node = get_parent()
	for body in bodies:
		if body == self:
			continue
		if body.get("is_dead") == true:
			continue
		var target_team: Variant = body.get("team_id")
		if typeof(target_team) != TYPE_INT or int(target_team) == team_id:
			continue
		HeroNet.apply_damage_on_victim(body, SPRING_PUNCH_DAMAGE, name.to_int())
		if w != null and w.has_method("record_damaged_by_me"):
			w.record_damaged_by_me(body.name.to_int())
	_rpc_play_shoot_effects_for_all()
	_rpc_spring_punch_vfx_all(xf.origin, dir, use_len)


func _rpc_spring_punch_vfx_all(center: Vector3, dir: Vector3, length: float) -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_spring_punch_spawn_world_vfx"), [center, dir, length])
	else:
		_spring_punch_spawn_world_vfx.rpc(center, dir, length)


@rpc("any_peer", "reliable", "call_local")
func _spring_punch_spawn_world_vfx(center: Vector3, dir: Vector3, length: float) -> void:
	var fx := MeshInstance3D.new()
	fx.name = "SpringPunchVfx"
	var cyl := CylinderMesh.new()
	cyl.height = length
	cyl.top_radius = SPRING_PUNCH_RADIUS
	cyl.bottom_radius = SPRING_PUNCH_RADIUS
	fx.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.28, 0.62, 1.0, 0.42)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fx.material_override = mat
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var d: Vector3 = dir.normalized()
	var x_axis: Vector3 = Vector3.UP.cross(d)
	if x_axis.length_squared() < 1e-8:
		x_axis = Vector3.RIGHT.cross(d)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(d).normalized()
	# Mesh height is `length`; unit basis only — no transform scale (avoids distorted radius vs charge).
	var unit_basis: Basis = Basis(x_axis, d, z_axis)
	add_child(fx)
	# Parented to the puncher so translation/rotation during the flash follows the body.
	fx.global_transform = Transform3D(unit_basis, center)
	var tw: SceneTreeTimer = get_tree().create_timer(SPRING_PUNCH_VFX_DURATION)
	tw.timeout.connect(
		func() -> void:
			if is_instance_valid(fx):
				fx.queue_free()
	)

func _character_select_open() -> bool:
	var w: Node = get_parent()
	return w != null and w.has_method("is_character_select_open") and w.is_character_select_open()


func _world_match_input_locked() -> bool:
	var w: Node = get_parent()
	return w != null and w.has_method("is_match_input_locked") and w.is_match_input_locked()


func _world_match_rules_actual() -> bool:
	var w: Node = get_parent()
	return w != null and bool(w.get("match_rules_actual"))


func _pawn_soft_lock() -> bool:
	return _character_select_open() or _world_match_input_locked()


func _hero_archetype() -> String:
	var hero: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero != null and hero.archetype_id != "":
		return hero.archetype_id
	return hero_id


func _hud_resolved_actions_for_me() -> PackedStringArray:
	var h: HeroResource = HeroesRegistry.get_hero(hero_id)
	if h == null or h.hud_ability_actions.is_empty():
		return PackedStringArray(["weapon1", "weapon2", "secondary"])
	var out := PackedStringArray()
	var custom: PackedStringArray = h.hud_ability_actions
	for i in range(3):
		out.append(custom[i] if i < custom.size() else "")
	return out


func _hud_slot_index_for_action(action: String) -> int:
	var ra: PackedStringArray = _hud_resolved_actions_for_me()
	for i in range(mini(ra.size(), 3)):
		if str(ra[i]) == action:
			return i
	return -1


func _get_hud_slot_cooldown_duration(slot_idx: int) -> float:
	var h: HeroResource = HeroesRegistry.get_hero(hero_id)
	if h == null or slot_idx < 0:
		return 0.0
	if slot_idx >= h.hud_ability_cooldown_seconds.size():
		return 0.0
	return float(h.hud_ability_cooldown_seconds[slot_idx])


func _tick_hud_ability_cooldowns(delta: float) -> void:
	for i in range(mini(3, hud_ability_cd_remaining.size())):
		hud_ability_cd_remaining[i] = maxf(0.0, hud_ability_cd_remaining[i] - delta)


func _player_uses_imported_character_model() -> bool:
	return character_model_root != null and character_model_root.get_child_count() > 0


func _find_first_animation_player(p: Node) -> AnimationPlayer:
	if p is AnimationPlayer:
		return p as AnimationPlayer
	for c in p.get_children():
		var found: AnimationPlayer = _find_first_animation_player(c)
		if found != null:
			return found
	return null


## Prefer the AnimationPlayer that drives the rig (sibling of `Skeleton3D` is typical for GLTF). Avoids picking a weapon/auxiliary player when the `.glb` has several.
func _find_body_animation_player(import_root: Node) -> AnimationPlayer:
	var skeletons: Array[Node] = import_root.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skel: Node = skeletons[0]
		var parent: Node = skel.get_parent()
		if parent != null:
			for c in parent.get_children():
				if c is AnimationPlayer:
					return c as AnimationPlayer
	var aps: Array[Node] = import_root.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return null
	if aps.size() == 1:
		return aps[0] as AnimationPlayer
	var best: AnimationPlayer = null
	var best_count: int = -1
	for ap_node in aps:
		var ap: AnimationPlayer = ap_node as AnimationPlayer
		var n: int = ap.get_animation_list().size()
		if n > best_count:
			best_count = n
			best = ap
	return best


func _resolve_body_anim_library_source_scene_path(hero: HeroResource) -> String:
	if hero == null:
		return ""
	var ref_id: String = hero.body_anim_library_source_hero_id.strip_edges()
	if not ref_id.is_empty():
		var src_hero: HeroResource = HeroesRegistry.get_hero(ref_id)
		if src_hero == null:
			push_warning("body_anim_library_source_hero_id unknown hero: %s" % ref_id)
		else:
			var ref_path: String = src_hero.model_scene_path.strip_edges()
			if not ref_path.is_empty() and ResourceLoader.exists(ref_path):
				return ref_path
			push_warning("Hero %s has no valid model_scene_path for animation library copy" % ref_id)
	return hero.body_anim_library_source_path.strip_edges()


func _remove_animation_named_from_player(ap: AnimationPlayer, clip_name: StringName) -> void:
	if ap == null:
		return
	for lib_name in ap.get_animation_library_list():
		var lib: AnimationLibrary = ap.get_animation_library(lib_name)
		if lib != null and lib.has_animation(clip_name):
			lib.remove_animation(clip_name)


func _merge_body_anim_external_resources(ap: AnimationPlayer, hero: HeroResource) -> void:
	if ap == null or hero == null:
		return
	var d: Dictionary = hero.body_anim_external_resources
	if d.is_empty():
		return
	if not ap.has_animation_library(&""):
		ap.add_animation_library(&"", AnimationLibrary.new())
	var lib0: AnimationLibrary = ap.get_animation_library(&"")
	if lib0 == null:
		return
	for clip_key in d.keys():
		var path_val: Variant = d[clip_key]
		if typeof(path_val) != TYPE_STRING:
			continue
		var path: String = String(path_val).strip_edges()
		if path.is_empty() or not ResourceLoader.exists(path):
			push_warning("body_anim_external_resources missing or invalid path for '%s': %s" % [str(clip_key), path])
			continue
		var res: Resource = load(path)
		if res == null or not (res is Animation):
			push_warning("body_anim_external_resources is not an Animation resource: %s" % path)
			continue
		var clip_name: StringName = StringName(str(clip_key))
		_remove_animation_named_from_player(ap, clip_name)
		lib0.add_animation(clip_name, (res as Animation).duplicate())


func _inject_body_anim_libraries_from_source_scene(source_scene_path: String, target_ap: AnimationPlayer) -> void:
	if target_ap == null:
		return
	var trimmed: String = source_scene_path.strip_edges()
	if trimmed.is_empty():
		return
	if not ResourceLoader.exists(trimmed):
		push_warning("body_anim_library_source_path missing: %s" % trimmed)
		return
	var ps: PackedScene = load(trimmed) as PackedScene
	if ps == null:
		push_warning("Could not load body anim library scene: %s" % trimmed)
		return
	var src_root: Node = ps.instantiate()
	var src_ap: AnimationPlayer = _find_body_animation_player(src_root)
	if src_ap == null:
		src_ap = _find_first_animation_player(src_root)
	if src_ap == null:
		push_warning("No AnimationPlayer under body anim source: %s" % trimmed)
		src_root.queue_free()
		return
	## Short names (lowercase) present on the source rig — used to keep target-only clips (e.g. `Sniper_shoot` on sniper .glb) when pulling locomotion from another asset.
	var source_short_lower: Dictionary = {}
	for full in src_ap.get_animation_list():
		var s: String = String(full)
		if s.contains("/"):
			s = s.get_slice("/", 1)
		source_short_lower[s.to_lower()] = true
	var preserved: Dictionary = {}
	for full in target_ap.get_animation_list():
		var anim: Animation = target_ap.get_animation(full)
		if anim == null:
			continue
		var s2: String = String(full)
		if s2.contains("/"):
			s2 = s2.get_slice("/", 1)
		if not source_short_lower.has(s2.to_lower()):
			preserved[StringName(s2)] = anim.duplicate()
	var libs_out: Dictionary = {}
	for ln in src_ap.get_animation_library_list():
		var lib: AnimationLibrary = src_ap.get_animation_library(ln)
		if lib != null:
			libs_out[ln] = lib.duplicate(true)
	if libs_out.is_empty():
		var fallback_lib := AnimationLibrary.new()
		for full_name in src_ap.get_animation_list():
			var an: Animation = src_ap.get_animation(full_name)
			if an == null:
				continue
			var store_name: StringName = full_name
			var fs: String = String(full_name)
			if fs.contains("/"):
				store_name = StringName(fs.get_slice("/", 1))
			fallback_lib.add_animation(store_name, an.duplicate())
		if not fallback_lib.get_animation_list().is_empty():
			libs_out[&""] = fallback_lib
	if libs_out.is_empty():
		push_warning("Body anim source had no animation libraries or clips: %s" % trimmed)
		src_root.queue_free()
		return
	var existing_libs: Array[StringName] = []
	for ln in target_ap.get_animation_library_list():
		existing_libs.append(ln)
	for ln in existing_libs:
		target_ap.remove_animation_library(ln)
	for ln in libs_out.keys():
		target_ap.add_animation_library(ln, libs_out[ln])
	if not preserved.is_empty():
		if not target_ap.has_animation_library(&""):
			target_ap.add_animation_library(&"", AnimationLibrary.new())
		var def_lib: AnimationLibrary = target_ap.get_animation_library(&"")
		if def_lib != null:
			for sn_key in preserved.keys():
				if not def_lib.has_animation(sn_key):
					def_lib.add_animation(sn_key, preserved[sn_key])
	src_root.queue_free()


func _apply_body_locomotion_loop_modes(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	for wa in [&"idle", &"move", &"shoot"]:
		var c: StringName = _resolve_playable_anim_name(ap, wa)
		if c == StringName("") or not ap.has_animation(c):
			continue
		var anim_res: Animation = ap.get_animation(c)
		if anim_res == null:
			continue
		if String(wa) == "shoot":
			anim_res.loop_mode = Animation.LOOP_NONE
		else:
			anim_res.loop_mode = Animation.LOOP_LINEAR


func _reset_local_view_pitch_after_spawn_or_hero_change() -> void:
	if not _local_authority() or camera == null:
		return
	camera.rotation.x = 0.0


## When no AnimationTree, AnimationPlayer must still run before Player `_process` so head look reads this frame’s poses.
func _prioritize_imported_anim_players_if_no_layered_tree() -> void:
	if _hero_body_anim_world != null and not _hero_body_uses_layered_anim:
		_hero_body_anim_world.process_priority = BODY_ANIM_TREE_PROCESS_PRIORITY
	if _hero_shadow_anim != null and not _hero_shadow_uses_layered_anim:
		_hero_shadow_anim.process_priority = BODY_ANIM_TREE_PROCESS_PRIORITY


func _resolve_body_anim_name(weapon_anim: StringName) -> StringName:
	var h: HeroResource = HeroesRegistry.get_hero(hero_id)
	if h == null:
		return weapon_anim
	match String(weapon_anim):
		"idle":
			return StringName(h.body_anim_idle)
		"move":
			return StringName(h.body_anim_move)
		"shoot":
			return StringName(h.body_anim_shoot)
		_:
			return weapon_anim


func _find_anim_by_keywords(anim: AnimationPlayer, keywords: PackedStringArray) -> StringName:
	var available: PackedStringArray = anim.get_animation_list()
	for clip_name in available:
		var clip_lower: String = String(clip_name).to_lower()
		for kw in keywords:
			if clip_lower.find(String(kw).to_lower()) >= 0:
				return StringName(clip_name)
	return StringName("")


func _first_non_idle_anim(anim: AnimationPlayer) -> StringName:
	var available: PackedStringArray = anim.get_animation_list()
	for clip_name in available:
		var clip_lower: String = String(clip_name).to_lower()
		if clip_lower.find("idle") < 0 and clip_lower.find("rest") < 0 and clip_lower.find("tpose") < 0:
			return StringName(clip_name)
	if available.size() > 0:
		return StringName(available[0])
	return StringName("")


func _resolve_playable_anim_name(anim: AnimationPlayer, weapon_anim: StringName) -> StringName:
	var preferred: StringName = _resolve_body_anim_name(weapon_anim)
	if anim.has_animation(preferred):
		return preferred
	if preferred != StringName(""):
		for full in anim.get_animation_list():
			var short: String = String(full)
			if short.contains("/"):
				short = short.get_slice("/", 1)
			if short.to_lower() == String(preferred).to_lower():
				return StringName(full)
	match String(weapon_anim):
		"move":
			var by_keywords: StringName = _find_anim_by_keywords(anim, PackedStringArray(["walk", "run", "move"]))
			return by_keywords if by_keywords != StringName("") else _first_non_idle_anim(anim)
		"idle":
			var by_idle: StringName = _find_anim_by_keywords(anim, PackedStringArray(["idle", "rest"]))
			if by_idle != StringName(""):
				return by_idle
			## Do not use `_first_non_idle_anim` here — it often picks `walk_cycle`. Many GLBs list idle as the first clip.
			var list_idle: PackedStringArray = anim.get_animation_list()
			if list_idle.size() > 0:
				var first_clip: StringName = StringName(list_idle[0])
				if anim.has_animation(first_clip):
					return first_clip
			return StringName("")
		"shoot":
			var exact_names: PackedStringArray = PackedStringArray(["shot", "shot.", "Shoot", "shoot", "fire"])
			for en in exact_names:
				var sn := StringName(en)
				if anim.has_animation(sn):
					return sn
			var by_shoot: StringName = _find_anim_by_keywords(
				anim,
				PackedStringArray(["shot.", "shoot", "shot", "fire", "attack"])
			)
			return by_shoot if by_shoot != StringName("") else _first_non_idle_anim(anim)
		_:
			return StringName("")


func _hero_jump_anim_pref(which: String) -> String:
	var h: HeroResource = HeroesRegistry.get_hero(hero_id)
	if h == null:
		return ""
	match which:
		"start":
			return h.body_anim_jump_start
		"loop":
			return h.body_anim_jump_loop
		"land":
			return h.body_anim_jump_land
		_:
			return ""


func _resolve_playable_jump_anim_name(anim: AnimationPlayer, which: String) -> StringName:
	var pref_str: String = _hero_jump_anim_pref(which)
	var preferred: StringName = StringName(pref_str) if pref_str != "" else StringName("")
	if preferred != StringName("") and anim.has_animation(preferred):
		return preferred
	match which:
		"start":
			for cand in [&"jump", &"Jump"]:
				if anim.has_animation(cand):
					return cand
			var available_s: PackedStringArray = anim.get_animation_list()
			for clip_name in available_s:
				var sl := String(clip_name).to_lower()
				if sl.find("jump") >= 0 and sl.find("cycle") < 0 and sl.find("land") < 0:
					return StringName(clip_name)
			return StringName("")
		"loop":
			for cand in [&"jump_cycle", &"jump_Cycle", &"Jump_Cycle"]:
				if anim.has_animation(cand):
					return cand
			var by_loop: StringName = _find_anim_by_keywords(
				anim,
				PackedStringArray(["jump_cycle", "jump cycle"])
			)
			return by_loop
		"land":
			for cand in [&"jump_landing", &"jump_Landing", &"Jump_Landing"]:
				if anim.has_animation(cand):
					return cand
			var by_land: StringName = _find_anim_by_keywords(
				anim,
				PackedStringArray(["jump_landing", "jump landing", "landing"])
			)
			return by_land
		_:
			return StringName("")


func _apply_body_jump_clip_loop_modes(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	for which in [&"start", &"loop", &"land"]:
		var c: StringName = _resolve_playable_jump_anim_name(ap, String(which))
		if c == StringName("") or not ap.has_animation(c):
			continue
		var anim_res: Animation = ap.get_animation(c)
		if anim_res == null:
			continue
		if String(which) == "loop":
			anim_res.loop_mode = Animation.LOOP_LINEAR
		else:
			anim_res.loop_mode = Animation.LOOP_NONE


func _player_has_full_jump_body_clip_set() -> bool:
	if _hero_body_anim_world == null:
		return false
	var ap: AnimationPlayer = _hero_body_anim_world
	return (
		_resolve_playable_jump_anim_name(ap, "start") != StringName("")
		and _resolve_playable_jump_anim_name(ap, "loop") != StringName("")
		and _resolve_playable_jump_anim_name(ap, "land") != StringName("")
	)


func _layered_set_jump_blend_weight(w: float) -> void:
	if _hero_body_anim_tree != null and is_instance_valid(_hero_body_anim_tree) and _layered_jump_anim_node_body != null:
		_hero_body_anim_tree.set(&"parameters/jump_lower_blend/blend_amount", w)
	if _hero_shadow_anim_tree != null and is_instance_valid(_hero_shadow_anim_tree) and _layered_jump_anim_node_shadow != null:
		_hero_shadow_anim_tree.set(&"parameters/jump_lower_blend/blend_amount", w)


func _layered_seek_jump_clip_to_start() -> void:
	if not _layered_jump_blend_available():
		return
	if _hero_body_anim_tree != null and is_instance_valid(_hero_body_anim_tree):
		_hero_body_anim_tree.set(&"parameters/jump_time_seek/seek_request", 0.0)
	if _hero_shadow_anim_tree != null and is_instance_valid(_hero_shadow_anim_tree):
		_hero_shadow_anim_tree.set(&"parameters/jump_time_seek/seek_request", 0.0)


func _layered_set_jump_clip(clip: StringName) -> void:
	if clip == StringName(""):
		return
	var changed: bool = false
	if _layered_jump_anim_node_body != null and _layered_jump_anim_node_body.animation != clip:
		_layered_jump_anim_node_body.animation = clip
		changed = true
	if _layered_jump_anim_node_shadow != null and _layered_jump_anim_node_shadow.animation != clip:
		_layered_jump_anim_node_shadow.animation = clip
		changed = true
	if changed:
		_layered_seek_jump_clip_to_start()


func _layered_jump_blend_available() -> bool:
	return _layered_jump_anim_node_body != null


func _layered_apply_air_jump_walk_upper_pose() -> void:
	if not _layered_jump_blend_available():
		return
	if _jump_body_phase == _JUMP_BODY_PHASE_NONE:
		return
	if _hero_body_anim_tree != null and is_instance_valid(_hero_body_anim_tree):
		_hero_body_anim_tree.set(&"parameters/locomotion/blend_amount", 1.0)
	if _hero_shadow_anim_tree != null and is_instance_valid(_hero_shadow_anim_tree):
		_hero_shadow_anim_tree.set(&"parameters/locomotion/blend_amount", 1.0)


func _jump_anim_clip_length_sec(which: String) -> float:
	var ap: AnimationPlayer = _hero_body_anim_world
	if ap == null:
		return 0.35
	var cn: StringName = _resolve_playable_jump_anim_name(ap, which)
	if cn == StringName("") or not ap.has_animation(cn):
		return 0.35
	var ar: Animation = ap.get_animation(cn)
	if ar == null:
		return 0.35
	return maxf(ar.length, 0.05)


func _jump_fallback_invalidate() -> void:
	_jump_fallback_id += 1


func _jump_schedule_layered_phase_fallback(which_clip: String, required_phase: int, fn: Callable) -> void:
	if not _layered_jump_blend_available():
		return
	_jump_fallback_invalidate()
	var my_id: int = _jump_fallback_id
	var sec: float = _jump_anim_clip_length_sec(which_clip)
	get_tree().create_timer(sec).timeout.connect(func() -> void:
		if not is_instance_valid(self):
			return
		if my_id != _jump_fallback_id:
			return
		if _jump_body_phase != required_phase:
			return
		fn.call()
	)


func _set_body_jump_trees_suppressed(suppress: bool) -> void:
	if _layered_jump_anim_node_body != null:
		return
	if not _hero_body_uses_layered_anim:
		_jump_trees_suppressed_for_body_anim = false
		return
	if suppress:
		if _jump_trees_suppressed_for_body_anim:
			return
		if _hero_body_anim_tree != null:
			_hero_body_anim_tree.active = false
		if _hero_shadow_anim_tree != null:
			_hero_shadow_anim_tree.active = false
		_jump_trees_suppressed_for_body_anim = true
	else:
		if _hero_body_anim_tree != null:
			_hero_body_anim_tree.active = true
		if _hero_shadow_anim_tree != null:
			_hero_shadow_anim_tree.active = true
		_jump_trees_suppressed_for_body_anim = false


func _ensure_jump_body_anim_finished_connected() -> void:
	if _hero_body_anim_world == null:
		return
	if not _hero_body_anim_world.animation_finished.is_connected(_on_jump_body_anim_finished):
		_hero_body_anim_world.animation_finished.connect(_on_jump_body_anim_finished)


func _play_jump_clip_on_body_and_shadow(clip: StringName, speed_scale: float = 1.0) -> void:
	if clip == StringName(""):
		return
	if _hero_body_anim_world != null and _hero_body_anim_world.has_animation(clip):
		_hero_body_anim_world.play(clip, -1.0, speed_scale)
	if _hero_shadow_anim != null and _hero_shadow_anim.has_animation(clip):
		_hero_shadow_anim.play(clip, -1.0, speed_scale)


func _cancel_jump_body_landing_if_playing() -> void:
	if _jump_body_phase != _JUMP_BODY_PHASE_LANDING:
		return
	_jump_fallback_invalidate()
	_jump_body_phase = _JUMP_BODY_PHASE_NONE
	if _layered_jump_blend_available():
		_layered_set_jump_blend_weight(0.0)
	else:
		_set_body_jump_trees_suppressed(false)
		if _hero_body_anim_world != null:
			_hero_body_anim_world.stop()
		if _hero_shadow_anim != null:
			_hero_shadow_anim.stop()


func _restore_locomotion_after_landing_cancelled() -> void:
	if is_dead:
		return
	_update_locomotion_animation_from_velocity(true)


func _on_jump_body_anim_finished(anim_name: StringName) -> void:
	if _hero_body_anim_world == null:
		return
	if _jump_body_phase == _JUMP_BODY_PHASE_START:
		var expect_start: StringName = _resolve_playable_jump_anim_name(_hero_body_anim_world, "start")
		if anim_name != expect_start:
			return
		_transition_jump_body_to_cycle_anim()
	elif _jump_body_phase == _JUMP_BODY_PHASE_LANDING:
		var expect_land: StringName = _resolve_playable_jump_anim_name(_hero_body_anim_world, "land")
		if anim_name != expect_land:
			return
		_finish_jump_body_animation_restore_locomotion()


func _apply_jump_body_takeoff_visual() -> void:
	if not _player_has_full_jump_body_clip_set():
		return
	## New jump while landing: drop low-priority land clip first (all peers run this RPC).
	if _jump_body_phase == _JUMP_BODY_PHASE_LANDING:
		_cancel_jump_body_landing_if_playing()
	var ap: AnimationPlayer = _hero_body_anim_world
	var clip: StringName = _resolve_playable_jump_anim_name(ap, "start")
	if clip == StringName(""):
		return
	_ensure_jump_body_anim_finished_connected()
	_jump_body_phase = _JUMP_BODY_PHASE_START
	if _layered_jump_blend_available():
		_layered_set_jump_clip(clip)
		_layered_set_jump_blend_weight(1.0)
		_layered_apply_air_jump_walk_upper_pose()
		_jump_schedule_layered_phase_fallback("start", _JUMP_BODY_PHASE_START, Callable(self, "_transition_jump_body_to_cycle_anim"))
	else:
		_set_body_jump_trees_suppressed(true)
		_play_jump_clip_on_body_and_shadow(clip)


func _transition_jump_body_to_cycle_anim() -> void:
	if _jump_body_phase != _JUMP_BODY_PHASE_START:
		return
	_jump_fallback_invalidate()
	var ap: AnimationPlayer = _hero_body_anim_world
	if ap == null:
		_finish_jump_body_animation_restore_locomotion()
		return
	var clip: StringName = _resolve_playable_jump_anim_name(ap, "loop")
	if clip == StringName(""):
		_finish_jump_body_animation_restore_locomotion()
		return
	_jump_body_phase = _JUMP_BODY_PHASE_CYCLE
	if _layered_jump_blend_available():
		_layered_set_jump_clip(clip)
		_layered_set_jump_blend_weight(1.0)
		_layered_apply_air_jump_walk_upper_pose()
	else:
		_play_jump_clip_on_body_and_shadow(clip)


func _play_jump_body_landing_phase() -> void:
	var ap: AnimationPlayer = _hero_body_anim_world
	if ap == null:
		_finish_jump_body_animation_restore_locomotion()
		return
	var clip: StringName = _resolve_playable_jump_anim_name(ap, "land")
	if clip == StringName(""):
		_finish_jump_body_animation_restore_locomotion()
		return
	_jump_body_phase = _JUMP_BODY_PHASE_LANDING
	if _layered_jump_blend_available():
		_layered_set_jump_clip(clip)
		_layered_set_jump_blend_weight(1.0)
		_layered_apply_air_jump_walk_upper_pose()
		_jump_schedule_layered_phase_fallback("land", _JUMP_BODY_PHASE_LANDING, Callable(self, "_finish_jump_body_animation_restore_locomotion"))
	else:
		_set_body_jump_trees_suppressed(true)
		_play_jump_clip_on_body_and_shadow(clip)


func _apply_jump_body_landing_visual() -> void:
	if not _player_has_full_jump_body_clip_set():
		return
	_ensure_jump_body_anim_finished_connected()
	_play_jump_body_landing_phase()


func _finish_jump_body_animation_restore_locomotion() -> void:
	_jump_fallback_invalidate()
	_jump_body_phase = _JUMP_BODY_PHASE_NONE
	if _layered_jump_blend_available():
		_layered_set_jump_blend_weight(0.0)
	else:
		_set_body_jump_trees_suppressed(false)
	if is_dead:
		return
	## Land clip finished while standing still — force tree back to idle blend before velocity pass.
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var wants_move: bool = horizontal_speed >= FOOTSTEP_MIN_MOVE_SPEED and is_on_floor()
	if not wants_move:
		if _hero_body_uses_layered_anim:
			if _hero_body_anim_tree != null:
				_body_anim_play_tree(_hero_body_anim_tree, &"idle")
			if _hero_shadow_anim_tree != null:
				_body_anim_play_tree(_hero_shadow_anim_tree, &"idle")
		elif _hero_body_anim_world != null:
			_body_anim_play_simple_player(_hero_body_anim_world, &"idle")
			if _hero_shadow_anim != null:
				_body_anim_play_simple_player(_hero_shadow_anim, &"idle")
		if anim_player.current_animation != "shoot" and _body_shoot_hold_left <= 0.0:
			anim_player.play(&"idle")
	_update_locomotion_animation_from_velocity(true)
	call_deferred("_post_jump_land_refresh_locomotion")


func _post_jump_land_refresh_locomotion() -> void:
	if is_dead:
		return
	if _jump_body_phase != _JUMP_BODY_PHASE_NONE:
		return
	_update_locomotion_animation_from_velocity(true)
	## Still idle after land: hero may use same clip name for idle/move (e.g. Walk_cycle); re-assert idle blend.
	if Vector2(velocity.x, velocity.z).length() < FOOTSTEP_MIN_MOVE_SPEED and is_on_floor():
		if _hero_body_uses_layered_anim:
			if _hero_body_anim_tree != null:
				_body_anim_play_tree(_hero_body_anim_tree, &"idle")
			if _hero_shadow_anim_tree != null:
				_body_anim_play_tree(_hero_shadow_anim_tree, &"idle")


func _interrupt_jump_body_animation_if_needed() -> void:
	if _jump_body_phase == _JUMP_BODY_PHASE_NONE:
		return
	_jump_fallback_invalidate()
	_jump_body_phase = _JUMP_BODY_PHASE_NONE
	if _layered_jump_blend_available():
		_layered_set_jump_blend_weight(0.0)
	else:
		_set_body_jump_trees_suppressed(false)
		if _hero_body_anim_world != null:
			_hero_body_anim_world.stop()
		if _hero_shadow_anim != null:
			_hero_shadow_anim.stop()
	if not is_dead:
		_update_locomotion_animation_from_velocity(true)


func _clear_jump_body_animation_state() -> void:
	if _hero_body_anim_world != null and _hero_body_anim_world.animation_finished.is_connected(_on_jump_body_anim_finished):
		_hero_body_anim_world.animation_finished.disconnect(_on_jump_body_anim_finished)
	_jump_fallback_invalidate()
	_jump_body_phase = _JUMP_BODY_PHASE_NONE
	_jump_trees_suppressed_for_body_anim = false
	_layered_set_jump_blend_weight(0.0)
	_layered_jump_anim_node_body = null
	_layered_jump_anim_node_shadow = null
	if _hero_body_anim_tree != null and is_instance_valid(_hero_body_anim_tree):
		_hero_body_anim_tree.active = true
	if _hero_shadow_anim_tree != null and is_instance_valid(_hero_shadow_anim_tree):
		_hero_shadow_anim_tree.active = true


func _physics_jump_body_step_after_move(on_floor_now: bool) -> void:
	if is_dead:
		return
	if not _player_has_full_jump_body_clip_set():
		_jump_slide_was_on_floor = on_floor_now
		return
	if not _local_authority():
		_jump_slide_was_on_floor = on_floor_now
		return
	var prev_on_floor: bool = _jump_slide_was_on_floor
	_jump_slide_was_on_floor = on_floor_now
	if on_floor_now and not prev_on_floor:
		if _jump_body_phase == _JUMP_BODY_PHASE_CYCLE or _jump_body_phase == _JUMP_BODY_PHASE_START:
			_broadcast_jump_body_landing_for_all()
		return
	if not on_floor_now and prev_on_floor and velocity.y > _JUMP_TAKEOFF_VY_THRESHOLD:
		if _jump_body_phase == _JUMP_BODY_PHASE_LANDING:
			_cancel_jump_body_landing_if_playing()
		if _jump_body_phase == _JUMP_BODY_PHASE_NONE:
			_broadcast_jump_body_takeoff_for_all()


func _bone_path_for_animation_filter(root: Node, skeleton: Skeleton3D, bone_name: StringName) -> NodePath:
	var skel_path: NodePath = root.get_path_to(skeleton)
	return NodePath(str(skel_path) + ":" + str(bone_name))


func _bone_is_lower_body(name_str: String) -> bool:
	var n: String = name_str.to_lower()
	if n.contains("hip") or n.contains("pelvis") or n.contains("root"):
		return true
	if n.contains("leg") or n.contains("thigh") or n.contains("calf") or n.contains("foot") or n.contains("toe") or n.contains("ankle") or n.contains("ball"):
		return true
	return false


## Shoot blend drives spine/arms recoil; skip head/neck so pistol clip doesn’t jerk aim (additive head look stays dominant).
func _bone_skip_upper_body_shoot_for_head_stability(name_str: String) -> bool:
	var n: String = name_str.to_lower()
	if n.contains("neck"):
		return true
	if n.ends_with("head") or (n.contains("head") and not n.contains("fore") and not n.contains("hand")):
		return true
	return false


func _apply_upper_body_shoot_filters(anim_node: AnimationNode, skeleton: Skeleton3D, root: Node) -> void:
	anim_node.filter_enabled = true
	var bone_count: int = skeleton.get_bone_count()
	for i in bone_count:
		var bn: StringName = skeleton.get_bone_name(i)
		if _bone_is_lower_body(str(bn)):
			continue
		if _bone_skip_upper_body_shoot_for_head_stability(str(bn)):
			continue
		var pth: NodePath = _bone_path_for_animation_filter(root, skeleton, bn)
		anim_node.set_filter_path(pth, true)


## Walk blends only onto hips/legs; spine/arms/head stay on idle unless the upper-body shoot OneShot fires.
func _apply_locomotion_walk_lower_body_filters(loco_blend: AnimationNodeBlend2, skeleton: Skeleton3D, root: Node) -> void:
	loco_blend.filter_enabled = true
	var bone_count: int = skeleton.get_bone_count()
	for i in bone_count:
		var bn: StringName = skeleton.get_bone_name(i)
		if not _bone_is_lower_body(str(bn)):
			continue
		var pth: NodePath = _bone_path_for_animation_filter(root, skeleton, bn)
		loco_blend.set_filter_path(pth, true)


func _find_head_bone_idx(sk: Skeleton3D) -> int:
	var exact: PackedStringArray = PackedStringArray(["Head", "mixamorigHead", "head", "CC_Base_Head"])
	for sn in exact:
		var bi: int = sk.find_bone(StringName(sn))
		if bi >= 0:
			return bi
	for i in sk.get_bone_count():
		var nm := str(sk.get_bone_name(i)).to_lower()
		if nm.ends_with("head") or (nm.contains("head") and not nm.contains("fore") and not nm.contains("hand")):
			return i
	return -1


func _find_neck_bone_idx(sk: Skeleton3D) -> int:
	var exact: PackedStringArray = PackedStringArray(["Neck", "mixamorigNeck", "neck", "CC_Base_Neck"])
	for sn in exact:
		var bi: int = sk.find_bone(StringName(sn))
		if bi >= 0:
			return bi
	for i in sk.get_bone_count():
		var nm := str(sk.get_bone_name(i)).to_lower()
		if nm.contains("neck"):
			return i
	return -1


func _find_right_shoulder_bone_idx(sk: Skeleton3D) -> int:
	## Mixamo: parent of RightArm is the shoulder/clavicle — more reliable than name alone.
	for arm_nm in PackedStringArray(["RightArm", "mixamorigRightArm", "RightUpperArm", "mixamorigRightUpperArm"]):
		var ai: int = sk.find_bone(StringName(arm_nm))
		if ai >= 0:
			var pi: int = sk.get_bone_parent(ai)
			if pi >= 0:
				return pi
	var exact: PackedStringArray = PackedStringArray([
		"RightShoulder",
		"mixamorigRightShoulder",
		"RightCollar",
		"mixamorigRightCollar",
	])
	for sn in exact:
		var bi: int = sk.find_bone(StringName(sn))
		if bi >= 0:
			return bi
	for i in sk.get_bone_count():
		var nm := str(sk.get_bone_name(i)).to_lower()
		if nm.contains("right") and nm.contains("shoulder"):
			return i
	return -1


func _find_tp_weapon_attach_bone_idx(sk: Skeleton3D) -> int:
	## Prefer explicit weapon/helper bones, then right forearm (soldier3: gun follows `LowerArm.R` / `LowerArm.R.001`).
	for nm in PackedStringArray([
		"LowerArm.R.001",
		"LowerArm.R",
		"RightHand",
		"mixamorigRightHand",
		"mixamorigRightArm",
		"Hand.R",
		"Weapon.R",
		"Gun_R",
	]):
		var bi: int = sk.find_bone(StringName(nm))
		if bi >= 0:
			return bi
	for i in sk.get_bone_count():
		var nl: String = str(sk.get_bone_name(i)).to_lower()
		if nl.contains("right") and (nl.contains("hand") or nl.contains("lowerarm") or nl.contains("weapon") or nl.contains("gun")):
			return i
	return -1


func _cache_hero_body_skeleton_for_head_look(import_root: Node) -> void:
	_hero_body_skeleton = null
	_hero_head_bone_idx = -1
	_hero_neck_bone_idx = -1
	_hero_right_shoulder_bone_idx = -1
	_hero_tp_weapon_bone_idx = -1
	var sk_nodes: Array[Node] = import_root.find_children("*", "Skeleton3D", true, false)
	if sk_nodes.is_empty():
		return
	_hero_body_skeleton = sk_nodes[0] as Skeleton3D
	if _hero_body_skeleton == null:
		return
	_hero_head_bone_idx = _find_head_bone_idx(_hero_body_skeleton)
	_hero_neck_bone_idx = _find_neck_bone_idx(_hero_body_skeleton)
	_hero_right_shoulder_bone_idx = _find_right_shoulder_bone_idx(_hero_body_skeleton)
	_hero_tp_weapon_bone_idx = _find_tp_weapon_attach_bone_idx(_hero_body_skeleton)


func _cache_hero_shadow_skeleton_for_head_look(shadow_root: Node) -> void:
	_hero_shadow_skeleton = null
	if shadow_root == null:
		return
	var sk_nodes: Array[Node] = shadow_root.find_children("*", "Skeleton3D", true, false)
	if sk_nodes.is_empty():
		return
	_hero_shadow_skeleton = sk_nodes[0] as Skeleton3D


func _apply_imported_character_visual_offsets() -> void:
	_apply_imported_head_look_from_camera()
	_apply_third_person_muzzle_anchor_from_rig()
	_sync_weapon_vfx_attachment_for_view()


func _bone_local_nod_axis_x(sk: Skeleton3D, bone_idx: int) -> Vector3:
	var rest: Transform3D = sk.get_bone_rest(bone_idx)
	var ax: Vector3 = rest.basis.x
	if ax.length_squared() < 1e-10:
		return Vector3.RIGHT
	return ax.normalized()


## Horizontal aim pitch (look up/down): axis is aim_fwd × world_up in bone-local space. Shoulder rest X often
## follows the upper arm, so `_bone_local_nod_axis_x` does not tilt the shoulder visibly.
func _bone_horizontal_pitch_axis_local(sk: Skeleton3D, bone_idx: int, aim_fwd_world: Vector3) -> Vector3:
	sk.force_update_all_bone_transforms()
	var fwd_flat: Vector3 = aim_fwd_world
	fwd_flat.y = 0.0
	if fwd_flat.length_squared() < 1e-10:
		fwd_flat = Vector3(0.0, 0.0, -1.0)
	else:
		fwd_flat = fwd_flat.normalized()
	var axis_world: Vector3 = fwd_flat.cross(Vector3.UP)
	if axis_world.length_squared() < 1e-10:
		return _bone_local_nod_axis_x(sk, bone_idx)
	axis_world = axis_world.normalized()
	var axis_skeleton: Vector3 = sk.global_transform.basis.inverse() * axis_world
	var g: Transform3D = sk.get_bone_global_pose(bone_idx)
	var b: Basis = g.basis
	if absf(b.determinant()) < 1e-10:
		return _bone_local_nod_axis_x(sk, bone_idx)
	var axis_local: Vector3 = b.inverse() * axis_skeleton
	if axis_local.length_squared() < 1e-10:
		return _bone_local_nod_axis_x(sk, bone_idx)
	return axis_local.normalized()


func _head_look_world_forward_for_pitch() -> Vector3:
	## Third person: aim pitch for neck/head comes from the camera. TP pistol is bound to the body weapon bone each frame,
	## so its node forward must not drive head look.
	var aim_node: Node3D = camera
	if aim_node == null:
		return Vector3(0.0, 0.0, -1.0)
	if not _third_person_enabled:
		if pistol_node != null:
			aim_node = pistol_node
	var fwd: Vector3 = (-aim_node.global_transform.basis.z).normalized()
	if fwd.length_squared() < 1e-10:
		return Vector3(0.0, 0.0, -1.0)
	return fwd


func _head_look_vertical_pitch_rad_from_forward(fwd: Vector3) -> float:
	var horiz: float = sqrt(maxf(1e-10, fwd.x * fwd.x + fwd.z * fwd.z))
	return atan2(fwd.y, horiz)


func _hl_bone_pose_still_matches_last_apply(current: Quaternion, last_after_apply: Quaternion, have_saved: bool) -> bool:
	if not have_saved:
		return false
	return absf(current.dot(last_after_apply)) > 0.9995


func _apply_head_look_rotations_to_skeleton(
	sk: Skeleton3D,
	pitch_neck: float,
	pitch_head: float,
	pitch_shoulder: float,
	aim_fwd_world: Vector3,
	shadow_duplicate: bool
) -> void:
	if sk == null or _hero_head_bone_idx < 0:
		return
	var neck_prev: Quaternion = _hl_neck_q_shadow if shadow_duplicate else _hl_neck_q_body
	var head_prev: Quaternion = _hl_head_q_shadow if shadow_duplicate else _hl_head_q_body
	var have_neck_saved: bool = _hl_have_neck_saved_shadow if shadow_duplicate else _hl_have_neck_saved_body
	var have_head_saved: bool = _hl_have_head_saved_shadow if shadow_duplicate else _hl_have_head_saved_body
	var last_neck_after: Quaternion = _hl_last_neck_pose_after_shadow if shadow_duplicate else _hl_last_neck_pose_after_body
	var last_head_after: Quaternion = _hl_last_head_pose_after_shadow if shadow_duplicate else _hl_last_head_pose_after_body
	if _hero_neck_bone_idx >= 0:
		var ax_n: Vector3 = _bone_local_nod_axis_x(sk, _hero_neck_bone_idx)
		var q_n: Quaternion = Quaternion(ax_n, pitch_neck)
		var rot_n: Quaternion = sk.get_bone_pose_rotation(_hero_neck_bone_idx)
		var anim_n: Quaternion = rot_n * neck_prev.inverse() if _hl_bone_pose_still_matches_last_apply(rot_n, last_neck_after, have_neck_saved) else rot_n
		sk.set_bone_pose_rotation(_hero_neck_bone_idx, anim_n * q_n)
		if shadow_duplicate:
			_hl_neck_q_shadow = q_n
			_hl_have_neck_saved_shadow = true
			_hl_last_neck_pose_after_shadow = sk.get_bone_pose_rotation(_hero_neck_bone_idx)
		else:
			_hl_neck_q_body = q_n
			_hl_have_neck_saved_body = true
			_hl_last_neck_pose_after_body = sk.get_bone_pose_rotation(_hero_neck_bone_idx)
	var ax_h: Vector3 = _bone_local_nod_axis_x(sk, _hero_head_bone_idx)
	var q_h: Quaternion = Quaternion(ax_h, pitch_head)
	var rot_h: Quaternion = sk.get_bone_pose_rotation(_hero_head_bone_idx)
	var anim_h: Quaternion = rot_h * head_prev.inverse() if _hl_bone_pose_still_matches_last_apply(rot_h, last_head_after, have_head_saved) else rot_h
	sk.set_bone_pose_rotation(_hero_head_bone_idx, anim_h * q_h)
	if shadow_duplicate:
		_hl_head_q_shadow = q_h
		_hl_have_head_saved_shadow = true
		_hl_last_head_pose_after_shadow = sk.get_bone_pose_rotation(_hero_head_bone_idx)
	else:
		_hl_head_q_body = q_h
		_hl_have_head_saved_body = true
		_hl_last_head_pose_after_body = sk.get_bone_pose_rotation(_hero_head_bone_idx)
	if _hero_right_shoulder_bone_idx >= 0:
		var ax_ra: Vector3 = _bone_horizontal_pitch_axis_local(sk, _hero_right_shoulder_bone_idx, aim_fwd_world)
		var q_ra: Quaternion = Quaternion(ax_ra, pitch_shoulder)
		var rot_ra: Quaternion = sk.get_bone_pose_rotation(_hero_right_shoulder_bone_idx)
		var rarm_prev: Quaternion = _hl_rarm_q_shadow if shadow_duplicate else _hl_rarm_q_body
		var have_rarm_saved: bool = _hl_have_rarm_saved_shadow if shadow_duplicate else _hl_have_rarm_saved_body
		var last_rarm_after: Quaternion = _hl_last_rarm_pose_after_shadow if shadow_duplicate else _hl_last_rarm_pose_after_body
		var anim_ra: Quaternion = rot_ra * rarm_prev.inverse() if _hl_bone_pose_still_matches_last_apply(rot_ra, last_rarm_after, have_rarm_saved) else rot_ra
		sk.set_bone_pose_rotation(_hero_right_shoulder_bone_idx, anim_ra * q_ra)
		if shadow_duplicate:
			_hl_rarm_q_shadow = q_ra
			_hl_have_rarm_saved_shadow = true
			_hl_last_rarm_pose_after_shadow = sk.get_bone_pose_rotation(_hero_right_shoulder_bone_idx)
		else:
			_hl_rarm_q_body = q_ra
			_hl_have_rarm_saved_body = true
			_hl_last_rarm_pose_after_body = sk.get_bone_pose_rotation(_hero_right_shoulder_bone_idx)


func _tp_muzzle_effects_use_rig_anchor() -> bool:
	if not _player_uses_imported_character_model():
		return false
	if _hero_body_skeleton == null or _hero_tp_weapon_bone_idx < 0:
		return false
	## Local controlled pawn: rig-mounted VFX only in third person (first person keeps camera pistol). Remote pawns are
	## always drawn full-body for everyone else, so always bind effects to the animated gun bone.
	if _local_authority():
		return _third_person_enabled
	return true


func _apply_third_person_muzzle_anchor_from_rig() -> void:
	if not _tp_muzzle_effects_use_rig_anchor() or _tp_muzzle_effects_anchor == null:
		return
	var sk: Skeleton3D = _hero_body_skeleton
	sk.force_update_all_bone_transforms()
	var bone_world: Transform3D = sk.global_transform * sk.get_bone_global_pose(_hero_tp_weapon_bone_idx)
	_tp_muzzle_effects_anchor.global_transform = bone_world * TP_THIRD_PERSON_PISTOL_BIND_OFFSET


func _sync_pistol_parent_for_camera_mode() -> void:
	## FP: pistol under `Camera3D` for AnimationPlayer view-model tracks.
	## TP + rig gun: pistol stays under camera (hidden); muzzle/VFX use `_tp_muzzle_effects_anchor` on the body bone.
	## TP without rig bone: pistol under pawn so it does not inherit camera pitch (fallback).
	if pistol_node == null or camera == null:
		return
	if _tp_muzzle_effects_use_rig_anchor():
		if pistol_node.get_parent() != camera:
			pistol_node.reparent(camera, true)
	elif _third_person_enabled:
		if pistol_node.get_parent() != self:
			pistol_node.reparent(self, true)
	else:
		if pistol_node.get_parent() != camera:
			pistol_node.reparent(camera, true)


func _sync_muzzle_effect_nodes_for_tp() -> void:
	if _tp_muzzle_effects_anchor == null:
		return
	if _tp_muzzle_effects_use_rig_anchor():
		if muzzle_flash != null and muzzle_flash.get_parent() != _tp_muzzle_effects_anchor:
			muzzle_flash.reparent(_tp_muzzle_effects_anchor, true)
		if big_muzzle_flash != null and big_muzzle_flash.get_parent() != _tp_muzzle_effects_anchor:
			big_muzzle_flash.reparent(_tp_muzzle_effects_anchor, true)
		if big_muzzle_flash_sniper != null and big_muzzle_flash_sniper.get_parent() != _tp_muzzle_effects_anchor:
			big_muzzle_flash_sniper.reparent(_tp_muzzle_effects_anchor, true)
	else:
		if muzzle_flash != null and pistol_node != null and muzzle_flash.get_parent() != pistol_node:
			muzzle_flash.reparent(pistol_node, true)
		if big_muzzle_flash != null and camera != null and big_muzzle_flash.get_parent() != camera:
			big_muzzle_flash.reparent(camera, true)
		if big_muzzle_flash_sniper != null and camera != null and big_muzzle_flash_sniper.get_parent() != camera:
			big_muzzle_flash_sniper.reparent(camera, true)


func _sync_weapon_vfx_attachment_for_view() -> void:
	_sync_pistol_parent_for_camera_mode()
	_sync_muzzle_effect_nodes_for_tp()
	if pistol_node != null:
		var hide_fp_pistol_mesh: bool = _tp_muzzle_effects_use_rig_anchor()
		pistol_node.visible = not is_dead and not hide_fp_pistol_mesh


func _apply_imported_head_look_from_camera() -> void:
	if _hero_body_skeleton == null or _hero_head_bone_idx < 0:
		return
	if not _player_uses_imported_character_model():
		return
	if is_dead:
		return
	if camera == null:
		return
	## Vertical pitch from world aim direction (Camera3D / Pistol forward).
	var fwd: Vector3 = _head_look_world_forward_for_pitch()
	## Negate vertical pitch so imported rig nod matches camera (bone rest X may point opposite world up).
	var pitch_cam: float = -_head_look_vertical_pitch_rad_from_forward(fwd) * HEAD_LOOK_CAMERA_MULT
	if absf(pitch_cam) < HEAD_LOOK_FORWARD_DEADZONE_RAD:
		pitch_cam = 0.0
	pitch_cam = clampf(pitch_cam, -HEAD_LOOK_CAM_PITCH_MAX_RAD, HEAD_LOOK_CAM_PITCH_MAX_RAD)
	var pitch_neck: float = pitch_cam * HEAD_LOOK_NECK_FRACTION
	var pitch_head: float = pitch_cam * (1.0 - HEAD_LOOK_NECK_FRACTION)
	pitch_neck = clampf(pitch_neck, -HEAD_LOOK_NECK_PITCH_MAX_RAD, HEAD_LOOK_NECK_PITCH_MAX_RAD)
	pitch_head = clampf(pitch_head, -HEAD_LOOK_HEAD_PITCH_MAX_RAD, HEAD_LOOK_HEAD_PITCH_MAX_RAD)
	_apply_head_look_rotations_to_skeleton(_hero_body_skeleton, pitch_neck, pitch_head, pitch_cam, fwd, false)
	if _hero_shadow_skeleton != null:
		_apply_head_look_rotations_to_skeleton(_hero_shadow_skeleton, pitch_neck, pitch_head, pitch_cam, fwd, true)


func _setup_layered_body_animation_tree(import_root: Node, anim_player: AnimationPlayer) -> AnimationTree:
	if anim_player == null:
		return null
	var skeleton: Skeleton3D = null
	for n in import_root.find_children("*", "Skeleton3D", true, false):
		skeleton = n as Skeleton3D
		break
	if skeleton == null:
		return null
	var idle_clip: StringName = _resolve_playable_anim_name(anim_player, &"idle")
	var walk_clip: StringName = _resolve_playable_anim_name(anim_player, &"move")
	var shot_clip: StringName = _resolve_playable_anim_name(anim_player, &"shoot")
	if idle_clip == StringName("") or walk_clip == StringName("") or shot_clip == StringName(""):
		return null
	if not anim_player.has_animation(idle_clip) or not anim_player.has_animation(walk_clip) or not anim_player.has_animation(shot_clip):
		return null
	var jump_start_clip: StringName = _resolve_playable_jump_anim_name(anim_player, "start")
	var jump_loop_clip: StringName = _resolve_playable_jump_anim_name(anim_player, "loop")
	var jump_land_clip: StringName = _resolve_playable_jump_anim_name(anim_player, "land")
	var has_jump_clips: bool = (
		jump_start_clip != StringName("")
		and jump_loop_clip != StringName("")
		and jump_land_clip != StringName("")
		and anim_player.has_animation(jump_start_clip)
		and anim_player.has_animation(jump_loop_clip)
		and anim_player.has_animation(jump_land_clip)
	)
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = idle_clip
	var walk_node := AnimationNodeAnimation.new()
	walk_node.animation = walk_clip
	var walk_scale := AnimationNodeTimeScale.new()
	## Speed is driven only via AnimationTree parameters (no `scale` property on the node resource in 4.4).
	var loco_blend := AnimationNodeBlend2.new()
	loco_blend.sync = true
	_apply_locomotion_walk_lower_body_filters(loco_blend, skeleton, import_root)
	var shot_anim := AnimationNodeAnimation.new()
	shot_anim.animation = shot_clip
	var shoot_oneshot := AnimationNodeOneShot.new()
	shoot_oneshot.fadein_time = 0.05
	shoot_oneshot.fadeout_time = 0.08
	_apply_upper_body_shoot_filters(shoot_oneshot, skeleton, import_root)
	var blend_tree := AnimationNodeBlendTree.new()
	## Godot 4.4+: add_node(name, node, position); connect_node(input_node, input_index, output_node).
	blend_tree.add_node(&"idle", idle_node, Vector2(-320.0, -80.0))
	blend_tree.add_node(&"walk", walk_node, Vector2(-320.0, 80.0))
	blend_tree.add_node(&"walk_speed", walk_scale, Vector2(-140.0, 80.0))
	blend_tree.add_node(&"locomotion", loco_blend, Vector2(40.0, 0.0))
	blend_tree.add_node(&"shot_anim", shot_anim, Vector2(-140.0, -200.0))
	blend_tree.add_node(&"shoot_oneshot", shoot_oneshot, Vector2(260.0, 0.0))
	blend_tree.connect_node(&"locomotion", 0, &"idle")
	blend_tree.connect_node(&"walk_speed", 0, &"walk")
	blend_tree.connect_node(&"locomotion", 1, &"walk_speed")
	if has_jump_clips:
		var jump_anim_node := AnimationNodeAnimation.new()
		jump_anim_node.animation = jump_start_clip
		var jump_time_seek := AnimationNodeTimeSeek.new()
		var jump_lower_blend := AnimationNodeBlend2.new()
		jump_lower_blend.sync = false
		_apply_locomotion_walk_lower_body_filters(jump_lower_blend, skeleton, import_root)
		blend_tree.add_node(&"jump_anim", jump_anim_node, Vector2(40.0, -220.0))
		blend_tree.add_node(&"jump_time_seek", jump_time_seek, Vector2(120.0, -220.0))
		blend_tree.add_node(&"jump_lower_blend", jump_lower_blend, Vector2(160.0, 0.0))
		blend_tree.connect_node(&"jump_lower_blend", 0, &"locomotion")
		blend_tree.connect_node(&"jump_time_seek", 0, &"jump_anim")
		blend_tree.connect_node(&"jump_lower_blend", 1, &"jump_time_seek")
		blend_tree.connect_node(&"shoot_oneshot", 0, &"jump_lower_blend")
		if _layered_jump_anim_node_body == null:
			_layered_jump_anim_node_body = jump_anim_node
		else:
			_layered_jump_anim_node_shadow = jump_anim_node
	else:
		blend_tree.connect_node(&"shoot_oneshot", 0, &"locomotion")
	blend_tree.connect_node(&"shoot_oneshot", 1, &"shot_anim")
	blend_tree.connect_node(&"output", 0, &"shoot_oneshot")
	var tree := AnimationTree.new()
	tree.name = "BodyAnimationTree"
	tree.process_priority = BODY_ANIM_TREE_PROCESS_PRIORITY
	tree.tree_root = blend_tree
	import_root.add_child(tree)
	tree.anim_player = tree.get_path_to(anim_player)
	tree.active = true
	anim_player.stop()
	tree.set(&"parameters/locomotion/blend_amount", 0.0)
	tree.set(&"parameters/walk_speed/scale", BODY_MOVE_ANIM_SPEED_MULT)
	if has_jump_clips:
		tree.set(&"parameters/jump_lower_blend/blend_amount", 0.0)
	_apply_body_locomotion_loop_modes(anim_player)
	return tree


func _body_anim_play_simple_player(ap: AnimationPlayer, weapon_anim: StringName) -> void:
	var anim_speed: float = BODY_MOVE_ANIM_SPEED_MULT if String(weapon_anim) == "move" else 1.0
	var clip: StringName = _resolve_playable_anim_name(ap, weapon_anim)
	if clip != StringName(""):
		ap.play(clip, -1.0, anim_speed)


func _body_anim_play_tree(tree: AnimationTree, weapon_anim: StringName) -> void:
	if tree == null:
		return
	match String(weapon_anim):
		"idle":
			tree.set(&"parameters/locomotion/blend_amount", 0.0)
		"move":
			tree.set(&"parameters/locomotion/blend_amount", 1.0)
		_:
			pass


func _body_anim_play(weapon_anim: StringName) -> void:
	_cancel_jump_body_landing_if_playing()
	if _hero_body_uses_layered_anim and _hero_body_anim_tree != null:
		_body_anim_play_tree(_hero_body_anim_tree, weapon_anim)
	elif _hero_body_anim_world != null:
		_body_anim_play_simple_player(_hero_body_anim_world, weapon_anim)
	if _hero_shadow_uses_layered_anim and _hero_shadow_anim_tree != null:
		_body_anim_play_tree(_hero_shadow_anim_tree, weapon_anim)
	elif _hero_shadow_anim != null:
		_body_anim_play_simple_player(_hero_shadow_anim, weapon_anim)


func _tag_world_body_visual_layers(root: Node) -> void:
	## Exclusive layer so we can strip it from the owner’s camera without layer-1 meshes still drawing.
	var bit: int = RENDER_LAYER_WORLD_BODY_OWNER_OCCLUDED - 1
	var layer_only: int = 1 << bit
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		vi.layers = layer_only


func _tag_shadow_only_duplicate(root: Node) -> void:
	## Layer 1 + shadows-only so the owner’s camera draws a correct silhouette on the ground, not the mesh.
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		gi.layers = 1
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _disable_owned_world_mesh_shadow_cast(imported_root: Node) -> void:
	for node in imported_root.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _refresh_owner_world_body_camera_cull() -> void:
	if camera == null:
		return
	var own_pawn: bool = str(name).is_valid_int() and int(str(name)) == HeroNet.my_id()
	var hide_mesh_not_shadow: bool = (
		own_pawn
		and _player_uses_imported_character_model()
		and not is_dead
		and not _third_person_enabled
	)
	var layer_bit: int = 1 << (RENDER_LAYER_WORLD_BODY_OWNER_OCCLUDED - 1)
	if hide_mesh_not_shadow:
		camera.cull_mask = _default_camera_cull_mask & ~layer_bit
	else:
		camera.cull_mask = _default_camera_cull_mask


func _clear_character_model_instances() -> void:
	_clear_jump_body_animation_state()
	_hero_body_anim_world = null
	if _hero_body_anim_tree != null and is_instance_valid(_hero_body_anim_tree):
		_hero_body_anim_tree.queue_free()
	_hero_body_anim_tree = null
	_hero_body_uses_layered_anim = false
	_hero_shadow_anim = null
	if _hero_shadow_anim_tree != null and is_instance_valid(_hero_shadow_anim_tree):
		_hero_shadow_anim_tree.queue_free()
	_hero_shadow_anim_tree = null
	_hero_shadow_uses_layered_anim = false
	_hero_body_skeleton = null
	_hero_shadow_skeleton = null
	_hero_head_bone_idx = -1
	_hero_neck_bone_idx = -1
	_hero_right_shoulder_bone_idx = -1
	_hero_tp_weapon_bone_idx = -1
	_hl_neck_q_body = Quaternion.IDENTITY
	_hl_head_q_body = Quaternion.IDENTITY
	_hl_neck_q_shadow = Quaternion.IDENTITY
	_hl_head_q_shadow = Quaternion.IDENTITY
	_hl_have_neck_saved_body = false
	_hl_have_head_saved_body = false
	_hl_have_neck_saved_shadow = false
	_hl_have_head_saved_shadow = false
	_hl_rarm_q_body = Quaternion.IDENTITY
	_hl_have_rarm_saved_body = false
	_hl_last_rarm_pose_after_body = Quaternion.IDENTITY
	_hl_rarm_q_shadow = Quaternion.IDENTITY
	_hl_have_rarm_saved_shadow = false
	_hl_last_rarm_pose_after_shadow = Quaternion.IDENTITY
	if character_model_root != null:
		for c in character_model_root.get_children():
			character_model_root.remove_child(c)
			c.free()


func _refresh_hero_character_model() -> void:
	_clear_character_model_instances()
	var hero: HeroResource = HeroesRegistry.get_hero(hero_id)
	var model_path: String = hero.model_scene_path if hero != null else ""
	var mesh_inst: MeshInstance3D = body_mesh_placeholder
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		if mesh_inst != null:
			mesh_inst.visible = not is_dead
		_update_dead_visibility()
		return
	var ps: PackedScene = load(model_path) as PackedScene
	if ps == null:
		if mesh_inst != null:
			mesh_inst.visible = not is_dead
		_update_dead_visibility()
		return
	var inst_world: Node = ps.instantiate()
	var imported_meshes: Array[Node] = inst_world.find_children("*", "MeshInstance3D", true, false)
	if imported_meshes.is_empty():
		push_warning("Imported model has no MeshInstance3D and cannot be rendered: %s" % model_path)
		inst_world.free()
		if mesh_inst != null:
			mesh_inst.visible = not is_dead
		_update_dead_visibility()
		return
	character_model_root.add_child(inst_world)
	## Only the owning client strips this layer from their camera; tagging remotes would hide them from everyone using an imported hero.
	if _local_authority():
		_tag_world_body_visual_layers(inst_world)
	_hero_body_anim_world = _find_body_animation_player(inst_world)
	if _hero_body_anim_world == null:
		_hero_body_anim_world = _find_first_animation_player(inst_world)
	var anim_src_path: String = _resolve_body_anim_library_source_scene_path(hero)
	if not anim_src_path.is_empty():
		_inject_body_anim_libraries_from_source_scene(anim_src_path, _hero_body_anim_world)
	if hero != null:
		_merge_body_anim_external_resources(_hero_body_anim_world, hero)
	_hero_body_anim_tree = null
	_hero_body_uses_layered_anim = false
	if _hero_body_anim_world != null:
		_hero_body_anim_tree = _setup_layered_body_animation_tree(inst_world, _hero_body_anim_world)
		_hero_body_uses_layered_anim = _hero_body_anim_tree != null

	_cache_hero_body_skeleton_for_head_look(inst_world)

	_hero_shadow_anim = null
	_hero_shadow_anim_tree = null
	_hero_shadow_uses_layered_anim = false
	if str(name).is_valid_int() and int(str(name)) == HeroNet.my_id():
		var inst_shadow: Node = ps.instantiate()
		character_model_root.add_child(inst_shadow)
		_tag_shadow_only_duplicate(inst_shadow)
		_hero_shadow_anim = _find_body_animation_player(inst_shadow)
		if _hero_shadow_anim == null:
			_hero_shadow_anim = _find_first_animation_player(inst_shadow)
		var shadow_anim_src: String = anim_src_path
		if not shadow_anim_src.is_empty():
			_inject_body_anim_libraries_from_source_scene(shadow_anim_src, _hero_shadow_anim)
		if hero != null:
			_merge_body_anim_external_resources(_hero_shadow_anim, hero)
		if _hero_shadow_anim != null:
			_hero_shadow_anim_tree = _setup_layered_body_animation_tree(inst_shadow, _hero_shadow_anim)
			_hero_shadow_uses_layered_anim = _hero_shadow_anim_tree != null
		_cache_hero_shadow_skeleton_for_head_look(inst_shadow)
		_disable_owned_world_mesh_shadow_cast(inst_world)

	_prioritize_imported_anim_players_if_no_layered_tree()
	if _hero_body_anim_world != null:
		_apply_body_locomotion_loop_modes(_hero_body_anim_world)
		_apply_body_jump_clip_loop_modes(_hero_body_anim_world)
	if _hero_shadow_anim != null:
		_apply_body_locomotion_loop_modes(_hero_shadow_anim)
		_apply_body_jump_clip_loop_modes(_hero_shadow_anim)

	if mesh_inst != null:
		mesh_inst.visible = false
	_update_dead_visibility()


func _try_play_pistol_idle_or_move(clip: StringName) -> void:
	if not _hero_body_uses_layered_anim:
		if anim_player.current_animation == "shoot":
			return
	## Legacy full-body jump on AnimationPlayer only — skip tree locomotion during air start/cycle.
	if _jump_body_phase == _JUMP_BODY_PHASE_START or _jump_body_phase == _JUMP_BODY_PHASE_CYCLE:
		if not _layered_jump_blend_available():
			return
		anim_player.play(clip)
		return
	## Landing is low priority: walking preempts land clip; standing keeps land until it finishes.
	if _jump_body_phase == _JUMP_BODY_PHASE_LANDING:
		anim_player.play(clip)
		if clip == &"move":
			_cancel_jump_body_landing_if_playing()
			_body_anim_play(clip)
			_restore_locomotion_after_landing_cancelled()
		return
	anim_player.play(clip)
	_body_anim_play(clip)


func _play_pistol_shoot() -> void:
	_cancel_jump_body_landing_if_playing()
	anim_player.stop()
	anim_player.play(&"shoot")
	if _hero_body_uses_layered_anim:
		if _hero_body_anim_tree != null:
			_hero_body_anim_tree.set(&"parameters/shoot_oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		if _hero_shadow_anim_tree != null:
			_hero_shadow_anim_tree.set(&"parameters/shoot_oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	else:
		_body_anim_play(&"shoot")
	_body_shoot_hold_left = BODY_SHOOT_HOLD_SEC


func _update_locomotion_animation_from_velocity(grounded_hint: bool = true, horizontal_speed_override: float = -1.0) -> void:
	if is_dead:
		return
	if (_jump_body_phase == _JUMP_BODY_PHASE_START or _jump_body_phase == _JUMP_BODY_PHASE_CYCLE) and not _layered_jump_blend_available():
		return
	if not _hero_body_uses_layered_anim:
		if anim_player.current_animation == "shoot" or _body_shoot_hold_left > 0.0:
			return
	var horizontal_speed: float = horizontal_speed_override if horizontal_speed_override >= 0.0 else Vector2(velocity.x, velocity.z).length()
	var moving: bool = horizontal_speed >= FOOTSTEP_MIN_MOVE_SPEED
	if horizontal_speed_override >= 0.0:
		# Remote replicas can jitter around threshold; hysteresis + linger prevents rapid idle/walk toggling.
		if _remote_anim_is_moving:
			if horizontal_speed >= REMOTE_MOVE_EXIT_SPEED:
				_remote_anim_move_hold_left = REMOTE_MOVE_HOLD_SEC
			elif _remote_anim_move_hold_left > 0.0:
				_remote_anim_move_hold_left = maxf(0.0, _remote_anim_move_hold_left - get_physics_process_delta_time())
			else:
				_remote_anim_is_moving = false
		else:
			if horizontal_speed >= REMOTE_MOVE_ENTER_SPEED:
				_remote_anim_is_moving = true
				_remote_anim_move_hold_left = REMOTE_MOVE_HOLD_SEC
		moving = _remote_anim_is_moving
	if grounded_hint and not is_on_floor():
		moving = false
	_try_play_pistol_idle_or_move(&"move" if moving else &"idle")
	if _layered_jump_blend_available() and _jump_body_phase != _JUMP_BODY_PHASE_NONE:
		_layered_apply_air_jump_walk_upper_pose()


func _remote_horizontal_speed_from_pos_delta(delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	var pos: Vector3 = global_position
	if not _remote_anim_pos_valid:
		_remote_prev_anim_pos = pos
		_remote_anim_pos_valid = true
		return 0.0
	var d: Vector3 = pos - _remote_prev_anim_pos
	_remote_prev_anim_pos = pos
	d.y = 0.0
	var k: float = 1.0 - exp(-REMOTE_MOVE_SPEED_SMOOTH * delta)
	var raw_speed: float = d.length() / delta
	_remote_anim_speed_smooth = lerpf(_remote_anim_speed_smooth, raw_speed, k)
	return _remote_anim_speed_smooth


func _ensure_tank_laser_shield() -> void:
	if _laser_shield != null and is_instance_valid(_laser_shield):
		return
	var inst := LaserShieldScene.instantiate()
	if not (inst is LaserShield):
		return
	_laser_shield = inst as LaserShield
	add_child(_laser_shield)
	_laser_shield.scale = Vector3(TANK_LASER_SHIELD_WIDTH_SCALE_MULT, TANK_LASER_SHIELD_HEIGHT_SCALE_MULT, TANK_LASER_SHIELD_WIDTH_SCALE_MULT)
	_laser_shield.position = Vector3(0.0, TANK_LASER_SHIELD_HEIGHT_OFFSET, -TANK_LASER_SHIELD_FORWARD_OFFSET)
	_laser_shield.set_owner_team(team_id)
	_laser_shield.max_health = TANK_LASER_SHIELD_MAX_HEALTH
	_laser_shield.reset_health()
	_laser_shield.set_active_shield(false)
	if not _laser_shield.shield_broken.is_connected(_on_tank_laser_shield_broken):
		_laser_shield.shield_broken.connect(_on_tank_laser_shield_broken)


func _set_tank_laser_shield_up(enabled: bool) -> void:
	_tank_laser_shield_up = enabled and hero_id == "tank_laser" and weaponNum == 1
	_ensure_tank_laser_shield()
	if _laser_shield != null and is_instance_valid(_laser_shield):
		if _tank_laser_shield_up:
			_laser_shield.set_owner_team(team_id)
			_laser_shield.reset_health()
		_laser_shield.set_active_shield(_tank_laser_shield_up)
		_update_tank_laser_shield_pose()
	if _tank_laser_shield_up:
		_stop_tank_laser_fire_if_needed()
	if _local_authority():
		_push_tank_laser_shield_health_to_peers()


func _on_tank_laser_shield_broken() -> void:
	# Ignore stale/remote break callbacks when shield is already down.
	if not _tank_laser_shield_up:
		return
	_tank_laser_shield_up = false
	_stop_tank_laser_fire_if_needed()
	tank_laser_shield_health_pct = 0.0
	tank_laser_shield_ui_active = false
	if _local_authority():
		var slot_i: int = _hud_slot_index_for_action("secondary")
		if slot_i >= 0:
			hud_ability_cd_remaining[slot_i] = maxf(hud_ability_cd_remaining[slot_i], TANK_LASER_SHIELD_BREAK_COOLDOWN_SEC)
		_push_tank_laser_shield_state(false)
		_push_tank_laser_shield_health_to_peers()
	_refresh_tank_laser_shield_aura_audio()


func _recall_tank_laser_shield_with_cooldown() -> void:
	if hero_id != "tank_laser":
		return
	var was_up: bool = _tank_laser_shield_up
	_set_tank_laser_shield_up(false)
	_push_tank_laser_shield_state(false)
	if _local_authority() and was_up:
		var slot_i: int = _hud_slot_index_for_action("secondary")
		if slot_i >= 0:
			hud_ability_cd_remaining[slot_i] = maxf(hud_ability_cd_remaining[slot_i], TANK_LASER_SHIELD_BREAK_COOLDOWN_SEC)
	_push_tank_laser_shield_health_to_peers()


func _try_damage_shield_collider(hit_obj: Variant, damage_amount: int) -> bool:
	if hit_obj == null:
		return false
	if not hit_obj.has_method("try_block_projectile"):
		return false
	var shield_node: Node = hit_obj as Node
	if shield_node == null:
		return false
	var owner_player: Node = shield_node.get_parent()
	if owner_player == null:
		return false
	# If this peer owns the shielded player, apply directly once.
	if HeroNet.controls_local_pawn(owner_player):
		var blocked_local: bool = bool(hit_obj.call("try_block_projectile", team_id, damage_amount))
		if blocked_local:
			_push_tank_laser_shield_health_to_peers()
		return blocked_local
	# Otherwise ask the shield owner peer to apply exactly one damage event.
	var owner_id_str: String = str(owner_player.name)
	if not owner_id_str.is_valid_int():
		return false
	var owner_peer_id: int = int(owner_id_str)
	var dmg: int = maxi(1, damage_amount)
	if HeroNet.is_gdsync():
		GDSync.call_func_on(owner_peer_id, Callable(owner_player, "_net_receive_tank_laser_shield_damage"), [dmg, team_id])
	else:
		owner_player._net_receive_tank_laser_shield_damage.rpc_id(owner_player.get_multiplayer_authority(), dmg, team_id)
	return true


@rpc("any_peer", "reliable")
func _net_receive_tank_laser_shield_damage(amount: int, attacker_team_id: int) -> void:
	if not _local_authority():
		return
	if hero_id != "tank_laser":
		return
	if not _tank_laser_shield_up:
		return
	if _laser_shield == null or not is_instance_valid(_laser_shield):
		return
	var hp_before: int = _laser_shield.current_health
	_laser_shield.try_block_projectile(attacker_team_id, amount)
	var blocked_amount: int = maxi(0, hp_before - _laser_shield.current_health)
	if blocked_amount > 0:
		notify_shield_tanked_for_ultimate(blocked_amount)
	_push_tank_laser_shield_health_to_peers()


func _is_me_hostile_to_local_viewer() -> bool:
	var w: Node = get_parent()
	if w == null:
		return false
	var me: Node = w.get_node_or_null(str(HeroNet.my_id()))
	if me == null:
		return false
	return int(me.get("team_id")) != team_id


func _update_tank_laser_shield_pose() -> void:
	if _laser_shield == null or not is_instance_valid(_laser_shield):
		tank_laser_shield_health_pct = 100.0
		tank_laser_shield_ui_active = false
		_refresh_tank_laser_shield_aura_audio()
		return
	_laser_shield.set_hostile_view(_is_me_hostile_to_local_viewer())
	if _laser_shield.max_health > 0:
		tank_laser_shield_health_pct = clampf(100.0 * float(_laser_shield.current_health) / float(_laser_shield.max_health), 0.0, 100.0)
	else:
		tank_laser_shield_health_pct = 0.0
	tank_laser_shield_ui_active = _tank_laser_shield_up and _laser_shield.is_active_shield()
	if _tank_laser_shield_up:
		var forward: Vector3 = (-camera.global_transform.basis.z).normalized()
		var right: Vector3 = Vector3.UP.cross(forward)
		if right.length_squared() < 1e-8:
			right = Vector3.RIGHT
		right = right.normalized()
		var up: Vector3 = forward.cross(right).normalized()
		var basis := Basis(right, up, -forward)
		var pos := camera.global_position + forward * TANK_LASER_SHIELD_FORWARD_OFFSET
		pos.y += (TANK_LASER_SHIELD_HEIGHT_OFFSET - 1.0)
		_laser_shield.global_transform = Transform3D(basis, pos)
	_refresh_tank_laser_shield_aura_audio()


func _push_tank_laser_shield_state(active: bool) -> void:
	if HeroNet.is_gdsync():
		HeroNet.broadcast_call(Callable(self, "_net_set_tank_laser_shield"), [active])
		return
	if multiplayer.multiplayer_peer == null:
		return
	_net_set_tank_laser_shield.rpc(active)


@rpc("any_peer", "reliable")
func _net_set_tank_laser_shield(active: bool) -> void:
	if _local_authority():
		return
	_set_tank_laser_shield_up(active)


func _push_tank_laser_shield_health_to_peers() -> void:
	if not _local_authority():
		return
	if _laser_shield == null or not is_instance_valid(_laser_shield):
		return
	var hp: int = _laser_shield.current_health
	var active: bool = _tank_laser_shield_up and _laser_shield.is_active_shield()
	if HeroNet.is_gdsync():
		HeroNet.broadcast_call(Callable(self, "_net_set_tank_laser_shield_health"), [hp, active])
		return
	if multiplayer.multiplayer_peer == null:
		return
	_net_set_tank_laser_shield_health.rpc(hp, active)


@rpc("any_peer", "reliable")
func _net_set_tank_laser_shield_health(hp: int, active: bool) -> void:
	if _local_authority():
		return
	_ensure_tank_laser_shield()
	if _laser_shield == null or not is_instance_valid(_laser_shield):
		return
	_laser_shield.set_health_value(hp)
	_tank_laser_shield_up = active
	_laser_shield.set_active_shield(active)


func _is_tank_explosive_ultimate_active() -> bool:
	return ultimate_active and hero_id == "tank_explosive"


func _set_tank_laser_ultimate_vfx_active(active: bool, immediate_clear: bool = false) -> void:
	if not active:
		if immediate_clear:
			if _tank_laser_ult_vfx_scale_tween != null and _tank_laser_ult_vfx_scale_tween.is_valid():
				_tank_laser_ult_vfx_scale_tween.kill()
			_tank_laser_ult_vfx_scale_tween = null
			_tank_laser_ult_vfx_shrink_out_active = false
			if _tank_laser_ult_vfx != null and is_instance_valid(_tank_laser_ult_vfx):
				_tank_laser_ult_vfx.queue_free()
			_tank_laser_ult_vfx = null
			_refresh_tank_laser_shield_aura_audio()
			return
		if _tank_laser_ult_vfx_shrink_out_active:
			return
		if _tank_laser_ult_vfx == null or not is_instance_valid(_tank_laser_ult_vfx):
			if _tank_laser_ult_vfx_scale_tween != null and _tank_laser_ult_vfx_scale_tween.is_valid():
				_tank_laser_ult_vfx_scale_tween.kill()
			_tank_laser_ult_vfx_scale_tween = null
			_tank_laser_ult_vfx = null
			_refresh_tank_laser_shield_aura_audio()
			return
		if _tank_laser_ult_vfx_scale_tween != null and _tank_laser_ult_vfx_scale_tween.is_valid():
			_tank_laser_ult_vfx_scale_tween.kill()
		_tank_laser_ult_vfx_scale_tween = null
		var exit_node: Node3D = _tank_laser_ult_vfx
		_tank_laser_ult_vfx_shrink_out_active = true
		var tw_out := create_tween()
		tw_out.set_trans(Tween.TRANS_CUBIC)
		tw_out.set_ease(Tween.EASE_IN)
		tw_out.tween_property(exit_node, "scale", Vector3.ZERO, TANK_LASER_ULT_VFX_SCALE_OUT_SEC)
		tw_out.tween_callback(func() -> void:
			_tank_laser_ult_vfx_shrink_out_active = false
			_tank_laser_ult_vfx_scale_tween = null
			if is_instance_valid(exit_node):
				exit_node.queue_free()
			if _tank_laser_ult_vfx == exit_node:
				_tank_laser_ult_vfx = null
			_refresh_tank_laser_shield_aura_audio()
		)
		_tank_laser_ult_vfx_scale_tween = tw_out
		return
	if _tank_laser_ult_vfx != null and is_instance_valid(_tank_laser_ult_vfx):
		return
	if _tank_laser_ult_vfx_scale_tween != null and _tank_laser_ult_vfx_scale_tween.is_valid():
		_tank_laser_ult_vfx_scale_tween.kill()
	_tank_laser_ult_vfx_scale_tween = null
	var w: Node = get_parent()
	if w == null:
		return
	var inst := TankLaserPulseAreaVfxScene.instantiate()
	if not (inst is Node3D):
		return
	_tank_laser_ult_vfx = inst as Node3D
	_tank_laser_ult_vfx.position = Vector3(0.0, TANK_LASER_ULT_VFX_Y_OFFSET, 0.0)
	_tank_laser_ult_vfx.scale = Vector3.ZERO
	add_child(_tank_laser_ult_vfx)
	if _tank_laser_ult_vfx.has_method("play"):
		_tank_laser_ult_vfx.set("autoplay", false)
		_tank_laser_ult_vfx.set("one_shot", false)
		_tank_laser_ult_vfx.play()
	_update_tank_laser_ultimate_vfx_tint()
	var full_scale: Vector3 = Vector3.ONE * TANK_LASER_ULT_SCALE_MULT
	var tw_in := create_tween()
	tw_in.set_trans(Tween.TRANS_CUBIC)
	tw_in.set_ease(Tween.EASE_OUT)
	tw_in.tween_property(_tank_laser_ult_vfx, "scale", full_scale, TANK_LASER_ULT_VFX_SCALE_IN_SEC)
	tw_in.finished.connect(func() -> void:
		if _tank_laser_ult_vfx_scale_tween == tw_in:
			_tank_laser_ult_vfx_scale_tween = null
	)
	_tank_laser_ult_vfx_scale_tween = tw_in
	_refresh_tank_laser_shield_aura_audio()


func _update_tank_laser_ultimate_vfx_tint() -> void:
	if _tank_laser_ult_vfx == null or not is_instance_valid(_tank_laser_ult_vfx):
		return
	var hostile: bool = _is_me_hostile_to_local_viewer()
	var pcol: Color = Color(1.0, 0.4, 0.4, 1.0) if hostile else Color(0.2, 0.68, 1.0, 1.0)
	var scol: Color = Color(0.78, 0.22, 0.22, 1.0) if hostile else Color(0.38, 0.82, 1.0, 1.0)
	var tcol: Color = Color(0.56, 0.12, 0.12, 1.0) if hostile else Color(0.24, 0.5, 0.96, 1.0)
	_tank_laser_ult_vfx.set("primary_color", pcol)
	_tank_laser_ult_vfx.set("secondary_color", scol)
	_tank_laser_ult_vfx.set("tertiary_color", tcol)
	_tank_laser_ult_vfx.set("light_color", pcol)


func _push_tank_laser_ultimate_visual_state(active: bool) -> void:
	if HeroNet.is_gdsync():
		HeroNet.broadcast_call(Callable(self, "_net_set_tank_laser_ultimate_visual"), [active])
		return
	if multiplayer.multiplayer_peer == null:
		return
	_net_set_tank_laser_ultimate_visual.rpc(active)


@rpc("any_peer", "reliable")
func _net_set_tank_laser_ultimate_visual(active: bool) -> void:
	if _local_authority():
		return
	_set_tank_laser_ultimate_vfx_active(active)


func _activate_hero_ultimate() -> void:
	if ultimate_active or (ultimate_charge + 0.001) < maxf(ultimate_cost, 1.0):
		return
	if hero_id != "tank_explosive" and hero_id != "tank_laser" and hero_id != "dps_missile" and hero_id != "dps_spring" and hero_id != "dps_sniper" and hero_id != "healer_orb" and hero_id != "healer_medic":
		return
	ultimate_active = true
	if hero_id == "tank_explosive":
		_broadcast_tank_ult_activate_sfx()
		ultimate_duration_sec = TANK_EXPLOSIVE_ULT_DURATION_SEC
		ultimate_remaining_sec = TANK_EXPLOSIVE_ULT_DURATION_SEC
		# Active ult should not show reload state; explosive shells fire continuously for its duration.
		_timed_mag_reload_active = false
		_timed_mag_reload_remaining = 0.0
		if magazine_max_clip > 0:
			magazine_current = magazine_max_clip
	elif hero_id == "tank_laser":
		# Tank laser ult disables both primary (beam) and secondary (shield).
		_stop_tank_laser_fire_if_needed()
		_recall_tank_laser_shield_with_cooldown()
		ultimate_duration_sec = TANK_LASER_ULT_DURATION_SEC
		ultimate_remaining_sec = TANK_LASER_ULT_DURATION_SEC
		_tank_laser_ult_push_accum = 0.0
		_set_tank_laser_ultimate_vfx_active(true)
		_push_tank_laser_ultimate_visual_state(true)
	elif hero_id == "dps_missile":
		_broadcast_missile_ult_activate_sfx()
		ultimate_duration_sec = MISSILE_ULT_DURATION_SEC
		ultimate_remaining_sec = MISSILE_ULT_DURATION_SEC
		_missile_ult_hover_active = true
		_missile_ult_arm_delay_left = MISSILE_ULT_ARM_DELAY_SEC
		_missile_ult_has_fired = false
		_missile_ult_hover_target_y = global_position.y + MISSILE_ULT_HOVER_HEIGHT_DELTA
	elif hero_id == "dps_spring":
		ultimate_duration_sec = SPRING_ULT_DURATION_SEC
		ultimate_remaining_sec = SPRING_ULT_DURATION_SEC
		_spring_ult_hover_active = true
		_spring_ult_hover_target_y = global_position.y + SPRING_ULT_HOVER_HEIGHT_DELTA
		_spring_ult_launch_active = false
		_spring_ult_has_launched = false
		_spring_ult_last_valid_target_data.clear()
	elif hero_id == "dps_sniper":
		_sniper_ult_windup_left = SNIPER_ULT_WINDUP_SEC
		ultimate_duration_sec = SNIPER_ULT_WINDUP_SEC
		ultimate_remaining_sec = SNIPER_ULT_WINDUP_SEC
	elif hero_id == "healer_orb":
		ultimate_duration_sec = ORB_ULT_DURATION_SEC
		ultimate_remaining_sec = ORB_ULT_DURATION_SEC
		_begin_orb_ultimate_orbit_state()
	elif hero_id == "healer_medic":
		ultimate_duration_sec = MEDIC_GLOBAL_ULT_DURATION_SEC
		ultimate_remaining_sec = MEDIC_GLOBAL_ULT_DURATION_SEC
		_push_medic_global_ultimate_to_world()
	ultimate_charge = 0.0
	_request_cancel_missile_windup()
	_replicate_combat_state()


func _push_medic_global_ultimate_to_world() -> void:
	var w: Node = get_parent()
	if w == null or not w.has_method("sync_medic_global_ultimate"):
		return
	if not HeroNet.has_multiplayer_session():
		w.sync_medic_global_ultimate(team_id)
	elif HeroNet.is_gdsync():
		HeroNet.broadcast_call(Callable(w, "sync_medic_global_ultimate"), [team_id])
	else:
		w.sync_medic_global_ultimate.rpc(team_id)


func _tank_laser_ultimate_push_tick() -> void:
	var w: Node = get_parent()
	if w == null:
		return
	var candidates: Array = SplashOverlap.character_bodies_in_sphere(
		get_world_3d(),
		global_position,
		TANK_LASER_ULT_PUSH_RADIUS * TANK_LASER_ULT_SCALE_MULT,
		PLAYER_PHYSICS_LAYER,
		[get_rid()]
	)
	for body in candidates:
		if body.get("is_dead") == true:
			continue
		var tid: Variant = body.get("team_id")
		if typeof(tid) != TYPE_INT or int(tid) == team_id:
			continue
		HeroNet.apply_damage_on_victim(body, TANK_LASER_ULT_PUSH_DAMAGE, name.to_int(), true)
		if w.has_method("record_damaged_by_me"):
			w.record_damaged_by_me(body.name.to_int())
		HeroNet.apply_explosion_knockback_on_victim(body, global_position, TANK_LASER_ULT_PUSH_STRENGTH)


func _update_ultimate_state(delta: float) -> void:
	if hero_id == "dps_sniper" and ultimate_active:
		if is_dead:
			ultimate_active = false
			_sniper_ult_windup_left = 0.0
			ultimate_remaining_sec = 0.0
			ultimate_duration_sec = 0.0
			return
		if _sniper_ult_windup_left > 0.0:
			_sniper_ult_windup_left = maxf(0.0, _sniper_ult_windup_left - delta)
			ultimate_remaining_sec = _sniper_ult_windup_left
			if _sniper_ult_windup_left <= 0.0:
				if _local_authority():
					_sniper_ult_execute_burst_and_begin_linger()
				ultimate_active = false
				ultimate_remaining_sec = 0.0
				ultimate_duration_sec = 0.0
			return
		ultimate_active = false
		ultimate_remaining_sec = 0.0
		ultimate_duration_sec = 0.0
		return
	if not ultimate_active:
		_missile_ult_hover_active = false
		_missile_ult_arm_delay_left = 0.0
		_missile_ult_preview_clear()
		_end_orb_ultimate_orbit_state(false)
		_spring_ult_hover_active = false
		if _spring_ult_target_preview != null and is_instance_valid(_spring_ult_target_preview):
			_spring_ult_target_preview.queue_free()
		_spring_ult_target_preview = null
		return
	if is_dead:
		ultimate_active = false
		ultimate_remaining_sec = 0.0
		_missile_ult_hover_active = false
		_missile_ult_arm_delay_left = 0.0
		_missile_ult_preview_clear()
		_end_orb_ultimate_orbit_state(false)
		_spring_ult_hover_active = false
		if _spring_ult_target_preview != null and is_instance_valid(_spring_ult_target_preview):
			_spring_ult_target_preview.queue_free()
		_spring_ult_target_preview = null
		if hero_id == "tank_laser":
			_set_tank_laser_ultimate_vfx_active(false)
			_push_tank_laser_ultimate_visual_state(false)
		return
	ultimate_remaining_sec = maxf(0.0, ultimate_remaining_sec - delta)
	if hero_id == "dps_missile":
		_missile_ult_arm_delay_left = maxf(0.0, _missile_ult_arm_delay_left - delta)
	if hero_id == "tank_explosive":
		if magazine_max_clip > 0:
			magazine_current = magazine_max_clip
		_timed_mag_reload_active = false
		_timed_mag_reload_remaining = 0.0
	elif hero_id == "tank_laser":
		_set_tank_laser_ultimate_vfx_active(true)
		_update_tank_laser_ultimate_vfx_tint()
		_tank_laser_ult_push_accum += delta
		while _tank_laser_ult_push_accum >= TANK_LASER_ULT_PUSH_INTERVAL:
			_tank_laser_ult_push_accum -= TANK_LASER_ULT_PUSH_INTERVAL
			_tank_laser_ultimate_push_tick()
	elif hero_id == "healer_orb":
		_update_orb_ultimate_orbit_visuals(delta)
	if ultimate_remaining_sec <= 0.0:
		if hero_id == "dps_missile" and not _missile_ult_has_fired:
			_missile_ult_try_fire_triplet()
		if hero_id == "dps_spring" and not _spring_ult_has_launched:
			_spring_ult_try_launch()
		if hero_id == "healer_orb":
			_end_orb_ultimate_orbit_state(true)
		ultimate_active = false
		ultimate_remaining_sec = 0.0
		_missile_ult_hover_active = false
		_missile_ult_arm_delay_left = 0.0
		_missile_ult_preview_clear()
		_spring_ult_hover_active = false
		if not _spring_ult_launch_active:
			_spring_ult_has_launched = false
		_spring_ult_last_valid_target_data.clear()
		if _spring_ult_target_preview != null and is_instance_valid(_spring_ult_target_preview):
			_spring_ult_target_preview.queue_free()
		_spring_ult_target_preview = null
		if hero_id == "tank_laser":
			_set_tank_laser_ultimate_vfx_active(false)
			_push_tank_laser_ultimate_visual_state(false)


func _apply_hero_stats() -> void:
	var prev_hero_id: String = _last_hero_id_for_stats
	var hero: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero:
		max_health = hero.max_health
		move_speed = hero.run_speed
		jump_velocity = hero.jump_velocity
		weaponNum = hero.default_weapon
		var mesh_inst: MeshInstance3D = get_node_or_null("MeshInstance3D")
		if mesh_inst:
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = hero.body_color
			mesh_inst.set_surface_override_material(0, mat)
	else:
		max_health = 250
		ultimate_cost = DEFAULT_ULTIMATE_COST
	if hero:
		ultimate_cost = maxf(1.0, hero.ultimate_cost)
	if hero and hero.magazine_size >= 0:
		magazine_max_clip = hero.magazine_size
		magazine_current = hero.magazine_size
	else:
		magazine_max_clip = 0
		magazine_current = -1
	hud_ability_cd_remaining = [0.0, 0.0, 0.0]
	ultimate_charge = clampf(ultimate_charge, 0.0, ultimate_cost)
	if _local_authority():
		health = max_health
		health_changed.emit(health)
		_replicate_combat_state()
	_sniper_fire_cooldown = 0.0
	_sniper_is_reloading = false
	_sniper_reload_left = 0.0
	_sniper_ult_windup_left = 0.0
	_sniper_ult_primary_lock_left = 0.0
	_sniper_ult_linger_left = 0.0
	_sniper_ult_linger_burst_ids.clear()
	_sniper_ult_linger_done_ids.clear()
	_missile_ability_cooldown_left = 0.0
	_missile_targeting_hold_active = false
	_missile_preview_clear()
	_missile_windup_active = false
	if _missile_windup_marker != null and is_instance_valid(_missile_windup_marker):
		_missile_windup_marker.queue_free()
	_missile_windup_marker = null
	_missile_shoot_lock_left = 0.0
	missile_targeting_ui_active = false
	_missile_ult_hover_active = false
	_missile_ult_hover_target_y = 0.0
	_missile_ult_arm_delay_left = 0.0
	_missile_ult_has_fired = false
	_missile_ult_preview_clear()
	_orb_dash_active = false
	_orb_dash_time_left = 0.0
	_orb_dash_velocity_xz = Vector3.ZERO
	_orb_primary_fire_cooldown_left = 0.0
	_end_orb_ultimate_orbit_state(false)
	_timed_mag_reload_remaining = 0.0
	_timed_mag_reload_active = false
	_tank_laser_shield_up = false
	_ensure_tank_laser_shield()
	if _laser_shield != null and is_instance_valid(_laser_shield):
		_laser_shield.set_owner_team(team_id)
		_laser_shield.set_active_shield(false)
	_set_tank_laser_ultimate_vfx_active(false, true)
	_tank_laser_ult_push_accum = 0.0
	ultimate_active = false
	ultimate_duration_sec = 0.0
	ultimate_remaining_sec = 0.0
	if _local_authority() and hero_id != prev_hero_id:
		_reset_local_view_pitch_after_spawn_or_hero_change()
	_last_hero_id_for_stats = hero_id
	_refresh_hero_character_model()
	_sync_muzzle_flash_for_hero()
	_apply_body_locomotion_loop_modes(anim_player)


func _sync_muzzle_flash_for_hero() -> void:
	if muzzle_flash != null:
		muzzle_flash.visible = hero_id != "dps_missile" and not (hero_id == "dps_sniper" and weaponNum == 1)
	if big_muzzle_flash != null:
		big_muzzle_flash.visible = hero_id == "dps_missile"
	if big_muzzle_flash_sniper != null:
		big_muzzle_flash_sniper.visible = hero_id == "dps_sniper" and weaponNum == 1


func _unhandled_input(event):
	if not _local_authority():
		return
	if _character_select_open():
		return
	if is_dead: return
	if _world_match_input_locked() and event is InputEventMouseMotion:
		return

	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_1 and not _world_match_rules_actual():
			_debug_set_health_to_one()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_2:
		if not _world_match_input_locked() and not _world_match_rules_actual():
			ultimate_charge = maxf(ultimate_cost, 1.0)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		var sens: float = GameSettings.get_mouse_look_scale()
		if _is_crosshair_over_enemy_for_aim_slow():
			sens /= CROSSHAIR_AIM_SLOW_ENEMY_DIVISOR
		if hero_id == "dps_missile" and ultimate_active:
			sens *= MISSILE_ULT_LOOK_SENS_MULT
		rotate_y(-event.relative.x * sens)
		camera.rotate_x(-event.relative.y * sens)
		camera.rotation.x = clampf(camera.rotation.x, -CAMERA_PITCH_LIMIT_RAD, CAMERA_PITCH_LIMIT_RAD)

	if _world_match_input_locked():
		return

	if Input.is_action_just_pressed("reload"):
		_try_reload_magazine()
	if Input.is_action_just_pressed("ultimate"):
		_activate_hero_ultimate()

	# Explosive tank: E — place a landmine (cooldown + max active handled in `landmine.gd`).
	if Input.is_action_just_pressed("ability_e"):
		if hero_id == "tank_explosive" and weaponNum == 1:
			var slot_e: int = _hud_slot_index_for_action("ability_e")
			if slot_e >= 0 and hud_ability_cd_remaining[slot_e] <= 0.0:
				var sid_m: int = HeroNet.my_id()
				var dir_m: Vector3 = projectile_aim_direction_from_muzzle().normalized()
				_rpc_play_shoot_effects_for_all()
				_spawn_landmine(muzzle_flash.global_position, dir_m * LANDMINE_THROW_SPEED, sid_m)
				_rpc_spawn_landmine_all(muzzle_flash.global_position, dir_m * LANDMINE_THROW_SPEED, sid_m)
				var cd_e: float = _get_hud_slot_cooldown_duration(slot_e)
				if cd_e > 0.0:
					hud_ability_cd_remaining[slot_e] = cd_e

	# Explosive tank: right-click — same aim + shoot gate as primary (`projectile_aim_direction_from_muzzle`, no fire during shoot anim).
	if Input.is_action_just_pressed("secondary"):
		if hero_id == "healer_orb" and weaponNum == 2 and not ultimate_active:
			_orb_try_dash_secondary()
		if hero_id == "tank_laser" and weaponNum == 1 and not ultimate_active:
			var slot_laser: int = _hud_slot_index_for_action("secondary")
			var on_cd: bool = (slot_laser >= 0 and hud_ability_cd_remaining[slot_laser] > 0.0)
			if _tank_laser_shield_up:
				_recall_tank_laser_shield_with_cooldown()
			elif not on_cd:
				_set_tank_laser_shield_up(true)
				_push_tank_laser_shield_state(true)
		if hero_id == "tank_explosive" and weaponNum == 1 and anim_player.current_animation != "shoot":
			var slot_i: int = _hud_slot_index_for_action("secondary")
			if slot_i >= 0 and hud_ability_cd_remaining[slot_i] <= 0.0:
				var shooter_peer_id_r: int = HeroNet.my_id()
				var aim_dir_r: Vector3 = projectile_aim_direction_from_muzzle()
				_apply_tank_secondary_fire_recoil(aim_dir_r)
				_rpc_play_shoot_effects_for_all()
				_spawn_tank_round(muzzle_flash.global_position, aim_dir_r, shooter_peer_id_r, 1)
				_rpc_spawn_tank_round_all(muzzle_flash.global_position, aim_dir_r, shooter_peer_id_r, 1)
				var cd_len: float = _get_hud_slot_cooldown_duration(slot_i)
				if cd_len > 0.0:
					hud_ability_cd_remaining[slot_i] = cd_len
	if Input.is_action_just_pressed("shoot"):
		# Spring: charged punch — hold in _physics_process, release to strike.
		if hero_id == "dps_spring" and weaponNum == 1:
			if not ultimate_active:
				_spring_try_begin_charge()
		# Continuous beam: hold-to-fire is handled in _physics_process (no hitscan tap here).
		elif hero_id == "tank_laser" and weaponNum == 1:
			pass
		elif _hero_archetype() == "medic" and weaponNum == 2:
			pass
		elif hero_id == "dps_missile" and weaponNum == 1:
			pass
		elif hero_id == "dps_sniper" and weaponNum == 1:
			pass
		elif anim_player.current_animation != "shoot":
			if hero_id == "healer_orb" and weaponNum == 2 and (ultimate_active or _orb_primary_fire_cooldown_left > 0.0):
				return
			_rpc_play_shoot_effects_for_all()
			# Orb healer: primary fires bouncing heal orbs (gate on hero_id — archetype can read as "healer_orb" if registry load fails).
			if hero_id == "healer_orb" and weaponNum == 2:
				var shooter_peer_id: int = HeroNet.my_id()
				var aim_dir: Vector3 = projectile_aim_direction_from_muzzle()
				_spawn_heal_orb(
					muzzle_flash.global_position,
					aim_dir,
					shooter_peer_id
				)
				_sync_play_orb_shoot_only()
				_rpc_spawn_heal_orb_all(muzzle_flash.global_position, aim_dir, shooter_peer_id)
				_orb_primary_fire_cooldown_left = ORB_PRIMARY_MIN_FIRE_INTERVAL_SEC
			# Tank: explosive shells (laser hero uses continuous beam in _physics_process).
			elif _hero_archetype() == "tank" and weaponNum == 1:
				if hero_id == "tank_explosive":
					var hero_tank: HeroResource = HeroesRegistry.get_hero(hero_id)
					if hero_tank != null and hero_tank.magazine_size >= 0:
						if not _is_tank_explosive_ultimate_active() and (_timed_mag_reload_active or magazine_current <= 0):
							return
				var shooter_peer_id: int = HeroNet.my_id()
				var aim_dir_tank: Vector3 = projectile_aim_direction_from_muzzle()
				_spawn_tank_round(
					muzzle_flash.global_position,
					aim_dir_tank,
					shooter_peer_id,
					0
				)
				_rpc_spawn_tank_round_all(muzzle_flash.global_position, aim_dir_tank, shooter_peer_id, 0)
				if hero_id == "tank_explosive":
					var hero_d: HeroResource = HeroesRegistry.get_hero(hero_id)
					if hero_d != null and hero_d.magazine_size >= 0 and not _is_tank_explosive_ultimate_active():
						magazine_current = maxi(magazine_current - 1, 0)
						_maybe_auto_reload_after_primary_empty()
			# Medic: purple burst projectile primary with small splash.
			elif _hero_archetype() == "medic" and weaponNum == 1:
				var medic_shooter_peer_id: int = HeroNet.my_id()
				var aim_dir_burst: Vector3 = projectile_aim_direction_from_muzzle()
				_broadcast_medic_pulse_fire_sfx()
				_spawn_medic_burst(
					muzzle_flash.global_position,
					aim_dir_burst,
					medic_shooter_peer_id
				)
				_rpc_spawn_medic_burst_all(muzzle_flash.global_position, aim_dir_burst, medic_shooter_peer_id)
			elif hero_id == "dps_spring" and weaponNum == 1:
				pass
			else:
				if raycast.is_colliding():
					var hit_player = raycast.get_collider()
					if _try_damage_shield_collider(hit_player, HITSCAN_DAMAGE):
						return
					if hit_player != null and hit_player.has_method("receive_damage") and hit_player.has_method("heal_damage"):
						var target_team = hit_player.get("team_id")
						if typeof(target_team) != TYPE_INT:
							return
						if weaponNum == 1 and int(target_team) != team_id:
							# Damage only enemies
							HeroNet.apply_damage_on_victim(hit_player, HITSCAN_DAMAGE, name.to_int())
							get_parent().record_damaged_by_me(hit_player.name.to_int())
						elif weaponNum == 2 and int(target_team) == team_id and _hero_archetype() != "medic":
							# Heal only allies (medic uses hold-beam targeting; no crosshair tap heal).
							HeroNet.apply_heal_on_target(hit_player, HITSCAN_HEAL, name.to_int())

func _physics_process(delta: float) -> void:
	_body_shoot_hold_left = maxf(0.0, _body_shoot_hold_left - delta)
	if hero_id != _last_hero_id_for_stats:
		_apply_hero_stats()
	_update_dead_visibility()
	if _local_authority():
		_sync_camera_mode_from_game_state()
		_update_third_person_camera_position()
		_tick_hud_ability_cooldowns(delta)
		_missile_ability_cooldown_left = maxf(0.0, _missile_ability_cooldown_left - delta)
		_tank_laser_release_cooldown_left = maxf(0.0, _tank_laser_release_cooldown_left - delta)
		_missile_shoot_lock_left = maxf(0.0, _missile_shoot_lock_left - delta)
		_orb_primary_fire_cooldown_left = maxf(0.0, _orb_primary_fire_cooldown_left - delta)
		_sniper_ult_primary_lock_left = maxf(0.0, _sniper_ult_primary_lock_left - delta)
		_update_sniper_ult_linger(delta)
		_maybe_sniper_smoke_secondary_press()
		if hero_id != "tank_laser" and _tank_laser_shield_up:
			_set_tank_laser_shield_up(false)
			_push_tank_laser_shield_state(false)
		_update_tank_laser_shield_pose()
		_update_timed_mag_reload(delta)
		_update_ultimate_state(delta)
		_update_missile_full_auto(delta)
		_update_missile_secondary_targeting()
		_update_spring_ultimate_targeting()
		_update_sniper_combat(delta)
		_spring_update_punch_charge(delta)
		_spring_update_jump_charge(delta)
	if not _local_authority():
		_update_tank_laser_shield_pose()
		if hero_id == "healer_orb" and _orb_ult_orbit_active:
			_update_orb_ultimate_orbit_visuals(delta)
		if _net_medic_beam_replica_active and _continuous_heal_beam != null and is_instance_valid(_continuous_heal_beam):
			_continuous_heal_beam.update_beam(_net_medic_beam_snap_start, _net_medic_beam_snap_end, _net_medic_beam_snap_fwd, delta)
		# Remote pawns should emit their own 3D footsteps so other players can hear them.
		# Remote replicas do not run full floor collision, so use a permissive grounded heuristic.
		_update_footstep_audio(delta, false)
		if HeroNet.is_gdsync() and not is_dead:
			_gdsync_smooth_remote_motion(delta)
		# Replicated players do not run local input code; drive body locomotion from synced velocity.
		var remote_speed: float = _remote_horizontal_speed_from_pos_delta(delta)
		_update_locomotion_animation_from_velocity(false, remote_speed)
		_jump_slide_was_on_floor = is_on_floor()
		return
	if is_dead: return
	if global_position.y < VOID_KILL_WORLD_Y:
		receive_damage(maxi(max_health, 9999), -1, true)
		return
	_tick_spawn_room_heal(delta)
	# Add the gravity.
	_apply_missile_ult_hover(delta)
	_apply_spring_ult_hover(delta)
	if not is_on_floor():
		if not ((hero_id == "dps_missile" and ultimate_active and _missile_ult_hover_active) or (hero_id == "dps_spring" and ((ultimate_active and _spring_ult_hover_active) or _spring_ult_launch_active))):
			velocity.y -= gravity * delta

	if _pawn_soft_lock():
		_interrupt_jump_body_animation_if_needed()
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		if anim_player.current_animation != "shoot":
			_try_play_pistol_idle_or_move(&"idle")
		move_and_slide()
		_physics_jump_body_step_after_move(is_on_floor())
		if _local_authority():
			_update_tank_laser_continuous_beam(delta)
			_update_medic_heal_continuous_beam(delta)
			_update_footstep_audio(delta)
		_maybe_push_gdsync_transform(delta)
		return
	if hero_id == "dps_spring" and _spring_ult_launch_active:
		# Never rotate Spring model during ult launch; keep body upright.
		rotation.x = 0.0
		rotation.z = 0.0
		move_and_slide()
		_physics_jump_body_step_after_move(is_on_floor())
		if is_on_floor():
			_spring_ult_launch_active = false
			rotation.x = 0.0
			rotation.z = 0.0
			_spring_ult_land_shockwave()
			ultimate_active = false
			ultimate_remaining_sec = 0.0
		_maybe_push_gdsync_transform(delta)
		return
	if _orb_dash_active:
		_orb_update_dash(delta)
		move_and_slide()
		_physics_jump_body_step_after_move(is_on_floor())
		if _local_authority():
			_update_tank_laser_continuous_beam(delta)
			_update_medic_heal_continuous_beam(delta)
			if not is_dead and not _pawn_soft_lock():
				_grant_ultimate_charge(ultimate_cost * ULTIMATE_PASSIVE_FRACTION_PER_SEC * delta)
			_update_footstep_audio(delta)
		_maybe_push_gdsync_transform(delta)
		return

	# Handle jump.
	if hero_id == "dps_spring" and is_on_floor() and Input.is_action_just_pressed("jump"):
		_spring_begin_jump_charge()
	elif Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir: Vector2 = Input.get_vector("left", "right", "up", "down")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var eff_move_speed: float = move_speed
	if hero_id == "tank_laser" and ultimate_active:
		eff_move_speed *= TANK_LASER_ULT_MOVE_MULT
	if hero_id == "healer_orb" and ultimate_active:
		eff_move_speed *= ORB_ULT_MOVE_MULT
	if hero_id == "tank_laser" and _tank_laser_shield_up:
		eff_move_speed *= TANK_LASER_SHIELD_MOVE_MULT_WHILE_UP
	if hero_id == "dps_spring" and _spring_jump_charging and is_on_floor():
		eff_move_speed *= SPRING_JUMP_CHARGE_MOVE_MULT
	if is_on_floor():
		_air_momentum_floor_prev = true
		if direction:
			velocity.x = direction.x * eff_move_speed
			velocity.z = direction.z * eff_move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, eff_move_speed)
			velocity.z = move_toward(velocity.z, 0, eff_move_speed)
	elif _air_momentum_floor_prev:
		_jump_air_begin_takeoff_snapshot(eff_move_speed)
		_air_momentum_floor_prev = false
	if not is_on_floor():
		var h: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		var f: Vector3 = _jump_takeoff_forward_xz
		var cap_spd: float = _jump_takeoff_h_cap
		var dir_xz := Vector3(direction.x, 0.0, direction.z)
		if dir_xz.length_squared() > 1e-8:
			var wish: Vector3 = dir_xz.normalized()
			var wish_dot_f: float = wish.dot(f)
			var wish_perp: Vector3 = wish - f * wish_dot_f
			if wish_perp.length_squared() > 1e-8:
				wish_perp = wish_perp.normalized()
				var pa: float = AIR_PERP_ACCEL_SPRING if hero_id == "dps_spring" else AIR_PERP_ACCEL
				h += wish_perp * pa * delta
			if wish_dot_f < -0.22:
				var h_along: float = h.dot(f)
				if h_along > 0.0:
					var brake_amt: float = minf(AIR_PARALLEL_BRAKE * delta * absf(wish_dot_f), h_along)
					h -= f * brake_amt
		var h_len_sq: float = h.length_squared()
		var cap_sq: float = cap_spd * cap_spd
		if h_len_sq > cap_sq and cap_sq > 1e-8:
			var hl: float = sqrt(h_len_sq)
			h *= cap_spd / maxf(hl, 1e-8)
		if hero_id == "dps_spring" and ultimate_active and not _spring_ult_launch_active:
			var hs2: float = h.length_squared()
			var ult_cap2: float = SPRING_ULT_AIR_TOP_SPEED * SPRING_ULT_AIR_TOP_SPEED
			if hs2 > ult_cap2 and ult_cap2 > 1e-8:
				h = h.normalized() * SPRING_ULT_AIR_TOP_SPEED
		velocity.x = h.x
		velocity.z = h.z
		
	_update_locomotion_animation_from_velocity(true)


	move_and_slide()
	_physics_jump_body_step_after_move(is_on_floor())
	if _local_authority():
		_update_tank_laser_continuous_beam(delta)
		_update_medic_heal_continuous_beam(delta)
		if not is_dead and not _pawn_soft_lock():
			_grant_ultimate_charge(ultimate_cost * ULTIMATE_PASSIVE_FRACTION_PER_SEC * delta)
		_update_footstep_audio(delta)
	_maybe_push_gdsync_transform(delta)


func _init_footstep_audio() -> void:
	_footstep_player = AudioStreamPlayer3D.new()
	_footstep_player.name = "FootstepAudio3D"
	_footstep_player.max_distance = 22.0
	_footstep_player.unit_size = 4.0
	_footstep_player.max_polyphony = 2
	_footstep_player.bus = "Master"
	add_child(_footstep_player)
	_footstep_streams = _load_footstep_streams()
	if _footstep_streams.is_empty():
		push_warning("No footstep WAV files found in %s (expected step#_#.wav)." % FOOTSTEP_SFX_DIR)


func _load_footstep_streams() -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	var dir: DirAccess = DirAccess.open(FOOTSTEP_SFX_DIR)
	if dir == null:
		return out
	var rx := RegEx.new()
	rx.compile("^step\\d+_\\d+\\.wav$")
	dir.list_dir_begin()
	var fn: String = dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			if rx.search(fn.to_lower()) != null:
				var full_path: String = "%s/%s" % [FOOTSTEP_SFX_DIR, fn]
				var loaded: Resource = load(full_path)
				if loaded is AudioStream:
					out.append(loaded as AudioStream)
		fn = dir.get_next()
	dir.list_dir_end()
	return out


func _update_footstep_audio(delta: float, require_floor: bool = true) -> void:
	if _footstep_player == null or _footstep_streams.is_empty():
		return
	_footstep_cooldown_left = maxf(0.0, _footstep_cooldown_left - delta)
	if is_dead or _pawn_soft_lock() or _orb_dash_active or _spring_ult_launch_active:
		_footstep_cooldown_left = 0.0
		_footstep_move_hold_sec = 0.0
		return
	var grounded_ok: bool = is_on_floor() if require_floor else absf(velocity.y) < 1.0
	if not grounded_ok:
		_footstep_cooldown_left = 0.0
		_footstep_move_hold_sec = 0.0
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < FOOTSTEP_MIN_MOVE_SPEED:
		_footstep_cooldown_left = 0.0
		_footstep_move_hold_sec = 0.0
		return
	_footstep_move_hold_sec += delta
	if _footstep_cooldown_left > 0.0:
		return
	if _footstep_move_hold_sec < FOOTSTEP_MOVEMENT_PREROLL_SEC:
		return
	var i: int = _footstep_rng.randi_range(0, _footstep_streams.size() - 1)
	_footstep_player.stream = _footstep_streams[i]
	_footstep_player.pitch_scale = _footstep_rng.randf_range(0.95, 1.06)
	_footstep_player.volume_db = _footstep_rng.randf_range(-18.0, -14.5)
	_footstep_player.play()
	var t: float = inverse_lerp(FOOTSTEP_MIN_MOVE_SPEED, FOOTSTEP_SPEED_REF, horizontal_speed)
	t = clampf(t, 0.0, 1.0)
	if t < 0.45:
		_footstep_cooldown_left = lerpf(FOOTSTEP_INTERVAL_SLOW, FOOTSTEP_INTERVAL_WALK, t / 0.45)
	else:
		_footstep_cooldown_left = lerpf(FOOTSTEP_INTERVAL_WALK, FOOTSTEP_INTERVAL_RUN, (t - 0.45) / 0.55)


func _init_missile_audio() -> void:
	_missile_fly_streams.clear()
	for p in MISSILE_FLY_STREAM_PATHS:
		var res: Resource = load(str(p))
		if res is AudioStream:
			_missile_fly_streams.append(res as AudioStream)
	var ult_res: Resource = load(MISSILE_ULT_STREAM_PATH)
	if ult_res is AudioStream:
		_missile_ult_stream = ult_res as AudioStream
	var shot_res: Resource = load(MISSILE_SINGLE_SHOT_STREAM_PATH)
	if shot_res is AudioStream:
		_missile_single_shot_stream = shot_res as AudioStream
	_missile_fly_player = _make_missile_audio_player("MissileFlyAudio3D", 20.0, 4.0, 2)
	_missile_ult_player = _make_missile_audio_player("MissileUltAudio3D", 22.0, 4.0, 1)
	_missile_single_shot_player = _make_missile_audio_player("MissileSingleShotAudio3D", 18.0, 4.0, 4)


func _init_tank_audio() -> void:
	var ult_res: Resource = load(TANK_ULT_STREAM_PATH)
	if ult_res is AudioStream:
		_tank_ult_stream = ult_res as AudioStream
	_tank_ult_player = _make_missile_audio_player("TankUltAudio3D", 34.0, 6.0, 1)


func _make_missile_audio_player(player_name: String, max_distance: float, unit_size: float, max_polyphony: int, attach_parent: Node = null) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = player_name
	p.max_distance = max_distance
	p.unit_size = unit_size
	p.max_polyphony = max_polyphony
	p.attenuation_filter_cutoff_hz = 20500.0
	p.attenuation_filter_db = 0.0
	p.bus = "Master"
	var mount: Node = attach_parent if attach_parent != null else self
	mount.add_child(p)
	return p


func _play_missile_fly_sfx() -> void:
	if _missile_fly_player == null or _missile_fly_streams.is_empty():
		return
	var i: int = _footstep_rng.randi_range(0, _missile_fly_streams.size() - 1)
	_missile_fly_player.stream = _missile_fly_streams[i]
	_missile_fly_player.pitch_scale = _footstep_rng.randf_range(0.98, 1.03)
	_missile_fly_player.volume_db = MISSILE_FLY_BASE_DB
	_missile_fly_player.play()


func _play_missile_ult_activate_sfx() -> void:
	if _missile_ult_player == null or _missile_ult_stream == null:
		return
	_missile_ult_player.stream = _missile_ult_stream
	_missile_ult_player.pitch_scale = 1.0
	_missile_ult_player.volume_db = MISSILE_ULT_BASE_DB
	_missile_ult_player.play()


func _play_tank_ult_sfx() -> void:
	if _tank_ult_player == null or _tank_ult_stream == null:
		return
	_tank_ult_player.stream = _tank_ult_stream
	_tank_ult_player.pitch_scale = 1.0
	_tank_ult_player.volume_db = TANK_ULT_SFX_DB
	_tank_ult_player.play()


func _play_missile_single_shot_sfx() -> void:
	if _missile_single_shot_player == null or _missile_single_shot_stream == null:
		return
	_missile_single_shot_player.stream = _missile_single_shot_stream
	_missile_single_shot_player.pitch_scale = _footstep_rng.randf_range(0.99, 1.02)
	var vol_db: float = MISSILE_PRIMARY_SFX_HALF_DB
	if _local_authority():
		vol_db += MISSILE_PRIMARY_LOCAL_EXTRA_HALF_DB
	_missile_single_shot_player.volume_db = vol_db
	_missile_single_shot_player.play()


func _init_medic_audio() -> void:
	var heal_res: Resource = load(MEDIC_HEALGUN_STREAM_PATH)
	if heal_res is AudioStream:
		_medic_healgun_stream = heal_res as AudioStream
	var pulse_res: Resource = load(MEDIC_PULSE_FIRE_STREAM_PATH)
	if pulse_res is AudioStream:
		_medic_pulse_fire_stream = pulse_res as AudioStream
	_medic_healgun_player = _make_missile_audio_player("MedicHealgunAudio3D", 24.0, 4.5, 2)
	_medic_pulse_fire_player = _make_missile_audio_player("MedicPulseFireAudio3D", 22.0, 4.0, 3)


func _init_healing_received_audio() -> void:
	var heal_recv_res: Resource = load(HEALING_RECEIVED_STREAM_PATH)
	if heal_recv_res is AudioStream:
		_healing_received_stream = heal_recv_res as AudioStream
	_healing_received_player = AudioStreamPlayer.new()
	_healing_received_player.name = "HealingReceivedAudio"
	_healing_received_player.bus = "Master"
	add_child(_healing_received_player)


func _init_orb_audio() -> void:
	## Single load attempt avoids duplicate engine errors if import cache is missing (open project in editor once).
	var shoot_res: Resource = load(ORB_SHOOT_STREAM_PATH)
	if shoot_res is AudioStream:
		_orb_shoot_stream = shoot_res as AudioStream
	elif not ResourceLoader.exists(ORB_SHOOT_STREAM_PATH):
		push_warning("Orb shoot WAV missing: %s" % ORB_SHOOT_STREAM_PATH)
	else:
		push_warning("Orb shoot SFX failed to load (reimport audio in Godot editor): %s" % ORB_SHOOT_STREAM_PATH)
	var ult_res: Resource = load(ORB_ULT_STREAM_PATH)
	if ult_res is AudioStream:
		_orb_ult_stream = ult_res as AudioStream
	var orb_mount: Node = muzzle_flash if muzzle_flash != null else self
	_orb_shoot_player = _make_missile_audio_player("OrbShootAudio3D", 48.0, 6.0, 4, orb_mount)
	_orb_ult_player = _make_missile_audio_player("OrbUltAudio3D", 26.0, 4.5, 1)


func _init_laser_once_audio() -> void:
	var res: Resource = ResourceLoader.load(LASER_ONCE_STREAM_PATH, "AudioStream")
	if res == null:
		res = load(LASER_ONCE_STREAM_PATH)
	if res is AudioStream:
		_laser_once_stream = res as AudioStream
	else:
		push_warning("Laser tick SFX missing or failed to load: %s" % LASER_ONCE_STREAM_PATH)
	# Emitter lives under the world root so impact positions stay stable (not carried by the moving tank body).
	var mount: Node = get_parent()
	if mount == null:
		mount = self
	_laser_damage_tick_player = _make_missile_audio_player("LaserDamageTickAudio3D", 56.0, 6.0, 12, mount)


func _init_laser_shield_aura_audio() -> void:
	if _laser_shield_aura_player != null:
		return
	var res: Resource = ResourceLoader.load(LASER_SHIELD_AURA_STREAM_PATH, "AudioStream")
	if res == null:
		res = load(LASER_SHIELD_AURA_STREAM_PATH)
	if res is AudioStream:
		var dup: AudioStream = (res as AudioStream).duplicate()
		if dup is AudioStreamMP3:
			(dup as AudioStreamMP3).loop = true
		_laser_shield_aura_stream = dup
	else:
		push_warning("Laser shield aura SFX missing or failed to load: %s" % LASER_SHIELD_AURA_STREAM_PATH)
	_laser_shield_aura_player = _make_missile_audio_player("LaserShieldAuraAudio3D", 26.0, 5.5, 1)
	_laser_shield_aura_player.position = Vector3(0.0, 1.1, 0.0)


func _init_sniper_audio() -> void:
	var shot_res: Resource = load(SNIPER_SHOT_STREAM_PATH)
	if shot_res is AudioStream:
		_sniper_shot_stream = shot_res as AudioStream
	var prime_res: Resource = load(SNIPER_SMOKE_PRIME_STREAM_PATH)
	if prime_res is AudioStream:
		_sniper_smoke_prime_stream = prime_res as AudioStream
	var ult_hit_res: Resource = ResourceLoader.load(SNIPER_ULT_HIT_STREAM_PATH, "AudioStream")
	if ult_hit_res == null:
		ult_hit_res = load(SNIPER_ULT_HIT_STREAM_PATH)
	if ult_hit_res is AudioStream:
		_sniper_ult_hit_stream = ult_hit_res as AudioStream
	var sniper_mount: Node = muzzle_flash if muzzle_flash != null else self
	_sniper_shot_player = _make_missile_audio_player("SniperShotAudio3D", 56.0, 6.0, 4, sniper_mount)
	_sniper_smoke_prime_player = _make_missile_audio_player("SniperSmokePrimeAudio3D", 48.0, 5.5, 2, sniper_mount)
	_sniper_ult_hit_player = AudioStreamPlayer.new()
	_sniper_ult_hit_player.name = "SniperUltHitAudio"
	_sniper_ult_hit_player.bus = "Master"
	add_child(_sniper_ult_hit_player)


func _init_reload_audio() -> void:
	var rm: Resource = load(RELOAD_MISSILE_STREAM_PATH)
	if rm is AudioStream:
		_reload_missile_stream = rm as AudioStream
	var rs: Resource = load(RELOAD_SNIPER_STREAM_PATH)
	if rs is AudioStream:
		_reload_sniper_stream = rs as AudioStream
	var re: Resource = load(RELOAD_EXPLOSIVE_STREAM_PATH)
	if re is AudioStream:
		_reload_explosive_stream = re as AudioStream
	var mount: Node = muzzle_flash if muzzle_flash != null else self
	_reload_player = _make_missile_audio_player("ReloadAudio3D", 24.0, 4.5, 1, mount)


func _play_reload_sfx_local() -> void:
	if _reload_player == null:
		return
	var stream: AudioStream = null
	match hero_id:
		"dps_missile":
			stream = _reload_missile_stream
		"dps_sniper":
			stream = _reload_sniper_stream
		"tank_explosive":
			stream = _reload_explosive_stream
		_:
			return
	if stream == null:
		return
	_reload_player.stream = stream
	_reload_player.pitch_scale = _footstep_rng.randf_range(0.98, 1.02)
	_reload_player.volume_db = RELOAD_SFX_DB
	_reload_player.play()


func _sync_reload_sfx() -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_net_play_reload_sfx"), [])
	elif multiplayer.multiplayer_peer == null:
		_net_play_reload_sfx()
	else:
		_net_play_reload_sfx.rpc()


@rpc("any_peer", "reliable", "call_local")
func _net_play_reload_sfx() -> void:
	_play_reload_sfx_local()


func _play_sniper_shot_sfx() -> void:
	if hero_id != "dps_sniper":
		return
	if _sniper_shot_player == null or _sniper_shot_stream == null:
		return
	_sniper_shot_player.stream = _sniper_shot_stream
	_sniper_shot_player.volume_db = SNIPER_SHOT_SFX_DB
	_sniper_shot_player.play()


func _sync_sniper_smoke_prime_sfx() -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_net_play_sniper_smoke_prime_sfx"), [])
	elif multiplayer.multiplayer_peer == null:
		_net_play_sniper_smoke_prime_sfx()
	else:
		_net_play_sniper_smoke_prime_sfx.rpc()


@rpc("any_peer", "reliable", "call_local")
func _net_play_sniper_smoke_prime_sfx() -> void:
	if hero_id != "dps_sniper":
		return
	if _sniper_smoke_prime_player == null or _sniper_smoke_prime_stream == null:
		return
	_sniper_smoke_prime_player.stream = _sniper_smoke_prime_stream
	_sniper_smoke_prime_player.volume_db = SNIPER_SMOKE_PRIME_SFX_DB
	_sniper_smoke_prime_player.play()


func _play_sniper_ult_hit_local() -> void:
	if _sniper_ult_hit_player == null or _sniper_ult_hit_stream == null:
		return
	var dup: AudioStream = _sniper_ult_hit_stream.duplicate()
	if dup is AudioStreamMP3:
		(dup as AudioStreamMP3).loop = false
	_sniper_ult_hit_player.stream = dup
	_sniper_ult_hit_player.volume_db = SNIPER_ULT_HIT_SFX_DB
	_sniper_ult_hit_player.play()


func _sync_sniper_ult_hit_feedback_on_victim(victim: Node) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	if not victim.has_method("_net_receive_sniper_ult_hit_sfx"):
		return
	if HeroNet.is_gdsync():
		var vid: int = int(str(victim.name))
		GDSync.call_func_on(vid, Callable(victim, "_net_receive_sniper_ult_hit_sfx"), [])
	elif not HeroNet.has_multiplayer_session():
		victim._net_receive_sniper_ult_hit_sfx()
	else:
		victim._net_receive_sniper_ult_hit_sfx.rpc_id(victim.get_multiplayer_authority())


@rpc("any_peer", "reliable")
func _net_receive_sniper_ult_hit_sfx() -> void:
	if not HeroNet.controls_local_pawn(self):
		return
	_play_sniper_ult_hit_local()


func _tank_laser_shield_aura_should_play() -> bool:
	if hero_id != "tank_laser":
		return false
	if tank_laser_shield_ui_active:
		return true
	if _tank_laser_ult_vfx != null and is_instance_valid(_tank_laser_ult_vfx):
		return true
	return false


func _tank_laser_shield_aura_volume_db() -> float:
	var db: float = LASER_SHIELD_AURA_DB
	if _tank_laser_ult_vfx != null and is_instance_valid(_tank_laser_ult_vfx):
		db += LASER_SHIELD_AURA_ULT_EXTRA_DB
	return db


func _refresh_tank_laser_shield_aura_audio() -> void:
	if hero_id != "tank_laser":
		if _laser_shield_aura_player != null and _laser_shield_aura_player.playing:
			_laser_shield_aura_player.stop()
		return
	if _laser_shield_aura_player == null or _laser_shield_aura_stream == null:
		_init_laser_shield_aura_audio()
	if _laser_shield_aura_player == null or _laser_shield_aura_stream == null:
		return
	var want: bool = _tank_laser_shield_aura_should_play()
	if not want:
		if _laser_shield_aura_player.playing:
			_laser_shield_aura_player.stop()
		return
	if _laser_shield_aura_player.stream != _laser_shield_aura_stream:
		if _laser_shield_aura_player.playing:
			_laser_shield_aura_player.stop()
		_laser_shield_aura_player.stream = _laser_shield_aura_stream
	var target_vol: float = _tank_laser_shield_aura_volume_db()
	if not is_equal_approx(_laser_shield_aura_player.volume_db, target_vol):
		_laser_shield_aura_player.volume_db = target_vol
	if not _laser_shield_aura_player.playing:
		_laser_shield_aura_player.play()


func _laser_damage_pitch_scale() -> float:
	var t := clampf(_tank_laser_pitch_hold_sec / LASER_ONCE_PITCH_RAMP_SEC, 0.0, 1.0)
	return lerpf(LASER_ONCE_PITCH_MIN, LASER_ONCE_PITCH_MAX, t)


## Local laser user: 3D cue at true hit / target (unchanged). Other clients ignore this.
func _play_laser_owner_tick_sfx(world_pos: Vector3, pitch_scale: float) -> void:
	if not HeroNet.controls_local_pawn(self):
		return
	if _laser_damage_tick_player == null or _laser_once_stream == null:
		return
	_laser_damage_tick_player.global_position = world_pos
	_laser_damage_tick_player.stream = _laser_once_stream
	_laser_damage_tick_player.pitch_scale = pitch_scale
	_laser_damage_tick_player.volume_db = LASER_ONCE_SFX_DB
	_laser_damage_tick_player.play()


## Other players: one cue per tick at the beam tip (muzzle → crosshair end), not on the tank's body.
func _sync_laser_remote_tick_sfx(beam_end_global: Vector3, pitch_scale: float) -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_net_play_laser_remote_tick_sfx"), [beam_end_global, pitch_scale])
	elif multiplayer.multiplayer_peer == null:
		_net_play_laser_remote_tick_sfx(beam_end_global, pitch_scale)
	else:
		_net_play_laser_remote_tick_sfx.rpc(beam_end_global, pitch_scale)


@rpc("any_peer", "reliable")
func _net_play_laser_remote_tick_sfx(beam_end_global: Vector3, pitch_scale: float) -> void:
	if HeroNet.controls_local_pawn(self):
		return
	if hero_id != "tank_laser":
		return
	if _laser_damage_tick_player == null or _laser_once_stream == null:
		return
	_laser_damage_tick_player.global_position = beam_end_global
	_laser_damage_tick_player.stream = _laser_once_stream
	_laser_damage_tick_player.pitch_scale = pitch_scale
	_laser_damage_tick_player.volume_db = LASER_ONCE_SFX_DB
	_laser_damage_tick_player.play()


func _sync_play_orb_shoot_only() -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "play_orb_shoot_only"), [])
	elif multiplayer.multiplayer_peer == null:
		play_orb_shoot_only()
	else:
		play_orb_shoot_only.rpc()


func _play_orb_ult_sfx_start() -> void:
	if _orb_ult_fade_tween != null:
		_orb_ult_fade_tween.kill()
		_orb_ult_fade_tween = null
	if _orb_ult_player == null or _orb_ult_stream == null:
		return
	_orb_ult_player.stop()
	_orb_ult_player.volume_db = ORB_ULT_SFX_DB
	_orb_ult_player.stream = _orb_ult_stream
	_orb_ult_player.pitch_scale = 1.0
	_orb_ult_player.play()


func _start_orb_ult_fade_out(play_shoot_after: bool) -> void:
	if _orb_ult_fade_tween != null:
		_orb_ult_fade_tween.kill()
		_orb_ult_fade_tween = null
	if _orb_ult_player == null:
		if play_shoot_after:
			_sync_play_orb_shoot_only()
		return
	if not _orb_ult_player.playing:
		if play_shoot_after:
			_sync_play_orb_shoot_only()
		return
	_orb_ult_fade_tween = create_tween()
	_orb_ult_fade_tween.tween_property(_orb_ult_player, "volume_db", -80.0, ORB_ULT_FADE_OUT_SEC)
	_orb_ult_fade_tween.tween_callback(func():
		if _orb_ult_player != null:
			_orb_ult_player.stop()
			_orb_ult_player.volume_db = ORB_ULT_SFX_DB
		_orb_ult_fade_tween = null
		if play_shoot_after:
			_sync_play_orb_shoot_only()
	)


func _broadcast_medic_healgun_use_sfx() -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_net_play_medic_healgun_use_sfx"), [])
	else:
		_net_play_medic_healgun_use_sfx.rpc()


@rpc("any_peer", "reliable", "call_local")
func _net_play_medic_healgun_use_sfx() -> void:
	if _medic_healgun_player == null or _medic_healgun_stream == null:
		return
	_medic_healgun_player.stream = _medic_healgun_stream
	_medic_healgun_player.pitch_scale = _footstep_rng.randf_range(0.98, 1.03)
	_medic_healgun_player.volume_db = MEDIC_HEALGUN_SFX_DB
	_medic_healgun_player.play()


func _broadcast_medic_pulse_fire_sfx() -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_net_play_medic_pulse_fire_sfx"), [])
	else:
		_net_play_medic_pulse_fire_sfx.rpc()


@rpc("any_peer", "reliable", "call_local")
func _net_play_medic_pulse_fire_sfx() -> void:
	if _medic_pulse_fire_player == null or _medic_pulse_fire_stream == null:
		return
	_medic_pulse_fire_player.stream = _medic_pulse_fire_stream
	_medic_pulse_fire_player.pitch_scale = _footstep_rng.randf_range(0.99, 1.02)
	_medic_pulse_fire_player.volume_db = MEDIC_PULSE_FIRE_SFX_DB
	_medic_pulse_fire_player.play()


func _broadcast_missile_ult_activate_sfx() -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_net_play_missile_ult_activate_sfx"), [])
	else:
		_net_play_missile_ult_activate_sfx.rpc()


@rpc("any_peer", "reliable", "call_local")
func _net_play_missile_ult_activate_sfx() -> void:
	_play_missile_ult_activate_sfx()


func _broadcast_tank_ult_activate_sfx() -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_net_play_tank_ult_activate_sfx"), [])
	else:
		_net_play_tank_ult_activate_sfx.rpc()


@rpc("any_peer", "reliable", "call_local")
func _net_play_tank_ult_activate_sfx() -> void:
	_play_tank_ult_sfx()


func _set_third_person_enabled(enabled: bool) -> void:
	_third_person_enabled = enabled
	_update_camera_mode_visuals()
	_update_third_person_camera_position()


func _sync_camera_mode_from_game_state() -> void:
	# Manual toggle is disabled: tank_laser shield/ultimate force third-person.
	var should_be_third_person: bool = (
		hero_id == "tank_laser"
		and not is_dead
		and (ultimate_active or _tank_laser_shield_up)
	)
	if hero_id == "healer_orb" and not is_dead and ultimate_active:
		should_be_third_person = true
	if should_be_third_person != _third_person_enabled:
		_set_third_person_enabled(should_be_third_person)


func _update_camera_mode_visuals() -> void:
	if not _local_authority():
		return
	_sync_weapon_vfx_attachment_for_view()
	if camera != null:
		camera.current = not _third_person_enabled
	if third_person_camera != null:
		third_person_camera.current = _third_person_enabled
	var show_crosshair: bool = not is_dead and (not _third_person_enabled or (hero_id == "healer_orb" and ultimate_active))
	_set_local_crosshair_visible(show_crosshair)
	_refresh_owner_world_body_camera_cull()


func _update_third_person_camera_position() -> void:
	if not _local_authority():
		return
	if third_person_camera == null or camera == null:
		return
	# Keep third-person follow camera above/behind the player, with terrain collision push-in.
	var shoulder_anchor: Vector3 = global_position + Vector3(0.0, THIRD_PERSON_CAMERA_HEIGHT, 0.0)
	var backward: Vector3 = camera.global_transform.basis.z.normalized()
	var desired: Vector3 = shoulder_anchor + backward * THIRD_PERSON_CAMERA_DISTANCE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(shoulder_anchor, desired)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = THIRD_PERSON_CAMERA_COLLISION_MASK
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var final_pos: Vector3 = desired
	if not hit.is_empty():
		var hit_pos: Vector3 = hit["position"] as Vector3
		var to_cam: Vector3 = hit_pos - shoulder_anchor
		var dist: float = maxf(to_cam.length() - THIRD_PERSON_CAMERA_CLEARANCE, 0.3)
		final_pos = shoulder_anchor + backward * dist
	third_person_camera.global_position = final_pos
	third_person_camera.look_at(shoulder_anchor, Vector3.UP)


func _set_local_crosshair_visible(is_visible: bool) -> void:
	var world: Node = get_parent()
	if world == null:
		return
	var hud_node: Node = world.get("hud") if world.get("hud") != null else null
	if hud_node != null and hud_node.has_method("set_crosshair_visible"):
		hud_node.set_crosshair_visible(is_visible)


func _try_reload_magazine() -> void:
	if not _local_authority():
		return
	var hero: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero == null or hero.magazine_size < 0:
		return
	if hero.magazine_reload_seconds >= 0.0 and weaponNum == 1:
		if magazine_current >= magazine_max_clip:
			return
		if _timed_mag_reload_active:
			return
		_timed_mag_reload_active = true
		_timed_mag_reload_remaining = hero.magazine_reload_seconds
		_sync_reload_sfx()
		return
	if hero_id == "dps_sniper":
		if magazine_current >= magazine_max_clip:
			return
		if _sniper_is_reloading:
			return
		_sniper_is_reloading = true
		_sniper_reload_left = SNIPER_RELOAD_SEC
		_sync_reload_sfx()
		return
	if hero_id != "dps_missile" or weaponNum != 1:
		return
	magazine_current = magazine_max_clip


func _update_missile_full_auto(delta: float) -> void:
	if hero_id != "dps_missile" or weaponNum != 1:
		return
	if _timed_mag_reload_active or magazine_current <= 0:
		_missile_fire_cooldown = 0.0
		return
	# While missile ult is active, primary fire is fully locked (prevents one-frame stray shot at ult launch).
	if ultimate_active:
		_missile_fire_cooldown = 0.0
		return
	if _missile_windup_active or _missile_shoot_lock_left > 0.0:
		_missile_fire_cooldown = 0.0
		return
	if is_dead or _pawn_soft_lock():
		_missile_fire_cooldown = 0.0
		return
	if not Input.is_action_pressed("shoot"):
		_missile_fire_cooldown = 0.0
		return
	var period: float = 1.0 / MISSILE_ROUNDS_PER_SEC
	_missile_fire_cooldown -= delta
	while _missile_fire_cooldown <= 0.0:
		_fire_missile_primary_shot()
		_missile_fire_cooldown += period


func _missile_ult_target_triplet() -> Array[Dictionary]:
	var center: Dictionary = _missile_resolved_target_data()
	var cpos: Vector3 = center.get("point", global_position) as Vector3
	var cnormal: Vector3 = center.get("normal", Vector3.UP) as Vector3
	var eye: Vector3 = camera.global_position
	var to_center: Vector3 = cpos - eye
	var fwd: Vector3 = to_center.normalized() if to_center.length_squared() > 1e-8 else (-camera.global_transform.basis.z).normalized()
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	if right.length_squared() < 1e-8:
		right = Vector3.RIGHT
	var left_data: Dictionary = {"point": cpos - right * MISSILE_ULT_SIDE_OFFSET_M, "normal": cnormal}
	var right_data: Dictionary = {"point": cpos + right * MISSILE_ULT_SIDE_OFFSET_M, "normal": cnormal}
	return [center, left_data, right_data]


func _missile_ult_try_fire_triplet() -> void:
	if hero_id != "dps_missile" or not ultimate_active:
		return
	if _missile_ult_has_fired:
		return
	_missile_ult_has_fired = true
	var triplet: Array[Dictionary] = _missile_ult_target_triplet()
	for i in range(triplet.size()):
		var d: Dictionary = triplet[i]
		var p: Vector3 = d.get("point", global_position) as Vector3
		var n: Vector3 = d.get("normal", Vector3.UP) as Vector3
		var speed_mult: float = MISSILE_ULT_CENTER_FLIGHT_SPEED_MULT if i == 0 else 1.0
		var play_launch_sfx: bool = i == 0
		if HeroNet.is_gdsync():
			GDSync.call_func_all(Callable(self, "_spawn_missile_immediate_strike"), [p, n, speed_mult, play_launch_sfx])
		else:
			_spawn_missile_immediate_strike.rpc(p, n, speed_mult, play_launch_sfx)
	# Lock missile actions briefly after ult fires: no primary or secondary during this window.
	_missile_shoot_lock_left = maxf(_missile_shoot_lock_left, MISSILE_ULT_END_AFTER_FIRE_SEC)
	ultimate_remaining_sec = minf(ultimate_remaining_sec, MISSILE_ULT_END_AFTER_FIRE_SEC)


func _apply_missile_ult_hover(delta: float) -> void:
	if hero_id != "dps_missile" or not ultimate_active or not _missile_ult_hover_active:
		return
	var target_y: float = _missile_ult_hover_target_y
	global_position.y = lerpf(global_position.y, target_y, 1.0 - exp(-MISSILE_ULT_HOVER_FOLLOW_SPEED * delta))
	velocity.y = 0.0


func _apply_spring_ult_hover(delta: float) -> void:
	if hero_id != "dps_spring" or not ultimate_active or not _spring_ult_hover_active:
		return
	var target_y: float = _spring_ult_hover_target_y
	global_position.y = lerpf(global_position.y, target_y, 1.0 - exp(-SPRING_ULT_HOVER_FOLLOW_SPEED * delta))
	velocity.y = 0.0


func _update_sniper_combat(delta: float) -> void:
	if hero_id != "dps_sniper" or weaponNum != 1:
		return
	if _sniper_ult_primary_lock_left > 0.0:
		return
	if ultimate_active:
		return
	if not (is_dead or _pawn_soft_lock()):
		if _sniper_is_reloading:
			_sniper_reload_left -= delta
			if _sniper_reload_left <= 0.0:
				_sniper_is_reloading = false
				_sniper_reload_left = 0.0
				magazine_current = magazine_max_clip
	if is_dead or _pawn_soft_lock() or _sniper_is_reloading:
		return
	_sniper_fire_cooldown = maxf(_sniper_fire_cooldown - delta, 0.0)
	if not Input.is_action_pressed("shoot"):
		return
	if _sniper_fire_cooldown > 0.0:
		return
	var hero_check: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero_check != null and hero_check.magazine_size >= 0 and magazine_current <= 0:
		return
	_sniper_fire_cooldown = SNIPER_FIRE_PERIOD_SEC
	_fire_sniper_shot()


func _sniper_ult_execute_burst_and_begin_linger() -> void:
	if hero_id != "dps_sniper":
		return
	var beam_start: Vector3 = muzzle_flash.global_position
	var aim_dir: Vector3 = (-camera.global_transform.basis.z).normalized()
	var beam_len: float = SNIPER_ULT_MAX_RANGE
	var beam_end: Vector3 = beam_start + aim_dir * beam_len
	var xf: Transform3D = _spring_cylinder_transform(beam_start, aim_dir, beam_len)
	var bodies: Array = SplashOverlap.character_bodies_in_cylinder(
		get_world_3d(),
		xf,
		beam_len,
		SNIPER_ULT_BEAM_RADIUS,
		PLAYER_PHYSICS_LAYER,
		[get_rid()]
	)
	var w: Node = get_parent()
	_sniper_ult_linger_burst_ids.clear()
	_sniper_ult_linger_done_ids.clear()
	for body in bodies:
		if body == self:
			continue
		if body.get("is_dead") == true:
			continue
		var target_team: Variant = body.get("team_id")
		if typeof(target_team) != TYPE_INT or int(target_team) == team_id:
			continue
		HeroNet.apply_damage_on_victim(body, SNIPER_ULT_BURST_DAMAGE, name.to_int(), true)
		if w != null and w.has_method("record_damaged_by_me"):
			w.record_damaged_by_me(body.name.to_int())
		_sniper_ult_linger_burst_ids[(body as Object).get_instance_id()] = true
		_sync_sniper_ult_hit_feedback_on_victim(body)
		if HeroNet.controls_local_pawn(self):
			_play_sniper_ult_hit_local()
	_sniper_ult_linger_xf = xf
	_sniper_ult_linger_len = beam_len
	_sniper_ult_linger_left = SNIPER_ULT_LINGER_SEC
	_sniper_ult_primary_lock_left = SNIPER_ULT_PRIMARY_LOCK_SEC
	_rpc_sniper_ult_beam_vfx_all(beam_start, beam_end, name.to_int())
	_replicate_combat_state()


func _update_sniper_ult_linger(delta: float) -> void:
	if _sniper_ult_linger_left <= 0.0:
		return
	if not _local_authority():
		return
	if hero_id != "dps_sniper":
		_sniper_ult_linger_left = 0.0
		return
	var bodies: Array = SplashOverlap.character_bodies_in_cylinder(
		get_world_3d(),
		_sniper_ult_linger_xf,
		_sniper_ult_linger_len,
		SNIPER_ULT_BEAM_RADIUS,
		PLAYER_PHYSICS_LAYER,
		[get_rid()]
	)
	var w: Node = get_parent()
	for body in bodies:
		if body == self:
			continue
		if body.get("is_dead") == true:
			continue
		var target_team: Variant = body.get("team_id")
		if typeof(target_team) != TYPE_INT or int(target_team) == team_id:
			continue
		var bid: int = (body as Object).get_instance_id()
		if _sniper_ult_linger_burst_ids.has(bid):
			continue
		if _sniper_ult_linger_done_ids.has(bid):
			continue
		HeroNet.apply_damage_on_victim(body, SNIPER_ULT_LINGER_DAMAGE, name.to_int(), true)
		if w != null and w.has_method("record_damaged_by_me"):
			w.record_damaged_by_me(body.name.to_int())
		_sniper_ult_linger_done_ids[bid] = true
		_sync_sniper_ult_hit_feedback_on_victim(body)
		if HeroNet.controls_local_pawn(self):
			_play_sniper_ult_hit_local()
	_sniper_ult_linger_left = maxf(0.0, _sniper_ult_linger_left - delta)


func _maybe_sniper_smoke_secondary_press() -> void:
	if hero_id != "dps_sniper" or weaponNum != 1:
		return
	if ultimate_active:
		return
	if is_dead or _pawn_soft_lock():
		return
	if not Input.is_action_just_pressed("secondary"):
		return
	var slot_sb: int = _hud_slot_index_for_action("secondary")
	if slot_sb < 0:
		return
	if hud_ability_cd_remaining[slot_sb] > 0.0:
		return
	var sid_sb: int = HeroNet.my_id()
	var vel_sb: Vector3 = projectile_aim_direction_from_muzzle().normalized() * SMOKE_BOMB_THROW_SPEED
	var muzzle_pos: Vector3 = muzzle_flash.global_position if muzzle_flash != null else (global_position + Vector3(0.0, 1.2, 0.0))
	_rpc_spawn_smoke_bomb_all(muzzle_pos, vel_sb, sid_sb)
	_sync_sniper_smoke_prime_sfx()
	var cd_sb: float = _get_hud_slot_cooldown_duration(slot_sb)
	if cd_sb > 0.0:
		hud_ability_cd_remaining[slot_sb] = cd_sb


func _rpc_sniper_ult_beam_vfx_all(start: Vector3, end: Vector3, shooter_peer_id: int) -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_sniper_ult_spawn_world_beam"), [start, end, shooter_peer_id])
	elif multiplayer.multiplayer_peer == null:
		_sniper_ult_spawn_world_beam(start, end, shooter_peer_id)
	else:
		_sniper_ult_spawn_world_beam.rpc(start, end, shooter_peer_id)


@rpc("any_peer", "reliable", "call_local")
func _sniper_ult_spawn_world_beam(start: Vector3, end: Vector3, shooter_peer_id: int) -> void:
	var w: Node = get_parent()
	if w == null:
		return
	var beam: Node = SniperUltBeamScene.instantiate()
	w.add_child(beam)
	if beam.has_method("setup_world"):
		beam.setup_world(start, end, shooter_peer_id, SNIPER_ULT_BEAM_VFX_SEC)


func _fire_sniper_shot() -> void:
	var hero_check: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero_check != null and hero_check.magazine_size >= 0 and magazine_current <= 0:
		return
	if hero_check != null and hero_check.magazine_size >= 0:
		magazine_current = maxi(magazine_current - 1, 0)
		if magazine_current <= 0 and not _sniper_is_reloading:
			_sniper_is_reloading = true
			_sniper_reload_left = SNIPER_RELOAD_SEC
			_sync_reload_sfx()
	raycast.force_raycast_update()
	if raycast.is_colliding():
		var hit_player = raycast.get_collider()
		if _try_damage_shield_collider(hit_player, SNIPER_DAMAGE):
			if HeroNet.is_gdsync():
				GDSync.call_func_all(Callable(self, "play_sniper_muzzle_only"), [])
			else:
				play_sniper_muzzle_only.rpc()
			return
		if hit_player != null and hit_player.has_method("receive_damage") and hit_player.has_method("heal_damage"):
			var target_team = hit_player.get("team_id")
			if typeof(target_team) == TYPE_INT and int(target_team) != team_id:
				HeroNet.apply_damage_on_victim(hit_player, SNIPER_DAMAGE, name.to_int())
				var w: Node = get_parent()
				if w != null and w.has_method("record_damaged_by_me"):
					w.record_damaged_by_me(hit_player.name.to_int())
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "play_sniper_muzzle_only"), [])
	else:
		play_sniper_muzzle_only.rpc()


@rpc("call_local")
func play_sniper_muzzle_only() -> void:
	if hero_id != "dps_sniper":
		return
	_play_sniper_shot_sfx()
	if big_muzzle_flash_sniper != null and big_muzzle_flash_sniper.has_method("play"):
		big_muzzle_flash_sniper.play()


func _fire_missile_primary_shot() -> void:
	var hero_check: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero_check != null and hero_check.magazine_size >= 0 and magazine_current <= 0:
		return
	if hero_check != null and hero_check.magazine_size >= 0:
		magazine_current = maxi(magazine_current - 1, 0)
		_maybe_auto_reload_after_primary_empty()
	raycast.force_raycast_update()
	if raycast.is_colliding():
		var hit_player = raycast.get_collider()
		if _try_damage_shield_collider(hit_player, MISSILE_HITSCAN_DAMAGE):
			_rpc_play_shoot_effects_for_all()
			return
		if hit_player != null and hit_player.has_method("receive_damage") and hit_player.has_method("heal_damage"):
			var target_team = hit_player.get("team_id")
			if typeof(target_team) == TYPE_INT and int(target_team) != team_id:
				HeroNet.apply_damage_on_victim(hit_player, MISSILE_HITSCAN_DAMAGE, name.to_int())
				var w: Node = get_parent()
				if w != null and w.has_method("record_damaged_by_me"):
					w.record_damaged_by_me(hit_player.name.to_int())
	_rpc_play_shoot_effects_for_all()


@rpc("call_local")
func play_missile_muzzle_only() -> void:
	if hero_id != "dps_missile":
		return
	if big_muzzle_flash != null and big_muzzle_flash.has_method("play"):
		big_muzzle_flash.play()
	_play_missile_single_shot_sfx()


@rpc("call_local")
func play_orb_shoot_only() -> void:
	if big_muzzle_flash != null and big_muzzle_flash.has_method("play"):
		big_muzzle_flash.play()
	if _orb_shoot_player == null or _orb_shoot_stream == null:
		return
	_orb_shoot_player.stream = _orb_shoot_stream
	_orb_shoot_player.pitch_scale = _footstep_rng.randf_range(0.99, 1.02)
	_orb_shoot_player.volume_db = ORB_SHOOT_SFX_DB
	_orb_shoot_player.play()


func _crosshair_world_hit_point(max_range: float = PROJECTILE_AIM_MAX_RANGE) -> Vector3:
	var cam_from: Vector3 = camera.global_position
	var cam_to: Vector3 = cam_from - camera.global_transform.basis.z * max_range
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cam_from, cam_to)
	query.collision_mask = COLLISION_MASK_WORLD_PLAYER_SHIELD
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [self]
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty() and hit.has("position"):
		return hit["position"]
	return cam_to


func _missile_marker_basis_from_normal(normal: Vector3) -> Basis:
	# Keep floor orientation matching the old behavior; only tilt by surface normal.
	var y_axis: Vector3 = normal.normalized()
	if y_axis.length_squared() < 1e-8:
		y_axis = Vector3.UP
	var x_axis: Vector3 = Vector3.FORWARD.cross(y_axis)
	if x_axis.length_squared() < 1e-8:
		x_axis = Vector3.RIGHT.cross(y_axis)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = y_axis.cross(x_axis).normalized()
	x_axis = z_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _missile_resolved_target_data() -> Dictionary:
	var raw_target: Vector3 = _crosshair_world_hit_point()
	var eye_origin: Vector3 = camera.global_position
	if eye_origin.distance_to(raw_target) <= MISSILE_ABILITY_MAX_TARGET_RANGE:
		var ray_from: Vector3 = eye_origin
		var ray_to: Vector3 = raw_target
		var space_state_hit: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var q_hit: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		q_hit.collision_mask = COLLISION_MASK_WORLD_PLAYER_SHIELD
		q_hit.collide_with_areas = false
		q_hit.collide_with_bodies = true
		q_hit.exclude = [self]
		var hit_direct: Dictionary = space_state_hit.intersect_ray(q_hit)
		var direct_normal: Vector3 = Vector3.UP
		if not hit_direct.is_empty() and hit_direct.has("normal"):
			direct_normal = hit_direct["normal"] as Vector3
		return {"point": raw_target, "normal": direct_normal}
	var facing: Vector3 = -camera.global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 1e-8:
		facing = -global_transform.basis.z
		facing.y = 0.0
	if facing.length_squared() < 1e-8:
		facing = Vector3(0.0, 0.0, -1.0)
	facing = facing.normalized()
	var flat_point: Vector3 = global_position + facing * MISSILE_ABILITY_MAX_TARGET_RANGE
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_from: Vector3 = flat_point + Vector3.UP * 32.0
	var ray_to: Vector3 = flat_point + Vector3.DOWN * 256.0
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	q.collision_mask = COLLISION_MASK_WORLD_ONLY
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = [self]
	var hit: Dictionary = space_state.intersect_ray(q)
	if not hit.is_empty() and hit.has("position"):
		var ground_normal: Vector3 = hit["normal"] as Vector3 if hit.has("normal") else Vector3.UP
		return {"point": hit["position"], "normal": ground_normal}
	return {"point": flat_point, "normal": Vector3.UP}


func _missile_preview_ensure_exists() -> void:
	if _missile_targeting_preview != null and is_instance_valid(_missile_targeting_preview):
		return
	var inst := MissileAbilityTargetVfxScene.instantiate()
	if not (inst is Node3D):
		return
	_missile_targeting_preview = inst as Node3D
	add_child(_missile_targeting_preview)
	var pcol := Color(1.0, 1.0, 1.0, 1.0)
	_missile_targeting_preview.set("primary_color", pcol)
	_missile_targeting_preview.set("secondary_color", pcol.lightened(0.16))
	_missile_targeting_preview.set("tertiary_color", pcol.darkened(0.16))
	_missile_targeting_preview.set("light_color", pcol)
	_missile_targeting_preview.set("autoplay", false)
	_missile_targeting_preview.set("one_shot", false)
	for n in _missile_targeting_preview.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l != null:
			l.light_energy = 0.0
			l.visible = false
	if _missile_targeting_preview.has_method("play"):
		_missile_targeting_preview.play()


func _missile_preview_clear() -> void:
	if _missile_targeting_preview != null and is_instance_valid(_missile_targeting_preview):
		_missile_targeting_preview.queue_free()
	_missile_targeting_preview = null


func _missile_ult_preview_clear() -> void:
	for m in _missile_ult_preview_markers:
		if m != null and is_instance_valid(m):
			m.queue_free()
	_missile_ult_preview_markers.clear()


func _missile_ult_preview_color() -> Color:
	return Color(1.0, 0.28, 0.28, 1.0) if _is_me_hostile_to_local_viewer() else Color(0.34, 0.68, 1.0, 1.0)


func _missile_ult_preview_update(triplet: Array[Dictionary] = []) -> void:
	if triplet.is_empty():
		triplet = _missile_ult_target_triplet()
	var pcol: Color = _missile_ult_preview_color()
	var scol: Color = pcol.lightened(0.16)
	var tcol: Color = pcol.darkened(0.16)
	while _missile_ult_preview_markers.size() < 3:
		var inst := MissileAbilityTargetVfxScene.instantiate()
		if not (inst is Node3D):
			break
		var mk := inst as Node3D
		add_child(mk)
		mk.set("autoplay", false)
		mk.set("one_shot", false)
		mk.set("primary_color", pcol)
		mk.set("secondary_color", scol)
		mk.set("tertiary_color", tcol)
		mk.set("light_color", pcol)
		for n in mk.find_children("*", "Light3D", true, false):
			var l := n as Light3D
			if l != null:
				l.visible = true
				l.light_energy = maxf(l.light_energy, 1.0)
		if mk.has_method("play"):
			mk.play()
		_missile_ult_preview_markers.append(mk)
	for i in range(_missile_ult_preview_markers.size()):
		if i >= triplet.size():
			break
		var mk2: Node3D = _missile_ult_preview_markers[i]
		if mk2 == null or not is_instance_valid(mk2):
			continue
		mk2.set("primary_color", pcol)
		mk2.set("secondary_color", scol)
		mk2.set("tertiary_color", tcol)
		mk2.set("light_color", pcol)
		var td: Dictionary = triplet[i]
		var p: Vector3 = td.get("point", global_position) as Vector3
		var nrm: Vector3 = td.get("normal", Vector3.UP) as Vector3
		mk2.global_position = p + Vector3.UP * MISSILE_ABILITY_MARKER_Y_OFFSET
		mk2.global_basis = _missile_marker_basis_from_normal(nrm)


func _push_missile_ult_preview_sync(active: bool, triplet: Array[Dictionary] = []) -> void:
	if not _local_authority():
		return
	var points: Array = []
	var normals: Array = []
	if active:
		for d in triplet:
			points.append(d.get("point", global_position) as Vector3)
			normals.append(d.get("normal", Vector3.UP) as Vector3)
	if HeroNet.is_gdsync():
		HeroNet.broadcast_unreliable_to_others(Callable(self, "_net_missile_ult_preview_pose"), [points, normals, active])
		return
	if multiplayer.multiplayer_peer == null:
		return
	_net_missile_ult_preview_pose.rpc(points, normals, active)


@rpc("any_peer", "unreliable")
func _net_missile_ult_preview_pose(points: Array, normals: Array, active: bool) -> void:
	if _local_authority():
		return
	if not active:
		_missile_ult_preview_clear()
		return
	var count: int = mini(points.size(), normals.size())
	var triplet: Array[Dictionary] = []
	for i in range(count):
		triplet.append({
			"point": points[i] as Vector3,
			"normal": normals[i] as Vector3
		})
	_missile_ult_preview_update(triplet)


func _request_cancel_missile_windup() -> void:
	if not _missile_windup_active:
		return
	if not _local_authority():
		return
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_net_cancel_missile_windup"), [])
	else:
		_net_cancel_missile_windup.rpc()


@rpc("any_peer", "reliable", "call_local")
func _net_cancel_missile_windup() -> void:
	_missile_windup_active = false
	missile_targeting_ui_active = false
	if _missile_windup_marker != null and is_instance_valid(_missile_windup_marker):
		_missile_windup_marker.queue_free()
	_missile_windup_marker = null
	# Canceling windup removes the post-launch lock because no missile is fired.
	_missile_shoot_lock_left = 0.0


func _update_missile_secondary_targeting() -> void:
	if hero_id != "dps_missile" or weaponNum != 1 or is_dead or _pawn_soft_lock():
		_missile_targeting_hold_active = false
		missile_targeting_ui_active = false
		_missile_preview_clear()
		_missile_ult_preview_clear()
		_push_missile_ult_preview_sync(false)
		return
	if _missile_shoot_lock_left > 0.0:
		_missile_targeting_hold_active = false
		missile_targeting_ui_active = false
		_missile_preview_clear()
		_missile_ult_preview_clear()
		_push_missile_ult_preview_sync(false)
		return
	if ultimate_active:
		missile_targeting_ui_active = false
		_missile_targeting_hold_active = false
		_missile_preview_clear()
		if _missile_ult_arm_delay_left > 0.0:
			_missile_ult_preview_clear()
			_push_missile_ult_preview_sync(false)
		elif not _missile_ult_has_fired:
			var triplet: Array[Dictionary] = _missile_ult_target_triplet()
			_missile_ult_preview_update(triplet)
			_missile_ult_preview_net_sync_accum += get_physics_process_delta_time()
			if _missile_ult_preview_net_sync_accum >= MISSILE_ULT_PREVIEW_NET_SYNC_INTERVAL:
				_missile_ult_preview_net_sync_accum = 0.0
				_push_missile_ult_preview_sync(true, triplet)
		else:
			_missile_ult_preview_clear()
			_push_missile_ult_preview_sync(false)
		if _missile_ult_arm_delay_left <= 0.0 and (Input.is_action_just_pressed("secondary") or Input.is_action_just_pressed("shoot")):
			_missile_ult_try_fire_triplet()
		return
	_missile_ult_preview_clear()
	_push_missile_ult_preview_sync(false)
	var slot_idx: int = _hud_slot_index_for_action("secondary")
	var off_cd: bool = _missile_ability_cooldown_left <= 0.0 and (slot_idx < 0 or hud_ability_cd_remaining[slot_idx] <= 0.0)
	if Input.is_action_just_pressed("secondary") and off_cd and not _missile_targeting_hold_active and not _missile_windup_active:
		_missile_targeting_hold_active = true
	if _missile_targeting_hold_active and Input.is_action_pressed("secondary"):
		_missile_preview_ensure_exists()
		var tdata: Dictionary = _missile_resolved_target_data()
		var p: Vector3 = tdata.get("point", global_position) as Vector3
		var n: Vector3 = tdata.get("normal", Vector3.UP) as Vector3
		if _missile_targeting_preview != null and is_instance_valid(_missile_targeting_preview):
			_missile_targeting_preview.global_position = p + Vector3.UP * MISSILE_ABILITY_MARKER_Y_OFFSET
			_missile_targeting_preview.global_basis = _missile_marker_basis_from_normal(n)
	missile_targeting_ui_active = _missile_targeting_hold_active or _missile_windup_active
	if _missile_targeting_hold_active and Input.is_action_just_released("secondary"):
		_missile_targeting_hold_active = false
		if _missile_windup_active:
			return
		var tdata_release: Dictionary = _missile_resolved_target_data()
		var target_point: Vector3 = tdata_release.get("point", global_position) as Vector3
		var target_normal: Vector3 = tdata_release.get("normal", Vector3.UP) as Vector3
		_missile_preview_clear()
		_cast_missile_target_strike(target_point, target_normal)
		_missile_shoot_lock_left = MISSILE_ABILITY_WINDUP_SEC


func _spring_ult_target_data() -> Dictionary:
	var raw_target: Vector3 = _crosshair_world_hit_point()
	var eye_origin: Vector3 = camera.global_position
	if eye_origin.distance_to(raw_target) <= MISSILE_ABILITY_MAX_TARGET_RANGE:
		var ray_from: Vector3 = eye_origin
		var ray_to: Vector3 = raw_target
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
		q.collision_mask = COLLISION_MASK_WORLD_PLAYER_SHIELD
		q.collide_with_areas = false
		q.collide_with_bodies = true
		q.exclude = [self]
		var hit: Dictionary = space_state.intersect_ray(q)
		var normal: Vector3 = hit["normal"] as Vector3 if (not hit.is_empty() and hit.has("normal")) else Vector3.UP
		var data: Dictionary = {"point": raw_target, "normal": normal}
		_spring_ult_last_valid_target_data = data.duplicate(true)
		return data
	if not _spring_ult_last_valid_target_data.is_empty():
		return _spring_ult_last_valid_target_data
	# No previous valid point yet: fall back to missile resolver once.
	return _missile_resolved_target_data()


func _spring_ult_preview_ensure_exists() -> void:
	if _spring_ult_target_preview != null and is_instance_valid(_spring_ult_target_preview):
		return
	var inst := MissileAbilityTargetVfxScene.instantiate()
	if not (inst is Node3D):
		return
	_spring_ult_target_preview = inst as Node3D
	add_child(_spring_ult_target_preview)
	var pcol := Color(1.0, 1.0, 1.0, 1.0)
	_spring_ult_target_preview.set("primary_color", pcol)
	_spring_ult_target_preview.set("secondary_color", pcol.lightened(0.16))
	_spring_ult_target_preview.set("tertiary_color", pcol.darkened(0.16))
	_spring_ult_target_preview.set("light_color", pcol)
	_spring_ult_target_preview.set("autoplay", false)
	_spring_ult_target_preview.set("one_shot", false)
	if _spring_ult_target_preview.has_method("play"):
		_spring_ult_target_preview.play()


func _spring_ult_preview_clear() -> void:
	if _spring_ult_target_preview != null and is_instance_valid(_spring_ult_target_preview):
		_spring_ult_target_preview.queue_free()
	_spring_ult_target_preview = null


func _spring_ult_try_launch() -> void:
	if hero_id != "dps_spring" or not ultimate_active:
		return
	if _spring_ult_has_launched or _spring_ult_launch_active:
		return
	var to_target: Vector3 = _spring_ult_target_point - global_position
	var duration: float = maxf(SPRING_ULT_LAUNCH_DURATION_SEC, 0.12)
	# Straight shot toward selected target.
	velocity = to_target / duration
	_spring_ult_hover_active = false
	_spring_ult_launch_active = true
	_interrupt_jump_body_animation_if_needed()
	_spring_ult_has_launched = true
	_spring_ult_preview_clear()


func _spring_ult_land_shockwave() -> void:
	var w: Node = get_parent()
	if w == null:
		return
	var vfx_inst := TankLaserPulseAreaVfxScene.instantiate()
	var vfx: Node3D = vfx_inst as Node3D
	if vfx != null:
		w.add_child(vfx)
		vfx.global_position = global_position + Vector3(0.0, TANK_LASER_ULT_VFX_Y_OFFSET, 0.0)
		vfx.scale = Vector3.ONE * 0.2
		vfx.set("autoplay", false)
		vfx.set("one_shot", false)
		if vfx.has_method("play"):
			vfx.play()
		var tw := create_tween()
		tw.tween_property(vfx, "scale", Vector3.ONE * SPRING_ULT_SHOCKWAVE_SCALE_MULT, SPRING_ULT_SHOCKWAVE_GROW_SEC)
		tw.tween_property(vfx, "scale", Vector3.ONE * 0.45, SPRING_ULT_SHOCKWAVE_SHRINK_SEC)
		tw.finished.connect(func() -> void:
			if is_instance_valid(vfx):
				vfx.queue_free()
		)
	var victims: Array = SplashOverlap.character_bodies_in_sphere(
		get_world_3d(),
		global_position,
		SPRING_ULT_SHOCKWAVE_RADIUS,
		PLAYER_PHYSICS_LAYER,
		[get_rid()]
	)
	for body in victims:
		if body == self:
			continue
		if body.get("is_dead") == true:
			continue
		var tid: Variant = body.get("team_id")
		if typeof(tid) != TYPE_INT or int(tid) == team_id:
			continue
		HeroNet.apply_damage_on_victim(body, SPRING_ULT_SLAM_DAMAGE, name.to_int(), true)
		if w.has_method("record_damaged_by_me"):
			w.record_damaged_by_me(body.name.to_int())
		HeroNet.apply_explosion_knockback_on_victim(body, global_position, SPRING_ULT_SHOCKWAVE_PUSH_STRENGTH)


func _update_spring_ultimate_targeting() -> void:
	if hero_id != "dps_spring":
		_spring_ult_preview_clear()
		return
	if _spring_ult_launch_active:
		_spring_ult_preview_clear()
		if is_on_floor():
			_spring_ult_launch_active = false
			_spring_ult_land_shockwave()
			ultimate_active = false
			ultimate_remaining_sec = 0.0
		return
	if not ultimate_active:
		_spring_ult_preview_clear()
		return
	_spring_ult_preview_ensure_exists()
	var tdata: Dictionary = _spring_ult_target_data()
	_spring_ult_target_point = tdata.get("point", global_position) as Vector3
	_spring_ult_target_normal = tdata.get("normal", Vector3.UP) as Vector3
	if _spring_ult_target_preview != null and is_instance_valid(_spring_ult_target_preview):
		_spring_ult_target_preview.global_position = _spring_ult_target_point + Vector3.UP * MISSILE_ABILITY_MARKER_Y_OFFSET
		_spring_ult_target_preview.global_basis = _missile_marker_basis_from_normal(_spring_ult_target_normal)
	if Input.is_action_just_pressed("shoot"):
		_spring_ult_try_launch()


func _cast_missile_target_strike(target_point: Vector3, target_normal: Vector3) -> void:
	if HeroNet.is_gdsync():
		GDSync.call_func_all(Callable(self, "_spawn_missile_target_strike"), [target_point, target_normal])
	else:
		_spawn_missile_target_strike.rpc(target_point, target_normal)


func _build_missile_ability_mesh_root() -> Node3D:
	var root := Node3D.new()
	root.name = "MissileAbilityVisual"
	var visual := MissileAbilityRocketScene.instantiate() as Node3D
	if visual != null:
		visual.name = "Visual"
		visual.scale = Vector3(2.0, 2.0, 2.0)
		root.add_child(visual)
	return root


func _missile_arc_point(start: Vector3, target: Vector3, t: float) -> Vector3:
	var linear: Vector3 = start.lerp(target, t)
	var lift: float = sin(PI * t) * MISSILE_ABILITY_ARC_HEIGHT
	return linear + Vector3.UP * lift


func _spawn_missile_impact_vfx(pos: Vector3) -> void:
	_play_missile_explosion_sound_3d(pos)
	if _should_cull_missile_impact_vfx(pos):
		return
	var w: Node = get_parent()
	if w == null:
		return
	var vfx := MissileAbilityImpactVfxScene.instantiate()
	if not (vfx is Node3D):
		return
	var n3: Node3D = vfx as Node3D
	n3.set("autoplay", false)
	n3.set("one_shot", true)
	_disable_missile_impact_vfx_lights(n3)
	w.add_child(n3)
	n3.global_position = pos
	n3.global_basis = Basis.IDENTITY
	if n3.has_method("play"):
		n3.play()
	get_tree().create_timer(MISSILE_ABILITY_VFX_CLEANUP_SEC).timeout.connect(
		func() -> void:
			if is_instance_valid(n3):
				n3.queue_free()
	)


func _disable_missile_impact_vfx_lights(root: Node) -> void:
	for c in root.get_children():
		_disable_missile_impact_vfx_lights(c)
	if root is Light3D:
		var l := root as Light3D
		l.visible = false
		l.light_energy = 0.0
		l.shadow_enabled = false


func _should_cull_missile_impact_vfx(pos: Vector3) -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return false
	var to_vfx: Vector3 = pos - cam.global_position
	var dist_sq: float = to_vfx.length_squared()
	if dist_sq <= MISSILE_IMPACT_BEHIND_CAMERA_CULL_MIN_DISTANCE * MISSILE_IMPACT_BEHIND_CAMERA_CULL_MIN_DISTANCE:
		return false
	if dist_sq < 1e-8:
		return false
	var view_fwd: Vector3 = (-cam.global_basis.z).normalized()
	var dot: float = view_fwd.dot(to_vfx.normalized())
	return dot <= MISSILE_IMPACT_BEHIND_CAMERA_CULL_DOT


@rpc("any_peer", "reliable", "call_local")
func _spawn_missile_target_strike(target_point: Vector3, target_normal: Vector3) -> void:
	var w: Node = get_parent()
	if w == null:
		return
	_missile_windup_active = true
	var marker_inst := MissileAbilityTargetVfxScene.instantiate()
	var marker: Node3D = marker_inst as Node3D
	if marker != null:
		var local_is_mine: bool = str(name).is_valid_int() and int(str(name)) == HeroNet.my_id()
		var hostile_to_local: bool = _is_me_hostile_to_local_viewer()
		var pcol: Color = Color(1.0, 1.0, 1.0, 1.0) if local_is_mine else (Color(1.0, 0.28, 0.28, 1.0) if hostile_to_local else Color(0.34, 0.68, 1.0, 1.0))
		var scol: Color = pcol.lightened(0.16)
		var tcol: Color = pcol.darkened(0.16)
		marker.set("primary_color", pcol)
		marker.set("secondary_color", scol)
		marker.set("tertiary_color", tcol)
		marker.set("light_color", pcol)
		marker.set("autoplay", false)
		marker.set("one_shot", false)
		w.add_child(marker)
		marker.global_position = target_point + Vector3.UP * MISSILE_ABILITY_MARKER_Y_OFFSET
		marker.global_basis = _missile_marker_basis_from_normal(target_normal)
		if marker.has_method("play"):
			marker.play()
	_missile_windup_marker = marker
	await get_tree().create_timer(MISSILE_ABILITY_WINDUP_SEC).timeout
	if not _missile_windup_active or is_dead:
		if _missile_windup_marker != null and is_instance_valid(_missile_windup_marker):
			_missile_windup_marker.queue_free()
		_missile_windup_marker = null
		_missile_windup_active = false
		missile_targeting_ui_active = false
		return
	_missile_windup_active = false
	_missile_windup_marker = null
	missile_targeting_ui_active = false
	if _local_authority():
		_missile_shoot_lock_left = maxf(_missile_shoot_lock_left, MISSILE_ABILITY_POST_WINDUP_SHOOT_LOCK_SEC)
		_missile_ability_cooldown_left = MISSILE_ABILITY_COOLDOWN_SEC
		var slot_idx: int = _hud_slot_index_for_action("secondary")
		if slot_idx >= 0:
			hud_ability_cd_remaining[slot_idx] = MISSILE_ABILITY_COOLDOWN_SEC
	var launch_from: Vector3 = muzzle_flash.global_position + Vector3.UP * 0.35
	_play_missile_fly_sfx()
	var missile: Node3D = _build_missile_ability_mesh_root()
	w.add_child(missile)
	var dist: float = launch_from.distance_to(target_point)
	var flight_sec: float = clampf(0.55 + dist * 0.02, MISSILE_ABILITY_MIN_FLIGHT_SEC, MISSILE_ABILITY_MAX_FLIGHT_SEC)
	var life_limit_sec: float = MISSILE_ABILITY_TIMEOUT_SEC
	var elapsed: float = 0.0
	var prev_pos: Vector3 = _missile_arc_point(launch_from, target_point, 0.0)
	var exploded_on_terrain: bool = false
	var explode_pos: Vector3 = prev_pos
	missile.global_position = prev_pos
	while elapsed < life_limit_sec and is_instance_valid(missile):
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		var t: float = clampf(elapsed / flight_sec, 0.0, 1.0)
		var pos: Vector3 = _missile_arc_point(launch_from, target_point, t)
		var terrain_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(prev_pos, pos)
		terrain_query.collision_mask = COLLISION_MASK_WORLD_ONLY
		terrain_query.collide_with_areas = false
		terrain_query.collide_with_bodies = true
		terrain_query.exclude = [get_rid()]
		var terrain_hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(terrain_query)
		if not terrain_hit.is_empty():
			var hit_pos_var: Variant = terrain_hit.get("position", pos)
			explode_pos = hit_pos_var as Vector3
			exploded_on_terrain = true
			break
		var tangent: Vector3 = pos - prev_pos
		if tangent.length_squared() > 1e-8:
			var up_axis: Vector3 = tangent.normalized()
			var side_axis: Vector3 = Vector3.FORWARD.cross(up_axis)
			if side_axis.length_squared() < 1e-8:
				side_axis = Vector3.RIGHT.cross(up_axis)
			side_axis = side_axis.normalized()
			var fwd_axis: Vector3 = side_axis.cross(up_axis).normalized()
			missile.global_basis = Basis(side_axis, up_axis, fwd_axis)
		missile.global_position = pos
		prev_pos = pos
		if t >= 1.0:
			break
	if not exploded_on_terrain:
		var did_reach_target: bool = elapsed >= flight_sec
		explode_pos = target_point if did_reach_target else prev_pos
	if _local_authority():
		var victims: Array = SplashOverlap.character_bodies_in_sphere(
			get_world_3d(),
			explode_pos,
			MISSILE_ABILITY_DAMAGE_RADIUS,
			PLAYER_PHYSICS_LAYER,
			[get_rid()]
		)
		var world_node: Node = get_parent()
		for body in victims:
			if body == self:
				continue
			if body.get("is_dead") == true:
				continue
			var tid: Variant = body.get("team_id")
			if typeof(tid) != TYPE_INT or int(tid) == team_id:
				continue
			HeroNet.apply_damage_on_victim(body, MISSILE_ABILITY_DAMAGE, name.to_int())
			if world_node != null and world_node.has_method("record_damaged_by_me"):
				world_node.record_damaged_by_me(body.name.to_int())
	if is_instance_valid(missile):
		missile.queue_free()
	if is_instance_valid(marker):
		marker.queue_free()
	_spawn_missile_impact_vfx(explode_pos)


@rpc("any_peer", "reliable", "call_local")
func _spawn_missile_immediate_strike(target_point: Vector3, target_normal: Vector3, flight_speed_mult: float = 1.0, play_launch_sfx: bool = true) -> void:
	var w: Node = get_parent()
	if w == null:
		return
	var marker_inst := MissileAbilityTargetVfxScene.instantiate()
	var marker: Node3D = marker_inst as Node3D
	if marker != null:
		var local_is_mine: bool = str(name).is_valid_int() and int(str(name)) == HeroNet.my_id()
		var hostile_to_local: bool = _is_me_hostile_to_local_viewer()
		var pcol: Color = Color(1.0, 1.0, 1.0, 1.0) if local_is_mine else (Color(1.0, 0.28, 0.28, 1.0) if hostile_to_local else Color(0.34, 0.68, 1.0, 1.0))
		var scol: Color = pcol.lightened(0.16)
		var tcol: Color = pcol.darkened(0.16)
		marker.set("primary_color", pcol)
		marker.set("secondary_color", scol)
		marker.set("tertiary_color", tcol)
		marker.set("light_color", pcol)
		marker.set("autoplay", false)
		marker.set("one_shot", false)
		w.add_child(marker)
		marker.global_position = target_point + Vector3.UP * MISSILE_ABILITY_MARKER_Y_OFFSET
		marker.global_basis = _missile_marker_basis_from_normal(target_normal)
		if marker.has_method("play"):
			marker.play()
	var launch_from: Vector3 = muzzle_flash.global_position + Vector3.UP * 0.35
	if play_launch_sfx:
		_play_missile_fly_sfx()
	var missile: Node3D = _build_missile_ability_mesh_root()
	w.add_child(missile)
	var dist: float = launch_from.distance_to(target_point)
	var flight_sec_base: float = clampf(0.55 + dist * 0.02, MISSILE_ABILITY_MIN_FLIGHT_SEC, MISSILE_ABILITY_MAX_FLIGHT_SEC)
	var speed_mult: float = maxf(flight_speed_mult, 0.01)
	var flight_sec: float = maxf(0.01, flight_sec_base / speed_mult)
	var life_limit_sec: float = MISSILE_ABILITY_TIMEOUT_SEC
	var elapsed: float = 0.0
	var prev_pos: Vector3 = _missile_arc_point(launch_from, target_point, 0.0)
	var exploded_on_terrain: bool = false
	var explode_pos: Vector3 = prev_pos
	missile.global_position = prev_pos
	while elapsed < life_limit_sec and is_instance_valid(missile):
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		var t: float = clampf(elapsed / flight_sec, 0.0, 1.0)
		var pos: Vector3 = _missile_arc_point(launch_from, target_point, t)
		var terrain_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(prev_pos, pos)
		terrain_query.collision_mask = COLLISION_MASK_WORLD_ONLY
		terrain_query.collide_with_areas = false
		terrain_query.collide_with_bodies = true
		terrain_query.exclude = [get_rid()]
		var terrain_hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(terrain_query)
		if not terrain_hit.is_empty():
			var hit_pos_var: Variant = terrain_hit.get("position", pos)
			explode_pos = hit_pos_var as Vector3
			exploded_on_terrain = true
			break
		var tangent: Vector3 = pos - prev_pos
		if tangent.length_squared() > 1e-8:
			var up_axis: Vector3 = tangent.normalized()
			var side_axis: Vector3 = Vector3.FORWARD.cross(up_axis)
			if side_axis.length_squared() < 1e-8:
				side_axis = Vector3.RIGHT.cross(up_axis)
			side_axis = side_axis.normalized()
			var fwd_axis: Vector3 = side_axis.cross(up_axis).normalized()
			missile.global_basis = Basis(side_axis, up_axis, fwd_axis)
		missile.global_position = pos
		prev_pos = pos
		if t >= 1.0:
			break
	if not exploded_on_terrain:
		var did_reach_target: bool = elapsed >= flight_sec
		explode_pos = target_point if did_reach_target else prev_pos
	if _local_authority():
		var victims: Array = SplashOverlap.character_bodies_in_sphere(
			get_world_3d(),
			explode_pos,
			MISSILE_ABILITY_DAMAGE_RADIUS,
			PLAYER_PHYSICS_LAYER,
			[get_rid()]
		)
		var world_node: Node = get_parent()
		for body in victims:
			if body == self:
				continue
			if body.get("is_dead") == true:
				continue
			var tid: Variant = body.get("team_id")
			if typeof(tid) != TYPE_INT or int(tid) == team_id:
				continue
			HeroNet.apply_damage_on_victim(body, MISSILE_ABILITY_DAMAGE, name.to_int(), true)
			if world_node != null and world_node.has_method("record_damaged_by_me"):
				world_node.record_damaged_by_me(body.name.to_int())
	if is_instance_valid(missile):
		missile.queue_free()
	if is_instance_valid(marker):
		marker.queue_free()
	_spawn_missile_impact_vfx(explode_pos)


@rpc("call_local")
func play_shoot_effects():
	_play_pistol_shoot()
	if hero_id == "dps_missile" and big_muzzle_flash != null and big_muzzle_flash.has_method("play"):
		big_muzzle_flash.play()
		_play_missile_single_shot_sfx()
	elif hero_id == "dps_sniper" and weaponNum == 1 and big_muzzle_flash_sniper != null and big_muzzle_flash_sniper.has_method("play"):
		big_muzzle_flash_sniper.play()
	else:
		muzzle_flash.restart()
		muzzle_flash.emitting = true
	
@rpc("any_peer", "reliable")
func receive_explosion_knockback(explosion_origin: Vector3, horizontal_strength: float) -> void:
	if not _local_authority():
		return
	if is_dead:
		return
	var away: Vector3 = global_position - explosion_origin
	away.y = 0.0
	if away.length_squared() < 0.04:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away = away.normalized()
	velocity.x += away.x * horizontal_strength
	velocity.z += away.z * horizontal_strength
	velocity.y += horizontal_strength * 0.38


func _broadcast_player_death_explosion_vfx_to_all() -> void:
	if not _local_authority():
		return
	var w := get_parent()
	if w == null:
		return
	const MID_BODY_Y := 1.0
	var center := global_position + Vector3(0.0, MID_BODY_Y, 0.0)
	var nrm := Vector3.UP
	var victim_peer_id: int = name.to_int()
	if not HeroNet.has_multiplayer_session():
		if w.has_method("spawn_player_death_explosion_vfx_at"):
			w.spawn_player_death_explosion_vfx_at(center, nrm, victim_peer_id)
		return
	if HeroNet.is_gdsync() and w.has_method("_spawn_player_death_explosion_binbun_at"):
		GDSync.call_func_all(Callable(w, "_spawn_player_death_explosion_binbun_at"), [center, nrm, victim_peer_id])
	elif w.has_method("sync_player_death_explosion_vfx"):
		w.sync_player_death_explosion_vfx.rpc(center, nrm, victim_peer_id)


func _play_missile_explosion_sound_3d(pos: Vector3) -> void:
	if _missile_explosion_sfx_pool.is_empty():
		return
	var idx: int = _footstep_rng.randi_range(0, _missile_explosion_sfx_pool.size() - 1)
	var stream: AudioStream = _missile_explosion_sfx_pool[idx]
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "Master"
	p.max_distance = 28.0
	p.unit_size = 4.0
	p.attenuation_filter_cutoff_hz = 20500.0
	p.attenuation_filter_db = 0.0
	p.volume_db = GameSettings.slider_to_db(GameSettings.explosion_missile_volume_slider)
	p.global_position = pos
	var w: Node = get_parent()
	if w == null:
		return
	w.add_child(p)
	p.play()
	var life_sec: float = maxf(0.35, stream.get_length() + 0.2)
	get_tree().create_timer(life_sec).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)


func _is_inside_own_spawn_room() -> bool:
	var w: Node = get_parent()
	if w == null or not w.has_method("is_player_in_own_spawn_room"):
		return false
	return w.is_player_in_own_spawn_room(self)


func _tick_spawn_room_heal(delta: float) -> void:
	if not _local_authority() or is_dead:
		return
	var w: Node = get_parent()
	if w == null or not w.has_method("is_player_in_own_spawn_room"):
		_spawn_room_heal_carry = 0.0
		return
	if not w.is_player_in_own_spawn_room(self):
		_spawn_room_heal_carry = 0.0
		return
	if health >= max_health:
		return
	_spawn_room_heal_carry += SPAWN_ROOM_HEAL_PER_SEC * delta
	if _spawn_room_heal_carry < 1.0:
		return
	var room_heal: int = mini(int(_spawn_room_heal_carry), max_health - health)
	if room_heal <= 0:
		return
	_spawn_room_heal_carry -= float(room_heal)
	heal_damage(room_heal)


@rpc("any_peer")
func receive_damage(amount: int = HITSCAN_DAMAGE, attacker_peer_id: int = -1, void_kill: bool = false) -> void:
	if is_dead:
		return
	if not void_kill and _is_respawn_invulnerable():
		return
	if not void_kill and _is_inside_own_spawn_room():
		return
	var applied_amount: int = amount
	if _is_tank_explosive_ultimate_active():
		applied_amount = maxi(1, int(round(float(amount) * TANK_EXPLOSIVE_ULT_DAMAGE_MULT)))
	health -= applied_amount
	if health <= 0:
		health = 0
		is_dead = true
		_interrupt_jump_body_animation_if_needed()
		_stop_tank_laser_fire_if_needed()
		_request_cancel_missile_windup()
		_recall_tank_laser_shield_with_cooldown()
		var victim_peer_id: int = name.to_int()
		var w: Node = get_parent()
		if w != null and w.has_method("broadcast_killfeed_line"):
			w.broadcast_killfeed_line(attacker_peer_id, victim_peer_id)
		player_died.emit()
		_broadcast_player_death_explosion_vfx_to_all()
		health_changed.emit(health)
		var t: SceneTreeTimer = get_tree().create_timer(RESPAWN_DELAY)
		t.timeout.connect(_on_respawn_timer_timeout)
	else:
		health_changed.emit(health)
	_replicate_combat_state()

func _debug_set_health_to_one() -> void:
	if not OS.is_debug_build():
		return
	if not _local_authority():
		return
	if is_dead:
		return
	health = 1
	health_changed.emit(health)
	_replicate_combat_state()


@rpc("any_peer")
func heal_damage(amount: int = HITSCAN_HEAL) -> void:
	if is_dead:
		return
	var before: int = health
	health = mini(health + amount, max_health)
	var healed_amount: int = maxi(0, health - before)
	if _local_authority() and healed_amount > 0:
		_maybe_play_healing_received_sfx()
	health_changed.emit(health)
	_replicate_combat_state()


func _maybe_play_healing_received_sfx() -> void:
	if _healing_received_player == null or _healing_received_stream == null:
		return
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0
	var had_heal_gap: bool = (now_sec - _healing_received_last_event_sec) >= HEALING_RECEIVED_GAP_RESET_SEC
	var cooldown_ready: bool = (now_sec - _healing_received_last_sound_sec) >= HEALING_RECEIVED_SOUND_COOLDOWN_SEC
	_healing_received_last_event_sec = now_sec
	if not had_heal_gap or not cooldown_ready:
		return
	_healing_received_last_sound_sec = now_sec
	_healing_received_player.stream = _healing_received_stream
	_healing_received_player.volume_db = HEALING_RECEIVED_SFX_DB
	_healing_received_player.play()


func _is_ult_charge_gain_blocked() -> bool:
	return is_dead or ultimate_active or _pawn_soft_lock()


func _grant_ultimate_charge(amount: float, from_ultimate_effect: bool = false) -> void:
	if not _local_authority():
		return
	if from_ultimate_effect or amount <= 0.0:
		return
	if _is_ult_charge_gain_blocked():
		return
	var max_cost: float = maxf(ultimate_cost, 1.0)
	ultimate_charge = clampf(ultimate_charge + amount, 0.0, max_cost)


func notify_damage_dealt_for_ultimate(amount: int, from_ultimate_effect: bool = false) -> void:
	_grant_ultimate_charge(float(maxi(amount, 0)), from_ultimate_effect)


func notify_heal_done_for_ultimate(amount: int, from_ultimate_effect: bool = false) -> void:
	_grant_ultimate_charge(float(maxi(amount, 0)), from_ultimate_effect)


func notify_shield_tanked_for_ultimate(amount: int) -> void:
	_grant_ultimate_charge(float(maxi(amount, 0)))


func _replicate_combat_state() -> void:
	if not _local_authority():
		return
	if not HeroNet.has_multiplayer_session():
		return
	var w: Node = get_parent()
	if w == null or not w.has_method("broadcast_player_combat_replicate"):
		return
	w.broadcast_player_combat_replicate(str(name).to_int(), health, is_dead)


## Non-authoritative puppets: match the owning client’s HP and death so overhead bars and meshes stay in sync.
func apply_remote_combat_snapshot(health_val: int, dead: bool) -> void:
	if _local_authority():
		return
	health = clampi(health_val, 0, max_health)
	is_dead = dead
	health_changed.emit(health)
	_update_dead_visibility()


func _on_animation_player_animation_finished(anim_name):
	if anim_name == "shoot":
		anim_player.play(&"idle")
		_body_anim_play(&"idle")

@rpc("any_peer", "reliable")
func _spawn_heal_orb(origin: Vector3, direction: Vector3, shooter_peer_id: int, exempt_from_orb_cap: bool = false) -> void:
	# Every peer spawns the orb visually, but only the shooter peer heals on impact.
	var orb: Node3D = HealOrbScene.instantiate() as Node3D
	if orb.has_method("set_exempt_from_orb_cap"):
		orb.call("set_exempt_from_orb_cap", exempt_from_orb_cap)
	orb.global_position = origin
	get_parent().add_child(orb)
	if orb.has_method("setup"):
		orb.setup(shooter_peer_id, direction.normalized() * HEAL_ORB_SPEED)


func _orb_try_dash_secondary() -> void:
	var slot_i: int = _hud_slot_index_for_action("secondary")
	if slot_i >= 0 and hud_ability_cd_remaining[slot_i] > 0.0:
		return
	var dash_dir: Vector3 = -camera.global_transform.basis.z
	dash_dir.y = 0.0
	if dash_dir.length_squared() < 1e-8:
		dash_dir = -global_transform.basis.z
		dash_dir.y = 0.0
	if dash_dir.length_squared() < 1e-8:
		dash_dir = Vector3.FORWARD
	_interrupt_jump_body_animation_if_needed()
	_orb_dash_active = true
	_orb_dash_time_left = ORB_DASH_DURATION_SEC
	_orb_dash_velocity_xz = dash_dir.normalized() * (ORB_DASH_DISTANCE_M / ORB_DASH_DURATION_SEC)
	velocity = Vector3.ZERO
	if slot_i >= 0:
		hud_ability_cd_remaining[slot_i] = maxf(hud_ability_cd_remaining[slot_i], ORB_DASH_COOLDOWN_SEC)


func _apply_tank_secondary_fire_recoil(aim_dir: Vector3) -> void:
	var flat: Vector3 = Vector3(aim_dir.x, 0.0, aim_dir.z)
	if flat.length_squared() < 1e-8:
		flat = -global_transform.basis.z
		flat.y = 0.0
	if flat.length_squared() < 1e-8:
		return
	var push_back: Vector3 = -flat.normalized()
	velocity.x += push_back.x * TANK_SECONDARY_RECOIL_HORIZONTAL
	velocity.z += push_back.z * TANK_SECONDARY_RECOIL_HORIZONTAL
	velocity.y += TANK_SECONDARY_RECOIL_UPWARD
	# Recoil should still matter in air: raise air-momentum cap to include recoil speed.
	var recoil_h: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var recoil_h_len: float = recoil_h.length()
	if recoil_h_len > 1e-4:
		_jump_takeoff_h_cap = maxf(_jump_takeoff_h_cap, recoil_h_len)
		_jump_takeoff_forward_xz = recoil_h / recoil_h_len
		_air_momentum_floor_prev = false


func _orb_update_dash(delta: float) -> void:
	if not _orb_dash_active:
		return
	_orb_dash_time_left -= delta
	velocity.x = _orb_dash_velocity_xz.x
	velocity.z = _orb_dash_velocity_xz.z
	velocity.y = 0.0
	if _orb_dash_time_left <= 0.0:
		_orb_dash_active = false
		_orb_dash_time_left = 0.0
		_orb_dash_velocity_xz = Vector3.ZERO
		velocity = Vector3.ZERO


func _begin_orb_ultimate_orbit_state() -> void:
	_play_orb_ult_sfx_start()
	_orb_ult_orbit_active = true
	_orb_ult_orbit_angle = 0.0
	_orb_ult_base_dirs.clear()
	_orb_ult_clear_visual_orbs()
	var base_fwd: Vector3 = -camera.global_transform.basis.z
	base_fwd.y = 0.0
	if base_fwd.length_squared() < 1e-8:
		base_fwd = -global_transform.basis.z
		base_fwd.y = 0.0
	if base_fwd.length_squared() < 1e-8:
		base_fwd = Vector3.FORWARD
	base_fwd = base_fwd.normalized()
	for i in range(ORB_ULT_ORBIT_COUNT):
		var ang: float = (TAU * float(i)) / float(ORB_ULT_ORBIT_COUNT)
		_orb_ult_base_dirs.append(base_fwd.rotated(Vector3.UP, ang))
	for i in range(ORB_ULT_ORBIT_COUNT):
		var orb_node := HealOrbScene.instantiate()
		if not (orb_node is Node3D):
			continue
		var orb_vis: Node3D = orb_node as Node3D
		orb_vis.name = "OrbUltOrbitVis_%d" % i
		if orb_vis.has_method("configure_orb_ultimate_orbit_spin"):
			orb_vis.configure_orb_ultimate_orbit_spin(name.to_int())
		get_parent().add_child(orb_vis)
		_orb_ult_visual_orbs.append(orb_vis)
	velocity = Vector3.ZERO
	_update_orb_ultimate_orbit_visuals(0.0)
	if _local_authority():
		_push_orb_ult_visual_state(true)


func _update_orb_ultimate_orbit_visuals(delta: float) -> void:
	if not _orb_ult_orbit_active:
		return
	_orb_ult_orbit_angle = fmod(_orb_ult_orbit_angle + ORB_ULT_ORBIT_ANGULAR_SPEED * delta, TAU)
	var center: Vector3 = global_position + Vector3(0.0, ORB_ULT_ORBIT_HEIGHT, 0.0)
	for i in range(mini(_orb_ult_visual_orbs.size(), _orb_ult_base_dirs.size())):
		var orb_n: Node3D = _orb_ult_visual_orbs[i]
		if orb_n == null or not is_instance_valid(orb_n):
			continue
		var d: Vector3 = _orb_ult_base_dirs[i].rotated(Vector3.UP, _orb_ult_orbit_angle).normalized()
		orb_n.global_position = center + d * ORB_ULT_ORBIT_RADIUS


func _end_orb_ultimate_orbit_state(launch_orbs: bool) -> void:
	if not _orb_ult_orbit_active:
		return
	if launch_orbs and _local_authority() and hero_id == "healer_orb":
		var launch_positions: Array[Vector3] = []
		for n in _orb_ult_visual_orbs:
			if n == null or not is_instance_valid(n):
				continue
			launch_positions.append(n.global_position)
		var launch_dirs: Array[Vector3] = []
		for i in range(_orb_ult_base_dirs.size()):
			var d: Vector3 = _orb_ult_base_dirs[i].rotated(Vector3.UP, _orb_ult_orbit_angle)
			d.y = 0.0
			if d.length_squared() < 1e-8:
				d = Vector3.FORWARD
			launch_dirs.append(d.normalized())
		var count: int = mini(launch_positions.size(), launch_dirs.size())
		var shooter_peer_id: int = HeroNet.my_id()
		for i in range(count):
			_spawn_heal_orb(launch_positions[i], launch_dirs[i], shooter_peer_id, true)
			_rpc_spawn_heal_orb_all(launch_positions[i], launch_dirs[i], shooter_peer_id, true)
	_start_orb_ult_fade_out(launch_orbs and _local_authority())
	_orb_ult_orbit_active = false
	_orb_ult_orbit_angle = 0.0
	_orb_ult_base_dirs.clear()
	_orb_ult_clear_visual_orbs()
	if _local_authority():
		_push_orb_ult_visual_state(false)


func _push_orb_ult_visual_state(active: bool) -> void:
	if HeroNet.is_gdsync():
		HeroNet.broadcast_call(Callable(self, "_net_set_orb_ult_visual"), [active])
		return
	if multiplayer.multiplayer_peer == null:
		return
	_net_set_orb_ult_visual.rpc(active)


@rpc("any_peer", "reliable")
func _net_set_orb_ult_visual(active: bool) -> void:
	if _local_authority():
		return
	if active:
		if not _orb_ult_orbit_active:
			_begin_orb_ultimate_orbit_state()
	else:
		if _orb_ult_orbit_active:
			_end_orb_ultimate_orbit_state(false)


func _orb_ult_clear_visual_orbs() -> void:
	for n in _orb_ult_visual_orbs:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_orb_ult_visual_orbs.clear()

func _update_timed_mag_reload(delta: float) -> void:
	if _is_tank_explosive_ultimate_active():
		_timed_mag_reload_active = false
		_timed_mag_reload_remaining = 0.0
		return
	var hero: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero == null or hero.magazine_reload_seconds < 0.0 or weaponNum != 1:
		return
	if not _timed_mag_reload_active:
		return
	_timed_mag_reload_remaining -= delta
	if _timed_mag_reload_remaining <= 0.0:
		_timed_mag_reload_active = false
		_timed_mag_reload_remaining = 0.0
		magazine_current = magazine_max_clip


func _maybe_auto_reload_after_primary_empty() -> void:
	var hero: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero == null or hero.magazine_size < 0:
		return
	if magazine_current > 0:
		return
	if hero.magazine_reload_seconds < 0.0 or weaponNum != 1:
		return
	if _timed_mag_reload_active:
		return
	_timed_mag_reload_active = true
	_timed_mag_reload_remaining = hero.magazine_reload_seconds
	_sync_reload_sfx()


func is_primary_magazine_reloading() -> bool:
	if _is_tank_explosive_ultimate_active():
		return false
	if hero_id == "dps_sniper" and weaponNum == 1:
		return _sniper_is_reloading
	var hero: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero != null and hero.magazine_reload_seconds >= 0.0 and weaponNum == 1:
		return _timed_mag_reload_active
	return false


@rpc("any_peer", "reliable")
func _spawn_tank_round(origin: Vector3, direction: Vector3, shooter_peer_id: int, shell_kind: int = 0) -> void:
	var round: Node3D = TankRoundScene.instantiate() as Node3D
	round.global_position = origin
	get_parent().add_child(round)
	if round.has_method("setup"):
		var spd: float = TANK_SECONDARY_ROUND_SPEED if shell_kind == 1 else TANK_ROUND_SPEED
		round.setup(shooter_peer_id, direction.normalized() * spd, shell_kind)

@rpc("any_peer", "reliable")
func _spawn_medic_burst(origin: Vector3, direction: Vector3, shooter_peer_id: int) -> void:
	var burst: Node3D = MedicBurstScene.instantiate() as Node3D
	burst.global_position = origin
	get_parent().add_child(burst)
	if burst.has_method("setup"):
		burst.setup(shooter_peer_id, direction.normalized() * MEDIC_BURST_SPEED)


@rpc("any_peer", "reliable")
func _spawn_landmine(origin: Vector3, velocity: Vector3, shooter_peer_id: int) -> void:
	var lm: Node3D = LandmineScene.instantiate() as Node3D
	lm.global_position = origin
	get_parent().add_child(lm)
	if lm.has_method("setup"):
		lm.setup(shooter_peer_id, velocity)


@rpc("any_peer", "reliable", "call_local")
func _net_spawn_smoke_bomb_world(origin: Vector3, velocity: Vector3, shooter_peer_id: int) -> void:
	var w: Node = get_parent()
	if w != null and w.has_method("spawn_smoke_bomb_at"):
		w.spawn_smoke_bomb_at(origin, velocity, shooter_peer_id)


func _is_crosshair_over_enemy_for_aim_slow() -> bool:
	if raycast == null:
		return false
	raycast.force_raycast_update()
	if not raycast.is_colliding():
		return false
	var hit_player: Variant = raycast.get_collider()
	if hit_player == null:
		return false
	if not hit_player.has_method("receive_damage") or not hit_player.has_method("heal_damage"):
		return false
	var target_team: Variant = hit_player.get("team_id")
	return typeof(target_team) == TYPE_INT and int(target_team) != team_id


## Aim point along camera look (crosshair); beam is drawn from muzzle to here.
func _laser_beam_hit_point_global() -> Vector3:
	var cam_pos: Vector3 = camera.global_position
	var aim_dir: Vector3 = (-camera.global_transform.basis.z).normalized()
	var aim_to: Vector3 = cam_pos + aim_dir * LASER_MAX_RANGE
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cam_pos, aim_to)
	query.collision_mask = COLLISION_MASK_WORLD_PLAYER_SHIELD
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [self]
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.has("position"):
		return hit.position
	return aim_to


## From muzzle toward camera crosshair (raycast to world). Spawn at muzzle_flash.global_position with this direction.
func projectile_aim_direction_from_muzzle(max_range: float = PROJECTILE_AIM_MAX_RANGE) -> Vector3:
	var cam_from: Vector3 = camera.global_position
	var cam_to: Vector3 = cam_from - camera.global_transform.basis.z * max_range
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(cam_from, cam_to)
	query.collision_mask = COLLISION_MASK_WORLD_PLAYER_SHIELD
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [self]
	var hit: Dictionary = space_state.intersect_ray(query)
	var aim_point: Vector3 = cam_to
	if not hit.is_empty() and hit.has("position"):
		aim_point = hit["position"]
	var muzzle_pos: Vector3 = muzzle_flash.global_position
	var to_target: Vector3 = aim_point - muzzle_pos
	if to_target.length_squared() < 1e-10:
		return -camera.global_transform.basis.z
	return to_target.normalized()


func _tank_laser_apply_tick_damage(delta: float, beam_start: Vector3, beam_end: Vector3) -> void:
	var aim: Vector3 = beam_end - beam_start
	if aim.length_squared() < 1e-8:
		_laser_tick_accum = 0.0
		return
	aim = aim.normalized()
	var ray_end: Vector3 = beam_start + aim * LASER_MAX_RANGE
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(beam_start, ray_end)
	query.collision_mask = COLLISION_MASK_WORLD_PLAYER_SHIELD
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [self]
	var hit: Dictionary = space_state.intersect_ray(query)
	var impact: Vector3 = ray_end
	var hit_collider: Variant = null
	if not hit.is_empty() and hit.has("position"):
		impact = hit["position"]
		hit_collider = hit.get("collider")
	var shield_blocking: bool = false
	if hit_collider != null and hit_collider.has_method("try_block_projectile"):
		shield_blocking = true
	if shield_blocking:
		_laser_tick_accum += delta
		while _laser_tick_accum >= LASER_TICK_INTERVAL:
			_laser_tick_accum -= LASER_TICK_INTERVAL
			if not _try_damage_shield_collider(hit_collider, LASER_TICK_DAMAGE):
				break
			var pitch_s: float = _laser_damage_pitch_scale()
			_play_laser_owner_tick_sfx(impact, pitch_s)
			_sync_laser_remote_tick_sfx(beam_end, pitch_s)
		return
	var w: Node = get_parent()
	if w == null:
		_laser_tick_accum = 0.0
		return
	var candidates: Array = SplashOverlap.character_bodies_in_sphere(
		get_world_3d(),
		impact,
		LASER_SPLASH_RADIUS,
		PLAYER_PHYSICS_LAYER,
		[get_rid()]
	)
	var victims: Array = []
	for body in candidates:
		if body.get("is_dead") == true:
			continue
		var tid: Variant = body.get("team_id")
		if typeof(tid) != TYPE_INT or int(tid) == team_id:
			continue
		victims.append(body)
	if victims.is_empty():
		_laser_tick_accum += delta
		while _laser_tick_accum >= LASER_TICK_INTERVAL:
			_laser_tick_accum -= LASER_TICK_INTERVAL
			var pitch_idle: float = _laser_damage_pitch_scale()
			# Local player: cue at muzzle so it reads as “your” weapon, not the beam tip in space.
			_play_laser_owner_tick_sfx(beam_start, pitch_idle)
			_sync_laser_remote_tick_sfx(beam_end, pitch_idle)
		return
	_laser_tick_accum += delta
	while _laser_tick_accum >= LASER_TICK_INTERVAL:
		_laser_tick_accum -= LASER_TICK_INTERVAL
		var pitch_v: float = _laser_damage_pitch_scale()
		for body in victims:
			if not is_instance_valid(body) or body.get("is_dead") == true:
				continue
			HeroNet.apply_damage_on_victim(body, LASER_TICK_DAMAGE, name.to_int())
			if w.has_method("record_damaged_by_me"):
				w.record_damaged_by_me(body.name.to_int())
			var tick_pos: Vector3 = (body as Node3D).global_position + Vector3(0.0, 1.15, 0.0)
			_play_laser_owner_tick_sfx(tick_pos, pitch_v)
		_sync_laser_remote_tick_sfx(beam_end, pitch_v)


func _update_tank_laser_continuous_beam(delta: float) -> void:
	if hero_id != "tank_laser" or weaponNum != 1:
		_stop_tank_laser_fire_if_needed()
		return
	if ultimate_active:
		_stop_tank_laser_fire_if_needed()
		return
	var shoot_held: bool = Input.is_action_pressed("shoot")
	var want_laser: bool = (
		not is_dead
		and not _pawn_soft_lock()
		and not _tank_laser_shield_up
		and shoot_held
		and _tank_laser_release_cooldown_left <= 0.0
	)
	if not want_laser:
		_stop_tank_laser_fire_if_needed(shoot_held == false)
		return
	_tank_laser_pitch_hold_sec += delta
	var beam_start: Vector3 = muzzle_flash.global_position
	var beam_end: Vector3 = _laser_beam_hit_point_global()
	var just_started: bool = not _tank_laser_fire_active
	_tank_laser_fire_active = true
	_apply_continuous_laser_beam(beam_start, beam_end, false)
	if just_started:
		_laser_tick_accum = LASER_TICK_INTERVAL
	_tank_laser_apply_tick_damage(delta, beam_start, beam_end)
	if just_started:
		if anim_player.current_animation != "shoot":
			_rpc_play_shoot_effects_for_all()
		_push_laser_net_sync(true, beam_start, beam_end)
		_laser_net_sync_accum = 0.0
	else:
		_laser_net_sync_accum += delta
		if _laser_net_sync_accum >= LASER_NET_SYNC_INTERVAL:
			_laser_net_sync_accum = 0.0
			_push_laser_net_sync(true, beam_start, beam_end)


func _stop_tank_laser_fire_if_needed(apply_release_cooldown: bool = false) -> void:
	if not _tank_laser_fire_active:
		return
	_tank_laser_fire_active = false
	if apply_release_cooldown:
		_tank_laser_release_cooldown_left = maxf(_tank_laser_release_cooldown_left, LASER_RELEASE_COOLDOWN_SEC)
	_tank_laser_pitch_hold_sec = 0.0
	_laser_net_sync_accum = 0.0
	_laser_tick_accum = 0.0
	_clear_continuous_laser_visual()
	_push_laser_net_sync(false, Vector3.ZERO, Vector3.ZERO)


func _clear_continuous_laser_visual() -> void:
	if _continuous_laser != null and is_instance_valid(_continuous_laser):
		_continuous_laser.queue_free()
	_continuous_laser = null


func _apply_continuous_laser_beam(start: Vector3, end: Vector3, net_remote_visual: bool = false) -> void:
	if _continuous_laser == null or not is_instance_valid(_continuous_laser):
		_continuous_laser = LaserBeamScene.instantiate()
		get_parent().add_child(_continuous_laser)
		if _continuous_laser.has_method("set_shooter_peer_id"):
			_continuous_laser.set_shooter_peer_id(name.to_int())
	if _continuous_laser.has_method("set_beam_net_interpolated"):
		_continuous_laser.set_beam_net_interpolated(net_remote_visual)
	_continuous_laser.update_beam(start, end)


func _push_laser_net_sync(active: bool, start: Vector3, end: Vector3) -> void:
	if HeroNet.is_gdsync():
		HeroNet.broadcast_unreliable_to_others(Callable(self, "_net_laser_pose"), [start, end, active])
		return
	if multiplayer.multiplayer_peer == null:
		return
	_net_laser_pose.rpc(start, end, active)


@rpc("any_peer", "unreliable")
func _net_laser_pose(start: Vector3, end: Vector3, active: bool) -> void:
	if _local_authority():
		return
	if not active:
		_clear_continuous_laser_visual()
		return
	_apply_continuous_laser_beam(start, end, true)


func _medic_beam_target_anchor_global(target: Node3D) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	return target.global_position + Vector3(0.0, MEDIC_BEAM_TARGET_Y_OFFSET, 0.0)


func _find_medic_beam_target() -> Node3D:
	var w: Node = get_parent()
	if w == null:
		return null
	var best: Node3D = null
	var best_d2: float = INF
	var my_pos: Vector3 = global_position
	var r2: float = MEDIC_BEAM_MAX_RANGE * MEDIC_BEAM_MAX_RANGE
	for c in w.get_children():
		if c == self:
			continue
		if not c is CharacterBody3D:
			continue
		if c.get("is_dead") == true:
			continue
		var tid: Variant = c.get("team_id")
		if typeof(tid) != TYPE_INT or int(tid) != team_id:
			continue
		var d2: float = my_pos.distance_squared_to(c.global_position)
		if d2 > r2:
			continue
		if d2 < best_d2:
			best_d2 = d2
			best = c
	return best


func _medic_beam_view_forward_horizontal() -> Vector3:
	var f: Vector3 = -camera.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 1e-8:
		f = -global_transform.basis.z
		f.y = 0.0
	if f.length_squared() < 1e-8:
		return Vector3(0, 0, -1)
	return f.normalized()


func _medic_beam_view_forward() -> Vector3:
	var f: Vector3 = -camera.global_transform.basis.z
	if f.length_squared() < 1e-8:
		f = -global_transform.basis.z
	if f.length_squared() < 1e-8:
		return Vector3(0, 0, -1)
	return f.normalized()


func _update_medic_heal_continuous_beam(delta: float) -> void:
	if _hero_archetype() != "medic":
		_medic_beam_toggle_want = false
		_stop_medic_beam_fire_if_needed()
		return
	if _pawn_soft_lock():
		_medic_beam_toggle_want = false
		_stop_medic_beam_fire_if_needed()
		return
	if Input.is_action_just_pressed("secondary"):
		_medic_beam_toggle_want = not _medic_beam_toggle_want
		if not _medic_beam_toggle_want:
			_stop_medic_beam_fire_if_needed()
	if not _medic_beam_toggle_want:
		return
	var target: Node3D = _find_medic_beam_target()
	if target == null or not is_instance_valid(target):
		_stop_medic_beam_fire_if_needed()
		return
	var beam_start: Vector3 = muzzle_flash.global_position
	var beam_end: Vector3 = _medic_beam_target_anchor_global(target)
	var beam_fwd: Vector3 = _medic_beam_view_forward()
	var just_started: bool = not _medic_beam_fire_active
	_medic_beam_fire_active = true
	_apply_continuous_heal_beam(beam_start, beam_end, beam_fwd, delta)
	_medic_beam_heal_tick_accum += delta
	while _medic_beam_heal_tick_accum >= MEDIC_BEAM_HEAL_INTERVAL:
		_medic_beam_heal_tick_accum -= MEDIC_BEAM_HEAL_INTERVAL
		HeroNet.apply_heal_on_target(target, MEDIC_BEAM_ALLY_HEAL_PER_TICK, name.to_int())
		# Self-heal is local-authority; apply directly so it is never gated by RPC delivery.
		heal_damage(MEDIC_BEAM_SELF_HEAL_PER_TICK)
	if just_started:
		_broadcast_medic_healgun_use_sfx()
		if anim_player.current_animation != "shoot":
			_rpc_play_shoot_effects_for_all()
		_push_medic_beam_net_sync(true, beam_start, beam_end, beam_fwd)
		_medic_beam_net_sync_accum = 0.0
	else:
		_medic_beam_net_sync_accum += delta
		if _medic_beam_net_sync_accum >= MEDIC_BEAM_NET_SYNC_INTERVAL:
			_medic_beam_net_sync_accum = 0.0
			_push_medic_beam_net_sync(true, beam_start, beam_end, beam_fwd)


func _stop_medic_beam_fire_if_needed() -> void:
	if not _medic_beam_fire_active:
		return
	_medic_beam_fire_active = false
	_medic_beam_heal_tick_accum = 0.0
	_medic_beam_net_sync_accum = 0.0
	_clear_continuous_heal_beam_visual()
	_push_medic_beam_net_sync(false, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)


func _clear_continuous_heal_beam_visual() -> void:
	_net_medic_beam_replica_active = false
	if _continuous_heal_beam != null and is_instance_valid(_continuous_heal_beam):
		_continuous_heal_beam.queue_free()
	_continuous_heal_beam = null


func _apply_continuous_heal_beam(start: Vector3, end: Vector3, view_forward: Vector3, delta: float = -1.0) -> void:
	if _continuous_heal_beam == null or not is_instance_valid(_continuous_heal_beam):
		_continuous_heal_beam = HealBeamScene.instantiate()
		get_parent().add_child(_continuous_heal_beam)
		if _continuous_heal_beam.has_method("set_shooter_peer_id"):
			_continuous_heal_beam.set_shooter_peer_id(name.to_int())
	_continuous_heal_beam.update_beam(start, end, view_forward, delta)


func _push_medic_beam_net_sync(active: bool, start: Vector3, end: Vector3, view_forward: Vector3) -> void:
	if HeroNet.is_gdsync():
		HeroNet.broadcast_unreliable_to_others(Callable(self, "_net_medic_beam_pose"), [start, end, view_forward, active])
		return
	if multiplayer.multiplayer_peer == null:
		return
	_net_medic_beam_pose.rpc(start, end, view_forward, active)


@rpc("any_peer", "unreliable")
func _net_medic_beam_pose(start: Vector3, end: Vector3, view_forward: Vector3, active: bool) -> void:
	if _local_authority():
		return
	if not active:
		_clear_continuous_heal_beam_visual()
		return
	_net_medic_beam_snap_start = start
	_net_medic_beam_snap_end = end
	_net_medic_beam_snap_fwd = view_forward
	_net_medic_beam_replica_active = true
	_apply_continuous_heal_beam(start, end, view_forward, get_physics_process_delta_time())

func _update_dead_visibility() -> void:
	var mesh_inst: Node = body_mesh_placeholder if body_mesh_placeholder != null else get_node_or_null("MeshInstance3D")
	var health_bar_3d: Node = get_node_or_null("HealthBar3D")
	var col: Node = get_node_or_null("CollisionShape3D")
	if mesh_inst:
		mesh_inst.visible = not is_dead and not _player_uses_imported_character_model()
	if character_model_root != null and character_model_root.get_child_count() > 0:
		# Stay visible in the tree so shadows cast; owning player’s mesh is skipped via Camera3D.cull_mask + render layer.
		character_model_root.visible = not is_dead
	if health_bar_3d:
		health_bar_3d.visible = not is_dead
	if col:
		col.disabled = is_dead
	_update_camera_mode_visuals()


func _on_respawn_timer_timeout() -> void:
	_medic_beam_toggle_want = false
	_stop_medic_beam_fire_if_needed()
	_spring_cancel_charge()
	_spring_cancel_jump_charge()
	_spring_punch_cooldown_left = 0.0
	_spring_ult_hover_active = false
	_spring_ult_hover_target_y = 0.0
	_spring_ult_launch_active = false
	_spring_ult_has_launched = false
	_spring_ult_last_valid_target_data.clear()
	_spring_ult_preview_clear()
	_orb_dash_active = false
	_orb_dash_time_left = 0.0
	_orb_dash_velocity_xz = Vector3.ZERO
	_orb_primary_fire_cooldown_left = 0.0
	_end_orb_ultimate_orbit_state(false)
	_sniper_fire_cooldown = 0.0
	_sniper_is_reloading = false
	_sniper_reload_left = 0.0
	_sniper_ult_windup_left = 0.0
	_sniper_ult_primary_lock_left = 0.0
	_sniper_ult_linger_left = 0.0
	_sniper_ult_linger_burst_ids.clear()
	_sniper_ult_linger_done_ids.clear()
	_missile_ability_cooldown_left = 0.0
	_missile_windup_active = false
	if _missile_windup_marker != null and is_instance_valid(_missile_windup_marker):
		_missile_windup_marker.queue_free()
	_missile_windup_marker = null
	_missile_shoot_lock_left = 0.0
	missile_targeting_ui_active = false
	_missile_ult_hover_active = false
	_missile_ult_hover_target_y = 0.0
	_missile_ult_arm_delay_left = 0.0
	_missile_ult_has_fired = false
	_missile_ult_preview_clear()
	_timed_mag_reload_remaining = 0.0
	_timed_mag_reload_active = false
	_set_tank_laser_shield_up(false)
	_set_tank_laser_ultimate_vfx_active(false, true)
	_push_tank_laser_ultimate_visual_state(false)
	_tank_laser_ult_push_accum = 0.0
	ultimate_active = false
	ultimate_duration_sec = 0.0
	ultimate_remaining_sec = 0.0
	health = max_health
	var world: Node = get_parent()
	if world and world.has_method("respawn_player"):
		world.respawn_player(self)
	else:
		position = Vector3.ZERO
	velocity = Vector3.ZERO
	is_dead = false
	_respawn_invulnerable_until_msec = Time.get_ticks_msec() + 5000
	if _local_authority():
		_reset_local_view_pitch_after_spawn_or_hero_change()
	player_respawned.emit()
	var hero_after: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero_after != null and hero_after.magazine_size >= 0:
		magazine_current = magazine_max_clip
	health_changed.emit(health)
	_replicate_combat_state()


func _is_respawn_invulnerable() -> bool:
	return Time.get_ticks_msec() < _respawn_invulnerable_until_msec

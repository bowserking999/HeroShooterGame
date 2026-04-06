extends CharacterBody3D

signal health_changed(health_value)
signal player_died
signal player_respawned

const RESPAWN_DELAY := 5.0

@onready var camera = $Camera3D
@onready var anim_player = $AnimationPlayer
@onready var muzzle_flash = $Camera3D/Pistol/MuzzleFlash
@onready var raycast = $Camera3D/RayCast3D

const HealOrbScene = preload("res://heal_orb.tscn")
const TankRoundScene = preload("res://tank_round.tscn")
const LaserBeamScene = preload("res://laser_beam.tscn")

const HEAL_ORB_SPEED: float = 25.0
const TANK_ROUND_SPEED: float = 45.0
const LASER_MAX_RANGE: float = 50.0
const LASER_NET_SYNC_INTERVAL: float = 0.05
const HITSCAN_DAMAGE: int = 50
const HITSCAN_HEAL: int = 50

var move_speed: float = 10.0
var jump_velocity: float = 10.0
var gravity = 20
@export var max_health: int = 250
var health: int = 250
var weaponNum = 1
@export var team_id: int = 0 # 0 = Team A, 1 = Team B
@export var hero_id: String = "dps_missile"
var is_dead := false

var _continuous_laser: Node3D = null
var _tank_laser_fire_active: bool = false
var _laser_net_sync_accum: float = 0.0
var _last_hero_id_for_stats: String = ""

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func _ready():
	_apply_hero_stats()
	if not is_multiplayer_authority(): return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true

func _character_select_open() -> bool:
	var w := get_parent()
	return w != null and w.has_method("is_character_select_open") and w.is_character_select_open()

func _hero_archetype() -> String:
	var hero: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero != null and hero.archetype_id != "":
		return hero.archetype_id
	return hero_id

func _apply_hero_stats() -> void:
	var hero: HeroResource = HeroesRegistry.get_hero(hero_id)
	if hero:
		max_health = hero.max_health
		move_speed = hero.run_speed
		jump_velocity = hero.jump_velocity
		weaponNum = hero.default_weapon
		var mesh_inst: MeshInstance3D = get_node_or_null("MeshInstance3D")
		if mesh_inst:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = hero.body_color
			mesh_inst.set_surface_override_material(0, mat)
	else:
		max_health = 250
	if is_multiplayer_authority():
		health = max_health
		health_changed.emit(health)
	_last_hero_id_for_stats = hero_id


func _unhandled_input(event):
	if not is_multiplayer_authority(): return
	if _character_select_open():
		return
	if is_dead: return
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * .005)
		camera.rotate_x(-event.relative.y * .005)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
	
	if Input.is_action_just_pressed("shoot"):
		# Continuous beam: hold-to-fire is handled in _physics_process (no hitscan tap here).
		if hero_id == "tank_laser" and weaponNum == 1:
			pass
		elif anim_player.current_animation != "shoot":
			play_shoot_effects.rpc()
			# Orb healer: left-click fires bouncing healing orbs (hero id support / archetype support).
			if _hero_archetype() == "support" and weaponNum == 2:
				var shooter_peer_id := multiplayer.get_unique_id()
				_spawn_heal_orb(
					muzzle_flash.global_position,
					- camera.global_transform.basis.z,
					shooter_peer_id
				)
				_spawn_heal_orb.rpc(
					muzzle_flash.global_position,
					- camera.global_transform.basis.z,
					shooter_peer_id
				)
			# Tank: explosive shells (laser hero uses continuous beam in _physics_process).
			elif _hero_archetype() == "tank" and weaponNum == 1:
				var shooter_peer_id := multiplayer.get_unique_id()
				_spawn_tank_round(
					muzzle_flash.global_position,
					- camera.global_transform.basis.z,
					shooter_peer_id
				)
				_spawn_tank_round.rpc(
					muzzle_flash.global_position,
					- camera.global_transform.basis.z,
					shooter_peer_id
				)
			else:
				if raycast.is_colliding():
					var hit_player = raycast.get_collider()
					if hit_player != null and hit_player.has_method("receive_damage") and hit_player.has_method("heal_damage"):
						var target_team = hit_player.get("team_id")
						if typeof(target_team) != TYPE_INT:
							return
						if weaponNum == 1 and int(target_team) != team_id:
							# Damage only enemies
							hit_player.receive_damage.rpc_id(hit_player.get_multiplayer_authority(), HITSCAN_DAMAGE)
							get_parent().record_damaged_by_me(hit_player.name.to_int())
						elif weaponNum == 2 and int(target_team) == team_id:
							# Heal only allies
							hit_player.heal_damage.rpc_id(hit_player.get_multiplayer_authority(), HITSCAN_HEAL)

func _physics_process(delta: float) -> void:
	if hero_id != _last_hero_id_for_stats:
		_apply_hero_stats()
	_update_dead_visibility()
	if is_multiplayer_authority():
		_update_tank_laser_continuous_beam(delta)
	if not is_multiplayer_authority(): return
	if is_dead: return
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	if _character_select_open():
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		if anim_player.current_animation != "shoot":
			anim_player.play("idle")
		move_and_slide()
		return

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)
		
	if anim_player.current_animation == "shoot":
		pass
	elif input_dir != Vector2.ZERO and is_on_floor():
		anim_player.play("move")
	else:
		anim_player.play("idle")


	move_and_slide()

@rpc("call_local")
func play_shoot_effects():
	anim_player.stop()
	anim_player.play("shoot")
	muzzle_flash.restart()
	muzzle_flash.emitting = true
	
@rpc("any_peer")
func receive_damage(amount: int = HITSCAN_DAMAGE) -> void:
	if is_dead:
		return
	health -= amount
	if health <= 0:
		health = 0
		is_dead = true
		player_died.emit()
		health_changed.emit(health)
		var t := get_tree().create_timer(RESPAWN_DELAY)
		t.timeout.connect(_on_respawn_timer_timeout)
	else:
		health_changed.emit(health)

@rpc("any_peer")
func heal_damage(amount: int = HITSCAN_HEAL) -> void:
	if is_dead:
		return
	health = mini(health + amount, max_health)
	health_changed.emit(health)


func _on_animation_player_animation_finished(anim_name):
	if anim_name == "shoot":
		anim_player.play("idle")

@rpc("any_peer", "reliable")
func _spawn_heal_orb(origin: Vector3, direction: Vector3, shooter_peer_id: int) -> void:
	# Every peer spawns the orb visually, but only the shooter peer heals on impact.
	var orb = HealOrbScene.instantiate()
	orb.global_position = origin
	get_parent().add_child(orb)
	if orb.has_method("setup"):
		orb.setup(shooter_peer_id, direction.normalized() * HEAL_ORB_SPEED)

@rpc("any_peer", "reliable")
func _spawn_tank_round(origin: Vector3, direction: Vector3, shooter_peer_id: int) -> void:
	var round = TankRoundScene.instantiate()
	round.global_position = origin
	get_parent().add_child(round)
	if round.has_method("setup"):
		round.setup(shooter_peer_id, direction.normalized() * TANK_ROUND_SPEED)


## Aim point along camera look (crosshair); beam is drawn from muzzle to here.
func _laser_beam_hit_point_global() -> Vector3:
	var cam_pos: Vector3 = camera.global_position
	var aim_dir: Vector3 = (-camera.global_transform.basis.z).normalized()
	var aim_to: Vector3 = cam_pos + aim_dir * LASER_MAX_RANGE
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(cam_pos, aim_to)
	query.collision_mask = 0b11
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [self]
	var hit := space_state.intersect_ray(query)
	if hit.has("position"):
		return hit.position
	return aim_to


func _update_tank_laser_continuous_beam(delta: float) -> void:
	if hero_id != "tank_laser" or weaponNum != 1:
		_stop_tank_laser_fire_if_needed()
		return
	var want_laser := (
		not is_dead
		and not _character_select_open()
		and Input.is_action_pressed("shoot")
	)
	if not want_laser:
		_stop_tank_laser_fire_if_needed()
		return
	var beam_start: Vector3 = muzzle_flash.global_position
	var beam_end: Vector3 = _laser_beam_hit_point_global()
	var just_started := not _tank_laser_fire_active
	_tank_laser_fire_active = true
	_apply_continuous_laser_beam(beam_start, beam_end)
	if just_started:
		if anim_player.current_animation != "shoot":
			play_shoot_effects.rpc()
		_push_laser_net_sync(true, beam_start, beam_end)
		_laser_net_sync_accum = 0.0
	else:
		_laser_net_sync_accum += delta
		if _laser_net_sync_accum >= LASER_NET_SYNC_INTERVAL:
			_laser_net_sync_accum = 0.0
			_push_laser_net_sync(true, beam_start, beam_end)


func _stop_tank_laser_fire_if_needed() -> void:
	if not _tank_laser_fire_active:
		return
	_tank_laser_fire_active = false
	_laser_net_sync_accum = 0.0
	_clear_continuous_laser_visual()
	_push_laser_net_sync(false, Vector3.ZERO, Vector3.ZERO)


func _clear_continuous_laser_visual() -> void:
	if _continuous_laser != null and is_instance_valid(_continuous_laser):
		_continuous_laser.queue_free()
	_continuous_laser = null


func _apply_continuous_laser_beam(start: Vector3, end: Vector3) -> void:
	if _continuous_laser == null or not is_instance_valid(_continuous_laser):
		_continuous_laser = LaserBeamScene.instantiate()
		get_parent().add_child(_continuous_laser)
		if _continuous_laser.has_method("set_shooter_peer_id"):
			_continuous_laser.set_shooter_peer_id(name.to_int())
	_continuous_laser.update_beam(start, end)


func _push_laser_net_sync(active: bool, start: Vector3, end: Vector3) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_net_laser_pose.rpc(start, end, active)


@rpc("any_peer", "unreliable")
func _net_laser_pose(start: Vector3, end: Vector3, active: bool) -> void:
	if is_multiplayer_authority():
		return
	if not active:
		_clear_continuous_laser_visual()
		return
	_apply_continuous_laser_beam(start, end)

func _update_dead_visibility() -> void:
	var mesh_inst := get_node_or_null("MeshInstance3D")
	var health_bar_3d := get_node_or_null("HealthBar3D")
	var pistol := get_node_or_null("Camera3D/Pistol")
	var col := get_node_or_null("CollisionShape3D")
	if mesh_inst:
		mesh_inst.visible = not is_dead
	if health_bar_3d:
		health_bar_3d.visible = not is_dead
	if pistol:
		pistol.visible = not is_dead
	if col:
		col.disabled = is_dead

func _on_respawn_timer_timeout() -> void:
	health = max_health
	var world := get_parent()
	if world and world.has_method("respawn_player"):
		world.respawn_player(self)
	else:
		position = Vector3.ZERO
	velocity = Vector3.ZERO
	is_dead = false
	player_respawned.emit()
	health_changed.emit(health)

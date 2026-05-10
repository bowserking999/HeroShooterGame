class_name HeroEffectsPreload
## Warms hero effects by drawing them in a hidden SubViewport for several frames.
## Loading + `play()` alone is not enough: GPUParticles3D and many materials only compile GPU
## pipelines on the first *draw*. Parenting VFX far from the map often yields **no camera**
## at the main menu, so nothing was rendered and the first real explosion still hitched.

## Binbun scenes every match needs (death feedback, capture area rim, etc.).
const _ALWAYS_WARM_PATHS: Array[String] = [
	"res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_01.tscn",
	"res://assets/BinbunVFX/magic_areas/effects/rim_area/rim_area_vfx_02.tscn",
]

const _HERO_PATHS: Dictionary = {
	"tank_explosive": [
		"res://tank_round.tscn",
		"res://landmine.tscn",
		"res://explosion_placeholder.tscn",
		"res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_06.tscn",
		"res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_05.tscn",
		"res://assets/BinbunVFX/impact_explosions/effects/impact/vfx_impact_02.tscn",
	],
	"tank_laser": [
		"res://laser_beam.tscn",
		"res://laser_shield.tscn",
		"res://assets/BinbunVFX/magic_areas/effects/pulse_area/pulse_area_vfx_02.tscn",
		"res://assets/BinbunVFX/beam_vfx/effects/laser/laser_vfx_02.tscn",
	],
	"dps_missile": [
		"res://assets/BinbunVFX/muzzle_flash/effects/big_flash/big_flash_04.tscn",
	],
	"dps_sniper": [
		"res://assets/BinbunVFX/muzzle_flash/effects/big_flash/big_flash_05.tscn",
		"res://sniper_ult_beam.tscn",
		"res://assets/BinbunVFX/beam_vfx/effects/beam/beam_vfx_08.tscn",
		"res://smoke_bomb.tscn",
		"res://assets/BinbunVFX/smoke_effects/effects/smoke/smoke_vfx_01.tscn",
		"res://assets/BinbunVFX/smoke_effects/effects/smoke_thin/smoke_thin_vfx_04.tscn",
	],
	"dps_spring": [],
	"healer_medic": [
		"res://medic_burst.tscn",
		"res://heal_beam.tscn",
		"res://heal_beam.gdshader",
		"res://assets/BinbunVFX/poison_effects/effects/poison_bubble/poison_bubble_vfx_03.tscn",
		"res://assets/BinbunVFX/magic_projectiles/effects/mprojectile_basic/mprojectile_basic_vfx_04.tscn",
	],
	"healer_orb": [
		"res://heal_orb.tscn",
		"res://assets/BinbunVFX/magic_orbs/effects/magic_orb_flare/magic_orb_flare_vfx_04.tscn",
		"res://assets/BinbunVFX/magic_orbs/effects/magic_orb_huge/magic_orb_huge_vfx_01.tscn",
	],
}

## Fallback when a scene root is not Node3D (rare).
const _WARM_POSITION := Vector3(4096.0, -512.0, 4096.0)
const _TOUCH_DELAY_SEC := 0.03
const _FREE_AFTER_TOUCH_SEC := 0.85
## Extra time after `play()` so the GPU can finish pipeline creation for heavy particle shaders.
const _GPU_WARM_HOLD_SEC := 0.45

## Spread `play()` across frames so one boot frame does not compile every pipeline at once.
static var _warm_boot_stagger_sec: float = 0.0


## Warm every registered hero's paths once at boot (all roles in a match).
static func warm_all_registered_heroes(world: Node) -> void:
	for hid in HeroesRegistry.get_all_hero_ids():
		warm(str(hid), world)


static func warm_always(world: Node) -> void:
	if world == null or not world.is_inside_tree():
		for path_str in _ALWAYS_WARM_PATHS:
			var path := str(path_str)
			if path.is_empty() or not ResourceLoader.exists(path):
				continue
			ResourceLoader.load(path)
		return
	for path_str in _ALWAYS_WARM_PATHS:
		var path := str(path_str)
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		if path.ends_with(".tscn"):
			_warm_scene(world, path)


static func warm(hero_id: String, world: Node) -> void:
	var paths: Variant = _HERO_PATHS.get(hero_id)
	if paths == null:
		return
	for path_str in paths as Array:
		var path := str(path_str)
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		if path.ends_with(".tscn"):
			if world != null and world.is_inside_tree():
				_warm_scene(world, path)
			else:
				ResourceLoader.load(path)
		else:
			ResourceLoader.load(path)

static func _warm_scene(world: Node, scene_path: String) -> void:
	var packed: PackedScene = ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	var tree := world.get_tree()
	if inst is Node3D:
		var vp := _make_offscreen_warm_viewport(world)
		vp.add_child(inst)
		(inst as Node3D).transform = Transform3D.IDENTITY
		var delay := _TOUCH_DELAY_SEC + _warm_boot_stagger_sec
		_warm_boot_stagger_sec += 0.028
		tree.create_timer(delay).timeout.connect(func () -> void:
			if not is_instance_valid(vp) or not is_instance_valid(inst):
				return
			_warm_touch(inst, scene_path)
			tree.create_timer(_GPU_WARM_HOLD_SEC).timeout.connect(func () -> void:
				if is_instance_valid(vp):
					vp.queue_free()
			)
		)
	else:
		world.add_child(inst)
		inst.set_process(false)
		inst.set_physics_process(false)
		tree.create_timer(_TOUCH_DELAY_SEC).timeout.connect(func () -> void:
			if not is_instance_valid(inst):
				return
			inst.set_process(false)
			inst.set_physics_process(false)
			_warm_touch(inst, scene_path)
			tree.create_timer(_FREE_AFTER_TOUCH_SEC).timeout.connect(func () -> void:
				if is_instance_valid(inst):
					inst.queue_free()
			)
		)


static func _make_offscreen_warm_viewport(world: Node) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = "_HeroFxWarmSubViewport"
	vp.size = Vector2i(256, 256)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.world_3d = World3D.new()
	world.add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.2, 0.22)
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, 38.0, 0.0)
	sun.shadow_enabled = false
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(0.0, 10.0, 26.0)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	vp.add_child(cam)
	return vp

static func _warm_touch(inst: Node, scene_path: String) -> void:
	# Binbun explosion: force one play() so particle/shader pipelines compile.
	if scene_path.contains("vfx_explosion"):
		if inst.has_method("play"):
			inst.set("autoplay", false)
			inst.set("one_shot", true)
			inst.play()
		return
	# Heal orb: magic flare child gets AnimationPlayer in _ready; kick anims + particles.
	if scene_path.ends_with("heal_orb.tscn"):
		for n in inst.find_children("*", "AnimationPlayer", true, false):
			if n is AnimationPlayer:
				var ap := n as AnimationPlayer
				if ap.has_animation("main"):
					ap.play("main")
		for n in inst.find_children("*", "GPUParticles3D", true, false):
			if n is GPUParticles3D:
				(n as GPUParticles3D).restart()
		return
	# Magic orb scene alone (if ever listed).
	if scene_path.contains("magic_orb_flare"):
		if inst.has_method("play"):
			inst.set("autoplay", false)
			inst.set("one_shot", true)
			inst.play()
		return
	if scene_path.contains("magic_orb_huge"):
		if inst.has_method("play"):
			inst.set("autoplay", false)
			inst.set("one_shot", true)
			inst.play()
		return
	if scene_path.contains("rim_area"):
		if inst.has_method("play"):
			inst.set("autoplay", false)
			inst.set("one_shot", true)
			inst.play()
		return
	if scene_path.ends_with("laser_beam.tscn"):
		var lvfx: Node = inst.get_node_or_null("LaserVFX_02")
		if lvfx != null and lvfx.has_method("play"):
			lvfx.set("autoplay", false)
			lvfx.set("one_shot", true)
			lvfx.play()
		return
	if scene_path.ends_with("heal_beam.tscn"):
		for child in inst.get_children():
			if child.has_method("play"):
				child.set("autoplay", false)
				child.set("one_shot", true)
				child.play()
		return
	# Placeholder / tank round: existing _ready + mesh is enough after one frame.
	if scene_path.ends_with("explosion_placeholder.tscn"):
		return
	if scene_path.ends_with("tank_round.tscn"):
		return
	if scene_path.contains("vfx_explosion_05"):
		if inst.has_method("play"):
			inst.set("autoplay", false)
			inst.set("one_shot", true)
			inst.play()
		return
	if scene_path.contains("vfx_impact_02"):
		if inst.has_method("play"):
			inst.set("autoplay", false)
			inst.set("one_shot", true)
			inst.play()
		return
	if scene_path.ends_with("landmine.tscn"):
		return
	if scene_path.contains("big_flash"):
		if inst.has_method("play"):
			inst.set("autoplay", false)
			inst.set("one_shot", true)
			inst.play()
		return
	if scene_path.contains("mprojectile_basic") or scene_path.contains("poison_bubble"):
		if inst.has_method("play"):
			inst.set("autoplay", false)
			inst.set("one_shot", true)
			inst.play()
		return
	if inst.has_method("play"):
		inst.set("autoplay", false)
		inst.set("one_shot", true)
		inst.play()

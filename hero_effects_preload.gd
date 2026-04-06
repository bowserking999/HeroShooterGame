class_name HeroEffectsPreload
## Warms hero effects by instantiating scenes off-world and running VFX one tick.
## ResourceLoader.load alone does not compile shaders or run _ready(); first real use still hitches.

const _HERO_PATHS: Dictionary = {
	"tank_explosive": [
		"res://tank_round.tscn",
		"res://explosion_placeholder.tscn",
		"res://assets/BinbunVFX/impact_explosions/effects/explosion/vfx_explosion_06.tscn",
	],
	"tank_laser": [
		"res://laser_beam.tscn",
		"res://assets/BinbunVFX/beam_vfx/effects/laser/laser_vfx_02.tscn",
	],
	"dps_missile": [],
	"dps_sniper": [],
	"dps_spring": [],
	"healer_medic": [],
	"healer_orb": [
		"res://heal_orb.tscn",
		"res://assets/BinbunVFX/magic_orbs/effects/magic_orb_huge/magic_orb_huge_vfx_01.tscn",
	],
}

## Far from gameplay so warmup flashes are not visible (World root is a plain Node).
const _WARM_POSITION := Vector3(4096.0, -512.0, 4096.0)
const _TOUCH_DELAY_SEC := 0.03
const _FREE_AFTER_TOUCH_SEC := 0.85

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
	world.add_child(inst)
	if inst is Node3D:
		(inst as Node3D).position = _WARM_POSITION
	inst.set_process(false)
	inst.set_physics_process(false)
	var tree := world.get_tree()
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
	# Placeholder / tank round: existing _ready + mesh is enough after one frame.
	if scene_path.ends_with("explosion_placeholder.tscn"):
		return
	if scene_path.ends_with("tank_round.tscn"):
		return

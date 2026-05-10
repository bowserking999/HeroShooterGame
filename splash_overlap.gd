class_name SplashOverlap
extends RefCounted

## Sphere overlap against the physics world (capsules, etc.), not CharacterBody3D origins.
static func character_bodies_in_sphere(
	world: World3D,
	center: Vector3,
	radius: float,
	collision_mask: int,
	exclude_rids: Array = []
) -> Array:
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = collision_mask
	if not exclude_rids.is_empty():
		params.exclude = exclude_rids
	var hits: Array = space.intersect_shape(params, 32)
	var out: Array = []
	var seen: Dictionary = {}
	for hit in hits:
		if not hit.has("collider"):
			continue
		var c: Variant = hit["collider"]
		if not (c is CharacterBody3D):
			continue
		var body: CharacterBody3D = c
		if not body.has_method("receive_damage"):
			continue
		var id: int = body.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		out.append(body)
	return out


## Cylinder overlap (axis = shape transform +Y), for melee / punch volumes.
static func character_bodies_in_cylinder(
	world: World3D,
	transform: Transform3D,
	height: float,
	radius: float,
	collision_mask: int,
	exclude_rids: Array = []
) -> Array:
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var shape := CylinderShape3D.new()
	shape.height = height
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = transform
	params.collision_mask = collision_mask
	if not exclude_rids.is_empty():
		params.exclude = exclude_rids
	var hits: Array = space.intersect_shape(params, 32)
	var out: Array = []
	var seen: Dictionary = {}
	for hit in hits:
		if not hit.has("collider"):
			continue
		var c: Variant = hit["collider"]
		if not (c is CharacterBody3D):
			continue
		var body: CharacterBody3D = c
		if not body.has_method("receive_damage"):
			continue
		var id: int = body.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		out.append(body)
	return out

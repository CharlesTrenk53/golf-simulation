extends Node3D

# POC-30E: Construction Grid -> Course Dressing / Environment
# -------------------------------------------------------------
# Presentation-only vegetation and environmental dressing derived from the
# authoritative construction grid. This layer deliberately does NOT create
# golf-rule authority: no tree/shrub generated here changes lie, collision,
# hazards, shot outcomes, scoring, traffic, or saved construction data.
#
# Until a future construction/object system makes vegetation authoritative,
# dressing is kept in safe ROUGH cells only and is excluded from any rough cell
# touching a non-rough golf surface. This lets the visual course feel framed and
# alive without putting fake obstacles into the player's intended shot corridor.

const TREE_DENSITY_MOD: int = 3
const SHRUB_DENSITY_MOD: int = 2
const SAFE_NEIGHBOR_DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

var construction_grid = null
var dressing_records: Array = []


func render_dressing(grid) -> bool:
	clear_dressing()
	if grid == null or grid.width <= 0 or grid.height <= 0 or grid.tile_size_yards <= 0.0:
		return false

	construction_grid = grid
	dressing_records = build_dressing_plan(grid)
	_add_environment()
	_add_tree_multimeshes()
	_add_shrub_multimesh()
	return true


func clear_dressing() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	dressing_records.clear()
	construction_grid = null


# Stable, replayable presentation plan. No random-number generator is used;
# cell coordinates alone determine whether dressing appears and where it sits.
func build_dressing_plan(grid) -> Array:
	var plan: Array = []
	if grid == null:
		return plan

	for y in range(int(grid.height)):
		for x in range(int(grid.width)):
			if not _is_safe_rough_cell(grid, x, y):
				continue
			var seed: int = _cell_seed(x, y)
			var base: Vector3 = grid.tile_center_world(x, y)
			var size: float = float(grid.tile_size_yards)

			# Trees are sparse enough to read as framing rather than a wall. Property
			# perimeter cells get one extra chance so the playable land has a horizon.
			var perimeter: bool = x == 0 or y == 0 or x == int(grid.width) - 1 or y == int(grid.height) - 1
			if seed % TREE_DENSITY_MOD == 0 or (perimeter and seed % 2 == 0):
				var tree_offset := Vector3(
					_offset_component(seed, 11) * size * 0.24,
					0.0,
					_offset_component(seed, 23) * size * 0.24
				)
				plan.append({
					"kind": "TREE",
					"cell": Vector2i(x, y),
					"position": base + tree_offset,
					"scale": 0.85 + float(seed % 7) * 0.045,
					"source": "construction_grid_safe_rough"
				})

			# Low shrubs provide near-ground variation, also only in safe rough.
			if int(seed / 7) % SHRUB_DENSITY_MOD == 0:
				var shrub_offset := Vector3(
					_offset_component(seed, 37) * size * 0.30,
					0.0,
					_offset_component(seed, 41) * size * 0.30
				)
				plan.append({
					"kind": "SHRUB",
					"cell": Vector2i(x, y),
					"position": base + shrub_offset,
					"scale": 0.70 + float(int(seed / 13) % 6) * 0.055,
					"source": "construction_grid_safe_rough"
				})
	return plan


func dressing_count(kind_value: String = "") -> int:
	var kind: String = kind_value.to_upper()
	if kind.is_empty():
		return dressing_records.size()
	var count: int = 0
	for record_value in dressing_records:
		var record: Dictionary = record_value
		if str(record.get("kind", "")) == kind:
			count += 1
	return count


func _is_safe_rough_cell(grid, x: int, y: int) -> bool:
	if not grid.is_in_bounds(x, y) or str(grid.surface_at(x, y)) != "ROUGH":
		return false
	var neighbors: Dictionary = grid.surface_neighbors(x, y)
	for direction_value in SAFE_NEIGHBOR_DIRECTIONS:
		var direction: String = str(direction_value)
		var neighbor_surface: String = str(neighbors.get(direction, ""))
		if not neighbor_surface.is_empty() and neighbor_surface != "ROUGH":
			return false
	return true


func _cell_seed(x: int, y: int) -> int:
	# Positive integer hash with stable constants; intentionally independent of
	# runtime RNG state so saves/screenshots remain visually repeatable.
	return absi(((x + 17) * 73856093) ^ ((y + 31) * 19349663))


func _offset_component(seed: int, salt: int) -> float:
	var mixed: int = absi(seed ^ (salt * 83492791))
	return (float(mixed % 2001) / 1000.0) - 1.0


func _add_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "CourseWorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.47, 0.69, 0.88)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.83, 0.76)
	environment.ambient_light_energy = 0.72
	world_environment.environment = environment
	world_environment.set_meta("classification", "COURSE_ENVIRONMENT")
	world_environment.set_meta("authority", "presentation_only")
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "CourseSun"
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.set_meta("classification", "COURSE_LIGHTING")
	sun.set_meta("authority", "presentation_only")
	add_child(sun)


func _add_tree_multimeshes() -> void:
	var trees: Array = []
	for record_value in dressing_records:
		var record: Dictionary = record_value
		if str(record.get("kind", "")) == "TREE":
			trees.append(record)
	if trees.is_empty():
		return

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.32
	trunk_mesh.bottom_radius = 0.42
	trunk_mesh.height = 4.4
	trunk_mesh.radial_segments = 7
	trunk_mesh.material = _material(Color(0.27, 0.18, 0.10), 0.98)
	var trunk_instance := _make_multimesh_instance("TreeTrunks", trunk_mesh, trees, "TRUNK")
	trunk_instance.set_meta("classification", "COURSE_DRESSING_TREES")
	add_child(trunk_instance)

	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 2.45
	canopy_mesh.height = 4.3
	canopy_mesh.radial_segments = 10
	canopy_mesh.rings = 6
	canopy_mesh.material = _material(Color(0.12, 0.34, 0.12), 0.96)
	var canopy_instance := _make_multimesh_instance("TreeCanopies", canopy_mesh, trees, "CANOPY")
	canopy_instance.set_meta("classification", "COURSE_DRESSING_CANOPIES")
	add_child(canopy_instance)


func _add_shrub_multimesh() -> void:
	var shrubs: Array = []
	for record_value in dressing_records:
		var record: Dictionary = record_value
		if str(record.get("kind", "")) == "SHRUB":
			shrubs.append(record)
	if shrubs.is_empty():
		return

	var shrub_mesh := SphereMesh.new()
	shrub_mesh.radius = 1.05
	shrub_mesh.height = 1.45
	shrub_mesh.radial_segments = 8
	shrub_mesh.rings = 5
	shrub_mesh.material = _material(Color(0.16, 0.39, 0.14), 0.98)
	var shrub_instance := _make_multimesh_instance("RoughShrubs", shrub_mesh, shrubs, "SHRUB")
	shrub_instance.set_meta("classification", "COURSE_DRESSING_SHRUBS")
	add_child(shrub_instance)


func _make_multimesh_instance(name_value: String, mesh: Mesh, records: Array, part: String) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = records.size()
	for i in range(records.size()):
		var record: Dictionary = records[i]
		var base: Vector3 = record.get("position", Vector3.ZERO)
		var scale_value: float = float(record.get("scale", 1.0))
		var basis := Basis.IDENTITY.scaled(Vector3(scale_value, scale_value, scale_value))
		var origin: Vector3 = base
		match part:
			"TRUNK":
				origin.y += 2.2 * scale_value
			"CANOPY":
				origin.y += 5.25 * scale_value
			"SHRUB":
				origin.y += 0.55 * scale_value
		multimesh.set_instance_transform(i, Transform3D(basis, origin))

	var instance := MultiMeshInstance3D.new()
	instance.name = name_value
	instance.multimesh = multimesh
	instance.set_meta("instance_count", records.size())
	instance.set_meta("source", "construction_grid_safe_rough")
	instance.set_meta("authority", "presentation_only")
	return instance


func _material(color: Color, roughness_value: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness_value
	return material

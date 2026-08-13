extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const ConstructionGridRenderer = preload("res://scenes/construction_grid_renderer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-22D: construction grid course renderer")
	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(6, 5, 5.0, Vector2(-15.0, -10.0)), "construction grid configures")

	# Build a compact but varied player-authored hole footprint.
	grid.set_surface(2, 4, "TEE")
	grid.set_surface(3, 4, "TEE")
	for y in range(1, 4):
		grid.set_surface(2, y, "FAIRWAY")
		grid.set_surface(3, y, "FAIRWAY")
	grid.set_surface(2, 0, "GREEN")
	grid.set_surface(3, 0, "GREEN")
	grid.set_surface(1, 1, "BUNKER")
	grid.set_surface(4, 2, "WATER")

	# Elevation changes should create shared sloping edges rather than isolated
	# vertical tile steps.
	grid.set_elevation(2, 2, 2.0)
	grid.set_elevation(3, 2, 4.0)
	grid.set_elevation(2, 3, 6.0)
	grid.set_elevation(3, 3, 8.0)

	var renderer = ConstructionGridRenderer.new()
	get_root().add_child(renderer)
	_assert_true(renderer.render_grid(grid), "renderer accepts authoritative construction grid")
	_assert_equal(renderer.rendered_surfaces.size(), 6, "renderer creates one mesh per represented surface class")

	for surface in ["ROUGH", "FAIRWAY", "GREEN", "TEE", "BUNKER", "WATER"]:
		var visual = renderer.surface_visual(surface)
		_assert_true(visual != null, "%s visual exists" % surface.to_lower())
		if visual != null:
			_assert_equal(str(visual.get_meta("source", "")), "construction_grid", "%s visual identifies construction grid as source" % surface.to_lower())
			_assert_equal(renderer.rendered_tile_count(surface), grid.count_surface(surface), "%s rendered tile count reconciles" % surface.to_lower())

	# The corner between four elevated fairway tiles averages 2,4,6,8 = 5.
	_assert_float_close(renderer.terrain_height_at_grid_corner(3, 3), 5.0, "shared terrain corner averages neighboring authored elevations")

	# Outer property corner is driven by its one adjacent rough tile.
	_assert_float_close(renderer.terrain_height_at_grid_corner(0, 0), 0.0, "property edge terrain remains deterministic")

	var fairway_visual = renderer.surface_visual("FAIRWAY")
	if fairway_visual != null and fairway_visual is MeshInstance3D:
		var mesh: ArrayMesh = fairway_visual.mesh
		_assert_true(mesh != null and mesh.get_surface_count() == 1, "fairway tiles are batched into one coherent mesh")
		if mesh != null and mesh.get_surface_count() == 1:
			var arrays: Array = mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			_assert_equal(vertices.size(), grid.count_surface("FAIRWAY") * 6, "batched fairway mesh contains two triangles per purchased tile")

	print("POC22_RENDERER_SUMMARY surfaces=%d rough=%d fairway=%d green=%d" % [
		renderer.rendered_surfaces.size(),
		grid.count_surface("ROUGH"),
		grid.count_surface("FAIRWAY"),
		grid.count_surface("GREEN")
	])

	renderer.queue_free()
	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _assert_float_close(actual: float, expected: float, label: String) -> void:
	if abs(actual - expected) <= 0.001:
		print("PASS: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-22D CONSTRUCTION GRID COURSE RENDERER PASSED")
		quit(0)
	else:
		push_error("POC-22D CONSTRUCTION GRID COURSE RENDERER FAILED: %d" % failures)
		quit(1)

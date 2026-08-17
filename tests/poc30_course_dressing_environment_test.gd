extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const ConstructionGridCourseDressing = preload("res://scenes/construction_grid_course_dressing.gd")

var failures: int = 0


func _init() -> void:
	print("POC-30E: deterministic safe-rough course dressing and environment")

	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(9, 9, 10.0, Vector2(-45.0, -45.0)), "authoritative dressing proving grid configures")

	# Build a compact playable corridor in the middle. POC-30E dressing must stay
	# out of these cells AND every rough cell directly touching them.
	for y in range(2, 7):
		_assert_true(grid.set_surface(4, y, "FAIRWAY"), "central fairway cell %d paints authoritatively" % y)
	_assert_true(grid.set_surface(4, 7, "TEE"), "tee paints authoritatively")
	for y in range(0, 2):
		for x in range(3, 6):
			_assert_true(grid.set_surface(x, y, "GREEN"), "green cell %d,%d paints authoritatively" % [x, y])
	_assert_true(grid.set_surface(2, 1, "BUNKER"), "bunker paints authoritatively")
	_assert_true(grid.set_surface(6, 3, "WATER"), "water paints authoritatively")

	# Add authored elevation to prove vegetation bases follow grid truth without
	# changing it. Perimeter rough remains mostly zero and visually frames course.
	_assert_true(grid.set_elevation(0, 4, 2.5), "rough dressing cell stores authored elevation")
	_assert_true(grid.set_elevation(8, 4, -1.5), "opposite rough dressing cell stores authored elevation")

	var before_render: Dictionary = grid.to_dictionary()
	var dressing = ConstructionGridCourseDressing.new()
	get_root().add_child(dressing)

	var first_plan: Array = dressing.build_dressing_plan(grid)
	var second_plan: Array = dressing.build_dressing_plan(grid)
	_assert_equal(first_plan, second_plan, "dressing plan is deterministic for identical authoritative grid")
	_assert_true(first_plan.size() > 0, "proving property produces visible course dressing")

	var tree_count: int = 0
	var shrub_count: int = 0
	for record_value in first_plan:
		var record: Dictionary = record_value
		var cell: Vector2i = record.get("cell", Vector2i(-1, -1))
		var kind: String = str(record.get("kind", ""))
		_assert_equal(grid.surface_at(cell.x, cell.y), "ROUGH", "%s dressing only occupies authoritative ROUGH" % kind)
		_assert_true(_cell_has_only_rough_or_property_edge_neighbors(grid, cell), "%s dressing stays one-cell clear of non-rough golf surfaces" % kind)
		_assert_equal(str(record.get("source", "")), "construction_grid_safe_rough", "%s dressing records authoritative derivation source" % kind)
		var expected_y: float = float(grid.tile_at(cell.x, cell.y).get("elevation", 0.0))
		var position: Vector3 = record.get("position", Vector3.ZERO)
		_assert_close(position.y, expected_y, 0.0001, "%s base elevation comes from owner cell" % kind)
		if kind == "TREE":
			tree_count += 1
		elif kind == "SHRUB":
			shrub_count += 1

	_assert_true(tree_count > 0, "safe rough produces deterministic tree framing")
	_assert_true(shrub_count > 0, "safe rough produces deterministic low shrub detail")

	_assert_true(dressing.render_dressing(grid), "course dressing renderer accepts authoritative grid")
	_assert_equal(dressing.dressing_count(), first_plan.size(), "render metadata reconciles deterministic dressing plan")
	_assert_equal(dressing.dressing_count("TREE"), tree_count, "rendered tree count reconciles plan")
	_assert_equal(dressing.dressing_count("SHRUB"), shrub_count, "rendered shrub count reconciles plan")
	_assert_true(dressing.get_node_or_null("CourseWorldEnvironment") != null, "course receives presentation-only world environment")
	_assert_true(dressing.get_node_or_null("CourseSun") != null, "course receives presentation-only directional sunlight")

	var world_environment = dressing.get_node_or_null("CourseWorldEnvironment")
	var sun = dressing.get_node_or_null("CourseSun")
	if world_environment != null:
		_assert_equal(str(world_environment.get_meta("authority", "")), "presentation_only", "world environment declares presentation-only authority")
	if sun != null:
		_assert_equal(str(sun.get_meta("authority", "")), "presentation_only", "sun declares presentation-only authority")

	if tree_count > 0:
		_assert_true(dressing.get_node_or_null("TreeTrunks") != null, "tree trunks render through one grouped MultiMesh")
		_assert_true(dressing.get_node_or_null("TreeCanopies") != null, "tree canopies render through one grouped MultiMesh")
	if shrub_count > 0:
		_assert_true(dressing.get_node_or_null("RoughShrubs") != null, "shrubs render through one grouped MultiMesh")

	_assert_equal(grid.to_dictionary(), before_render, "environment and vegetation dressing never mutate authoritative grid")
	_assert_equal(grid.count_surface("FAIRWAY"), 5, "fairway authority unchanged after dressing")
	_assert_equal(grid.count_surface("GREEN"), 6, "green authority unchanged after dressing")
	_assert_equal(grid.count_surface("TEE"), 1, "tee authority unchanged after dressing")
	_assert_equal(grid.count_surface("BUNKER"), 1, "bunker authority unchanged after dressing")
	_assert_equal(grid.count_surface("WATER"), 1, "water authority unchanged after dressing")

	print("POC30E_DRESSING_SUMMARY total=%d trees=%d shrubs=%d children=%d" % [
		first_plan.size(), tree_count, shrub_count, dressing.get_child_count()
	])

	dressing.queue_free()
	_finish()


func _cell_has_only_rough_or_property_edge_neighbors(grid, cell: Vector2i) -> bool:
	var neighbors: Dictionary = grid.surface_neighbors(cell.x, cell.y)
	for direction_value in ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]:
		var surface: String = str(neighbors.get(str(direction_value), ""))
		if not surface.is_empty() and surface != "ROUGH":
			return false
	return true


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


func _assert_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.4f expected=%.4f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.4f expected=%.4f)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-30E COURSE DRESSING AND ENVIRONMENT PASSED")
		quit(0)
	else:
		push_error("POC-30E COURSE DRESSING AND ENVIRONMENT FAILED: %d" % failures)
		quit(1)

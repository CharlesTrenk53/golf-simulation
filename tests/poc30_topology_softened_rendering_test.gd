extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const ConstructionGridRenderer = preload("res://scenes/construction_grid_renderer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-30B: neighborhood-aware softened construction-grid rendering")

	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(7, 7, 10.0, Vector2.ZERO), "authoritative grid configures")

	# A three-cell fairway corridor proves that same-surface neighbors remain
	# continuous while only the exposed outside edges are softened.
	for y in range(2, 5):
		_assert_true(grid.set_surface(3, y, "FAIRWAY"), "fairway corridor cell %d paints authoritatively" % y)

	# One isolated green cell gives us a fully exposed footprint that should be
	# visibly softened on every outside corner while never escaping its owner cell.
	_assert_true(grid.set_surface(1, 1, "GREEN"), "isolated green cell paints authoritatively")

	var before_render: Dictionary = grid.to_dictionary()
	var renderer = ConstructionGridRenderer.new()
	get_root().add_child(renderer)
	_assert_true(renderer.render_grid(grid), "topology-aware renderer accepts grid")

	var middle: PackedVector2Array = renderer.visual_footprint_for_cell(3, 3)
	_assert_true(middle.size() >= 4, "middle fairway cell receives a valid visual footprint")
	_assert_close(_min_x(middle), 1.2, 0.001, "middle fairway exposed west edge pulls inward")
	_assert_close(_max_x(middle), 8.8, 0.001, "middle fairway exposed east edge pulls inward")
	_assert_close(_min_y(middle), 0.0, 0.001, "middle fairway stays flush with same-surface north neighbor")
	_assert_close(_max_y(middle), 10.0, 0.001, "middle fairway stays flush with same-surface south neighbor")

	var end_cap: PackedVector2Array = renderer.visual_footprint_for_cell(3, 2)
	_assert_true(end_cap.size() > middle.size(), "fairway end cap adds softened outside-corner vertices")
	_assert_close(_min_y(end_cap), 1.2, 0.001, "exposed north end pulls inward")
	_assert_close(_max_y(end_cap), 10.0, 0.001, "same-surface south edge remains continuous")

	var isolated: PackedVector2Array = renderer.visual_footprint_for_cell(1, 1)
	_assert_equal(isolated.size(), 8, "isolated green becomes an eight-point softened footprint")
	_assert_true(_footprint_inside_cell(isolated, 10.0), "softened green remains completely inside authoritative owner cell")
	_assert_close(_min_x(isolated), 1.2, 0.001, "isolated green west boundary stays inside its cell")
	_assert_close(_max_x(isolated), 8.8, 0.001, "isolated green east boundary stays inside its cell")
	_assert_close(_min_y(isolated), 1.2, 0.001, "isolated green north boundary stays inside its cell")
	_assert_close(_max_y(isolated), 8.8, 0.001, "isolated green south boundary stays inside its cell")

	# ROUGH is intentionally a continuous base projection. Organic overlays are
	# allowed to reveal rough beneath softened edges, but never to alter ownership.
	var rough: PackedVector2Array = renderer.visual_footprint_for_cell(0, 0)
	_assert_equal(rough.size(), 4, "rough remains a full-cell base footprint")
	_assert_close(_min_x(rough), 0.0, 0.001, "rough reaches owner-cell west edge")
	_assert_close(_max_x(rough), 10.0, 0.001, "rough reaches owner-cell east edge")

	_assert_equal(renderer.rendered_tile_count("FAIRWAY"), 3, "fairway render metadata still reconciles exact authoritative tile count")
	_assert_equal(renderer.rendered_tile_count("GREEN"), 1, "green render metadata still reconciles exact authoritative tile count")
	_assert_equal(renderer.softened_boundary_cell_count("FAIRWAY"), 3, "all three corridor cells correctly report exposed visual boundaries")
	_assert_equal(renderer.softened_boundary_cell_count("GREEN"), 1, "isolated green reports one softened boundary cell")
	_assert_equal(grid.to_dictionary(), before_render, "visual smoothing does not mutate authoritative grid data")
	_assert_equal(grid.count_surface("FAIRWAY"), 3, "authoritative fairway ownership remains unchanged")
	_assert_equal(grid.count_surface("GREEN"), 1, "authoritative green ownership remains unchanged")

	print("POC30B_SOFTENING_SUMMARY fairway_tiles=%d green_tiles=%d middle_vertices=%d end_vertices=%d isolated_vertices=%d" % [
		grid.count_surface("FAIRWAY"),
		grid.count_surface("GREEN"),
		middle.size(),
		end_cap.size(),
		isolated.size()
	])

	renderer.queue_free()
	_finish()


func _min_x(points: PackedVector2Array) -> float:
	var value: float = INF
	for point: Vector2 in points:
		value = minf(value, point.x)
	return value


func _max_x(points: PackedVector2Array) -> float:
	var value: float = -INF
	for point: Vector2 in points:
		value = maxf(value, point.x)
	return value


func _min_y(points: PackedVector2Array) -> float:
	var value: float = INF
	for point: Vector2 in points:
		value = minf(value, point.y)
	return value


func _max_y(points: PackedVector2Array) -> float:
	var value: float = -INF
	for point: Vector2 in points:
		value = maxf(value, point.y)
	return value


func _footprint_inside_cell(points: PackedVector2Array, size: float) -> bool:
	for point: Vector2 in points:
		if point.x < -0.001 or point.y < -0.001 or point.x > size + 0.001 or point.y > size + 0.001:
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
		print("PASS: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-30B TOPOLOGY-SOFTENED RENDERING PASSED")
		quit(0)
	else:
		push_error("POC-30B TOPOLOGY-SOFTENED RENDERING FAILED: %d" % failures)
		quit(1)

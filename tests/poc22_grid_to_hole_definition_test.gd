extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const GridHoleBuilder = preload("res://simulation/construction_grid_hole_builder.gd")

var failures: int = 0


func _init() -> void:
	print("POC-22C: construction grid to playable hole definition")
	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(10, 12, 5.0, Vector2(-25.0, -10.0)), "construction grid configures")

	# Player-built tee.
	grid.set_surface(4, 10, "TEE")
	grid.set_surface(5, 10, "TEE")

	# Player-built fairway corridor.
	for y in range(3, 10):
		for x in range(4, 6):
			grid.set_surface(x, y, "FAIRWAY")

	# A 2x2 green proves that green size comes from multiple purchased tiles,
	# not a hard-coded green rectangle in the golfer simulation.
	for y in range(1, 3):
		for x in range(4, 6):
			grid.set_surface(x, y, "GREEN")

	# Strategic features placed by the player.
	grid.set_surface(3, 4, "BUNKER")
	grid.set_surface(6, 6, "WATER")
	grid.set_elevation(4, 10, 2.0)
	grid.set_elevation(4, 1, 1.0)

	var builder = GridHoleBuilder.new()
	var hole = builder.build_hole(
		grid,
		"player_course",
		1,
		"First Investment",
		3,
		Vector2i(4, 10),
		Vector2i(4, 1),
		"starter",
		"Starter Tee"
	)

	_assert_true(hole != null, "player-built grid produces a valid HoleDefinition")
	if hole == null:
		_finish()
		return

	_assert_equal(hole.course_id, "player_course", "course identity survives conversion")
	_assert_equal(hole.hole_number, 1, "hole number survives conversion")
	_assert_equal(hole.par, 3, "par survives conversion")
	_assert_vector_close(hole.tee_position("starter"), grid.tile_center_world(4, 10), "tee position comes from purchased tee tile")
	_assert_vector_close(hole.pin_position, grid.tile_center_world(4, 1), "pin position comes from purchased green tile")

	var expected_yardage := Vector2(hole.tee_position("starter").x, hole.tee_position("starter").z).distance_to(Vector2(hole.pin_position.x, hole.pin_position.z))
	_assert_float_close(hole.nominal_yardage, expected_yardage, "yardage is derived from player placement")

	_assert_equal(hole.green_polygon.size(), 4, "adjacent green tiles merge to one outside green outline")
	_assert_float_close(absf(_polygon_area(hole.green_polygon)), 100.0, "four 5x5 green tiles produce 100 square yards of authoritative green")
	_assert_true(_point_in_polygon(Vector2(hole.pin_position.x, hole.pin_position.z), hole.green_polygon), "pin lies inside generated green")

	var fairway_regions: int = 0
	var tee_regions: int = 0
	for region in hole.surface_regions:
		match str(region.get("surface", "")):
			"FAIRWAY": fairway_regions += 1
			"TEE": tee_regions += 1
	_assert_equal(fairway_regions, 14, "every purchased fairway tile enters playable geometry")
	_assert_equal(tee_regions, 2, "every purchased tee tile enters playable geometry")

	var bunker_regions: int = 0
	var water_regions: int = 0
	for hazard in hole.hazards:
		match str(hazard.get("type", "")):
			"BUNKER": bunker_regions += 1
			"WATER": water_regions += 1
	_assert_equal(bunker_regions, 1, "purchased bunker becomes authoritative hazard")
	_assert_equal(water_regions, 1, "purchased water becomes authoritative hazard")
	_assert_equal(hole.elevation_points.size(), grid.width * grid.height, "tile elevations are carried into hole geometry")

	# Invalid construction should not silently become a playable hole.
	var invalid_grid = CourseConstructionGrid.new()
	invalid_grid.configure(4, 4, 5.0)
	invalid_grid.set_surface(1, 3, "TEE")
	_assert_true(builder.build_hole(invalid_grid, "bad", 1, "Missing Green", 3, Vector2i(1, 3), Vector2i(1, 1)) == null, "hole without a player-built green is rejected")

	print("POC22_GRID_HOLE_SUMMARY yardage=%.1f fairway_tiles=%d green_tiles=%d hazards=%d" % [
		hole.nominal_yardage,
		fairway_regions,
		grid.count_surface("GREEN"),
		hole.hazards.size()
	])
	_finish()


func _polygon_area(polygon: PackedVector2Array) -> float:
	var area: float = 0.0
	for i in range(polygon.size()):
		var current: Vector2 = polygon[i]
		var next: Vector2 = polygon[(i + 1) % polygon.size()]
		area += current.x * next.y - next.x * current.y
	return area * 0.5


func _point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon)


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
	if absf(actual - expected) <= 0.001:
		print("PASS: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-22C GRID TO PLAYABLE HOLE DEFINITION PASSED")
		quit(0)
	else:
		push_error("POC-22C GRID TO PLAYABLE HOLE DEFINITION FAILED: %d" % failures)
		quit(1)

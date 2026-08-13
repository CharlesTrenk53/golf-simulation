extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")

var failures: int = 0


func _init() -> void:
	print("POC-22A: course construction grid")
	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(8, 6, 5.0, Vector2(-20.0, 10.0)), "construction grid configures")
	_assert_equal(grid.width, 8, "grid width preserved")
	_assert_equal(grid.height, 6, "grid height preserved")
	_assert_equal(grid.count_surface("ROUGH"), 48, "new owned land begins as rough")

	_assert_true(grid.set_surface(1, 1, "TEE"), "tee tile can be placed")
	_assert_true(grid.set_surface(2, 1, "FAIRWAY"), "fairway tile can be placed")
	_assert_true(grid.set_surface(3, 1, "FAIRWAY"), "second fairway tile can be placed")
	_assert_true(grid.set_surface(4, 1, "BUNKER"), "bunker tile can be placed")
	_assert_true(grid.set_surface(5, 1, "WATER"), "water tile can be placed")
	_assert_true(grid.set_surface(6, 1, "GREEN"), "green tile can be placed")
	_assert_true(grid.set_elevation(6, 1, 3.5), "tile elevation can be authored")

	_assert_equal(grid.surface_at(4, 1), "BUNKER", "placed surface reads back")
	_assert_equal(grid.count_surface("FAIRWAY"), 2, "surface counts are derived from grid")
	_assert_equal(grid.count_surface("GREEN"), 1, "green count is derived from grid")
	_assert_true(not grid.set_surface(-1, 0, "GREEN"), "out-of-bounds construction is rejected")
	_assert_true(not grid.set_surface(0, 0, "CLUBHOUSE"), "unknown surface is rejected")

	var green_center: Vector3 = grid.tile_center_world(6, 1)
	_assert_vector_close(green_center, Vector3(12.5, 3.5, 17.5), "tile maps deterministically into course-space yards")
	_assert_equal(grid.total_placed_build_cost(), 960, "placed tile construction cost is deterministic")

	var saved: Dictionary = grid.to_dictionary()
	var restored = CourseConstructionGrid.from_dictionary(saved)
	_assert_true(restored != null, "construction grid round-trips through save data")
	if restored != null:
		_assert_equal(restored.surface_at(1, 1), "TEE", "restored tee survives serialization")
		_assert_equal(restored.surface_at(5, 1), "WATER", "restored water survives serialization")
		_assert_vector_close(restored.tile_center_world(6, 1), green_center, "restored elevation and world position survive serialization")
		_assert_equal(restored.total_placed_build_cost(), grid.total_placed_build_cost(), "restored construction cost reconciles")

	print("POC22_GRID_SUMMARY tiles=%d rough=%d fairway=%d green=%d cost=%d" % [
		grid.width * grid.height,
		grid.count_surface("ROUGH"),
		grid.count_surface("FAIRWAY"),
		grid.count_surface("GREEN"),
		grid.total_placed_build_cost()
	])
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


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-22A COURSE CONSTRUCTION GRID PASSED")
		quit(0)
	else:
		push_error("POC-22A COURSE CONSTRUCTION GRID FAILED: %d" % failures)
		quit(1)

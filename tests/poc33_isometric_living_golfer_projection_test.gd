extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const IsometricRotatableCourseRenderer = preload("res://scenes/isometric_rotatable_course_renderer.gd")
const IsometricLivingGolferLayer = preload("res://scenes/isometric_living_golfer_layer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-33A: isometric living golfer projection foundation")

	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(6, 6, 10.0, Vector2(-30.0, -30.0)), "projection test construction grid configures")
	grid.set_elevation(2, 2, 3.5)
	grid.set_elevation(3, 3, -1.25)
	grid.set_elevation(0, 0, 1.0)
	var grid_before: Dictionary = grid.to_dictionary()

	var renderer = IsometricRotatableCourseRenderer.new()
	get_root().add_child(renderer)
	_assert_true(renderer.configure(grid), "accepted rotatable isometric renderer configures")

	var layer = IsometricLivingGolferLayer.new()
	get_root().add_child(layer)
	_assert_true(layer.configure(renderer, grid), "living golfer projection layer configures")

	var back_world: Vector3 = grid.tile_center_world(0, 0)
	var hill_world: Vector3 = grid.tile_center_world(2, 2)
	var front_world: Vector3 = grid.tile_center_world(3, 3)
	var records := [
		{
			"golfer_id": "group_a:back",
			"group_id": "group_a",
			"member_index": 0,
			"golfer_name": "Back Golfer",
			"world_position": back_world
		},
		{
			"golfer_id": "group_a:hill",
			"group_id": "group_a",
			"member_index": 1,
			"golfer_name": "Hill Golfer",
			"world_position": hill_world
		},
		{
			"golfer_id": "group_b:front",
			"group_id": "group_b",
			"member_index": 0,
			"golfer_name": "Front Golfer",
			"world_position": front_world
		}
	]
	_assert_true(layer.set_golfers(records), "authoritative golfer position records are accepted")
	_assert_equal(int(layer.snapshot().get("golfer_count", 0)), 3, "all golfer identities survive projection")

	var hill: Dictionary = layer.projected_record("group_a:hill")
	_assert_true(not hill.is_empty(), "projected golfer remains addressable by stable identity")
	_assert_vector2_close(hill.get("grid_position", Vector2.ZERO), Vector2(2.5, 2.5), 0.000001, "course-space golfer position converts to exact construction-grid coordinates")
	_assert_close(float(hill.get("terrain_elevation", 0.0)), 3.5, 0.000001, "golfer projection samples authored terrain elevation")
	_assert_vector2_close(hill.get("iso_position", Vector2.ZERO), renderer.cell_center_iso(2, 2), 0.000001, "golfer stands on exact accepted isometric tile center")

	# Golfer glyphs are grounded to the visible terrain from X/Z. Vertical values in
	# a movement record cannot make the presentation float away from the authored land.
	var airborne_copy: Vector3 = hill_world
	airborne_copy.y += 100.0
	_assert_vector2_close(layer.project_world_position(airborne_copy), layer.project_world_position(hill_world), 0.000001, "golfer projection grounds movement records to visible terrain")

	var ordered: Array = layer.snapshot().get("records", [])
	_assert_equal(str(ordered[0].get("golfer_id", "")), "group_a:back", "back golfer paints first in initial view")
	_assert_equal(str(ordered[-1].get("golfer_id", "")), "group_b:front", "front golfer paints last in initial view")

	var initial_hill_iso: Vector2 = hill.get("iso_position", Vector2.ZERO)
	renderer.rotate_view(1)
	layer.refresh_projection()
	var rotated_hill: Dictionary = layer.projected_record("group_a:hill")
	_assert_true(rotated_hill.get("iso_position", Vector2.ZERO) != initial_hill_iso, "cardinal camera rotation reprojects living golfers")
	_assert_vector2_close(
		rotated_hill.get("iso_position", Vector2.ZERO),
		renderer.grid_to_iso(2.5, 2.5, renderer.terrain_height_at_grid_position(2.5, 2.5)),
		0.000001,
		"golfer projection uses the renderer's rotated terrain basis"
	)
	_assert_equal(str(rotated_hill.get("golfer_name", "")), "Hill Golfer", "golfer identity survives camera rotation")

	_assert_true(grid.to_dictionary() == grid_before, "presentation layer never mutates authoritative construction terrain")
	print("POC33A_PROJECTION_SUMMARY golfers=%d rotation=%d hill_elev=%.2f hill_iso=%s" % [
		int(layer.snapshot().get("golfer_count", 0)),
		int(renderer.rotation_quarters),
		float(rotated_hill.get("terrain_elevation", 0.0)),
		str(rotated_hill.get("iso_position", Vector2.ZERO))
	])

	layer.queue_free()
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


func _assert_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.9f expected=%.9f tolerance=%.9f)" % [label, actual, expected, tolerance])


func _assert_vector2_close(actual: Vector2, expected: Vector2, tolerance: float, label: String) -> void:
	if actual.distance_to(expected) <= tolerance:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-33A ISOMETRIC LIVING GOLFER PROJECTION PASSED")
		quit(0)
	else:
		push_error("POC-33A ISOMETRIC LIVING GOLFER PROJECTION FAILED: %d" % failures)
		quit(1)

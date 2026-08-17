extends SceneTree

const IsometricProofScene = preload("res://scenes/poc30_isometric_visual_spike.tscn")
const IsometricCourseRenderer = preload("res://scenes/isometric_course_renderer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-30H: 64x32 isometric rendering spike over authoritative Contour Creek")

	var proof = IsometricProofScene.instantiate()
	get_root().add_child(proof)
	var initialized_now: bool = bool(proof.initialize_proof())
	_assert_true(initialized_now and bool(proof.initialized), "isometric proof initializes from authoritative construction grid")
	if not initialized_now or not bool(proof.initialized):
		proof.free()
		_finish()
		return

	var grid = proof.grid
	var hole = proof.hole
	var renderer = proof.renderer
	var before: Dictionary = grid.to_dictionary()

	_assert_true(hole != null, "same construction grid builds playable HoleDefinition")
	_assert_close(float(hole.nominal_yardage), 410.0, 0.001, "isometric proof preserves Contour Creek 410-yard routing")
	_assert_equal(int(hole.par), 4, "isometric proof preserves Contour Creek par")
	_assert_true(int(proof.economy.lifetime_construction_spend) > 0, "isometric proof uses real paid construction")

	_assert_equal(int(grid.count_surface("TEE")), 6, "same proof hole retains six tee blocks")
	_assert_equal(int(grid.count_surface("FAIRWAY")), 108, "same proof hole retains 108 fairway blocks")
	_assert_equal(int(grid.count_surface("FRINGE")), 16, "same proof hole retains explicit sixteen-block fringe")
	_assert_equal(int(grid.count_surface("GREEN")), 9, "same proof hole retains nine-block green")
	_assert_equal(int(grid.count_surface("BUNKER")), 4, "same proof hole retains four bunker blocks")
	_assert_equal(int(grid.count_surface("WATER")), 8, "same proof hole retains eight water blocks")

	_assert_true(renderer != null and bool(renderer.configured), "64x32 isometric renderer is configured")
	_assert_close(IsometricCourseRenderer.TILE_WIDTH, 64.0, 0.001, "isometric diamond width is 64 pixels")
	_assert_close(IsometricCourseRenderer.TILE_HEIGHT, 32.0, 0.001, "isometric diamond height is 32 pixels")
	_assert_vector2_close(renderer.grid_to_iso(1.0, 0.0, 0.0) - renderer.grid_to_iso(0.0, 0.0, 0.0), Vector2(32.0, 16.0), "one grid step east projects to 32,16 pixels")
	_assert_vector2_close(renderer.grid_to_iso(0.0, 1.0, 0.0) - renderer.grid_to_iso(0.0, 0.0, 0.0), Vector2(-32.0, 16.0), "one grid step south projects to -32,16 pixels")
	_assert_vector2_close(renderer.grid_to_iso(0.0, 0.0, 1.0) - renderer.grid_to_iso(0.0, 0.0, 0.0), Vector2(0.0, -IsometricCourseRenderer.ELEVATION_PIXELS_PER_YARD), "one yard of elevation projects vertically without changing surface ownership")

	# Four cardinal viewpoints rotate only the presentation basis. The authoritative
	# grid and 64x32 diamond geometry remain unchanged.
	_assert_equal(int(renderer.rotation_quarters), 0, "isometric view starts at canonical orientation")
	var canonical_origin: Vector2 = renderer.grid_to_iso(0.0, 0.0, 0.0)
	var canonical_east_step: Vector2 = renderer.grid_to_iso(1.0, 0.0, 0.0) - canonical_origin
	var canonical_south_step: Vector2 = renderer.grid_to_iso(0.0, 1.0, 0.0) - canonical_origin
	renderer.rotate_view(1)
	_assert_equal(int(renderer.rotation_quarters), 1, "clockwise rotation advances one cardinal viewpoint")
	_assert_vector2_close(renderer.grid_to_iso(1.0, 0.0, 0.0) - renderer.grid_to_iso(0.0, 0.0, 0.0), Vector2(-32.0, 16.0), "rotated east grid step projects down-left")
	_assert_vector2_close(renderer.grid_to_iso(0.0, 1.0, 0.0) - renderer.grid_to_iso(0.0, 0.0, 0.0), Vector2(-32.0, -16.0), "rotated south grid step projects up-left")
	var rotated_west_tile_corners: PackedVector2Array = renderer.tile_corners_iso(6, 20)
	var rotated_east_tile_corners: PackedVector2Array = renderer.tile_corners_iso(7, 20)
	_assert_vector2_close(rotated_west_tile_corners[1], rotated_east_tile_corners[0], "shared terrain corner remains crack-free after camera rotation")
	_assert_vector2_close(rotated_west_tile_corners[2], rotated_east_tile_corners[3], "shared terrain edge remains crack-free after camera rotation")
	_assert_true(renderer.visual_bounds().size.x > 0.0 and renderer.visual_bounds().size.y > 0.0, "rotated viewpoint exposes finite course bounds")
	renderer.rotate_view(3)
	_assert_equal(int(renderer.rotation_quarters), 0, "four quarter turns return to canonical orientation")
	_assert_vector2_close(renderer.grid_to_iso(1.0, 0.0, 0.0) - renderer.grid_to_iso(0.0, 0.0, 0.0), canonical_east_step, "full rotation restores canonical east projection")
	_assert_vector2_close(renderer.grid_to_iso(0.0, 1.0, 0.0) - renderer.grid_to_iso(0.0, 0.0, 0.0), canonical_south_step, "full rotation restores canonical south projection")

	# Elevation presentation reconciles shared corners/edges while preserving exact
	# authored tile-center elevations.
	var corner_x: int = 7
	var corner_y: int = 20
	var expected_corner_elevation: float = 0.0
	var corner_contributors: int = 0
	for tile_y in [corner_y - 1, corner_y]:
		for tile_x in [corner_x - 1, corner_x]:
			if grid.is_in_bounds(tile_x, tile_y):
				expected_corner_elevation += float(grid.tile_at(tile_x, tile_y).get("elevation", 0.0))
				corner_contributors += 1
	expected_corner_elevation /= float(corner_contributors)
	_assert_close(renderer.terrain_corner_elevation(corner_x, corner_y), expected_corner_elevation, 0.0001, "shared terrain corner averages surrounding authoritative elevations")

	var west_tile_corners: PackedVector2Array = renderer.tile_corners_iso(6, 20)
	var east_tile_corners: PackedVector2Array = renderer.tile_corners_iso(7, 20)
	_assert_vector2_close(west_tile_corners[1], east_tile_corners[0], "adjacent tiles share identical projected north corner")
	_assert_vector2_close(west_tile_corners[2], east_tile_corners[3], "adjacent tiles share identical projected south corner")

	var authored_center_elevation: float = float(grid.tile_at(7, 20).get("elevation", 0.0))
	_assert_close(renderer.terrain_height_at_grid_position(7.5, 20.5), authored_center_elevation, 0.0001, "smoothed terrain still passes through exact authored tile center")
	var shared_edge_expected: float = (
		float(grid.tile_at(6, 20).get("elevation", 0.0))
		+ float(grid.tile_at(7, 20).get("elevation", 0.0))
	) * 0.5
	_assert_close(renderer.terrain_height_at_grid_position(7.0, 20.5), shared_edge_expected, 0.0001, "shared tile edge reconciles neighboring authoritative center elevations")

	_assert_equal(renderer.rendered_surface_count("FAIRWAY"), grid.count_surface("FAIRWAY"), "isometric fairway presentation reconciles exact grid ownership")
	_assert_equal(renderer.rendered_surface_count("GREEN"), grid.count_surface("GREEN"), "isometric green presentation reconciles exact grid ownership")
	_assert_equal(renderer.rendered_surface_count("BUNKER"), grid.count_surface("BUNKER"), "isometric bunker presentation reconciles exact grid ownership")
	_assert_equal(renderer.rendered_surface_count("WATER"), grid.count_surface("WATER"), "isometric water presentation reconciles exact grid ownership")
	_assert_true(renderer.visual_bounds().size.x > 0.0 and renderer.visual_bounds().size.y > 0.0, "isometric renderer exposes finite full-course visual bounds")
	_assert_true(proof.dressing_plan.size() > 0, "same deterministic safe-rough dressing feeds isometric world")
	_assert_equal(grid.to_dictionary(), before, "isometric rotation/presentation never mutates authoritative construction data")

	print("POC30H_ISOMETRIC_SUMMARY yardage=%.1f par=%d width=%d height=%d tile=%dx%d fairway=%d green=%d bunker=%d water=%d dressing=%d corner=%.3f rotation=%d bounds=%s" % [
		float(hole.nominal_yardage),
		int(hole.par),
		int(grid.width),
		int(grid.height),
		int(IsometricCourseRenderer.TILE_WIDTH),
		int(IsometricCourseRenderer.TILE_HEIGHT),
		int(grid.count_surface("FAIRWAY")),
		int(grid.count_surface("GREEN")),
		int(grid.count_surface("BUNKER")),
		int(grid.count_surface("WATER")),
		proof.dressing_plan.size(),
		renderer.terrain_corner_elevation(corner_x, corner_y),
		int(renderer.rotation_quarters),
		str(renderer.visual_bounds())
	])

	proof.free()
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
		print("PASS: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])


func _assert_vector2_close(actual: Vector2, expected: Vector2, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-30H ISOMETRIC VISUAL SPIKE PASSED")
		quit(0)
	else:
		push_error("POC-30H ISOMETRIC VISUAL SPIKE FAILED: %d" % failures)
		quit(1)

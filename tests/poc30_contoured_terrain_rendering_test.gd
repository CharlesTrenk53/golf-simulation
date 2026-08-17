extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const ConstructionGridContouredTerrain = preload("res://scenes/construction_grid_contoured_terrain.gd")

var failures: int = 0


func _init() -> void:
	print("POC-30D: center-anchored contoured terrain rendering")

	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(4, 4, 10.0, Vector2(-20.0, -20.0)), "authoritative elevation proving grid configures")
	_assert_true(grid.set_elevation(1, 1, 4.0), "northwest proving cell stores authored elevation")
	_assert_true(grid.set_elevation(2, 1, 8.0), "northeast proving cell stores authored elevation")
	_assert_true(grid.set_elevation(1, 2, 2.0), "southwest proving cell stores authored elevation")
	_assert_true(grid.set_elevation(2, 2, 6.0), "southeast proving cell stores authored elevation")

	var before_render: Dictionary = grid.to_dictionary()
	var terrain = ConstructionGridContouredTerrain.new()
	get_root().add_child(terrain)
	_assert_true(terrain.render_grid(grid), "contoured terrain renderer accepts authoritative grid")
	_assert_true(terrain.terrain_visual != null, "contoured terrain produces a visible mesh")

	# Every tile center is still the exact elevation the player authored. This is
	# the bridge between the existing simulation elevation point and the prettier
	# presentation mesh; smoothing happens between authoritative centers.
	_assert_close(terrain.terrain_height_at_cell_uv(1, 1, 0.5, 0.5), 4.0, 0.0001, "terrain passes exactly through authored cell center")
	_assert_close(terrain.terrain_height_at_cell_uv(2, 1, 0.5, 0.5), 8.0, 0.0001, "neighbor terrain passes exactly through its authored center")
	_assert_close(grid.tile_center_world(1, 1).y, terrain.terrain_height_at_cell_uv(1, 1, 0.5, 0.5), 0.0001, "visual center reconciles with authoritative tile-center elevation")

	# Shared edge midpoints are one deterministic average viewed identically from
	# either owner, eliminating cracks while preserving both authored elevations.
	_assert_close(terrain.terrain_height_at_cell_uv(1, 1, 1.0, 0.5), 6.0, 0.0001, "east edge midpoint averages neighboring authored heights")
	_assert_close(terrain.terrain_height_at_cell_uv(2, 1, 0.0, 0.5), 6.0, 0.0001, "same east/west edge midpoint is identical from neighboring cell")
	_assert_close(terrain.terrain_height_at_cell_uv(1, 1, 0.5, 1.0), 3.0, 0.0001, "south edge midpoint averages neighboring authored heights")
	_assert_close(terrain.terrain_height_at_cell_uv(1, 2, 0.5, 0.0), 3.0, 0.0001, "same north/south edge midpoint is identical from neighboring cell")

	# The four-cell meeting corner is the mean of all four authoritative centers.
	_assert_close(terrain.terrain_height_at_grid_corner(2, 2), 5.0, 0.0001, "four-cell terrain corner averages the four authored elevations")
	_assert_close(terrain.terrain_height_at_cell_uv(1, 1, 1.0, 1.0), 5.0, 0.0001, "northwest cell reaches shared corner continuously")
	_assert_close(terrain.terrain_height_at_cell_uv(2, 1, 0.0, 1.0), 5.0, 0.0001, "northeast cell reaches shared corner continuously")
	_assert_close(terrain.terrain_height_at_cell_uv(1, 2, 1.0, 0.0), 5.0, 0.0001, "southwest cell reaches shared corner continuously")
	_assert_close(terrain.terrain_height_at_cell_uv(2, 2, 0.0, 0.0), 5.0, 0.0001, "southeast cell reaches shared corner continuously")

	# Half-cell tessellation gives the terrain enough geometry to bend through the
	# authoritative center instead of flattening the whole tile between corners.
	_assert_close(terrain.terrain_height_at_cell_uv(1, 1, 0.5, 0.25), 3.0, 0.0001, "interior contour interpolates from shared edge into exact center")
	_assert_equal(terrain.rendered_cells, 16, "all property cells receive contoured base terrain")
	_assert_equal(terrain.rendered_triangles, 16 * ConstructionGridContouredTerrain.TRIANGLES_PER_CELL, "each cell receives deterministic half-cell tessellation")
	_assert_equal(terrain.rendered_vertex_count(), terrain.rendered_triangles * 3, "mesh vertex count reconciles with generated terrain triangles")
	_assert_equal(int(terrain.terrain_visual.get_meta("triangles_per_cell", 0)), 8, "terrain mesh records eight triangles per authoritative cell")
	_assert_equal(str(terrain.terrain_visual.get_meta("source", "")), "construction_grid_elevation", "terrain identifies construction grid as its source")

	_assert_equal(grid.to_dictionary(), before_render, "terrain projection never mutates authoritative elevations or surfaces")
	_assert_equal(grid.count_surface("ROUGH"), 16, "terrain presentation does not alter surface ownership")

	print("POC30D_TERRAIN_SUMMARY cells=%d triangles=%d vertices=%d center=%.2f east_mid=%.2f shared_corner=%.2f" % [
		terrain.rendered_cells,
		terrain.rendered_triangles,
		terrain.rendered_vertex_count(),
		terrain.terrain_height_at_cell_uv(1, 1, 0.5, 0.5),
		terrain.terrain_height_at_cell_uv(1, 1, 1.0, 0.5),
		terrain.terrain_height_at_grid_corner(2, 2)
	])

	terrain.queue_free()
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
		print("PASS: %s (actual=%.4f expected=%.4f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.4f expected=%.4f)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-30D CONTOURED TERRAIN RENDERING PASSED")
		quit(0)
	else:
		push_error("POC-30D CONTOURED TERRAIN RENDERING FAILED: %d" % failures)
		quit(1)

extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const ContinuousSurfaceRenderer = preload("res://scenes/construction_grid_contoured_surface_renderer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-30G: continuous presentation surface over authoritative construction grid")

	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(7, 7, 10.0, Vector2.ZERO), "continuous-surface proving grid configures")

	# A one-cell-wide fairway is intentionally harsh source data. The presentation
	# renderer must make its visible edge continuous without repainting any cell.
	for y in range(1, 6):
		_assert_true(grid.set_surface(3, y, "FAIRWAY"), "fairway corridor cell %d paints authoritatively" % y)
	for y in range(1, 4):
		for x in range(4, 6):
			_assert_true(grid.set_surface(x, y, "GREEN"), "green proving cell %d,%d paints authoritatively" % [x, y])
	_assert_true(grid.set_surface(2, 1, "BUNKER"), "bunker proving cell paints authoritatively")
	_assert_true(grid.set_surface(5, 5, "WATER"), "water proving cell paints authoritatively")

	# Give the property non-flat authoritative landform values so the continuous
	# mesh has to preserve elevation interpolation while smoothing its appearance.
	for y in range(int(grid.height)):
		for x in range(int(grid.width)):
			grid.set_elevation(x, y, 0.6 * sin(float(y) * 0.55) + 0.25 * cos(float(x) * 0.7))

	var before_render: Dictionary = grid.to_dictionary()
	var renderer = ContinuousSurfaceRenderer.new()
	get_root().add_child(renderer)
	_assert_true(renderer.render_grid(grid), "continuous renderer accepts authoritative grid")
	_assert_true(renderer.continuous_surface_active, "continuous presentation path is active")
	_assert_true(renderer.continuous_visual != null, "continuous renderer produces one visible course mesh")
	_assert_equal(renderer.get_child_count(), 1, "renderer uses one continuous visual mesh rather than per-cell/per-surface tiles")
	_assert_true(renderer.get_node_or_null("FairwaySurface") == null, "legacy fairway tile mesh is absent from continuous path")

	var expected_triangles: int = int(grid.width * grid.height * ContinuousSurfaceRenderer.SUBDIVISIONS_PER_CELL * ContinuousSurfaceRenderer.SUBDIVISIONS_PER_CELL * 2)
	_assert_equal(renderer.rendered_triangle_count(), expected_triangles, "dense mesh tessellation covers every authoritative cell")
	_assert_equal(renderer.rendered_vertex_count(), expected_triangles * 3, "dense mesh vertex count reconciles generated triangles")
	_assert_true(ContinuousSurfaceRenderer.SUBDIVISIONS_PER_CELL >= 6, "visual mesh resolves each ten-yard construction cell into sub-yard-scale presentation samples")

	_assert_equal(renderer.rendered_tile_count("FAIRWAY"), grid.count_surface("FAIRWAY"), "fairway metadata still reconciles exact authoritative ownership")
	_assert_equal(renderer.rendered_tile_count("GREEN"), grid.count_surface("GREEN"), "green metadata still reconciles exact authoritative ownership")
	_assert_equal(renderer.rendered_tile_count("BUNKER"), grid.count_surface("BUNKER"), "bunker metadata still reconciles exact authoritative ownership")
	_assert_equal(renderer.rendered_tile_count("WATER"), grid.count_surface("WATER"), "water metadata still reconciles exact authoritative ownership")
	_assert_true(renderer.rendered_transition_edge_count() > 0, "renderer records source-grid boundaries while no longer drawing them as polygons")

	# At the center of the fairway owner cell, fairway should visually dominate.
	var fairway_center_weight: float = renderer.visual_surface_weight_at_cell_uv(3, 3, 0.5, 0.5, "FAIRWAY")
	var rough_center_weight: float = renderer.visual_surface_weight_at_cell_uv(3, 3, 0.5, 0.5, "ROUGH")
	_assert_true(fairway_center_weight > 0.70, "fairway remains clearly readable at its authoritative center")
	_assert_true(fairway_center_weight > rough_center_weight, "fairway center visually dominates rough influence")

	# The exact west owner-cell boundary is no longer a hard color wall. Both
	# authoritative neighbors contribute to the same continuous visual sample.
	var boundary_fairway_weight: float = renderer.visual_surface_weight_at_cell_uv(3, 3, 0.0, 0.5, "FAIRWAY")
	var boundary_rough_weight: float = renderer.visual_surface_weight_at_cell_uv(3, 3, 0.0, 0.5, "ROUGH")
	_assert_true(boundary_fairway_weight > 0.15, "fairway influence reaches the visible boundary smoothly")
	_assert_true(boundary_rough_weight > 0.15, "rough influence reaches the same visible boundary smoothly")
	_assert_true(absf(boundary_fairway_weight - boundary_rough_weight) < 0.70, "boundary sample is a blend rather than a hard tile classification")

	var boundary_color: Color = renderer.visual_color_at_cell_uv(3, 3, 0.0, 0.5)
	var fairway_color: Color = renderer.visual_color_at_cell_uv(3, 3, 0.5, 0.5)
	_assert_true(boundary_color != fairway_color, "continuous edge produces a visual gradient inside one dense mesh")

	var arrays: Array = renderer.continuous_visual.mesh.surface_get_arrays(0)
	var mesh_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_assert_equal(mesh_colors.size(), renderer.rendered_vertex_count(), "every dense visual vertex carries blended course-surface color")
	var material = renderer.continuous_visual.mesh.surface_get_material(0)
	_assert_true(material is StandardMaterial3D and material.vertex_color_use_as_albedo, "continuous material renders vertex-blended course colors")

	_assert_equal(grid.to_dictionary(), before_render, "continuous presentation never mutates authoritative construction data")
	_assert_equal(grid.count_surface("FAIRWAY"), 5, "fairway authority remains exact after visual smoothing")
	_assert_equal(grid.count_surface("GREEN"), 6, "green authority remains exact after visual smoothing")
	_assert_equal(grid.count_surface("BUNKER"), 1, "bunker authority remains exact after visual smoothing")
	_assert_equal(grid.count_surface("WATER"), 1, "water authority remains exact after visual smoothing")

	print("POC30G_CONTINUOUS_SURFACE_SUMMARY triangles=%d vertices=%d fairway_center=%.3f boundary_fairway=%.3f boundary_rough=%.3f transitions=%d" % [
		renderer.rendered_triangle_count(),
		renderer.rendered_vertex_count(),
		fairway_center_weight,
		boundary_fairway_weight,
		boundary_rough_weight,
		renderer.rendered_transition_edge_count()
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


func _finish() -> void:
	if failures == 0:
		print("POC-30G CONTINUOUS SURFACE PROJECTION PASSED")
		quit(0)
	else:
		push_error("POC-30G CONTINUOUS SURFACE PROJECTION FAILED: %d" % failures)
		quit(1)

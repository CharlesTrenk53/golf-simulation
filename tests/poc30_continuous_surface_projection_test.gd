extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const ContinuousSurfaceRenderer = preload("res://scenes/construction_grid_contoured_surface_renderer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-30G: dense terrain with crisp authoritative surface boundaries")

	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(7, 7, 10.0, Vector2.ZERO), "continuous-surface proving grid configures")

	# A one-cell-wide fairway is intentionally harsh source data. POC-30G now
	# preserves that exact block ownership visually while using dense geometry for
	# smoother terrain, lighting, mowing patterns, and material detail.
	for y in range(1, 6):
		_assert_true(grid.set_surface(3, y, "FAIRWAY"), "fairway corridor cell %d paints authoritatively" % y)
	for y in range(1, 4):
		for x in range(4, 6):
			_assert_true(grid.set_surface(x, y, "GREEN"), "green proving cell %d,%d paints authoritatively" % [x, y])
	_assert_true(grid.set_surface(2, 1, "BUNKER"), "bunker proving cell paints authoritatively")
	_assert_true(grid.set_surface(5, 5, "WATER"), "water proving cell paints authoritatively")

	for y in range(int(grid.height)):
		for x in range(int(grid.width)):
			grid.set_elevation(x, y, 0.6 * sin(float(y) * 0.55) + 0.25 * cos(float(x) * 0.7))

	var before_render: Dictionary = grid.to_dictionary()
	var renderer = ContinuousSurfaceRenderer.new()
	get_root().add_child(renderer)
	_assert_true(renderer.render_grid(grid), "dense renderer accepts authoritative grid")
	_assert_true(renderer.continuous_surface_active, "dense continuous terrain path is active")
	_assert_true(renderer.continuous_visual != null, "renderer produces one visible course mesh")
	_assert_equal(renderer.get_child_count(), 1, "renderer uses one dense visual mesh rather than per-surface tile nodes")
	_assert_true(renderer.get_node_or_null("FairwaySurface") == null, "legacy fairway tile mesh is absent from dense path")
	_assert_equal(str(renderer.continuous_visual.get_meta("visual_projection", "")), "dense_crisp_authoritative_blocks", "visual metadata declares crisp authoritative block projection")

	var expected_triangles: int = int(grid.width * grid.height * ContinuousSurfaceRenderer.SUBDIVISIONS_PER_CELL * ContinuousSurfaceRenderer.SUBDIVISIONS_PER_CELL * 2)
	_assert_equal(renderer.rendered_triangle_count(), expected_triangles, "dense mesh tessellation covers every authoritative cell")
	_assert_equal(renderer.rendered_vertex_count(), expected_triangles * 3, "dense mesh vertex count reconciles generated triangles")
	_assert_true(ContinuousSurfaceRenderer.SUBDIVISIONS_PER_CELL >= 6, "each ten-yard construction block receives dense presentation geometry")

	_assert_equal(renderer.rendered_tile_count("FAIRWAY"), grid.count_surface("FAIRWAY"), "fairway metadata reconciles exact authoritative ownership")
	_assert_equal(renderer.rendered_tile_count("GREEN"), grid.count_surface("GREEN"), "green metadata reconciles exact authoritative ownership")
	_assert_equal(renderer.rendered_tile_count("BUNKER"), grid.count_surface("BUNKER"), "bunker metadata reconciles exact authoritative ownership")
	_assert_equal(renderer.rendered_tile_count("WATER"), grid.count_surface("WATER"), "water metadata reconciles exact authoritative ownership")
	_assert_true(renderer.rendered_transition_edge_count() > 0, "renderer records exact source-grid surface boundaries")

	# Surface presentation is now one-hot all the way to the owner-cell edge.
	var fairway_center_weight: float = renderer.visual_surface_weight_at_cell_uv(3, 3, 0.5, 0.5, "FAIRWAY")
	var fairway_edge_weight: float = renderer.visual_surface_weight_at_cell_uv(3, 3, 0.0, 0.5, "FAIRWAY")
	var rough_on_fairway_edge: float = renderer.visual_surface_weight_at_cell_uv(3, 3, 0.0, 0.5, "ROUGH")
	_assert_equal(fairway_center_weight, 1.0, "fairway center is visually pure fairway")
	_assert_equal(fairway_edge_weight, 1.0, "fairway remains visually pure through its owner-cell edge")
	_assert_equal(rough_on_fairway_edge, 0.0, "rough does not bleed into fairway owner cell")

	# The neighboring ROUGH cell owns the other side of the exact same geometric
	# boundary. Its duplicated boundary vertex receives ROUGH color, creating the
	# requested hard cut with no blended transition band.
	var rough_edge_weight: float = renderer.visual_surface_weight_at_cell_uv(2, 3, 1.0, 0.5, "ROUGH")
	var fairway_on_rough_edge: float = renderer.visual_surface_weight_at_cell_uv(2, 3, 1.0, 0.5, "FAIRWAY")
	_assert_equal(rough_edge_weight, 1.0, "neighbor rough remains visually pure through its owner-cell edge")
	_assert_equal(fairway_on_rough_edge, 0.0, "fairway does not bleed into neighboring rough owner cell")

	var fairway_boundary_color: Color = renderer.visual_color_at_cell_uv(3, 3, 0.0, 0.5)
	var rough_boundary_color: Color = renderer.visual_color_at_cell_uv(2, 3, 1.0, 0.5)
	_assert_true(fairway_boundary_color != rough_boundary_color, "different surfaces have a defined color cut at the exact shared boundary")

	# Same-surface neighboring blocks still meet seamlessly because their material
	# treatment is evaluated at the same world coordinate.
	var fairway_north_color: Color = renderer.visual_color_at_cell_uv(3, 3, 0.5, 0.0)
	var fairway_south_color: Color = renderer.visual_color_at_cell_uv(3, 2, 0.5, 1.0)
	_assert_equal(fairway_north_color, fairway_south_color, "same-surface neighboring blocks remain visually continuous")

	var arrays: Array = renderer.continuous_visual.mesh.surface_get_arrays(0)
	var mesh_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_assert_equal(mesh_colors.size(), renderer.rendered_vertex_count(), "every dense vertex carries owner-surface presentation color")
	var material = renderer.continuous_visual.mesh.surface_get_material(0)
	_assert_true(material is StandardMaterial3D and material.vertex_color_use_as_albedo, "dense material renders authoritative per-vertex course colors")

	_assert_equal(grid.to_dictionary(), before_render, "dense presentation never mutates authoritative construction data")
	_assert_equal(grid.count_surface("FAIRWAY"), 5, "fairway authority remains exact after rendering")
	_assert_equal(grid.count_surface("GREEN"), 6, "green authority remains exact after rendering")
	_assert_equal(grid.count_surface("BUNKER"), 1, "bunker authority remains exact after rendering")
	_assert_equal(grid.count_surface("WATER"), 1, "water authority remains exact after rendering")

	print("POC30G_CRISP_SURFACE_SUMMARY triangles=%d vertices=%d fairway_center=%.1f fairway_edge=%.1f rough_edge=%.1f transitions=%d" % [
		renderer.rendered_triangle_count(),
		renderer.rendered_vertex_count(),
		fairway_center_weight,
		fairway_edge_weight,
		rough_edge_weight,
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
		print("POC-30G CRISP SURFACE PROJECTION PASSED")
		quit(0)
	else:
		push_error("POC-30G CRISP SURFACE PROJECTION FAILED: %d" % failures)
		quit(1)

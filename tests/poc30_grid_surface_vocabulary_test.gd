extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const CourseConstructionEconomy = preload("res://simulation/course_construction_economy.gd")
const ConstructionGridHoleBuilder = preload("res://simulation/construction_grid_hole_builder.gd")
const ConstructionGridRenderer = preload("res://scenes/construction_grid_renderer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-30A: authoritative grid surface vocabulary and rendering contract")

	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(7, 12, 10.0, Vector2(-35.0, -20.0)), "construction grid configures with existing POC-22 API")
	_assert_equal(grid.count_surface("ROUGH"), 84, "new property still defaults entirely to rough")

	for required_surface in ["TEE", "FAIRWAY", "ROUGH", "GREEN", "FRINGE", "BUNKER", "WATER"]:
		_assert_true(CourseConstructionGrid.SURFACE_TYPES.has(required_surface), "authoritative vocabulary contains %s" % required_surface)

	# Build one simple hole directly into the authoritative grid. The green collar
	# is deliberately painted FRINGE: presentation is not allowed to invent it.
	_assert_true(grid.set_surface(3, 10, "TEE"), "tee can be painted on the authoritative grid")
	for y in range(4, 10):
		_assert_true(grid.set_surface(3, y, "FAIRWAY"), "fairway cell %d can be painted" % y)
	for y in range(0, 5):
		for x in range(1, 6):
			grid.set_surface(x, y, "FRINGE")
	for y in range(1, 4):
		for x in range(2, 5):
			grid.set_surface(x, y, "GREEN")
	_assert_true(grid.set_surface(1, 6, "BUNKER"), "bunker can be painted on the authoritative grid")
	_assert_true(grid.set_surface(5, 7, "WATER"), "water can be painted on the authoritative grid")

	_assert_equal(grid.count_surface("FRINGE"), 16, "green collar is stored as sixteen real fringe cells")
	_assert_equal(grid.count_surface("GREEN"), 9, "green remains a separate nine-cell surface")
	_assert_equal(grid.surface_at(3, 0), "FRINGE", "fringe ownership comes from the grid")
	_assert_equal(grid.surface_at(3, 2), "GREEN", "green ownership comes from the grid")

	var top_green_neighbors: Dictionary = grid.surface_neighbors(3, 1)
	_assert_equal(str(top_green_neighbors.get("N", "")), "FRINGE", "north neighbor exposes authoritative fringe boundary")
	_assert_equal(str(top_green_neighbors.get("E", "")), "GREEN", "east neighbor exposes continuous green")
	var same_neighbors: Dictionary = grid.same_surface_neighbors(3, 1)
	_assert_true(not bool(same_neighbors.get("N", true)), "surface topology marks green-to-fringe edge as a boundary")
	_assert_true(bool(same_neighbors.get("E", false)), "surface topology marks adjoining green cells as continuous")
	_assert_equal(str(grid.surface_neighbors(0, 0).get("N", "sentinel")), "", "property edge is explicit rather than silently treated as rough")

	# Save/load must preserve exact player surface choices and the neighborhood
	# contract because future smoothing will be reconstructed from this data.
	var saved: Dictionary = grid.to_dictionary()
	var restored = CourseConstructionGrid.from_dictionary(saved)
	_assert_true(restored != null, "typed construction grid round-trips through existing save contract")
	if restored != null:
		_assert_equal(restored.count_surface("FRINGE"), 16, "save/load preserves fringe cells exactly")
		_assert_equal(restored.surface_at(3, 0), "FRINGE", "save/load preserves fringe classification")
		_assert_equal(str(restored.surface_neighbors(3, 1).get("N", "")), "FRINGE", "save/load reconstructs the same visual topology")

	# Existing construction economy automatically accepts the expanded vocabulary;
	# this verifies FRINGE is a real build choice rather than presentation metadata.
	var economy = CourseConstructionEconomy.new()
	_assert_true(economy.configure(grid, 1000), "existing construction economy accepts expanded grid")
	var fringe_quote: Dictionary = economy.quote_surface_change(0, 11, "FRINGE")
	_assert_true(bool(fringe_quote.get("valid", false)), "construction economy recognizes fringe as a buildable surface")
	_assert_equal(int(fringe_quote.get("cost", -1)), int(CourseConstructionGrid.SURFACE_BUILD_COST["FRINGE"]), "fringe quote comes from authoritative surface cost table")

	# POC-30 begins visually without changing truth: the renderer must project the
	# exact typed cell counts and must not mutate the grid while doing so.
	var before_render: Dictionary = grid.to_dictionary()
	var renderer = ConstructionGridRenderer.new()
	get_root().add_child(renderer)
	_assert_true(renderer.render_grid(grid), "construction renderer accepts authoritative POC-30 surface grid")
	for rendered_surface in ["TEE", "FAIRWAY", "GREEN", "FRINGE", "BUNKER", "WATER"]:
		_assert_equal(renderer.rendered_tile_count(rendered_surface), grid.count_surface(rendered_surface), "rendered %s count reconciles exactly with grid" % rendered_surface)
	_assert_true(renderer.surface_visual("FRINGE") != null, "fringe receives its own visible course surface")
	_assert_equal(grid.to_dictionary(), before_render, "rendering remains downstream and does not mutate authoritative construction data")

	# The playable hole projection carries FRINGE forward as a surface region. It
	# is not synthesized from the green mesh and does not disappear at simulation.
	var builder = ConstructionGridHoleBuilder.new()
	var hole = builder.build_hole(grid, "poc30_grid_course", 1, "Surface Truth", 4, Vector2i(3, 10), Vector2i(3, 2), "default", "Back Tee")
	_assert_true(hole != null, "expanded construction grid still builds a playable HoleDefinition")
	if hole != null:
		_assert_equal(_count_surface_regions(hole.surface_regions, "FRINGE"), 16, "all authoritative fringe cells propagate into HoleDefinition")
		_assert_equal(_count_surface_regions(hole.surface_regions, "FAIRWAY"), 6, "existing fairway projection remains intact")

	print("POC30A_SURFACE_SUMMARY rough=%d fairway=%d tee=%d green=%d fringe=%d bunker=%d water=%d" % [
		grid.count_surface("ROUGH"),
		grid.count_surface("FAIRWAY"),
		grid.count_surface("TEE"),
		grid.count_surface("GREEN"),
		grid.count_surface("FRINGE"),
		grid.count_surface("BUNKER"),
		grid.count_surface("WATER")
	])

	renderer.queue_free()
	_finish()


func _count_surface_regions(regions: Array, surface: String) -> int:
	var count: int = 0
	for region_value in regions:
		if typeof(region_value) == TYPE_DICTIONARY and str(region_value.get("surface", "")) == surface:
			count += 1
	return count


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
		print("POC-30A GRID SURFACE VOCABULARY PASSED")
		quit(0)
	else:
		push_error("POC-30A GRID SURFACE VOCABULARY FAILED: %d" % failures)
		quit(1)

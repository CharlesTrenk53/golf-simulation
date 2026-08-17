extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const ConstructionGridRenderer = preload("res://scenes/construction_grid_renderer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-30C: authoritative surface transition rendering")

	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(8, 8, 10.0, Vector2.ZERO), "authoritative transition proving grid configures")

	# Isolated fairway proves the ordinary turf-to-rough shoulder.
	_assert_true(grid.set_surface(4, 4, "FAIRWAY"), "isolated fairway paints authoritatively")

	# Adjacent GREEN / FRINGE proves that both half-strips meet at the same exact
	# authoritative boundary without either visual crossing into the other cell.
	_assert_true(grid.set_surface(1, 1, "GREEN"), "green transition cell paints authoritatively")
	_assert_true(grid.set_surface(1, 2, "FRINGE"), "fringe transition cell paints authoritatively")

	# Isolated hazards prove that visual banks descend toward the depressed core.
	_assert_true(grid.set_surface(6, 1, "BUNKER"), "bunker transition cell paints authoritatively")
	_assert_true(grid.set_surface(6, 6, "WATER"), "water transition cell paints authoritatively")

	var before_render: Dictionary = grid.to_dictionary()
	var renderer = ConstructionGridRenderer.new()
	get_root().add_child(renderer)
	_assert_true(renderer.render_grid(grid), "POC-30C renderer accepts authoritative proving grid")

	_assert_equal(renderer.transition_edge_count("FAIRWAY", "ROUGH"), 4, "isolated fairway creates four turf-to-rough transition edges")
	_assert_equal(renderer.transition_edge_count("GREEN", "FRINGE"), 2, "green/fringe shared boundary renders one half inside each owner cell")
	_assert_equal(renderer.transition_edge_count("GREEN", "ROUGH"), 3, "green's other three sides transition only to rough")
	_assert_equal(renderer.transition_edge_count("FRINGE", "ROUGH"), 3, "fringe's other three sides transition only to rough")
	_assert_equal(renderer.transition_edge_count("BUNKER", "ROUGH"), 4, "isolated bunker creates four authoritative bank edges")
	_assert_equal(renderer.transition_edge_count("WATER", "ROUGH"), 4, "isolated water creates four authoritative bank edges")
	_assert_equal(renderer.rendered_transition_edge_count(), 20, "renderer exposes exactly the expected transition half-edges")

	_assert_true(renderer.transition_visual("FAIRWAY", "ROUGH") != null, "fairway-to-rough transition receives visible geometry")
	_assert_true(renderer.transition_visual("GREEN", "FRINGE") != null, "green-to-fringe transition receives visible geometry")
	_assert_true(renderer.transition_visual("FRINGE", "GREEN") != null, "fringe-to-green companion half receives visible geometry")
	_assert_true(renderer.transition_visual("BUNKER", "ROUGH") != null, "bunker bank receives visible geometry")
	_assert_true(renderer.transition_visual("WATER", "ROUGH") != null, "water bank receives visible geometry")
	_assert_true(renderer.transition_visual("ROUGH", "FAIRWAY") == null, "rough remains the base and does not manufacture a second transition half")

	var fairway_east: Dictionary = renderer.transition_strip_for_edge(4, 4, "E")
	_assert_true(bool(fairway_east.get("valid", false)), "fairway exposed edge produces transition strip contract")
	_assert_equal(fairway_east.get("from_surface", ""), "FAIRWAY", "fairway strip preserves authoritative owner")
	_assert_equal(fairway_east.get("to_surface", ""), "ROUGH", "fairway strip derives neighbor from authoritative topology")
	_assert_vector2_close(fairway_east.get("outer_a", Vector2.ZERO), Vector2(10.0, 0.0), "fairway transition starts on exact owner-cell boundary")
	_assert_vector2_close(fairway_east.get("inner_a", Vector2.ZERO), Vector2(8.8, 0.0), "fairway transition ends at softened core inset")
	_assert_true(float(fairway_east.get("outer_offset_y", 0.0)) < float(fairway_east.get("inner_offset_y", 0.0)), "fairway shoulder rises subtly toward fairway core")

	var green_south: Dictionary = renderer.transition_strip_for_edge(1, 1, "S")
	var fringe_north: Dictionary = renderer.transition_strip_for_edge(1, 2, "N")
	_assert_true(bool(green_south.get("valid", false)) and bool(fringe_north.get("valid", false)), "both sides of green/fringe boundary expose visual half-strips")
	_assert_close(float(green_south.get("outer_offset_y", -1.0)), float(fringe_north.get("outer_offset_y", -2.0)), 0.000001, "green and fringe meet at identical visual boundary height")
	_assert_equal(green_south.get("to_surface", ""), "FRINGE", "green transition knows fringe is authoritative neighbor")
	_assert_equal(fringe_north.get("to_surface", ""), "GREEN", "fringe transition knows green is authoritative neighbor")

	var bunker_east: Dictionary = renderer.transition_strip_for_edge(6, 1, "E")
	_assert_true(bool(bunker_east.get("valid", false)), "bunker edge exposes bank contract")
	_assert_true(float(bunker_east.get("inner_offset_y", 0.0)) < float(bunker_east.get("outer_offset_y", 0.0)), "bunker bank descends from surrounding terrain into sand core")

	var water_east: Dictionary = renderer.transition_strip_for_edge(6, 6, "E")
	_assert_true(bool(water_east.get("valid", false)), "water edge exposes bank contract")
	_assert_true(float(water_east.get("inner_offset_y", 0.0)) < float(water_east.get("outer_offset_y", 0.0)), "water bank descends from surrounding terrain into water core")
	_assert_true(float(water_east.get("inner_offset_y", 0.0)) < float(bunker_east.get("inner_offset_y", 0.0)), "water core is visually lower than bunker core")

	_assert_equal(renderer.transition_strip_for_edge(4, 4, "Q").get("reason", ""), "INVALID_DIRECTION", "transition contract rejects non-cardinal directions")
	_assert_equal(renderer.transition_strip_for_edge(0, 0, "N").get("reason", ""), "ROUGH_IS_BASE", "rough cells remain base terrain rather than owning overlay transitions")
	_assert_equal(grid.to_dictionary(), before_render, "transition rendering never mutates authoritative grid ownership")
	_assert_equal(grid.count_surface("FAIRWAY"), 1, "fairway authority remains one cell after transition rendering")
	_assert_equal(grid.count_surface("GREEN"), 1, "green authority remains one cell after transition rendering")
	_assert_equal(grid.count_surface("FRINGE"), 1, "fringe authority remains one cell after transition rendering")
	_assert_equal(grid.count_surface("BUNKER"), 1, "bunker authority remains one cell after transition rendering")
	_assert_equal(grid.count_surface("WATER"), 1, "water authority remains one cell after transition rendering")

	print("POC30C_TRANSITION_SUMMARY total_edges=%d fairway_rough=%d green_fringe=%d bunker_rough=%d water_rough=%d" % [
		renderer.rendered_transition_edge_count(),
		renderer.transition_edge_count("FAIRWAY", "ROUGH"),
		renderer.transition_edge_count("GREEN", "FRINGE"),
		renderer.transition_edge_count("BUNKER", "ROUGH"),
		renderer.transition_edge_count("WATER", "ROUGH")
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


func _assert_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])


func _assert_vector2_close(actual: Vector2, expected: Vector2, label: String) -> void:
	if actual.distance_to(expected) <= 0.0001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-30C SURFACE TRANSITION RENDERING PASSED")
		quit(0)
	else:
		push_error("POC-30C SURFACE TRANSITION RENDERING FAILED: %d" % failures)
		quit(1)

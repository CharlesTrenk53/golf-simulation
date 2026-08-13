extends SceneTree

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const CourseConstructionEconomy = preload("res://simulation/course_construction_economy.gd")
const ConstructionGridHoleBuilder = preload("res://simulation/construction_grid_hole_builder.gd")
const ConstructionGridRenderer = preload("res://scenes/construction_grid_renderer.gd")
const PlayableHoleRuntime = preload("res://scenes/playable_hole_runtime.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-22E: player-built course build-and-play proof")

	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(15, 48, 10.0, Vector2(-75.0, -15.0)), "starter property construction grid configures")
	if grid.width <= 0:
		_finish()
		return

	var economy = CourseConstructionEconomy.new()
	_assert_true(economy.configure(grid, 20000), "starter course construction budget configures")
	_assert_true(_build_player_hole(economy), "hole can be built entirely through paid construction actions")
	_assert_true(economy.cash_balance > 0, "player remains solvent after constructing starter hole")
	_assert_true(economy.lifetime_construction_spend > 0, "starter hole has a real construction cost")

	var builder = ConstructionGridHoleBuilder.new()
	var hole = builder.build_hole(
		grid,
		"poc22_player_built_course",
		1,
		"First Investment",
		4,
		Vector2i(7, 44),
		Vector2i(7, 3),
		"starter",
		"Starter Tee"
	)
	_assert_true(hole != null, "paid construction converts into a valid playable HoleDefinition")
	if hole == null:
		_finish()
		return
	_assert_close(hole.nominal_yardage, 410.0, 0.001, "player placement produces a realistic 410-yard par four")
	_assert_equal(hole.par, 4, "player-built hole preserves authored par")
	_assert_equal(grid.count_surface("GREEN"), 9, "player chose a nine-tile green footprint")
	_assert_equal(grid.count_surface("BUNKER"), 3, "player-built bunker footprint survives construction")
	_assert_equal(grid.count_surface("WATER"), 6, "player-built water feature survives construction")

	var grid_renderer = ConstructionGridRenderer.new()
	get_root().add_child(grid_renderer)
	_assert_true(grid_renderer.render_grid(grid), "same construction grid renders into visible course terrain")
	_assert_equal(grid_renderer.rendered_tile_count("FAIRWAY"), grid.count_surface("FAIRWAY"), "visible fairway exactly reconciles with purchased fairway tiles")
	_assert_equal(grid_renderer.rendered_tile_count("GREEN"), grid.count_surface("GREEN"), "visible green exactly reconciles with purchased green tiles")
	_assert_equal(grid_renderer.rendered_tile_count("BUNKER"), grid.count_surface("BUNKER"), "visible bunker exactly reconciles with purchased bunker tiles")
	_assert_equal(grid_renderer.rendered_tile_count("WATER"), grid.count_surface("WATER"), "visible water exactly reconciles with purchased water tiles")

	var golfer = Golfer.new()
	golfer.profile = Golfer.GolferProfile.WILD_BILL
	golfer.apply_profile()
	get_root().add_child(golfer)

	var runtime = PlayableHoleRuntime.new()
	get_root().add_child(runtime)
	_assert_true(runtime.configure(hole, golfer, "starter", 22022), "existing autonomous runtime accepts the player-built hole")
	var summary: Dictionary = runtime.play_to_completion(false)
	_assert_true(bool(summary.get("finished", false)), "Wild Bill completes the player-built hole")
	_assert_true(int(summary.get("strokes", 0)) > 0, "player-built hole produces a real score")
	_assert_equal(int(summary.get("par", 0)), 4, "played result preserves player-authored par")
	_assert_equal(int(summary.get("shots_presented", 0)), runtime.presented_history.size(), "every autonomous shot on the player-built hole is presented")
	_assert_equal(runtime.presented_history.size(), runtime.playable.autonomous.shot_history.size(), "visible history reconciles with authoritative simulation history")
	_assert_vector_close(summary.get("visual_ball_position", Vector3.ZERO), runtime.state.ball_position, "visible ball finishes at authoritative final lie")
	_assert_vector_close(summary.get("visual_golfer_position", Vector3.ZERO), runtime.state.ball_position, "visible golfer finishes at authoritative final lie")

	print("POC22_BUILD_PLAY_SUMMARY golfer=%s yardage=%.1f par=%d strokes=%d build_cost=%d cash_remaining=%d fairway=%d green=%d bunker=%d water=%d" % [
		golfer.golfer_name,
		hole.nominal_yardage,
		hole.par,
		int(summary.get("strokes", 0)),
		economy.lifetime_construction_spend,
		economy.cash_balance,
		grid.count_surface("FAIRWAY"),
		grid.count_surface("GREEN"),
		grid.count_surface("BUNKER"),
		grid.count_surface("WATER")
	])

	runtime.queue_free()
	golfer.queue_free()
	grid_renderer.queue_free()
	_finish()


func _build_player_hole(economy) -> bool:
	# Tee box: four purchased tiles near the rear of the owned property.
	for y in range(44, 46):
		for x in range(6, 8):
			if not _purchase(economy, x, y, "TEE"):
				return false

	# Fairway: a modest three-tile-wide corridor. The deliberate slight bend
	# demonstrates that the course is constructed from player choices rather than
	# being a pre-authored rectangle.
	for y in range(8, 44):
		var center_x: int = 7
		if y >= 22 and y < 34:
			center_x = 8
		for x in range(center_x - 1, center_x + 2):
			if not _purchase(economy, x, y, "FAIRWAY"):
				return false

	# Nine-tile green with the pin in the center tile.
	for y in range(2, 5):
		for x in range(6, 9):
			if not _purchase(economy, x, y, "GREEN"):
				return false

	# A greenside bunker and a water feature beside the landing corridor.
	for cell in [Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 6)]:
		if not _purchase(economy, cell.x, cell.y, "BUNKER"):
			return false
	for cell in [Vector2i(10, 25), Vector2i(11, 25), Vector2i(10, 26), Vector2i(11, 26), Vector2i(10, 27), Vector2i(11, 27)]:
		if not _purchase(economy, cell.x, cell.y, "WATER"):
			return false

	return true


func _purchase(economy, x: int, y: int, surface: String) -> bool:
	var result: Dictionary = economy.construct_surface(x, y, surface)
	return bool(result.get("success", false))


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


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-22E PLAYER-BUILT COURSE BUILD-AND-PLAY PROOF PASSED")
		quit(0)
	else:
		push_error("POC-22E PLAYER-BUILT COURSE BUILD-AND-PLAY PROOF FAILED: %d" % failures)
		quit(1)

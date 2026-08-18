extends SceneTree

const ElevationScene = preload("res://scenes/poc32_isometric_elevation.tscn")

var failures := 0


func _init() -> void:
	print("POC-32A/B/C: player-facing isometric elevation")
	var scene = ElevationScene.instantiate()
	get_root().add_child(scene)
	var initialized_now: bool = bool(scene.initialize_property())
	_assert_true(initialized_now and bool(scene.initialized), "elevation construction scene initializes")
	if not initialized_now or not bool(scene.initialized):
		scene.free()
		_finish()
		return

	var grid = scene.grid
	var economy = scene.economy
	var renderer = scene.renderer
	var target := Vector2i(12, 12)
	_assert_true(scene.select_cell(target), "terrain target can be selected")

	var center_before: float = _elevation_at(grid, target)
	var north_before: float = _elevation_at(grid, target + Vector2i(0, -1))
	var diagonal_before: float = _elevation_at(grid, target + Vector2i(1, 1))
	var far_before: float = _elevation_at(grid, target + Vector2i(2, 0))
	var surface_before: String = grid.surface_at(target.x, target.y)
	var cash_before: int = int(economy.cash_balance)
	var iso_before: Vector2 = renderer.cell_center_iso(target.x, target.y)

	var quote: Dictionary = scene.quote_terrain_sculpt(target, 1)
	_assert_true(bool(quote.get("valid", false)), "raise terrain quote is valid")
	_assert_equal(int(quote.get("changes", []).size()), 9, "accepted normal terrain brush remains nine authoritative cells")
	_assert_equal(int(quote.get("cost", -1)), 120, "accepted normal 3x3 terrain brush keeps deterministic placeholder cost")
	_assert_true(bool(quote.get("affordable", false)), "initial terrain edit is affordable")

	# POC-32C: the same quote is exposed in player-facing feedback before money is
	# spent. Normal edits show their exact footprint, and affordable actions remain enabled.
	var feedback: Dictionary = scene.terrain_feedback(target)
	_assert_true(bool(feedback.get("valid", false)), "terrain feedback is valid for selected cell")
	_assert_equal(int(feedback.get("raise_cost", -1)), 120, "terrain feedback exposes raise cost")
	_assert_equal(int(feedback.get("lower_cost", -1)), 120, "terrain feedback exposes lower cost")
	_assert_equal(int(feedback.get("raise_cells", -1)), 9, "terrain feedback exposes normal raise footprint")
	_assert_equal(int(feedback.get("lower_cells", -1)), 9, "terrain feedback exposes normal lower footprint")
	_assert_true(bool(feedback.get("raise_affordable", false)), "terrain feedback marks affordable raise")
	_assert_true(bool(feedback.get("lower_affordable", false)), "terrain feedback marks affordable lower")
	scene._update_terrain_hud()
	_assert_true(scene.terrain_quote_label != null and "9 cells" in scene.terrain_quote_label.text, "terrain HUD displays quoted footprint")
	_assert_true(scene.terrain_raise_button != null and not scene.terrain_raise_button.disabled, "affordable raise button remains enabled")
	_assert_true(scene.terrain_lower_button != null and not scene.terrain_lower_button.disabled, "affordable lower button remains enabled")

	var raised: Dictionary = scene.sculpt_terrain(target, 1)
	_assert_true(bool(raised.get("built", false)), "raise terrain action succeeds")
	_assert_equal(int(raised.get("cost", -1)), 120, "raise terrain action charges quoted cost")
	_assert_equal(int(economy.cash_balance), cash_before - 120, "raise terrain action deducts construction funds")
	_assert_approx(_elevation_at(grid, target), center_before + 0.25, 0.0000000001, "center elevation rises by full brush step")
	_assert_approx(_elevation_at(grid, target + Vector2i(0, -1)), north_before + 0.125, 0.0000000001, "orthogonal neighbor receives half terrain step")
	_assert_approx(_elevation_at(grid, target + Vector2i(1, 1)), diagonal_before + 0.0625, 0.0000000001, "diagonal neighbor receives quarter terrain step")
	_assert_approx(_elevation_at(grid, target + Vector2i(2, 0)), far_before, 0.0000000001, "normal terrain brush does not mutate cells outside 3x3 footprint")
	_assert_equal(grid.surface_at(target.x, target.y), surface_before, "terrain sculpting never changes authoritative surface ownership")
	_assert_true(not economy.transaction_history.is_empty(), "terrain action records an economy transaction")
	if not economy.transaction_history.is_empty():
		_assert_equal(str(economy.transaction_history[-1].get("type", "")), "TERRAIN", "terrain transaction is explicitly typed")

	var iso_after: Vector2 = renderer.cell_center_iso(target.x, target.y)
	_assert_approx(iso_after.x, iso_before.x, 0.000001, "raising terrain preserves isometric lateral position")
	_assert_approx(iso_after.y, iso_before.y - 1.75, 0.000001, "raising terrain moves selected tile upward in isometric presentation")

	var boundary_quote: Dictionary = scene.quote_terrain_sculpt(Vector2i(0, 0), 1)
	_assert_true(bool(boundary_quote.get("valid", false)), "terrain brush clips cleanly at property edge")
	_assert_equal(int(boundary_quote.get("changes", []).size()), 4, "corner terrain brush affects only in-bounds cells")
	_assert_equal(int(boundary_quote.get("cost", -1)), 68, "clipped corner terrain brush charges only affected elevation volume")

	# Save at the raised state, mutate afterward, then prove the inherited POC-31
	# persistence restores terrain and economy together.
	var saved_center: float = _elevation_at(grid, target)
	var saved_cash: int = int(economy.cash_balance)
	var save_path := "user://poc32_elevation_test.json"
	_assert_true(scene.save_to_path(save_path), "elevation construction state saves to disk")
	var lowered: Dictionary = scene.sculpt_terrain(target, -1)
	_assert_true(bool(lowered.get("built", false)), "lower terrain action succeeds")
	_assert_approx(_elevation_at(grid, target), center_before, 0.0000000001, "opposite normal brush returns center to original elevation")
	_assert_true(scene.load_from_path(save_path), "saved elevation construction state reloads from disk")
	grid = scene.grid
	economy = scene.economy
	renderer = scene.renderer
	_assert_approx(_elevation_at(grid, target), saved_center, 0.0000000001, "reload restores authored terrain elevation")
	_assert_equal(int(economy.cash_balance), saved_cash, "reload restores terrain construction funds")
	_assert_approx(renderer.cell_center_iso(target.x, target.y).y, iso_after.y, 0.000001, "reload restores rendered terrain height")

	# Unaffordable terrain editing must be rejected without touching any grid data,
	# and POC-32C should make that state obvious before the player clicks.
	_assert_true(scene.select_cell(target), "terrain target can be reselected after reload")
	var reject_before: Dictionary = grid.to_dictionary()
	economy.cash_balance = 0
	var no_funds_feedback: Dictionary = scene.terrain_feedback(target)
	_assert_true(not bool(no_funds_feedback.get("raise_affordable", true)), "terrain feedback marks unaffordable raise")
	_assert_true(not bool(no_funds_feedback.get("lower_affordable", true)), "terrain feedback marks unaffordable lower")
	scene._update_terrain_hud()
	_assert_true(scene.terrain_raise_button != null and scene.terrain_raise_button.disabled, "unaffordable raise button disables")
	_assert_true(scene.terrain_lower_button != null and scene.terrain_lower_button.disabled, "unaffordable lower button disables")
	_assert_true(scene.terrain_quote_label != null and "NO FUNDS" in scene.terrain_quote_label.text, "terrain HUD explicitly reports insufficient funds")
	var rejected: Dictionary = scene.sculpt_terrain(target, -1)
	_assert_true(not bool(rejected.get("built", false)), "unaffordable terrain edit is rejected")
	_assert_equal(str(rejected.get("reason", "")), "INSUFFICIENT_FUNDS", "unaffordable terrain edit reports reason")
	_assert_true(grid.to_dictionary() == reject_before, "rejected terrain edit leaves authoritative grid unchanged")

	print("POC32A_C_ELEVATION_SUMMARY raise_cost=%d boundary_cost=%d center_step=%.2f brush_cells=%d saved_elevation=%.4f feedback=GREEN" % [
		int(raised.get("cost", 0)),
		int(boundary_quote.get("cost", 0)),
		float(scene.TERRAIN_STEP_YARDS),
		int(quote.get("changes", []).size()),
		saved_center
	])
	scene.free()

	# POC-32B: a deliberately exaggerated repeated edit should retain the exact
	# accepted normal brush at first, then broaden only when needed to prevent a
	# cliff. The safety ceiling is expressed as grade, so it scales with tile size.
	var guard_scene = ElevationScene.instantiate()
	get_root().add_child(guard_scene)
	var guard_initialized: bool = bool(guard_scene.initialize_property())
	_assert_true(guard_initialized and bool(guard_scene.initialized), "slope-guard scene initializes")
	if guard_initialized and bool(guard_scene.initialized):
		var guard_grid = guard_scene.grid
		var guard_economy = guard_scene.economy
		var guard_target := Vector2i(12, 12)
		var guard_center_before: float = _elevation_at(guard_grid, guard_target)
		var guard_surface_before: String = guard_grid.surface_at(guard_target.x, guard_target.y)
		guard_economy.add_revenue(100000, "POC32B_TEST_FUNDS")

		var all_built: bool = true
		var broadened: bool = false
		var widest_change_count: int = 0
		var repeated_edits: int = 28
		for _i in range(repeated_edits):
			var repeated_quote: Dictionary = guard_scene.quote_terrain_sculpt(guard_target, 1)
			if not bool(repeated_quote.get("valid", false)):
				all_built = false
				break
			var change_count: int = int(repeated_quote.get("changes", []).size())
			widest_change_count = maxi(widest_change_count, change_count)
			broadened = broadened or change_count > 9
			var repeated_result: Dictionary = guard_scene.sculpt_terrain(guard_target, 1)
			if not bool(repeated_result.get("built", false)):
				all_built = false
				break

		_assert_true(all_built, "repeated terrain shaping remains a valid paid construction action")
		_assert_true(broadened, "strong repeated sculpting broadens beyond 3x3 instead of creating a cliff")
		_assert_approx(
			_elevation_at(guard_grid, guard_target),
			guard_center_before + float(repeated_edits) * float(guard_scene.TERRAIN_STEP_YARDS),
			0.000000001,
			"slope guard preserves the player's requested center elevation"
		)
		_assert_equal(guard_grid.surface_at(guard_target.x, guard_target.y), guard_surface_before, "slope stabilization preserves surface ownership")
		var maximum_grade: float = float(guard_scene.max_cardinal_terrain_grade())
		_assert_true(
			maximum_grade <= float(guard_scene.MAX_ADJACENT_GRADE) + 0.000000001,
			"repeated terrain sculpting respects maximum adjacent grade"
		)
		var spread_feedback: Dictionary = guard_scene.terrain_feedback(guard_target)
		_assert_true(
			bool(spread_feedback.get("raise_expanded", false)),
			"terrain feedback warns when the next raise needs slope-safe spread"
		)
		_assert_true(
			int(spread_feedback.get("raise_cells", 0)) > 9,
			"terrain feedback reports expanded slope-safe footprint"
		)
		print("POC32B_SLOPE_SUMMARY repeated_edits=%d widest_cells=%d next_raise_cells=%d max_grade=%.6f grade_limit=%.6f center_rise=%.2f" % [
			repeated_edits,
			widest_change_count,
			int(spread_feedback.get("raise_cells", 0)),
			maximum_grade,
			float(guard_scene.MAX_ADJACENT_GRADE),
			_elevation_at(guard_grid, guard_target) - guard_center_before
		])
	guard_scene.free()

	_finish()


func _elevation_at(grid, cell: Vector2i) -> float:
	return float(grid.tile_at(cell.x, cell.y).get("elevation", 0.0))


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


func _assert_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.12f expected=%.12f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.16f expected=%.16f tolerance=%.16f)" % [label, actual, expected, tolerance])


func _finish() -> void:
	if failures == 0:
		print("POC-32A/B/C ISOMETRIC ELEVATION PASSED")
		quit(0)
	else:
		push_error("POC-32A/B/C ISOMETRIC ELEVATION FAILED: %d" % failures)
		quit(1)

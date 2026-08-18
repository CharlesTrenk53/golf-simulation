extends SceneTree

const ElevationScene = preload("res://scenes/poc32_isometric_elevation.tscn")

var failures := 0


func _init() -> void:
	print("POC-32A: player-facing isometric elevation")
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
	_assert_equal(int(quote.get("changes", []).size()), 9, "interior terrain brush affects nine authoritative cells")
	_assert_equal(int(quote.get("cost", -1)), 120, "full 3x3 terrain brush has deterministic placeholder cost")
	_assert_true(bool(quote.get("affordable", false)), "initial terrain edit is affordable")

	var raised: Dictionary = scene.sculpt_terrain(target, 1)
	_assert_true(bool(raised.get("built", false)), "raise terrain action succeeds")
	_assert_equal(int(raised.get("cost", -1)), 120, "raise terrain action charges quoted cost")
	_assert_equal(int(economy.cash_balance), cash_before - 120, "raise terrain action deducts construction funds")
	_assert_approx(_elevation_at(grid, target), center_before + 0.25, 0.0000000001, "center elevation rises by full brush step")
	_assert_approx(_elevation_at(grid, target + Vector2i(0, -1)), north_before + 0.125, 0.0000000001, "orthogonal neighbor receives half terrain step")
	_assert_approx(_elevation_at(grid, target + Vector2i(1, 1)), diagonal_before + 0.0625, 0.0000000001, "diagonal neighbor receives quarter terrain step")
	_assert_approx(_elevation_at(grid, target + Vector2i(2, 0)), far_before, 0.0000000001, "terrain brush does not mutate cells outside 3x3 footprint")
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
	_assert_approx(_elevation_at(grid, target), center_before, 0.0000000001, "opposite brush returns center to original elevation")
	_assert_true(scene.load_from_path(save_path), "saved elevation construction state reloads from disk")
	grid = scene.grid
	economy = scene.economy
	renderer = scene.renderer
	_assert_approx(_elevation_at(grid, target), saved_center, 0.0000000001, "reload restores authored terrain elevation")
	_assert_equal(int(economy.cash_balance), saved_cash, "reload restores terrain construction funds")
	_assert_approx(renderer.cell_center_iso(target.x, target.y).y, iso_after.y, 0.000001, "reload restores rendered terrain height")

	# Unaffordable terrain editing must be rejected without touching any grid data.
	var reject_before: Dictionary = grid.to_dictionary()
	economy.cash_balance = 0
	var rejected: Dictionary = scene.sculpt_terrain(target, -1)
	_assert_true(not bool(rejected.get("built", false)), "unaffordable terrain edit is rejected")
	_assert_equal(str(rejected.get("reason", "")), "INSUFFICIENT_FUNDS", "unaffordable terrain edit reports reason")
	_assert_equal(grid.to_dictionary(), reject_before, "rejected terrain edit leaves authoritative grid unchanged")

	print("POC32_ELEVATION_SUMMARY raise_cost=%d boundary_cost=%d center_step=%.2f brush_cells=%d saved_elevation=%.4f" % [
		int(raised.get("cost", 0)),
		int(boundary_quote.get("cost", 0)),
		float(scene.TERRAIN_STEP_YARDS),
		int(quote.get("changes", []).size()),
		saved_center
	])

	scene.free()
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
		print("POC-32A ISOMETRIC ELEVATION PASSED")
		quit(0)
	else:
		push_error("POC-32A ISOMETRIC ELEVATION FAILED: %d" % failures)
		quit(1)

extends SceneTree

const ConstructionScene = preload("res://scenes/poc31_isometric_construction.tscn")

var failures := 0


func _init() -> void:
	print("POC-31: player-facing isometric construction")
	var scene = ConstructionScene.instantiate()
	get_root().add_child(scene)
	var initialized_now: bool = bool(scene.initialize_property())

	_assert_true(initialized_now and bool(scene.initialized), "construction scene initializes")
	if not initialized_now or not bool(scene.initialized):
		scene.free()
		_finish()
		return

	var grid = scene.grid
	var economy = scene.economy
	var renderer = scene.renderer
	var untouched_before: Dictionary = grid.to_dictionary()

	_assert_equal(int(grid.width), 24, "construction property width")
	_assert_equal(int(grid.height), 24, "construction property height")
	_assert_equal(int(economy.cash_balance), 30000, "construction property starts with configured funds")
	_assert_equal(str(scene.selected_surface), "FAIRWAY", "fairway is the default construction tool")

	# POC-31A: point picking must select the same authoritative cell in every
	# cardinal presentation orientation.
	var target := Vector2i(8, 11)
	for quarter in range(4):
		renderer.set_view_rotation_quarters(quarter)
		var projected_center: Vector2 = renderer.cell_center_iso(target.x, target.y)
		var picked: Vector2i = renderer.pick_cell_at_local_point(projected_center)
		_assert_equal(picked, target, "rotation %d picks the authoritative cell at its projected center" % quarter)
		_assert_true(scene.select_cell(picked), "rotation %d selection accepts picked cell" % quarter)
		_assert_equal(renderer.selected_cell, target, "rotation %d renderer selection mirrors authoritative cell" % quarter)
	_assert_equal(grid.to_dictionary(), untouched_before, "hover/selection/rotation never mutate construction data")

	# POC-31B: all surface changes go through the existing economy.
	renderer.set_view_rotation_quarters(0)
	var starting_cash: int = int(economy.cash_balance)
	_assert_true(scene.set_selected_surface("FAIRWAY"), "player can choose fairway tool")
	var fairway_result: Dictionary = scene.build_at_cell(Vector2i(5, 18))
	_assert_true(bool(fairway_result.get("built", false)), "fairway construction succeeds")
	_assert_equal(grid.surface_at(5, 18), "FAIRWAY", "fairway construction changes authoritative grid")
	_assert_equal(int(fairway_result.get("cost", -1)), 80, "fairway charges authoritative economy cost")
	_assert_equal(int(economy.cash_balance), starting_cash - 80, "cash balance decreases by construction cost")

	var repeat_cash: int = int(economy.cash_balance)
	var repeat_result: Dictionary = scene.build_at_cell(Vector2i(5, 18), "FAIRWAY")
	_assert_true(bool(repeat_result.get("built", false)), "rebuilding same surface is accepted")
	_assert_equal(int(repeat_result.get("cost", -1)), 0, "same-surface repaint is free")
	_assert_equal(int(economy.cash_balance), repeat_cash, "free repaint leaves funds unchanged")

	# Prepare a player-authored tee and connected green, then mark tee/cup. This
	# proves that the editor can hand exact construction truth to HoleDefinition.
	_assert_true(bool(scene.build_at_cell(Vector2i(5, 20), "TEE").get("built", false)), "tee construction succeeds")
	for cell in [Vector2i(16, 3), Vector2i(17, 3), Vector2i(16, 4), Vector2i(17, 4)]:
		_assert_true(bool(scene.build_at_cell(cell, "GREEN").get("built", false)), "connected green cell builds at %s" % str(cell))
	_assert_true(scene.set_tee_anchor(Vector2i(5, 20)), "constructed tee can become hole start")
	_assert_true(scene.set_cup_cell(Vector2i(16, 3)), "constructed green can receive cup")
	_assert_true(not scene.set_cup_cell(Vector2i(0, 0)), "rough tile cannot receive cup")
	_assert_equal(scene.cup_cell, Vector2i(16, 3), "invalid cup attempt does not replace valid cup")

	var validation: Dictionary = scene.validate_current_hole(4)
	_assert_true(bool(validation.get("valid", false)), "player-authored construction validates as a hole")
	var hole = validation.get("hole", null)
	_assert_true(hole != null, "player construction builds a real HoleDefinition")
	if hole != null:
		_assert_equal(int(hole.par), 4, "player-authored hole preserves selected par")
		_assert_true(float(hole.nominal_yardage) > 150.0, "player-authored tee/cup produce meaningful yardage")

	# Save/reload economy + grid + hole markers + view orientation through an
	# actual FileAccess round trip. Integer/string construction truth is exact;
	# authored elevations must survive within negligible serialization precision.
	renderer.set_view_rotation_quarters(3)
	var saved_grid: Dictionary = grid.to_dictionary()
	var saved_cash: int = int(economy.cash_balance)
	var save_path := "user://poc31_construction_test.json"
	_assert_true(scene.save_to_path(save_path), "construction state saves to disk")
	_assert_true(bool(scene.build_at_cell(Vector2i(2, 2), "WATER").get("built", false)), "post-save mutation succeeds")
	renderer.set_view_rotation_quarters(1)
	_assert_true(scene.load_from_path(save_path), "construction state reloads from disk")
	grid = scene.grid
	economy = scene.economy
	renderer = scene.renderer
	_assert_grid_roundtrip(grid.to_dictionary(), saved_grid, "reload restores authoritative grid")
	_assert_equal(int(economy.cash_balance), saved_cash, "reload restores cash balance")
	_assert_equal(scene.tee_anchor, Vector2i(5, 20), "reload restores tee marker")
	_assert_equal(scene.cup_cell, Vector2i(16, 3), "reload restores cup marker")
	_assert_equal(int(renderer.rotation_quarters), 3, "reload restores cardinal camera orientation")

	# Repainting a marked hole feature must invalidate the marker rather than
	# leave stale hole-authoring state behind.
	_assert_true(bool(scene.build_at_cell(Vector2i(16, 3), "FRINGE").get("built", false)), "cup tile can be repainted")
	_assert_equal(scene.cup_cell, Vector2i(-1, -1), "repainting cup tile away from green clears cup marker")
	_assert_true(not bool(scene.validate_current_hole(4).get("valid", false)), "hole validation fails after cup marker is invalidated")
	_assert_true(scene.load_from_path(save_path), "saved valid construction can be restored after marker invalidation")
	grid = scene.grid
	economy = scene.economy
	renderer = scene.renderer

	# Insufficient funds must reject construction without touching the grid.
	var reject_before: Dictionary = grid.to_dictionary()
	economy.cash_balance = 0
	var rejected: Dictionary = scene.build_at_cell(Vector2i(1, 1), "WATER")
	_assert_true(not bool(rejected.get("built", false)), "unaffordable construction is rejected")
	_assert_equal(str(rejected.get("reason", "")), "INSUFFICIENT_FUNDS", "unaffordable build reports reason")
	_assert_equal(grid.to_dictionary(), reject_before, "rejected build leaves authoritative grid unchanged")

	print("POC31_CONSTRUCTION_SUMMARY funds=%d spend=%d fairway=%d tee=%d green=%d rotation=%d yardage=%.1f" % [
		int(economy.cash_balance),
		int(economy.lifetime_construction_spend),
		int(grid.count_surface("FAIRWAY")),
		int(grid.count_surface("TEE")),
		int(grid.count_surface("GREEN")),
		int(renderer.rotation_quarters),
		float(hole.nominal_yardage) if hole != null else 0.0
	])

	scene.free()
	_finish()


func _assert_grid_roundtrip(actual: Dictionary, expected: Dictionary, label: String) -> void:
	const ELEVATION_TOLERANCE := 0.000000000001
	var structural_ok := true
	var max_elevation_drift := 0.0

	for key in ["schema_version", "width", "height"]:
		if int(actual.get(key, -1)) != int(expected.get(key, -2)):
			structural_ok = false

	if absf(float(actual.get("tile_size_yards", 0.0)) - float(expected.get("tile_size_yards", 0.0))) > ELEVATION_TOLERANCE:
		structural_ok = false

	var actual_origin: Array = actual.get("origin", [])
	var expected_origin: Array = expected.get("origin", [])
	if actual_origin.size() != 2 or expected_origin.size() != 2:
		structural_ok = false
	else:
		for i in range(2):
			if absf(float(actual_origin[i]) - float(expected_origin[i])) > ELEVATION_TOLERANCE:
				structural_ok = false

	var actual_rows: Array = actual.get("tiles", [])
	var expected_rows: Array = expected.get("tiles", [])
	if actual_rows.size() != expected_rows.size():
		structural_ok = false
	else:
		for y in range(actual_rows.size()):
			if not actual_rows[y] is Array or not expected_rows[y] is Array or actual_rows[y].size() != expected_rows[y].size():
				structural_ok = false
				continue
			for x in range(actual_rows[y].size()):
				var actual_tile: Dictionary = actual_rows[y][x]
				var expected_tile: Dictionary = expected_rows[y][x]
				if int(actual_tile.get("x", -1)) != int(expected_tile.get("x", -2)):
					structural_ok = false
				if int(actual_tile.get("y", -1)) != int(expected_tile.get("y", -2)):
					structural_ok = false
				if str(actual_tile.get("surface", "")) != str(expected_tile.get("surface", "__missing__")):
					structural_ok = false
				if int(actual_tile.get("build_cost", -1)) != int(expected_tile.get("build_cost", -2)):
					structural_ok = false
				var elevation_drift := absf(float(actual_tile.get("elevation", 0.0)) - float(expected_tile.get("elevation", 0.0)))
				max_elevation_drift = maxf(max_elevation_drift, elevation_drift)

	var elevation_ok := max_elevation_drift <= ELEVATION_TOLERANCE
	if structural_ok and elevation_ok:
		print("PASS: %s (max_elevation_drift=%.3e)" % [label, max_elevation_drift])
	else:
		failures += 1
		push_error("FAIL: %s (structural_ok=%s max_elevation_drift=%.16g tolerance=%.3e)" % [
			label,
			str(structural_ok),
			max_elevation_drift,
			ELEVATION_TOLERANCE
		])


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
		print("POC-31 ISOMETRIC CONSTRUCTION PASSED")
		quit(0)
	else:
		push_error("POC-31 ISOMETRIC CONSTRUCTION FAILED: %d" % failures)
		quit(1)

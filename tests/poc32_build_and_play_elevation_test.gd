extends SceneTree

const ElevationScene = preload("res://scenes/poc32_isometric_elevation.tscn")
const PlayableHoleRuntime = preload("res://scenes/playable_hole_runtime.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-32D: sculpted elevation build-and-play proof")

	var scene = ElevationScene.instantiate()
	get_root().add_child(scene)
	_assert_true(bool(scene.initialize_property()), "POC-32 construction property initializes")
	if not bool(scene.initialized):
		scene.free()
		_finish()
		return

	var tee_cell := Vector2i(12, 20)
	var pin_cell := Vector2i(12, 4)
	_assert_true(_build_par_three(scene, tee_cell, pin_cell), "player builds a playable par-three through construction actions")
	_assert_true(scene.set_tee_anchor(tee_cell), "player marks authored tee")
	_assert_true(scene.set_cup_cell(pin_cell), "player marks authored cup")

	# Shape distinct elevations at both ends of the hole. These edits go through
	# the same paid terrain economy as the player-facing controls.
	for _i in range(4):
		var raised: Dictionary = scene.sculpt_terrain(tee_cell, 1)
		_assert_true(bool(raised.get("built", false)), "tee terrain raise succeeds")
	for _i in range(3):
		var lowered: Dictionary = scene.sculpt_terrain(pin_cell, -1)
		_assert_true(bool(lowered.get("built", false)), "green terrain lower succeeds")

	var authored_tee_elevation: float = _elevation_at(scene.grid, tee_cell)
	var authored_pin_elevation: float = _elevation_at(scene.grid, pin_cell)
	_assert_true(absf(authored_tee_elevation - authored_pin_elevation) > 0.5, "player-authored tee and green have meaningfully different elevations")
	_assert_equal(scene.grid.surface_at(tee_cell.x, tee_cell.y), "TEE", "terrain shaping preserves tee surface")
	_assert_equal(scene.grid.surface_at(pin_cell.x, pin_cell.y), "GREEN", "terrain shaping preserves green surface")

	# Save the authored course, deliberately mutate it afterward, then reload to
	# prove the playable definition will be built from persisted terrain rather
	# than transient scene state.
	var save_path := "user://poc32d_elevation_play_test.json"
	var saved_cash: int = int(scene.economy.cash_balance)
	_assert_true(scene.save_to_path(save_path), "player-shaped course saves")
	var post_save_mutation: Dictionary = scene.sculpt_terrain(tee_cell, 1)
	_assert_true(bool(post_save_mutation.get("built", false)), "post-save terrain mutation succeeds")
	_assert_true(absf(_elevation_at(scene.grid, tee_cell) - authored_tee_elevation) > 0.1, "post-save mutation actually changes authoritative terrain")
	_assert_true(scene.load_from_path(save_path), "player-shaped course reloads")
	_assert_close(_elevation_at(scene.grid, tee_cell), authored_tee_elevation, 0.000000001, "reload restores authored tee elevation")
	_assert_close(_elevation_at(scene.grid, pin_cell), authored_pin_elevation, 0.000000001, "reload restores authored pin elevation")
	_assert_equal(int(scene.economy.cash_balance), saved_cash, "reload restores terrain construction economy")
	_assert_equal(scene.tee_anchor, tee_cell, "reload restores tee marker")
	_assert_equal(scene.cup_cell, pin_cell, "reload restores cup marker")

	var hole = scene.build_current_hole(3, "Elevation Proof")
	_assert_true(hole != null, "reloaded construction becomes the authoritative HoleDefinition")
	if hole == null:
		scene.free()
		_finish()
		return

	var tee_world: Vector3 = scene.grid.tile_center_world(tee_cell.x, tee_cell.y)
	var pin_world: Vector3 = scene.grid.tile_center_world(pin_cell.x, pin_cell.y)
	_assert_vector_close(hole.tee_position("player_tee"), tee_world, "HoleDefinition tee position includes player-authored elevation")
	_assert_vector_close(hole.pin_position, pin_world, "HoleDefinition pin position includes player-authored elevation")
	_assert_close(hole.tee_position("player_tee").y, authored_tee_elevation, 0.000000001, "HoleDefinition tee Y exactly matches construction grid")
	_assert_close(hole.pin_position.y, authored_pin_elevation, 0.000000001, "HoleDefinition pin Y exactly matches construction grid")
	_assert_equal(hole.elevation_points.size(), int(scene.grid.width * scene.grid.height), "HoleDefinition carries one authoritative elevation sample for every construction cell")
	_assert_true(_definition_contains_elevation(hole, tee_world, authored_tee_elevation), "HoleDefinition elevation field contains sculpted tee terrain")
	_assert_true(_definition_contains_elevation(hole, pin_world, authored_pin_elevation), "HoleDefinition elevation field contains sculpted green terrain")

	var golfer = Golfer.new()
	golfer.profile = Golfer.GolferProfile.WILD_BILL
	golfer.apply_profile()
	get_root().add_child(golfer)

	var runtime = PlayableHoleRuntime.new()
	get_root().add_child(runtime)
	_assert_true(runtime.configure(hole, golfer, "player_tee", 32032), "existing autonomous runtime accepts sculpted player-built hole")
	if runtime.state != null:
		_assert_vector_close(runtime.state.ball_position, hole.tee_position("player_tee"), "autonomous simulation starts from elevated authored tee")

	var first_shot: Dictionary = runtime.play_next_shot(false)
	_assert_true(not first_shot.is_empty(), "golfer generates a real first shot on sculpted course")
	if not first_shot.is_empty():
		_assert_vector_close(first_shot.get("start_position", Vector3.ZERO), hole.tee_position("player_tee"), "golfer shot starts from exact sculpted tee elevation")

	var summary: Dictionary = runtime.play_to_completion(false)
	_assert_true(bool(summary.get("finished", false)), "golfer completes player-shaped elevated hole")
	_assert_true(int(summary.get("strokes", 0)) > 0, "elevated player-built hole produces a real score")
	_assert_equal(int(summary.get("par", 0)), 3, "played result preserves authored par")
	_assert_equal(runtime.presented_history.size(), runtime.playable.autonomous.shot_history.size(), "presentation history reconciles with authoritative autonomous simulation")

	print("POC32D_BUILD_PLAY_SUMMARY golfer=%s yardage=%.1f par=%d strokes=%d tee_elev=%.3f pin_elev=%.3f elevation_points=%d cash=%d" % [
		golfer.golfer_name,
		hole.nominal_yardage,
		hole.par,
		int(summary.get("strokes", 0)),
		authored_tee_elevation,
		authored_pin_elevation,
		hole.elevation_points.size(),
		int(scene.economy.cash_balance)
	])

	runtime.queue_free()
	golfer.queue_free()
	scene.queue_free()
	_finish()


func _build_par_three(scene, tee_cell: Vector2i, pin_cell: Vector2i) -> bool:
	# Small teeing ground.
	for cell in [tee_cell, tee_cell + Vector2i(-1, 0), tee_cell + Vector2i(0, 1), tee_cell + Vector2i(-1, 1)]:
		if not _build_surface(scene, cell, "TEE"):
			return false

	# Three-tile-wide approach corridor between tee and green.
	for y in range(6, 20):
		for x in range(11, 14):
			if not _build_surface(scene, Vector2i(x, y), "FAIRWAY"):
				return false

	# Connected 3x3 green so ConstructionGridHoleBuilder can trace a valid outline.
	for y in range(pin_cell.y - 1, pin_cell.y + 2):
		for x in range(pin_cell.x - 1, pin_cell.x + 2):
			if not _build_surface(scene, Vector2i(x, y), "GREEN"):
				return false
	return true


func _build_surface(scene, cell: Vector2i, surface: String) -> bool:
	var result: Dictionary = scene.build_at_cell(cell, surface)
	return bool(result.get("built", false))


func _definition_contains_elevation(hole, expected_position: Vector3, expected_elevation: float) -> bool:
	for point in hole.elevation_points:
		var position: Vector3 = point.get("position", Vector3.ZERO)
		if absf(position.x - expected_position.x) <= 0.000001 and absf(position.z - expected_position.z) <= 0.000001:
			return absf(float(point.get("elevation", 0.0)) - expected_elevation) <= 0.000000001 and absf(position.y - expected_elevation) <= 0.000000001
	return false


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


func _assert_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.12f expected=%.12f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.16f expected=%.16f tolerance=%.16f)" % [label, actual, expected, tolerance])


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.000001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-32D SCULPTED ELEVATION BUILD-AND-PLAY PROOF PASSED")
		quit(0)
	else:
		push_error("POC-32D SCULPTED ELEVATION BUILD-AND-PLAY PROOF FAILED: %d" % failures)
		quit(1)

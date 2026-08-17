extends SceneTree

const VisualProofScene = preload("res://scenes/poc30_grid_course_visual_proof.tscn")
const PlayableHoleRuntime = preload("res://scenes/playable_hole_runtime.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-30F: authoritative grid build-and-play visual proof")

	var proof = VisualProofScene.instantiate()
	get_root().add_child(proof)
	var initialized_now: bool = bool(proof.initialize_proof())
	_assert_true(initialized_now and bool(proof.initialized), "visual proof scene initializes from authoritative construction grid")
	if not initialized_now or not bool(proof.initialized):
		_finish()
		return

	var grid = proof.grid
	var hole = proof.hole
	var before: Dictionary = grid.to_dictionary()

	_assert_true(hole != null, "visual proof grid converts into playable HoleDefinition")
	_assert_close(float(hole.nominal_yardage), 410.0, 0.001, "visual proof preserves player-authored 410-yard routing")
	_assert_equal(int(hole.par), 4, "visual proof preserves player-authored par")
	_assert_true(int(proof.economy.lifetime_construction_spend) > 0, "visual proof surfaces are real paid construction actions")
	_assert_true(int(proof.economy.cash_balance) > 0, "proof course remains within starter construction budget")

	_assert_true(int(grid.count_surface("TEE")) > 0, "authoritative grid contains built tee surface")
	_assert_true(int(grid.count_surface("FAIRWAY")) > 0, "authoritative grid contains built fairway surface")
	_assert_equal(int(grid.count_surface("FRINGE")), 16, "authoritative grid contains explicit player-built fringe collar")
	_assert_equal(int(grid.count_surface("GREEN")), 9, "authoritative grid contains nine-cell green")
	_assert_equal(int(grid.count_surface("BUNKER")), 4, "authoritative grid contains greenside bunker")
	_assert_equal(int(grid.count_surface("WATER")), 8, "authoritative grid contains landing-zone water")

	_assert_true(proof.terrain != null and proof.terrain.terrain_visual != null, "POC-30D contoured base terrain is present")
	_assert_equal(int(proof.terrain.rendered_cells), int(grid.width * grid.height), "contoured terrain covers every authoritative property cell")
	_assert_true(proof.surfaces != null and proof.surfaces.contoured_base_active, "POC-30B/C surfaces are projected onto contoured base")
	_assert_true(proof.surfaces.rough_base_hidden(), "legacy rough plane is hidden beneath contoured terrain")
	_assert_equal(proof.surfaces.rendered_tile_count("FAIRWAY"), grid.count_surface("FAIRWAY"), "visible fairway reconciles exact authoritative ownership")
	_assert_equal(proof.surfaces.rendered_tile_count("FRINGE"), grid.count_surface("FRINGE"), "visible fringe reconciles exact authoritative ownership")
	_assert_equal(proof.surfaces.rendered_tile_count("GREEN"), grid.count_surface("GREEN"), "visible green reconciles exact authoritative ownership")
	_assert_equal(proof.surfaces.rendered_tile_count("BUNKER"), grid.count_surface("BUNKER"), "visible bunker reconciles exact authoritative ownership")
	_assert_equal(proof.surfaces.rendered_tile_count("WATER"), grid.count_surface("WATER"), "visible water reconciles exact authoritative ownership")
	_assert_true(proof.surfaces.rendered_transition_edge_count() > 0, "organic surface transition geometry is active on proof course")

	var sample_x: int = 7
	var sample_y: int = 20
	var authoritative_center: float = float(grid.tile_at(sample_x, sample_y).get("elevation", 0.0))
	_assert_close(
		proof.terrain.terrain_height_at_cell_uv(sample_x, sample_y, 0.5, 0.5),
		authoritative_center,
		0.0001,
		"contoured base passes through authoritative sample elevation"
	)
	_assert_close(
		proof.surfaces.surface_height_at_cell_uv(sample_x, sample_y, 0.5, 0.5),
		authoritative_center,
		0.0001,
		"surface overlay passes through same authoritative sample elevation"
	)
	_assert_close(
		proof.surfaces.surface_height_at_cell_uv(sample_x, sample_y, 0.25, 0.5),
		proof.terrain.terrain_height_at_cell_uv(sample_x, sample_y, 0.25, 0.5),
		0.0001,
		"surface overlay and contoured terrain share interior landform interpolation"
	)

	_assert_true(proof.dressing != null and proof.dressing.dressing_count() > 0, "POC-30E safe-rough course dressing is present")
	_assert_true(proof.get_node_or_null("CourseDressingLayer/CourseWorldEnvironment") != null, "visual proof includes course environment")
	_assert_true(proof.get_node_or_null("CourseDressingLayer/CourseSun") != null, "visual proof includes course sunlight")
	_assert_equal(grid.to_dictionary(), before, "all POC-30 visual layers leave authoritative grid unchanged")

	var golfer = Golfer.new()
	golfer.profile = Golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	get_root().add_child(golfer)

	var runtime = PlayableHoleRuntime.new()
	get_root().add_child(runtime)
	_assert_true(runtime.configure(hole, golfer, "back", 30030), "existing autonomous runtime accepts exact visually rendered HoleDefinition")
	var summary: Dictionary = runtime.play_to_completion(false)
	_assert_true(bool(summary.get("finished", false)), "golfer completes the exact grid-built visual proof hole")
	_assert_true(int(summary.get("strokes", 0)) > 0, "grid-built visual proof produces a real authoritative score")
	_assert_equal(int(summary.get("par", 0)), 4, "played result preserves grid-authored par")
	_assert_equal(runtime.presented_history.size(), runtime.playable.autonomous.shot_history.size(), "presentation history reconciles authoritative simulation history")
	_assert_vector_close(summary.get("visual_ball_position", Vector3.ZERO), runtime.state.ball_position, "visible ball finishes at authoritative final lie")
	_assert_equal(grid.to_dictionary(), before, "playing the rendered hole does not mutate construction truth")

	print("POC30F_BUILD_PLAY_VISUAL_SUMMARY golfer=%s yardage=%.1f par=%d strokes=%d spend=%d fairway=%d fringe=%d green=%d bunker=%d water=%d dressing=%d transitions=%d" % [
		golfer.golfer_name,
		float(hole.nominal_yardage),
		int(hole.par),
		int(summary.get("strokes", 0)),
		int(proof.economy.lifetime_construction_spend),
		int(grid.count_surface("FAIRWAY")),
		int(grid.count_surface("FRINGE")),
		int(grid.count_surface("GREEN")),
		int(grid.count_surface("BUNKER")),
		int(grid.count_surface("WATER")),
		int(proof.dressing.dressing_count()),
		int(proof.surfaces.rendered_transition_edge_count())
	])

	runtime.queue_free()
	golfer.queue_free()
	proof.queue_free()
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


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-30F GRID BUILD-AND-PLAY VISUAL PROOF PASSED")
		quit(0)
	else:
		push_error("POC-30F GRID BUILD-AND-PLAY VISUAL PROOF FAILED: %d" % failures)
		quit(1)

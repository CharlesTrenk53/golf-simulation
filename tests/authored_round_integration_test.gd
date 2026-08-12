extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const CourseAuthoringModel = preload("res://simulation/course_authoring_model.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")

var failures: int = 0


func _init() -> void:
	print("POC-18A: authored course round integration")
	var course = _build_course()
	_assert_true(course != null, "authored course builds a valid CourseDefinition")
	if course == null:
		_finish()
		return

	_assert_equal(course.hole_count(), 3, "course contains three authored holes")
	_assert_equal(course.total_par(), 12, "course total par derives from authored holes")
	_assert_float_close(course.total_yardage("back"), 1103.0, 0.001, "course total yardage uses authored back tees")

	var golfer = _build_golfer()
	var round = AutonomousRound.new(course, "back")
	var result: Dictionary = round.play_round(golfer, 180100)
	var hole_results: Array = result.get("hole_results", [])
	var scorecard: Array = result.get("scorecard", [])

	_assert_true(bool(result.get("round_finished", false)), "golfer completes the authored round")
	_assert_true(bool(result.get("complete", false)), "RoundState reports complete")
	_assert_equal(int(result.get("holes_completed", 0)), 3, "all three holes are recorded")
	_assert_equal(int(result.get("remaining_holes", -1)), 0, "no holes remain after round")
	_assert_equal(hole_results.size(), 3, "round exposes three hole results")
	_assert_equal(scorecard.size(), 3, "round exposes three scorecard rows")
	_assert_equal(int(result.get("par_played", 0)), 12, "round par played reconciles to course par")

	var summed_strokes: int = 0
	for index in range(hole_results.size()):
		var hole_result: Dictionary = hole_results[index]
		summed_strokes += int(hole_result.get("strokes", 0))
		_assert_true(bool(hole_result.get("finished", false)), "hole %d finishes" % (index + 1))
		_assert_true(bool(hole_result.get("recorded", false)), "hole %d score is recorded" % (index + 1))
		_assert_equal(int(hole_result.get("hole_number", 0)), index + 1, "hole %d remains in authored order" % (index + 1))
		_assert_true(not hole_result.get("history", []).is_empty(), "hole %d produces shot history" % (index + 1))

	_assert_equal(int(result.get("total_strokes", -1)), summed_strokes, "round total strokes equals sum of hole results")
	_assert_equal(int(result.get("score_to_par", 999)), summed_strokes - 12, "round score-to-par reconciles")

	for index in range(scorecard.size()):
		var row: Dictionary = scorecard[index]
		_assert_equal(int(row.get("hole_number", 0)), index + 1, "scorecard row %d preserves hole number" % (index + 1))
		_assert_true(bool(row.get("completed", false)), "scorecard row %d is completed" % (index + 1))
		_assert_equal(int(row.get("strokes", -1)), int(hole_results[index].get("strokes", -2)), "scorecard row %d matches hole result" % (index + 1))

	print("ROUND_SUMMARY finished=%s holes=%d strokes=%d par=%d score_to_par=%+d" % [
		str(result.get("round_finished", false)),
		int(result.get("holes_completed", 0)),
		int(result.get("total_strokes", 0)),
		int(result.get("par_played", 0)),
		int(result.get("score_to_par", 0))
	])
	for row in scorecard:
		print("SCORECARD hole=%d name=%s par=%d yardage=%.0f strokes=%d score_to_par=%+d" % [
			int(row.get("hole_number", 0)),
			str(row.get("hole_name", "")),
			int(row.get("par", 0)),
			float(row.get("yardage", 0.0)),
			int(row.get("strokes", 0)),
			int(row.get("score_to_par", 0))
		])

	golfer.free()
	_finish()


func _build_course():
	var author = CourseAuthoringModel.new()
	author.configure_identity("poc18_authored_round", "POC-18 Authored Three")
	_assert_true(author.add_hole_definition(_build_straight_par4()), "straight par 4 enters course")
	_assert_true(author.add_hole_definition(_build_water_par3()), "water par 3 enters course")
	_assert_true(author.add_hole_definition(_build_risk_reward_par5()), "risk-reward par 5 enters course")
	return author.build_definition()


func _build_straight_par4():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc18_authored_round", 1, "Opening Drive", 4, 410.0)
	author.add_tee("back", "Back", Vector3(0, 0, 410), 410.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-18, -16, 18, 16))
	author.add_surface_region("fairway", "Fairway", "FAIRWAY", _rect(-32, 28, 32, 390))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, 400, 10, 420))
	return author.build_definition()


func _build_water_par3():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc18_authored_round", 2, "Carry the Water", 3, 168.0)
	author.add_tee("back", "Back", Vector3(0, 0, 168), 168.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-20, -15, 20, 16))
	author.add_surface_region("approach_rough", "Approach Rough", "ROUGH", _rect(-42, 16, 42, 55))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, 158, 10, 178))
	author.add_hazard("front_water", "Front Water", "WATER", _rect(-48, 55, 48, 118), 1, "lateral")
	return author.build_definition()


func _build_risk_reward_par5():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc18_authored_round", 3, "Split Decision", 5, 525.0)
	author.add_tee("back", "Back", Vector3(0, 0, 525), 525.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-22, -17, 22, 18))
	author.add_surface_region("left_fairway", "Left Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-58, 25), Vector2(-12, 25), Vector2(-8, 205), Vector2(-18, 360), Vector2(-45, 500), Vector2(-78, 500)
	]))
	author.add_surface_region("right_fairway", "Right Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(12, 25), Vector2(62, 25), Vector2(70, 205), Vector2(55, 365), Vector2(40, 500), Vector2(12, 500)
	]))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, 515, 10, 535))
	author.add_hazard("center_lake", "Center Lake", "WATER", PackedVector2Array([
		Vector2(-16, 205), Vector2(18, 205), Vector2(24, 350), Vector2(-20, 350)
	]), 1, "lateral")
	return author.build_definition()


func _build_golfer() -> Node:
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.golfer_name = "POC18 Round Golfer"
	golfer.driving = 78.0
	golfer.approach = 78.0
	golfer.short_game = 78.0
	golfer.putting = 78.0
	golfer.risk_tolerance = 35.0
	golfer.confidence = 72.0
	golfer.decision_variability = 0.0
	golfer.physical_power = 72.0
	golfer.mobility = 72.0
	golfer.coordination = 72.0
	golfer.endurance = 72.0
	return golfer


func _rect(left: float, near_z: float, right: float, far_z: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(left, near_z), Vector2(right, near_z), Vector2(right, far_z), Vector2(left, far_z)
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


func _assert_float_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-18A AUTHORED ROUND INTEGRATION PASSED")
		quit(0)
	else:
		push_error("POC-18A AUTHORED ROUND INTEGRATION FAILED: %d" % failures)
		quit(1)

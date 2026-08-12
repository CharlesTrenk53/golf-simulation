extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const CourseAuthoringModel = preload("res://simulation/course_authoring_model.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")

var failures: int = 0


func _init() -> void:
	print("POC-18B: authored round stepwise progression")
	var course = _build_course()
	_assert_true(course != null, "authored course builds")
	if course == null:
		_finish()
		return

	var golfer = _build_golfer()
	var round = AutonomousRound.new(course, "back")

	var before: Dictionary = round.snapshot()
	_assert_equal(int(before.get("holes_completed", -1)), 0, "round starts with zero completed holes")
	_assert_equal(int(before.get("current_hole_number", 0)), 1, "round starts on hole 1")
	_assert_true(not bool(before.get("round_finished", true)), "round starts unfinished")

	var result1: Dictionary = round.play_current_hole(golfer, 180201)
	_assert_true(bool(result1.get("finished", false)), "hole 1 finishes stepwise")
	_assert_true(bool(result1.get("recorded", false)), "hole 1 records stepwise")
	var after1: Dictionary = round.snapshot()
	_assert_equal(int(after1.get("holes_completed", 0)), 1, "one hole completed after first step")
	_assert_equal(int(after1.get("current_hole_number", 0)), 2, "round advances to hole 2")
	_assert_equal(int(after1.get("remaining_holes", -1)), 2, "two holes remain after first step")
	_assert_equal(after1.get("hole_results", []).size(), 1, "one hole result retained after first step")

	var result2: Dictionary = round.play_current_hole(golfer, 180202)
	_assert_true(bool(result2.get("finished", false)), "hole 2 finishes stepwise")
	_assert_true(bool(result2.get("recorded", false)), "hole 2 records stepwise")
	var after2: Dictionary = round.snapshot()
	_assert_equal(int(after2.get("holes_completed", 0)), 2, "two holes completed after second step")
	_assert_equal(int(after2.get("current_hole_number", 0)), 3, "round advances to hole 3")
	_assert_equal(int(after2.get("remaining_holes", -1)), 1, "one hole remains after second step")
	_assert_equal(after2.get("hole_results", []).size(), 2, "two hole results retained after second step")

	var result3: Dictionary = round.play_current_hole(golfer, 180203)
	_assert_true(bool(result3.get("finished", false)), "hole 3 finishes stepwise")
	_assert_true(bool(result3.get("recorded", false)), "hole 3 records stepwise")
	var final: Dictionary = round.snapshot()
	_assert_true(bool(final.get("round_finished", false)), "round finishes after third step")
	_assert_true(bool(final.get("complete", false)), "RoundState is complete after third step")
	_assert_equal(int(final.get("holes_completed", 0)), 3, "all holes completed stepwise")
	_assert_equal(int(final.get("remaining_holes", -1)), 0, "no holes remain")
	_assert_equal(final.get("hole_results", []).size(), 3, "all three hole results retained")
	_assert_equal(final.get("scorecard", []).size(), 3, "scorecard retains all three rows")
	_assert_equal(int(final.get("par_played", 0)), 12, "stepwise par played reconciles")

	var summed_strokes := int(result1.get("strokes", 0)) + int(result2.get("strokes", 0)) + int(result3.get("strokes", 0))
	_assert_equal(int(final.get("total_strokes", -1)), summed_strokes, "stepwise total strokes reconcile")
	_assert_equal(int(final.get("score_to_par", 999)), summed_strokes - 12, "stepwise score-to-par reconciles")

	var memory = golfer.get("memory")
	if memory != null:
		var attempts = int(memory.get("shots_attempted"))
		_assert_true(attempts >= summed_strokes, "same golfer memory persists across holes")

	print("STEPWISE_SUMMARY finished=%s holes=%d strokes=%d par=%d score_to_par=%+d" % [
		str(final.get("round_finished", false)),
		int(final.get("holes_completed", 0)),
		int(final.get("total_strokes", 0)),
		int(final.get("par_played", 0)),
		int(final.get("score_to_par", 0))
	])

	golfer.free()
	_finish()


func _build_course():
	var author = CourseAuthoringModel.new()
	author.configure_identity("poc18_stepwise", "POC-18 Stepwise Three")
	author.add_hole_definition(_build_straight_par4())
	author.add_hole_definition(_build_water_par3())
	author.add_hole_definition(_build_risk_reward_par5())
	return author.build_definition()


func _build_straight_par4():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc18_stepwise", 1, "Opening Drive", 4, 410.0)
	author.add_tee("back", "Back", Vector3(0, 0, 410), 410.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-18, -16, 18, 16))
	author.add_surface_region("fairway", "Fairway", "FAIRWAY", _rect(-32, 28, 32, 390))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, 400, 10, 420))
	return author.build_definition()


func _build_water_par3():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc18_stepwise", 2, "Carry the Water", 3, 168.0)
	author.add_tee("back", "Back", Vector3(0, 0, 168), 168.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-20, -15, 20, 16))
	author.add_surface_region("approach_rough", "Approach Rough", "ROUGH", _rect(-42, 16, 42, 55))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, 158, 10, 178))
	author.add_hazard("front_water", "Front Water", "WATER", _rect(-48, 55, 48, 118), 1, "lateral")
	return author.build_definition()


func _build_risk_reward_par5():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc18_stepwise", 3, "Split Decision", 5, 525.0)
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
	golfer.golfer_name = "POC18 Stepwise Golfer"
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


func _finish() -> void:
	if failures == 0:
		print("POC-18B AUTHORED ROUND STEPWISE PROGRESSION PASSED")
		quit(0)
	else:
		push_error("POC-18B AUTHORED ROUND STEPWISE PROGRESSION FAILED: %d" % failures)
		quit(1)

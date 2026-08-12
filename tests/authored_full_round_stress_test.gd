extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const CourseAuthoringModel = preload("res://simulation/course_authoring_model.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")

var failures: int = 0


func _init() -> void:
	print("POC-18D: full 18-hole authored round stress test")
	var course = _build_course()
	_assert_true(course != null, "18-hole authored course builds")
	if course == null:
		_finish()
		return

	_assert_equal(course.hole_count(), 18, "course contains 18 holes")
	_assert_equal(course.total_par(), 72, "course totals par 72")
	_assert_true(course.total_yardage("back") > 6500.0, "course has regulation-length back-tee yardage")

	var golfer = _build_golfer()
	var round = AutonomousRound.new(course, "back")
	var result: Dictionary = round.play_round(golfer, 181800)
	var hole_results: Array = result.get("hole_results", [])
	var scorecard: Array = result.get("scorecard", [])

	_assert_true(bool(result.get("round_finished", false)), "golfer completes all 18 authored holes")
	_assert_equal(int(result.get("holes_completed", 0)), 18, "all 18 holes are recorded")
	_assert_equal(int(result.get("remaining_holes", -1)), 0, "no holes remain")
	_assert_equal(hole_results.size(), 18, "18 hole results retained")
	_assert_equal(scorecard.size(), 18, "18 scorecard rows retained")
	_assert_equal(int(result.get("par_played", 0)), 72, "round par played reconciles to 72")

	var summed_strokes: int = 0
	var completed_rows: int = 0
	var par3_count: int = 0
	var par4_count: int = 0
	var par5_count: int = 0
	for index in range(hole_results.size()):
		var hole_result: Dictionary = hole_results[index]
		summed_strokes += int(hole_result.get("strokes", 0))
		_assert_true(bool(hole_result.get("finished", false)), "hole %d finishes" % (index + 1))
		_assert_true(bool(hole_result.get("recorded", false)), "hole %d records" % (index + 1))
		_assert_equal(int(hole_result.get("hole_number", 0)), index + 1, "hole %d preserves authored order" % (index + 1))
		var row: Dictionary = scorecard[index]
		if bool(row.get("completed", false)):
			completed_rows += 1
		match int(row.get("par", 0)):
			3:
				par3_count += 1
			4:
				par4_count += 1
			5:
				par5_count += 1

	_assert_equal(completed_rows, 18, "every scorecard row is complete")
	_assert_equal(par3_count, 4, "course retains four par 3s")
	_assert_equal(par4_count, 10, "course retains ten par 4s")
	_assert_equal(par5_count, 4, "course retains four par 5s")
	_assert_equal(int(result.get("total_strokes", -1)), summed_strokes, "18-hole total strokes reconcile")
	_assert_equal(int(result.get("score_to_par", 999)), summed_strokes - 72, "18-hole score-to-par reconciles")

	print("FULL_ROUND_SUMMARY finished=%s holes=%d strokes=%d par=%d score_to_par=%+d yardage=%.0f" % [
		str(result.get("round_finished", false)),
		int(result.get("holes_completed", 0)),
		int(result.get("total_strokes", 0)),
		int(result.get("par_played", 0)),
		int(result.get("score_to_par", 0)),
		course.total_yardage("back")
	])

	golfer.free()
	_finish()


func _build_course():
	var course_author = CourseAuthoringModel.new()
	course_author.configure_identity("poc18_full_round", "POC-18 Full Round")
	var pars := [4, 4, 3, 5, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4]
	var yardages := [420.0, 395.0, 175.0, 535.0, 445.0, 380.0, 160.0, 550.0, 410.0, 430.0, 405.0, 190.0, 525.0, 460.0, 400.0, 170.0, 545.0, 415.0]
	for index in range(18):
		var definition = _build_hole(index + 1, int(pars[index]), float(yardages[index]))
		if not course_author.add_hole_definition(definition):
			return null
	return course_author.build_definition()


func _build_hole(hole_number: int, par: int, yardage: float):
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc18_full_round", hole_number, "Hole %d" % hole_number, par, yardage)
	author.add_tee("back", "Back", Vector3(0, 0, yardage), yardage)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-20, -16, 20, 17))
	author.add_surface_region("fairway_%d" % hole_number, "Fairway", "FAIRWAY", _rect(-34, 24, 34, yardage - 20.0))
	author.add_surface_region("tee_%d" % hole_number, "Tee", "TEE", _rect(-10, yardage - 10.0, 10, yardage + 10.0))
	if hole_number in [3, 8, 12, 17]:
		var hazard_far: float = minf(yardage - 55.0, yardage * 0.62)
		var hazard_near: float = maxf(65.0, hazard_far - 45.0)
		author.add_hazard("water_%d" % hole_number, "Water", "WATER", _rect(-42, hazard_near, 42, hazard_far), 1, "lateral")
	return author.build_definition()


func _build_golfer() -> Node:
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.golfer_name = "POC18 Full Round Golfer"
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
		print("POC-18D FULL 18-HOLE AUTHORED ROUND PASSED")
		quit(0)
	else:
		push_error("POC-18D FULL 18-HOLE AUTHORED ROUND FAILED: %d" % failures)
		quit(1)

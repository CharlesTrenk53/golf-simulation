extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const CourseAuthoringModel = preload("res://simulation/course_authoring_model.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")

var failures: int = 0


func _init() -> void:
	print("POC-18E: authored 18-hole golfer profile comparison")
	var course = _build_course()
	_assert_true(course != null, "comparison course builds")
	if course == null:
		_finish()
		return

	var profiles := [
		GolferScript.GolferProfile.WILD_BILL,
		GolferScript.GolferProfile.RECKLESS_RICK,
		GolferScript.GolferProfile.CAREFUL_CARL
	]

	print("PROFILE_SCORE,profile,hole,par,strokes,score_to_par")
	for profile_id in profiles:
		var golfer = GolferScript.new()
		golfer.profile = profile_id
		golfer.apply_profile()
		var profile_name: String = golfer.golfer_name
		var round = AutonomousRound.new(course, "back")
		# Each profile receives the same base seed so the comparison starts from
		# the same stochastic sequence while still allowing profile behavior to
		# alter how that sequence is consumed during play.
		var result: Dictionary = round.play_round(golfer, 181850)
		var scorecard: Array = result.get("scorecard", [])

		_assert_true(bool(result.get("round_finished", false)), "%s completes 18 holes" % profile_name)
		_assert_equal(scorecard.size(), 18, "%s retains 18 scorecard rows" % profile_name)

		for row in scorecard:
			print("PROFILE_SCORE,%s,%d,%d,%d,%+d" % [
				profile_name,
				int(row.get("hole_number", 0)),
				int(row.get("par", 0)),
				int(row.get("strokes", 0)),
				int(row.get("score_to_par", 0))
			])

		print("PROFILE_SUMMARY,%s,strokes=%d,par=%d,score_to_par=%+d,water_balls=%d,aggressive_attempts=%d,aggressive_successes=%d,aggressive_failures=%d,shots_attempted=%d,successful_shots=%d" % [
			profile_name,
			int(result.get("total_strokes", 0)),
			int(result.get("par_played", 0)),
			int(result.get("score_to_par", 0)),
			golfer.water_balls,
			golfer.aggressive_attempts,
			golfer.aggressive_successes,
			golfer.aggressive_failures,
			golfer.shots_attempted,
			golfer.successful_shots
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
		print("POC-18E AUTHORED PROFILE ROUND COMPARISON PASSED")
		quit(0)
	else:
		push_error("POC-18E AUTHORED PROFILE ROUND COMPARISON FAILED: %d" % failures)
		quit(1)

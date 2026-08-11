extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")
const GolferScript = preload("res://scenes/golfer.gd")

var failures: int = 0


func _init() -> void:
	print("POC-12C: load proving course and golfer")
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		quit(1)
		return

	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	var golfer_instance_id: int = golfer.get_instance_id()

	var round = AutonomousRound.new(course, "default")
	_assert_true(round.round_state.current_hole_number() == 1, "round begins on hole 1")

	print("POC-12C: play autonomous three-hole round")
	var result: Dictionary = round.play_round(golfer, 42)
	var hole_results: Array = result.get("hole_results", [])

	_assert_true(golfer.get_instance_id() == golfer_instance_id, "same golfer instance survives the full round")
	_assert_true(hole_results.size() >= 1, "round produces at least one autonomous hole result")

	for index in range(hole_results.size()):
		var hole_result: Dictionary = hole_results[index]
		_assert_true(int(hole_result.get("hole_number", 0)) == index + 1, "hole results preserve course order")
		_assert_true(not hole_result.get("history", []).is_empty(), "each attempted hole contains autonomous shot history")
		if bool(hole_result.get("recorded", false)):
			_assert_true(bool(hole_result.get("finished", false)), "only genuinely finished holes are recorded")

	_assert_true(bool(result.get("round_finished", false)), "Careful Carl completes the three-hole proving round")
	_assert_true(not bool(result.get("stopped_on_unfinished_hole", true)), "round does not stop on an unfinished hole")
	_assert_true(int(result.get("holes_completed", 0)) == 3, "all three holes are recorded")
	_assert_true(int(result.get("remaining_holes", -1)) == 0, "no holes remain after completion")
	_assert_true(hole_results.size() == 3, "one autonomous result is produced per hole")
	_assert_true(result.get("scorecard", []).size() == 3, "completed round exposes three-row scorecard")
	_assert_true(int(result.get("total_strokes", 0)) > 0, "completed round has a cumulative stroke total")
	_assert_true(int(result.get("par_played", 0)) == 12, "completed round records all 12 par strokes")

	for hole_number in range(1, 4):
		_assert_true(round.round_state.score_for_hole(hole_number) > 0, "hole %d has a recorded score" % hole_number)

	golfer.free()

	if failures == 0:
		print("POC-12C AUTONOMOUS ROUND TESTS PASSED")
		quit(0)
	else:
		push_error("POC-12C AUTONOMOUS ROUND TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)

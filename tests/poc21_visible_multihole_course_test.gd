extends SceneTree

const StrategicCourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")
const GolferScript = preload("res://scenes/golfer.gd")
const PlayableCourseRuntime = preload("res://scenes/playable_course_runtime.gd")

var failures: int = 0


func _init() -> void:
	print("POC-21E: visible multi-hole course")
	var full_course = StrategicCourseFixture.new().build_course()
	_assert_true(full_course != null, "strategic authored course builds")
	if full_course == null:
		_finish()
		return

	# Use the first three authored holes to prove real hole-to-hole runtime
	# progression before the final full-18 visible-round stress test.
	var short_course = _first_three_hole_course(full_course)
	_assert_true(short_course != null, "three-hole authored course slice builds")
	if short_course == null:
		_finish()
		return

	var golfer := GolferScript.new()
	golfer.profile = GolferScript.GolferProfile.WILD_BILL
	golfer.apply_profile()
	get_root().add_child(golfer)

	var runtime := PlayableCourseRuntime.new()
	get_root().add_child(runtime)
	_assert_true(runtime.configure(short_course, golfer, "back", 4100), "visible course runtime configures")
	_assert_equal(runtime.active_hole_number, 1, "runtime begins on authored hole 1")

	var hole_one: Dictionary = runtime.play_current_hole(false)
	_assert_true(bool(hole_one.get("recorded", false)), "hole 1 completes and records")
	_assert_equal(runtime.active_hole_number, 2, "runtime transitions to authored hole 2 tee")
	_assert_vector_close(runtime.ball_visual.course_position, short_course.holes[1].tee_position("back"), "ball resets to authoritative hole 2 tee")
	_assert_vector_close(runtime.golfer_visual.course_position, short_course.holes[1].tee_position("back"), "golfer resets to authoritative hole 2 tee")

	var final: Dictionary = runtime.play_course(false)
	_assert_true(bool(final.get("round_finished", false)), "golfer completes visible three-hole course")
	_assert_equal(int(final.get("holes_completed", 0)), 3, "authoritative RoundState completes all three holes")
	_assert_equal(runtime.presented_holes.size(), 3, "all three holes receive visible presentation")

	var scorecard: Array = final.get("scorecard", [])
	_assert_equal(scorecard.size(), 3, "scorecard contains three completed holes")
	var stroke_sum := 0
	var par_sum := 0
	for row_value in scorecard:
		var row: Dictionary = row_value
		stroke_sum += int(row.get("strokes", 0))
		par_sum += int(row.get("par", 0))
	_assert_equal(int(final.get("total_strokes", 0)), stroke_sum, "visible course total matches authoritative scorecard")
	_assert_equal(int(final.get("par_played", 0)), par_sum, "visible course par matches authoritative scorecard")
	_assert_equal(int(final.get("score_to_par", 0)), stroke_sum - par_sum, "visible course score-to-par reconciles")

	for index in range(runtime.presented_holes.size()):
		var presented: Dictionary = runtime.presented_holes[index]
		_assert_true(bool(presented.get("finished", false)), "presented hole %d finished" % (index + 1))
		_assert_true(bool(presented.get("recorded", false)), "presented hole %d recorded" % (index + 1))
		_assert_equal(int(presented.get("shots_presented", 0)), int(presented.get("simulation_shots", 0)), "presented hole %d shows every authoritative shot" % (index + 1))
		_assert_vector_close(presented.get("visual_ball_position", Vector3.ZERO), presented.get("final_position", Vector3.ZERO), "presented hole %d ball finishes at authoritative lie" % (index + 1))
		_assert_vector_close(presented.get("visual_golfer_position", Vector3.ZERO), presented.get("final_position", Vector3.ZERO), "presented hole %d golfer finishes at authoritative lie" % (index + 1))

	print("POC21_MULTIHole_SUMMARY holes=%d strokes=%d par=%d score=%+d" % [
		int(final.get("holes_completed", 0)),
		int(final.get("total_strokes", 0)),
		int(final.get("par_played", 0)),
		int(final.get("score_to_par", 0))
	])

	runtime.queue_free()
	golfer.queue_free()
	_finish()


func _first_three_hole_course(full_course):
	var CourseAuthoringModel = preload("res://simulation/course_authoring_model.gd")
	var author = CourseAuthoringModel.new()
	author.configure_identity("poc21_three_hole_runtime", "POC-21 Three-Hole Runtime")
	for index in range(3):
		if not author.add_hole_definition(full_course.holes[index]):
			return null
	return author.build_definition()


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


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-21E VISIBLE MULTI-HOLE COURSE PASSED")
		quit(0)
	else:
		push_error("POC-21E VISIBLE MULTI-HOLE COURSE FAILED: %d" % failures)
		quit(1)

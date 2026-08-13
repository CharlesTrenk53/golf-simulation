extends SceneTree

const StrategicCourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")
const GolferScript = preload("res://scenes/golfer.gd")
const PlayableCourseRuntime = preload("res://scenes/playable_course_runtime.gd")

var failures: int = 0


func _init() -> void:
	print("POC-21F: full 18-hole visible runtime stress")
	var course = StrategicCourseFixture.new().build_course()
	_assert_true(course != null, "full strategic authored course builds")
	if course == null:
		_finish()
		return

	var golfer := GolferScript.new()
	golfer.profile = GolferScript.GolferProfile.WILD_BILL
	golfer.apply_profile()
	get_root().add_child(golfer)

	var runtime := PlayableCourseRuntime.new()
	get_root().add_child(runtime)
	_assert_true(runtime.configure(course, golfer, "back", 42100), "visible 18-hole runtime configures")

	var final: Dictionary = runtime.play_course(false)
	_assert_true(bool(final.get("round_finished", false)), "golfer completes all 18 visible holes")
	_assert_equal(int(final.get("holes_completed", 0)), 18, "authoritative RoundState completes 18 holes")
	_assert_equal(runtime.presented_holes.size(), 18, "all 18 holes receive visible presentation")

	var scorecard: Array = final.get("scorecard", [])
	_assert_equal(scorecard.size(), 18, "scorecard contains 18 completed holes")
	var stroke_sum := 0
	var par_sum := 0
	for row_value in scorecard:
		var row: Dictionary = row_value
		stroke_sum += int(row.get("strokes", 0))
		par_sum += int(row.get("par", 0))
	_assert_equal(int(final.get("total_strokes", 0)), stroke_sum, "visible 18-hole total matches authoritative scorecard")
	_assert_equal(int(final.get("par_played", 0)), par_sum, "visible 18-hole par matches authoritative scorecard")
	_assert_equal(int(final.get("score_to_par", 0)), stroke_sum - par_sum, "visible 18-hole score-to-par reconciles")

	var total_presented_shots := 0
	var total_simulation_shots := 0
	for index in range(runtime.presented_holes.size()):
		var presented: Dictionary = runtime.presented_holes[index]
		var hole_number := index + 1
		_assert_true(bool(presented.get("finished", false)), "presented hole %d finished" % hole_number)
		_assert_true(bool(presented.get("recorded", false)), "presented hole %d recorded" % hole_number)
		var shown := int(presented.get("shots_presented", 0))
		var simulated := int(presented.get("simulation_shots", 0))
		total_presented_shots += shown
		total_simulation_shots += simulated
		_assert_equal(shown, simulated, "presented hole %d shows every authoritative shot" % hole_number)
		_assert_vector_close(presented.get("visual_ball_position", Vector3.ZERO), presented.get("final_position", Vector3.ZERO), "presented hole %d ball finishes at authoritative lie" % hole_number)
		_assert_vector_close(presented.get("visual_golfer_position", Vector3.ZERO), presented.get("final_position", Vector3.ZERO), "presented hole %d golfer finishes at authoritative lie" % hole_number)

	_assert_equal(total_presented_shots, total_simulation_shots, "full-round visible shot count matches authoritative simulation history")
	_assert_equal(golfer.shots_attempted, total_simulation_shots, "golfer memory counts the same authoritative shot sequence exactly once")

	print("POC21_FULL_VISIBLE_ROUND_SUMMARY holes=%d strokes=%d par=%d score=%+d shots=%d" % [
		int(final.get("holes_completed", 0)),
		int(final.get("total_strokes", 0)),
		int(final.get("par_played", 0)),
		int(final.get("score_to_par", 0)),
		total_presented_shots
	])

	runtime.queue_free()
	golfer.queue_free()
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


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-21F FULL 18-HOLE VISIBLE RUNTIME PASSED")
		quit(0)
	else:
		push_error("POC-21F FULL 18-HOLE VISIBLE RUNTIME FAILED: %d" % failures)
		quit(1)

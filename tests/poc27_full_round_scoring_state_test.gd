extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const RoundState = preload("res://simulation/round_state.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27B: full-round state and scoring")

	var course = POC27Course.build()
	_assert_true(course != null, "18-hole course builds for round-state proof")
	if course == null:
		_finish()
		return

	var round_state = RoundState.new(course, "default")
	var opening: Dictionary = round_state.snapshot()
	_assert_equal_int(int(opening.get("holes_completed", -1)), 0, "new round starts with zero completed holes")
	_assert_equal_int(int(opening.get("current_hole_number", -1)), 1, "new round points at Hole 1")
	_assert_equal_string(str(opening.get("round_phase", "")), "NOT_STARTED", "new round exposes not-started phase")
	_assert_true(not bool(opening.get("round_started", true)), "new round is not marked started before first score")
	_assert_true(not bool(opening.get("turn_reached", true)), "new round has not reached the turn")

	var front_offsets: Array[int] = [0, 1, 0, -1, 1, 0, 0, 1, 0]
	var back_offsets: Array[int] = [-1, 0, 1, 0, 0, -1, 1, 0, 0]
	var expected_front_strokes: int = 0
	var expected_back_strokes: int = 0

	for hole_number in range(1, 10):
		var hole = course.hole_by_number(hole_number)
		var strokes: int = int(hole.par) + front_offsets[hole_number - 1]
		expected_front_strokes += strokes
		_assert_true(round_state.record_current_hole(strokes), "front-nine score records for Hole %d" % hole_number)

	var turn_snapshot: Dictionary = round_state.snapshot()
	_assert_equal_int(int(turn_snapshot.get("holes_completed", -1)), 9, "exactly nine holes are complete at the turn")
	_assert_equal_int(int(turn_snapshot.get("current_hole_number", -1)), 10, "round advances naturally to Hole 10")
	_assert_equal_string(str(turn_snapshot.get("round_phase", "")), "BACK_NINE", "round enters back-nine phase after Hole 9")
	_assert_true(bool(turn_snapshot.get("round_started", false)), "round is marked started after scoring begins")
	_assert_true(bool(turn_snapshot.get("turn_reached", false)), "round explicitly records reaching the turn")

	var front: Dictionary = turn_snapshot.get("front_nine", {})
	var back: Dictionary = turn_snapshot.get("back_nine", {})
	_assert_equal_int(int(front.get("holes_total", -1)), 9, "front-nine summary owns nine holes")
	_assert_equal_int(int(front.get("holes_completed", -1)), 9, "front-nine summary records all nine completed")
	_assert_equal_int(int(front.get("strokes", -1)), expected_front_strokes, "front-nine strokes are authoritative")
	_assert_equal_int(int(front.get("par_played", -1)), 36, "front-nine par derives from authored course")
	_assert_equal_int(int(front.get("score_to_par", -99)), 2, "front-nine score to par derives from strokes and par")
	_assert_true(bool(front.get("complete", false)), "front nine is explicitly complete")
	_assert_equal_int(int(back.get("holes_completed", -1)), 0, "back nine remains untouched at the turn")
	_assert_true(not bool(back.get("complete", true)), "back nine is not prematurely complete")

	var restored = RoundState.new(course, "default")
	_assert_true(restored.restore_snapshot(turn_snapshot), "turn snapshot restores through existing save contract")
	_assert_equal_int(restored.current_hole_number(), 10, "restored round resumes on Hole 10")
	_assert_equal_int(restored.front_nine_strokes(), expected_front_strokes, "restored round preserves front-nine total")
	_assert_equal_string(restored.round_phase(), "BACK_NINE", "restored round preserves back-nine phase")

	for hole_number in range(10, 19):
		var hole = course.hole_by_number(hole_number)
		var strokes: int = int(hole.par) + back_offsets[hole_number - 10]
		expected_back_strokes += strokes
		_assert_true(restored.record_current_hole(strokes), "back-nine score records for Hole %d" % hole_number)

	var finished: Dictionary = restored.snapshot()
	_assert_true(bool(finished.get("complete", false)), "round completes only after Hole 18 is recorded")
	_assert_true(bool(finished.get("round_finished", false)), "snapshot explicitly marks full round finished")
	_assert_equal_string(str(finished.get("round_phase", "")), "COMPLETE", "completed round exposes complete phase")
	_assert_equal_int(int(finished.get("holes_completed", -1)), 18, "all 18 holes are complete")
	_assert_equal_int(int(finished.get("remaining_holes", -1)), 0, "completed round has no remaining holes")
	_assert_equal_int(int(finished.get("par_played", -1)), 72, "full-round par derives from all 18 holes")
	_assert_equal_int(int(finished.get("total_strokes", -1)), expected_front_strokes + expected_back_strokes, "full-round strokes equal front plus back")
	_assert_equal_int(int(finished.get("score_to_par", -99)), 2, "full-round score to par remains authoritative")

	front = finished.get("front_nine", {})
	back = finished.get("back_nine", {})
	_assert_equal_int(int(front.get("strokes", -1)), expected_front_strokes, "finished scorecard retains front-nine total")
	_assert_equal_int(int(back.get("strokes", -1)), expected_back_strokes, "finished scorecard retains back-nine total")
	_assert_equal_int(int(back.get("par_played", -1)), 36, "back-nine par derives from authored course")
	_assert_equal_int(int(back.get("score_to_par", -99)), 0, "back-nine score to par derives independently")
	_assert_true(bool(front.get("complete", false)) and bool(back.get("complete", false)), "both nines are complete at round finish")

	var scorecard: Array = finished.get("scorecard", [])
	_assert_equal_int(scorecard.size(), 18, "finished round retains all 18 scorecard rows")
	var scorecard_complete: bool = true
	for row_value in scorecard:
		var row: Dictionary = row_value
		if not bool(row.get("completed", false)) or int(row.get("strokes", -1)) <= 0:
			scorecard_complete = false
	_assert_true(scorecard_complete, "every scorecard row contains a completed authoritative score")

	var restored_finished = RoundState.new(course, "default")
	_assert_true(restored_finished.restore_snapshot(finished), "finished 18-hole snapshot restores")
	_assert_true(restored_finished.complete, "restored finished round remains complete")
	_assert_equal_int(restored_finished.total_strokes(), expected_front_strokes + expected_back_strokes, "restored finished round preserves total strokes")
	_assert_equal_int(restored_finished.score_to_par(), 2, "restored finished round preserves score to par")

	print("POC27B_ROUND_STATE_SUMMARY front=%d back=%d total=%d to_par=%+d phase=%s" % [
		expected_front_strokes,
		expected_back_strokes,
		expected_front_strokes + expected_back_strokes,
		int(finished.get("score_to_par", 0)),
		str(finished.get("round_phase", ""))
	])
	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal_int(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%d expected=%d)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%d expected=%d)" % [label, actual, expected])


func _assert_equal_string(actual: String, expected: String, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-27B FULL-ROUND STATE AND SCORING PASSED")
		quit(0)
	else:
		push_error("POC-27B FULL-ROUND STATE AND SCORING FAILED: %d" % failures)
		quit(1)

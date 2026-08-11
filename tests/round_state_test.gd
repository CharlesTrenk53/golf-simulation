extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const RoundState = preload("res://simulation/round_state.gd")

var failures: int = 0


func _init() -> void:
	print("POC-12B: load proving course")
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "proving course loads")
	if course == null:
		quit(1)
		return

	var round = RoundState.new(course, "default")
	_assert_true(not round.complete, "new round starts active")
	_assert_true(round.current_hole_number() == 1, "round starts on hole 1")
	_assert_true(round.holes_completed() == 0, "no holes completed initially")
	_assert_true(round.total_strokes() == 0, "round starts at zero strokes")
	_assert_true(round.score_to_par() == 0, "round starts even to par")
	_assert_true(round.remaining_holes() == 3, "all proving holes remain initially")
	_assert_true(not round.record_current_hole(0), "zero-stroke hole score is rejected")

	print("POC-12B: record hole 1")
	_assert_true(round.record_current_hole(4), "hole 1 score records")
	_assert_true(round.score_for_hole(1) == 4, "hole 1 score is addressable")
	_assert_true(round.current_hole_number() == 2, "recording hole 1 advances to hole 2")
	_assert_true(round.total_strokes() == 4, "partial total follows completed holes")
	_assert_true(round.par_played() == 4, "partial par follows completed holes")
	_assert_true(round.score_to_par() == 0, "par on hole 1 leaves round even")
	_assert_true(round.holes_completed() == 1, "one hole completed after first score")

	print("POC-12B: record hole 2")
	_assert_true(round.record_current_hole(4), "hole 2 score records")
	_assert_true(round.current_hole_number() == 3, "recording hole 2 advances to hole 3")
	_assert_true(round.total_strokes() == 8, "two-hole total accumulates")
	_assert_true(round.par_played() == 7, "two-hole par accumulates")
	_assert_true(round.score_to_par() == 1, "bogey on par 3 moves round to plus one")

	print("POC-12B: finish round")
	_assert_true(round.record_current_hole(5), "hole 3 score records")
	_assert_true(round.complete, "final hole completes round")
	_assert_true(round.current_hole() == null, "completed round has no active hole")
	_assert_true(round.current_hole_number() == 0, "completed round exposes no current hole number")
	_assert_true(round.total_strokes() == 13, "final score totals all holes")
	_assert_true(round.par_played() == 12, "final par totals all holes")
	_assert_true(round.score_to_par() == 1, "final round score is plus one")
	_assert_true(round.remaining_holes() == 0, "completed round has no remaining holes")
	_assert_true(not round.record_current_hole(3), "completed round rejects additional scoring")

	var scorecard: Array = round.scorecard()
	_assert_true(scorecard.size() == 3, "scorecard contains every course hole")
	_assert_true(bool(scorecard[0].get("completed", false)), "scorecard marks completed holes")
	_assert_true(int(scorecard[1].get("score_to_par", 0)) == 1, "scorecard derives per-hole relation to par")
	_assert_true(int(scorecard[2].get("strokes", 0)) == 5, "scorecard preserves final-hole strokes")

	var snapshot: Dictionary = round.snapshot()
	_assert_true(bool(snapshot.get("complete", false)), "round snapshot reports completion")
	_assert_true(int(snapshot.get("total_strokes", 0)) == 13, "round snapshot reports final strokes")
	_assert_true(int(snapshot.get("score_to_par", 0)) == 1, "round snapshot reports final relation to par")

	if failures == 0:
		print("POC-12B ROUND STATE TESTS PASSED")
		quit(0)
	else:
		push_error("POC-12B ROUND STATE TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

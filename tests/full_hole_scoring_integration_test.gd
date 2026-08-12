extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const CourseContext = preload("res://simulation/course_context.gd")
const AutonomousHole = preload("res://simulation/autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-16A: full-hole scoring integration")
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.decision_variability = 0.0

	var context = _build_par4_context()
	var simulation = AutonomousHole.new()
	# POC-16A uses a literal 410-yard hole. Preserve legacy compact-distance defaults
	# elsewhere, but explicitly put both autonomous club-distance consumers into the
	# literal-yardage profile for this full-length integration run.
	simulation.bag.use_literal_yardages(true)
	simulation.option_generator.bag.use_literal_yardages(true)
	var result: Dictionary = simulation.play_hole(
		golfer,
		Vector3(0, 0, 410),
		Vector3.ZERO,
		[],
		4,
		1601,
		context
	)

	_print_trace(result)
	_validate_scoring(result)

	golfer.free()
	if failures == 0:
		print("POC-16A FULL-HOLE SCORING INTEGRATION PASSED")
		quit(0)
	else:
		push_error("POC-16A FULL-HOLE SCORING INTEGRATION FAILED: %d" % failures)
		quit(1)


func _build_par4_context() -> RefCounted:
	var context = CourseContext.new()
	# Full-length scoring requires an actual cup outcome. A close approach must
	# transition to putting rather than being auto-holed by legacy proximity rules.
	context.explicit_hole_out_required = true
	# Straight, representative par-4 used to prove the entire tee-to-cup chain.
	# The first POC-16 slice intentionally avoids forced hazards so failures expose
	# integration problems rather than course-design difficulty.
	context.add_zone("Fairway", CourseContext.Surface.FAIRWAY, Vector3(0, 0, 205), Vector2(20, 195))
	context.add_zone("Tee", CourseContext.Surface.TEE, Vector3(0, 0, 410), Vector2(10, 8))
	context.add_zone("Green", CourseContext.Surface.GREEN, Vector3(0, 0, 0), Vector2(16, 14))
	return context


func _print_trace(result: Dictionary) -> void:
	print("=== SHOT-BY-SHOT TRACE ===")
	print("shot,surface_before,option,club,outcome,surface_after,remaining_yards,decision_quality,execution_quality")
	for shot in result.get("history", []):
		print("%d,%s,%s,%s,%s,%s,%.2f,%s,%s" % [
			int(shot.get("shot_number", 0)),
			str(shot.get("surface_before", "")),
			str(shot.get("option", "")),
			str(shot.get("club_name", "")),
			str(shot.get("outcome", "")),
			str(shot.get("surface_after", "")),
			float(shot.get("remaining_after_shot", 0.0)),
			str(shot.get("decision_quality", "")),
			str(shot.get("execution_quality", ""))
		])
	print("=== SCORE SUMMARY ===")
	print("finished=%s strokes=%d par=%d score_to_par=%+d final_surface=%s remaining=%.3f" % [
		str(result.get("finished", false)),
		int(result.get("strokes", 0)),
		int(result.get("par", 0)),
		int(result.get("strokes", 0)) - int(result.get("par", 0)),
		str(result.get("final_surface", "")),
		float(result.get("remaining_distance", 0.0))
	])
	print("")


func _validate_scoring(result: Dictionary) -> void:
	var history: Array = result.get("history", [])
	_assert_true(bool(result.get("finished", false)), "representative par-4 finishes in the cup")
	_assert_true(not history.is_empty(), "hole produces a shot history")
	_assert_true(int(result.get("strokes", 0)) <= 12, "hole finishes within scoring safety limit")
	_assert_true(float(result.get("remaining_distance", 999.0)) <= 0.01, "finished hole ends at cup position")

	var expected_strokes: int = history.size()
	var saw_tee: bool = false
	var saw_putt: bool = false
	var final_was_holed_putt: bool = false
	for shot in history:
		expected_strokes += int(shot.get("penalty_strokes", 0))
		if str(shot.get("surface_before", "")) == "TEE":
			saw_tee = true
		if int(shot.get("shot_type", -1)) == 3:
			saw_putt = true
	var last_shot: Dictionary = history.back() if not history.is_empty() else {}
	final_was_holed_putt = int(last_shot.get("shot_type", -1)) == 3 and bool(last_shot.get("putting_holed", false))

	_assert_true(int(result.get("strokes", -1)) == expected_strokes, "final score reconciles played shots plus penalties")
	_assert_true(saw_tee, "trace begins from a tee context")
	_assert_true(saw_putt, "full-hole chain reaches autonomous putting")
	_assert_true(final_was_holed_putt, "final stroke is a holed putt")


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const CourseAuthoringModel = preload("res://simulation/course_authoring_model.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")

var failures: int = 0


func _init() -> void:
	print("POC-18C: authored round persistence")
	var course = _build_course()
	_assert_true(course != null, "authored course builds")
	if course == null:
		_finish()
		return

	var golfer = _build_golfer()
	var original = AutonomousRound.new(course, "back")
	var first: Dictionary = original.play_current_hole(golfer, 180201)
	_assert_true(bool(first.get("finished", false)), "hole 1 finishes before save")
	_assert_true(bool(first.get("recorded", false)), "hole 1 records before save")

	var saved: Dictionary = original.snapshot()
	_assert_equal(int(saved.get("holes_completed", 0)), 1, "snapshot records one completed hole")
	_assert_equal(int(saved.get("current_hole_number", 0)), 2, "snapshot points to hole 2")
	_assert_equal(int(saved.get("total_strokes", 0)), int(first.get("strokes", 0)), "snapshot preserves running strokes")

	var restored = AutonomousRound.new(course, "back")
	_assert_true(restored.restore_snapshot(saved), "round restores from snapshot")
	var restored_snapshot: Dictionary = restored.snapshot()
	_assert_equal(int(restored_snapshot.get("holes_completed", 0)), 1, "restored round keeps completed-hole count")
	_assert_equal(int(restored_snapshot.get("current_hole_number", 0)), 2, "restored round resumes on hole 2")
	_assert_equal(int(restored_snapshot.get("total_strokes", 0)), int(first.get("strokes", 0)), "restored round keeps running strokes")
	_assert_equal(restored_snapshot.get("hole_results", []).size(), 1, "restored round keeps prior hole result")

	var final: Dictionary = restored.play_round(golfer, 180202)
	_assert_true(bool(final.get("round_finished", false)), "restored round finishes")
	_assert_equal(int(final.get("holes_completed", 0)), 3, "restored round completes all holes")
	_assert_equal(int(final.get("remaining_holes", -1)), 0, "restored round has no remaining holes")
	_assert_equal(final.get("hole_results", []).size(), 3, "restored round retains all hole results")
	_assert_equal(final.get("scorecard", []).size(), 3, "restored round retains full scorecard")
	_assert_equal(int(final.get("par_played", 0)), 12, "restored round par reconciles")

	var summed: int = 0
	for result in final.get("hole_results", []):
		summed += int(result.get("strokes", 0))
	_assert_equal(int(final.get("total_strokes", -1)), summed, "restored total strokes reconcile")
	_assert_equal(int(final.get("score_to_par", 999)), summed - 12, "restored score-to-par reconciles")

	var wrong_course = _build_other_course()
	var rejected = AutonomousRound.new(wrong_course, "back")
	_assert_true(not rejected.restore_snapshot(saved), "snapshot rejects different course identity")

	print("PERSISTENCE_SUMMARY finished=%s holes=%d strokes=%d par=%d score_to_par=%+d" % [
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
	author.configure_identity("poc18_persistence", "POC-18 Persistence Three")
	author.add_hole_definition(_build_hole(1, "Opening Drive", 4, 410.0))
	author.add_hole_definition(_build_hole(2, "Middle Iron", 3, 168.0))
	author.add_hole_definition(_build_hole(3, "Closing Five", 5, 525.0))
	return author.build_definition()


func _build_other_course():
	var author = CourseAuthoringModel.new()
	author.configure_identity("poc18_other", "Other Course")
	author.add_hole_definition(_build_hole_for_course("poc18_other", 1, "Only Hole", 4, 410.0))
	return author.build_definition()


func _build_hole(number: int, name: String, par_value: int, yardage: float):
	return _build_hole_for_course("poc18_persistence", number, name, par_value, yardage)


func _build_hole_for_course(course_id: String, number: int, name: String, par_value: int, yardage: float):
	var author = HoleAuthoringModel.new()
	author.configure_identity(course_id, number, name, par_value, yardage)
	author.add_tee("back", "Back", Vector3(0, 0, yardage), yardage)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-20, -16, 20, 16))
	author.add_surface_region("fairway", "Fairway", "FAIRWAY", _rect(-35, 25, 35, yardage - 15.0))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, yardage - 10.0, 10, yardage + 10.0))
	return author.build_definition()


func _build_golfer() -> Node:
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.golfer_name = "POC18 Persistence Golfer"
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
		print("POC-18C AUTHORED ROUND PERSISTENCE PASSED")
		quit(0)
	else:
		push_error("POC-18C AUTHORED ROUND PERSISTENCE FAILED: %d" % failures)
		quit(1)

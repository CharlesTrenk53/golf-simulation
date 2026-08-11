extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleDefinition = preload("res://simulation/hole_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-13G: same golfer, different hole geometry")
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.set_meta("course_management", 88.0)

	var decision_point: Dictionary = _decision_for("res://data/courses/poc11_test_hole.json", golfer, 1301)
	var open_fairway: Dictionary = _decision_for("res://data/courses/poc13_open_fairway_hole.json", golfer, 1302)
	var split_decision: Dictionary = _decision_for("res://data/courses/poc13_center_hazard_hole.json", golfer, 1303)

	_assert_true(not decision_point.is_empty(), "Decision Point produces a strategy decision")
	_assert_true(not open_fairway.is_empty(), "open fairway produces a strategy decision")
	_assert_true(not split_decision.is_empty(), "center-hazard hole produces a strategy decision")

	if not open_fairway.is_empty():
		_assert_true(str(open_fairway.get("club_id", "")) == "DRIVER", "wide-open hole rewards maximum useful tee distance")
		_assert_true(str(open_fairway.get("target_variant", "")) == "CENTER", "wide-open symmetric hole prefers center aim")

	if not split_decision.is_empty():
		_assert_true(str(split_decision.get("target_variant", "")) != "CENTER", "center bunker forces Carl away from center aim")
		_assert_true(str(split_decision.get("expected_surface", "")) != "BUNKER", "chosen split-fairway target avoids the center bunker landing surface")

	if not open_fairway.is_empty() and not split_decision.is_empty():
		var open_signature := "%s/%s" % [str(open_fairway.get("club_id", "")), str(open_fairway.get("target_variant", ""))]
		var split_signature := "%s/%s" % [str(split_decision.get("club_id", "")), str(split_decision.get("target_variant", ""))]
		_assert_true(open_signature != split_signature, "same golfer changes club-target decision when geometry changes")

	if not decision_point.is_empty() and not split_decision.is_empty():
		_assert_true(str(decision_point.get("target_variant", "")) != str(split_decision.get("target_variant", "")), "Decision Point and center-hazard layouts do not collapse to the same aiming lane")

	golfer.free()
	if failures == 0:
		print("POC-13G LAYOUT VARIATION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-13G LAYOUT VARIATION TESTS FAILED: %d" % failures)
		quit(1)


func _decision_for(path: String, golfer: Node, seed_value: int) -> Dictionary:
	var hole = HoleDefinition.load_json(path)
	_assert_true(hole != null, "%s loads" % path.get_file())
	if hole == null:
		return {}
	var playable = DataDefinedAutonomousHole.new(hole)
	var state = playable.create_state(seed_value)
	var decision: Dictionary = playable.choose_course_strategy(golfer, state)
	return decision.get("chosen", {})


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)

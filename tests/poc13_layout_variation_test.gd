extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleDefinition = preload("res://simulation/hole_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0

const LAYOUTS := {
	"Decision Point": "res://data/courses/poc11_test_hole.json",
	"Green Light": "res://data/courses/poc13_open_fairway_hole.json",
	"Split Decision": "res://data/courses/poc13_center_hazard_hole.json",
	"Trouble Right": "res://data/courses/poc13_right_trouble_hole.json",
	"Thread the Needle": "res://data/courses/poc13_narrow_fairway_hole.json"
}


func _init() -> void:
	print("POC-13G/H: course geometry + golfer strategy matrix")

	var carl = GolferScript.new()
	carl.profile = carl.GolferProfile.CAREFUL_CARL
	carl.apply_profile()
	carl.set_meta("course_management", 88.0)

	var rick = GolferScript.new()
	rick.profile = rick.GolferProfile.RECKLESS_RICK
	rick.apply_profile()
	# Keep the comparison deterministic and make the intended strategic contrast
	# explicit: Carl reads scoring consequences very well; Rick underprices them.
	rick.set_meta("course_management", 45.0)

	var carl_decisions: Dictionary = _decision_matrix(carl, 1300)
	var rick_decisions: Dictionary = _decision_matrix(rick, 2300)

	var decision_point: Dictionary = carl_decisions.get("Decision Point", {})
	var open_fairway: Dictionary = carl_decisions.get("Green Light", {})
	var split_decision: Dictionary = carl_decisions.get("Split Decision", {})
	var trouble_right: Dictionary = carl_decisions.get("Trouble Right", {})
	var narrow: Dictionary = carl_decisions.get("Thread the Needle", {})

	if not open_fairway.is_empty():
		_assert_true(str(open_fairway.get("club_id", "")) == "DRIVER", "wide-open hole rewards maximum useful tee distance")
		_assert_true(str(open_fairway.get("target_variant", "")) == "CENTER", "wide-open symmetric hole prefers center aim")

	if not split_decision.is_empty():
		_assert_true(str(split_decision.get("target_variant", "")) != "CENTER", "center bunker forces Carl away from center aim")
		_assert_true(str(split_decision.get("expected_surface", "")) != "BUNKER", "chosen split-fairway target avoids the center bunker landing surface")

	if not trouble_right.is_empty():
		var right_lane := str(trouble_right.get("target_variant", ""))
		_assert_true(right_lane != "RIGHT" and right_lane != "FAR_RIGHT", "right-side water pushes Carl away from right aiming lanes")
		_assert_true(str(trouble_right.get("expected_surface", "")) != "WATER", "chosen Trouble Right target avoids water")

	if not open_fairway.is_empty() and not split_decision.is_empty():
		_assert_true(_signature(open_fairway) != _signature(split_decision), "same golfer changes club-target decision when center geometry changes")

	if not decision_point.is_empty() and not split_decision.is_empty():
		_assert_true(str(decision_point.get("target_variant", "")) != str(split_decision.get("target_variant", "")), "Decision Point and center-hazard layouts do not collapse to the same aiming lane")

	if not open_fairway.is_empty() and not narrow.is_empty():
		_assert_true(_signature(open_fairway) != _signature(narrow), "narrow corridor changes Carl's tee strategy from the wide-open baseline")

	var golfer_differences: int = 0
	for layout_name in LAYOUTS.keys():
		var carl_choice: Dictionary = carl_decisions.get(layout_name, {})
		var rick_choice: Dictionary = rick_decisions.get(layout_name, {})
		if carl_choice.is_empty() or rick_choice.is_empty():
			continue
		var carl_signature := _signature(carl_choice)
		var rick_signature := _signature(rick_choice)
		print("MATRIX: ", layout_name, " | Carl ", carl_signature, " | Rick ", rick_signature)
		if carl_signature != rick_signature:
			golfer_differences += 1

	_assert_true(golfer_differences >= 1, "same geometry produces at least one different Carl/Rick club-target decision")

	carl.free()
	rick.free()
	if failures == 0:
		print("POC-13G/H COURSE STRATEGY MATRIX TESTS PASSED")
		quit(0)
	else:
		push_error("POC-13G/H COURSE STRATEGY MATRIX TESTS FAILED: %d" % failures)
		quit(1)


func _decision_matrix(golfer: Node, seed_base: int) -> Dictionary:
	var result: Dictionary = {}
	var offset: int = 0
	for layout_name in LAYOUTS.keys():
		var path: String = str(LAYOUTS[layout_name])
		var choice: Dictionary = _decision_for(path, golfer, seed_base + offset)
		result[layout_name] = choice
		offset += 1
	return result


func _decision_for(path: String, golfer: Node, seed_value: int) -> Dictionary:
	var hole = HoleDefinition.load_json(path)
	_assert_true(hole != null, "%s loads for %s" % [path.get_file(), golfer.golfer_name])
	if hole == null:
		return {}
	var playable = DataDefinedAutonomousHole.new(hole)
	var state = playable.create_state(seed_value)
	var decision: Dictionary = playable.choose_course_strategy(golfer, state)
	var chosen: Dictionary = decision.get("chosen", {})
	_assert_true(not chosen.is_empty(), "%s produces a strategy decision for %s" % [path.get_file(), golfer.golfer_name])
	return chosen


func _signature(choice: Dictionary) -> String:
	return "%s/%s" % [str(choice.get("club_id", "")), str(choice.get("target_variant", ""))]


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)

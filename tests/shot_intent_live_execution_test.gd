extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleDefinition = preload("res://simulation/hole_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-14F: selected shot intent drives live autonomous execution")
	var hole = HoleDefinition.load_json("res://data/courses/poc11_test_hole.json")
	_assert_true(hole != null, "Decision Point loads")
	if hole == null:
		quit(1)
		return

	var playable = DataDefinedAutonomousHole.new(hole)
	var state = playable.create_state(14141)
	var golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	golfer.set_meta("course_management", 90.0)

	var preview: Dictionary = playable.choose_course_strategy(golfer, state)
	var choice: Dictionary = preview.get("chosen", {})
	var chosen_intent: Dictionary = choice.get("chosen_intent", {})
	var predicted: Dictionary = choice.get("chosen_predicted_flight", {})
	var proficiency: Dictionary = choice.get("chosen_proficiency", {})
	_assert_true(not chosen_intent.is_empty(), "autonomous club/target choice now includes a shot intent")
	_assert_true(not predicted.is_empty(), "selected intent carries predicted flight")
	_assert_true(not proficiency.is_empty(), "selected intent carries golfer proficiency")

	var result: Dictionary = playable.play_step(golfer, state)
	_assert_true(not result.is_empty(), "live shot executes")
	if not result.is_empty():
		var signature: String = str(chosen_intent.get("signature", ""))
		_assert_true(str(result.get("intent_signature", "")) == signature, "live execution preserves the selected intent signature")
		_assert_true(str(result.get("shot_execution", {}).get("intent_signature", "")) == signature, "stochastic realization came from the selected intent")
		_assert_true(result.has("predicted_flight"), "live result retains theoretical predicted flight")
		_assert_true(result.has("shotmaking_proficiency"), "live result retains golfer-specific proficiency")
		_assert_true(result.has("execution_seed"), "live intent execution records deterministic simulation seed")
		_assert_true(Vector3(result.get("landing_position", Vector3.ZERO)) != Vector3(result.get("start_position", Vector3.ZERO)), "intent-driven execution advances the ball in course space")
		_assert_true(float(result.get("shot_execution", {}).get("actual_total_yards", 0.0)) > 0.0, "live result records realized total distance")
		_assert_true(str(result.get("club_id", "")) == str(choice.get("club_id", "")), "intent execution does not change the selected club")

	golfer.free()
	if failures == 0:
		print("POC-14F LIVE SHOT INTENT EXECUTION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-14F LIVE SHOT INTENT EXECUTION TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")

var failures: int = 0


func _init() -> void:
	print("POC-18F: aggressive strategy memory propagation")
	var hole = _build_risk_reward_hole()
	_assert_true(hole != null, "risk-reward hole builds")
	if hole == null:
		_finish()
		return

	var golfer = GolferScript.new()
	golfer.profile = GolferScript.GolferProfile.RECKLESS_RICK
	golfer.apply_profile()
	var playable = DataDefinedAutonomousHole.new(hole, "back")
	var state = playable.create_state(181902)

	var selection: Dictionary = playable.choose_course_strategy(golfer, state)
	var chosen: Dictionary = selection.get("chosen", {})
	_assert_true(not chosen.is_empty(), "Rick receives a strategy choice")
	_assert_true(bool(chosen.get("is_aggressive", false)), "Rick selects the aggressive strategy")

	var attempts_before: int = golfer.aggressive_attempts
	var total_before: int = golfer.shots_attempted
	var result: Dictionary = playable.play_step(golfer, state)

	_assert_true(not result.is_empty(), "strategy shot executes")
	_assert_true(bool(result.get("was_aggressive", false)), "execution result preserves aggressive posture")
	_assert_true(bool(result.get("selected_option", {}).get("is_aggressive", false)), "selected option remains aggressive in shot history")
	_assert_equal(golfer.shots_attempted, total_before + 1, "golfer records the executed shot")
	_assert_equal(golfer.aggressive_attempts, attempts_before + 1, "golfer memory records aggressive attempt")

	golfer.free()
	_finish()


func _build_risk_reward_hole():
	var author = HoleAuthoringModel.new()
	author.configure_identity("poc18_memory", 1, "Temptation Memory", 4, 430.0)
	author.add_tee("back", "Back", Vector3(0, 0, 430), 430.0)
	author.set_pin(Vector3(0, 0, 0))
	author.set_green(_rect(-21, -16, 21, 18))
	author.add_surface_region("bailout_fairway", "Bailout Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-34, 256), Vector2(-18, 256), Vector2(-18, 266), Vector2(-34, 266)
	]))
	author.add_surface_region("attack_fairway", "Attack Fairway", "FAIRWAY", PackedVector2Array([
		Vector2(-10, 205), Vector2(10, 205), Vector2(10, 247), Vector2(-10, 247)
	]))
	author.add_surface_region("approach_fairway", "Approach Fairway", "FAIRWAY", _rect(-34, 24, 34, 205))
	author.add_surface_region("tee", "Tee", "TEE", _rect(-10, 420, 10, 440))
	author.add_hazard("decision_lake", "Decision Lake", "WATER", PackedVector2Array([
		Vector2(10.0, 205), Vector2(56, 205), Vector2(56, 275), Vector2(10.0, 275)
	]), 1, "lateral")
	author.add_hazard("bailout_bunker", "Bailout Bunker", "BUNKER", PackedVector2Array([
		Vector2(-38, 252), Vector2(-30, 252), Vector2(-30, 270), Vector2(-38, 270)
	]), 1, "standard")
	return author.build_definition()


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
		print("PASS: %s (actual=%s expected=%s)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, actual, expected])


func _finish() -> void:
	if failures == 0:
		print("POC-18F AGGRESSIVE STRATEGY MEMORY PROPAGATION PASSED")
		quit(0)
	else:
		push_error("POC-18F AGGRESSIVE STRATEGY MEMORY PROPAGATION FAILED: %d" % failures)
		quit(1)

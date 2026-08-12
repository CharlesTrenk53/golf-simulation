extends SceneTree

const ShotIntentExecutionBridge = preload("res://simulation/shot_intent_execution_bridge.gd")

var failures: int = 0


func _init() -> void:
	print("POC-14F: shot intent execution bridge")
	var bridge = ShotIntentExecutionBridge.new()
	var start := Vector3(0.0, 0.0, 0.0)
	var target := Vector3(0.0, 0.0, -200.0)
	var predicted := {
		"intent_signature": "NORMAL|DRAW|FULL|STOCK",
		"carry_yards": 190.0,
		"rollout_yards": 12.0,
		"curve_yards": -10.0,
		"apex_factor": 1.0,
		"dispersion_yards": 8.0
	}
	var proficiency := {
		"execution_reliability": 0.82,
		"expected_dispersion_multiplier": 0.95
	}

	var first: Dictionary = bridge.execute(start, target, predicted, proficiency, 4411)
	var repeat: Dictionary = bridge.execute(start, target, predicted, proficiency, 4411)
	var changed: Dictionary = bridge.execute(start, target, predicted, proficiency, 4412)

	_assert_true(first["landing_position"].is_equal_approx(repeat["landing_position"]), "same seed maps to same course landing position")
	_assert_true(not first["landing_position"].is_equal_approx(changed["landing_position"]), "different seed changes the course landing position")
	_assert_true(str(first.get("intent_signature", "")) == "NORMAL|DRAW|FULL|STOCK", "execution bridge preserves shot-intent identity")
	_assert_true(float(first.get("forward_yards", 0.0)) > 0.0, "execution bridge advances the ball forward")
	_assert_true(absf(float(first.get("target_line_lateral_yards", 0.0))) > 0.01, "shape plus execution creates lateral movement")
	_assert_true(first["landing_position"].distance_to(start) > 100.0, "course-space landing reflects realized shot distance")
	_assert_true(is_finite(float(first.get("target_miss_distance", INF))), "target miss distance remains finite")

	if failures == 0:
		print("POC-14F SHOT INTENT EXECUTION BRIDGE TESTS PASSED")
		quit(0)
	else:
		push_error("POC-14F SHOT INTENT EXECUTION BRIDGE TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

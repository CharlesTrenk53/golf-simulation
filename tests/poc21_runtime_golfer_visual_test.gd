extends SceneTree

const Golfer = preload("res://scenes/golfer.gd")
const RuntimeGolferVisual = preload("res://scenes/runtime_golfer_visual.gd")

var failures: int = 0


func _init() -> void:
	print("POC-21C: visible autonomous golfer")

	var golfer := Golfer.new()
	golfer.profile = golfer.GolferProfile.CAREFUL_CARL
	golfer.apply_profile()
	var baseline_risk: float = golfer.risk_tolerance
	var baseline_confidence: float = golfer.confidence

	var visual := RuntimeGolferVisual.new()
	get_root().add_child(visual)
	_assert_true(visual.configure_golfer(golfer), "visual accepts authoritative golfer")
	_assert_equal(str(visual.get_meta("golfer_name", "")), "Careful Carl", "visual identifies current golfer")

	var tee := Vector3(0.0, 0.0, 420.0)
	visual.place_at_ball(tee)
	_assert_vector_close(visual.get_meta("course_position", Vector3.ZERO), tee, "golfer begins at authoritative ball position")
	_assert_vector_close(Vector3(visual.position.x, 0.0, visual.position.z), tee, "visual X/Z matches course-space ball coordinates")

	var fairway_result := {
		"shot_number": 1,
		"option": "CENTER",
		"club_id": "DRIVER",
		"club_name": "Driver",
		"start_position": tee,
		"target_position": Vector3(4.0, 0.0, 180.0),
		"landing_position": Vector3(6.0, 0.0, 168.0),
		"relief_position": Vector3(6.0, 0.0, 168.0),
		"outcome": "SUCCESS",
		"intent_signature": "DRIVER|CENTER|STANDARD"
	}
	_assert_true(visual.observe_shot_result(fairway_result), "golfer visual accepts simulation shot context")
	var context: Dictionary = visual.get_meta("last_shot_context", {})
	_assert_equal(str(context.get("club_id", "")), "DRIVER", "visual exposes selected club")
	_assert_equal(str(context.get("intent_signature", "")), "DRIVER|CENTER|STANDARD", "visual exposes shot intent signature")
	_assert_true(visual.move_to_resolved_ball(fairway_result), "golfer follows resolved ball after shot")
	_assert_vector_close(visual.get_meta("course_position", Vector3.ZERO), fairway_result["landing_position"], "golfer arrives at authoritative landing position")

	var water_result := {
		"shot_number": 2,
		"option": "ATTACK",
		"club_id": "4_IRON",
		"club_name": "4 Iron",
		"start_position": fairway_result["landing_position"],
		"target_position": Vector3(20.0, 0.0, 40.0),
		"landing_position": Vector3(30.0, 0.0, 82.0),
		"relief_position": Vector3(18.0, 0.0, 96.0),
		"outcome": "WATER"
	}
	_assert_true(visual.move_to_resolved_ball(water_result), "golfer can follow simulation-resolved penalty position")
	_assert_vector_close(visual.get_meta("course_position", Vector3.ZERO), water_result["relief_position"], "golfer follows relief, not water landing point")

	_assert_close(golfer.risk_tolerance, baseline_risk, "visual projection does not rewrite golfer risk tolerance")
	_assert_close(golfer.confidence, baseline_confidence, "visual projection does not rewrite golfer confidence")
	_assert_true(not visual.observe_shot_result({"landing_position": Vector3.ZERO}), "visual rejects incomplete shot context")

	print("POC21_GOLFER_SUMMARY golfer=%s final=%s club=%s" % [
		golfer.golfer_name,
		str(visual.get_meta("course_position", Vector3.ZERO)),
		str(visual.last_shot_context.get("club_id", ""))
	])

	visual.queue_free()
	golfer.free()
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


func _assert_close(actual: float, expected: float, label: String) -> void:
	if abs(actual - expected) <= 0.001:
		print("PASS: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.3f expected=%.3f)" % [label, actual, expected])


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-21C VISIBLE AUTONOMOUS GOLFER PASSED")
		quit(0)
	else:
		push_error("POC-21C VISIBLE AUTONOMOUS GOLFER FAILED: %d" % failures)
		quit(1)

extends SceneTree

const RuntimeBallVisual = preload("res://scenes/runtime_ball_visual.gd")

var failures: int = 0
var ball = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27 kickoff: putts roll along the ground")
	ball = RuntimeBallVisual.new()
	get_root().add_child(ball)

	var putt := {
		"shot_type": 3,
		"club_id": "PUTTER",
		"start_position": Vector3(2.0, 0.0, 10.0),
		"target_position": Vector3(2.0, 0.0, 22.0),
		"landing_position": Vector3(3.0, 0.0, 20.0),
		# A bogus apex is included deliberately. A putt must ignore generic
		# airborne presentation even if flight-shaped metadata is present.
		"shot_execution": {"apex_height_yards": 14.0},
		"putting": {"rolled_distance_feet": 30.0}
	}
	_assert_true(ball.present_shot(putt, true), "putt presentation begins")
	_assert_equal(str(ball.get_meta("trajectory_kind", "")), "GROUND_ROLL", "putt is classified as ground roll")
	ball.set_flight_progress(0.5)
	var putt_midpoint: Vector3 = putt["start_position"].lerp(putt["landing_position"], 0.5)
	_assert_near(ball.position.y, putt_midpoint.y + ball.ball_radius, 0.0001, "putt midpoint stays on ground instead of rising into an arc")
	_assert_near(ball.position.x, putt_midpoint.x, 0.0001, "putt follows authoritative lateral roll")
	_assert_near(ball.position.z, putt_midpoint.z, 0.0001, "putt follows authoritative forward roll")
	ball.set_flight_progress(1.0)
	_assert_vector_near(ball.course_position, putt["landing_position"], 0.0001, "putt still finishes at exact authoritative landing")

	var full_shot := {
		"shot_type": 0,
		"club_id": "DRIVER",
		"start_position": Vector3(0.0, 0.0, 0.0),
		"target_position": Vector3(0.0, 0.0, 220.0),
		"landing_position": Vector3(5.0, 0.0, 215.0),
		"shot_execution": {"apex_height_yards": 18.0}
	}
	_assert_true(ball.present_shot(full_shot, true), "full-shot presentation begins")
	_assert_equal(str(ball.get_meta("trajectory_kind", "")), "AIRBORNE", "non-putt retains airborne presentation")
	ball.set_flight_progress(0.5)
	_assert_near(ball.position.y, ball.ball_radius + 18.0, 0.0001, "full shot retains resolved apex arc")
	ball.set_flight_progress(1.0)
	_assert_vector_near(ball.course_position, full_shot["landing_position"], 0.0001, "full shot still finishes at authoritative landing")

	var putter_fallback := {
		"club_id": "putter",
		"start_position": Vector3.ZERO,
		"landing_position": Vector3(0.0, 0.0, 5.0)
	}
	_assert_true(ball.present_shot(putter_fallback, true), "putter result without shot-type metadata still presents")
	_assert_equal(str(ball.get_meta("trajectory_kind", "")), "GROUND_ROLL", "putter identity safely falls back to ground roll")

	print("POC27_PUTT_ROLL_SUMMARY putt_mid_y=%.3f full_mid_y=%.3f" % [
		putt_midpoint.y + ball.ball_radius,
		18.0 + ball.ball_radius
	])
	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual: String, expected: String, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, actual, expected])


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if abs(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.4f expected=%.4f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.4f expected=%.4f)" % [label, actual, expected])


func _assert_vector_near(actual: Vector3, expected: Vector3, tolerance: float, label: String) -> void:
	if actual.distance_to(expected) <= tolerance:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if ball != null and is_instance_valid(ball):
		ball.queue_free()
	if failures == 0:
		print("POC-27 PUTT GROUND-ROLL PRESENTATION PASSED")
		quit(0)
	else:
		push_error("POC-27 PUTT GROUND-ROLL PRESENTATION FAILED: %d" % failures)
		quit(1)

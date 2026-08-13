extends SceneTree

const RuntimeBallVisual = preload("res://scenes/runtime_ball_visual.gd")

var failures: int = 0


func _init() -> void:
	print("POC-21B: runtime ball representation")
	var ball = RuntimeBallVisual.new()
	get_root().add_child(ball)
	await process_frame

	var start := Vector3(0.0, 0.0, 420.0)
	var target := Vector3(8.0, 0.0, 155.0)
	var landing := Vector3(5.0, 0.0, 162.0)
	var result := {
		"start_position": start,
		"target_position": target,
		"landing_position": landing,
		"relief_position": landing,
		"shot_execution": {"apex_height_yards": 12.0}
	}

	_assert_true(ball.present_shot(result, true), "ball accepts authoritative shot result")
	_assert_vector_close(ball.course_position, start, "flight begins at simulation start position")
	_assert_true(ball.is_flying, "ball enters visual flight state")

	ball.set_flight_progress(0.5)
	var midpoint := start.lerp(landing, 0.5)
	_assert_vector_close(Vector3(ball.course_position.x, 0.0, ball.course_position.z), Vector3(midpoint.x, 0.0, midpoint.z), "mid-flight horizontal position interpolates between simulation endpoints")
	_assert_true(ball.position.y > ball.ball_radius, "mid-flight representation has a visible arc")

	ball.set_flight_progress(1.0)
	_assert_true(not ball.is_flying, "visual flight completes")
	_assert_vector_close(ball.course_position, landing, "ball finishes exactly at simulation landing position")
	_assert_vector_close(ball.get_meta("course_position", Vector3.ZERO), landing, "ball metadata preserves authoritative landing position")

	var water_landing := Vector3(32.0, 0.0, 220.0)
	var relief := Vector3(18.0, 0.0, 235.0)
	var water_result := {
		"start_position": landing,
		"target_position": Vector3(28.0, 0.0, 205.0),
		"landing_position": water_landing,
		"outcome": "WATER",
		"relief_position": relief
	}
	_assert_true(ball.present_shot(water_result, false), "ball accepts resolved water shot")
	_assert_vector_close(ball.course_position, water_landing, "water shot is first displayed at authoritative landing point")
	_assert_true(ball.has_relief, "ball remembers simulation relief separately from flight")
	ball.apply_simulation_relief()
	_assert_vector_close(ball.course_position, relief, "ball moves to simulation-provided relief position only when relief is applied")

	var invalid_result := {"target_position": Vector3.ZERO}
	_assert_true(not ball.present_shot(invalid_result), "ball rejects shot result without authoritative endpoints")

	print("POC21_BALL_SUMMARY start=%s landing=%s relief=%s" % [str(start), str(landing), str(relief)])
	ball.queue_free()
	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_vector_close(actual: Vector3, expected: Vector3, label: String) -> void:
	if actual.distance_to(expected) <= 0.001:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-21B RUNTIME BALL REPRESENTATION PASSED")
		quit(0)
	else:
		push_error("POC-21B RUNTIME BALL REPRESENTATION FAILED: %d" % failures)
		quit(1)

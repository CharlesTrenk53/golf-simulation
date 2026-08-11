extends SceneTree

const DecisionPointScene = preload("res://scenes/decision_point_demo.tscn")

var failures: int = 0


func _init() -> void:
	print("POC-11D/E: instantiate Decision Point visual demo")
	var demo = DecisionPointScene.instantiate()
	demo.autoplay = false
	root.add_child(demo)
	await process_frame

	_assert_true(demo.hole_definition != null, "visual demo loads authoritative hole definition")
	_assert_true(demo.state != null, "visual demo creates autonomous course state")
	_assert_true(demo.golfer_logic != null, "visual demo creates autonomous golfer")
	_assert_true(demo.get_node_or_null("RoughBase") != null, "visual demo renders rough base")
	_assert_true(demo.get_node_or_null("fairway_main") != null, "visual demo renders fairway polygon")
	_assert_true(demo.get_node_or_null("water_left") != null, "visual demo renders water polygon")
	_assert_true(demo.get_node_or_null("right_fairway_bunker") != null, "visual demo renders bunker polygon")
	_assert_true(demo.get_node_or_null("Green") != null, "visual demo renders green polygon")
	_assert_true(demo.get_node_or_null("Pin") != null, "visual demo renders pin")
	_assert_true(demo.ball_visual != null, "visual demo creates ball")
	_assert_true(demo.golfer_visual != null, "visual demo creates golfer marker")

	if demo.state != null and demo.golfer_logic != null and demo.simulation != null:
		var start_position: Vector3 = demo.state.ball_position
		var result: Dictionary = demo.simulation.play_step(demo.golfer_logic, demo.state)
		_assert_true(not result.is_empty(), "visual demo golfer can take autonomous shot")
		_assert_true(demo.state.ball_position != start_position, "visual demo shot advances ball state")

	demo.queue_free()

	if failures == 0:
		print("POC-11D/E DECISION POINT VISUAL DEMO TESTS PASSED")
		quit(0)
	else:
		push_error("POC-11D/E DECISION POINT VISUAL DEMO TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)

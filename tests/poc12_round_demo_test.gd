extends SceneTree

const DemoScript = preload("res://scenes/poc12_round_demo.gd")

var failures: int = 0


func _init() -> void:
	var demo = DemoScript.new()
	demo.autoplay = false
	root.add_child(demo)
	await process_frame

	_assert_true(demo.course != null, "watchable demo loads data-defined proving course")
	_assert_true(demo.round_state != null, "watchable demo owns persistent round state")
	_assert_true(demo.golfer_logic != null, "watchable demo owns one persistent golfer")
	_assert_true(demo.course.hole_count() == 3, "watchable demo sees all three course holes")
	_assert_true(demo.round_state.current_hole_number() == 1, "watchable demo begins on hole 1")
	_assert_true(not demo.round_state.complete, "watchable demo begins with round active")

	var golfer_instance_id: int = demo.golfer_logic.get_instance_id()
	for hole_number in [1, 2, 3]:
		var hole = demo.course.hole_by_number(hole_number)
		_assert_true(hole != null, "course exposes hole %d to visual scene" % hole_number)
		if hole != null:
			demo._render_hole(hole)
			_assert_true(demo.hole_visuals != null, "hole %d builds replaceable visual container" % hole_number)
			_assert_true(demo.hole_visuals.get_child_count() > 0, "hole %d creates visible geometry" % hole_number)
		_assert_true(demo.golfer_logic.get_instance_id() == golfer_instance_id, "golfer persists while hole %d visuals change" % hole_number)

	var score_text: String = demo._score_to_par_text(0)
	_assert_true(score_text == "E", "even-par scoreboard formatting is stable")
	_assert_true(demo._score_to_par_text(2) == "+2", "over-par scoreboard formatting is stable")
	_assert_true(demo._score_to_par_text(-1) == "-1", "under-par scoreboard formatting is stable")

	demo.queue_free()
	await process_frame

	if failures == 0:
		print("POC-12D WATCHABLE ROUND DEMO TESTS PASSED")
		quit(0)
	else:
		push_error("POC-12D WATCHABLE ROUND DEMO TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)

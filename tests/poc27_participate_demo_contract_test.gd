extends SceneTree

const DEMO_SCENE := preload("res://scenes/poc27_participate_demo.tscn")

var failures: int = 0
var demo = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27 MANUAL GATE: 18-hole participate demo contract")
	demo = DEMO_SCENE.instantiate()
	get_root().add_child(demo)

	_assert_true(demo != null, "POC-27 participate scene instantiates")
	_assert_true(bool(demo.initialized), "POC-27 participate demo initializes")
	if demo == null or not bool(demo.initialized):
		_finish()
		return

	_assert_true(demo.controller != null and demo.controller.course != null, "demo owns ordinary living-course authority")
	_assert_equal_int(demo.controller.course.hole_count(), 18, "manual gate launches complete 18-hole course")
	_assert_equal_int(demo.controller.living_course.population.group_count(), 4, "manual gate launches four ordinary groups")

	var expected_sizes := {
		"group_1": 4,
		"group_2": 2,
		"group_3": 2,
		"group_4": 2
	}
	for group_id in expected_sizes.keys():
		var group = demo.controller.living_course.population.group_by_id(group_id)
		_assert_true(group != null, "%s exists in manual living-course population" % group_id)
		if group != null:
			_assert_equal_int(group.member_count(), int(expected_sizes[group_id]), "%s has intended group size" % group_id)

	_assert_equal_int(int(demo.controller.group_controls["group_1"].get("human_member_index", -1)), 0, "Group 1 member 0 is human-controlled through ordinary group config")
	for group_id in ["group_2", "group_3", "group_4"]:
		_assert_equal_int(int(demo.controller.group_controls[group_id].get("human_member_index", 99)), -1, "%s remains fully autonomous" % group_id)

	_assert_true(demo.population_view != null, "manual demo owns spectator population view")
	_assert_equal_int(demo.population_view.group_visuals.size(), 4, "all four living groups receive persistent presentation visuals")
	_assert_true(demo.session != null and bool(demo.session.started), "participate session starts normally")
	_assert_equal_int(demo.controller.traffic.group_hole("group_1"), 1, "player group releases onto Hole 1")
	_assert_equal_int(demo.controller.traffic.group_hole("group_2"), 0, "first follower begins safely off Hole 1")
	_assert_equal_int(demo.controller.traffic.group_hole("group_3"), 0, "second follower begins in tee queue")
	_assert_equal_int(demo.controller.traffic.group_hole("group_4"), 0, "third follower begins in tee queue")
	_assert_equal_str(demo.focus_controller.selected_group_id(), "group_1", "camera/HUD focus begins on player group")
	_assert_true(demo.get_node_or_null("ShotDispersionPreview") != null, "model-derived shot dispersion preview remains attached")
	_assert_true(not demo._physical_round_complete(), "manual demo begins with a live unfinished 18-hole round")

	_assert_true(demo.select_group("group_4"), "manual observer can jump to fourth living group")
	_assert_equal_str(demo.focus_controller.selected_group_id(), "group_4", "four-group focus selection works")
	_assert_true(demo.select_group("group_1"), "manual observer can return to player group")
	_assert_equal_str(demo.focus_controller.selected_group_id(), "group_1", "player focus restores cleanly")

	print("POC27_MANUAL_DEMO_SUMMARY holes=%d groups=%d golfers=10 player_group_size=4 autonomous_groups=3" % [
		demo.controller.course.hole_count(),
		demo.controller.living_course.population.group_count()
	])
	_finish()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal_int(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%d expected=%d)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%d expected=%d)" % [label, actual, expected])


func _assert_equal_str(actual: String, expected: String, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, actual, expected])


func _finish() -> void:
	if demo != null and is_instance_valid(demo):
		demo.queue_free()
	if failures == 0:
		print("POC-27 18-HOLE PARTICIPATE DEMO CONTRACT PASSED")
		quit(0)
	else:
		push_error("POC-27 18-HOLE PARTICIPATE DEMO CONTRACT FAILED: %d" % failures)
		quit(1)

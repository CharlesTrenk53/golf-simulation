extends SceneTree

const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
const PlayerWorldHub = preload("res://simulation/player_world_hub.gd")
const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-29A: persistent world hub foundation")

	var unconfigured_hub = PlayerWorldHub.new()
	_assert_true(not unconfigured_hub.configure(null), "hub rejects missing persistent session")
	var empty_context: Dictionary = unconfigured_hub.context()
	_assert_true(not bool(empty_context.get("configured", true)), "unconfigured hub reports no authority")
	_assert_true(not bool(empty_context.get("can_choose_activity", true)), "unconfigured hub cannot launch activities")

	var course = POC27Course.build()
	_assert_true(course != null and course.hole_count() == 18, "18-hole living course builds")
	if course == null:
		_finish()
		return

	var player = Golfer.new()
	player.profile = Golfer.GolferProfile.CAREFUL_CARL
	player.apply_profile()
	get_root().add_child(player)
	created_nodes.append(player)
	var player_id: int = player.get_instance_id()
	var starting_driving: float = float(player.driving)

	var persistent = PlayerWorldSession.new()
	persistent.name = "POC29PersistentWorld"
	get_root().add_child(persistent)
	created_nodes.append(persistent)
	_assert_true(persistent.configure(player, course, 21, 10000.0), "persistent world session configures")
	var controller_id: int = persistent.controller.get_instance_id()

	var hub = PlayerWorldHub.new()
	_assert_true(hub.configure(persistent), "world hub binds to existing persistent session")
	_assert_true(hub.world_session == persistent, "hub references exact persistent session instead of copying it")
	_assert_true(player.get_parent() == persistent, "persistent session remains golfer owner")

	var world_context: Dictionary = hub.context()
	_assert_equal_str(str(world_context.get("state", "")), PlayerWorldHub.STATE_WORLD, "idle session projects WORLD hub state")
	_assert_true(bool(world_context.get("can_choose_activity", false)), "idle world allows activity selection")
	_assert_equal_str(str(world_context.get("active_activity_type", "")), PlayerWorldHub.ACTIVITY_NONE, "idle hub reports no active activity")
	_assert_equal_int(int(world_context.get("golfer_instance_id", 0)), player_id, "hub exposes exact persistent golfer identity")
	_assert_equal_int(int(world_context.get("controller_instance_id", 0)), controller_id, "hub exposes exact living-world controller identity")
	_assert_equal_int(int(world_context.get("day", -1)), 21, "hub exposes persistent world day")
	_assert_near(float(world_context.get("world_time_seconds", 0.0)), 10000.0, 0.0001, "hub exposes persistent world clock")
	_assert_equal_int(int(world_context.get("population", {}).get("group_count", -1)), 0, "empty living course is represented factually")
	_assert_near(float(world_context.get("abilities", {}).get("driving", -1.0)), starting_driving, 0.0001, "hub reads golfer ability without creating a profile copy")

	var partner = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	var entered: Dictionary = persistent.enter_round("player_group", [partner], "default", 1, 29101)
	_assert_true(bool(entered.get("entered", false)), "player round enters through existing POC-28 authority")
	var auto_a = _new_golfer(Golfer.GolferProfile.RECKLESS_RICK)
	var auto_b = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	_assert_true(persistent.add_world_group("other_group", [auto_a, auto_b], "default", 29201), "autonomous group joins same living world")

	var activity_context: Dictionary = hub.context()
	_assert_equal_str(str(activity_context.get("state", "")), PlayerWorldHub.STATE_ACTIVITY, "active round projects ACTIVITY hub state")
	_assert_true(not bool(activity_context.get("can_choose_activity", true)), "hub cannot launch a second activity while one is active")
	_assert_equal_str(str(activity_context.get("active_activity_type", "")), "ROUND", "hub identifies active round factually")
	_assert_equal_int(int(activity_context.get("golfer_instance_id", 0)), player_id, "activity projection keeps exact golfer identity")
	_assert_equal_int(int(activity_context.get("controller_instance_id", 0)), controller_id, "activity projection keeps exact controller identity")
	_assert_equal_int(int(activity_context.get("population", {}).get("group_count", -1)), 2, "hub reads current living-course population")
	_assert_equal_int(int(activity_context.get("population", {}).get("golfer_count", -1)), 4, "hub reads current living-course golfer count")
	_assert_equal_str(str(activity_context.get("active_round", {}).get("group_id", "")), "player_group", "hub projects current round metadata from persistent session")

	persistent.advance_world_time(120.0)
	var advanced_context: Dictionary = hub.context()
	_assert_true(float(advanced_context.get("world_time_seconds", 0.0)) >= 10120.0, "hub reads live world-clock changes without reconfiguration")
	_assert_equal_int(int(advanced_context.get("golfer_instance_id", 0)), player_id, "golfer identity survives live hub refresh")
	_assert_equal_int(int(advanced_context.get("controller_instance_id", 0)), controller_id, "controller identity survives live hub refresh")
	_assert_true(hub.world_session == persistent, "hub remains a view over the same world session after activity entry")

	print("POC29A_WORLD_HUB_SUMMARY golfer_id=%d controller_id=%d state=%s groups=%d world_time=%.1f" % [
		player_id,
		controller_id,
		str(advanced_context.get("state", "")),
		int(advanced_context.get("population", {}).get("group_count", 0)),
		float(advanced_context.get("world_time_seconds", 0.0))
	])
	_finish()


func _new_golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	created_nodes.append(golfer)
	return golfer


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


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if abs(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])


func _finish() -> void:
	for node in created_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("POC-29A PERSISTENT WORLD HUB FOUNDATION PASSED")
		quit(0)
	else:
		push_error("POC-29A PERSISTENT WORLD HUB FOUNDATION FAILED: %d" % failures)
		quit(1)

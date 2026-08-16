extends SceneTree

const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
const PlayerWorldHub = preload("res://simulation/player_world_hub.gd")
const PlayerActivityContract = preload("res://simulation/player_activity_contract.gd")
const PlayerActivityLauncher = preload("res://simulation/player_activity_launcher.gd")
const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-29C: play-round activity launch")
	var course = POC27Course.build()
	_assert_true(course != null and course.hole_count() == 18, "18-hole living course builds")
	if course == null:
		_finish()
		return

	var player = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var persistent = PlayerWorldSession.new()
	persistent.name = "PersistentPlayerWorldSession"
	get_root().add_child(persistent)
	created_nodes.append(persistent)
	_assert_true(persistent.configure(player, course, 30, 18000.0), "persistent world session configures")

	var hub = PlayerWorldHub.new()
	_assert_true(hub.configure(persistent), "world hub configures over persistent session")
	var original_player_id: int = player.get_instance_id()
	var original_controller_id: int = persistent.controller.get_instance_id()
	var original_world_time: float = persistent.world_time_seconds

	var partner_a = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	var partner_b = _new_golfer(Golfer.GolferProfile.RECKLESS_RICK)
	var selected: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_ROUND, {
		"group_id": "hub_player_group",
		"other_golfers": [partner_a, partner_b],
		"tee_id": "default",
		"player_member_index": 1,
		"seed_base": 29101
	})
	_assert_true(bool(selected.get("accepted", false)), "hub accepts valid round selection")
	_assert_equal_str(str(selected.get("activity_type", "")), PlayerActivityContract.ACTIVITY_ROUND, "selection remains canonical ROUND")
	_assert_equal_int(persistent.controller.living_course.population.group_count(), 0, "selection alone still does not mutate course population")
	_assert_near(persistent.world_time_seconds, original_world_time, 0.0001, "selection alone does not advance world time")

	var launched: Dictionary = hub.launch_selected_activity(selected)
	_assert_true(bool(launched.get("launched", false)), "accepted ROUND selection launches")
	_assert_equal_str(str(launched.get("activity_type", "")), PlayerActivityContract.ACTIVITY_ROUND, "launcher reports ROUND activity")
	_assert_equal_str(str(launched.get("reason", "unexpected")), "", "successful launch has no rejection reason")
	var entry: Dictionary = launched.get("entry", {})
	_assert_true(bool(entry.get("entered", false)), "round launcher delegates to ordinary PlayerWorldSession entry")
	_assert_equal_str(str(entry.get("group_id", "")), "hub_player_group", "launcher preserves requested group id")
	_assert_equal_int(int(entry.get("player_member_index", -1)), 1, "launcher preserves requested player group slot")
	_assert_equal_int(int(entry.get("member_count", 0)), 3, "launcher creates intended ordinary threesome")
	_assert_equal_int(int(entry.get("golfer_instance_id", 0)), original_player_id, "launcher uses exact persistent golfer")

	var group = persistent.controller.living_course.population.group_by_id("hub_player_group")
	_assert_true(group != null, "hub-launched player group exists in ordinary course population")
	if group != null:
		_assert_equal_int(group.member_count(), 3, "ordinary group retains all selected members")
		_assert_true(group.golfers[1] == player, "persistent player occupies selected ordinary group slot")
		_assert_equal_str(str(group.status), "WAITING", "round launch enters normal tee queue without auto-release")
	_assert_equal_int(persistent.controller.get_instance_id(), original_controller_id, "round launch preserves exact living-world controller")
	_assert_equal_int(player.get_instance_id(), original_player_id, "round launch preserves exact golfer identity")
	_assert_near(persistent.world_time_seconds, original_world_time, 0.0001, "round launch itself does not advance world clock")
	_assert_equal_int(persistent.controller.traffic.group_hole("hub_player_group"), 0, "round launch does not bypass tee-release traffic authority")

	var queue: Array[String] = persistent.controller.living_course.start_sequencer.waiting_group_ids()
	_assert_equal_int(queue.size(), 1, "hub-launched round joins ordinary tee queue")
	if queue.size() == 1:
		_assert_equal_str(queue[0], "hub_player_group", "hub-launched group is queued by normal sequencer")
	_assert_equal_int(int(persistent.controller.group_controls["hub_player_group"].get("human_member_index", -1)), 1, "existing mixed-group contract owns human slot")

	var context: Dictionary = hub.context()
	_assert_equal_str(str(context.get("state", "")), PlayerWorldHub.STATE_ACTIVITY, "hub immediately reflects active round after launch")
	_assert_equal_str(str(context.get("active_activity_type", "")), PlayerActivityContract.ACTIVITY_ROUND, "hub projects active ROUND from persistent session")
	_assert_true(not bool(context.get("can_choose_activity", true)), "hub blocks another activity while launched round is active")
	_assert_equal_int(int(context.get("golfer_instance_id", 0)), original_player_id, "hub projection keeps same golfer after launch")
	_assert_equal_int(int(context.get("controller_instance_id", 0)), original_controller_id, "hub projection keeps same controller after launch")

	var second_launch: Dictionary = hub.launch_selected_activity(selected)
	_assert_true(not bool(second_launch.get("launched", true)), "stale accepted selection cannot launch a second round")
	_assert_equal_str(str(second_launch.get("reason", "")), PlayerActivityContract.REASON_ACTIVITY_ALREADY_ACTIVE, "authoritative session rejects stale second launch")
	_assert_equal_int(persistent.controller.living_course.population.group_count(), 1, "rejected stale launch cannot duplicate course population")

	var rejected_selection: Dictionary = {
		"accepted": false,
		"activity_type": PlayerActivityContract.ACTIVITY_ROUND,
		"reason": "TEST_REJECTION",
		"options": {}
	}
	var rejected_launch: Dictionary = hub.launch_selected_activity(rejected_selection)
	_assert_true(not bool(rejected_launch.get("launched", true)), "launcher refuses unaccepted selection")
	_assert_equal_str(str(rejected_launch.get("reason", "")), PlayerActivityLauncher.REASON_SELECTION_NOT_ACCEPTED, "unaccepted selection has explicit launcher rejection")

	# POC-29D will implement practice mutation. For 29C, accepted PRACTICE intent must
	# remain explicit rather than accidentally falling through the round launcher.
	var standalone_session = PlayerWorldSession.new()
	standalone_session.name = "StandalonePersistentSession"
	get_root().add_child(standalone_session)
	created_nodes.append(standalone_session)
	var practice_player = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	_assert_true(standalone_session.configure(practice_player, course, 30, 18000.0), "second idle session configures for unsupported-activity check")
	var practice_hub = PlayerWorldHub.new()
	_assert_true(practice_hub.configure(standalone_session), "second hub configures")
	var practice_selection: Dictionary = practice_hub.select_activity(PlayerActivityContract.ACTIVITY_PRACTICE, {"practice_type": "PUTTING"})
	_assert_true(bool(practice_selection.get("accepted", false)), "practice intent remains selectable under shared contract")
	var practice_launch: Dictionary = practice_hub.launch_selected_activity(practice_selection)
	_assert_true(not bool(practice_launch.get("launched", true)), "29C launcher does not fake practice activity")
	_assert_equal_str(str(practice_launch.get("reason", "")), PlayerActivityLauncher.REASON_ACTIVITY_NOT_IMPLEMENTED, "unimplemented practice launch is explicit")
	_assert_true(standalone_session.active_round.is_empty(), "unimplemented practice cannot mutate round state")

	var release: Dictionary = persistent.release_next_group()
	_assert_true(bool(release.get("released", false)), "hub-launched group later releases through normal living-course authority")
	_assert_equal_str(str(release.get("group_id", "")), "hub_player_group", "normal release starts the hub-launched group")
	_assert_equal_int(persistent.controller.traffic.group_hole("hub_player_group"), 1, "traffic authority places released group on Hole 1")
	_assert_equal_int(player.get_instance_id(), original_player_id, "golfer identity remains stable through normal release")
	_assert_equal_int(persistent.controller.get_instance_id(), original_controller_id, "controller identity remains stable through normal release")

	print("POC29C_ROUND_LAUNCH_SUMMARY golfer_id=%d controller_id=%d group=%s slot=%d world_time=%.1f traffic_hole=%d" % [
		original_player_id,
		original_controller_id,
		str(entry.get("group_id", "")),
		int(entry.get("player_member_index", -1)),
		persistent.world_time_seconds,
		persistent.controller.traffic.group_hole("hub_player_group")
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
		print("POC-29C PLAY-ROUND ACTIVITY LAUNCH PASSED")
		quit(0)
	else:
		push_error("POC-29C PLAY-ROUND ACTIVITY LAUNCH FAILED: %d" % failures)
		quit(1)

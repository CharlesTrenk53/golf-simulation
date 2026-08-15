extends SceneTree

const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-28A/B/C: persistent player world-session contract")
	var course = POC27Course.build()
	_assert_true(course != null and course.hole_count() == 18, "18-hole living course builds")
	if course == null:
		_finish()
		return

	# The player begins under a disposable scene owner. Configuring the persistent
	# world session must adopt the exact same Node rather than cloning/rebuilding it.
	var disposable_scene = Node.new()
	disposable_scene.name = "DisposableActivityScene"
	get_root().add_child(disposable_scene)
	created_nodes.append(disposable_scene)

	var player = Golfer.new()
	player.profile = Golfer.GolferProfile.CAREFUL_CARL
	player.apply_profile()
	player.shots_attempted = 7
	player.successful_shots = 5
	disposable_scene.add_child(player)
	var original_player_id: int = player.get_instance_id()
	var original_driving: float = float(player.driving)
	var original_memory_attempts: int = int(player.shots_attempted)

	var persistent = PlayerWorldSession.new()
	persistent.name = "PersistentPlayerWorldSession"
	get_root().add_child(persistent)
	created_nodes.append(persistent)
	_assert_true(persistent.configure(player, course, 12, 3600.0), "persistent player/world session configures")
	_assert_true(persistent.player_golfer == player, "session owns exact original golfer object")
	_assert_equal_int(persistent.player_golfer.get_instance_id(), original_player_id, "player identity is preserved across ownership transfer")
	_assert_true(player.get_parent() == persistent, "persistent session adopts player out of disposable scene")
	_assert_near(float(player.driving), original_driving, 0.0001, "golfer ability survives scene transfer")
	_assert_equal_int(int(player.shots_attempted), original_memory_attempts, "golfer memory survives scene transfer")

	disposable_scene.queue_free()
	created_nodes.erase(disposable_scene)
	await process_frame
	_assert_true(is_instance_valid(player), "player survives disposal of previous activity scene")
	_assert_true(player.get_parent() == persistent, "player remains owned by persistent world after scene disposal")

	var partner_a = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	var partner_b = _new_golfer(Golfer.GolferProfile.RECKLESS_RICK)
	var entered: Dictionary = persistent.enter_round("player_group", [partner_a, partner_b], "default", 2, 28101)
	_assert_true(bool(entered.get("entered", false)), "player enters an ordinary three-person group")
	_assert_equal_int(int(entered.get("player_member_index", -1)), 2, "player may occupy a non-special group slot")
	_assert_equal_int(int(entered.get("golfer_instance_id", 0)), original_player_id, "round entry uses exact persistent golfer instance")

	var player_group = persistent.controller.living_course.population.group_by_id("player_group")
	_assert_true(player_group != null, "ordinary player group exists in living-course population")
	if player_group != null:
		_assert_equal_int(player_group.member_count(), 3, "ordinary group retains intended membership")
		_assert_true(player_group.golfers[2] == player, "ordinary GolferGroup contains exact persistent player object")
		_assert_equal_int(player_group.golfers[2].get_instance_id(), original_player_id, "group does not clone persistent player")
	_assert_equal_int(int(persistent.controller.group_controls["player_group"].get("human_member_index", -1)), 2, "existing mixed-group contract designates player slot as human")

	var auto_a = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var auto_b = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	_assert_true(persistent.add_world_group("other_group", [auto_a, auto_b], "default", 28201), "autonomous group joins same persistent world")
	var queue: Array[String] = persistent.controller.living_course.start_sequencer.waiting_group_ids()
	_assert_equal_int(queue.size(), 2, "player group and autonomous group share ordinary tee queue")
	if queue.size() == 2:
		_assert_equal_str(queue[0], "player_group", "player group obeys insertion-order tee queue")
		_assert_equal_str(queue[1], "other_group", "autonomous group queues normally behind player group")

	var release: Dictionary = persistent.release_next_group()
	_assert_true(bool(release.get("released", false)), "player group releases through normal living-course authority")
	_assert_equal_str(str(release.get("group_id", "")), "player_group", "ordinary FIFO release starts player group")
	_assert_equal_int(persistent.controller.traffic.group_hole("player_group"), 1, "player group occupies Hole 1 through normal traffic authority")

	var context: Dictionary = persistent.player_round_context()
	_assert_equal_str(str(context.get("activity_type", "")), "ROUND", "round context identifies active round")
	_assert_equal_str(str(context.get("status", "")), "PLAYING", "round context reflects ordinary group playing status")
	_assert_equal_int(int(context.get("hole_number", 0)), 1, "round context derives current hole from RoundState")
	_assert_true(int(context.get("par", 0)) > 0, "round context exposes authoritative hole par")
	_assert_true(float(context.get("yardage", 0.0)) > 0.0, "round context exposes selected-tee yardage")
	_assert_equal_int(int(context.get("holes_completed", -1)), 0, "new round context starts with zero completed holes")
	_assert_equal_int(int(context.get("total_strokes", -1)), 0, "new round context starts with zero strokes")
	_assert_equal_int(context.get("scorecard", []).size(), 18, "round context exposes complete 18-hole scorecard")
	_assert_equal_int(int(context.get("traffic_hole_number", 0)), 1, "round context exposes real traffic occupancy")
	_assert_equal_int(int(context.get("day", -1)), 12, "persistent world day survives round entry")
	_assert_near(float(context.get("world_time_seconds", 0.0)), 3600.0, 0.0001, "persistent world time survives round entry")

	var initial_round_state = persistent.player_round_state()
	_assert_true(initial_round_state != null, "player receives ordinary disposable RoundState")
	var initial_round_state_id: int = initial_round_state.get_instance_id() if initial_round_state != null else 0
	_assert_true(initial_round_state_id != original_player_id, "round state is distinct from persistent golfer identity")

	# Advance enough authoritative time to process any AI tee turns before the
	# player's turn. The controller must stop at the existing human decision seam.
	var search_iterations: int = 0
	var decision: Dictionary = persistent.pending_player_decision()
	while decision.is_empty() and search_iterations < 60:
		persistent.advance_world_time(60.0)
		decision = persistent.pending_player_decision()
		search_iterations += 1
	_assert_true(search_iterations < 60, "persistent world reaches player turn in bounded authoritative time")
	_assert_true(not decision.is_empty(), "persistent session exposes existing authoritative human decision")
	_assert_true(persistent.world_time_seconds > 3600.0, "world clock advances while round is active")
	_assert_equal_int(player.get_instance_id(), original_player_id, "player identity remains stable while world advances")
	_assert_equal_int(int(player.shots_attempted), original_memory_attempts, "human golfer is not autoplayed while waiting for choice")

	var decision_id: String = str(decision.get("decision_id", ""))
	persistent.advance_world_time(300.0)
	var after_think: Dictionary = persistent.pending_player_decision()
	_assert_equal_str(str(after_think.get("decision_id", "")), decision_id, "human decision remains stable while persistent world time advances")
	_assert_equal_int(int(player.shots_attempted), original_memory_attempts, "world advancement cannot silently execute human shot")

	var snapshot: Dictionary = persistent.snapshot()
	_assert_equal_int(int(snapshot.get("golfer_instance_id", 0)), original_player_id, "persistent snapshot identifies same player golfer")
	_assert_equal_int(int(snapshot.get("day", -1)), 12, "persistent snapshot retains world day")
	_assert_true(float(snapshot.get("world_time_seconds", 0.0)) > 3600.0, "persistent snapshot retains advanced world time")
	_assert_equal_int(snapshot.get("completed_rounds", []).size(), 0, "unfinished round is not prematurely archived")
	_assert_equal_int(int(snapshot.get("golf_activity", {}).get("career_rounds_played", -1)), 0, "unfinished round does not count as completed activity")

	print("POC28ABC_PERSISTENT_SESSION_SUMMARY golfer_id=%d day=%d world_time=%.1f group_slot=%d hole=%d decision=%s" % [
		original_player_id,
		persistent.world_day,
		persistent.world_time_seconds,
		int(entered.get("player_member_index", -1)),
		int(persistent.player_round_context().get("hole_number", 0)),
		decision_id
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
		print("POC-28A/B/C PERSISTENT PLAYER WORLD SESSION PASSED")
		quit(0)
	else:
		push_error("POC-28A/B/C PERSISTENT PLAYER WORLD SESSION FAILED: %d" % failures)
		quit(1)

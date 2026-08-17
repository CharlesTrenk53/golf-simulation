extends SceneTree

const DEMO_SCENE := preload("res://scenes/poc29_world_hub_demo.tscn")

var failures: int = 0
var demo = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-29 MANUAL GATE: world hub activity-selection demo contract")
	demo = DEMO_SCENE.instantiate()
	demo.auto_advance = false
	get_root().add_child(demo)

	_assert_true(demo != null, "POC-29 world hub scene instantiates")
	_assert_true(bool(demo.initialized), "POC-29 world hub demo initializes")
	if demo == null or not bool(demo.initialized):
		_finish()
		return

	var player_id: int = demo.persistent_player.get_instance_id()
	var controller_id: int = demo.controller.get_instance_id()
	var starting_time: float = demo.world_session.world_time_seconds
	_assert_true(demo.world_session != null and demo.world_hub != null, "demo owns persistent session plus POC-29 hub coordinator")
	_assert_true(demo.world_session.controller == demo.controller, "hub demo shares exact living-course controller")
	_assert_equal_str(str(demo.engagement_state), "WORLD", "player begins in world rather than an assumed round")
	_assert_true(demo.world_session.active_round.is_empty(), "no player round is active at world entry")
	_assert_true(demo.world_session.active_practice.is_empty(), "no player practice is active at world entry")
	_assert_equal_int(demo.controller.course.hole_count(), 18, "world hub uses complete 18-hole living course")
	_assert_equal_int(demo.controller.living_course.population.group_count(), 3, "living world already contains three autonomous groups")
	_assert_true(demo.session != null and bool(demo.session.started), "living course session runs before player chooses an activity")
	_assert_equal_str(str(demo.focus_controller.selected_group_id()), "group_2", "world hub initially watches ordinary world population")
	_assert_true(demo.engagement_panel != null and demo.engagement_panel.visible, "activity-selection hub is visible at world entry")
	_assert_true(demo.engagement_action != null and demo.practice_action != null, "hub exposes separate round and practice controls")
	_assert_true(demo.engagement_action.visible and demo.practice_action.visible, "both activity controls are visible at world entry")
	_assert_true(demo.engagement_panel.offset_bottom <= 700.0, "world hub panel stays inside 768p acceptance viewport")
	_assert_equal_str(str(demo.clock_label.text), "Course clock: %s" % demo._clock_label(demo.controller.current_time_seconds), "living-course HUD and world hub use same HH:MM clock convention")

	var context: Dictionary = demo.world_hub.context()
	_assert_equal_str(str(context.get("state", "")), "WORLD", "POC-29 hub reports WORLD state")
	_assert_true(bool(context.get("can_choose_activity", false)), "POC-29 hub permits activity choice")
	_assert_equal_int(context.get("activity_catalog", []).size(), 2, "hub catalog exposes round and practice")
	_assert_equal_int(int(context.get("golfer_instance_id", 0)), player_id, "hub references exact persistent golfer")
	_assert_equal_int(int(context.get("controller_instance_id", 0)), controller_id, "hub references exact persistent controller")

	# Practice is selected/launched/finalized through POC-29 and its outcome comes
	# from the existing putting proficiency/execution models, not a fixed XP award.
	_assert_true(demo.begin_practice_activity(), "player can choose modeled putting practice from world hub")
	_assert_equal_str(str(demo.engagement_state), "RESULTS", "completed practice enters player-facing results state")
	_assert_equal_int(demo.world_session.completed_practices.size(), 1, "modeled practice archives exactly once")
	_assert_equal_int(demo.world_session.golf_activity.total_practice_repetitions(), 30, "modeled practice commits factual 30-rep volume")
	_assert_near(demo.world_session.world_time_seconds, starting_time + 600.0, 0.0001, "practice advances same living-world clock by ten minutes")
	_assert_equal_int(demo.persistent_player.get_instance_id(), player_id, "practice preserves exact persistent golfer")
	_assert_equal_int(demo.controller.get_instance_id(), controller_id, "practice preserves exact living-world controller")
	var practice_archive: Dictionary = demo.last_completed_practice
	var putting_observation: Dictionary = practice_archive.get("observations", {}).get(3, {})
	_assert_equal_int(int(putting_observation.get("sample_count", 0)), 30, "practice result is aggregated from 30 modeled putting executions")
	_assert_true(float(putting_observation.get("execution_score", 0.0)) > 0.0, "modeled practice produces observed execution quality")
	_assert_equal_str(str(demo.world_hub.context().get("state", "")), "WORLD", "practice finalization returns persistent authority to WORLD")

	demo._return_to_world()
	_assert_equal_str(str(demo.engagement_state), "WORLD", "practice results return player-facing UI to world hub")
	_assert_true(demo.practice_action.visible, "practice remains selectable after returning to world")

	# Round launch must now use the POC-29 activity contract but still create the
	# same ordinary foursome/human-control structure used by POC-28.
	_assert_true(demo.begin_round_activity(), "player can choose a round after practice")
	_assert_equal_str(str(demo.engagement_state), "PLAYING", "round choice enters playing state")
	_assert_true(not str(demo.active_player_group_id).is_empty(), "round launch creates ordinary player group identity")
	var player_group = demo.controller.living_course.population.group_by_id(demo.active_player_group_id)
	_assert_true(player_group != null, "hub-launched round exists in ordinary living-course population")
	if player_group != null:
		_assert_equal_int(player_group.member_count(), 4, "hub-launched round is ordinary foursome")
		_assert_true(player_group.golfers[0] == demo.persistent_player, "ordinary foursome contains exact persistent golfer")
	_assert_equal_int(int(demo.controller.group_controls.get(demo.active_player_group_id, {}).get("human_member_index", -1)), 0, "hub-launched round uses existing human-control contract")
	_assert_equal_int(demo.persistent_player.get_instance_id(), player_id, "round launch keeps same golfer used by practice")
	_assert_equal_int(demo.controller.get_instance_id(), controller_id, "round launch keeps same world used by practice")
	_assert_equal_int(demo.world_session.completed_practices.size(), 1, "round launch preserves prior practice archive")
	_assert_equal_int(demo.world_session.golf_activity.total_practice_repetitions(), 30, "round launch preserves prior practice volume")
	_assert_equal_str(str(demo.world_hub.context().get("state", "")), "ACTIVITY", "hub reports active round after launch")

	print("POC29_MANUAL_DEMO_SUMMARY golfer_id=%d controller_id=%d practices=%d practice_reps=%d player_group=%s groups=%d world_time=%.1f" % [
		player_id,
		controller_id,
		demo.world_session.completed_practices.size(),
		demo.world_session.golf_activity.total_practice_repetitions(),
		demo.active_player_group_id,
		demo.controller.living_course.population.group_count(),
		demo.world_session.world_time_seconds
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


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if abs(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])


func _finish() -> void:
	if demo != null and is_instance_valid(demo):
		demo.queue_free()
	if failures == 0:
		print("POC-29 WORLD HUB DEMO CONTRACT PASSED")
		quit(0)
	else:
		push_error("POC-29 WORLD HUB DEMO CONTRACT FAILED: %d" % failures)
		quit(1)
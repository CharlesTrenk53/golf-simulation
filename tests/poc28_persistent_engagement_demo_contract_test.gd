extends SceneTree

const DEMO_SCENE := preload("res://scenes/poc28_persistent_engagement_demo.tscn")

var failures: int = 0
var demo = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-28 MANUAL GATE: persistent engagement demo contract")
	demo = DEMO_SCENE.instantiate()
	demo.auto_advance = false
	get_root().add_child(demo)

	_assert_true(demo != null, "POC-28 persistent engagement scene instantiates")
	_assert_true(bool(demo.initialized), "POC-28 persistent engagement demo initializes")
	if demo == null or not bool(demo.initialized):
		_finish()
		return

	_assert_true(demo.world_session != null, "manual demo owns persistent player/world session")
	_assert_true(demo.controller != null and demo.world_session.controller == demo.controller, "presentation and persistence share exact living-course controller")
	_assert_equal_int(demo.controller.course.hole_count(), 18, "persistent demo launches complete 18-hole course")
	_assert_equal_str(str(demo.engagement_state), "PLAYING", "engagement loop begins in PLAYING state")
	_assert_equal_int(int(demo.round_number), 1, "engagement loop begins with Round 1")
	_assert_true(not str(demo.active_player_group_id).is_empty(), "Round 1 has ordinary player group identity")
	_assert_equal_str(str(demo.world_session.active_round.get("group_id", "")), str(demo.active_player_group_id), "persistent session tracks same active player group")

	var player_id: int = demo.persistent_player.get_instance_id()
	var controller_id: int = demo.controller.get_instance_id()
	_assert_true(demo.persistent_player.get_parent() == demo.world_session, "persistent session owns exact player node")
	_assert_equal_int(int(demo.world_session.player_golfer.get_instance_id()), player_id, "persistent session and scene reference same player golfer")

	var player_group = demo.controller.living_course.population.group_by_id(demo.active_player_group_id)
	_assert_true(player_group != null, "player activity exists as ordinary living-course group")
	if player_group != null:
		_assert_equal_int(player_group.member_count(), 4, "player activity is ordinary foursome")
		_assert_true(player_group.golfers[0] == demo.persistent_player, "ordinary group contains exact persistent golfer")
	_assert_equal_int(int(demo.controller.group_controls[demo.active_player_group_id].get("human_member_index", -1)), 0, "ordinary player group uses existing human-control contract")

	for group_id in ["group_2", "group_3", "group_4"]:
		var group = demo.controller.living_course.population.group_by_id(group_id)
		_assert_true(group != null, "%s remains ordinary autonomous world population" % group_id)
		_assert_equal_int(int(demo.controller.group_controls[group_id].get("human_member_index", 99)), -1, "%s remains fully autonomous" % group_id)

	_assert_equal_int(demo.controller.living_course.population.group_count(), 4, "persistent demo begins with four ordinary groups")
	_assert_true(demo.population_view != null, "persistent demo has spectator population view")
	_assert_equal_int(demo.population_view.group_visuals.size(), 4, "all initial groups receive presentation visuals")
	_assert_true(demo.session != null and bool(demo.session.started), "persistent participate session starts normally")
	_assert_equal_int(demo.controller.traffic.group_hole(demo.active_player_group_id), 1, "player group begins on Hole 1 through ordinary traffic authority")
	_assert_equal_str(demo.focus_controller.selected_group_id(), demo.active_player_group_id, "camera/HUD begins focused on current player group")
	_assert_true(demo.get_node_or_null("ShotDispersionPreview") != null, "model-derived shot dispersion preview remains attached")
	_assert_true(demo.engagement_panel != null and not demo.engagement_panel.visible, "post-round/world overlay starts hidden during play")

	var context: Dictionary = demo.world_session.player_round_context()
	_assert_equal_int(int(context.get("hole_number", 0)), 1, "player-facing persistent context begins on Hole 1")
	_assert_equal_int(int(context.get("holes_completed", -1)), 0, "persistent Round 1 begins with no completed holes")
	_assert_equal_int(context.get("scorecard", []).size(), 18, "persistent player-facing context carries full scorecard")
	_assert_true(demo.round_context_label != null, "persistent round context has player-facing HUD projection")

	# The presentation helper may ask authority to release the next waiting group,
	# but it must not bypass POC-24 spacing. With the player group still on its first
	# tee, Group 2 must remain waiting.
	var follower_release: Dictionary = demo.session.attempt_release_next(false)
	_assert_true(not bool(follower_release.get("released", false)), "presentation release seam cannot bypass first-hole traffic safety")
	_assert_equal_str(str(follower_release.get("group_id", "")), "group_2", "next ordinary follower remains Group 2")
	_assert_equal_int(demo.controller.traffic.group_hole("group_2"), 0, "blocked follower remains physically off Hole 1")

	var snap: Dictionary = demo.snapshot()
	_assert_equal_int(int(snap.get("persistent_player_instance_id", 0)), player_id, "manual scene snapshot exposes stable persistent player identity")
	_assert_equal_int(int(snap.get("persistent_world", {}).get("golfer_instance_id", 0)), player_id, "persistent world snapshot matches same golfer")
	_assert_equal_int(demo.controller.get_instance_id(), controller_id, "manual contract never replaces living-world controller")

	print("POC28_MANUAL_DEMO_SUMMARY golfer_id=%d controller_id=%d round=%d player_group=%s groups=%d world_time=%.1f" % [
		player_id,
		controller_id,
		demo.round_number,
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


func _finish() -> void:
	if demo != null and is_instance_valid(demo):
		demo.queue_free()
	if failures == 0:
		print("POC-28 PERSISTENT ENGAGEMENT DEMO CONTRACT PASSED")
		quit(0)
	else:
		push_error("POC-28 PERSISTENT ENGAGEMENT DEMO CONTRACT FAILED: %d" % failures)
		quit(1)

extends SceneTree

const AUTOPLAY_SCENE := preload("res://scenes/poc28_persistent_engagement_autoplay_review.tscn")

const MAX_FRAMES := 120

var failures: int = 0
var demo = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-28 AUTOPLAY GATE: post-round results and persistent-world transition")
	demo = AUTOPLAY_SCENE.instantiate()
	get_root().add_child(demo)
	await process_frame

	_assert_true(demo != null, "autoplay review scene instantiates")
	_assert_true(bool(demo.initialized), "autoplay review scene initializes persistent living world")
	if demo == null or not bool(demo.initialized):
		_finish()
		return

	var player_id: int = demo.persistent_player.get_instance_id()
	var controller_id: int = demo.controller.get_instance_id()
	var first_group_id: String = str(demo.active_player_group_id)

	var frames: int = 0
	while frames < MAX_FRAMES and str(demo.engagement_state) != "RESULTS":
		await process_frame
		frames += 1

	_assert_true(frames < MAX_FRAMES, "autorunner reaches post-round results in bounded review frames")
	_assert_equal_str(str(demo.engagement_state), "RESULTS", "autorunner stops on real RESULTS state")
	_assert_true(demo.autoplay_human_shots > 18, "computer committed a full round of authoritative human choices")
	_assert_true(demo.engagement_panel != null and bool(demo.engagement_panel.visible), "post-round results overlay is visible")
	_assert_true(str(demo.engagement_title.text).begins_with("ROUND 1 COMPLETE"), "results overlay identifies completed Round 1")
	_assert_equal_str(str(demo.engagement_action.text), "RETURN TO WORLD  (Enter)", "results screen waits for reviewer before world transition")

	var archive: Dictionary = demo.last_completed_round
	var stats: Dictionary = archive.get("statistics", {})
	_assert_equal_int(archive.get("scorecard", []).size(), 18, "results use complete authoritative 18-hole scorecard")
	_assert_true(int(archive.get("total_strokes", 0)) > 18, "results retain authoritative stroke total")
	_assert_equal_int(int(stats.get("human_shots", -1)), int(stats.get("total_shots", -2)), "all player shots retain human-control provenance despite review automation")
	_assert_equal_int(int(stats.get("total_shots", 0)), int(demo.autoplay_human_shots), "autorunner committed exactly the archived player shot count")
	_assert_equal_int(int(demo.world_session.golf_activity.career_rounds_played), 1, "completed autoplay round records one persistent factual activity")
	_assert_true(demo.world_session.active_round.is_empty(), "completed player activity returns to persistent session idle state")
	_assert_true(demo.controller.living_course.population.group_by_id(first_group_id) == null, "completed player group retires before results review")
	_assert_equal_int(demo.persistent_player.get_instance_id(), player_id, "results screen preserves exact persistent golfer")
	_assert_equal_int(demo.controller.get_instance_id(), controller_id, "results screen preserves exact living-world controller")

	# Exercise the same transition the reviewer will trigger with Enter/button.
	demo._return_to_world()
	_assert_equal_str(str(demo.engagement_state), "WORLD", "results transition returns player to living-world hub")
	_assert_true(demo.engagement_panel.visible, "world hub remains visibly inspectable")
	_assert_equal_str(str(demo.engagement_title.text), "LIVING GOLF WORLD", "world transition shows persistent world hub")
	_assert_equal_str(str(demo.engagement_action.text), "PLAY ANOTHER ROUND  (Enter)", "world hub offers another ordinary round")
	_assert_equal_int(demo.persistent_player.get_instance_id(), player_id, "world hub keeps same persistent golfer")
	_assert_equal_int(demo.controller.get_instance_id(), controller_id, "world hub keeps same persistent controller")
	_assert_equal_int(demo.world_session.completed_rounds.size(), 1, "world hub retains completed-round history")

	# Prove the next engagement starts from that same changed golfer/world. Do not
	# wait another frame, so the review autorunner cannot race through Round 2 before
	# these entry invariants are inspected.
	demo._begin_next_round()
	_assert_equal_str(str(demo.engagement_state), "PLAYING", "world hub can begin another round")
	_assert_equal_int(int(demo.round_number), 2, "second engagement receives Round 2 identity")
	_assert_true(not demo.world_session.active_round.is_empty(), "Round 2 becomes active ordinary player activity")
	_assert_equal_int(demo.persistent_player.get_instance_id(), player_id, "Round 2 reuses exact persistent golfer")
	_assert_equal_int(demo.controller.get_instance_id(), controller_id, "Round 2 reuses exact persistent living world")
	var round_2_state = demo.world_session.player_round_state()
	_assert_true(round_2_state != null, "Round 2 receives fresh disposable round state")
	if round_2_state != null:
		_assert_equal_int(int(round_2_state.total_strokes()), 0, "Round 2 scoring starts fresh while golfer/world persist")

	print("POC28_AUTOPLAY_POST_ROUND_SUMMARY frames=%d player_id=%d controller_id=%d round1_shots=%d score=%d next_round=%d" % [
		frames,
		player_id,
		controller_id,
		int(stats.get("total_shots", 0)),
		int(archive.get("total_strokes", 0)),
		int(demo.round_number)
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
		print("POC-28 AUTOPLAY POST-ROUND REVIEW PASSED")
		quit(0)
	else:
		push_error("POC-28 AUTOPLAY POST-ROUND REVIEW FAILED: %d" % failures)
		quit(1)

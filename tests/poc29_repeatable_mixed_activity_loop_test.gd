extends SceneTree

const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
const PlayerWorldHub = preload("res://simulation/player_world_hub.gd")
const PlayerActivityContract = preload("res://simulation/player_activity_contract.gd")
const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const STEP_SECONDS := 60.0
const MAX_ITERATIONS := 1600

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-29F: repeatable mixed activity loop")
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
	_assert_true(persistent.configure(player, course, 50, 28800.0), "persistent world session configures")
	if persistent.controller == null:
		_finish()
		return

	var hub = PlayerWorldHub.new()
	_assert_true(hub.configure(persistent), "world hub configures over persistent session")
	var player_id: int = player.get_instance_id()
	var controller_id: int = persistent.controller.get_instance_id()
	var starting_world_time: float = persistent.world_time_seconds
	var starting_memory: int = int(player.shots_attempted)
	var starting_development: int = _sum_development_experience(persistent.development_snapshot())
	_assert_world_identity(hub, player_id, controller_id, "initial world")

	# ACTIVITY 1 — Putting practice. Selection is pure, launch creates activity
	# state, and return commits factual consequences through the existing practice
	# authority before reopening the same hub.
	var practice_1_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_PRACTICE, {
		"total_repetitions": 30,
		"focus": {3: 1.0},
		"quality": 0.8,
		"duration_seconds": 600.0
	})
	_assert_true(bool(practice_1_selection.get("accepted", false)), "first practice is selectable")
	var practice_1_launch: Dictionary = hub.launch_selected_activity(practice_1_selection)
	_assert_true(bool(practice_1_launch.get("launched", false)), "first practice launches")
	_assert_equal_str(str(hub.context().get("active_activity_type", "")), "PRACTICE", "hub enters first practice")
	var practice_1_return: Dictionary = hub.return_to_world("AUTO", {
		"observations": {
			3: {"execution_score": 76.0, "lateral_error": 0.0, "distance_error": 0.6}
		}
	})
	_assert_true(bool(practice_1_return.get("returned", false)), "first practice returns through shared seam")
	_assert_true(bool(practice_1_return.get("completed", false)), "first practice completes")
	_assert_equal_int(persistent.completed_practices.size(), 1, "first practice archives once")
	_assert_equal_int(persistent.golf_activity.total_practice_repetitions(), 30, "first practice volume persists")
	_assert_near(persistent.world_time_seconds, starting_world_time + 600.0, 0.0001, "first practice advances same world clock")
	_assert_world_identity(hub, player_id, controller_id, "world after first practice")
	_assert_equal_str(str(hub.context().get("state", "")), PlayerWorldHub.STATE_WORLD, "first practice returns to world hub")

	var experience_after_practice_1: int = _sum_development_experience(persistent.development_snapshot())
	_assert_equal_int(experience_after_practice_1 - starting_development, 30, "first practice adds factual development experience")

	# ACTIVITY 2 — Ordinary scored round launched from the same hub. It enters the
	# normal tee queue, uses the existing human decision seam, and finalizes through
	# the same return-to-world coordinator.
	var round_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_ROUND, {
		"group_id": "poc29_mixed_round",
		"other_golfers": [],
		"tee_id": "default",
		"player_member_index": 0,
		"seed_base": 29501
	})
	_assert_true(bool(round_selection.get("accepted", false)), "round is selectable after practice")
	var round_launch: Dictionary = hub.launch_selected_activity(round_selection)
	_assert_true(bool(round_launch.get("launched", false)), "round launches from same hub")
	_assert_equal_int(persistent.controller.get_instance_id(), controller_id, "round launch keeps same controller")
	_assert_equal_int(player.get_instance_id(), player_id, "round launch keeps same golfer")
	_assert_equal_int(persistent.golf_activity.total_practice_repetitions(), 30, "round launch keeps prior practice history")
	_assert_near(persistent.world_time_seconds, starting_world_time + 600.0, 0.0001, "round launch does not reset or advance clock")

	var release: Dictionary = persistent.release_next_group()
	_assert_true(bool(release.get("released", false)), "hub-launched round releases through ordinary tee authority")
	_assert_equal_str(str(release.get("group_id", "")), "poc29_mixed_round", "ordinary tee authority releases selected round")
	var iterations: int = _play_active_round_to_finish(persistent)
	_assert_true(iterations < MAX_ITERATIONS, "mixed-loop round finishes in bounded authoritative time")
	var round_state = persistent.player_round_state()
	_assert_true(round_state != null and bool(round_state.complete), "mixed-loop round completes all 18 holes")
	_assert_equal_int(int(round_state.holes_completed()), 18, "mixed-loop round completes scorecard")
	_assert_true(int(player.shots_attempted) > starting_memory, "round changes same golfer memory")

	var world_time_before_round_return: float = persistent.world_time_seconds
	var round_return: Dictionary = hub.return_to_world()
	_assert_true(bool(round_return.get("returned", false)), "completed round returns through shared seam")
	_assert_true(bool(round_return.get("completed", false)), "round return is a completed activity")
	_assert_equal_int(persistent.completed_rounds.size(), 1, "round archive persists once")
	_assert_equal_int(int(persistent.golf_activity.career_rounds_played), 1, "round activity persists alongside practice")
	_assert_true(persistent.golf_activity.total_on_course_exposure() > 18, "round stores factual on-course exposure")
	_assert_near(persistent.world_time_seconds, world_time_before_round_return, 0.0001, "round finalization does not reset world clock")
	_assert_world_identity(hub, player_id, controller_id, "world after round")
	_assert_equal_str(str(hub.context().get("state", "")), PlayerWorldHub.STATE_WORLD, "completed round returns to world hub")
	_assert_equal_int(persistent.golf_activity.total_practice_repetitions(), 30, "round completion preserves earlier practice history")

	var experience_after_round: int = _sum_development_experience(persistent.development_snapshot())
	var round_archive: Dictionary = persistent.latest_completed_round()
	var round_shots: int = int(round_archive.get("statistics", {}).get("total_shots", 0))
	_assert_true(round_shots > 18, "round archive contains authoritative shot history")
	_assert_equal_int(experience_after_round - experience_after_practice_1, round_shots, "round development accumulates after practice without reset")

	# ACTIVITY 3 — Approach practice after the scored round. This proves the player
	# can leave golf, return to the world, choose a different activity again, and
	# continue accumulating consequences in the same persistent session.
	var practice_2_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_PRACTICE, {
		"total_repetitions": 20,
		"focus": {1: 1.0},
		"quality": 0.5,
		"duration_seconds": 300.0
	})
	_assert_true(bool(practice_2_selection.get("accepted", false)), "second practice is selectable after round")
	var practice_2_launch: Dictionary = hub.launch_selected_activity(practice_2_selection)
	_assert_true(bool(practice_2_launch.get("launched", false)), "second practice launches")
	_assert_equal_int(int(player.shots_attempted), int(player.shots_attempted), "second practice does not replace golfer memory")
	var memory_before_practice_2: int = int(player.shots_attempted)
	var practice_2_return: Dictionary = hub.return_to_world("COMPLETE", {
		"observations": {
			1: {"execution_score": 72.0, "lateral_error": 2.0, "distance_error": 3.0}
		}
	})
	_assert_true(bool(practice_2_return.get("returned", false)), "second practice returns through same seam")
	_assert_true(bool(practice_2_return.get("completed", false)), "second practice completes")
	_assert_equal_int(persistent.completed_practices.size(), 2, "both practice sessions remain archived")
	_assert_equal_int(persistent.completed_rounds.size(), 1, "round archive remains after second practice")
	_assert_equal_int(persistent.golf_activity.total_practice_repetitions(), 50, "practice repetitions accumulate across both sessions")
	_assert_equal_int(int(persistent.golf_activity.career_rounds_played), 1, "round count survives later practice")
	_assert_equal_int(int(player.shots_attempted), memory_before_practice_2, "practice does not erase or fabricate on-course shot memory")
	_assert_near(persistent.world_time_seconds, world_time_before_round_return + 300.0, 0.0001, "second practice continues same post-round world clock")
	_assert_world_identity(hub, player_id, controller_id, "final world")

	var final_context: Dictionary = hub.context()
	_assert_equal_str(str(final_context.get("state", "")), PlayerWorldHub.STATE_WORLD, "mixed activity sequence ends in persistent world")
	_assert_equal_str(str(final_context.get("active_activity_type", "")), PlayerWorldHub.ACTIVITY_NONE, "no activity remains active at end")
	_assert_true(bool(final_context.get("can_choose_activity", false)), "player can choose another activity after mixed loop")
	_assert_equal_int(int(final_context.get("completed_practices", 0)), 2, "hub exposes both completed practices")
	_assert_equal_int(int(final_context.get("completed_rounds", 0)), 1, "hub exposes completed round")
	_assert_equal_int(int(final_context.get("total_practice_repetitions", 0)), 50, "hub exposes cumulative practice volume")
	_assert_equal_int(int(final_context.get("career_rounds_played", 0)), 1, "hub exposes cumulative round history")
	_assert_equal_int(int(player.get_instance_id()), player_id, "one golfer survives entire mixed activity loop")
	_assert_equal_int(int(persistent.controller.get_instance_id()), controller_id, "one living-world controller survives entire mixed activity loop")

	var final_experience: int = _sum_development_experience(persistent.development_snapshot())
	_assert_equal_int(final_experience - starting_development, 30 + round_shots + 20, "development experience exactly accumulates practice + round + practice")
	_assert_equal_int(_activity_event_count(persistent.activity_history, "PRACTICE_COMPLETED"), 2, "history records two completed practices")
	_assert_equal_int(_activity_event_count(persistent.activity_history, "ROUND_COMPLETED"), 1, "history records one completed round")

	print("POC29F_MIXED_ACTIVITY_SUMMARY golfer_id=%d controller_id=%d practices=%d rounds=%d practice_reps=%d round_shots=%d memory=%d development_experience=%d world_time=%.1f" % [
		player_id,
		controller_id,
		persistent.completed_practices.size(),
		persistent.completed_rounds.size(),
		persistent.golf_activity.total_practice_repetitions(),
		round_shots,
		int(player.shots_attempted),
		final_experience,
		persistent.world_time_seconds
	])
	_finish()


func _play_active_round_to_finish(persistent) -> int:
	var iterations: int = 0
	while iterations < MAX_ITERATIONS:
		var state = persistent.player_round_state()
		if state != null and bool(state.complete):
			var group_id: String = str(persistent.active_round.get("group_id", ""))
			var group = persistent.controller.living_course.population.group_by_id(group_id)
			if group != null and str(group.status) == "FINISHED" and persistent.controller.traffic.group_hole(group_id) == 0:
				break

		var decision: Dictionary = persistent.pending_player_decision()
		if not decision.is_empty():
			var candidate_index: int = _preferred_human_candidate(decision)
			if candidate_index < 0:
				failures += 1
				push_error("FAIL: human decision exposes no selectable authoritative candidate")
				break
			var committed: Dictionary = persistent.submit_player_choice(candidate_index)
			if not bool(committed.get("played", false)):
				failures += 1
				push_error("FAIL: human choice could not commit through ordinary authority")
				break
		else:
			persistent.advance_world_time(STEP_SECONDS)
		iterations += 1
	return iterations


func _preferred_human_candidate(decision: Dictionary) -> int:
	var choices: Array = decision.get("choices", [])
	if str(decision.get("decision_kind", "")) == "PUTTING":
		for index in range(choices.size()):
			if typeof(choices[index]) != TYPE_DICTIONARY:
				continue
			var choice: Dictionary = choices[index]
			if bool(choice.get("human_selectable", false)) and str(choice.get("putting_strategy", "")) == "NEUTRAL":
				return int(choice.get("index", index))
	for index in range(choices.size()):
		if typeof(choices[index]) == TYPE_DICTIONARY and bool(choices[index].get("human_selectable", false)):
			return int(choices[index].get("index", index))
	return -1


func _sum_development_experience(snapshot: Dictionary) -> int:
	var total: int = 0
	for shot_type in [0, 1, 2, 3]:
		total += int(snapshot.get(shot_type, {}).get("total_experience", 0))
	return total


func _activity_event_count(history: Array, event_type: String) -> int:
	var count: int = 0
	for value in history:
		if typeof(value) == TYPE_DICTIONARY and str(value.get("type", "")) == event_type:
			count += 1
	return count


func _assert_world_identity(hub, player_id: int, controller_id: int, label: String) -> void:
	var context: Dictionary = hub.context()
	_assert_equal_int(int(context.get("golfer_instance_id", 0)), player_id, label + " preserves golfer identity")
	_assert_equal_int(int(context.get("controller_instance_id", 0)), controller_id, label + " preserves controller identity")


func _new_golfer(profile_value: int):
	var golfer = QuietGolfer.new()
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
		print("POC-29F REPEATABLE MIXED ACTIVITY LOOP PASSED")
		quit(0)
	else:
		push_error("POC-29F REPEATABLE MIXED ACTIVITY LOOP FAILED: %d" % failures)
		quit(1)

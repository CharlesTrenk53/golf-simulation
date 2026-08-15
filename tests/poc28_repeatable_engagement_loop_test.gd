extends SceneTree

const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
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
	print("POC-28D/E/F: repeatable persistent engagement loop")
	var course = POC27Course.build()
	_assert_true(course != null and course.hole_count() == 18, "18-hole course builds for repeat-loop proof")
	if course == null:
		_finish()
		return

	var player = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var persistent = PlayerWorldSession.new()
	persistent.name = "PersistentPlayerWorldSession"
	get_root().add_child(persistent)
	created_nodes.append(persistent)
	_assert_true(persistent.configure(player, course, 4, 7200.0), "persistent session configures for repeat loop")
	if persistent.controller == null:
		_finish()
		return

	var player_id: int = player.get_instance_id()
	var controller_id: int = persistent.controller.get_instance_id()
	var starting_memory: int = int(player.shots_attempted)
	var starting_world_time: float = persistent.world_time_seconds
	var starting_development_evidence: int = _sum_development_evidence(persistent.development_snapshot())

	# ROUND 1: player is an ordinary second member of a twosome.
	var partner_1 = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	var entered_1: Dictionary = persistent.enter_round("persistent_round_1", [partner_1], "default", 1, 28801)
	_assert_true(bool(entered_1.get("entered", false)), "Round 1 enters ordinary twosome")
	_assert_equal_int(int(entered_1.get("golfer_instance_id", 0)), player_id, "Round 1 uses persistent golfer identity")
	_assert_equal_int(int(entered_1.get("player_member_index", -1)), 1, "Round 1 player occupies ordinary second slot")
	var round_1_state = persistent.player_round_state()
	_assert_true(round_1_state != null, "Round 1 receives fresh RoundState")
	var round_1_state_id: int = round_1_state.get_instance_id() if round_1_state != null else 0
	_assert_false(persistent.controller.retire_finished_group("persistent_round_1"), "active Round 1 group cannot retire early through live authority")

	var release_1: Dictionary = persistent.release_next_group()
	_assert_true(bool(release_1.get("released", false)), "Round 1 releases through ordinary tee authority")
	_assert_equal_str(str(release_1.get("group_id", "")), "persistent_round_1", "Round 1 group is normal FIFO release")
	var round_1_iterations: int = _play_active_round_to_finish(persistent)
	_assert_true(round_1_iterations < MAX_ITERATIONS, "Round 1 finishes in bounded authoritative time")
	_assert_true(round_1_state != null and bool(round_1_state.complete), "Round 1 RoundState completes all 18 holes")
	_assert_equal_int(int(round_1_state.holes_completed()), 18, "Round 1 completes 18 scorecard holes")
	_assert_true(int(player.shots_attempted) > starting_memory, "Round 1 naturally changes persistent golfer memory")
	var memory_after_round_1: int = int(player.shots_attempted)
	var world_time_after_round_1: float = persistent.world_time_seconds
	_assert_true(world_time_after_round_1 > starting_world_time, "Round 1 advances persistent world clock")
	_assert_equal_int(persistent.controller.traffic.group_hole("persistent_round_1"), 0, "Round 1 leaves physical course after Hole 18")

	var finalized_1: Dictionary = persistent.finalize_player_round()
	_assert_true(bool(finalized_1.get("finalized", false)), "Round 1 finalizes into persistent history")
	var archive_1: Dictionary = finalized_1.get("round", {})
	var stats_1: Dictionary = archive_1.get("statistics", {})
	var exposure_1: Dictionary = stats_1.get("shot_type_exposure", {})
	var development_evidence_1: Dictionary = archive_1.get("development_evidence", {})
	var development_after_1: Dictionary = archive_1.get("development_after", {})
	_assert_equal_int(archive_1.get("scorecard", []).size(), 18, "Round 1 archive retains authoritative 18-hole scorecard")
	_assert_equal_int(int(archive_1.get("total_strokes", -1)), int(round_1_state.total_strokes()), "Round 1 archive retains authoritative stroke total")
	_assert_true(int(stats_1.get("total_shots", 0)) > 18, "Round 1 archive contains authoritative player shot history")
	_assert_equal_int(_sum_exposure(exposure_1), int(stats_1.get("total_shots", -1)), "Round 1 factual exposure equals authoritative shot count")
	_assert_true(int(stats_1.get("putts", 0)) > 0, "Round 1 archive derives putting count from authoritative shot types")
	_assert_equal_int(int(stats_1.get("human_shots", 0)), int(stats_1.get("total_shots", -1)), "Round 1 player shots retain human provenance")
	_assert_equal_int(int(persistent.golf_activity.career_rounds_played), 1, "Round 1 records one factual GolfActivity round")
	_assert_equal_int(persistent.golf_activity.total_on_course_exposure(), int(stats_1.get("total_shots", -1)), "GolfActivity uses actual Round 1 shot exposure rather than placeholder distribution")
	_assert_equal_int(int(development_evidence_1.get("unsupported_shots", -1)), 0, "every authoritative Round 1 shot carries usable development evidence")
	_assert_equal_int(int(development_evidence_1.get("total_evidence", 0)), int(stats_1.get("total_shots", -1)), "Round 1 sends every authoritative shot through existing development bridge")
	_assert_equal_int(_sum_exposure(development_evidence_1.get("shot_type_evidence", {})), int(stats_1.get("total_shots", -1)), "Round 1 development evidence preserves exact shot-family exposure")
	_assert_equal_int(_sum_development_evidence(development_after_1) - starting_development_evidence, int(stats_1.get("total_shots", -1)), "Round 1 development engine accumulates one evidence event per played shot")
	_assert_golfer_experience_matches_development(player, development_after_1, "Round 1 syncs development experience back onto persistent golfer")
	_assert_golfer_ability_matches_development(player, development_after_1, "Round 1 projects durable development back to ordinary golfer abilities")
	_assert_equal_int(persistent.completed_rounds.size(), 1, "Round 1 appears once in persistent completed-round history")
	_assert_true(persistent.active_round.is_empty(), "player returns to persistent world with no active activity")
	_assert_equal_str(str(persistent.player_round_context().get("activity_type", "")), "NONE", "post-round context returns to world/idle state")
	_assert_true(persistent.controller.living_course.population.group_by_id("persistent_round_1") == null, "finished Round 1 group retires from current population")
	_assert_false(persistent.controller.living_course.population.golfer_assignments.has(player_id), "Round 1 retirement releases persistent golfer assignment")
	_assert_equal_int(player.get_instance_id(), player_id, "Round 1 finalization preserves exact golfer object")
	_assert_equal_int(persistent.controller.get_instance_id(), controller_id, "Round 1 finalization preserves exact living-world controller")

	# ROUND 2: same world, same golfer, new ordinary group and fresh round state.
	var development_total_after_round_1: int = _sum_development_evidence(persistent.development_snapshot())
	var partner_2 = _new_golfer(Golfer.GolferProfile.RECKLESS_RICK)
	var entered_2: Dictionary = persistent.enter_round("persistent_round_2", [partner_2], "default", 0, 28901)
	_assert_true(bool(entered_2.get("entered", false)), "same persistent golfer can enter Round 2 after retirement")
	_assert_equal_int(int(entered_2.get("golfer_instance_id", 0)), player_id, "Round 2 reuses exact same golfer identity")
	_assert_equal_int(int(player.shots_attempted), memory_after_round_1, "Round 2 begins with Round 1 golfer memory intact")
	_assert_equal_int(_sum_development_evidence(persistent.development_snapshot()), development_total_after_round_1, "Round 2 begins with Round 1 development evidence intact")
	_assert_golfer_ability_matches_development(player, persistent.development_snapshot(), "Round 2 begins using the durable ability state produced after Round 1")
	_assert_equal_int(int(persistent.golf_activity.career_rounds_played), 1, "Round 1 activity history remains before Round 2 completion")
	_assert_near(persistent.world_time_seconds, world_time_after_round_1, 0.0001, "Round 2 entry does not reset persistent world clock")
	_assert_equal_int(persistent.controller.get_instance_id(), controller_id, "Round 2 uses same living-world controller")
	var round_2_state = persistent.player_round_state()
	_assert_true(round_2_state != null, "Round 2 receives new RoundState")
	if round_2_state != null:
		_assert_true(round_2_state.get_instance_id() != round_1_state_id, "Round 2 state is fresh while golfer remains persistent")
		_assert_equal_int(int(round_2_state.total_strokes()), 0, "fresh Round 2 scoring begins at zero")

	var release_2: Dictionary = persistent.release_next_group()
	_assert_true(bool(release_2.get("released", false)), "Round 2 releases normally into unchanged world")
	_assert_equal_str(str(release_2.get("group_id", "")), "persistent_round_2", "Round 2 uses new ordinary group identity")
	var round_2_iterations: int = _play_active_round_to_finish(persistent)
	_assert_true(round_2_iterations < MAX_ITERATIONS, "Round 2 finishes in bounded authoritative time")
	_assert_true(round_2_state != null and bool(round_2_state.complete), "Round 2 completes all 18 holes")
	_assert_true(int(player.shots_attempted) > memory_after_round_1, "Round 2 continues changing same golfer memory")
	_assert_true(persistent.world_time_seconds > world_time_after_round_1, "Round 2 continues same world clock rather than restarting")

	var finalized_2: Dictionary = persistent.finalize_player_round()
	_assert_true(bool(finalized_2.get("finalized", false)), "Round 2 finalizes without rebuilding persistent world")
	var archive_2: Dictionary = finalized_2.get("round", {})
	var stats_2: Dictionary = archive_2.get("statistics", {})
	var development_evidence_2: Dictionary = archive_2.get("development_evidence", {})
	var development_after_2: Dictionary = archive_2.get("development_after", {})
	_assert_equal_int(archive_2.get("scorecard", []).size(), 18, "Round 2 archive retains complete authoritative scorecard")
	_assert_equal_int(int(persistent.golf_activity.career_rounds_played), 2, "two completed activities accumulate on same GolfActivity history")
	_assert_equal_int(persistent.completed_rounds.size(), 2, "persistent history retains both completed rounds")
	_assert_equal_int(player.get_instance_id(), player_id, "same golfer identity survives two complete activities")
	_assert_equal_int(persistent.controller.get_instance_id(), controller_id, "same world authority survives two complete activities")
	_assert_true(float(archive_2.get("entered_time_seconds", 0.0)) >= float(archive_1.get("completed_time_seconds", 0.0)), "Round 2 begins no earlier than Round 1 world completion")
	_assert_true(int(stats_2.get("total_shots", 0)) > 18, "Round 2 also derives factual authoritative shot history")
	_assert_equal_int(int(development_evidence_2.get("unsupported_shots", -1)), 0, "every authoritative Round 2 shot carries usable development evidence")
	_assert_equal_int(int(development_evidence_2.get("total_evidence", 0)), int(stats_2.get("total_shots", -1)), "Round 2 sends every authoritative shot through same development bridge")
	_assert_equal_int(_sum_development_evidence(development_after_2) - development_total_after_round_1, int(stats_2.get("total_shots", -1)), "Round 2 development evidence accumulates instead of resetting")
	_assert_golfer_experience_matches_development(player, development_after_2, "Round 2 preserves cumulative development experience on persistent golfer")
	_assert_golfer_ability_matches_development(player, development_after_2, "Round 2 leaves ordinary golfer abilities synchronized to cumulative durable development")
	_assert_equal_int(
		persistent.golf_activity.total_on_course_exposure(),
		int(stats_1.get("total_shots", 0)) + int(stats_2.get("total_shots", 0)),
		"career activity exposure exactly accumulates both authoritative rounds"
	)
	_assert_equal_int(
		_sum_development_evidence(persistent.development_snapshot()) - starting_development_evidence,
		int(stats_1.get("total_shots", 0)) + int(stats_2.get("total_shots", 0)),
		"persistent development evidence exactly accumulates both authoritative rounds"
	)
	_assert_equal_str(str(persistent.player_round_context().get("status", "")), "IDLE", "repeat loop returns to persistent idle world after Round 2")

	print("POC28F_REPEATABLE_LOOP_SUMMARY golfer_id=%d controller_id=%d rounds=%d memory=%d development_evidence=%d world_time=%.1f round1_shots=%d round2_shots=%d" % [
		player_id,
		controller_id,
		persistent.golf_activity.career_rounds_played,
		int(player.shots_attempted),
		_sum_development_evidence(persistent.development_snapshot()),
		persistent.world_time_seconds,
		int(stats_1.get("total_shots", 0)),
		int(stats_2.get("total_shots", 0))
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
			_assert_true(candidate_index >= 0, "human decision exposes a selectable authoritative candidate")
			if candidate_index < 0:
				break
			var committed: Dictionary = persistent.submit_player_choice(candidate_index)
			_assert_true(bool(committed.get("played", false)), "human choice commits through ordinary authority")
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


func _sum_exposure(exposure: Dictionary) -> int:
	var total: int = 0
	for shot_type in [0, 1, 2, 3]:
		total += int(exposure.get(shot_type, 0))
	return total


func _sum_development_evidence(snapshot: Dictionary) -> int:
	var total: int = 0
	for shot_type in [0, 1, 2, 3]:
		var state: Dictionary = snapshot.get(shot_type, {})
		total += int(state.get("evidence_count", 0))
	return total


func _assert_golfer_experience_matches_development(player, snapshot: Dictionary, label: String) -> void:
	var all_match: bool = true
	for shot_type in [0, 1, 2, 3]:
		var state: Dictionary = snapshot.get(shot_type, {})
		if int(player.skill_experience_for(shot_type)) != int(state.get("total_experience", -1)):
			all_match = false
			break
	_assert_true(all_match, label)


func _assert_golfer_ability_matches_development(player, snapshot: Dictionary, label: String) -> void:
	var all_match: bool = true
	for shot_type in [0, 1, 2, 3]:
		var state: Dictionary = snapshot.get(shot_type, {})
		if abs(float(player.get_shot_ability(shot_type)) - float(state.get("effective_skill", -999.0))) > 0.0001:
			all_match = false
			break
	_assert_true(all_match, label)


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


func _assert_false(value: bool, label: String) -> void:
	_assert_true(not value, label)


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
		print("POC-28D/E/F REPEATABLE ENGAGEMENT LOOP PASSED")
		quit(0)
	else:
		push_error("POC-28D/E/F REPEATABLE ENGAGEMENT LOOP FAILED: %d" % failures)
		quit(1)

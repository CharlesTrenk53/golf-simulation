extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const ParticipateSpectatorSession = preload("res://scenes/participate_spectator_session.gd")
const Golfer = preload("res://scenes/golfer.gd")

const PLAYER_GROUP := "group_1"
const OTHER_GROUP := "group_2"
const HUMAN_MEMBER := 0
const THINK_WAIT_SECONDS := 360.0

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	print("POC-26F: full two-group three-hole mixed participation round")

	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null, "three-hole proving course loads")
	if course == null:
		_finish()
		return
	_assert_equal(course.hole_count(), 3, "closure proof uses all three proving-course holes")

	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "shot-progressive living course configures")

	var player = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var partner = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	var other_a = _new_golfer(Golfer.GolferProfile.RECKLESS_RICK)
	var other_b = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	_assert_true(runtime.add_group(PLAYER_GROUP, [player, partner], "default", HUMAN_MEMBER, 28601), "mixed player group joins normal living course")
	_assert_true(runtime.add_group(OTHER_GROUP, [other_a, other_b], "default", -1, 28701), "fully autonomous group joins same living course")

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	created_nodes.append(world)
	_assert_true(world.configure(course), "POC-25 spectator course world is reused")

	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	created_nodes.append(view)
	_assert_true(view.configure(world, runtime), "POC-25 spectator population view binds shot-progressive authority")
	_assert_equal(view.group_visuals.size(), 2, "both living groups own spectator visuals")

	var session = ParticipateSpectatorSession.new()
	get_root().add_child(session)
	created_nodes.append(session)
	_assert_true(session.configure(runtime, world, view), "participate session bridges full living round to presentation")

	var opening: Dictionary = session.start_session()
	_assert_true(not opening.is_empty(), "participate session releases first group")
	_assert_equal(str(opening.get("group_id", "")), PLAYER_GROUP, "FIFO start order releases mixed player group first")
	_assert_equal(int(runtime.traffic.group_hole(PLAYER_GROUP)), 1, "player group owns first-hole traffic authority")
	_assert_equal(int(runtime.traffic.group_hole(OTHER_GROUP)), 0, "autonomous group initially remains off the first hole")

	var blocked_opening: Dictionary = runtime.release_next_group()
	_assert_true(not bool(blocked_opening.get("released", false)), "following group cannot bypass live first-tee safety gate")
	_assert_equal(str(blocked_opening.get("group_id", "")), OTHER_GROUP, "blocked follower remains next in FIFO queue")
	_assert_true(not str(blocked_opening.get("reason", "")).is_empty(), "blocked first-tee release reports mechanical reason")

	var group_1 = runtime.living_course.population.group_by_id(PLAYER_GROUP)
	var group_2 = runtime.living_course.population.group_by_id(OTHER_GROUP)
	_assert_true(group_1 != null and group_2 != null, "both groups remain ordinary living-course population members")
	if group_1 == null or group_2 == null:
		_finish()
		return

	var overlap_seen: bool = false
	var same_hole_overlap_seen: bool = false
	var think_wait_performed: bool = false
	var think_wait_other_progress: bool = false
	var human_turns: int = 0
	var processed_event_count: int = 0
	var iterations: int = 0

	while iterations < 600 and not _round_world_complete(runtime, group_1, group_2):
		iterations += 1

		var player_hole: int = int(runtime.traffic.group_hole(PLAYER_GROUP))
		var other_hole: int = int(runtime.traffic.group_hole(OTHER_GROUP))
		if player_hole > 0 and other_hole > 0:
			overlap_seen = true
			if player_hole == other_hole:
				same_hole_overlap_seen = true

		var decision: Dictionary = session.pending_human_decision(PLAYER_GROUP)
		if not decision.is_empty():
			if not think_wait_performed and other_hole > 0 and str(group_2.status) != "FINISHED":
				var before_time: float = runtime.current_time_seconds
				var before_player_shots: int = runtime.group_live_shot_count(PLAYER_GROUP)
				var before_other_shots: int = runtime.group_live_shot_count(OTHER_GROUP)
				var before_decision_id: String = str(decision.get("decision_id", ""))
				var before_ball: Vector3 = group_1.rounds[HUMAN_MEMBER].active_hole_state.ball_position
				var before_strokes: int = int(group_1.rounds[HUMAN_MEMBER].active_hole_state.strokes)

				var waited_events: Array = session.advance_time(THINK_WAIT_SECONDS, false)
				processed_event_count += waited_events.size()
				think_wait_performed = true

				_assert_near(runtime.current_time_seconds, before_time + THINK_WAIT_SECONDS, 0.0001, "global course clock advances through deliberate human think time")
				_assert_equal(runtime.group_live_shot_count(PLAYER_GROUP), before_player_shots, "player group cannot autoplay through pending human turn")
				_assert_equal(group_1.rounds[HUMAN_MEMBER].active_hole_state.ball_position, before_ball, "human authoritative ball remains frozen while deciding")
				_assert_equal(int(group_1.rounds[HUMAN_MEMBER].active_hole_state.strokes), before_strokes, "human authoritative strokes remain frozen while deciding")
				var after_wait_decision: Dictionary = session.pending_human_decision(PLAYER_GROUP)
				_assert_equal(str(after_wait_decision.get("decision_id", "")), before_decision_id, "same authoritative human decision survives extended think time")
				think_wait_other_progress = runtime.group_live_shot_count(OTHER_GROUP) > before_other_shots
				_assert_true(think_wait_other_progress, "autonomous group keeps taking real shots while human thinks")
				decision = after_wait_decision

			var candidate_index: int = _preferred_human_candidate(decision)
			_assert_true(candidate_index >= 0, "pending human decision exposes a deterministic selectable choice")
			if candidate_index < 0:
				break
			var submitted: Dictionary = session.submit_human_choice(PLAYER_GROUP, candidate_index, false)
			_assert_true(bool(submitted.get("played", false)), "scripted human choice executes through normal authoritative contract")
			if not bool(submitted.get("played", false)):
				break
			human_turns += 1
			processed_event_count += 1 + submitted.get("world_events", []).size()
			continue

		var before_step_time: float = runtime.current_time_seconds
		var emitted: Array = session.advance_time(30.0, false)
		processed_event_count += emitted.size()
		_assert_true(runtime.current_time_seconds > before_step_time, "living course clock advances between player decisions")

	_assert_true(iterations < 600, "full mixed living round remains bounded")
	_assert_true(think_wait_performed, "full round includes a deliberate human think period while another group is live")
	_assert_true(think_wait_other_progress, "other-group golf progresses during full-round human think period")
	_assert_true(overlap_seen, "both groups coexist on the living course during the round")

	# Drain any last presentation-only work after physical authority has completed.
	session.drain_visuals_immediate()

	_assert_equal(str(group_1.status), "FINISHED", "mixed player group completes all three holes")
	_assert_equal(str(group_2.status), "FINISHED", "autonomous group completes all three holes")
	_assert_equal(int(runtime.traffic.group_hole(PLAYER_GROUP)), 0, "player group clears course traffic after round")
	_assert_equal(int(runtime.traffic.group_hole(OTHER_GROUP)), 0, "autonomous group clears course traffic after round")
	_assert_true(runtime.live_sessions.is_empty(), "no live hole sessions remain after both rounds")
	_assert_true(runtime.blocked_transitions.is_empty(), "no blocked inter-hole transitions remain after both rounds")

	var live_start_count: int = 0
	var live_finish_count: int = 0
	var live_shot_count: int = 0
	var ai_turns: int = 0
	var inter_hole_wait_count: int = 0
	var safe_follow_release_seen: bool = false
	var authority_provenance_ok: bool = true
	var authority_decision_ids_ok: bool = true
	var authority_shots: Dictionary = {}

	for event_value in runtime.event_history:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		var event_type: String = str(event.get("type", ""))
		if event_type == "LIVE_HOLE_START":
			live_start_count += 1
		elif event_type == "LIVE_HOLE_FINISH":
			live_finish_count += 1
		elif event_type == "LIVE_INTER_HOLE_WAIT":
			inter_hole_wait_count += 1
		elif event_type == "LIVE_TEE_RELEASE" and str(event.get("group_id", "")) == OTHER_GROUP and bool(event.get("released", false)):
			var spacing: Dictionary = event.get("spacing", {})
			if bool(spacing.get("safe", false)):
				safe_follow_release_seen = true
		elif event_type == "LIVE_SHOT":
			live_shot_count += 1
			var event_group: String = str(event.get("group_id", ""))
			var member_index: int = int(event.get("member_index", -1))
			var expected_source: String = "HUMAN" if event_group == PLAYER_GROUP and member_index == HUMAN_MEMBER else "AI"
			if str(event.get("choice_source", "")) != expected_source or str(event.get("control_source", "")) != expected_source:
				authority_provenance_ok = false
			if str(event.get("decision_id", "")).is_empty():
				authority_decision_ids_ok = false
			if expected_source == "AI":
				ai_turns += 1
			var key: String = _shot_key(event)
			if authority_shots.has(key):
				authority_provenance_ok = false
			else:
				authority_shots[key] = event.duplicate(true)

	_assert_equal(live_start_count, 6, "two groups start exactly three authoritative holes each")
	_assert_equal(live_finish_count, 6, "two groups finish exactly three authoritative holes each")
	_assert_true(live_shot_count > 0, "full round records real shot-progressive golf events")
	_assert_true(human_turns > 0, "human participates across the full living round")
	_assert_true(ai_turns > 0, "AI partners and autonomous group participate across the full living round")
	_assert_equal(live_shot_count, human_turns + ai_turns, "every live shot is attributable to exactly one human or AI turn")
	_assert_true(authority_provenance_ok, "all live shots preserve correct HUMAN versus AI authority provenance")
	_assert_true(authority_decision_ids_ok, "every live shot retains authoritative decision identity")
	_assert_true(safe_follow_release_seen, "following group enters first hole only through mechanically safe live release")

	var round_history_provenance_ok: bool = true
	for group_value in [group_1, group_2]:
		var group = group_value
		_assert_equal(group.rounds.size(), 2, "%s retains two ordinary golfer rounds" % str(group.group_id))
		for member_index in range(group.rounds.size()):
			var autonomous_round = group.rounds[member_index]
			_assert_true(autonomous_round != null and autonomous_round.round_state != null, "%s member %d retains authoritative round state" % [str(group.group_id), member_index])
			if autonomous_round == null or autonomous_round.round_state == null:
				continue
			_assert_true(autonomous_round.round_state.complete, "%s member %d completes round state" % [str(group.group_id), member_index])
			_assert_equal(autonomous_round.round_state.holes_completed(), 3, "%s member %d records all three holes" % [str(group.group_id), member_index])
			_assert_equal(autonomous_round.hole_results.size(), 3, "%s member %d owns three authoritative hole results" % [str(group.group_id), member_index])
			var expected_source: String = "HUMAN" if str(group.group_id) == PLAYER_GROUP and member_index == HUMAN_MEMBER else "AI"
			for hole_result_value in autonomous_round.hole_results:
				if typeof(hole_result_value) != TYPE_DICTIONARY:
					round_history_provenance_ok = false
					continue
				var hole_result: Dictionary = hole_result_value
				if not bool(hole_result.get("finished", false)) or not bool(hole_result.get("recorded", false)):
					round_history_provenance_ok = false
				for shot_value in hole_result.get("history", []):
					if typeof(shot_value) != TYPE_DICTIONARY or str(shot_value.get("choice_source", "")) != expected_source:
						round_history_provenance_ok = false
	_assert_true(round_history_provenance_ok, "authoritative completed-round histories preserve human versus AI provenance")

	var completed_playbacks: Array = session.completed_playbacks
	_assert_equal(completed_playbacks.size(), 6, "presentation retires exactly one playback for each group-hole")
	var playback_holes: Dictionary = {PLAYER_GROUP: {}, OTHER_GROUP: {}}
	var presented_shot_count: int = 0
	var presented_keys: Dictionary = {}
	var playback_exact_ok: bool = true

	for playback_value in completed_playbacks:
		if typeof(playback_value) != TYPE_DICTIONARY:
			playback_exact_ok = false
			continue
		var playback: Dictionary = playback_value
		var playback_group: String = str(playback.get("group_id", ""))
		var playback_hole: int = int(playback.get("hole_number", 0))
		if not playback_holes.has(playback_group) or playback_hole < 1 or playback_hole > 3:
			playback_exact_ok = false
			continue
		playback_holes[playback_group][playback_hole] = int(playback_holes[playback_group].get(playback_hole, 0)) + 1
		for presented_value in playback.get("presented_events", []):
			if typeof(presented_value) != TYPE_DICTIONARY:
				playback_exact_ok = false
				continue
			var presented: Dictionary = presented_value
			presented_shot_count += 1
			var key: String = _shot_key(presented)
			if presented_keys.has(key) or not authority_shots.has(key):
				playback_exact_ok = false
				continue
			presented_keys[key] = true
			var authority_event: Dictionary = authority_shots[key]
			var authoritative_landing = authority_event.get("shot", {}).get("landing_position", null)
			var presented_landing = presented.get("shot", {}).get("landing_position", null)
			if typeof(authoritative_landing) != TYPE_VECTOR3 or presented_landing != authoritative_landing:
				playback_exact_ok = false
				continue
			var expected_world: Vector3 = world.world_position(int(authority_event.get("hole_number", 0)), authoritative_landing)
			if presented.get("world_shot", {}).get("landing_position", Vector3.INF) != expected_world:
				playback_exact_ok = false

	for group_id in playback_holes.keys():
		for hole_number in range(1, 4):
			if int(playback_holes[group_id].get(hole_number, 0)) != 1:
				playback_exact_ok = false

	_assert_equal(presented_shot_count, live_shot_count, "every authoritative live shot is presented exactly once")
	_assert_equal(presented_keys.size(), authority_shots.size(), "presentation keyset matches authoritative live-shot keyset one-for-one")
	_assert_true(playback_exact_ok, "playback preserves exact authoritative landings with presentation-only world translation")
	_assert_equal(str(view.group_visual(PLAYER_GROUP).projected_status), "FINISHED", "player group spectator visual finishes coherently")
	_assert_equal(str(view.group_visual(OTHER_GROUP).projected_status), "FINISHED", "autonomous group spectator visual finishes coherently")

	print("POC26F_FULL_MIXED_ROUND_SUMMARY time=%.1f starts=%d finishes=%d playbacks=%d live_shots=%d human_turns=%d ai_turns=%d overlap=%s same_hole_overlap=%s inter_hole_waits=%d think_wait=%.0f processed=%d iterations=%d" % [
		runtime.current_time_seconds,
		live_start_count,
		live_finish_count,
		completed_playbacks.size(),
		live_shot_count,
		human_turns,
		ai_turns,
		str(overlap_seen),
		str(same_hole_overlap_seen),
		inter_hole_wait_count,
		THINK_WAIT_SECONDS if think_wait_performed else 0.0,
		processed_event_count,
		iterations
	])
	_finish()


func _round_world_complete(runtime, group_1, group_2) -> bool:
	if str(group_1.status) != "FINISHED" or str(group_2.status) != "FINISHED":
		return false
	if int(runtime.traffic.group_hole(PLAYER_GROUP)) != 0 or int(runtime.traffic.group_hole(OTHER_GROUP)) != 0:
		return false
	return runtime.live_sessions.is_empty() and runtime.blocked_transitions.is_empty()


func _preferred_human_candidate(decision: Dictionary) -> int:
	var choices: Array = decision.get("choices", [])
	if str(decision.get("decision_kind", "")) == "PUTTING":
		for index in range(choices.size()):
			if typeof(choices[index]) == TYPE_DICTIONARY:
				var choice: Dictionary = choices[index]
				if bool(choice.get("human_selectable", false)) and str(choice.get("putting_strategy", "")) == "NEUTRAL":
					return int(choice.get("index", index))
	for index in range(choices.size()):
		if typeof(choices[index]) == TYPE_DICTIONARY and bool(choices[index].get("human_selectable", false)):
			return int(choices[index].get("index", index))
	return -1


func _shot_key(event: Dictionary) -> String:
	return "%s|H%d|M%d|S%d" % [
		str(event.get("group_id", "")),
		int(event.get("hole_number", 0)),
		int(event.get("member_index", -1)),
		int(event.get("shot_number", 0))
	]


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


func _assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


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
		print("POC-26F FULL TWO-GROUP THREE-HOLE MIXED PARTICIPATION ROUND PASSED")
		quit(0)
	else:
		push_error("POC-26F FULL TWO-GROUP THREE-HOLE MIXED PARTICIPATION ROUND FAILED: %d" % failures)
		quit(1)

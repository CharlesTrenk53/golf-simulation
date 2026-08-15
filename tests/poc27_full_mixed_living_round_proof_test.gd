extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const ParticipateSpectatorSession = preload("res://scenes/participate_spectator_session.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const PLAYER_GROUP := "player_group"
const AUTO_GROUPS := ["auto_group_1", "auto_group_2", "auto_group_3"]
const GROUP_IDS := [PLAYER_GROUP, "auto_group_1", "auto_group_2", "auto_group_3"]
const HUMAN_MEMBER := 0
const STEP_SECONDS := 30.0
const THINK_WAIT_SECONDS := 300.0
const MAX_ITERATIONS := 3500

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27F: full 18-hole mixed living-round closure proof")

	var course = POC27Course.build()
	_assert_true(course != null, "POC-27 18-hole living course builds for final proof")
	if course == null:
		_finish()
		return
	_assert_equal_int(course.hole_count(), 18, "final proof uses the complete 18-hole course")

	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "ordinary shot-progressive living authority configures unchanged")

	var player_golfers := [
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_new_golfer(Golfer.GolferProfile.WILD_BILL),
		_new_golfer(Golfer.GolferProfile.RECKLESS_RICK),
		_new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	]
	_assert_true(runtime.add_group(PLAYER_GROUP, player_golfers, "default", HUMAN_MEMBER, 40100), "human golfer joins one ordinary foursome")
	_assert_true(runtime.add_group(AUTO_GROUPS[0], _twosome(0), "default", -1, 41100), "first autonomous twosome joins same living course")
	_assert_true(runtime.add_group(AUTO_GROUPS[1], _twosome(1), "default", -1, 42100), "second autonomous twosome joins same living course")
	_assert_true(runtime.add_group(AUTO_GROUPS[2], _twosome(2), "default", -1, 43100), "third autonomous twosome joins same living course")
	_assert_equal_int(runtime.living_course.population.group_count(), 4, "four ordinary groups share one course population")
	_assert_equal_int(int(runtime.group_controls[PLAYER_GROUP].get("human_member_index", -1)), HUMAN_MEMBER, "human designation remains ordinary group configuration")

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	created_nodes.append(world)
	_assert_true(world.configure(course), "shared spectator world configures for all 18 holes")

	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	created_nodes.append(view)
	_assert_true(view.configure(world, runtime), "presentation binds all four authoritative groups")
	_assert_equal_int(view.group_visuals.size(), 4, "every living group owns one persistent presentation visual")

	var session = ParticipateSpectatorSession.new()
	get_root().add_child(session)
	created_nodes.append(session)
	_assert_true(session.configure(runtime, world, view), "participate session bridges final mixed round to presentation")

	var opening: Dictionary = session.start_session()
	_assert_true(not opening.is_empty(), "final mixed round starts through normal first-tee release")
	_assert_equal_str(str(opening.get("group_id", "")), PLAYER_GROUP, "player group remains first in ordinary FIFO tee order")
	var blocked_follower: Dictionary = runtime.release_next_group()
	_assert_true(not bool(blocked_follower.get("released", false)), "first autonomous follower initially obeys live tee-safety gate")
	_assert_equal_str(str(blocked_follower.get("group_id", "")), AUTO_GROUPS[0], "blocked follower remains next in FIFO queue")

	var player_group = runtime.living_course.population.group_by_id(PLAYER_GROUP)
	_assert_true(player_group != null, "player group retains ordinary living-course identity")
	if player_group == null:
		_finish()
		return

	var player_holes_seen: Dictionary = {}
	var human_decision_holes: Dictionary = {}
	var human_shot_holes: Dictionary = {}
	var think_wait_performed: bool = false
	var think_wait_other_progress: bool = false
	var same_hole_overlap_seen: bool = false
	var multiple_holes_occupied_seen: bool = false
	var max_live_groups: int = 0
	var max_occupied_holes: int = 0
	var max_active_playbacks: int = 0
	var max_completed_playbacks: int = 0
	var human_turns: int = 0
	var iterations: int = 0

	while iterations < MAX_ITERATIONS and not _world_complete(runtime):
		iterations += 1

		for group_id in GROUP_IDS:
			if runtime.live_sessions.has(group_id):
				var live_session = runtime.live_sessions[group_id]
				if live_session != null and live_session.has_failed():
					push_error("POC27F FAILED SESSION group=%s snapshot=%s" % [group_id, str(live_session.snapshot())])
					failures += 1
					_finish()
					return

		var player_hole: int = int(runtime.traffic.group_hole(PLAYER_GROUP))
		if player_hole > 0:
			player_holes_seen[player_hole] = true

		var occupancy := _occupancy_snapshot(runtime, course.hole_count())
		max_live_groups = maxi(max_live_groups, int(occupancy.get("live_groups", 0)))
		max_occupied_holes = maxi(max_occupied_holes, int(occupancy.get("occupied_holes", 0)))
		if bool(occupancy.get("same_hole_overlap", false)):
			same_hole_overlap_seen = true
		if int(occupancy.get("occupied_holes", 0)) >= 2:
			multiple_holes_occupied_seen = true

		max_active_playbacks = maxi(max_active_playbacks, session.active_playbacks.size())
		max_completed_playbacks = maxi(max_completed_playbacks, session.completed_playbacks.size())

		var decision: Dictionary = session.pending_human_decision(PLAYER_GROUP)
		if not decision.is_empty():
			var decision_hole: int = player_hole if player_hole > 0 else player_group.current_hole_number()
			human_decision_holes[decision_hole] = true

			if not think_wait_performed and decision_hole >= 2 and _any_autonomous_group_live(runtime):
				var before_time: float = runtime.current_time_seconds
				var before_player_shots: int = runtime.group_live_shot_count(PLAYER_GROUP)
				var before_auto_shots: int = _autonomous_shot_count(runtime)
				var before_decision_id: String = str(decision.get("decision_id", ""))
				var human_round = player_group.rounds[HUMAN_MEMBER]
				var before_ball: Vector3 = human_round.active_hole_state.ball_position
				var before_strokes: int = int(human_round.active_hole_state.strokes)

				session.advance_time(THINK_WAIT_SECONDS, false)
				think_wait_performed = true
				_assert_near(runtime.current_time_seconds, before_time + THINK_WAIT_SECONDS, 0.0001, "global course clock advances through deliberate full-round human think time")
				_assert_equal_int(runtime.group_live_shot_count(PLAYER_GROUP), before_player_shots, "player group cannot autoplay through pending human decision")
				_assert_true(human_round.active_hole_state.ball_position == before_ball, "human authoritative lie remains fixed while deciding")
				_assert_equal_int(int(human_round.active_hole_state.strokes), before_strokes, "human authoritative stroke count remains fixed while deciding")
				var after_wait_decision: Dictionary = session.pending_human_decision(PLAYER_GROUP)
				_assert_equal_str(str(after_wait_decision.get("decision_id", "")), before_decision_id, "same human decision survives autonomous world activity")
				think_wait_other_progress = _autonomous_shot_count(runtime) > before_auto_shots
				_assert_true(think_wait_other_progress, "autonomous groups continue real golf while human thinks")
				decision = after_wait_decision

			var candidate_index: int = _preferred_human_candidate(decision)
			_assert_true(candidate_index >= 0, "pending human decision exposes a deterministic selectable choice")
			if candidate_index < 0:
				break
			var submitted: Dictionary = session.submit_human_choice(PLAYER_GROUP, candidate_index, false)
			_assert_true(bool(submitted.get("played", false)), "human intent executes through shared authoritative decision contract")
			if not bool(submitted.get("played", false)):
				break
			human_turns += 1
			var shot_event: Dictionary = submitted.get("shot_event", {})
			human_shot_holes[int(shot_event.get("hole_number", decision_hole))] = true
			continue

		var emitted: Array = session.advance_time(STEP_SECONDS, false)
		var residual: int = session.drain_visuals_immediate()
		if residual != 0:
			push_error("POC27F unexpected residual presentation work after immediate advance: %d" % residual)
			failures += 1

		if iterations <= 10 or iterations % 100 == 0:
			print("POC27F PROGRESS iteration=%d time=%.1f player_hole=%d live_groups=%d occupied_holes=%d emitted=%d authority_events=%d playbacks=%d" % [
				iterations,
				runtime.current_time_seconds,
				int(runtime.traffic.group_hole(PLAYER_GROUP)),
				int(occupancy.get("live_groups", 0)),
				int(occupancy.get("occupied_holes", 0)),
				emitted.size(),
				runtime.event_history.size(),
				session.completed_playbacks.size()
			])

	session.drain_visuals_immediate()

	_assert_true(iterations < MAX_ITERATIONS, "full mixed 18-hole living round remains bounded")
	_assert_true(_world_complete(runtime), "all four groups finish and leave the authoritative course")
	_assert_true(think_wait_performed, "closure proof includes deliberate human think time")
	_assert_true(think_wait_other_progress, "living world remains active during that human think time")
	_assert_equal_int(player_holes_seen.size(), 18, "same ordinary player group reaches all 18 holes")
	_assert_equal_int(human_decision_holes.size(), 18, "human receives authoritative decision opportunities on every hole")
	_assert_equal_int(human_shot_holes.size(), 18, "human executes authoritative golf on every hole")
	_assert_true(human_decision_holes.has(2) and human_decision_holes.has(17), "late-round player decisions use the same seam as early-round decisions")
	_assert_true(max_live_groups >= 3, "several groups coexist live on the course")
	_assert_true(max_occupied_holes >= 2 and multiple_holes_occupied_seen, "living population spreads across multiple holes")
	_assert_true(same_hole_overlap_seen, "mechanically safe same-hole concurrency occurs during final proof")
	_assert_true(max_active_playbacks >= 3 and max_active_playbacks <= GROUP_IDS.size(), "presentation concurrently tracks several live groups without unbounded playback state")
	_assert_true(max_completed_playbacks <= GROUP_IDS.size() * 18, "retired presentation state remains bounded by completed group-holes")

	var release_count: int = 0
	var release_ids: Array = []
	var safe_follower_release_count: int = 0
	var mechanical_release_ok: bool = true
	var live_start_count: int = 0
	var live_finish_count: int = 0
	var player_start_count: int = 0
	var player_finish_count: int = 0
	var wait_count: int = 0
	var human_live_shots: int = 0
	var ai_live_shots: int = 0
	var authority_provenance_ok: bool = true
	var authority_shots: Dictionary = {}

	for event_value in runtime.event_history:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		var event_type: String = str(event.get("type", ""))
		match event_type:
			"LIVE_TEE_RELEASE":
				if bool(event.get("released", false)):
					release_count += 1
					release_ids.append(str(event.get("group_id", "")))
					if release_count > 1:
						var spacing: Dictionary = event.get("spacing", {})
						if str(event.get("reason", "")) != "SAFE_LIVE_SPACING" or not bool(spacing.get("safe", false)) or str(spacing.get("release_rule", "")) != "RANGE_SAFE_AND_ALL_LEAD_GOLFERS_ON_GREEN":
							mechanical_release_ok = false
						else:
							safe_follower_release_count += 1
			"LIVE_HOLE_START":
				live_start_count += 1
				if str(event.get("group_id", "")) == PLAYER_GROUP:
					player_start_count += 1
			"LIVE_HOLE_FINISH":
				live_finish_count += 1
				if str(event.get("group_id", "")) == PLAYER_GROUP:
					player_finish_count += 1
			"LIVE_INTER_HOLE_WAIT":
				wait_count += 1
			"LIVE_SHOT":
				var event_group: String = str(event.get("group_id", ""))
				var member_index: int = int(event.get("member_index", -1))
				var expected_source: String = "HUMAN" if event_group == PLAYER_GROUP and member_index == HUMAN_MEMBER else "AI"
				if str(event.get("control_source", "")) != expected_source or str(event.get("choice_source", "")) != expected_source or str(event.get("decision_id", "")).is_empty():
					authority_provenance_ok = false
				if expected_source == "HUMAN":
					human_live_shots += 1
				else:
					ai_live_shots += 1
				var key: String = _shot_key(event)
				if authority_shots.has(key):
					authority_provenance_ok = false
				else:
					authority_shots[key] = event.duplicate(true)

	_assert_equal_int(release_count, GROUP_IDS.size(), "every group receives exactly one first-tee release")
	_assert_true(release_ids == GROUP_IDS, "all first-tee releases preserve FIFO identity")
	_assert_true(mechanical_release_ok and safe_follower_release_count == GROUP_IDS.size() - 1, "every autonomous follower enters through the unchanged POC-24 mechanical safety contract")
	_assert_equal_int(live_start_count, GROUP_IDS.size() * 18, "four groups start exactly 18 authoritative holes each")
	_assert_equal_int(live_finish_count, GROUP_IDS.size() * 18, "four groups finish exactly 18 authoritative holes each")
	_assert_equal_int(player_start_count, 18, "player group starts all 18 authoritative holes")
	_assert_equal_int(player_finish_count, 18, "player group finishes all 18 authoritative holes")
	_assert_true(wait_count > 0, "real inter-hole traffic waits emerge during the final mixed round")
	_assert_true(authority_provenance_ok, "every authoritative shot retains unique decision identity and correct HUMAN/AI provenance")
	_assert_true(human_live_shots == human_turns and human_live_shots > 18, "every scripted human turn maps one-to-one to an authoritative human shot")
	_assert_true(ai_live_shots > human_live_shots, "AI partners and autonomous groups remain the majority of world golf activity")
	_assert_true(authority_shots.size() >= 500, "final proof contains hundreds of authoritative shots across the living course")

	var human_round = player_group.rounds[HUMAN_MEMBER]
	_assert_true(human_round.round_state.complete, "human RoundState completes after Hole 18")
	_assert_equal_int(human_round.round_state.holes_completed(), 18, "human RoundState records all 18 holes")
	_assert_true(human_round.round_state.front_nine_complete(), "human scorecard completes the front nine")
	_assert_true(human_round.round_state.back_nine_complete(), "human scorecard completes the back nine")
	_assert_equal_str(human_round.round_state.round_phase(), "COMPLETE", "human full-round phase is COMPLETE")
	var scorecard: Array = human_round.round_state.scorecard()
	_assert_equal_int(scorecard.size(), 18, "human retains one complete 18-hole scorecard")
	var scorecard_valid: bool = true
	for row_value in scorecard:
		if typeof(row_value) != TYPE_DICTIONARY:
			scorecard_valid = false
			continue
		var row: Dictionary = row_value
		if not bool(row.get("completed", false)) or int(row.get("strokes", -1)) <= 0:
			scorecard_valid = false
	_assert_true(scorecard_valid, "every human scorecard row contains a completed positive stroke total")
	_assert_equal_int(human_round.hole_results.size(), 18, "human retains 18 authoritative hole histories")

	for group_id in GROUP_IDS:
		var group = runtime.living_course.population.group_by_id(group_id)
		_assert_true(group != null, "%s retains stable group identity through the full day" % group_id)
		if group == null:
			continue
		_assert_equal_str(str(group.status), "FINISHED", "%s finishes normally" % group_id)
		_assert_equal_int(runtime.traffic.group_hole(group_id), 0, "%s clears traffic after Hole 18" % group_id)
		for autonomous_round in group.rounds:
			_assert_true(autonomous_round.round_state.complete, "%s member RoundState completes" % group_id)
			_assert_equal_int(autonomous_round.round_state.holes_completed(), 18, "%s member records all 18 holes" % group_id)
			_assert_equal_int(autonomous_round.hole_results.size(), 18, "%s member retains 18 authoritative hole results" % group_id)

	var completed: Array = session.completed_playbacks
	_assert_equal_int(completed.size(), GROUP_IDS.size() * 18, "presentation retires exactly one playback per group-hole")
	var playback_holes: Dictionary = {}
	for group_id in GROUP_IDS:
		playback_holes[group_id] = {}
	var presented_keys: Dictionary = {}
	var presented_count: int = 0
	var presentation_exact_ok: bool = true

	for playback_value in completed:
		if typeof(playback_value) != TYPE_DICTIONARY:
			presentation_exact_ok = false
			continue
		var playback: Dictionary = playback_value
		var playback_group: String = str(playback.get("group_id", ""))
		var hole_number: int = int(playback.get("hole_number", 0))
		if not playback_holes.has(playback_group) or hole_number < 1 or hole_number > 18:
			presentation_exact_ok = false
			continue
		playback_holes[playback_group][hole_number] = int(playback_holes[playback_group].get(hole_number, 0)) + 1
		if int(playback.get("queued_event_count", -1)) != 0 or bool(playback.get("active_flight", false)) or not playback.get("tee_dispersion", {}).is_empty():
			presentation_exact_ok = false
		for presented_value in playback.get("presented_events", []):
			if typeof(presented_value) != TYPE_DICTIONARY:
				presentation_exact_ok = false
				continue
			var presented: Dictionary = presented_value
			presented_count += 1
			var key: String = _shot_key(presented)
			if presented_keys.has(key) or not authority_shots.has(key):
				presentation_exact_ok = false
				continue
			presented_keys[key] = true
			var authority_event: Dictionary = authority_shots[key]
			var authoritative_landing = authority_event.get("shot", {}).get("landing_position", null)
			var presented_landing = presented.get("shot", {}).get("landing_position", null)
			var world_landing = presented.get("world_shot", {}).get("landing_position", null)
			if typeof(authoritative_landing) != TYPE_VECTOR3 or presented_landing != authoritative_landing:
				presentation_exact_ok = false
				continue
			var expected_world: Vector3 = world.world_position(hole_number, authoritative_landing)
			if typeof(world_landing) != TYPE_VECTOR3 or world_landing != expected_world:
				presentation_exact_ok = false

	for group_id in GROUP_IDS:
		_assert_equal_int(playback_holes[group_id].size(), 18, "%s owns one retired playback for every hole" % group_id)
		for hole_number in range(1, 19):
			if int(playback_holes[group_id].get(hole_number, 0)) != 1:
				presentation_exact_ok = false

	_assert_equal_int(presented_count, authority_shots.size(), "every authoritative shot is presented exactly once")
	_assert_equal_int(presented_keys.size(), authority_shots.size(), "presentation shot keyset matches authority one-for-one")
	_assert_true(presentation_exact_ok, "presentation preserves exact authoritative landings with no duplicate, skipped, queued, or stale playback work")
	_assert_true(session.active_playbacks.is_empty(), "no active playback objects remain after all golfers exit")
	_assert_true(session.pending_next_hole.is_empty(), "no pending next-hole presentation state remains after finish")
	_assert_true(not session.presentation_busy(), "presentation is fully caught up at final world state")
	_assert_true(runtime.live_sessions.is_empty(), "no authoritative live sessions remain after all groups finish")
	_assert_true(runtime.blocked_transitions.is_empty(), "no authoritative blocked transitions remain after all groups finish")

	for group_id in GROUP_IDS:
		var visual = view.group_visual(group_id)
		_assert_true(visual != null, "%s final presentation visual still exists" % group_id)
		if visual == null:
			continue
		_assert_equal_str(str(visual.projected_status), "FINISHED", "%s visual final status matches authority" % group_id)
		_assert_equal_int(int(visual.projected_hole_number), 18, "%s visual finishes associated with Hole 18" % group_id)
		_assert_true(not visual.has_active_inter_hole_transition(), "%s has no stale inter-hole motion" % group_id)
		_assert_true(visual.active_member_shots.is_empty(), "%s has no stale member-shot visual state" % group_id)

	print("POC27F_FULL_MIXED_LIVING_ROUND_SUMMARY time=%.1f groups=%d golfers=%d starts=%d finishes=%d shots=%d human_shots=%d ai_shots=%d waits=%d playbacks=%d presented=%d player_score=%d player_to_par=%+d max_live=%d max_holes=%d iterations=%d" % [
		runtime.current_time_seconds,
		GROUP_IDS.size(),
		10,
		live_start_count,
		live_finish_count,
		authority_shots.size(),
		human_live_shots,
		ai_live_shots,
		wait_count,
		completed.size(),
		presented_count,
		human_round.round_state.total_strokes(),
		human_round.round_state.score_to_par(),
		max_live_groups,
		max_occupied_holes,
		iterations
	])
	_finish()


func _occupancy_snapshot(runtime, hole_count: int) -> Dictionary:
	var occupied_holes: int = 0
	var live_groups: int = 0
	var same_hole_overlap: bool = false
	for hole_number in range(1, hole_count + 1):
		var occupants: Array = runtime.traffic.groups_on_hole(hole_number)
		if occupants.is_empty():
			continue
		occupied_holes += 1
		live_groups += occupants.size()
		if occupants.size() >= 2:
			same_hole_overlap = true
	return {
		"occupied_holes": occupied_holes,
		"live_groups": live_groups,
		"same_hole_overlap": same_hole_overlap
	}


func _any_autonomous_group_live(runtime) -> bool:
	for group_id in AUTO_GROUPS:
		var group = runtime.living_course.population.group_by_id(group_id)
		if group != null and str(group.status) != "FINISHED" and runtime.traffic.group_hole(group_id) > 0:
			return true
	return false


func _autonomous_shot_count(runtime) -> int:
	var total: int = 0
	for group_id in AUTO_GROUPS:
		total += runtime.group_live_shot_count(group_id)
	return total


func _world_complete(runtime) -> bool:
	for group_id in GROUP_IDS:
		var group = runtime.living_course.population.group_by_id(group_id)
		if group == null or str(group.status) != "FINISHED":
			return false
		if runtime.traffic.group_hole(group_id) != 0:
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


func _twosome(offset: int) -> Array:
	var profiles := [Golfer.GolferProfile.WILD_BILL, Golfer.GolferProfile.RECKLESS_RICK, Golfer.GolferProfile.CAREFUL_CARL]
	return [
		_new_golfer(int(profiles[offset % profiles.size()])),
		_new_golfer(int(profiles[(offset + 1) % profiles.size()]))
	]


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
		print("PASS: %s (actual=%.4f expected=%.4f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.4f expected=%.4f)" % [label, actual, expected])


func _finish() -> void:
	for node in created_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("POC-27F FULL 18-HOLE MIXED LIVING-ROUND PROOF PASSED")
		quit(0)
	else:
		push_error("POC-27F FULL 18-HOLE MIXED LIVING-ROUND PROOF FAILED: %d" % failures)
		quit(1)

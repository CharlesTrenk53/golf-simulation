extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const ParticipateSpectatorSession = preload("res://scenes/participate_spectator_session.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const GROUP_IDS := ["group_1", "group_2"]
const STEP_SECONDS := 30.0
const MAX_ITERATIONS := 1800

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27E: long-session presentation integrity over a full 18-hole living round")

	var course = POC27Course.build()
	_assert_true(course != null, "POC-27 18-hole course builds for presentation stress")
	if course == null:
		_finish()
		return

	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "shot-progressive living authority configures unchanged")
	_assert_true(runtime.add_group("group_1", _foursome(0), "default", -1, 37100), "first autonomous foursome joins ordinary living course")
	_assert_true(runtime.add_group("group_2", _foursome(1), "default", -1, 38100), "second autonomous foursome joins ordinary living course")

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	created_nodes.append(world)
	_assert_true(world.configure(course), "shared spectator world configures for all 18 holes")

	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	created_nodes.append(view)
	_assert_true(view.configure(world, runtime), "population presentation binds authoritative two-group course")
	_assert_equal_int(view.group_visuals.size(), 2, "both groups receive persistent presentation visuals")

	var session = ParticipateSpectatorSession.new()
	get_root().add_child(session)
	created_nodes.append(session)
	_assert_true(session.configure(runtime, world, view), "participate presentation session binds long-lived authority")

	var opening: Dictionary = session.start_session()
	_assert_true(not opening.is_empty(), "presentation session starts through normal first-tee release")
	_assert_equal_str(str(opening.get("group_id", "")), "group_1", "presentation preserves FIFO opening group")

	var iterations: int = 0
	var max_active_playbacks: int = 0
	var max_completed_playbacks: int = 0
	var max_session_event_log: int = 0
	var visual_alignment_ok: bool = true
	var queues_drain_ok: bool = true
	var stale_motion_ok: bool = true
	var seen_projected_holes := {
		"group_1": {},
		"group_2": {}
	}

	while iterations < MAX_ITERATIONS and not _world_complete(runtime):
		iterations += 1
		var emitted: Array = session.advance_time(STEP_SECONDS, false)
		var residual_presented: int = session.drain_visuals_immediate()

		max_active_playbacks = maxi(max_active_playbacks, session.active_playbacks.size())
		max_completed_playbacks = maxi(max_completed_playbacks, session.completed_playbacks.size())
		max_session_event_log = maxi(max_session_event_log, session.event_log.size())

		for playback_value in session.active_playbacks.values():
			if playback_value == null:
				continue
			var playback_snapshot: Dictionary = playback_value.snapshot()
			if int(playback_snapshot.get("queued_event_count", -1)) != 0:
				queues_drain_ok = false
			if bool(playback_snapshot.get("active_flight", false)):
				stale_motion_ok = false
			if not playback_snapshot.get("tee_dispersion", {}).is_empty():
				stale_motion_ok = false

		for group_id in GROUP_IDS:
			var visual = view.group_visual(group_id)
			if visual == null:
				visual_alignment_ok = false
				continue
			var traffic_hole: int = runtime.traffic.group_hole(group_id)
			if traffic_hole > 0:
				if int(visual.projected_hole_number) != traffic_hole:
					visual_alignment_ok = false
				else:
					seen_projected_holes[group_id][traffic_hole] = true
			if visual.has_active_inter_hole_transition():
				stale_motion_ok = false
			if not visual.active_member_shots.is_empty():
				stale_motion_ok = false

		if iterations <= 10 or iterations % 100 == 0:
			print("POC27E PROGRESS iteration=%d time=%.1f emitted=%d residual=%d authority_events=%d session_events=%d active_playbacks=%d completed=%d" % [
				iterations,
				runtime.current_time_seconds,
				emitted.size(),
				residual_presented,
				runtime.event_history.size(),
				session.event_log.size(),
				session.active_playbacks.size(),
				session.completed_playbacks.size()
			])

	session.drain_visuals_immediate()

	_assert_true(iterations < MAX_ITERATIONS, "18-hole presentation stress remains bounded")
	_assert_true(_world_complete(runtime), "both authoritative groups finish all 18 holes")
	_assert_true(visual_alignment_ok, "presentation hole projection never leaks an old hole after immediate catch-up")
	_assert_true(queues_drain_ok, "per-group presentation queues drain throughout the long session")
	_assert_true(stale_motion_ok, "no stale flight, tee-dispersion, or inter-hole motion survives a catch-up boundary")
	_assert_true(max_active_playbacks <= GROUP_IDS.size(), "active playback state stays bounded by live group count")
	_assert_true(max_active_playbacks >= 2, "both groups own presentation playback concurrently during the round")
	_assert_true(max_completed_playbacks <= GROUP_IDS.size() * 18, "retired playback state stays bounded by completed group-holes")

	for group_id in GROUP_IDS:
		_assert_equal_int(seen_projected_holes[group_id].size(), 18, "%s presentation projects every hole exactly within the same long session" % group_id)

	var authority_shots: Dictionary = {}
	var live_start_count: int = 0
	var live_finish_count: int = 0
	for event_value in runtime.event_history:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		match str(event.get("type", "")):
			"LIVE_HOLE_START": live_start_count += 1
			"LIVE_HOLE_FINISH": live_finish_count += 1
			"LIVE_SHOT":
				var key: String = _shot_key(event)
				if authority_shots.has(key):
					failures += 1
					push_error("FAIL: duplicate authoritative shot key " + key)
				else:
					authority_shots[key] = event.duplicate(true)

	_assert_equal_int(live_start_count, 36, "two groups start exactly 18 authoritative holes each")
	_assert_equal_int(live_finish_count, 36, "two groups finish exactly 18 authoritative holes each")
	_assert_true(authority_shots.size() >= 300, "long session contains hundreds of authoritative shots")

	var completed: Array = session.completed_playbacks
	_assert_equal_int(completed.size(), 36, "presentation retires exactly one playback per group-hole")

	var playback_holes := {
		"group_1": {},
		"group_2": {}
	}
	var presented_keys: Dictionary = {}
	var presented_count: int = 0
	var exact_landing_ok: bool = true
	var completed_playback_clean: bool = true

	for playback_value in completed:
		if typeof(playback_value) != TYPE_DICTIONARY:
			completed_playback_clean = false
			continue
		var playback: Dictionary = playback_value
		var group_id: String = str(playback.get("group_id", ""))
		var hole_number: int = int(playback.get("hole_number", 0))
		if not playback_holes.has(group_id) or hole_number < 1 or hole_number > 18:
			completed_playback_clean = false
			continue
		playback_holes[group_id][hole_number] = int(playback_holes[group_id].get(hole_number, 0)) + 1
		if int(playback.get("queued_event_count", -1)) != 0 or bool(playback.get("active_flight", false)) or not playback.get("tee_dispersion", {}).is_empty():
			completed_playback_clean = false

		for presented_value in playback.get("presented_events", []):
			if typeof(presented_value) != TYPE_DICTIONARY:
				completed_playback_clean = false
				continue
			var presented: Dictionary = presented_value
			presented_count += 1
			var key: String = _shot_key(presented)
			if presented_keys.has(key) or not authority_shots.has(key):
				completed_playback_clean = false
				continue
			presented_keys[key] = true
			var authority_event: Dictionary = authority_shots[key]
			var authoritative_landing = authority_event.get("shot", {}).get("landing_position", null)
			var presented_landing = presented.get("shot", {}).get("landing_position", null)
			var world_landing = presented.get("world_shot", {}).get("landing_position", null)
			if typeof(authoritative_landing) != TYPE_VECTOR3 or presented_landing != authoritative_landing:
				exact_landing_ok = false
				continue
			var expected_world: Vector3 = world.world_position(hole_number, authoritative_landing)
			if typeof(world_landing) != TYPE_VECTOR3 or world_landing != expected_world:
				exact_landing_ok = false

	for group_id in GROUP_IDS:
		_assert_equal_int(playback_holes[group_id].size(), 18, "%s owns one retired playback for every hole" % group_id)
		for hole_number in range(1, 19):
			_assert_equal_int(int(playback_holes[group_id].get(hole_number, 0)), 1, "%s Hole %d playback is neither duplicated nor skipped" % [group_id, hole_number])

	_assert_true(completed_playback_clean, "retired playback snapshots contain no queued or stale visual work")
	_assert_equal_int(presented_count, authority_shots.size(), "every authoritative shot is presented exactly once across the full round")
	_assert_equal_int(presented_keys.size(), authority_shots.size(), "presentation and authority shot keysets match one-for-one")
	_assert_true(exact_landing_ok, "presentation preserves authoritative landing positions with world translation only")

	_assert_true(session.active_playbacks.is_empty(), "no active playback objects remain after both rounds finish")
	_assert_true(session.pending_next_hole.is_empty(), "no pending next-hole presentation state remains")
	_assert_true(not session.presentation_busy(), "presentation reports fully caught up at end of day")
	_assert_true(session.event_log.size() <= runtime.event_history.size() + 2, "session event retention remains linear without runaway duplication")
	_assert_true(max_session_event_log <= runtime.event_history.size() + 2, "peak session event retention remains bounded by authoritative history")

	for group_id in GROUP_IDS:
		var visual = view.group_visual(group_id)
		_assert_true(visual != null, "%s final visual still exists" % group_id)
		if visual == null:
			continue
		_assert_equal_str(str(visual.projected_status), "FINISHED", "%s final visual status matches authority" % group_id)
		_assert_equal_int(int(visual.projected_hole_number), 18, "%s final visual remains associated with completed Hole 18 rather than a stale earlier hole" % group_id)
		_assert_true(not visual.has_active_inter_hole_transition(), "%s has no stale inter-hole transition after finish" % group_id)
		_assert_true(visual.active_member_shots.is_empty(), "%s has no stale member-shot visual state after finish" % group_id)

	print("POC27E_PRESENTATION_INTEGRITY_SUMMARY time=%.1f authority_shots=%d presented=%d playbacks=%d authority_events=%d session_events=%d max_active=%d iterations=%d" % [
		runtime.current_time_seconds,
		authority_shots.size(),
		presented_count,
		completed.size(),
		runtime.event_history.size(),
		session.event_log.size(),
		max_active_playbacks,
		iterations
	])
	_finish()


func _world_complete(runtime) -> bool:
	for group_id in GROUP_IDS:
		var group = runtime.living_course.population.group_by_id(group_id)
		if group == null or str(group.status) != "FINISHED":
			return false
		if runtime.traffic.group_hole(group_id) != 0:
			return false
	return runtime.live_sessions.is_empty() and runtime.blocked_transitions.is_empty()


func _shot_key(event: Dictionary) -> String:
	return "%s|H%d|M%d|S%d" % [
		str(event.get("group_id", "")),
		int(event.get("hole_number", 0)),
		int(event.get("member_index", -1)),
		int(event.get("shot_number", 0))
	]


func _foursome(offset: int) -> Array:
	var profiles := [Golfer.GolferProfile.CAREFUL_CARL, Golfer.GolferProfile.WILD_BILL, Golfer.GolferProfile.RECKLESS_RICK, Golfer.GolferProfile.CAREFUL_CARL]
	var golfers: Array = []
	for index in range(4):
		var golfer = QuietGolfer.new()
		golfer.profile = int(profiles[(index + offset) % profiles.size()])
		golfer.apply_profile()
		get_root().add_child(golfer)
		created_nodes.append(golfer)
		golfers.append(golfer)
	return golfers


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
	for node in created_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("POC-27E LONG-SESSION PRESENTATION INTEGRITY PASSED")
		quit(0)
	else:
		push_error("POC-27E LONG-SESSION PRESENTATION INTEGRITY FAILED: %d" % failures)
		quit(1)

extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const GROUP_IDS := ["lead", "follow"]
const STEP_SECONDS := 30.0
const MAX_ITERATIONS := 2000

var created_golfers: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27C DIAGNOSTIC: two foursomes full 18-hole traffic progression")
	var course = POC27Course.build()
	assert(course != null)

	var runtime = ShotProgressiveLivingCourseController.new()
	assert(runtime.configure(course))

	assert(runtime.add_group("lead", _foursome(0), "default", -1, 27100))
	assert(runtime.add_group("follow", _foursome(1), "default", -1, 28100))
	assert(bool(runtime.release_next_group().get("released", false)))
	var blocked_initial: Dictionary = runtime.release_next_group()
	assert(not bool(blocked_initial.get("released", false)))
	print("DIAG INITIAL follow_block_reason=%s" % str(blocked_initial.get("reason", "")))

	var iterations: int = 0
	var previous_holes := {"lead": 1, "follow": 1}
	var max_live_groups: int = 0
	var max_occupied_holes: int = 0
	var saw_same_hole_overlap: bool = false
	var saw_wait: bool = false
	var saw_follow_release: bool = false

	while iterations < MAX_ITERATIONS and not _all_finished(runtime):
		iterations += 1
		if iterations <= 20 or iterations % 50 == 0:
			print("DIAG BEFORE iteration=%d time=%.1f %s" % [iterations, runtime.current_time_seconds, _world_summary(runtime)])

		var processed: Array = runtime.advance_time(STEP_SECONDS)

		if iterations <= 20 or iterations % 50 == 0:
			print("DIAG AFTER iteration=%d time=%.1f processed=%d events=%d %s" % [iterations, runtime.current_time_seconds, processed.size(), runtime.event_history.size(), _world_summary(runtime)])

		for group_id in GROUP_IDS:
			if runtime.live_sessions.has(group_id):
				var session = runtime.live_sessions[group_id]
				if session != null and session.has_failed():
					push_error("DIAG FAILED SESSION group=%s snapshot=%s" % [group_id, str(session.snapshot())])
					_cleanup_and_quit(1)
					return

		for group_id in GROUP_IDS:
			var group = runtime.living_course.population.group_by_id(group_id)
			var hole_number: int = group.current_hole_number() if group != null else -99
			if hole_number != int(previous_holes[group_id]):
				print("DIAG HOLE CHANGE group=%s from=%d to=%d time=%.1f iteration=%d" % [group_id, int(previous_holes[group_id]), hole_number, runtime.current_time_seconds, iterations])
				previous_holes[group_id] = hole_number

		var occupied_holes: int = 0
		var live_groups: int = 0
		for hole_number in range(1, 19):
			var occupants: Array = runtime.traffic.groups_on_hole(hole_number)
			if not occupants.is_empty():
				occupied_holes += 1
				live_groups += occupants.size()
				if occupants.size() >= 2:
					saw_same_hole_overlap = true
		max_live_groups = maxi(max_live_groups, live_groups)
		max_occupied_holes = maxi(max_occupied_holes, occupied_holes)

		if not runtime.blocked_transitions.is_empty():
			saw_wait = true
		var follow_group = runtime.living_course.population.group_by_id("follow")
		if follow_group != null and str(follow_group.status) != "WAITING":
			saw_follow_release = true

	assert(iterations < MAX_ITERATIONS)
	assert(_all_finished(runtime))
	assert(saw_follow_release)
	assert(saw_same_hole_overlap)
	assert(saw_wait)
	assert(max_live_groups >= 2)
	assert(max_occupied_holes >= 2)
	assert(runtime.live_sessions.is_empty())
	assert(runtime.blocked_transitions.is_empty())

	var starts: int = 0
	var finishes: int = 0
	var waits: int = 0
	var releases: int = 0
	for event_value in runtime.event_history:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		match str(event.get("type", "")):
			"LIVE_HOLE_START": starts += 1
			"LIVE_HOLE_FINISH": finishes += 1
			"LIVE_INTER_HOLE_WAIT": waits += 1
			"LIVE_TEE_RELEASE": releases += 1

	assert(starts == 36)
	assert(finishes == 36)
	assert(releases == 2)
	assert(waits > 0)
	for group_id in GROUP_IDS:
		var group = runtime.living_course.population.group_by_id(group_id)
		assert(group != null)
		assert(str(group.status) == "FINISHED")
		assert(runtime.traffic.group_hole(group_id) == 0)
		for autonomous_round in group.rounds:
			assert(autonomous_round.round_state.complete)
			assert(autonomous_round.round_state.holes_completed() == 18)
			assert(autonomous_round.hole_results.size() == 18)

	print("POC27C_TWO_GROUP_DIAG_SUMMARY starts=%d finishes=%d waits=%d releases=%d max_live=%d max_holes=%d time=%.1f iterations=%d events=%d" % [starts, finishes, waits, releases, max_live_groups, max_occupied_holes, runtime.current_time_seconds, iterations, runtime.event_history.size()])
	print("POC-27C TWO-GROUP FULL-ROUND DIAGNOSTIC PASSED")
	_cleanup_and_quit(0)


func _foursome(offset: int) -> Array:
	var profiles := [Golfer.GolferProfile.CAREFUL_CARL, Golfer.GolferProfile.WILD_BILL, Golfer.GolferProfile.RECKLESS_RICK, Golfer.GolferProfile.CAREFUL_CARL]
	var golfers: Array = []
	for index in range(4):
		var golfer = QuietGolfer.new()
		golfer.profile = int(profiles[(index + offset) % profiles.size()])
		golfer.apply_profile()
		get_root().add_child(golfer)
		created_golfers.append(golfer)
		golfers.append(golfer)
	return golfers


func _all_finished(runtime) -> bool:
	for group_id in GROUP_IDS:
		var group = runtime.living_course.population.group_by_id(group_id)
		if group == null or str(group.status) != "FINISHED":
			return false
	return true


func _world_summary(runtime) -> String:
	var group_parts: Array[String] = []
	for group_id in GROUP_IDS:
		var group = runtime.living_course.population.group_by_id(group_id)
		var status: String = str(group.status) if group != null else "MISSING"
		var current_hole: int = group.current_hole_number() if group != null else -99
		var traffic_hole: int = runtime.traffic.group_hole(group_id)
		var live: bool = runtime.live_sessions.has(group_id)
		var blocked: bool = runtime.blocked_transitions.has(group_id)
		group_parts.append("%s(status=%s,current=%d,traffic=%d,live=%s,blocked=%s)" % [group_id, status, current_hole, traffic_hole, str(live), str(blocked)])
	return "groups=[%s] waiting=%d live_sessions=%d blocked=%d" % [", ".join(group_parts), runtime.living_course.start_sequencer.waiting_group_ids().size(), runtime.live_sessions.size(), runtime.blocked_transitions.size()]


func _cleanup_and_quit(code: int) -> void:
	for golfer in created_golfers:
		if golfer != null and is_instance_valid(golfer):
			golfer.queue_free()
	quit(code)

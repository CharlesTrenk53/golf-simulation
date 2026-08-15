extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const GROUP_IDS := ["group_1", "group_2", "group_3", "group_4"]
const GROUP_SIZES := [4, 1, 3, 2]
const STEP_SECONDS := 30.0
const MAX_ITERATIONS := 3000

var created_golfers: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27C DIAGNOSTIC: four mixed-size groups full 18-hole traffic progression")
	var course = POC27Course.build()
	assert(course != null)

	var runtime = ShotProgressiveLivingCourseController.new()
	assert(runtime.configure(course))

	for group_index in range(GROUP_IDS.size()):
		assert(runtime.add_group(
			GROUP_IDS[group_index],
			_group_members(GROUP_SIZES[group_index], group_index),
			"default",
			-1,
			27000 + group_index * 1000
		))

	assert(bool(runtime.release_next_group().get("released", false)))
	var blocked_initial: Dictionary = runtime.release_next_group()
	assert(not bool(blocked_initial.get("released", false)))
	print("DIAG INITIAL next_block_reason=%s waiting=%d" % [
		str(blocked_initial.get("reason", "")),
		runtime.living_course.start_sequencer.waiting_group_ids().size()
	])

	var iterations: int = 0
	var previous_holes := {
		"group_1": 1,
		"group_2": 1,
		"group_3": 1,
		"group_4": 1
	}
	var released_groups := {
		"group_1": true,
		"group_2": false,
		"group_3": false,
		"group_4": false
	}
	var max_live_groups: int = 0
	var max_occupied_holes: int = 0
	var saw_same_hole_overlap: bool = false
	var saw_wait: bool = false

	while iterations < MAX_ITERATIONS and not _all_finished(runtime):
		iterations += 1
		if iterations <= 20 or iterations % 50 == 0:
			print("DIAG BEFORE iteration=%d time=%.1f %s" % [iterations, runtime.current_time_seconds, _world_summary(runtime)])

		var processed: Array = runtime.advance_time(STEP_SECONDS)

		if iterations <= 20 or iterations % 50 == 0:
			print("DIAG AFTER iteration=%d time=%.1f processed=%d events=%d %s" % [
				iterations,
				runtime.current_time_seconds,
				processed.size(),
				runtime.event_history.size(),
				_world_summary(runtime)
			])

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
				print("DIAG HOLE CHANGE group=%s from=%d to=%d time=%.1f iteration=%d" % [
					group_id,
					int(previous_holes[group_id]),
					hole_number,
					runtime.current_time_seconds,
					iterations
				])
				previous_holes[group_id] = hole_number
			if group != null and str(group.status) != "WAITING":
				released_groups[group_id] = true

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

	assert(iterations < MAX_ITERATIONS)
	assert(_all_finished(runtime))
	for group_id in GROUP_IDS:
		assert(bool(released_groups[group_id]))
	assert(saw_same_hole_overlap)
	assert(saw_wait)
	assert(max_live_groups >= 4)
	assert(max_occupied_holes >= 3)
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

	assert(starts == GROUP_IDS.size() * 18)
	assert(finishes == GROUP_IDS.size() * 18)
	assert(releases == GROUP_IDS.size())
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

	print("POC27C_FOUR_GROUP_DIAG_SUMMARY groups=%d golfers=%d starts=%d finishes=%d waits=%d releases=%d max_live=%d max_holes=%d time=%.1f iterations=%d events=%d" % [
		GROUP_IDS.size(),
		_total_golfers(),
		starts,
		finishes,
		waits,
		releases,
		max_live_groups,
		max_occupied_holes,
		runtime.current_time_seconds,
		iterations,
		runtime.event_history.size()
	])
	print("POC-27C FOUR-GROUP FULL-ROUND DIAGNOSTIC PASSED")
	_cleanup_and_quit(0)


func _group_members(group_size: int, offset: int) -> Array:
	var profiles := [
		Golfer.GolferProfile.CAREFUL_CARL,
		Golfer.GolferProfile.WILD_BILL,
		Golfer.GolferProfile.RECKLESS_RICK
	]
	var golfers: Array = []
	for index in range(group_size):
		var golfer = QuietGolfer.new()
		golfer.profile = int(profiles[(index + offset) % profiles.size()])
		golfer.apply_profile()
		get_root().add_child(golfer)
		created_golfers.append(golfer)
		golfers.append(golfer)
	return golfers


func _total_golfers() -> int:
	var total: int = 0
	for group_size in GROUP_SIZES:
		total += int(group_size)
	return total


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
		group_parts.append("%s(status=%s,current=%d,traffic=%d,live=%s,blocked=%s)" % [
			group_id,
			status,
			current_hole,
			traffic_hole,
			str(live),
			str(blocked)
		])
	return "groups=[%s] waiting=%d live_sessions=%d blocked=%d" % [
		", ".join(group_parts),
		runtime.living_course.start_sequencer.waiting_group_ids().size(),
		runtime.live_sessions.size(),
		runtime.blocked_transitions.size()
	]


func _cleanup_and_quit(code: int) -> void:
	for golfer in created_golfers:
		if golfer != null and is_instance_valid(golfer):
			golfer.queue_free()
	quit(code)

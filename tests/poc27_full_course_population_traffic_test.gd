extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const GROUP_IDS := ["group_1", "group_2", "group_3", "group_4", "group_5"]
const GROUP_SIZES := [4, 1, 3, 2, 4]
const STEP_SECONDS := 30.0
const MAX_ITERATIONS := 5000

var failures: int = 0
var created_golfers: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27C: five-group full-course population and traffic")

	var course = POC27Course.build()
	_assert_true(course != null, "18-hole course builds for full-course traffic proof")
	if course == null:
		_finish()
		return

	var runtime = ShotProgressiveLivingCourseController.new()
	_assert_true(runtime.configure(course), "existing shot-progressive living controller configures unchanged")

	for group_index in range(GROUP_IDS.size()):
		var golfers: Array = []
		for member_index in range(GROUP_SIZES[group_index]):
			var profile: int = _profile_for(group_index, member_index)
			golfers.append(_new_golfer(profile))
		_assert_true(
			runtime.add_group(GROUP_IDS[group_index], golfers, "default", -1, 27000 + group_index * 1000),
			"%s joins as an ordinary autonomous living-course group" % GROUP_IDS[group_index]
		)

	_assert_equal_int(runtime.living_course.population.group_count(), GROUP_IDS.size(), "all five groups exist in one course population")
	_assert_equal_int(runtime.living_course.start_sequencer.waiting_count(), GROUP_IDS.size(), "all five groups begin in the same FIFO tee queue")

	var opening: Dictionary = runtime.release_next_group()
	_assert_true(bool(opening.get("released", false)), "first group releases onto open Hole 1")
	_assert_equal_str(str(opening.get("group_id", "")), GROUP_IDS[0], "first tee preserves FIFO group identity")

	var initial_follower: Dictionary = runtime.release_next_group()
	_assert_true(not bool(initial_follower.get("released", false)), "second group cannot bypass live first-tee safety gate")
	_assert_true(not str(initial_follower.get("reason", "")).is_empty(), "blocked follower reports mechanical spacing reason")

	var iterations: int = 0
	var max_live_groups: int = 0
	var max_occupied_holes: int = 0
	var same_hole_overlap_seen: bool = false
	var course_spread_seen: bool = false
	var back_nine_population_seen: bool = false
	var first_group_finished_while_others_live: bool = false
	var par3_congestion_seen: bool = false

	while iterations < MAX_ITERATIONS and not _all_groups_finished(runtime):
		iterations += 1
		runtime.advance_time(STEP_SECONDS)

		var occupied_holes: int = 0
		var live_groups: int = 0
		var min_live_hole: int = 999
		var max_live_hole: int = 0
		for hole_number in range(1, course.hole_count() + 1):
			var occupants: Array = runtime.traffic.groups_on_hole(hole_number)
			if not occupants.is_empty():
				occupied_holes += 1
				live_groups += occupants.size()
				min_live_hole = mini(min_live_hole, hole_number)
				max_live_hole = maxi(max_live_hole, hole_number)
				if occupants.size() >= 2:
					same_hole_overlap_seen = true
				if int(course.hole_by_number(hole_number).par) == 3 and occupants.size() == 1:
					for group_value in runtime.blocked_transitions.keys():
						var blocked: Dictionary = runtime.blocked_transitions[group_value]
						if int(blocked.get("to_hole_number", 0)) == hole_number:
							par3_congestion_seen = true
		max_live_groups = maxi(max_live_groups, live_groups)
		max_occupied_holes = maxi(max_occupied_holes, occupied_holes)
		if occupied_holes >= 3 and max_live_hole - min_live_hole >= 2:
			course_spread_seen = true
		if max_live_hole >= 10:
			back_nine_population_seen = true

		var finished_count: int = 0
		var unfinished_count: int = 0
		for group_id in GROUP_IDS:
			var group = runtime.living_course.population.group_by_id(group_id)
			if group != null and str(group.status) == "FINISHED":
				finished_count += 1
			else:
				unfinished_count += 1
		if finished_count > 0 and unfinished_count > 0:
			first_group_finished_while_others_live = true

	_assert_true(iterations < MAX_ITERATIONS, "five-group 18-hole traffic simulation remains bounded")
	_assert_true(_all_groups_finished(runtime), "all five groups finish the complete living round")
	_assert_true(runtime.current_time_seconds > 0.0, "one global course clock advances throughout the day")
	_assert_true(max_live_groups >= 3, "at least three groups coexist live on the course")
	_assert_true(max_occupied_holes >= 3, "population spreads across at least three holes simultaneously")
	_assert_true(course_spread_seen, "groups become spatially distributed instead of moving as one batch")
	_assert_true(back_nine_population_seen, "live population reaches the back nine")
	_assert_true(same_hole_overlap_seen, "safe same-hole concurrency occurs under existing POC-24 rules")
	_assert_true(first_group_finished_while_others_live, "groups finish independently while the course remains alive")
	_assert_true(par3_congestion_seen, "short-hole geometry naturally produces a blocked following transition")

	var tee_release_count: int = 0
	var hole_start_count: int = 0
	var hole_finish_count: int = 0
	var wait_count: int = 0
	var safe_overlap_release_count: int = 0
	var mechanical_release_contract_ok: bool = true
	var ordered_release_ids: Array = []

	for event_value in runtime.event_history:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		match str(event.get("type", "")):
			"LIVE_TEE_RELEASE":
				tee_release_count += 1
				ordered_release_ids.append(str(event.get("group_id", "")))
				if tee_release_count > 1:
					var reason: String = str(event.get("reason", ""))
					if reason == "SAFE_LIVE_SPACING":
						var spacing: Dictionary = event.get("spacing", {})
						if not bool(spacing.get("safe", false)):
							mechanical_release_contract_ok = false
						if str(spacing.get("release_rule", "")) != "RANGE_SAFE_AND_ALL_LEAD_GOLFERS_ON_GREEN":
							mechanical_release_contract_ok = false
						safe_overlap_release_count += 1
					elif reason != "OPEN_FIRST_HOLE":
						mechanical_release_contract_ok = false
			"LIVE_HOLE_START":
				hole_start_count += 1
			"LIVE_HOLE_FINISH":
				hole_finish_count += 1
			"LIVE_INTER_HOLE_WAIT":
				wait_count += 1

	_assert_equal_int(tee_release_count, GROUP_IDS.size(), "every group receives exactly one first-tee release")
	_assert_true(ordered_release_ids == GROUP_IDS, "first tee remains FIFO under a populated course")
	_assert_true(mechanical_release_contract_ok, "all follower tee releases remain mechanical rather than timer-based")
	_assert_true(safe_overlap_release_count > 0, "at least one follower is released while lead group remains safely ahead")
	_assert_true(wait_count > 0, "real inter-hole traffic waits emerge during the full day")
	_assert_equal_int(hole_start_count, GROUP_IDS.size() * 18, "five groups start exactly 18 authoritative holes each")
	_assert_equal_int(hole_finish_count, GROUP_IDS.size() * 18, "five groups finish exactly 18 authoritative holes each")

	for group_id in GROUP_IDS:
		var group = runtime.living_course.population.group_by_id(group_id)
		_assert_true(group != null, "%s retains stable group identity" % group_id)
		if group == null:
			continue
		_assert_equal_str(str(group.status), "FINISHED", "%s finishes through ordinary group progression" % group_id)
		_assert_equal_int(runtime.traffic.group_hole(group_id), 0, "%s clears traffic after Hole 18" % group_id)
		for member_index in range(group.rounds.size()):
			var autonomous_round = group.rounds[member_index]
			_assert_true(autonomous_round.round_state.complete, "%s member %d completes authoritative RoundState" % [group_id, member_index])
			_assert_equal_int(autonomous_round.round_state.holes_completed(), 18, "%s member %d records all 18 holes" % [group_id, member_index])
			_assert_equal_int(autonomous_round.hole_results.size(), 18, "%s member %d retains 18 authoritative hole results" % [group_id, member_index])

	_assert_true(runtime.live_sessions.is_empty(), "no live hole sessions remain after the course clears")
	_assert_true(runtime.blocked_transitions.is_empty(), "no blocked transitions remain after the course clears")
	for hole_number in range(1, 19):
		_assert_true(runtime.traffic.groups_on_hole(hole_number).is_empty(), "Hole %d is empty at end of day" % hole_number)

	print("POC27C_TRAFFIC_SUMMARY groups=%d golfer_rounds=%d starts=%d finishes=%d waits=%d safe_overlap_releases=%d max_live=%d max_holes=%d time=%.1f iterations=%d" % [
		GROUP_IDS.size(),
		_total_golfer_rounds(),
		hole_start_count,
		hole_finish_count,
		wait_count,
		safe_overlap_release_count,
		max_live_groups,
		max_occupied_holes,
		runtime.current_time_seconds,
		iterations
	])
	_finish()


func _all_groups_finished(runtime) -> bool:
	for group_id in GROUP_IDS:
		var group = runtime.living_course.population.group_by_id(group_id)
		if group == null or str(group.status) != "FINISHED":
			return false
	return true


func _profile_for(group_index: int, member_index: int) -> int:
	var profiles := [Golfer.GolferProfile.CAREFUL_CARL, Golfer.GolferProfile.WILD_BILL, Golfer.GolferProfile.RECKLESS_RICK]
	return int(profiles[(group_index + member_index) % profiles.size()])


func _new_golfer(profile: int):
	var golfer = QuietGolfer.new()
	golfer.profile = profile
	golfer.apply_profile()
	get_root().add_child(golfer)
	created_golfers.append(golfer)
	return golfer


func _total_golfer_rounds() -> int:
	var total: int = 0
	for size in GROUP_SIZES:
		total += int(size)
	return total


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
	for golfer in created_golfers:
		if golfer != null and is_instance_valid(golfer):
			golfer.queue_free()
	if failures == 0:
		print("POC-27C FULL-COURSE POPULATION AND TRAFFIC PASSED")
		quit(0)
	else:
		push_error("POC-27C FULL-COURSE POPULATION AND TRAFFIC FAILED: %d" % failures)
		quit(1)

extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const SpacingAwareTimedCourseController = preload("res://simulation/spacing_aware_timed_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const LivingSpectatorSession = preload("res://scenes/living_spectator_session.gd")
const Golfer = preload("res://scenes/golfer.gd")


func _init() -> void:
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	assert(course != null and course.hole_count() == 3)

	var controller = SpacingAwareTimedCourseController.new()
	assert(controller.configure(course))
	var lead_a = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var lead_b = _golfer(Golfer.GolferProfile.WILD_BILL)
	var follow_a = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var follow_b = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	assert(controller.add_group("group_1", [lead_a, lead_b]))
	assert(controller.add_group("group_2", [follow_a, follow_b]))

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	assert(world.configure(course))
	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	assert(view.configure(world, controller))
	assert(view.group_visual("group_1").projected_status == "WAITING")
	assert(view.group_visual("group_2").projected_status == "WAITING")

	var session = LivingSpectatorSession.new()
	get_root().add_child(session)
	assert(session.configure(controller, world, view, 26501))
	var opening: Dictionary = session.start_session()
	assert(not opening.is_empty())
	assert(controller.traffic.group_hole("group_1") == 1)
	assert(controller.traffic.group_hole("group_2") == 0)
	assert(view.group_visual("group_2").projected_status == "WAITING")

	var group_1 = controller.living_course.population.group_by_id("group_1")
	var group_2 = controller.living_course.population.group_by_id("group_2")
	assert(group_1 != null and group_2 != null)

	var overlap_seen: bool = false
	var safe_first_tee_release_seen: bool = false
	var inter_hole_wait_count: int = 0
	var processed_event_count: int = 0
	var iterations: int = 0
	while iterations < 240 and (
		str(group_1.status) != "FINISHED"
		or str(group_2.status) != "FINISHED"
		or controller.traffic.group_hole("group_1") != 0
		or controller.traffic.group_hole("group_2") != 0
		or not controller.active_event("group_1").is_empty()
		or not controller.active_event("group_2").is_empty()
	):
		iterations += 1
		var before_time: float = controller.current_time_seconds
		var emitted: Array = session.advance_time(30.0, false)
		assert(controller.current_time_seconds > before_time)
		processed_event_count += emitted.size()
		for event_value in emitted:
			if typeof(event_value) != TYPE_DICTIONARY:
				continue
			var event: Dictionary = event_value
			if str(event.get("type", "")) == "TEE_RELEASE" and bool(event.get("released", false)):
				safe_first_tee_release_seen = true
			if str(event.get("type", "")) == "INTER_HOLE_TRANSITION" and bool(event.get("waited_for_group_ahead", false)):
				inter_hole_wait_count += 1

		var lead_hole: int = int(controller.traffic.group_hole("group_1"))
		var follower_hole: int = int(controller.traffic.group_hole("group_2"))
		if lead_hole > follower_hole and follower_hole > 0:
			overlap_seen = true

	assert(str(group_1.status) == "FINISHED")
	assert(str(group_2.status) == "FINISHED")
	assert(safe_first_tee_release_seen)
	assert(overlap_seen)
	assert(controller.traffic.group_hole("group_1") == 0)
	assert(controller.traffic.group_hole("group_2") == 0)
	assert(controller.active_event("group_1").is_empty())
	assert(controller.active_event("group_2").is_empty())
	assert(session.playback_for_group("group_1") == null)
	assert(session.playback_for_group("group_2") == null)

	for group in [group_1, group_2]:
		assert(group.rounds.size() == 2)
		for autonomous_round in group.rounds:
			assert(autonomous_round != null)
			assert(autonomous_round.round_state != null)
			assert(autonomous_round.round_state.complete)
			assert(autonomous_round.round_state.holes_completed() == 3)
			assert(autonomous_round.hole_results.size() == 3)
			for hole_result_value in autonomous_round.hole_results:
				assert(typeof(hole_result_value) == TYPE_DICTIONARY)
				var hole_result: Dictionary = hole_result_value
				assert(bool(hole_result.get("finished", false)))
				assert(bool(hole_result.get("recorded", false)))

	var session_snapshot: Dictionary = session.snapshot()
	assert(int(session_snapshot.get("completed_playback_count", 0)) == 6)
	var playback_counts := {"group_1": {}, "group_2": {}}
	for playback_value in session_snapshot.get("completed_playbacks", []):
		assert(typeof(playback_value) == TYPE_DICTIONARY)
		var playback: Dictionary = playback_value
		assert(bool(playback.get("complete", false)))
		var group_id: String = str(playback.get("group_id", ""))
		var hole_number: int = int(playback.get("hole_number", 0))
		assert(playback_counts.has(group_id))
		assert(hole_number >= 1 and hole_number <= 3)
		playback_counts[group_id][hole_number] = int(playback_counts[group_id].get(hole_number, 0)) + 1
	for group_id in playback_counts.keys():
		for hole_number in range(1, 4):
			assert(int(playback_counts[group_id].get(hole_number, 0)) == 1)

	var play_start_count: int = 0
	var hole_finish_count: int = 0
	for event_value in session_snapshot.get("event_log", []):
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) == "PLAY_START":
			play_start_count += 1
		elif str(event.get("type", "")) == "HOLE_FINISH":
			hole_finish_count += 1
	assert(play_start_count == 6)
	assert(hole_finish_count == 6)
	assert(view.group_visual("group_1").projected_status == "FINISHED")
	assert(view.group_visual("group_2").projected_status == "FINISHED")

	print("POC25_FULL_ROUND_SUMMARY time=%.1f starts=%d finishes=%d playbacks=%d overlap=%s inter_hole_waits=%d processed=%d iterations=%d" % [controller.current_time_seconds, play_start_count, hole_finish_count, int(session_snapshot.get("completed_playback_count", 0)), str(overlap_seen), inter_hole_wait_count, processed_event_count, iterations])
	print("POC-25F FULL TWO-GROUP THREE-HOLE SPECTATOR ROUND PASSED")

	session.queue_free();view.queue_free();world.queue_free()
	lead_a.queue_free();lead_b.queue_free();follow_a.queue_free();follow_b.queue_free()
	quit(0)


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer

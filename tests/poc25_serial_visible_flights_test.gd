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
	var session = LivingSpectatorSession.new()
	get_root().add_child(session)
	assert(session.configure(controller, world, view, 27501))
	assert(not session.start_session().is_empty())

	var pending: Dictionary = controller.release_scheduler.pending_release("group_2")
	assert(not pending.is_empty())
	var release_time: float = float(pending.get("release_time_seconds", -1.0))
	assert(release_time > 0.0)

	# Advance headlessly across Group 2's legal release so both groups own active
	# playbacks without leaving any visual flight running.
	session.advance_time((release_time - controller.current_time_seconds) + 0.10, false)
	var lead_playback = session.playback_for_group("group_1")
	var follow_playback = session.playback_for_group("group_2")
	assert(lead_playback != null and follow_playback != null)
	assert(not lead_playback.has_active_flight())
	assert(not follow_playback.has_active_flight())

	var lead_next: Dictionary = lead_playback.next_event()
	var follow_next: Dictionary = follow_playback.next_event()
	assert(not lead_next.is_empty() and not follow_next.is_empty())
	var lead_time: float = float(lead_next.get("time_seconds", -1.0))
	var follow_time: float = float(follow_next.get("time_seconds", -1.0))
	assert(lead_time >= 0.0 and follow_time >= 0.0)

	# Force one spectator presentation update far enough forward that both groups
	# have a due shot. Only the earliest legal shot may become a visible flight.
	var visual_target: float = maxf(lead_time, follow_time) + 0.10
	var authority_before: float = controller.current_time_seconds
	session._advance_playbacks_to(visual_target, true)
	var flying_groups: Array[String] = []
	if lead_playback.has_active_flight():
		flying_groups.append("group_1")
	if follow_playback.has_active_flight():
		flying_groups.append("group_2")
	assert(flying_groups.size() == 1)
	assert(is_equal_approx(controller.current_time_seconds, authority_before))

	var expected_first: String = "group_1" if lead_time <= follow_time else "group_2"
	assert(flying_groups[0] == expected_first)

	print("POC25_SERIAL_FLIGHT_SUMMARY lead_next=%.1f follower_next=%.1f visible=%s authority=%.1f" % [
		lead_time,
		follow_time,
		flying_groups[0],
		controller.current_time_seconds
	])
	print("POC-25 SERIAL VISIBLE FLIGHTS PASSED")

	session.queue_free();view.queue_free();world.queue_free()
	lead_a.queue_free();lead_b.queue_free();follow_a.queue_free();follow_b.queue_free()
	quit(0)


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer

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

	var lead_event: Dictionary = controller.active_event("group_1")
	assert(not lead_event.is_empty())
	var lead_result: Dictionary = lead_event.get("play_result", {})
	assert(not lead_result.is_empty())
	var hole = course.hole_by_number(1)
	assert(hole != null)

	var spacing: Dictionary = controller.spacing_model.earliest_safe_tee_time(
		lead_result,
		hole,
		[follow_a, follow_b],
		"default"
	)
	assert(bool(spacing.get("safe", false)))
	var green_gate: Dictionary = controller.spacing_model.earliest_all_members_green_time(
		lead_result,
		hole,
		"default"
	)
	assert(bool(green_gate.get("reached", false)))

	var range_time: float = float(spacing.get("safe_time_seconds", -1.0))
	var green_time: float = float(green_gate.get("green_time_seconds", -1.0))
	assert(range_time >= 0.0 and green_time >= 0.0)
	assert(green_time > range_time)

	var pending: Dictionary = controller.release_scheduler.pending_release("group_2")
	assert(not pending.is_empty())
	assert(str(pending.get("release_rule", "")) == "RANGE_SAFE_AND_ALL_LEAD_GOLFERS_ON_GREEN")
	assert(is_equal_approx(float(pending.get("range_safe_time_seconds", -1.0)), range_time))
	assert(is_equal_approx(float(pending.get("lead_group_green_time_seconds", -1.0)), green_time))
	var release_time: float = float(pending.get("release_time_seconds", -1.0))
	var lead_start: float = float(pending.get("lead_start_time_seconds", 0.0))
	assert(is_equal_approx(release_time, lead_start + max(range_time, green_time)))

	var pre_release_target: float = release_time - 0.05
	assert(pre_release_target > controller.current_time_seconds)
	session.advance_time(pre_release_target - controller.current_time_seconds, false)
	assert(controller.current_time_seconds < release_time)
	assert(controller.traffic.group_hole("group_2") == 0)
	assert(session.playback_for_group("group_2") == null)

	session.advance_time(0.10, false)
	assert(controller.current_time_seconds > release_time)
	assert(controller.traffic.group_hole("group_2") == 1)
	assert(session.playback_for_group("group_2") != null)

	print("POC25_GREEN_RELEASE_SUMMARY range=%.1f green=%.1f release=%.1f follower_hole=%d" % [
		range_time,
		green_time,
		release_time,
		int(controller.traffic.group_hole("group_2"))
	])
	print("POC-25 FIRST-TEE LEAD-GROUP-GREEN RELEASE PASSED")

	session.queue_free();view.queue_free();world.queue_free()
	lead_a.queue_free();lead_b.queue_free();follow_a.queue_free();follow_b.queue_free()
	quit(0)


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer

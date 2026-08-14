extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const SpacingAwareTimedCourseController = preload("res://simulation/spacing_aware_timed_course_controller.gd")
const GroupShotOrderModel = preload("res://simulation/group_shot_order_model.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const SpectatorTimedGroupPlayback = preload("res://scenes/spectator_timed_group_playback.gd")
const Golfer = preload("res://scenes/golfer.gd")


func _init() -> void:
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	assert(course != null)
	var controller = SpacingAwareTimedCourseController.new()
	assert(controller.configure(course))
	var lead_a = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var lead_b = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var follow = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	assert(controller.add_group("lead", [lead_a, lead_b]))
	assert(controller.add_group("following", [follow]))
	assert(bool(controller.release_next_group().get("released", false)))

	var start: Dictionary = controller.start_group_current_hole("lead", 25101)
	assert(bool(start.get("started", false)))
	var tee_release: Dictionary = start.get("tee_release", {})
	assert(bool(tee_release.get("scheduled", false)))
	var active: Dictionary = controller.active_event("lead")
	assert(not active.is_empty())
	var traffic_before: Dictionary = controller.traffic.snapshot().duplicate(true)
	var round_holes_before: int = controller.living_course.population.group_by_id("lead").rounds[0].round_state.holes_completed()

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	assert(world.configure(course))
	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	assert(view.configure(world, controller))
	var lead_visual = view.group_visual("lead")
	assert(lead_visual != null)

	var timed = SpectatorTimedGroupPlayback.new()
	get_root().add_child(timed)
	assert(timed.configure(lead_visual, active, course.hole_by_number(1), "default"))
	var schedule: Dictionary = timed.schedule
	assert(int(schedule.get("event_count", 0)) > 0)
	var events: Array = schedule.get("events", [])
	for index in range(1, events.size()):
		assert(float(events[index].get("time_seconds", 0.0)) >= float(events[index - 1].get("time_seconds", 0.0)))

	var order_model = GroupShotOrderModel.new()
	var authoritative_order: Array = order_model.build_order(active.get("play_result", {}), course.hole_by_number(1), "default")
	assert(authoritative_order.size() == events.size())
	for index in range(events.size()):
		assert(int(events[index].get("member_index", -1)) == int(authoritative_order[index].get("member_index", -2)))
		assert(int(events[index].get("shot_index", -1)) == int(authoritative_order[index].get("shot_index", -2)))

	var start_time: float = float(active.get("start_time_seconds", 0.0))
	assert(timed.advance_to(start_time, false).is_empty())
	assert(int(timed.snapshot().get("presented_event_count", -1)) == 0)
	var first_time: float = float(events[0].get("time_seconds", start_time))
	var first_due: Array = timed.advance_to(first_time, false)
	assert(not first_due.is_empty())
	assert(int(timed.snapshot().get("presented_event_count", 0)) == first_due.size())

	var release_time: float = float(tee_release.get("release_time_seconds", -1.0))
	var release_sequence: int = int(tee_release.get("sequence_index", -1))
	assert(release_sequence >= 0 and release_sequence < events.size())
	var release_visual_event: Dictionary = events[release_sequence]
	assert(is_equal_approx(float(release_visual_event.get("clearance_time_seconds", -2.0)), release_time))
	assert(int(release_visual_event.get("member_index", -1)) == int(tee_release.get("member_index", -2)))

	var due_at_release: Array = timed.advance_to(release_time, false)
	assert(not due_at_release.is_empty())
	var presented_at_release: int = int(timed.snapshot().get("presented_event_count", 0))
	var expected_through_release: int = 0
	for event_value in events:
		if float(event_value.get("time_seconds", INF)) <= release_time:
			expected_through_release += 1
	assert(presented_at_release == expected_through_release)

	var finish_time: float = float(active.get("finish_time_seconds", release_time))
	timed.advance_to(finish_time, false)
	assert(timed.is_complete())
	assert(int(timed.snapshot().get("presented_event_count", 0)) == events.size())
	assert(controller.traffic.snapshot() == traffic_before)
	assert(controller.living_course.population.group_by_id("lead").rounds[0].round_state.holes_completed() == round_holes_before)
	assert(controller.current_time_seconds == 0.0)
	assert(controller.traffic.group_hole("following") == 0)

	print("POC25_TIMED_SUMMARY shots=%d release=%.1f finish=%.1f release_sequence=%d" % [events.size(), release_time, finish_time, release_sequence])
	print("POC-25D PACE-SYNCHRONIZED AWAY-ORDER SPECTATOR PLAYBACK PASSED")
	timed.queue_free()
	view.queue_free()
	world.queue_free()
	lead_a.queue_free();lead_b.queue_free();follow.queue_free()
	quit(0)


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer

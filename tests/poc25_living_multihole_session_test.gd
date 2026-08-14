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
	assert(session.configure(controller, world, view, 25501))
	var opening: Dictionary = session.start_session()
	assert(not opening.is_empty())
	assert(controller.traffic.group_hole("group_1") == 1)
	assert(controller.traffic.group_hole("group_2") == 0)
	assert(not controller.active_event("group_1").is_empty())
	assert(controller.active_event("group_2").is_empty())
	assert(session.playback_for_group("group_1") != null)
	assert(session.playback_for_group("group_2") == null)
	assert(view.group_visual("group_2").projected_status == "WAITING")

	var lead_hole_one: Dictionary = controller.active_event("group_1")
	var release: Dictionary = lead_hole_one.get("tee_release", {})
	var same_hole_release: bool = bool(release.get("scheduled", false))
	var lead_finish: float = float(lead_hole_one.get("finish_time_seconds", -1.0))
	assert(lead_finish > controller.current_time_seconds)
	var follower_start_boundary: float = lead_finish
	var release_path: String = "HOLE_CLEAR"
	if same_hole_release:
		follower_start_boundary = float(release.get("release_time_seconds", -1.0))
		release_path = "SAFE_SAME_HOLE"
		assert(follower_start_boundary > controller.current_time_seconds)
		assert(follower_start_boundary <= lead_finish)
	else:
		assert(str(release.get("status", "WAIT_FOR_HOLE_CLEAR")) == "WAIT_FOR_HOLE_CLEAR")

	var through_release: Array = session.advance_time(follower_start_boundary - controller.current_time_seconds, false)
	assert(not through_release.is_empty())
	assert(is_equal_approx(controller.current_time_seconds, follower_start_boundary))
	assert(controller.traffic.group_hole("group_2") == 1)
	var follower_hole_one: Dictionary = controller.active_event("group_2")
	assert(not follower_hole_one.is_empty())
	var actual_follower_start: float = float(follower_hole_one.get("start_time_seconds", -1.0))
	print("POC25_RELEASE_DEBUG path=%s expected=%.6f actual=%.6f controller=%.6f lead_finish=%.6f processed=%s" % [release_path, follower_start_boundary, actual_follower_start, controller.current_time_seconds, lead_finish, str(through_release)])
	assert(is_equal_approx(actual_follower_start, follower_start_boundary))
	assert(session.playback_for_group("group_2") != null)
	assert(view.group_visual("group_2").projected_status == "PLAYING")
	assert(view.group_visual("group_2").projected_hole_number == 1)

	if lead_finish > controller.current_time_seconds:
		session.advance_time(lead_finish - controller.current_time_seconds, false)
	assert(is_equal_approx(controller.current_time_seconds, lead_finish))
	var lead_hole_two: Dictionary = controller.active_event("group_1")
	assert(not lead_hole_two.is_empty())
	assert(int(lead_hole_two.get("hole_number", 0)) == 2)
	assert(is_equal_approx(float(lead_hole_two.get("start_time_seconds", -1.0)), lead_finish))
	assert(controller.traffic.group_hole("group_1") == 2)
	assert(session.playback_for_group("group_1") != null)
	assert(int(session.playback_for_group("group_1").snapshot().get("hole_number", 0)) == 2)
	assert(view.group_visual("group_1").projected_hole_number == 2)

	var follower_traffic_hole: int = controller.traffic.group_hole("group_2")
	assert(follower_traffic_hole == 1 or follower_traffic_hole == 2)
	var session_snapshot: Dictionary = session.snapshot()
	assert(int(session_snapshot.get("completed_playback_count", 0)) >= 1)
	var first_completed: Dictionary = session_snapshot.get("completed_playbacks", [])[0]
	assert(str(first_completed.get("group_id", "")) == "group_1")
	assert(int(first_completed.get("hole_number", 0)) == 1)
	assert(bool(first_completed.get("complete", false)))

	print("POC25_SESSION_SUMMARY release_path=%s follower_start=%.1f lead_h2_start=%.1f follower_hole=%d completed_playbacks=%d" % [release_path, follower_start_boundary, lead_finish, follower_traffic_hole, int(session_snapshot.get("completed_playback_count", 0))])
	print("POC-25E LIVING TWO-GROUP MULTI-HOLE SPECTATOR SESSION PASSED")
	session.queue_free();view.queue_free();world.queue_free()
	lead_a.queue_free();lead_b.queue_free();follow_a.queue_free();follow_b.queue_free()
	quit(0)


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer

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
	assert(release_time > controller.current_time_seconds)

	# The follower must remain a pure waiting visual before its authoritative
	# first-tee release. No playback history may be attached or presented early.
	var pre_release_target: float = maxf(controller.current_time_seconds, release_time - 0.05)
	assert(pre_release_target > controller.current_time_seconds)
	session.advance_time(pre_release_target - controller.current_time_seconds, false)
	assert(controller.current_time_seconds < release_time)
	assert(controller.traffic.group_hole("group_2") == 0)
	assert(session.playback_for_group("group_2") == null)
	var follower_visual = view.group_visual("group_2")
	assert(follower_visual != null)
	assert(follower_visual.loaded_playback.is_empty())
	assert(follower_visual.active_member_shots.is_empty())
	assert(follower_visual.projected_status == "WAITING")

	# Crossing the authoritative release boundary may start Group 2, but its
	# playback and first shot timestamp must belong to Group 2 and cannot predate
	# that release.
	session.advance_time(0.10, false)
	assert(controller.current_time_seconds > release_time)
	assert(controller.traffic.group_hole("group_2") == 1)
	var follower_playback = session.playback_for_group("group_2")
	assert(follower_playback != null)
	var playback_snapshot: Dictionary = follower_playback.snapshot()
	assert(str(playback_snapshot.get("group_id", "")) == "group_2")
	assert(int(playback_snapshot.get("hole_number", 0)) == 1)
	var next_event: Dictionary = follower_playback.next_event()
	if not next_event.is_empty():
		assert(float(next_event.get("time_seconds", -1.0)) >= release_time - 0.0001)

	print("POC25_FIRST_TEE_ISOLATION release=%.1f pre_release=%.1f follower_hole=%d playback_group=%s" % [
		release_time,
		pre_release_target,
		int(controller.traffic.group_hole("group_2")),
		str(playback_snapshot.get("group_id", ""))
	])
	print("POC-25 FIRST-TEE GROUP ISOLATION PASSED")

	session.queue_free();view.queue_free();world.queue_free()
	lead_a.queue_free();lead_b.queue_free();follow_a.queue_free();follow_b.queue_free()
	quit(0)


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer

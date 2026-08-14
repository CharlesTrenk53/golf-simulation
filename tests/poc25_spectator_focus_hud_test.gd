extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const SpacingAwareTimedCourseController = preload("res://simulation/spacing_aware_timed_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const LivingSpectatorSession = preload("res://scenes/living_spectator_session.gd")
const SpectatorFocusController = preload("res://scenes/spectator_focus_controller.gd")
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

	var focus = SpectatorFocusController.new()
	get_root().add_child(focus)
	assert(focus.configure(session, view))
	assert(focus.available_group_ids() == ["group_1", "group_2"])
	assert(focus.selected_group_id() == "group_1")

	# The simulation has already resolved Group 1's first-hole outcome, but the
	# spectator has not physically watched the hole finish yet. The HUD must not
	# reveal that future score.
	var lead_opening: Dictionary = focus.presentation_snapshot()
	assert(str(lead_opening.get("status", "")) == "PLAYING")
	assert(int(lead_opening.get("hole_number", 0)) == 1)
	assert(int(lead_opening.get("physically_completed_holes", -1)) == 0)
	assert(bool(lead_opening.get("active_playback", false)))
	assert(typeof(lead_opening.get("camera_target", null)) == TYPE_VECTOR3)
	var lead_members: Array = lead_opening.get("members", [])
	assert(lead_members.size() == 2)
	for member_value in lead_members:
		var member: Dictionary = member_value
		assert(int(member.get("completed_holes", -1)) == 0)
		assert(int(member.get("total_strokes", -1)) == 0)
		assert(str(member.get("score_label", "")) == "E")
	var opening_shot: Dictionary = lead_opening.get("shot", {})
	assert(str(opening_shot.get("phase", "")) == "NEXT")
	assert(not str(opening_shot.get("golfer_name", "")).is_empty())
	assert(not str(opening_shot.get("club_id", "")).is_empty())
	assert(not opening_shot.has("outcome"))

	# Group selection changes only presentation focus. Group 2 remains visibly
	# waiting while Group 1 owns the first tee/hole traffic.
	assert(focus.select_group("group_2"))
	var follower_waiting: Dictionary = focus.presentation_snapshot()
	assert(str(follower_waiting.get("status", "")) == "WAITING")
	assert(int(follower_waiting.get("hole_number", 0)) == 1)
	assert(int(follower_waiting.get("physically_completed_holes", -1)) == 0)
	assert(not bool(follower_waiting.get("active_playback", true)))
	assert(str(follower_waiting.get("shot", {}).get("phase", "")) == "NONE")
	assert(focus.cycle_group(1) == "group_1")

	# Advance precisely to Group 1's physical first-hole finish. The session will
	# immediately start its second-hole event, meaning the simulation already knows
	# hole 2 as well. The HUD must reveal hole 1 only.
	var lead_hole_one: Dictionary = controller.active_event("group_1")
	var lead_finish: float = float(lead_hole_one.get("finish_time_seconds", -1.0))
	assert(lead_finish > controller.current_time_seconds)
	session.advance_time(lead_finish - controller.current_time_seconds, false)
	var lead_hole_two: Dictionary = controller.active_event("group_1")
	assert(not lead_hole_two.is_empty())
	assert(int(lead_hole_two.get("hole_number", 0)) == 2)

	var hole_two_hud: Dictionary = focus.presentation_snapshot()
	assert(str(hole_two_hud.get("status", "")) == "PLAYING")
	assert(int(hole_two_hud.get("hole_number", 0)) == 2)
	assert(int(hole_two_hud.get("physically_completed_holes", -1)) == 1)
	var group_1 = controller.living_course.population.group_by_id("group_1")
	assert(group_1 != null)
	var hole_one = course.hole_by_number(1)
	for index in range(group_1.rounds.size()):
		var expected_score: int = group_1.rounds[index].round_state.score_for_hole(1)
		var member: Dictionary = hole_two_hud.get("members", [])[index]
		assert(int(member.get("total_strokes", -1)) == expected_score)
		assert(int(member.get("score_to_par", 999)) == expected_score - int(hole_one.par))
		assert(int(member.get("completed_holes", -1)) == 1)

	print("POC25_FOCUS_SUMMARY selected=%s hole=%d status=%s completed_visible=%d shot=%s" % [focus.selected_group_id(), int(hole_two_hud.get("hole_number", 0)), str(hole_two_hud.get("status", "")), int(hole_two_hud.get("physically_completed_holes", -1)), str(hole_two_hud.get("shot", {}).get("phase", ""))])
	print("POC-25G SPECTATOR FOCUS AND SPOILER-SAFE HUD PASSED")

	focus.queue_free();session.queue_free();view.queue_free();world.queue_free()
	lead_a.queue_free();lead_b.queue_free();follow_a.queue_free();follow_b.queue_free()
	quit(0)


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer

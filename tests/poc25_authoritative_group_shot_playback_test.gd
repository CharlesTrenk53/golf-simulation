extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const SpacingAwareTimedCourseController = preload("res://simulation/spacing_aware_timed_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const Golfer = preload("res://scenes/golfer.gd")


func _init() -> void:
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	assert(course != null)

	var controller = SpacingAwareTimedCourseController.new()
	assert(controller.configure(course))
	var carl = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var bill = _golfer(Golfer.GolferProfile.WILD_BILL)
	var waiting = _golfer(Golfer.GolferProfile.RECKLESS_RICK)
	assert(controller.add_group("group_1", [carl, bill]))
	assert(controller.add_group("group_2", [waiting]))
	assert(bool(controller.release_next_group().get("released", false)))

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	assert(world.configure(course))
	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	assert(view.configure(world, controller))
	var group_visual = view.group_visual("group_1")
	assert(group_visual != null)

	var start: Dictionary = controller.start_group_current_hole("group_1", 25001)
	assert(bool(start.get("started", false)))
	var play_result: Dictionary = start.get("play_result", {})
	assert(bool(play_result.get("completed", false)))
	assert(int(play_result.get("hole_number", 0)) == 1)
	assert(controller.traffic.group_hole("group_1") == 1)
	assert(controller.traffic.group_hole("group_2") == 0)
	assert(not controller.active_event("group_1").is_empty())

	var member_results: Array = play_result.get("member_results", [])
	assert(member_results.size() == 2)
	var source_first_start: Vector3 = member_results[0].get("history", [])[0].get("start_position", Vector3.ZERO)
	var source_first_landing: Vector3 = member_results[0].get("history", [])[0].get("landing_position", Vector3.ZERO)

	var loaded: Dictionary = group_visual.load_authoritative_hole_result(play_result)
	assert(int(loaded.get("hole_number", 0)) == 1)
	assert(int(loaded.get("member_count", 0)) == 2)

	var total_shots: int = 0
	for member_result_value in member_results:
		var member_result: Dictionary = member_result_value
		var member_index: int = int(member_result.get("member_index", -1))
		var history: Array = member_result.get("history", [])
		var projected: Array = group_visual.playback_shots(member_index)
		assert(not history.is_empty())
		assert(projected.size() == history.size())
		total_shots += history.size()
		for shot_index in range(history.size()):
			var authoritative_shot: Dictionary = history[shot_index]
			var projected_shot: Dictionary = projected[shot_index]
			var expected_start: Vector3 = world.world_position(1, authoritative_shot.get("start_position", Vector3.ZERO))
			var expected_landing: Vector3 = world.world_position(1, authoritative_shot.get("landing_position", Vector3.ZERO))
			assert(projected_shot.get("start_position", Vector3.ZERO).distance_to(expected_start) < 0.001)
			assert(projected_shot.get("landing_position", Vector3.ZERO).distance_to(expected_landing) < 0.001)
			var authoritative_distance: float = authoritative_shot.get("start_position", Vector3.ZERO).distance_to(authoritative_shot.get("landing_position", Vector3.ZERO))
			var projected_distance: float = projected_shot.get("start_position", Vector3.ZERO).distance_to(projected_shot.get("landing_position", Vector3.ZERO))
			assert(is_equal_approx(authoritative_distance, projected_distance))

	# Prove the one-shot animated seam independently before running the whole
	# loaded history in immediate/headless mode.
	var animated_shot: Dictionary = group_visual.present_member_shot(0, 0, true)
	assert(not animated_shot.is_empty())
	assert(group_visual.member_ball_visuals[0].is_flying)
	assert(group_visual.complete_member_shot(0))
	assert(not group_visual.member_ball_visuals[0].is_flying)

	# Reloading the exact same authoritative result resets presentation state but
	# does not ask the simulation to resolve anything again.
	assert(not group_visual.load_authoritative_hole_result(play_result).is_empty())
	assert(group_visual.present_all_loaded_shots_immediate() == total_shots)

	for member_result_value in member_results:
		var member_result: Dictionary = member_result_value
		var member_index: int = int(member_result.get("member_index", -1))
		var history: Array = member_result.get("history", [])
		var final_shot: Dictionary = history[history.size() - 1]
		var resolved: Vector3 = _resolved_position(final_shot)
		var expected_world: Vector3 = world.world_position(1, resolved)
		assert(group_visual.member_visuals[member_index].course_position.distance_to(expected_world) < 0.001)
		assert(group_visual.member_ball_visuals[member_index].course_position.distance_to(expected_world) < 0.001)

	# Projection must not rewrite the authoritative history or traffic state.
	assert(member_results[0].get("history", [])[0].get("start_position", Vector3.ZERO).distance_to(source_first_start) < 0.001)
	assert(member_results[0].get("history", [])[0].get("landing_position", Vector3.ZERO).distance_to(source_first_landing) < 0.001)
	assert(controller.traffic.group_hole("group_1") == 1)
	assert(controller.traffic.group_hole("group_2") == 0)

	print("POC25_PLAYBACK_SUMMARY members=%d shots=%d traffic_hole=%d" % [member_results.size(), total_shots, controller.traffic.group_hole("group_1")])
	print("POC-25C AUTHORITATIVE GROUP SHOT PLAYBACK PASSED")
	view.queue_free()
	world.queue_free()
	carl.queue_free(); bill.queue_free(); waiting.queue_free()
	quit(0)


func _resolved_position(shot: Dictionary) -> Vector3:
	var resolved: Vector3 = shot.get("landing_position", Vector3.ZERO)
	if str(shot.get("outcome", "")).to_upper() == "WATER" and shot.has("relief_position"):
		resolved = shot.get("relief_position", resolved)
	return resolved


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer

extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const SpacingAwareTimedCourseController = preload("res://simulation/spacing_aware_timed_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const LivingSpectatorSession = preload("res://scenes/living_spectator_session.gd")
const Golfer = preload("res://scenes/golfer.gd")

const POSITION_EPSILON := 0.05


func _init() -> void:
	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	assert(course != null and course.hole_count() == 3)

	var controller = SpacingAwareTimedCourseController.new()
	assert(controller.configure(course))
	var golfer_a = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var golfer_b = _golfer(Golfer.GolferProfile.WILD_BILL)
	assert(controller.add_group("group_1", [golfer_a, golfer_b]))

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	assert(world.configure(course))
	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	assert(view.configure(world, controller))
	var session = LivingSpectatorSession.new()
	get_root().add_child(session)
	assert(session.configure(controller, world, view, 28501))
	assert(not session.start_session().is_empty())

	var playback = session.playback_for_group("group_1")
	var visual = view.group_visual("group_1")
	assert(playback != null and visual != null)
	assert(visual.member_visuals.size() == 2)
	assert(visual.member_ball_visuals.size() == 2)
	assert(playback.tee_rest_positions.size() == 2)

	var tee_positions: Array = playback.tee_rest_positions.duplicate()
	var first_event: Dictionary = playback.next_event()
	assert(not first_event.is_empty())
	assert(int(first_event.get("shot_index", -1)) == 0)
	var first_member: int = int(first_event.get("member_index", -1))
	assert(first_member >= 0 and first_member < 2)
	assert(playback.advance_to(float(first_event.get("time_seconds", 0.0)), true).size() == 1)
	var first_ball = visual.member_ball_visuals[first_member]
	assert(first_ball != null and first_ball.is_flying)
	first_ball.set_flight_progress(1.0)
	assert(playback.complete_finished_flights() == 1)
	assert(not playback.has_active_tee_dispersion())
	assert(_near(visual.member_visuals[first_member].course_position, tee_positions[first_member]))
	assert(first_ball.course_position.distance_to(tee_positions[first_member]) > 10.0)

	var second_event: Dictionary = playback.next_event()
	assert(not second_event.is_empty())
	assert(int(second_event.get("shot_index", -1)) == 0)
	var second_member: int = int(second_event.get("member_index", -1))
	assert(second_member >= 0 and second_member < 2 and second_member != first_member)
	# The first golfer must still be with the group when the second tee shot starts.
	assert(_near(visual.member_visuals[first_member].course_position, tee_positions[first_member]))
	assert(playback.advance_to(float(second_event.get("time_seconds", 0.0)), true).size() == 1)
	var second_ball = visual.member_ball_visuals[second_member]
	assert(second_ball != null and second_ball.is_flying)
	second_ball.set_flight_progress(1.0)
	assert(playback.complete_finished_flights() == 1)

	# Only after every golfer has teed off does the group begin leaving the tee.
	assert(playback.has_active_tee_dispersion())
	for member_index in range(2):
		assert(_near(visual.member_visuals[member_index].course_position, tee_positions[member_index]))

	var dispersion: Dictionary = playback.tee_dispersion_snapshot()
	var starts: Array = dispersion.get("start_positions", [])
	var destinations: Array = dispersion.get("destination_positions", [])
	assert(starts.size() == 2 and destinations.size() == 2)
	for member_index in range(2):
		assert(typeof(destinations[member_index]) == TYPE_VECTOR3)
		assert(destinations[member_index].distance_to(starts[member_index]) > 10.0)
		assert(_near(visual.member_ball_visuals[member_index].course_position, destinations[member_index]))

	var duration: float = float(dispersion.get("duration_seconds", 0.0))
	assert(duration > 0.0)
	assert(playback.advance_tee_dispersion(duration * 0.5))
	for member_index in range(2):
		var midway: Vector3 = visual.member_visuals[member_index].course_position
		assert(midway.distance_to(starts[member_index]) > POSITION_EPSILON)
		assert(midway.distance_to(destinations[member_index]) > POSITION_EPSILON)

	assert(not playback.advance_tee_dispersion(duration * 0.5 + 0.01))
	assert(not playback.has_active_tee_dispersion())
	for member_index in range(2):
		assert(_near(visual.member_visuals[member_index].course_position, destinations[member_index]))

	var next_after_walk: Dictionary = playback.next_event()
	assert(not next_after_walk.is_empty())
	assert(int(next_after_walk.get("shot_index", -1)) > 0)

	print("POC25_TEE_DISPERSION_SUMMARY first=%d second=%d duration=%.2f separation=%.1f/%.1f" % [
		first_member,
		second_member,
		duration,
		destinations[0].distance_to(starts[0]),
		destinations[1].distance_to(starts[1])
	])
	print("POC-25 GROUP TEE-SHOT DISPERSION PASSED")

	session.queue_free();view.queue_free();world.queue_free()
	golfer_a.queue_free();golfer_b.queue_free()
	quit(0)


func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) <= POSITION_EPSILON


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer

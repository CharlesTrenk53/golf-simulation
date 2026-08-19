extends SceneTree

const CourseDefinition = preload("res://simulation/course_definition.gd")
const SpacingAwareTimedCourseController = preload("res://simulation/spacing_aware_timed_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const LivingSpectatorSession = preload("res://scenes/living_spectator_session.gd")
const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const IsometricRotatableCourseRenderer = preload("res://scenes/isometric_rotatable_course_renderer.gd")
const IsometricLivingGolferLayer = preload("res://scenes/isometric_living_golfer_layer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const POSITION_EPSILON: float = 0.05

var failures: int = 0


func _init() -> void:
	print("POC-33B: isometric shot and group movement presentation")

	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null and course.hole_count() == 3, "proven three-hole spectator course loads")
	if course == null:
		_finish()
		return

	var controller = SpacingAwareTimedCourseController.new()
	_assert_true(controller.configure(course), "authoritative spacing controller configures")
	var golfer_a = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var golfer_b = _golfer(Golfer.GolferProfile.WILD_BILL)
	_assert_true(controller.add_group("group_1", [golfer_a, golfer_b]), "authoritative twosome enters living course")

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	_assert_true(world.configure(course), "proven spectator world configures")
	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	_assert_true(view.configure(world, controller), "proven spectator population view configures")
	var session = LivingSpectatorSession.new()
	get_root().add_child(session)
	_assert_true(session.configure(controller, world, view, 33002), "living spectator session configures")
	_assert_true(not session.start_session().is_empty(), "living spectator session starts from authority")

	var playback = session.playback_for_group("group_1")
	var visual = view.group_visual("group_1")
	_assert_true(playback != null and visual != null, "existing spectator playback and group visual are available")
	if playback == null or visual == null:
		_cleanup(session, view, world, golfer_a, golfer_b)
		_finish()
		return

	# The spectator world lays holes left-to-right in positive world X/Z. This
	# player-authored construction grid is deliberately large enough to cover that
	# already-established presentation world so POC-33B can test projection only.
	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(80, 50, 10.0, Vector2(0.0, 0.0)), "isometric presentation grid configures around living course")
	var grid_before: Dictionary = grid.to_dictionary()
	var renderer = IsometricRotatableCourseRenderer.new()
	get_root().add_child(renderer)
	_assert_true(renderer.configure(grid), "accepted rotatable isometric renderer configures for living movement")
	var layer = IsometricLivingGolferLayer.new()
	get_root().add_child(layer)
	_assert_true(layer.configure(renderer, grid), "isometric living golfer layer configures")
	_assert_true(layer.sync_from_group_visual(visual), "isometric layer mirrors existing spectator group visual")
	_assert_equal(int(layer.snapshot().get("golfer_count", 0)), 2, "both golfer identities project from existing group visual")

	var tee_positions: Array = playback.tee_rest_positions.duplicate()
	_assert_equal(tee_positions.size(), 2, "existing playback exposes proven tee staging positions")
	for member_index in range(2):
		var projected: Dictionary = layer.projected_record("group_1:%d" % member_index)
		_assert_true(not projected.is_empty(), "tee-staged golfer %d has stable isometric identity" % member_index)
		_assert_vector2_close(
			projected.get("iso_position", Vector2.ZERO),
			layer.project_world_position(tee_positions[member_index]),
			0.000001,
			"tee-staged golfer %d uses exact isometric projection" % member_index
		)

	# First tee shot: the existing RuntimeBallVisual owns the resolved trajectory.
	# At half flight POC-33B should mirror its X/Z plus presentation-only arc lift.
	var first_event: Dictionary = playback.next_event()
	_assert_true(not first_event.is_empty() and int(first_event.get("shot_index", -1)) == 0, "first authoritative presentation event is a tee shot")
	var first_member: int = int(first_event.get("member_index", -1))
	_assert_true(playback.advance_to(float(first_event.get("time_seconds", 0.0)), true).size() == 1, "existing spectator playback launches first tee shot")
	var first_ball = visual.member_ball_visuals[first_member]
	_assert_true(first_ball != null and first_ball.is_flying, "existing runtime ball owns active first flight")
	if first_ball != null:
		first_ball.set_flight_progress(0.5)
	_assert_true(layer.sync_from_group_visual(visual), "isometric layer refreshes during active ball flight")
	var first_ball_projection: Dictionary = layer.projected_ball_record("group_1:%d:ball" % first_member)
	_assert_true(not first_ball_projection.is_empty(), "active ball retains stable isometric identity")
	_assert_true(bool(first_ball_projection.get("is_flying", false)), "isometric projection mirrors existing flying state")
	_assert_true(float(first_ball_projection.get("visual_height_yards", 0.0)) > 0.5, "isometric ball preserves existing presentation arc lift")
	var grounded_ball_iso: Vector2 = layer.project_world_position(first_ball.course_position)
	_assert_true(
		float(first_ball_projection.get("iso_position", Vector2.ZERO).y) < grounded_ball_iso.y - 1.0,
		"airborne ball renders above player-authored terrain rather than snapping to ground"
	)
	var first_golfer_midflight: Dictionary = layer.projected_record("group_1:%d" % first_member)
	var first_shot_start: Vector3 = first_event.get("presented", {}).get("start_position", tee_positions[first_member])
	_assert_vector2_close(
		first_golfer_midflight.get("iso_position", Vector2.ZERO),
		layer.project_world_position(first_shot_start),
		0.000001,
		"first golfer addresses the authoritative tee-shot start while ball is in flight"
	)
	if first_ball != null:
		first_ball.set_flight_progress(1.0)
	_assert_equal(playback.complete_finished_flights(), 1, "existing playback resolves first tee flight")
	_assert_true(layer.sync_from_group_visual(visual), "isometric layer refreshes after first tee flight")
	_assert_vector2_close(
		layer.projected_record("group_1:%d" % first_member).get("iso_position", Vector2.ZERO),
		layer.project_world_position(tee_positions[first_member]),
		0.000001,
		"first golfer remains staged until partner tees off"
	)

	# Second tee shot triggers the already-proven POC-25 group dispersion. POC-33
	# must simply mirror each movement frame into the isometric projection.
	var second_event: Dictionary = playback.next_event()
	_assert_true(not second_event.is_empty() and int(second_event.get("shot_index", -1)) == 0, "second authoritative presentation event is partner tee shot")
	var second_member: int = int(second_event.get("member_index", -1))
	_assert_true(second_member != first_member, "different group member owns second tee shot")
	_assert_true(playback.advance_to(float(second_event.get("time_seconds", 0.0)), true).size() == 1, "existing spectator playback launches second tee shot")
	var second_ball = visual.member_ball_visuals[second_member]
	_assert_true(second_ball != null and second_ball.is_flying, "existing runtime ball owns active second flight")
	if second_ball != null:
		second_ball.set_flight_progress(1.0)
	_assert_equal(playback.complete_finished_flights(), 1, "existing playback resolves second tee flight")
	_assert_true(playback.has_active_tee_dispersion(), "existing POC-25 tee dispersion begins only after both tee shots")

	var dispersion: Dictionary = playback.tee_dispersion_snapshot()
	var starts: Array = dispersion.get("start_positions", [])
	var destinations: Array = dispersion.get("destination_positions", [])
	var duration: float = float(dispersion.get("duration_seconds", 0.0))
	_assert_true(starts.size() == 2 and destinations.size() == 2 and duration > 0.0, "authoritative presentation exposes valid tee dispersion path")
	_assert_true(layer.sync_from_group_visual(visual), "isometric layer captures dispersion start")
	var start_iso: Array = []
	for member_index in range(2):
		start_iso.append(layer.projected_record("group_1:%d" % member_index).get("iso_position", Vector2.ZERO))

	_assert_true(playback.advance_tee_dispersion(duration * 0.5), "existing tee dispersion advances to midpoint")
	_assert_true(layer.sync_from_group_visual(visual), "isometric layer mirrors tee dispersion midpoint")
	for member_index in range(2):
		var mid_iso: Vector2 = layer.projected_record("group_1:%d" % member_index).get("iso_position", Vector2.ZERO)
		var destination_iso: Vector2 = layer.project_world_position(destinations[member_index])
		_assert_true(mid_iso.distance_to(start_iso[member_index]) > POSITION_EPSILON, "golfer %d moves away from tee in isometric view" % member_index)
		_assert_true(mid_iso.distance_to(destination_iso) > POSITION_EPSILON, "golfer %d has not snapped to dispersion destination" % member_index)

	_assert_true(not playback.advance_tee_dispersion(duration * 0.5 + 0.01), "existing tee dispersion completes naturally")
	_assert_true(layer.sync_from_group_visual(visual), "isometric layer mirrors completed tee dispersion")
	for member_index in range(2):
		_assert_vector2_close(
			layer.projected_record("group_1:%d" % member_index).get("iso_position", Vector2.ZERO),
			layer.project_world_position(destinations[member_index]),
			0.000001,
			"golfer %d finishes at authoritative first-shot destination" % member_index
		)

	# Stop exactly at the first-hole finish boundary. At that boundary authority
	# enters the open next hole and SpectatorGroupVisual starts its presentation-
	# only inter-hole interpolation. Advancing again in immediate/headless mode
	# would intentionally drain that animation, so the proof inspects it here.
	var active_event: Dictionary = controller.active_event("group_1")
	var finish_time: float = float(active_event.get("finish_time_seconds", controller.current_time_seconds))
	_assert_true(finish_time > controller.current_time_seconds, "authoritative first-hole finish boundary is available")
	if finish_time > controller.current_time_seconds:
		session.advance_time(finish_time - controller.current_time_seconds, false)
	var transition_found: bool = visual.has_active_inter_hole_transition()
	_assert_true(transition_found, "existing living-course presentation begins an inter-hole walk")
	if transition_found:
		var transition: Dictionary = visual.transition_snapshot()
		var transition_starts: Array = transition.get("start_positions", [])
		var transition_destinations: Array = transition.get("destination_positions", [])
		var transition_duration: float = float(transition.get("duration_seconds", 0.0))
		_assert_true(transition_starts.size() == 2 and transition_destinations.size() == 2 and transition_duration > 0.0, "existing inter-hole transition exposes valid movement path")
		_assert_true(layer.sync_from_group_visual(visual), "isometric layer captures inter-hole walk start")
		var walk_start_iso: Array = []
		for member_index in range(2):
			walk_start_iso.append(layer.projected_record("group_1:%d" % member_index).get("iso_position", Vector2.ZERO))
		_assert_true(visual.advance_inter_hole_transition(transition_duration * 0.5), "existing inter-hole walk advances to midpoint")
		_assert_true(layer.sync_from_group_visual(visual), "isometric layer mirrors inter-hole midpoint")
		for member_index in range(2):
			var mid_walk_iso: Vector2 = layer.projected_record("group_1:%d" % member_index).get("iso_position", Vector2.ZERO)
			var destination_walk_iso: Vector2 = layer.project_world_position(transition_destinations[member_index])
			_assert_true(mid_walk_iso.distance_to(walk_start_iso[member_index]) > POSITION_EPSILON, "golfer %d visibly progresses between holes" % member_index)
			_assert_true(mid_walk_iso.distance_to(destination_walk_iso) > POSITION_EPSILON, "golfer %d inter-hole walk remains interpolated" % member_index)
		_assert_true(not visual.advance_inter_hole_transition(transition_duration * 0.5 + 0.01), "existing inter-hole walk completes")
		_assert_true(layer.sync_from_group_visual(visual), "isometric layer mirrors inter-hole destination")
		for member_index in range(2):
			_assert_vector2_close(
				layer.projected_record("group_1:%d" % member_index).get("iso_position", Vector2.ZERO),
				layer.project_world_position(transition_destinations[member_index]),
				0.000001,
				"golfer %d arrives at authoritative next-tee staging area" % member_index
			)

	renderer.rotate_view(1)
	layer.refresh_projection()
	_assert_equal(str(layer.projected_record("group_1:0").get("golfer_id", "")), "group_1:0", "stable golfer identity survives movement plus camera rotation")
	_assert_true(grid.to_dictionary() == grid_before, "shot and movement projection never mutates player-authored terrain")

	print("POC33B_MOVEMENT_SUMMARY golfers=%d balls=%d first_member=%d second_member=%d tee_walk=%.2fs inter_hole=%s rotation=%d" % [
		int(layer.snapshot().get("golfer_count", 0)),
		int(layer.snapshot().get("ball_count", 0)),
		first_member,
		second_member,
		duration,
		str(transition_found),
		int(renderer.rotation_quarters)
	])

	layer.queue_free()
	renderer.queue_free()
	_cleanup(session, view, world, golfer_a, golfer_b)
	_finish()


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer


func _cleanup(session, view, world, golfer_a, golfer_b) -> void:
	if session != null:
		session.queue_free()
	if view != null:
		view.queue_free()
	if world != null:
		world.queue_free()
	if golfer_a != null:
		golfer_a.queue_free()
	if golfer_b != null:
		golfer_b.queue_free()


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _assert_vector2_close(actual: Vector2, expected: Vector2, tolerance: float, label: String) -> void:
	if actual.distance_to(expected) <= tolerance:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-33B ISOMETRIC SHOT AND GROUP MOVEMENT PASSED")
		quit(0)
	else:
		push_error("POC-33B ISOMETRIC SHOT AND GROUP MOVEMENT FAILED: %d" % failures)
		quit(1)

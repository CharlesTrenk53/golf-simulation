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

var failures: int = 0


func _init() -> void:
	print("POC-33C: living-course population integration")

	var course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	_assert_true(course != null and course.hole_count() == 3, "proven three-hole course loads")
	if course == null:
		_finish()
		return

	var controller = SpacingAwareTimedCourseController.new()
	_assert_true(controller.configure(course), "authoritative spacing controller configures")

	var golfers: Array = [
		_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_golfer(Golfer.GolferProfile.WILD_BILL),
		_golfer(Golfer.GolferProfile.WILD_BILL),
		_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_golfer(Golfer.GolferProfile.CAREFUL_CARL),
		_golfer(Golfer.GolferProfile.WILD_BILL)
	]
	_assert_true(controller.add_group("group_1", [golfers[0], golfers[1]]), "first twosome enters living population")
	_assert_true(controller.add_group("group_2", [golfers[2], golfers[3]]), "second twosome enters living population")
	_assert_true(controller.add_group("group_3", [golfers[4], golfers[5]]), "third twosome enters living population")

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	_assert_true(world.configure(course), "proven spectator world configures")
	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	_assert_true(view.configure(world, controller), "spectator population view creates all group visuals")
	_assert_equal(int(view.snapshot().get("group_count", 0)), 3, "all three authoritative groups have presentation visuals")

	var session = LivingSpectatorSession.new()
	get_root().add_child(session)
	_assert_true(session.configure(controller, world, view, 33103), "living spectator session configures")
	_assert_true(not session.start_session().is_empty(), "living session releases and starts first group")

	var grid = CourseConstructionGrid.new()
	_assert_true(grid.configure(80, 50, 10.0, Vector2(0.0, 0.0)), "isometric presentation grid covers spectator world")
	var grid_before: Dictionary = grid.to_dictionary()
	var renderer = IsometricRotatableCourseRenderer.new()
	get_root().add_child(renderer)
	_assert_true(renderer.configure(grid), "accepted rotatable isometric renderer configures")
	var layer = IsometricLivingGolferLayer.new()
	get_root().add_child(layer)
	_assert_true(layer.configure(renderer, grid), "isometric living population layer configures")
	_assert_true(layer.sync_from_population_view(view), "isometric layer aggregates entire spectator population")

	var initial: Dictionary = layer.snapshot()
	_assert_equal(int(initial.get("group_count", 0)), 3, "all living groups survive isometric aggregation")
	_assert_equal(int(initial.get("golfer_count", 0)), 6, "all six golfer identities survive isometric aggregation")
	_assert_equal(int(initial.get("ball_count", 0)), 6, "all six existing runtime balls survive isometric aggregation")
	_assert_group_state(layer, "group_1", "PLAYING", 1, "lead group mirrors playing traffic authority")
	_assert_group_state(layer, "group_2", "WAITING", 0, "second group remains visibly waiting off-course")
	_assert_group_state(layer, "group_3", "WAITING", 0, "third group remains visibly waiting off-course")

	for group_number in range(1, 4):
		for member_index in range(2):
			var golfer_id: String = "group_%d:%d" % [group_number, member_index]
			var record: Dictionary = layer.projected_record(golfer_id)
			_assert_true(not record.is_empty(), "%s remains addressable by stable identity" % golfer_id)
			_assert_equal(str(record.get("group_id", "")), "group_%d" % group_number, "%s keeps group ownership" % golfer_id)

	# The POC-24 spacing system schedules group_2 onto hole 1 while group_1 is
	# still active. Advance exactly to that authoritative release boundary so the
	# isometric layer must present multiple active groups at once.
	var release_snapshot: Dictionary = controller.release_scheduler.snapshot()
	var pending: Array = release_snapshot.get("pending_releases", [])
	_assert_true(not pending.is_empty(), "spacing authority schedules the second group release")
	var release_time: float = INF
	for value in pending:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var release: Dictionary = value
		if str(release.get("following_group_id", "")) == "group_2":
			release_time = float(release.get("release_time_seconds", INF))
			break
	_assert_true(release_time < INF, "second-group release boundary is discoverable")
	var lead_finish: float = float(controller.active_event("group_1").get("finish_time_seconds", -1.0))
	_assert_true(release_time > controller.current_time_seconds and release_time < lead_finish, "second group is released before lead group finishes")

	if release_time < INF:
		var delta: float = maxf(release_time - controller.current_time_seconds + 0.01, 0.01)
		session.advance_time(delta, false)
	_assert_true(not controller.active_event("group_1").is_empty(), "lead group remains actively playing after follower release")
	_assert_true(not controller.active_event("group_2").is_empty(), "second group begins authoritative play after safe release")
	_assert_equal(controller.traffic.groups_on_hole(1).size(), 2, "two authoritative groups concurrently occupy hole 1")
	_assert_true(session.playback_for_group("group_1") != null, "lead group keeps existing spectator playback")
	_assert_true(session.playback_for_group("group_2") != null, "second group receives existing spectator playback")

	_assert_true(layer.sync_from_population_view(view), "isometric layer refreshes all groups after traffic transition")
	_assert_group_state(layer, "group_1", "PLAYING", 1, "lead group remains visibly tied to hole 1 authority")
	_assert_group_state(layer, "group_2", "PLAYING", 1, "second active group mirrors hole 1 authority")
	_assert_group_state(layer, "group_3", "WAITING", 0, "third group remains waiting while two groups play")
	_assert_equal(int(layer.snapshot().get("golfer_count", 0)), 6, "population refresh never drops waiting or active golfer identities")

	var ids_before_rotation: Dictionary = _identity_set(layer.snapshot().get("records", []))
	renderer.rotate_view(1)
	layer.refresh_projection()
	var ids_after_rotation: Dictionary = _identity_set(layer.snapshot().get("records", []))
	_assert_true(ids_before_rotation == ids_after_rotation, "all golfer identities survive cardinal camera re-projection")
	_assert_true(grid.to_dictionary() == grid_before, "multi-group presentation never mutates player-authored terrain")

	print("POC33C_POPULATION_SUMMARY groups=%d golfers=%d active_hole1=%d waiting=%s rotation=%d" % [
		int(layer.snapshot().get("group_count", 0)),
		int(layer.snapshot().get("golfer_count", 0)),
		controller.traffic.groups_on_hole(1).size(),
		str(layer.projected_group("group_3").get("status", "")),
		int(renderer.rotation_quarters)
	])

	layer.queue_free()
	renderer.queue_free()
	session.queue_free()
	view.queue_free()
	world.queue_free()
	for golfer in golfers:
		if golfer != null:
			golfer.queue_free()
	_finish()


func _golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	return golfer


func _assert_group_state(layer, group_id: String, expected_status: String, expected_traffic_hole: int, label: String) -> void:
	var group: Dictionary = layer.projected_group(group_id)
	_assert_true(not group.is_empty(), label + " exists")
	if group.is_empty():
		return
	_assert_equal(str(group.get("status", "")), expected_status, label + " status")
	_assert_equal(int(group.get("traffic_hole_number", -1)), expected_traffic_hole, label + " traffic hole")
	_assert_equal(int(group.get("member_count", 0)), 2, label + " member count")


func _identity_set(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in records:
		if typeof(value) == TYPE_DICTIONARY:
			result[str(value.get("golfer_id", ""))] = true
	return result


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


func _finish() -> void:
	if failures == 0:
		print("POC-33C LIVING-COURSE POPULATION INTEGRATION PASSED")
		quit(0)
	else:
		push_error("POC-33C LIVING-COURSE POPULATION INTEGRATION FAILED: %d" % failures)
		quit(1)

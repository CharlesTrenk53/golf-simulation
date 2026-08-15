extends SceneTree

const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const ShotProgressiveLivingCourseController = preload("res://simulation/shot_progressive_living_course_controller.gd")
const SpectatorCourseWorld = preload("res://scenes/spectator_course_world.gd")
const SpectatorPopulationView = preload("res://scenes/spectator_population_view.gd")
const ParticipateSpectatorSession = preload("res://scenes/participate_spectator_session.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const STEP_SECONDS := 30.0
const MAX_ITERATIONS := 140

var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-27E DIAGNOSTIC: presentation boundary around iteration 100")
	var course = POC27Course.build()
	assert(course != null)

	var runtime = ShotProgressiveLivingCourseController.new()
	assert(runtime.configure(course))
	assert(runtime.add_group("group_1", _foursome(0), "default", -1, 37100))
	assert(runtime.add_group("group_2", _foursome(1), "default", -1, 38100))

	var world = SpectatorCourseWorld.new()
	get_root().add_child(world)
	created_nodes.append(world)
	assert(world.configure(course))

	var view = SpectatorPopulationView.new()
	get_root().add_child(view)
	created_nodes.append(view)
	assert(view.configure(world, runtime))

	var session = ParticipateSpectatorSession.new()
	get_root().add_child(session)
	created_nodes.append(session)
	assert(session.configure(runtime, world, view))
	assert(not session.start_session().is_empty())

	for iteration in range(1, MAX_ITERATIONS + 1):
		var detailed: bool = iteration >= 90
		if detailed:
			print("BOUNDARY %d A before advance time=%.1f auth=%d session=%d active=%d completed=%d" % [
				iteration,
				runtime.current_time_seconds,
				runtime.event_history.size(),
				session.event_log.size(),
				session.active_playbacks.size(),
				session.completed_playbacks.size()
			])

		var emitted: Array = session.advance_time(STEP_SECONDS, false)
		if detailed:
			print("BOUNDARY %d B after advance emitted=%d time=%.1f auth=%d session=%d active=%d completed=%d" % [
				iteration,
				emitted.size(),
				runtime.current_time_seconds,
				runtime.event_history.size(),
				session.event_log.size(),
				session.active_playbacks.size(),
				session.completed_playbacks.size()
			])

		if detailed:
			print("BOUNDARY %d C before explicit drain" % iteration)
		var residual: int = session.drain_visuals_immediate()
		if detailed:
			print("BOUNDARY %d D after explicit drain residual=%d" % [iteration, residual])

		if detailed:
			print("BOUNDARY %d E before active-playback inspection" % iteration)
		for playback_value in session.active_playbacks.values():
			if playback_value != null:
				var playback_snapshot: Dictionary = playback_value.snapshot()
				var _queued: int = int(playback_snapshot.get("queued_event_count", -1))
		if detailed:
			print("BOUNDARY %d F after active-playback inspection" % iteration)

		if detailed:
			print("BOUNDARY %d G before group-visual inspection" % iteration)
		for group_id in ["group_1", "group_2"]:
			var visual = view.group_visual(group_id)
			if visual != null:
				var _traffic_hole: int = runtime.traffic.group_hole(group_id)
				var _projected_hole: int = int(visual.projected_hole_number)
				var _transitioning: bool = visual.has_active_inter_hole_transition()
				var _active_shots: int = visual.active_member_shots.size()
		if detailed:
			print("BOUNDARY %d H after group-visual inspection" % iteration)

		if iteration % 10 == 0 and not detailed:
			print("BOUNDARY checkpoint iteration=%d time=%.1f auth=%d session=%d active=%d completed=%d" % [
				iteration,
				runtime.current_time_seconds,
				runtime.event_history.size(),
				session.event_log.size(),
				session.active_playbacks.size(),
				session.completed_playbacks.size()
			])

	print("POC27E_BOUNDARY_DIAG_SUMMARY iterations=%d time=%.1f auth=%d session=%d active=%d completed=%d" % [
		MAX_ITERATIONS,
		runtime.current_time_seconds,
		runtime.event_history.size(),
		session.event_log.size(),
		session.active_playbacks.size(),
		session.completed_playbacks.size()
	])
	print("POC-27E PRESENTATION BOUNDARY DIAGNOSTIC PASSED")
	_cleanup_and_quit(0)


func _foursome(offset: int) -> Array:
	var profiles := [Golfer.GolferProfile.CAREFUL_CARL, Golfer.GolferProfile.WILD_BILL, Golfer.GolferProfile.RECKLESS_RICK, Golfer.GolferProfile.CAREFUL_CARL]
	var golfers: Array = []
	for index in range(4):
		var golfer = QuietGolfer.new()
		golfer.profile = int(profiles[(index + offset) % profiles.size()])
		golfer.apply_profile()
		get_root().add_child(golfer)
		created_nodes.append(golfer)
		golfers.append(golfer)
	return golfers


func _cleanup_and_quit(code: int) -> void:
	for node in created_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	quit(code)

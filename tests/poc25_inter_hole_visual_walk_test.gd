extends SceneTree

const SpectatorDemo = preload("res://scenes/spectator_demo.gd")


func _init() -> void:
	call_deferred("_run_proof")


func _run_proof() -> void:
	var demo = SpectatorDemo.new()
	demo.auto_advance = false
	get_root().add_child(demo)
	await process_frame
	assert(demo.initialized)

	var lead_visual = demo.population_view.group_visual("group_1")
	assert(lead_visual != null)
	assert(int(lead_visual.projected_hole_number) == 1)
	var hole_1_event: Dictionary = demo.controller.active_event("group_1")
	assert(not hole_1_event.is_empty())
	var finish_time: float = float(hole_1_event.get("finish_time_seconds", -1.0))
	assert(finish_time > demo.controller.current_time_seconds)

	# Advance authority exactly to Group 1's Hole 1 completion. The controller may
	# enter Hole 2 immediately, but the visual must retain its old world position
	# and begin a presentation-only walk instead of snapping to the next tee.
	demo.session.advance_time(finish_time - demo.controller.current_time_seconds, false)
	assert(int(demo.controller.traffic.group_hole("group_1")) == 2)
	assert(lead_visual.has_active_inter_hole_transition())
	var transition: Dictionary = lead_visual.transition_snapshot()
	assert(int(transition.get("from_hole_number", 0)) == 1)
	assert(int(transition.get("to_hole_number", 0)) == 2)
	var starts: Array = transition.get("start_positions", [])
	var destinations: Array = transition.get("destination_positions", [])
	assert(starts.size() == 2 and destinations.size() == 2)
	assert(starts[0].distance_to(destinations[0]) > 1.0)
	assert(lead_visual.member_visuals[0].course_position.distance_to(starts[0]) < 0.001)
	assert(lead_visual.member_visuals[0].course_position.distance_to(destinations[0]) > 1.0)

	# While walking, the launchable spectator presentation must freeze the
	# authoritative course clock so the next visible shot cannot overtake the walk.
	var clock_before: float = demo.controller.current_time_seconds
	demo.advance_presentation(0.05)
	assert(is_equal_approx(demo.controller.current_time_seconds, clock_before))

	# A partial visual step must put the golfer strictly between endpoints.
	var duration: float = float(transition.get("duration_seconds", 1.75))
	lead_visual.advance_inter_hole_transition(duration * 0.5)
	var midpoint: Vector3 = lead_visual.member_visuals[0].course_position
	assert(midpoint.distance_to(starts[0]) > 0.1)
	assert(midpoint.distance_to(destinations[0]) > 0.1)

	lead_visual.advance_inter_hole_transition(duration)
	assert(not lead_visual.has_active_inter_hole_transition())
	assert(lead_visual.member_visuals[0].course_position.distance_to(destinations[0]) < 0.001)
	assert(lead_visual.member_ball_visuals[0].visible)

	print("POC25_INTER_HOLE_WALK_SUMMARY from=%d to=%d distance=%.1f duration=%.2f clock=%.1f" % [
		int(transition.get("from_hole_number", 0)),
		int(transition.get("to_hole_number", 0)),
		starts[0].distance_to(destinations[0]),
		duration,
		clock_before
	])
	print("POC-25 INTER-HOLE VISUAL WALK PASSED")

	demo.queue_free()
	quit(0)

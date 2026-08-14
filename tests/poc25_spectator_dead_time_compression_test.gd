extends SceneTree

const SpectatorDemoScene = preload("res://scenes/spectator_demo.tscn")


func _init() -> void:
	call_deferred("_run_proof")


func _run_proof() -> void:
	var demo = SpectatorDemoScene.instantiate()
	demo.auto_advance = false
	get_root().add_child(demo)
	await process_frame

	assert(demo.initialized)
	assert(is_equal_approx(float(demo.controller.pace_model.shot_routine_seconds), 30.0))
	assert(is_equal_approx(float(demo.simulation_speed), 30.0))

	var release_before: Dictionary = demo.controller.release_scheduler.pending_release("group_2")
	assert(not release_before.is_empty())
	var release_time_before: float = float(release_before.get("release_time_seconds", -1.0))
	assert(release_time_before > 0.0)

	var initial: Dictionary = demo.snapshot()
	assert(str(initial.get("focus", {}).get("group_id", "")) == "group_1")
	assert(str(initial.get("focus", {}).get("status", "")) == "PLAYING")
	var playing_speed: float = float(initial.get("presentation_speed", 0.0))
	assert(is_equal_approx(playing_speed, 120.0))
	assert(playing_speed > float(demo.simulation_speed))

	var lead_playback = demo.session.playback_for_group("group_1")
	assert(lead_playback != null)
	var events: Array = lead_playback.schedule.get("events", [])
	assert(events.size() >= 2)
	var previous_time: float = float(lead_playback.schedule.get("start_time_seconds", 0.0))
	var largest_gap: float = 0.0
	for event_value in events:
		assert(typeof(event_value) == TYPE_DICTIONARY)
		var event: Dictionary = event_value
		var event_time: float = float(event.get("time_seconds", previous_time))
		largest_gap = maxf(largest_gap, maxf(0.0, event_time - previous_time))
		previous_time = event_time
	assert(largest_gap > 0.0)
	var baseline_real_gap: float = largest_gap / float(demo.simulation_speed)
	var compressed_real_gap: float = largest_gap / playing_speed
	assert(compressed_real_gap < baseline_real_gap)
	assert(compressed_real_gap <= baseline_real_gap * 0.26)

	assert(demo.select_group("group_2"))
	var waiting: Dictionary = demo.snapshot()
	assert(str(waiting.get("focus", {}).get("status", "")) == "WAITING")
	var waiting_speed: float = float(waiting.get("presentation_speed", 0.0))
	assert(is_equal_approx(waiting_speed, 60.0))
	assert(waiting_speed > float(demo.simulation_speed))
	assert(waiting_speed < playing_speed)

	var release_after: Dictionary = demo.controller.release_scheduler.pending_release("group_2")
	assert(not release_after.is_empty())
	assert(is_equal_approx(float(release_after.get("release_time_seconds", -2.0)), release_time_before))
	assert(is_equal_approx(float(demo.controller.pace_model.shot_routine_seconds), 30.0))

	print("POC25_PACING_SUMMARY base=%.0fx playing=%.0fx waiting=%.0fx largest_gap_sim=%.1fs baseline_real=%.2fs compressed_real=%.2fs release=%.1fs" % [
		float(demo.simulation_speed),
		playing_speed,
		waiting_speed,
		largest_gap,
		baseline_real_gap,
		compressed_real_gap,
		release_time_before
	])
	print("POC-25 SPECTATOR DEAD-TIME COMPRESSION PASSED")

	demo.queue_free()
	quit(0)

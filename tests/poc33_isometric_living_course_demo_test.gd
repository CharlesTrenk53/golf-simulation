extends SceneTree

const POC33LivingCourseDemo = preload("res://scenes/poc33_isometric_living_course_demo.gd")

var failures: int = 0


func _init() -> void:
	print("POC-33D: full isometric living-course visual proof")

	var demo = POC33LivingCourseDemo.new()
	demo.auto_advance = false
	get_root().add_child(demo)
	_assert_true(demo.initialize_demo(), "launchable POC-33D scene initializes")
	if not demo.initialized:
		demo.queue_free()
		_finish()
		return

	var initial: Dictionary = demo.snapshot()
	_assert_equal(int(initial.get("grid_width", 0)), 80, "living-course property uses authoritative 80-cell construction width")
	_assert_equal(int(initial.get("grid_height", 0)), 50, "living-course property uses authoritative 50-cell construction height")
	_assert_true(int(initial.get("fairway_cells", 0)) > 100, "player-authored property contains substantial fairway terrain")
	_assert_true(int(initial.get("tee_cells", 0)) >= 3, "player-authored property contains tee surfaces for living course")
	_assert_true(int(initial.get("green_cells", 0)) >= 15, "player-authored property contains visible greens")
	_assert_true(int(initial.get("bunker_cells", 0)) > 0, "player-authored property contains crisp bunker surfaces")
	_assert_equal(int(initial.get("group_count", 0)), 3, "launchable scene exposes all three living groups")
	_assert_equal(int(initial.get("golfer_count", 0)), 6, "launchable scene exposes all six living golfers")
	_assert_equal(int(initial.get("ball_count", 0)), 6, "launchable scene mirrors all six existing runtime balls")
	_assert_true(demo.renderer != null and demo.renderer.construction_grid == demo.grid, "accepted isometric renderer reads the authoritative construction grid")
	_assert_true(demo.camera != null and demo.camera.is_current(), "launchable scene owns an active isometric camera")
	_assert_true(demo.status_label != null and not demo.status_label.text.is_empty(), "launchable scene exposes living-course HUD status")

	var nonflat_samples: int = 0
	for sample in [Vector2i(4, 4), Vector2i(20, 15), Vector2i(45, 30), Vector2i(70, 42)]:
		if absf(float(demo.grid.tile_at(sample.x, sample.y).get("elevation", 0.0))) > 0.05:
			nonflat_samples += 1
	_assert_true(nonflat_samples >= 3, "living-course property retains authored rolling elevation")

	var grid_before: Dictionary = demo.grid.to_dictionary()
	_assert_true(demo.rotate_view(1), "living-course camera rotates through accepted isometric cardinal view")
	_assert_equal(int(demo.snapshot().get("rotation_quarters", -1)), 1, "rotation state is reflected by launchable scene")
	_assert_equal(int(demo.living_layer.snapshot().get("golfer_count", 0)), 6, "all golfer identities survive launchable camera rotation")
	_assert_true(demo.grid.to_dictionary() == grid_before, "camera rotation never mutates player-authored terrain")

	# Consume only dead authoritative clock time until the already-proven spectator
	# runtime launches a visible shot. The RuntimeBallVisual remains the trajectory
	# owner; POC-33D merely proves the launchable scene sees that live flight.
	var launched_flight: bool = false
	var clock_before: float = float(demo.controller.current_time_seconds)
	for _step in range(240):
		demo.advance_presentation(0.05)
		for ball_value in demo.living_layer.snapshot().get("balls", []):
			var ball: Dictionary = ball_value
			if bool(ball.get("is_flying", false)):
				launched_flight = true
				break
		if launched_flight:
			break
	_assert_true(float(demo.controller.current_time_seconds) > clock_before, "launchable presentation consumes authoritative course time")
	_assert_true(launched_flight, "launchable isometric scene receives a live authoritative ball flight")
	_assert_true(demo.grid.to_dictionary() == grid_before, "living playback never mutates player-authored construction terrain")

	var final_snapshot: Dictionary = demo.snapshot()
	print("POC33D_LIVING_VISUAL_SUMMARY groups=%d golfers=%d fairway=%d greens=%d bunkers=%d rotation=%d clock=%.1f live_flight=%s" % [
		int(final_snapshot.get("group_count", 0)),
		int(final_snapshot.get("golfer_count", 0)),
		int(final_snapshot.get("fairway_cells", 0)),
		int(final_snapshot.get("green_cells", 0)),
		int(final_snapshot.get("bunker_cells", 0)),
		int(final_snapshot.get("rotation_quarters", 0)),
		float(final_snapshot.get("simulation_time_seconds", 0.0)),
		str(launched_flight)
	])

	demo.queue_free()
	_finish()


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
		print("POC-33D FULL ISOMETRIC LIVING-COURSE VISUAL PROOF PASSED")
		quit(0)
	else:
		push_error("POC-33D FULL ISOMETRIC LIVING-COURSE VISUAL PROOF FAILED: %d" % failures)
		quit(1)

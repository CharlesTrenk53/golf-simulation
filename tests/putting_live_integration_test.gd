extends SceneTree

const AutonomousHole = preload("res://simulation/autonomous_hole.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

class FakeGreenContext:
	extends RefCounted
	func surface_at(_position: Vector3) -> int:
		return 5
	func surface_name(_surface: int) -> String:
		return "GREEN"
	func lie_quality(_surface: int) -> float:
		return 1.0
	func risk_modifier(_surface: int) -> float:
		return 0.0

var failures: int = 0


func _init() -> void:
	print("POC-15E: live autonomous putting integration")

	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.putting = 82.0
	golfer.confidence = 72.0
	golfer.risk_tolerance = 35.0
	get_root().add_child(golfer)

	var green = FakeGreenContext.new()
	var sim = AutonomousHole.new()
	var state = sim.create_state(Vector3.ZERO, Vector3(6.0, 0.0, 0.0), 4, 15015, green)
	var result: Dictionary = sim.play_step(golfer, state)

	_assert_true(not result.is_empty(), "autonomous hole produces a live putt result")
	_assert_true(int(result.get("shot_type", -1)) == 3, "live execution identifies the shot as a putt")
	_assert_true(result.has("putting"), "live putt carries the integrated putting pipeline payload")
	_assert_true(result.has("putting_strategy"), "live putt exposes chosen putting strategy")
	_assert_true(result["putting"].has("read"), "live putt includes green read")
	_assert_true(result["putting"].has("proficiency"), "live putt includes golfer-specific proficiency")
	_assert_true(result["putting"].has("execution"), "live putt includes stochastic execution")
	_assert_true(result["putting"].has("roll"), "live putt includes resolved ball roll")
	_assert_true(float(result["intended_distance"]) > 5.9, "course-space distance remains expressed in yards")
	_assert_true(float(result["putting"]["read"]["distance_feet"]) > 17.9, "putting pipeline converts live course yards to feet")
	_assert_true(bool(result.get("putting_holed", false)) == state.finished, "hole completion follows actual cup outcome rather than generic proximity")

	# A miss inside the old two-yard auto-finish radius must remain a live ball.
	var found_close_miss: bool = false
	for seed_value in range(1, 500):
		var retry_state = sim.create_state(Vector3.ZERO, Vector3(6.0, 0.0, 0.0), 4, seed_value, green)
		var retry: Dictionary = sim.play_step(golfer, retry_state)
		if retry.is_empty() or bool(retry.get("putting_holed", false)):
			continue
		if float(retry.get("remaining_after_shot", 99.0)) < 2.0:
			found_close_miss = true
			_assert_true(not retry_state.finished, "close missed putt is not falsely counted as holed")
			break
	_assert_true(found_close_miss, "seeded sample produces at least one close miss for finish-radius regression guard")

	golfer.queue_free()
	if failures == 0:
		print("POC-15E LIVE PUTTING INTEGRATION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-15E LIVE PUTTING INTEGRATION TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

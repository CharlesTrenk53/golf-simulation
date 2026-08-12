extends SceneTree

const PuttingReadModel = preload("res://simulation/putting_read_model.gd")
const PuttingProficiencyModel = preload("res://simulation/putting_proficiency_model.gd")
const PuttingExecutionModel = preload("res://simulation/putting_execution_model.gd")

class FakeGolfer:
	extends Node
	var putting: float = 70.0
	var coordination: float = 70.0
	var confidence: float = 70.0
	func get_shot_ability(shot_type: int) -> float:
		if shot_type == 3:
			return putting
		return 50.0

var failures: int = 0


func _init() -> void:
	print("POC-15B: putting proficiency and execution")
	var read_model = PuttingReadModel.new()
	var proficiency_model = PuttingProficiencyModel.new()
	var execution_model = PuttingExecutionModel.new()
	var planned: Dictionary = read_model.plan_putt(24.0, 1.2, 0.5, 10.5)

	var elite := FakeGolfer.new()
	elite.putting = 94.0
	elite.coordination = 92.0
	elite.confidence = 82.0
	get_root().add_child(elite)
	var developing := FakeGolfer.new()
	developing.putting = 45.0
	developing.coordination = 52.0
	developing.confidence = 58.0
	get_root().add_child(developing)

	var elite_profile: Dictionary = proficiency_model.assess(elite, planned)
	var developing_profile: Dictionary = proficiency_model.assess(developing, planned)
	_assert_true(float(elite_profile["execution_reliability"]) > float(developing_profile["execution_reliability"]), "better putter has higher execution reliability")
	_assert_true(float(elite_profile["line_sigma_inches"]) < float(developing_profile["line_sigma_inches"]), "better putter has tighter start-line dispersion")
	_assert_true(float(elite_profile["pace_sigma_feet"]) < float(developing_profile["pace_sigma_feet"]), "better putter has tighter pace dispersion")

	var elite_first: Dictionary = execution_model.realize(planned, elite_profile, 15021)
	var elite_repeat: Dictionary = execution_model.realize(planned, elite_profile, 15021)
	_assert_near(float(elite_first["line_error_inches"]), float(elite_repeat["line_error_inches"]), 0.000001, "same seed reproduces start-line error")
	_assert_near(float(elite_first["pace_error_feet"]), float(elite_repeat["pace_error_feet"]), 0.000001, "same seed reproduces pace error")
	_assert_true(str(elite_first["putt_signature"]) == str(planned["signature"]), "execution preserves planned putt identity")

	var alternate: Dictionary = execution_model.realize(planned, elite_profile, 15022)
	var changed: bool = absf(float(elite_first["line_error_inches"]) - float(alternate["line_error_inches"])) > 0.0001 or absf(float(elite_first["pace_error_feet"]) - float(alternate["pace_error_feet"])) > 0.0001
	_assert_true(changed, "different seed produces a different realized putt")

	var long_plan: Dictionary = read_model.plan_putt(45.0, 0.0, 0.0, 10.0)
	var long_profile: Dictionary = proficiency_model.assess(elite, long_plan)
	_assert_true(float(long_profile["pace_sigma_feet"]) > float(elite_profile["pace_sigma_feet"]), "longer putt widens pace uncertainty")

	elite.queue_free()
	developing.queue_free()
	if failures == 0:
		print("POC-15B PUTTING EXECUTION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-15B PUTTING EXECUTION TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(absf(actual - expected) <= tolerance, label)

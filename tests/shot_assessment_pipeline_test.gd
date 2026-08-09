extends SceneTree

const Pipeline = preload("res://simulation/shot_assessment_pipeline.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

var failures := 0

func _init() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	var original_driving = golfer.driving
	var bag = GolfBag.new()
	var driver = bag.get_club("DRIVER")
	var state = _AssessmentState.new()
	var options = [{
		"name": "DRIVER ATTACK",
		"club": driver,
		"shot_type": 0,
		"shot_form": "NORMAL",
		"target_position": Vector3(0, 0, 0),
		"model_success_chance": 62.0,
		"reward": 72.0,
		"risk": 55.0,
		"is_aggressive": true
	}]

	var supportive = Pipeline.new()
	supportive.initialize(golfer)
	supportive.set_social_context({
		"group_comfort": 90.0,
		"group_support": 90.0,
		"group_trust": 85.0,
		"group_intimidation": 5.0,
		"social_pressure": 5.0,
		"comparison_pressure": 5.0,
		"group_competitiveness": 50.0
	})
	var supportive_result = supportive.assess_options(golfer, state, options)[0]

	var intimidating = Pipeline.new()
	intimidating.initialize(golfer)
	intimidating.set_social_context({
		"group_comfort": 15.0,
		"group_support": 5.0,
		"group_trust": 20.0,
		"group_intimidation": 90.0,
		"social_pressure": 85.0,
		"comparison_pressure": 75.0,
		"group_competitiveness": 50.0
	})
	var intimidating_result = intimidating.assess_options(golfer, state, options)[0]

	var supportive_objective: Dictionary = supportive_result["assessment"]["objective"]
	var supportive_subjective: Dictionary = supportive_result["assessment"]["subjective"]
	var intimidating_subjective: Dictionary = intimidating_result["assessment"]["subjective"]
	_expect(supportive_result["assessment"].has("objective"), "pipeline exposes objective shot assessment")
	_expect(supportive_result["assessment"].has("subjective"), "pipeline exposes golfer-subjective shot assessment")
	_expect(float(supportive_objective["model_success_chance"]) == 62.0, "objective model success remains the supplied shot probability")
	_expect(float(supportive_subjective["social_readiness"]) > float(intimidating_subjective["social_readiness"]), "playing group changes social execution readiness")
	_expect(float(supportive_subjective["willingness"]["willingness_score"]) > float(intimidating_subjective["willingness"]["willingness_score"]), "supportive group can increase willingness for the same shot")
	_expect(float(supportive_subjective["believed_success_chance"]) > float(intimidating_subjective["believed_success_chance"]), "playing group can alter perceived success without rewriting objective success")
	_expect(abs(golfer.driving - original_driving) < 0.001, "playing-group context never rewrites underlying driving skill")

	print("============================================================")
	print("POC-08 INTEGRATED SHOT ASSESSMENT")
	print("Supportive social readiness: %.2f | willingness: %.2f | believed success: %.2f" % [
		float(supportive_subjective["social_readiness"]),
		float(supportive_subjective["willingness"]["willingness_score"]),
		float(supportive_subjective["believed_success_chance"])
	])
	print("Intimidating social readiness: %.2f | willingness: %.2f | believed success: %.2f" % [
		float(intimidating_subjective["social_readiness"]),
		float(intimidating_subjective["willingness"]["willingness_score"]),
		float(intimidating_subjective["believed_success_chance"])
	])
	print("============================================================")

	golfer.free()
	if failures == 0:
		print("POC-08 INTEGRATED SHOT ASSESSMENT TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 INTEGRATED SHOT ASSESSMENT TESTS FAILED: %d" % failures)
		quit(1)

class _AssessmentState:
	extends RefCounted
	var ball_position := Vector3(0, 0, 55)
	var hole_position := Vector3(0, 0, 0)
	var current_lie_quality := 0.95
	var course_context = null
	func surface_name() -> String:
		return "TEE"

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

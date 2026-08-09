extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const CourseState = preload("res://simulation/course_state.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")
const ShotAssessmentPipeline = preload("res://simulation/shot_assessment_pipeline.gd")

var failures := 0

func _init() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 0
	golfer.apply_profile()
	var bag = GolfBag.new()
	var driver = bag.get_club("DRIVER")
	var state = CourseState.new(Vector3.ZERO, Vector3(0, 0, -70), 4)
	var pipeline = ShotAssessmentPipeline.new()
	pipeline.initialize(golfer)

	var option = {
		"name": "ATTACK",
		"shot_type": 0,
		"club": driver,
		"club_id": driver.get("id", "DRIVER"),
		"club_name": driver.get("name", "Driver"),
		"target_position": state.hole_position,
		"reward": 65.0,
		"risk": 35.0,
		"model_success_chance": 72.0,
		"is_aggressive": true,
		"shot_form": "NORMAL"
	}

	var before = pipeline.assess_options(golfer, state, [option], [])[0]
	var before_assessment: Dictionary = before["assessment"]
	var before_capability = float(before_assessment["capability"]["capability_score"])
	var before_confidence = float(before_assessment["specific_confidence"])
	var before_comfort = float(before_assessment["comfort"]["comfort"])
	var before_willingness = float(before_assessment["willingness"]["willingness_score"])
	var before_belief = float(before_assessment["comfort_believed_success_chance"])

	for _i in range(5):
		pipeline.record_result(before, {
			"target_position": state.hole_position,
			"landing_position": Vector3(15, 0, -48),
			"start_position": Vector3.ZERO,
			"outcome": "SUCCESS",
			"execution_quality": "POOR",
			"execution_score": 15.0
		})

	var after = pipeline.assess_options(golfer, state, [option], [])[0]
	var after_assessment: Dictionary = after["assessment"]
	var after_capability = float(after_assessment["capability"]["capability_score"])
	var after_confidence = float(after_assessment["specific_confidence"])
	var after_comfort = float(after_assessment["comfort"]["comfort"])
	var after_willingness = float(after_assessment["willingness"]["willingness_score"])
	var after_belief = float(after_assessment["comfort_believed_success_chance"])

	_expect(is_equal_approx(before_capability, after_capability), "poor Driver history does not rewrite underlying capability")
	_expect(after_comfort < before_comfort, "poor Driver history lowers learned Driver comfort")
	_expect(after_confidence < before_confidence, "lower comfort feeds specific shot confidence")
	_expect(after_willingness < before_willingness, "lower comfort reduces willingness to choose the same shot")
	_expect(after_belief < before_belief, "lower comfort reduces perceived success without changing model success")
	_expect(is_equal_approx(float(after["model_success_chance"]), 72.0), "objective model success chance remains unchanged")

	var commitment_before = pipeline.commitment_model.assess_commitment(golfer, before_assessment["capability"], before_confidence, {"focus": 75.0, "nervous": 0.0, "fear": 0.0, "frustrated": 0.0}, 0.0)
	var commitment_after = pipeline.commitment_model.assess_commitment(golfer, after_assessment["capability"], after_confidence, {"focus": 75.0, "nervous": 0.0, "fear": 0.0, "frustrated": 0.0}, 0.0)
	_expect(float(commitment_after["score"]) < float(commitment_before["score"]), "learned comfort can reduce commitment through specific confidence")

	golfer.free()
	if failures == 0:
		print("POC-08 GOLFER COMFORT INTEGRATION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 GOLFER COMFORT INTEGRATION TESTS FAILED: %d" % failures)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

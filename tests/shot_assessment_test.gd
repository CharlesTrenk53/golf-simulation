extends SceneTree

const ShotSituation = preload("res://simulation/shot_situation.gd")
const ShotRequirements = preload("res://simulation/shot_requirements.gd")
const GolferAssessment = preload("res://simulation/golfer_assessment.gd")
const GolferStateContext = preload("res://simulation/golfer_state_context.gd")
const RecentPerformanceContext = preload("res://simulation/recent_performance_context.gd")
const ShotCommitment = preload("res://simulation/shot_commitment.gd")
const FutureStateEstimator = preload("res://simulation/future_state_estimator.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

var failures := 0

func _init() -> void:
	var hazards = [{"name": "Water", "position": Vector3(0, 0, 25), "radius": 7.0, "risk": 90.0}]
	var situation = ShotSituation.new(Vector3(0, 0, 55), Vector3(0, 0, -10), "FAIRWAY", 0.95, hazards)
	_expect(abs(situation.distance_to_target - 65.0) < 0.01, "world tracks physical distance")
	situation.set_weather(10.0, Vector3(0, 0, 1), 50.0, 0.0)
	_expect(situation.effective_playing_distance() > situation.distance_to_target, "headwind/cold can increase playing distance")

	var requirements_model = ShotRequirements.new()
	var requirements = requirements_model.derive(situation)
	_expect(float(requirements["required_carry"]) > 30.0, "hazard creates meaningful carry requirement")
	_expect(float(requirements["short_miss_cost"]) >= 90.0, "water makes short miss expensive")
	_expect(bool(requirements["obstacle_clearance_required"]), "hazard can require obstacle clearance")

	var bill = QuietGolfer.new(); bill.profile = 0; bill.apply_profile()
	var rick = QuietGolfer.new(); rick.profile = 1; rick.apply_profile()
	var assessment = GolferAssessment.new()
	var bill_perception = assessment.perceive(bill, situation)
	var rick_perception = assessment.perceive(rick, situation)
	_expect(bill_perception.has("distance") and rick_perception.has("distance"), "perception layer produces golfer belief state")
	_expect(float(bill_perception["judgment_skill"]) != float(rick_perception["judgment_skill"]), "golfers can perceive same world differently")

	var bag = GolfBag.new()
	var driver = bag.get_club("DRIVER")
	var bill_driver = assessment.assess_club(bill, situation, requirements, driver)
	var rick_driver = assessment.assess_club(rick, situation, requirements, driver)
	_expect(float(bill_driver["capability_score"]) > float(rick_driver["capability_score"]), "same club-shot requirement can fit golfers differently")
	_expect(float(bill_driver["expected_carry"]) > float(rick_driver["expected_carry"]), "golfer ability changes expected club performance")

	var fresh = GolferStateContext.new()
	var tired = GolferStateContext.new()
	tired.set_physical_condition({"fatigue": 85.0, "energy": 35.0, "balance": 70.0, "hydration": 60.0, "holes_played": 17})
	_expect(tired.physical_readiness() < fresh.physical_readiness(), "fatigue and low energy reduce current physical readiness")
	var fresh_bill_driver = assessment.assess_club(bill, situation, requirements, driver, fresh)
	var tired_bill_driver = assessment.assess_club(bill, situation, requirements, driver, tired)
	_expect(float(tired_bill_driver["expected_carry"]) < float(fresh_bill_driver["expected_carry"]), "current physical condition can reduce effective carry")

	var focused = GolferStateContext.new()
	var rattled = GolferStateContext.new()
	rattled.set_mental_state({"calm": 20.0, "nervous": 70.0, "frustration": 75.0, "focus": 35.0, "distraction": 60.0, "pressure": 80.0})
	_expect(rattled.mental_execution_readiness() < focused.mental_execution_readiness(), "nerves frustration distraction and pressure reduce mental readiness")
	var rattled_driver = assessment.assess_club(bill, situation, requirements, driver, rattled)
	_expect(float(rattled_driver["expected_dispersion"]) > float(fresh_bill_driver["expected_dispersion"]), "poor mental state can widen expected dispersion")

	var chasing = GolferStateContext.new()
	chasing.set_strategic_context({"hole_number": 18, "holes_remaining": 0, "chasing": true, "score_differential_to_target": -3})
	var protecting = GolferStateContext.new()
	protecting.set_strategic_context({"hole_number": 18, "holes_remaining": 0, "protecting_lead": true, "score_differential_to_target": 3})
	_expect(chasing.aggression_pressure() > 0.0, "late chasing situation increases strategic aggression pressure")
	_expect(protecting.aggression_pressure() < 0.0, "protecting a lead reduces strategic aggression pressure")
	var attack_option = {"name": "ATTACK", "risk": 60.0, "is_aggressive": true}
	var chase_willingness = assessment.assess_willingness(bill, fresh_bill_driver, attack_option, chasing)
	var protect_willingness = assessment.assess_willingness(bill, fresh_bill_driver, attack_option, protecting)
	_expect(float(chase_willingness["willingness_score"]) > float(protect_willingness["willingness_score"]), "same golfer becomes more willing to attack when strategic context demands it")

	var performance = RecentPerformanceContext.new()
	performance.initialize_from_golfer(bill)
	var baseline_confidence = performance.confidence_for(bill, driver, "FAIRWAY", 20.0)
	for _i in range(3):
		performance.record_shot(driver, "WATER", "POOR", -5.0, -4.0)
	var slumping_confidence = performance.confidence_for(bill, driver, "FAIRWAY", 20.0)
	var slump_modifier = performance.performance_modifier_for(driver)
	_expect(slumping_confidence < baseline_confidence, "repeated poor driver outcomes reduce club-specific confidence")
	_expect(float(slump_modifier["dispersion_factor"]) > 1.0, "recent poor driving can widen expected dispersion")
	_expect(float(slump_modifier["directional_bias"]) < 0.0, "recent misses can create a remembered left-right tendency")

	var commitment_model = ShotCommitment.new()
	var miss_map = commitment_model.assess_miss_consequences(situation, situation.target_position, float(fresh_bill_driver["expected_dispersion"]))
	_expect(miss_map.has("short") == false and miss_map.has("costs"), "miss consequence layer returns directional cost map")
	_expect(float(miss_map["worst_cost"]) >= float(miss_map["safest_cost"]), "miss consequences identify safer and worse miss directions")

	var calm_mental = {"focus": 85.0, "nervous": 10.0, "fear": 5.0, "frustrated": 5.0}
	var doubtful_mental = {"focus": 30.0, "nervous": 80.0, "fear": 70.0, "frustrated": 60.0}
	var committed = commitment_model.assess_commitment(bill, fresh_bill_driver, 90.0, calm_mental, 0.0)
	var doubtful = commitment_model.assess_commitment(bill, fresh_bill_driver, 35.0, doubtful_mental, 12.0)
	_expect(float(committed["score"]) > float(doubtful["score"]), "specific confidence and mental state alter commitment after decision")
	_expect(float(doubtful["dispersion_factor"]) > float(committed["dispersion_factor"]), "low commitment can worsen execution dispersion")
	_expect(float(doubtful["carry_factor"]) < float(committed["carry_factor"]), "low commitment can reduce effective carry")

	# Shallow look-ahead distinguishes a shot that leaves a strong next state from
	# a conservative shot that still leaves too much work.
	var estimator = FutureStateEstimator.new()
	var fake_state = RefCounted.new()
	fake_state.set_meta("unused", true)
	# Use a lightweight object with the fields/methods the estimator needs.
	var state = _FutureTestState.new()
	state.hole_position = Vector3(0, 0, 0)
	var attack = {"name": "ATTACK", "target_position": Vector3(0, 0, 8), "model_success_chance": 80.0, "assessment": {"capability": {"expected_dispersion": 3.0}, "miss_consequences": {"worst_cost": 15.0}}}
	var layup = {"name": "LAYUP", "target_position": Vector3(0, 0, 38), "model_success_chance": 95.0, "assessment": {"capability": {"expected_dispersion": 2.0}, "miss_consequences": {"worst_cost": 5.0}}}
	var attack_future = estimator.estimate(bill, state, attack)
	var layup_future = estimator.estimate(bill, state, layup)
	_expect(float(attack_future["expected_strokes_remaining"]) < float(layup_future["expected_strokes_remaining"]), "lookahead rewards a materially stronger next state")
	_expect(int(attack_future["lookahead_depth"]) == 1, "future-state estimator remains intentionally shallow")

	bill.free(); rick.free()
	if failures == 0:
		print("POC-08 SHOT ASSESSMENT TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 SHOT ASSESSMENT TESTS FAILED: %d" % failures)
		quit(1)

class _FutureTestState:
	extends RefCounted
	var hole_position := Vector3.ZERO
	var course_context = null

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

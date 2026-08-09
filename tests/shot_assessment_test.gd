extends SceneTree

const ShotSituation = preload("res://simulation/shot_situation.gd")
const ShotRequirements = preload("res://simulation/shot_requirements.gd")
const GolferAssessment = preload("res://simulation/golfer_assessment.gd")
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

	bill.free(); rick.free()
	if failures == 0:
		print("POC-08 SHOT ASSESSMENT TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 SHOT ASSESSMENT TESTS FAILED: %d" % failures)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

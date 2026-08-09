extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const AutonomousHole = preload("res://simulation/autonomous_hole.gd")
const CourseState = preload("res://simulation/course_state.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")

const START := Vector3(0, 0, 55)
const HOLE := Vector3(0, 0, -55)

var failures := 0

func _init() -> void:
	var bag = GolfBag.new()
	var driver = bag.get_club("DRIVER")

	var rick = _golfer(1)
	var carl = _golfer(2)
	var rick_sim = AutonomousHole.new()
	var carl_sim = AutonomousHole.new()

	# Initialize once, then carry the same memory model across a sequence of holes.
	var rick_before = _tee_attack_assessment(rick_sim, rick)
	var carl_before = _tee_attack_assessment(carl_sim, carl)
	var rick_capability_before = float(rick_before["assessment"]["capability"]["capability_score"])
	var carl_capability_before = float(carl_before["assessment"]["capability"]["capability_score"])

	var rick_confidence_path: Array = [float(rick_before["assessment"]["specific_confidence"])]
	var carl_confidence_path: Array = [float(carl_before["assessment"]["specific_confidence"])]
	var rick_willingness_path: Array = [float(rick_before["assessment"]["willingness"]["willingness_score"])]
	var carl_willingness_path: Array = [float(carl_before["assessment"]["willingness"]["willingness_score"])]

	# Six bad Driver experiences represent an early-round slump. We use the same
	# execution evidence for both golfers so any difference in reaction comes from
	# golfer state/personality, not different outcomes.
	for hole_number in range(1, 7):
		rick_sim.assessment_pipeline.memory_comfort.record_experience(driver, "NORMAL", "POOR", "WATER", 18.0)
		carl_sim.assessment_pipeline.memory_comfort.record_experience(driver, "NORMAL", "POOR", "WATER", 18.0)
		var rick_after_hole = _tee_attack_assessment(rick_sim, rick)
		var carl_after_hole = _tee_attack_assessment(carl_sim, carl)
		rick_confidence_path.append(float(rick_after_hole["assessment"]["specific_confidence"]))
		carl_confidence_path.append(float(carl_after_hole["assessment"]["specific_confidence"]))
		rick_willingness_path.append(float(rick_after_hole["assessment"]["willingness"]["willingness_score"]))
		carl_willingness_path.append(float(carl_after_hole["assessment"]["willingness"]["willingness_score"]))

	var rick_after = _tee_attack_assessment(rick_sim, rick)
	var carl_after = _tee_attack_assessment(carl_sim, carl)
	var rick_capability_after = float(rick_after["assessment"]["capability"]["capability_score"])
	var carl_capability_after = float(carl_after["assessment"]["capability"]["capability_score"])

	var rick_conf_drop = rick_confidence_path[0] - rick_confidence_path[-1]
	var carl_conf_drop = carl_confidence_path[0] - carl_confidence_path[-1]
	var rick_will_drop = rick_willingness_path[0] - rick_willingness_path[-1]
	var carl_will_drop = carl_willingness_path[0] - carl_willingness_path[-1]

	_expect(rick_confidence_path[-1] < rick_confidence_path[0], "Rick remembers repeated Driver failures")
	_expect(carl_confidence_path[-1] < carl_confidence_path[0], "Carl remembers repeated Driver failures")
	_expect(carl_conf_drop > rick_conf_drop, "Carl's high responsiveness creates a larger confidence reaction than Rick")
	_expect(carl_will_drop > rick_will_drop, "Carl's high responsiveness creates a larger willingness reaction than Rick")
	_expect(abs(rick_capability_after - rick_capability_before) < 0.001, "Rick's learned slump does not rewrite Driver capability")
	_expect(abs(carl_capability_after - carl_capability_before) < 0.001, "Carl's learned slump does not rewrite Driver capability")
	_expect(_is_nonincreasing(rick_confidence_path), "Rick's Driver confidence trends downward as failures accumulate")
	_expect(_is_nonincreasing(carl_confidence_path), "Carl's Driver confidence trends downward as failures accumulate")

	print("============================================================")
	print("POC-08 MULTI-HOLE MEMORY ADAPTATION")
	print("Rick responsiveness %.1f | confidence drop %.2f | willingness drop %.2f" % [rick.responsiveness_to_experience, rick_conf_drop, rick_will_drop])
	print("Rick confidence path: ", rick_confidence_path)
	print("Carl responsiveness %.1f | confidence drop %.2f | willingness drop %.2f" % [carl.responsiveness_to_experience, carl_conf_drop, carl_will_drop])
	print("Carl confidence path: ", carl_confidence_path)
	print("============================================================")

	rick.free()
	carl.free()
	if failures == 0:
		print("POC-08 MULTI-HOLE MEMORY ADAPTATION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 MULTI-HOLE MEMORY ADAPTATION TESTS FAILED: %d" % failures)
		quit(1)

func _golfer(profile: int) -> Node:
	var golfer = QuietGolfer.new()
	golfer.profile = profile
	golfer.apply_profile()
	golfer.decision_variability = 0.0
	return golfer

func _tee_attack_assessment(simulation, golfer: Node) -> Dictionary:
	var state = CourseState.new(START, HOLE, 4, null)
	var options = simulation.option_generator.generate_options(golfer, state, [])
	var attack: Dictionary = {}
	for option in options:
		if String(option.get("name", "")) == "ATTACK":
			attack = option.duplicate(true)
			break
	if attack.is_empty():
		failures += 1
		push_error("Could not locate ATTACK option")
		return {}

	# This test is specifically about Driver memory. Rick and Carl's normal club
	# selector prefers a 5 Iron at this synthetic distance, so explicitly bind the
	# ATTACK probe to Driver instead of silently assessing the wrong club.
	var driver = GolfBag.new().get_club("DRIVER")
	attack["club"] = driver
	attack["club_id"] = driver["id"]
	attack["club_name"] = driver["name"]
	attack["shot_type"] = driver["shot_type"]
	var assessed = simulation.assessment_pipeline.assess_options(golfer, state, [attack], [])
	return assessed[0]

func _is_nonincreasing(values: Array) -> bool:
	for i in range(1, values.size()):
		if float(values[i]) > float(values[i - 1]) + 0.001:
			return false
	return true

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

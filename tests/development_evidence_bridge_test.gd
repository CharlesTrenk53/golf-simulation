extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const DevelopmentEvidenceBridge = preload("res://simulation/development_evidence_bridge.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

var failures := 0

func _init() -> void:
	_test_practice_quality_separates_experience_from_evidence()
	_test_play_exposure_is_contextual_evidence_and_experience()
	_test_zero_quality_practice_does_not_award_skill()
	_test_legacy_record_execution_behavior_remains_intact()
	if failures == 0:
		print("POC-10 DEVELOPMENT EVIDENCE BRIDGE TESTS PASSED")
		quit(0)
	else:
		push_error("POC-10 DEVELOPMENT EVIDENCE BRIDGE TESTS FAILED: %d" % failures)
		quit(1)

func _test_practice_quality_separates_experience_from_evidence() -> void:
	var low = _development()
	var high = _development()
	var bridge = DevelopmentEvidenceBridge.new()
	bridge.apply_practice_exposure(low, 0, 100, 0.25, 70.0)
	bridge.apply_practice_exposure(high, 0, 100, 0.90, 70.0)
	var low_state: Dictionary = low.development_state(0)
	var high_state: Dictionary = high.development_state(0)
	_expect(int(low_state["total_experience"]) == int(high_state["total_experience"]), "same raw practice volume creates the same total experience")
	_expect(int(low_state["evidence_count"]) == 25, "25 percent quality practice creates 25 evidence repetitions from 100 reps")
	_expect(int(high_state["evidence_count"]) == 90, "90 percent quality practice creates 90 evidence repetitions from 100 reps")
	_expect(int(low_state["supplemental_experience"]) == 75, "low-quality repetitions still remain as experience")
	_expect(int(high_state["supplemental_experience"]) == 10, "high-quality practice needs fewer experience-only repetitions")

func _test_play_exposure_is_contextual_evidence_and_experience() -> void:
	var development = _development()
	var bridge = DevelopmentEvidenceBridge.new()
	var before: Dictionary = development.development_state(1)
	bridge.apply_play_exposure(development, 1, 40, 68.0)
	var after: Dictionary = development.development_state(1)
	_expect(int(after["evidence_count"]) - int(before["evidence_count"]) == 40, "on-course repetitions enter the current engine as contextual evidence")
	_expect(int(after["total_experience"]) - int(before["total_experience"]) == 40, "on-course repetitions also increase experience")
	_expect(int(after["supplemental_experience"]) == 0, "play does not need experience-only bookkeeping")

func _test_zero_quality_practice_does_not_award_skill() -> void:
	var development = _development()
	var bridge = DevelopmentEvidenceBridge.new()
	var before: Dictionary = development.development_state(2)
	bridge.apply_practice_exposure(development, 2, 200, 0.0, 90.0)
	var after: Dictionary = development.development_state(2)
	_expect(int(after["evidence_count"]) == int(before["evidence_count"]), "zero-quality practice produces no development evidence")
	_expect(int(after["total_experience"]) - int(before["total_experience"]) == 200, "zero-quality practice still records repetitions as experience")
	_expect(abs(float(after["skill_delta"]) - float(before["skill_delta"])) < 0.000001, "experience-only practice does not directly award skill")

func _test_legacy_record_execution_behavior_remains_intact() -> void:
	var development = _development()
	var before: Dictionary = development.development_state(3)
	development.record_execution(3, 70.0, 0.0, 0.0)
	var after: Dictionary = development.development_state(3)
	_expect(int(after["evidence_count"]) - int(before["evidence_count"]) == 1, "legacy record_execution still records one evidence event")
	_expect(int(after["total_experience"]) - int(before["total_experience"]) == 1, "legacy record_execution still contributes one experience event")

func _development():
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.age = 30
	golfer.driving = 50.0
	golfer.approach = 50.0
	golfer.short_game = 50.0
	golfer.putting = 50.0
	golfer.career_shot_experience = {0: 0, 1: 0, 2: 0, 3: 0}
	var development = TechniqueSkillDevelopment.new()
	development.initialize_from_golfer(golfer)
	golfer.free()
	return development

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

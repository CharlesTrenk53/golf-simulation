extends SceneTree

const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

var failures := 0

func _init() -> void:
	_test_legacy_default_is_neutral()
	_test_skill_specific_potential_persists_on_golfer()
	_test_development_reads_golfer_potential()

	if failures == 0:
		print("POC-09 GOLFER SKILL POTENTIAL TESTS PASSED")
		quit(0)
	else:
		push_error("POC-09 GOLFER SKILL POTENTIAL TESTS FAILED: %d" % failures)
		quit(1)

func _test_legacy_default_is_neutral() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	_expect(golfer.skill_potential_for(0) == 100.0, "unconfigured golfer defaults to neutral drive potential")
	_expect(golfer.skill_potential_for(1) == 100.0, "unconfigured golfer defaults to neutral approach potential")
	golfer.free()

func _test_skill_specific_potential_persists_on_golfer() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.set_skill_potential(0, 68.0)
	golfer.set_skill_potential(1, 84.0)
	_expect(golfer.skill_potential_for(0) == 68.0, "drive potential is stored on the golfer")
	_expect(golfer.skill_potential_for(1) == 84.0, "approach potential is stored independently on the golfer")
	_expect(golfer.skill_potential_for(2) == 100.0, "unconfigured skill remains legacy-neutral")
	golfer.free()

func _test_development_reads_golfer_potential() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.set_skill_potential(0, 61.0)
	golfer.set_skill_potential(1, 88.0)
	var development = TechniqueSkillDevelopment.new()
	development.initialize_from_golfer(golfer)
	_expect(development.skill_potential_for(0) == 61.0, "technique development reads persistent drive potential from golfer")
	_expect(development.skill_potential_for(1) == 88.0, "technique development reads persistent approach potential from golfer")
	_expect(development.skill_potential_for(2) == 100.0, "development preserves neutral default for unconfigured golfer skill")
	golfer.free()

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

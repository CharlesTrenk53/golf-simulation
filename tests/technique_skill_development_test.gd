extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")

var failures := 0

func _init() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 0
	golfer.apply_profile()
	var model = TechniqueSkillDevelopment.new()
	model.initialize_from_golfer(golfer)
	var baseline = model.development_state(0)
	_expect(abs(float(baseline["skill_delta"])) < 0.001, "skill starts at established baseline")

	# Short slump: confidence systems may react, but true skill must not.
	for i in range(20):
		model.record_execution(0, 22.0, 8.0, -5.0)
	var short_slump = model.development_state(0)
	_expect(abs(float(short_slump["skill_delta"])) < 0.001, "short slump does not change true skill")
	_expect(float(short_slump["technique_bias"]["lateral"]) > 0.0, "repeated directional misses begin forming a technique pattern")

	# Sustained poor execution: skill should drift, but only slightly.
	for i in range(140):
		model.record_execution(0, 24.0, 8.0, -5.0)
	var long_slump = model.development_state(0)
	_expect(float(long_slump["skill_delta"]) < 0.0, "sustained poor execution eventually lowers skill")
	_expect(float(long_slump["skill_delta"]) > -2.0, "skill deterioration remains deliberately gradual")
	_expect(not bool(long_slump["coaching_candidate"]), "moderate drift does not trigger coaching too early")

	# Much longer poor stretch can eventually cross a future coaching threshold.
	for i in range(500):
		model.record_execution(0, 18.0, 9.0, -6.0)
	var deep_slump = model.development_state(0)
	_expect(float(deep_slump["skill_delta"]) <= -2.5, "very long slump can reach coaching threshold")
	_expect(bool(deep_slump["coaching_candidate"]), "coaching candidate flag activates at threshold delta")

	# Recovery is also slow; a few good shots should not instantly restore skill.
	var before_recovery = float(deep_slump["skill_delta"])
	for i in range(30):
		model.record_execution(0, 90.0, 0.0, 0.0)
	var early_recovery = model.development_state(0)
	_expect(float(early_recovery["skill_delta"]) > before_recovery, "excellent execution begins gradual recovery")
	_expect(float(early_recovery["skill_delta"]) < -1.5, "short recovery streak cannot erase a long-term skill decline")

	print("============================================================")
	print("POC-08 TECHNIQUE & SKILL DEVELOPMENT")
	print("Short slump delta: %.3f" % float(short_slump["skill_delta"]))
	print("Long slump delta: %.3f" % float(long_slump["skill_delta"]))
	print("Deep slump delta: %.3f | coaching candidate %s" % [float(deep_slump["skill_delta"]), str(deep_slump["coaching_candidate"])])
	print("Early recovery delta: %.3f" % float(early_recovery["skill_delta"]))
	print("============================================================")
	golfer.free()
	if failures == 0:
		print("POC-08 TECHNIQUE & SKILL DEVELOPMENT TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 TECHNIQUE & SKILL DEVELOPMENT TESTS FAILED: %d" % failures)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

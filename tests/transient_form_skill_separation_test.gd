extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const TechniqueSkillDevelopment = preload("res://simulation/technique_skill_development.gd")

var failures := 0

func _init() -> void:
	var unfiltered_golfer = QuietGolfer.new()
	unfiltered_golfer.profile = 1
	unfiltered_golfer.apply_profile()
	unfiltered_golfer.career_shot_experience[0] = 6000

	var filtered_golfer = QuietGolfer.new()
	filtered_golfer.profile = 1
	filtered_golfer.apply_profile()
	filtered_golfer.career_shot_experience[0] = 6000

	var unfiltered = TechniqueSkillDevelopment.new()
	unfiltered.initialize_from_golfer(unfiltered_golfer)
	var filtered = TechniqueSkillDevelopment.new()
	filtered.initialize_from_golfer(filtered_golfer)

	# Both golfers experience the same prolonged -8 point form stretch. The first
	# model has no knowledge that the poor execution is transient. The second gets
	# the underlying persistent-learning quality (65) separately from observed form
	# performance (57). Current execution is therefore equally poor, but learned
	# technique should be protected from being rewritten as aggressively.
	for _shot in range(1200):
		unfiltered.record_execution(0, 57.0, 2.0, -1.0)
		filtered.record_execution(0, 57.0, 2.0, -1.0, 65.0)

	var unfiltered_state: Dictionary = unfiltered.development_state(0)
	var filtered_state: Dictionary = filtered.development_state(0)
	var unfiltered_delta: float = float(unfiltered_state["skill_delta"])
	var filtered_delta: float = float(filtered_state["skill_delta"])

	_expect(unfiltered_delta < 0.0, "unidentified prolonged poor execution can lower persistent skill")
	_expect(filtered_delta > unfiltered_delta + 0.25, "known transient form is substantially filtered from persistent skill change")
	_expect(float(filtered_state["average_execution_quality"]) < 60.0, "observed current execution still reflects the slump")
	_expect(float(filtered_state["average_persistent_execution_quality"]) > 64.0, "persistent learning evidence retains underlying quality")

	print("============================================================")
	print("POC-08 TRANSIENT FORM / PERSISTENT SKILL SEPARATION")
	print("Unfiltered skill delta: %.3f" % unfiltered_delta)
	print("Filtered skill delta:   %.3f" % filtered_delta)
	print("Observed quality:       %.3f" % float(filtered_state["average_execution_quality"]))
	print("Persistent quality:     %.3f" % float(filtered_state["average_persistent_execution_quality"]))
	print("============================================================")

	unfiltered_golfer.free()
	filtered_golfer.free()
	if failures == 0:
		print("POC-08 TRANSIENT FORM SKILL SEPARATION TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 TRANSIENT FORM SKILL SEPARATION TESTS FAILED: %d" % failures)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

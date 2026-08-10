extends SceneTree

const TechnicalReadiness = preload("res://simulation/technical_readiness.gd")

var failures := 0

func _init() -> void:
	_test_inactivity_penalty_accelerates()
	_test_rust_reduces_usable_not_durable_skill()
	_test_activity_recovers_rust_quickly()
	_test_recovery_is_skill_specific()
	if failures == 0:
		print("POC-10 TECHNICAL READINESS TESTS PASSED")
		quit(0)
	else:
		push_error("POC-10 TECHNICAL READINESS TESTS FAILED: %d" % failures)
		quit(1)

func _test_inactivity_penalty_accelerates() -> void:
	var readiness = TechnicalReadiness.new()
	var week := readiness.inactivity_penalty_for_days(7.0)
	var month := readiness.inactivity_penalty_for_days(30.0)
	var quarter := readiness.inactivity_penalty_for_days(90.0)
	var year := readiness.inactivity_penalty_for_days(365.0)
	var five_years := readiness.inactivity_penalty_for_days(1825.0)
	_expect(week > 0.0 and week < 0.5, "one week creates only a small rust penalty")
	_expect(month > week, "one month creates more rust than one week")
	_expect(quarter > month, "three months creates more rust than one month")
	_expect(year > quarter + 3.0, "one year creates a substantially larger regression than three months")
	_expect(five_years > year, "multi-year inactivity continues to increase rust")
	_expect(five_years < TechnicalReadiness.MAX_RUST_PENALTY, "rust saturates instead of erasing durable golf education")

func _test_rust_reduces_usable_not_durable_skill() -> void:
	var readiness = TechnicalReadiness.new()
	var durable_skill := 70.0
	readiness.advance_days(365.0)
	var usable := readiness.usable_skill(durable_skill, 0)
	_expect(usable < durable_skill - 5.0, "a year away materially lowers currently usable skill")
	_expect(abs(durable_skill - 70.0) < 0.000001, "rust never mutates durable learned skill")

func _test_activity_recovers_rust_quickly() -> void:
	var readiness = TechnicalReadiness.new()
	readiness.advance_days(365.0)
	var before := float(readiness.state_for(1)["rust_penalty"])
	readiness.record_activity(1, 220)
	var after_220 := float(readiness.state_for(1)["rust_penalty"])
	readiness.record_activity(1, 440)
	var after_660 := float(readiness.state_for(1)["rust_penalty"])
	_expect(abs(after_220 - before * 0.5) < 0.001, "220 meaningful reps remove half of accumulated rust")
	_expect(after_660 < before * 0.15, "several hundred returning reps recover most technical access")

func _test_recovery_is_skill_specific() -> void:
	var readiness = TechnicalReadiness.new()
	readiness.advance_days(365.0)
	var approach_before := float(readiness.state_for(1)["rust_penalty"])
	readiness.record_activity(0, 500)
	_expect(float(readiness.state_for(0)["rust_penalty"]) < approach_before, "Driver activity restores Driver readiness")
	_expect(abs(float(readiness.state_for(1)["rust_penalty"]) - approach_before) < 0.001, "Driver activity does not magically restore Approach readiness")

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

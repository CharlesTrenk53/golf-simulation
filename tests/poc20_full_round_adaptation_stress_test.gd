extends SceneTree

const GolferScript = preload("res://scenes/golfer.gd")
const QuietGolfer = preload("res://tests/fixtures/poc19_quiet_golfer.gd")
const AutonomousRound = preload("res://simulation/autonomous_round.gd")
const StrategicCourseFixture = preload("res://tests/fixtures/poc19_strategic_course_fixture.gd")

const ROUNDS_PER_PROFILE := 30
const BASE_SEED := 202000

var failures: int = 0
var summaries: Dictionary = {}


func _init() -> void:
	print("POC-20E: full-round adaptation stress test")
	var fixture = StrategicCourseFixture.new()
	var course = fixture.build_course()
	_assert_true(course != null, "strategic proving course builds")
	if course == null:
		_finish()
		return

	var profiles := [
		GolferScript.GolferProfile.WILD_BILL,
		GolferScript.GolferProfile.RECKLESS_RICK,
		GolferScript.GolferProfile.CAREFUL_CARL
	]
	for profile_id in profiles:
		_run_profile(course, profile_id)

	var bill: Dictionary = summaries.get("Wild Bill", {})
	var rick: Dictionary = summaries.get("Reckless Rick", {})
	var carl: Dictionary = summaries.get("Careful Carl", {})
	_assert_true(not bill.is_empty() and not rick.is_empty() and not carl.is_empty(), "all three profile summaries are available")
	if not bill.is_empty() and not rick.is_empty() and not carl.is_empty():
		_assert_true(float(bill["avg_score"]) < float(rick["avg_score"]), "Bill remains stronger overall than Rick")
		_assert_true(float(bill["avg_score"]) < float(carl["avg_score"]), "Bill remains stronger overall than Carl")
		_assert_true(int(rick["aggressive_attempts"]) > int(carl["aggressive_attempts"]), "Rick remains more aggressive than Carl")
		_assert_true(int(carl["aggressive_attempts"]) > int(bill["aggressive_attempts"]), "Carl remains more aggressive than Bill's objectively safe baseline")

	_finish()


func _run_profile(course, profile_id: int) -> void:
	var profile_name := ""
	var completed_rounds := 0
	var total_score := 0
	var front_nine_score := 0
	var back_nine_score := 0
	var front_dispersion_sum := 0.0
	var back_dispersion_sum := 0.0
	var front_dispersion_count := 0
	var back_dispersion_count := 0
	var absolute_risk_shift_sum := 0.0
	var risk_shift_count := 0
	var positive_risk_contexts := 0
	var negative_risk_contexts := 0
	var total_aggressive_attempts := 0

	for round_index in range(ROUNDS_PER_PROFILE):
		var golfer = QuietGolfer.new()
		golfer.profile = profile_id
		golfer.apply_profile()
		profile_name = golfer.golfer_name
		var baseline_risk := float(golfer.risk_tolerance)
		var round = AutonomousRound.new(course, "back")
		var seed_value := BASE_SEED + profile_id * 100000 + round_index * 137
		var result: Dictionary = round.play_round(golfer, seed_value)
		if not bool(result.get("round_finished", false)):
			failures += 1
			push_error("FAIL: %s round %d did not complete" % [profile_name, round_index + 1])
			golfer.free()
			continue

		completed_rounds += 1
		total_score += int(result.get("total_strokes", 0))
		total_aggressive_attempts += golfer.aggressive_attempts
		var scorecard: Array = result.get("scorecard", [])
		for row in scorecard:
			var hole_number := int(row.get("hole_number", 0))
			var strokes := int(row.get("strokes", 0))
			if hole_number <= 9:
				front_nine_score += strokes
			else:
				back_nine_score += strokes

		var hole_results: Array = result.get("hole_results", [])
		for hole_result in hole_results:
			var hole_number := int(hole_result.get("hole_number", 0))
			var behavior: Dictionary = hole_result.get("pre_hole_behavior_adjustment", {})
			if behavior.is_empty():
				failures += 1
				push_error("FAIL: %s hole %d missing behavior adjustment" % [profile_name, hole_number])
				continue
			var dispersion := float(behavior.get("execution_dispersion_multiplier", 1.0))
			if hole_number <= 9:
				front_dispersion_sum += dispersion
				front_dispersion_count += 1
			else:
				back_dispersion_sum += dispersion
				back_dispersion_count += 1

			var effective_risk := float(behavior.get("effective_risk_tolerance", baseline_risk))
			var risk_shift := effective_risk - baseline_risk
			absolute_risk_shift_sum += absf(risk_shift)
			risk_shift_count += 1
			if risk_shift > 0.001:
				positive_risk_contexts += 1
			elif risk_shift < -0.001:
				negative_risk_contexts += 1

		golfer.free()

	_assert_equal(completed_rounds, ROUNDS_PER_PROFILE, "%s completes all adaptation stress-test rounds" % profile_name)
	var avg_score := float(total_score) / float(maxi(1, completed_rounds))
	var avg_front := float(front_nine_score) / float(maxi(1, completed_rounds))
	var avg_back := float(back_nine_score) / float(maxi(1, completed_rounds))
	var avg_front_dispersion := front_dispersion_sum / float(maxi(1, front_dispersion_count))
	var avg_back_dispersion := back_dispersion_sum / float(maxi(1, back_dispersion_count))
	var avg_abs_risk_shift := absolute_risk_shift_sum / float(maxi(1, risk_shift_count))

	_assert_true(avg_back_dispersion > avg_front_dispersion, "%s accumulates more execution load on the back nine" % profile_name)
	_assert_true(avg_back_dispersion <= 1.15 + 0.0001, "%s late-round execution adjustment remains bounded" % profile_name)
	_assert_true(avg_abs_risk_shift >= 0.0, "%s risk adaptation remains numerically valid" % profile_name)

	summaries[profile_name] = {
		"avg_score": avg_score,
		"avg_front": avg_front,
		"avg_back": avg_back,
		"front_dispersion": avg_front_dispersion,
		"back_dispersion": avg_back_dispersion,
		"avg_abs_risk_shift": avg_abs_risk_shift,
		"positive_risk_contexts": positive_risk_contexts,
		"negative_risk_contexts": negative_risk_contexts,
		"aggressive_attempts": total_aggressive_attempts
	}

	print("POC20_PROFILE_30,%s,rounds=%d,avg=%.3f,front=%.3f,back=%.3f,front_disp=%.4f,back_disp=%.4f,avg_abs_risk_shift=%.3f,positive=%d,negative=%d,aggressive=%d" % [
		profile_name,
		completed_rounds,
		avg_score,
		avg_front,
		avg_back,
		avg_front_dispersion,
		avg_back_dispersion,
		avg_abs_risk_shift,
		positive_risk_contexts,
		negative_risk_contexts,
		total_aggressive_attempts
	])


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if failures == 0:
		print("POC-20E FULL-ROUND ADAPTATION STRESS TEST PASSED")
		quit(0)
	else:
		push_error("POC-20E FULL-ROUND ADAPTATION STRESS TEST FAILED: %d" % failures)
		quit(1)

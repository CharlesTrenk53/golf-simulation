extends SceneTree

const GolfActivity = preload("res://simulation/golf_activity.gd")
const DevelopmentOpportunity = preload("res://simulation/development_opportunity.gd")

var failures := 0

func _init() -> void:
	_test_play_and_practice_remain_separate()
	_test_practice_quality_changes_useful_opportunity_not_raw_volume()
	_test_practice_focus_routes_opportunity()
	_test_accumulation_is_additive()
	if failures == 0:
		print("POC-10 DEVELOPMENT OPPORTUNITY TESTS PASSED")
		quit(0)
	else:
		push_error("POC-10 DEVELOPMENT OPPORTUNITY TESTS FAILED: %d" % failures)
		quit(1)

func _test_play_and_practice_remain_separate() -> void:
	var activity = GolfActivity.new()
	var opportunity = DevelopmentOpportunity.new()
	var round_result := activity.record_rounds(2)
	var practice_result := activity.record_practice(100, {0: 1.0}, 0.80)
	opportunity.record_round_activity(round_result)
	opportunity.record_practice_activity(practice_result)
	var drive: Dictionary = opportunity.state_for(0)
	_expect(int(drive["on_course_repetitions"]) == 28, "two rounds create 28 contextual Driver repetitions")
	_expect(int(drive["practice_repetitions"]) == 100, "practice volume remains a separate raw Driver count")
	_expect(abs(float(drive["quality_weighted_practice"]) - 80.0) < 0.001, "practice quality creates 80 quality-weighted Driver opportunity units")
	var approach: Dictionary = opportunity.state_for(1)
	_expect(int(approach["on_course_repetitions"]) == 44, "rounds independently create contextual Approach repetitions")
	_expect(int(approach["practice_repetitions"]) == 0, "Driver-focused practice does not create Approach practice opportunity")

func _test_practice_quality_changes_useful_opportunity_not_raw_volume() -> void:
	var activity_low = GolfActivity.new()
	var activity_high = GolfActivity.new()
	var low = DevelopmentOpportunity.new()
	var high = DevelopmentOpportunity.new()
	low.record_practice_activity(activity_low.record_practice(1000, {1: 1.0}, 0.25))
	high.record_practice_activity(activity_high.record_practice(1000, {1: 1.0}, 0.90))
	var low_state: Dictionary = low.state_for(1)
	var high_state: Dictionary = high.state_for(1)
	_expect(int(low_state["practice_repetitions"]) == int(high_state["practice_repetitions"]), "equal practice volume preserves equal raw repetition counts")
	_expect(float(high_state["quality_weighted_practice"]) > float(low_state["quality_weighted_practice"]), "higher-quality practice creates more useful technical opportunity")
	_expect(abs(float(low_state["quality_weighted_practice"]) - 250.0) < 0.001, "low-quality practice records its quality-weighted opportunity")
	_expect(abs(float(high_state["quality_weighted_practice"]) - 900.0) < 0.001, "high-quality practice records its quality-weighted opportunity")

func _test_practice_focus_routes_opportunity() -> void:
	var activity = GolfActivity.new()
	var opportunity = DevelopmentOpportunity.new()
	var practice := activity.record_practice(1000, {0: 0.50, 1: 0.30, 2: 0.15, 3: 0.05}, 0.80)
	opportunity.record_practice_activity(practice)
	_expect(int(opportunity.state_for(0)["practice_repetitions"]) == 500, "practice focus routes half the repetitions to Driver")
	_expect(int(opportunity.state_for(1)["practice_repetitions"]) == 300, "practice focus routes thirty percent to Approach")
	_expect(int(opportunity.state_for(2)["practice_repetitions"]) == 150, "practice focus routes fifteen percent to Short Game")
	_expect(int(opportunity.state_for(3)["practice_repetitions"]) == 50, "practice focus routes five percent to Putting")
	_expect(abs(float(opportunity.state_for(0)["quality_weighted_practice"]) - 400.0) < 0.001, "quality weighting happens after skill-family routing")

func _test_accumulation_is_additive() -> void:
	var activity = GolfActivity.new()
	var opportunity = DevelopmentOpportunity.new()
	opportunity.record_practice_activity(activity.record_practice(200, {2: 1.0}, 0.50))
	opportunity.record_practice_activity(activity.record_practice(300, {2: 1.0}, 1.00))
	var short_game: Dictionary = opportunity.state_for(2)
	_expect(int(short_game["practice_repetitions"]) == 500, "multiple practice sessions accumulate raw repetitions")
	_expect(abs(float(short_game["quality_weighted_practice"]) - 400.0) < 0.001, "quality-weighted opportunity accumulates across sessions")
	var total: Dictionary = opportunity.state()
	_expect(int(total["total_practice_repetitions"]) == 500, "opportunity ledger reports total raw practice volume")
	_expect(abs(float(total["total_quality_weighted_practice"]) - 400.0) < 0.001, "opportunity ledger reports total quality-weighted practice")

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

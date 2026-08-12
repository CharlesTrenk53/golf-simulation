extends SceneTree

const GolfBag = preload("res://simulation/golf_bag.gd")
const ShotIntent = preload("res://simulation/shot_intent.gd")
const ShotIntentStrategyModel = preload("res://simulation/shot_intent_strategy_model.gd")

class FakeGolfer:
	extends Node
	var coordination: float = 82.0
	var confidence: float = 72.0
	func get_shot_ability(_shot_type: int) -> float:
		return 82.0

var failures: int = 0


func _init() -> void:
	print("POC-14E: autonomous shot-intent strategy")
	var bag = GolfBag.new()
	bag.use_literal_yardages(true)
	var model = ShotIntentStrategyModel.new()
	var golfer = FakeGolfer.new()
	get_root().add_child(golfer)

	# A full-distance Driver plan should remain a stock shot. There is no course
	# problem here that justifies paying extra execution cost for manufactured shape.
	var driver: Dictionary = bag.get_club("DRIVER")
	var driver_candidate := {
		"club": driver,
		"effective_carry": 220.0,
		"stock_forward_distance": 220.0,
		"intended_distance": 220.0,
		"dispersion": 9.0,
		"expected_surface": "FAIRWAY",
		"corridor_hazard_count": 0
	}
	var driver_choice: Dictionary = model.choose_for_candidate(golfer, driver_candidate, "TEE")
	_assert_true(not driver_choice.get("chosen_intent", {}).is_empty(), "driver receives an autonomous intent")
	_assert_true(str(driver_choice["chosen_intent"].get("signature", "")) == "NORMAL|STRAIGHT|FULL|STOCK", "open full-distance Driver plan prefers stock intent")

	# At twenty yards, a 60-yard lob wedge cannot rationally use its full stock
	# motion. The intent layer should discover a touch/partial technique whose
	# predicted carry fits the requested target much better.
	var lob_wedge: Dictionary = bag.get_club("LOB_WEDGE")
	var short_candidate := {
		"club": lob_wedge,
		"effective_carry": 60.0,
		"stock_forward_distance": 20.0,
		"intended_distance": 20.0,
		"dispersion": 4.5,
		"expected_surface": "GREEN",
		"corridor_hazard_count": 0
	}
	var short_choice: Dictionary = model.choose_for_candidate(golfer, short_candidate, "FAIRWAY")
	var short_intent: Dictionary = short_choice.get("chosen_intent", {})
	var short_flight: Dictionary = short_choice.get("chosen_predicted_flight", {})
	_assert_true(not short_intent.is_empty(), "short wedge plan receives an autonomous intent")
	_assert_true(int(short_intent.get("swing_length", ShotIntent.SwingLength.FULL)) != ShotIntent.SwingLength.FULL, "short wedge plan autonomously chooses less than a full swing")
	_assert_true(absf(float(short_flight.get("carry_yards", 60.0)) - 20.0) < 20.0, "chosen short-shot intent materially improves carry fit")
	_assert_true(str(short_choice.get("chosen_predicted_flight", {}).get("intent_signature", "")) == str(short_intent.get("signature", "")), "chosen predicted flight preserves chosen intent identity")
	_assert_true(str(short_choice.get("chosen_proficiency", {}).get("intent_signature", "")) == str(short_intent.get("signature", "")), "proficiency assessment preserves chosen intent identity")

	# Geometry pressure enters as corridor hazards and makes dispersion more costly;
	# the model must still return a finite ranked menu rather than a hard-coded safe
	# shot label.
	var pressured_candidate: Dictionary = driver_candidate.duplicate(true)
	pressured_candidate["corridor_hazard_count"] = 2
	var pressured: Dictionary = model.choose_for_candidate(golfer, pressured_candidate, "TEE")
	_assert_true(pressured.get("evaluated_intents", []).size() >= 5, "hazard-pressure decision ranks a real intent menu")
	_assert_true(is_finite(float(pressured.get("intent_decision_cost", INF))), "hazard-pressure choice has finite decision cost")

	golfer.queue_free()
	if failures == 0:
		print("POC-14E SHOT INTENT STRATEGY TESTS PASSED")
		quit(0)
	else:
		push_error("POC-14E SHOT INTENT STRATEGY TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

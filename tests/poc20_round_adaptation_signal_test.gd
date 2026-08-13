extends SceneTree

const RoundAdaptationModel = preload("res://simulation/round_adaptation_model.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures := 0


func _init() -> void:
	print("POC-20B: round adaptation signals")
	var model = RoundAdaptationModel.new()

	var bill = _golfer(Golfer.GolferProfile.WILD_BILL)
	var rick = _golfer(Golfer.GolferProfile.RECKLESS_RICK)
	var carl = _golfer(Golfer.GolferProfile.CAREFUL_CARL)

	var opening := _context(0.0, 0, 0.0, 18, 0)
	var late_neutral := _context(15.0 / 18.0, 3, 0.0, 3, 0)
	var late_good := _context(15.0 / 18.0, 3, -1.0, 3, -2)
	var late_bad := _context(15.0 / 18.0, 3, 1.0, 3, 4)

	var bill_open: Dictionary = model.interpret(bill, opening)
	var bill_late: Dictionary = model.interpret(bill, late_neutral)
	var rick_late: Dictionary = model.interpret(rick, late_neutral)
	var carl_late: Dictionary = model.interpret(carl, late_neutral)

	_expect_close("opening physical load is zero", float(bill_open["physical_load_exposure"]), 0.0)
	_expect_true("physical load grows with round progress", float(bill_late["physical_load_exposure"]) > float(bill_open["physical_load_exposure"]))
	_expect_true("lower endurance creates more late-round load exposure", float(carl_late["physical_load_exposure"]) > float(bill_late["physical_load_exposure"]))
	_expect_true("Rick load sits between Bill and Carl", float(rick_late["physical_load_exposure"]) > float(bill_late["physical_load_exposure"]) and float(rick_late["physical_load_exposure"]) < float(carl_late["physical_load_exposure"]))

	var carl_good: Dictionary = model.interpret(carl, late_good)
	var carl_bad: Dictionary = model.interpret(carl, late_bad)
	var rick_good: Dictionary = model.interpret(rick, late_good)
	var rick_bad: Dictionary = model.interpret(rick, late_bad)

	_expect_true("below-par recent play creates positive form signal", float(carl_good["recent_form_signal"]) > 0.0)
	_expect_true("above-par recent play creates negative form signal", float(carl_bad["recent_form_signal"]) < 0.0)
	_expect_close("neutral recent play creates neutral form signal", float(carl_late["recent_form_signal"]), 0.0)
	_expect_true("responsive Carl internalizes good form more than Rick", float(carl_good["confidence_momentum_signal"]) > float(rick_good["confidence_momentum_signal"]))
	_expect_true("responsive Carl internalizes bad form more than Rick", abs(float(carl_bad["confidence_momentum_signal"])) > abs(float(rick_bad["confidence_momentum_signal"])))
	_expect_close("form signal is symmetric for equal good/bad stretches", float(carl_good["confidence_momentum_signal"]), -float(carl_bad["confidence_momentum_signal"]))
	_expect_true("adaptation does not invent pressure output", not carl_good.has("pressure") and not carl_good.has("pressure_signal"))
	_expect_true("baseline confidence remains separate from momentum", float(carl_good["baseline_confidence"]) == float(carl_bad["baseline_confidence"]))

	print("POC20_ADAPTATION_SUMMARY bill_load=%.3f rick_load=%.3f carl_load=%.3f carl_good=%.3f carl_bad=%.3f rick_good=%.3f" % [
		float(bill_late["physical_load_exposure"]),
		float(rick_late["physical_load_exposure"]),
		float(carl_late["physical_load_exposure"]),
		float(carl_good["confidence_momentum_signal"]),
		float(carl_bad["confidence_momentum_signal"]),
		float(rick_good["confidence_momentum_signal"])
	])

	bill.free()
	rick.free()
	carl.free()

	if failures == 0:
		print("POC-20B ROUND ADAPTATION SIGNALS PASSED")
		quit(0)
	else:
		push_error("POC-20B failed with %d assertion(s)" % failures)
		quit(1)


func _golfer(profile_value: int) -> Node:
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	return golfer


func _context(progress: float, recent_count: int, recent_average: float, holes_remaining: int, score_to_par: int) -> Dictionary:
	return {
		"round_progress": progress,
		"recent_holes_count": recent_count,
		"recent_average_to_par": recent_average,
		"holes_remaining": holes_remaining,
		"score_to_par": score_to_par
	}


func _expect_true(label: String, condition: bool) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _expect_close(label: String, actual: float, expected: float, tolerance: float = 0.000001) -> void:
	if abs(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])
	else:
		failures += 1
		print("FAIL: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])

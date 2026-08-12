extends SceneTree

const Golfer = preload("res://scenes/golfer.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")
const ShotIntent = preload("res://simulation/shot_intent.gd")
const ShotFlightModel = preload("res://simulation/shot_flight_model.gd")
const ShotmakingProficiencyModel = preload("res://simulation/shotmaking_proficiency_model.gd")

var failures: int = 0


func _init() -> void:
	print("POC-14C: golfer-specific shotmaking proficiency and confidence")
	var bag = GolfBag.new()
	bag.use_literal_yardages(true)
	var flight_model = ShotFlightModel.new()
	var proficiency_model = ShotmakingProficiencyModel.new()

	var carl = _golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var rick = _golfer(Golfer.GolferProfile.RECKLESS_RICK)
	var bill = _golfer(Golfer.GolferProfile.WILD_BILL)

	var driver: Dictionary = bag.get_club("DRIVER")
	var stock: Dictionary = ShotIntent.make()
	var stock_flight: Dictionary = flight_model.predict(driver, stock, 220.0, 12.0)
	var carl_stock: Dictionary = proficiency_model.assess(carl, driver, stock, stock_flight)
	var rick_stock: Dictionary = proficiency_model.assess(rick, driver, stock, stock_flight)
	var bill_stock: Dictionary = proficiency_model.assess(bill, driver, stock, stock_flight)

	_assert_true(float(bill_stock["proficiency"]) > float(carl_stock["proficiency"]), "Wild Bill's elite driving foundation produces higher stock-driver proficiency than Carl")
	_assert_true(float(carl_stock["proficiency"]) > float(rick_stock["proficiency"]), "Carl's better coordination produces higher true stock-driver proficiency than Rick at equal driving skill")
	_assert_true(float(rick_stock["self_confidence"]) > float(carl_stock["self_confidence"]), "Rick remains more confident than Carl despite lower true proficiency")
	_assert_true(float(rick_stock["confidence_gap"]) > float(carl_stock["confidence_gap"]), "confidence and proficiency are separate enough to represent overconfidence")

	var stinger: Dictionary = ShotIntent.make(ShotIntent.Trajectory.LOW, ShotIntent.Shape.STRAIGHT, ShotIntent.SwingLength.FULL, ShotIntent.Technique.STINGER)
	var stinger_flight: Dictionary = flight_model.predict(driver, stinger, 220.0, 12.0)
	var bill_stinger: Dictionary = proficiency_model.assess(bill, driver, stinger, stinger_flight)
	_assert_true(float(bill_stinger["proficiency"]) < float(bill_stock["proficiency"]), "specialized Driver stinger is harder to execute than stock Driver")
	_assert_true(float(bill_stinger["execution_reliability"]) < float(bill_stock["execution_reliability"]), "harder intent lowers execution reliability for the same golfer")
	_assert_true(float(bill_stinger["expected_dispersion_multiplier"]) > float(bill_stock["expected_dispersion_multiplier"]), "harder intent increases execution-driven dispersion")

	var lob_wedge: Dictionary = bag.get_club("LOB_WEDGE")
	var wedge_stock: Dictionary = ShotIntent.make()
	var flop: Dictionary = ShotIntent.make(ShotIntent.Trajectory.HIGH, ShotIntent.Shape.STRAIGHT, ShotIntent.SwingLength.TOUCH, ShotIntent.Technique.FLOP)
	var wedge_stock_flight: Dictionary = flight_model.predict(lob_wedge, wedge_stock, 60.0, 6.0)
	var flop_flight: Dictionary = flight_model.predict(lob_wedge, flop, 60.0, 6.0)
	var carl_wedge_stock: Dictionary = proficiency_model.assess(carl, lob_wedge, wedge_stock, wedge_stock_flight)
	var carl_flop: Dictionary = proficiency_model.assess(carl, lob_wedge, flop, flop_flight)
	_assert_true(float(carl_flop["proficiency"]) < float(carl_wedge_stock["proficiency"]), "flop demands more execution skill than a stock wedge")
	_assert_true(float(carl_flop["theoretical_difficulty"]) > float(carl_wedge_stock["theoretical_difficulty"]), "proficiency layer consumes predicted-flight difficulty instead of redefining physics")

	_assert_true(str(carl_flop["intent_signature"]) == str(flop["signature"]), "proficiency assessment preserves the selected composable intent")

	carl.free()
	rick.free()
	bill.free()

	if failures == 0:
		print("POC-14C SHOTMAKING PROFICIENCY TESTS PASSED")
		quit(0)
	else:
		push_error("POC-14C SHOTMAKING PROFICIENCY TESTS FAILED: %d" % failures)
		quit(1)


func _golfer(profile: int) -> Node:
	var golfer = Golfer.new()
	golfer.profile = profile
	golfer.apply_profile()
	return golfer


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

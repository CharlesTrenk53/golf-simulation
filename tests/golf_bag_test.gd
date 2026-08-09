extends SceneTree

const GolfBag = preload("res://simulation/golf_bag.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

var failures := 0


func _init() -> void:
	var bag = GolfBag.new()
	var bill = QuietGolfer.new()
	bill.profile = 0
	bill.apply_profile()
	var rick = QuietGolfer.new()
	rick.profile = 1
	rick.apply_profile()

	_check(bag.all_clubs().size() == 8, "bag contains eight clubs")
	_check(not bag.get_club("DRIVER").is_empty(), "driver exists")
	_check(bag.get_club("PUTTER")["name"] == "Putter", "putter exists")
	_check(bag.clubs_for_surface("GREEN").size() == 1, "green restricts bag to putter")
	_check(bag.clubs_for_surface("BUNKER").size() >= 2, "bunker offers wedges")

	var driver = bag.get_club("DRIVER")
	var bill_driver = bag.effective_carry(driver, bill, "TEE", 1.0)
	var rick_driver = bag.effective_carry(driver, rick, "TEE", 1.0)
	_check(bill_driver > rick_driver, "better driver ability increases effective carry")
	_check(
		bag.effective_dispersion(driver, bill, "TEE", 1.0) < bag.effective_dispersion(driver, rick, "TEE", 1.0),
		"better driver ability reduces dispersion"
	)

	var seven_iron = bag.get_club("7_IRON")
	_check(
		bag.effective_carry(seven_iron, rick, "ROUGH", 0.72) < bag.effective_carry(seven_iron, rick, "FAIRWAY", 0.95),
		"rough reduces effective club carry"
	)

	var match = bag.best_distance_match(bill, "TEE", 1.0, bill_driver)
	_check(match["id"] == "DRIVER", "distance matching can select driver")

	bill.free()
	rick.free()

	if failures == 0:
		print("POC-07 CLUB TESTS PASSED")
		quit(0)
	else:
		print("POC-07 CLUB TESTS FAILED: ", failures)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)

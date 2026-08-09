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
	_check(bill_driver > rick_driver, "physical capacity and strike quality can create different driver carry")
	_check(
		bag.effective_dispersion(driver, bill, "TEE", 1.0) < bag.effective_dispersion(driver, rick, "TEE", 1.0),
		"better driver technique reduces dispersion"
	)

	# Hold technique constant and change only physical capacity. Carry should move,
	# while dispersion should remain unchanged.
	var physical_a = QuietGolfer.new()
	physical_a.profile = 1
	physical_a.apply_profile()
	var physical_b = QuietGolfer.new()
	physical_b.profile = 1
	physical_b.apply_profile()
	physical_a.driving = 70.0
	physical_b.driving = 70.0
	physical_a.physical_power = 85.0
	physical_a.mobility = 80.0
	physical_a.coordination = 70.0
	physical_b.physical_power = 45.0
	physical_b.mobility = 55.0
	physical_b.coordination = 70.0
	var strong_carry = bag.effective_carry(driver, physical_a, "TEE", 1.0)
	var limited_carry = bag.effective_carry(driver, physical_b, "TEE", 1.0)
	_check(strong_carry > limited_carry, "physical capacity changes distance at equal technical skill")
	_check(abs(bag.effective_dispersion(driver, physical_a, "TEE", 1.0) - bag.effective_dispersion(driver, physical_b, "TEE", 1.0)) < 0.001, "physical power does not rewrite technical dispersion")

	# Age is metadata for future physical evolution, not an arbitrary direct penalty.
	var age_carry_before = bag.effective_carry(driver, physical_a, "TEE", 1.0)
	physical_a.age = 65
	var age_carry_after = bag.effective_carry(driver, physical_a, "TEE", 1.0)
	_check(abs(age_carry_before - age_carry_after) < 0.001, "age affects distance only through changing physical capacity")

	var seven_iron = bag.get_club("7_IRON")
	_check(
		bag.effective_carry(seven_iron, rick, "ROUGH", 0.72) < bag.effective_carry(seven_iron, rick, "FAIRWAY", 0.95),
		"rough reduces effective club carry"
	)

	var match = bag.best_distance_match(bill, "TEE", 1.0, bill_driver)
	_check(match["id"] == "DRIVER", "distance matching can select driver")

	bill.free()
	rick.free()
	physical_a.free()
	physical_b.free()

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

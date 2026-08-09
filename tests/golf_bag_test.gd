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

	_check(bag.all_clubs().size() == 14, "default bag contains fourteen clubs")
	_check(bag.all_catalog_clubs().size() > bag.all_clubs().size(), "catalog includes alternatives beyond the active bag")
	_check(not bag.get_club("DRIVER").is_empty(), "driver exists")
	_check(not bag.get_club("4_HYBRID").is_empty(), "hybrid exists")
	_check(not bag.get_club("4_IRON").is_empty(), "long-iron alternative exists")
	_check(not bag.get_club("7_WOOD").is_empty(), "fairway-wood alternative exists")
	_check(bag.get_club("PUTTER")["name"] == "Putter", "putter exists")
	_check(bag.clubs_for_surface("GREEN").size() == 1, "green restricts bag to putter")
	_check(bag.clubs_for_surface("BUNKER").size() >= 4, "bunker offers multiple wedges")

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

	# Physical sensitivity forms a continuum down the bag. At identical approach
	# skill, a physical change should matter more to a 5-iron than a 9-iron, and
	# should not change putter distance at all.
	physical_a.approach = 70.0
	physical_b.approach = 70.0
	var five_iron = bag.get_club("5_IRON")
	var nine_iron = bag.get_club("9_IRON")
	var five_pct_gap = abs((bag.effective_carry(five_iron, physical_a, "FAIRWAY", 1.0) / bag.effective_carry(five_iron, physical_b, "FAIRWAY", 1.0)) - 1.0)
	var nine_pct_gap = abs((bag.effective_carry(nine_iron, physical_a, "FAIRWAY", 1.0) / bag.effective_carry(nine_iron, physical_b, "FAIRWAY", 1.0)) - 1.0)
	_check(five_pct_gap > nine_pct_gap, "5-iron distance is more physically sensitive than 9-iron distance")
	_check(float(bag.get_club("4_HYBRID")["forgiveness"]) > float(bag.get_club("4_IRON")["forgiveness"]), "hybrid carries more forgiveness metadata than comparable long iron")
	_check(float(bag.get_club("4_IRON")["physical_sensitivity"]) > float(bag.get_club("4_HYBRID")["physical_sensitivity"]), "long iron is more physically demanding than comparable hybrid")

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
		print("POC-08 CLUB TAXONOMY TESTS PASSED")
		quit(0)
	else:
		print("POC-08 CLUB TAXONOMY TESTS FAILED: ", failures)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)

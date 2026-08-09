extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const GolferLifecycle = preload("res://simulation/golfer_lifecycle.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")

var failures := 0

func _init() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.age = 35
	golfer.driving = 70.0
	golfer.approach = 70.0
	golfer.short_game = 70.0
	golfer.putting = 70.0
	golfer.physical_power = 75.0
	golfer.mobility = 75.0
	golfer.coordination = 75.0
	golfer.endurance = 75.0

	var lifecycle = GolferLifecycle.new()
	var bag = GolfBag.new()
	var driver: Dictionary = bag.get_club("DRIVER")
	var skill_before: float = float(golfer.driving)
	var carry_35: float = float(bag.effective_carry(driver, golfer, "TEE", 1.0))

	for _year in range(30):
		lifecycle.advance_year(golfer)
	var carry_65: float = float(bag.effective_carry(driver, golfer, "TEE", 1.0))

	_expect(golfer.age == 65, "thirty annual advances move golfer from age 35 to 65")
	_expect(abs(golfer.driving - skill_before) < 0.001, "aging does not directly erase Driver technical skill")
	_expect(carry_65 < carry_35, "age-related physical capacity change can reduce Driver carry")
	_expect(golfer.physical_power < 75.0, "physical power gradually declines across later adulthood")
	_expect(golfer.coordination > golfer.physical_power, "coordination is more age-resistant than raw power")

	var young_rates: Dictionary = lifecycle.annual_capacity_rates(22)
	var prime_rates: Dictionary = lifecycle.annual_capacity_rates(30)
	var older_rates: Dictionary = lifecycle.annual_capacity_rates(68)
	_expect(float(young_rates["power"]) > 0.0, "young golfer can still gain physical power")
	_expect(float(prime_rates["power"]) >= 0.0, "prime-age physical trajectory is not forced into decline")
	_expect(float(older_rates["power"]) < 0.0, "older golfer faces a physical power headwind")
	_expect(abs(float(older_rates["coordination"])) < abs(float(older_rates["power"])), "coordination declines more slowly than power")

	golfer.free()
	if failures == 0:
		print("POC-08 GOLFER LIFECYCLE TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 GOLFER LIFECYCLE TESTS FAILED: %d" % failures)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

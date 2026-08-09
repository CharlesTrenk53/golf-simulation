extends SceneTree

const GolferMemoryComfort = preload("res://simulation/golfer_memory_comfort.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")

var failures := 0

func _init() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 0
	golfer.apply_profile()
	var bag = GolfBag.new()
	var driver = bag.get_club("DRIVER")
	var iron = bag.get_club("7_IRON")
	var memory = GolferMemoryComfort.new()
	memory.initialize_from_golfer(golfer, bag.all_clubs())

	var driver_start = memory.comfort_for(golfer, driver, "NORMAL")
	var iron_start = memory.comfort_for(golfer, iron, "NORMAL")
	_expect(float(driver_start["comfort"]) > 50.0, "strong driver ability creates positive baseline driver comfort")
	_expect(float(driver_start["certainty"]) < 50.0, "untested club comfort begins with limited evidence certainty")

	for _i in range(5):
		memory.record_experience(driver, "NORMAL", "GOOD", "SUCCESS", 90.0)
	var driver_hot = memory.comfort_for(golfer, driver, "NORMAL")
	_expect(float(driver_hot["comfort"]) > float(driver_start["comfort"]), "repeated good driver swings raise learned comfort")
	_expect(float(driver_hot["recent"]) > float(driver_hot["long_term"]), "recent success can outweigh diluted long-term history")
	_expect(float(driver_hot["certainty"]) > float(driver_start["certainty"]), "experience increases confidence in the comfort estimate")

	var iron_after_driver = memory.comfort_for(golfer, iron, "NORMAL")
	_expect(float(iron_after_driver["comfort"]) < float(driver_hot["comfort"]), "club-specific success does not fully transfer to another club")

	var fade_before = memory.comfort_for(golfer, driver, "FADE")
	for _i in range(4):
		memory.record_experience(driver, "FADE", "POOR", "SUCCESS", 22.0)
	var fade_bad = memory.comfort_for(golfer, driver, "FADE")
	var normal_after_fades = memory.comfort_for(golfer, driver, "NORMAL")
	_expect(float(fade_bad["comfort"]) < float(fade_before["comfort"]), "poor fade execution lowers shot-form comfort")
	_expect(float(fade_bad["comfort"]) < float(normal_after_fades["comfort"]), "driver fade comfort can diverge from normal driver comfort")

	# Recency weighting: an old slump should be partially repaired by a short run
	# of excellent recent swings even though the old failures remain in history.
	for _i in range(8):
		memory.record_experience(iron, "NORMAL", "POOR", "SUCCESS", 20.0)
	var iron_slump = memory.comfort_for(golfer, iron, "NORMAL")
	for _i in range(3):
		memory.record_experience(iron, "NORMAL", "GOOD", "SUCCESS", 94.0)
	var iron_rebound = memory.comfort_for(golfer, iron, "NORMAL")
	_expect(float(iron_rebound["comfort"]) > float(iron_slump["comfort"]), "recent successes can repair confidence after an older slump")
	_expect(float(iron_rebound["recent"]) > float(iron_rebound["long_term"]), "recent rebound is weighted more heavily than older failures")

	# Outcome and execution are deliberately not identical. A well-executed shot
	# that finds water should hurt less than a genuinely poor swing into water.
	var good_water_memory = GolferMemoryComfort.new()
	good_water_memory.initialize_from_golfer(golfer, bag.all_clubs())
	good_water_memory.record_experience(driver, "NORMAL", "GOOD", "WATER", 88.0)
	var good_water = good_water_memory.comfort_for(golfer, driver, "NORMAL")
	var bad_water_memory = GolferMemoryComfort.new()
	bad_water_memory.initialize_from_golfer(golfer, bag.all_clubs())
	bad_water_memory.record_experience(driver, "NORMAL", "POOR", "WATER", 18.0)
	var bad_water = bad_water_memory.comfort_for(golfer, driver, "NORMAL")
	_expect(float(good_water["comfort"]) > float(bad_water["comfort"]), "perceived execution matters more than outcome alone")

	# Current-round state should react rapidly while long-term comfort still
	# preserves older experience.
	memory.start_new_round()
	var before_round = memory.comfort_for(golfer, driver, "NORMAL")
	for _i in range(3):
		memory.record_experience(driver, "NORMAL", "POOR", "SUCCESS", 16.0)
	var during_round = memory.comfort_for(golfer, driver, "NORMAL")
	_expect(float(during_round["current_round"]) < float(before_round["current_round"]), "current-round slump moves round momentum quickly")
	_expect(float(during_round["long_term"]) > float(during_round["current_round"]), "older positive history cushions a short current-round slump")

	golfer.free()
	if failures == 0:
		print("POC-08 GOLFER MEMORY & COMFORT TESTS PASSED")
		quit(0)
	else:
		push_error("POC-08 GOLFER MEMORY & COMFORT TESTS FAILED: %d" % failures)
		quit(1)

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

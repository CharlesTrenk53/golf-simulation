extends SceneTree

const GolfBag = preload("res://simulation/golf_bag.gd")
const ShotIntent = preload("res://simulation/shot_intent.gd")
const ShotFlightModel = preload("res://simulation/shot_flight_model.gd")

var failures: int = 0


func _init() -> void:
	print("POC-14B: shot intent predicted flight")
	var bag = GolfBag.new()
	bag.use_literal_yardages(true)
	var model = ShotFlightModel.new()
	var driver: Dictionary = bag.get_club("DRIVER")
	var seven_iron: Dictionary = bag.get_club("7_IRON")
	var lob_wedge: Dictionary = bag.get_club("LOB_WEDGE")

	var driver_carry: float = bag.baseline_distance(driver)
	var driver_dispersion: float = float(driver.get("dispersion", 9.0))
	var stock = model.predict(driver, ShotIntent.make(), driver_carry, driver_dispersion)
	var draw = model.predict(driver, ShotIntent.make(ShotIntent.Trajectory.NORMAL, ShotIntent.Shape.DRAW), driver_carry, driver_dispersion)
	var fade = model.predict(driver, ShotIntent.make(ShotIntent.Trajectory.NORMAL, ShotIntent.Shape.FADE), driver_carry, driver_dispersion)
	var low = model.predict(driver, ShotIntent.make(ShotIntent.Trajectory.LOW), driver_carry, driver_dispersion)
	var high = model.predict(driver, ShotIntent.make(ShotIntent.Trajectory.HIGH), driver_carry, driver_dispersion)
	var stinger = model.predict(driver, ShotIntent.make(ShotIntent.Trajectory.LOW, ShotIntent.Shape.STRAIGHT, ShotIntent.SwingLength.FULL, ShotIntent.Technique.STINGER), driver_carry, driver_dispersion)

	_assert_close(stock["carry_yards"], 220.0, 0.01, "stock driver preserves baseline carry")
	_assert_true(draw["curve_yards"] < 0.0, "driver draw curves left in signed planning coordinates")
	_assert_true(fade["curve_yards"] > 0.0, "driver fade curves right in signed planning coordinates")
	_assert_true(draw["carry_yards"] > fade["carry_yards"], "driver draw carries slightly farther than fade")
	_assert_true(draw["rollout_yards"] > fade["rollout_yards"], "driver draw rolls farther than fade")
	_assert_true(low["apex_factor"] < stock["apex_factor"], "low trajectory lowers apex")
	_assert_true(low["rollout_yards"] > stock["rollout_yards"], "low trajectory increases rollout")
	_assert_true(high["apex_factor"] > stock["apex_factor"], "high trajectory raises apex")
	_assert_true(high["rollout_yards"] < stock["rollout_yards"], "high trajectory reduces rollout")
	_assert_true(stinger["carry_yards"] < low["carry_yards"], "stinger gives up carry versus generic low stock shot")
	_assert_true(stinger["rollout_yards"] > low["rollout_yards"], "stinger produces extra rollout")
	_assert_true(stinger["execution_difficulty"] > stock["execution_difficulty"], "stinger is harder than stock driver")

	var iron_carry: float = bag.baseline_distance(seven_iron)
	var iron_dispersion: float = float(seven_iron.get("dispersion", 4.5))
	var iron_stock = model.predict(seven_iron, ShotIntent.make(), iron_carry, iron_dispersion)
	var iron_punch = model.predict(seven_iron, ShotIntent.make(ShotIntent.Trajectory.LOW, ShotIntent.Shape.STRAIGHT, ShotIntent.SwingLength.THREE_QUARTER, ShotIntent.Technique.PUNCH), iron_carry, iron_dispersion)
	_assert_true(iron_punch["carry_yards"] < iron_stock["carry_yards"], "7 iron punch carries shorter than stock")
	_assert_true(iron_punch["apex_factor"] < iron_stock["apex_factor"], "7 iron punch flies materially lower")
	_assert_true(iron_punch["dispersion_yards"] < iron_stock["dispersion_yards"], "controlled punch narrows planned dispersion")

	var wedge_carry: float = bag.baseline_distance(lob_wedge)
	var wedge_dispersion: float = float(lob_wedge.get("dispersion", 4.5))
	var half_pitch = model.predict(lob_wedge, ShotIntent.make(ShotIntent.Trajectory.NORMAL, ShotIntent.Shape.STRAIGHT, ShotIntent.SwingLength.HALF, ShotIntent.Technique.PITCH), wedge_carry, wedge_dispersion)
	var flop = model.predict(lob_wedge, ShotIntent.make(ShotIntent.Trajectory.HIGH, ShotIntent.Shape.STRAIGHT, ShotIntent.SwingLength.TOUCH, ShotIntent.Technique.FLOP), wedge_carry, wedge_dispersion)
	var bump = model.predict(lob_wedge, ShotIntent.make(ShotIntent.Trajectory.LOW, ShotIntent.Shape.STRAIGHT, ShotIntent.SwingLength.TOUCH, ShotIntent.Technique.BUMP_AND_RUN), wedge_carry, wedge_dispersion)
	_assert_true(half_pitch["carry_yards"] < wedge_carry, "half pitch creates partial-wedge distance")
	_assert_true(flop["apex_factor"] > half_pitch["apex_factor"], "flop is substantially higher than pitch")
	_assert_true(flop["rollout_yards"] < half_pitch["rollout_yards"], "flop minimizes rollout")
	_assert_true(flop["execution_difficulty"] > half_pitch["execution_difficulty"], "flop is materially harder than pitch")
	_assert_true(bump["apex_factor"] < half_pitch["apex_factor"], "bump-and-run stays lower than pitch")
	_assert_true(bump["rollout_factor"] > half_pitch["rollout_factor"], "bump-and-run emphasizes rollout")

	_assert_true(stock.has("carry_yards") and stock.has("total_yards") and stock.has("curve_yards") and stock.has("dispersion_yards"), "prediction exposes planning flight outputs")

	if failures == 0:
		print("POC-14B SHOT FLIGHT MODEL TESTS PASSED")
		quit(0)
	else:
		push_error("POC-14B SHOT FLIGHT MODEL TESTS FAILED: %d" % failures)
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	_assert_true(abs(actual - expected) <= tolerance, "%s (actual %.3f expected %.3f)" % [label, actual, expected])

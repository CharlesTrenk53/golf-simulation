extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const GolferLifecycle = preload("res://simulation/golfer_lifecycle.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")

const START_AGE := 16
const END_AGE := 76
const CHECKPOINT_AGES := [16, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 76]
const STARTING_CAPACITIES := [50.0, 70.0, 90.0]
const DRIVER_SKILL := 70.0

func _init() -> void:
	print("AGECALCSV,start_capacity,age,driver_skill,power,mobility,coordination,endurance,physical_factor,driver_carry,carry_change_from_16,pct_carry_change_from_16")
	for starting_capacity in STARTING_CAPACITIES:
		_run_trajectory(float(starting_capacity))
	print("POC-08 AGE CALIBRATION DIAGNOSTIC COMPLETE")
	quit(0)

func _run_trajectory(starting_capacity: float) -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.age = START_AGE
	golfer.driving = DRIVER_SKILL
	golfer.approach = DRIVER_SKILL
	golfer.short_game = DRIVER_SKILL
	golfer.putting = DRIVER_SKILL
	golfer.physical_power = starting_capacity
	golfer.mobility = starting_capacity
	golfer.coordination = starting_capacity
	golfer.endurance = starting_capacity

	var lifecycle = GolferLifecycle.new()
	var bag = GolfBag.new()
	var driver: Dictionary = bag.get_club("DRIVER")
	var carry_at_16: float = bag.effective_carry(driver, golfer, "TEE", 1.0)
	var peak_carry: float = carry_at_16
	var peak_age: int = START_AGE

	_record_if_checkpoint(golfer, bag, driver, starting_capacity, carry_at_16)
	while golfer.age < END_AGE:
		lifecycle.advance_year(golfer)
		var current_carry: float = bag.effective_carry(driver, golfer, "TEE", 1.0)
		if current_carry > peak_carry:
			peak_carry = current_carry
			peak_age = int(golfer.age)
		_record_if_checkpoint(golfer, bag, driver, starting_capacity, carry_at_16)

	var carry_at_76: float = bag.effective_carry(driver, golfer, "TEE", 1.0)
	print("AGECALSUMMARY,start_capacity=%.1f,peak_age=%d,peak_carry=%.6f,carry_age_16=%.6f,carry_age_76=%.6f,pct_change_16_to_76=%.6f" % [
		starting_capacity,
		peak_age,
		peak_carry,
		carry_at_16,
		carry_at_76,
		((carry_at_76 - carry_at_16) / carry_at_16) * 100.0
	])
	golfer.free()

func _record_if_checkpoint(golfer: Node, bag, driver: Dictionary, starting_capacity: float, carry_at_16: float) -> void:
	if not CHECKPOINT_AGES.has(int(golfer.age)):
		return
	var physical_factor: float = golfer.physical_distance_factor(0)
	var carry: float = bag.effective_carry(driver, golfer, "TEE", 1.0)
	var carry_change: float = carry - carry_at_16
	var pct_change: float = (carry_change / carry_at_16) * 100.0
	print("AGECALCSV,%.1f,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
		starting_capacity,
		int(golfer.age),
		float(golfer.driving),
		float(golfer.physical_power),
		float(golfer.mobility),
		float(golfer.coordination),
		float(golfer.endurance),
		physical_factor,
		carry,
		carry_change,
		pct_change
	])

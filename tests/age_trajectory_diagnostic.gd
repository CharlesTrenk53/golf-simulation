extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const GolferLifecycle = preload("res://simulation/golfer_lifecycle.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")

const START_AGE := 16
const END_AGE := 76

func _init() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 2
	golfer.apply_profile()
	golfer.age = START_AGE
	golfer.driving = 70.0
	golfer.approach = 70.0
	golfer.short_game = 70.0
	golfer.putting = 70.0
	golfer.physical_power = 70.0
	golfer.mobility = 70.0
	golfer.coordination = 70.0
	golfer.endurance = 70.0

	var lifecycle = GolferLifecycle.new()
	var bag = GolfBag.new()
	var driver: Dictionary = bag.get_club("DRIVER")

	print("AGECSV,age,driving_skill,power,mobility,coordination,endurance,driver_physical_factor,driver_carry")
	_record(golfer, bag, driver)
	while golfer.age < END_AGE:
		lifecycle.advance_year(golfer)
		_record(golfer, bag, driver)

	print("POC-08 AGE TRAJECTORY DIAGNOSTIC COMPLETE")
	golfer.free()
	quit(0)

func _record(golfer: Node, bag, driver: Dictionary) -> void:
	var physical_factor: float = golfer.physical_distance_factor(0)
	var carry: float = bag.effective_carry(driver, golfer, "TEE", 1.0)
	print("AGECSV,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f" % [
		int(golfer.age),
		float(golfer.driving),
		float(golfer.physical_power),
		float(golfer.mobility),
		float(golfer.coordination),
		float(golfer.endurance),
		physical_factor,
		carry
	])

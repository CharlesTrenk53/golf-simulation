extends Node

const GolfBag = preload("res://simulation/golf_bag.gd")

var bag = GolfBag.new()

enum ShotType {
	DRIVE,
	APPROACH,
	SHORT_GAME,
	PUTT
}

func simulate_shot(
	golfer: Node,
	shot_type: ShotType,
	target_position: Vector3,
	max_lateral_error: float,
	max_distance_error: float,
	required_carry: float = 0.0,
	water_position: Vector3 = Vector3.ZERO
) -> Vector3:
	var club = _club_for_shot_type(shot_type)
	var ability = golfer.get_shot_ability(shot_type)
	var is_aggressive = shot_type == ShotType.DRIVE and required_carry > 0.0

	if is_aggressive:
		var carry_result = calculate_carry_result(golfer, required_carry)
		if not carry_result["success"]:
			var water_destination = create_water_destination(water_position, max_lateral_error)
			print("--------------------")
			print("SHOT RESULT: WATER")
			print("Water destination: ", water_destination)
			golfer.record_shot_result("WATER", true)
			return water_destination

	var model_dispersion = bag.effective_dispersion(club, golfer, "FAIRWAY", 1.0) if not club.is_empty() else max_lateral_error
	var lateral_error_range = min(max_lateral_error, model_dispersion)
	var distance_error_range = min(max_distance_error, model_dispersion * 0.7)
	var x_error = randf_range(-lateral_error_range, lateral_error_range)
	var z_error = randf_range(-distance_error_range, distance_error_range)
	var shot_destination = target_position + Vector3(x_error, 0.0, z_error)

	print("--------------------")
	print("SHOT RESULT: SUCCESS")
	print("Golfer: ", golfer.golfer_name)
	print("Shot type: ", ShotType.keys()[shot_type])
	print("Ability used: ", ability)
	print("Physical distance factor: ", golfer.physical_distance_factor(shot_type) if golfer.has_method("physical_distance_factor") else 1.0)
	print("Model dispersion: ", model_dispersion)
	print("Lateral error: ", x_error)
	print("Distance error: ", z_error)
	print("Shot destination: ", shot_destination)
	golfer.record_shot_result("SUCCESS", is_aggressive)
	return shot_destination

func calculate_carry_success_chance(golfer: Node, required_carry: float) -> float:
	var driver = bag.get_club("DRIVER")
	var effective_carry = bag.effective_carry(driver, golfer, "TEE", 1.0)
	var dispersion = bag.effective_dispersion(driver, golfer, "TEE", 1.0)
	var carry_margin = effective_carry - required_carry
	var uncertainty = max(dispersion, 1.0)
	return clamp(50.0 + (carry_margin / uncertainty) * 18.0, 5.0, 95.0)

func calculate_carry_result(golfer: Node, required_carry: float) -> Dictionary:
	var driver = bag.get_club("DRIVER")
	var effective_carry = bag.effective_carry(driver, golfer, "TEE", 1.0)
	var carry_margin = effective_carry - required_carry
	var success_chance = calculate_carry_success_chance(golfer, required_carry)
	var roll = randf_range(0.0, 100.0)
	var success = roll <= success_chance

	print("------ SHOT EXECUTION ------")
	print("Required carry: ", required_carry)
	print("Effective Driver carry: ", effective_carry)
	print("Physical distance factor: ", golfer.physical_distance_factor(ShotType.DRIVE) if golfer.has_method("physical_distance_factor") else 1.0)
	print("Carry margin: ", carry_margin)
	print("Driving technique: ", golfer.get_shot_ability(ShotType.DRIVE))
	print("Success chance: ", success_chance)
	print("Execution roll: ", roll)
	print("Carry outcome: ", "CLEARED" if success else "WATER")
	return {"success": success, "success_chance": success_chance, "roll": roll, "effective_carry": effective_carry}

func create_water_destination(water_position: Vector3, max_lateral_error: float) -> Vector3:
	var water_x = randf_range(-max_lateral_error * 0.5, max_lateral_error * 0.5)
	var water_z = randf_range(-3.0, 3.0)
	return water_position + Vector3(water_x, 0.3, water_z)

func get_shot_ability(golfer: Node, shot_type: ShotType) -> float:
	return golfer.get_shot_ability(shot_type)

func _club_for_shot_type(shot_type: int) -> Dictionary:
	match shot_type:
		ShotType.DRIVE:
			return bag.get_club("DRIVER")
		ShotType.APPROACH:
			return bag.get_club("7_IRON")
		ShotType.SHORT_GAME:
			return bag.get_club("PITCHING_WEDGE")
		ShotType.PUTT:
			return bag.get_club("PUTTER")
	return {}

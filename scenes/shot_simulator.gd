extends Node

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

	var ability = get_shot_ability(golfer, shot_type)

	# Only aggressive DRIVE shots test whether the golfer
	# successfully clears the water.
	if shot_type == ShotType.DRIVE and required_carry > 0.0:
		var carry_result = calculate_carry_result(
			golfer,
			required_carry
		)

		if not carry_result["success"]:
			var water_destination = create_water_destination(
				water_position,
				max_lateral_error
			)

			print("--------------------")
			print("SHOT RESULT: WATER")
			print("Water destination: ", water_destination)

			golfer.record_shot_result("WATER")

			return water_destination

	# If the golfer clears the hazard, or the shot is not
	# an aggressive drive, calculate the normal shot result.
	var accuracy_factor = 1.0 - (ability / 100.0)

	var lateral_error_range = max_lateral_error * accuracy_factor
	var distance_error_range = max_distance_error * accuracy_factor

	var x_error = randf_range(
		-lateral_error_range,
		lateral_error_range
	)

	var z_error = randf_range(
		-distance_error_range,
		distance_error_range
	)

	var shot_destination = target_position + Vector3(
		x_error,
		0.0,
		z_error
	)

	print("--------------------")
	print("SHOT RESULT: SUCCESS")
	print("Golfer: ", golfer.golfer_name)
	print("Shot type: ", ShotType.keys()[shot_type])
	print("Ability used: ", ability)
	print("Lateral error: ", x_error)
	print("Distance error: ", z_error)
	print("Shot destination: ", shot_destination)

	golfer.record_shot_result("SUCCESS")

	return shot_destination


func calculate_carry_result(
	golfer: Node,
	required_carry: float
) -> Dictionary:

	var carry_margin = golfer.driving_distance - required_carry

	# 50% success when normal driving distance exactly
	# equals the required carry.
	var success_chance = 50.0 + (carry_margin * 5.0)

	# Driving ability modifies execution quality.
	var ability_adjustment = (golfer.driving - 50.0) * 0.3
	success_chance += ability_adjustment

	success_chance = clamp(
		success_chance,
		5.0,
		95.0
	)

	var roll = randf_range(0.0, 100.0)
	var success = roll <= success_chance

	print("------ SHOT EXECUTION ------")
	print("Required carry: ", required_carry)
	print("Golfer distance: ", golfer.driving_distance)
	print("Carry margin: ", carry_margin)
	print("Driving ability: ", golfer.driving)
	print("Success chance: ", success_chance)
	print("Execution roll: ", roll)

	if success:
		print("Carry outcome: CLEARED")
	else:
		print("Carry outcome: WATER")

	return {
		"success": success,
		"success_chance": success_chance,
		"roll": roll
	}


func create_water_destination(
	water_position: Vector3,
	max_lateral_error: float
) -> Vector3:

	var water_x = randf_range(
		-max_lateral_error * 0.5,
		max_lateral_error * 0.5
	)

	var water_z = randf_range(-3.0, 3.0)

	return water_position + Vector3(
		water_x,
		0.3,
		water_z
	)


func get_shot_ability(
	golfer: Node,
	shot_type: ShotType
) -> float:

	match shot_type:
		ShotType.DRIVE:
			return golfer.driving

		ShotType.APPROACH:
			return golfer.approach

		ShotType.SHORT_GAME:
			return golfer.short_game

		ShotType.PUTT:
			return golfer.putting

	return golfer.approach

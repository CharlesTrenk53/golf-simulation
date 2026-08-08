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
	max_distance_error: float
) -> Vector3:

	var ability = get_shot_ability(golfer, shot_type)

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
	print("Golfer: ", golfer.golfer_name)
	print("Shot type: ", ShotType.keys()[shot_type])
	print("Ability used: ", ability)
	print("Lateral error: ", x_error)
	print("Distance error: ", z_error)
	print("Shot destination: ", shot_destination)

	return shot_destination


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

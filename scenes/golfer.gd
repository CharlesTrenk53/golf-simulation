extends Node

enum ShotType {
	DRIVE,
	APPROACH,
	SHORT_GAME,
	PUTT
}

@export var golfer_name: String = "Test Golfer"

@export_range(0.0, 100.0, 1.0) var driving: float = 70.0
@export_range(0.0, 100.0, 1.0) var approach: float = 70.0
@export_range(0.0, 100.0, 1.0) var short_game: float = 70.0
@export_range(0.0, 100.0, 1.0) var putting: float = 70.0


func choose_shot(distance_to_target: float) -> ShotType:
	if distance_to_target > 40.0:
		return ShotType.DRIVE

	if distance_to_target > 15.0:
		return ShotType.APPROACH

	if distance_to_target > 5.0:
		return ShotType.SHORT_GAME

	return ShotType.PUTT

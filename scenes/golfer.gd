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
@export_range(0.0, 100.0, 1.0) var risk_tolerance: float = 50.0

func choose_shot(distance_to_target: float) -> ShotType:
	if distance_to_target > 40.0:
		return choose_long_shot()

	if distance_to_target > 15.0:
		return ShotType.APPROACH

	if distance_to_target > 5.0:
		return ShotType.SHORT_GAME

	return ShotType.PUTT


func choose_long_shot() -> ShotType:
	var safe_reward: float = 50.0
	var safe_risk: float = 20.0

	var aggressive_reward: float = 80.0
	var aggressive_base_risk: float = 80.0

	# Better driving ability reduces the perceived risk
	# of taking the aggressive option.
	var ability_factor = driving / 100.0
	var ability_adjusted_aggressive_risk = (
		aggressive_base_risk * (1.0 - (ability_factor * 0.6))
	)

	# High risk tolerance reduces how heavily the golfer
	# penalizes risky options.
	var risk_weight = 1.0 - (risk_tolerance / 100.0)

	var safe_utility = safe_reward - (
		safe_risk * risk_weight
	)

	var aggressive_utility = aggressive_reward - (
		ability_adjusted_aggressive_risk * risk_weight
	)

	print("------ DECISION ANALYSIS ------")
	print("Golfer: ", golfer_name)
	print("Driving ability: ", driving)
	print("Risk tolerance: ", risk_tolerance)
	print("Safe risk: ", safe_risk)
	print(
		"Aggressive ability-adjusted risk: ",
		ability_adjusted_aggressive_risk
	)
	print("Safe utility: ", safe_utility)
	print("Aggressive utility: ", aggressive_utility)

	if aggressive_utility > safe_utility:
		print("Decision preference: AGGRESSIVE")
		return ShotType.DRIVE

	print("Decision preference: SAFE")
	return ShotType.APPROACH

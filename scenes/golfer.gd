extends Node

enum GolferProfile {
	WILD_BILL,
	RECKLESS_RICK,
	CAREFUL_CARL
}

enum ShotType {
	DRIVE,
	APPROACH,
	SHORT_GAME,
	PUTT
}

@export var profile: GolferProfile = GolferProfile.WILD_BILL

var golfer_name: String
var driving: float
var driving_distance: float
var approach: float
var short_game: float
var putting: float
var risk_tolerance: float


func _ready() -> void:
	apply_profile()

	print("=== ACTIVE GOLFER ===")
	print("Profile: ", GolferProfile.keys()[profile])
	print("Name: ", golfer_name)
	print("Driving: ", driving)
	print("Driving distance: ", driving_distance)
	print("Approach: ", approach)
	print("Short game: ", short_game)
	print("Putting: ", putting)
	print("Risk tolerance: ", risk_tolerance)


func apply_profile() -> void:
	match profile:
		GolferProfile.WILD_BILL:
			golfer_name = "Wild Bill"
			driving = 95.0
			driving_distance = 70.0
			approach = 70.0
			short_game = 70.0
			putting = 70.0
			risk_tolerance = 90.0

		GolferProfile.RECKLESS_RICK:
			golfer_name = "Reckless Rick"
			driving = 30.0
			driving_distance = 48.0
			approach = 70.0
			short_game = 70.0
			putting = 70.0
			risk_tolerance = 90.0

		GolferProfile.CAREFUL_CARL:
			golfer_name = "Careful Carl"
			driving = 30.0
			driving_distance = 48.0
			approach = 70.0
			short_game = 70.0
			putting = 70.0
			risk_tolerance = 10.0


func choose_shot(
	distance_to_target: float,
	hazard_risk: float
) -> ShotType:
	if distance_to_target > 40.0:
		return choose_long_shot(hazard_risk)

	if distance_to_target > 15.0:
		return ShotType.APPROACH

	if distance_to_target > 5.0:
		return ShotType.SHORT_GAME

	return ShotType.PUTT


func choose_long_shot(hazard_risk: float) -> ShotType:
	var safe_reward: float = 50.0
	var safe_risk: float = 20.0
	var aggressive_reward: float = 65.0

	var ability_factor = driving / 100.0

	var ability_adjusted_aggressive_risk = (
		hazard_risk * (1.0 - (ability_factor * 0.6))
	)

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
	print("Driving distance: ", driving_distance)
	print("Risk tolerance: ", risk_tolerance)
	print("Hazard risk: ", hazard_risk)
	print("Safe utility: ", safe_utility)
	print("Aggressive utility: ", aggressive_utility)

	if aggressive_utility > safe_utility:
		print("Decision preference: AGGRESSIVE")
		return ShotType.DRIVE

	print("Decision preference: SAFE")
	return ShotType.APPROACH

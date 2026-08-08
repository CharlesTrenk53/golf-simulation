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

# How strongly personal outcomes influence future choices.
# 0 = almost ignores experience
# 100 = highly responsive to experience
var responsiveness_to_experience: float

# General outcome memory
var shots_attempted: int = 0
var successful_shots: int = 0
var water_balls: int = 0

# Memory specifically for aggressive carry attempts
var aggressive_attempts: int = 0
var aggressive_successes: int = 0
var aggressive_failures: int = 0


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
	print(
		"Responsiveness to experience: ",
		responsiveness_to_experience
	)


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
			responsiveness_to_experience = 50.0

		GolferProfile.RECKLESS_RICK:
			golfer_name = "Reckless Rick"
			driving = 30.0
			driving_distance = 48.0
			approach = 70.0
			short_game = 70.0
			putting = 70.0
			risk_tolerance = 90.0
			responsiveness_to_experience = 15.0

		GolferProfile.CAREFUL_CARL:
			golfer_name = "Careful Carl"
			driving = 30.0
			driving_distance = 48.0
			approach = 70.0
			short_game = 70.0
			putting = 70.0
			risk_tolerance = 10.0
			responsiveness_to_experience = 85.0


func choose_shot(
	distance_to_target: float,
	hazard_risk: float,
	model_success_chance: float
) -> ShotType:

	if distance_to_target > 40.0:
		return choose_long_shot(
			hazard_risk,
			model_success_chance
		)

	if distance_to_target > 15.0:
		return ShotType.APPROACH

	if distance_to_target > 5.0:
		return ShotType.SHORT_GAME

	return ShotType.PUTT


func choose_long_shot(
	hazard_risk: float,
	model_success_chance: float
) -> ShotType:

	var safe_reward: float = 50.0
	var safe_risk: float = 20.0
	var aggressive_reward: float = 65.0

	var believed_success_chance = get_believed_aggressive_success(
		model_success_chance
	)

	var ability_factor = driving / 100.0

	var ability_adjusted_aggressive_risk = (
		hazard_risk
		* (1.0 - (ability_factor * 0.6))
	)

	var experience_adjusted_aggressive_reward = aggressive_reward

	# Experience only begins to influence the choice after
	# several attempts.
	if aggressive_attempts >= 3:
		var experience_factor = (
			responsiveness_to_experience / 100.0
		)

		# Lower believed success makes the aggressive option
		# less attractive. The effect depends on how strongly
		# this golfer responds to experience.
		var failure_belief = (
			1.0
			- (believed_success_chance / 100.0)
		)

		# The effect increases gradually as the golfer builds
		# a larger personal sample of aggressive attempts.
		var learning_maturity = clamp(
			float(aggressive_attempts - 2) / 18.0,
			0.0,
			1.0
		)

		var experience_penalty = (
			failure_belief
			* experience_factor
			* learning_maturity
			* 30.0
		)

		experience_adjusted_aggressive_reward -= experience_penalty

	var risk_weight = 1.0 - (risk_tolerance / 100.0)

	var safe_utility = safe_reward - (
		safe_risk * risk_weight
	)

	var aggressive_utility = (
		experience_adjusted_aggressive_reward
		- (
			ability_adjusted_aggressive_risk
			* risk_weight
		)
	)

	print("------ DECISION ANALYSIS ------")
	print("Golfer: ", golfer_name)
	print("Driving ability: ", driving)
	print("Driving distance: ", driving_distance)
	print("Risk tolerance: ", risk_tolerance)
	print(
		"Responsiveness to experience: ",
		responsiveness_to_experience
	)
	print("Hazard risk: ", hazard_risk)
	print("Model success chance: ", model_success_chance)
	print(
		"Believed aggressive success chance: ",
		believed_success_chance
	)
	print(
		"Experience-adjusted aggressive reward: ",
		experience_adjusted_aggressive_reward
	)
	print("Safe utility: ", safe_utility)
	print("Aggressive utility: ", aggressive_utility)

	if aggressive_utility > safe_utility:
		print("Decision preference: AGGRESSIVE")
		return ShotType.DRIVE

	print("Decision preference: SAFE")
	return ShotType.APPROACH


func get_believed_aggressive_success(
	model_success_chance: float
) -> float:

	if aggressive_attempts == 0:
		return model_success_chance

	var observed_success_rate = (
		float(aggressive_successes)
		/ float(aggressive_attempts)
	) * 100.0

	var experience_weight = clamp(
		float(aggressive_attempts) / 20.0,
		0.0,
		0.75
	)

	var model_weight = 1.0 - experience_weight

	var believed_success = (
		model_success_chance * model_weight
		+ observed_success_rate * experience_weight
	)

	print("------ EXPERIENCE BELIEF ------")
	print("Aggressive attempts: ", aggressive_attempts)
	print("Aggressive successes: ", aggressive_successes)
	print("Aggressive failures: ", aggressive_failures)
	print("Observed success rate: ", observed_success_rate)
	print("Experience weight: ", experience_weight)
	print("Model weight: ", model_weight)
	print("Believed success chance: ", believed_success)

	return believed_success


func record_shot_result(
	result: String,
	was_aggressive: bool = false
) -> void:

	shots_attempted += 1

	match result:
		"SUCCESS":
			successful_shots += 1

		"WATER":
			water_balls += 1

	if was_aggressive:
		aggressive_attempts += 1

		if result == "SUCCESS":
			aggressive_successes += 1

		elif result == "WATER":
			aggressive_failures += 1

	print("------ GOLFER MEMORY ------")
	print("Golfer: ", golfer_name)
	print("Shots attempted: ", shots_attempted)
	print("Successful shots: ", successful_shots)
	print("Water balls: ", water_balls)

	if shots_attempted > 0:
		var success_rate = (
			float(successful_shots)
			/ float(shots_attempted)
		) * 100.0

		print("Overall success rate: ", success_rate, "%")

	print("Aggressive attempts: ", aggressive_attempts)
	print("Aggressive successes: ", aggressive_successes)
	print("Aggressive failures: ", aggressive_failures)

	if aggressive_attempts > 0:
		var aggressive_success_rate = (
			float(aggressive_successes)
			/ float(aggressive_attempts)
		) * 100.0

		print(
			"Aggressive success rate: ",
			aggressive_success_rate,
			"%"
		)

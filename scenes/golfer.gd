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
var responsiveness_to_experience: float

# General outcome memory
var shots_attempted: int = 0
var successful_shots: int = 0
var water_balls: int = 0

# Memory specifically for aggressive attempts
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


func choose_best_option(
	options: Array
) -> Dictionary:

	var best_option: Dictionary = {}
	var best_utility: float = -999999.0

	print("====== SHOT OPTION EVALUATION ======")

	for option in options:
		var evaluation = evaluate_option(option)
		var utility: float = evaluation["utility"]

		print("Option: ", option["name"])
		print("Reward: ", option["reward"])
		print("Risk: ", option["risk"])
		print("Relevant ability: ", evaluation["ability"])
		print("Ability bonus: ", evaluation["ability_bonus"])

		if option["is_aggressive"]:
			print(
				"Model success chance: ",
				option["model_success_chance"]
			)
			print(
				"Believed success chance: ",
				evaluation["believed_success_chance"]
			)
			print(
				"Experience penalty: ",
				evaluation["experience_penalty"]
			)

		print("Utility: ", utility)
		print("--------------------")

		if utility > best_utility:
			best_utility = utility
			best_option = option

	print("SELECTED OPTION: ", best_option["name"])
	print("SELECTED UTILITY: ", best_utility)

	return best_option


func evaluate_option(
	option: Dictionary
) -> Dictionary:

	var reward: float = option["reward"]
	var risk: float = option["risk"]
	var shot_type: int = option["shot_type"]

	var ability = get_shot_ability(shot_type)

	# Better skill with the required shot makes an option
	# somewhat more attractive.
	var ability_bonus = ability * 0.10

	# High risk tolerance reduces the golfer's perceived
	# cost of risky options.
	var risk_weight = (
		1.0
		- (risk_tolerance / 100.0)
	)

	var risk_penalty = (
		risk * risk_weight
	)

	var experience_penalty: float = 0.0
	var believed_success_chance: float = 100.0

	if option["is_aggressive"]:
		var model_success_chance: float = (
			option["model_success_chance"]
		)

		believed_success_chance = (
			get_believed_aggressive_success(
				model_success_chance
			)
		)

		# The golfer must actually build some experience
		# before personal history begins affecting utility.
		if aggressive_attempts >= 3:
			var experience_factor = (
				responsiveness_to_experience / 100.0
			)

			var failure_belief = (
				1.0
				- (
					believed_success_chance
					/ 100.0
				)
			)

			var learning_maturity = clamp(
				float(aggressive_attempts - 2)
				/ 18.0,
				0.0,
				1.0
			)

			experience_penalty = (
				failure_belief
				* experience_factor
				* learning_maturity
				* 30.0
			)

	var utility = (
		reward
		+ ability_bonus
		- risk_penalty
		- experience_penalty
	)

	return {
		"utility": utility,
		"ability": ability,
		"ability_bonus": ability_bonus,
		"risk_penalty": risk_penalty,
		"experience_penalty": experience_penalty,
		"believed_success_chance": believed_success_chance
	}


func get_shot_ability(
	shot_type: int
) -> float:

	match shot_type:
		ShotType.DRIVE:
			return driving

		ShotType.APPROACH:
			return approach

		ShotType.SHORT_GAME:
			return short_game

		ShotType.PUTT:
			return putting

	return approach


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

	var model_weight = (
		1.0 - experience_weight
	)

	var believed_success = (
		model_success_chance * model_weight
		+ observed_success_rate * experience_weight
	)

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

		print(
			"Overall success rate: ",
			success_rate,
			"%"
		)

	print(
		"Aggressive attempts: ",
		aggressive_attempts
	)
	print(
		"Aggressive successes: ",
		aggressive_successes
	)
	print(
		"Aggressive failures: ",
		aggressive_failures
	)

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

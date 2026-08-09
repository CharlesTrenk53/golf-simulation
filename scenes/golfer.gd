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
var confidence: float

# Long-horizon golfer development. Experience is stored separately from current
# skill so a well-established motor pattern is harder to permanently move.
var career_shot_experience: Dictionary = {}

# Physical capacity is intentionally separate from technical golf skill. Age is
# recorded now for future aging logic; it does not directly subtract distance.
# Instead, future aging/injury systems can gradually alter these capacities.
var age: int = 35
var physical_power: float = 70.0
var mobility: float = 70.0
var coordination: float = 70.0
var endurance: float = 70.0

var decision_variability: float
var exploration_margin: float = 5.0

var shots_attempted: int = 0
var successful_shots: int = 0
var water_balls: int = 0

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
	print("Confidence: ", confidence)
	print("Responsiveness to experience: ", responsiveness_to_experience)
	print("Decision variability: ", decision_variability)

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
			confidence = 90.0
			responsiveness_to_experience = 50.0
			decision_variability = 20.0
			age = 35
			physical_power = 70.0
			mobility = 72.0
			coordination = 82.0
			endurance = 72.0
			career_shot_experience = {ShotType.DRIVE: 4200, ShotType.APPROACH: 7000, ShotType.SHORT_GAME: 5200, ShotType.PUTT: 7800}
		GolferProfile.RECKLESS_RICK:
			golfer_name = "Reckless Rick"
			driving = 30.0
			driving_distance = 48.0
			approach = 70.0
			short_game = 70.0
			putting = 70.0
			risk_tolerance = 90.0
			confidence = 95.0
			responsiveness_to_experience = 15.0
			decision_variability = 65.0
			age = 31
			physical_power = 48.0
			mobility = 68.0
			coordination = 55.0
			endurance = 70.0
			career_shot_experience = {ShotType.DRIVE: 1200, ShotType.APPROACH: 2600, ShotType.SHORT_GAME: 1800, ShotType.PUTT: 3000}
		GolferProfile.CAREFUL_CARL:
			golfer_name = "Careful Carl"
			driving = 30.0
			driving_distance = 48.0
			approach = 70.0
			short_game = 70.0
			putting = 70.0
			risk_tolerance = 10.0
			confidence = 60.0
			responsiveness_to_experience = 85.0
			decision_variability = 5.0
			age = 43
			physical_power = 48.0
			mobility = 62.0
			coordination = 74.0
			endurance = 66.0
			career_shot_experience = {ShotType.DRIVE: 3200, ShotType.APPROACH: 5800, ShotType.SHORT_GAME: 5000, ShotType.PUTT: 6500}

func skill_experience_for(shot_type: int) -> int:
	return int(career_shot_experience.get(shot_type, 0))

func physical_distance_factor(shot_type: int) -> float:
	var power_weight = 0.0
	var mobility_weight = 0.0
	var coordination_weight = 0.0
	match shot_type:
		ShotType.DRIVE:
			power_weight = 0.62
			mobility_weight = 0.23
			coordination_weight = 0.15
		ShotType.APPROACH:
			power_weight = 0.45
			mobility_weight = 0.25
			coordination_weight = 0.30
		ShotType.SHORT_GAME:
			power_weight = 0.12
			mobility_weight = 0.18
			coordination_weight = 0.70
		ShotType.PUTT:
			power_weight = 0.02
			mobility_weight = 0.03
			coordination_weight = 0.95
	var capacity = physical_power * power_weight + mobility * mobility_weight + coordination * coordination_weight
	return clamp(lerp(0.82, 1.18, capacity / 100.0) / lerp(0.82, 1.18, 0.70), 0.72, 1.22)

func choose_best_option(options: Array) -> Dictionary:
	var evaluated_options: Array = []
	var best_utility: float = -999999.0
	var best_option: Dictionary = {}
	print("====== SHOT OPTION EVALUATION ======")
	for option in options:
		var evaluation = evaluate_option(option)
		var utility: float = evaluation["utility"]
		evaluated_options.append({"option": option, "utility": utility})
		print("Option: ", option["name"])
		print("Decision basis: ", evaluation["decision_basis"])
		print("Perceived reward: ", evaluation["perceived_reward"])
		print("Perceived risk: ", evaluation["perceived_risk"])
		print("Relevant ability: ", evaluation["ability"])
		print("Ability bonus: ", evaluation["ability_bonus"])
		if evaluation["lie_improvement_bonus"] > 0.0:
			print("Lie improvement bonus: ", evaluation["lie_improvement_bonus"])
			print("Expected next lie: ", option.get("expected_surface", "PLAYABLE"))
		if option.has("next_shot_quality"):
			print("Next-shot quality: ", option["next_shot_quality"])
			print("Next shot green reachable: ", option.get("next_shot_green_reachable", false))
		if option["is_aggressive"]:
			print("Model success chance: ", option["model_success_chance"])
			print("Believed success chance: ", evaluation["believed_success_chance"])
			print("Personality override: ", evaluation.get("personality_override", 0.0))
		print("Specific confidence: ", evaluation["specific_confidence"])
		print("Willingness: ", evaluation["willingness"])
		print("Utility: ", utility)
		print("--------------------")
		if utility > best_utility:
			best_utility = utility
			best_option = option
	var selected_option = apply_behavioral_variability(evaluated_options, best_option, best_utility)
	print("UTILITY-BEST OPTION: ", best_option["name"])
	print("UTILITY-BEST SCORE: ", best_utility)
	print("FINAL SELECTED OPTION: ", selected_option["name"])
	return selected_option

func apply_behavioral_variability(evaluated_options: Array, best_option: Dictionary, best_utility: float) -> Dictionary:
	var alternatives: Array = []
	for entry in evaluated_options:
		var option: Dictionary = entry["option"]
		var utility: float = entry["utility"]
		if option["name"] == best_option["name"]:
			continue
		if best_utility - utility <= exploration_margin:
			alternatives.append(entry)
	print("------ BEHAVIORAL VARIABILITY ------")
	print("Golfer: ", golfer_name)
	print("Decision variability: ", decision_variability)
	print("Exploration margin: ", exploration_margin)
	print("Near-best alternatives: ", alternatives.size())
	if alternatives.is_empty():
		print("No reasonable alternative available.")
		print("Decision: UTILITY BEST")
		return best_option
	var exploration_roll = randf_range(0.0, 100.0)
	print("Exploration roll: ", exploration_roll)
	if exploration_roll > decision_variability:
		print("Decision: UTILITY BEST")
		return best_option
	var selected_entry = alternatives.pick_random()
	var selected_option: Dictionary = selected_entry["option"]
	var selected_utility: float = selected_entry["utility"]
	print("Decision: EXPLORE")
	print("Exploration option: ", selected_option["name"])
	print("Exploration utility: ", selected_utility)
	print("Utility gap: ", best_utility - selected_utility)
	return selected_option

func evaluate_option(option: Dictionary) -> Dictionary:
	var assessment: Dictionary = option.get("assessment", {})
	var subjective: Dictionary = assessment.get("subjective", {})
	if not subjective.is_empty():
		return _evaluate_subjective_option(option, subjective)
	return _evaluate_legacy_option(option)

func _evaluate_subjective_option(option: Dictionary, subjective: Dictionary) -> Dictionary:
	# Perception remains honest: the golfer sees the perceived risk and believed
	# success supplied by the assessment layer. Personality acts only afterward,
	# on how willing the golfer is to accept that perceived risk.
	var perceived_reward = float(subjective.get("assessed_reward", option.get("reward", 0.0)))
	var perceived_risk = float(subjective.get("assessed_risk", option.get("risk", 0.0)))
	var shot_type = int(option.get("shot_type", ShotType.APPROACH))
	var ability = get_shot_ability(shot_type)
	var ability_bonus = ability * 0.06
	var risk_weight = 1.0 - (risk_tolerance / 100.0)
	var risk_penalty = perceived_risk * risk_weight
	var lie_improvement = float(option.get("lie_improvement", 0.0))
	var lie_improvement_bonus = lie_improvement * risk_weight * 60.0
	var believed_success = float(subjective.get("believed_success_chance", option.get("model_success_chance", 50.0)))
	var specific_confidence = float(subjective.get("specific_confidence", confidence))
	var willingness_data: Dictionary = subjective.get("willingness", {})
	var willingness = float(willingness_data.get("willingness_score", 50.0))
	var belief_adjustment = (believed_success - 50.0) * 0.12
	var willingness_adjustment = (willingness - 50.0) * 0.10
	var confidence_adjustment = (specific_confidence - 50.0) * 0.06
	var personality_override = 0.0
	if bool(option.get("is_aggressive", false)):
		var boldness = max(0.0, risk_tolerance - 50.0) * 0.12
		var self_belief = max(0.0, confidence - 50.0) * 0.04
		var stubbornness = max(0.0, 50.0 - responsiveness_to_experience) * 0.06
		personality_override = boldness + self_belief + stubbornness
	var utility = perceived_reward + ability_bonus + lie_improvement_bonus - risk_penalty
	utility += belief_adjustment + willingness_adjustment + confidence_adjustment + personality_override
	return {
		"utility": utility,
		"decision_basis": "SUBJECTIVE_ASSESSMENT",
		"perceived_reward": perceived_reward,
		"perceived_risk": perceived_risk,
		"ability": ability,
		"ability_bonus": ability_bonus,
		"risk_penalty": risk_penalty,
		"lie_improvement_bonus": lie_improvement_bonus,
		"experience_penalty": 0.0,
		"believed_success_chance": believed_success,
		"specific_confidence": specific_confidence,
		"willingness": willingness,
		"belief_adjustment": belief_adjustment,
		"willingness_adjustment": willingness_adjustment,
		"confidence_adjustment": confidence_adjustment,
		"personality_override": personality_override
	}

func _evaluate_legacy_option(option: Dictionary) -> Dictionary:
	var reward = float(option.get("reward", 0.0))
	var risk = float(option.get("risk", 0.0))
	var shot_type = int(option.get("shot_type", ShotType.APPROACH))
	var ability = get_shot_ability(shot_type)
	var ability_bonus = ability * 0.10
	var risk_weight = 1.0 - (risk_tolerance / 100.0)
	var risk_penalty = risk * risk_weight
	var lie_improvement = float(option.get("lie_improvement", 0.0))
	var lie_improvement_bonus = lie_improvement * risk_weight * 60.0
	var experience_penalty = 0.0
	var believed_success_chance = 100.0
	if bool(option.get("is_aggressive", false)):
		var model_success_chance = float(option.get("model_success_chance", 50.0))
		believed_success_chance = get_believed_aggressive_success(model_success_chance)
		if aggressive_attempts >= 3:
			var experience_factor = responsiveness_to_experience / 100.0
			var failure_belief = 1.0 - (believed_success_chance / 100.0)
			var learning_maturity = clamp(float(aggressive_attempts - 2) / 18.0, 0.0, 1.0)
			experience_penalty = failure_belief * experience_factor * learning_maturity * 30.0
	var utility = reward + ability_bonus + lie_improvement_bonus - risk_penalty - experience_penalty
	return {
		"utility": utility,
		"decision_basis": "LEGACY",
		"perceived_reward": reward,
		"perceived_risk": risk,
		"ability": ability,
		"ability_bonus": ability_bonus,
		"risk_penalty": risk_penalty,
		"lie_improvement_bonus": lie_improvement_bonus,
		"experience_penalty": experience_penalty,
		"believed_success_chance": believed_success_chance,
		"specific_confidence": confidence,
		"willingness": 50.0,
		"personality_override": 0.0
	}

func get_shot_ability(shot_type: int) -> float:
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

func get_believed_aggressive_success(model_success_chance: float) -> float:
	if aggressive_attempts == 0:
		return model_success_chance
	var observed_success_rate = (float(aggressive_successes) / float(aggressive_attempts)) * 100.0
	var experience_weight = clamp(float(aggressive_attempts) / 20.0, 0.0, 0.75)
	var model_weight = 1.0 - experience_weight
	return model_success_chance * model_weight + observed_success_rate * experience_weight

func record_shot_result(result: String, was_aggressive: bool = false) -> void:
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
		var success_rate = (float(successful_shots) / float(shots_attempted)) * 100.0
		print("Overall success rate: ", success_rate, "%")
	print("Aggressive attempts: ", aggressive_attempts)
	print("Aggressive successes: ", aggressive_successes)
	print("Aggressive failures: ", aggressive_failures)
	if aggressive_attempts > 0:
		var aggressive_success_rate = (float(aggressive_successes) / float(aggressive_attempts)) * 100.0
		print("Aggressive success rate: ", aggressive_success_rate, "%")

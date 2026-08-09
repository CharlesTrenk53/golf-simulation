extends "res://scenes/golfer.gd"


func choose_best_option(options: Array) -> Dictionary:
	var evaluated_options: Array = []
	var best_utility: float = -999999.0
	var best_option: Dictionary = {}

	for option in options:
		var evaluation = evaluate_option(option)
		var utility: float = evaluation["utility"]
		evaluated_options.append({
			"option": option,
			"utility": utility
		})
		if utility > best_utility:
			best_utility = utility
			best_option = option

	return _apply_behavioral_variability_quiet(
		evaluated_options,
		best_option,
		best_utility
	)


func _apply_behavioral_variability_quiet(
	evaluated_options: Array,
	best_option: Dictionary,
	best_utility: float
) -> Dictionary:
	var alternatives: Array = []

	for entry in evaluated_options:
		var option: Dictionary = entry["option"]
		var utility: float = entry["utility"]
		if option["name"] == best_option["name"]:
			continue
		if best_utility - utility <= exploration_margin:
			alternatives.append(entry)

	if alternatives.is_empty():
		return best_option

	if randf_range(0.0, 100.0) > decision_variability:
		return best_option

	return alternatives.pick_random()["option"]


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

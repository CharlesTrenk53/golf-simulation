extends RefCounted

# Judges decisions using the same assessment evidence available at choice time.
# It deliberately excludes the realized shot outcome so good decisions can still
# be followed by poor execution and vice versa.

func evaluate(golfer: Node, chosen: Dictionary, options: Array) -> Dictionary:
	var chosen_score = score_option(golfer, chosen)
	var best_score = chosen_score
	var best_name = String(chosen.get("name", ""))
	for option in options:
		var score = score_option(golfer, option)
		if score > best_score:
			best_score = score
			best_name = String(option.get("name", ""))
	var gap = max(best_score - chosen_score, 0.0)
	var quality = _quality_for_gap(gap)
	var reason = _reason_for(chosen, quality, gap, best_name)
	return {
		"quality": quality,
		"score": chosen_score,
		"best_score": best_score,
		"gap": gap,
		"best_option": best_name,
		"reason": reason
	}

func score_option(golfer: Node, option: Dictionary) -> float:
	var assessment: Dictionary = option.get("assessment", {})
	var capability: Dictionary = assessment.get("capability", {})
	var willingness: Dictionary = assessment.get("willingness", {})
	var miss: Dictionary = assessment.get("miss_consequences", {})
	var requirements: Dictionary = assessment.get("requirements", {})

	var capability_score = float(capability.get("capability_score", 50.0))
	var willingness_score = float(willingness.get("willingness_score", 50.0))
	var specific_confidence = float(assessment.get("specific_confidence", golfer.confidence))
	var miss_cost = float(miss.get("worst_cost", assessment.get("base_risk", option.get("risk", 50.0))))
	var success_chance = float(option.get("model_success_chance", 50.0))
	var base_reward = float(assessment.get("base_reward", option.get("reward", 0.0)))
	var required_carry = float(requirements.get("required_carry", 0.0))
	var expected_carry = float(capability.get("expected_carry", required_carry))
	var carry_margin = expected_carry - required_carry

	# Capability is the heart of objective decision quality: the same physical
	# shot can be excellent for one golfer and poor for another.
	var score = capability_score * 0.34
	score += success_chance * 0.18
	score += willingness_score * 0.10
	score += specific_confidence * 0.08
	score += clamp(base_reward, 0.0, 100.0) * 0.16
	score += clamp(100.0 - miss_cost, 0.0, 100.0) * 0.14

	# Penalize options that ask for carry the golfer does not realistically own.
	if carry_margin < 0.0:
		score += max(carry_margin * 1.8, -25.0)
	elif carry_margin <= 8.0:
		score += 3.0

	# Reward useful next-shot positioning without assuming that maximum progress
	# is always best. This preserves the value of layups and rough recovery.
	if option.has("next_shot_quality"):
		score += (float(option["next_shot_quality"]) - 50.0) * 0.08
	if option.get("next_shot_green_reachable", false):
		score += 4.0
	if option.get("expected_surface", "") == "FAIRWAY":
		score += 2.0

	return clamp(score, 0.0, 100.0)

func _quality_for_gap(gap: float) -> String:
	if gap <= 2.5:
		return "OPTIMAL"
	if gap <= 7.5:
		return "SENSIBLE"
	if gap <= 15.0:
		return "QUESTIONABLE"
	return "POOR"

func _reason_for(chosen: Dictionary, quality: String, gap: float, best_name: String) -> String:
	if quality == "OPTIMAL":
		return "Selected option is at or near the best golfer-specific assessed choice (gap %.1f)" % gap
	if chosen.get("name", "") == "RECOVER_TO_FAIRWAY":
		return "Recovery was judged against capability, miss cost and next-shot setup; best alternative was %s (gap %.1f)" % [best_name, gap]
	return "%s decision is %.1f assessment points behind %s" % [quality.capitalize(), gap, best_name]

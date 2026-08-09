extends RefCounted

# Judges decisions using the same assessment evidence available at choice time.
# It deliberately excludes the realized shot outcome so good decisions can still
# be followed by poor execution and vice versa.

func evaluate(golfer: Node, chosen: Dictionary, options: Array) -> Dictionary:
	var chosen_breakdown = score_breakdown(golfer, chosen)
	var chosen_score = float(chosen_breakdown["final_score"])
	var best_score = chosen_score
	var best_name = String(chosen.get("name", ""))
	var best_breakdown: Dictionary = chosen_breakdown
	var option_breakdowns: Array = []
	for option in options:
		var breakdown = score_breakdown(golfer, option)
		var score = float(breakdown["final_score"])
		option_breakdowns.append(breakdown)
		if score > best_score:
			best_score = score
			best_name = String(option.get("name", ""))
			best_breakdown = breakdown
	var gap = max(best_score - chosen_score, 0.0)
	var quality = _quality_for_gap(gap)
	var reason = _reason_for(chosen, quality, gap, best_name)
	return {
		"quality": quality,
		"score": chosen_score,
		"best_score": best_score,
		"gap": gap,
		"best_option": best_name,
		"reason": reason,
		"chosen_breakdown": chosen_breakdown,
		"best_breakdown": best_breakdown,
		"option_breakdowns": option_breakdowns
	}

func score_option(golfer: Node, option: Dictionary) -> float:
	return float(score_breakdown(golfer, option)["final_score"])

func score_breakdown(golfer: Node, option: Dictionary) -> Dictionary:
	var assessment: Dictionary = option.get("assessment", {})
	var capability: Dictionary = assessment.get("capability", {})
	var willingness: Dictionary = assessment.get("willingness", {})
	var miss: Dictionary = assessment.get("miss_consequences", {})
	var requirements: Dictionary = assessment.get("requirements", {})
	var future: Dictionary = assessment.get("future_state", {})

	var capability_score = float(capability.get("capability_score", 50.0))
	var willingness_score = float(willingness.get("willingness_score", 50.0))
	var specific_confidence = float(assessment.get("specific_confidence", golfer.confidence))
	var miss_cost = float(miss.get("worst_cost", assessment.get("base_risk", option.get("risk", 50.0))))
	var success_chance = float(option.get("model_success_chance", 50.0))
	var base_reward = float(assessment.get("base_reward", option.get("reward", 0.0)))
	var required_carry = float(requirements.get("required_carry", 0.0))
	var expected_carry = float(capability.get("expected_carry", required_carry))
	var carry_margin = expected_carry - required_carry
	var expected_strokes_remaining = float(future.get("expected_strokes_remaining", 3.0))

	var capability_component = capability_score * 0.26
	var success_component = success_chance * 0.14
	var willingness_component = willingness_score * 0.07
	var confidence_component = specific_confidence * 0.06
	var reward_component = clamp(base_reward, 0.0, 100.0) * 0.11
	var miss_component = clamp(100.0 - miss_cost, 0.0, 100.0) * 0.10
	var future_component = clamp(60.0 - expected_strokes_remaining * 12.0, 0.0, 60.0) * 0.43
	var carry_component = 0.0
	if carry_margin < 0.0:
		carry_component = max(carry_margin * 1.5, -22.0)
	elif carry_margin <= 8.0:
		carry_component = 2.0
	var next_shot_component = 0.0
	if option.has("next_shot_quality"):
		next_shot_component += (float(option["next_shot_quality"]) - 50.0) * 0.04
	if option.get("next_shot_green_reachable", false):
		next_shot_component += 2.0
	if option.get("expected_surface", "") == "FAIRWAY":
		next_shot_component += 1.0

	var raw_score = capability_component + success_component + willingness_component + confidence_component + reward_component + miss_component + future_component + carry_component + next_shot_component
	var final_score = clamp(raw_score, 0.0, 100.0)
	return {
		"option": String(option.get("name", "")),
		"club": String(option.get("club_name", "")),
		"final_score": final_score,
		"raw_score": raw_score,
		"capability": capability_score,
		"success_chance": success_chance,
		"willingness": willingness_score,
		"specific_confidence": specific_confidence,
		"miss_cost": miss_cost,
		"base_reward": base_reward,
		"required_carry": required_carry,
		"expected_carry": expected_carry,
		"carry_margin": carry_margin,
		"expected_surface": String(future.get("expected_surface", option.get("expected_surface", ""))),
		"expected_remaining_distance": float(future.get("expected_remaining_distance", 0.0)),
		"expected_strokes_remaining": expected_strokes_remaining,
		"hazard_penalty_strokes": float(future.get("hazard_penalty_strokes", 0.0)),
		"capability_component": capability_component,
		"success_component": success_component,
		"willingness_component": willingness_component,
		"confidence_component": confidence_component,
		"reward_component": reward_component,
		"miss_component": miss_component,
		"future_component": future_component,
		"carry_component": carry_component,
		"next_shot_component": next_shot_component
	}

func _quality_for_gap(gap: float) -> String:
	if gap <= 2.5:
		return "OPTIMAL"
	if gap <= 7.5:
		return "SENSIBLE"
	if gap <= 15.0:
		return "QUESTIONABLE"
	return "POOR"

func _reason_for(chosen: Dictionary, quality: String, gap: float, best_name: String) -> String:
	var future: Dictionary = chosen.get("assessment", {}).get("future_state", {})
	var strokes = float(future.get("expected_strokes_remaining", -1.0))
	var future_text = ""
	if strokes >= 0.0:
		future_text = " with %.2f expected strokes remaining" % strokes
	if quality == "OPTIMAL":
		return "Selected option is at or near the best golfer-specific assessed choice%s (gap %.1f)" % [future_text, gap]
	if chosen.get("name", "") == "RECOVER_TO_FAIRWAY":
		return "Recovery was judged against capability, miss cost and future state%s; best alternative was %s (gap %.1f)" % [future_text, best_name, gap]
	return "%s decision%s is %.1f assessment points behind %s" % [quality.capitalize(), future_text, gap, best_name]

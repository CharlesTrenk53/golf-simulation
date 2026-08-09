extends RefCounted

# Judges the objective quality of the decision using world/capability evidence,
# not the golfer's subjective confidence or willingness. This lets the simulator
# distinguish a believable personal choice from the objectively strongest play.
# Realized shot outcome is deliberately excluded.

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
	return {
		"quality": quality,
		"score": chosen_score,
		"best_score": best_score,
		"gap": gap,
		"best_option": best_name,
		"reason": _reason_for(chosen, quality, gap, best_name),
		"chosen_breakdown": chosen_breakdown,
		"best_breakdown": best_breakdown,
		"option_breakdowns": option_breakdowns
	}

func score_option(golfer: Node, option: Dictionary) -> float:
	return float(score_breakdown(golfer, option)["final_score"])

func score_breakdown(golfer: Node, option: Dictionary) -> Dictionary:
	var assessment: Dictionary = option.get("assessment", {})
	var objective: Dictionary = assessment.get("objective", assessment)
	var subjective: Dictionary = assessment.get("subjective", {})
	var capability: Dictionary = objective.get("capability", {})
	var miss: Dictionary = objective.get("miss_consequences", {})
	var requirements: Dictionary = objective.get("requirements", {})
	var future: Dictionary = objective.get("future_state", assessment.get("future_state", {}))

	var capability_score = float(capability.get("capability_score", 50.0))
	var miss_cost = float(miss.get("worst_cost", objective.get("base_risk", option.get("risk", 50.0))))
	var success_chance = float(objective.get("model_success_chance", option.get("model_success_chance", 50.0)))
	var base_reward = float(objective.get("base_reward", option.get("reward", 0.0)))
	var required_carry = float(requirements.get("required_carry", 0.0))
	var expected_carry = float(capability.get("expected_carry", required_carry))
	var carry_margin = expected_carry - required_carry
	var expected_strokes_remaining = float(future.get("expected_strokes_remaining", 3.0))

	var capability_component = capability_score * 0.32
	var success_component = success_chance * 0.18
	var reward_component = clamp(base_reward, 0.0, 100.0) * 0.13
	var miss_component = clamp(100.0 - miss_cost, 0.0, 100.0) * 0.12
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

	var raw_score = capability_component + success_component + reward_component + miss_component + future_component + carry_component + next_shot_component
	var final_score = clamp(raw_score, 0.0, 100.0)
	var willingness_data: Dictionary = subjective.get("willingness", {})
	return {
		"option": String(option.get("name", "")),
		"club": String(option.get("club_name", "")),
		"final_score": final_score,
		"raw_score": raw_score,
		"capability": capability_score,
		"success_chance": success_chance,
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
		"reward_component": reward_component,
		"miss_component": miss_component,
		"future_component": future_component,
		"carry_component": carry_component,
		"next_shot_component": next_shot_component,
		# Subjective values are retained for explanation only; they do not affect
		# the objective quality score.
		"subjective_willingness": float(willingness_data.get("willingness_score", 50.0)),
		"subjective_confidence": float(subjective.get("specific_confidence", golfer.confidence)),
		"subjective_believed_success": float(subjective.get("believed_success_chance", success_chance))
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
	var assessment: Dictionary = chosen.get("assessment", {})
	var objective: Dictionary = assessment.get("objective", assessment)
	var future: Dictionary = objective.get("future_state", assessment.get("future_state", {}))
	var strokes = float(future.get("expected_strokes_remaining", -1.0))
	var future_text = ""
	if strokes >= 0.0:
		future_text = " with %.2f expected strokes remaining" % strokes
	if quality == "OPTIMAL":
		return "Selected option is at or near the objectively strongest golfer-capability choice%s (gap %.1f)" % [future_text, gap]
	if chosen.get("name", "") == "RECOVER_TO_FAIRWAY":
		return "Recovery was judged against objective capability, miss cost and future state%s; best alternative was %s (gap %.1f)" % [future_text, best_name, gap]
	return "%s decision%s is %.1f objective assessment points behind %s" % [quality.capitalize(), future_text, gap, best_name]

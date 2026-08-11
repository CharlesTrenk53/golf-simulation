extends RefCounted

# POC-13B: golfer-specific evaluation of bag-derived club candidates.
# ------------------------------------------------------------------
# ClubCandidateGenerator owns feasibility and geometry facts. This evaluator does
# not alter those facts; it turns them into strategic scores for a particular
# golfer so cautious and aggressive players can value the same shot differently.

const GolfBag = preload("res://simulation/golf_bag.gd")

var bag = GolfBag.new()


func evaluate_all(golfer: Node, state, candidates: Array) -> Array:
	var evaluated: Array = []
	if golfer == null or state == null:
		return evaluated
	for candidate in candidates:
		evaluated.append(evaluate(golfer, state, candidate))
	evaluated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("strategy_score", -INF)) > float(b.get("strategy_score", -INF))
	)
	return evaluated


func evaluate(golfer: Node, state, candidate: Dictionary) -> Dictionary:
	var result: Dictionary = candidate.duplicate(true)
	var remaining_before: float = max(1.0, state.remaining_distance())
	var remaining_after: float = max(0.0, float(candidate.get("remaining_after_target", remaining_before)))
	var progress: float = clamp((remaining_before - remaining_after) / remaining_before, 0.0, 1.0)
	var progress_score: float = progress * 55.0

	var expected_surface: String = str(candidate.get("expected_surface", "UNKNOWN"))
	var landing_score: float = _landing_surface_score(expected_surface)
	var dispersion: float = max(0.0, float(candidate.get("dispersion", 0.0)))
	var dispersion_penalty: float = min(24.0, dispersion * 0.9)
	var hazard_count: int = int(candidate.get("corridor_hazard_count", 0))
	var hazard_pressure: float = min(55.0, float(hazard_count) * 18.0)
	var ob_pressure: float = 65.0 if bool(candidate.get("out_of_bounds", false)) else 0.0
	var risk_pressure: float = hazard_pressure + ob_pressure + dispersion_penalty

	# Personality changes willingness, not perception. A risk-tolerant golfer sees
	# the same hazard pressure as Carl; he simply pays less strategic cost for it.
	var risk_tolerance: float = clamp(float(golfer.get("risk_tolerance")), 0.0, 100.0)
	var risk_weight: float = lerp(1.35, 0.45, risk_tolerance / 100.0)
	var risk_penalty: float = risk_pressure * risk_weight

	var next_shot_score: float = _next_shot_setup_score(golfer, expected_surface, remaining_after)
	var green_bonus: float = 18.0 if bool(candidate.get("green_reaching", false)) else 0.0
	var ability: float = golfer.get_shot_ability(int(candidate.get("shot_type", 1)))
	var ability_bonus: float = ability * 0.08
	var confidence: float = clamp(float(golfer.get("confidence")), 0.0, 100.0)
	var confidence_bonus: float = confidence * 0.025

	var strategy_score: float = progress_score + landing_score + next_shot_score + green_bonus + ability_bonus + confidence_bonus - risk_penalty
	result["progress_score"] = progress_score
	result["landing_score"] = landing_score
	result["dispersion_penalty"] = dispersion_penalty
	result["hazard_pressure"] = hazard_pressure
	result["ob_pressure"] = ob_pressure
	result["risk_pressure"] = risk_pressure
	result["risk_weight"] = risk_weight
	result["risk_penalty"] = risk_penalty
	result["next_shot_score"] = next_shot_score
	result["green_bonus"] = green_bonus
	result["ability_bonus"] = ability_bonus
	result["confidence_bonus"] = confidence_bonus
	result["strategy_score"] = strategy_score
	return result


func _landing_surface_score(surface: String) -> float:
	match surface.to_upper():
		"GREEN": return 26.0
		"FAIRWAY": return 18.0
		"TEE": return 10.0
		"ROUGH": return 3.0
		"BUNKER": return -16.0
		"WATER": return -48.0
		_: return 0.0


func _next_shot_setup_score(golfer: Node, expected_surface: String, remaining_distance: float) -> float:
	if remaining_distance <= 8.0:
		return 24.0
	var surface: String = expected_surface.to_upper()
	if surface == "GREEN":
		return 24.0
	if surface == "WATER" or surface == "BUNKER" or surface == "UNKNOWN":
		return 0.0
	var lie_quality: float = 0.95 if surface == "FAIRWAY" else 0.72
	var best_gap: float = INF
	for club in bag.clubs_for_surface(surface):
		if str(club.get("id", "")) == "PUTTER":
			continue
		var carry: float = bag.effective_carry(club, golfer, surface, lie_quality)
		best_gap = min(best_gap, abs(carry - remaining_distance))
	if is_inf(best_gap):
		return 0.0
	return clamp(20.0 - best_gap * 0.12, 0.0, 20.0)

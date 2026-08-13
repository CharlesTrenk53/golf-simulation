extends RefCounted

# POC-20B: Round Adaptation Signals
# ---------------------------------
# Interprets objective RoundContext facts through persistent golfer traits.
# These are signals only: this model does not modify strategy or shot execution.
# That separation lets later slices decide how much each signal should matter
# without hiding behavioral tuning inside scorekeeping or golfer state.
#
# Pressure is intentionally absent here. Score relative to par alone is not a
# meaningful pressure condition without a target, opponent, cut line, or goal.


func interpret(golfer: Node, context: Dictionary) -> Dictionary:
	if golfer == null or context.is_empty():
		return {}

	var progress: float = clamp(float(context.get("round_progress", 0.0)), 0.0, 1.0)
	var endurance: float = _trait_01(golfer, "endurance", 70.0)
	var responsiveness: float = _trait_01(golfer, "responsiveness_to_experience", 50.0)
	var baseline_confidence: float = _trait_01(golfer, "confidence", 50.0)
	var recent_average_to_par: float = float(context.get("recent_average_to_par", 0.0))
	var recent_count: int = int(context.get("recent_holes_count", 0))

	# Physical load is deliberately relative rather than a direct skill penalty.
	# A golfer with 100 endurance has no modeled endurance vulnerability; a golfer
	# with lower endurance accumulates more exposure as the round progresses.
	var endurance_vulnerability: float = 1.0 - endurance
	var physical_load_exposure: float = progress * endurance_vulnerability

	# Recent form is directional: below-par play is positive, above-par play is
	# negative, and par is neutral. One stroke per hole is enough to represent a
	# full-strength directional signal; larger scoring swings do not stack without
	# bound. No completed recent holes means no momentum signal.
	var recent_form_signal: float = 0.0
	if recent_count > 0:
		recent_form_signal = clamp(-recent_average_to_par, -1.0, 1.0)

	# Responsiveness says how strongly the golfer tends to internalize recent
	# experience. This remains a signal, not a rewritten confidence rating.
	var confidence_momentum_signal: float = recent_form_signal * responsiveness

	return {
		"round_progress": progress,
		"endurance": endurance,
		"endurance_vulnerability": endurance_vulnerability,
		"physical_load_exposure": physical_load_exposure,
		"baseline_confidence": baseline_confidence,
		"experience_responsiveness": responsiveness,
		"recent_form_signal": recent_form_signal,
		"confidence_momentum_signal": confidence_momentum_signal,
		"score_to_par": int(context.get("score_to_par", 0)),
		"holes_remaining": int(context.get("holes_remaining", 0))
	}


func _trait_01(golfer: Node, property_name: String, fallback: float) -> float:
	var raw: Variant = golfer.get(property_name)
	if raw == null:
		raw = fallback
	return clamp(float(raw) / 100.0, 0.0, 1.0)

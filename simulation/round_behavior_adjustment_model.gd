extends RefCounted

# POC-20D: Transient Round Behavior Adjustments
# ----------------------------------------------
# Converts round-adaptation signals into small, bounded, per-hole behavioral
# modifiers. Persistent golfer traits are never rewritten here.
#
# These are intentionally first-pass magnitudes, not scoring calibration knobs.
# POC-20D proves directionality and separation; later stress tests decide whether
# their magnitude is believable over full rounds.

const MAX_RISK_TOLERANCE_SHIFT := 8.0
const MAX_EXECUTION_DISPERSION_INCREASE := 0.20


func build(golfer: Node, adaptation: Dictionary) -> Dictionary:
	if golfer == null or adaptation.is_empty():
		return {
			"base_risk_tolerance": 50.0,
			"risk_tolerance_shift": 0.0,
			"effective_risk_tolerance": 50.0,
			"execution_dispersion_multiplier": 1.0
		}

	var raw_risk = golfer.get("risk_tolerance")
	var base_risk_tolerance: float = 50.0 if raw_risk == null else clamp(float(raw_risk), 0.0, 100.0)
	var momentum: float = clamp(float(adaptation.get("confidence_momentum_signal", 0.0)), -1.0, 1.0)
	var physical_load: float = clamp(float(adaptation.get("physical_load_exposure", 0.0)), 0.0, 1.0)

	# Positive recent form makes a golfer modestly more willing to accept close
	# strategic risks; negative form does the reverse. The shift is deliberately
	# bounded so context can break close ties without overriding personality.
	var risk_tolerance_shift: float = momentum * MAX_RISK_TOLERANCE_SHIFT
	var effective_risk_tolerance: float = clamp(base_risk_tolerance + risk_tolerance_shift, 0.0, 100.0)

	# Physical load modestly widens execution dispersion. It does not reduce club
	# distance, skill ratings, or reliability directly, which keeps fatigue from
	# silently becoming a second aging/ability system.
	var execution_dispersion_multiplier: float = 1.0 + physical_load * MAX_EXECUTION_DISPERSION_INCREASE

	return {
		"base_risk_tolerance": base_risk_tolerance,
		"risk_tolerance_shift": risk_tolerance_shift,
		"effective_risk_tolerance": effective_risk_tolerance,
		"physical_load_exposure": physical_load,
		"execution_dispersion_multiplier": execution_dispersion_multiplier
	}

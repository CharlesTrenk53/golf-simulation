extends RefCounted

# POC-14D: stochastic execution realization.
# Theoretical flight and golfer proficiency remain immutable inputs. This layer
# realizes one actual shot from them using a deterministic seed for repeatable
# tests and simulations.


func realize(predicted_flight: Dictionary, proficiency: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var reliability: float = clamp(float(proficiency.get("execution_reliability", 0.70)), 0.05, 0.99)
	var dispersion_multiplier: float = max(0.1, float(proficiency.get("expected_dispersion_multiplier", 1.0)))
	var planned_carry: float = max(0.0, float(predicted_flight.get("carry_yards", 0.0)))
	var planned_rollout: float = max(0.0, float(predicted_flight.get("rollout_yards", 0.0)))
	var planned_curve: float = float(predicted_flight.get("curve_yards", 0.0))
	var planned_apex: float = max(0.05, float(predicted_flight.get("apex_factor", 1.0)))
	var planned_dispersion: float = max(0.1, float(predicted_flight.get("dispersion_yards", 1.0)))

	# Better reliability narrows strike/launch/direction error. We use bounded
	# Gaussian-like noise so actual shots remain variable without absurd outliers.
	var error_scale: float = lerp(1.0, 0.18, reliability)
	var lateral_sigma: float = planned_dispersion * dispersion_multiplier * error_scale
	var distance_sigma: float = planned_carry * lerp(0.10, 0.025, reliability)
	var apex_sigma: float = planned_apex * lerp(0.14, 0.035, reliability)
	var curve_sigma: float = max(1.0, abs(planned_curve) * 0.28 + planned_dispersion * 0.20) * error_scale

	var lateral_error: float = clamp(rng.randfn(0.0, lateral_sigma), -lateral_sigma * 2.5, lateral_sigma * 2.5)
	var carry_error: float = clamp(rng.randfn(0.0, distance_sigma), -distance_sigma * 2.5, distance_sigma * 2.5)
	var apex_error: float = clamp(rng.randfn(0.0, apex_sigma), -apex_sigma * 2.5, apex_sigma * 2.5)
	var curve_error: float = clamp(rng.randfn(0.0, curve_sigma), -curve_sigma * 2.5, curve_sigma * 2.5)

	var actual_carry: float = max(0.0, planned_carry + carry_error)
	var carry_ratio: float = actual_carry / planned_carry if planned_carry > 0.01 else 1.0
	var actual_rollout: float = max(0.0, planned_rollout * clamp(carry_ratio, 0.65, 1.25))
	var actual_curve: float = planned_curve + curve_error
	var actual_apex: float = max(0.05, planned_apex + apex_error)
	var final_lateral: float = actual_curve + lateral_error

	return {
		"intent_signature": str(predicted_flight.get("intent_signature", "")),
		"seed": seed_value,
		"planned_carry_yards": planned_carry,
		"actual_carry_yards": actual_carry,
		"carry_error_yards": carry_error,
		"planned_rollout_yards": planned_rollout,
		"actual_rollout_yards": actual_rollout,
		"actual_total_yards": actual_carry + actual_rollout,
		"planned_curve_yards": planned_curve,
		"actual_curve_yards": actual_curve,
		"curve_error_yards": curve_error,
		"lateral_error_yards": lateral_error,
		"final_lateral_yards": final_lateral,
		"planned_apex_factor": planned_apex,
		"actual_apex_factor": actual_apex,
		"execution_reliability": reliability,
		"error_scale": error_scale
	}

extends RefCounted

# POC-15B: realize one actual putt from an immutable read + proficiency profile.
# Seeded noise keeps tests and simulations repeatable while still producing
# golfer-specific line and pace misses.


func realize(planned_putt: Dictionary, proficiency: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var planned_aim_feet: float = float(planned_putt.get("aim_offset_feet", 0.0))
	var planned_distance_feet: float = maxf(0.0, float(planned_putt.get("intended_distance_feet", 0.0)))
	var line_sigma_inches: float = maxf(0.05, float(proficiency.get("line_sigma_inches", 2.0)))
	var pace_sigma_feet: float = maxf(0.05, float(proficiency.get("pace_sigma_feet", 1.0)))

	var line_error_inches: float = clampf(
		rng.randfn(0.0, line_sigma_inches),
		-line_sigma_inches * 2.5,
		line_sigma_inches * 2.5
	)
	var pace_error_feet: float = clampf(
		rng.randfn(0.0, pace_sigma_feet),
		-pace_sigma_feet * 2.5,
		pace_sigma_feet * 2.5
	)
	var actual_aim_feet: float = planned_aim_feet + line_error_inches / 12.0
	var actual_distance_feet: float = maxf(0.0, planned_distance_feet + pace_error_feet)

	return {
		"seed": seed_value,
		"putt_signature": str(planned_putt.get("signature", "")),
		"planned_aim_offset_feet": planned_aim_feet,
		"actual_aim_offset_feet": actual_aim_feet,
		"line_error_inches": line_error_inches,
		"planned_distance_feet": planned_distance_feet,
		"actual_distance_feet": actual_distance_feet,
		"pace_error_feet": pace_error_feet,
		"execution_reliability": float(proficiency.get("execution_reliability", 0.5))
	}

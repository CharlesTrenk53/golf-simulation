extends RefCounted

# POC-15D: choose how assertively to roll a putt after the green has been read.
# This layer does not change the read itself. It adjusts only the intended pace
# according to golfer traits and the consequence of leaving a difficult comeback.

const STRATEGY_LAG := "LAG"
const STRATEGY_NEUTRAL := "NEUTRAL"
const STRATEGY_ATTACK := "ATTACK"


func choose_strategy(golfer: Node, planned_putt: Dictionary) -> Dictionary:
	var distance_feet: float = maxf(0.0, float(planned_putt.get("distance_feet", 0.0)))
	var slope_along_percent: float = float(planned_putt.get("slope_along_percent", 0.0))
	var green_speed: float = clampf(float(planned_putt.get("green_speed", 10.0)), 7.0, 14.0)
	var putting_ability: float = clampf(float(golfer.get_shot_ability(3)), 0.0, 100.0)
	var confidence: float = clampf(float(golfer.get("confidence")), 0.0, 100.0)
	var risk_tolerance: float = clampf(float(golfer.get("risk_tolerance")), 0.0, 100.0)

	# Makeability falls primarily with distance. Better putters retain more license
	# to attack because they are both more likely to hole the first putt and better
	# equipped to handle the resulting comeback.
	var distance_pressure: float = clampf((distance_feet - 8.0) / 32.0, 0.0, 1.0)
	var downhill_pressure: float = clampf(maxf(-slope_along_percent, 0.0) / 4.0, 0.0, 1.0)
	var speed_pressure: float = clampf((green_speed - 10.0) / 4.0, 0.0, 1.0)
	var golfer_assertiveness: float = (
		putting_ability * 0.45 + risk_tolerance * 0.35 + confidence * 0.20
	) / 100.0
	var caution_pressure: float = clampf(
		distance_pressure * 0.58 + downhill_pressure * 0.30 + speed_pressure * 0.12,
		0.0,
		1.0
	)
	var attack_margin: float = golfer_assertiveness - caution_pressure

	var strategy: String = STRATEGY_NEUTRAL
	var pace_multiplier: float = 1.0
	if attack_margin >= 0.38 and distance_feet <= 25.0:
		strategy = STRATEGY_ATTACK
		pace_multiplier = 1.06
	elif attack_margin <= 0.02 or distance_feet >= 35.0:
		# From roughly 35 feet, even confident players should primarily manage the
		# next putt rather than behave as if this were a normal make-range attempt.
		strategy = STRATEGY_LAG
		pace_multiplier = 0.94

	var base_intended_distance: float = maxf(0.0, float(planned_putt.get("intended_distance_feet", distance_feet)))
	var adjusted_intended_distance: float = distance_feet + (base_intended_distance - distance_feet) * pace_multiplier
	adjusted_intended_distance = maxf(distance_feet * 0.90, adjusted_intended_distance)

	var result: Dictionary = planned_putt.duplicate(true)
	result["strategy"] = strategy
	result["strategy_pace_multiplier"] = pace_multiplier
	result["strategy_attack_margin"] = attack_margin
	result["strategy_caution_pressure"] = caution_pressure
	result["putting_ability"] = putting_ability
	result["risk_tolerance"] = risk_tolerance
	result["confidence"] = confidence
	result["base_intended_distance_feet"] = base_intended_distance
	result["intended_distance_feet"] = adjusted_intended_distance
	result["pace_feet_past_hole"] = maxf(0.0, adjusted_intended_distance - distance_feet)
	return result

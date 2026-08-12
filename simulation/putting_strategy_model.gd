extends RefCounted

# POC-15D: choose how assertively to roll a putt after the green has been read.
# This layer preserves the read and continuously adjusts intended pace according
# to golfer traits and the consequence of leaving a difficult comeback.

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

	# Pace intent is continuous even though we retain categorical labels for
	# diagnostics. Close decisions therefore produce subtly different golfers
	# instead of every player snapping to exactly the same ATTACK/NEUTRAL/LAG pace.
	var assertive_tendency: float = clampf(0.50 + attack_margin * 0.85, 0.0, 1.0)
	var pace_adjustment_feet: float = lerpf(-0.30, 0.35, assertive_tendency)
	# Very long putts have an additional consequence-management pull toward lag
	# pace, while fast/downhill contexts are already represented in caution.
	var long_lag_pressure: float = clampf((distance_feet - 28.0) / 20.0, 0.0, 1.0)
	pace_adjustment_feet -= long_lag_pressure * 0.20

	var strategy: String = STRATEGY_NEUTRAL
	if assertive_tendency >= 0.68 and distance_feet <= 28.0:
		strategy = STRATEGY_ATTACK
	elif assertive_tendency <= 0.34 or distance_feet >= 35.0:
		strategy = STRATEGY_LAG

	var base_intended_distance: float = maxf(0.0, float(planned_putt.get("intended_distance_feet", distance_feet)))
	var adjusted_intended_distance: float = maxf(0.0, base_intended_distance + pace_adjustment_feet)
	# Keep an intentional but modest capture pace. Defensive strategy can target
	# near the cup, but never an implausibly large deliberate under-hit.
	adjusted_intended_distance = maxf(distance_feet - 0.15, adjusted_intended_distance)

	var result: Dictionary = planned_putt.duplicate(true)
	result["strategy"] = strategy
	result["strategy_assertive_tendency"] = assertive_tendency
	result["strategy_pace_adjustment_feet"] = pace_adjustment_feet
	result["strategy_attack_margin"] = attack_margin
	result["strategy_caution_pressure"] = caution_pressure
	result["strategy_long_lag_pressure"] = long_lag_pressure
	result["putting_ability"] = putting_ability
	result["risk_tolerance"] = risk_tolerance
	result["confidence"] = confidence
	result["base_intended_distance_feet"] = base_intended_distance
	result["intended_distance_feet"] = adjusted_intended_distance
	result["pace_feet_past_hole"] = maxf(0.0, adjusted_intended_distance - distance_feet)
	return result

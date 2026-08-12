extends RefCounted

const ShotIntent = preload("res://simulation/shot_intent.gd")

# POC-14C: golfer-specific ability to execute a requested shot intent.
# Predicted flight remains the theoretical shot. This layer answers a different
# question: how capable and how confident is THIS golfer when attempting it?
# Keeping those concepts separate lets a golfer be skilled but cautious, or
# relatively unskilled but overconfident, without corrupting physical prediction.


func assess(golfer: Node, club: Dictionary, intent: Dictionary, predicted_flight: Dictionary) -> Dictionary:
	var shot_type: int = int(club.get("shot_type", 1))
	var base_ability: float = _shot_ability(golfer, shot_type)
	var coordination: float = clamp(float(golfer.get("coordination")), 0.0, 100.0)
	var general_confidence: float = clamp(float(golfer.get("confidence")), 0.0, 100.0)
	var difficulty: float = clamp(float(predicted_flight.get("execution_difficulty", 0.0)), 0.0, 1.0)

	# Technical ability drives most of true proficiency; coordination matters more
	# as the requested shot departs from a stock motion. Difficulty then creates a
	# soft execution burden rather than making any feasible intent impossible.
	var technical_foundation: float = base_ability * 0.72 + coordination * 0.28
	var intent_familiarity: float = _intent_familiarity(intent)
	var complexity_penalty: float = difficulty * lerp(18.0, 34.0, 1.0 - intent_familiarity)
	var proficiency: float = clamp(technical_foundation - complexity_penalty, 0.0, 100.0)

	# Confidence intentionally does not equal proficiency. General confidence is
	# anchored toward demonstrated proficiency, but bold/overconfident golfers can
	# still believe in a shot more than their execution skill warrants.
	var self_confidence: float = clamp(general_confidence * 0.62 + proficiency * 0.38 - difficulty * 8.0, 0.0, 100.0)
	var confidence_gap: float = self_confidence - proficiency
	var execution_reliability: float = clamp((proficiency / 100.0) * (1.0 - difficulty * 0.42), 0.05, 0.99)
	var expected_dispersion_multiplier: float = lerp(1.55, 0.72, proficiency / 100.0) * (1.0 + difficulty * 0.38)

	return {
		"intent_signature": str(intent.get("signature", "")),
		"base_ability": base_ability,
		"coordination": coordination,
		"theoretical_difficulty": difficulty,
		"intent_familiarity": intent_familiarity,
		"proficiency": proficiency,
		"self_confidence": self_confidence,
		"confidence_gap": confidence_gap,
		"execution_reliability": execution_reliability,
		"expected_dispersion_multiplier": expected_dispersion_multiplier
	}


func _shot_ability(golfer: Node, shot_type: int) -> float:
	if golfer.has_method("get_shot_ability"):
		return clamp(float(golfer.get_shot_ability(shot_type)), 0.0, 100.0)
	return 70.0


func _intent_familiarity(intent: Dictionary) -> float:
	var familiarity: float = 1.0
	if int(intent.get("shape", ShotIntent.Shape.STRAIGHT)) != ShotIntent.Shape.STRAIGHT:
		familiarity -= 0.10
	if int(intent.get("trajectory", ShotIntent.Trajectory.NORMAL)) != ShotIntent.Trajectory.NORMAL:
		familiarity -= 0.08
	if int(intent.get("swing_length", ShotIntent.SwingLength.FULL)) != ShotIntent.SwingLength.FULL:
		familiarity -= 0.08

	match int(intent.get("technique", ShotIntent.Technique.STOCK)):
		ShotIntent.Technique.PUNCH:
			familiarity -= 0.06
		ShotIntent.Technique.STINGER:
			familiarity -= 0.14
		ShotIntent.Technique.PITCH:
			familiarity -= 0.05
		ShotIntent.Technique.FLOP:
			familiarity -= 0.22
		ShotIntent.Technique.CHIP:
			familiarity -= 0.04
		ShotIntent.Technique.BUMP_AND_RUN:
			familiarity -= 0.03
		ShotIntent.Technique.BUNKER:
			familiarity -= 0.14

	return clamp(familiarity, 0.35, 1.0)

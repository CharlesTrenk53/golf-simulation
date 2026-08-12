extends RefCounted

# POC-13D / POC-14E: autonomous course-strategy selector.
# -------------------------------------------------------
# POC-13 chooses club + target from golfer, bag and geometry. POC-14 now layers a
# separate HOW decision onto each feasible plan: trajectory, shape, swing length
# and technique. The ordering remains intentional:
# club + target -> shot intent -> execution.

const ClubCandidateGenerator = preload("res://simulation/club_candidate_generator.gd")
const ClubCandidateEvaluator = preload("res://simulation/club_candidate_evaluator.gd")
const CourseManagementModel = preload("res://simulation/course_management_model.gd")
const ShotIntentStrategyModel = preload("res://simulation/shot_intent_strategy_model.gd")

var generator = ClubCandidateGenerator.new()
var evaluator = ClubCandidateEvaluator.new()
var course_management = CourseManagementModel.new()
var shot_intent_strategy = ShotIntentStrategyModel.new()


func use_literal_yardages(enabled: bool = true) -> void:
	generator.bag.use_literal_yardages(enabled)
	evaluator.bag.use_literal_yardages(enabled)


func choose(golfer: Node, state) -> Dictionary:
	var candidates: Array = generator.generate(golfer, state)
	if candidates.is_empty():
		return {"chosen": {}, "evaluated": []}

	var objective_ranked: Array = evaluator.evaluate_all(golfer, state, candidates)
	var decision_ranked: Array = []
	var current_surface: String = state.surface_name()
	for objective in objective_ranked:
		var candidate: Dictionary = objective.duplicate(true)
		var perception: Dictionary = course_management.perception_for(
			golfer,
			objective,
			candidate,
			state.remaining_distance()
		)
		for key in perception.keys():
			candidate[key] = perception[key]
		var personality: Dictionary = _personality_strategy_adjustment(golfer, candidate)
		for key in personality.keys():
			candidate[key] = personality[key]

		# POC-14E deliberately chooses intent after club + target have been evaluated.
		# This preserves the proven POC-13 strategy architecture while making HOW the
		# shot is played an autonomous golfer decision rather than a fixed stock shot.
		var intent_choice: Dictionary = shot_intent_strategy.choose_for_candidate(golfer, candidate, current_surface)
		for key in intent_choice.keys():
			candidate[key] = intent_choice[key]

		candidate = _execution_option(candidate)
		decision_ranked.append(candidate)

	decision_ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("decision_expected_strokes", INF)) < float(b.get("decision_expected_strokes", INF))
	)

	return {
		"chosen": decision_ranked[0].duplicate(true),
		"evaluated": decision_ranked
	}


func _personality_strategy_adjustment(golfer: Node, candidate: Dictionary) -> Dictionary:
	# Course Management answers "what do I think this shot will cost?" Personality
	# answers "how willing am I to accept variance around that expectation?" This
	# keeps objective golf scoring and perceived scoring separate from temperament.
	var perceived: float = float(candidate.get("perceived_expected_strokes_to_hole", INF))
	var risk_tolerance: float = 50.0
	if golfer != null:
		var raw_risk = golfer.get("risk_tolerance")
		if raw_risk != null:
			risk_tolerance = clamp(float(raw_risk), 0.0, 100.0)

	var hazard_probability: float = clamp(float(candidate.get("hazard_probability", 0.0)), 0.0, 1.0)
	var ob_probability: float = clamp(float(candidate.get("out_of_bounds_probability", 0.0)), 0.0, 1.0)
	var strike_miss_probability: float = clamp(float(candidate.get("strike_miss_probability", 0.0)), 0.0, 1.0)
	var downside_exposure: float = clamp(hazard_probability + ob_probability + strike_miss_probability * 0.35, 0.0, 1.0)

	# At 50 risk tolerance, personality is neutral. A cautious golfer adds up to
	# roughly three tenths of a stroke to highly volatile choices; a very bold
	# golfer discounts that same volatility by a similar amount. The adjustment is
	# intentionally modest: it can break close strategic ties, but should not make
	# obviously poor shots attractive merely because a golfer is reckless.
	var risk_preference: float = (50.0 - risk_tolerance) / 50.0
	var personality_risk_adjustment: float = downside_exposure * risk_preference * 0.30
	var decision_expected: float = perceived + personality_risk_adjustment

	return {
		"risk_tolerance": risk_tolerance,
		"downside_exposure": downside_exposure,
		"personality_risk_adjustment": personality_risk_adjustment,
		"decision_expected_strokes": decision_expected
	}


func _execution_option(candidate: Dictionary) -> Dictionary:
	var result: Dictionary = candidate.duplicate(true)
	var hazard_probability: float = float(result.get("hazard_probability", 0.0))
	var ob_probability: float = float(result.get("out_of_bounds_probability", 0.0))
	var failure_probability: float = clamp(hazard_probability + ob_probability, 0.0, 0.95)

	result["name"] = "EMERGENT_%s" % str(result.get("club_id", "CLUB"))
	result["target_position"] = result.get("target", Vector3.ZERO)
	result["reward"] = 0.0
	result["risk"] = failure_probability * 100.0
	result["is_aggressive"] = false
	result["model_success_chance"] = (1.0 - failure_probability) * 100.0
	result["assessment"] = {}
	return result

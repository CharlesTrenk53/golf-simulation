extends RefCounted

# POC-13D: autonomous course-strategy selector.
# ---------------------------------------------
# Feasibility comes from ClubCandidateGenerator. Objective scoring comes from
# ClubCandidateEvaluator. CourseManagementModel converts objective consequences
# into the golfer's perceived consequences. The chosen shot is the candidate the
# golfer believes minimizes expected strokes to hole out.

const ClubCandidateGenerator = preload("res://simulation/club_candidate_generator.gd")
const ClubCandidateEvaluator = preload("res://simulation/club_candidate_evaluator.gd")
const CourseManagementModel = preload("res://simulation/course_management_model.gd")

var generator = ClubCandidateGenerator.new()
var evaluator = ClubCandidateEvaluator.new()
var course_management = CourseManagementModel.new()


func use_literal_yardages(enabled: bool = true) -> void:
	generator.bag.use_literal_yardages(enabled)
	evaluator.bag.use_literal_yardages(enabled)


func choose(golfer: Node, state) -> Dictionary:
	var candidates: Array = generator.generate(golfer, state)
	if candidates.is_empty():
		return {"chosen": {}, "evaluated": []}

	var objective_ranked: Array = evaluator.evaluate_all(golfer, state, candidates)
	var perceived_ranked: Array = []
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
		candidate = _execution_option(candidate)
		perceived_ranked.append(candidate)

	perceived_ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("perceived_expected_strokes_to_hole", INF)) < float(b.get("perceived_expected_strokes_to_hole", INF))
	)

	return {
		"chosen": perceived_ranked[0].duplicate(true),
		"evaluated": perceived_ranked
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

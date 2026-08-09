extends RefCounted

const ShotSituation = preload("res://simulation/shot_situation.gd")
const ShotRequirements = preload("res://simulation/shot_requirements.gd")
const GolferAssessment = preload("res://simulation/golfer_assessment.gd")
const GolferStateContext = preload("res://simulation/golfer_state_context.gd")
const RecentPerformanceContext = preload("res://simulation/recent_performance_context.gd")
const GolferMemoryComfort = preload("res://simulation/golfer_memory_comfort.gd")
const ShotCommitment = preload("res://simulation/shot_commitment.gd")
const FutureStateEstimator = preload("res://simulation/future_state_estimator.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")

var requirements_model = ShotRequirements.new()
var assessment_model = GolferAssessment.new()
var commitment_model = ShotCommitment.new()
var future_state_model = FutureStateEstimator.new()
var state_context = GolferStateContext.new()
var recent_performance = RecentPerformanceContext.new()
var memory_comfort = GolferMemoryComfort.new()
var bag = GolfBag.new()
var initialized_for_golfer := false

func initialize(golfer: Node) -> void:
	recent_performance.initialize_from_golfer(golfer)
	memory_comfort.initialize_from_golfer(golfer, bag.all_clubs())
	initialized_for_golfer = true

func assess_options(golfer: Node, state, options: Array, hazards: Array = []) -> Array:
	if not initialized_for_golfer:
		initialize(golfer)
	var assessed: Array = []
	for source_option in options:
		var option: Dictionary = source_option.duplicate(true)
		var situation = ShotSituation.new(
			state.ball_position,
			option.get("target_position", state.hole_position),
			state.surface_name(),
			state.current_lie_quality,
			hazards
		)
		var perception = assessment_model.perceive(golfer, situation)
		var requirements = requirements_model.derive(situation)
		var club: Dictionary = option.get("club", {})
		var capability = assessment_model.assess_club(golfer, situation, requirements, club, state_context)

		var performance = recent_performance.performance_modifier_for(club) if not club.is_empty() else {"carry_factor": 1.0, "dispersion_factor": 1.0, "directional_bias": 0.0}
		capability["expected_carry"] = float(capability.get("expected_carry", 0.0)) * float(performance["carry_factor"])
		capability["expected_dispersion"] = float(capability.get("expected_dispersion", 0.0)) * float(performance["dispersion_factor"])

		var shot_form = String(option.get("shot_form", "NORMAL")).to_upper()
		var comfort = memory_comfort.comfort_for(golfer, club, shot_form) if not club.is_empty() else {"comfort": float(golfer.confidence), "certainty": 35.0, "baseline": float(golfer.confidence), "long_term": float(golfer.confidence), "recent": float(golfer.confidence), "current_round": float(golfer.confidence)}
		var recent_confidence = recent_performance.confidence_for(golfer, club, situation.surface, state_context.pressure) if not club.is_empty() else float(golfer.confidence)
		var comfort_certainty = float(comfort.get("certainty", 35.0))
		var comfort_influence = lerp(0.15, 0.45, comfort_certainty / 100.0)
		var confidence = recent_confidence * (1.0 - comfort_influence) + float(comfort.get("comfort", recent_confidence)) * comfort_influence

		var miss = commitment_model.assess_miss_consequences(situation, option.get("target_position", state.hole_position), max(float(capability.get("expected_dispersion", 2.0)), 2.0))
		var willingness = assessment_model.assess_willingness(golfer, capability, option, state_context)
		var raw_willingness = float(willingness.get("willingness_score", 50.0))
		var comfort_adjustment = (float(comfort.get("comfort", 50.0)) - 50.0) * 0.20
		willingness["pre_comfort_willingness"] = raw_willingness
		willingness["comfort_adjustment"] = comfort_adjustment
		willingness["willingness_score"] = clamp(raw_willingness + comfort_adjustment, 0.0, 100.0)

		var model_success = float(option.get("model_success_chance", 50.0))
		var comfort_believed_success = clamp(model_success + (float(comfort.get("comfort", 50.0)) - 50.0) * 0.12, 0.0, 100.0)
		option["comfort_believed_success_chance"] = comfort_believed_success

		var base_reward = float(option.get("reward", 0.0))
		var base_risk = float(option.get("risk", 0.0))
		var capability_score = float(capability.get("capability_score", 0.0))
		var willingness_score = float(willingness.get("willingness_score", 0.0))
		var perceived_distance = float(perception.get("distance", situation.distance_to_target))
		var distance_error = abs(perceived_distance - situation.effective_playing_distance())
		var miss_cost = float(miss.get("worst_cost", 0.0))
		var confidence_shift = (confidence - 50.0) * 0.08
		var assessment_reward = base_reward + (capability_score - 50.0) * 0.18 + (willingness_score - 50.0) * 0.12 + confidence_shift
		var assessment_risk = base_risk + miss_cost * 0.16 + distance_error * 1.5 + max(0.0, 50.0 - capability_score) * 0.22
		option["reward"] = assessment_reward
		option["risk"] = assessment_risk
		option["shot_form"] = shot_form
		option["assessment"] = {
			"world_distance": situation.effective_playing_distance(),
			"perceived_distance": perceived_distance,
			"judgment_skill": perception.get("judgment_skill", 50.0),
			"requirements": requirements,
			"capability": capability,
			"specific_confidence": confidence,
			"recent_confidence": recent_confidence,
			"comfort": comfort,
			"comfort_believed_success_chance": comfort_believed_success,
			"shot_form": shot_form,
			"miss_consequences": miss,
			"willingness": willingness,
			"performance": performance,
			"base_reward": base_reward,
			"base_risk": base_risk,
			"assessed_reward": assessment_reward,
			"assessed_risk": assessment_risk
		}
		var future_state = future_state_model.estimate(golfer, state, option)
		option["assessment"]["future_state"] = future_state
		option["expected_strokes_remaining"] = future_state["expected_strokes_remaining"]
		option["expected_remaining_distance"] = future_state["expected_remaining_distance"]
		assessed.append(option)
	return assessed

func prepare_execution(golfer: Node, chosen: Dictionary, decision_gap: float = 0.0) -> Dictionary:
	var assessment: Dictionary = chosen.get("assessment", {})
	var capability: Dictionary = assessment.get("capability", {})
	var specific_confidence = float(assessment.get("specific_confidence", golfer.confidence))
	var mental_state = {
		"focus": state_context.focus,
		"nervous": state_context.nervous,
		"fear": 0.0,
		"frustrated": state_context.frustration
	}
	return commitment_model.assess_commitment(golfer, capability, specific_confidence, mental_state, decision_gap)

func record_result(chosen: Dictionary, result: Dictionary) -> void:
	var club: Dictionary = chosen.get("club", {})
	if club.is_empty():
		return
	var target: Vector3 = result.get("target_position", Vector3.ZERO)
	var landing: Vector3 = result.get("landing_position", target)
	var start: Vector3 = result.get("start_position", Vector3.ZERO)
	var direction = target - start
	direction.y = 0.0
	if direction.length() <= 0.001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var lateral = Vector3(-direction.z, 0.0, direction.x)
	var error = landing - target
	var lateral_error = error.dot(lateral)
	var distance_error = error.dot(direction)
	var outcome = String(result.get("outcome", "SUCCESS"))
	var execution_quality = String(result.get("execution_quality", "ACCEPTABLE"))
	var execution_score = float(result.get("execution_score", -1.0))
	var shot_form = String(chosen.get("shot_form", chosen.get("assessment", {}).get("shot_form", "NORMAL")))
	recent_performance.record_shot(club, outcome, execution_quality, lateral_error, distance_error)
	memory_comfort.record_experience(club, shot_form, execution_quality, outcome, execution_score)

func start_new_round() -> void:
	memory_comfort.start_new_round()

func set_physical_condition(values: Dictionary) -> void:
	state_context.set_physical_condition(values)

func set_mental_state(values: Dictionary) -> void:
	state_context.set_mental_state(values)

func set_strategic_context(values: Dictionary) -> void:
	state_context.set_strategic_context(values)

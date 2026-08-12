extends RefCounted

const ShotIntentCatalog = preload("res://simulation/shot_intent_catalog.gd")
const ShotFlightModel = preload("res://simulation/shot_flight_model.gd")
const ShotmakingProficiencyModel = preload("res://simulation/shotmaking_proficiency_model.gd")

# POC-14E: choose HOW to hit an already-feasible club + target candidate.
# The POC-13 club/target architecture remains authoritative. This layer asks which
# feasible intent best fits that plan after considering predicted flight, landing
# needs, hazard pressure, and this golfer's ability to execute the requested shot.

var catalog = ShotIntentCatalog.new()
var flight_model = ShotFlightModel.new()
var proficiency_model = ShotmakingProficiencyModel.new()


func choose_for_candidate(golfer: Node, candidate: Dictionary, surface: String) -> Dictionary:
	var club: Dictionary = candidate.get("club", {})
	if club.is_empty():
		return {"chosen_intent": {}, "evaluated_intents": []}

	var intents: Array[Dictionary] = catalog.intents_for(club, surface)
	if intents.is_empty():
		return {"chosen_intent": {}, "evaluated_intents": []}

	# The club+target candidate is already a concrete distance plan. When a stock
	# club carries farther than the selected target, execution must honor the
	# candidate's shortened forward distance rather than silently reverting to the
	# club's full carry. This keeps POC-14 HOW execution faithful to POC-13 WHAT/WHERE.
	var baseline_carry: float = float(candidate.get("stock_forward_distance", candidate.get("intended_distance", candidate.get("effective_carry", 0.0))))
	var baseline_dispersion: float = float(candidate.get("dispersion", club.get("dispersion", 1.0)))
	var expected_surface: String = str(candidate.get("expected_surface", "FAIRWAY")).to_upper()
	var hazard_count: int = int(candidate.get("corridor_hazard_count", 0))
	var evaluated: Array[Dictionary] = []

	for intent in intents:
		var predicted: Dictionary = flight_model.predict(club, intent, baseline_carry, baseline_dispersion)
		var proficiency: Dictionary = proficiency_model.assess(golfer, club, intent, predicted)
		var score: float = _decision_cost(candidate, predicted, proficiency, expected_surface, hazard_count)
		evaluated.append({
			"intent": intent.duplicate(true),
			"predicted_flight": predicted,
			"proficiency": proficiency,
			"intent_decision_cost": score
		})

	evaluated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("intent_decision_cost", INF)) < float(b.get("intent_decision_cost", INF))
	)

	return {
		"chosen_intent": evaluated[0]["intent"].duplicate(true),
		"chosen_predicted_flight": evaluated[0]["predicted_flight"].duplicate(true),
		"chosen_proficiency": evaluated[0]["proficiency"].duplicate(true),
		"intent_decision_cost": float(evaluated[0]["intent_decision_cost"]),
		"evaluated_intents": evaluated
	}


func _decision_cost(candidate: Dictionary, predicted: Dictionary, proficiency: Dictionary, expected_surface: String, hazard_count: int) -> float:
	var intended_distance: float = maxf(1.0, float(candidate.get("stock_forward_distance", candidate.get("intended_distance", 1.0))))
	var carry: float = float(predicted.get("carry_yards", intended_distance))
	var carry_fit: float = absf(carry - intended_distance) / intended_distance
	var dispersion: float = float(predicted.get("dispersion_yards", 1.0)) * float(proficiency.get("expected_dispersion_multiplier", 1.0))
	var dispersion_cost: float = dispersion / maxf(30.0, intended_distance)
	var reliability: float = float(proficiency.get("execution_reliability", 0.5))
	var difficulty: float = float(predicted.get("execution_difficulty", 0.0))

	# Stock distance fit and execution reliability are the default anchors. Special
	# shots only win when their flight characteristics solve a real course problem.
	var cost: float = carry_fit * 2.00
	cost += dispersion_cost * 0.85
	cost += (1.0 - reliability) * 0.52
	cost += difficulty * 0.18

	# Hazard corridors value tighter predictable execution. This is not a named
	# "safe shot" bonus; the pressure comes from geometry already attached to the
	# candidate by POC-13.
	if hazard_count > 0:
		cost += dispersion_cost * minf(float(hazard_count), 3.0) * 0.55

	# A green landing values stopping power: less rollout and a steeper/high flight
	# can outweigh a small carry sacrifice. Fairway/rough plans remain primarily
	# distance-and-dispersion problems.
	if expected_surface == "GREEN":
		var rollout_ratio: float = float(predicted.get("rollout_yards", 0.0)) / maxf(1.0, carry)
		var apex_factor: float = float(predicted.get("apex_factor", 1.0))
		cost += rollout_ratio * 1.10
		cost -= clampf(apex_factor - 1.0, 0.0, 0.75) * 0.14
	elif expected_surface in ["FAIRWAY", "TEE"]:
		var total: float = float(predicted.get("total_yards", carry))
		if total < intended_distance * 0.88:
			cost += (intended_distance * 0.88 - total) / intended_distance

	return cost

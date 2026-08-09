extends RefCounted

const GolfBag = preload("res://simulation/golf_bag.gd")

var bag = GolfBag.new()

# PERCEPTION: returns what this golfer believes about the objective situation.
# The first implementation is deliberately conservative: perception errors are
# small, skill-linked and deterministic enough to test. Later weather/green-
# reading systems can expand this without changing the API.
func perceive(golfer: Node, situation) -> Dictionary:
	var judgment = _judgment_skill(golfer)
	var error_scale = (100.0 - judgment) / 100.0
	var distance_bias = (50.0 - float(golfer.confidence)) * 0.02 * error_scale
	var perceived_distance = max(0.0, situation.effective_playing_distance() + distance_bias)
	var perceived_wind = situation.wind_speed * (1.0 - 0.20 * error_scale)
	var perceived_lie_quality = clamp(situation.lie_quality + (0.5 - error_scale) * 0.04, 0.0, 1.0)
	return {
		"distance": perceived_distance,
		"wind_speed": perceived_wind,
		"surface": situation.surface,
		"lie_quality": perceived_lie_quality,
		"hazards": situation.hazards.duplicate(true),
		"judgment_skill": judgment
	}

# ABILITY/CAPABILITY MATCH: asks whether the golfer can execute a candidate
# club/shot solution to the requirements. This is distinct from willingness.
func assess_club(golfer: Node, situation, requirements: Dictionary, club: Dictionary) -> Dictionary:
	if club.is_empty():
		return {"feasible": false, "capability_score": 0.0, "distance_margin": -999.0}
	var carry = bag.effective_carry(club, golfer, situation.surface, situation.lie_quality)
	var dispersion = bag.effective_dispersion(club, golfer, situation.surface, situation.lie_quality)
	var shot_ability = float(golfer.get_shot_ability(int(club["shot_type"])))
	var distance_margin = carry - float(requirements["required_carry"])
	var distance_fit = clamp(70.0 + distance_margin * 5.0, 0.0, 100.0)
	var accuracy_capacity = clamp(100.0 - dispersion * 8.0, 0.0, 100.0)
	var lie_capacity = _lie_skill(golfer, situation.surface)
	var accuracy_match = 100.0 - max(0.0, float(requirements["accuracy_demand"]) - accuracy_capacity)
	var lie_match = 100.0 - max(0.0, float(requirements["lie_demand"]) - lie_capacity)
	var capability_score = clamp(
		distance_fit * 0.30
		+ accuracy_match * 0.25
		+ lie_match * 0.20
		+ shot_ability * 0.25,
		0.0,
		100.0
	)
	var feasible = distance_margin >= -2.0 and capability_score >= 45.0
	return {
		"feasible": feasible,
		"capability_score": capability_score,
		"expected_carry": carry,
		"expected_dispersion": dispersion,
		"distance_margin": distance_margin,
		"shot_ability": shot_ability,
		"accuracy_capacity": accuracy_capacity,
		"lie_capacity": lie_capacity
	}

func rank_clubs(golfer: Node, situation, requirements: Dictionary) -> Array:
	var ranked: Array = []
	for club in bag.clubs_for_surface(situation.surface):
		var assessment = assess_club(golfer, situation, requirements, club)
		ranked.append({"club": club, "assessment": assessment})
	ranked.sort_custom(func(a, b): return float(a["assessment"]["capability_score"]) > float(b["assessment"]["capability_score"]))
	return ranked

func _judgment_skill(golfer: Node) -> float:
	# Temporary bridge until perception/judgment becomes a full golfer skill set.
	# Responsiveness to experience provides a reasonable current differentiator.
	return clamp(45.0 + float(golfer.responsiveness_to_experience) * 0.45, 0.0, 100.0)

func _lie_skill(golfer: Node, surface: String) -> float:
	match surface:
		"TEE", "FAIRWAY": return float(golfer.approach)
		"ROUGH": return float(golfer.approach) * 0.90
		"BUNKER": return float(golfer.short_game)
		"GREEN": return float(golfer.putting)
	return float(golfer.approach)

extends RefCounted

# POC-13B/C: expected-strokes evaluation of bag-derived club candidates.
# --------------------------------------------------------------------
# The strategic objective is always to finish the hole in the fewest expected
# strokes. This evaluator first computes an objective scoring consequence, then
# CourseManagementModel converts that truth into the golfer's perceived estimate.
# Decision making can therefore be imperfect without changing the objective of
# golf or hiding personality bonuses inside course geometry.

const GolfBag = preload("res://simulation/golf_bag.gd")
const CourseManagementModel = preload("res://simulation/course_management_model.gd")

var bag = GolfBag.new()
var course_management = CourseManagementModel.new()


func evaluate_all(golfer: Node, state, candidates: Array) -> Array:
	var evaluated: Array = []
	if golfer == null or state == null:
		return evaluated
	for candidate in candidates:
		evaluated.append(evaluate(golfer, state, candidate))
	# The golfer acts on perceived expected strokes. Objective expected strokes are
	# retained beside them so diagnostics can measure decision quality/calibration.
	evaluated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("perceived_expected_strokes_to_hole", INF)) < float(b.get("perceived_expected_strokes_to_hole", INF))
	)
	return evaluated


func evaluate(golfer: Node, state, candidate: Dictionary) -> Dictionary:
	var result: Dictionary = candidate.duplicate(true)
	var expected_surface: String = str(candidate.get("expected_surface", "UNKNOWN")).to_upper()
	var remaining_before: float = max(0.0, state.remaining_distance())
	var remaining_after: float = max(0.0, float(candidate.get("remaining_after_target", remaining_before)))
	var dispersion: float = max(0.0, float(candidate.get("dispersion", 0.0)))
	var surface_execution_penalty: float = clamp(float(candidate.get("surface_execution_penalty", 0.0)), 0.0, 1.0)
	var hazard_count: int = int(candidate.get("corridor_hazard_count", 0))
	var out_of_bounds: bool = bool(candidate.get("out_of_bounds", false))
	var ability: float = clamp(float(golfer.get_shot_ability(int(candidate.get("shot_type", 1)))), 0.0, 100.0)

	# Objective consequence model. These values describe the simulator's best
	# current estimate of what the shot costs, regardless of who is considering it.
	var dispersion_factor: float = clamp(dispersion / 12.0, 0.0, 1.5)
	var ability_error_factor: float = lerp(1.35, 0.55, ability / 100.0)
	var hazard_probability: float = clamp(float(hazard_count) * 0.12 * dispersion_factor * ability_error_factor, 0.0, 0.75)
	var ob_probability: float = 0.0
	if out_of_bounds:
		ob_probability = clamp(0.35 * max(0.45, dispersion_factor) * ability_error_factor, 0.0, 0.80)

	# A physically awkward club/surface combination can cost strokes even when the
	# center-line target itself avoids a named hazard. This captures thin/heavy/offline
	# strikes such as driver from the deck without banning the shot outright.
	var strike_miss_probability: float = clamp(surface_execution_penalty * 0.42 * ability_error_factor, 0.0, 0.45)
	var expected_strike_cost: float = strike_miss_probability * 0.55

	var expected_penalty_strokes: float = hazard_probability * 1.0 + ob_probability * 1.0
	var expected_recovery_strokes: float = hazard_probability * 0.55 + ob_probability * 0.85 + expected_strike_cost
	var continuation_strokes: float = _expected_strokes_from_landing(golfer, expected_surface, remaining_after)
	var true_expected_strokes: float = 1.0 + expected_penalty_strokes + expected_recovery_strokes + continuation_strokes

	result["hazard_probability"] = hazard_probability
	result["out_of_bounds_probability"] = ob_probability
	result["strike_miss_probability"] = strike_miss_probability
	result["expected_strike_cost"] = expected_strike_cost
	result["expected_penalty_strokes"] = expected_penalty_strokes
	result["expected_recovery_strokes"] = expected_recovery_strokes
	result["expected_continuation_strokes"] = continuation_strokes
	result["expected_strokes_to_hole"] = true_expected_strokes
	result["true_expected_strokes_to_hole"] = true_expected_strokes

	var perception: Dictionary = course_management.perception_for(golfer, result, candidate, remaining_before)
	for key in perception.keys():
		result[key] = perception[key]

	# Convenience scores only; strokes remain the authoritative decision currency.
	result["objective_strategy_score"] = -true_expected_strokes
	result["strategy_score"] = -float(result.get("perceived_expected_strokes_to_hole", true_expected_strokes))
	return result


func _expected_strokes_from_landing(golfer: Node, surface: String, remaining_distance: float) -> float:
	if remaining_distance <= 2.0:
		return 1.0
	if surface == "GREEN":
		return _expected_putts(remaining_distance, golfer)

	var base: float = _distance_baseline(remaining_distance)
	match surface:
		"FAIRWAY": base += 0.00
		"TEE": base += 0.05
		"ROUGH": base += 0.28
		"BUNKER": base += 0.62
		"WATER": base += 1.35
		"UNKNOWN": base += 0.40

	# A good leave is represented as strokes saved because the next real club fits
	# the distance well, not as an arbitrary reward bonus.
	if surface == "FAIRWAY" or surface == "ROUGH" or surface == "TEE":
		var lie_quality: float = 1.0
		if surface == "FAIRWAY":
			lie_quality = 0.95
		elif surface == "ROUGH":
			lie_quality = 0.72
		var best_gap: float = INF
		for club in bag.clubs_for_surface(surface):
			if str(club.get("id", "")) == "PUTTER":
				continue
			var carry: float = bag.effective_carry(club, golfer, surface, lie_quality)
			best_gap = min(best_gap, abs(carry - remaining_distance))
		if not is_inf(best_gap):
			base -= clamp((22.0 - best_gap) / 22.0, 0.0, 1.0) * 0.16

	return max(1.0, base)


func _distance_baseline(distance: float) -> float:
	# Provisional POC expectation curve expressed in strokes. Earlier POC-13 builds
	# used hard buckets, which made materially different clubs tie whenever their
	# leaves landed inside the same distance band. Interpolating between the same
	# anchors preserves the calibration scale while allowing a 15-yard improvement
	# in position to actually matter to strategy selection.
	if distance <= 2.0:
		return 1.0
	if distance <= 25.0:
		return lerp(1.0, 1.75, clamp((distance - 2.0) / 23.0, 0.0, 1.0))
	if distance <= 75.0:
		return lerp(1.75, 2.15, (distance - 25.0) / 50.0)
	if distance <= 125.0:
		return lerp(2.15, 2.45, (distance - 75.0) / 50.0)
	if distance <= 175.0:
		return lerp(2.45, 2.70, (distance - 125.0) / 50.0)
	if distance <= 225.0:
		return lerp(2.70, 2.95, (distance - 175.0) / 50.0)
	if distance <= 300.0:
		return lerp(2.95, 3.25, (distance - 225.0) / 75.0)
	# Long-hole continuation remains monotonic instead of flattening completely.
	return 3.25 + clamp((distance - 300.0) / 200.0, 0.0, 1.0) * 0.40


func _expected_putts(distance: float, golfer: Node) -> float:
	var putting: float = clamp(float(golfer.get_shot_ability(3)), 0.0, 100.0)
	var skill_adjustment: float = lerp(0.20, -0.12, putting / 100.0)
	var base: float
	if distance <= 3.0:
		base = 1.08
	elif distance <= 8.0:
		base = 1.35
	elif distance <= 20.0:
		base = 1.72
	elif distance <= 40.0:
		base = 1.98
	else:
		base = 2.18
	return max(1.0, base + skill_adjustment)

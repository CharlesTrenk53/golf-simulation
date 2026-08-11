extends RefCounted

# POC-13C: Course Management
# --------------------------
# Course management is decision calibration, not shotmaking ability and not
# personality. It governs how closely the golfer's perceived scoring consequence
# matches the simulator's objective expected-strokes estimate.
#
# A permanent golfer property can override the derived value later. For this POC,
# career shot exposure supplies a believable default: experienced golfers tend to
# read strategic consequences more accurately, while inexperienced golfers are
# more prone to optimistic/aggressive miscalibration.

const REFERENCE_CAREER_SHOTS := 30000.0


func rating_for(golfer: Node) -> float:
	if golfer == null:
		return 50.0

	# Allow tests/future golfer models to provide an explicit value without
	# coupling this strategy module to one concrete Golfer implementation.
	if golfer.has_meta("course_management"):
		return clamp(float(golfer.get_meta("course_management")), 0.0, 100.0)

	var total_experience: float = 0.0
	var experience = golfer.get("career_shot_experience")
	if experience is Dictionary:
		for value in experience.values():
			total_experience += max(0.0, float(value))

	# Square-root growth gives large gains early, then diminishing returns as
	# experience accumulates. It is provisional calibration, not a hard ceiling.
	return clamp(sqrt(total_experience / REFERENCE_CAREER_SHOTS) * 100.0, 20.0, 95.0)


func perception_for(golfer: Node, objective: Dictionary, candidate: Dictionary, remaining_before: float) -> Dictionary:
	var management: float = rating_for(golfer)
	var inexperience: float = 1.0 - management / 100.0
	var true_expected: float = float(objective.get("expected_strokes_to_hole", INF))
	var penalty_cost: float = float(objective.get("expected_penalty_strokes", 0.0))
	var recovery_cost: float = float(objective.get("expected_recovery_strokes", 0.0))
	var intended_distance: float = float(candidate.get("intended_distance", 0.0))
	var progress_fraction: float = 0.0
	if remaining_before > 0.001:
		progress_fraction = clamp(intended_distance / remaining_before, 0.0, 1.0)

	# Lower-management golfers tend to underprice penalties/recovery and slightly
	# overvalue raw advancement. This produces an aggressive tendency without a
	# hidden "reckless" bonus: they choose the shot because they believe it scores
	# better, not because the objective of golf changed.
	var underestimated_bad_outcomes: float = (penalty_cost * 0.70 + recovery_cost * 0.55) * inexperience
	var advancement_optimism: float = progress_fraction * 0.22 * inexperience
	var perceived_expected: float = max(1.0, true_expected - underestimated_bad_outcomes - advancement_optimism)

	return {
		"course_management": management,
		"calibration_gap": perceived_expected - true_expected,
		"perceived_expected_strokes_to_hole": perceived_expected,
		"underestimated_bad_outcomes": underestimated_bad_outcomes,
		"advancement_optimism": advancement_optimism
	}

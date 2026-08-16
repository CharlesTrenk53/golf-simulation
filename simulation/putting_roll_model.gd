extends RefCounted

# POC-15C: convert an executed putting line + delivered pace into a deterministic
# roll outcome. Reading and execution remain immutable upstream inputs.
#
# Sign convention inherited from PuttingReadModel:
# - positive slope_across_percent makes the ball break toward negative lateral
#   space, so the read compensates with a positive aim offset;
# - negative cross slope behaves symmetrically.

const CUP_RADIUS_FEET: float = 0.177
const MAX_CAPTURE_PAST_FEET: float = 3.0


func resolve(planned_putt: Dictionary, executed_putt: Dictionary) -> Dictionary:
	var hole_distance: float = maxf(0.0, float(planned_putt.get("distance_feet", 0.0)))
	var cross_slope: float = float(planned_putt.get("slope_across_percent", 0.0))
	var along_slope: float = float(planned_putt.get("slope_along_percent", 0.0))
	var green_speed: float = clampf(float(planned_putt.get("green_speed", 10.0)), 7.0, 14.0)
	var actual_aim: float = float(executed_putt.get("actual_aim_offset_feet", 0.0))
	var delivered_distance: float = maxf(0.0, float(executed_putt.get("actual_distance_feet", 0.0)))

	# The read model adds/subtracts these terms to intended delivered distance.
	# Removing them here turns delivered pace back into realized physical travel,
	# allowing a correct uphill/downhill/green-speed read to cancel naturally.
	var slope_distance_effect: float = along_slope * hole_distance * 0.045
	var speed_distance_effect: float = (10.0 - green_speed) * hole_distance * 0.012
	var rolled_distance: float = maxf(0.0, delivered_distance - slope_distance_effect - speed_distance_effect)

	# Cross-slope break mirrors the read model's compensation magnitude. Using the
	# hole distance keeps a correct deterministic read centered at the cup; line
	# execution error then survives as genuine residual miss.
	var speed_factor: float = lerpf(0.80, 1.25, (green_speed - 7.0) / 7.0)
	var distance_factor: float = pow(maxf(hole_distance, 1.0) / 10.0, 1.35)
	var break_feet: float = -cross_slope * distance_factor * speed_factor * 0.42
	var final_lateral_feet: float = actual_aim + break_feet

	# Cup capture is circular. Requiring the ball center to reach the cup center
	# allowed a putt to finish geometrically inside the cup radius while remaining
	# live, which could create repeated "0.0 yd" putts. For a valid line, compute
	# the front edge of the circular capture area along the ball's travel path.
	var lateral_abs: float = absf(final_lateral_feet)
	var on_capture_line: bool = lateral_abs <= CUP_RADIUS_FEET
	var capture_half_chord: float = 0.0
	if on_capture_line:
		capture_half_chord = sqrt(maxf(0.0, CUP_RADIUS_FEET * CUP_RADIUS_FEET - final_lateral_feet * final_lateral_feet))
	var cup_entry_distance: float = maxf(0.0, hole_distance - capture_half_chord)
	var reached_capture_zone: bool = on_capture_line and rolled_distance >= cup_entry_distance
	var reached_hole: bool = rolled_distance >= hole_distance
	var distance_past_hole: float = maxf(0.0, rolled_distance - hole_distance)
	var distance_short_of_hole: float = maxf(0.0, hole_distance - rolled_distance)
	var already_in_cup: bool = hole_distance <= CUP_RADIUS_FEET
	var capture_pace: bool = already_in_cup or distance_past_hole <= MAX_CAPTURE_PAST_FEET
	var holed: bool = already_in_cup or (reached_capture_zone and capture_pace)

	var finish_distance_from_hole: float
	if holed:
		finish_distance_from_hole = 0.0
	else:
		finish_distance_from_hole = sqrt(
			pow(rolled_distance - hole_distance, 2.0) + pow(final_lateral_feet, 2.0)
		)

	var miss_side: String = "CENTER"
	if final_lateral_feet > CUP_RADIUS_FEET:
		miss_side = "POSITIVE"
	elif final_lateral_feet < -CUP_RADIUS_FEET:
		miss_side = "NEGATIVE"

	return {
		"putt_signature": str(planned_putt.get("signature", "")),
		"hole_distance_feet": hole_distance,
		"delivered_distance_feet": delivered_distance,
		"rolled_distance_feet": rolled_distance,
		"break_feet": break_feet,
		"actual_aim_offset_feet": actual_aim,
		"final_lateral_feet": final_lateral_feet,
		"distance_short_of_hole_feet": distance_short_of_hole,
		"distance_past_hole_feet": distance_past_hole,
		"finish_distance_from_hole_feet": finish_distance_from_hole,
		"miss_side": miss_side,
		"reached_hole": reached_hole,
		"reached_capture_zone": reached_capture_zone,
		"cup_entry_distance_feet": cup_entry_distance,
		"already_in_cup": already_in_cup,
		"capture_line": on_capture_line,
		"capture_pace": capture_pace,
		"holed": holed
	}

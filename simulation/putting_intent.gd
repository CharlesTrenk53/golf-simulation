extends RefCounted

# POC-15 keeps putting separate from full-shot ShotIntent. A putt is planned by
# start line and pace rather than trajectory/shape/swing technique.

var aim_offset_feet: float = 0.0
var pace_feet_past_hole: float = 1.5
var intended_distance_feet: float = 0.0
var signature: String = ""


func _init(
	p_aim_offset_feet: float = 0.0,
	p_pace_feet_past_hole: float = 1.5,
	p_intended_distance_feet: float = 0.0
) -> void:
	aim_offset_feet = p_aim_offset_feet
	pace_feet_past_hole = max(0.0, p_pace_feet_past_hole)
	intended_distance_feet = max(0.0, p_intended_distance_feet)
	signature = _build_signature()


func as_dictionary() -> Dictionary:
	return {
		"aim_offset_feet": aim_offset_feet,
		"pace_feet_past_hole": pace_feet_past_hole,
		"intended_distance_feet": intended_distance_feet,
		"signature": signature
	}


func _build_signature() -> String:
	return "AIM_%.2f|PACE_%.2f|DIST_%.2f" % [aim_offset_feet, pace_feet_past_hole, intended_distance_feet]

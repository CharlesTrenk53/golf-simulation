extends RefCounted

# POC-20A: Round Context
# ----------------------
# Converts RoundState into objective, golfer-independent context facts.
# It deliberately does not apply pressure, fatigue, confidence, or strategy
# modifiers. Later POC-20 slices can interpret these facts without coupling
# scorekeeping to golfer behavior.

const RECENT_HOLE_WINDOW := 3


func build(round_state) -> Dictionary:
	if round_state == null or round_state.course == null:
		return {}

	var rows: Array = round_state.scorecard()
	var completed_rows: Array = []
	for row in rows:
		if bool(row.get("completed", false)):
			completed_rows.append(row)

	var recent_rows: Array = []
	var recent_start := maxi(0, completed_rows.size() - RECENT_HOLE_WINDOW)
	for index in range(recent_start, completed_rows.size()):
		recent_rows.append(completed_rows[index])

	var recent_total_to_par := 0
	var recent_scores_to_par: Array[int] = []
	for row in recent_rows:
		var value := int(row.get("score_to_par", 0))
		recent_total_to_par += value
		recent_scores_to_par.append(value)

	var total_holes := rows.size()
	var holes_completed := completed_rows.size()
	var recent_average_to_par := 0.0
	if not recent_rows.is_empty():
		recent_average_to_par = float(recent_total_to_par) / float(recent_rows.size())

	var last_hole_to_par := 0
	if not completed_rows.is_empty():
		last_hole_to_par = int(completed_rows[-1].get("score_to_par", 0))

	return {
		"holes_completed": holes_completed,
		"holes_remaining": round_state.remaining_holes(),
		"total_holes": total_holes,
		"round_progress": float(holes_completed) / float(total_holes) if total_holes > 0 else 0.0,
		"strokes_played": round_state.total_strokes(),
		"par_played": round_state.par_played(),
		"score_to_par": round_state.score_to_par(),
		"last_hole_to_par": last_hole_to_par,
		"recent_holes_count": recent_rows.size(),
		"recent_total_to_par": recent_total_to_par,
		"recent_average_to_par": recent_average_to_par,
		"recent_scores_to_par": recent_scores_to_par,
		"under_par_holes": _count_relative_results(completed_rows, -1),
		"par_holes": _count_relative_results(completed_rows, 0),
		"over_par_holes": _count_relative_results(completed_rows, 1),
		"current_hole_number": round_state.current_hole_number(),
		"round_complete": round_state.complete
	}


func _count_relative_results(rows: Array, direction: int) -> int:
	var count := 0
	for row in rows:
		var value := int(row.get("score_to_par", 0))
		if direction < 0 and value < 0:
			count += 1
		elif direction == 0 and value == 0:
			count += 1
		elif direction > 0 and value > 0:
			count += 1
	return count

extends RefCounted

# POC-12B: Round State
# --------------------
# Tracks progression and scoring across an arbitrary CourseDefinition. This
# object deliberately does not execute golf shots; POC-12C will feed completed
# hole scores into it.

var course = null
var tee_id: String = "default"
var current_hole_index: int = 0
var hole_scores: Array[int] = []
var complete: bool = false


func _init(course_definition = null, selected_tee_id: String = "default") -> void:
	course = course_definition
	tee_id = selected_tee_id
	if course != null:
		for _index in range(course.hole_count()):
			hole_scores.append(-1)
		complete = course.hole_count() == 0
	else:
		complete = true


func current_hole():
	if complete or course == null:
		return null
	return course.hole_at(current_hole_index)


func current_hole_number() -> int:
	var hole = current_hole()
	if hole == null:
		return 0
	return int(hole.hole_number)


func holes_completed() -> int:
	var count: int = 0
	for score in hole_scores:
		if score >= 0:
			count += 1
	return count


func record_current_hole(strokes: int) -> bool:
	if complete or course == null:
		return false
	if strokes <= 0:
		return false
	if current_hole_index < 0 or current_hole_index >= hole_scores.size():
		return false
	if hole_scores[current_hole_index] >= 0:
		return false

	hole_scores[current_hole_index] = strokes
	if current_hole_index + 1 >= course.hole_count():
		complete = true
	else:
		current_hole_index += 1
	return true


func score_for_hole(hole_number: int) -> int:
	if course == null:
		return -1
	var index: int = hole_number - 1
	if index < 0 or index >= hole_scores.size():
		return -1
	return hole_scores[index]


func total_strokes() -> int:
	var total: int = 0
	for score in hole_scores:
		if score >= 0:
			total += score
	return total


func par_played() -> int:
	if course == null:
		return 0
	var total: int = 0
	for index in range(hole_scores.size()):
		if hole_scores[index] >= 0:
			var hole = course.hole_at(index)
			if hole != null:
				total += int(hole.par)
	return total


func score_to_par() -> int:
	return total_strokes() - par_played()


func remaining_holes() -> int:
	if course == null:
		return 0
	return max(0, course.hole_count() - holes_completed())


func scorecard() -> Array:
	var rows: Array = []
	if course == null:
		return rows
	for index in range(course.hole_count()):
		var hole = course.hole_at(index)
		var strokes: int = hole_scores[index]
		rows.append({
			"hole_number": int(hole.hole_number),
			"hole_name": str(hole.hole_name),
			"par": int(hole.par),
			"yardage": float(hole.tee_yardage(tee_id)),
			"strokes": strokes,
			"score_to_par": strokes - int(hole.par) if strokes >= 0 else 0,
			"completed": strokes >= 0
		})
	return rows


func snapshot() -> Dictionary:
	return {
		"course_id": str(course.course_id) if course != null else "",
		"tee_id": tee_id,
		"current_hole_index": current_hole_index,
		"current_hole_number": current_hole_number(),
		"holes_completed": holes_completed(),
		"remaining_holes": remaining_holes(),
		"total_strokes": total_strokes(),
		"par_played": par_played(),
		"score_to_par": score_to_par(),
		"complete": complete,
		"scorecard": scorecard()
	}

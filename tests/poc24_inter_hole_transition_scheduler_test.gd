extends SceneTree
const I=preload("res://simulation/inter_hole_transition_scheduler.gd")
func _init()->void:
 var s=I.new()
 var e=s.schedule_transition("follow","lead",1,2,600.0,645.0)
 assert(bool(e.get("waited_for_group_ahead",false)))
 assert(is_equal_approx(float(e.get("wait_seconds",0.0)),45.0))
 assert(s.due_transitions(644.99).is_empty())
 assert(s.due_transitions(645.01).size()==1)
 print("POC-24H INTER-HOLE CATCH-UP WAIT SCHEDULING PASSED")
 quit(0)

extends SceneTree
const C=preload("res://simulation/course_definition.gd")
const T=preload("res://simulation/spacing_aware_timed_course_controller.gd")
const G=preload("res://scenes/golfer.gd")
func _init()->void:
 var c=T.new();assert(c.configure(C.load_json("res://data/courses/poc12_proving_course.json")))
 var lead:Array=[]
 for _i in range(4): lead.append(_g(G.GolferProfile.CAREFUL_CARL))
 assert(c.add_group("lead",lead));assert(c.add_group("follow",[_g(G.GolferProfile.WILD_BILL)]))
 assert(bool(c.release_next_group().get("released",false)))
 var lead1:Dictionary=c.start_group_current_hole("lead",101);assert(bool(lead1.get("started",false)))
 var release:Dictionary=lead1.get("tee_release",{});assert(bool(release.get("scheduled",false)))
 var release_time:float=float(release.get("release_time_seconds",0.0));var lead1_finish:float=float(lead1.get("finish_time_seconds",0.0));assert(release_time<lead1_finish)
 c.advance_time(release_time-c.current_time_seconds+0.01);assert(c.traffic.groups_on_hole(1)==["lead","follow"])
 var follow1:Dictionary=c.start_group_current_hole("follow",211);assert(bool(follow1.get("started",false)))
 c.advance_time(lead1_finish-c.current_time_seconds+0.01);assert(c.traffic.group_hole("lead")==2)
 var lead2:Dictionary=c.start_group_current_hole("lead",301);assert(bool(lead2.get("started",false)))
 var follow1_finish:float=float(follow1.get("finish_time_seconds",0.0));var lead2_finish:float=float(lead2.get("finish_time_seconds",0.0));assert(follow1_finish<lead2_finish)
 c.advance_time(follow1_finish-c.current_time_seconds+0.01)
 var blocked:Dictionary=c.blocked_transition("follow");assert(not blocked.is_empty());assert(bool(blocked.get("waited_for_group_ahead",false)));assert(float(blocked.get("wait_seconds",0.0))>0.0);assert(c.traffic.group_hole("follow")==0)
 var transition_time:float=float(blocked.get("transition_time_seconds",0.0));assert(is_equal_approx(transition_time,lead2_finish))
 c.advance_time(transition_time-c.current_time_seconds-0.01);assert(c.traffic.group_hole("follow")==0)
 var due:Array=c.advance_time(0.02);assert(c.traffic.group_hole("follow")==2);assert(c.traffic.group_hole("lead")==3)
 var saw_transition:=false
 for event in due:
  if str(event.get("type",""))=="INTER_HOLE_TRANSITION" and bool(event.get("entered",false)): saw_transition=true
 assert(saw_transition)
 print("POC24_CATCHUP_SUMMARY follow_arrival=%.1f lead_clear=%.1f wait=%.1f"%[follow1_finish,lead2_finish,float(blocked.get("wait_seconds",0.0))]);print("POC-24H EMERGENT INTER-HOLE CATCH-UP WAIT PASSED");quit(0)
func _g(p:int):
 var g=G.new();g.profile=p;g.apply_profile();get_root().add_child(g);return g

extends SceneTree
const C=preload("res://simulation/course_definition.gd")
const T=preload("res://simulation/spacing_aware_timed_course_controller.gd")
const G=preload("res://scenes/golfer.gd")
func _init()->void:
 var c=T.new();assert(c.configure(C.load_json("res://data/courses/poc12_proving_course.json")))
 assert(c.add_group("lead",[_g(G.GolferProfile.CAREFUL_CARL)]));assert(c.add_group("follow",[_g(G.GolferProfile.WILD_BILL)]))
 assert(bool(c.release_next_group().get("released",false)))
 var lead:Dictionary=c.start_group_current_hole("lead",101);assert(bool(lead.get("started",false)))
 var release:Dictionary=lead.get("tee_release",{});assert(bool(release.get("scheduled",false)))
 var release_time:float=float(release.get("release_time_seconds",0.0));var lead_finish:float=float(lead.get("finish_time_seconds",0.0));assert(release_time>0.0 and release_time<lead_finish)
 assert(c.traffic.groups_on_hole(1)==["lead"]);assert(not bool(c.release_next_group().get("released",true)))
 assert(c.advance_time(release_time-0.01).is_empty());assert(c.traffic.groups_on_hole(1)==["lead"])
 var due:Array=c.advance_time(0.02);assert(due.size()==1);assert(str(due[0].get("type",""))=="TEE_RELEASE");assert(bool(due[0].get("released",false)))
 assert(c.current_time_seconds<lead_finish);assert(c.traffic.groups_on_hole(1)==["lead","follow"]);assert(c.traffic.group_ahead("follow")=="lead")
 var follow:Dictionary=c.start_group_current_hole("follow",211);assert(bool(follow.get("started",false)));assert(not c.active_event("lead").is_empty() and not c.active_event("follow").is_empty())
 print("POC24_CONCURRENT_SUMMARY release=%.1f lead_finish=%.1f follow_finish=%.1f"%[release_time,lead_finish,float(follow.get("finish_time_seconds",0.0))]);print("POC-24G SAFE SAME-HOLE CONCURRENT TRAFFIC PASSED");quit(0)
func _g(p:int):
 var g=G.new();g.profile=p;g.apply_profile();get_root().add_child(g);return g

extends SceneTree
const C=preload("res://simulation/course_definition.gd")
const T=preload("res://simulation/timed_course_traffic_controller.gd")
const G=preload("res://scenes/golfer.gd")
func _init()->void:
 var c=T.new();assert(c.configure(C.load_json("res://data/courses/poc12_proving_course.json")))
 assert(c.add_group("lead",[_g(G.GolferProfile.CAREFUL_CARL)]));assert(c.add_group("follow",[_g(G.GolferProfile.WILD_BILL)]))
 assert(bool(c.release_next_group().get("released",false)))
 var e:Dictionary=c.start_group_current_hole("lead",101);assert(bool(e.get("started",false)))
 assert(c.living_course.population.group_by_id("lead").current_hole_number()==2);assert(c.traffic.occupant_for_hole(1)=="lead")
 assert(not bool(c.release_next_group().get("released",true)))
 var d:float=float(e.get("finish_time_seconds",0.0));assert(c.advance_time(d-0.01).is_empty());assert(c.traffic.occupant_for_hole(1)=="lead")
 var done:Array=c.advance_time(0.02);assert(done.size()==1);assert(c.traffic.occupant_for_hole(1)=="");assert(c.traffic.occupant_for_hole(2)=="lead")
 assert(bool(c.release_next_group().get("released",false)));assert(c.traffic.occupant_for_hole(1)=="follow")
 print("POC-24D SIMULATED EVENT CLOCK PASSED");quit(0)
func _g(p:int):
 var g=G.new();g.profile=p;g.apply_profile();get_root().add_child(g);return g

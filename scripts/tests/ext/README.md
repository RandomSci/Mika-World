Plug-in test modes for milestone_k_test.gd: `--mktest=<mode>` loads `res://scripts/tests/ext/<mode>.gd` and awaits
its `static func run(t)` (t = the MilestoneKTest node; use t._wait(s), t._check(ok, msg), t.main, t._lake_setup(...),
t._cine_setup(stage), t._cine_cut(...), t._force_luna_l1(), t._hold_all()). One file per feature.

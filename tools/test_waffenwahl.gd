extends SceneTree
## Prüft die Vorwahl der höchsten Waffe zum Laufbeginn.
## godot --headless --path . --script tools/test_waffenwahl.gd
func _fall(frei: Array, stufen: Dictionary, laser: String, rakete: String) -> bool:
	var s := Schiff.new()
	s.waffen_frei.assign(frei)
	s.waffen_stufen = stufen
	s.beste_vorwaehlen()
	var ok := s.laser_wahl == laser and s.rakete_wahl == rakete
	print("%s frei %s stufen %s → %s + %s (soll %s + %s)" % ["ok  " if ok else "FEHL", frei, stufen, s.laser_wahl, s.rakete_wahl, laser, rakete])
	s.free()
	return ok

func _init() -> void:
	var ok := true
	ok = _fall(["zwilling", "zielsuch"], {}, "zwilling", "zielsuch") and ok
	ok = _fall(["zwilling", "streu", "plasma", "zielsuch", "smart"], {"streu": 4, "plasma": 2, "zielsuch": 3}, "streu", "zielsuch") and ok
	ok = _fall(["zwilling", "vulkan", "zielsuch", "mega"], {"zwilling": 5, "vulkan": 5, "mega": 2}, "vulkan", "mega") and ok
	ok = _fall(["zwilling", "streu", "zielsuch"], {"plasma": 5}, "streu", "zielsuch") and ok   # gestuft, aber nicht frei
	print("WAFFENWAHL-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))
	quit(0 if ok else 1)

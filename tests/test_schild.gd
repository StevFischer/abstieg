extends SceneTree
## Schild-Aufladen: godot --headless --path . --script tests/test_schild.gd


func _init() -> void:
	var s = load("res://scripts/Schiff.gd").new()
	var fehler := 0
	var dt := 1.0 / 60.0
	s.schild_max = 100.0
	s.schild = 100.0
	s.treffer(60.0)                       # 40 übrig, Pause beginnt
	for i in int(4.9 / dt):
		s.schild_laden(dt)
	fehler += _pruef("in der Pause (4,9 s) kein Laden", is_equal_approx(s.schild, 40.0), s.schild)
	for i in int(10.1 / dt):
		s.schild_laden(dt)
	# 5 s Pause sind durch, danach ~10 s Laden mit 1,5/s → ~55
	fehler += _pruef("nach 15 s etwa 55", absf(s.schild - 55.0) < 1.0, s.schild)
	s.treffer(5.0)
	var vorher: float = s.schild
	for i in int(3.0 / dt):
		s.schild_laden(dt)
	fehler += _pruef("neuer Treffer unterbricht", is_equal_approx(s.schild, vorher), s.schild)
	for i in int(120.0 / dt):
		s.schild_laden(dt)
	fehler += _pruef("nie über das Maximum", is_equal_approx(s.schild, 100.0), s.schild)
	s.treffer(500.0)                      # tot
	for i in int(20.0 / dt):
		s.schild_laden(dt)
	fehler += _pruef("nach dem Tod kein Laden", s.schild == 0.0, s.schild)
	s.free()
	print("Schild-Test: 5 Prüfungen, %d Fehler" % fehler)
	quit(1 if fehler > 0 else 0)


func _pruef(name: String, ok: bool, wert: float) -> int:
	print("%s  %s (Schild %.2f)" % ["ok    " if ok else "FEHLER", name, wert])
	return 0 if ok else 1

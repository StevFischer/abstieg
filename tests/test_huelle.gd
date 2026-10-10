extends SceneTree
## Schild vor Hülle: godot --headless --path . --script tests/test_huelle.gd


func _init() -> void:
	var s = load("res://scripts/Schiff.gd").new()
	var tot := [false]
	s.gestorben.connect(func(): tot[0] = true)
	var fehler := 0
	var dt := 1.0 / 60.0
	s.schild = 100.0
	s.huelle = 100.0
	s.treffer(60.0)
	fehler += _pruef("60 Schaden nur am Schild", s.schild == 40.0 and s.huelle == 100.0, s)
	s.treffer(70.0)
	fehler += _pruef("Überschuss 30 geht auf die Hülle", s.schild == 0.0 and s.huelle == 70.0, s)
	fehler += _pruef("lebt bei Schild 0", not tot[0] and s.aktiv, s)
	for i in int(60.0 / dt):
		s.schild_laden(dt)
	fehler += _pruef("nach 60 s: Schild lädt, Hülle nicht", s.schild > 50.0 and s.huelle == 70.0, s)
	fehler += _pruef("Reparatur +30", s.aufnehmen("reparatur", 30) and s.huelle == 100.0, s)
	fehler += _pruef("Reparatur bei voller Hülle wird nicht aufgenommen", not s.aufnehmen("reparatur", 30), s)
	s.treffer(s.schild + 99.0)
	fehler += _pruef("Hülle 1: noch am Leben", not tot[0] and is_equal_approx(s.huelle, 1.0), s)
	s.treffer(5.0)
	fehler += _pruef("Hülle 0: zerstört", tot[0] and not s.aktiv and s.huelle == 0.0, s)
	s.free()
	print("Hüllen-Test: 8 Prüfungen, %d Fehler" % fehler)
	quit(1 if fehler > 0 else 0)


func _pruef(name: String, ok: bool, s) -> int:
	print("%s  %s (Schild %.1f, Hülle %.1f)" % ["ok    " if ok else "FEHLER", name, s.schild, s.huelle])
	return 0 if ok else 1

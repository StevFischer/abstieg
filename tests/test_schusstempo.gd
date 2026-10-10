extends SceneTree
## Gegnergeschosse: godot --headless --path . --script tests/test_schusstempo.gd


func _init() -> void:
	var G = load("res://scripts/Gegner.gd")
	var fehler := 0
	print("Typ         T1    T3    T6    T10   T13   T30  (m/s, vorher überall 38)")
	for typ in ["jaeger", "geschuetz", "waechter"]:
		var zeile := "%-10s" % typ
		var werte := []
		for t in [1, 3, 6, 10, 13, 30]:
			var g = G.new()
			g.einrichten(typ, t)
			werte.append(g.schuss_tempo)
			zeile += "  %4.1f" % g.schuss_tempo
			g.free()
		print(zeile)
		if werte[0] > 20.0:
			fehler += 1
			print("FEHLER %s auf Tiefe 1 zu schnell" % typ)
		for i in range(1, werte.size()):
			if werte[i] < werte[i - 1]:
				fehler += 1
				print("FEHLER %s wird mit der Tiefe langsamer" % typ)
		if werte[-1] > werte[0] * 2.0 + 0.01 or werte[-1] > 38.0:
			fehler += 1
			print("FEHLER %s über der Obergrenze" % typ)
	# Reichweite: in 6 s Lebenszeit muss auch der langsamste Schuss die Sichtweite (55 m) schaffen
	var g2 = G.new()
	g2.einrichten("waechter", 1)
	if g2.schuss_tempo * 6.0 < 55.0:
		fehler += 1
		print("FEHLER langsamster Schuss erreicht die Sichtweite nicht: %.0f m" % (g2.schuss_tempo * 6.0))
	g2.free()
	print("Schusstempo-Test: %d Fehler" % fehler)
	quit(1 if fehler > 0 else 0)

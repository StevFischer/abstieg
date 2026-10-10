extends SceneTree
## Generator-Test ohne Szene: godot --headless --path . --script tests/test_gen.gd
## Prüft über viele Saaten und Tiefen, dass jede Mine zusammenhängt, der Reaktor
## erreichbar ist und verschiedene Saaten verschiedene Grundrisse geben.


func _init() -> void:
	var Gen = load("res://scripts/LevelGen.gd")
	var Th = load("res://scripts/Themen.gd")
	var fehler := 0
	var pruefungen := 0
	var abdruecke := {}
	var laeufe := 0
	var t0 := Time.get_ticks_msec()
	var tiefen := range(1, 41) + [60, 100, 250, 1000]
	for tiefe in tiefen:
		for saat in range(1, 26):
			var g = Gen.new()
			g.erzeuge(saat * 7919 + tiefe * 31, tiefe)
			laeufe += 1
			pruefungen += 5
			if g.raeume.size() < 5:
				fehler += 1
				print("FEHLER zu wenige Räume: Tiefe %d Saat %d → %d" % [tiefe, saat, g.raeume.size()])
			if g.reaktor_raum == g.start_raum:
				fehler += 1
				print("FEHLER Reaktor im Startraum: Tiefe %d Saat %d" % [tiefe, saat])
			if g.pfad(g.mittelzelle(g.start_raum), g.mittelzelle(g.reaktor_raum)).is_empty():
				fehler += 1
				print("FEHLER Reaktor nicht erreichbar: Tiefe %d Saat %d" % [tiefe, saat])
			if g.erreichbare(g.mittelzelle(0)).size() != g.zellen.size():
				fehler += 1
				print("FEHLER Mine zerfällt: Tiefe %d Saat %d" % [tiefe, saat])
			if g.fluchtzeit() < 8.0 or g.fluchtzeit() > 300.0:
				fehler += 1
				print("FEHLER Fluchtzeit %.0f: Tiefe %d Saat %d" % [g.fluchtzeit(), tiefe, saat])
			if g.ist_boss_tiefe(tiefe):
				pruefungen += 1
				if g.raeume[g.reaktor_raum].groesse != g.BOSS_RAUM:
					fehler += 1
					print("FEHLER Boss-Tiefe %d Saat %d ohne Bossraum (Reaktorraum %s)" % [tiefe, saat, g.raeume[g.reaktor_raum].groesse])
			abdruecke[g.fingerabdruck()] = true
	pruefungen += 1
	if abdruecke.size() != laeufe:
		fehler += 1
		print("FEHLER nur %d verschiedene Grundrisse bei %d Läufen" % [abdruecke.size(), laeufe])
	# Gleiche Saat, gleiche Mine — sonst ist ein Fehler nicht nachstellbar.
	var a = Gen.new()
	a.erzeuge(42, 7)
	var b = Gen.new()
	b.erzeuge(42, 7)
	pruefungen += 1
	if a.fingerabdruck() != b.fingerabdruck():
		fehler += 1
		print("FEHLER gleiche Saat gibt verschiedene Minen")
	# Themen für jede Tiefe vorhanden, ohne Obergrenze
	for t in [1, 3, 4, 15, 16, 31, 100, 1000]:
		pruefungen += 1
		var th: Dictionary = Th.fuer_tiefe(t)
		if not th.has("name") or not (th.wand_hell is Color):
			fehler += 1
			print("FEHLER Thema für Tiefe %d" % t)
	var ms := Time.get_ticks_msec() - t0
	print("Generator-Test: %d Prüfungen, %d Fehler, %d Minen in %d ms (%.1f ms je Mine), %d verschiedene Grundrisse" % [
		pruefungen, fehler, laeufe, ms, float(ms) / laeufe, abdruecke.size()])
	quit(1 if fehler > 0 else 0)

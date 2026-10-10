extends SceneTree
## Misst über viele Saaten und Tiefen, wie groß der Reaktorraum ausfällt.
## godot --headless --path . --script tools/reaktor_mass.gd
func _init() -> void:
	var zu_klein := 0
	var n := 0
	var groessen := {}
	for tiefe in range(1, 31):
		for s in 40:
			var g := LevelGen.new()
			g.erzeuge(tiefe * 1000 + s, tiefe)
			var r: Dictionary = g.raeume[g.reaktor_raum]
			var gr: Vector3i = r.groesse
			var soll := LevelGen.BOSS_RAUM if LevelGen.ist_boss_tiefe(tiefe) else LevelGen.REAKTOR_RAUM
			n += 1
			if gr.x < soll.x or gr.y < soll.y or gr.z < soll.z:
				zu_klein += 1
			var k := str(gr)
			groessen[k] = groessen.get(k, 0) + 1
	print("Reaktorraum: %d von %d Levels kleiner als Soll" % [zu_klein, n])
	var keys := groessen.keys(); keys.sort_custom(func(a, b): return groessen[a] > groessen[b])
	for k in keys.slice(0, 12):
		print("  %s: %d" % [k, groessen[k]])
	quit(0)

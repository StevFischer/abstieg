class_name Themen
extends RefCounted
## Fünf Minentypen, je drei Tiefen lang. Danach beginnt die Reihe von vorn,
## mit verschobenem Farbton, damit sich auch Tiefe 40 anders anfühlt als Tiefe 1.

const LISTE := [
	{"name": "Mondmine", "fels": true, "zacken": 0.8, "metall": 0.15,
		"wand_dunkel": Color(0.16, 0.13, 0.10), "wand_hell": Color(0.56, 0.47, 0.37),
		"boden_dunkel": Color(0.18, 0.18, 0.20), "boden_hell": Color(0.52, 0.52, 0.55),
		"decke": Color(0.30, 0.27, 0.23), "lichter": [Color(1.0, 0.84, 0.6), Color(1.0, 0.6, 0.28)],
		"nebel": Color(0.07, 0.055, 0.04), "umgebung": Color(0.40, 0.33, 0.26), "kern": Color(1.0, 0.5, 0.1)},
	{"name": "Eisstollen", "fels": true, "zacken": 0.9, "metall": 0.05,
		"wand_dunkel": Color(0.10, 0.16, 0.24), "wand_hell": Color(0.62, 0.78, 0.90),
		"boden_dunkel": Color(0.15, 0.18, 0.22), "boden_hell": Color(0.48, 0.55, 0.62),
		"decke": Color(0.25, 0.32, 0.40), "lichter": [Color(0.55, 0.85, 1.0), Color(0.8, 0.95, 1.0)],
		"nebel": Color(0.04, 0.07, 0.11), "umgebung": Color(0.28, 0.38, 0.50), "kern": Color(0.2, 0.8, 1.0)},
	# Schmelzwerk 2026-10-10 aufgehellt (Stev: „gefällt mir sehr gut, aber zu dunkel“; gemessen 18/255):
	# hellere Platten, wärmeres statt tiefrotes Lampenlicht, Lampen ×1,5 und mehr Umgebungslicht.
	{"name": "Schmelzwerk", "fels": false, "zacken": 0.0, "metall": 0.55, "licht": 1.5, "umgebung_kraft": 0.6,
		"wand_dunkel": Color(0.26, 0.13, 0.08), "wand_hell": Color(0.74, 0.46, 0.30),
		"boden_dunkel": Color(0.20, 0.17, 0.15), "boden_hell": Color(0.58, 0.52, 0.47),
		"decke": Color(0.32, 0.22, 0.16), "lichter": [Color(1.0, 0.55, 0.30), Color(1.0, 0.78, 0.45)],
		"nebel": Color(0.12, 0.05, 0.03), "umgebung": Color(0.62, 0.38, 0.26), "kern": Color(1.0, 0.25, 0.05)},
	# Kristallader 2026-10-10 aufgehellt (Stev: „ist dunkel“; gemessen 24/255): wie beim Schmelzwerk
	# hellere Flächen, Lampen ×1,5, mehr Umgebungslicht — Farbton bleibt violett/türkis.
	{"name": "Kristallader", "fels": true, "zacken": 1.0, "metall": 0.25, "licht": 1.5, "umgebung_kraft": 0.55,
		"wand_dunkel": Color(0.18, 0.10, 0.26), "wand_hell": Color(0.70, 0.52, 0.88),
		"boden_dunkel": Color(0.19, 0.16, 0.23), "boden_hell": Color(0.55, 0.50, 0.64),
		"decke": Color(0.30, 0.22, 0.40), "lichter": [Color(1.0, 0.55, 0.95), Color(0.55, 0.95, 1.0)],
		"nebel": Color(0.08, 0.05, 0.12), "umgebung": Color(0.50, 0.38, 0.62), "kern": Color(0.9, 0.3, 1.0)},
	{"name": "Reaktorebene", "fels": false, "zacken": 0.0, "metall": 0.6,
		"wand_dunkel": Color(0.10, 0.14, 0.11), "wand_hell": Color(0.45, 0.55, 0.46),
		"boden_dunkel": Color(0.12, 0.13, 0.12), "boden_hell": Color(0.42, 0.46, 0.42),
		"decke": Color(0.18, 0.22, 0.19), "lichter": [Color(0.45, 1.0, 0.5), Color(0.9, 1.0, 0.7)],
		"nebel": Color(0.03, 0.07, 0.04), "umgebung": Color(0.26, 0.40, 0.28), "kern": Color(0.3, 1.0, 0.3)},
]


static func fuer_tiefe(tiefe: int) -> Dictionary:
	var i := ((tiefe - 1) / 3) % LISTE.size()
	var runde := (tiefe - 1) / (3 * LISTE.size())
	var th: Dictionary = LISTE[i].duplicate(true)
	if runde > 0:
		th.name = "%s %d" % [th.name, runde + 1]
		for k in th.keys():
			if th[k] is Color:
				th[k] = _verschieben(th[k], runde)
			elif th[k] is Array:
				var neu := []
				for c in th[k]:
					neu.append(_verschieben(c, runde))
				th[k] = neu
	return th


static func _verschieben(c: Color, runde: int) -> Color:
	var n := c
	n.h = fmod(c.h + 0.09 * runde, 1.0)
	return n

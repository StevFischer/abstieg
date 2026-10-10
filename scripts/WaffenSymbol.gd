class_name WaffenSymbol
extends Control
## Symbol einer Waffe, als Vektorgrafik gezeichnet — scharf in jeder Größe, in der Waffenfarbe.
## Laser: Zwilling (zwei Bolzen), Streufeuer (Fächer), Vulkan (Kette), Plasma (Kugel).
## Raketen: Zielsuch (Rakete mit Bogenspur), Streurakete (drei Raketen), Smart (Rakete mit Splittern),
## Mega (große Rakete mit Explosionsstern).
## Aufrüstungen: Schildgenerator (Schild mit Wellen), Panzerung (Platte mit Nieten), Triebwerk (Düse mit
## Flamme), Raketenschacht (Magazin mit drei Raketen) — IDs mit Vorsilbe "auf_".
## Zum Einbetten (Hangar) als Control; im HUD über die statische Funktion zeichnen().

var waffe := "zwilling"
var farbe := Color.WHITE


func _init(p_waffe := "zwilling", p_farbe := Color.WHITE) -> void:
	waffe = p_waffe
	farbe = p_farbe
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	zeichnen(self, Rect2(Vector2.ZERO, size), waffe, farbe)


static func _rakete(ci: CanvasItem, spitze: Vector2, richtung: Vector2, l: float, b: float, f: Color) -> void:
	var r := richtung.normalized()
	var n := Vector2(-r.y, r.x)
	var hinten := spitze - r * l
	ci.draw_colored_polygon(PackedVector2Array([
		spitze, spitze - r * l * 0.3 + n * b, hinten + n * b, hinten - n * b, spitze - r * l * 0.3 - n * b]), f)
	# Leitwerk
	ci.draw_colored_polygon(PackedVector2Array([hinten + n * b, hinten + n * b * 2.0 - r * b, hinten + r * b * 1.5 + n * b]), f)
	ci.draw_colored_polygon(PackedVector2Array([hinten - n * b, hinten - n * b * 2.0 - r * b, hinten + r * b * 1.5 - n * b]), f)
	# Flamme
	ci.draw_colored_polygon(PackedVector2Array([hinten + n * b * 0.6, hinten - r * b * 2.2, hinten - n * b * 0.6]),
		Color(1.0, 0.75, 0.3, f.a))


static func zeichnen(ci: CanvasItem, r: Rect2, id: String, f: Color) -> void:
	var m := r.get_center()
	var s := minf(r.size.x, r.size.y) / 2.0     # halbe Kantenlänge
	var dick := maxf(2.0, s * 0.16)
	match id:
		"zwilling":
			for x in [-0.32, 0.32]:
				ci.draw_line(m + Vector2(x * s, s * 0.75), m + Vector2(x * s, -s * 0.75), f, dick, true)
				ci.draw_circle(m + Vector2(x * s, -s * 0.75), dick * 0.9, f)
		"streu":
			for w in [-28.0, 0.0, 28.0]:
				var d := Vector2(0, -1).rotated(deg_to_rad(w))
				ci.draw_line(m + Vector2(0, s * 0.8), m + Vector2(0, s * 0.8) + d * s * 1.55, f, dick * 0.8, true)
				ci.draw_circle(m + Vector2(0, s * 0.8) + d * s * 1.55, dick * 0.8, f)
		"vulkan":
			for i in 5:
				var y := s * 0.85 - i * s * 0.42
				ci.draw_line(m + Vector2(0, y), m + Vector2(0, y - s * 0.22), f, dick * 0.9, true)
			ci.draw_arc(m, s * 0.95, deg_to_rad(110), deg_to_rad(250), 12, Color(f, f.a * 0.5), dick * 0.5, true)
			ci.draw_arc(m, s * 0.95, deg_to_rad(-70), deg_to_rad(70), 12, Color(f, f.a * 0.5), dick * 0.5, true)
		"plasma":
			ci.draw_circle(m, s * 0.55, f)
			ci.draw_circle(m - Vector2(s, s) * 0.15, s * 0.18, Color(1, 1, 1, f.a * 0.7))
			ci.draw_arc(m, s * 0.85, 0, TAU, 24, Color(f, f.a * 0.55), dick * 0.5, true)
		"zielsuch":
			ci.draw_arc(m + Vector2(s * 0.45, s * 0.55), s * 0.75, deg_to_rad(180), deg_to_rad(265), 10, Color(f, f.a * 0.55), dick * 0.5, true)
			_rakete(ci, m + Vector2(s * 0.55, -s * 0.75), Vector2(0.45, -1), s * 1.2, s * 0.17, f)
		"streu_r":
			for w in [-25.0, 0.0, 25.0]:
				var d := Vector2(0, -1).rotated(deg_to_rad(w))
				_rakete(ci, m + Vector2(0, s * 0.7) + d * s * 1.6, d, s * 0.9, s * 0.12, f)
		"smart":
			_rakete(ci, m + Vector2(-s * 0.15, -s * 0.05), Vector2(0.6, -1), s * 1.0, s * 0.16, f)
			for i in 5:
				var d := Vector2(0, -1).rotated(deg_to_rad(-60 + i * 30))
				ci.draw_circle(m + Vector2(s * 0.25, -s * 0.55) + d * s * 0.45, dick * 0.55, f)
		"auf_schild":
			var pkt := PackedVector2Array()
			for i in 17:      # Wappenschild: oben gerade, unten spitz
				var t := float(i) / 16.0
				var x := lerpf(-0.75, 0.75, t)
				pkt.append(m + Vector2(x * s, -0.7 * s + 0.08 * s * sin(t * PI)))
			pkt.append(m + Vector2(0.75 * s, 0.05 * s))
			pkt.append(m + Vector2(0, 0.9 * s))
			pkt.append(m + Vector2(-0.75 * s, 0.05 * s))
			ci.draw_colored_polygon(pkt, Color(f, f.a * 0.35))
			pkt.append(pkt[0])
			ci.draw_polyline(pkt, f, dick * 0.7, true)
			for k in 2:
				ci.draw_arc(m + Vector2(0, 0.05 * s), s * (0.25 + 0.2 * k), deg_to_rad(200), deg_to_rad(340), 10, f, dick * 0.45, true)
		"auf_panzerung":
			var platte := Rect2(m - Vector2(0.75, 0.6) * s, Vector2(1.5, 1.2) * s)
			ci.draw_rect(platte, Color(f, f.a * 0.35))
			ci.draw_rect(platte, f, false, dick * 0.7)
			ci.draw_line(m + Vector2(-0.75, 0) * s, m + Vector2(0.75, 0) * s, Color(f, f.a * 0.7), dick * 0.4)
			for p in [Vector2(-0.55, -0.4), Vector2(0.55, -0.4), Vector2(-0.55, 0.4), Vector2(0.55, 0.4)]:
				ci.draw_circle(m + p * s, dick * 0.55, f)
			ci.draw_line(m + Vector2(0, -0.25) * s, m + Vector2(0, 0.25) * s, f, dick * 0.6)
			ci.draw_line(m + Vector2(-0.25, 0) * s, m + Vector2(0.25, 0) * s, f, dick * 0.6)
		"auf_triebwerk":
			ci.draw_colored_polygon(PackedVector2Array([
				m + Vector2(-0.35, -0.85) * s, m + Vector2(0.35, -0.85) * s,
				m + Vector2(0.55, 0.05) * s, m + Vector2(-0.55, 0.05) * s]), Color(f, f.a * 0.6))
			ci.draw_rect(Rect2(m + Vector2(-0.45, -0.95) * s, Vector2(0.9, 0.18) * s), f)
			ci.draw_colored_polygon(PackedVector2Array([
				m + Vector2(-0.45, 0.05) * s, m + Vector2(0.45, 0.05) * s, m + Vector2(0, 0.95) * s]),
				Color(1.0, 0.75, 0.3, f.a))
			ci.draw_colored_polygon(PackedVector2Array([
				m + Vector2(-0.22, 0.05) * s, m + Vector2(0.22, 0.05) * s, m + Vector2(0, 0.6) * s]),
				Color(1.0, 0.95, 0.7, f.a))
		"auf_raketen":
			var kasten := Rect2(m + Vector2(-0.85, 0.15) * s, Vector2(1.7, 0.65) * s)
			ci.draw_rect(kasten, Color(f, f.a * 0.3))
			ci.draw_rect(kasten, f, false, dick * 0.6)
			for x in [-0.5, 0.0, 0.5]:
				_rakete(ci, m + Vector2(x * s, -0.85 * s), Vector2(0, -1), s * 1.1, s * 0.12, f)
		"auf_laserschaden":      # Bolzen mit Verstärkerringen
			ci.draw_line(m + Vector2(0, s * 0.85), m + Vector2(0, -s * 0.85), f, dick * 1.1, true)
			ci.draw_circle(m + Vector2(0, -s * 0.85), dick, f)
			for y in [0.25, -0.2]:
				ci.draw_arc(m + Vector2(0, y * s), s * 0.42, 0, TAU, 20, Color(f, f.a * 0.7), dick * 0.45, true)
		"auf_feuerrate":         # drei Bolzen hintereinander mit Tempostrichen
			for i in 3:
				var y := s * (0.6 - i * 0.6)
				ci.draw_line(m + Vector2(s * 0.1, y + s * 0.2), m + Vector2(s * 0.1, y - s * 0.2), f, dick, true)
				ci.draw_line(m + Vector2(-s * 0.55, y + s * 0.1), m + Vector2(-s * 0.2, y + s * 0.1), Color(f, f.a * 0.5), dick * 0.4)
		"auf_raketenschaden":    # Rakete mit Sprengkopf-Stern
			_rakete(ci, m + Vector2(s * 0.1, -s * 0.2), Vector2(0, -1), s * 1.1, s * 0.2, f)
			for i in 8:
				var d := Vector2(cos(TAU * i / 8.0), sin(TAU * i / 8.0))
				ci.draw_line(m + Vector2(s * 0.1, -s * 0.55) + d * s * 0.2, m + Vector2(s * 0.1, -s * 0.55) + d * s * 0.42, f, dick * 0.4)
		"auf_kritisch":          # Fadenkreuz mit Doppelpunkt
			ci.draw_arc(m, s * 0.7, 0, TAU, 28, f, dick * 0.55, true)
			for r2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				ci.draw_line(m + r2 * s * 0.45, m + r2 * s * 0.95, f, dick * 0.55)
			ci.draw_circle(m + Vector2(-s * 0.13, 0), dick * 0.7, f)
			ci.draw_circle(m + Vector2(s * 0.13, 0), dick * 0.7, f)
		"auf_schildladen":       # Schildbogen mit Pfeil nach oben
			ci.draw_arc(m + Vector2(0, s * 0.35), s * 0.8, deg_to_rad(200), deg_to_rad(340), 16, f, dick * 0.7, true)
			ci.draw_line(m + Vector2(0, s * 0.8), m + Vector2(0, -s * 0.5), f, dick * 0.7)
			ci.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -s * 0.9), m + Vector2(s * 0.3, -s * 0.45), m + Vector2(-s * 0.3, -s * 0.45)]), f)
		"auf_schildpause":       # Uhr
			ci.draw_arc(m, s * 0.75, 0, TAU, 28, f, dick * 0.6, true)
			ci.draw_line(m, m + Vector2(0, -s * 0.5), f, dick * 0.6)
			ci.draw_line(m, m + Vector2(s * 0.35, s * 0.1), f, dick * 0.6)
		"auf_reparatur":         # Schraubenschlüssel als Kreuz mit Ring
			ci.draw_line(m + Vector2(-s * 0.6, s * 0.6), m + Vector2(s * 0.35, -s * 0.35), f, dick * 1.1)
			ci.draw_arc(m + Vector2(s * 0.45, -s * 0.45), s * 0.32, deg_to_rad(-20), deg_to_rad(250), 14, f, dick * 0.8, true)
			ci.draw_line(m + Vector2(-s * 0.15, -s * 0.1), m + Vector2(-s * 0.15, -s * 0.7), Color(f, f.a * 0.6), dick * 0.5)
			ci.draw_line(m + Vector2(-s * 0.45, -s * 0.4), m + Vector2(s * 0.15, -s * 0.4), Color(f, f.a * 0.6), dick * 0.5)
		"auf_notschild":         # Schild mit Ausrufezeichen
			var pk := PackedVector2Array([m + Vector2(-0.7, -0.7) * s, m + Vector2(0.7, -0.7) * s, m + Vector2(0.7, 0.05) * s,
				m + Vector2(0, 0.9) * s, m + Vector2(-0.7, 0.05) * s, m + Vector2(-0.7, -0.7) * s])
			ci.draw_polyline(pk, f, dick * 0.7, true)
			ci.draw_line(m + Vector2(0, -s * 0.45), m + Vector2(0, s * 0.15), f, dick)
			ci.draw_circle(m + Vector2(0, s * 0.42), dick * 0.6, f)
		"auf_erzausbeute":       # Kristall mit Plus
			ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-0.2, -0.85) * s, m + Vector2(0.25, -0.1) * s,
				m + Vector2(-0.2, 0.8) * s, m + Vector2(-0.65, -0.1) * s]), Color(f, f.a * 0.8))
			ci.draw_line(m + Vector2(0.55, -0.6) * s, m + Vector2(0.55, 0.0) * s, f, dick * 0.7)
			ci.draw_line(m + Vector2(0.25, -0.3) * s, m + Vector2(0.85, -0.3) * s, f, dick * 0.7)
		"auf_beutechance":       # Kralle
			for x in [-0.45, 0.0, 0.45]:
				ci.draw_arc(m + Vector2(x * s, s * 0.1), s * 0.3, deg_to_rad(0), deg_to_rad(180), 8, f, dick * 0.6, true)
			ci.draw_line(m + Vector2(0, -s * 0.85), m + Vector2(0, -s * 0.2), f, dick * 0.7)
			ci.draw_line(m + Vector2(-s * 0.75, -s * 0.2), m + Vector2(s * 0.75, -s * 0.2), f, dick * 0.7)
		"auf_magnet":            # Hufeisen
			ci.draw_arc(m + Vector2(0, -s * 0.1), s * 0.55, deg_to_rad(180), deg_to_rad(360), 16, f, dick * 1.2, true)
			for x in [-0.55, 0.55]:
				ci.draw_line(m + Vector2(x * s, -s * 0.1), m + Vector2(x * s, s * 0.7), f, dick * 1.2)
				ci.draw_line(m + Vector2(x * s, s * 0.5), m + Vector2(x * s, s * 0.75), Color(1, 1, 1, f.a * 0.8), dick * 1.2)
		"auf_abschluss":         # Münze/Erzstapel mit Haken
			ci.draw_arc(m, s * 0.75, 0, TAU, 28, f, dick * 0.6, true)
			ci.draw_polyline(PackedVector2Array([m + Vector2(-0.4, 0.0) * s, m + Vector2(-0.1, 0.32) * s, m + Vector2(0.45, -0.35) * s]), f, dick * 0.9, true)
		"auf_nachbrenner":       # Düse mit langer Flamme und Pfeilen
			ci.draw_rect(Rect2(m + Vector2(-0.35, -0.9) * s, Vector2(0.7, 0.55) * s), f)
			ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-0.35, -0.35) * s, m + Vector2(0.35, -0.35) * s, m + Vector2(0, 0.95) * s]),
				Color(1.0, 0.75, 0.3, f.a))
			for x in [-0.7, 0.7]:
				ci.draw_line(m + Vector2(x * s, s * 0.6), m + Vector2(x * s, -s * 0.5), Color(f, f.a * 0.6), dick * 0.45)
		"auf_fluchtzeit":        # Sanduhr
			ci.draw_polyline(PackedVector2Array([m + Vector2(-0.5, -0.8) * s, m + Vector2(0.5, -0.8) * s, m + Vector2(-0.5, 0.8) * s,
				m + Vector2(0.5, 0.8) * s, m + Vector2(-0.5, -0.8) * s]), f, dick * 0.6, true)
			ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-0.3, 0.75) * s, m + Vector2(0.3, 0.75) * s, m + Vector2(0, 0.35) * s]), f)
		"auf_radar":             # Radarschirm mit Kreisen und Punkt
			for k in 3:
				ci.draw_arc(m, s * (0.3 + 0.27 * k), 0, TAU, 24, Color(f, f.a * (1.0 - 0.25 * k)), dick * 0.4, true)
			ci.draw_line(m, m + Vector2(s * 0.6, -s * 0.5), f, dick * 0.5)
			ci.draw_circle(m + Vector2(-s * 0.35, s * 0.3), dick * 0.8, Color(1.0, 0.3, 0.25, f.a))
		"mega":
			var stern := PackedVector2Array()
			for i in 16:
				var rad := s * (0.95 if i % 2 == 0 else 0.55)
				stern.append(m + Vector2(s * 0.3, -s * 0.35) + Vector2(cos(TAU * i / 16.0), sin(TAU * i / 16.0)) * rad * 0.6)
			ci.draw_colored_polygon(stern, Color(f, f.a * 0.45))
			_rakete(ci, m + Vector2(s * 0.25, -s * 0.3), Vector2(0.6, -1), s * 1.3, s * 0.26, f)

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
		"mega":
			var stern := PackedVector2Array()
			for i in 16:
				var rad := s * (0.95 if i % 2 == 0 else 0.55)
				stern.append(m + Vector2(s * 0.3, -s * 0.35) + Vector2(cos(TAU * i / 16.0), sin(TAU * i / 16.0)) * rad * 0.6)
			ci.draw_colored_polygon(stern, Color(f, f.a * 0.45))
			_rakete(ci, m + Vector2(s * 0.25, -s * 0.3), Vector2(0.6, -1), s * 1.3, s * 0.26, f)

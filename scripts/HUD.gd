class_name HUD
extends CanvasLayer
## Cockpitanzeige wie im Descent-Cockpit: Schild (blauer Bogen links) und Hülle (orangener Bogen rechts)
## ums Fadenkreuz, darunter die Waffenleiste (Laser 1–4, Raketen 5–8). Dazu Tiefe, Erz, Ziel, Leitstrahl.

const GRUEN := Color(0.4, 1.0, 0.5)
const GELB := Color(1.0, 0.82, 0.3)
const ROT := Color(1.0, 0.3, 0.25)

const BLAU := Color(0.35, 0.65, 1.0)
const ORANGE := Color(1.0, 0.58, 0.22)
const BOGEN_R := 80.0
const BOGEN_SPANNE := 110.0      ## Grad je Bogen
const KURZ := {"zwilling": "Zwilling", "streu": "Streufeuer", "vulkan": "Vulkan", "plasma": "Plasma",
	"zielsuch": "Zielsuch", "streu_r": "Streurakete", "smart": "Smart", "mega": "Mega"}

var _schiff: Schiff
var _zeit := 0.0
var _tiefe: Label
var _erz: Label
var _status: Label
var _mitteilung: Label
var _aufnahme: Label
var _boss_name: Label
var _boss_balken: ProgressBar
var _aufnahme_tw: Tween
var _abschluss: PanelContainer
var _abschluss_tw: Tween
var _blitz: ColorRect
var _zeichnung: Control

var leit_an := false
var leit_pos := Vector2.ZERO
var leit_rand := false
var leit_richtung := Vector2.ZERO
var leit_text := ""


func _init() -> void:
	layer = 5
	var wurzel := Control.new()
	wurzel.set_anchors_preset(Control.PRESET_FULL_RECT)
	wurzel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wurzel)

	_blitz = ColorRect.new()
	_blitz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blitz.color = Color(1, 0.1, 0.05, 0.0)
	_blitz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wurzel.add_child(_blitz)

	_zeichnung = Control.new()
	_zeichnung.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zeichnung.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zeichnung.draw.connect(_zeichnen)
	wurzel.add_child(_zeichnung)


	_tiefe = _label("", 28, GRUEN)
	_ecke(_tiefe, 0, 0, Vector2(30, 24), Vector2(700, 70))
	wurzel.add_child(_tiefe)
	_erz = _label("", 26, GELB)
	_erz.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ecke(_erz, 1, 0, Vector2(-640, 24), Vector2(-30, 70))
	wurzel.add_child(_erz)
	_status = _label("", 30, GELB)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ecke(_status, 0.5, 0, Vector2(-600, 80), Vector2(600, 130))
	wurzel.add_child(_status)
	_mitteilung = _label("", 54, GELB)
	_mitteilung.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mitteilung.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ecke(_mitteilung, 0.5, 0.5, Vector2(-900, -300), Vector2(900, -80))
	wurzel.add_child(_mitteilung)
	_boss_name = _label("", 24, ROT)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ecke(_boss_name, 0.5, 0, Vector2(-400, 135), Vector2(400, 165))
	wurzel.add_child(_boss_name)
	_boss_balken = _balken(ROT)
	_ecke(_boss_balken, 0.5, 0, Vector2(-400, 170), Vector2(400, 184))
	wurzel.add_child(_boss_balken)
	boss_aus()
	_abschluss = PanelContainer.new()
	var stil := StyleBoxFlat.new()
	stil.bg_color = Color(0.02, 0.03, 0.02, 0.78)
	stil.border_color = Color(GRUEN, 0.7)
	stil.set_border_width_all(2)
	stil.set_corner_radius_all(6)
	stil.content_margin_left = 26
	stil.content_margin_right = 26
	stil.content_margin_top = 14
	stil.content_margin_bottom = 16
	_abschluss.add_theme_stylebox_override("panel", stil)
	_abschluss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_abschluss.visible = false
	_ecke(_abschluss, 0.5, 0.5, Vector2(-300, 120), Vector2(300, 120))
	_abschluss.grow_vertical = Control.GROW_DIRECTION_END
	wurzel.add_child(_abschluss)
	_aufnahme = _label("", 30, GRUEN)
	_aufnahme.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ecke(_aufnahme, 0.5, 0.5, Vector2(-500, 90), Vector2(500, 140))
	wurzel.add_child(_aufnahme)


## Schild links, Hülle rechts: Bögen ums Fadenkreuz, füllen sich von unten nach oben.
func _boegen(m: Vector2) -> void:
	if _schiff == null or not is_instance_valid(_schiff):
		return
	var f := ThemeDB.fallback_font
	var puls := 0.55 + 0.45 * sin(_zeit * 8.0)
	for links in [true, false]:
		var wert: float = _schiff.schild if links else _schiff.huelle
		var maxi: float = _schiff.schild_max if links else _schiff.huelle_max
		var anteil := clampf(wert / maxf(maxi, 1.0), 0.0, 1.0)
		var farbe := BLAU if links else ORANGE
		if anteil < 0.3:
			farbe = Color(ROT, puls)          # knapp: rot und pulsierend
		var mitte_w := 180.0 if links else 0.0
		# Bildschirm-y zeigt nach unten: links ist "unten" bei 180°−55°, rechts bei 0°+55°.
		var unten_w := deg_to_rad(mitte_w + BOGEN_SPANNE / 2.0 * (-1.0 if links else 1.0))
		var oben_w := deg_to_rad(mitte_w - BOGEN_SPANNE / 2.0 * (-1.0 if links else 1.0))
		_zeichnung.draw_arc(m, BOGEN_R, unten_w, oben_w, 40, Color(0, 0, 0, 0.45), 9.0, true)
		_zeichnung.draw_arc(m, BOGEN_R, unten_w, oben_w, 40, Color(farbe, 0.18), 7.0, true)
		if anteil > 0.0:
			_zeichnung.draw_arc(m, BOGEN_R, unten_w, lerpf(unten_w, oben_w, anteil), 40, farbe, 7.0, true)
		# Endkappen als feine Striche
		for w in [unten_w, oben_w]:
			var r := Vector2(cos(w), sin(w))
			_zeichnung.draw_line(m + r * (BOGEN_R - 7), m + r * (BOGEN_R + 7), Color(farbe, 0.6), 1.5)
		var x := m.x - BOGEN_R - 64 if links else m.x + BOGEN_R + 14
		var zahl := "%d" % ceili(wert)
		_zeichnung.draw_string_outline(f, Vector2(x, m.y + 8), zahl, HORIZONTAL_ALIGNMENT_RIGHT if links else HORIZONTAL_ALIGNMENT_LEFT, 50, 24, 5, Color(0, 0, 0, 0.85))
		_zeichnung.draw_string(f, Vector2(x, m.y + 8), zahl, HORIZONTAL_ALIGNMENT_RIGHT if links else HORIZONTAL_ALIGNMENT_LEFT, 50, 24, farbe)
		var name := "SCHILD" if links else "HÜLLE"
		_zeichnung.draw_string_outline(f, Vector2(x, m.y - 18), name, HORIZONTAL_ALIGNMENT_RIGHT if links else HORIZONTAL_ALIGNMENT_LEFT, 50, 12, 4, Color(0, 0, 0, 0.85))
		_zeichnung.draw_string(f, Vector2(x, m.y - 18), name, HORIZONTAL_ALIGNMENT_RIGHT if links else HORIZONTAL_ALIGNMENT_LEFT, 50, 12, Color(farbe, 0.8))


## Waffenleiste unten mittig: oben Laser 1–4, unten Raketen 5–8; gewählte hell umrandet,
## gesperrte (noch nicht gekauft) blass. Rechts daneben der Raketenvorrat.
func _waffenleiste() -> void:
	if _schiff == null or not is_instance_valid(_schiff):
		return
	var f := ThemeDB.fallback_font
	var b := 132.0
	var h := 30.0
	var abst := 6.0
	var breite := 4 * b + 3 * abst
	var start := Vector2((_zeichnung.size.x - breite) / 2.0, _zeichnung.size.y - 2 * h - abst - 26)
	for reihe in 2:
		var liste: Array = Waffen.LASER if reihe == 0 else Waffen.RAKETEN
		var gewaehlt: String = _schiff.laser_wahl if reihe == 0 else _schiff.rakete_wahl
		for i in 4:
			var w: Dictionary = liste[i]
			var r := Rect2(start + Vector2(i * (b + abst), reihe * (h + abst)), Vector2(b, h))
			var frei: bool = w.id in _schiff.waffen_frei
			var an: bool = w.id == gewaehlt
			var farbe: Color = w.farbe
			_zeichnung.draw_rect(r, Color(0, 0, 0, 0.55))
			if an:
				_zeichnung.draw_rect(r, Color(farbe, 0.22))
				_zeichnung.draw_rect(r, Color(farbe, 0.95), false, 2.0)
			else:
				_zeichnung.draw_rect(r, Color(1, 1, 1, 0.18 if frei else 0.07), false, 1.0)
			var taste := i + 1 + reihe * 4
			var text := "%d  %s" % [taste, KURZ.get(w.id, w.name)]
			var tf := Color(1, 1, 1, 0.95) if an else (Color(0.85, 0.85, 0.85, 0.75) if frei else Color(0.6, 0.6, 0.6, 0.3))
			_zeichnung.draw_string(f, r.position + Vector2(8, 20), text, HORIZONTAL_ALIGNMENT_LEFT, b - 10, 15, tf)
			if reihe == 1 and frei and int(w.kosten_munition) > 1:
				_zeichnung.draw_string(f, r.position + Vector2(b - 26, 20), "×%d" % w.kosten_munition, HORIZONTAL_ALIGNMENT_LEFT, 24, 12, Color(tf, tf.a * 0.7))
	# Raketenvorrat rechts neben der Raketenreihe
	var vorrat := start + Vector2(breite + 14, h + abst)
	var knapp: bool = _schiff.raketen < int(Waffen.finde(_schiff.rakete_wahl).kosten_munition)
	_zeichnung.draw_string_outline(f, vorrat + Vector2(0, 21), "%d/%d" % [_schiff.raketen, _schiff.raketen_max], HORIZONTAL_ALIGNMENT_LEFT, 80, 20, 5, Color(0, 0, 0, 0.85))
	_zeichnung.draw_string(f, vorrat + Vector2(0, 21), "%d/%d" % [_schiff.raketen, _schiff.raketen_max], HORIZONTAL_ALIGNMENT_LEFT, 80, 20, ROT if knapp else Color(1.0, 0.75, 0.4))


func _ecke(c: Control, ax: float, ay: float, von: Vector2, bis: Vector2) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = von.x
	c.offset_top = von.y
	c.offset_right = bis.x
	c.offset_bottom = bis.y
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _label(text: String, groesse: int, farbe: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", groesse)
	l.add_theme_color_override("font_color", farbe)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _balken(farbe: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(380, 16)
	var voll := StyleBoxFlat.new()
	voll.bg_color = farbe
	var leer := StyleBoxFlat.new()
	leer.bg_color = Color(0, 0, 0, 0.55)
	leer.border_color = farbe.darkened(0.4)
	leer.set_border_width_all(1)
	b.add_theme_stylebox_override("fill", voll)
	b.add_theme_stylebox_override("background", leer)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func werte(s: Schiff) -> void:
	_schiff = s
	_zeit = Time.get_ticks_msec() / 1000.0
	_zeichnung.queue_redraw()


func setze_tiefe(tiefe: int, name: String) -> void:
	_tiefe.text = "TIEFE %d  ·  %s" % [tiefe, name.to_upper()]


func setze_erz(level: int, lauf: int, bank: int) -> void:
	_erz.text = "ERZ %d  (Lauf %d · Bank %d)" % [level, lauf, bank]


func status(text: String, farbe := GELB) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", farbe)


func mitteilung(text: String, dauer := 2.5, farbe := GELB) -> void:
	_mitteilung.text = text
	_mitteilung.add_theme_color_override("font_color", farbe)
	_mitteilung.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(dauer)
	tw.tween_property(_mitteilung, "modulate:a", 0.0, 0.8)


## Abrechnung nach einer geschafften Tiefe: Posten mit Betrag, unten die Summe.
func abschluss(tiefe: int, posten: Array, summe: int) -> void:
	for k in _abschluss.get_children():
		k.queue_free()
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 6)
	_abschluss.add_child(spalte)
	var titel := _label("TIEFE %d GESCHAFFT" % tiefe, 30, GRUEN)
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spalte.add_child(titel)
	for p in posten:
		var zeile := HBoxContainer.new()
		var links := _label(p[0], 20, Color(0.9, 0.9, 0.85))
		links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zeile.add_child(links)
		zeile.add_child(_label(p[1], 20, GELB))
		spalte.add_child(zeile)
	var linie := HSeparator.new()
	spalte.add_child(linie)
	var gesamt := HBoxContainer.new()
	var gl := _label("In die Bank", 24, GELB)
	gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gesamt.add_child(gl)
	gesamt.add_child(_label("+%d Erz" % summe, 24, GELB))
	spalte.add_child(gesamt)
	_abschluss.visible = true
	_abschluss.modulate.a = 1.0
	if _abschluss_tw:
		_abschluss_tw.kill()
	_abschluss_tw = create_tween()
	_abschluss_tw.tween_interval(4.0)
	_abschluss_tw.tween_property(_abschluss, "modulate:a", 0.0, 0.8)
	_abschluss_tw.tween_callback(func(): _abschluss.visible = false)


func boss_an(name: String) -> void:
	_boss_name.text = name
	_boss_name.visible = true
	_boss_balken.visible = true


func boss_wert(hp: float, hp_max: float) -> void:
	_boss_balken.max_value = hp_max
	_boss_balken.value = maxf(hp, 0.0)


func boss_aus() -> void:
	_boss_name.visible = false
	_boss_balken.visible = false


## Kurze Meldung unter dem Fadenkreuz: was eingesammelt wurde (oder dass es voll ist).
func aufnahme(text: String, farbe: Color) -> void:
	_aufnahme.text = text
	_aufnahme.add_theme_color_override("font_color", farbe)
	_aufnahme.modulate.a = 1.0
	if _aufnahme_tw:
		_aufnahme_tw.kill()
	_aufnahme_tw = create_tween()
	_aufnahme_tw.tween_interval(1.2)
	_aufnahme_tw.tween_property(_aufnahme, "modulate:a", 0.0, 0.6)


func blitz(staerke: float) -> void:
	_blitz.color.a = clampf(staerke / 40.0, 0.12, 0.5)
	create_tween().tween_property(_blitz, "color:a", 0.0, 0.35)


func _zeichnen() -> void:
	# Zielkreuz: rot, mit Kreis drumherum
	var m := _zeichnung.size / 2.0
	_boegen(m)
	_waffenleiste()
	var f := Color(1.0, 0.18, 0.12, 0.9)
	for r in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_zeichnung.draw_line(m + r * 7.0, m + r * 30.0, f, 2.0)
	_zeichnung.draw_arc(m, 22.0, 0.0, TAU, 48, f, 2.0, true)
	_zeichnung.draw_circle(m, 1.6, f)
	if not leit_an:
		return
	var c := Color(0.4, 1.0, 0.6, 0.9)
	if leit_rand:
		var d := leit_richtung
		var n := Vector2(-d.y, d.x)
		_zeichnung.draw_colored_polygon(PackedVector2Array([
			leit_pos + d * 18.0, leit_pos - d * 8.0 + n * 12.0, leit_pos - d * 8.0 - n * 12.0]), c)
	else:
		var p := leit_pos
		_zeichnung.draw_polyline(PackedVector2Array([
			p + Vector2(0, -14), p + Vector2(14, 0), p + Vector2(0, 14), p + Vector2(-14, 0), p + Vector2(0, -14)]), c, 2.5)
	_zeichnung.draw_string(ThemeDB.fallback_font, leit_pos + Vector2(-40, 34), leit_text,
		HORIZONTAL_ALIGNMENT_CENTER, 80, 16, c)

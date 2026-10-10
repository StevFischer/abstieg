class_name HUD
extends CanvasLayer
## Cockpitanzeige: Schild, Energie, Raketen, Tiefe, Erz, Ziel — und der Leitstrahl.

const GRUEN := Color(0.4, 1.0, 0.5)
const GELB := Color(1.0, 0.82, 0.3)
const ROT := Color(1.0, 0.3, 0.25)

var _schild: ProgressBar
var _energie: ProgressBar
var _huelle: ProgressBar
var _huelle_txt: Label
var _schild_txt: Label
var _energie_txt: Label
var _raketen: Label
var _tiefe: Label
var _erz: Label
var _status: Label
var _mitteilung: Label
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

	var unten := VBoxContainer.new()
	_ecke(unten, 0, 1, Vector2(30, -250), Vector2(420, -30))
	wurzel.add_child(unten)
	_schild_txt = _label("SCHILD", 22, GRUEN)
	unten.add_child(_schild_txt)
	_schild = _balken(Color(0.3, 0.6, 1.0))
	unten.add_child(_schild)
	_huelle_txt = _label("HÜLLE", 22, Color(1.0, 0.6, 0.25))
	unten.add_child(_huelle_txt)
	_huelle = _balken(Color(1.0, 0.55, 0.2))
	unten.add_child(_huelle)
	_energie_txt = _label("ENERGIE", 22, GELB)
	unten.add_child(_energie_txt)
	_energie = _balken(GELB)
	unten.add_child(_energie)
	_raketen = _label("RAKETEN 0", 22, ROT)
	unten.add_child(_raketen)

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
	_schild.max_value = s.schild_max
	_schild.value = s.schild
	_schild_txt.text = "SCHILD %d / %d" % [ceili(s.schild), int(s.schild_max)]
	_schild_txt.add_theme_color_override("font_color", GELB if s.schild < s.schild_max * 0.3 else GRUEN)
	_huelle.max_value = s.huelle_max
	_huelle.value = s.huelle
	_huelle_txt.text = "HÜLLE %d / %d" % [ceili(s.huelle), int(s.huelle_max)]
	_huelle_txt.add_theme_color_override("font_color", ROT if s.huelle < s.huelle_max * 0.3 else Color(1.0, 0.6, 0.25))
	_energie.max_value = s.energie_max
	_energie.value = s.energie
	_energie_txt.text = "ENERGIE %d" % int(s.energie)
	_raketen.text = "RAKETEN %d / %d" % [s.raketen, s.raketen_max]
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


func blitz(staerke: float) -> void:
	_blitz.color.a = clampf(staerke / 40.0, 0.12, 0.5)
	create_tween().tween_property(_blitz, "color:a", 0.0, 0.35)


func _zeichnen() -> void:
	var m := _zeichnung.size / 2.0
	var f := Color(GRUEN, 0.8)
	for r in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_zeichnung.draw_line(m + r * 8.0, m + r * 20.0, f, 2.0)
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

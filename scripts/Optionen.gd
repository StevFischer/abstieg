class_name Optionen
extends Control
## Optionen-Bildschirm: Lautstärke gesamt und je Tonart (gespeichert beim Verlassen) und Tastenbelegung
## (gespeichert sofort, siehe Eingabe.gd).

signal zurueck

const ORANGE := Color(1.0, 0.6, 0.2)
const PROBE := {"laser": "laser", "gegner": "laser_gegner", "explosionen": "explosion", "gesamt": "explosion"}

var _probe_t := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(dt: float) -> void:
	_probe_t -= dt


func aufbauen() -> void:
	for k in get_children():
		k.queue_free()
	var grund := ColorRect.new()
	grund.color = Color(0.03, 0.025, 0.02, 1.0)
	grund.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grund)
	var rollen := ScrollContainer.new()        # mit der Tastenliste wird die Seite höher als der Bildschirm
	rollen.set_anchors_preset(Control.PRESET_FULL_RECT)
	rollen.follow_focus = true
	rollen.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(rollen)
	var mitte := CenterContainer.new()
	mitte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mitte.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rollen.add_child(mitte)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 18)
	spalte.custom_minimum_size = Vector2(820, 0)
	mitte.add_child(spalte)
	var titel := Label.new()
	titel.text = "OPTIONEN"
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titel.add_theme_font_size_override("font_size", 56)
	titel.add_theme_color_override("font_color", ORANGE)
	spalte.add_child(titel)
	spalte.add_child(_text("LAUTSTÄRKE", 22, ORANGE))
	var erster: HSlider = null
	for k in Klang.KANAELE:
		var zeile := HBoxContainer.new()
		zeile.add_theme_constant_override("separation", 20)
		var name_l := _text(Klang.KANAL_NAMEN[k], 24, Color(0.9, 0.88, 0.8))
		name_l.custom_minimum_size = Vector2(300, 0)      # „Explosionen und Treffer“ ist die längste Beschriftung
		zeile.add_child(name_l)
		var regler := HSlider.new()
		regler.min_value = 0
		regler.max_value = 100
		regler.step = 5
		regler.value = round(Klang.lautstaerke[k] * 100.0)
		regler.custom_minimum_size = Vector2(420, 36)
		regler.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		zeile.add_child(regler)
		var wert := _text("%d %%" % int(regler.value), 24, Color(1.0, 0.85, 0.35))
		wert.custom_minimum_size = Vector2(90, 0)
		wert.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		zeile.add_child(wert)
		var kanal: String = k
		regler.value_changed.connect(func(v: float):
			Klang.setze(kanal, v / 100.0)
			wert.text = "%d %%" % int(v)
			if _probe_t <= 0.0:          # Probeton, damit man hört, was man einstellt
				_probe_t = 0.25
				Klang.spiele(PROBE[kanal]))
		spalte.add_child(zeile)
		if erster == null:
			erster = regler
	if not OS.has_feature("android"):
		_tasten_liste(spalte)
	var zur := Button.new()
	zur.text = "Zurück"
	zur.custom_minimum_size = Vector2(0, 52)
	zur.add_theme_font_size_override("font_size", 24)
	zur.pressed.connect(_schliessen)
	spalte.add_child(zur)
	spalte.add_child(_text("Pfeiltasten oder Steuerkreuz links/rechts verschieben den gewählten Regler.", 16,
		Color(0.6, 0.58, 0.52)))
	erster.call_deferred("grab_focus")


## Tastatur & Maus (Stev 2026-10-10: „Tastatur belegen bei den Optionen anzeigen und veränderbar machen“):
## je Aktion ein Knopf mit der aktuellen Belegung; Klick, dann neue Taste oder Maustaste; Esc bricht ab.
var _wartet := ""                 ## Aktion, die gerade auf eine Taste wartet
var _knoepfe := {}                ## Aktion -> Button
var _tasten_info: Label

func _tasten_liste(spalte: VBoxContainer) -> void:
	spalte.add_child(_text("TASTATUR & MAUS", 22, ORANGE))
	var raster := GridContainer.new()
	raster.columns = 4
	raster.add_theme_constant_override("h_separation", 16)
	raster.add_theme_constant_override("v_separation", 6)
	spalte.add_child(raster)
	_knoepfe.clear()
	for b in Eingabe.BELEGBAR:
		var name_l := _text(b[1], 20, Color(0.9, 0.88, 0.8))
		name_l.custom_minimum_size = Vector2(170, 0)
		raster.add_child(name_l)
		var k := Button.new()
		k.name = "Taste_" + b[0]
		k.custom_minimum_size = Vector2(220, 38)
		k.add_theme_font_size_override("font_size", 18)
		var aktion: String = b[0]
		k.pressed.connect(func(): _warten_auf(aktion))
		raster.add_child(k)
		_knoepfe[aktion] = k
	_tasten_info = _text("Auf eine Taste klicken, dann die neue Taste oder Maustaste drücken. Esc bricht ab. Doppelt belegt? Dann tauschen die beiden.",
		16, Color(0.6, 0.58, 0.52))
	_tasten_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spalte.add_child(_tasten_info)
	var std := Button.new()
	std.name = "TastenStandard"
	std.text = "Tasten auf Standard zurücksetzen"
	std.custom_minimum_size = Vector2(0, 40)
	std.add_theme_font_size_override("font_size", 18)
	std.pressed.connect(func():
		Eingabe.zuruecksetzen()
		_tasten_zeigen())
	spalte.add_child(std)
	_tasten_zeigen()


func _tasten_zeigen() -> void:
	for a in _knoepfe:
		_knoepfe[a].text = "Taste drücken …" if a == _wartet else Eingabe.text_fuer(a)


func _warten_auf(aktion: String) -> void:
	_wartet = aktion
	_tasten_zeigen()


func _input(e: InputEvent) -> void:
	if _wartet == "" or not visible:
		return
	var ist_taste: bool = e is InputEventKey and e.pressed and not e.echo
	var ist_maus: bool = e is InputEventMouseButton and e.pressed
	if not (ist_taste or ist_maus):
		return
	get_viewport().set_input_as_handled()
	var aktion := _wartet
	_wartet = ""
	if ist_taste and e.physical_keycode == KEY_ESCAPE:
		_tasten_zeigen()
		return
	var getauscht := Eingabe.belegen(aktion, e)
	if getauscht != "":
		_tasten_info.text = "%s hatte diese Taste — jetzt auf %s." % [_name_von(getauscht), Eingabe.text_fuer(getauscht)]
	_tasten_zeigen()
	_knoepfe[aktion].call_deferred("grab_focus")


func _name_von(aktion: String) -> String:
	for b in Eingabe.BELEGBAR:
		if b[0] == aktion:
			return b[1]
	return aktion


func _unhandled_input(e: InputEvent) -> void:
	if visible and e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_schliessen()


func _schliessen() -> void:
	Klang.speichern()
	zurueck.emit()


func _text(t: String, groesse: int, farbe: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", groesse)
	l.add_theme_color_override("font_color", farbe)
	return l

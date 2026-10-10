class_name Optionen
extends Control
## Optionen-Bildschirm: Lautstärke gesamt und je Tonart. Wirkt sofort, gespeichert beim Verlassen.

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
	var mitte := CenterContainer.new()
	mitte.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(mitte)
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
	var zur := Button.new()
	zur.text = "Zurück"
	zur.custom_minimum_size = Vector2(0, 52)
	zur.add_theme_font_size_override("font_size", 24)
	zur.pressed.connect(_schliessen)
	spalte.add_child(zur)
	spalte.add_child(_text("Pfeiltasten oder Steuerkreuz links/rechts verschieben den gewählten Regler.", 16,
		Color(0.6, 0.58, 0.52)))
	erster.call_deferred("grab_focus")


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

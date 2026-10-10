class_name Hangar
extends Control
## Startbildschirm zwischen den Läufen: Bank, Rekord, Aufrüstungen kaufen, losfliegen.

signal starten
signal beenden
signal optionen

const ORANGE := Color(1.0, 0.6, 0.2)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func aufbauen() -> void:
	for k in get_children():
		k.queue_free()
	var grund := ColorRect.new()
	grund.color = Color(0.03, 0.025, 0.02)
	grund.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grund)
	var mitte := CenterContainer.new()
	mitte.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(mitte)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 14)
	spalte.custom_minimum_size = Vector2(1500, 0)
	mitte.add_child(spalte)

	spalte.add_child(_label("ABSTIEG", 84, ORANGE, true))
	spalte.add_child(_label("Endlose Minen. Zerstöre den Reaktor, entkomme, steig tiefer.", 22, Color(0.8, 0.75, 0.65), true))
	spalte.add_child(_label("Erz in der Bank: %d     ·     Rekordtiefe: %d     ·     Läufe: %d" % [
		Meta.bank, Meta.rekord, Meta.laeufe], 24, Color(1.0, 0.85, 0.35), true))
	spalte.add_child(HSeparator.new())
	var zwei := HBoxContainer.new()
	zwei.add_theme_constant_override("separation", 60)
	spalte.add_child(zwei)
	var links := VBoxContainer.new()
	links.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	links.add_theme_constant_override("separation", 10)
	zwei.add_child(links)
	var rechts := VBoxContainer.new()
	rechts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rechts.add_theme_constant_override("separation", 10)
	zwei.add_child(rechts)
	_waffen_spalte(rechts)
	links.add_child(_label("AUFRÜSTUNGEN — bleiben nach dem Tod", 22, ORANGE, false))
	var erster: Button = null
	for a in Meta.AUFRUESTUNGEN:
		var zeile := HBoxContainer.new()
		var text := _label("%s  (%s)   Stufe %d/%d" % [a.name, a.text, Meta.stufe(a.id), a.max], 22, Color(0.9, 0.88, 0.8), false)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zeile.add_child(text)
		var b := Button.new()
		b.custom_minimum_size = Vector2(240, 44)
		b.add_theme_font_size_override("font_size", 20)
		if Meta.ausgereizt(a.id):
			b.text = "ausgebaut"
			b.disabled = true
		else:
			b.text = "Kaufen · %d Erz" % Meta.kosten(a.id)
			b.disabled = not Meta.kaufbar(a.id)
		var id: String = a.id
		b.pressed.connect(func():
			if Meta.kaufen(id):
				aufbauen())
		zeile.add_child(b)
		links.add_child(zeile)
	spalte.add_child(HSeparator.new())
	var los := Button.new()
	los.text = "ABSTIEG BEGINNEN"
	los.custom_minimum_size = Vector2(0, 64)
	los.add_theme_font_size_override("font_size", 30)
	los.pressed.connect(func(): starten.emit())
	spalte.add_child(los)
	erster = los
	var opt := Button.new()
	opt.text = "Optionen"
	opt.custom_minimum_size = Vector2(0, 40)
	opt.pressed.connect(func(): optionen.emit())
	spalte.add_child(opt)
	var ende := Button.new()
	ende.text = "Beenden"
	ende.custom_minimum_size = Vector2(0, 40)
	ende.pressed.connect(func(): beenden.emit())
	spalte.add_child(ende)
	spalte.add_child(_label(
		"Maus drehen · WASD fliegen · Leertaste/Strg hoch/runter · Q/E rollen · Linke Maustaste Laser · Rechte Rakete\n" +
		"1–4 Laser wählen · 5–8 Rakete wählen · Tab Leitstrahl · F Scheinwerfer · Esc Pause\n" +
		"Controller: linker Stick fliegen · rechter Stick drehen · LB/RB rollen · A/B hoch/runter · RT Laser · LT Rakete · Steuerkreuz ←→ Laser, ↑↓ Rakete",
		16, Color(0.6, 0.58, 0.52), true))
	erster.call_deferred("grab_focus")


func _waffen_spalte(rechts: VBoxContainer) -> void:
	rechts.add_child(_label("WAFFEN — dauerhaft freischalten (Laser 1–4, Raketen 5–8)", 22, ORANGE, false))
	var frei := Meta.waffen_frei()
	for liste in [Waffen.LASER, Waffen.RAKETEN]:
		for i in liste.size():
			var w: Dictionary = liste[i]
			var taste: int = i + 1 if liste == Waffen.LASER else i + 5
			var zeile := HBoxContainer.new()
			var text := _label("%d  %s  (%s)" % [taste, w.name, w.text], 20, Color(0.9, 0.88, 0.8), false)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			zeile.add_child(text)
			var b := Button.new()
			b.custom_minimum_size = Vector2(220, 40)
			b.add_theme_font_size_override("font_size", 19)
			if w.id in frei:
				b.text = "vorhanden"
				b.disabled = true
			else:
				b.text = "Kaufen · %d Erz" % w.preis
				b.disabled = not Meta.waffe_kaufbar(w.id)
			var id: String = w.id
			b.pressed.connect(func():
				if Meta.waffe_kaufen(id):
					aufbauen())
			zeile.add_child(b)
			rechts.add_child(zeile)


func _label(text: String, groesse: int, farbe: Color, zentriert: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", groesse)
	l.add_theme_color_override("font_color", farbe)
	if zentriert:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

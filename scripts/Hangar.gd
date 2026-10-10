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
	var neu := Button.new()
	neu.text = "Neues Spiel (alles zurücksetzen)"
	neu.custom_minimum_size = Vector2(0, 40)
	neu.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	neu.pressed.connect(_frage_neues_spiel)
	spalte.add_child(neu)
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


## Sicherheitsabfrage — Neues Spiel lässt sich nicht rückgängig machen.
func _frage_neues_spiel() -> void:
	var schleier := ColorRect.new()
	schleier.name = "Abfrage"
	schleier.color = Color(0, 0, 0, 0.8)
	schleier.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(schleier)
	var mitte := CenterContainer.new()
	mitte.set_anchors_preset(Control.PRESET_FULL_RECT)
	schleier.add_child(mitte)
	var kasten := PanelContainer.new()
	mitte.add_child(kasten)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 18)
	spalte.custom_minimum_size = Vector2(760, 0)
	kasten.add_child(spalte)
	spalte.add_child(_label("NEUES SPIEL?", 40, Color(1.0, 0.4, 0.35), true))
	spalte.add_child(_label("Erz in der Bank (%d), alle Aufrüstungen, freigeschaltete Waffen,\nRekordtiefe und Läufe werden gelöscht. Das lässt sich nicht rückgängig machen." % Meta.bank,
		20, Color(0.9, 0.88, 0.8), true))
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 20)
	zeile.alignment = BoxContainer.ALIGNMENT_CENTER
	spalte.add_child(zeile)
	var nein := Button.new()
	nein.text = "Abbrechen"
	nein.custom_minimum_size = Vector2(260, 52)
	nein.pressed.connect(func(): schleier.queue_free())
	zeile.add_child(nein)
	var ja := Button.new()
	ja.text = "Ja, alles löschen"
	ja.custom_minimum_size = Vector2(260, 52)
	ja.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	ja.pressed.connect(func():
		Meta.zuruecksetzen()
		aufbauen())
	zeile.add_child(ja)
	nein.call_deferred("grab_focus")      # Vorauswahl ist das Harmlose


func _waffen_spalte(rechts: VBoxContainer) -> void:
	rechts.add_child(_label("WAFFEN — freischalten, dann bis Mk V verbessern (+30 % Schaden je Version)", 22, ORANGE, false))
	var frei := Meta.waffen_frei()
	for liste in [Waffen.LASER, Waffen.RAKETEN]:
		for i in liste.size():
			var w: Dictionary = liste[i]
			var taste: int = i + 1 if liste == Waffen.LASER else i + 5
			var zeile := HBoxContainer.new()
			var besitzt: bool = w.id in frei
			var mk := Meta.waffen_stufe(w.id)
			var text := _label("%d  %s%s  (%s)" % [taste, w.name, ("  " + Waffen.MK[mk]) if besitzt else "", w.text],
				20, Color(0.9, 0.88, 0.8), false)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			zeile.add_child(text)
			var b := Button.new()
			b.custom_minimum_size = Vector2(220, 40)
			b.add_theme_font_size_override("font_size", 19)
			var id: String = w.id
			if besitzt and mk >= Waffen.MAX_STUFE:
				b.text = "Mk V · ausgebaut"
				b.disabled = true
			elif besitzt:
				b.text = "%s · %d Erz" % [Waffen.MK[mk + 1], Waffen.verbessern_preis(id, mk)]
				b.disabled = not Meta.waffe_verbesserbar(id)
				b.pressed.connect(func():
					if Meta.waffe_verbessern(id):
						aufbauen())
			else:
				b.text = "Kaufen · %d Erz" % w.preis
				b.disabled = not Meta.waffe_kaufbar(w.id)
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

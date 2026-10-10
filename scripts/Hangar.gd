class_name Hangar
extends Control
## Startbildschirm zwischen den Läufen: Bank, Rekord, Aufrüstungen kaufen, losfliegen.

signal starten
signal beenden
signal optionen

const ORANGE := Color(1.0, 0.6, 0.2)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Tooltips mit dunklem Kasten — die Vorgabe ist durchsichtig und läuft über die Karten
	var t := Theme.new()
	var kasten := StyleBoxFlat.new()
	kasten.bg_color = Color(0.05, 0.045, 0.04, 0.97)
	kasten.border_color = ORANGE
	kasten.set_border_width_all(1)
	kasten.set_corner_radius_all(5)
	kasten.content_margin_left = 12
	kasten.content_margin_right = 12
	kasten.content_margin_top = 8
	kasten.content_margin_bottom = 8
	t.set_stylebox("panel", "TooltipPanel", kasten)
	t.set_font_size("font_size", "TooltipLabel", 17)
	t.set_color("font_color", "TooltipLabel", Color(0.95, 0.92, 0.85))
	theme = t


func aufbauen() -> void:
	for k in get_children():
		remove_child(k)          # sofort raus, damit find_child den neuen Knopf findet, nicht den alten
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
	# Spielzeit wie bei Steam
	spalte.add_child(_label("Spielzeit: %s insgesamt     ·     %s in den letzten 2 Wochen     ·     zuletzt gespielt: %s" % [
		Meta.spielzeit_text(Meta.spielzeit), Meta.spielzeit_text(Meta.spielzeit_zwei_wochen()), Meta.zuletzt_text()],
		18, Color(0.62, 0.72, 0.85), true))
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
	var raster := GridContainer.new()
	raster.columns = 2
	raster.add_theme_constant_override("h_separation", 10)
	raster.add_theme_constant_override("v_separation", 10)
	links.add_child(raster)
	for a in Meta.AUFRUESTUNGEN:
		raster.add_child(_aufruestkarte(a))
	_info = _label("Steuerkreuz/Maus auf eine Karte: Name und Werte erscheinen hier.", 17, Color(0.7, 0.68, 0.6), true)
	_info.custom_minimum_size = Vector2(0, 52)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spalte.add_child(_info)
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
	# Nach einem Kauf bleibt der Fokus auf demselben Knopf (Controller), sonst auf "Abstieg beginnen".
	var ziel: Control = erster
	if _fokus_merken != "":
		var k := find_child(_fokus_merken, true, false)
		if k is Control:
			ziel = k
	_fokus_merken = ""
	ziel.call_deferred("grab_focus")


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


const AUF_FARBE := {"schild": Color(0.35, 0.65, 1.0), "panzerung": Color(1.0, 0.58, 0.22),
	"triebwerk": Color(0.4, 1.0, 0.6), "raketen": Color(1.0, 0.4, 0.35)}


## Aufrüstung als Karte wie die Waffen: Stufenpunkte, Symbol, Kaufknopf; Wirkung im Tooltip.
func _aufruestkarte(a: Dictionary) -> Control:
	var st := Meta.stufe(a.id)
	var farbe: Color = AUF_FARBE.get(a.id, ORANGE)
	var karte := PanelContainer.new()
	karte.custom_minimum_size = Vector2(250, 0)
	karte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	karte.mouse_filter = Control.MOUSE_FILTER_STOP
	var stil := StyleBoxFlat.new()
	stil.bg_color = Color(farbe.r * 0.12, farbe.g * 0.12, farbe.b * 0.12, 0.95)
	stil.border_color = Color(farbe, 0.85 if st > 0 else 0.45)
	stil.set_border_width_all(2)
	stil.set_corner_radius_all(8)
	stil.content_margin_left = 10
	stil.content_margin_right = 10
	stil.content_margin_top = 6
	stil.content_margin_bottom = 8
	karte.add_theme_stylebox_override("panel", stil)
	var spalte := VBoxContainer.new()
	spalte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spalte.add_theme_constant_override("separation", 4)
	karte.add_child(spalte)
	# Stufenpunkte: gefüllt = gekauft
	var punkte := _label("●".repeat(st) + "○".repeat(int(a.max) - st), 15, farbe, true)
	punkte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spalte.add_child(punkte)
	var sym := WaffenSymbol.new("auf_" + a.id, farbe)
	sym.custom_minimum_size = Vector2(0, 70)
	spalte.add_child(sym)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 16)
	var id: String = a.id
	b.name = "Knopf_" + id
	var tip := _aufruest_tooltip(a, st)
	if Meta.ausgereizt(id):
		b.text = "ausgebaut"
		_knopf(b, false, tip, func(): return false, "Schon ganz ausgebaut")
	else:
		b.text = "Kaufen · %d" % Meta.kosten(id)
		_knopf(b, Meta.kaufbar(id), tip, func(): return Meta.kaufen(id), "Zu wenig Erz")
	spalte.add_child(b)
	karte.tooltip_text = tip
	b.tooltip_text = tip
	return karte


func _aufruest_tooltip(a: Dictionary, st: int) -> String:
	var jetzt := Meta.schiffswerte()
	var zeilen: Array[String] = ["%s   Stufe %d/%d" % [a.name, st, a.max], a.text + " je Stufe"]
	match a.id:
		"schild":
			zeilen.append("Schild jetzt %d%s" % [jetzt.schild_max, (" → %d" % (jetzt.schild_max + 25)) if st < a.max else ""])
		"panzerung":
			zeilen.append("Hülle jetzt %d%s" % [jetzt.huelle_max, (" → %d" % (jetzt.huelle_max + 25)) if st < a.max else ""])
		"triebwerk":
			zeilen.append("Tempo jetzt %.1f m/s%s" % [jetzt.tempo, (" → %.1f" % (14.0 * (1.0 + 0.08 * (st + 1)))) if st < a.max else ""])
		"raketen":
			zeilen.append("Raketen jetzt %d%s" % [jetzt.raketen_max, (" → %d" % (jetzt.raketen_max + 2)) if st < a.max else ""])
	return "\n".join(zeilen)


func _waffen_spalte(rechts: VBoxContainer) -> void:
	rechts.add_child(_label("WAFFEN — Maus drauf für Name und Werte", 22, ORANGE, false))
	var frei := Meta.waffen_frei()
	for liste in [Waffen.LASER, Waffen.RAKETEN]:
		var raster := GridContainer.new()
		raster.columns = 4
		raster.add_theme_constant_override("h_separation", 10)
		raster.add_theme_constant_override("v_separation", 10)
		rechts.add_child(raster)
		for i in liste.size():
			raster.add_child(_waffenkarte(liste[i], i + 1 if liste == Waffen.LASER else i + 5, frei))


## Eine Karte je Waffe: Taste, Symbol, Version, Kaufknopf. Name und Werte stehen im Tooltip.
func _waffenkarte(w: Dictionary, taste: int, frei: Array) -> Control:
	var besitzt: bool = w.id in frei
	var mk := Meta.waffen_stufe(w.id)
	var farbe: Color = w.farbe if besitzt else Color(0.55, 0.55, 0.55)
	var karte := PanelContainer.new()
	karte.custom_minimum_size = Vector2(170, 0)
	karte.mouse_filter = Control.MOUSE_FILTER_STOP
	var stil := StyleBoxFlat.new()
	stil.bg_color = Color(farbe.r * 0.12, farbe.g * 0.12, farbe.b * 0.12, 0.95)
	stil.border_color = Color(farbe, 0.85 if besitzt else 0.35)
	stil.set_border_width_all(2)
	stil.set_corner_radius_all(8)
	stil.content_margin_left = 8
	stil.content_margin_right = 8
	stil.content_margin_top = 6
	stil.content_margin_bottom = 8
	karte.add_theme_stylebox_override("panel", stil)
	var spalte := VBoxContainer.new()
	spalte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spalte.add_theme_constant_override("separation", 4)
	karte.add_child(spalte)
	var kopf := HBoxContainer.new()
	kopf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _label("%d" % taste, 16, Color(0.75, 0.75, 0.7), false)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kopf.add_child(t)
	var v := _label(Waffen.MK[mk] if besitzt else "gesperrt", 16, farbe, false)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kopf.add_child(v)
	spalte.add_child(kopf)
	var sym := WaffenSymbol.new(w.id, Color(farbe, 1.0 if besitzt else 0.6))
	sym.custom_minimum_size = Vector2(0, 74)
	spalte.add_child(sym)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 16)
	var id: String = w.id
	b.name = "Knopf_" + id
	var tip := _tooltip(w, besitzt, mk)
	if besitzt and mk >= Waffen.MAX_STUFE:
		b.text = "Mk V · max"
		_knopf(b, false, tip, func(): return false, "Schon Mk V")
	elif besitzt:
		b.text = "%s · %d" % [Waffen.MK[mk + 1], Waffen.verbessern_preis(id, mk)]
		_knopf(b, Meta.waffe_verbesserbar(id), tip, func(): return Meta.waffe_verbessern(id), "Zu wenig Erz")
	else:
		b.text = "Kaufen · %d" % w.preis
		_knopf(b, Meta.waffe_kaufbar(id), tip, func(): return Meta.waffe_kaufen(id), "Zu wenig Erz")
	spalte.add_child(b)
	karte.tooltip_text = tip
	b.tooltip_text = tip
	return karte


## Kaufknopf, der auch mit dem Controller funktioniert: nie gesperrt (gesperrte Knöpfe kann man mit dem
## Steuerkreuz nicht anwählen), sondern abgedunkelt; Fokus zeigt den Tooltip-Text im Infofeld.
func _knopf(b: Button, moeglich: bool, tip: String, kaufen: Callable, warum: String) -> void:
	if not moeglich:
		b.modulate = Color(1, 1, 1, 0.45)
	b.focus_entered.connect(func(): _info_zeigen(tip))
	b.mouse_entered.connect(func(): _info_zeigen(tip))
	b.pressed.connect(func():
		if moeglich and kaufen.call():
			_fokus_merken = b.name
			aufbauen()
		else:
			_info_zeigen(warum + "\n" + tip, true))


var _info: Label
var _fokus_merken := ""


func _info_zeigen(text: String, warnung := false) -> void:
	if _info == null or not is_instance_valid(_info):
		return
	_info.text = text
	_info.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4) if warnung else Color(0.92, 0.9, 0.82))


func _tooltip(w: Dictionary, besitzt: bool, mk: int) -> String:
	var faktor := Waffen.schaden_faktor(mk)
	var zeilen: Array[String] = ["%s%s" % [w.name, ("  " + Waffen.MK[mk]) if besitzt else ""], w.text]
	if Waffen.ist_laser(w.id):
		zeilen.append("Schaden %.0f je Schuss%s · %.1f Schuss/s" % [
			w.schaden * faktor, (" × %d" % w.anzahl) if w.anzahl > 1 else "", 1.0 / w.cd])
	else:
		zeilen.append("Schaden %.0f%s · %d Munition je Schuss" % [
			w.schaden * faktor, (" × %d" % w.anzahl) if w.anzahl > 1 else "", w.kosten_munition])
	if besitzt and mk < Waffen.MAX_STUFE:
		zeilen.append("Nächste Version %s: Schaden %.0f" % [Waffen.MK[mk + 1], w.schaden * Waffen.schaden_faktor(mk + 1)])
	elif not besitzt:
		zeilen.append("Noch nicht freigeschaltet")
	return "\n".join(zeilen)


func _label(text: String, groesse: int, farbe: Color, zentriert: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", groesse)
	l.add_theme_color_override("font_color", farbe)
	if zentriert:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

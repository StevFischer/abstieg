class_name Hangar
extends Control
## Startbildschirm zwischen den Läufen: Bank, Rekord, Aufrüstungen kaufen, losfliegen.

signal starten
signal beenden
signal optionen

const ORANGE := Color(1.0, 0.6, 0.2)
const ART_FARBE := {"kampf": Color(1.0, 0.35, 0.3), "ueberleben": Color(0.4, 0.75, 1.0),
	"wirtschaft": Color(1.0, 0.82, 0.3), "werkzeuge": Color(0.35, 0.95, 0.85), "forschung": Color(0.75, 0.55, 1.0), "module": Color(1.0, 0.6, 0.15), "pakt": Color(1.0, 0.3, 0.3), "station": Color(0.55, 0.85, 0.75)}
const ZWEIG_FARBE := {"Waffen": Color(1.0, 0.35, 0.3), "Schiff": Color(0.4, 0.75, 1.0),
	"Bergbau": Color(1.0, 0.82, 0.3), "Taktik": Color(0.35, 0.95, 0.85)}

var _reiter := "schiff"          ## gewählter Aufrüstungs-Reiter, bleibt über Käufe hinweg


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
	# Scrollbar, damit der Hangar auch auf dem Handy (größere Schrift, niedrige Fläche) ganz erreichbar ist;
	# der Bildlauf folgt dem Fokus, also auch dem Steuerkreuz. Am PC passt alles, dort scrollt nichts.
	var rollen := ScrollContainer.new()
	rollen.name = "Rollen"
	rollen.set_anchors_preset(Control.PRESET_FULL_RECT)
	rollen.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rollen.follow_focus = true
	add_child(rollen)
	var mitte := CenterContainer.new()
	mitte.custom_minimum_size = get_viewport_rect().size
	mitte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rollen.add_child(mitte)
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 10)
	spalte.custom_minimum_size = Vector2(1500, 0)
	mitte.add_child(spalte)

	# Titel kleiner als früher (84), damit Reiter, Starttiefe und alle Hilfszeilen bei 1080 px Höhe Platz haben
	spalte.add_child(_label("ABSTIEG", 60, ORANGE, true))
	spalte.add_child(_label("Endlose Minen. Zerstöre den Reaktor, entkomme, steig tiefer.", 19, Color(0.8, 0.75, 0.65), true))
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
	var erster: Button = null
	_reiter_zeile(links)
	var raster := GridContainer.new()
	raster.columns = 2
	raster.add_theme_constant_override("h_separation", 10)
	raster.add_theme_constant_override("v_separation", 10)
	links.add_child(raster)
	for a in Meta.AUFRUESTUNGEN:
		if a.art == _reiter:
			raster.add_child(_aufruestkarte(a))
	if _reiter in ["forschung", "module", "pakt", "station"]:
		links.remove_child(raster)
		raster.queue_free()
		match _reiter:
			"forschung": _forschungsbaum(links)
			"module": _module_ansicht(links)
			"pakt": _pakt_ansicht(links)
			"station": _station_ansicht(links)
	_info = _label("Steuerkreuz/Maus auf eine Karte: Name und Werte erscheinen hier.", 17, Color(0.7, 0.68, 0.6), true)
	_info.custom_minimum_size = Vector2(0, 52)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spalte.add_child(_info)
	spalte.add_child(HSeparator.new())
	_starttiefe_zeile(spalte)
	var los := Button.new()
	los.text = "ABSTIEG BEGINNEN"
	los.custom_minimum_size = Vector2(0, 64)
	los.add_theme_font_size_override("font_size", 30)
	los.pressed.connect(func(): starten.emit())
	spalte.add_child(los)
	erster = los
	# Steuerkreuz: vom Startknopf hoch auf die gewählte Starttiefe, von dort runter zurück.
	for b in _start_knoepfe:
		b.focus_neighbor_bottom = b.get_path_to(los)
		if b.button_pressed:
			los.focus_neighbor_top = los.get_path_to(b)
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
	# Auf dem Handy nur die Controller-Zeile: Maus und Tastatur gibt es dort nicht.
	var tastatur := "" if OS.has_feature("android") else \
		"Maus drehen · WASD fliegen · Leertaste/Strg hoch/runter · Q/E rollen · Linke Maustaste Laser · Rechte Rakete\n" + \
		"1–4 Laser wählen · 5–8 Rakete wählen · Umschalt Nachbrenner · R Notfallschild · Tab Leitstrahl · F Scheinwerfer · Esc Pause\n"
	spalte.add_child(_label(tastatur +
		"Controller: linker Stick fliegen · rechter Stick drehen · LB/RB rollen · A/B hoch/runter · RT Laser · LT Rakete · X Nachbrenner · R3 Notfallschild · Steuerkreuz ←→ Laser, ↑↓ Rakete · Hangar: LB/RB Reiter",
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


## Reiter nach Art: Schiff · Kampf · Überleben · Wirtschaft · Werkzeuge. Mit LB/RB oder Steuerkreuz wechselbar.
## Gesperrte Reiter (noch kein Boss) sind wählbar und zeigen, ab wann sie freigeschaltet werden.
## Zwei Zeilen: oben die Aufrüstungs-Arten, unten Forschung · Module · Pakt · Station (die Zeile ersetzt
## die frühere Überschrift „AUFRÜSTUNGEN“, damit die Seite nicht höher wird).
func _reiter_zeile(links: VBoxContainer) -> void:
	var zeilen: Array[HBoxContainer] = []
	for z in 2:
		var hb := HBoxContainer.new()
		hb.name = "Reiter" if z == 0 else "Reiter2"
		hb.add_theme_constant_override("separation", 6)
		links.add_child(hb)
		zeilen.append(hb)
	var gruppe := ButtonGroup.new()
	for r in Meta.REITER:
		var id: String = r[0]
		var reihe: HBoxContainer = zeilen[1] if id in ["forschung", "module", "pakt", "station"] else zeilen[0]
		var b := Button.new()
		b.name = "Reiter_" + id
		var neu := 0
		var frei := false
		for a in Meta.AUFRUESTUNGEN:
			if a.art == id:
				frei = frei or Meta.freigeschaltet(a.id)
				if Meta.kaufbar(a.id):
					neu += 1
		if id == "module":
			frei = true
			neu = Meta.module.size()
		if id == "pakt":
			frei = Meta.pakt_frei()
			neu = Meta.pakt_punkte()
		if id == "station":
			frei = true
			for gb in Meta.GEBAEUDE:
				if Meta.ausbaubar(gb.id):
					neu += 1
		if id == "forschung":
			frei = true
			for k in Meta.FORSCHUNG:
				if Meta.erforschbar(k.id):
					neu += 1
		b.text = r[1] + (" · %d" % neu if neu > 0 else "")
		if not frei:
			b.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		b.toggle_mode = true
		b.button_group = gruppe
		b.button_pressed = id == _reiter
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 13)
		var farbe: Color = ART_FARBE.get(id, ORANGE)
		var gedrueckt := StyleBoxFlat.new()
		gedrueckt.bg_color = Color(farbe.r * 0.22, farbe.g * 0.22, farbe.b * 0.22)
		gedrueckt.set_border_width_all(2)
		gedrueckt.border_color = farbe
		var normal := b.get_theme_stylebox("normal")
		for seite in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			gedrueckt.set_content_margin(seite, normal.get_content_margin(seite))
		b.add_theme_stylebox_override("pressed", gedrueckt)
		b.add_theme_stylebox_override("hover_pressed", gedrueckt)
		b.add_theme_color_override("font_pressed_color", farbe)
		b.add_theme_color_override("font_hover_pressed_color", farbe)
		b.tooltip_text = "Kaufbar: %d" % neu if frei else "Wird mit einem besiegten Boss freigeschaltet."
		b.pressed.connect(func(): reiter_waehlen(id))
		reihe.add_child(b)


## Forschungsbaum: vier Zweige als Zeilen, Knoten als Knöpfe, Linien zu den Voraussetzungen.
## Erforscht = gefüllt, erforschbar = leuchtender Rand, sonst abgedunkelt.
func _forschungsbaum(links: VBoxContainer) -> void:
	links.add_child(_label("Forschungspunkte: %d frei   ·   1 Punkt je erreichter Tiefe (Rekord %d)" % [
		Meta.forschungspunkte_frei(), Meta.rekord], 17, ART_FARBE.forschung, false))
	var flaeche := Control.new()
	flaeche.name = "Forschungsbaum"
	var bw := 166.0
	var bh := 54.0
	var dx := 182.0
	var dy := 64.0
	flaeche.custom_minimum_size = Vector2(dx * 3 + bw, dy * 3 + bh)
	links.add_child(flaeche)
	var pos := {}
	for k in Meta.FORSCHUNG:
		pos[k.id] = Vector2(k.spalte * dx, k.zeile * dy)
	# Linien hinter den Knöpfen
	var linien := Control.new()
	linien.mouse_filter = Control.MOUSE_FILTER_IGNORE
	linien.set_anchors_preset(Control.PRESET_FULL_RECT)
	linien.draw.connect(func():
		for k in Meta.FORSCHUNG:
			for v in k.vor:
				var a: Vector2 = pos[v] + Vector2(bw, bh) / 2.0
				var b: Vector2 = pos[k.id] + Vector2(bw, bh) / 2.0
				var an := Meta.erforscht(v)
				linien.draw_line(a, b, Color(0.75, 0.55, 1.0, 0.9) if an else Color(0.4, 0.4, 0.45, 0.6), 3.0 if an else 2.0, true))
	flaeche.add_child(linien)
	for k in Meta.FORSCHUNG:
		var id: String = k.id
		var farbe: Color = ZWEIG_FARBE.get(k.zweig, ORANGE)
		var b := Button.new()
		b.name = "Knopf_" + id
		b.position = pos[id]
		b.size = Vector2(bw, bh)
		b.custom_minimum_size = Vector2(bw, bh)
		b.add_theme_font_size_override("font_size", 14)
		var stil := StyleBoxFlat.new()
		stil.set_corner_radius_all(6)
		stil.set_border_width_all(2)
		var fertig := Meta.erforscht(id)
		var moeglich := Meta.erforschbar(id)
		if fertig:
			stil.bg_color = Color(farbe.r * 0.45, farbe.g * 0.45, farbe.b * 0.45)
			stil.border_color = farbe
			b.text = "%s\n✓ erforscht" % k.name
		else:
			stil.bg_color = Color(farbe.r * 0.1, farbe.g * 0.1, farbe.b * 0.1)
			stil.border_color = farbe if moeglich else Color(farbe, 0.3)
			b.text = "%s\n%d Punkt%s" % [k.name, k.kosten, "" if int(k.kosten) == 1 else "e"]
		for zustand in ["normal", "hover", "pressed", "focus"]:
			var st := stil.duplicate() as StyleBoxFlat
			if zustand in ["hover", "focus"]:
				st.border_color = Color.WHITE
			b.add_theme_stylebox_override(zustand, st)
		var vor_namen: Array = k.vor.map(func(v): return Meta.forschung_def(v).name)
		var tip := "%s  (%s)\n%s\nKosten: %d Punkt%s%s" % [k.name, k.zweig, k.text, k.kosten, "" if int(k.kosten) == 1 else "e",
			("\nBraucht: " + ", ".join(vor_namen)) if not vor_namen.is_empty() else ""]
		var warum := "Schon erforscht" if fertig else ("Erst " + ", ".join(vor_namen) + " erforschen" if not Meta.voraussetzungen_erfuellt(id) else "Zu wenig Forschungspunkte")
		b.tooltip_text = tip
		_knopf(b, moeglich, tip, func(): return Meta.erforschen(id), warum)
		if fertig:
			b.modulate = Color.WHITE
		flaeche.add_child(b)


## Module: oben die vier Steckplätze, darunter das Inventar (nach Platz und Seltenheit sortiert).
## A/Klick baut ein (das alte geht ins Inventar), Y/Rechtsklick zerlegt zu Bauteilen.
func _module_ansicht(links: VBoxContainer) -> void:
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 16)
	links.add_child(kopf)
	var info := _label("Bauteile %d · Kristalle %d · Inventar %d/%d   ·   A einbauen · Y zerlegen · X aufwerten" % [
		Meta.bauteile, Meta.kristalle, Meta.module.size(), Meta.inventar_max()], 14, ART_FARBE.module, false)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(info)
	var alle := Button.new()
	alle.name = "ZerlegeGewoehnliche"
	alle.text = "Gewöhnliche zerlegen"
	alle.add_theme_font_size_override("font_size", 14)
	var gewoehnliche_zerlegen := func() -> bool:
		for i in range(Meta.module.size() - 1, -1, -1):
			if int(Meta.module[i].selten) == 0:
				Meta.modul_zerlegen(i)
		return true
	_knopf(alle, true, "Alle grauen Module im Inventar zu Bauteilen zerlegen", gewoehnliche_zerlegen, "")
	kopf.add_child(alle)
	# Steckplätze
	var plaetze := HBoxContainer.new()
	plaetze.add_theme_constant_override("separation", 8)
	links.add_child(plaetze)
	for platz in Module.PLATZ_REIHE:
		var m: Dictionary = Meta.eingebaut.get(platz, {})
		var leer := m.is_empty()
		var farbe: Color = Color(0.4, 0.4, 0.4) if leer else Module.farbe(m)
		var b := Button.new()
		b.name = "Platz_" + platz
		b.custom_minimum_size = Vector2(0, 70)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_BOTTOM
		b.text = "\n\n\n" + (("leer · " + Module.PLAETZE[platz].name) if leer else Module.name_von(m))
		b.add_theme_stylebox_override("normal", _modul_stil(farbe, not leer))
		b.add_theme_stylebox_override("hover", _modul_stil(Color.WHITE, not leer))
		b.add_theme_stylebox_override("focus", _modul_stil(Color.WHITE, not leer))
		b.add_theme_color_override("font_color", farbe.lerp(Color.WHITE, 0.3))
		var sym := WaffenSymbol.new(Module.PLAETZE[platz].symbol, farbe)
		sym.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sym.offset_top = 4
		sym.offset_bottom = -30      # oberer Teil des Knopfs, darunter steht der Name
		b.add_child(sym)
		var tip := ("Steckplatz %s: leer — Module fallen von Gegnern (Bosse immer)" % Module.PLAETZE[platz].name) if leer else "Eingebaut: " + Module.beschreibung(m)
		b.tooltip_text = tip
		_knopf(b, not leer, tip, func(): return false, tip)
		plaetze.add_child(b)
	# Inventar
	var reihe := []
	for i in Meta.module.size():
		reihe.append(i)
	reihe.sort_custom(func(a, b):
		var ma: Dictionary = Meta.module[a]
		var mb: Dictionary = Meta.module[b]
		var pa := Module.PLATZ_REIHE.find(ma.platz)
		var pb := Module.PLATZ_REIHE.find(mb.platz)
		return pa < pb if pa != pb else int(ma.selten) > int(mb.selten))
	var gitter := GridContainer.new()
	gitter.name = "Inventar"
	gitter.columns = 6
	gitter.add_theme_constant_override("h_separation", 6)
	gitter.add_theme_constant_override("v_separation", 6)
	links.add_child(gitter)
	if reihe.is_empty():
		links.add_child(_label("Noch keine Module. Sie fallen von Gegnern (5 %), vom Reaktor (30 %) und von jedem Boss.", 15, Color(0.6, 0.58, 0.52), false))
	for i in reihe:
		var m: Dictionary = Meta.module[i]
		var b := Button.new()
		b.name = "Modul_%d" % i
		b.set_meta("modul_index", i)
		b.custom_minimum_size = Vector2(112, 36)
		b.add_theme_font_size_override("font_size", 12)
		b.text = "%s · T%d" % [Module.PLAETZE[m.platz].name, m.stufe]
		var farbe := Module.farbe(m)
		b.add_theme_stylebox_override("normal", _modul_stil(farbe, false))
		b.add_theme_stylebox_override("hover", _modul_stil(Color.WHITE, false))
		b.add_theme_stylebox_override("focus", _modul_stil(Color.WHITE, false))
		b.add_theme_color_override("font_color", farbe)
		var alt: Dictionary = Meta.eingebaut.get(m.platz, {})
		# Zwei Zeilen fürs Infofeld: Name + was es ersetzt, dann die Eigenschaften und der Zerlegewert
		var ak := Meta.aufwert_kosten(m)
		var auf_text := ("aufwerten %d Kr + %d Bt" % [ak[0], ak[1]]) if int(m.get("auf", 0)) < Meta.gebaeude_stufe("werkstatt") else "aufwerten: Werkstatt nötig"
		var tip := "%s   ·   ersetzt: %s\n%s   ·   zerlegen +%d Bt   ·   %s" % [Module.beschreibung(m).get_slice("\n", 0),
			Module.name_von(alt) if not alt.is_empty() else "nichts", Module.beschreibung(m).get_slice("\n", 1), Module.bauteile_wert(m), auf_text]
		b.tooltip_text = tip
		var idx: int = i
		_knopf(b, true, tip, func(): return Meta.modul_einbauen(idx), "")
		b.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
				modul_zerlegen_knopf(idx)
			elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and e.shift_pressed:
				modul_aufwerten_knopf(idx)
				get_viewport().set_input_as_handled())
		gitter.add_child(b)


## Pakt: acht Erschwernisse als Schalter (A/Klick: eine Stufe weiter, nach der höchsten wieder aus).
func _pakt_ansicht(links: VBoxContainer) -> void:
	var p := Meta.pakt_punkte()
	var meilen: Array[String] = []
	for m in Meta.PAKT_MEILENSTEINE:
		meilen.append("Pakt %d: %s %s" % [m[0], Module.SELTEN[m[1]].name.to_lower(), "erhalten" if m[0] in Meta.pakt_meilen else "offen"])
	var rek: Dictionary = Meta.pakt_rekord
	links.add_child(_label("Pakt %d aktiv  ·  +%d %% Erz, Module öfter  ·  Rekord: Pakt %d bis Tiefe %d" % [
		p, p * 10, rek.punkte, rek.tiefe], 15, ART_FARBE.pakt, false))
	links.add_child(_label("Meilensteine (Boss besiegen): " + "  ·  ".join(meilen), 13, Color(0.75, 0.7, 0.62), false))
	var gitter := GridContainer.new()
	gitter.name = "PaktListe"
	gitter.columns = 2
	gitter.add_theme_constant_override("h_separation", 8)
	gitter.add_theme_constant_override("v_separation", 6)
	links.add_child(gitter)
	var frei := Meta.pakt_frei()
	for e in Meta.PAKT:
		var id: String = e.id
		var st := Meta.pakt_stufe(id)
		var mx := int(e.max)
		var b := Button.new()
		b.name = "Pakt_" + id
		b.custom_minimum_size = Vector2(355, 50)
		b.add_theme_font_size_override("font_size", 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   %s   (%d Punkt%s je Stufe)\n%s" % [e.name, "●".repeat(st) + "○".repeat(mx - st), e.punkte,
			"" if int(e.punkte) == 1 else "e", e.text]
		var farbe := ART_FARBE.pakt if st > 0 else Color(0.5, 0.45, 0.42)
		b.add_theme_stylebox_override("normal", _modul_stil(farbe, st > 0))
		b.add_theme_stylebox_override("hover", _modul_stil(Color.WHITE, st > 0))
		b.add_theme_stylebox_override("focus", _modul_stil(Color.WHITE, st > 0))
		b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.8) if st > 0 else Color(0.75, 0.72, 0.68))
		var tip := "%s: Stufe %d/%d — A/Klick schaltet eine Stufe weiter\n%s" % [e.name, st, mx, e.text]
		_knopf(b, frei, tip, func(): return Meta.pakt_umschalten(id), "Der Pakt wird mit dem ersten besiegten Boss (Tiefe 5) freigeschaltet")
		gitter.add_child(b)


func _modul_stil(farbe: Color, gefuellt: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(farbe.r * 0.2, farbe.g * 0.2, farbe.b * 0.2) if gefuellt else Color(0.06, 0.055, 0.05)
	st.border_color = farbe
	st.set_border_width_all(2)
	st.set_corner_radius_all(5)
	st.set_content_margin_all(4)
	return st


func modul_aufwerten_knopf(index: int) -> void:
	if index < 0 or index >= Meta.module.size():
		return
	var m: Dictionary = Meta.module[index]
	if not Meta.modul_aufwerten(m):
		_info_zeigen("Aufwerten geht nicht: " + ("Werkstatt ausbauen" if int(m.get("auf", 0)) >= Meta.gebaeude_stufe("werkstatt") else "zu wenig Kristalle oder Bauteile"), true)
		return
	_fokus_merken = "Modul_%d" % index
	aufbauen()


## Station: vier Gebäude als Karten mit Stufenpunkten, Wirkung und Kosten.
func _station_ansicht(links: VBoxContainer) -> void:
	links.add_child(_label("Erz %d   ·   Kristalle %d   ·   Bauteile %d" % [Meta.bank, Meta.kristalle, Meta.bauteile],
		16, ART_FARBE.station, false))
	var raster := GridContainer.new()
	raster.name = "Gebaeude"
	raster.columns = 2
	raster.add_theme_constant_override("h_separation", 10)
	raster.add_theme_constant_override("v_separation", 8)
	links.add_child(raster)
	for gb in Meta.GEBAEUDE:
		var id: String = gb.id
		var st := Meta.gebaeude_stufe(id)
		var farbe: Color = ART_FARBE.station
		var karte := PanelContainer.new()
		karte.custom_minimum_size = Vector2(350, 0)
		karte.add_theme_stylebox_override("panel", _modul_stil(farbe if st > 0 else Color(0.4, 0.45, 0.43), st > 0))
		var sp := VBoxContainer.new()
		sp.add_theme_constant_override("separation", 2)
		karte.add_child(sp)
		var kopf := HBoxContainer.new()
		sp.add_child(kopf)
		var sym := WaffenSymbol.new("auf_" + id, farbe)
		sym.custom_minimum_size = Vector2(44, 44)
		kopf.add_child(sym)
		var txt := VBoxContainer.new()
		txt.add_theme_constant_override("separation", 0)
		kopf.add_child(txt)
		txt.add_child(_label("%s   %s" % [gb.name, "●".repeat(st) + "○".repeat(3 - st)], 16, farbe if st > 0 else Color(0.8, 0.8, 0.78), false))
		var t := _label(gb.text, 12, Color(0.75, 0.72, 0.68), false)
		txt.add_child(t)
		var b := Button.new()
		b.name = "Bau_" + id
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 13)
		var k := Meta.gebaeude_kosten(id)
		var tip := "%s: Stufe %d/3 — %s" % [gb.name, st, gb.text]
		if k.is_empty():
			b.text = "ganz ausgebaut"
			_knopf(b, false, tip, func(): return false, "Schon ganz ausgebaut")
		else:
			b.text = "%s · %d Erz · %d Kristalle · %d Bauteile" % ["Bauen" if st == 0 else "Ausbauen", k[0], k[1], k[2]]
			_knopf(b, Meta.ausbaubar(id), tip, func(): return Meta.ausbauen(id), "Zu wenig Erz, Kristalle oder Bauteile")
		sp.add_child(b)
		raster.add_child(karte)


func modul_zerlegen_knopf(index: int) -> void:
	Meta.modul_zerlegen(index)
	_fokus_merken = "Modul_%d" % mini(index, Meta.module.size() - 1)
	aufbauen()


func reiter_waehlen(id: String) -> void:
	if id == _reiter:
		return
	_reiter = id
	_fokus_merken = "Reiter_" + id
	aufbauen()


func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var schritt := 0
	if e.is_action_pressed("rollen_rechts"):
		schritt = 1
	elif e.is_action_pressed("rollen_links"):
		schritt = -1
	# X auf einem Inventar-Modul: aufwerten (Werkstatt)
	if e.is_action_pressed("nachbrenner") and not Input.is_key_pressed(KEY_SHIFT):
		var fx := get_viewport().gui_get_focus_owner()
		if fx != null and fx.has_meta("modul_index"):
			modul_aufwerten_knopf(int(fx.get_meta("modul_index")))
			get_viewport().set_input_as_handled()
		return
	# Y auf einem Inventar-Modul: zerlegen
	if e.is_action_pressed("licht"):
		var f := get_viewport().gui_get_focus_owner()
		if f != null and f.has_meta("modul_index"):
			modul_zerlegen_knopf(int(f.get_meta("modul_index")))
			get_viewport().set_input_as_handled()
		return
	if schritt == 0:
		return
	var ids: Array = Meta.REITER.map(func(r): return r[0])
	reiter_waehlen(ids[(ids.find(_reiter) + schritt + ids.size()) % ids.size()])
	get_viewport().set_input_as_handled()


## Aufrüstung als Karte wie die Waffen: Stufenpunkte, Symbol, Kaufknopf; Wirkung im Tooltip.
func _aufruestkarte(a: Dictionary) -> Control:
	var st := Meta.stufe(a.id)
	var farbe: Color = AUF_FARBE.get(a.id, ART_FARBE.get(a.art, ORANGE))
	var frei := Meta.freigeschaltet(a.id)
	if not frei:
		farbe = farbe.lerp(Color(0.45, 0.45, 0.45), 0.7)
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
	var mx := int(a.max)
	var meister := Meta.meisterstufe(a.id)
	var punkte := _label("●".repeat(mini(st, mx)) + "○".repeat(maxi(mx - st, 0)) + ("   Meister %d" % meister if meister > 0 else ""), 15, farbe, true)
	punkte.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spalte.add_child(punkte)
	var sym := WaffenSymbol.new("auf_" + a.id, farbe)
	sym.custom_minimum_size = Vector2(0, 58)
	spalte.add_child(sym)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 16)
	var id: String = a.id
	b.name = "Knopf_" + id
	var tip := _aufruest_tooltip(a, st)
	if not frei:
		b.text = "gesperrt · Boss %d" % int(a.boss)
		_knopf(b, false, tip, func(): return false, "Gesperrt: erst Boss %d besiegen" % int(a.boss))
	elif Meta.ausgereizt(id):
		b.text = "ausgebaut"
		_knopf(b, false, tip, func(): return false, "Schon ganz ausgebaut")
	elif st >= mx:
		b.text = "Meister · %d" % Meta.kosten(id)
		_knopf(b, Meta.kaufbar(id), tip, func(): return Meta.kaufen(id), "Zu wenig Erz")
	else:
		b.text = "Kaufen · %d" % Meta.kosten(id)
		_knopf(b, Meta.kaufbar(id), tip, func(): return Meta.kaufen(id), "Zu wenig Erz")
	spalte.add_child(b)
	karte.tooltip_text = tip
	b.tooltip_text = tip
	return karte


func _aufruest_tooltip(a: Dictionary, st: int) -> String:
	var mx := int(a.max)
	var stand := "Stufe %d/%d" % [mini(st, mx), mx] + (" · Meister %d" % (st - mx) if st > mx else "")
	var zeilen: Array[String] = ["%s   %s" % [a.name, stand], a.text + " je Stufe"]
	var naechste := "" if Meta.ausgereizt(a.id) else " → " + Meta.wirkung_text(a.id, st + 1)
	zeilen.append("Jetzt: %s%s" % [Meta.wirkung_text(a.id, st), naechste])
	if Meta.hat_meisterschaft(a.id):
		zeilen.append("Nach Stufe %d endlos weiter als Meisterschaft" % mx)
	if not Meta.freigeschaltet(a.id):
		zeilen.append("Gesperrt bis Boss %d besiegt ist" % int(a.boss))
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
	# Höchstens zwei Zeilen, damit das Feld die Seite nicht nach unten schiebt: ab Zeile 2 alles in eine Zeile.
	var zeilen := text.split("\n")
	_info.text = zeilen[0] if zeilen.size() == 1 else zeilen[0] + "\n" + "   ·   ".join(zeilen.slice(1))
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


## Starttiefe: von vorne oder direkt nach einem schon besiegten Boss (6, 11, …).
## Knöpfe in einer Reihe, damit sie mit dem Steuerkreuz erreichbar sind.
var _start_knoepfe: Array[Button] = []


func _starttiefe_zeile(spalte: VBoxContainer) -> void:
	_start_knoepfe.clear()
	var reihe := HFlowContainer.new()
	reihe.alignment = FlowContainer.ALIGNMENT_CENTER
	reihe.add_theme_constant_override("h_separation", 10)
	reihe.add_theme_constant_override("v_separation", 8)
	reihe.name = "Starttiefen"
	spalte.add_child(reihe)
	var titel := _label("STARTTIEFE", 20, ORANGE, false)
	titel.custom_minimum_size = Vector2(150, 0)
	titel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reihe.add_child(titel)
	var gruppe := ButtonGroup.new()
	var gewaehlt := Meta.gueltige_starttiefe()
	for t in Meta.starttiefen():
		var b := Button.new()
		b.name = "Start_%d" % t
		b.text = "Tiefe 1 · von vorne" if t == 1 else "Tiefe %d · nach Boss %d" % [t, t - 1]
		b.toggle_mode = true
		b.button_group = gruppe
		b.button_pressed = t == gewaehlt
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 18)
		# Die gewählte Tiefe orange umrandet und beschriftet, damit sie ohne Fokus erkennbar ist.
		var gedrueckt := StyleBoxFlat.new()
		gedrueckt.bg_color = Color(0.25, 0.14, 0.05)
		gedrueckt.set_border_width_all(2)
		gedrueckt.border_color = ORANGE
		# Gleiche Innenabstände wie der normale Knopf: sonst passt die Breite nach dem Umschalten nicht mehr.
		var normal := b.get_theme_stylebox("normal")
		for seite in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			gedrueckt.set_content_margin(seite, normal.get_content_margin(seite))
		b.add_theme_stylebox_override("pressed", gedrueckt)
		b.add_theme_stylebox_override("hover_pressed", gedrueckt)
		b.add_theme_color_override("font_pressed_color", ORANGE)
		b.add_theme_color_override("font_hover_pressed_color", ORANGE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
		var tip := "Der Lauf beginnt in Tiefe %d." % t
		b.tooltip_text = tip
		b.focus_entered.connect(func(): _info_zeigen(tip))
		b.pressed.connect(func():
			Meta.start_tiefe = t
			Meta.speichern())
		reihe.add_child(b)
		_start_knoepfe.append(b)
	if Meta.starttiefen().size() == 1:
		reihe.add_child(_label("Weitere Starttiefen nach dem ersten besiegten Boss (Tiefe 5).", 16, Color(0.6, 0.58, 0.52), false))


func _label(text: String, groesse: int, farbe: Color, zentriert: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", groesse)
	l.add_theme_color_override("font_color", farbe)
	if zentriert:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

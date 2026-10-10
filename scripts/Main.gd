extends Node3D
## Ablauf: Hangar → Tiefe 1 → Reaktor zerstören → zum Ausgang → Tiefe 2 → … bis zum Tod.
## Mit `-- --autotest` fliegt ein Autopilot zwei Tiefen durch und legt Bilder in pruefung/ ab.

var gen := LevelGen.new()
var spiel: Node3D
var schiff: Schiff
var level: Node3D
var reaktor: Reaktor
var ausgang: Ausgang
var hud: HUD
var hangar: Hangar
var hangar_ebene: CanvasLayer
var pause_ebene: CanvasLayer
var umgebung: WorldEnvironment
var thema: Dictionary

var zustand := "hangar"   ## hangar | flug | wechsel | tot
var tiefe := 0
var level_erz := 0
var lauf_erz := 0
var countdown := -1.0
var leitstrahl := true
var autotest := false
var _leit_t := 0.0
var _leit_ziel := Vector3.ZERO
var _leit_weg := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	autotest = "--autotest" in OS.get_cmdline_user_args()
	umgebung = WorldEnvironment.new()
	umgebung.environment = Environment.new()
	add_child(umgebung)
	spiel = Node3D.new()
	spiel.name = "Spiel"
	spiel.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(spiel)
	hud = HUD.new()
	hud.visible = false
	add_child(hud)
	hangar_ebene = CanvasLayer.new()
	hangar_ebene.layer = 10
	add_child(hangar_ebene)
	hangar = Hangar.new()
	hangar.starten.connect(_starte_lauf)
	hangar.beenden.connect(func(): get_tree().quit())
	hangar_ebene.add_child(hangar)
	_pause_bauen()
	if autotest:
		_autotest()
	else:
		_zeige_hangar()


# --- Ablauf -----------------------------------------------------------------

func _zeige_hangar() -> void:
	zustand = "hangar"
	get_tree().paused = false
	pause_ebene.visible = false
	if level:
		level.queue_free()
		level = null
	if schiff:
		schiff.queue_free()
		schiff = null
	hud.visible = false
	hangar.aufbauen()
	hangar_ebene.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _starte_lauf() -> void:
	Meta.laeufe += 1
	Meta.speichern()
	tiefe = 1
	lauf_erz = 0
	schiff = Schiff.new()
	schiff.werte_setzen(Meta.schiffswerte())
	schiff.gestorben.connect(func(): _schiff_tot("Schiff zerstört"))
	schiff.getroffen.connect(func(s: float): hud.blitz(s))
	schiff.erz_gefunden.connect(func(m: int): level_erz += m)
	spiel.add_child(schiff)
	hangar_ebene.visible = false
	hud.visible = true
	Protokoll.schreib("lauf", "Lauf %d beginnt, Werte %s" % [Meta.laeufe, Meta.schiffswerte()])
	_lade_level()


func _lade_level() -> void:
	var t0 := Time.get_ticks_msec()
	zustand = "flug"
	countdown = -1.0
	level_erz = 0
	if level:
		level.queue_free()
	var saat := _rng.randi()
	gen.erzeuge(saat, tiefe)
	thema = Themen.fuer_tiefe(tiefe)
	level = LevelBau.baue(gen, thema, Texturen.materialien(thema, saat))
	spiel.add_child(level)
	_umgebung_setzen()
	Meta.rekord = maxi(Meta.rekord, tiefe)
	Meta.speichern()

	var sr := gen.raeume[gen.start_raum]
	var start_pos := LevelGen.welt_von(sr.pos)
	ausgang = Ausgang.new()
	ausgang.position = LevelGen.welt_von(sr.pos + sr.groesse - Vector3i.ONE)
	ausgang.erreicht.connect(_ausgang_erreicht)
	level.add_child(ausgang)
	schiff.global_position = start_pos
	schiff.velocity = Vector3.ZERO
	var blick := gen.mitte(gen.start_raum)
	blick.y = start_pos.y
	schiff.look_at(blick, Vector3.UP)
	schiff.welt = level
	schiff.aktiv = true
	schiff.autopilot.clear()

	reaktor = Reaktor.new()
	reaktor.einrichten(tiefe, thema.kern)
	reaktor.position = gen.mitte(gen.reaktor_raum)
	reaktor.ziel = schiff
	reaktor.welt = level
	reaktor.zerstoert.connect(_reaktor_weg)
	level.add_child(reaktor)

	var gegner_zahl := _gegner_setzen()
	var t := Time.get_ticks_msec() - t0
	Protokoll.schreib("level", "Tiefe %d, Saat %d, Thema %s, Räume %d, Zellen %d, Gegner %d, Fluchtzeit %.0f s, Aufbau %d ms" % [
		tiefe, saat, thema.name, gen.raeume.size(), gen.zellen.size(), gegner_zahl, gen.fluchtzeit(), t])
	hud.setze_tiefe(tiefe, thema.name)
	hud.mitteilung("TIEFE %d\n%s" % [tiefe, thema.name])
	hud.status("Ziel: Reaktor zerstören")
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _gegner_setzen() -> int:
	var zahl := 0
	var pool := ["jaeger", "jaeger", "geschuetz"]
	if tiefe >= 3:
		pool.append("waechter")
	if tiefe >= 6:
		pool.append_array(["waechter", "jaeger"])
	for i in gen.raeume.size():
		if i == gen.start_raum:
			continue
		var zellen := gen.zellen_von_raum(i)
		var n := _rng.randi_range(1, mini(2 + tiefe / 2, 7))
		if i == gen.reaktor_raum:
			n += 2
		for j in n:
			var pos := LevelGen.welt_von(zellen[_rng.randi_range(0, zellen.size() - 1)])
			pos += Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.5, 1.5))
			if i == gen.reaktor_raum and pos.distance_to(reaktor.position) < 4.5:
				pos = reaktor.position + (pos - reaktor.position).normalized() * 4.5
			_gegner(pool[_rng.randi_range(0, pool.size() - 1)], pos)
			zahl += 1
		if _rng.randf() < 0.35:
			var art: String = ["schild", "reparatur", "energie", "rakete", "erz", "erz"][_rng.randi_range(0, 5)]
			level.add_child(Beute.neu(art, LevelGen.welt_von(zellen[_rng.randi_range(0, zellen.size() - 1)])))
		# Wache im langen Stollen davor
		var weg: Array = gen.raeume[i].tunnel
		if weg.size() >= 5 and _rng.randf() < 0.4:
			_gegner("jaeger", LevelGen.welt_von(weg[weg.size() / 2]))
			zahl += 1
	return zahl


func _gegner(typ: String, pos: Vector3) -> void:
	var g := Gegner.new()
	g.einrichten(typ, tiefe)
	g.position = pos
	g.ziel = schiff
	g.welt = level
	g.zerstoert.connect(_gegner_weg)
	level.add_child(g)


func _umgebung_setzen() -> void:
	var e := umgebung.environment
	e.background_mode = Environment.BG_COLOR
	e.background_color = thema.nebel
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = thema.umgebung
	e.ambient_light_energy = 0.35
	e.fog_enabled = true
	e.fog_light_color = thema.nebel
	e.fog_density = 0.012
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_hdr_threshold = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC


func _gegner_weg(g: Gegner) -> void:
	var b := Beute.neu("erz", g.global_position, g.erz)
	level.add_child.call_deferred(b)
	if _rng.randf() < 0.2:
		var art: String = ["schild", "reparatur", "energie", "rakete"][_rng.randi_range(0, 3)]
		level.add_child.call_deferred(Beute.neu(art, g.global_position + Vector3(0, 1.2, 0)))


func _reaktor_weg() -> void:
	countdown = gen.fluchtzeit()
	level_erz += 10 + 5 * tiefe
	ausgang.oeffnen()
	hud.mitteilung("REAKTOR ZERSTÖRT", 2.0, HUD.ROT)
	Protokoll.schreib("level", "Reaktor zerstört auf Tiefe %d, Fluchtzeit %.0f s" % [tiefe, countdown])


func _ausgang_erreicht() -> void:
	if zustand != "flug":
		return
	zustand = "wechsel"
	Meta.bank += level_erz
	lauf_erz += level_erz
	Meta.speichern()
	Protokoll.schreib("level", "Tiefe %d geschafft, %d Erz gesichert (Lauf %d, Bank %d), Restzeit %.0f s" % [
		tiefe, level_erz, lauf_erz, Meta.bank, countdown])
	tiefe += 1
	schiff.schild = minf(schiff.schild_max, schiff.schild + 30.0)
	schiff.huelle = minf(schiff.huelle_max, schiff.huelle + 30.0)
	call_deferred("_lade_level")


func _schiff_tot(grund: String) -> void:
	if zustand != "flug":
		return
	zustand = "tot"
	schiff.aktiv = false
	Effekte.explosion(level, schiff.global_position, Color(1.0, 0.5, 0.2), 6.0)
	var gerettet := level_erz / 2
	Meta.bank += gerettet
	lauf_erz += gerettet
	Meta.speichern()
	Protokoll.schreib("lauf", "%s auf Tiefe %d, Erz im Lauf %d (davon %d aus dieser Tiefe gerettet), Bank %d" % [
		grund, tiefe, lauf_erz, gerettet, Meta.bank])
	hud.status("")
	hud.mitteilung("%s\nTiefe %d erreicht · %d Erz gesichert" % [grund.to_upper(), tiefe, lauf_erz], 3.5, HUD.ROT)
	await get_tree().create_timer(4.5).timeout
	if not autotest:
		_zeige_hangar()


# --- Jedes Bild ----------------------------------------------------------------

func _process(dt: float) -> void:
	if Input.is_action_just_pressed("pause") and zustand == "flug" and not autotest:
		_pause(not get_tree().paused)
	if get_tree().paused or schiff == null or zustand != "flug":
		return
	if Input.is_action_just_pressed("leitstrahl"):
		leitstrahl = not leitstrahl
	if countdown >= 0.0:
		countdown -= dt
		var blink := HUD.ROT if fmod(countdown, 1.0) > 0.5 else HUD.GELB
		hud.status("SELBSTZERSTÖRUNG  %d:%02d  —  zum Ausgang!" % [int(countdown) / 60, int(countdown) % 60], blink)
		if countdown <= 0.0:
			countdown = -1.0
			_schiff_tot("Die Mine ist explodiert")
			return
	hud.setze_erz(level_erz, lauf_erz, Meta.bank)
	_leitstrahl(dt)
	hud.werte(schiff)


func _leitstrahl(dt: float) -> void:
	hud.leit_an = leitstrahl
	if not leitstrahl:
		return
	var ziel_pos := ausgang.global_position if reaktor.kaputt else reaktor.global_position
	_leit_t -= dt
	if _leit_t <= 0.0:
		_leit_t = 0.3
		var p := gen.pfad(gen.naechste_zelle(schiff.global_position), gen.naechste_zelle(ziel_pos))
		_leit_ziel = ziel_pos if p.size() <= 3 else LevelGen.welt_von(p[3])
		_leit_weg = maxf(p.size() - 1, 0) * LevelGen.ZELLE
	hud.leit_text = "%d m" % int(_leit_weg)
	var cam := schiff.kamera
	var vp := get_viewport().get_visible_rect().size
	if not cam.is_position_behind(_leit_ziel):
		var sp := cam.unproject_position(_leit_ziel)
		if Rect2(Vector2.ZERO, vp).grow(-40.0).has_point(sp):
			hud.leit_pos = sp
			hud.leit_rand = false
			return
	var lokal := cam.global_transform.affine_inverse() * _leit_ziel
	var r := Vector2(lokal.x, -lokal.y)
	r = Vector2(0, 1) if r.length_squared() < 0.0001 else r.normalized()
	var mitte := vp / 2.0
	var rand := mitte - Vector2(50, 50)
	var k := minf(rand.x / maxf(absf(r.x), 0.0001), rand.y / maxf(absf(r.y), 0.0001))
	hud.leit_pos = mitte + r * k
	hud.leit_rand = true
	hud.leit_richtung = r


# --- Pause --------------------------------------------------------------------

func _pause_bauen() -> void:
	pause_ebene = CanvasLayer.new()
	pause_ebene.layer = 20
	pause_ebene.visible = false
	add_child(pause_ebene)
	var grund := ColorRect.new()
	grund.color = Color(0, 0, 0, 0.6)
	grund.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_ebene.add_child(grund)
	var mitte := CenterContainer.new()
	mitte.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_ebene.add_child(mitte)
	var spalte := VBoxContainer.new()
	spalte.custom_minimum_size = Vector2(420, 0)
	spalte.add_theme_constant_override("separation", 12)
	mitte.add_child(spalte)
	var titel := Label.new()
	titel.text = "PAUSE"
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titel.add_theme_font_size_override("font_size", 56)
	titel.add_theme_color_override("font_color", Hangar.ORANGE)
	spalte.add_child(titel)
	for eintrag in [["Weiter", func(): _pause(false)],
			["Lauf aufgeben", func():
				_pause(false)
				_schiff_tot("Lauf aufgegeben")],
			["Spiel beenden", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = eintrag[0]
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(eintrag[1])
		spalte.add_child(b)


func _pause(an: bool) -> void:
	get_tree().paused = an
	pause_ebene.visible = an
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if an else Input.MOUSE_MODE_CAPTURED
	if an:
		var erster: Button = pause_ebene.find_children("*", "Button", true, false)[0]
		erster.grab_focus()


# --- Selbsttest ---------------------------------------------------------------

func _autotest() -> void:
	Protokoll.schreib("test", "Autotest beginnt, Audiotreiber %s" % AudioServer.get_driver_name())
	# Den echten Spielton mitschneiden: Aufnahme am Master-Bus.
	var aufnahme := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, aufnahme)
	aufnahme.set_recording_active(true)
	_starte_lauf()
	schiff.unverwundbar = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--start-tiefe="):
			tiefe = int(a.get_slice("=", 1))
			_lade_level()
	var abdruecke := [gen.fingerabdruck()]
	var ok := true
	for runde in 2:
		var t := tiefe
		await _warte(1.5)
		_foto("tiefe%d_1_start" % t)
		for i in 6:                      # Spielerlaser: dieselbe Funktion wie die Feuertaste
			schiff.laser_schuss()
			await _warte(0.15)
		var opfer := get_tree().get_nodes_in_group("gegner")
		if not opfer.is_empty():
			opfer[0].treffer(1.0e9)          # Roboterexplosion samt Ton
			Protokoll.schreib("test", "Roboter zerstört bei %s" % opfer[0].global_position)
			await _warte(1.0)
		if runde == 0:
			# Hülle sichtbar machen: 130 Schaden = Schild leer, Hülle 70
			schiff.unverwundbar = false
			schiff.treffer(130.0)
			schiff.unverwundbar = true
			Protokoll.schreib("test", "Nach 130 Schaden: Schild %.0f, Hülle %.0f" % [schiff.schild, schiff.huelle])
			await _warte(0.6)
			_foto("tiefe%d_0_huelle" % t)
		# Zum Reaktor: Pfad bis kurz vor den Kern, der Autopilot würde sonst gegen ihn drücken.
		var weg := gen.pfad(gen.naechste_zelle(schiff.global_position), gen.naechste_zelle(reaktor.global_position))
		for z in weg:
			if LevelGen.welt_von(z).distance_to(reaktor.global_position) > 7.0:
				schiff.autopilot.append(LevelGen.welt_von(z))
		var t0 := Time.get_ticks_msec()
		while not schiff.autopilot.is_empty() and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().process_frame
		var abstand := schiff.global_position.distance_to(reaktor.global_position)
		var im_raum: bool = gen.zellen.get(gen.naechste_zelle(schiff.global_position), -2) == gen.reaktor_raum
		var angekommen := schiff.autopilot.is_empty() and (im_raum or abstand < 14.0)
		Protokoll.schreib("test", "Tiefe %d: Flug zum Reaktor über %d Zellen in %.1f s, Restabstand %.1f m → %s" % [
			t, weg.size(), (Time.get_ticks_msec() - t0) / 1000.0, abstand, "angekommen" if angekommen else "STECKENGEBLIEBEN"])
		ok = ok and angekommen
		schiff.autopilot.clear()
		schiff.look_at(reaktor.global_position, Vector3.UP)
		await _warte(0.5)
		_foto("tiefe%d_2_reaktor" % t)
		reaktor.treffer(1.0e9)
		await _warte(1.0)
		_foto("tiefe%d_3_flucht" % t)
		# Zurück zum Ausgang
		weg = gen.pfad(gen.naechste_zelle(schiff.global_position), gen.naechste_zelle(ausgang.global_position))
		for z in weg:
			schiff.autopilot.append(LevelGen.welt_von(z))
		schiff.autopilot.append(ausgang.global_position)
		t0 = Time.get_ticks_msec()
		while tiefe == t and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().process_frame
		var gewechselt := tiefe != t
		Protokoll.schreib("test", "Tiefe %d: Ausgang %s nach %.1f s" % [
			t, "erreicht" if gewechselt else "NICHT erreicht", (Time.get_ticks_msec() - t0) / 1000.0])
		ok = ok and gewechselt
		if not gewechselt:
			break
		abdruecke.append(gen.fingerabdruck())
	await _warte(1.5)
	_foto("tiefe%d_1_start" % tiefe)
	var verschieden: bool = abdruecke.size() == 3 and abdruecke[0] != abdruecke[1] and abdruecke[1] != abdruecke[2]
	Protokoll.schreib("test", "Grundrisse verschieden: %s %s" % [verschieden, abdruecke])
	ok = ok and verschieden
	aufnahme.set_recording_active(false)
	var wav := aufnahme.get_recording()
	if wav != null:
		var pfad := ProjectSettings.globalize_path("res://pruefung/ton.wav")
		wav.save_to_wav(pfad)
		Protokoll.schreib("test", "Ton mitgeschnitten: %s, %.1f s" % [pfad, wav.get_length()])
	else:
		Protokoll.schreib("test", "Ton: keine Aufnahme")
	Protokoll.schreib("test", "Abgespielte Töne: %s" % get_node("/root/Klang").zaehler)
	Protokoll.schreib("test", "AUTOTEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))
	get_tree().quit(0 if ok else 1)


func _warte(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _foto(name: String) -> void:
	var ordner := ProjectSettings.globalize_path("res://pruefung")
	DirAccess.make_dir_recursive_absolute(ordner)
	var bild := get_viewport().get_texture().get_image()
	if bild == null:
		Protokoll.schreib("test", "Bild %s übersprungen: keine Grafikausgabe (headless)" % name)
		return
	var pfad := "%s/%s.png" % [ordner, name]
	bild.save_png(pfad)
	Protokoll.schreib("test", "Bild %s (%dx%d)" % [pfad, bild.get_width(), bild.get_height()])

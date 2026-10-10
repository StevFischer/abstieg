extends Node3D
## Ablauf: Hangar → Tiefe 1 → Reaktor zerstören → zum Ausgang → Tiefe 2 → … bis zum Tod.
## Mit `-- --autotest` fliegt ein Autopilot zwei Tiefen durch und legt Bilder in pruefung/ ab.

var gen := LevelGen.new()
var spiel: Node3D
var schiff: Schiff
var level: Node3D
var reaktor: Reaktor
var boss: Gegner
var ausgang: Ausgang
var hud: HUD
var hangar: Hangar
var hangar_ebene: CanvasLayer
var pause_ebene: CanvasLayer
var optionen: Optionen
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
var _opt_zu_bild := -1   ## Bild, in dem die Optionen per Esc geschlossen wurden — dieselbe Esc soll nicht auch die Pause beenden
var _leit_ziel := Vector3.ZERO
var _leit_weg := 0.0
var _rng := RandomNumberGenerator.new()
var _piep_t := 0.0
var _alarm_zeit := 0.0


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
	var opt_ebene := CanvasLayer.new()
	opt_ebene.layer = 30
	add_child(opt_ebene)
	optionen = Optionen.new()
	optionen.visible = false
	opt_ebene.add_child(optionen)
	optionen.zurueck.connect(_optionen_zu)
	hangar.optionen.connect(_optionen_auf)
	if autotest:
		_autotest()
	else:
		_zeige_hangar()
		if "--zeige-optionen" in OS.get_cmdline_user_args():
			_optionen_auf()


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
	schiff.waffen_frei = Meta.waffen_frei()
	schiff.waffe_gewechselt.connect(func(n: String): hud.aufnahme(n, Color(1.0, 0.8, 0.4)))
	schiff.gestorben.connect(func(): _schiff_tot("Schiff zerstört"))
	schiff.getroffen.connect(func(s: float): hud.blitz(s))
	schiff.erz_gefunden.connect(func(m: int): level_erz += m)
	schiff.aufgenommen.connect(func(art: String, m: int):
		hud.aufnahme(Beute.beschriftung(art, m), Beute.ARTEN[art].farbe.lerp(Color.WHITE, 0.3)))
	schiff.voll.connect(func(art: String):
		if art != "erz":
			hud.aufnahme("%s VOLL" % Beute.ARTEN[art].name, Color(0.7, 0.7, 0.7)))
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
	# Wer ab welcher Tiefe dazukommt. Dieb und Reparierer sind Einzelgänger (höchstens 2 je Mine).
	var pool := ["jaeger", "jaeger", "geschuetz"]
	if tiefe >= 2:
		pool.append("kamikaze")
	if tiefe >= 3:
		pool.append("waechter")
	if tiefe >= 4:
		pool.append("schildtraeger")
	if tiefe >= 5:
		pool.append("minenleger")
	if tiefe >= 6:
		pool.append_array(["waechter", "jaeger", "kamikaze"])
	if tiefe >= 8:
		pool.append_array(["tarn", "tarn"])
	if tiefe >= 9:
		pool.append_array(["teleporter", "schildtraeger"])
	var einzel := {"dieb": 0, "reparierer": 0}
	boss = null
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
		# Einzelgänger
		for typ in einzel:
			var ab: int = 6 if typ == "dieb" else 7
			if tiefe >= ab and einzel[typ] < 2 and _rng.randf() < 0.15:
				einzel[typ] += 1
				_gegner(typ, LevelGen.welt_von(zellen[_rng.randi_range(0, zellen.size() - 1)]))
				zahl += 1
		# Schwarm: fünf Drohnen zusammen
		if tiefe >= 3 and i != gen.reaktor_raum and _rng.randf() < 0.25:
			var mitte := LevelGen.welt_von(zellen[_rng.randi_range(0, zellen.size() - 1)])
			for k in 5:
				_gegner("drohne", mitte + Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-1, 1), _rng.randf_range(-2, 2)))
			zahl += 5
		if _rng.randf() < 0.35:
			var art: String = ["schild", "reparatur", "energie", "rakete", "erz", "erz"][_rng.randi_range(0, 5)]
			level.add_child(Beute.neu(art, LevelGen.welt_von(zellen[_rng.randi_range(0, zellen.size() - 1)])))
		# Wache im langen Stollen davor
		var weg: Array = gen.raeume[i].tunnel
		if weg.size() >= 5 and _rng.randf() < 0.4:
			_gegner("jaeger", LevelGen.welt_von(weg[weg.size() / 2]))
			zahl += 1
	if LevelGen.ist_boss_tiefe(tiefe):
		_boss_setzen()
		zahl += 1
	return zahl


## Jede 5. Tiefe: einer von drei Bossen im Wechsel bewacht den Reaktor, der bis dahin geschirmt ist.
func _boss_setzen() -> void:
	var typ: String = Gegner.BOSSE[(tiefe / 5 - 1) % Gegner.BOSSE.size()]
	var r := gen.raeume[gen.reaktor_raum]
	var vor := (gen.mitte(gen.start_raum) - reaktor.position)
	vor.y = 0
	boss = _gegner(typ, reaktor.position + vor.normalized() * 9.0)
	for z in gen.zellen_von_raum(gen.reaktor_raum):
		var p := LevelGen.welt_von(z)
		if p.distance_to(reaktor.position) > 6.0:
			boss.boss_raum.append(p)
	reaktor.schirm_an()
	hud.boss_an(boss.boss_name())
	Protokoll.schreib("level", "Boss %s auf Tiefe %d, Leben %.0f, Raum %s" % [boss.boss_name(), tiefe, boss.hp, r.groesse])


func _gegner(typ: String, pos: Vector3) -> Gegner:
	var g := Gegner.new()
	g.einrichten(typ, tiefe)
	g.position = pos
	g.ziel = schiff
	g.welt = level
	g.zerstoert.connect(_gegner_weg)
	g.verstaerkung.connect(func(t: String, p: Vector3, von: Gegner):
		var neu := _gegner(t, p)
		neu.alarmieren(schiff.global_position)
		if von.typ == "boss_brutmutter":
			neu.add_to_group("brut"))
	g.klaut.connect(_dieb_klaut)
	g.phase_zwei.connect(func(b: Gegner):
		hud.mitteilung("%s — PHASE 2" % b.boss_name(), 1.8, HUD.ROT)
		Protokoll.schreib("level", "Boss %s Phase 2" % b.boss_name()))
	if Engine.is_in_physics_frame():      # aus einem Gegner-Physikschritt heraus (Bossnachschub)
		level.add_child.call_deferred(g)
	else:
		level.add_child(g)
	return g


func _dieb_klaut(g: Gegner) -> void:
	var menge := mini(level_erz, 15 + tiefe * 3)
	level_erz -= menge
	g.beute = menge if menge > 0 else -1
	hud.aufnahme("DIEB! −%d ERZ — abschießen holt es zurück" % menge if menge > 0 else "DIEB! (nichts zu holen)", HUD.ROT)
	Protokoll.schreib("level", "Dieb klaut %d Erz auf Tiefe %d" % [menge, tiefe])


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
	e.glow_intensity = 0.4          # Stev: Leuchteffekte waren übertrieben hell (vorher 0.7 / 0.9)
	e.glow_hdr_threshold = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC


func _gegner_weg(g: Gegner) -> void:
	if g.erz > 0 and not g.ist_boss:
		level.add_child.call_deferred(Beute.neu("erz", g.global_position, g.erz))
	if g.beute > 0:
		level.add_child.call_deferred(Beute.neu("erz", g.global_position + Vector3(0, 0.8, 0), g.beute))
	if g.ist_boss:
		for i in 8:     # Bossbeute: ein Kranz aus Erz
			var p := g.global_position + Vector3(cos(TAU * i / 8.0), 0.3 * (i % 2), sin(TAU * i / 8.0)) * 2.5
			level.add_child.call_deferred(Beute.neu("erz", p, g.erz / 8))
		reaktor.schirm_aus()
		hud.boss_aus()
		hud.mitteilung("%s BESIEGT\nReaktor ungeschützt" % g.boss_name(), 2.5, HUD.GELB)
		Protokoll.schreib("level", "Boss %s besiegt auf Tiefe %d" % [g.boss_name(), tiefe])
		boss = null
	if _rng.randf() < 0.2:
		var art: String = ["schild", "reparatur", "energie", "rakete"][_rng.randi_range(0, 3)]
		level.add_child.call_deferred(Beute.neu(art, g.global_position + Vector3(0, 1.2, 0)))


func _reaktor_weg() -> void:
	countdown = gen.fluchtzeit()
	_alarm_zeit = 0.0
	_piep_t = 2.0                       # erst die Sirene, dann das Piepen
	var klang := get_node("/root/Klang")
	klang.spiele("sirene", null, -2.0)
	get_tree().create_timer(1.7).timeout.connect(func():
		if countdown >= 0.0:
			klang.spiele("sirene", null, -2.0))
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
	if Input.is_action_just_pressed("pause") and zustand == "flug" and not autotest and not optionen.visible \
			and Engine.get_process_frames() != _opt_zu_bild:
		_pause(not get_tree().paused)
	if get_tree().paused or schiff == null or zustand != "flug":
		return
	if Input.is_action_just_pressed("leitstrahl"):
		leitstrahl = not leitstrahl
	if countdown >= 0.0:
		countdown -= dt
		_alarm(dt)
		var blink := HUD.ROT if fmod(countdown, 1.0) > 0.5 else HUD.GELB
		hud.status("SELBSTZERSTÖRUNG  %d:%02d  —  zum Ausgang!" % [int(countdown) / 60, int(countdown) % 60], blink)
		if countdown <= 0.0:
			countdown = -1.0
			_schiff_tot("Die Mine ist explodiert")
			return
	hud.setze_erz(level_erz, lauf_erz, Meta.bank)
	if boss != null and is_instance_valid(boss):
		hud.boss_wert(boss.hp, boss.hp_max)
	_leitstrahl(dt)
	hud.werte(schiff)


## Selbstzerstörung läuft: Minenlicht pulsiert rot, Countdown piept (letzte 10 s doppelt so schnell, höher).
func _alarm(dt: float) -> void:
	_alarm_zeit += dt
	var puls := 0.5 + 0.5 * sin(_alarm_zeit * TAU * 1.2)
	for l in get_tree().get_nodes_in_group("minenlicht"):
		l.light_color = (l.get_meta("farbe") as Color).lerp(Color(1.0, 0.05, 0.02), 0.35 + 0.6 * puls)
	umgebung.environment.ambient_light_color = thema.umgebung.lerp(Color(0.8, 0.05, 0.02), 0.6 * puls)
	_piep_t -= dt
	if _piep_t <= 0.0 and countdown > 0.0:
		var schnell := countdown <= 10.0
		_piep_t = 0.5 if schnell else 1.0
		get_node("/root/Klang").spiele("piep", null, -6.0, 1.35 if schnell else 1.0)


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
			["Optionen", func(): _optionen_auf()],
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


func _optionen_auf() -> void:
	optionen.aufbauen()
	optionen.visible = true


func _optionen_zu() -> void:
	optionen.visible = false
	_opt_zu_bild = Engine.get_process_frames()
	if zustand == "hangar":
		hangar.aufbauen()
	else:
		var erster: Button = pause_ebene.find_children("*", "Button", true, false)[0]
		erster.grab_focus()


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
	# Lautstärke: Regler setzen, Bus messen, aus der Datei neu laden
	var klang := get_node("/root/Klang")
	klang.setze("explosionen", 0.25)
	klang.setze("gegner", 0.0)
	klang.speichern()
	klang.lautstaerke["explosionen"] = 1.0
	klang.laden()
	var bus_ex := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Explosionen"))
	var stumm := AudioServer.is_bus_mute(AudioServer.get_bus_index("Gegner"))
	var lautst_ok: bool = absf(bus_ex - linear_to_db(0.25)) < 0.1 and stumm and is_equal_approx(klang.lautstaerke["explosionen"], 0.25)
	Protokoll.schreib("test", "Lautstärke: Explosionen-Bus %.1f dB nach Neuladen (Soll %.1f), Gegner stumm %s → %s" % [
		bus_ex, linear_to_db(0.25), stumm, "ok" if lautst_ok else "FEHLER"])
	klang.setze("explosionen", 1.0)
	klang.setze("gegner", 1.0)
	klang.speichern()
	_starte_lauf()
	schiff.unverwundbar = true
	# Der Autopilot prüft, ob die Mine befliegbar ist — Roboter im Weg (etwa ein Geschütz im Stollen,
	# belegt 2026-10-10 auf Tiefe 16) würde ein Spieler abschießen; der Autopilot fliegt hindurch.
	schiff.collision_mask = 1
	if "--zeige-waffen" in OS.get_cmdline_user_args():
		await _waffen_schau()
		get_tree().quit(0)
		return
	if "--zeige-neu3" in OS.get_cmdline_user_args():
		await _schau3()
		get_tree().quit(0)
		return
	if "--zeige-gegner2" in OS.get_cmdline_user_args():
		await _gegner_schau2()
		get_tree().quit(0)
		return
	if "--zeige-gegner" in OS.get_cmdline_user_args():
		await _gegner_schau()
		get_tree().quit(0)
		return
	if "--zeige-beute" in OS.get_cmdline_user_args():
		await _beute_schau()
		get_tree().quit(0)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--start-tiefe="):
			tiefe = int(a.get_slice("=", 1))
			_lade_level()
	var abdruecke := [gen.fingerabdruck()]
	var ok := lautst_ok
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
		if boss != null and is_instance_valid(boss):
			var b := boss
			var vorher := reaktor.hp
			reaktor.treffer(500.0)
			var geschuetzt := reaktor.hp == vorher
			b.treffer(b.hp - b.hp_max * 0.45)
			await _warte(2.5)
			_foto("tiefe%d_boss_phase2" % t)
			var phase_ok := is_instance_valid(b) and b.phase == 2
			b.treffer(1.0e9)
			await _warte(0.5)
			var frei := not reaktor.geschirmt
			Protokoll.schreib("test", "Boss Tiefe %d: Reaktor geschirmt %s, Phase 2 %s, nach Sieg Schirm weg %s → %s" % [
				t, geschuetzt, phase_ok, frei, "ok" if geschuetzt and phase_ok and frei else "FEHLER"])
			ok = ok and geschuetzt and phase_ok and frei
		# Zum Reaktor: Pfad bis kurz vor den Kern, der Autopilot würde sonst gegen ihn drücken.
		var weg := gen.pfad(gen.naechste_zelle(schiff.global_position), gen.naechste_zelle(reaktor.global_position))
		for z in weg:
			if LevelGen.welt_von(z).distance_to(reaktor.global_position) > 7.0:
				schiff.autopilot.append(LevelGen.welt_von(z))
		var t0 := Time.get_ticks_msec()
		var bilder := []
		while not schiff.autopilot.is_empty() and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().process_frame
			bilder.append(get_process_delta_time())
		bilder.sort()
		if bilder.size() > 20:
			Protokoll.schreib("test", "Tiefe %d: Bildrate im Flug Mittel %.0f fps, schlechteste 5 %% %.0f fps, %d Gegner, %d Teile gezeichnet" % [
				t, bilder.size() / ((Time.get_ticks_msec() - t0) / 1000.0), 1.0 / bilder[int(bilder.size() * 0.95)],
				get_tree().get_nodes_in_group("gegner").size(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
		var abstand := schiff.global_position.distance_to(reaktor.global_position)
		var im_raum: bool = gen.zellen.get(gen.naechste_zelle(schiff.global_position), -2) == gen.reaktor_raum
		# Angekommen heißt: alle Wegpunkte abgeflogen (der letzte liegt bei kleinen Reaktorräumen im Zugang).
		var angekommen := schiff.autopilot.is_empty() and (im_raum or abstand < 20.0)
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
		var stand_pos := schiff.global_position
		var stand_t := Time.get_ticks_msec()
		while tiefe == t and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().process_frame
			# Messpunkt: hängt der Autopilot 3 s fest, wer steht im Weg?
			if schiff.global_position.distance_to(stand_pos) > 1.0:
				stand_pos = schiff.global_position
				stand_t = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - stand_t > 3000:
				stand_t = Time.get_ticks_msec()
				Protokoll.schreib("test", "FESTGEHANGEN bei %s: %s" % [schiff.global_position.snapped(Vector3.ONE * 0.1), _naechstes_hindernis()])
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


## Jede Waffe auf drei zähe Ziele: Schaden, getroffene Ziele, Splitter — dazu je ein Bild.
func _waffen_schau() -> void:
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	await _warte(3.0)
	var alle := []
	for w in Waffen.LASER + Waffen.RAKETEN:
		alle.append(w.id)
	schiff.waffen_frei = alle
	var vor := -schiff.global_basis.z
	var rechts := schiff.global_basis.x
	var ziele := []
	for i in 3:
		var g := Gegner.new()
		g.einrichten("waechter", 1)
		g.position = schiff.global_position + vor * 13.0 + rechts * (i - 1) * 3.2
		level.add_child(g)
		g.set_physics_process(false)
		g.hp = 100000.0
		ziele.append(g)
	for w in Waffen.LASER + Waffen.RAKETEN:
		schiff.waehle(w.id)
		schiff.energie = schiff.energie_max
		schiff.raketen = 99
		var vorher := []
		for z in ziele:
			vorher.append(z.hp)
		var schuesse := 0
		var splitter_max := 0
		if Waffen.ist_laser(w.id):
			var t0 := Time.get_ticks_msec()
			var foto_gemacht := false
			while Time.get_ticks_msec() - t0 < 1500:
				if schiff._laser_cd <= 0.0 and schiff.energie >= w.energie:
					schiff.laser_schuss()
					schuesse += int(w.anzahl)
				if not foto_gemacht and Time.get_ticks_msec() - t0 > 250:
					_foto("waffe_%s" % w.id)
					foto_gemacht = true
				await get_tree().physics_frame
				schiff._laser_cd -= get_physics_process_delta_time()
		else:
			schiff.raketen_schuss()
			schuesse += int(w.anzahl)
			await _warte(0.25)
			_foto("waffe_%s" % w.id)
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 3500:
				await get_tree().physics_frame
				var kleine := 0
				for k in level.get_children():
					if k is Geschoss and k.rundum:
						kleine += 1
				splitter_max = maxi(splitter_max, kleine)
		await _warte(0.6)
		var schaden := 0.0
		var getroffen := 0
		for i in 3:
			var d: float = vorher[i] - ziele[i].hp
			schaden += d
			if d > 0.0:
				getroffen += 1
		Protokoll.schreib("test", "Waffe %-14s %3d Geschosse, Schaden %6.0f, getroffene Ziele %d%s" % [
			w.name, schuesse, schaden, getroffen, (", Splitter %d" % splitter_max) if splitter_max > 0 else ""])
	Protokoll.schreib("test", "Schiffswerte: Schild %d / %d" % [schiff.schild, schiff.schild_max])


## Portal, Minen gegen Beute, Halle mit Säulen und Lampen, Lampen an echter Decke, Neues-Spiel-Abfrage.
func _schau3() -> void:
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	await _warte(3.5)
	var start := schiff.global_transform
	# Portal zu / offen
	var mitte_start := gen.mitte(gen.start_raum)
	schiff.global_position = ausgang.global_position + (mitte_start - ausgang.global_position).normalized() * 7.0
	schiff.look_at(ausgang.global_position, Vector3.UP)
	await _warte(0.6)
	_foto("neu3_portal_zu")
	schiff.unverwundbar = true
	ausgang.offen = true
	ausgang._zustand_zeigen()
	await _warte(1.2)
	_foto("neu3_portal_offen")
	ausgang.offen = false
	ausgang._zustand_zeigen()
	schiff.global_transform = start
	# Mine neben Beute
	var vor := -schiff.global_basis.z
	var rechts := schiff.global_basis.x
	var mp := schiff.global_position + vor * 7.0
	var m := Mine.neu(mp - rechts * 1.8, 1.0)
	level.add_child(m)
	m.set_physics_process(false)
	level.add_child(Beute.neu("schild", mp + rechts * 1.8))
	level.add_child(Beute.neu("erz", mp))
	await _warte(0.8)
	_foto("neu3_mine_beute")
	m.free()
	# Lampen: jede muss an Decke hängen (Zelle darüber Fels, eigene Zelle befahrbar)
	var falsch := 0
	var lampen := get_tree().get_nodes_in_group("lampe")
	for l in lampen:
		var c := LevelGen.zelle_von(l.global_position - Vector3(0, 1.0, 0))
		if not gen.zellen.has(c) or gen.zellen.has(c + Vector3i.UP):
			falsch += 1
	Protokoll.schreib("test", "Lampen: %d gesamt, %d nicht an echter Decke → %s" % [lampen.size(), falsch, "ok" if falsch == 0 else "FEHLER"])
	# Halle mit Säulen suchen (notfalls neue Minen erzeugen)
	var halle := -1
	for versuch in 12:
		for i in gen.raeume.size():
			if gen.raeume[i].groesse.x >= 6 and gen.raeume[i].groesse.z >= 6 and i != gen.reaktor_raum and i != gen.start_raum:
				halle = i
		if halle >= 0:
			break
		_lade_level()
		await _warte(0.3)
		for g in get_tree().get_nodes_in_group("gegner"):
			g.free()
	if halle >= 0:
		var r := gen.raeume[halle]
		var ecke := LevelGen.welt_von(r.pos) + Vector3(0, (r.groesse.y - 1) * LevelGen.ZELLE * 0.5, 0)
		var gegenueber := LevelGen.welt_von(r.pos + r.groesse - Vector3i.ONE)
		schiff.global_position = LevelGen.welt_von(gen.naechste_zelle(ecke))
		schiff.look_at(Vector3(gegenueber.x, schiff.global_position.y - 2.0, gegenueber.z), Vector3.UP)
		await _warte(1.0)
		var saeulen := 0
		for x in range(r.pos.x, r.pos.x + r.groesse.x):
			for z in range(r.pos.z, r.pos.z + r.groesse.z):
				if not gen.zellen.has(Vector3i(x, r.pos.y, z)):
					saeulen += 1
		_foto("neu3_halle")
		Protokoll.schreib("test", "Halle %s mit %d Säulen, Lampen gesamt %d" % [r.groesse, saeulen, get_tree().get_nodes_in_group("lampe").size()])
	else:
		Protokoll.schreib("test", "Halle: in 12 Minen keine gefunden")
	# Neues Spiel (nur im Test-Spielstand)
	Meta.bank = 777
	Meta.rekord = 9
	Meta.laeufe = 5
	Meta.stufen = {"schild": 3}
	Meta.waffen = ["plasma"]
	Meta.speichern()
	hud.visible = false
	hangar.aufbauen()
	hangar_ebene.visible = true
	await _warte(0.3)
	hangar._frage_neues_spiel()
	await _warte(0.5)
	_foto("neu3_reset_abfrage")
	var ja: Button = null
	for b in hangar.find_children("*", "Button", true, false):
		if b.text.begins_with("Ja, alles"):
			ja = b
	ja.pressed.emit()
	await _warte(0.5)
	_foto("neu3_reset_danach")
	Meta.laden()
	var leer := Meta.bank == 0 and Meta.rekord == 0 and Meta.laeufe == 0 and Meta.stufen.is_empty() and Meta.waffen.is_empty()
	Protokoll.schreib("test", "Neues Spiel: nach Neuladen Bank %d, Rekord %d, Läufe %d, Stufen %s, Waffen %s → %s" % [
		Meta.bank, Meta.rekord, Meta.laeufe, Meta.stufen, Meta.waffen, "ok" if leer else "FEHLER"])


func _testgegner(typ: String, pos: Vector3, physik: bool) -> Gegner:
	var g := _gegner(typ, pos)
	g.look_at(schiff.global_position, Vector3.UP)
	g.set_physics_process(physik)
	return g


## Neue Gegner: Bilder aller Modelle, dann jedes Verhalten einzeln gemessen.
func _gegner_schau2() -> void:
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	await _warte(3.5)
	var vor := -schiff.global_basis.z
	var rechts := schiff.global_basis.x
	var start := schiff.global_transform
	for typ in ["schildtraeger", "kamikaze", "drohne", "teleporter", "dieb", "reparierer",
			"boss_koloss", "boss_brutmutter", "boss_phantom"]:
		var abst := 13.0 if typ.begins_with("boss") else (3.5 if typ == "drohne" else 5.0)
		var g := _testgegner(typ, schiff.global_position + vor * abst + Vector3(0, 0.4, 0), false)
		g.rotate_y(0.7)
		if typ.begins_with("boss"):
			hud.boss_an(g.boss_name())
			hud.boss_wert(g.hp * 0.7, g.hp_max)
		schiff.global_position += Vector3(0, 1.4, 0) + vor * 0.8
		schiff.look_at(g.global_position, Vector3.UP)
		await _warte(0.8)
		_foto("neu_%s" % typ)
		schiff.global_transform = start
		hud.boss_aus()
		g.free()
	var erg := []
	# 1 Schildträger
	var st := _testgegner("schildtraeger", schiff.global_position + vor * 8.0, false)
	await _warte(0.2)
	var h0 := st.hp
	st.treffer_von(20.0, st.global_position - schiff.global_position)       # Schuss vom Schiff aus: von vorn
	var vorn_geblockt := st.hp == h0
	st.treffer_von(20.0, schiff.global_position - st.global_position)       # von hinten
	var hinten_trifft := st.hp < h0
	erg.append("Schildträger vorn geblockt %s, hinten Schaden %s" % [vorn_geblockt, hinten_trifft])
	st.free()
	# 2 Kamikaze
	schiff.unverwundbar = false
	schiff.schild = schiff.schild_max
	var k := _testgegner("kamikaze", schiff.global_position + vor * 16.0, true)
	var vorher := schiff.schild + schiff.huelle
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(k) and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().physics_frame
	erg.append("Kamikaze explodiert %s nach %.1f s, Schaden am Schiff %.0f" % [
		not is_instance_valid(k), (Time.get_ticks_msec() - t0) / 1000.0, vorher - schiff.schild - schiff.huelle])
	schiff.unverwundbar = true
	if is_instance_valid(k):
		k.free()
	# 3 Teleporter
	var tp := _testgegner("teleporter", schiff.global_position + vor * 14.0, true)
	var sprung := 0.0
	var alt := tp.global_position
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 7000 and is_instance_valid(tp):
		await get_tree().physics_frame
		sprung = maxf(sprung, tp.global_position.distance_to(alt))
		alt = tp.global_position
	erg.append("Teleporter größter Sprung je Bild %.1f m" % sprung)
	if is_instance_valid(tp):
		tp.free()
	# 4 Dieb
	level_erz = 60
	var d := _testgegner("dieb", schiff.global_position + vor * 12.0, true)
	t0 = Time.get_ticks_msec()
	while d.beute == 0 and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().physics_frame
	var nach_klau := level_erz
	var nah := d.global_position.distance_to(schiff.global_position)
	await _warte(2.0)
	var flucht := d.global_position.distance_to(schiff.global_position)
	var gestohlen := d.beute
	d.treffer(1.0e9)
	await _warte(0.3)
	var zurueck := 0
	for b in get_tree().get_nodes_in_group("beute_erz"):
		if b.menge == gestohlen:
			zurueck = b.menge
	erg.append("Dieb: Erz 60 → %d, Abstand beim Klau %.0f m, 2 s später %.0f m, abgeschossen: %d Erz liegen bereit" % [
		nach_klau, nah, flucht, zurueck])
	# 5 Reparierer
	var patient := _testgegner("waechter", schiff.global_position + vor * 10.0, false)
	patient.hp = patient.hp_max * 0.4
	var hp_vor := patient.hp
	var rep := _testgegner("reparierer", schiff.global_position + vor * 15.0 + rechts * 3.0, true)
	rep.alarmieren(schiff.global_position)
	await _warte(3.0)
	_foto("neu_heilstrahl")
	await _warte(1.0)
	erg.append("Reparierer: Wächter %.0f → %.0f Leben" % [hp_vor, patient.hp])
	patient.free()
	rep.free()
	# 6 Verstärkung rufen
	var gruppe := []
	for i in 3:
		gruppe.append(_testgegner("jaeger", schiff.global_position + vor * 12.0 + rechts * (i - 1) * 3.0, false))
	var rufe_vor := Gegner.rufe
	gruppe[0]._alarm = true
	gruppe[0]._rufen()
	erg.append("Verstärkung: gerufen %d, alarmiert %d von 2" % [Gegner.rufe - rufe_vor, int(gruppe[1]._alarm) + int(gruppe[2]._alarm)])
	for g in gruppe:
		g.free()
	# 7 Ausweichen
	var j := _testgegner("jaeger", schiff.global_position + vor * 14.0, true)
	j.alarmieren(schiff.global_position)
	var aus_vor := Gegner.ausweicher
	for i in 12:
		if is_instance_valid(j):
			schiff.look_at(j.global_position, Vector3.UP)
		schiff.energie = schiff.energie_max
		schiff.laser_schuss()
		await _warte(0.18)
	erg.append("Ausweichen: %d Ausweichmanöver bei 12 Schüssen" % (Gegner.ausweicher - aus_vor))
	if is_instance_valid(j):
		j.free()
	for e in erg:
		Protokoll.schreib("test", "Neue Gegner: " + e)


## Alle fünf Gegnertypen vor dem Schiff (Bildprüfung), danach Verhalten von Minenleger und Tarnroboter.
func _gegner_schau() -> void:
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	var vor := -schiff.global_basis.z
	var rechts := schiff.global_basis.x
	var typen := ["jaeger", "geschuetz", "waechter", "minenleger", "tarn"]
	var reihe := []
	await _warte(3.5)                      # Tiefen-Einblendung abwarten
	for i in typen.size():
		var g := Gegner.new()
		g.einrichten(typen[i], 1)
		g.position = schiff.global_position + vor * 10.0 + rechts * (i - 2) * 2.5
		g.ziel = schiff
		level.add_child(g)
		g.set_physics_process(false)       # erst nach dem Einhängen — vorher schaltet Godot es wieder ein
		g.look_at(schiff.global_position, Vector3.UP)
		g.rotate_y(0.6)                    # schräg von vorn
		reihe.append(g)
	await _warte(1.5)
	_foto("gegner_reihe")
	for g in reihe:
		g.free()
	# Nahaufnahmen: je Typ allein, 5 m vor dem Schiff, schräg von vorn
	for typ in typen:
		var g := Gegner.new()
		g.einrichten(typ, 1)
		g.position = schiff.global_position + vor * 5.0 + Vector3(0, 0.4, 0)
		g.ziel = schiff
		level.add_child(g)
		g.set_physics_process(false)       # erst nach dem Einhängen — vorher schaltet Godot es wieder ein
		g.look_at(schiff.global_position, Vector3.UP)
		g.rotate_y(0.7)
		var alt := schiff.global_transform
		schiff.global_position += Vector3(0, 1.6, 0) + vor * 1.2      # leicht von oben
		schiff.look_at(g.global_position, Vector3.UP)
		await _warte(1.0)
		_foto("gegner_%s" % typ)
		schiff.global_transform = alt
		g.free()
	# Tarnroboter: aus 25 m getarnt, aus 8 m sichtbar
	var t := Gegner.new()
	t.einrichten("tarn", 8)
	t.position = schiff.global_position + vor * 25.0
	t.ziel = schiff
	level.add_child(t)
	t.set_physics_process(false)
	await _warte(1.0)
	var fern := t.ist_getarnt()
	_foto("tarn_fern")
	t.position = schiff.global_position + vor * 8.0
	await _warte(1.0)
	var nah := t.ist_getarnt()
	Protokoll.schreib("test", "Tarnroboter: in 25 m getarnt %s, in 8 m getarnt %s → %s" % [fern, nah, "ok" if fern and not nah else "FEHLER"])
	t.free()
	# Minenleger: legt Minen, Mine trifft das Schiff
	var m := Gegner.new()
	m.einrichten("minenleger", 5)
	m.position = schiff.global_position + vor * 16.0
	m.ziel = schiff
	m.welt = level
	level.add_child(m)
	await _warte(7.0)
	var minen := get_tree().get_nodes_in_group("minen")
	Protokoll.schreib("test", "Minenleger: %d Minen in 7 s gelegt → %s" % [minen.size(), "ok" if minen.size() >= 1 else "FEHLER"])
	_foto("minenleger_minen")
	if not minen.is_empty():
		schiff.unverwundbar = false
		var vorher := schiff.schild + schiff.huelle
		schiff.global_position = minen[0].global_position + Vector3(0, 0, 2.0)
		await _warte(1.2)
		Protokoll.schreib("test", "Mine: Schild+Hülle vorher %.0f, nachher %.0f → %s" % [
			vorher, schiff.schild + schiff.huelle, "ok" if schiff.schild + schiff.huelle < vorher else "FEHLER"])
		schiff.unverwundbar = true


## Alle Fundstückarten nebeneinander vor dem Schiff — in 8 m und 15 m Abstand — für die Bildprüfung.
func _beute_schau() -> void:
	for g in get_tree().get_nodes_in_group("gegner"):
		g.queue_free()
	schiff.huelle = 50.0
	schiff.raketen = schiff.raketen_max
	var vor := -schiff.global_basis.z
	var rechts := schiff.global_basis.x
	var arten := Beute.ARTEN.keys()
	for reihe in [[8.0, 0.0], [15.0, 2.2]]:
		for i in arten.size():
			var p: Vector3 = schiff.global_position + vor * reihe[0] + rechts * (i - 2) * 3.4 + Vector3(0, reihe[1] - 0.8, 0)
			level.add_child(Beute.neu(arten[i], p))
	await _warte(1.5)
	_foto("beute_reihe")
	# In die Reparatur der vorderen Reihe fliegen: Meldung "HÜLLE +30"
	var ziel: Vector3 = schiff.global_position + vor * 8.0 + rechts * (arten.find("reparatur") - 2) * 3.4 + Vector3(0, -0.8, 0)
	schiff.autopilot.append(ziel)
	await _warte(1.2)
	_foto("beute_meldung")
	Protokoll.schreib("test", "Beute-Schau: Hülle jetzt %.0f (vorher 50)" % schiff.huelle)
	# Raketen sind voll: Einfliegen darf nichts nehmen und muss "RAKETEN VOLL" melden
	var vorrat := schiff.raketen
	var rp: Vector3 = Vector3.ZERO
	for b in get_tree().get_nodes_in_group("beute_rakete"):
		rp = b.global_position
		break
	schiff.autopilot.append(rp)
	await _warte(1.5)
	_foto("beute_voll")
	Protokoll.schreib("test", "Beute-Schau: Raketen vorher %d, nachher %d, Fundstück noch da: %s" % [
		vorrat, schiff.raketen, not get_tree().get_nodes_in_group("beute_rakete").is_empty()])


func _naechstes_hindernis() -> String:
	var beste := ""
	var bd := INF
	for g in get_tree().get_nodes_in_group("gegner") + get_tree().get_nodes_in_group("minen"):
		var d: float = g.global_position.distance_to(schiff.global_position)
		if d < bd:
			bd = d
			beste = "%s in %.1f m" % [g.typ if g is Gegner else "Mine", d]
	var q := PhysicsRayQueryParameters3D.create(schiff.global_position, schiff.autopilot[0] if not schiff.autopilot.is_empty() else schiff.global_position, 1)
	var wand := get_world_3d().direct_space_state.intersect_ray(q)
	return "nächstes: %s; Wand zwischen Schiff und Wegpunkt: %s" % [beste, not wand.is_empty()]


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

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
var touch: Touch
var _fluss_zelle := Vector3i(1 << 20, 0, 0)   ## Zelle, für die das Gegner-Flussfeld zuletzt gerechnet wurde
var neuer_gegner := ""         ## Hinweis auf die Art, die diese Tiefe einführt (HUD.hinweis unter dem Fadenkreuz)
var schwarm_je_raum := {}      ## Raum → Zahl der Drohnenschwärme der zuletzt besetzten Mine (für --besetzung-test)
var autotest := false
const HANDY_SKALA := 1.4
var _leit_t := 0.0
var _klick_hinweis := false      ## Browser: Hinweis „ins Bild klicken“ steht gerade
var _opt_zu_bild := -1   ## Bild, in dem die Optionen per Esc geschlossen wurden — dieselbe Esc soll nicht auch die Pause beenden
var _leit_ziel := Vector3.ZERO
var _leit_weg := 0.0
var _rng := RandomNumberGenerator.new()
var _piep_t := 0.0
var _bilder: Array[float] = []      ## Bildzeiten der laufenden Tiefe — fürs Leistungsprotokoll (Handy)
var _bilder_tiefe := 0
var _alarm_zeit := 0.0


func _ready() -> void:
	# Im Browser gibt es keine Systemschriften: ● ○ ★ ← → fehlen in der eingebauten Schrift (Kästchen).
	if OS.has_feature("web") or OS.has_feature("android"):     # Android: für die Zeichen der Touch-Knöpfe (↺ ↻ ⇄ ▲ ▼)
		var ersatz: Font = load("res://assets/schrift/DejaVuSans.ttf")
		ThemeDB.fallback_font.fallbacks = ThemeDB.fallback_font.fallbacks + [ersatz]
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	autotest = "--autotest" in OS.get_cmdline_user_args()
	if "--ki-aus" in OS.get_cmdline_user_args():      # Gegner-KI vom 2026-10-11 aus (Vergleich alt/neu)
		for k in Gegner.KI:
			Gegner.KI[k] = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ki-nur="):               # nur diese Teile an, z. B. --ki-nur=weg,schwarm
			for k in Gegner.KI:
				Gegner.KI[k] = k in a.get_slice("=", 1).split(",")
	# Handy: Oberfläche 1,4× größer (Stev 2026-10-10: „Ja, größer“) und die volle Breite des 20:9-Schirms nutzen.
	# Am PC bleibt sie pixelgenau. Mit --handy-skala lässt sich das am PC nachstellen.
	if OS.has_feature("android") or "--handy-skala" in OS.get_cmdline_user_args():
		var w := get_window()
		var px := DisplayServer.window_get_size()
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		w.content_scale_size = Vector2i(roundi(px.x / HANDY_SKALA), roundi(px.y / HANDY_SKALA))
		Protokoll.schreib("start", "Handy-Skalierung %.1f: %s Pixel → %s Fläche" % [HANDY_SKALA, px, w.content_scale_size])
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
	var touch_ebene := CanvasLayer.new()       # über dem HUD, unter Hangar (10) und Pause
	touch_ebene.layer = 6
	add_child(touch_ebene)
	touch = Touch.new()
	touch.main = self
	touch_ebene.add_child(touch)
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
	boss = null
	hud.boss_aus()
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
	tiefe = Meta.gueltige_starttiefe()
	lauf_erz = 0
	schiff = Schiff.new()
	schiff.werte_setzen(Meta.schiffswerte())
	schiff.waffen_frei = Meta.waffen_frei()
	schiff.waffen_stufen = Meta.waffen_stufen.duplicate()
	schiff.beste_vorwaehlen()
	schiff.waffe_gewechselt.connect(func(n: String): hud.aufnahme(n, Color(1.0, 0.8, 0.4)))
	schiff.gestorben.connect(func(): _schiff_tot("Schiff zerstört"))
	schiff.getroffen.connect(func(s: float): hud.blitz(s))
	schiff.behindert.connect(func(t: String): hud.mitteilung(t, 1.2, HUD.ROT))
	schiff.erz_gefunden.connect(func(m: int): level_erz += m)
	schiff.kristall_gefunden.connect(func(m: int):
		Meta.kristalle += m        # sofort gesichert wie Module
		Meta.speichern())
	schiff.modul_gefunden.connect(func(m: Dictionary):
		var weg := Meta.modul_hinzu(m)
		hud.aufnahme(Module.name_von(m).to_upper() + ("  (Inventar voll: %s zerlegt)" % Module.name_von(weg) if not weg.is_empty() else ""), Module.farbe(m)))
	schiff.notfall_ausgeloest.connect(func():
		hud.mitteilung("NOTFALLSCHILD — SCHILD VOLL", 1.5, HUD.BLAU)
		Protokoll.schreib("lauf", "Notfallschild auf Tiefe %d, nächstes in %.0f s" % [tiefe, schiff.notfall_cd]))
	schiff.notschild_ausgeloest.connect(func():
		hud.mitteilung("NOTSCHILD!", 1.8, HUD.BLAU)
		Protokoll.schreib("lauf", "Notschild ausgelöst auf Tiefe %d, übrig %d" % [tiefe, schiff.notschild]))
	schiff.aufgenommen.connect(func(art: String, m: int):
		hud.aufnahme(Beute.beschriftung(art, m), Beute.ARTEN[art].farbe.lerp(Color.WHITE, 0.3)))
	schiff.voll.connect(func(art: String):
		if art != "erz":
			hud.aufnahme("%s VOLL" % Beute.ARTEN[art].name, Color(0.7, 0.7, 0.7)))
	spiel.add_child(schiff)
	hangar_ebene.visible = false
	hud.visible = true
	Protokoll.schreib("lauf", "Lauf %d beginnt in Tiefe %d, Werte %s, Waffen %s + %s" % [Meta.laeufe, tiefe, Meta.schiffswerte(), schiff.laser_wahl, schiff.rakete_wahl])
	_lade_level()


## Leistung der eben gespielten Tiefe ins Log: Mittel und schlechteste 5 % — so lässt sich am Handy-Log
## ablesen, ob es flüssig läuft, ohne dass jemand misst.
func _leistung_protokollieren() -> void:
	if _bilder.size() < 30:
		_bilder.clear()
		return
	var summe := 0.0
	for b in _bilder:
		summe += b
	var sortiert := _bilder.duplicate()
	sortiert.sort()
	Protokoll.schreib("leistung", "Tiefe %d: %.0f fps im Mittel, schlechteste 5 %% %.0f fps, %d Bilder, Renderer %s, Auflösung %s" % [
		_bilder_tiefe, _bilder.size() / summe, 1.0 / sortiert[int(sortiert.size() * 0.95)], _bilder.size(),
		ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"), get_viewport().get_visible_rect().size])
	_bilder.clear()


func _lade_level() -> void:
	_leistung_protokollieren()
	_bilder_tiefe = tiefe
	# Bossanzeige gehört nur zur Boss-Tiefe: bei jedem neuen Level weg (Boss-Tiefen schalten sie wieder an).
	# Vorher verschwand sie nur, wenn der Boss besiegt wurde — nach einem Tod blieb sie mit altem Stand stehen.
	boss = null
	hud.boss_aus()
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
	Meta.pakt_tiefe_erreicht(tiefe)
	if Meta.pakt_stufe("dunkel") > 0:      # Pakt „Dunkelheit“
		for l in get_tree().get_nodes_in_group("minenlicht"):
			l.light_energy *= 0.5
	if schiff:
		schiff.schaden_faktor = 2.0 if Meta.pakt_stufe("glas") > 0 else 1.0
		schiff.schild_laedt = Meta.pakt_stufe("ohneschild") == 0
	if schiff:
		if Meta.erforscht("b_magazin"):
			schiff.raketen = schiff.raketen_max
		if Meta.erforscht("t_tarn"):
			schiff.tarn_t = 5.0
	# Reparaturdrohne: zu Beginn jeder Tiefe Hülle zurück
	var rep := float(Meta.schiffswerte().reparatur)
	if schiff and rep > 0.0 and schiff.huelle < schiff.huelle_max:
		schiff.huelle = minf(schiff.huelle_max, schiff.huelle + rep)
		Protokoll.schreib("lauf", "Reparaturdrohne: Hülle +%.0f → %.0f" % [rep, schiff.huelle])

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

	_fluss_zelle = Vector3i(1 << 20, 0, 0)
	Gegner.fluss = {}
	var gegner_zahl := _gegner_setzen()
	var t := Time.get_ticks_msec() - t0
	Protokoll.schreib("level", "Tiefe %d, Saat %d, Thema %s, Räume %d, Zellen %d, Gegner %d, Fluchtzeit %.0f s, Aufbau %d ms" % [
		tiefe, saat, thema.name, gen.raeume.size(), gen.zellen.size(), gegner_zahl, gen.fluchtzeit(), t])
	hud.setze_tiefe(tiefe, thema.name)
	hud.mitteilung("TIEFE %d\n%s" % [tiefe, thema.name])
	if neuer_gegner != "":
		hud.hinweis(neuer_gegner)
	hud.status("Ziel: Reaktor zerstören")
	if OS.has_feature("web") or "--aufwaermen" in OS.get_cmdline_user_args():
		_aufwaermen()
	if not autotest:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Pakt „Horde“: +30 % Gegner je Stufe, zufällig gerundet — sonst würde aus 1 × 1,3 in kleinen Räumen stets 2.
func horde_anzahl(n: int) -> int:
	var mehr := n * (1.0 + 0.3 * Meta.pakt_stufe("horde"))
	return int(mehr) + (1 if _rng.randf() < mehr - int(mehr) else 0)


func _gegner_setzen() -> int:
	var zahl := 0
	# Besetzung dieser Mine aus Gegner.EINFUEHRUNG (Stev 2026-10-11: „nicht alle am Anfang, das verwirrt“):
	# Grundbesetzung Jäger und Geschütz; die Art dieser Tiefe nur einzeln in eigenen Räumen; frisch eingeführte
	# (bis 2 Tiefen danach) immer dabei, aber selten; von den älteren nur eine Auswahl, damit jede Mine
	# eine überschaubare Besetzung hat statt aller Arten auf einmal.
	var pool := ["jaeger", "jaeger", "geschuetz"]
	var debuet := ""
	neuer_gegner = ""
	var frisch: Array = []
	var alt: Array = []
	for typ in Gegner.EINFUEHRUNG:
		var ab: int = Gegner.EINFUEHRUNG[typ][0]
		if ab == 1 or tiefe < ab:
			continue
		if ab == tiefe:
			debuet = typ
		elif typ in Gegner.EINZELGAENGER or typ == "drohne":
			continue
		elif tiefe - ab <= 2:
			frisch.append(typ)
		else:
			alt.append(typ)
	for k in range(alt.size() - 1, 0, -1):          # mischen mit der Level-Saat, damit gleiche Saat = gleiche Mine
		var j := _rng.randi_range(0, k)
		var t = alt[k]
		alt[k] = alt[j]
		alt[j] = t
	var besetzung: Array = frisch + alt.slice(0, maxi(0, mini(2 + tiefe / 5, 5) - frisch.size()))
	for typ in besetzung:
		pool.append_array([typ] if typ in frisch else [typ, typ])
	# Räume für die neue Art: sie steht dort allein, damit man sie kennenlernt (Schwarm und Einzelgänger: ein Raum)
	var debuet_raeume: Array = []
	if debuet != "":
		var kandidaten: Array = []
		for i in gen.raeume.size():
			if i != gen.start_raum and i != gen.reaktor_raum:
				kandidaten.append(i)
		var wie_viele := 1 if (debuet == "drohne" or debuet in Gegner.EINZELGAENGER) else 2
		for k in mini(wie_viele, kandidaten.size()):
			debuet_raeume.append(kandidaten.pop_at(_rng.randi_range(0, kandidaten.size() - 1)))
		var info: Array = Gegner.EINFUEHRUNG[debuet]
		neuer_gegner = "NEUER GEGNER: %s — %s" % [info[1], info[2]]
	Protokoll.schreib("level", "Besetzung Tiefe %d: neu %s, frisch %s, dazu %s" % [tiefe, debuet if debuet != "" else "—", frisch, besetzung.slice(frisch.size())])
	var einzel := {"dieb": 0, "reparierer": 0, "nest": 0}
	# Drohnenschwarm ab Tiefe 10, höchstens einer je Raum und wenige je Mine (Stev 2026-10-11)
	var schwaerme := 0
	schwarm_je_raum.clear()
	var schwarm_max := 0 if tiefe <= Gegner.EINFUEHRUNG["drohne"][0] else (1 if tiefe <= 12 else (2 if tiefe < 20 else 3))
	boss = null
	for i in gen.raeume.size():
		if i == gen.start_raum:
			continue
		var zellen := gen.zellen_von_raum(i)
		var zufall_zelle := func() -> Vector3: return LevelGen.welt_von(zellen[_rng.randi_range(0, zellen.size() - 1)])
		if i in debuet_raeume:
			if debuet == "drohne":
				zahl += _schwarm(zufall_zelle.call())
				schwarm_je_raum[i] = schwarm_je_raum.get(i, 0) + 1
			else:
				_gegner(debuet, zufall_zelle.call())
				zahl += 1
				if debuet in einzel:
					einzel[debuet] += 1
		else:
			var n := _rng.randi_range(1, mini(2 + tiefe / 2, 7))
			if i == gen.reaktor_raum:
				n += 2
			n = horde_anzahl(n)
			for j in n:
				var pos: Vector3 = zufall_zelle.call()
				pos += Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.5, 1.5))
				if i == gen.reaktor_raum and pos.distance_to(reaktor.position) < 4.5:
					pos = reaktor.position + (pos - reaktor.position).normalized() * 4.5
				_gegner(pool[_rng.randi_range(0, pool.size() - 1)], pos)
				zahl += 1
			# Einzelgänger (höchstens 2 je Mine); das Nest nie zusammen mit einem Schwarm im selben Raum
			var nest_hier := false
			for typ in einzel:
				var ab: int = Gegner.EINFUEHRUNG[typ][0]
				if tiefe > ab and einzel[typ] < 2 and _rng.randf() < 0.15:
					einzel[typ] += 1
					_gegner(typ, zufall_zelle.call())
					zahl += 1
					nest_hier = nest_hier or typ == "nest"
			if schwaerme < schwarm_max and not nest_hier and i != gen.reaktor_raum and _rng.randf() < 0.25:
				schwaerme += 1
				zahl += _schwarm(zufall_zelle.call())
				schwarm_je_raum[i] = schwarm_je_raum.get(i, 0) + 1
		# Kristalle: in jedem Raum mit 20 %, in der Kristallader mit 60 %
		if _rng.randf() < (0.6 if thema.name.begins_with("Kristallader") else 0.2):
			level.add_child(Beute.neu("kristall", LevelGen.welt_von(zellen[_rng.randi_range(0, zellen.size() - 1)])))
		if _rng.randf() < 0.35:
			var art: String = ["schild", "reparatur", "rakete", "erz", "erz"][_rng.randi_range(0, 4)]
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


## Gegner-Wegfinder: ein Flussfeld vom Schiff aus, neu nur wenn das Schiff die Zelle wechselt (Gegner.gd liest es).
func _fluss_pruefen(zwingen := false) -> void:
	var z := gen.naechste_zelle(schiff.global_position)
	if z == _fluss_zelle and not zwingen:
		return
	_fluss_zelle = z
	Gegner.fluss = gen.flussfeld(z, Gegner.WEG_MAX + 4)
	Gegner.fluss_gen = gen


## Schwarm: drei Drohnen zusammen (Stev 2026-10-11: fünf waren „zu viele“). Gibt die Zahl zurück.
func _schwarm(mitte: Vector3) -> int:
	var schwarm := horde_anzahl(3)
	for k in schwarm:
		_gegner("drohne", mitte + Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-1, 1), _rng.randf_range(-2, 2)))
	return schwarm


## Jede 5. Tiefe: einer von drei Bossen im Wechsel bewacht den Reaktor, der bis dahin geschirmt ist.
func _boss_setzen() -> void:
	var typ: String = Gegner.BOSSE[(tiefe / 5 - 1) % Gegner.BOSSE.size()]
	var r := gen.raeume[gen.reaktor_raum]
	var vor := (gen.mitte(gen.start_raum) - reaktor.position)
	vor.y = 0
	boss = _gegner(typ, reaktor.position + vor.normalized() * 9.0)
	boss.gen = gen
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
	# Pakt: zähere Gegner, schnellere Schüsse, wütende Bosse
	var hp_f := 1.0 + 0.25 * Meta.pakt_stufe("zaeh")
	if g.ist_boss and Meta.pakt_stufe("wut") > 0:
		hp_f *= 1.5
		g.phase2_anteil = 0.7
	g.hp *= hp_f
	g.hp_max *= hp_f
	g.schuss_tempo *= 1.0 + 0.2 * Meta.pakt_stufe("scharf")
	g.position = pos
	g.ziel = schiff
	g.welt = level
	g.zerstoert.connect(_gegner_weg)
	g.verstaerkung.connect(func(t: String, p: Vector3, von: Gegner):
		var neu := _gegner(t, p)
		neu.alarmieren(schiff.global_position)
		if von.typ == "boss_brutmutter":
			neu.add_to_group("brut")
		if von.typ == "nest":
			neu.set_meta("nest", von.get_instance_id()))
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
	e.ambient_light_energy = float(thema.get("umgebung_kraft", 0.35)) * (0.5 if Meta.pakt_stufe("dunkel") > 0 else 1.0)
	e.fog_enabled = true
	e.fog_light_color = thema.nebel
	e.fog_density = 0.012
	e.glow_enabled = true
	e.glow_intensity = 0.4          # Stev: Leuchteffekte waren übertrieben hell (vorher 0.7 / 0.9)
	e.glow_hdr_threshold = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC


const MODUL_CHANCE := 0.05     ## je normalem Gegner; Bosse immer (mindestens Selten), Reaktor 30 %


func _modul_fallen(pos: Vector3, boss: bool) -> Beute:
	var b := Beute.neu("modul", pos)
	b.modul = Module.erzeugen(_rng, tiefe, boss)
	level.add_child.call_deferred(b)
	Protokoll.schreib("level", "Modul fällt: %s auf Tiefe %d" % [Module.name_von(b.modul), tiefe])
	return b


## Pakt-Meilenstein: Boss mit Pakt ≥ 5 / ≥ 10 besiegt → einmalig ein episches / legendäres Modul.
func _pakt_meilenstein(pos: Vector3) -> void:
	for m in Meta.PAKT_MEILENSTEINE:
		if Meta.pakt_punkte() >= m[0] and not m[0] in Meta.pakt_meilen:
			Meta.pakt_meilen.append(m[0])
			Meta.speichern()
			var b := _modul_fallen(pos + Vector3(0, 3.0, 0), true)
			b.modul = Module.erzeugen(_rng, tiefe, true, "", m[1])
			hud.mitteilung("PAKT %d — MEILENSTEIN\n%s" % [m[0], Module.name_von(b.modul)], 3.0, HUD.GELB)
			Protokoll.schreib("lauf", "Pakt-Meilenstein %d: %s" % [m[0], Module.name_von(b.modul)])


## Schatzsucher: Bosse lassen doppelt so viel Erz fallen.
func boss_erz_faktor() -> int:
	return 2 if Meta.erforscht("b_schatz") else 1


func _gegner_weg(g: Gegner) -> void:
	if schiff and is_instance_valid(schiff):
		schiff.ueberladung_ausloesen()
	if g.erz > 0 and not g.ist_boss:
		level.add_child.call_deferred(Beute.neu("erz", g.global_position, g.erz))
	if g.beute > 0:
		level.add_child.call_deferred(Beute.neu("erz", g.global_position + Vector3(0, 0.8, 0), g.beute))
	if g.ist_boss:
		_modul_fallen(g.global_position + Vector3(0, 1.5, 0), true)
		_pakt_meilenstein(g.global_position)
	elif _rng.randf() < MODUL_CHANCE * (1.0 + 0.05 * Meta.pakt_punkte()):
		_modul_fallen(g.global_position + Vector3(0, 0.6, 0), false)
	if _rng.randf() < 0.06:
		level.add_child.call_deferred(Beute.neu("kristall", g.global_position + Vector3(0, -0.6, 0)))
	if g.ist_boss:
		for i in 8:     # Bossbeute: ein Kranz aus Erz
			var p := g.global_position + Vector3(cos(TAU * i / 8.0), 0.3 * (i % 2), sin(TAU * i / 8.0)) * 2.5
			level.add_child.call_deferred(Beute.neu("erz", p, g.erz / 8 * boss_erz_faktor()))
		reaktor.schirm_aus()
		hud.boss_aus()
		hud.mitteilung("%s BESIEGT\nReaktor ungeschützt" % g.boss_name(), 2.5, HUD.GELB)
		Protokoll.schreib("level", "Boss %s besiegt auf Tiefe %d" % [g.boss_name(), tiefe])
		boss = null
	if _rng.randf() < beute_chance():
		var art: String = ["schild", "reparatur", "rakete"][_rng.randi_range(0, 2)]
		level.add_child.call_deferred(Beute.neu(art, g.global_position + Vector3(0, 1.2, 0)))


## Chance, dass ein Gegner ein Fundstück fallen lässt: 20 % plus Bergungskralle.
func beute_chance() -> float:
	return 0.2 + float(Meta.schiffswerte().beute_bonus)


func _reaktor_weg() -> void:
	countdown = gen.fluchtzeit() * float(Meta.schiffswerte().flucht_mult) * (1.0 - 0.2 * Meta.pakt_stufe("lunte"))
	_alarm_zeit = 0.0
	_piep_t = 2.0                       # erst die Sirene, dann das Piepen
	var klang := get_node("/root/Klang")
	# Pegel gemessen (2026-10-10): Sirene war mit −2 dB rund 10 dB lauter als eine Explosion (Stev: „zu laut“).
	# Jetzt: Sirene knapp unter Explosionen (−16 dB), Piepen auf Höhe des eigenen Lasers (−19 dB).
	klang.spiele("sirene", null, -13.0)
	get_tree().create_timer(1.7).timeout.connect(func():
		if countdown >= 0.0:
			klang.spiele("sirene", null, -13.0))
	level_erz += 10 + 5 * tiefe
	if _rng.randf() < 0.3:
		_modul_fallen(reaktor.global_position + Vector3(0, 3.0, 0), false)
	ausgang.oeffnen()
	hud.mitteilung("REAKTOR ZERSTÖRT", 2.0, HUD.ROT)
	Protokoll.schreib("level", "Reaktor zerstört auf Tiefe %d, Fluchtzeit %.0f s" % [tiefe, countdown])


## Abschlussbonus einer Tiefe (Boss-Tiefen doppelt), mit Vertragsbonus.
func abschluss_bonus(t: int) -> int:
	return int(round((15 + 8 * t) * (2 if LevelGen.ist_boss_tiefe(t) else 1) * float(Meta.schiffswerte().abschluss_mult)))


func _ausgang_erreicht() -> void:
	if zustand != "flug":
		return
	zustand = "wechsel"
	# Belohnung fürs Abschließen: Abschlussbonus (in Boss-Tiefen doppelt), 1 Erz je übrige Sekunde,
	# Schild voll, Hülle +30, Raketen +2 — und eine Abrechnung auf dem Schirm.
	var abschluss := abschluss_bonus(tiefe)
	var restzeit := maxi(int(countdown), 0)
	var gesichert := level_erz
	level_erz += abschluss + restzeit
	var pakt_bonus := pakt_erz_bonus(level_erz)
	level_erz += pakt_bonus
	Meta.bank += level_erz
	lauf_erz += level_erz
	Meta.speichern()
	var huelle_vorher := schiff.huelle
	var raketen_vorher := schiff.raketen
	schiff.schild = schiff.schild_max
	schiff.huelle = minf(schiff.huelle_max, schiff.huelle + 30.0)
	schiff.raketen = mini(schiff.raketen_max, schiff.raketen + 2)
	hud.abschluss(tiefe, [
		["Erz aus dieser Tiefe", "+%d" % gesichert],
		["Abschlussbonus" + (" (Boss ×2)" if LevelGen.ist_boss_tiefe(tiefe) else ""), "+%d" % abschluss],
		["Zeitbonus (%d s übrig)" % restzeit, "+%d" % restzeit],
	] + ([["Paktbonus (Pakt %d · +%d %%)" % [Meta.pakt_punkte(), Meta.pakt_punkte() * 10], "+%d" % pakt_bonus]] if pakt_bonus > 0 else []) + [
		[_auffuellung(int(schiff.huelle - huelle_vorher), schiff.raketen - raketen_vorher), ""],
	], level_erz)
	Protokoll.schreib("level", "Tiefe %d geschafft: Erz %d + Abschlussbonus %d + Zeitbonus %d = %d gesichert (Lauf %d, Bank %d)" % [
		tiefe, gesichert, abschluss, restzeit, level_erz, lauf_erz, Meta.bank])
	tiefe += 1
	call_deferred("_lade_level")


## Pakt: +10 % Erz je Paktpunkt auf alles, was eine Tiefe einbringt.
func pakt_erz_bonus(erz: int) -> int:
	return int(round(erz * 0.1 * Meta.pakt_punkte()))


func _auffuellung(huelle: int, raketen: int) -> String:
	var teile := ["Schild aufgeladen"]
	if huelle > 0:
		teile.append("Hülle +%d" % huelle)
	if raketen > 0:
		teile.append("Raketen +%d" % raketen)
	return " · ".join(teile)


## Beim Tod gerettetes Erz der Tiefe: die Hälfte, mit Notreserve alles.
func gerettetes_erz() -> int:
	return level_erz if Meta.erforscht("b_reserve") else level_erz / 2


func _schiff_tot(grund: String) -> void:
	if zustand != "flug":
		return
	_leistung_protokollieren()
	zustand = "tot"
	schiff.aktiv = false
	Effekte.explosion(level, schiff.global_position, Color(1.0, 0.5, 0.2), 6.0)
	var gerettet := gerettetes_erz()
	Meta.bank += gerettet
	var raffiniert := Meta.raffinerie_ertrag()       # Station: Raffinerie liefert nach jedem Lauf
	Meta.bank += raffiniert
	lauf_erz += gerettet
	Meta.speichern()
	if raffiniert > 0:
		Protokoll.schreib("lauf", "Raffinerie liefert %d Erz" % raffiniert)
	Protokoll.schreib("lauf", "%s auf Tiefe %d, Erz im Lauf %d (davon %d aus dieser Tiefe gerettet), Bank %d" % [
		grund, tiefe, lauf_erz, gerettet, Meta.bank])
	hud.status("")
	hud.mitteilung("%s\nTiefe %d erreicht · %d Erz gesichert%s" % [grund.to_upper(), tiefe, lauf_erz,
		("\nRaffinerie +%d Erz" % raffiniert) if raffiniert > 0 else ""], 3.5, HUD.ROT)
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
	_fluss_pruefen()
	if Input.is_action_just_pressed("leitstrahl"):
		leitstrahl = not leitstrahl
		hud.mitteilung("LEITSTRAHL %s" % ("AN" if leitstrahl else "AUS"), 1.2, HUD.GRUEN if leitstrahl else HUD.GELB)
		Protokoll.schreib("lauf", "Leitstrahl %s auf Tiefe %d" % ["an" if leitstrahl else "aus", tiefe])
	if countdown >= 0.0:
		countdown -= dt
		_alarm(dt)
		var blink := HUD.ROT if fmod(countdown, 1.0) > 0.5 else HUD.GELB
		hud.status("SELBSTZERSTÖRUNG  %d:%02d  —  zum Ausgang!" % [int(countdown) / 60, int(countdown) % 60], blink)
		if countdown <= 0.0:
			countdown = -1.0
			_schiff_tot("Die Mine ist explodiert")
			return
	_bilder.append(dt)
	hud.setze_erz(level_erz, lauf_erz, Meta.bank)
	if boss != null and is_instance_valid(boss):
		hud.boss_wert(boss.hp, boss.hp_max)
	_leitstrahl(dt)
	if OS.has_feature("web"):
		_ton_pruefen(dt)
		var frei := Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or _ton_zustand == "suspended"
		if frei:
			hud.status("Ins Bild klicken, um mit der Maus zu steuern" + (" und den Ton einzuschalten" if _ton_zustand == "suspended" else ""))
		elif _klick_hinweis and countdown < 0.0:
			hud.status("" if reaktor.kaputt else "Ziel: Reaktor zerstören")
		_klick_hinweis = frei
	_radar()
	hud.werte(schiff)


## Browser (Stev 2026-10-10: „lags“): WebGL kompiliert Shader erst beim ersten Zeichnen — gemessen 140–190 ms
## Hänger bei der ersten Explosion, beim Reaktor usw. Deshalb beim Laden jeder Tiefe hinter einem schwarzen
## Ladebild einmal alles zeichnen, was später auftaucht: alle Gegnerarten, Fundstücke, Mine, Geschosse,
## Schadenszahl, Explosionskugel mit Licht (Wände und Gegner einmal von einem Punktlicht beleuchtet).
func _aufwaermen() -> void:
	var t0 := Time.get_ticks_msec()
	var schirm := CanvasLayer.new()
	schirm.layer = 100
	var schwarz := ColorRect.new()
	schwarz.color = Color.BLACK
	schwarz.set_anchors_preset(Control.PRESET_FULL_RECT)
	schirm.add_child(schwarz)
	var text := Label.new()
	text.text = "Lädt …"
	text.set_anchors_preset(Control.PRESET_CENTER)
	text.add_theme_font_size_override("font_size", 28)
	schirm.add_child(text)
	add_child(schirm)
	var cam := schiff.kamera
	var vor := -cam.global_basis.z
	var rechts := cam.global_basis.x
	var oben := cam.global_basis.y
	var mitte := cam.global_position + vor * 5.0
	var teile: Array[Node] = []
	var setzen := func(n: Node3D, versatz: Vector3):
		level.add_child(n)
		n.global_position = mitte + versatz
		n.process_mode = Node.PROCESS_MODE_DISABLED     # nur zeichnen, nichts tun
		for gr in n.get_groups():
			n.remove_from_group(gr)
		teile.append(n)
	var typen := Gegner.TYPEN.keys().filter(func(t): return not t.begins_with("boss_"))
	if LevelGen.ist_boss_tiefe(tiefe):
		typen.append(Gegner.BOSSE[(tiefe / 5 - 1) % Gegner.BOSSE.size()])
	for i in typen.size():
		var g := Gegner.new()
		g.einrichten(typen[i], tiefe)
		setzen.call(g, rechts * (i % 6 - 2.5) * 1.6 + oben * (i / 6 - 1.5) * 1.6)
		if g.typ in ["lauerer", "tarn"]:
			g._tarn = 0.7
			g._tarnung_anwenden()
	var arten := Beute.ARTEN.keys()
	for i in arten.size():
		var b := Beute.neu(arten[i], Vector3.ZERO)
		if arten[i] == "modul":
			b.modul = Module.erzeugen(RandomNumberGenerator.new(), tiefe)
		setzen.call(b, -vor * 1.5 + rechts * (i - 2.5) * 1.2 - oben * 2.5)
	setzen.call(Mine.neu(Vector3.ZERO, 0.0), -vor * 1.5 + oben * 2.5)
	# jede Geschossoptik (Optik.gd): alle Laser, alle Raketenmodelle, Splitter-Zielsucher, Gegnerschuss
	var arten_g: Array = Waffen.LASER.map(func(w): return w.id) + Waffen.RAKETEN.map(func(w): return w.id) + ["mini", ""]
	for i in arten_g.size():
		setzen.call(Geschoss.neu(Vector3.ZERO, vor, 0.1, 0.0, arten_g[i] != "", Color(1, 0.5, 0.2), 0.0, 1.0, arten_g[i]),
			-vor * 2.0 + rechts * (i - arten_g.size() / 2.0) * 0.5 + oben * 1.5)
	Optik.explosion(level, mitte - vor * 1.0, Color(1, 0.6, 0.2), 6.0)        # Explosion ohne Ton (räumt sich selbst weg)
	Optik.explosion(level, mitte - vor * 1.0 + rechts, Color(1, 0.3, 0.2), 1.0)
	var zahl := Effekte.schadenszahl(level, mitte, "0")
	if zahl:
		teile.append(zahl)
	# dazu große Punktlichter, die Wände und Gegner treffen
	# Jedes Material, das im Level schon steckt (Wände, Gitter, Deko, Reaktor), einmal auf einem kleinen Quadrat
	var mats := {}
	for mi: MeshInstance3D in level.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override:
			mats[mi.material_override] = true
		for si in mi.get_surface_override_material_count():
			var sm := mi.get_surface_override_material(si)
			if sm:
				mats[sm] = true
		if mi.mesh:
			for si in mi.mesh.get_surface_count():
				var mm := mi.mesh.surface_get_material(si)
				if mm:
					mats[mm] = true
	var n_mat := 0
	for mat in mats:
		if n_mat >= 400:
			break
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.4, 0.4)
		q.mesh = qm
		q.material_override = mat
		setzen.call(q, rechts * ((n_mat % 16) - 7.5) * 0.45 + oben * ((n_mat / 16) % 8 - 3.5) * 0.45 - vor * 0.5)
		n_mat += 1
	# Funken des Ausgangs (erscheinen erst nach dem Reaktor — Partikel-Shader)
	if ausgang and ausgang._funken:
		var f: GPUParticles3D = ausgang._funken.duplicate()
		f.emitting = true
		setzen.call(f, -vor * 1.0 + oben * 1.0)
		f.process_mode = Node.PROCESS_MODE_INHERIT
	var lichter: Array[Node] = []
	for reichweite in [3.0, 36.0]:
		var l := OmniLight3D.new()
		l.omni_range = reichweite
		l.light_energy = 2.2
		setzen.call(l, Vector3.ZERO)
		lichter.append(l)
	for i in 3:
		await get_tree().process_frame
	# Zweite Runde nur mit dem Scheinwerfer, dritte ganz ohne Licht: jede Lichtlage ist eine eigene Shader-Variante
	for l in lichter:
		l.queue_free()
	for i in 3:
		await get_tree().process_frame
	var scheinwerfer_an: bool = schiff.scheinwerfer.visible
	schiff.scheinwerfer.visible = false
	for i in 3:
		await get_tree().process_frame
	schiff.scheinwerfer.visible = scheinwerfer_an
	for n in teile:
		if is_instance_valid(n):
			n.queue_free()
	schirm.queue_free()
	Protokoll.schreib("leistung", "Aufwärmen Tiefe %d: %d Teile (%d Levelmaterialien) in %d ms" % [tiefe, teile.size(), n_mat, Time.get_ticks_msec() - t0])


## Browser (Stev 2026-10-10: „keinen Sound im Browser“): Der Browser startet den Ton erst nach einer Eingabe.
## Die Seite weckt ihn bei jedem Klick/jeder Taste (head_include im Web-Export); hier wird der Zustand jede
## Sekunde gelesen, bei Änderung protokolliert (Browserkonsole) und im Bild ein Hinweis gezeigt, solange er ruht.
var _ton_zustand := ""
var _ton_t := 0.0
func _ton_pruefen(dt: float) -> void:
	_ton_t -= dt
	if _ton_t > 0.0:
		return
	_ton_t = 1.0
	var z := str(JavaScriptBridge.eval("window.__abstiegTon ? window.__abstiegTon() : 'unbekannt'"))
	if z != _ton_zustand:
		Protokoll.schreib("ton", "Browser-Tonausgabe: %s" % z)
		_ton_zustand = z


## Browser: Die Maus lässt sich nur nach einem Klick einfangen (Pointer Lock). Ein Klick ins Bild holt sie.
func _input(e: InputEvent) -> void:
	if OS.has_feature("web") and e is InputEventMouseButton and e.pressed and zustand == "flug" \
			and not get_tree().paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
		get_node("/root/Klang").spiele("piep", null, -17.0, 1.35 if schnell else 1.0)


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


## Gegnerradar: Gegner in Reichweite als Punkte im HUD, auch hinter Wänden; hinter der Kamera am Rand.
func _radar() -> void:
	hud.radar_punkte.clear()
	var weite := float(Meta.schiffswerte().radar)
	hud.notfall = "" if schiff.notfall_cd <= 0.0 else ("Notfallschild bereit" if schiff.notfall_rest <= 0.0 else
		"Notfallschild %d:%02d" % [ceili(schiff.notfall_rest) / 60, ceili(schiff.notfall_rest) % 60])
	hud.nachbrenner = "" if schiff.nachbrenner_cd <= 0.0 else (
		"NACHBRENNER" if schiff.boost_aktiv() else (
		"Nachbrenner bereit" if schiff.nachbrenner_bereit <= 0.0 else "Nachbrenner %d s" % ceili(schiff.nachbrenner_bereit)))
	if weite <= 0.0:
		return
	var cam := schiff.kamera
	var vp := get_viewport().get_visible_rect().size
	var mitte := vp / 2.0
	for g: Gegner in get_tree().get_nodes_in_group("gegner"):
		if g.global_position.distance_to(schiff.global_position) > weite or g.ist_getarnt():
			continue
		if not cam.is_position_behind(g.global_position):
			var sp := cam.unproject_position(g.global_position)
			if Rect2(Vector2.ZERO, vp).grow(-20.0).has_point(sp):
				hud.radar_punkte.append([sp, false])
				continue
		var lokal := cam.global_transform.affine_inverse() * g.global_position
		var r := Vector2(lokal.x, -lokal.y)
		r = Vector2(0, 1) if r.length_squared() < 0.0001 else r.normalized()
		var rand := mitte - Vector2(30, 30)
		var k := minf(rand.x / maxf(absf(r.x), 0.0001), rand.y / maxf(absf(r.y), 0.0001))
		hud.radar_punkte.append([mitte + r * k, true])


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
	if "--spielzeit-test" in OS.get_cmdline_user_args():
		await _spielzeit_test()
		get_tree().quit(0)
		return
	if "--boss-reset" in OS.get_cmdline_user_args():
		await _boss_reset_test()
		get_tree().quit(0)
		return
	if "--controller-test" in OS.get_cmdline_user_args():
		await _controller_test()
		get_tree().quit(0)
		return
	if "--toene-export" in OS.get_cmdline_user_args():
		var ordner := ProjectSettings.globalize_path("res://pruefung")
		for n in get_node("/root/Klang").toene:
			get_node("/root/Klang").toene[n].save_to_wav("%s/ton_%s.wav" % [ordner, n])
		get_tree().quit(0)
		return
	if "--zeige-hangar" in OS.get_cmdline_user_args():
		Meta.waffen_stufen = {"zwilling": 3, "plasma": 2, "zielsuch": 5}
		Meta.stufen["schild"] = 12          # Meister 4: zeigt die endlose Schildstufe
		hud.visible = false
		hangar.aufbauen()
		hangar_ebene.visible = true
		await _warte(0.8)
		_foto("hangar_versionen")
		# Tooltip: Maus über die Karte des Plasmawerfers fahren lassen
		for k in hangar.find_children("*", "PanelContainer", true, false):
			if k.tooltip_text.begins_with("Schildgenerator"):
				var bew := InputEventMouseMotion.new()
				bew.position = k.get_global_rect().get_center()
				bew.global_position = bew.position
				get_viewport().push_input(bew)
				await _warte(0.1)
				bew = bew.duplicate()
				bew.position += Vector2(2, 1)
				bew.global_position = bew.position
				get_viewport().push_input(bew)
		await _warte(1.5)
		_foto("hangar_tooltip")
		Meta.laden()
		get_tree().quit(0)
		return
	if "--zeige-schild" in OS.get_cmdline_user_args():
		await _schild_messung()
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
	if "--zeige-geschosse" in OS.get_cmdline_user_args():
		await _geschoss_schau()
		get_tree().quit(0)
		return
	if "--ki-test" in OS.get_cmdline_user_args():
		await _ki_test()
		get_tree().quit(0)
		return
	if "--touch-test" in OS.get_cmdline_user_args():
		await _touch_test()
		get_tree().quit(0)
		return
	if "--pad-test" in OS.get_cmdline_user_args():
		await _pad_test()
		get_tree().quit(0)
		return
	if "--besetzung-test" in OS.get_cmdline_user_args():
		_besetzung_test()
		get_tree().quit(0)
		return
	if "--tasten-test" in OS.get_cmdline_user_args():
		await _tasten_test()
		get_tree().quit(0)
		return
	if "--gegner-neu-test" in OS.get_cmdline_user_args():
		await _gegner_neu_test()
		get_tree().quit(0)
		return
	if "--sicht-test" in OS.get_cmdline_user_args():
		await _sicht_test()
		get_tree().quit(0)
		return
	if "--raketen-test" in OS.get_cmdline_user_args():
		Meta.start_tiefe = 1
		_starte_lauf()
		await _warte(1.0)
		schiff.unverwundbar = true
		var erg := []
		var meldung := [""]       # Lambdas fangen Variablen als Kopie, ein Array als Verweis
		schiff.aufgenommen.connect(func(art: String, m: int): meldung[0] = Beute.beschriftung(art, m))
		for vorher in [0, schiff.raketen_max / 2]:
			schiff.raketen = vorher
			var gut := schiff.aufnehmen("rakete", 2)
			erg.append("%d/%d → %d/%d, Meldung „%s“" % [vorher, schiff.raketen_max, schiff.raketen, schiff.raketen_max, meldung[0]])
			if not gut or schiff.raketen != schiff.raketen_max or meldung[0] != "RAKETEN +%d" % (schiff.raketen_max - vorher):
				erg.append("FEHLER")
		var voll_genommen := schiff.aufnehmen("rakete", 2)
		for vorher in [10.0, schiff.huelle_max * 0.7]:
			schiff.huelle = vorher
			var gut := schiff.aufnehmen("reparatur", 30)
			erg.append("Hülle %.0f/%.0f → %.0f, Meldung „%s“" % [vorher, schiff.huelle_max, schiff.huelle, meldung[0]])
			if not gut or schiff.huelle != schiff.huelle_max or meldung[0] != "HÜLLE +%d" % ceili(schiff.huelle_max - vorher):
				erg.append("FEHLER")
		voll_genommen = voll_genommen or schiff.aufnehmen("reparatur", 30)
		var rep_text := Beute.schild_text("reparatur", 30)
		var b := Beute.neu("rakete", schiff.global_position - schiff.global_basis.z * 6.0)
		level.add_child(b)
		await _warte(0.4)
		var schild_text: String = (b.get_children().filter(func(c): return c is Label3D)[0] as Label3D).text
		# Fundstück im Schiff bei vollem Vorrat, danach leer geschossen: muss jetzt eingesammelt werden
		schiff.raketen = schiff.raketen_max
		var kleber := Beute.neu("rakete", schiff.global_position)
		level.add_child(kleber)
		await _warte(0.6)
		var liegt_bei_voll := is_instance_valid(kleber)
		schiff.raketen = 0
		await _warte(0.6)
		var spaeter_genommen := not is_instance_valid(kleber) and schiff.raketen == schiff.raketen_max
		erg.append("Fundstück im Schiff: bei vollem Vorrat liegen geblieben %s, nach Leerschießen eingesammelt %s" % [liegt_bei_voll, spaeter_genommen])
		var ok: bool = not "FEHLER" in erg and not voll_genommen and schild_text == "RAKETEN · AUFFÜLLEN" and rep_text == "HÜLLE · VOLL REPARIEREN" \
			and liegt_bei_voll and spaeter_genommen
		Protokoll.schreib("test", "Raketen-/Reparaturfund: %s; bei vollem Vorrat genommen %s; Schilder im Bergwerk „%s“, „%s“ → %s" % [
			"; ".join(erg), voll_genommen, schild_text, rep_text, "BESTANDEN" if ok else "FEHLGESCHLAGEN"])
		get_tree().quit(0)
		return
	if "--ton-test" in OS.get_cmdline_user_args():
		await _ton_test()
		get_tree().quit(0)
		return
	if "--station-test" in OS.get_cmdline_user_args():
		await _station_test()
		get_tree().quit(0)
		return
	if "--pakt-test" in OS.get_cmdline_user_args():
		await _pakt_test()
		get_tree().quit(0)
		return
	if "--module-test" in OS.get_cmdline_user_args():
		await _module_test()
		get_tree().quit(0)
		return
	if "--forschung-test" in OS.get_cmdline_user_args():
		await _forschung_test()
		get_tree().quit(0)
		return
	if "--boss-jagd-test" in OS.get_cmdline_user_args():
		await _boss_jagd_test()
		get_tree().quit(0)
		return
	if "--aufwertungs-test" in OS.get_cmdline_user_args():
		await _aufwertungs_test()
		get_tree().quit(0)
		return
	if "--starttiefe-test" in OS.get_cmdline_user_args():
		await _starttiefe_test()
		get_tree().quit(0)
		return
	if "--sammel-test" in OS.get_cmdline_user_args():
		await _sammel_test()
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
		# Überblick: aus einer Ecke des Reaktorraums auf den Reaktor, damit die Raumgröße sichtbar ist.
		var rr: Dictionary = gen.raeume[gen.reaktor_raum]
		var eck := LevelGen.welt_von(Vector3i(rr.pos) + Vector3i(0, int(rr.groesse.y) - 1, 0))
		var p_vor := schiff.global_position
		schiff.global_position = eck
		schiff.look_at(reaktor.global_position, Vector3.UP)
		await _warte(0.4)
		_foto("tiefe%d_2b_reaktorraum" % t)
		Protokoll.schreib("test", "Tiefe %d: Reaktorraum %s Zellen = %.0f × %.0f × %.0f m" % [
			t, rr.groesse, rr.groesse.x * LevelGen.ZELLE, rr.groesse.y * LevelGen.ZELLE, rr.groesse.z * LevelGen.ZELLE])
		schiff.global_position = p_vor
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
				if schiff._laser_cd <= 0.0:
					schiff.laser_schuss()
					schuesse += int(w.anzahl)
				if not foto_gemacht and Time.get_ticks_msec() - t0 > 250:
					_foto("waffe_%s" % w.id)
					foto_gemacht = true
				if foto_gemacht and Time.get_ticks_msec() - t0 > 1100 and Time.get_ticks_msec() - t0 < 1130:
					_foto("waffe_%s_einschlag" % w.id)
				await get_tree().physics_frame
				schiff._laser_cd -= get_physics_process_delta_time()
		else:
			schiff.raketen_schuss()
			schuesse += int(w.anzahl)
			await _warte(0.25)
			_foto("waffe_%s" % w.id)
			await _warte(0.65)
			_foto("waffe_%s_einschlag" % w.id)
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
	# Versionen: gleiche Schusszahl auf ein Ziel, Mk I / Mk III / Mk V
	for id in ["zwilling", "plasma", "zielsuch", "smart"]:
		var zeile := ""
		for st in [1, 3, 5]:
			schiff.waffen_stufen[id] = st
			schiff.waehle(id)
			var vorher := 0.0
			for z in ziele:
				vorher += z.hp
			if Waffen.ist_laser(id):
				for n in 4:
					schiff.laser_schuss()
					await _warte(0.5)
			else:
				schiff.raketen = 99
				schiff.raketen_schuss()
				await _warte(3.0)
			await _warte(0.6)
			var nach := 0.0
			for z in ziele:
				nach += z.hp
			zeile += "  %s %.0f" % [Waffen.MK[st], vorher - nach]
		Protokoll.schreib("test", "Version %-14s%s" % [Waffen.finde(id).name, zeile])


## Spielzeit: läuft hoch, übersteht Speichern+Neuladen und „Neues Spiel“; Hangar zeigt sie an.
func _spielzeit_test() -> void:
	var gestern := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400)
	var alt := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 30 * 86400)
	Meta.spielzeit = 5.0 * 3600.0                       # Vorgeschichte: 5 h insgesamt …
	Meta.spielzeit_tage = {gestern: 1.5 * 3600.0, alt: 2.0 * 3600.0}   # … 1,5 h gestern, 2 h vor 30 Tagen
	Meta.zuletzt = int(Time.get_unix_time_from_system()) - 86400
	var s0 := Meta.spielzeit
	await _warte(3.0)
	var gelaufen := Meta.spielzeit - s0
	Meta.speichern()
	Meta.zuruecksetzen()
	Meta.laden()
	var nach := Meta.spielzeit
	var zwei_w := Meta.spielzeit_zwei_wochen()
	Meta.zuletzt = int(Time.get_unix_time_from_system()) - 86400
	_zeige_hangar()
	await _warte(0.8)
	_foto("hangar_spielzeit")
	var ok := gelaufen > 2.5 and gelaufen < 3.6 and nach >= s0 + 2.5 and zwei_w > 1.5 * 3600.0 and zwei_w < 1.6 * 3600.0
	Protokoll.schreib("test", "Spielzeit: in 3 s gezählt %.1f s; nach Speichern, Neues Spiel und Neuladen %.0f s (vorher %.0f); letzte 2 Wochen %.0f s (soll ~5400, ohne den Tag vor 30 Tagen) → %s" % [
		gelaufen, nach, s0, zwei_w, "BESTANDEN" if ok else "FEHLGESCHLAGEN"])


## Stevs Fall: in einer Boss-Tiefe sterben → Hangar → neuer Lauf. Die Bossanzeige darf außerhalb von
## Boss-Tiefen nicht stehen bleiben, und der Boss beginnt beim nächsten Mal mit vollem Leben.
func _boss_reset_test() -> void:
	autotest = false                     # echter Ablauf: nach dem Tod zurück in den Hangar
	var erg: Array[String] = []
	_starte_lauf()
	tiefe = 5
	_lade_level()
	await _warte(1.0)
	var b1 := boss
	var an_boss := hud._boss_balken.visible
	b1.treffer(b1.hp * 0.6)
	await _warte(0.3)
	_schiff_tot("Testtod im Bosslevel")
	await _warte(5.0)
	var im_hangar := zustand == "hangar"
	var balken_hangar := hud._boss_balken.visible
	_starte_lauf()
	await _warte(1.0)
	var balken_t1 := hud._boss_balken.visible
	tiefe = 5
	_lade_level()
	await _warte(1.0)
	var voll := boss != null and is_equal_approx(boss.hp, boss.hp_max)
	var balken_t5 := hud._boss_balken.visible
	erg.append("Bosslevel: Anzeige an %s; nach Tod im Hangar %s, Anzeige dort %s; neuer Lauf Tiefe 1 Anzeige %s; wieder Tiefe 5: Anzeige %s, Boss volles Leben %s" % [
		an_boss, im_hangar, balken_hangar, balken_t1, balken_t5, voll])
	var ok := an_boss and im_hangar and not balken_hangar and not balken_t1 and balken_t5 and voll
	for e in erg:
		Protokoll.schreib("test", "Boss-Reset: " + e)
	Protokoll.schreib("test", "BOSS-RESET-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))


# --- Controller-Test: alles nur mit simulierten Gamepad-Eingaben (wie der GameSir am Handy) -----------

func _knopf_druck(knopf: JoyButton, halten := 0.12) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = knopf
	e.pressed = true
	Input.parse_input_event(e)
	await _warte(halten)
	var los := e.duplicate()
	los.pressed = false
	Input.parse_input_event(los)
	await _warte(0.12)


func _achse(achse: JoyAxis, wert: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = achse
	e.axis_value = wert
	Input.parse_input_event(e)


func _controller_test() -> void:
	autotest = false        # wie im echten Spiel: Pause und Mausfang aktiv (Spielstand bleibt der Testspielstand)
	var erg: Array[String] = []
	var ok := true
	Meta.bank = 2000
	Meta.waffen = ["streu"]
	Meta.speichern()
	# 1) Hangar nur mit dem Steuerkreuz
	_zeige_hangar()
	await _warte(0.6)
	var start_fokus := get_viewport().gui_get_focus_owner()
	await _knopf_druck(JOY_BUTTON_DPAD_UP)
	await _knopf_druck(JOY_BUTTON_DPAD_UP)
	var karte_fokus := get_viewport().gui_get_focus_owner()
	var karte_name := String(karte_fokus.name) if karte_fokus else ""
	var start_name := String(start_fokus.name) if start_fokus else ""
	var info: String = hangar._info.text
	erg.append("Hangar: Start-Fokus %s, nach 2× Steuerkreuz hoch Fokus %s, Infofeld \"%s\"" % [
		start_fokus.name if start_fokus else "keiner", karte_fokus.name if karte_fokus else "keiner", info.get_slice("\n", 0)])
	var bank_vor := Meta.bank
	await _knopf_druck(JOY_BUTTON_A)
	await _warte(0.3)
	erg.append("Hangar: A auf %s → Bank %d → %d, Fokus danach %s" % [
		karte_name, bank_vor, Meta.bank,
		get_viewport().gui_get_focus_owner().name if get_viewport().gui_get_focus_owner() else "keiner"])
	_foto("controller_hangar")
	ok = ok and karte_name.begins_with("Knopf_") and karte_name != start_name and info.length() > 5 and Meta.bank < bank_vor
	# zurück zu "Abstieg beginnen" und starten
	for i in 8:
		var f := get_viewport().gui_get_focus_owner()
		if f is Button and f.text == "ABSTIEG BEGINNEN":
			break
		await _knopf_druck(JOY_BUTTON_DPAD_DOWN)
	var vor_start := get_viewport().gui_get_focus_owner()
	await _knopf_druck(JOY_BUTTON_A)
	await _warte(1.5)
	erg.append("Start mit A (Fokus war %s): Zustand %s" % [vor_start.text if vor_start is Button else "?", zustand])
	ok = ok and zustand == "flug"
	if zustand != "flug":
		for e in erg:
			Protokoll.schreib("test", "Controller: " + e)
		Protokoll.schreib("test", "CONTROLLER-TEST FEHLGESCHLAGEN")
		return
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	schiff.unverwundbar = true
	await _warte(2.5)
	# 2) Fliegen: linker Stick vor, rechter Stick drehen, LB rollen, A hoch
	var p0 := schiff.global_position
	_achse(JOY_AXIS_LEFT_Y, -1.0)
	await _warte(1.2)
	_achse(JOY_AXIS_LEFT_Y, 0.0)
	var vor := schiff.global_position.distance_to(p0)
	var b0 := schiff.global_basis
	_achse(JOY_AXIS_RIGHT_X, 1.0)
	await _warte(0.6)
	_achse(JOY_AXIS_RIGHT_X, 0.0)
	var dreh := rad_to_deg(b0.z.angle_to(schiff.global_basis.z))
	var b1 := schiff.global_basis
	await _knopf_druck(JOY_BUTTON_LEFT_SHOULDER, 0.5)
	var roll := rad_to_deg(b1.y.angle_to(schiff.global_basis.y))
	var y0 := schiff.global_position.y
	await _knopf_druck(JOY_BUTTON_A, 0.8)
	var hoch := schiff.global_position.y - y0
	erg.append("Flug: linker Stick vor %.1f m, rechter Stick %.0f° gedreht, LB %.0f° gerollt, A %.1f m hoch" % [vor, dreh, roll, hoch])
	ok = ok and vor > 4.0 and dreh > 20.0 and roll > 20.0 and hoch > 0.5
	# 3) Waffen: RT feuern, Steuerkreuz rechts wechseln, LT Rakete
	var schuesse := 0
	_achse(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	for i in 30:
		await get_tree().physics_frame
		for k in level.get_children():
			if k is Geschoss and k.vom_spieler and not k.has_meta("gezaehlt"):
				k.set_meta("gezaehlt", true)
				schuesse += 1
	_achse(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	var laser_vor := schiff.laser_wahl
	await _knopf_druck(JOY_BUTTON_DPAD_RIGHT)
	var laser_nach := schiff.laser_wahl
	var rak_vor := schiff.raketen
	_achse(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _warte(0.2)
	_achse(JOY_AXIS_TRIGGER_LEFT, 0.0)
	erg.append("Waffen: RT %d Schüsse in 0,5 s, Steuerkreuz rechts %s → %s, LT Raketen %d → %d" % [
		schuesse, laser_vor, laser_nach, rak_vor, schiff.raketen])
	_foto("controller_flug")
	ok = ok and schuesse >= 3 and laser_nach != laser_vor and schiff.raketen < rak_vor
	# 3b) Zielhilfe: Drehrate halber/voller Stick, Treffer auf einen Gegner 3,5° neben dem Fadenkreuz
	var raten := []
	for st in [0.3, 1.0]:
		var bz := schiff.global_basis
		_achse(JOY_AXIS_RIGHT_X, st)
		await _warte(0.5)
		_achse(JOY_AXIS_RIGHT_X, 0.0)
		raten.append(rad_to_deg(bz.z.angle_to(schiff.global_basis.z)) / 0.5)
	await _warte(0.3)
	# Messplatz in der Mitte des Startraums (18 m breit): Schiff 6 m links der Mitte, Blick nach +x
	var raum_mitte := gen.mitte(gen.start_raum)
	schiff.global_position = raum_mitte + Vector3(-6, 0, 0)
	schiff.look_at(raum_mitte + Vector3(10, 0, 0), Vector3.UP)
	schiff.velocity = Vector3.ZERO
	var ziel_p := schiff.global_position + (-schiff.global_basis.z).rotated(schiff.global_basis.y, deg_to_rad(4.0)) * 10.0
	var tg := _testgegner("drohne", ziel_p, false)
	tg.hp = 100000.0
	var sicht := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(schiff.global_position, ziel_p, 1)).is_empty()
	var treffer := {}
	var laser_merken := schiff.laser_wahl
	schiff.waehle("zwilling")          # Einzelbolzen — beim Streufeuer trifft der Fächer auch ohne Hilfe
	for hilfe in [false, true]:
		schiff.pad_aktiv = hilfe
		var h0 := tg.hp
		for i in 8:
			schiff.laser_schuss()
			await _warte(0.18)
		await _warte(0.5)
		treffer[hilfe] = h0 - tg.hp
	tg.free()
	schiff.waehle(laser_merken)
	erg.append("Zielhilfe: Drehung %.0f°/s bei 30 %% Stick, %.0f°/s bei vollem Stick; Drohne 4° neben dem Fadenkreuz in 10 m (freie Sicht %s): Schaden ohne Hilfe %.0f, mit Hilfe %.0f" % [
		raten[0], raten[1], sicht, treffer[false], treffer[true]])
	ok = ok and treffer[true] > treffer[false]
	# 3c) Leitstrahl: ab Werk keine Taste (Stev 2026-10-11) — Select schaltet ihn nicht mehr aus
	await _knopf_druck(JOY_BUTTON_BACK)
	var leit_bleibt := leitstrahl and hud.leit_an
	erg.append("Leitstrahl: Select lässt ihn an %s" % leit_bleibt)
	ok = ok and leit_bleibt
	# 4) Pause (Start), Optionen per Steuerkreuz + A, zurück mit B, weiter mit Start
	await _knopf_druck(JOY_BUTTON_START)
	var pausiert := get_tree().paused
	await _knopf_druck(JOY_BUTTON_DPAD_DOWN)
	await _knopf_druck(JOY_BUTTON_A)
	await _warte(0.3)
	var opt_auf := optionen.visible
	_foto("controller_optionen")
	await _knopf_druck(JOY_BUTTON_B)
	var opt_zu := not optionen.visible and get_tree().paused
	await _knopf_druck(JOY_BUTTON_START)
	erg.append("Pause mit Start %s, Optionen per Steuerkreuz+A %s, mit B zurück in die Pause %s, Start weiter %s" % [
		pausiert, opt_auf, opt_zu, not get_tree().paused])
	ok = ok and pausiert and opt_auf and opt_zu and not get_tree().paused
	for e in erg:
		Protokoll.schreib("test", "Controller: " + e)
	Protokoll.schreib("test", "CONTROLLER-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))


## Schildträger umkreisen: Anteil der Zeit, in der seine ungeschützte Seite zum Schiff zeigt.
func _schild_messung() -> void:
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	await _warte(1.0)
	var mitte := gen.mitte(gen.start_raum)
	var st := _testgegner("schildtraeger", mitte, true)
	st.alarmieren(schiff.global_position)
	st.tempo = 0.0                          # nur drehen, nicht fliegen — gemessen wird die Drehung
	var r := 6.0
	for v in [6.0, 10.0, 14.0]:
		var w := 0.0
		var offen := 0
		var bilder := 0
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 6000:
			await get_tree().physics_frame
			w += v / r * get_physics_process_delta_time()
			schiff.global_position = st.global_position + Vector3(cos(w), 0.3, sin(w)) * r
			schiff.look_at(st.global_position, Vector3.UP)
			var zum := (schiff.global_position - st.global_position).normalized()
			if Time.get_ticks_msec() - t0 > 1000:      # erste Sekunde einschwingen lassen
				bilder += 1
				if (-st.global_basis.z).dot(zum) <= Gegner.schild_kegel:
					offen += 1
		Protokoll.schreib("test", "Schildträger (Drehung %.1f, Kegel %.2f): beim Umkreisen mit %2.0f m/s in %d m Abstand ungeschützt %3.0f %% der Zeit" % [
			Gegner.schild_drehung, Gegner.schild_kegel, v, int(r), 100.0 * offen / maxi(bilder, 1)])
	# Schüsse aus festen Winkeln neben seiner Frontrichtung: geblockt oder Treffer?
	st.set_physics_process(false)
	var vorn := -st.global_basis.z
	var ergebnis := ""
	for winkel in [0, 20, 30, 40, 50, 60, 90, 180]:
		var von := vorn.rotated(Vector3.UP, deg_to_rad(winkel))       # Schütze steht in dieser Richtung
		var h := st.hp
		st.treffer_von(10.0, -von)                                   # Geschoss fliegt auf ihn zu
		ergebnis += "  %d°:%s" % [winkel, "Block" if st.hp == h else "Treffer"]
	Protokoll.schreib("test", "Schildträger (Kegel %.2f) Schüsse aus Winkel:%s" % [Gegner.schild_kegel, ergebnis])
	st.set_physics_process(true)
	# Stillstand vor ihm: muss geschützt bleiben
	schiff.global_position = st.global_position + Vector3(0, 0.3, 6)
	await _warte(2.0)
	var vorn_ok := (-st.global_basis.z).dot((schiff.global_position - st.global_position).normalized()) > Gegner.schild_kegel
	Protokoll.schreib("test", "Schildträger: von vorn stehend geschützt %s" % vorn_ok)
	# Schadenszahlen im Bild: Schildträger von vorn und von der Seite beschießen
	schiff.global_position = st.global_position + Vector3(0, 1.5, 7)
	schiff.look_at(st.global_position, Vector3.UP)
	st.set_physics_process(false)
	st.hp = 10000.0
	st.hp_max = 10000.0
	for i in 6:
		st.treffer_von(12.0 + i * 9.0, -(-st.global_basis.z).rotated(Vector3.UP, deg_to_rad(80 if i % 2 == 0 else 0)))
		await _warte(0.12)
	_foto("schadenszahlen")


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


## Früher bemerken: Gegner hinter einer Wand in Gehörweite wird alarmiert, weiter weg nicht.
func _sicht_test() -> void:
	await _warte(1.0)       # Lauf läuft schon (Autotest-Start)
	schiff.unverwundbar = true
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	await _warte(0.2)
	var space := get_viewport().get_world_3d().direct_space_state
	# Schiff in einen Stollen setzen, von dem aus beide Fälle (verdeckte Zelle nah und fern) existieren
	var sp := schiff.global_position
	var faelle := {}       # "nah" (6 m bis GEHOER-2) / "fern" (GEHOER+5 bis 30 m): verdeckte Zellmitte
	for s in gen.zellen:
		if gen.zellen[s] != -1:
			continue
		sp = gen.welt_von(s)
		faelle = {}
		for z in gen.zellen:
			var p: Vector3 = gen.welt_von(z)
			var d := p.distance_to(sp)
			var art := "nah" if d < Gegner.GEHOER - 2.0 and d > 6.0 else ("fern" if d > Gegner.GEHOER + 5.0 and d < 30.0 else "")
			if art == "" or faelle.has(art):
				continue
			var verdeckt := true      # auch ±0,6 m höher/tiefer verdeckt: das Schweben darf nicht um die Kante sehen
			for dy in [-0.6, 0.0, 0.6]:
				if space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, dy, 0), sp, 1)).is_empty():
					verdeckt = false
			if verdeckt:
				faelle[art] = p
		if faelle.size() == 2:
			break
	schiff.global_position = sp
	schiff.velocity = Vector3.ZERO
	await _warte(0.2)
	sp = schiff.global_position
	var erg := []
	var ok := faelle.size() == 2
	for art in ["nah", "fern"]:
		if not faelle.has(art):
			erg.append("%s: keine verdeckte Zelle gefunden" % art)
			continue
		var g := _testgegner("waechter", faelle[art], true)
		g.tempo = 0.0
		await _warte(0.6)
		var d: float = g.global_position.distance_to(sp)
		erg.append("%s %.1f m hinter Wand: Sicht %s, alarmiert %s" % [art, d, g._sicht, g._alarm])
		ok = ok and not g._sicht and g._alarm == (art == "nah")
		g.free()
	erg.append("Sichtweite %.0f m (vorher 55)" % Gegner.SICHT_WEITE)
	ok = ok and Gegner.SICHT_WEITE > 55.0
	Protokoll.schreib("test", "Sicht: %s → %s" % ["; ".join(erg), "BESTANDEN" if ok else "FEHLGESCHLAGEN"])


## Geschoss- und Explosionsschau (2026-10-10): Seitenansicht aller Geschosse, eigenes Feuer aus dem Cockpit,
## Explosionen in drei Größen zu drei Zeitpunkten. Bilder in pruefung/geschoss_*.png.
func _geschoss_schau() -> void:
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	await _warte(1.0)
	hud.visible = false
	var vor := -schiff.global_basis.z
	var rechts := schiff.global_basis.x
	var oben := schiff.global_basis.y
	var p0 := schiff.global_position
	var reihen := [
		["laser", [["zwilling", true, Color(1.0, 0.3, 0.2), 1.0], ["streu", true, Color(0.35, 1.0, 0.35), 1.0],
			["vulkan", true, Color(1.0, 0.9, 0.3), 0.7], ["plasma", true, Color(0.3, 0.8, 1.0), 1.7],
			["", false, Color(1.0, 0.25, 0.1), 1.0], ["", false, Color(0.5, 1.0, 0.9), 2.4]]],
		["raketen", [["zielsuch", true, Color(1.0, 0.75, 0.3), 1.6], ["streu_r", true, Color(1.0, 0.55, 0.2), 1.3],
			["smart", true, Color(0.6, 1.0, 0.4), 1.8], ["mega", true, Color(1.0, 0.3, 0.9), 2.0], ["mini", true, Color(0.6, 1.0, 0.4), 0.9]]],
	]
	for r in reihen:
		var teile := []
		var n: int = r[1].size()
		for i in n:
			var d: Array = r[1][i]
			var g := Geschoss.neu(p0 + vor * 5.0 + rechts * 0.8 - oben * (i - (n - 1) / 2.0) * 0.75, rechts, 0.1, 0.0, d[1], d[2], 0.0, d[3], d[0])
			g.process_mode = Node.PROCESS_MODE_DISABLED
			level.add_child(g)
			g.global_basis = Basis.looking_at(rechts.rotated(oben, -0.35), oben)     # schräg von der Seite
			teile.append(g)
		await _warte(0.4)
		_foto("geschoss_%s" % r[0])
		for t in teile:
			t.free()
	# Eigenes Feuer aus dem Cockpit
	hud.visible = true
	schiff.laser_wahl = "zwilling"
	for i in 3:
		schiff.laser_schuss()
		await _warte(0.07)
	_foto("geschoss_cockpit_laser")
	await _warte(0.6)
	schiff.rakete_wahl = "zielsuch"
	schiff.raketen = schiff.raketen_max
	schiff.raketen_schuss()
	await _warte(0.18)
	_foto("geschoss_cockpit_rakete")
	await _warte(1.5)
	hud.visible = false
	# Explosionen: Einschlag, Rakete, Mega — je bei 0,06 / 0,18 / 0,35 s
	# je Zeitpunkt eine eigene Explosion: das Foto selbst kostet Zeit und würde die nächste Aufnahme verschieben
	for e in [[1.0, Color(1.0, 0.3, 0.2), 6.0], [3.5, Color(1.0, 0.6, 0.2), 10.0], [9.0, Color(1.0, 0.3, 0.9), 16.0]]:
		for zeit in [0.06, 0.18, 0.35]:
			Effekte.explosion(level, p0 + vor * e[2], e[1], e[0], false)
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < zeit * 1000.0:
				await get_tree().process_frame
			_foto("geschoss_explosion_%s_%03d" % [str(e[0]).replace(".", ""), int(zeit * 1000)])
			await _warte(0.9)
	Protokoll.schreib("test", "Geschoss-Schau fertig")


## Tastenbelegung: Anzeige, Umbelegen über die Optionen (echter Tastendruck), Tausch, Speichern/Laden, Standard.
## Gegner-KI (Stev 2026-10-11): jede der vier Verbesserungen vorher (Schalter aus) und nachher (an) im Spiel gemessen.
func _ki_test() -> void:
	var erg: Array[String] = []
	var ok := true
	var pruef := func(name: String, gut: bool, text: String):
		erg.append("%s %s: %s" % ["ok  " if gut else "FEHL", name, text])
		return gut
	await _warte(1.0)
	var aufraeumen := func():
		for g in get_tree().get_nodes_in_group("gegner"):
			g.free()
		for k in level.get_children():
			if k is Geschoss:
				k.queue_free()
	aufraeumen.call()
	schiff.aktiv = false              # das Schiff bewegt der Test selbst
	schiff.velocity = Vector3.ZERO
	var alle_an := func(an: bool):
		for k in Gegner.KI:
			Gegner.KI[k] = an
	var start_pos := schiff.global_position

	# 1) Wegfinder: Gegner 5–9 Zellen Weg entfernt ohne Sicht, alarmiert. Wie viele finden in 15 s zu dir?
	_fluss_pruefen(true)
	var orte: Array[Vector3] = []
	var feld: Dictionary = Gegner.fluss
	var raum := get_world_3d().direct_space_state
	# echte Ecken: Weg mindestens 1,8-mal so lang wie die Luftlinie, sonst käme man auch geradeaus an der Wand entlang
	var kandidaten: Array = []
	for z in feld:
		var d: int = feld[z]
		var p := LevelGen.welt_von(z)
		var umweg := d * LevelGen.ZELLE / maxf(p.distance_to(start_pos), 0.1)
		if d >= 4 and d <= 14 and umweg >= 1.25 and not raum.intersect_ray(PhysicsRayQueryParameters3D.create(start_pos, p, 1)).is_empty():
			kandidaten.append([umweg, p])
	kandidaten.sort_custom(func(a, b): return a[0] > b[0])
	for k in kandidaten.slice(0, 4):
		orte.append(k[1])
	erg.append("Wegfinder: %d Orte ohne Sicht mit Umweg ≥ 1,25, genommen die 4 größten (%s)" % [kandidaten.size(), ", ".join(kandidaten.slice(0, 4).map(func(k): return "%.1f" % k[0]))])
	var finden := {}
	for an in [false, true]:
		alle_an.call(true)
		Gegner.KI.weg = an
		var gefunden := 0
		var zeiten: Array[String] = []
		for p in orte:
			var g := _gegner("jaeger", p)
			g.alarmieren(start_pos)
			var t := 0.0
			while t < 15.0 and is_instance_valid(g) and not g._sicht:
				await _warte(0.25)
				t += 0.25
			if is_instance_valid(g) and g._sicht:
				gefunden += 1
				zeiten.append("%.1f s" % t)
			aufraeumen.call()
			await _warte(0.1)
		finden[an] = gefunden
		erg.append("Wegfinder %s: %d von %d Jägern ohne Sicht (4–14 Zellen Weg) fanden dich in 15 s %s" % ["an " if an else "aus", gefunden, orte.size(), zeiten])
	ok = pruef.call("Wegfinder", orte.size() >= 2 and finden[true] == orte.size() and finden[true] > finden[false],
		"aus %d, an %d von %d" % [finden[false], finden[true], orte.size()]) and ok

	# 2) Ausschwärmen + Kreisen: 5 Wächter an derselben Stelle vor dir, 6 s, dann Abstände und Bewegung messen
	var vor := -schiff.global_basis.z
	var frei_bis := start_pos + vor * 40.0
	var tr := raum.intersect_ray(PhysicsRayQueryParameters3D.create(start_pos, frei_bis, 1))
	var stelle: Vector3 = start_pos + vor * minf(18.0, (tr.position.distance_to(start_pos) - 3.0) if not tr.is_empty() else 18.0)
	var schwarm := {}
	for an in [false, true]:
		alle_an.call(true)
		Gegner.KI.schwarm = an
		var gs: Array[Gegner] = []
		for i in 5:
			var g := _gegner("waechter", stelle + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)))
			g.alarmieren(start_pos)
			g.hp = 1e9
			g.hp_max = 1e9
			gs.append(g)
		await _warte(5.0)
		var bewegt := 0.0             # zurückgelegte Strecke in den nächsten 2 s (nicht die Verschiebung)
		var vorher: Array[Vector3] = []
		for g in gs:
			vorher.append(g.global_position)
		var tt := 0.0
		while tt < 2.0:
			await get_tree().physics_frame
			tt += get_physics_process_delta_time()
			for i in gs.size():
				bewegt += gs[i].global_position.distance_to(vorher[i]) / 2.0
				vorher[i] = gs[i].global_position
		var winkel: Array[float] = []           # Richtung jedes Wächters vom Schiff aus, waagerecht
		for g in gs:
			var r: Vector3 = g.global_position - start_pos
			winkel.append(rad_to_deg(atan2(r.x, r.z)))
		var spanne := 0.0
		for a in winkel:
			for b in winkel:
				spanne = maxf(spanne, absf(wrapf(a - b, -180.0, 180.0)))
		var min_d := INF
		var summe_d := 0.0
		var paare := 0
		for i in gs.size():
			for j in range(i + 1, gs.size()):
				var d := gs[i].global_position.distance_to(gs[j].global_position)
				min_d = minf(min_d, d)
				summe_d += d
				paare += 1
		if an:
			_foto("ki_schwarm")
		schwarm[an] = [min_d, summe_d / paare, bewegt / gs.size(), spanne]
		erg.append("Schwarm %s: verteilt über %.0f° um dich, kleinster Abstand %.1f m, mittlerer %.1f m, Tempo am Platz %.1f m/s" % ["an " if an else "aus", spanne, min_d, summe_d / paare, bewegt / gs.size()])
		aufraeumen.call()
		await _warte(0.1)
	ok = pruef.call("Ausschwärmen", schwarm[true][3] > 45.0 and schwarm[true][3] > schwarm[false][3] * 1.5 and schwarm[true][0] >= schwarm[false][0],
		"verteilt über %.0f° → %.0f°, kleinster Abstand %.1f → %.1f m" % [schwarm[false][3], schwarm[true][3], schwarm[false][0], schwarm[true][0]]) and ok
	ok = pruef.call("Kreisen", schwarm[true][2] > 1.0 and schwarm[true][2] > schwarm[false][2] * 2.0,
		"Tempo am Platz %.1f → %.1f m/s" % [schwarm[false][2], schwarm[true][2]]) and ok

	# 3) Vorhalt: Geschütz im Reaktorraum, du fliegst 14 m davor gerade hin und her (8 m/s, 30 m Bahn).
	# Gemessen: mittlerer Fehlabstand der Schüsse und Anteil Treffer (< 1,2 m), mit dem echten Schusstempo der Tiefe.
	var seite := schiff.global_basis.x
	var mitte_r: Vector3 = reaktor.position + Vector3(0, 7.0, 0)
	var g_ort: Vector3 = mitte_r + Vector3(0, 0, -14.0)
	var quote := {}
	var fehl := {}
	for fall in [["Tiefe 3 aus", false, 3], ["Tiefe 3 an", true, 3], ["Tiefe 10 an", true, 10], ["Tiefe 15 aus", false, 15], ["Tiefe 15 an", true, 15]]:
		alle_an.call(true)
		Gegner.KI.vorhalt = fall[1]
		var g := _gegner("geschuetz", g_ort)
		g._stufe = fall[2]
		g.schuss_tempo = 13.0 * minf(1.0 + 0.08 * (fall[2] - 1), 2.0)
		g.cd_basis = 0.4
		g.hp = 1e9
		g.alarmieren(mitte_r)
		var naechst := {}      # Geschoss → kleinster Abstand zum Schiff
		var t := 0.0
		while t < 15.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var phase := fmod(t, 7.5)          # 3,75 s nach rechts, 3,75 s nach links
			var hin := phase < 3.75
			schiff.global_position = mitte_r + Vector3((phase if hin else 7.5 - phase) * 8.0 - 15.0, 0, 0)
			schiff.velocity = Vector3(8.0 if hin else -8.0, 0, 0)
			for k in level.get_children():
				if k is Geschoss and not k.vom_spieler:
					var d: float = k.global_position.distance_to(schiff.global_position)
					naechst[k.get_instance_id()] = minf(naechst.get(k.get_instance_id(), INF), d)
		var werte: Array = naechst.values()
		var treffer := werte.filter(func(d): return d < 1.2).size()
		var mittel := 0.0
		for d in werte:
			mittel += minf(d, 10.0) / werte.size()
		quote[fall[0]] = float(treffer) / maxf(1.0, werte.size())
		fehl[fall[0]] = mittel
		erg.append("Vorhalt %s (Anteil %.0f %%, Schuss %.0f m/s): %d von %d Schüssen träfen, mittlerer Fehlabstand %.1f m" % [
			fall[0], (Gegner.vorhalt_anteil(fall[2]) * 100.0) if fall[1] else 0.0, g.schuss_tempo, treffer, werte.size(), mittel])
		aufraeumen.call()
		await _warte(0.2)
	schiff.global_position = start_pos
	schiff.velocity = Vector3.ZERO
	ok = pruef.call("Vorhalt gestaffelt", absf(fehl["Tiefe 3 an"] - fehl["Tiefe 3 aus"]) < fehl["Tiefe 3 aus"] * 0.3 and fehl["Tiefe 15 an"] < fehl["Tiefe 15 aus"] * 0.8,
		"Fehlabstand Tiefe 3: %.1f → %.1f m (kein Vorhalt), Tiefe 10: %.1f m, Tiefe 15: %.1f → %.1f m; Treffer Tiefe 15 %.0f → %.0f %%" % [
		fehl["Tiefe 3 aus"], fehl["Tiefe 3 an"], fehl["Tiefe 10 an"], fehl["Tiefe 15 aus"], fehl["Tiefe 15 an"], quote["Tiefe 15 aus"] * 100, quote["Tiefe 15 an"] * 100]) and ok

	# 4) Rückzug: Wächter mit Sicht, auf 20 % Leben gesetzt; nach 6 s: Abstand und ob er aus der Sicht ist.
	# Ort: eine Zelle in Sicht, von der aus der Weg mindestens 3 Zellen weiter vom Schiff wegführt (keine Sackgasse,
	# dort kämpft er absichtlich weiter). Danach mit Reparierer.
	_fluss_pruefen(true)           # das Schiff war eben noch im Reaktorraum
	var flucht_ort := stelle
	for z in Gegner.fluss:
		var d0z: int = Gegner.fluss[z]
		var pz := LevelGen.welt_von(z)
		if d0z < 2 or d0z > 4 or not raum.intersect_ray(PhysicsRayQueryParameters3D.create(start_pos, pz, 1)).is_empty():
			continue
		var kette := 0
		var c: Vector3i = z
		while kette < 3:
			var weiter := false
			for r in LevelGen.RICHTUNGEN:
				if Gegner.fluss.has(c + r) and int(Gegner.fluss[c + r]) > int(Gegner.fluss[c]):
					c = c + r
					weiter = true
					break
			if not weiter:
				break
			kette += 1
		if kette >= 3:
			flucht_ort = pz
			break
	erg.append("Rückzug: Startort %s (Fluchtweg vorhanden: %s)" % [flucht_ort.snapped(Vector3.ONE * 0.1), flucht_ort != stelle])
	var rueck := {}
	for an in [false, true]:
		alle_an.call(true)
		Gegner.KI.rueckzug = an
		var g := _gegner("waechter", flucht_ort)
		g.alarmieren(start_pos)
		await _warte(1.0)
		var d0 := g.global_position.distance_to(start_pos)
		g.hp = g.hp_max * 0.2
		var weg_t := -1.0
		var tt := 0.0
		while tt < 6.0:
			await _warte(0.25)
			tt += 0.25
			if weg_t < 0.0 and not g._sicht:
				weg_t = tt
			if an and fmod(tt, 1.0) < 0.01:
				var zz := gen.naechste_zelle(g.global_position)
				erg.append("  Rückzug-Spur %.0f s: Zelle %s Fluss %s, Ort %s, Ziel %s (Zelle %s, Fluss %s), Tempo %.1f m/s, im Rückzug %s, Sicht %s" % [tt, zz, Gegner.fluss.get(zz, "—"),
					g.global_position.snapped(Vector3.ONE * 0.1), g.rueck_ziel, LevelGen.zelle_von(g.rueck_ziel) if g.rueck_ziel != Vector3.INF else "—",
					Gegner.fluss.get(LevelGen.zelle_von(g.rueck_ziel), "—") if g.rueck_ziel != Vector3.INF else "—", g.velocity.length(), g._rueckzug, g._sicht])
		rueck[an] = [g.global_position.distance_to(start_pos) - d0, weg_t]
		erg.append("Rückzug %s: Abstand %+.1f m in 6 s, aus der Sicht nach %s" % ["an " if an else "aus", rueck[an][0], ("%.1f s" % weg_t) if weg_t >= 0.0 else "—"])
		aufraeumen.call()
		await _warte(0.1)
	ok = pruef.call("Rückzug", rueck[true][0] > rueck[false][0] + 5.0 and rueck[true][1] >= 0.0, "Abstand aus %+.1f m, an %+.1f m; aus der Sicht: aus %s, an %s" % [rueck[false][0], rueck[true][0],
		("%.1f s" % rueck[false][1]) if rueck[false][1] >= 0.0 else "nie", ("%.1f s" % rueck[true][1]) if rueck[true][1] >= 0.0 else "nie"]) and ok
	alle_an.call(true)
	var w := _gegner("waechter", stelle)
	var rep := _gegner("reparierer", stelle + seite * 8.0 + vor * 6.0)
	w.alarmieren(start_pos)
	rep.alarmieren(start_pos)
	await _warte(0.5)
	w.hp = w.hp_max * 0.2
	await _warte(7.0)
	var geheilt := w.hp / w.hp_max
	ok = pruef.call("Rückzug zum Reparierer", geheilt >= 0.6, "Leben 20 %% → %.0f %% nach 7 s" % (geheilt * 100)) and ok
	aufraeumen.call()

	# 5) Kamikaze schneidet den Weg ab: du kreist im Reaktorraum (10 m/s, 14 m), er startet in der Mitte (Tiefe 15)
	var kreisbahn := func(t: float, r: float, v: float) -> Array:
		var wb := t * v / r
		return [mitte_r + Vector3(cos(wb), 0, sin(wb)) * r, Vector3(-sin(wb), 0, cos(wb)) * v]
	var kami := {}
	for an in [false, true]:
		alle_an.call(true)
		Gegner.KI.vorhalt = an
		var g := _gegner("kamikaze", mitte_r)
		g._stufe = 15
		g.tempo = 9.0              # langsamer als sonst, damit der Unterschied messbar wird
		g.alarmieren(mitte_r + Vector3(14, 0, 0))
		var t := 0.0
		while t < 8.0 and is_instance_valid(g) and not g._tot:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var bahn: Array = kreisbahn.call(t, 14.0, 10.0)
			schiff.global_position = bahn[0]
			schiff.velocity = bahn[1]
		kami[an] = t
		erg.append("Kamikaze %s: erreicht dich nach %.1f s%s" % ["an " if an else "aus", t, "" if t < 8.0 else " (gar nicht)"])
		aufraeumen.call()
		schiff.global_position = start_pos
		await _warte(0.1)
	ok = pruef.call("Kamikaze schneidet ab", kami[true] < kami[false] - 0.3, "erreicht dich nach %.1f s statt %.1f s" % [kami[true], kami[false]]) and ok
	alle_an.call(true)
	schiff.velocity = Vector3.ZERO
	schiff.aktiv = true
	for e in erg:
		Protokoll.schreib("test", "KI: " + e)
	Protokoll.schreib("test", "KI-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))


## Touch-Steuerung (Stev 2026-10-11): Berührungen simulieren und die Wirkung am Schiff messen. Start mit --touch.
func _touch_test() -> void:
	var erg: Array[String] = []
	var ok := true
	var pruef := func(name: String, gut: bool, text: String):
		erg.append("%s %s: %s" % ["ok  " if gut else "FEHL", name, text])
		return gut
	await _warte(1.0)
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	var s := touch.get_viewport_rect().size
	# Ereignisse kommen in Bildschirmpunkten an, die Knöpfe liegen in der (am Handy 1,4× skalierten) Fläche
	var f := float(DisplayServer.window_get_size().x) / s.x
	var beruehre := func(i: int, p: Vector2, an: bool):
		var e := InputEventScreenTouch.new()
		e.index = i
		e.position = p * f
		e.pressed = an
		Input.parse_input_event(e)
	var ziehe := func(i: int, p: Vector2, rel: Vector2):
		var e := InputEventScreenDrag.new()
		e.index = i
		e.position = p * f
		e.relative = rel * f
		Input.parse_input_event(e)
	await _warte(0.2)
	erg.append("Fläche %s, Faktor Bildschirm/Fläche %.2f" % [s, f])
	ok = pruef.call("Sichtbar", touch.visible and not Input.emulate_mouse_from_touch, "Ebene %s, Maus aus Berührung %s (soll aus)" % [touch.visible, Input.emulate_mouse_from_touch]) and ok
	# Stick: Daumen links unten, 110 nach oben gezogen → volle Fahrt vorwärts
	var st := Vector2(220, s.y - 220)
	beruehre.call(0, st, true)
	ziehe.call(0, st + Vector2(0, -110), Vector2(0, -110))
	await _warte(0.05)
	var vor := Input.get_action_strength("vor")
	var p0 := schiff.global_position
	# zweiter Finger gleichzeitig: Feuer halten
	var feuer_k: Dictionary = touch._knoepfe.filter(func(k): return k.aktion == "feuer")[0]
	var schuesse0 := get_tree().get_nodes_in_group("spieler_geschoss").size()
	beruehre.call(1, feuer_k.mitte, true)
	await _warte(0.5)
	_foto("touch_flug")
	var feuer := Input.is_action_pressed("feuer")
	var schuesse1 := get_tree().get_nodes_in_group("spieler_geschoss").size()
	var weg := schiff.global_position.distance_to(p0)
	ok = pruef.call("Stick", vor > 0.95 and weg > 1.0, "vor %.2f, in 0,5 s %.1f m geflogen" % [vor, weg]) and ok
	ok = pruef.call("Feuer halten (mit Stick zugleich)", feuer and schuesse1 > schuesse0,
		"feuer gedrückt %s, eigene Geschosse %d → %d" % [feuer, schuesse0, schuesse1]) and ok
	beruehre.call(1, feuer_k.mitte, false)
	beruehre.call(0, st + Vector2(0, -110), false)
	await _warte(0.05)
	ok = pruef.call("Loslassen", not Input.is_action_pressed("feuer") and Input.get_action_strength("vor") == 0.0,
		"feuer %s, vor %.2f" % [Input.is_action_pressed("feuer"), Input.get_action_strength("vor")]) and ok
	# Wischen rechts: 300 nach rechts → Schiff dreht nach rechts
	var wisch := func() -> float:
		var blick0 := -schiff.global_basis.z
		var bp := Vector2(s.x * 0.6, s.y * 0.45)
		beruehre.call(2, bp, true)
		for i in 6:
			ziehe.call(2, bp + Vector2(50 * (i + 1), 0), Vector2(50, 0))
			await _warte(0.02)
		beruehre.call(2, bp + Vector2(300, 0), false)
		await _warte(0.1)
		return rad_to_deg(blick0.signed_angle_to(-schiff.global_basis.z, schiff.global_basis.y))
	Eingabe.touch_empfindlichkeit = 1.0
	var winkel: float = await wisch.call()
	ok = pruef.call("Wischen dreht", winkel < -20.0, "300 Bildpunkte nach rechts → %.0f° (negativ = rechts)" % winkel) and ok
	# Empfindlichkeit über den Regler in den Optionen auf 200 % → derselbe Wisch dreht doppelt so weit
	optionen.aufbauen()
	var regler: HSlider = optionen.find_child("TouchEmpfindlichkeit", true, false)
	if regler:
		regler.value = 200
	Eingabe.speichern()
	var winkel2: float = await wisch.call()
	ok = pruef.call("Regler Empfindlichkeit", regler != null and absf(winkel2 / winkel - 2.0) < 0.15,
		"Regler %s, 100 %% → %.0f°, 200 %% → %.0f° (×%.2f, soll 2)" % ["da" if regler else "fehlt", winkel, winkel2, winkel2 / winkel]) and ok
	Eingabe.touch_empfindlichkeit = 1.0
	Eingabe.laden()
	ok = pruef.call("Empfindlichkeit gespeichert", is_equal_approx(Eingabe.touch_empfindlichkeit, 2.0), "nach Laden %.2f" % Eingabe.touch_empfindlichkeit) and ok
	Eingabe.touch_empfindlichkeit = 1.0
	Eingabe.speichern()
	# Knopf hoch und Rollen
	for a in ["hoch", "rollen_links"]:
		var k: Dictionary = touch._knoepfe.filter(func(x): return x.aktion == a)[0]
		beruehre.call(3, k.mitte, true)
		await _warte(0.05)
		var gedr := Input.is_action_pressed(a)
		beruehre.call(3, k.mitte, false)
		ok = pruef.call("Knopf " + a, gedr, "gedrückt %s" % gedr) and ok
	# Waffenwechsel über die Leiste (läuft über _unhandled_input im Schiff)
	var laser0: String = schiff.laser_wahl
	var lw: Dictionary = touch._knoepfe.filter(func(x): return x.aktion == "laser_weiter")[0]
	beruehre.call(4, lw.mitte, true)
	await _warte(0.05)
	beruehre.call(4, lw.mitte, false)
	erg.append("Laserwechsel: %s → %s" % [laser0, schiff.laser_wahl])
	# Pause-Knopf: pausiert, Ebene weg, Maus aus Berührung wieder an (Menü per Tipp)
	var pk: Dictionary = touch._knoepfe.filter(func(x): return x.aktion == "pause")[0]
	var autotest_merken := autotest
	autotest = false             # die Pause greift sonst im Autotest nicht
	beruehre.call(5, pk.mitte, true)
	await _warte(0.1)
	beruehre.call(5, pk.mitte, false)
	await _warte(0.1)
	var pausiert := get_tree().paused
	_foto("touch_pause")
	ok = pruef.call("Pause-Knopf", pausiert and not touch.visible and Input.emulate_mouse_from_touch,
		"pausiert %s, Ebene %s, Maus aus Berührung %s" % [pausiert, touch.visible, Input.emulate_mouse_from_touch]) and ok
	_pause(false)
	autotest = autotest_merken
	await _warte(0.1)
	# Controller benutzt → ausgeblendet; Berührung → wieder da
	await _knopf_druck(JOY_BUTTON_Y)
	var weg_bei_pad := not touch.visible
	beruehre.call(6, Vector2(s.x * 0.6, s.y * 0.3), true)
	await _warte(0.05)
	beruehre.call(6, Vector2(s.x * 0.6, s.y * 0.3), false)
	await _warte(0.05)
	ok = pruef.call("Controller blendet aus", weg_bei_pad and touch.visible, "nach Y weg %s, nach Berührung wieder da %s" % [weg_bei_pad, touch.visible]) and ok
	for e in erg:
		Protokoll.schreib("test", "Touch: " + e)
	Protokoll.schreib("test", "TOUCH-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))


## Controller-Belegung (Stev 2026-10-11): über die Optionen umbelegen, Tausch, Speichern/Laden, Standard.
func _pad_test() -> void:
	var erg: Array[String] = []
	var ok := true
	var pruef := func(name: String, gut: bool, text: String):
		erg.append("%s %s: %s" % ["ok  " if gut else "FEHL", name, text])
		return gut
	Eingabe.zuruecksetzen_pad()
	ok = pruef.call("Standard-Anzeige", Eingabe.pad_text("feuer") == "RT" and Eingabe.pad_text("licht") == "Y" and Eingabe.pad_text("leitstrahl") == "—",
		"Laser „%s“, Scheinwerfer „%s“, Leitstrahl „%s“" % [Eingabe.pad_text("feuer"), Eingabe.pad_text("licht"), Eingabe.pad_text("leitstrahl")]) and ok
	_zeige_hangar()
	await _warte(0.3)
	_optionen_auf()
	await _warte(0.4)
	var knopf: Button = optionen.find_child("Pad_licht", true, false)
	ok = pruef.call("Abschnitt sichtbar", knopf != null and knopf.is_visible_in_tree(), "Knopf Scheinwerfer %s" % ("da" if knopf else "fehlt")) and ok
	# Scheinwerfer über die Optionen auf X: Knopf drücken (A), dann X am Controller
	knopf.grab_focus()
	await _warte(0.1)
	await _knopf_druck(JOY_BUTTON_A)
	var wartet := knopf.text
	await _knopf_druck(JOY_BUTTON_X)
	await _warte(0.1)
	ok = pruef.call("Umbelegen", wartet.begins_with("Knopf drücken") and Eingabe.pad_text("licht") == "X" and Eingabe.pad_text("nachbrenner") == "Y",
		"wartete „%s“, Scheinwerfer „%s“, Nachbrenner (hatte X) „%s“" % [wartet, Eingabe.pad_text("licht"), Eingabe.pad_text("nachbrenner")]) and ok
	var x := InputEventJoypadButton.new()
	x.button_index = JOY_BUTTON_X
	ok = pruef.call("Wirkung", InputMap.event_is_action(x, "licht") and not InputMap.event_is_action(x, "nachbrenner"), "X löst Scheinwerfer aus") and ok
	# B belegen (sonst Zurück) und Optionen bleiben offen
	var leit: Button = optionen.find_child("Pad_leitstrahl", true, false)
	leit.grab_focus()
	await _knopf_druck(JOY_BUTTON_A)
	await _knopf_druck(JOY_BUTTON_BACK)
	await _warte(0.1)
	ok = pruef.call("Leitstrahl auf Select", Eingabe.pad_text("leitstrahl") == "Select" and optionen.visible, "Leitstrahl „%s“, Optionen offen %s" % [Eingabe.pad_text("leitstrahl"), optionen.visible]) and ok
	# Trigger: Rakete auf RT → Laser bekommt LT
	Eingabe.belegen_pad("rakete", _trigger(JOY_AXIS_TRIGGER_RIGHT))
	ok = pruef.call("Trigger tauschen", Eingabe.pad_text("rakete") == "RT" and Eingabe.pad_text("feuer") == "LT", "Rakete „%s“, Laser „%s“" % [Eingabe.pad_text("rakete"), Eingabe.pad_text("feuer")]) and ok
	# Abbruch nach 5 s ohne Eingabe
	knopf.grab_focus()
	await _knopf_druck(JOY_BUTTON_A)
	await _warte(Optionen.PAD_WARTEN + 0.3)
	ok = pruef.call("Abbruch nach Wartezeit", optionen._wartet_pad == "" and Eingabe.pad_text("licht") == "X", "wartet noch „%s“, Scheinwerfer „%s“" % [optionen._wartet_pad, Eingabe.pad_text("licht")]) and ok
	_foto("optionen_controller")
	# Speichern und Laden
	for a in Eingabe._standard_pad:
		Eingabe._setze_pad(a, Eingabe._standard_pad[a])
	Eingabe.laden()
	ok = pruef.call("Gespeichert", Eingabe.pad_text("licht") == "X" and Eingabe.pad_text("rakete") == "RT" and Eingabe.pad_text("leitstrahl") == "Select",
		"nach Laden Scheinwerfer „%s“, Rakete „%s“, Leitstrahl „%s“" % [Eingabe.pad_text("licht"), Eingabe.pad_text("rakete"), Eingabe.pad_text("leitstrahl")]) and ok
	_optionen_zu()
	await _warte(0.3)
	var hilfe := ""
	for l in hangar.find_children("*", "Label", true, false):
		if l.text.contains("Controller:"):
			hilfe = l.text
	ok = pruef.call("Hilfetext", "RT Rakete" in hilfe and "LT Laser" in hilfe, hilfe.get_slice("Controller:", 1).left(120)) and ok
	_optionen_auf()
	await _warte(0.3)
	(optionen.find_child("PadStandard", true, false) as Button).pressed.emit()
	ok = pruef.call("Standard", Eingabe.pad_text("licht") == "Y" and Eingabe.pad_text("feuer") == "RT" and Eingabe.pad_text("leitstrahl") == "—",
		"Scheinwerfer „%s“, Laser „%s“, Leitstrahl „%s“" % [Eingabe.pad_text("licht"), Eingabe.pad_text("feuer"), Eingabe.pad_text("leitstrahl")]) and ok
	_optionen_zu()
	await _warte(0.3)
	# Die Controller-Zeile im Hangar muss in die Breite passen (2026-10-11: lief mit „Steuerkreuz ← / Steuerkreuz →“ aus dem Bild)
	var zeile := ""
	var groesse := 16
	for l in hangar.find_children("*", "Label", true, false):
		if l.text.contains("Controller:"):
			zeile = l.text.get_slice("\n", l.text.count("\n"))
			groesse = l.get_theme_font_size("font_size")
	var breite := ThemeDB.fallback_font.get_string_size(zeile, HORIZONTAL_ALIGNMENT_LEFT, -1, groesse).x
	var platz := hangar.get_viewport_rect().size.x
	if platz < 640.0:              # ohne Fenster (headless) gibt es keine echte Breite
		erg.append("Hilfszeile passt: übersprungen, Fläche nur %.0f Punkte breit (ohne Fenster)" % platz)
	else:
		ok = pruef.call("Hilfszeile passt", breite <= platz, "%.0f von %.0f Punkten: %s" % [breite, platz, zeile.right(60)]) and ok
	for e in erg:
		Protokoll.schreib("test", "Controller-Belegung: " + e)
	Protokoll.schreib("test", "PAD-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))


func _trigger(achse: JoyAxis) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = achse
	e.axis_value = 1.0
	return e


## Gegner-Einführung (Stev 2026-10-11): je Tiefe 1–25 zwölf Minen besetzen und zählen, wer vorkommt.
func _besetzung_test() -> void:
	var ok := true
	var tiefe_merken := tiefe
	for t in range(1, 26):
		tiefe = t
		var arten := {}
		var arten_je_mine := 0
		var max_schwarm_raum := 0
		var max_schwaerme_mine := 0
		var debuet_n: Array[int] = []
		var debuet := ""
		for typ in Gegner.EINFUEHRUNG:
			if Gegner.EINFUEHRUNG[typ][0] == t and t > 1:
				debuet = typ
		for saat in 12:
			gen.erzeuge(9000 + saat * 31 + t, t)
			reaktor.position = gen.mitte(gen.reaktor_raum)
			_rng.seed = 777 + saat
			_gegner_setzen()
			var hier := {}
			for g in get_tree().get_nodes_in_group("gegner"):
				if not g.ist_boss and g.get_meta("nest", 0) == 0:
					hier[g.typ] = hier.get(g.typ, 0) + 1
				g.free()
			for typ in hier:
				arten[typ] = arten.get(typ, 0) + hier[typ]
			arten_je_mine += hier.size()
			for r in schwarm_je_raum:
				max_schwarm_raum = maxi(max_schwarm_raum, schwarm_je_raum[r])
			max_schwaerme_mine = maxi(max_schwaerme_mine, schwarm_je_raum.size())
			if debuet != "":
				debuet_n.append(hier.get(debuet, 0))
		hud.boss_aus()
		var zu_frueh: Array = arten.keys().filter(func(typ): return Gegner.EINFUEHRUNG.has(typ) and Gegner.EINFUEHRUNG[typ][0] > t)
		var gut := zu_frueh.is_empty() and max_schwarm_raum <= 1 and (t >= 10 or not arten.has("drohne"))
		if debuet != "":
			var soll := 3 if debuet == "drohne" else (1 if debuet in Gegner.EINZELGAENGER else 2)
			gut = gut and debuet_n.all(func(n): return n == soll)
		ok = ok and gut
		Protokoll.schreib("test", "Besetzung %s Tiefe %2d: neu %-14s je Mine %.1f Arten, Schwärme je Mine ≤%d, je Raum ≤%d, Arten %s%s" % [
			"ok  " if gut else "FEHL", t, (debuet + " " + str(debuet_n)) if debuet != "" else "—", arten_je_mine / 12.0,
			max_schwaerme_mine, max_schwarm_raum, arten, (" ZU FRÜH %s" % [zu_frueh]) if not zu_frueh.is_empty() else ""])
	tiefe = tiefe_merken
	Protokoll.schreib("test", "BESETZUNG-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))


func _tasten_test() -> void:
	var erg: Array[String] = []
	var ok := true
	var pruef := func(name: String, gut: bool, text: String):
		erg.append("%s %s: %s" % ["ok  " if gut else "FEHL", name, text])
		return gut
	Eingabe.zuruecksetzen()
	ok = pruef.call("Anzeige", Eingabe.text_fuer("notfallschild") == "R" and Eingabe.text_fuer("runter") == "Strg / C" and Eingabe.text_fuer("feuer") == "Linke Maustaste",
		"Notfallschild „%s“, Runter „%s“, Laser „%s“" % [Eingabe.text_fuer("notfallschild"), Eingabe.text_fuer("runter"), Eingabe.text_fuer("feuer")]) and ok
	# Leitstrahl ab Werk unbelegt (Stev 2026-10-11), auch nicht am Controller; alte Dateien mit Tab werden umgestellt
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	var sel := InputEventJoypadButton.new()
	sel.button_index = JOY_BUTTON_BACK
	ok = pruef.call("Leitstrahl unbelegt", InputMap.action_get_events("leitstrahl").is_empty() and not InputMap.event_is_action(tab, "leitstrahl") and not InputMap.event_is_action(sel, "leitstrahl"),
		"Belegung „%s“, Ereignisse %d" % [Eingabe.text_fuer("leitstrahl"), InputMap.action_get_events("leitstrahl").size()]) and ok
	var alt_datei := ConfigFile.new()
	alt_datei.set_value("tasten", "leitstrahl", ["taste:%d" % KEY_TAB])
	alt_datei.set_value("tasten", "licht", ["taste:%d" % KEY_L])
	alt_datei.save(Eingabe._datei)
	Eingabe.laden()
	ok = pruef.call("Alte Belegung umgestellt", Eingabe.text_fuer("leitstrahl") == "—" and Eingabe.text_fuer("licht") == "L",
		"Leitstrahl „%s“ (soll —), eigene Taste Scheinwerfer „%s“ bleibt" % [Eingabe.text_fuer("leitstrahl"), Eingabe.text_fuer("licht")]) and ok
	Eingabe.belegen("leitstrahl", tab)
	var neu_datei := ConfigFile.new()
	neu_datei.load(Eingabe._datei)
	for a in Eingabe._standard:
		Eingabe._setze_pc(a, Eingabe._standard[a])
	Eingabe.laden()
	ok = pruef.call("Leitstrahl selbst belegbar", Eingabe.text_fuer("leitstrahl") == "Tab" and neu_datei.get_value("stand", "fassung", 1) == 2,
		"nach Belegen und Neuladen „%s“, Fassung %s" % [Eingabe.text_fuer("leitstrahl"), neu_datei.get_value("stand", "fassung", 1)]) and ok
	Eingabe.zuruecksetzen()
	# Optionen öffnen, Knopf „Notfallschild“ drücken, dann G auf der Tastatur
	_zeige_hangar()
	await _warte(0.3)
	_optionen_auf()
	await _warte(0.4)
	var knopf: Button = optionen.find_child("Taste_notfallschild", true, false)
	knopf.pressed.emit()
	await _warte(0.1)
	var wartet := knopf.text
	var g := InputEventKey.new()
	g.physical_keycode = KEY_G
	g.keycode = KEY_G
	g.pressed = true
	Input.parse_input_event(g)
	await _warte(0.2)
	var g_los := g.duplicate()
	g_los.pressed = false
	Input.parse_input_event(g_los)
	await _warte(0.2)
	ok = pruef.call("Umbelegen", wartet == "Taste drücken …" and knopf.text == "G" and Eingabe.text_fuer("notfallschild") == "G",
		"Knopf zeigte „%s“, danach „%s“" % [wartet, knopf.text]) and ok
	var g_wirkt := InputMap.event_is_action(g, "notfallschild")
	var r := InputEventKey.new()
	r.physical_keycode = KEY_R
	ok = pruef.call("Wirkung", g_wirkt and not InputMap.event_is_action(r, "notfallschild"), "G löst Notfallschild aus %s, R nicht mehr %s" % [g_wirkt, not InputMap.event_is_action(r, "notfallschild")]) and ok
	# Tausch: Scheinwerfer auf G → Notfallschild bekommt F
	var getauscht := Eingabe.belegen("licht", g)
	ok = pruef.call("Tausch", getauscht == "notfallschild" and Eingabe.text_fuer("licht") == "G" and Eingabe.text_fuer("notfallschild") == "F",
		"Scheinwerfer „%s“, Notfallschild „%s“" % [Eingabe.text_fuer("licht"), Eingabe.text_fuer("notfallschild")]) and ok
	# Maustaste: Rakete auf mittlere Maustaste
	var mm := InputEventMouseButton.new()
	mm.button_index = MOUSE_BUTTON_MIDDLE
	Eingabe.belegen("rakete", mm)
	# Speichern und Laden: InputMap auf Standard zurück (ohne Speichern), dann aus der Datei laden
	for a in Eingabe._standard:
		Eingabe._setze_pc(a, Eingabe._standard[a])
	var vorher := Eingabe.text_fuer("licht")
	Eingabe.laden()
	ok = pruef.call("Gespeichert", vorher == "F" and Eingabe.text_fuer("licht") == "G" and Eingabe.text_fuer("rakete") == "Mittlere Maustaste",
		"nach Zurücksetzen im Speicher „%s“, nach Laden Scheinwerfer „%s“, Rakete „%s“" % [vorher, Eingabe.text_fuer("licht"), Eingabe.text_fuer("rakete")]) and ok
	optionen.aufbauen()
	await _warte(0.4)
	_foto("optionen_tasten")
	var hilfe := ""
	_optionen_zu()
	await _warte(0.3)
	for l in hangar.find_children("*", "Label", true, false):
		if "Nachbrenner" in l.text and "Notfallschild" in l.text:
			hilfe = l.text
	ok = pruef.call("Hilfetext", "G Scheinwerfer" in hilfe and "Mittlere Maustaste Rakete" in hilfe, hilfe.get_slice("\n", 1).left(140)) and ok
	# Standard
	optionen.aufbauen()
	(optionen.find_child("TastenStandard", true, false) as Button).pressed.emit()
	ok = pruef.call("Standard", Eingabe.text_fuer("licht") == "F" and Eingabe.text_fuer("notfallschild") == "R" and Eingabe.text_fuer("rakete") == "Rechte Maustaste",
		"Scheinwerfer „%s“, Notfallschild „%s“, Rakete „%s“" % [Eingabe.text_fuer("licht"), Eingabe.text_fuer("notfallschild"), Eingabe.text_fuer("rakete")]) and ok
	for e in erg:
		Protokoll.schreib("test", "Tasten: " + e)
	Protokoll.schreib("test", "TASTEN-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))


## Neue Gegnerarten (2026-10-10): Bild je Art, dann jedes Verhalten gemessen.
func _gegner_neu_test() -> void:
	# Der Lauf läuft schon (Autotest-Start); ein zweites _starte_lauf ließe das erste Schiff stehen.
	await _warte(1.0)
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	await _warte(0.3)
	var vor := -schiff.global_basis.z
	var rechts := schiff.global_basis.x
	var start := schiff.global_transform
	var erg: Array[String] = []
	var ok := true
	var pruef := func(name: String, gut: bool, text: String):
		erg.append("%s %s: %s" % ["ok  " if gut else "FEHL", name, text])
		Protokoll.schreib("test", "Neue Gegner: " + erg[-1])      # sofort, damit ein Hänger zeigt, wo
		return gut
	# Bilder
	for typ in ["saeger", "rammbock", "greifer", "lauerer", "netzwerfer", "stoerer", "scharfschuetze", "splitter", "splitterteil", "nest"]:
		var abst: float = {"nest": 7.5, "rammbock": 6.5, "splitterteil": 3.0, "scharfschuetze": 6.5}.get(typ, 5.0)
		var g := _testgegner(typ, schiff.global_position + vor * abst + Vector3(0, 0.4, 0), false)
		g.rotate_y(0.7)
		await _warte(0.5)
		_foto("neu2_%s" % typ)
		g.free()
	var schutz := func():
		schiff.unverwundbar = false
		schiff.schild_max = 100000.0
		schiff.schild = 100000.0
		schiff.huelle = schiff.huelle_max
		schiff.global_transform = start
		schiff.velocity = Vector3.ZERO
		Protokoll.schreib("test", "Neue Gegner: Schiff aktiv %s, unverwundbar %s, Schild %.0f" % [schiff.aktiv, schiff.unverwundbar, schiff.schild])
	# 1 Säger
	schutz.call()
	var g := _testgegner("saeger", schiff.global_position + vor * 10.0, true)
	g.alarmieren(schiff.global_position)
	var min_d := 99.0
	var weg_danach := 0.0
	for i in 240:
		await get_tree().physics_frame
		var d := g.global_position.distance_to(schiff.global_position)
		min_d = minf(min_d, d)
		if min_d < Gegner.SAEGE_NAH:
			weg_danach = maxf(weg_danach, d)
	var verlust := 100000.0 - schiff.schild
	ok = pruef.call("Säger", verlust > 10.0 and weg_danach > 4.0, "kam auf %.1f m, sägte %.0f Schaden, prallte ab auf %.1f m" % [min_d, verlust, weg_danach]) and ok
	g.free()
	# 2 Rammbock: Front blockt, Rücken nicht; Sturmlauf; Wand betäubt
	schutz.call()
	g = _testgegner("rammbock", schiff.global_position + vor * 8.0, false)
	await _warte(0.1)
	var h0 := g.hp
	g.treffer_von(20.0, g.global_position - schiff.global_position)
	var vorn_block := g.hp == h0
	g.treffer_von(20.0, schiff.global_position - g.global_position)
	var hinten := g.hp < h0
	g.free()
	g = _testgegner("rammbock", schiff.global_position + vor * 20.0, true)
	g.alarmieren(schiff.global_position)
	g._cd = 0.0
	var max_v := 0.0
	for i in 240:
		await get_tree().physics_frame
		max_v = maxf(max_v, g.velocity.length())
	verlust = 100000.0 - schiff.schild
	ok = pruef.call("Rammbock", vorn_block and hinten and max_v > 18.0 and verlust > 20.0,
		"vorn geblockt %s, hinten Schaden %s, Sturm %.0f m/s, Schaden %.0f" % [vorn_block, hinten, max_v, verlust]) and ok
	# Wand: in Richtung der nächsten Wand losrasen lassen
	var raum := get_viewport().get_world_3d().direct_space_state
	var wand_r := Vector3.ZERO
	for r in [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var t := raum.intersect_ray(PhysicsRayQueryParameters3D.create(g.global_position, g.global_position + r * 25.0, 1))
		if not t.is_empty():
			wand_r = r
			break
	g.global_basis = Basis.looking_at(wand_r, Vector3.UP if absf(wand_r.y) < 0.9 else Vector3.FORWARD)
	g._modus = "ramme"
	g._ramm_dir = wand_r
	g._phase_t = 3.0
	var betaeubt := false
	for i in 150:
		await get_tree().physics_frame
		if g.ist_betaeubt():
			betaeubt = true
			break
	h0 = g.hp
	g.treffer_von(20.0, -(-g.global_basis.z))       # von vorn, aber betäubt
	ok = pruef.call("Rammbock Wand", betaeubt and g.hp < h0, "betäubt %s, dann von vorn verwundbar %s" % [betaeubt, g.hp < h0]) and ok
	g.free()
	# 3 Greifer: zieht das stehende Schiff heran
	schutz.call()
	g = _testgegner("greifer", schiff.global_position + vor * 17.0, true)
	g.alarmieren(schiff.global_position)
	g._cd = 0.0
	await get_tree().physics_frame
	var d0 := g.global_position.distance_to(schiff.global_position)
	await _warte(2.0)
	var d1 := g.global_position.distance_to(schiff.global_position)
	var p_schiff := schiff.global_position.distance_to(start.origin)
	ok = pruef.call("Greifer", p_schiff > 3.0, "Schiff %.1f m herangezogen (Abstand %.1f → %.1f m)" % [p_schiff, d0, d1]) and ok
	g.free()
	# 4 Lauerer: an der Wand, flimmert, bemerkt erst nah, springt an
	schutz.call()
	g = _testgegner("lauerer", schiff.global_position + vor * 10.0, true)
	g._sicht_t = 0.5           # erster Blick erst, wenn das Schiff unten auf Abstand gerückt ist (sonst bemerkt er es aus 10 m)
	await _warte(0.2)
	var front: Vector3 = -g.global_basis.z
	var frei_t := raum.intersect_ray(PhysicsRayQueryParameters3D.create(g.global_position, g.global_position + front * 30.0, 1))
	var frei_l: float = 30.0 if frei_t.is_empty() else g.global_position.distance_to(frei_t.position)
	var fern := minf(frei_l - 2.0, 20.0)
	schiff.global_position = g.global_position + front * fern
	var t_min := 1.0
	var t_max := 0.0
	for i in 40:
		await get_tree().physics_frame
		t_min = minf(t_min, g._tarn)
		t_max = maxf(t_max, g._tarn)
	var ruhig := not g._alarm
	schiff.global_position = g.global_position + front * 9.0
	var sichtbar_beim_angriff := false
	var lauer_min := 99.0
	for i in 180:
		await get_tree().physics_frame
		lauer_min = minf(lauer_min, g.global_position.distance_to(schiff.global_position))
		if g._modus == "sprung" and g._tarn < 0.05:
			sichtbar_beim_angriff = true
	Protokoll.schreib("test", "Neue Gegner: Lauerer kam bis %.1f m, Modus %s, Schiff aktiv %s unverwundbar %s" % [lauer_min, g._modus, schiff.aktiv, schiff.unverwundbar])
	verlust = 100000.0 - schiff.schild
	ok = pruef.call("Lauerer", t_min > 0.5 and t_max < 0.9 and t_max - t_min > 0.05 and (ruhig or fern <= Gegner.LAUER_NAH) and verlust > 10.0 and sichtbar_beim_angriff,
		"Durchsichtigkeit %.2f–%.2f, in %.0f m ruhig %s, in 9 m angesprungen: Schaden %.0f, beim Sprung sichtbar %s" % [t_min, t_max, fern, ruhig, verlust, sichtbar_beim_angriff]) and ok
	g.free()
	# 5 Netzwerfer: Netz bremst
	schutz.call()
	g = _testgegner("netzwerfer", schiff.global_position + vor * 12.0, true)
	g.alarmieren(schiff.global_position)
	g._cd = 0.0
	for i in 300:
		await get_tree().physics_frame
		if schiff.netz_t > 0.0:
			break
	var genetzt := schiff.netz_t > 0.0
	Protokoll.schreib("test", "Neue Gegner: Netzwerfer Sicht %s, Alarm %s, cd %.1f, Abstand %.1f, Netzschüsse in der Luft %d" % [g._sicht, g._alarm, g._cd,
		g.global_position.distance_to(schiff.global_position), level.get_children().filter(func(k): return k is Geschoss and k.wirkung == "netz").size()])
	g.free()
	Input.action_press("zurueck")
	await _warte(0.8)
	var v_netz := schiff.velocity.length()
	Input.action_release("zurueck")
	await _warte(2.5)
	schiff.velocity = Vector3.ZERO
	Input.action_press("zurueck")
	await _warte(0.8)
	var v_frei := schiff.velocity.length()
	Input.action_release("zurueck")
	ok = pruef.call("Netzwerfer", genetzt and v_netz < v_frei * 0.5, "Netz getroffen %s, Tempo im Netz %.1f m/s, frei %.1f m/s" % [genetzt, v_netz, v_frei]) and ok
	# 6 Störsender: nur Schild, doppelt, Laden gesperrt
	schutz.call()
	schiff.schild_max = 200.0
	schiff.schild = 200.0
	var huelle0 := schiff.huelle
	g = _testgegner("stoerer", schiff.global_position + vor * 12.0, true)
	g.alarmieren(schiff.global_position)
	g._cd = 0.0
	for i in 300:
		await get_tree().physics_frame
		if schiff.emp_t > 0.0:
			break
	var emp := schiff.emp_t > 0.0
	var schild_weg := 200.0 - schiff.schild
	var emp_schaden := g.schaden
	g.free()
	schiff.schild = 100.0
	schiff._seit_treffer = 100.0
	schiff.emp_t = 3.0
	await _warte(1.0)
	var gesperrt := schiff.schild == 100.0
	schiff.emp_t = 0.0
	await _warte(1.0)
	var laedt := schiff.schild > 100.0
	ok = pruef.call("Störsender", emp and huelle0 == schiff.huelle and schild_weg >= 2.0 * emp_schaden * 0.99 and gesperrt and laedt,
		"getroffen %s, Schild −%.0f (Schuss %.0f ×2), Hülle unverändert %s, Laden gesperrt %s, danach lädt %s" % [emp, schild_weg, emp_schaden, huelle0 == schiff.huelle, gesperrt, laedt]) and ok
	# 7 Scharfschütze: stillhalten = Treffer, seitlich weg = verfehlt
	var faelle := []
	for ausweichen in [false, true]:
		schutz.call()
		var vt := raum.intersect_ray(PhysicsRayQueryParameters3D.create(schiff.global_position, schiff.global_position + vor * 25.0, 1))
		var frei_vor: float = 25.0 if vt.is_empty() else schiff.global_position.distance_to(vt.position)
		g = _testgegner("scharfschuetze", schiff.global_position + vor * minf(frei_vor - 3.0, 22.0), true)
		g.alarmieren(schiff.global_position)
		g._cd = 0.0
		var t0 := Time.get_ticks_msec()
		while not g.zielt_gerade() and Time.get_ticks_msec() - t0 < 3000:
			await get_tree().physics_frame
		Protokoll.schreib("test", "Neue Gegner: Scharfschütze legt an %s nach %.1f s, Sicht %s, Abstand %.1f" % [g.zielt_gerade(), (Time.get_ticks_msec() - t0) / 1000.0, g._sicht, g.global_position.distance_to(schiff.global_position)])
		await _warte(0.3)
		if ausweichen:
			var seite := rechts * 10.0
			if not raum.intersect_ray(PhysicsRayQueryParameters3D.create(schiff.global_position, schiff.global_position + seite * 1.2, 1)).is_empty():
				seite = -seite
			schiff.global_position += seite
		await _warte(2.5)
		faelle.append(100000.0 - schiff.schild)
		g.free()
	ok = pruef.call("Scharfschütze", faelle[0] > 20.0 and faelle[1] == 0.0, "stillgehalten Schaden %.0f, nach 0,3 s 10 m seitlich weg Schaden %.0f" % [faelle[0], faelle[1]]) and ok
	# 8 Splitter
	schutz.call()
	var teile_vor := get_tree().get_nodes_in_group("gegner").size()
	g = _testgegner("splitter", schiff.global_position + vor * 12.0, false)
	g.treffer(1e9)
	await _warte(0.3)
	var teile := 0
	for x in get_tree().get_nodes_in_group("gegner"):
		if x.typ == "splitterteil":
			teile += 1
	ok = pruef.call("Splitter", teile == 0, "Teile beim Abschuss: %d (soll 0, teilt sich nicht mehr)" % teile) and ok
	for x in get_tree().get_nodes_in_group("gegner"):
		x.free()
	# 9 Schwarmnest
	g = _testgegner("nest", schiff.global_position + vor * 12.0, true)
	await _warte(0.2)
	var an_wand := raum.intersect_ray(PhysicsRayQueryParameters3D.create(g.global_position, g.global_position + g.global_basis.z * 3.0, 1)).size() > 0
	g.alarmieren(schiff.global_position)
	var kinder := []
	for runde in 5:
		g._spezial_t = 0.0
		await _warte(0.3)
		kinder.append(g.nest_kinder())
	ok = pruef.call("Schwarmnest", an_wand and kinder[0] == 2 and kinder[-1] == Gegner.NEST_MAX, "an der Wand %s, Drohnen je Takt %s (höchstens %d)" % [an_wand, kinder, Gegner.NEST_MAX]) and ok
	for x in get_tree().get_nodes_in_group("gegner"):
		x.free()
	Protokoll.schreib("test", "GEGNER-NEU-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))


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
		if typ == "drohne":       # Schussfarbe mit aufs Bild (gelb, nicht Augenfarbe)
			g._schiessen()
			await _warte(0.08)
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


## Neue Aufrüstungen: jede einzeln im Spiel gemessen, dazu Meisterschaft, Sperren und Hangar-Reiter.
func _aufwertungs_test() -> void:
	var erg: Array[String] = []
	var ok := true
	var pruef := func(name: String, gut: bool, text: String):
		erg.append("%s %s: %s" % ["ok  " if gut else "FEHL", name, text])
		return gut
	# Sperren und Meisterschaft
	Meta.zuruecksetzen()
	Meta.rekord = 4
	ok = pruef.call("Sperre", not Meta.freigeschaltet("erzausbeute") and Meta.freigeschaltet("laserschaden") and not Meta.freigeschaltet("radar"),
		"Rekord 4: Wirtschaft %s, Kampf %s, Werkzeuge %s" % [Meta.freigeschaltet("erzausbeute"), Meta.freigeschaltet("laserschaden"), Meta.freigeschaltet("radar")]) and ok
	Meta.rekord = 16
	Meta.bank = 999999
	Meta.stufen = {"laserschaden": 10}
	var k_soll := int(round(50 * pow(Meta.PREIS_FAKTOR, 8) * pow(Meta.MEISTER_FAKTOR, 2)))
	ok = pruef.call("Meisterschaft", is_equal_approx(Meta.wert("laserschaden"), 0.84) and Meta.kosten("laserschaden") == k_soll and Meta.kaufbar("laserschaden"),
		"Stufe 10 (8 + Meister 2) → +%.0f %% Schaden, nächste kostet %d (soll %d), kaufbar %s" % [Meta.wert("laserschaden") * 100, Meta.kosten("laserschaden"), k_soll, Meta.kaufbar("laserschaden")]) and ok
	# Preiskurve ×2,0: Schild Stufe 1/4/8 kostet 40/320/5120, Streufeuer Mk II→III 72→144
	Meta.stufen = {}
	var p1 := Meta.kosten("schild")
	Meta.stufen = {"schild": 3}
	var p4 := Meta.kosten("schild")
	Meta.stufen = {"schild": 7}
	var p8 := Meta.kosten("schild")
	Meta.stufen = {"laserschaden": 10}
	ok = pruef.call("Preiskurve", p1 == 40 and p4 == 320 and p8 == 5120 and Waffen.verbessern_preis("streu", 2) == 2 * Waffen.verbessern_preis("streu", 1),
		"Schild 40/%d/%d, Streufeuer Mk %d → %d" % [p4, p8, Waffen.verbessern_preis("streu", 1), Waffen.verbessern_preis("streu", 2)]) and ok
	# Schild endlos: Meister 1/10/30 → +25 je Stufe, Preis 10240 · (1 + 0,2 · n)
	var schild_k := []
	var schild_w := []
	for n in [0, 10, 30]:
		Meta.stufen = {"schild": 8 + n}
		schild_k.append(Meta.kosten("schild"))
		schild_w.append(Meta.wirkung_text("schild", 8 + n))
	Meta.stufen = {"laserschaden": 10}
	ok = pruef.call("Schild endlos", schild_k == [10240, 30720, 71680] and schild_w == ["Schild 250", "Schild 500", "Schild 1000"] and not (func(): Meta.stufen["schild"] = 200; var a := Meta.ausgereizt("schild"); Meta.stufen.erase("schild"); return a).call(),
		"Meister 0/10/30: %s, Preise %s" % [", ".join(schild_w), schild_k]) and ok
	# Notfallschild: erst kaufen (10 min), dann −8 % je Stufe, endlos
	var nf := []
	for st in [0, 1, 2, 11]:
		Meta.stufen = {"schildladung": st}
		nf.append(Meta.notfall_abklingzeit(st))
	Meta.stufen = {"schildladung": 0}
	var nf_k0 := Meta.kosten("schildladung")
	Meta.stufen = {"laserschaden": 10}
	ok = pruef.call("Notfallschild Stufen", nf[0] == 0.0 and is_equal_approx(nf[1], 600.0) and is_equal_approx(nf[2], 576.0) and absf(nf[3] - 600.0 * pow(0.96, 10)) < 0.01 and nf_k0 == 250,
		"Abklingzeit Stufe 0/1/2/11: %s s, erste Stufe kostet %d" % [nf.map(func(x): return "%.0f" % x), nf_k0]) and ok
	# Alle Aufrüstungen endlos: keine ist bei Stufe 200 ausgereizt; Wartezeiten −4 %, Reichweiten +4 % je Meisterstufe
	var nie_aus := Meta.AUFRUESTUNGEN.filter(func(a): Meta.stufen = {a.id: 200}; return Meta.ausgereizt(a.id)).map(func(a): return a.id)
	Meta.stufen = {"schildpause": 15, "nachbrenner": 14, "magnet": 13, "radar": 13, "notschild": 5}
	var sw := Meta.schiffswerte()
	var soll_e := [3.0 * pow(0.96, 10), 4.5 * pow(0.96, 10), 12.0 * pow(1.04, 10), 45.0 * pow(1.04, 10), 5]
	var ist_e := [sw.schild_pause, sw.nachbrenner_cd, sw.magnet, sw.radar, sw.notschild]
	var gleich := true
	for i in 5:
		gleich = gleich and absf(float(ist_e[i]) - float(soll_e[i])) < 0.01
	ok = pruef.call("Alles endlos", nie_aus.is_empty() and gleich, "ausgereizt bei Stufe 200: %s; Meister 10: Schildpause %.2f s, Nachbrenner %.2f s, Magnet %.1f m, Radar %.0f m, Notschild %d; Text „%s“" % [
		nie_aus, ist_e[0], ist_e[1], ist_e[2], ist_e[3], ist_e[4], Meta.wirkung_text("nachbrenner", 14)]) and ok
	Meta.stufen = {"laserschaden": 10}
	# Alles auf eine Teststufe
	Meta.stufen = {"laserschaden": 3, "feuerrate": 5, "raketenschaden": 2, "kritisch": 6, "schildladen": 5, "schildpause": 5,
		"reparatur": 2, "notschild": 1, "erzausbeute": 5, "beutechance": 5, "magnet": 2, "abschluss": 4,
		"nachbrenner": 3, "fluchtzeit": 5, "radar": 1, "schildladung": 3}
	Meta.start_tiefe = 1
	Meta.speichern()
	_starte_lauf()
	await _warte(1.0)
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	for b in get_tree().get_nodes_in_group("beute"):
		b.free()
	schiff.unverwundbar = true
	# Notfallschild im Flug: Taste R füllt den Schild, zweiter Druck während der Abklingzeit tut nichts
	schiff.schild = 5.0
	Input.action_press("notfallschild")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("notfallschild")
	var nf_voll := is_equal_approx(schiff.schild, schiff.schild_max)
	var nf_rest := schiff.notfall_rest
	schiff.schild = 5.0
	Input.action_press("notfallschild")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("notfallschild")
	await _warte(0.3)
	_foto("notfallschild_hud")
	ok = pruef.call("Notfallschild im Flug", nf_voll and absf(nf_rest - 600.0 * 0.96 * 0.96) < 0.1 and schiff.schild < 10.0 and hud.notfall.begins_with("Notfallschild 9:"),
		"Taste R: Schild 5 → voll %s, Abklingzeit %.0f s (Stufe 3), zweiter Druck Schild %.0f, HUD „%s“" % [nf_voll, nf_rest, schiff.schild, hud.notfall]) and ok
	var neue := func() -> Array:
		var aus := []
		for k in level.get_children():
			if k is Geschoss and k.vom_spieler and not k.has_meta("alt"):
				k.set_meta("alt", true)
				aus.append(k)
		return aus
	neue.call()
	# Laserschaden und Feuerrate (ohne Zielrechner)
	var krit := schiff.krit
	schiff.krit = 0.0
	schiff.laser_wahl = "zwilling"
	schiff.laser_schuss()
	var gs: Array = neue.call()
	var w := Waffen.finde("zwilling")
	ok = pruef.call("Laserschaden", gs.size() == 1 and is_equal_approx(gs[0].schaden, w.schaden * 1.3),
		"Zwilling %.1f statt %.1f (+30 %%)" % [gs[0].schaden if gs else 0.0, w.schaden]) and ok
	ok = pruef.call("Feuerrate", is_equal_approx(schiff._laser_cd, w.cd / 1.3), "Abklingzeit %.3f s statt %.3f s" % [schiff._laser_cd, w.cd]) and ok
	schiff.raketen_schuss()
	gs = neue.call()
	var rw := Waffen.finde(schiff.rakete_wahl)
	ok = pruef.call("Raketenschaden", gs.size() >= 1 and is_equal_approx(gs[0].schaden, rw.schaden * 1.24),
		"%s %.1f statt %.1f (+24 %%)" % [rw.id, gs[0].schaden if gs else 0.0, rw.schaden]) and ok
	# Zielrechner: 400 Schüsse, Anteil doppelter Schaden
	schiff.krit = krit
	var doppelt := 0
	for i in 400:
		schiff.laser_schuss()
		for g in neue.call():
			if g.schaden > w.schaden * 1.3 * 1.5:
				doppelt += 1
			g.free()
	ok = pruef.call("Zielrechner", doppelt > 400 * 0.17 and doppelt < 400 * 0.31, "%d von 400 doppelt (soll ~24 %%)" % doppelt) and ok
	# Schild
	schiff.velocity = Vector3.ZERO
	schiff.schild = 0.0
	schiff._seit_treffer = schiff.schild_pause + 0.01
	schiff.schild_laden(1.0)
	ok = pruef.call("Schildlader", is_equal_approx(schiff.schild, 1.5 * 2.0 * 3.0), "im Stand %.1f je s statt 4,5" % schiff.schild) and ok
	ok = pruef.call("Schnellstart", is_equal_approx(schiff.schild_pause, 3.0), "Pause %.1f s statt 5,0" % schiff.schild_pause) and ok
	# Notschild
	schiff.unverwundbar = false
	schiff.treffer(1.0e6)
	ok = pruef.call("Notschild", schiff.aktiv and is_equal_approx(schiff.huelle, 1.0) and schiff.schild == schiff.schild_max and schiff.notschild == 0,
		"nach tödlichem Treffer aktiv %s, Hülle %.0f, Schild %.0f/%.0f, übrig %d" % [schiff.aktiv, schiff.huelle, schiff.schild, schiff.schild_max, schiff.notschild]) and ok
	schiff.unverwundbar = true
	# Reparaturdrohne: neue Tiefe lädt
	schiff.huelle = 50.0
	_lade_level()
	await _warte(1.0)
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	for b in get_tree().get_nodes_in_group("beute"):
		b.free()
	ok = pruef.call("Reparaturdrohne", is_equal_approx(schiff.huelle, 70.0), "Hülle 50 → %.0f beim Laden der Tiefe (+20)" % schiff.huelle) and ok
	# Raffinerie
	var e0 := level_erz
	schiff.aufnehmen("erz", 10)
	ok = pruef.call("Raffinerie", level_erz - e0 == 15, "10 Erz aufgenommen → +%d (+50 %%)" % (level_erz - e0)) and ok
	ok = pruef.call("Bergungskralle", is_equal_approx(beute_chance(), 0.4), "Beutechance %.0f %% statt 20 %%" % (beute_chance() * 100)) and ok
	ok = pruef.call("Vertragsbonus", abschluss_bonus(3) == int(round(39 * 1.6)), "Tiefe 3: %d statt 39 (+60 %%)" % abschluss_bonus(3)) and ok
	# Erzmagnet (Stufe 2 = 9 m): Erz in 8 m kommt, Erz in 12 m bleibt
	schiff.velocity = Vector3.ZERO
	var x := schiff.global_basis.x
	var nah := Beute.neu("erz", schiff.global_position + x * 8.0)
	var fern := Beute.neu("erz", schiff.global_position - x * 12.0)
	level.add_child(nah)
	level.add_child(fern)
	await _warte(1.5)
	ok = pruef.call("Erzmagnet", not is_instance_valid(nah) and is_instance_valid(fern),
		"Magnet %.0f m: Erz in 8 m eingesammelt %s, in 12 m liegen %s" % [schiff.magnet, not is_instance_valid(nah), is_instance_valid(fern)]) and ok
	if is_instance_valid(fern):
		fern.free()
	# Nachbrenner: Tempo im Flug mit und ohne
	Input.action_press("vor")
	await _warte(1.2)
	var v1 := schiff.velocity.length()
	var gezuendet := schiff.nachbrenner_zuenden()
	await _warte(0.9)
	var v2 := schiff.velocity.length()
	var zweiter := schiff.nachbrenner_zuenden()
	Input.action_release("vor")
	ok = pruef.call("Nachbrenner", gezuendet and not zweiter and v2 > v1 * 1.6 and is_equal_approx(schiff.nachbrenner_cd, 6.0),
		"Tempo %.1f → %.1f m/s, sofort erneut zündbar %s, Abklingzeit %.1f s (soll 6)" % [v1, v2, zweiter, schiff.nachbrenner_cd]) and ok
	_foto("aufwertung_nachbrenner")
	await _warte(1.0)
	schiff.velocity = Vector3.ZERO
	# Gegnerradar (Stufe 1 = 25 m): Gegner in 20 m angezeigt, in 40 m nicht
	var vor := (-schiff.global_basis.z * 20.0 + schiff.global_basis.x * 7.0).normalized()   # seitlich, nicht unterm Fadenkreuz
	var g_nah := _testgegner("waechter", schiff.global_position + vor * 20.0, false)
	await _warte(0.3)
	var n_nah := hud.radar_punkte.size()
	g_nah.global_position = schiff.global_position + vor * 40.0
	await _warte(0.3)
	var n_fern := hud.radar_punkte.size()
	g_nah.global_position = schiff.global_position + vor * 20.0
	await _warte(0.3)
	_foto("aufwertung_radar")
	g_nah.free()
	ok = pruef.call("Gegnerradar", n_nah == 1 and n_fern == 0, "Gegner in 20 m: %d Punkt(e), in 40 m: %d" % [n_nah, n_fern]) and ok
	# Kühlstäbe: Fluchtzeit nach dem Reaktor
	_reaktor_weg()
	ok = pruef.call("Kühlstäbe", is_equal_approx(countdown, gen.fluchtzeit() * 1.5), "Fluchtzeit %.1f s statt %.1f s (+50 %%)" % [countdown, gen.fluchtzeit()]) and ok
	# Hangar: Reiter per RB durchschalten
	_zeige_hangar()
	await _warte(0.6)
	_foto("aufwertung_hangar_schiff")
	var gesehen := []
	for i in 5:
		await _knopf_druck(JOY_BUTTON_RIGHT_SHOULDER)
		await _warte(0.3)
		gesehen.append(hangar._reiter)
		_foto("aufwertung_hangar_%s" % hangar._reiter)
	ok = pruef.call("Reiter", gesehen == ["kampf", "ueberleben", "wirtschaft", "werkzeuge", "forschung"], "RB schaltet %s" % [gesehen]) and ok
	Meta.rekord = 4
	hangar.reiter_waehlen("wirtschaft")
	await _warte(0.4)
	var k := hangar.find_child("Knopf_erzausbeute", true, false) as Button
	_foto("aufwertung_hangar_gesperrt")
	ok = pruef.call("Gesperrt im Hangar", k != null and k.text.begins_with("gesperrt"), "Raffinerie bei Rekord 4: \"%s\"" % (k.text if k else "?")) and ok
	for e in erg:
		Protokoll.schreib("test", "Aufwertung: " + e)
	Protokoll.schreib("test", "AUFWERTUNGS-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))
	Meta.zuruecksetzen()     # Teststände nicht in den nächsten Test mitnehmen (gemeinsamer Autotest-Spielstand)


## Ton: den Spielton am Hauptkanal aufnehmen und jeden Klang einzeln auslösen; die Zeitmarken stehen im
## Log, die Pegel misst tools/ton_pruefen.py in der WAV-Datei pruefung/spielton.wav.
func _ton_test() -> void:
	var klang := get_node("/root/Klang")
	var t_warte := Time.get_ticks_msec()
	while not klang.musik_bereit and Time.get_ticks_msec() - t_warte < 20000:
		await get_tree().process_frame
	Protokoll.schreib("test", "Ton: Musik bereit nach %d ms Wartezeit" % (Time.get_ticks_msec() - t_warte))
	Meta.zuruecksetzen()
	Meta.start_tiefe = 1
	_starte_lauf()
	await _warte(1.0)
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	var musik_bus := AudioServer.get_bus_index("Musik")
	AudioServer.set_bus_mute(musik_bus, true)     # Einzeltöne ohne Musik darunter, Musik am Ende allein
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	rec.set_recording_active(true)
	var t0 := Time.get_ticks_msec()
	var marken := []
	var marke := func(name: String):
		marken.append("%s=%.2f" % [name, (Time.get_ticks_msec() - t0) / 1000.0])
	await _warte(0.8)
	marke.call("stille")
	await _warte(0.8)
	marke.call("laser")
	schiff.laser_schuss()
	await _warte(1.0)
	marke.call("rakete")
	schiff.raketen_schuss()
	await _warte(1.2)
	schiff.unverwundbar = false
	schiff.schild = 50.0
	marke.call("treffer_schild")
	schiff.treffer(5.0)
	await _warte(1.0)
	schiff.schild = 0.0
	marke.call("treffer_huelle")
	schiff.treffer(5.0)
	schiff.unverwundbar = true
	await _warte(1.0)
	marke.call("explosion")
	Effekte.explosion(level, schiff.global_position - schiff.global_basis.z * 8.0, Color.ORANGE, 3.5)
	await _warte(1.5)
	marke.call("sirene")
	_reaktor_weg()
	await _warte(1.9)
	marke.call("countdown")
	await _warte(1.6)
	countdown = -1.0
	await _warte(1.0)
	AudioServer.set_bus_mute(musik_bus, false)
	marke.call("musik")
	await _warte(3.0)
	marke.call("ende")
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	var pfad := ProjectSettings.globalize_path("res://pruefung/spielton.wav")
	var fehler := wav.save_to_wav(pfad) if wav else ERR_CANT_CREATE
	Protokoll.schreib("test", "Ton: Aufnahme %s (%s), Marken %s, Zähler %s" % [pfad, error_string(fehler), " ".join(marken), klang.zaehler])
	_zeige_hangar()
	_optionen_auf()
	await _warte(0.6)
	_foto("optionen_musik")


## Station: Kristalle finden, Gebäude bauen, jede Gebäudewirkung, Modul-Aufwertung, Hangar.
func _station_test() -> void:
	var erg: Array[String] = []
	var ok := true
	var pruef := func(name: String, gut: bool, text: String):
		erg.append("%s %s: %s" % ["ok  " if gut else "FEHL", name, text])
		return gut
	Meta.zuruecksetzen()
	# Kristalle in den Minen: Kristallader (Tiefe 10) gegen Mondmine (Tiefe 1), je 4 Level
	Meta.start_tiefe = 1
	_starte_lauf()
	await _warte(0.5)
	var zaehle := func(t: int) -> int:
		var n := 0
		for i in 4:
			tiefe = t
			_lade_level()
			n += get_tree().get_nodes_in_group("beute_kristall").size()
			await get_tree().process_frame
		return n
	var in_mond: int = await zaehle.call(1)
	var in_ader: int = await zaehle.call(10)
	ok = pruef.call("Kristallfunde", in_mond > 0 and in_ader > in_mond * 2, "4 Level Mondmine %d, 4 Level Kristallader %d" % [in_mond, in_ader]) and ok
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	schiff.unverwundbar = true
	schiff.aufnehmen("kristall", 3)
	ok = pruef.call("Kristall aufnehmen", Meta.kristalle == 3, "3 aufgenommen → Kristalle %d (sofort gespeichert)" % Meta.kristalle) and ok
	# Bauen
	Meta.bank = 100000
	Meta.kristalle = 1000
	Meta.bauteile = 1000
	ok = pruef.call("Erst Stufe 0", Meta.forschungspunkte_gesamt() == Meta.rekord and Meta.inventar_max() == 24 and Meta.raffinerie_ertrag() == 0, "ohne Gebäude: Punkte = Rekord, Inventar 24, Raffinerie 0") and ok
	var soll_erz := 0
	for gb in Meta.GEBAEUDE:
		for k in gb.kosten:
			soll_erz += int(k[0])
		for i in 3:
			Meta.ausbauen(gb.id)
	var voll := true
	for gb in Meta.GEBAEUDE:
		voll = voll and Meta.gebaeude_stufe(gb.id) == 3 and not Meta.ausbaubar(gb.id)
	ok = pruef.call("Ausbauen", voll and Meta.bank == 100000 - soll_erz, "alle 4 auf Stufe 3, Erz −%d (Tabelle %d)" % [100000 - Meta.bank, soll_erz]) and ok
	Meta.laden()
	ok = pruef.call("Gespeichert", Meta.gebaeude_stufe("labor") == 3, "nach Neuladen Labor Stufe %d" % Meta.gebaeude_stufe("labor")) and ok
	ok = pruef.call("Labor", Meta.forschungspunkte_gesamt() == Meta.rekord + 6, "Forschungspunkte %d = Rekord %d + 6" % [Meta.forschungspunkte_gesamt(), Meta.rekord]) and ok
	var rng := RandomNumberGenerator.new()
	for i in 40:
		Meta.modul_hinzu(Module.erzeugen(rng, 3))
	ok = pruef.call("Lager", Meta.inventar_max() == 48 and Meta.module.size() == 40, "Inventar %d/%d nach 40 Funden" % [Meta.module.size(), Meta.inventar_max()]) and ok
	# Werkstatt: dreimal aufwerten, das vierte Mal nicht
	var m: Dictionary = Meta.module[0]
	var w0: float = m.eig[0].wert
	var kr0 := Meta.kristalle
	var drei := Meta.modul_aufwerten(m) and Meta.modul_aufwerten(m) and Meta.modul_aufwerten(m)
	var vierte := Meta.modul_aufwerten(m)
	ok = pruef.call("Werkstatt", drei and not vierte and is_equal_approx(m.eig[0].wert, w0 * pow(1.15, 3)) and Module.name_von(m).ends_with("+3"),
		"%s: Wert %.3f → %.3f (×1,15³), 4. Aufwertung abgelehnt, Kristalle −%d" % [Module.name_von(m), w0, m.eig[0].wert, kr0 - Meta.kristalle]) and ok
	# Raffinerie beim Laufende
	var bank0 := Meta.bank
	level_erz = 40
	zustand = "flug"
	_schiff_tot("Test")
	ok = pruef.call("Raffinerie", Meta.bank - bank0 == 20 + 120, "Laufende: Bank +%d (20 gerettet + 120 Raffinerie)" % (Meta.bank - bank0)) and ok
	await _warte(5.0)
	# Hangar: Station und Aufwerten per Controller
	Meta.gebaeude = {"raffinerie": 1, "werkstatt": 1}
	Meta.bank = 800
	Meta.kristalle = 60
	Meta.bauteile = 40
	Meta.module = Meta.module.slice(0, 8)
	for x in Meta.module:
		x.erase("auf")
	Meta.speichern()
	_zeige_hangar()
	hangar.reiter_waehlen("station")
	await _warte(0.6)
	var b := hangar.find_child("Bau_labor", true, false) as Button
	b.grab_focus()
	await _warte(0.2)
	await _knopf_druck(JOY_BUTTON_A)
	await _warte(0.3)
	ok = pruef.call("Hangar bauen", Meta.gebaeude_stufe("labor") == 1, "A auf Labor → Stufe %d" % Meta.gebaeude_stufe("labor")) and ok
	_foto("station_hangar")
	hangar.reiter_waehlen("module")
	await _warte(0.5)
	var kachel := hangar.find_child("Inventar", true, false).get_child(0) as Button
	var idx: int = kachel.get_meta("modul_index")
	kachel.grab_focus()
	await _warte(0.2)
	await _knopf_druck(JOY_BUTTON_X)
	await _warte(0.3)
	ok = pruef.call("Hangar aufwerten", int(Meta.module[idx].get("auf", 0)) == 1, "X auf %s" % Module.name_von(Meta.module[idx])) and ok
	_foto("station_module")
	for e in erg:
		Protokoll.schreib("test", "Station: " + e)
	Protokoll.schreib("test", "STATION-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))
	Meta.zuruecksetzen()


## Pakt: Sperre, Umschalten, jede Erschwernis im Spiel, Erzbonus, Meilensteine, Rekord, Hangar.
func _pakt_test() -> void:
	var erg: Array[String] = []
	var ok := true
	var pruef := func(name: String, gut: bool, text: String):
		erg.append("%s %s: %s" % ["ok  " if gut else "FEHL", name, text])
		return gut
	Meta.zuruecksetzen()
	Meta.rekord = 4
	ok = pruef.call("Sperre", not Meta.pakt_umschalten("zaeh") and Meta.pakt_punkte() == 0, "vor Boss 5 nicht schaltbar") and ok
	Meta.rekord = 12
	var stufen := []
	for i in 4:
		Meta.pakt_umschalten("zaeh")
		stufen.append(Meta.pakt_stufe("zaeh"))
	ok = pruef.call("Umschalten", stufen == [1, 2, 3, 0], "Zähe Gegner schaltet %s" % [stufen]) and ok
	for e in Meta.PAKT:
		Meta.pakt[e.id] = int(e.max)
	Meta.speichern()
	Meta.pakt = {}
	Meta.laden()
	ok = pruef.call("Alles an", Meta.pakt_punkte() == 17, "alle Erschwernisse voll: %d Punkte, nach Neuladen" % Meta.pakt_punkte()) and ok
	ok = pruef.call("Erzbonus", pakt_erz_bonus(100) == 170, "100 Erz → +%d" % pakt_erz_bonus(100)) and ok
	Meta.start_tiefe = 1
	_starte_lauf()
	await _warte(1.0)
	schiff.tarn_t = 0.0
	# Gegnerwerte
	var g := _gegner("jaeger", schiff.global_position + Vector3(0, 0, -30))
	var ref := Gegner.new()
	ref.einrichten("jaeger", tiefe)
	ok = pruef.call("Zähe Gegner", is_equal_approx(g.hp_max, ref.hp_max * 1.75), "Jäger %.0f statt %.0f Leben" % [g.hp_max, ref.hp_max]) and ok
	ok = pruef.call("Scharfschützen", is_equal_approx(g.schuss_tempo, ref.schuss_tempo * 1.4), "Schusstempo %.1f statt %.1f" % [g.schuss_tempo, ref.schuss_tempo]) and ok
	ref.free()
	g.free()
	# Schiff
	schiff.unverwundbar = false
	var s0 := schiff.schild
	schiff.treffer(10.0)
	schiff.unverwundbar = true
	ok = pruef.call("Glaskanone", is_equal_approx(s0 - schiff.schild, 20.0), "Treffer 10 → Schild −%.0f" % (s0 - schiff.schild)) and ok
	schiff.schild = 0.0
	schiff._seit_treffer = 99.0
	schiff.velocity = Vector3.ZERO
	schiff.schild_laden(2.0)
	ok = pruef.call("Kein Schildladen", schiff.schild == 0.0, "nach 2 s Stillstand Schild %.1f" % schiff.schild) and ok
	var lampe: OmniLight3D = null
	for l in get_tree().get_nodes_in_group("minenlicht"):
		if l is OmniLight3D and l.omni_range > 10.0:
			lampe = l
	var licht_k := float(thema.get("licht", 1.0))
	ok = pruef.call("Dunkelheit", lampe != null and is_equal_approx(lampe.light_energy, 1.7 * licht_k * 0.5) and is_equal_approx(umgebung.environment.ambient_light_energy, float(thema.get("umgebung_kraft", 0.35)) * 0.5),
		"Raumlampe %.2f (sonst %.2f), Umgebung %.3f" % [lampe.light_energy if lampe else -1.0, 1.7 * licht_k, umgebung.environment.ambient_light_energy]) and ok
	# Horde: gleiche Würfel, einmal mit, einmal ohne
	var zaehle := func(horde: int) -> int:
		Meta.pakt["horde"] = horde
		var n := 0
		for saat in 30:      # 30 Saaten: mit mehr Gegnern laufen die Würfelfolgen auseinander, das streut
			_rng.seed = 4242 + saat
			n += _gegner_setzen()
			for x in get_tree().get_nodes_in_group("gegner"):
				x.free()
		return n
	var ohne: int = zaehle.call(0)
	var mit: int = zaehle.call(2)
	Meta.pakt["horde"] = 2
	var summe := 0
	for i in 10000:
		summe += horde_anzahl(3)
	ok = pruef.call("Horde-Rechnung", absf(summe / 30000.0 - 1.6) < 0.02, "3 Gegner → im Mittel %.3f (soll 4,8)" % (summe / 10000.0)) and ok
	ok = pruef.call("Horde", mit > ohne * 1.45 and mit < ohne * 1.75, "%d statt %d Gegner (×%.2f, soll ~1,6)" % [mit, ohne, float(mit) / ohne]) and ok
	_reaktor_weg()
	ok = pruef.call("Kurze Lunte", is_equal_approx(countdown, gen.fluchtzeit() * 0.6), "Fluchtzeit %.1f statt %.1f s" % [countdown, gen.fluchtzeit()]) and ok
	# Bosse, Meilensteine, Rekord
	tiefe = 5
	_lade_level()
	await _warte(1.0)
	var bs := boss
	var bref := Gegner.new()
	bref.einrichten(bs.typ, tiefe)
	ok = pruef.call("Wütende Bosse", is_equal_approx(bs.hp_max, bref.hp_max * 1.75 * 1.5) and is_equal_approx(bs.phase2_anteil, 0.7),
		"%s %.0f statt %.0f Leben, Phase 2 ab %.0f %%" % [bs.typ, bs.hp_max, bref.hp_max, bs.phase2_anteil * 100]) and ok
	bref.free()
	for x in get_tree().get_nodes_in_group("beute"):
		x.free()
	_gegner_weg(bs)
	await _warte(0.3)
	var seltene := []
	for x in get_tree().get_nodes_in_group("beute"):
		if x.art == "modul":
			seltene.append(int(x.modul.selten))
	seltene.sort()
	ok = pruef.call("Meilensteine", seltene.size() == 3 and seltene.has(3) and seltene.has(4) and Meta.pakt_meilen == [5, 10],
		"Boss mit Pakt 17: Module der Seltenheit %s, Meilensteine %s" % [seltene, Meta.pakt_meilen]) and ok
	for x in get_tree().get_nodes_in_group("beute"):
		x.free()
	_gegner_weg(bs)
	await _warte(0.3)
	var zweite := get_tree().get_nodes_in_group("beute").filter(func(x): return x.art == "modul").size()
	ok = pruef.call("Meilenstein einmalig", zweite == 1, "zweiter Bosssieg: %d Modul (nur das normale)" % zweite) and ok
	ok = pruef.call("Paktrekord", int(Meta.pakt_rekord.punkte) == 17 and int(Meta.pakt_rekord.tiefe) == 5, "Rekord Pakt %d bis Tiefe %d" % [Meta.pakt_rekord.punkte, Meta.pakt_rekord.tiefe]) and ok
	# Hangar
	Meta.pakt = {"zaeh": 2, "glas": 1, "lunte": 1}
	Meta.speichern()
	_zeige_hangar()
	hangar.reiter_waehlen("pakt")
	await _warte(0.6)
	var k := hangar.find_child("Pakt_dunkel", true, false) as Button
	k.grab_focus()
	await _warte(0.2)
	await _knopf_druck(JOY_BUTTON_A)
	await _warte(0.3)
	ok = pruef.call("Hangar", Meta.pakt_stufe("dunkel") == 1 and Meta.pakt_punkte() == 7, "A schaltet Dunkelheit an, Pakt jetzt %d" % Meta.pakt_punkte()) and ok
	_foto("pakt_hangar")
	for e in erg:
		Protokoll.schreib("test", "Pakt: " + e)
	Protokoll.schreib("test", "PAKT-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))
	Meta.zuruecksetzen()


## Module: Verteilung, Einbauen/Tauschen/Zerlegen, volles Inventar, Wirkung, Boss-Drop, Aufsammeln, Hangar.
func _module_test() -> void:
	var erg: Array[String] = []
	var ok := true
	var pruef := func(name: String, gut: bool, text: String):
		erg.append("%s %s: %s" % ["ok  " if gut else "FEHL", name, text])
		return gut
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var zahl := [0, 0, 0, 0, 0]
	var form_ok := true
	for i in 3000:
		var m := Module.erzeugen(rng, 10)
		zahl[m.selten] += 1
		form_ok = form_ok and m.eig.size() == mini(int(Module.SELTEN[m.selten].eig), 4) and (m.spezial != "") == (m.selten == 4)
		for e in m.eig:
			form_ok = form_ok and m.platz in Module.EIG[e.id].plaetze
	ok = pruef.call("Verteilung", zahl[0] > zahl[1] and zahl[1] > zahl[2] and zahl[2] > zahl[3] and zahl[3] > zahl[4] and zahl[4] > 0,
		"3000 Funde: gewöhnlich %d, ungewöhnlich %d, selten %d, episch %d, legendär %d" % zahl) and ok
	ok = pruef.call("Aufbau", form_ok, "Eigenschaften passen zu Platz und Seltenheit, Spezial nur bei legendär") and ok
	var boss_min := 4
	for i in 300:
		boss_min = mini(boss_min, Module.erzeugen(rng, 10, true).selten)
	ok = pruef.call("Bossbeute", boss_min >= 2, "300 Bossfunde, schlechteste Seltenheit %s" % Module.SELTEN[boss_min].name) and ok
	# Einbauen, Tauschen, Zerlegen
	Meta.zuruecksetzen()
	var L := {"platz": "laser", "selten": 4, "stufe": 10, "eig": [{"id": "laser_mult", "wert": 0.2}, {"id": "feuerrate", "wert": 0.1}, {"id": "krit", "wert": 0.05}], "spezial": "durchschlag"}
	var S := {"platz": "schild", "selten": 3, "stufe": 10, "eig": [{"id": "schild_max", "wert": 20.0}, {"id": "schild_laden", "wert": 0.3}, {"id": "huelle_max", "wert": 15.0}], "spezial": ""}
	var T := {"platz": "triebwerk", "selten": 4, "stufe": 10, "eig": [{"id": "tempo", "wert": 0.1}], "spezial": "sprint"}
	var R := {"platz": "rumpf", "selten": 4, "stufe": 10, "eig": [{"id": "raketen", "wert": 2.0}, {"id": "erz_mult", "wert": 0.2}], "spezial": "magnet"}
	for m in [L, S, T, R]:
		Meta.modul_hinzu(m)
	for i in 4:
		Meta.modul_einbauen(0)
	ok = pruef.call("Einbauen", Meta.eingebaut.size() == 4 and Meta.module.is_empty(), "4 Plätze belegt, Inventar %d" % Meta.module.size()) and ok
	var L2 := {"platz": "laser", "selten": 0, "stufe": 1, "eig": [{"id": "krit", "wert": 0.02}], "spezial": ""}
	Meta.modul_hinzu(L2)
	Meta.modul_einbauen(0)
	var getauscht: bool = Meta.eingebaut.laser.selten == 0 and Meta.module.size() == 1 and Meta.module[0].selten == 4
	Meta.modul_einbauen(0)
	ok = pruef.call("Tauschen", getauscht and Meta.eingebaut.laser.selten == 4 and Meta.module[0].selten == 0, "Laserlinsen getauscht und zurück") and ok
	var bt := Meta.bauteile
	Meta.modul_zerlegen(0)
	ok = pruef.call("Zerlegen", Meta.bauteile - bt == 1 and Meta.module.is_empty(), "gewöhnliche Linse T1 → +%d Bauteile" % (Meta.bauteile - bt)) and ok
	for i in Module.INVENTAR_MAX + 1:
		Meta.modul_hinzu(Module.erzeugen(rng, 3))
	ok = pruef.call("Inventar voll", Meta.module.size() == Module.INVENTAR_MAX, "%d Funde → Inventar %d, Bauteile %d" % [Module.INVENTAR_MAX + 1, Meta.module.size(), Meta.bauteile]) and ok
	Meta.module = []
	Meta.laden()
	ok = pruef.call("Gespeichert", Meta.eingebaut.size() == 4 and Meta.module.size() == Module.INVENTAR_MAX, "nach Neuladen %d eingebaut, %d im Inventar" % [Meta.eingebaut.size(), Meta.module.size()]) and ok
	# Wirkung
	var w := Meta.schiffswerte()
	var soll := {"schild_max": 70.0, "huelle_max": 115.0, "tempo": 14.0 * 1.1 * 1.12, "raketen_max": 6, "laser_mult": 1.2, "feuerrate": 1.1,
		"krit": 0.05, "schild_laden": 1.3, "erz_mult": 1.2, "magnet": 4.0, "durchschlag_extra": 1}
	var falsch := []
	for k in soll:
		if not is_equal_approx(float(w[k]), float(soll[k])):
			falsch.append("%s %s≠%s" % [k, w[k], soll[k]])
	ok = pruef.call("Schiffswerte", falsch.is_empty(), "alle 11 Werte stimmen" if falsch.is_empty() else str(falsch)) and ok
	Meta.start_tiefe = 1
	_starte_lauf()
	await _warte(1.0)
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	for b in get_tree().get_nodes_in_group("beute"):
		b.free()
	schiff.unverwundbar = true
	schiff.krit = 0.0
	schiff.laser_wahl = "zwilling"
	schiff.laser_schuss()
	var bolzen: Geschoss = null
	for k in level.get_children():
		if k is Geschoss and k.vom_spieler:
			bolzen = k
	ok = pruef.call("Im Schiff", bolzen != null and bolzen.durchschlag == 1 and is_equal_approx(bolzen.schaden, 12.0 * 1.2) and is_equal_approx(schiff.magnet, 4.0),
		"Bolzen %.1f Schaden, Durchschlag %d, Magnet %.0f m, Schild %.0f, Tempo %.2f" % [bolzen.schaden if bolzen else 0.0, bolzen.durchschlag if bolzen else -1, schiff.magnet, schiff.schild_max, schiff.tempo]) and ok
	# Funde im Bergwerk: eine Reihe aller Seltenheiten für das Bild
	var vor := -schiff.global_basis.z
	for i in 5:
		var mb := Beute.neu("modul", schiff.global_position + vor * (8.0 + 4.0 * (i % 2)) + schiff.global_basis.x * (i - 2) * 3.2 + Vector3(0, (i % 2) * 1.5 - 0.8, 0))
		mb.modul = Module.erzeugen(rng, 5, false, Module.PLATZ_REIHE[i % 4])
		mb.modul.selten = i
		level.add_child(mb)
	await _warte(0.8)
	_foto("module_funde")
	for b in get_tree().get_nodes_in_group("beute"):
		b.free()
	schiff.magnet = 0.0
	# Boss-Drop und Aufsammeln
	tiefe = 5
	_lade_level()
	await _warte(1.0)
	var bs := boss
	for g in get_tree().get_nodes_in_group("gegner"):
		if g != bs:
			g.free()
	for b in get_tree().get_nodes_in_group("beute"):
		b.free()
	var inv0 := Meta.module.size()
	Meta.module = Meta.module.slice(0, 10)
	inv0 = Meta.module.size()
	_gegner_weg(bs)
	await _warte(0.3)
	var drop: Beute = null
	for b in get_tree().get_nodes_in_group("beute"):
		if b.art == "modul":
			drop = b
	ok = pruef.call("Boss-Drop", drop != null and int(drop.modul.selten) >= 2, "Boss lässt fallen: %s" % (Module.name_von(drop.modul) if drop else "nichts")) and ok
	if drop:
		schiff.global_position = drop.global_position + Vector3(0, 0, 1.0)
		await _warte(0.5)
	ok = pruef.call("Aufsammeln", Meta.module.size() == inv0 + 1, "Inventar %d → %d" % [inv0, Meta.module.size()]) and ok
	# Hangar: Reiter Module, Controller A baut ein, Y zerlegt
	_zeige_hangar()
	hangar.reiter_waehlen("module")
	await _warte(0.6)
	_foto("module_hangar")
	var kacheln := []
	for k in hangar.find_child("Inventar", true, false).get_children():
		kacheln.append(k)
	var k0: Button = kacheln[0]
	var idx0: int = k0.get_meta("modul_index")
	var platz0: String = Meta.module[idx0].platz
	var neu_m: Dictionary = Meta.module[idx0]
	k0.grab_focus()
	await _warte(0.2)
	await _knopf_druck(JOY_BUTTON_A)
	await _warte(0.3)
	ok = pruef.call("Hangar A", Meta.eingebaut[platz0] == neu_m, "A auf %s → eingebaut" % Module.name_von(neu_m)) and ok
	var k1 := hangar.find_child("Inventar", true, false).get_child(0) as Button
	k1.grab_focus()
	var bt0 := Meta.bauteile
	var n0 := Meta.module.size()
	await _warte(0.2)
	await _knopf_druck(JOY_BUTTON_Y)
	await _warte(0.3)
	ok = pruef.call("Hangar Y", Meta.module.size() == n0 - 1 and Meta.bauteile > bt0, "Y zerlegt: Inventar %d → %d, Bauteile %d → %d" % [n0, Meta.module.size(), bt0, Meta.bauteile]) and ok
	_foto("module_hangar_danach")
	for e in erg:
		Protokoll.schreib("test", "Module: " + e)
	Protokoll.schreib("test", "MODULE-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))
	Meta.zuruecksetzen()


## Forschungsbaum: Punkte, Reihenfolge, Querverbindungen, jede Wirkung im Spiel, Hangar-Bild.
func _forschung_test() -> void:
	var erg: Array[String] = []
	var ok := true
	var pruef := func(name: String, gut: bool, text: String):
		erg.append("%s %s: %s" % ["ok  " if gut else "FEHL", name, text])
		return gut
	Meta.zuruecksetzen()
	Meta.rekord = 40
	ok = pruef.call("Punkte", Meta.forschungspunkte_frei() == 40, "Rekord 40 → %d Punkte frei" % Meta.forschungspunkte_frei()) and ok
	ok = pruef.call("Reihenfolge", not Meta.erforschen("f_durchschlag") and Meta.erforschen("f_fokus") and Meta.erforschen("f_durchschlag"),
		"Durchschlag erst nach Fokuslinse") and ok
	Meta.erforschen("f_abprall")
	ok = pruef.call("Querverbindung", not Meta.erforschen("f_kette"), "Kettenblitz ohne Trägheitsdämpfer gesperrt") and ok
	for runde in 3:      # Querverbindungen zeigen auf Knoten weiter unten in der Liste
		for k in Meta.FORSCHUNG:
			Meta.erforschen(k.id)
	ok = pruef.call("Alles", Meta.forschung.size() == 16 and Meta.forschungspunkte_frei() == 7, "%d Knoten erforscht, %d Punkte übrig (40 − 33)" % [Meta.forschung.size(), Meta.forschungspunkte_frei()]) and ok
	Meta.laden()
	ok = pruef.call("Gespeichert", Meta.forschung.size() == 16, "nach Neuladen %d Knoten" % Meta.forschung.size()) and ok
	Meta.start_tiefe = 1
	_starte_lauf()
	await _warte(1.0)
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	for b in get_tree().get_nodes_in_group("beute"):
		b.free()
	schiff.unverwundbar = true
	schiff.tarn_t = 0.0
	var neue := func() -> Array:
		var aus := []
		for k in level.get_children():
			if k is Geschoss and k.vom_spieler and not k.has_meta("alt"):
				k.set_meta("alt", true)
				aus.append(k)
		return aus
	neue.call()
	var w := Waffen.finde("zwilling")
	schiff.laser_wahl = "zwilling"
	schiff.krit = 0.0
	schiff.laser_schuss()
	var gs: Array = neue.call()
	ok = pruef.call("Fokuslinse", gs.size() == 1 and is_equal_approx(gs[0].schaden, w.schaden * 1.08), "Zwilling %.2f statt %.1f" % [gs[0].schaden, w.schaden]) and ok
	ok = pruef.call("Laser-Eigenschaften", gs[0].durchschlag == 1 and gs[0].abprall == 1 and gs[0].kette, "durchschlag %d, abprall %d, kette %s" % [gs[0].durchschlag, gs[0].abprall, gs[0].kette]) and ok
	gs[0].free()
	ok = pruef.call("Spulen", is_equal_approx(schiff.schild_max, 65.0), "Schild %.0f (50 + 15)" % schiff.schild_max) and ok
	ok = pruef.call("Dämpfer", is_equal_approx(schiff.tempo, 14.0 * 1.06), "Tempo %.2f m/s" % schiff.tempo) and ok
	# Feldregeneration: im Flug 1,5 × 1,5
	schiff.schild = 0.0
	schiff.velocity = Vector3(5, 0, 0)
	schiff._seit_treffer = 99.0
	schiff.schild_laden(1.0)
	ok = pruef.call("Feldregeneration", is_equal_approx(schiff.schild, 2.25), "im Flug %.2f je s statt 1,5" % schiff.schild) and ok
	schiff.huelle = 30.0
	schiff.schild_laden(1.0)
	ok = pruef.call("Nanoreparatur", is_equal_approx(schiff.huelle, 30.5), "Hülle 30 → %.1f in 1 s" % schiff.huelle) and ok
	schiff.velocity = Vector3.ZERO
	var e0 := level_erz
	schiff.aufnehmen("erz", 10)
	ok = pruef.call("Erzsonde", level_erz - e0 == 11, "10 Erz → +%d" % (level_erz - e0)) and ok
	level_erz = 40
	ok = pruef.call("Notreserve", gerettetes_erz() == 40, "beim Tod gerettet %d von 40" % gerettetes_erz()) and ok
	ok = pruef.call("Schatzsucher", boss_erz_faktor() == 2, "Boss-Erz ×%d" % boss_erz_faktor()) and ok
	# Raketensparer: 400 Schüsse
	schiff.raketen = 100000
	var r0 := schiff.raketen
	for i in 400:
		schiff.raketen_schuss()
		for g in neue.call():
			g.free()
	var gespart := 400 - (r0 - schiff.raketen)
	ok = pruef.call("Raketensparer", gespart > 60 and gespart < 140, "%d von 400 Raketen kostenlos (soll ~100)" % gespart) and ok
	schiff.raketen = 0
	# Überladung
	schiff.ueberladung_ausloesen()
	schiff.laser_schuss()
	for g in neue.call():
		g.free()
	ok = pruef.call("Überladung", is_equal_approx(schiff._laser_cd, w.cd / 1.25), "Abklingzeit %.3f statt %.3f" % [schiff._laser_cd, w.cd]) and ok
	await _warte(3.2)
	# Volle Magazine und Tarnstart: neue Tiefe laden
	_lade_level()
	await _warte(0.5)
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	for b in get_tree().get_nodes_in_group("beute"):
		b.free()
	ok = pruef.call("Volle Magazine", schiff.raketen == schiff.raketen_max, "Raketen %d/%d nach neuer Tiefe" % [schiff.raketen, schiff.raketen_max]) and ok
	var vor := -schiff.global_basis.z
	var weit := schiff.global_position + vor * 12.0
	var tg := _testgegner("waechter", weit, true)
	tg.hp = 100000.0
	await _warte(1.0)
	var sieht_getarnt: bool = tg._sicht
	var frei_sicht: bool = tg._frei(schiff.global_position)
	schiff.tarn_t = 0.0
	await _warte(0.6)
	ok = pruef.call("Tarnstart", frei_sicht and not sieht_getarnt and tg._sicht, "freie Sichtlinie %s; getarnt gesehen %s, danach gesehen %s" % [frei_sicht, sieht_getarnt, tg._sicht]) and ok
	tg.set_physics_process(false)
	tg.global_position = schiff.global_position + vor * 5.0
	# Schockwelle: Treffer auf die Hülle
	var hp0 := tg.hp
	schiff.unverwundbar = false
	schiff.schild = 0.0
	schiff.treffer(5.0)
	schiff.unverwundbar = true
	ok = pruef.call("Schockwelle", is_equal_approx(hp0 - tg.hp, 25.0), "Gegner in 5 m: −%.0f" % (hp0 - tg.hp)) and ok
	# Durchschlag + Kettenblitz: zwei Gegner hintereinander, ein dritter daneben
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	schiff.pad_aktiv = false
	var a := _testgegner("waechter", schiff.global_position + vor * 7.0, false)
	var b2 := _testgegner("waechter", schiff.global_position + vor * 11.0, false)
	var c := _testgegner("waechter", schiff.global_position + vor * 7.0 + schiff.global_basis.x * 5.0, false)
	for g in [a, b2, c]:
		g.hp = 100000.0
	Geschoss.ketten_zaehler = Geschoss.KETTE_JEDER - 1
	var ha := a.hp
	var hb := b2.hp
	var hc := c.hp
	schiff.global_basis = Basis.looking_at(vor, Vector3.UP)
	var start := schiff.global_position + vor * 1.5
	var g1 := Geschoss.neu(start, vor, 90.0, 10.0, true, Color.RED)
	g1.durchschlag = 1
	g1.kette = true
	level.add_child(g1)
	await _warte(0.5)
	ok = pruef.call("Durchschlag", ha - a.hp > 0.0 and hb - b2.hp > 0.0, "vorderer −%.0f, hinterer −%.0f" % [ha - a.hp, hb - b2.hp]) and ok
	ok = pruef.call("Kettenblitz", hc - c.hp > 0.0, "Gegner daneben −%.0f" % (hc - c.hp)) and ok
	for g in [a, b2, c]:
		g.free()
	# Abpraller: Schuss senkrecht auf die nächste Wand, danach fliegt er zurück
	var wand := Vector3.ZERO
	var beste := 999.0
	for d in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var q := PhysicsRayQueryParameters3D.create(schiff.global_position, schiff.global_position + d * 40.0, 1)
		var t := schiff.get_world_3d().direct_space_state.intersect_ray(q)
		if not t.is_empty() and t.position.distance_to(schiff.global_position) < beste:
			beste = t.position.distance_to(schiff.global_position)
			wand = d
	var g2 := Geschoss.neu(schiff.global_position + wand * 1.0, wand, 40.0, 10.0, true, Color.RED)
	g2.abprall = 1
	g2.lebenszeit = 10.0
	level.add_child(g2)
	await _warte((beste + 2.0) / 40.0 + 0.1)
	var zurueck := is_instance_valid(g2) and g2.geschw.dot(wand) < 0.0
	ok = pruef.call("Abpraller", zurueck, "Wand in %.1f m, Bolzen danach unterwegs zurück %s" % [beste, zurueck]) and ok
	if is_instance_valid(g2):
		g2.free()
	# Hangar mit teilweise erforschtem Baum
	Meta.forschung = ["f_fokus", "f_durchschlag", "s_spulen", "b_sonde", "b_reserve", "t_tarn"]
	Meta.rekord = 14
	Meta.speichern()
	_zeige_hangar()
	hangar.reiter_waehlen("forschung")
	await _warte(0.6)
	var kn := hangar.find_child("Knopf_s_feld", true, false) as Button
	if kn:
		kn.grab_focus()
	await _warte(0.2)
	_foto("forschung_baum")
	await _knopf_druck(JOY_BUTTON_A)
	ok = pruef.call("Hangar", Meta.erforscht("s_feld") and Meta.forschungspunkte_frei() == 14 - 10, "Feldregeneration per A erforscht %s, frei %d" % [Meta.erforscht("s_feld"), Meta.forschungspunkte_frei()]) and ok
	await _warte(0.3)
	_foto("forschung_baum_danach")
	for e in erg:
		Protokoll.schreib("test", "Forschung: " + e)
	Protokoll.schreib("test", "FORSCHUNG-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))
	Meta.zuruecksetzen()


## Bossjagd: Schiff im Bossraum zeigen, dann außer Sicht in einen Stollen setzen. Der Boss muss folgen.
func _boss_jagd_test() -> void:
	var ok := true
	for t in [5, 10, 15]:
		tiefe = t
		_lade_level()
		await _warte(1.0)
		for g in get_tree().get_nodes_in_group("gegner"):
			if g != boss:
				g.free()
		schiff.unverwundbar = true
		var b := boss
		b.alarmieren(schiff.global_position)
		# Versteck: Zelle auf dem Weg zum Start, mindestens 5 Zellen außerhalb des Bossraums, ohne Sichtlinie
		var weg := gen.pfad(gen.naechste_zelle(reaktor.global_position), gen.naechste_zelle(gen.mitte(gen.start_raum)))
		var draussen := 0
		var versteck := Vector3.ZERO
		for z in weg:
			if gen.zellen.get(z, -2) != gen.reaktor_raum:
				draussen += 1
				if draussen >= 5 and not b._frei(LevelGen.welt_von(z)):
					versteck = LevelGen.welt_von(z)
					break
		if versteck == Vector3.ZERO:
			Protokoll.schreib("test", "Bossjagd Tiefe %d: kein Versteck ohne Sichtlinie gefunden" % t)
			continue
		schiff.global_position = versteck
		schiff.velocity = Vector3.ZERO
		var wege := func() -> int:
			return gen.pfad(gen.naechste_zelle(b.global_position), gen.naechste_zelle(schiff.global_position)).size() - 1
		var w0: int = wege.call()
		var t0 := Time.get_ticks_msec()
		var gesehen := -1.0
		var gejagt := false
		while Time.get_ticks_msec() - t0 < 30000:
			await get_tree().physics_frame
			schiff.velocity = Vector3.ZERO
			gejagt = gejagt or b.jagt
			if b._sicht and b.global_position.distance_to(schiff.global_position) < 40.0 and Time.get_ticks_msec() - t0 > 500:
				gesehen = (Time.get_ticks_msec() - t0) / 1000.0
				break
		var w1: int = wege.call()
		var gut := gejagt and gesehen > 0.0
		if gesehen > 0.0:
			schiff.look_at(b.global_position, Vector3.UP)
			await _warte(0.3)
			_foto("boss_jagd_%d" % t)
		Protokoll.schreib("test", "Bossjagd Tiefe %d (%s): Schiff %d Zellen weg, jagt %s, nach %.1f s in Sicht, Restweg %d Zellen → %s" % [
			t, b.typ, w0, gejagt, gesehen, w1, "ok" if gut else "FEHLER"])
		ok = ok and gut
	Protokoll.schreib("test", "BOSSJAGD-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))


## Starttiefe: welche Knöpfe es gibt, Wahl per Controller, Lauf beginnt in der gewählten Tiefe.
func _starttiefe_test() -> void:
	var ok := true
	var erg: Array[String] = []
	for rek in [4, 6, 12]:
		Meta.rekord = rek
		erg.append("Rekord %d → wählbar %s" % [rek, Meta.starttiefen()])
	ok = ok and Meta.starttiefen() == [1, 6, 11]
	Meta.rekord = 4
	ok = ok and Meta.starttiefen() == [1]
	Meta.rekord = 12
	Meta.start_tiefe = 1
	Meta.speichern()
	_zeige_hangar()
	await _warte(0.6)
	var knoepfe := []
	for k in hangar.find_child("Starttiefen", true, false).get_children():
		if k is Button:
			knoepfe.append(str(k.name))
	erg.append("Hangar-Knöpfe %s" % [knoepfe])
	ok = ok and knoepfe == ["Start_1", "Start_6", "Start_11"]
	# Per Controller: vom Startknopf hoch in die Reihe, zweimal rechts, A
	await _knopf_druck(JOY_BUTTON_DPAD_UP)
	await _knopf_druck(JOY_BUTTON_DPAD_RIGHT)
	await _knopf_druck(JOY_BUTTON_DPAD_RIGHT)
	var f := get_viewport().gui_get_focus_owner()
	await _knopf_druck(JOY_BUTTON_A)
	erg.append("Controller: Fokus %s, gewählt Tiefe %d" % [f.name if f else "keiner", Meta.start_tiefe])
	ok = ok and Meta.start_tiefe == 11
	await _warte(0.3)
	_foto("hangar_starttiefe")
	# Gemerkt nach Neuladen, ungültig nach Neues Spiel
	Meta.laden()
	var gemerkt := Meta.gueltige_starttiefe()
	erg.append("nach Neuladen Starttiefe %d" % gemerkt)
	ok = ok and gemerkt == 11
	_starte_lauf()
	await _warte(1.0)
	erg.append("Lauf beginnt in Tiefe %d, Boss-Tiefe als nächstes: %s" % [tiefe, LevelGen.ist_boss_tiefe(tiefe + 4)])
	ok = ok and tiefe == 11 and zustand == "flug"
	Meta.rekord = 0
	erg.append("Rekord 0 → gültige Starttiefe %d" % Meta.gueltige_starttiefe())
	ok = ok and Meta.gueltige_starttiefe() == 1
	for e in erg:
		Protokoll.schreib("test", "Starttiefe: " + e)
	Protokoll.schreib("test", "STARTTIEFE-TEST %s" % ("BESTANDEN" if ok else "FEHLGESCHLAGEN"))


## Einsammelreichweite: Erz in 4,3 m (innerhalb der 4,6 m) wird aufgenommen, in 5,0 m nicht.
func _sammel_test() -> void:
	for g in get_tree().get_nodes_in_group("gegner"):
		g.free()
	await _warte(1.0)
	schiff.velocity = Vector3.ZERO
	schiff.magnet = 0.0      # gemessen wird die Aufnahmekugel allein, ohne Erzmagnet
	var x := schiff.global_basis.x
	var nah := Beute.neu("erz", schiff.global_position + x * 4.3)
	var fern := Beute.neu("erz", schiff.global_position - x * 5.0)
	level.add_child(nah)
	level.add_child(fern)
	await _warte(0.8)
	var nah_weg := not is_instance_valid(nah)
	var fern_da := is_instance_valid(fern)
	Protokoll.schreib("test", "Einsammeln: Erz in 4,3 m aufgenommen %s, in 5,0 m liegen geblieben %s → %s" % [
		nah_weg, fern_da, "BESTANDEN" if nah_weg and fern_da else "FEHLGESCHLAGEN"])


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
	# In die Reparatur der vorderen Reihe fliegen: Hülle wird voll repariert
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

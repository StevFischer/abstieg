extends Node
## Töne, beim Start im Code synthetisiert — kein fremdes Material, passt zum groben Retro-Look.
## Laser: fallender Frequenzsweep aus Rechteck und Sinus. Explosion: Rauschen durch einen
## Tiefpass, der sich schließt, darunter ein tiefes Grollen.
## Ohne Position spielt ein Ton direkt (eigener Laser), mit Position räumlich (alles andere).

const RATE := 44100
const MAX_GLEICHZEITIG := 28
## Lautstärkeregler: je Regler ein Audiokanal (Bus). "gesamt" ist der Hauptkanal.
const KANAELE := {"gesamt": "Master", "laser": "Laser", "gegner": "Gegner", "explosionen": "Explosionen", "alarm": "Alarm",
	"musik": "Musik"}
const KANAL_NAMEN := {"gesamt": "Gesamt", "laser": "Eigene Waffen", "gegner": "Gegnerschüsse", "explosionen": "Explosionen und Treffer",
	"alarm": "Alarm und Countdown", "musik": "Musik"}
const TON_KANAL := {"laser": "Laser", "rakete": "Laser", "laser_gegner": "Gegner", "einschlag": "Explosionen",
	"explosion": "Explosionen", "explosion_gross": "Explosionen", "treffer_schild": "Explosionen", "treffer_huelle": "Explosionen",
	"sirene": "Alarm", "piep": "Alarm"}
const MUSIK_RATE := 22050      ## Musik in halber Abtastrate: halb so viel Rechenzeit beim Erzeugen, klingt für Synthflächen gleich
const MUSIK_DB := -15.0

var lautstaerke := {"gesamt": 1.0, "laser": 1.0, "gegner": 1.0, "explosionen": 1.0, "alarm": 1.0, "musik": 1.0}
var musik: AudioStreamPlayer
var musik_bereit := false
var _musik_auftrag := -1
var _einstellungen := "user://abstieg_einstellungen.cfg"

var toene := {}
var zaehler := {}        ## je Ton, wie oft er abgespielt wurde — für Selbsttest und Log
var _laufend := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # Probetöne im Optionen-Bildschirm auch in der Pause
	_rng.seed = 4711
	if "--autotest" in OS.get_cmdline_user_args():
		_einstellungen = "user://abstieg_einstellungen_autotest.cfg"
	for k in KANAELE:
		var bus: String = KANAELE[k]
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	laden()
	# Begrenzer am Hauptkanal: viele gleichzeitige Einschläge dürfen nicht übersteuern.
	var begrenzer := AudioEffectHardLimiter.new()
	begrenzer.ceiling_db = -1.0
	begrenzer.pre_gain_db = -4.0
	AudioServer.add_bus_effect(0, begrenzer)
	var t0 := Time.get_ticks_msec()
	toene["laser"] = _laser(1500.0, 320.0, 0.16, 0.55)
	toene["laser_gegner"] = _laser(820.0, 170.0, 0.22, 0.75)
	toene["einschlag"] = _explosion(0.22, 0.55, 0.0, 30.0)
	toene["explosion"] = _explosion(0.75, 0.35, 0.5, 6.0)
	toene["explosion_gross"] = _explosion(2.2, 0.25, 0.9, 2.2)
	toene["sirene"] = _sirene(1.6)
	toene["piep"] = _piep(0.07, 1250.0)
	toene["rakete"] = _rakete(0.8)
	toene["treffer_schild"] = _treffer_schild(0.4)
	toene["treffer_huelle"] = _treffer_huelle(0.35)
	Protokoll.schreib("klang", "%d Töne erzeugt in %d ms" % [toene.size(), Time.get_ticks_msec() - t0])
	# Musik ist 16 s lang — im Hintergrund erzeugen, damit der Start (gerade am Handy) nicht wartet.
	musik = AudioStreamPlayer.new()
	musik.bus = "Musik"
	musik.volume_db = MUSIK_DB
	add_child(musik)
	_musik_auftrag = WorkerThreadPool.add_task(func():
		var t1 := Time.get_ticks_msec()
		var w := _musik_bauen()
		call_deferred("_musik_fertig", w, Time.get_ticks_msec() - t1))


## Beim Beenden auf die Musik-Erzeugung warten, sonst läuft der Faden in ein freigegebenes Objekt.
func _exit_tree() -> void:
	if _musik_auftrag >= 0:
		WorkerThreadPool.wait_for_task_completion(_musik_auftrag)


func _musik_fertig(w: AudioStreamWAV, ms: int) -> void:
	musik.stream = w
	musik.play()
	musik_bereit = true
	Protokoll.schreib("klang", "Musik erzeugt in %d ms (%.0f s Schleife), läuft" % [ms, w.data.size() / 2.0 / MUSIK_RATE])


## pos == null: ohne Raum (eigener Laser). Sonst räumlich an pos.
func spiele(name: String, pos: Variant = null, db := 0.0, tonhoehe := 1.0) -> void:
	if not toene.has(name) or _laufend >= MAX_GLEICHZEITIG:
		return
	zaehler[name] = int(zaehler.get(name, 0)) + 1
	var p: Node
	if pos == null:
		var a := AudioStreamPlayer.new()
		a.stream = toene[name]
		a.volume_db = db
		a.bus = TON_KANAL.get(name, "Master")
		a.pitch_scale = _rng.randf_range(0.94, 1.06) * tonhoehe
		p = a
	else:
		var a3 := AudioStreamPlayer3D.new()
		a3.stream = toene[name]
		a3.volume_db = db
		a3.bus = TON_KANAL.get(name, "Master")
		a3.unit_size = 12.0
		a3.max_distance = 140.0
		a3.pitch_scale = _rng.randf_range(0.9, 1.1) * tonhoehe
		a3.position = pos
		p = a3
	add_child(p)
	_laufend += 1
	p.finished.connect(func():
		_laufend -= 1
		p.queue_free())
	p.play()


func setze(kanal: String, wert: float) -> void:
	lautstaerke[kanal] = clampf(wert, 0.0, 1.0)
	var i := AudioServer.get_bus_index(KANAELE[kanal])
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lautstaerke[kanal], 0.0001)))
	AudioServer.set_bus_mute(i, lautstaerke[kanal] <= 0.001)


func laden() -> void:
	var c := ConfigFile.new()
	c.load(_einstellungen)
	for k in KANAELE:
		setze(k, float(c.get_value("lautstaerke", k, 1.0)))


func speichern() -> void:
	var c := ConfigFile.new()
	for k in KANAELE:
		c.set_value("lautstaerke", k, lautstaerke[k])
	var e := c.save(_einstellungen)
	Protokoll.schreib("klang", "Lautstärke gespeichert %s (%s)" % [lautstaerke, error_string(e)])


func _laser(f0: float, f1: float, dauer: float, rechteck: float) -> AudioStreamWAV:
	var n := int(dauer * RATE)
	var werte := PackedFloat32Array()
	werte.resize(n)
	var phase := 0.0
	var tief := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f0 * pow(f1 / f0, t / dauer)
		phase = fmod(phase + f / RATE, 1.0)
		var s := sin(TAU * phase)
		var q := 1.0 if phase < 0.5 else -1.0
		var roh := lerpf(s, q, rechteck)
		tief += (roh - tief) * 0.35          # Rechteck etwas entschärfen
		var huelle := minf(1.0, t * 600.0) * exp(-t * 14.0)
		werte[i] = tief * huelle
	return _wav(werte)


## Auf- und abschwellender Alarmton (zwei Wellen), wie die Selbstzerstörung im Original.
func _sirene(dauer: float) -> AudioStreamWAV:
	var n := int(dauer * RATE)
	var werte := PackedFloat32Array()
	werte.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 620.0 + 480.0 * (0.5 - 0.5 * cos(TAU * t / (dauer / 2.0)))
		phase = fmod(phase + f / RATE, 1.0)
		var s := sin(TAU * phase) * 0.6 + (1.0 if phase < 0.5 else -1.0) * 0.4
		werte[i] = s * minf(1.0, t * 80.0) * minf(1.0, (dauer - t) * 20.0)
	return _wav(werte)


func _piep(dauer: float, f: float) -> AudioStreamWAV:
	var n := int(dauer * RATE)
	var werte := PackedFloat32Array()
	werte.resize(n)
	for i in n:
		var t := float(i) / RATE
		werte[i] = (1.0 if fmod(t * f, 1.0) < 0.5 else -1.0) * 0.5 * minf(1.0, (dauer - t) * 60.0)
	return _wav(werte)


func _explosion(dauer: float, start_hell: float, grollen: float, abfall: float) -> AudioStreamWAV:
	var n := int(dauer * RATE)
	var werte := PackedFloat32Array()
	werte.resize(n)
	var tp := 0.0
	var tp2 := 0.0
	var phase := 0.0
	var knack := 0.0
	for i in n:
		var t := float(i) / RATE
		var anteil := t / dauer
		var hell := lerpf(start_hell, 0.02, sqrt(anteil))
		# Knistern: gelegentlich ein lauter Einzelwert
		if _rng.randf() < 0.002 * (1.0 - anteil):
			knack = _rng.randf_range(-1.0, 1.0)
		var rausch := _rng.randf_range(-1.0, 1.0) + knack
		knack *= 0.97
		tp += (rausch - tp) * hell
		tp2 += (tp - tp2) * hell
		var f := lerpf(70.0, 32.0, anteil)
		phase = fmod(phase + f / RATE, 1.0)
		var tiefton := sin(TAU * phase) * grollen * exp(-t * 1.5)
		var huelle := minf(1.0, t * 300.0) * exp(-t * abfall)
		werte[i] = (tp2 * 2.2 + tiefton) * huelle
	return _wav(werte)


## Raketenstart: Rauschen durch einen Filter, der auf- und wieder zugeht (Fauchen), darunter ein tiefer Schub.
func _rakete(dauer: float) -> AudioStreamWAV:
	var n := int(dauer * RATE)
	var werte := PackedFloat32Array()
	werte.resize(n)
	var tp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var anteil := t / dauer
		var hell := 0.05 + 0.4 * sin(PI * minf(anteil * 1.6, 1.0))
		tp += (_rng.randf_range(-1.0, 1.0) - tp) * hell
		phase = fmod(phase + lerpf(95.0, 60.0, anteil) / RATE, 1.0)
		var huelle := minf(1.0, t * 120.0) * exp(-t * 3.2)
		werte[i] = (tp * 1.6 + sin(TAU * phase) * 0.5) * huelle
	return _wav(werte)


## Treffer auf den Schild: heller, metallischer Klang (zwei unharmonische Teiltöne), schnell verklingend.
func _treffer_schild(dauer: float) -> AudioStreamWAV:
	var n := int(dauer * RATE)
	var werte := PackedFloat32Array()
	werte.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(620.0, 380.0, t / dauer)
		p1 = fmod(p1 + f / RATE, 1.0)
		p2 = fmod(p2 + f * 2.76 / RATE, 1.0)
		var s := sin(TAU * p1) + 0.45 * sin(TAU * p2) + _rng.randf_range(-0.15, 0.15) * exp(-t * 40.0)
		werte[i] = s * minf(1.0, t * 900.0) * exp(-t * 11.0)
	return _wav(werte)


## Treffer auf die Hülle: dumpfer Schlag mit Knirschen — klingt bedrohlicher als der Schild.
func _treffer_huelle(dauer: float) -> AudioStreamWAV:
	var n := int(dauer * RATE)
	var werte := PackedFloat32Array()
	werte.resize(n)
	var tp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		tp += (_rng.randf_range(-1.0, 1.0) - tp) * 0.18
		phase = fmod(phase + lerpf(85.0, 40.0, t / dauer) / RATE, 1.0)
		var knirschen := tp * (1.0 if fmod(t * 37.0, 1.0) < 0.6 else 0.3)
		werte[i] = (sin(TAU * phase) * 1.1 + knirschen * 1.4) * minf(1.0, t * 600.0) * exp(-t * 9.0)
	return _wav(werte)


## Musik: düstere Synth-Schleife wie in Descent, 120 BPM, 8 Takte Am–F–C–G (je zwei Takte):
## Bass in Achteln, weiche Fläche, Arpeggio in Sechzehnteln, Bassdrum auf 1 und 3, leise Hi-Hat.
func _musik_bauen() -> AudioStreamWAV:
	var r := MUSIK_RATE
	var takt := 2.0
	var n := int(8 * takt * r)
	# Überhang hinter dem Schleifenende: der Mischer liest beim Zurückspringen ein paar Samples über
	# loop_end hinaus. Ohne Überhang stürzte das Spiel auf dem Handy nach genau einer Schleife (16,9 s)
	# im Audio-Thread ab (SIGSEGV, 2026-10-10 15:12).
	var ueberhang := 64
	var werte := PackedFloat32Array()
	werte.resize(n + ueberhang)
	var grund := [110.0, 110.0, 87.31, 87.31, 130.81, 130.81, 98.0, 98.0]
	var akkord := [[0, 3, 7], [0, 3, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7]]
	var bass_p := 0.0
	var pad_p := [0.0, 0.0, 0.0, 0.0]
	var arp_p := 0.0
	var kick_p := 0.0
	var bass_tp := 0.0
	var pad_tp := 0.0
	var arp_tp := 0.0
	var hat_tp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in n + ueberhang:
		var t := float(i % n) / r          # der Überhang wiederholt den Anfang, damit der Sprung sauber klingt
		var tk := int(t / takt) % 8
		var g: float = grund[tk]
		var ak: Array = akkord[tk]
		# Bass: Sägezahn eine Oktave tiefer, Achtel mit Abklingen
		var achtel := fmod(t, 0.25)
		bass_p = fmod(bass_p + g * 0.5 / r, 1.0)
		bass_tp += ((bass_p * 2.0 - 1.0) - bass_tp) * 0.06
		var bass := bass_tp * exp(-achtel * 6.0) * 0.9
		# Fläche: zwei leicht verstimmte Sägezähne je Akkordton (Grundton + Terz), stark gefiltert
		var pad := 0.0
		for k in 2:
			var f: float = g * 2.0 * pow(2.0, ak[k] / 12.0)
			pad_p[k * 2] = fmod(pad_p[k * 2] + f / r, 1.0)
			pad_p[k * 2 + 1] = fmod(pad_p[k * 2 + 1] + f * 1.006 / r, 1.0)
			pad += pad_p[k * 2] + pad_p[k * 2 + 1] - 1.0
		pad_tp += (pad - pad_tp) * 0.025
		var pad_huelle := 0.6 + 0.4 * sin(TAU * t / (takt * 2.0))
		# Arpeggio: Rechteck, Sechzehntel durch die Akkordtöne, zwei Oktaven höher
		var sech := int(t / 0.125)
		var ton: int = ak[sech % 3] + (12 if (sech / 3) % 2 == 1 else 0)
		arp_p = fmod(arp_p + g * 4.0 * pow(2.0, ton / 12.0) / r, 1.0)
		arp_tp += ((1.0 if arp_p < 0.5 else -1.0) - arp_tp) * 0.12
		var arp := arp_tp * exp(-fmod(t, 0.125) * 18.0) * 0.28
		# Bassdrum auf 1 und 3 (jede zweite Viertel), Hi-Hat auf den Achtel-Zwischenschlägen
		var halbe := fmod(t, 1.0)
		kick_p = fmod(kick_p + lerpf(120.0, 42.0, minf(halbe / 0.15, 1.0)) / r, 1.0)
		var kick := sin(TAU * kick_p) * exp(-halbe * 18.0) * 0.9
		hat_tp += (rng.randf_range(-1.0, 1.0) - hat_tp) * 0.9
		var hat := (rng.randf_range(-1.0, 1.0) - hat_tp) * exp(-fmod(t + 0.25, 0.5) * 60.0) * 0.12
		werte[i] = bass + pad_tp * 0.35 * pad_huelle + arp + kick + hat
	var w := _wav(werte, r)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


func _wav(werte: PackedFloat32Array, rate := RATE) -> AudioStreamWAV:
	var spitze := 0.0001
	for v in werte:
		spitze = maxf(spitze, absf(v))
	var daten := PackedByteArray()
	daten.resize(werte.size() * 2)
	for i in werte.size():
		daten.encode_s16(i * 2, int(clampf(werte[i] / spitze * 0.9, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = daten
	return w

extends Node
## Töne, beim Start im Code synthetisiert — kein fremdes Material, passt zum groben Retro-Look.
## Laser: fallender Frequenzsweep aus Rechteck und Sinus. Explosion: Rauschen durch einen
## Tiefpass, der sich schließt, darunter ein tiefes Grollen.
## Ohne Position spielt ein Ton direkt (eigener Laser), mit Position räumlich (alles andere).

const RATE := 44100
const MAX_GLEICHZEITIG := 28
## Lautstärkeregler: je Regler ein Audiokanal (Bus). "gesamt" ist der Hauptkanal.
const KANAELE := {"gesamt": "Master", "laser": "Laser", "gegner": "Gegner", "explosionen": "Explosionen"}
const KANAL_NAMEN := {"gesamt": "Gesamt", "laser": "Eigener Laser", "gegner": "Gegnerschüsse", "explosionen": "Explosionen"}
const TON_KANAL := {"laser": "Laser", "laser_gegner": "Gegner", "einschlag": "Explosionen",
	"explosion": "Explosionen", "explosion_gross": "Explosionen"}

var lautstaerke := {"gesamt": 1.0, "laser": 1.0, "gegner": 1.0, "explosionen": 1.0}
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
	Protokoll.schreib("klang", "%d Töne erzeugt in %d ms" % [toene.size(), Time.get_ticks_msec() - t0])


## pos == null: ohne Raum (eigener Laser). Sonst räumlich an pos.
func spiele(name: String, pos: Variant = null, db := 0.0) -> void:
	if not toene.has(name) or _laufend >= MAX_GLEICHZEITIG:
		return
	zaehler[name] = int(zaehler.get(name, 0)) + 1
	var p: Node
	if pos == null:
		var a := AudioStreamPlayer.new()
		a.stream = toene[name]
		a.volume_db = db
		a.bus = TON_KANAL.get(name, "Master")
		a.pitch_scale = _rng.randf_range(0.94, 1.06)
		p = a
	else:
		var a3 := AudioStreamPlayer3D.new()
		a3.stream = toene[name]
		a3.volume_db = db
		a3.bus = TON_KANAL.get(name, "Master")
		a3.unit_size = 12.0
		a3.max_distance = 140.0
		a3.pitch_scale = _rng.randf_range(0.9, 1.1)
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


func _wav(werte: PackedFloat32Array) -> AudioStreamWAV:
	var spitze := 0.0001
	for v in werte:
		spitze = maxf(spitze, absf(v))
	var daten := PackedByteArray()
	daten.resize(werte.size() * 2)
	for i in werte.size():
		daten.encode_s16(i * 2, int(clampf(werte[i] / spitze * 0.9, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = daten
	return w

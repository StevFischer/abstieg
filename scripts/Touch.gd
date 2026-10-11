class_name Touch
extends Control
## Touch-Steuerung am Handy (Stev 2026-10-11, seine Wahl): linker Daumen ein schwebender Stick zum Fliegen,
## Ziehen auf der rechten Bildhälfte dreht das Schiff wie die Maus, Knöpfe am rechten Rand, Laser feuert solange
## der Feuerknopf gehalten wird. Alles läuft über InputEventAction, also über dieselben Aktionen wie Tastatur und
## Controller. Sobald ein Controller benutzt wird, blendet sich die Ebene aus; die nächste Berührung holt sie zurück.

const STICK_RADIUS := 110.0        ## so weit (Fläche, nicht Pixel) muss der Daumen für volle Fahrt ziehen
const STICK_TOT := 0.12            ## Totzone des Sticks
const DREH := 1.2                  ## Ziehen rechts: Faktor auf die Mausdrehung (Schiff.MAUS je Bildpunkt), mal Optionen-Regler
const FARBE := Color(1.0, 0.82, 0.3)

var main: Node                     ## Main.gd: zustand, schiff
var an := false                    ## Touch-Modus (Gerät mit Touchschirm oder --touch)
var _pad_modus := false            ## zuletzt Controller benutzt → ausgeblendet
var _finger := {}                  ## Fingerindex → {art: "stick"|"blick"|"knopf", ...}
var _stick_mitte := Vector2.ZERO
var _stick_wert := Vector2.ZERO
var _gedrueckt := {}               ## Aktion → Stärke, die wir gerade halten
var _knoepfe: Array = []           ## [{aktion, text, mitte, radius}] — neu berechnet je Bild (Fenstergröße, Freischaltungen)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	an = verfuegbar()
	Protokoll.schreib("start", "Touch-Steuerung %s (Touchschirm %s)" % ["an" if an else "aus", DisplayServer.is_touchscreen_available()])


## Gerät mit Touchschirm (Handy, Tablet, auch im Browser) oder am PC mit --touch nachgestellt
static func verfuegbar() -> bool:
	return DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()


func aktiv() -> bool:
	return an and not _pad_modus and main.zustand == "flug" and main.schiff != null and not get_tree().paused


func _process(_dt: float) -> void:
	var war := visible
	visible = aktiv()
	# Im Flug keine Maus aus Berührungen: ein Tipp wäre sonst ein Linksklick (= Laser) und ein Wischen eine Mausdrehung.
	# In Hangar und Pausenmenü bleibt sie an, dort bedient man die Knöpfe per Tipp.
	if an:
		Input.emulate_mouse_from_touch = not visible
	if war and not visible:
		_alles_los()
	if visible:
		_knoepfe_legen()
		queue_redraw()


func _knoepfe_legen() -> void:
	var s := get_viewport_rect().size
	var r := s.x
	var u := s.y
	_knoepfe = [
		{"aktion": "feuer", "text": "FEUER", "mitte": Vector2(r - 140, u - 150), "radius": 88.0},
		{"aktion": "rakete", "text": "RAKETE", "mitte": Vector2(r - 320, u - 105), "radius": 56.0},
		{"aktion": "hoch", "text": "▲", "mitte": Vector2(r - 90, u - 470), "radius": 50.0},
		{"aktion": "runter", "text": "▼", "mitte": Vector2(r - 90, u - 350), "radius": 50.0},
		{"aktion": "rollen_links", "text": "↺", "mitte": Vector2(r - 330, u - 265), "radius": 46.0},
		{"aktion": "rollen_rechts", "text": "↻", "mitte": Vector2(r - 220, u - 330), "radius": 46.0},
		{"aktion": "pause", "text": "II", "mitte": Vector2(60, 110), "radius": 38.0},
	]
	# Obere Leiste rechts: Waffenwechsel, Licht und was gekauft ist
	var leiste := [["laser_weiter", "LASER ⇄"], ["rakete_weiter", "RAK ⇄"], ["licht", "LICHT"]]
	if main.schiff.nachbrenner_cd > 0.0:
		leiste.append(["nachbrenner", "BOOST"])
	if main.schiff.notfall_cd > 0.0:
		leiste.append(["notfallschild", "SCHILD"])
	for i in leiste.size():
		_knoepfe.append({"aktion": leiste[i][0], "text": leiste[i][1], "mitte": Vector2(r - 80 - i * 104, 150), "radius": 42.0})


func _knopf_bei(p: Vector2) -> Dictionary:
	for k in _knoepfe:
		if p.distance_to(k.mitte) <= k.radius + 10.0:     # etwas großzügiger als gezeichnet
			return k
	return {}


func _input(e: InputEvent) -> void:
	if not an:
		return
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.3):
		if not _pad_modus:
			_pad_modus = true
			Protokoll.schreib("lauf", "Touch ausgeblendet: Controller benutzt")
		return
	if e is InputEventScreenTouch and _pad_modus and e.pressed:
		_pad_modus = false
		Protokoll.schreib("lauf", "Touch wieder eingeblendet")
	if not aktiv():
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			_finger_neu(e.index, e.position)
		else:
			_finger_los(e.index)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and _finger.has(e.index):
		var f: Dictionary = _finger[e.index]
		match f.art:
			"stick":
				var v: Vector2 = (e.position - _stick_mitte) / STICK_RADIUS
				_stick_setzen(v.limit_length(1.0))
			"blick":
				main.schiff.touch_drehen(e.relative * DREH * Eingabe.touch_empfindlichkeit)
			"knopf":
				# vom Knopf gerutscht: loslassen (sonst klemmt z. B. der Laser)
				if e.position.distance_to(f.knopf.mitte) > f.knopf.radius * 1.6:
					_aktion(f.knopf.aktion, 0.0)
					_finger.erase(e.index)
		get_viewport().set_input_as_handled()


func _finger_neu(index: int, p: Vector2) -> void:
	var k := _knopf_bei(p)
	if not k.is_empty():
		_finger[index] = {"art": "knopf", "knopf": k}
		_aktion(k.aktion, 1.0)
		return
	var s := get_viewport_rect().size
	if p.x < s.x * 0.42 and not _stick_belegt():
		_finger[index] = {"art": "stick"}
		_stick_mitte = p
		_stick_setzen(Vector2.ZERO)
	else:
		_finger[index] = {"art": "blick"}


func _finger_los(index: int) -> void:
	if not _finger.has(index):
		return
	var f: Dictionary = _finger[index]
	_finger.erase(index)
	if f.art == "stick":
		_stick_setzen(Vector2.ZERO)
	elif f.art == "knopf":
		_aktion(f.knopf.aktion, 0.0)


func _stick_belegt() -> bool:
	for f in _finger.values():
		if f.art == "stick":
			return true
	return false


func _stick_setzen(v: Vector2) -> void:
	_stick_wert = v
	var l := v.length()
	var w := Vector2.ZERO if l < STICK_TOT else v * ((l - STICK_TOT) / (1.0 - STICK_TOT) / l)
	_aktion("rechts", maxf(w.x, 0.0))
	_aktion("links", maxf(-w.x, 0.0))
	_aktion("zurueck", maxf(w.y, 0.0))
	_aktion("vor", maxf(-w.y, 0.0))


## Aktion drücken (Stärke > 0) oder loslassen; nur bei Änderung ein Ereignis, damit just_pressed stimmt.
func _aktion(name: String, staerke: float) -> void:
	var war: float = _gedrueckt.get(name, 0.0)
	if is_equal_approx(war, staerke):
		return
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = staerke > 0.0
	ev.strength = staerke
	Input.parse_input_event(ev)
	if staerke > 0.0:
		_gedrueckt[name] = staerke
	else:
		_gedrueckt.erase(name)


func _alles_los() -> void:
	for a in _gedrueckt.keys():
		_aktion(a, 0.0)
	_finger.clear()
	_stick_wert = Vector2.ZERO


func _draw() -> void:
	var s := get_viewport_rect().size
	var schrift := ThemeDB.fallback_font
	# Stick: ruht unten links, folgt dem Daumen, solange er unten ist
	var mitte := _stick_mitte if _stick_belegt() else Vector2(200, s.y - 200)
	draw_circle(mitte, STICK_RADIUS, Color(1, 1, 1, 0.06))
	draw_arc(mitte, STICK_RADIUS, 0, TAU, 48, Color(FARBE, 0.35), 3.0)
	draw_circle(mitte + _stick_wert * STICK_RADIUS, 42, Color(FARBE, 0.45 if _stick_belegt() else 0.2))
	for k in _knoepfe:
		var gedrueckt := _gedrueckt.has(k.aktion)
		draw_circle(k.mitte, k.radius, Color(FARBE, 0.32) if gedrueckt else Color(0, 0, 0, 0.28))
		draw_arc(k.mitte, k.radius, 0, TAU, 40, Color(FARBE, 0.8 if gedrueckt else 0.45), 3.0)
		var g := 26 if k.radius > 60 else (24 if k.text.length() <= 2 else 15)
		draw_string(schrift, k.mitte + Vector2(-k.radius, g * 0.35), k.text, HORIZONTAL_ALIGNMENT_CENTER, k.radius * 2.0, g,
			Color(1, 0.95, 0.85, 0.9))

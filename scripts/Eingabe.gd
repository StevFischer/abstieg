extends Node
## Tastenbelegung im Code: Maus/Tastatur und Controller nebeneinander.
## Die Maus dreht direkt (wie Descent mit flightsim=0), das liest Schiff.gd selbst aus.
## Tastatur und Maustasten sind in den Optionen umbelegbar (Stev 2026-10-10); die eigene Belegung steht in
## user://abstieg_tasten.cfg, der Controller bleibt fest.

## Umbelegbare Aktionen in der Reihenfolge der Optionsliste: [Aktion, Anzeigename]
const BELEGBAR := [
	["vor", "Vorwärts"], ["zurueck", "Rückwärts"], ["links", "Links"], ["rechts", "Rechts"],
	["hoch", "Hoch"], ["runter", "Runter"], ["rollen_links", "Rollen links"], ["rollen_rechts", "Rollen rechts"],
	["feuer", "Laser feuern"], ["rakete", "Rakete feuern"], ["nachbrenner", "Nachbrenner"], ["notfallschild", "Notfallschild"],
	["leitstrahl", "Leitstrahl"], ["licht", "Scheinwerfer"], ["pause", "Pause"],
	["waffe_1", "Laser 1"], ["waffe_2", "Laser 2"], ["waffe_3", "Laser 3"], ["waffe_4", "Laser 4"],
	["waffe_5", "Rakete 5"], ["waffe_6", "Rakete 6"], ["waffe_7", "Rakete 7"], ["waffe_8", "Rakete 8"],
]
var _standard := {}          ## Aktion -> Liste der PC-Ereignisse ab Werk
var _datei := "user://abstieg_tasten.cfg"
const FASSUNG := 2           ## 2: Leitstrahl ab Werk unbelegt (2026-10-11)


func _ready() -> void:
	_aktion("vor", [KEY_W], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_aktion("zurueck", [KEY_S], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_aktion("links", [KEY_A], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_aktion("rechts", [KEY_D], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_aktion("hoch", [KEY_SPACE], [JOY_BUTTON_A], [])
	_aktion("runter", [KEY_CTRL, KEY_C], [JOY_BUTTON_B], [])
	_aktion("rollen_links", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER], [])
	_aktion("rollen_rechts", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_aktion("blick_links", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_aktion("blick_rechts", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_aktion("blick_hoch", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_aktion("blick_runter", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_aktion("feuer", [], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], [MOUSE_BUTTON_LEFT])
	_aktion("rakete", [], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]], [MOUSE_BUTTON_RIGHT])
	# Stev 2026-10-11: ab Werk unbelegt, man kam dauernd versehentlich auf Tab/Select. Belegbar in den Optionen.
	_aktion("leitstrahl", [], [], [])
	_aktion("licht", [KEY_F], [JOY_BUTTON_Y], [])
	_aktion("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_aktion("nachbrenner", [KEY_SHIFT], [JOY_BUTTON_X], [])
	_aktion("notfallschild", [KEY_R], [JOY_BUTTON_RIGHT_STICK], [])
	# Menüs mit dem Gamepad (GameSir am Handy): Godot belegt Bestätigen/Zurück nicht von selbst mit A/B.
	_aktion("ui_accept", [], [JOY_BUTTON_A], [])
	_aktion("ui_cancel", [], [JOY_BUTTON_B], [])
	var tasten := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]
	for i in 8:
		_aktion("waffe_%d" % (i + 1), [tasten[i]], [], [])
	_aktion("laser_weiter", [], [JOY_BUTTON_DPAD_RIGHT], [], [MOUSE_BUTTON_WHEEL_UP])
	_aktion("laser_zurueck", [], [JOY_BUTTON_DPAD_LEFT], [], [MOUSE_BUTTON_WHEEL_DOWN])
	_aktion("rakete_weiter", [], [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN], [])
	for b in BELEGBAR:
		_standard[b[0]] = pc_ereignisse(b[0])
	if "--autotest" in OS.get_cmdline_user_args():
		_datei = "user://abstieg_tasten_autotest.cfg"
	laden()


## Tastatur- und Mausereignisse einer Aktion (ohne Controller)
func pc_ereignisse(aktion: String) -> Array:
	return InputMap.action_get_events(aktion).filter(func(e): return e is InputEventKey or e is InputEventMouseButton)


func _setze_pc(aktion: String, liste: Array) -> void:
	for e in pc_ereignisse(aktion):
		InputMap.action_erase_event(aktion, e)
	for e in liste:
		InputMap.action_add_event(aktion, e)


func _gleich(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.physical_keycode == b.physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false


## Neu belegen. Hatte eine andere Aktion die Taste schon, bekommt sie die bisherige der neuen Aktion (Tausch).
## Gibt die getauschte Aktion zurück (leer, wenn keine).
func belegen(aktion: String, e: InputEvent) -> String:
	var neu: InputEvent
	if e is InputEventKey:
		neu = InputEventKey.new()
		neu.physical_keycode = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
	elif e is InputEventMouseButton:
		neu = InputEventMouseButton.new()
		neu.button_index = e.button_index
	else:
		return ""
	var alt := pc_ereignisse(aktion)
	var getauscht := ""
	for b in BELEGBAR:
		if b[0] == aktion:
			continue
		var andere := pc_ereignisse(b[0])
		var rest := andere.filter(func(x): return not _gleich(x, neu))
		if rest.size() != andere.size():
			getauscht = b[0]
			_setze_pc(b[0], rest if not rest.is_empty() else alt)
	_setze_pc(aktion, [neu])
	speichern()
	Protokoll.schreib("tasten", "%s → %s%s" % [aktion, text_fuer(aktion), (" (getauscht mit %s → %s)" % [getauscht, text_fuer(getauscht)]) if getauscht != "" else ""])
	return getauscht


func zuruecksetzen() -> void:
	for a in _standard:
		_setze_pc(a, _standard[a])
	speichern()
	Protokoll.schreib("tasten", "Belegung auf Standard zurückgesetzt")


func speichern() -> void:
	var c := ConfigFile.new()
	for b in BELEGBAR:
		var liste: Array[String] = []
		for e in pc_ereignisse(b[0]):
			liste.append(("taste:%d" % e.physical_keycode) if e is InputEventKey else ("maus:%d" % e.button_index))
		c.set_value("tasten", b[0], liste)
	c.set_value("stand", "fassung", FASSUNG)
	c.save(_datei)


func laden() -> void:
	var c := ConfigFile.new()
	if c.load(_datei) != OK:
		return
	var fassung: int = c.get_value("stand", "fassung", 1)
	for b in BELEGBAR:
		var liste: Array = c.get_value("tasten", b[0], [])
		# Fassung 1 speicherte den alten Standard Tab für den Leitstrahl mit — der soll jetzt unbelegt sein
		if fassung < 2 and b[0] == "leitstrahl" and liste == ["taste:%d" % KEY_TAB]:
			continue
		if liste.is_empty():
			continue
		var ereignisse := []
		for eintrag: String in liste:
			var teil := eintrag.split(":")
			if teil[0] == "taste":
				var k := InputEventKey.new()
				k.physical_keycode = int(teil[1]) as Key
				ereignisse.append(k)
			else:
				var m := InputEventMouseButton.new()
				m.button_index = int(teil[1]) as MouseButton
				ereignisse.append(m)
		_setze_pc(b[0], ereignisse)


const NAMEN := {"Shift": "Umschalt", "Ctrl": "Strg", "Space": "Leertaste", "Escape": "Esc", "Enter": "Eingabe",
	"Backspace": "Rücktaste", "Up": "Pfeil hoch", "Down": "Pfeil runter", "Left": "Pfeil links", "Right": "Pfeil rechts",
	"CapsLock": "Feststell", "Delete": "Entf", "Insert": "Einfg", "PageUp": "Bild hoch", "PageDown": "Bild runter"}
const MAUS_NAMEN := {MOUSE_BUTTON_LEFT: "Linke Maustaste", MOUSE_BUTTON_RIGHT: "Rechte Maustaste",
	MOUSE_BUTTON_MIDDLE: "Mittlere Maustaste", MOUSE_BUTTON_XBUTTON1: "Maustaste 4", MOUSE_BUTTON_XBUTTON2: "Maustaste 5",
	MOUSE_BUTTON_WHEEL_UP: "Mausrad hoch", MOUSE_BUTTON_WHEEL_DOWN: "Mausrad runter"}


## Lesbarer Name der aktuellen PC-Belegung, z. B. „Strg / C“ oder „Linke Maustaste“.
func text_fuer(aktion: String) -> String:
	var teile: Array[String] = []
	for e in pc_ereignisse(aktion):
		if e is InputEventKey:
			var k: Key = DisplayServer.keyboard_get_keycode_from_physical(e.physical_keycode)
			var n := OS.get_keycode_string(k if k != KEY_NONE else e.physical_keycode)
			teile.append(NAMEN.get(n, n))
		else:
			teile.append(MAUS_NAMEN.get(e.button_index, "Maustaste %d" % e.button_index))
	return " / ".join(teile) if not teile.is_empty() else "—"


func _aktion(name: String, tasten: Array, knoepfe: Array, achsen: Array, maus: Array = []) -> void:
	if not InputMap.has_action(name):
		# Blick-Stick mit kleiner Totzone, damit feines Zielen möglich ist (die Kennlinie in Schiff.gd dämpft)
		InputMap.add_action(name, 0.12 if name.begins_with("blick_") else 0.2)
	for k in tasten:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(name, e)
	for b in knoepfe:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(name, e)
	for a in achsen:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(name, e)
	for m in maus:
		var e := InputEventMouseButton.new()
		e.button_index = m
		InputMap.action_add_event(name, e)

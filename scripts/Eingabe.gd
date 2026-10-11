extends Node
## Tastenbelegung im Code: Maus/Tastatur und Controller nebeneinander.
## Die Maus dreht direkt (wie Descent mit flightsim=0), das liest Schiff.gd selbst aus.
## Tastatur und Maustasten sind in den Optionen umbelegbar (Stev 2026-10-10); die eigene Belegung steht in
## user://abstieg_tasten.cfg. Seit 2026-10-11 auch die Controller-Knöpfe und Trigger (Stev: „für Controller die
## Tastenbelegung“ fehlte am Handy); die Sticks bleiben fest, Menüs bedienen sich weiter mit Steuerkreuz und A/B.

## Umbelegbare Aktionen in der Reihenfolge der Optionsliste: [Aktion, Anzeigename]
const BELEGBAR := [
	["vor", "Vorwärts"], ["zurueck", "Rückwärts"], ["links", "Links"], ["rechts", "Rechts"],
	["hoch", "Hoch"], ["runter", "Runter"], ["rollen_links", "Rollen links"], ["rollen_rechts", "Rollen rechts"],
	["feuer", "Laser feuern"], ["rakete", "Rakete feuern"], ["nachbrenner", "Nachbrenner"], ["notfallschild", "Notfallschild"],
	["leitstrahl", "Leitstrahl"], ["licht", "Scheinwerfer"], ["pause", "Pause"],
	["waffe_1", "Laser 1"], ["waffe_2", "Laser 2"], ["waffe_3", "Laser 3"], ["waffe_4", "Laser 4"],
	["waffe_5", "Rakete 5"], ["waffe_6", "Rakete 6"], ["waffe_7", "Rakete 7"], ["waffe_8", "Rakete 8"],
]
## Am Controller umbelegbar: Knöpfe und Trigger, nicht die Sticks
const PAD_BELEGBAR := [
	["hoch", "Hoch"], ["runter", "Runter"], ["rollen_links", "Rollen links"], ["rollen_rechts", "Rollen rechts"],
	["feuer", "Laser feuern"], ["rakete", "Rakete feuern"], ["nachbrenner", "Nachbrenner"], ["notfallschild", "Notfallschild"],
	["leitstrahl", "Leitstrahl"], ["licht", "Scheinwerfer"], ["pause", "Pause"],
	["laser_weiter", "Nächster Laser"], ["laser_zurueck", "Voriger Laser"], ["rakete_weiter", "Nächste Rakete"],
]
var _standard := {}          ## Aktion -> Liste der PC-Ereignisse ab Werk
var touch_empfindlichkeit := 1.0   ## Faktor auf die Drehung beim Wischen (Optionen-Regler, 0,25–3,0; Stev 2026-10-11)
var _standard_pad := {}      ## Aktion -> Liste der Controller-Ereignisse (Knöpfe, Trigger) ab Werk
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
	for b in PAD_BELEGBAR:
		_standard_pad[b[0]] = pad_ereignisse(b[0])
	if "--autotest" in OS.get_cmdline_user_args():
		_datei = "user://abstieg_tasten_autotest.cfg"
	laden()


## Tastatur- und Mausereignisse einer Aktion (ohne Controller)
func pc_ereignisse(aktion: String) -> Array:
	return InputMap.action_get_events(aktion).filter(func(e): return e is InputEventKey or e is InputEventMouseButton)


## Controller-Knöpfe und Trigger einer Aktion (ohne Sticks)
func pad_ereignisse(aktion: String) -> Array:
	return InputMap.action_get_events(aktion).filter(func(e): return e is InputEventJoypadButton or \
		(e is InputEventJoypadMotion and e.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]))


func _setze_pad(aktion: String, liste: Array) -> void:
	for e in pad_ereignisse(aktion):
		InputMap.action_erase_event(aktion, e)
	for e in liste:
		InputMap.action_add_event(aktion, e)


func _gleich_pad(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.axis == b.axis
	return false


## Controller neu belegen, mit Tausch wie bei der Tastatur. Nimmt Knöpfe und Trigger (Achse 4/5), sonst nichts.
func belegen_pad(aktion: String, e: InputEvent) -> String:
	var neu: InputEvent
	if e is InputEventJoypadButton:
		neu = InputEventJoypadButton.new()
		neu.button_index = e.button_index
	elif e is InputEventJoypadMotion and e.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		neu = InputEventJoypadMotion.new()
		neu.axis = e.axis
		neu.axis_value = 1.0
	else:
		return ""
	var alt := pad_ereignisse(aktion)
	var getauscht := ""
	for b in PAD_BELEGBAR:
		if b[0] == aktion:
			continue
		var andere := pad_ereignisse(b[0])
		var rest := andere.filter(func(x): return not _gleich_pad(x, neu))
		if rest.size() != andere.size():
			getauscht = b[0]
			_setze_pad(b[0], rest if not rest.is_empty() else alt)
	_setze_pad(aktion, [neu])
	speichern()
	Protokoll.schreib("tasten", "Controller %s → %s%s" % [aktion, pad_text(aktion), (" (getauscht mit %s → %s)" % [getauscht, pad_text(getauscht)]) if getauscht != "" else ""])
	return getauscht


func zuruecksetzen_pad() -> void:
	for a in _standard_pad:
		_setze_pad(a, _standard_pad[a])
	speichern()
	Protokoll.schreib("tasten", "Controller-Belegung auf Standard zurückgesetzt")


const PAD_NAMEN := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_BACK: "Select", JOY_BUTTON_START: "Start",
	JOY_BUTTON_GUIDE: "Home", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "Steuerkreuz ↑", JOY_BUTTON_DPAD_DOWN: "Steuerkreuz ↓", JOY_BUTTON_DPAD_LEFT: "Steuerkreuz ←",
	JOY_BUTTON_DPAD_RIGHT: "Steuerkreuz →"}

## Lesbarer Name der Controller-Belegung, z. B. „RT“ oder „Steuerkreuz ↑ / Steuerkreuz ↓“.
func pad_text(aktion: String) -> String:
	var teile: Array[String] = []
	for e in pad_ereignisse(aktion):
		if e is InputEventJoypadButton:
			teile.append(PAD_NAMEN.get(e.button_index, "Knopf %d" % e.button_index))
		else:
			teile.append("LT" if e.axis == JOY_AXIS_TRIGGER_LEFT else "RT")
	return " / ".join(teile) if not teile.is_empty() else "—"


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
	for b in PAD_BELEGBAR:
		var liste: Array[String] = []
		for e in pad_ereignisse(b[0]):
			liste.append(("knopf:%d" % e.button_index) if e is InputEventJoypadButton else ("achse:%d" % e.axis))
		c.set_value("controller", b[0], liste)
	c.set_value("touch", "empfindlichkeit", touch_empfindlichkeit)
	c.set_value("stand", "fassung", FASSUNG)
	c.save(_datei)


func laden() -> void:
	var c := ConfigFile.new()
	if c.load(_datei) != OK:
		return
	touch_empfindlichkeit = clampf(float(c.get_value("touch", "empfindlichkeit", 1.0)), 0.25, 3.0)
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
	for b in PAD_BELEGBAR:
		var liste: Array = c.get_value("controller", b[0], [])
		if liste.is_empty():
			continue
		var ereignisse := []
		for eintrag: String in liste:
			var teil := eintrag.split(":")
			if teil[0] == "knopf":
				var k := InputEventJoypadButton.new()
				k.button_index = int(teil[1]) as JoyButton
				ereignisse.append(k)
			else:
				var m := InputEventJoypadMotion.new()
				m.axis = int(teil[1]) as JoyAxis
				m.axis_value = 1.0
				ereignisse.append(m)
		_setze_pad(b[0], ereignisse)


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

extends Node
## Tastenbelegung im Code: Maus/Tastatur und Controller nebeneinander.
## Die Maus dreht direkt (wie Descent mit flightsim=0), das liest Schiff.gd selbst aus.


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
	_aktion("leitstrahl", [KEY_TAB], [JOY_BUTTON_BACK], [])
	_aktion("licht", [KEY_F], [JOY_BUTTON_Y], [])
	_aktion("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])


func _aktion(name: String, tasten: Array, knoepfe: Array, achsen: Array, maus: Array = []) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.2)
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

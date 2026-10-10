extends Node
## Roguelite-Fortschritt, der einen Tod überlebt: Erz in der Bank, gekaufte Aufrüstungen, Rekord.

var _pfad := "user://abstieg_meta.cfg"
const AUFRUESTUNGEN := [
	{"id": "schild", "name": "Schildgenerator", "text": "+25 Schild", "kosten": 40, "max": 8},
	{"id": "panzerung", "name": "Panzerung", "text": "+25 Hülle", "kosten": 40, "max": 8},
	{"id": "laser", "name": "Laserbündelung", "text": "+20 % Laserschaden", "kosten": 50, "max": 8},
	{"id": "energie", "name": "Energiewandler", "text": "+30 % Energie-Nachladen", "kosten": 35, "max": 6},
	{"id": "triebwerk", "name": "Triebwerk", "text": "+8 % Tempo", "kosten": 45, "max": 5},
	{"id": "raketen", "name": "Raketenschacht", "text": "+2 Raketen", "kosten": 30, "max": 6},
]

var bank := 0
var rekord := 0
var laeufe := 0
var stufen := {}
var waffen: Array = []     ## freigeschaltete Waffen-IDs, zusätzlich zu Waffen.START


func _ready() -> void:
	# Der Selbsttest schreibt in eine eigene Datei, sonst landet sein Fortschritt im echten Spielstand.
	if "--autotest" in OS.get_cmdline_user_args():
		_pfad = "user://abstieg_meta_autotest.cfg"
	laden()


func stufe(id: String) -> int:
	return int(stufen.get(id, 0))


func _def(id: String) -> Dictionary:
	for a in AUFRUESTUNGEN:
		if a.id == id:
			return a
	return {}


func kosten(id: String) -> int:
	return int(round(_def(id).kosten * pow(1.6, stufe(id))))


func ausgereizt(id: String) -> bool:
	return stufe(id) >= int(_def(id).max)


func kaufbar(id: String) -> bool:
	return not ausgereizt(id) and bank >= kosten(id)


func kaufen(id: String) -> bool:
	if not kaufbar(id):
		return false
	bank -= kosten(id)
	stufen[id] = stufe(id) + 1
	speichern()
	Protokoll.schreib("meta", "gekauft %s Stufe %d, Bank jetzt %d" % [id, stufe(id), bank])
	return true


func waffen_frei() -> Array:
	var alle: Array = Waffen.START.duplicate()
	alle.append_array(waffen)
	return alle


func waffe_kaufbar(id: String) -> bool:
	return not id in waffen_frei() and bank >= int(Waffen.finde(id).preis)


func waffe_kaufen(id: String) -> bool:
	if not waffe_kaufbar(id):
		return false
	bank -= int(Waffen.finde(id).preis)
	waffen.append(id)
	speichern()
	Protokoll.schreib("meta", "Waffe freigeschaltet %s, Bank jetzt %d" % [id, bank])
	return true


func schiffswerte() -> Dictionary:
	return {
		"schild_max": 50.0 + 25.0 * stufe("schild"),
		"huelle_max": 100.0 + 25.0 * stufe("panzerung"),
		"laser_mult": 1.0 + 0.2 * stufe("laser"),
		"energie_regen": 3.0 * (1.0 + 0.3 * stufe("energie")),
		"tempo": 14.0 * (1.0 + 0.08 * stufe("triebwerk")),
		"raketen_max": 4 + 2 * stufe("raketen"),
	}


func laden() -> void:
	var c := ConfigFile.new()
	if c.load(_pfad) != OK:
		return
	bank = c.get_value("meta", "bank", 0)
	rekord = c.get_value("meta", "rekord", 0)
	laeufe = c.get_value("meta", "laeufe", 0)
	stufen = c.get_value("meta", "stufen", {})
	waffen = c.get_value("meta", "waffen", [])


func speichern() -> void:
	var c := ConfigFile.new()
	c.set_value("meta", "bank", bank)
	c.set_value("meta", "rekord", rekord)
	c.set_value("meta", "laeufe", laeufe)
	c.set_value("meta", "stufen", stufen)
	c.set_value("meta", "waffen", waffen)
	var e := c.save(_pfad)
	if e != OK:
		Protokoll.schreib("fehler", "Meta speichern fehlgeschlagen: %s" % error_string(e))

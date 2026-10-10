extends Node
## Roguelite-Fortschritt, der einen Tod überlebt: Erz in der Bank, gekaufte Aufrüstungen, Rekord.

var _pfad := "user://abstieg_meta.cfg"
const AUFRUESTUNGEN := [
	{"id": "schild", "name": "Schildgenerator", "text": "+25 Schild", "kosten": 40, "max": 8},
	{"id": "panzerung", "name": "Panzerung", "text": "+25 Hülle", "kosten": 40, "max": 8},
	{"id": "triebwerk", "name": "Triebwerk", "text": "+8 % Tempo", "kosten": 45, "max": 5},
	{"id": "raketen", "name": "Raketenschacht", "text": "+2 Raketen", "kosten": 30, "max": 6},
]

var bank := 0
var rekord := 0
var laeufe := 0
var stufen := {}
var waffen: Array = []     ## freigeschaltete Waffen-IDs, zusätzlich zu Waffen.START
var waffen_stufen := {}    ## Version je Waffe (1 = Mk I); fehlt ein Eintrag, ist es Mk I


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


func waffen_stufe(id: String) -> int:
	return int(waffen_stufen.get(id, 1))


func waffe_verbesserbar(id: String) -> bool:
	return id in waffen_frei() and waffen_stufe(id) < Waffen.MAX_STUFE \
		and bank >= Waffen.verbessern_preis(id, waffen_stufe(id))


func waffe_verbessern(id: String) -> bool:
	if not waffe_verbesserbar(id):
		return false
	bank -= Waffen.verbessern_preis(id, waffen_stufe(id))
	waffen_stufen[id] = waffen_stufe(id) + 1
	speichern()
	Protokoll.schreib("meta", "Waffe %s auf %s verbessert, Bank jetzt %d" % [id, Waffen.MK[waffen_stufe(id)], bank])
	return true


func schiffswerte() -> Dictionary:
	return {
		"schild_max": 50.0 + 25.0 * stufe("schild"),
		"huelle_max": 100.0 + 25.0 * stufe("panzerung"),
		"tempo": 14.0 * (1.0 + 0.08 * stufe("triebwerk")),
		"raketen_max": 4 + 2 * stufe("raketen"),
	}


## Neues Spiel: alles auf null, außer den Lautstärke-Einstellungen (die liegen in einer eigenen Datei).
func zuruecksetzen() -> void:
	Protokoll.schreib("meta", "Neues Spiel: vorher Bank %d, Rekord %d, Läufe %d, Stufen %s, Waffen %s" % [
		bank, rekord, laeufe, stufen, waffen])
	bank = 0
	rekord = 0
	laeufe = 0
	stufen = {}
	waffen = []
	waffen_stufen = {}
	speichern()


func laden() -> void:
	var c := ConfigFile.new()
	if c.load(_pfad) != OK:
		return
	bank = c.get_value("meta", "bank", 0)
	rekord = c.get_value("meta", "rekord", 0)
	laeufe = c.get_value("meta", "laeufe", 0)
	stufen = c.get_value("meta", "stufen", {})
	waffen = c.get_value("meta", "waffen", [])
	waffen_stufen = c.get_value("meta", "waffen_stufen", {})
	# Laserbündelung gibt es seit 2026-10-10 nicht mehr (ersetzt durch Versionen je Waffe):
	# gekaufte Stufen werden einmalig als Erz zurückgebucht.
	if stufen.has("laser"):
		var zurueck_l := 0
		for k in int(stufen.laser):
			zurueck_l += int(round(50 * pow(1.6, k)))
		bank += zurueck_l
		stufen.erase("laser")
		speichern()
		Protokoll.schreib("meta", "Laserbündelung abgeschafft: %d Erz zurückgebucht, Bank jetzt %d" % [zurueck_l, bank])
	# Energie gibt es seit 2026-10-10 nicht mehr (Stev: „macht keinen Spaß“): gekaufte Energiewandler
	# werden einmalig als Erz zurückgebucht.
	if stufen.has("energie"):
		var zurueck := 0
		for k in int(stufen.energie):
			zurueck += int(round(35 * pow(1.6, k)))
		bank += zurueck
		stufen.erase("energie")
		speichern()
		Protokoll.schreib("meta", "Energiewandler abgeschafft: %d Erz zurückgebucht, Bank jetzt %d" % [zurueck, bank])


func speichern() -> void:
	var c := ConfigFile.new()
	c.set_value("meta", "bank", bank)
	c.set_value("meta", "rekord", rekord)
	c.set_value("meta", "laeufe", laeufe)
	c.set_value("meta", "stufen", stufen)
	c.set_value("meta", "waffen", waffen)
	c.set_value("meta", "waffen_stufen", waffen_stufen)
	var e := c.save(_pfad)
	if e != OK:
		Protokoll.schreib("fehler", "Meta speichern fehlgeschlagen: %s" % error_string(e))

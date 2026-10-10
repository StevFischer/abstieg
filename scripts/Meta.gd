extends Node
## Roguelite-Fortschritt, der einen Tod überlebt: Erz in der Bank, gekaufte Aufrüstungen, Rekord.

var _pfad := "user://abstieg_meta.cfg"
## Aufrüstungen in fünf Reitern. Je Stufe wirkt "pro"; nach "max" folgt die endlose Meisterschaft
## mit "meister" je Meisterstufe (0 = keine Meisterschaft). "boss": erst nach diesem besiegten Boss kaufbar.
## Stev 2026-10-10: „viel mehr Aufwertungen für die Langzeitmotivation“ — Kampf, Überleben, Wirtschaft,
## Werkzeuge; endlose Meisterschaft; an Bosse gekoppelt; Reiter nach Art.
const REITER := [["schiff", "Schiff"], ["kampf", "Kampf"], ["ueberleben", "Überleben"],
	["wirtschaft", "Wirtschaft"], ["werkzeuge", "Werkzeuge"]]
const AUFRUESTUNGEN := [
	{"id": "schild", "art": "schiff", "name": "Schildgenerator", "text": "+25 Schild", "kosten": 40, "max": 8, "pro": 25.0, "meister": 5.0, "boss": 0},
	{"id": "panzerung", "art": "schiff", "name": "Panzerung", "text": "+25 Hülle", "kosten": 40, "max": 8, "pro": 25.0, "meister": 5.0, "boss": 0},
	{"id": "triebwerk", "art": "schiff", "name": "Triebwerk", "text": "+8 % Tempo", "kosten": 45, "max": 5, "pro": 0.08, "meister": 0.01, "boss": 0},
	{"id": "raketen", "art": "schiff", "name": "Raketenschacht", "text": "+2 Raketen", "kosten": 30, "max": 6, "pro": 2.0, "meister": 1.0, "boss": 0},
	{"id": "laserschaden", "art": "kampf", "name": "Laserverstärker", "text": "+10 % Laserschaden", "kosten": 50, "max": 8, "pro": 0.10, "meister": 0.02, "boss": 0},
	{"id": "feuerrate", "art": "kampf", "name": "Schnellkühlung", "text": "+6 % Feuerrate der Laser", "kosten": 55, "max": 6, "pro": 0.06, "meister": 0.01, "boss": 0},
	{"id": "raketenschaden", "art": "kampf", "name": "Sprengkopf", "text": "+12 % Raketenschaden", "kosten": 50, "max": 6, "pro": 0.12, "meister": 0.02, "boss": 0},
	{"id": "kritisch", "art": "kampf", "name": "Zielrechner", "text": "+4 % Chance auf doppelten Schaden", "kosten": 70, "max": 6, "pro": 0.04, "meister": 0.005, "boss": 0},
	{"id": "schildladen", "art": "ueberleben", "name": "Schildlader", "text": "+20 % Schild-Ladetempo", "kosten": 45, "max": 6, "pro": 0.20, "meister": 0.03, "boss": 0},
	{"id": "schildpause", "art": "ueberleben", "name": "Schnellstart", "text": "Schild lädt 0,4 s früher", "kosten": 50, "max": 5, "pro": 0.4, "meister": 0.0, "boss": 0},
	{"id": "reparatur", "art": "ueberleben", "name": "Reparaturdrohne", "text": "+10 Hülle zu Beginn jeder Tiefe", "kosten": 60, "max": 5, "pro": 10.0, "meister": 2.0, "boss": 0},
	{"id": "notschild", "art": "ueberleben", "name": "Notschild", "text": "einmal je Lauf: tödlicher Treffer → 1 Hülle, Schild voll", "kosten": 300, "max": 2, "pro": 1.0, "meister": 0.0, "boss": 15},
	{"id": "erzausbeute", "art": "wirtschaft", "name": "Raffinerie", "text": "+10 % Erz je Fund", "kosten": 80, "max": 8, "pro": 0.10, "meister": 0.02, "boss": 5},
	{"id": "beutechance", "art": "wirtschaft", "name": "Bergungskralle", "text": "+4 % Chance, dass Gegner Beute fallen lassen", "kosten": 70, "max": 5, "pro": 0.04, "meister": 0.005, "boss": 5},
	{"id": "magnet", "art": "wirtschaft", "name": "Erzmagnet", "text": "Beute fliegt zum Schiff: 6 m, je Stufe +3 m", "kosten": 90, "max": 3, "pro": 1.0, "meister": 0.0, "boss": 5},
	{"id": "abschluss", "art": "wirtschaft", "name": "Vertragsbonus", "text": "+15 % Abschlussbelohnung", "kosten": 80, "max": 5, "pro": 0.15, "meister": 0.03, "boss": 5},
	{"id": "nachbrenner", "art": "werkzeuge", "name": "Nachbrenner", "text": "Sprint ×2 für 1,5 s (Umschalt / X); Abklingzeit 9 s, je Stufe −1,5 s", "kosten": 120, "max": 4, "pro": 1.0, "meister": 0.0, "boss": 10},
	{"id": "fluchtzeit", "art": "werkzeuge", "name": "Kühlstäbe", "text": "+10 % Fluchtzeit nach dem Reaktor", "kosten": 60, "max": 5, "pro": 0.10, "meister": 0.02, "boss": 10},
	{"id": "radar", "art": "werkzeuge", "name": "Gegnerradar", "text": "zeigt Gegner durch Wände: 25 m, je Stufe +10 m", "kosten": 150, "max": 3, "pro": 1.0, "meister": 0.0, "boss": 10},
]

var bank := 0
var rekord := 0
var start_tiefe := 1       ## im Hangar gewählte Starttiefe: 1 oder direkt nach einem besiegten Boss
var laeufe := 0
var stufen := {}
var waffen: Array = []     ## freigeschaltete Waffen-IDs, zusätzlich zu Waffen.START
var waffen_stufen := {}    ## Version je Waffe (1 = Mk I); fehlt ein Eintrag, ist es Mk I
## Spielzeit wie bei Steam: Zeit, in der das Spiel offen ist (auch Hangar/Pause). Übersteht „Neues Spiel“.
var spielzeit := 0.0       ## Sekunden insgesamt
var spielzeit_tage := {}   ## "JJJJ-MM-TT" -> Sekunden, nur die letzten 14 Tage
var zuletzt := 0           ## Unix-Zeit, zuletzt gespielt (vor dieser Sitzung — beim Laden gemerkt)
var _letzter_tick := 0
var _seit_speichern := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # Spielzeit zählt auch in der Pause, wie bei Steam
	# Der Selbsttest schreibt in eine eigene Datei, sonst landet sein Fortschritt im echten Spielstand.
	if "--autotest" in OS.get_cmdline_user_args():
		_pfad = "user://abstieg_meta_autotest.cfg"
	laden()
	_letzter_tick = Time.get_ticks_msec()


## Echte Zeit (nicht Spieltempo) aufsummieren, alle 30 s und beim Beenden/Wegwechseln sichern.
func _process(_dt: float) -> void:
	var jetzt := Time.get_ticks_msec()
	var dt := minf((jetzt - _letzter_tick) / 1000.0, 1.0)     # Hänger/Schlaf nicht mitzählen
	_letzter_tick = jetzt
	spielzeit += dt
	var heute := Time.get_date_string_from_system()
	spielzeit_tage[heute] = float(spielzeit_tage.get(heute, 0.0)) + dt
	_seit_speichern += dt
	if _seit_speichern >= 30.0:
		speichern()


func _notification(was: int) -> void:
	if was == NOTIFICATION_WM_CLOSE_REQUEST or was == NOTIFICATION_APPLICATION_PAUSED \
			or was == NOTIFICATION_APPLICATION_FOCUS_OUT or was == NOTIFICATION_PREDELETE:
		if _pfad != "":
			speichern()
	if was == NOTIFICATION_APPLICATION_RESUMED or was == NOTIFICATION_APPLICATION_FOCUS_IN:
		_letzter_tick = Time.get_ticks_msec()


func spielzeit_text(sek: float) -> String:
	if sek < 3600.0:
		return "%d Min." % int(sek / 60.0)
	return ("%.1f" % (sek / 3600.0)).replace(".", ",") + " Std."


func spielzeit_zwei_wochen() -> float:
	var grenze := Time.get_unix_time_from_system() - 14 * 86400
	var summe := 0.0
	for tag in spielzeit_tage:
		if Time.get_unix_time_from_datetime_string(tag + "T23:59:59") >= grenze:
			summe += float(spielzeit_tage[tag])
	return summe


func zuletzt_text() -> String:
	if zuletzt == 0:
		return "noch nie"
	var tag := Time.get_date_string_from_unix_time(zuletzt)
	var heute := Time.get_date_string_from_system()
	var gestern := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400)
	if tag == heute:
		return "heute"
	if tag == gestern:
		return "gestern"
	var d := Time.get_datetime_dict_from_unix_time(zuletzt)
	return "%02d.%02d.%d" % [d.day, d.month, d.year]


func stufe(id: String) -> int:
	return int(stufen.get(id, 0))


func _def(id: String) -> Dictionary:
	for a in AUFRUESTUNGEN:
		if a.id == id:
			return a
	return {}


## Stufen über "max" sind Meisterstufen (nur wo "meister" > 0). Kosten: ×1,6 je Stufe bis zum Maximum,
## danach ×1,15 je Meisterstufe — Erz hat so immer einen Zweck, der Zuwachs bleibt klein.
func kosten(id: String) -> int:
	var a := _def(id)
	var st := stufe(id)
	var mx := int(a.max)
	if st < mx:
		return int(round(a.kosten * pow(1.6, st)))
	return int(round(a.kosten * pow(1.6, mx) * pow(1.15, st - mx)))


func meisterstufe(id: String) -> int:
	return maxi(stufe(id) - int(_def(id).max), 0)


func hat_meisterschaft(id: String) -> bool:
	return float(_def(id).meister) > 0.0


## Gesamtwirkung einer Aufrüstung: Stufen bis max × pro, darüber × meister.
func wert(id: String) -> float:
	var a := _def(id)
	return mini(stufe(id), int(a.max)) * float(a.pro) + meisterstufe(id) * float(a.meister)


## Wirkung bei einer bestimmten Stufe — für den Tooltip „jetzt → nächste Stufe“.
func wert_bei(id: String, st: int) -> float:
	var a := _def(id)
	return mini(st, int(a.max)) * float(a.pro) + maxi(st - int(a.max), 0) * float(a.meister)


## Lesbare Gesamtwirkung bei Stufe st, z. B. „+30 % Laserschaden“ oder „Radar 35 m“.
func wirkung_text(id: String, st: int) -> String:
	var w := wert_bei(id, st)
	match id:
		"schild": return "Schild %d" % int(50 + w)
		"panzerung": return "Hülle %d" % int(100 + w)
		"triebwerk": return "Tempo %.1f m/s" % (14.0 * (1.0 + w))
		"raketen": return "Raketen %d" % (4 + int(w))
		"schildpause": return "Schild lädt nach %.1f s" % (5.0 - w)
		"reparatur": return "+%d Hülle je Tiefe" % int(w)
		"notschild": return "%d Notschild je Lauf" % int(w)
		"magnet": return "kein Magnet" if st == 0 else "Magnet %d m" % (6 + 3 * (st - 1))
		"nachbrenner": return "kein Nachbrenner" if st == 0 else "Abklingzeit %.1f s" % (9.0 - 1.5 * (st - 1))
		"radar": return "kein Radar" if st == 0 else "Radar %d m" % (25 + 10 * (st - 1))
		"kritisch": return "%.1f %% Chance auf doppelten Schaden" % (w * 100.0)
		"beutechance": return "Beutechance %.1f %%" % (20.0 + w * 100.0)
	return "+%d %%" % int(round(w * 100.0))


## Freigeschaltet, wenn der nötige Boss besiegt ist (Tiefe danach erreicht).
func freigeschaltet(id: String) -> bool:
	var b := int(_def(id).boss)
	return b == 0 or rekord > b


func ausgereizt(id: String) -> bool:
	return stufe(id) >= int(_def(id).max) and not hat_meisterschaft(id)


func kaufbar(id: String) -> bool:
	return freigeschaltet(id) and not ausgereizt(id) and bank >= kosten(id)


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
		"schild_max": 50.0 + wert("schild"),
		"huelle_max": 100.0 + wert("panzerung"),
		"tempo": 14.0 * (1.0 + wert("triebwerk")),
		"raketen_max": 4 + int(wert("raketen")),
		"laser_mult": 1.0 + wert("laserschaden"),
		"feuerrate": 1.0 + wert("feuerrate"),
		"raketen_mult": 1.0 + wert("raketenschaden"),
		"krit": minf(wert("kritisch"), 0.6),
		"schild_laden": 1.0 + wert("schildladen"),
		"schild_pause": 5.0 - wert("schildpause"),
		"reparatur": wert("reparatur"),
		"notschild": int(wert("notschild")),
		"erz_mult": 1.0 + wert("erzausbeute"),
		"beute_bonus": minf(wert("beutechance"), 0.5),
		"magnet": 0.0 if stufe("magnet") == 0 else 6.0 + 3.0 * (stufe("magnet") - 1),
		"abschluss_mult": 1.0 + wert("abschluss"),
		"nachbrenner_cd": 0.0 if stufe("nachbrenner") == 0 else 9.0 - 1.5 * (stufe("nachbrenner") - 1),
		"flucht_mult": 1.0 + wert("fluchtzeit"),
		"radar": 0.0 if stufe("radar") == 0 else 25.0 + 10.0 * (stufe("radar") - 1),
	}


## Neues Spiel: alles auf null, außer den Lautstärke-Einstellungen (die liegen in einer eigenen Datei).
## Wählbare Starttiefen: 1 und jede Tiefe direkt nach einem Boss, die schon erreicht wurde
## (Tiefe 6 erreicht heißt: der Boss auf Tiefe 5 ist besiegt, sonst wäre der Reaktor nicht gefallen).
func starttiefen() -> Array[int]:
	var aus: Array[int] = [1]
	var t := 6
	while t <= rekord:
		aus.append(t)
		t += 5
	return aus


## Die gemerkte Starttiefe, falls sie (noch) wählbar ist — sonst 1.
func gueltige_starttiefe() -> int:
	return start_tiefe if start_tiefe in starttiefen() else 1


func zuruecksetzen() -> void:
	Protokoll.schreib("meta", "Neues Spiel: vorher Bank %d, Rekord %d, Läufe %d, Stufen %s, Waffen %s" % [
		bank, rekord, laeufe, stufen, waffen])
	bank = 0
	rekord = 0
	start_tiefe = 1
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
	start_tiefe = c.get_value("meta", "start_tiefe", 1)
	laeufe = c.get_value("meta", "laeufe", 0)
	stufen = c.get_value("meta", "stufen", {})
	waffen = c.get_value("meta", "waffen", [])
	waffen_stufen = c.get_value("meta", "waffen_stufen", {})
	spielzeit = c.get_value("meta", "spielzeit", 0.0)
	spielzeit_tage = c.get_value("meta", "spielzeit_tage", {})
	zuletzt = c.get_value("meta", "zuletzt", 0)
	var grenze := Time.get_unix_time_from_system() - 15 * 86400
	for tag in spielzeit_tage.keys():
		if Time.get_unix_time_from_datetime_string(tag + "T00:00:00") < grenze:
			spielzeit_tage.erase(tag)
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
	c.set_value("meta", "start_tiefe", start_tiefe)
	c.set_value("meta", "laeufe", laeufe)
	c.set_value("meta", "stufen", stufen)
	c.set_value("meta", "waffen", waffen)
	c.set_value("meta", "waffen_stufen", waffen_stufen)
	c.set_value("meta", "spielzeit", spielzeit)
	c.set_value("meta", "spielzeit_tage", spielzeit_tage)
	c.set_value("meta", "zuletzt", int(Time.get_unix_time_from_system()) if spielzeit > 0.0 else zuletzt)
	_seit_speichern = 0.0
	var e := c.save(_pfad)
	if e != OK:
		Protokoll.schreib("fehler", "Meta speichern fehlgeschlagen: %s" % error_string(e))

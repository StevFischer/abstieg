class_name Waffen
extends RefCounted
## Alle Laser und Raketen. Zwillingslaser und Zielsuchrakete hat man von Anfang an,
## der Rest wird im Hangar dauerhaft freigeschaltet. Im Flug: Laser 1–4, Raketen 5–8.
##
## Laser schießen unbegrenzt, Raketen kosten Munition (die Zahl "kosten_munition").
## "flaeche": Explosionsradius mit Schaden an allem in der Nähe (auch am eigenen Schiff).
## "splitter": beim Einschlag so viele kleine Zielsucher in alle Richtungen.

const LASER := [
	{"id": "zwilling", "name": "Zwillingslaser", "preis": 0, "text": "zwei Läufe im Wechsel",
		"cd": 0.14, "schaden": 12.0, "tempo": 90.0, "anzahl": 1, "streuung": 0.0,
		"farbe": Color(1.0, 0.3, 0.2), "groesse": 1.0, "ton": "laser", "tonhoehe": 1.0, "db": -9.0},
	{"id": "streu", "name": "Streufeuer", "preis": 120, "text": "drei Bolzen im Fächer",
		"cd": 0.22, "schaden": 9.0, "tempo": 80.0, "anzahl": 3, "streuung": 6.0,
		"farbe": Color(0.35, 1.0, 0.35), "groesse": 1.0, "ton": "laser", "tonhoehe": 0.85, "db": -8.0},
	{"id": "vulkan", "name": "Vulkan", "preis": 150, "text": "sehr schnelles Dauerfeuer",
		"cd": 0.055, "schaden": 5.0, "tempo": 110.0, "anzahl": 1, "streuung": 1.5,
		"farbe": Color(1.0, 0.9, 0.3), "groesse": 0.7, "ton": "laser", "tonhoehe": 1.45, "db": -15.0},
	{"id": "plasma", "name": "Plasma", "preis": 180, "text": "langsame, schwere Kugeln",
		"cd": 0.42, "schaden": 40.0, "tempo": 45.0, "anzahl": 1, "streuung": 0.0,
		"farbe": Color(0.3, 0.8, 1.0), "groesse": 1.7, "ton": "laser_gegner", "tonhoehe": 0.6, "db": -4.0},
]

const RAKETEN := [
	{"id": "zielsuch", "name": "Zielsuchrakete", "preis": 0, "text": "folgt dem nächsten Ziel",
		"cd": 0.6, "kosten_munition": 1, "schaden": 70.0, "tempo": 34.0, "lenkung": 2.5, "anzahl": 1,
		"streuung": 0.0, "flaeche": 0.0, "splitter": 0, "farbe": Color(1.0, 0.75, 0.3), "groesse": 1.6},
	{"id": "streu_r", "name": "Streurakete", "preis": 100, "text": "drei ungelenkte auf einmal",
		"cd": 0.7, "kosten_munition": 1, "schaden": 40.0, "tempo": 42.0, "lenkung": 0.0, "anzahl": 3,
		"streuung": 8.0, "flaeche": 0.0, "splitter": 0, "farbe": Color(1.0, 0.55, 0.2), "groesse": 1.3},
	{"id": "smart", "name": "Smart-Rakete", "preis": 160, "text": "zerplatzt in 5 Zielsucher",
		"cd": 0.9, "kosten_munition": 2, "schaden": 50.0, "tempo": 30.0, "lenkung": 0.0, "anzahl": 1,
		"streuung": 0.0, "flaeche": 0.0, "splitter": 5, "farbe": Color(0.6, 1.0, 0.4), "groesse": 1.8},
	{"id": "mega", "name": "Mega-Rakete", "preis": 220, "text": "riesige Explosion, Abstand halten",
		"cd": 1.4, "kosten_munition": 3, "schaden": 150.0, "tempo": 22.0, "lenkung": 0.0, "anzahl": 1,
		"streuung": 0.0, "flaeche": 11.0, "splitter": 0, "farbe": Color(1.0, 0.3, 0.9), "groesse": 2.0},
]

const START := ["zwilling", "zielsuch"]
## Versionen: wer eine Waffe besitzt, kann sie im Hangar bis Mk V verbessern, je Stufe +30 % Schaden.
const MAX_STUFE := 5
const MK := ["", "Mk I", "Mk II", "Mk III", "Mk IV", "Mk V"]


static func schaden_faktor(stufe: int) -> float:
	return 1.0 + 0.3 * (maxi(stufe, 1) - 1)


## Preis für die nächste Version (von stufe auf stufe + 1).
static func verbessern_preis(id: String, stufe: int) -> int:
	var basis := maxf(60.0, float(finde(id).preis) * 0.6)
	return int(round(basis * pow(1.6, stufe - 1)))


static func finde(id: String) -> Dictionary:
	for w in LASER + RAKETEN:
		if w.id == id:
			return w
	return {}


static func ist_laser(id: String) -> bool:
	for w in LASER:
		if w.id == id:
			return true
	return false

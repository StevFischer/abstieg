class_name Module
extends RefCounted
## Ausrüstung als Beute (Stev 2026-10-10, Vorschlag „Beute mit Seltenheit wie Diablo“):
## Gegner und Bosse lassen Module fallen. Vier Steckplätze, fünf Seltenheiten, zufällige Eigenschaften,
## deren Stärke mit Seltenheit und Fundtiefe wächst. Legendäre haben zusätzlich einen Spezialeffekt.
## Ein Modul ist ein Dictionary {platz, selten, stufe, eig: [{id, wert}], spezial} — so speichert es
## ConfigFile ohne eigene Klasse.

const PLAETZE := {
	"laser": {"name": "Laserlinse", "endung": "e", "symbol": "zwilling"},
	"schild": {"name": "Schildkern", "endung": "er", "symbol": "auf_schild"},
	"triebwerk": {"name": "Triebwerksdüse", "endung": "e", "symbol": "auf_triebwerk"},
	"rumpf": {"name": "Rumpfplatte", "endung": "e", "symbol": "auf_panzerung"},
}
const PLATZ_REIHE := ["laser", "schild", "triebwerk", "rumpf"]
## Seltenheit: Anzahl Eigenschaften, Stärkefaktor, Fundgewicht
const SELTEN := [
	{"name": "Gewöhnlich", "stamm": "Gewöhnlich", "farbe": Color(0.75, 0.75, 0.75), "eig": 1, "faktor": 1.0, "gewicht": 55.0, "bauteile": 1},
	{"name": "Ungewöhnlich", "stamm": "Ungewöhnlich", "farbe": Color(0.35, 0.95, 0.4), "eig": 2, "faktor": 1.3, "gewicht": 28.0, "bauteile": 2},
	{"name": "Selten", "stamm": "Selten", "farbe": Color(0.3, 0.6, 1.0), "eig": 2, "faktor": 1.7, "gewicht": 12.0, "bauteile": 4},
	{"name": "Episch", "stamm": "Episch", "farbe": Color(0.75, 0.4, 1.0), "eig": 3, "faktor": 2.2, "gewicht": 4.0, "bauteile": 8},
	{"name": "Legendär", "stamm": "Legendär", "farbe": Color(1.0, 0.6, 0.15), "eig": 3, "faktor": 2.8, "gewicht": 1.0, "bauteile": 15},
]
## Eigenschaften je Platz: Grundwert bei Gewöhnlich auf Tiefe 1; "art": prozent (×100 angezeigt) oder zahl
const EIG := {
	"laser_mult": {"text": "+%s %% Laserschaden", "basis": 0.06, "art": "prozent", "plaetze": ["laser"]},
	"feuerrate": {"text": "+%s %% Feuerrate", "basis": 0.04, "art": "prozent", "plaetze": ["laser"]},
	"krit": {"text": "+%s %% doppelter Schaden", "basis": 0.02, "art": "prozent", "plaetze": ["laser"]},
	"raketen_mult": {"text": "+%s %% Raketenschaden", "basis": 0.06, "art": "prozent", "plaetze": ["laser", "triebwerk"]},
	"schild_max": {"text": "+%s Schild", "basis": 8.0, "art": "zahl", "plaetze": ["schild", "rumpf"]},
	"schild_laden": {"text": "+%s %% Schild-Ladetempo", "basis": 0.08, "art": "prozent", "plaetze": ["schild"]},
	"schild_pause": {"text": "Schild lädt %s s früher", "basis": 0.15, "art": "sekunden", "plaetze": ["schild"]},
	"huelle_max": {"text": "+%s Hülle", "basis": 9.0, "art": "zahl", "plaetze": ["schild", "rumpf"]},
	"tempo": {"text": "+%s %% Tempo", "basis": 0.03, "art": "prozent", "plaetze": ["triebwerk"]},
	"erz_mult": {"text": "+%s %% Erz", "basis": 0.04, "art": "prozent", "plaetze": ["triebwerk", "rumpf"]},
	"raketen": {"text": "+%s Raketen", "basis": 0.8, "art": "ganz", "plaetze": ["rumpf"]},
}
## Legendärer Spezialeffekt je Platz
const SPEZIAL := {
	"laser": {"id": "durchschlag", "text": "Laserbolzen durchschlagen einen Gegner mehr"},
	"schild": {"id": "notschild", "text": "+1 Notschild je Lauf"},
	"triebwerk": {"id": "sprint", "text": "+12 % Tempo zusätzlich"},
	"rumpf": {"id": "magnet", "text": "Erzmagnet +4 m"},
}
const INVENTAR_MAX := 24


## Seltenheit würfeln; boss = mindestens Selten und zweimal würfeln, das Bessere zählt.
static func seltenheit_wuerfeln(rng: RandomNumberGenerator, boss: bool) -> int:
	var summe := 0.0
	for s in SELTEN:
		summe += s.gewicht
	var beste := 0
	for wurf in (2 if boss else 1):
		var x := rng.randf() * summe
		var i := 0
		while i < SELTEN.size() - 1 and x > SELTEN[i].gewicht:
			x -= SELTEN[i].gewicht
			i += 1
		beste = maxi(beste, i)
	return maxi(beste, 2) if boss else beste


static func erzeugen(rng: RandomNumberGenerator, tiefe: int, boss := false, p_platz := "") -> Dictionary:
	var platz: String = p_platz if p_platz != "" else PLATZ_REIHE[rng.randi_range(0, 3)]
	var selten := seltenheit_wuerfeln(rng, boss)
	var moegliche: Array = []
	for id in EIG:
		if platz in EIG[id].plaetze:
			moegliche.append(id)
	moegliche.shuffle()
	var eig := []
	var tiefen_faktor := 1.0 + 0.04 * (tiefe - 1)
	for k in mini(int(SELTEN[selten].eig), moegliche.size()):
		var id: String = moegliche[k]
		var wert: float = EIG[id].basis * SELTEN[selten].faktor * tiefen_faktor * rng.randf_range(0.85, 1.15)
		eig.append({"id": id, "wert": wert})
	return {"platz": platz, "selten": selten, "stufe": tiefe, "eig": eig,
		"spezial": SPEZIAL[platz].id if selten == 4 else ""}


static func name_von(m: Dictionary) -> String:
	var p: Dictionary = PLAETZE[m.platz]
	return "%s%s %s" % [SELTEN[m.selten].stamm, p.endung, p.name]


static func farbe(m: Dictionary) -> Color:
	return SELTEN[m.selten].farbe


static func eig_text(e: Dictionary) -> String:
	var d: Dictionary = EIG[e.id]
	var w: float = e.wert
	match d.art:
		"prozent":
			return d.text % ("%.1f" % (w * 100.0)).replace(".", ",")
		"sekunden":
			return d.text % ("%.2f" % w).replace(".", ",")
		"ganz":
			return d.text % str(maxi(int(round(w)), 1))
	return d.text % str(int(round(w)))


## Zwei Zeilen für Infofeld und Tooltip: Name (Fundtiefe), dann die Eigenschaften.
static func beschreibung(m: Dictionary) -> String:
	var teile: Array[String] = []
	for e in m.eig:
		teile.append(eig_text(e))
	if m.spezial != "":
		teile.append("★ " + SPEZIAL[m.platz].text)
	return "%s  (Fundtiefe %d)\n%s" % [name_von(m), m.stufe, "   ·   ".join(teile)]


static func bauteile_wert(m: Dictionary) -> int:
	return int(SELTEN[m.selten].bauteile) + int(m.stufe) / 5


## Summe aller eingebauten Module: {eigenschaft: wert} plus Spezialeffekte als Zähler.
static func wirkung(eingebaut: Dictionary) -> Dictionary:
	var aus := {}
	for platz in eingebaut:
		var m: Dictionary = eingebaut[platz]
		for e in m.eig:
			var w: float = e.wert
			if EIG[e.id].art == "ganz":
				w = maxf(round(w), 1.0)
			aus[e.id] = aus.get(e.id, 0.0) + w
		if m.spezial != "":
			aus["spezial_" + m.spezial] = aus.get("spezial_" + m.spezial, 0.0) + 1.0
	return aus


## Grober Vergleichswert (Summe der Stärke), um beim vollen Inventar das schwächste zu finden.
static func staerke(m: Dictionary) -> float:
	return float(m.selten) * 10.0 + float(m.stufe) * 0.1

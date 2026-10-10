class_name LevelGen
extends RefCounted
## Erzeugt eine Mine aus Würfelzellen der Kantenlänge ZELLE: Räume, verbunden durch
## Stollen und Schächte, als Baum mit gelegentlichen Kreuzungen.
## Reine Daten, kein Knoten — damit läuft der Generator auch im Test ohne Szene.
##
## Zelle c hat ihren Mittelpunkt bei c * ZELLE und reicht ZELLE/2 in jede Richtung.

const ZELLE := 6.0
const BOSS_RAUM := Vector3i(5, 3, 5)
const RICHTUNGEN: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
## Waagerechte Richtungen doppelt, damit Schächte seltener sind als Stollen.
const ZUG_RICHTUNGEN: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0)]

var zellen: Dictionary = {}          ## Vector3i -> Raumindex, -1 = Stollen
var raeume: Array[Dictionary] = []   ## pos, groesse, eltern, stufe (Abstand zum Start im Raumbaum), tunnel
var start_raum := 0
var reaktor_raum := 0
var saat := 0
var tiefe := 1
var rng := RandomNumberGenerator.new()


func erzeuge(p_saat: int, p_tiefe: int) -> void:
	saat = p_saat
	tiefe = p_tiefe
	rng.seed = p_saat
	zellen.clear()
	raeume.clear()
	# Die Mine wächst mit der Tiefe, bis zu einer Obergrenze — schwerer wird es danach über die Gegner.
	var ziel := mini(6 + p_tiefe, 24)
	_raum_setzen(Vector3i.ZERO, Vector3i(3, 2, 3), -1, [])
	var versuche := 0
	while raeume.size() < ziel and versuche < 4000:
		versuche += 1
		_anbauen()
	_reaktor_waehlen()
	if ist_boss_tiefe(p_tiefe):
		# Großer Bossraum am tiefsten Punkt des Baums: dort steht der Reaktor mit seinem Wächter.
		var tiefster := reaktor_raum
		for i in 600:
			var quelle := tiefster if i < 300 else rng.randi_range(0, raeume.size() - 1)
			if _anbauen(BOSS_RAUM, quelle):
				reaktor_raum = raeume.size() - 1
				break
	_saeulen()


func _anbauen(fest := Vector3i.ZERO, quelle := -1) -> bool:
	var qi := quelle if quelle >= 0 else rng.randi_range(0, raeume.size() - 1)
	var r1: Vector3i = ZUG_RICHTUNGEN[rng.randi_range(0, ZUG_RICHTUNGEN.size() - 1)]
	var weg: Array[Vector3i] = []
	var p := _randzelle(raeume[qi], r1)
	for i in rng.randi_range(2, 6):
		p += r1
		weg.append(p)
	var r_ende := r1
	if rng.randf() < 0.45:
		var r2 := _senkrecht(r1)
		for i in rng.randi_range(2, 5):
			p += r2
			weg.append(p)
		r_ende = r2
	var groesse := Vector3i(rng.randi_range(2, 4), rng.randi_range(1, 3), rng.randi_range(2, 4))
	var wurf := rng.randf()
	if wurf < 0.12:
		groesse = Vector3i(rng.randi_range(4, 6), rng.randi_range(3, 4), rng.randi_range(4, 6))
	elif wurf < 0.28:
		# Halle: bis 48 × 30 × 48 m, bekommt später Felssäulen als Deckung
		groesse = Vector3i(rng.randi_range(5, 8), rng.randi_range(3, 5), rng.randi_range(5, 8))
	if fest != Vector3i.ZERO:
		groesse = fest
	var ein := p + r_ende
	var pos := Vector3i.ZERO
	for a in 3:
		if r_ende[a] > 0:
			pos[a] = ein[a]
		elif r_ende[a] < 0:
			pos[a] = ein[a] - groesse[a] + 1
		else:
			pos[a] = ein[a] - rng.randi_range(0, groesse[a] - 1)
	# Ein Stollen darf fremde Stollen kreuzen, aber keinen Raum durchstoßen.
	for z in weg:
		if zellen.has(z) and zellen[z] >= 0:
			return false
	# Der neue Raum samt einer Zelle Rand muss frei sein.
	for x in range(pos.x - 1, pos.x + groesse.x + 1):
		for y in range(pos.y - 1, pos.y + groesse.y + 1):
			for z in range(pos.z - 1, pos.z + groesse.z + 1):
				if zellen.has(Vector3i(x, y, z)):
					return false
	_raum_setzen(pos, groesse, qi, weg)
	return true


func _raum_setzen(pos: Vector3i, groesse: Vector3i, eltern: int, weg: Array[Vector3i]) -> void:
	var idx := raeume.size()
	var stufe := 0 if eltern < 0 else int(raeume[eltern].stufe) + 1
	raeume.append({"pos": pos, "groesse": groesse, "eltern": eltern, "stufe": stufe, "tunnel": weg})
	for z in weg:
		if not zellen.has(z):
			zellen[z] = -1
	for x in range(pos.x, pos.x + groesse.x):
		for y in range(pos.y, pos.y + groesse.y):
			for z in range(pos.z, pos.z + groesse.z):
				zellen[Vector3i(x, y, z)] = idx


func _randzelle(raum: Dictionary, r: Vector3i) -> Vector3i:
	var pos: Vector3i = raum.pos
	var g: Vector3i = raum.groesse
	var c := Vector3i.ZERO
	for a in 3:
		if r[a] > 0:
			c[a] = pos[a] + g[a] - 1
		elif r[a] < 0:
			c[a] = pos[a]
		else:
			c[a] = pos[a] + rng.randi_range(0, g[a] - 1)
	return c


func _senkrecht(r: Vector3i) -> Vector3i:
	var kandidaten: Array[Vector3i] = []
	for d in RICHTUNGEN:
		if d == r or d == -r:
			continue
		# Aus einem Schacht geht es waagerecht weiter; aus einem Stollen meist auch.
		if d.y != 0 and (r.y != 0 or rng.randf() < 0.7):
			continue
		kandidaten.append(d)
	return kandidaten[rng.randi_range(0, kandidaten.size() - 1)]


func _reaktor_waehlen() -> void:
	start_raum = 0
	var beste := -1
	var beste_wert := -1.0
	for i in range(1, raeume.size()):
		var r := raeume[i]
		# Am tiefsten im Baum, hohe Räume bevorzugt — der Reaktor ist fünf Meter hoch.
		var wert := float(r.stufe) * 10.0 + (3.0 if r.groesse.y >= 2 else 0.0) + rng.randf()
		if wert > beste_wert:
			beste_wert = wert
			beste = i
	reaktor_raum = maxi(beste, 0)


## Felssäulen in großen Hallen: jede dritte Zelle im Inneren (zwei Zellen Abstand zur Wand,
## damit die Stolleneingänge frei bleiben) über die ganze Höhe zurück zu Fels.
func _saeulen() -> void:
	for i in raeume.size():
		var r := raeume[i]
		if i == start_raum or i == reaktor_raum or r.groesse.x < 5 or r.groesse.z < 5:
			continue
		for x in range(r.pos.x + 2, r.pos.x + r.groesse.x - 2, 3):
			for z in range(r.pos.z + 2, r.pos.z + r.groesse.z - 2, 3):
				# kein Schacht darf genau hier in Decke oder Boden münden
				if zellen.has(Vector3i(x, r.pos.y + r.groesse.y, z)) or zellen.has(Vector3i(x, r.pos.y - 1, z)):
					continue
				for y in range(r.pos.y, r.pos.y + r.groesse.y):
					var c := Vector3i(x, y, z)
					if zellen.get(c, -2) == i:
						zellen.erase(c)


# --- Abfragen -------------------------------------------------------------

static func ist_boss_tiefe(t: int) -> bool:
	return t % 5 == 0

func mitte(i: int) -> Vector3:
	var r := raeume[i]
	return (Vector3(r.pos) + (Vector3(r.groesse) - Vector3.ONE) * 0.5) * ZELLE


func mittelzelle(i: int) -> Vector3i:
	var r := raeume[i]
	return r.pos + r.groesse / 2


func zellen_von_raum(i: int) -> Array[Vector3i]:
	var r := raeume[i]
	var aus: Array[Vector3i] = []
	for x in range(r.pos.x, r.pos.x + r.groesse.x):
		for y in range(r.pos.y, r.pos.y + r.groesse.y):
			for z in range(r.pos.z, r.pos.z + r.groesse.z):
				if zellen.has(Vector3i(x, y, z)):     # Säulen auslassen
					aus.append(Vector3i(x, y, z))
	return aus


static func welt_von(z: Vector3i) -> Vector3:
	return Vector3(z) * ZELLE


static func zelle_von(welt: Vector3) -> Vector3i:
	return Vector3i((welt / ZELLE).round())


## Die befahrbare Zelle, in der ein Punkt liegt — oder die nächste daneben,
## falls er wegen der Felszacken knapp jenseits einer Zellgrenze liegt.
func naechste_zelle(welt: Vector3) -> Vector3i:
	var z := zelle_von(welt)
	if zellen.has(z):
		return z
	var beste := z
	var beste_d := INF
	for x in range(-1, 2):
		for y in range(-1, 2):
			for w in range(-1, 2):
				var k := z + Vector3i(x, y, w)
				if zellen.has(k):
					var d := welt.distance_squared_to(welt_von(k))
					if d < beste_d:
						beste_d = d
						beste = k
	return beste


## Kürzester Weg durch befahrbare Zellen (Breitensuche). Leer, wenn keiner existiert.
func pfad(von: Vector3i, nach: Vector3i) -> Array[Vector3i]:
	var aus: Array[Vector3i] = []
	if not zellen.has(von) or not zellen.has(nach):
		return aus
	var herkunft := {von: von}
	var schlange: Array[Vector3i] = [von]
	var kopf := 0
	while kopf < schlange.size():
		var c := schlange[kopf]
		kopf += 1
		if c == nach:
			break
		for d in RICHTUNGEN:
			var n := c + d
			if zellen.has(n) and not herkunft.has(n):
				herkunft[n] = c
				schlange.append(n)
	if not herkunft.has(nach):
		return aus
	var c := nach
	while c != von:
		aus.append(c)
		c = herkunft[c]
	aus.append(von)
	aus.reverse()
	return aus


func erreichbare(von: Vector3i) -> Dictionary:
	var gesehen := {von: true}
	var schlange: Array[Vector3i] = [von]
	var kopf := 0
	while kopf < schlange.size():
		var c := schlange[kopf]
		kopf += 1
		for d in RICHTUNGEN:
			var n := c + d
			if zellen.has(n) and not gesehen.has(n):
				gesehen[n] = true
				schlange.append(n)
	return gesehen


## Zeit für die Flucht nach der Reaktorzerstörung.
## Gemessen an Stevs Läufen (2026-10-10): er fliegt die Strecke mit knapp 10 m/s und brauchte
## damals nur ein Drittel der Zeit. Jetzt: 6 s Anlauf + Weg mit 6 m/s (knapp doppelte Flugzeit
## als Puffer für Kampf und Umwege), mit jeder Tiefe 1,5 % knapper, höchstens 30 %.
func fluchtzeit() -> float:
	var weg := maxi(pfad(mittelzelle(reaktor_raum), mittelzelle(start_raum)).size() - 1, 0) * ZELLE
	var knapp := maxf(0.7, 1.0 - 0.015 * (tiefe - 1))
	return (6.0 + weg / 6.0) * knapp


func fingerabdruck() -> int:
	return hash(str(zellen.keys()))

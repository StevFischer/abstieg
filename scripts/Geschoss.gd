class_name Geschoss
extends Node3D
## Laserbolzen und Raketen. Treffer per Strahl von der alten zur neuen Lage —
## so fliegt auch ein schnelles Geschoss nicht durch eine dünne Wand.

const EBENE_WELT := 1
const EBENE_SPIELER := 2
const EBENE_GEGNER := 4

var geschw := Vector3.ZERO
var schaden := 10.0
var vom_spieler := true
var lebenszeit := 3.0
var lenkung := 0.0        ## > 0: Zielsuchrakete, Wendigkeit je Sekunde
var farbe := Color.RED
var knall := -1.0         ## Explosionsgröße beim Einschlag; < 0: nach Art (Laser klein, Rakete mittel)
var flaeche := 0.0        ## > 0: Flächenschaden in diesem Radius, nimmt nach außen ab (trifft auch das eigene Schiff)
var splitter := 0         ## > 0: beim Einschlag so viele kleine Zielsucher
var rundum := false       ## Zielsuche in alle Richtungen (Splitter), sonst nur nach vorn
var wirkung := ""         ## Gegnerschüsse: "netz" (bremst) oder "emp" (nur Schild, Laden gesperrt) — Schiff.sonder_treffer
var _ziel: Node3D
## Forschung (nur Spielerlaser): durchschlagen / abprallen / Kettenblitz
var durchschlag := 0
var abprall := 0
var kette := false
static var ketten_zaehler := 0
const KETTE_JEDER := 8
const KETTE_WEITE := 12.0
var _ausgenommen: Array[RID] = []


static func neu(pos: Vector3, richtung: Vector3, tempo: float, p_schaden: float, p_vom_spieler: bool,
		p_farbe: Color, p_lenkung := 0.0, groesse := 1.0, art := "") -> Geschoss:
	var g := Geschoss.new()
	g.position = pos
	g.geschw = richtung.normalized() * tempo
	g.schaden = p_schaden
	g.vom_spieler = p_vom_spieler
	g.farbe = p_farbe
	g.lenkung = p_lenkung
	if p_lenkung > 0.0 or tempo < 40.0:
		g.lebenszeit = 6.0      # Raketen und langsame Gegnerschüsse brauchen länger für dieselbe Strecke
	Optik.geschoss(g, art, p_farbe, groesse, p_vom_spieler)     # Aussehen je Waffe (Optik.gd)
	var l := OmniLight3D.new()
	l.light_color = p_farbe
	l.omni_range = 4.0 * groesse
	l.light_energy = 0.35 if p_vom_spieler else 0.8
	g.add_child(l)
	return g


func _ready() -> void:
	if vom_spieler:
		add_to_group("spieler_geschoss")      # Gegner sehen sie kommen und weichen aus
	_ausrichten()


func _physics_process(dt: float) -> void:
	lebenszeit -= dt
	if lebenszeit <= 0.0:
		queue_free()
		return
	if lenkung > 0.0:
		_lenken(dt)
	var von := global_position
	var nach := von + geschw * dt
	var maske := EBENE_WELT | (EBENE_GEGNER if vom_spieler else EBENE_SPIELER)
	var q := PhysicsRayQueryParameters3D.create(von, nach, maske)
	q.exclude = _ausgenommen
	var treffer := get_world_3d().direct_space_state.intersect_ray(q)
	if not treffer.is_empty():
		var obj: Object = treffer.collider
		var ist_ziel := obj != null and (obj.has_method("treffer_von") or obj.has_method("treffer"))
		# Abpraller: von der Wand zurück statt zerplatzen
		if not ist_ziel and abprall > 0:
			abprall -= 1
			geschw = geschw.bounce(treffer.normal)
			global_position = treffer.position + treffer.normal * 0.05
			Effekte.explosion(get_parent(), treffer.position, farbe, 0.4)
			_ausrichten()
			return
		if ist_ziel and kette:
			_kettenblitz(obj)
		# Durchschlag: Schaden machen, den Gegner ausnehmen und weiterfliegen
		if ist_ziel and durchschlag > 0 and flaeche <= 0.0:
			durchschlag -= 1
			if obj.has_method("treffer_von"):
				obj.treffer_von(schaden, geschw)
			else:
				obj.treffer(schaden)
			Effekte.explosion(get_parent(), treffer.position, farbe, 0.5)
			_ausgenommen.append(treffer.rid)
			global_position = treffer.position
			return
		if obj != null and flaeche <= 0.0:
			if wirkung != "" and obj.has_method("sonder_treffer"):
				obj.sonder_treffer(wirkung, schaden)
			elif obj.has_method("treffer_von"):
				obj.treffer_von(schaden, geschw)
			elif obj.has_method("treffer"):
				obj.treffer(schaden)
		var groesse := knall if knall > 0.0 else (4.0 if lenkung > 0.0 else 0.7)
		Effekte.explosion(get_parent(), treffer.position, farbe, groesse)
		if flaeche > 0.0:
			_flaechenschaden(treffer.position)
		if splitter > 0:
			_zersplittern(treffer.position, treffer.normal)
		queue_free()
		return
	global_position = nach
	_ausrichten()


## Jeder KETTE_JEDER-te Treffer springt mit halbem Schaden auf den nächsten anderen Gegner.
func _kettenblitz(getroffen: Object) -> void:
	ketten_zaehler += 1
	if ketten_zaehler % KETTE_JEDER != 0:
		return
	var bestes: Node3D = null
	var best_d := KETTE_WEITE
	for z in get_tree().get_nodes_in_group("gegner"):
		if z == getroffen:
			continue
		var d: float = z.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			bestes = z
	if bestes == null:
		return
	bestes.treffer(schaden * 0.5)
	# sichtbarer Sprung: kleine Blitze entlang der Linie
	for i in 4:
		Effekte.explosion(get_parent(), global_position.lerp(bestes.global_position, (i + 1) / 4.0), Color(0.6, 0.85, 1.0), 0.5)


func _flaechenschaden(mitte: Vector3) -> void:
	var opfer := get_tree().get_nodes_in_group("ziele") + get_tree().get_nodes_in_group("minen") \
		+ get_tree().get_nodes_in_group("spieler")
	for o in opfer:
		var d: float = o.global_position.distance_to(mitte)
		if d < flaeche and o.has_method("treffer"):
			o.treffer(schaden * (1.0 - d / flaeche * 0.7))


func _zersplittern(mitte: Vector3, normale: Vector3) -> void:
	for i in splitter:
		# enger Fächer weg von der Einschlagstelle; langsam und sehr wendig (Wendekreis ~2 m),
		# sonst prallen sie in einem 6 m hohen Raum gegen die Wand, bevor sie umdrehen
		var r := (normale + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 1.2).normalized()
		var g := Geschoss.neu(mitte + normale * 0.6, r, 20.0, schaden * 0.4, true, farbe, 10.0, 0.9, "mini")
		g.lebenszeit = 4.0
		g.rundum = true
		get_parent().add_child.call_deferred(g)


func _ausrichten() -> void:
	if geschw.length_squared() < 0.01:
		return
	var vor := geschw.normalized()
	var oben := Vector3.UP if absf(vor.y) < 0.95 else Vector3.FORWARD
	global_basis = Basis.looking_at(vor, oben)


func _lenken(dt: float) -> void:
	if _ziel == null or not is_instance_valid(_ziel) or not _ziel.is_in_group("ziele"):
		_ziel = null
		var beste := 70.0
		var vor := geschw.normalized()
		for z in get_tree().get_nodes_in_group("ziele"):
			var weg: Vector3 = z.global_position - global_position
			var d := weg.length()
			if d < beste and (rundum or vor.dot(weg / maxf(d, 0.01)) > 0.4):
				beste = d
				_ziel = z
	if _ziel == null:
		return
	var soll := (_ziel.global_position - global_position).normalized()
	var tempo := geschw.length()
	geschw = geschw.normalized().lerp(soll, clampf(lenkung * dt, 0.0, 1.0)).normalized() * tempo

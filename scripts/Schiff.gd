class_name Schiff
extends CharacterBody3D
## Das Spielerschiff: sechs Freiheitsgrade, Maus dreht direkt, das Schiff gleitet nach.

signal gestorben
signal getroffen(schaden: float)
signal erz_gefunden(menge: int)
signal aufgenommen(art: String, menge: int)   ## für die HUD-Meldung
signal voll(art: String)                       ## berührt, aber nicht gebraucht
signal waffe_gewechselt(name: String)
signal notschild_ausgeloest

const MAUS := 0.0022
const PAD_DREH := 2.0          ## Höchstdrehung mit dem Stick (rad/s); vorher 2,6 — Stev: Zielen mit Controller zu schwer
const PAD_KURVE := 1.5         ## Stick-Kennlinie: kleine Ausschläge drehen fein, voller Ausschlag voll
const KLEBEN_WINKEL := 6.0     ## Gegner so nah am Fadenkreuz (Grad): Drehung bremst …
const KLEBEN_FAKTOR := 0.45    ## … auf diesen Anteil
const MAGNET_WINKEL := 5.0     ## Laser lenken auf einen Gegner, der so nah am Fadenkreuz liegt
const ROLL := 2.2
const AUTOPILOT_TEMPO := 12.0
## Schild lädt sich von selbst auf, aber erst nach einer Pause ohne Treffer — und langsam:
## 1,5 je Sekunde im Flug, dreimal so schnell, wenn das Schiff steht (unter STILLSTAND m/s).
## Ein Treffer setzt die Pause zurück.
const SCHILD_PAUSE := 5.0
const SCHILD_LADEN := 1.5
const SCHILD_STEHEND := 3.0
const STILLSTAND := 2.0

var schild_max := 100.0
var schild := 100.0
## Hülle: nimmt erst Schaden, wenn der Schild leer ist, und lädt sich NICHT selbst auf —
## nur Reparatur-Fundstücke und der Tiefenwechsel bringen sie zurück.
var huelle_max := 100.0
var huelle := 100.0
var raketen_max := 4
var raketen := 4
var waffen_stufen := {}     ## Version je Waffe aus dem Hangar (1 = Mk I)
var tempo := 14.0
var welt: Node3D            ## Hier landen die Geschosse — das aktuelle Level.
var aktiv := true
var unverwundbar := false
var autopilot: Array[Vector3] = []   ## Nur für den Selbsttest: Wegpunkte abfliegen.
var waffen_frei: Array = Waffen.START.duplicate()   ## freigeschaltete Waffen-IDs (aus dem Hangar)
var laser_wahl := "zwilling"
var rakete_wahl := "zielsuch"

var kamera: Camera3D
var scheinwerfer: SpotLight3D
var _maus := Vector2.ZERO
var _laser_cd := 0.0
var _raketen_cd := 0.0
var _seite := 1.0
var _seit_treffer := 0.0
## Neue Gegner (2026-10-10): Netz bremst, Störsender sperrt das Schildladen, Greifer zieht.
signal behindert(text: String)
const NETZ_DAUER := 2.0
const NETZ_BREMSE := 0.35
const EMP_DAUER := 3.0
var netz_t := 0.0
var emp_t := 0.0
var _zug := Vector3.ZERO
## Aufrüstungen aus dem Hangar (Meta.schiffswerte), Grundwerte = ohne Aufrüstung.
var laser_mult := 1.0
var feuerrate := 1.0
var raketen_mult := 1.0
var krit := 0.0
var schild_laden_mult := 1.0
var schild_pause := SCHILD_PAUSE
var notschild := 0              ## übrige Notschilde in diesem Lauf
var erz_mult := 1.0
var magnet := 0.0               ## Reichweite des Erzmagneten in m, 0 = keiner
var nachbrenner_cd := 0.0       ## Abklingzeit, 0 = kein Nachbrenner
var notfall_cd := 0.0           ## Notfallschild: Abklingzeit (s), 0 = nicht gekauft
var notfall_rest := 0.0         ## bis wieder bereit; läuft über Tiefen hinweg
signal notfall_ausgeloest
var nachbrenner_bereit := 0.0   ## Restzeit bis zum nächsten Nachbrenner
var durchschlag_extra := 0      ## legendäre Laserlinse
signal modul_gefunden(m: Dictionary)
signal kristall_gefunden(menge: int)
var _boost := 0.0
## Forschung (Meta.erforscht), beim Laufstart gesetzt
var f := {}                     ## id -> true für erforschte Knoten
var tarn_t := 0.0               ## Tarnstart: Restzeit, in der Gegner das Schiff nicht sehen
var _ueberladung_t := 0.0
var _schock_cd := 0.0
var schaden_faktor := 1.0       ## Pakt „Glaskanone“: 2
var schild_laedt := true        ## Pakt „Kein Schildladen“: false
const NACHBRENNER_DAUER := 1.5
const NACHBRENNER_FAKTOR := 2.0
var pad_aktiv := false          ## zuletzt mit dem Gamepad gesteuert → Zielhilfe an; Maus schaltet sie aus


func _init() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1 | 4
	var form := CollisionShape3D.new()
	var kugel := SphereShape3D.new()
	kugel.radius = 0.9
	form.shape = kugel
	add_child(form)
	kamera = Camera3D.new()
	kamera.fov = 85.0
	kamera.near = 0.05
	kamera.far = 500.0
	add_child(kamera)
	scheinwerfer = SpotLight3D.new()
	scheinwerfer.spot_range = 38.0
	scheinwerfer.spot_angle = 32.0
	scheinwerfer.light_energy = 2.4
	scheinwerfer.position = Vector3(0, -0.2, 0)
	add_child(scheinwerfer)
	add_to_group("spieler")


func werte_setzen(w: Dictionary) -> void:
	schild_max = w.schild_max
	schild = schild_max
	huelle_max = w.huelle_max
	huelle = huelle_max
	tempo = w.tempo
	raketen_max = w.raketen_max
	raketen = raketen_max
	laser_mult = w.get("laser_mult", 1.0)
	feuerrate = w.get("feuerrate", 1.0)
	raketen_mult = w.get("raketen_mult", 1.0)
	krit = w.get("krit", 0.0)
	schild_laden_mult = w.get("schild_laden", 1.0)
	schild_pause = w.get("schild_pause", SCHILD_PAUSE)
	notschild = w.get("notschild", 0)
	erz_mult = w.get("erz_mult", 1.0)
	magnet = w.get("magnet", 0.0)
	nachbrenner_cd = w.get("nachbrenner_cd", 0.0)
	notfall_cd = w.get("notfall_cd", 0.0)
	durchschlag_extra = w.get("durchschlag_extra", 0)
	f = {}
	for id in w.get("forschung", []):
		f[id] = true


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_maus += e.relative
		if e.relative.length() > 2.0:
			pad_aktiv = false
	if e is InputEventJoypadMotion and absf(e.axis_value) > 0.3 or e is InputEventJoypadButton:
		pad_aktiv = true
	if e.is_action_pressed("licht"):
		scheinwerfer.visible = not scheinwerfer.visible
	if not aktiv:
		return
	for i in 4:
		if e.is_action_pressed("waffe_%d" % (i + 1)):
			waehle(Waffen.LASER[i].id)
		if e.is_action_pressed("waffe_%d" % (i + 5)):
			waehle(Waffen.RAKETEN[i].id)
	if e.is_action_pressed("laser_weiter"):
		_durchschalten(Waffen.LASER, laser_wahl)
	if e.is_action_pressed("laser_zurueck"):
		_durchschalten(Waffen.LASER, laser_wahl, -1)
	if e.is_action_pressed("rakete_weiter"):
		_durchschalten(Waffen.RAKETEN, rakete_wahl)


func _physics_process(dt: float) -> void:
	if not aktiv:
		_maus = Vector2.ZERO
		return
	netz_t = maxf(netz_t - dt, 0.0)
	notfall_rest = maxf(notfall_rest - dt, 0.0)
	if Input.is_action_just_pressed("notfallschild"):
		notfallschild()
	emp_t = maxf(emp_t - dt, 0.0)
	if not autopilot.is_empty():
		_zug = Vector3.ZERO
		_autopilot_fliegen(dt)
		return
	var pad := Input.get_vector("blick_links", "blick_rechts", "blick_hoch", "blick_runter")
	if pad.length() > 0.0:
		pad = pad.normalized() * pow(pad.length(), PAD_KURVE)
		if _ziel_nahe(KLEBEN_WINKEL) != null:
			pad *= KLEBEN_FAKTOR
	var gier := -_maus.x * MAUS - pad.x * PAD_DREH * dt
	var nick := -_maus.y * MAUS - pad.y * PAD_DREH * dt
	_maus = Vector2.ZERO
	var roll := Input.get_axis("rollen_rechts", "rollen_links") * ROLL * dt
	rotate_object_local(Vector3.UP, gier)
	rotate_object_local(Vector3.RIGHT, nick)
	rotate_object_local(Vector3.BACK, roll)
	transform.basis = transform.basis.orthonormalized()

	var ein := Vector3(Input.get_axis("links", "rechts"), Input.get_axis("runter", "hoch"),
		Input.get_axis("vor", "zurueck")).limit_length(1.0)
	nachbrenner_bereit = maxf(nachbrenner_bereit - dt, 0.0)
	tarn_t = maxf(tarn_t - dt, 0.0)
	_ueberladung_t = maxf(_ueberladung_t - dt, 0.0)
	_schock_cd = maxf(_schock_cd - dt, 0.0)
	_boost = maxf(_boost - dt, 0.0)
	if Input.is_action_just_pressed("nachbrenner"):
		nachbrenner_zuenden()
	var soll := transform.basis * ein * tempo * (NACHBRENNER_FAKTOR if _boost > 0.0 else 1.0) * (NETZ_BREMSE if netz_t > 0.0 else 1.0)
	velocity = velocity.lerp(soll, 1.0 - exp(-(3.5 if f.has("s_daempfer") else 2.5) * dt))
	velocity += _zug * dt
	_zug = Vector3.ZERO
	move_and_slide()
	_waffen(dt)
	schild_laden(dt)
	_erzmagnet(dt)


## Notfallschild: Schild sofort voll, dann notfall_cd Sekunden Abklingzeit. Gibt true zurück, wenn ausgelöst.
func notfallschild() -> bool:
	if notfall_cd <= 0.0 or notfall_rest > 0.0 or not aktiv:
		return false
	schild = schild_max
	notfall_rest = notfall_cd
	notfall_ausgeloest.emit()
	return true


## Nachbrenner: doppeltes Tempo für 1,5 s, danach Abklingzeit. Gibt true zurück, wenn gezündet.
func nachbrenner_zuenden() -> bool:
	if nachbrenner_cd <= 0.0 or nachbrenner_bereit > 0.0:
		return false
	_boost = NACHBRENNER_DAUER
	nachbrenner_bereit = nachbrenner_cd
	var klang := get_tree().root.get_node_or_null("Klang")
	if klang:
		klang.spiele("piep", null, -14.0, 0.6)
	return true


func boost_aktiv() -> bool:
	return _boost > 0.0


## Erzmagnet: Beute in Reichweite fliegt zum Schiff — nur, was das Schiff gerade aufnehmen kann.
func _erzmagnet(dt: float) -> void:
	if magnet <= 0.0:
		return
	for b in get_tree().get_nodes_in_group("beute"):
		var weg: Vector3 = global_position - b.global_position
		if weg.length() < magnet and kann_nehmen(b.art):
			b.global_position += weg.normalized() * minf(16.0 * dt, weg.length())


## Schockwelle: Gegner in 8 m nehmen 25 Schaden und werden weggestoßen, höchstens alle 6 s.
func _schockwelle() -> void:
	if not f.has("t_schock") or _schock_cd > 0.0:
		return
	_schock_cd = 6.0
	Effekte.explosion(get_parent(), global_position, Color(0.5, 0.8, 1.0), 6.0)
	for g in get_tree().get_nodes_in_group("gegner"):
		var weg: Vector3 = g.global_position - global_position
		if weg.length() < 8.0:
			g.treffer(25.0)
			if is_instance_valid(g) and g is CharacterBody3D:
				g.velocity += weg.normalized() * 18.0


func kann_nehmen(art: String) -> bool:
	match art:
		"schild":
			return schild < schild_max
		"reparatur":
			return huelle < huelle_max
		"rakete":
			return raketen < raketen_max
	return true


func schild_laden(dt: float) -> void:
	if not aktiv:
		return
	if f.has("s_nano") and huelle < huelle_max * 0.5:      # Nanoreparatur
		huelle = minf(huelle + 0.5 * dt, huelle_max * 0.5)
	_seit_treffer += dt
	if schild_laedt and emp_t <= 0.0 and _seit_treffer >= schild_pause:
		var rate := SCHILD_LADEN * schild_laden_mult * (SCHILD_STEHEND if velocity.length() < STILLSTAND else (1.5 if f.has("s_feld") else 1.0))
		schild = minf(schild_max, schild + rate * dt)


## Waffe wählen, wenn freigeschaltet. Gibt false zurück, wenn sie noch gekauft werden muss.
func stufe_von(id: String) -> int:
	return int(waffen_stufen.get(id, 1))


## Zum Laufbeginn: je Laser und Rakete die freigeschaltete Waffe mit der höchsten Mk-Stufe wählen;
## bei gleicher Stufe die teurere (weiter hinten in der Liste). Stev: „immer die max ausgebauten als Standard“.
func beste_vorwaehlen() -> void:
	for liste in [Waffen.LASER, Waffen.RAKETEN]:
		var beste := ""
		var beste_stufe := 0
		for w in liste:
			if w.id in waffen_frei and stufe_von(w.id) >= beste_stufe:
				beste = w.id
				beste_stufe = stufe_von(w.id)
		if beste != "":
			waehle(beste)


func waehle(id: String) -> bool:
	if not id in waffen_frei:
		waffe_gewechselt.emit("%s — im Hangar kaufen" % Waffen.finde(id).name)
		return false
	if Waffen.ist_laser(id):
		laser_wahl = id
	else:
		rakete_wahl = id
	return true


func _durchschalten(liste: Array, jetzt: String, richtung := 1) -> void:
	var i := 0
	for k in liste.size():
		if liste[k].id == jetzt:
			i = k
	for schritt in range(1, liste.size()):
		var w: Dictionary = liste[posmod(i + schritt * richtung, liste.size())]
		if w.id in waffen_frei:
			waehle(w.id)
			return


func _waffen(dt: float) -> void:
	_laser_cd -= dt
	_raketen_cd -= dt
	if welt == null:
		return
	if Input.is_action_pressed("feuer") and _laser_cd <= 0.0:
		laser_schuss()
	var r := Waffen.finde(rakete_wahl)
	if Input.is_action_just_pressed("rakete") and _raketen_cd <= 0.0 and raketen >= int(r.kosten_munition):
		raketen_schuss()


## Nächster Gegner (oder Reaktor) innerhalb von winkel Grad um die Blickrichtung, bis 70 m; sonst null.
func _ziel_nahe(winkel: float) -> Node3D:
	var vor := -global_basis.z
	var grenze := cos(deg_to_rad(winkel))
	var bestes: Node3D = null
	var best_d := 70.0
	for z in get_tree().get_nodes_in_group("ziele"):
		var weg: Vector3 = z.global_position - global_position
		var d := weg.length()
		if d < best_d and d > 1.0 and vor.dot(weg / d) > grenze:
			if z is Gegner and z.ist_getarnt():
				continue
			best_d = d
			bestes = z
	return bestes


func laser_schuss() -> void:
	var w := Waffen.finde(laser_wahl)
	_laser_cd = w.cd / (feuerrate * (1.25 if _ueberladung_t > 0.0 else 1.0))
	_seite = -_seite
	var versatz := 0.45 * _seite if w.anzahl == 1 else 0.0
	var start := global_transform * Vector3(versatz, -0.35, -1.0 - 1.0 * float(w.groesse))   # große Kugeln weiter vorn
	_salve(w, start, Waffen.schaden_faktor(stufe_von(w.id)) * laser_mult)
	var klang := get_tree().root.get_node_or_null("Klang")
	if klang:
		klang.spiele(w.ton, null, w.db, w.tonhoehe)


func raketen_schuss() -> void:
	var w := Waffen.finde(rakete_wahl)
	_raketen_cd = w.cd
	if not (f.has("t_sparer") and randf() < 0.25):          # Raketensparer
		raketen -= int(w.kosten_munition)
	var klang := get_tree().root.get_node_or_null("Klang")
	if klang:
		klang.spiele("rakete", null, -7.0, 1.15 if w.anzahl > 1 else 1.0)
	var start := global_transform * Vector3(0, -0.5, -1.2)
	for g in _salve(w, start, Waffen.schaden_faktor(stufe_von(w.id)) * raketen_mult):
		g.lenkung = w.lenkung
		g.flaeche = w.flaeche
		g.splitter = w.splitter
		g.lebenszeit = 6.0
		g.knall = 9.0 if w.flaeche > 0.0 else 3.5


## Schießt "anzahl" Geschosse im Fächer (Streuung in Grad), gibt sie zurück.
## Mit dem Gamepad zielen Laser auf einen Gegner nahe am Fadenkreuz (Treffhilfe).
func _salve(w: Dictionary, start: Vector3, mult: float) -> Array:
	var aus := []
	var n: int = w.anzahl
	var mitte := -global_basis.z
	if pad_aktiv and Waffen.ist_laser(w.id):
		var z := _ziel_nahe(MAGNET_WINKEL)
		if z != null:
			mitte = (z.global_position - start).normalized()
	for i in n:
		var winkel := 0.0 if n == 1 else lerpf(-w.streuung, w.streuung, float(i) / (n - 1))
		var r := mitte.rotated(global_basis.y, deg_to_rad(winkel))
		if n == 1 and w.streuung > 0.0:      # Vulkan: leichtes Flattern
			r = r.rotated(global_basis.x, deg_to_rad(randf_range(-w.streuung, w.streuung)))
			r = r.rotated(global_basis.y, deg_to_rad(randf_range(-w.streuung, w.streuung)))
		# höhere Version: etwas dickere Bolzen, damit man es sieht
		# Zielrechner: Chance auf doppelten Schaden je Geschoss
		var s: float = w.schaden * mult * (2.0 if krit > 0.0 and randf() < krit else 1.0)
		var g := Geschoss.neu(start, r, w.tempo, s, true, w.farbe, 0.0, w.groesse * (0.85 + 0.15 * minf(mult, 2.2)))
		if Waffen.ist_laser(w.id):
			g.durchschlag = (1 if f.has("f_durchschlag") else 0) + durchschlag_extra
			g.abprall = 1 if f.has("f_abprall") else 0
			g.kette = f.has("f_kette")
		welt.add_child(g)
		aus.append(g)
	return aus


func _autopilot_fliegen(dt: float) -> void:
	var weg := autopilot[0] - global_position
	if weg.length() < 1.8:
		autopilot.remove_at(0)
		return
	velocity = weg.normalized() * AUTOPILOT_TEMPO
	var vor := weg.normalized()
	var oben := global_basis.y if absf(vor.dot(global_basis.y)) < 0.95 else global_basis.z
	global_basis = global_basis.slerp(Basis.looking_at(vor, oben), minf(1.0, 6.0 * dt)).orthonormalized()
	move_and_slide()


func aufnehmen(art: String, menge: int) -> bool:
	if art == "erz":
		menge = int(round((menge + (1 if f.has("b_sonde") else 0)) * erz_mult))      # Erzsonde, Raffinerie
	elif art == "rakete":
		menge = raketen_max - raketen        # Meldung zeigt, wie viele wirklich dazukamen
	elif art == "reparatur":
		menge = ceili(huelle_max - huelle)
	var genommen := _aufnehmen(art, menge)
	if genommen:
		aufgenommen.emit(art, menge)
	else:
		voll.emit(art)
	return genommen


func _aufnehmen(art: String, menge: int) -> bool:
	match art:
		"schild":
			if schild >= schild_max:
				return false
			schild = minf(schild_max, schild + menge)
		"reparatur":
			if huelle >= huelle_max:
				return false
			huelle = huelle_max   # Stev 2026-10-10: ein Reparaturfund repariert alles, nicht nur +30
		"rakete":         # Stev 2026-10-10: ein Raketenfund füllt alle Raketen auf, nicht nur +2
			if raketen >= raketen_max:
				return false
			raketen = raketen_max
		"erz":
			erz_gefunden.emit(menge)
		"kristall":
			kristall_gefunden.emit(menge)
	return true


## Überladung: nach einem Abschuss kurz schneller feuern (ruft Main beim Abschuss auf).
func ueberladung_ausloesen() -> void:
	if f.has("t_ueberladung"):
		_ueberladung_t = 3.0


## Treffer hörbar machen: Schild klingt hell, Hülle dumpf. Höchstens alle 0,12 s, sonst prasselt es.
var _treffer_ton_t := 0
func _treffer_ton(nur_schild: bool) -> void:
	if Time.get_ticks_msec() - _treffer_ton_t < 120:
		return
	_treffer_ton_t = Time.get_ticks_msec()
	var klang := get_tree().root.get_node_or_null("Klang")
	if klang:
		klang.spiele("treffer_schild" if nur_schild else "treffer_huelle", null, -6.0 if nur_schild else -3.0)


func getarnt() -> bool:
	return tarn_t > 0.0


## Greifer: Zugkraft (m/s²) für diesen Physikschritt.
func ziehen(kraft: Vector3) -> void:
	_zug = kraft


func sonder_treffer(art: String, s: float) -> void:
	if unverwundbar or not aktiv:
		return
	match art:
		"netz":
			netz_t = NETZ_DAUER
			treffer(s)
			behindert.emit("NETZ — GEBREMST")
		"emp":             # trifft nur den Schild, dafür doppelt, und sperrt sein Laden
			_seit_treffer = 0.0
			schild = maxf(schild - 2.0 * s * schaden_faktor, 0.0)
			emp_t = EMP_DAUER
			_treffer_ton(true)
			getroffen.emit(s)
			behindert.emit("STÖRSENDER — SCHILD LÄDT NICHT")
		_:
			treffer(s)


func treffer(s: float) -> void:
	if unverwundbar or not aktiv:
		return
	_seit_treffer = 0.0
	s *= schaden_faktor
	var hatte_schild := schild > 0.0
	schild -= s
	_treffer_ton(hatte_schild and schild >= 0.0)
	if schild < 0.0:
		huelle += schild      # was der Schild nicht abfängt, trifft die Hülle
		schild = 0.0
		_schockwelle()
	getroffen.emit(s)
	if huelle <= 0.0 and notschild > 0:
		notschild -= 1
		huelle = 1.0
		schild = schild_max
		notschild_ausgeloest.emit()
		return
	if huelle <= 0.0:
		huelle = 0.0
		aktiv = false
		gestorben.emit()

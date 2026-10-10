class_name Schiff
extends CharacterBody3D
## Das Spielerschiff: sechs Freiheitsgrade, Maus dreht direkt, das Schiff gleitet nach.

signal gestorben
signal getroffen(schaden: float)
signal erz_gefunden(menge: int)
signal aufgenommen(art: String, menge: int)   ## für die HUD-Meldung
signal voll(art: String)                       ## berührt, aber nicht gebraucht
signal waffe_gewechselt(name: String)

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
	if not autopilot.is_empty():
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
	var soll := transform.basis * ein * tempo
	velocity = velocity.lerp(soll, 1.0 - exp(-2.5 * dt))
	move_and_slide()
	_waffen(dt)
	schild_laden(dt)


func schild_laden(dt: float) -> void:
	if not aktiv:
		return
	_seit_treffer += dt
	if _seit_treffer >= SCHILD_PAUSE:
		var rate := SCHILD_LADEN * (SCHILD_STEHEND if velocity.length() < STILLSTAND else 1.0)
		schild = minf(schild_max, schild + rate * dt)


## Waffe wählen, wenn freigeschaltet. Gibt false zurück, wenn sie noch gekauft werden muss.
func stufe_von(id: String) -> int:
	return int(waffen_stufen.get(id, 1))


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
	_laser_cd = w.cd
	_seite = -_seite
	var versatz := 0.45 * _seite if w.anzahl == 1 else 0.0
	var start := global_transform * Vector3(versatz, -0.35, -1.0 - 1.0 * float(w.groesse))   # große Kugeln weiter vorn
	_salve(w, start, Waffen.schaden_faktor(stufe_von(w.id)))
	var klang := get_tree().root.get_node_or_null("Klang")
	if klang:
		klang.spiele(w.ton, null, w.db, w.tonhoehe)


func raketen_schuss() -> void:
	var w := Waffen.finde(rakete_wahl)
	_raketen_cd = w.cd
	raketen -= int(w.kosten_munition)
	var start := global_transform * Vector3(0, -0.5, -1.2)
	for g in _salve(w, start, Waffen.schaden_faktor(stufe_von(w.id))):
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
		var g := Geschoss.neu(start, r, w.tempo, w.schaden * mult, true, w.farbe, 0.0, w.groesse * (0.85 + 0.15 * mult))
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
			huelle = minf(huelle_max, huelle + menge)
		"rakete":
			if raketen >= raketen_max:
				return false
			raketen = mini(raketen_max, raketen + menge)
		"erz":
			erz_gefunden.emit(menge)
	return true


func treffer(s: float) -> void:
	if unverwundbar or not aktiv:
		return
	_seit_treffer = 0.0
	schild -= s
	if schild < 0.0:
		huelle += schild      # was der Schild nicht abfängt, trifft die Hülle
		schild = 0.0
	getroffen.emit(s)
	if huelle <= 0.0:
		huelle = 0.0
		aktiv = false
		gestorben.emit()

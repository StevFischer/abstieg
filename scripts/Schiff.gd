class_name Schiff
extends CharacterBody3D
## Das Spielerschiff: sechs Freiheitsgrade, Maus dreht direkt, das Schiff gleitet nach.

signal gestorben
signal getroffen(schaden: float)
signal erz_gefunden(menge: int)

const MAUS := 0.0022
const PAD_DREH := 2.6
const ROLL := 2.2
const AUTOPILOT_TEMPO := 12.0
## Schild lädt sich von selbst auf, aber erst nach einer Pause ohne Treffer — und langsam:
## 1,5 je Sekunde heißt gut eine Minute von leer bis voll (100). Ein Treffer setzt die Pause zurück.
const SCHILD_PAUSE := 5.0
const SCHILD_LADEN := 1.5

var schild_max := 100.0
var schild := 100.0
## Hülle: nimmt erst Schaden, wenn der Schild leer ist, und lädt sich NICHT selbst auf —
## nur Reparatur-Fundstücke und der Tiefenwechsel bringen sie zurück.
var huelle_max := 100.0
var huelle := 100.0
var energie_max := 100.0
var energie := 100.0
var energie_regen := 3.0
var raketen_max := 4
var raketen := 4
var laser_mult := 1.0
var tempo := 14.0
var welt: Node3D            ## Hier landen die Geschosse — das aktuelle Level.
var aktiv := true
var unverwundbar := false
var autopilot: Array[Vector3] = []   ## Nur für den Selbsttest: Wegpunkte abfliegen.

var kamera: Camera3D
var scheinwerfer: SpotLight3D
var _maus := Vector2.ZERO
var _laser_cd := 0.0
var _raketen_cd := 0.0
var _seite := 1.0
var _seit_treffer := 0.0


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
	laser_mult = w.laser_mult
	energie_regen = w.energie_regen
	tempo = w.tempo
	raketen_max = w.raketen_max
	raketen = raketen_max
	energie = energie_max


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_maus += e.relative
	if e.is_action_pressed("licht"):
		scheinwerfer.visible = not scheinwerfer.visible


func _physics_process(dt: float) -> void:
	if not aktiv:
		_maus = Vector2.ZERO
		return
	if not autopilot.is_empty():
		_autopilot_fliegen(dt)
		return
	var pad := Input.get_vector("blick_links", "blick_rechts", "blick_hoch", "blick_runter")
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
	energie = minf(energie_max, energie + energie_regen * dt)
	schild_laden(dt)


func schild_laden(dt: float) -> void:
	if not aktiv:
		return
	_seit_treffer += dt
	if _seit_treffer >= SCHILD_PAUSE:
		schild = minf(schild_max, schild + SCHILD_LADEN * dt)


func _waffen(dt: float) -> void:
	_laser_cd -= dt
	_raketen_cd -= dt
	if welt == null:
		return
	if Input.is_action_pressed("feuer") and _laser_cd <= 0.0 and energie >= 1.0:
		laser_schuss()
	if Input.is_action_just_pressed("rakete") and _raketen_cd <= 0.0 and raketen > 0:
		_raketen_cd = 0.6
		raketen -= 1
		var start := global_transform * Vector3(0, -0.5, -1.2)
		welt.add_child(Geschoss.neu(start, -global_basis.z, 34.0, 70.0 * laser_mult, true,
			Color(1.0, 0.75, 0.3), 2.5, 1.6))


func laser_schuss() -> void:
	_laser_cd = 0.14
	energie -= 1.0
	_seite = -_seite
	var start := global_transform * Vector3(0.45 * _seite, -0.3, -1.0)
	welt.add_child(Geschoss.neu(start, -global_basis.z, 90.0, 12.0 * laser_mult, true, Color(1.0, 0.3, 0.2)))
	Effekte.ton("laser", null, -9.0)


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
	match art:
		"schild":
			if schild >= schild_max:
				return false
			schild = minf(schild_max, schild + menge)
		"reparatur":
			if huelle >= huelle_max:
				return false
			huelle = minf(huelle_max, huelle + menge)
		"energie":
			if energie >= energie_max:
				return false
			energie = minf(energie_max, energie + menge)
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

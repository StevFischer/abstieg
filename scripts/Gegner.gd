class_name Gegner
extends CharacterBody3D
## Minenroboter. Schweben ruhig, bis sie das Schiff sehen; danach jagen sie es,
## fliegen zur letzten bekannten Stelle, wenn die Sicht abreißt.
## Modelle: assets/gegner/<typ>.glb, gebaut von tools/modelle_bauen.py (Blender).
## Deren Materialnamen (Panzer, Rahmen, Leuchte, Duese, Mine, Schild) werden hier ersetzt.
##
## Gemeinsam: wer das Schiff zuerst sieht, ruft Verstärkung (alle im Umkreis von 30 m werden
## alarmiert). Wendige Typen weichen anfliegenden Schüssen aus und greifen von der Seite an.
## Eigenes Verhalten je Typ — siehe die Funktionen _verhalten_<typ>.
## Bosse (boss_*) haben zwei Phasen: unter 50 % Leben wechseln sie das Angriffsmuster.

signal zerstoert(g: Gegner)
signal verstaerkung(typ: String, pos: Vector3, von: Gegner)   ## Boss ruft Nachschub
signal klaut(g: Gegner)                                        ## Dieb hat das Schiff berührt
signal phase_zwei(g: Gegner)

const TYPEN := {
	"jaeger": {"hp": 30.0, "schaden": 6.0, "cd": 1.1, "schuss": 16.0, "tempo": 9.0, "abstand": 11.0, "radius": 1.0,
		"farbe": Color(0.55, 0.14, 0.10), "auge": Color(1.0, 0.25, 0.1), "erz": 4},
	"geschuetz": {"hp": 55.0, "schaden": 9.0, "cd": 1.6, "schuss": 13.0, "tempo": 0.0, "abstand": 0.0, "radius": 1.1,
		"farbe": Color(0.42, 0.42, 0.47), "auge": Color(1.0, 0.6, 0.1), "erz": 5},
	"waechter": {"hp": 130.0, "schaden": 14.0, "cd": 2.0, "schuss": 11.0, "tempo": 4.5, "abstand": 6.0, "radius": 1.4,
		"farbe": Color(0.22, 0.36, 0.22), "auge": Color(0.3, 1.0, 0.3), "erz": 10},
	"minenleger": {"hp": 70.0, "schaden": 18.0, "cd": 3.2, "schuss": 0.0, "tempo": 6.0, "abstand": 20.0, "radius": 1.25,
		"farbe": Color(0.55, 0.45, 0.16), "auge": Color(1.0, 0.5, 0.1), "erz": 12},
	"tarn": {"hp": 45.0, "schaden": 10.0, "cd": 1.4, "schuss": 20.0, "tempo": 11.0, "abstand": 9.0, "radius": 1.0,
		"farbe": Color(0.24, 0.2, 0.34), "auge": Color(0.85, 0.3, 1.0), "erz": 14},
	"schildtraeger": {"hp": 80.0, "schaden": 10.0, "cd": 2.2, "schuss": 15.0, "tempo": 4.0, "abstand": 10.0, "radius": 1.3,
		"farbe": Color(0.35, 0.38, 0.5), "auge": Color(0.4, 0.7, 1.0), "erz": 12},
	"kamikaze": {"hp": 25.0, "schaden": 30.0, "cd": 0.0, "schuss": 0.0, "tempo": 15.0, "abstand": 0.0, "radius": 0.9,
		"farbe": Color(0.6, 0.1, 0.08), "auge": Color(1.0, 0.15, 0.05), "erz": 6},
	"drohne": {"hp": 12.0, "schaden": 3.0, "cd": 1.0, "schuss": 18.0, "tempo": 12.0, "abstand": 7.0, "radius": 0.5,
		"farbe": Color(0.5, 0.5, 0.55), "auge": Color(1.0, 0.3, 0.3), "erz": 2},
	"teleporter": {"hp": 50.0, "schaden": 8.0, "cd": 0.18, "schuss": 22.0, "tempo": 3.0, "abstand": 12.0, "radius": 1.0,
		"farbe": Color(0.2, 0.45, 0.5), "auge": Color(0.3, 1.0, 0.9), "erz": 14},
	"dieb": {"hp": 40.0, "schaden": 0.0, "cd": 0.0, "schuss": 0.0, "tempo": 16.0, "abstand": 0.0, "radius": 0.9,
		"farbe": Color(0.3, 0.3, 0.3), "auge": Color(1.0, 0.85, 0.2), "erz": 10},
	"reparierer": {"hp": 60.0, "schaden": 0.0, "cd": 0.0, "schuss": 0.0, "tempo": 7.0, "abstand": 22.0, "radius": 1.1,
		"farbe": Color(0.85, 0.85, 0.85), "auge": Color(0.3, 1.0, 0.4), "erz": 12},
	"boss_koloss": {"hp": 1500.0, "schaden": 14.0, "cd": 2.0, "schuss": 18.0, "tempo": 2.5, "abstand": 14.0, "radius": 3.2,
		"farbe": Color(0.45, 0.18, 0.12), "auge": Color(1.0, 0.3, 0.1), "erz": 150, "name": "KOLOSS"},
	"boss_brutmutter": {"hp": 1200.0, "schaden": 22.0, "cd": 2.2, "schuss": 14.0, "tempo": 1.5, "abstand": 16.0, "radius": 2.8,
		"farbe": Color(0.4, 0.32, 0.12), "auge": Color(1.0, 0.6, 0.1), "erz": 150, "name": "BRUTMUTTER"},
	"boss_phantom": {"hp": 1000.0, "schaden": 10.0, "cd": 2.6, "schuss": 20.0, "tempo": 0.0, "abstand": 14.0, "radius": 2.6,
		"farbe": Color(0.22, 0.18, 0.35), "auge": Color(0.9, 0.3, 1.0), "erz": 150, "name": "PHANTOM"},
}
const BOSSE := ["boss_koloss", "boss_brutmutter", "boss_phantom"]
const WENDIG := ["jaeger", "tarn", "teleporter", "dieb"]       ## weichen Schüssen aus
const FLANKE := ["jaeger", "tarn", "drohne"]                    ## greifen von der Seite an
const TARN_NAH := 14.0      ## näher als das wird der Tarnroboter sichtbar
const TARN_UNSICHTBAR := 0.93
const RUF_WEITE := 30.0
## Stev 2026-10-10: „die Gegner sollen mich etwas früher sehen“ — Sichtweite 55 → 70 m, dazu ein
## Gehör: näher als GEHOER bemerken sie das Schiff auch ohne freie Sichtlinie (um die Ecke).
const SICHT_WEITE := 70.0
const GEHOER := 15.0
## Schildträger: wie schnell er sich nach dem Schiff dreht, und wie breit sein Schild schützt
## (Kosinus des halben Öffnungswinkels; 0,5 = ±60°). Gemessen 2026-10-10: mit 3,5 / 0,35 war er beim
## Umkreisen selbst mit 14 m/s 0 % der Zeit ungeschützt — praktisch unverwundbar.
static var schild_drehung := 1.2
static var schild_kegel := 0.82     ## ±35° (Stev: „seitlich auch treffbar“; vorher ±60°)

static var _modelle := {}
static var _platten: ImageTexture
static var rufe := 0            ## wie oft Verstärkung gerufen wurde (für Test und Log)
static var ausweicher := 0      ## wie oft ein Gegner einem Schuss ausgewichen ist

var typ := "jaeger"
var hp := 30.0
var hp_max := 30.0
var schaden := 6.0
var cd_basis := 1.0
var tempo := 9.0
var abstand := 10.0
var erz := 4
var beute := 0                  ## vom Dieb gestohlenes Erz, fällt beim Abschuss wieder heraus
var ist_boss := false
var boss_raum: Array = []       ## Phantom: Punkte im Bossraum zum Hinspringen
## Bossjagd (Stev 2026-10-10: „Boss kommt nicht aus dem Bossraum, man kann sich draußen verstecken“):
## Sieht der Boss das Schiff JAGD_NACH Sekunden nicht, folgt er ihm über den Wegfinder durch die Stollen.
## Seine Kollisionskugel schrumpft dabei auf JAGD_RADIUS, damit er durch 6-m-Stollen passt.
const JAGD_NACH := 2.0
const JAGD_TEMPO := 8.0
const JAGD_RADIUS := 2.4
var gen: LevelGen               ## nur für Bosse gesetzt: Zellen und Wegfinder
var jagt := false
var _ohne_sicht := 0.0
var _jagd_weg: Array[Vector3] = []
var _jagd_t := 0.0
var _kugel: SphereShape3D
var _radius_voll := 1.0
var phase := 1
## Geschosstempo: wie im Original anfangs gemächlich (11–16 m/s, das Schiff fliegt 14),
## +8 % je Tiefe, höchstens doppelt so schnell wie am Anfang.
var schuss_tempo := 16.0
var ziel: Node3D
var welt: Node3D
var _cd := 1.5
var _spezial_t := 3.0
var _salve := 0
var _sicht := false
var _sicht_t := 0.0
var _alarm := false
var _letzte := Vector3.ZERO
var _zeit := 0.0
var _tot := false
var _auge: Color
var _blitz: StandardMaterial3D
var _teile: Array[MeshInstance3D] = []
var _rotor: Node3D
var _tarn := 0.0            ## 0 = voll sichtbar, TARN_UNSICHTBAR = fast weg
var _enttarnt_t := 0.0
var _ausweich_cd := 0.0
var _flanke := 0.0
var _strahl: MeshInstance3D     ## Reparierer: Heilstrahl
var _geheilt := 0.0


func einrichten(p_typ: String, stufe: int) -> void:
	typ = p_typ
	var d: Dictionary = TYPEN[typ]
	ist_boss = typ.begins_with("boss_")
	var f := (1.0 + 0.12 * (stufe - 1)) if ist_boss else (1.0 + 0.18 * (stufe - 1))
	hp = d.hp * f
	hp_max = hp
	schaden = d.schaden * (1.0 + 0.1 * (stufe - 1))
	cd_basis = d.cd / (1.0 + 0.05 * (stufe - 1))
	tempo = d.tempo * minf(1.0 + 0.03 * (stufe - 1), 1.8)
	abstand = d.abstand
	erz = int(d.erz) + stufe * (10 if ist_boss else 1)
	schuss_tempo = d.schuss * minf(1.0 + 0.08 * (stufe - 1), 2.0)
	_auge = d.auge
	_zeit = randf() * 10.0
	_flanke = randf_range(-1.2, 1.2)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	add_to_group("ziele")
	add_to_group("gegner")
	if ist_boss:
		add_to_group("boss")
	var form := CollisionShape3D.new()
	var kugel := SphereShape3D.new()
	kugel.radius = d.radius
	_kugel = kugel
	_radius_voll = d.radius
	form.shape = kugel
	add_child(form)
	_modell_laden(d)
	if typ == "tarn":
		_tarn = TARN_UNSICHTBAR
		_tarnung_anwenden()


func boss_name() -> String:
	return TYPEN[typ].get("name", typ)


func _modell_laden(d: Dictionary) -> void:
	if not _modelle.has(typ):
		_modelle[typ] = load("res://assets/gegner/%s.glb" % typ)
	var modell: Node3D = _modelle[typ].instantiate()
	modell.name = "Modell"
	add_child(modell)
	_blitz = StandardMaterial3D.new()
	_blitz.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blitz.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blitz.albedo_color = Color(1, 1, 1, 0)
	var mats := _materialien(d)
	for mi: MeshInstance3D in modell.find_children("*", "MeshInstance3D", true, false):
		_teile.append(mi)
		mi.material_overlay = _blitz
		for s in mi.mesh.get_surface_count():
			var alt := mi.mesh.surface_get_material(s)
			var name := alt.resource_name if alt != null else ""
			for k in mats:
				if name.begins_with(k):
					mi.set_surface_override_material(s, mats[k])
		if mi.name.begins_with("Rotor") or mi.name.begins_with("Ring") or mi.name.begins_with("Halo"):
			_rotor = mi


## Je Typ ein Satz Materialien — geteilt, damit 80 Roboter nicht 400 Materialien bedeuten.
static var _mat_cache := {}
func _materialien(d: Dictionary) -> Dictionary:
	if _mat_cache.has(typ):
		return _mat_cache[typ]
	if _platten == null:
		var bild: Image = Texturen._platten({}, 7, Color(0.45, 0.45, 0.47), Color(1, 1, 1), 16)[0]
		bild.generate_mipmaps()
		_platten = ImageTexture.create_from_image(bild)
	var panzer := StandardMaterial3D.new()
	# Hell genug für die dunklen Minen: ohne Himmel spiegelt Metall nichts, also wenig Metallanteil.
	panzer.albedo_color = Color(minf(d.farbe.r * 1.7, 1.0), minf(d.farbe.g * 1.7, 1.0), minf(d.farbe.b * 1.7, 1.0))
	panzer.albedo_texture = _platten
	panzer.uv1_triplanar = true
	panzer.uv1_scale = Vector3(1.6, 1.6, 1.6)
	panzer.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	panzer.metallic = 0.2
	panzer.roughness = 0.5
	var rahmen := panzer.duplicate() as StandardMaterial3D
	rahmen.albedo_color = Color(0.34, 0.34, 0.37)
	rahmen.metallic = 0.3
	var leuchte := StandardMaterial3D.new()
	leuchte.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	leuchte.albedo_color = Color(d.auge.r * 1.8, d.auge.g * 1.8, d.auge.b * 1.8)
	var duese := leuchte.duplicate() as StandardMaterial3D
	duese.albedo_color = Color(1.6, 0.85, 0.3)
	var mine := leuchte.duplicate() as StandardMaterial3D
	mine.albedo_color = Color(1.8, 0.8, 0.2)
	var schild := StandardMaterial3D.new()
	schild.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	schild.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	schild.albedo_color = Color(0.4, 0.75, 1.6, 0.45)
	schild.cull_mode = BaseMaterial3D.CULL_DISABLED
	var satz := {"Panzer": panzer, "Rahmen": rahmen, "Leuchte": leuchte, "Duese": duese, "Mine": mine, "Schild": schild}
	_mat_cache[typ] = satz
	return satz


func _process(dt: float) -> void:
	if _rotor:
		_rotor.rotate_object_local(Vector3.UP, dt * 2.5)
	if typ == "tarn" or (typ == "boss_phantom" and phase == 2):
		_enttarnt_t -= dt
		var nah := ziel != null and is_instance_valid(ziel) and global_position.distance_to(ziel.global_position) < TARN_NAH
		var soll := 0.0 if (nah or _enttarnt_t > 0.0) else TARN_UNSICHTBAR
		var neu := move_toward(_tarn, soll, dt * 1.8)
		if neu != _tarn:
			_tarn = neu
			_tarnung_anwenden()
	if typ == "kamikaze" and _alarm:     # Auge blinkt rot, je näher, desto schneller
		var d := 40.0 if ziel == null or not is_instance_valid(ziel) else global_position.distance_to(ziel.global_position)
		_blitz.albedo_color = Color(1, 0.1, 0.05, 0.5 * maxf(0.0, sin(_zeit * lerpf(25.0, 6.0, clampf(d / 30.0, 0, 1)))))


func _tarnung_anwenden() -> void:
	for mi in _teile:
		mi.transparency = _tarn


func ist_getarnt() -> bool:
	return _tarn > 0.5


## Von außen alarmieren (Verstärkung): fliegt zur gemeldeten Stelle.
func alarmieren(pos: Vector3) -> void:
	if _tot or _alarm:
		return
	_alarm = true
	_letzte = pos


func _physics_process(dt: float) -> void:
	if _tot or ziel == null or not is_instance_valid(ziel):
		return
	_zeit += dt
	_cd -= dt
	_spezial_t -= dt
	_sicht_t -= dt
	_ausweich_cd -= dt
	var zum := ziel.global_position - global_position
	var dist := zum.length()
	if _sicht_t <= 0.0:
		_sicht_t = 0.25
		var getarnt: bool = ziel is Schiff and ziel.getarnt()
		_sicht = dist < SICHT_WEITE and _frei(ziel.global_position) and not getarnt
		if not _sicht and not _alarm and not getarnt and dist < GEHOER:
			_alarm = true                 # gehört, nicht gesehen: fliegt hin, schießt erst bei Sicht
			_letzte = ziel.global_position
			_rufen()
	if _sicht:
		if not _alarm:
			_alarm = true
			_rufen()
		_letzte = ziel.global_position
	var soll_v := Vector3(0, sin(_zeit * 1.7) * 0.4, 0)
	if ist_boss and gen != null and _alarm:
		_ohne_sicht = 0.0 if _sicht else _ohne_sicht + dt
		if _ohne_sicht > JAGD_NACH:
			soll_v = _jagen(dt)
			velocity = velocity.lerp(soll_v, 1.0 - exp(-3.0 * dt))
			move_and_slide()
			return
		_jagd_ende()
	if _alarm:
		match typ:
			"minenleger": soll_v = _verhalten_minenleger(zum, dist, dt)
			"kamikaze": soll_v = _verhalten_kamikaze(zum, dist, dt)
			"teleporter": soll_v = _verhalten_teleporter(zum, dist, dt)
			"dieb": soll_v = _verhalten_dieb(zum, dist, dt)
			"reparierer": soll_v = _verhalten_reparierer(zum, dist, dt)
			"boss_koloss": soll_v = _verhalten_koloss(zum, dist, dt)
			"boss_brutmutter": soll_v = _verhalten_brutmutter(zum, dist, dt)
			"boss_phantom": soll_v = _verhalten_phantom(zum, dist, dt)
			_: soll_v = _verhalten_standard(zum, dist, dt)
		if typ in WENDIG:
			_ausweichen()
	velocity = velocity.lerp(soll_v, 1.0 - exp(-3.0 * dt))
	move_and_slide()


# --- Bossjagd -------------------------------------------------------------------

func _jagen(dt: float) -> Vector3:
	if not jagt:
		jagt = true
		_kugel.radius = minf(_radius_voll, JAGD_RADIUS)
		_jagd_t = 0.0
		Protokoll.schreib("gegner", "Boss %s jagt das Schiff (Sicht seit %.1f s weg)" % [typ, _ohne_sicht])
	_jagd_t -= dt
	if _jagd_t <= 0.0:
		_jagd_t = 0.5
		_jagd_weg.clear()
		for z in gen.pfad(gen.naechste_zelle(global_position), gen.naechste_zelle(ziel.global_position)):
			_jagd_weg.append(LevelGen.welt_von(z))
	while not _jagd_weg.is_empty() and _jagd_weg[0].distance_to(global_position) < 2.5:
		_jagd_weg.remove_at(0)
	var hin: Vector3 = ziel.global_position if _jagd_weg.is_empty() else _jagd_weg[0]
	_drehen_zu(hin, dt * 2.0)
	if tempo <= 0.0:
		# Phantom: springt den Weg entlang, drei Zellen auf einmal
		_spezial_t -= dt
		# nicht direkt vors Schiff: zwei Zellen Weg bleiben stehen. Ist der Rest kürzer (das Schiff steckt
		# gleich hinter einer Ecke), auf die Zelle davor — sonst sähe es das Schiff nie (Fehler 14:38).
		if _spezial_t <= 0.0 and not _jagd_weg.is_empty():
			_spezial_t = 1.5
			_springen(_jagd_weg[mini(2, _jagd_weg.size() - 3)] if _jagd_weg.size() > 2 else _jagd_weg[0])
			_jagd_t = 0.0
		return Vector3.ZERO
	return (hin - global_position).normalized() * JAGD_TEMPO


## Wieder in Sicht: Jagd vorbei. Volle Größe erst zurück im Bossraum, im Stollen passte er sonst nicht.
func _jagd_ende() -> void:
	if not jagt:
		return
	if gen.zellen.get(gen.naechste_zelle(global_position), -2) != gen.reaktor_raum:
		return
	jagt = false
	_kugel.radius = _radius_voll
	Protokoll.schreib("gegner", "Boss %s zurück im Bossraum" % typ)


# --- Gemeinsame Bausteine ----------------------------------------------------

func _rufen() -> void:
	var n := 0
	for g in get_tree().get_nodes_in_group("gegner"):
		if g != self and g.global_position.distance_to(global_position) < RUF_WEITE:
			if not g._alarm:
				g.alarmieren(ziel.global_position)
				n += 1
	if n > 0:
		rufe += 1


## Hin zum Schiff bzw. zur letzten bekannten Stelle, Abstand halten; flankierende Typen
## suchen sich einen Platz seitlich des Schiffs statt frontal anzufliegen.
func _verfolgen(zum: Vector3, dist: float) -> Vector3:
	if tempo <= 0.0:
		return Vector3.ZERO
	if not _sicht:
		var w := _letzte - global_position
		return w.normalized() * tempo if w.length() > 2.0 else Vector3.ZERO
	var soll_pos := ziel.global_position - zum / maxf(dist, 0.01) * abstand
	if typ in FLANKE:
		var von_ziel := (global_position - ziel.global_position).normalized()
		soll_pos = ziel.global_position + von_ziel.rotated(Vector3.UP, _flanke) * abstand
	var w := soll_pos - global_position
	var v := w.normalized() * tempo if w.length() > 1.5 else Vector3.ZERO
	if typ in FLANKE:
		v += global_basis.x * sin(_zeit * 1.3) * tempo * 0.4
	return v


func _ausweichen() -> void:
	if _ausweich_cd > 0.0:
		return
	for g in get_tree().get_nodes_in_group("spieler_geschoss"):
		var rel: Vector3 = global_position - g.global_position
		var d := rel.length()
		if d < 12.0 and d > 0.5 and g.geschw.normalized().dot(rel / d) > 0.96:
			var seite: Vector3 = g.geschw.cross(Vector3.UP).normalized()
			if seite.length_squared() < 0.1:
				seite = g.geschw.cross(Vector3.RIGHT).normalized()
			velocity += seite * (1.0 if randf() < 0.5 else -1.0) * tempo * 1.6
			_ausweich_cd = randf_range(1.2, 2.0)
			ausweicher += 1
			return


func _zielt_auf(zum: Vector3, dist: float, genau := 0.85) -> bool:
	return (-global_basis.z).dot(zum / maxf(dist, 0.01)) > genau


func _verhalten_standard(zum: Vector3, dist: float, dt: float) -> Vector3:
	_drehen_zu(ziel.global_position if _sicht else _letzte, dt)
	if _sicht and _cd <= 0.0 and _zielt_auf(zum, dist):
		_schiessen()
		_cd = cd_basis * randf_range(0.8, 1.3)
	return _verfolgen(zum, dist)


# --- Typen ---------------------------------------------------------------------

func _verhalten_minenleger(zum: Vector3, dist: float, dt: float) -> Vector3:
	_drehen_zu(ziel.global_position if _sicht else _letzte, dt)
	if _cd <= 0.0 and dist < 45.0:
		_mine_legen(global_position + global_basis.z * 1.6)
		_cd = cd_basis * randf_range(0.8, 1.2)
	return _verfolgen(zum, dist) if _sicht else Vector3.ZERO


## Stürzt sich ohne zu bremsen auf das Schiff und explodiert in der Nähe.
func _verhalten_kamikaze(zum: Vector3, dist: float, dt: float) -> Vector3:
	var hin := ziel.global_position if _sicht else _letzte
	_drehen_zu(hin, dt * 2.0)
	if _sicht and dist < 2.8:
		_detonieren(5.0)
		return Vector3.ZERO
	return (hin - global_position).normalized() * tempo


## Springt hinter das Schiff und feuert dort eine Dreiersalve.
func _verhalten_teleporter(zum: Vector3, dist: float, dt: float) -> Vector3:
	_drehen_zu(ziel.global_position if _sicht else _letzte, dt * 3.0)
	if _salve > 0 and _cd <= 0.0:
		_schiessen()
		_salve -= 1
		_cd = cd_basis
	if _spezial_t <= 0.0 and _sicht and dist < 40.0:
		var hinter: Vector3 = ziel.global_position + ziel.global_basis.z * 8.0 + Vector3(randf_range(-2, 2), randf_range(-1, 1), 0)
		_springen(_frei_bis(ziel.global_position, hinter))
		_spezial_t = randf_range(4.0, 6.0)
		_salve = 3
		_cd = 0.35
	return _verfolgen(zum, dist)


## Fliegt auf das Schiff zu, stiehlt Erz bei Berührung und flieht danach.
func _verhalten_dieb(zum: Vector3, dist: float, dt: float) -> Vector3:
	if beute == 0:
		_drehen_zu(ziel.global_position if _sicht else _letzte, dt)
		if _sicht and dist < 2.6:
			klaut.emit(self)
			if beute == 0:
				beute = -1        # nichts zu holen: trotzdem abhauen
		var hin := ziel.global_position if _sicht else _letzte
		return (hin - global_position).normalized() * tempo
	_drehen_zu(global_position - zum, dt)
	return -zum.normalized() * tempo if dist < 70.0 else Vector3.ZERO


## Hält Abstand zum Schiff und heilt beschädigte Roboter in der Nähe (sichtbarer Strahl).
func _verhalten_reparierer(zum: Vector3, dist: float, dt: float) -> Vector3:
	var patient: Gegner = null
	var best := 25.0
	for g in get_tree().get_nodes_in_group("gegner"):
		if g != self and not g._tot and g.hp < g.hp_max:
			var d: float = g.global_position.distance_to(global_position)
			if d < best:
				best = d
				patient = g
	var v := Vector3.ZERO
	if dist < 12.0:
		v = -zum.normalized() * tempo           # Abstand zum Schiff
	if patient != null:
		_drehen_zu(patient.global_position, dt)
		if best > 7.0:
			v += (patient.global_position - global_position).normalized() * tempo
		if best < 10.0:
			var menge: float = minf(15.0 * dt, patient.hp_max - patient.hp)
			patient.hp += menge
			_geheilt += menge
			_strahl_zeigen(patient.global_position)
			return v
	_strahl_zeigen(Vector3.INF)
	if patient == null:
		_drehen_zu(ziel.global_position, dt)
		v = _verfolgen(zum, dist)
	return v


func geheilt_gesamt() -> float:
	return _geheilt


func _strahl_zeigen(nach: Vector3) -> void:
	if nach == Vector3.INF:
		if _strahl:
			_strahl.visible = false
		return
	if _strahl == null:
		_strahl = MeshInstance3D.new()
		var z := CylinderMesh.new()
		z.top_radius = 0.06
		z.bottom_radius = 0.06
		z.height = 1.0
		z.radial_segments = 6
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.6, 3.0, 0.9)
		z.material = m
		_strahl.mesh = z
		_strahl.top_level = true
		add_child(_strahl)
	_strahl.visible = true
	var mitte := (global_position + nach) * 0.5
	var r := nach - global_position
	_strahl.global_position = mitte
	_strahl.global_basis = Basis(Quaternion(Vector3.UP, r.normalized())).scaled(Vector3(1, r.length(), 1))


# --- Bosse -------------------------------------------------------------------

var phase2_anteil := 0.5       ## Pakt „Wütende Bosse“: schon ab 70 %

func _phase_pruefen() -> void:
	if phase == 1 and hp < hp_max * phase2_anteil:
		phase = 2
		cd_basis *= 0.6
		phase_zwei.emit(self)


## Koloss: langsame Fächersalven; Phase 2 schneller, breiter, und schickt Kamikazes.
func _verhalten_koloss(zum: Vector3, dist: float, dt: float) -> Vector3:
	_phase_pruefen()
	_drehen_zu(ziel.global_position if _sicht else _letzte, dt * 0.6)
	if _sicht and _cd <= 0.0 and _zielt_auf(zum, dist, 0.7):
		_faecher(5 if phase == 1 else 9, 24.0 if phase == 1 else 40.0)
		_cd = cd_basis
	if phase == 2 and _spezial_t <= 0.0:
		_spezial_t = 7.0
		for i in 2:
			verstaerkung.emit("kamikaze", global_position + global_basis.x * (3.5 if i == 0 else -3.5), self)
	return _verfolgen(zum, dist)


## Brutmutter: erzeugt Schwarmdrohnen und spuckt schwere Plasmakugeln; Phase 2 doppelt so oft, legt Minen.
func _verhalten_brutmutter(zum: Vector3, dist: float, dt: float) -> Vector3:
	_phase_pruefen()
	_drehen_zu(ziel.global_position if _sicht else _letzte, dt * 0.5)
	if _spezial_t <= 0.0:
		_spezial_t = 6.0 if phase == 1 else 3.0
		var eigene := 0
		for g in get_tree().get_nodes_in_group("brut"):
			eigene += 1
		if eigene < 12:
			for i in 3:
				var r := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
				verstaerkung.emit("drohne", global_position + r * 3.5, self)
		if phase == 2:
			for i in 2:
				_mine_legen(global_position + Vector3(randf_range(-5, 5), randf_range(-2, 2), randf_range(-5, 5)))
	if _sicht and _cd <= 0.0 and _zielt_auf(zum, dist, 0.6):
		var start := global_position - global_basis.z * 3.0
		var g := Geschoss.neu(start, (ziel.global_position - start).normalized(), schuss_tempo, schaden, false, _auge, 0.0, 3.0)
		welt.add_child(g)
		Effekte.ton("laser_gegner", start, 0.0)
		_cd = cd_basis
	return _verfolgen(zum, dist)


## Phantom: springt durch den Bossraum und feuert Ringe aus Schüssen; Phase 2 doppelte Ringe und Tarnung.
func _verhalten_phantom(zum: Vector3, dist: float, dt: float) -> Vector3:
	_phase_pruefen()
	_drehen_zu(ziel.global_position, dt * 2.0)
	if _spezial_t <= 0.0 and not boss_raum.is_empty():
		_spezial_t = 3.0 if phase == 1 else 2.0
		var beste: Vector3 = boss_raum[randi() % boss_raum.size()]
		for i in 6:     # nicht direkt neben dem Schiff landen
			var p: Vector3 = boss_raum[randi() % boss_raum.size()]
			if p.distance_to(ziel.global_position) > 9.0:
				beste = p
				break
		_springen(beste)
		_cd = 0.4
	if _cd <= 0.0 and _sicht:
		_ring(8 if phase == 1 else 16)
		_cd = cd_basis
		_enttarnt_t = 1.2
	return Vector3.ZERO


func _faecher(n: int, breite: float) -> void:
	var start := global_position - global_basis.z * 3.4
	var basis_r := (ziel.global_position - start).normalized()
	for i in n:
		var w := deg_to_rad(lerpf(-breite, breite, float(i) / (n - 1)))
		welt.add_child(Geschoss.neu(start, basis_r.rotated(Vector3.UP, w), schuss_tempo, schaden, false, _auge, 0.0, 1.6))
	Effekte.ton("laser_gegner", start, 2.0)


func _ring(n: int) -> void:
	var zum := (ziel.global_position - global_position).normalized()
	var a := zum.cross(Vector3.UP).normalized()
	if a.length_squared() < 0.1:
		a = Vector3.RIGHT
	var b := zum.cross(a).normalized()
	for i in n:
		var w := TAU * i / n
		var r := (zum * 0.75 + (a * cos(w) + b * sin(w)) * 0.66).normalized()
		welt.add_child(Geschoss.neu(global_position + r * 2.8, r, schuss_tempo, schaden, false, _auge, 0.0, 1.3))
	Effekte.ton("laser_gegner", global_position, 2.0)


# --- Hilfen --------------------------------------------------------------------

func _frei(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position, p, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Wie weit man von "von" Richtung "nach" fliegen kann, bevor eine Wand kommt (mit 1,5 m Abstand).
func _frei_bis(von: Vector3, nach: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(von, nach, 1)
	var t := get_world_3d().direct_space_state.intersect_ray(q)
	if t.is_empty():
		return nach
	return t.position - (nach - von).normalized() * 1.5


func _springen(nach: Vector3) -> void:
	Effekte.explosion(get_parent(), global_position, _auge, 2.5)
	global_position = nach
	velocity = Vector3.ZERO
	Effekte.explosion(get_parent(), global_position, _auge, 2.5)
	_enttarnt_t = 1.5


func _drehen_zu(p: Vector3, dt: float) -> void:
	var vor := p - global_position
	if vor.length_squared() < 0.01:
		return
	vor = vor.normalized()
	var oben := Vector3.UP if absf(vor.y) < 0.95 else Vector3.FORWARD
	var rate := 2.0 if typ == "geschuetz" else (schild_drehung if typ == "schildtraeger" else 3.5)
	global_basis = global_basis.slerp(Basis.looking_at(vor, oben), minf(1.0, rate * dt)).orthonormalized()


func _schiessen() -> void:
	if welt == null:
		return
	var start := global_position - global_basis.z * 1.4
	var richtung := (ziel.global_position - start).normalized()
	richtung = (richtung + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.06).normalized()
	welt.add_child(Geschoss.neu(start, richtung, schuss_tempo, schaden, false, _auge))
	Effekte.ton("laser_gegner", start, -4.0)
	if typ == "tarn":
		_enttarnt_t = 2.0      # wer schießt, verrät sich


func _mine_legen(pos: Vector3) -> void:
	if welt == null:
		return
	welt.add_child(Mine.neu(pos, schaden))


## Kamikaze: Explosion mit Schaden am Schiff, wenn es nahe genug ist.
func _detonieren(radius: float) -> void:
	if _tot:
		return
	if ziel != null and is_instance_valid(ziel):
		var d := global_position.distance_to(ziel.global_position)
		if d < radius and ziel.has_method("treffer"):
			ziel.treffer(schaden * (1.0 - d / radius * 0.5))
	erz = 0             # wer sich selbst sprengt, hinterlässt nichts
	hp = 0.0
	_sterben()


## Treffer mit Richtung (vom Geschoss): der Schildträger blockt alles, was von vorn kommt.
func treffer_von(s: float, richtung: Vector3) -> bool:
	if typ == "schildtraeger" and not _tot and (-global_basis.z).dot(-richtung.normalized()) > schild_kegel:
		Effekte.explosion(get_parent(), global_position - global_basis.z * 1.2, Color(0.4, 0.7, 1.0), 1.0)
		Effekte.schadenszahl(get_parent(), global_position - global_basis.z * 1.2, "BLOCK", 0.0, true)
		return false
	treffer(s)
	return true


func treffer(s: float) -> void:
	if _tot:
		return
	if s < 100000.0:            # Testabschüsse (1e9) nicht als Zahl zeigen
		Effekte.schaden_sammeln(self, get_parent(), global_position, s)
	hp -= s
	if not _alarm:
		_alarm = true
		if ziel != null and is_instance_valid(ziel):
			_rufen()
	_enttarnt_t = 2.0
	if ziel != null and is_instance_valid(ziel):
		_letzte = ziel.global_position
	_blitz.albedo_color = Color(1, 1, 1, 0.75)
	create_tween().tween_property(_blitz, "albedo_color:a", 0.0, 0.15)
	if hp <= 0.0:
		_sterben()


func _sterben() -> void:
	_tot = true
	remove_from_group("ziele")
	Effekte.explosion(get_parent(), global_position, Color(1.0, 0.6, 0.2), 9.0 if ist_boss else 3.5)
	zerstoert.emit(self)
	queue_free()

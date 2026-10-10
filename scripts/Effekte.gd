class_name Effekte
extends RefCounted
## Explosionen: leuchtende Kugel, die aufbläht und verblasst, dazu ein kurzer Lichtblitz.


## Ton über das Autoload Klang — per Pfad geholt, damit Skripte, die Effekte benutzen,
## auch in Tests ohne Autoloads (godot --script) übersetzen.
static func ton(name: String, pos: Variant = null, db := 0.0) -> void:
	var baum := Engine.get_main_loop() as SceneTree
	if baum == null:
		return
	var k := baum.root.get_node_or_null("Klang")
	if k != null:
		k.spiele(name, pos, db)


## Aufsteigende Schadenszahl am Ziel: steigt 1,6 m hoch und verblasst. Größer und wärmer bei viel Schaden,
## blau für geblockte Treffer. Immer gleich groß auf dem Schirm und durch Wände sichtbar, damit man sie liest.
## Schnelle Treffer am selben Ziel (Vulkan, Streufeuer) zu einer hochzählenden Zahl zusammenfassen,
## statt einen unlesbaren Stapel kleiner Zahlen zu erzeugen. Fenster: 0,45 s seit dem letzten Treffer.
static var _laufend := {}

static func schaden_sammeln(ziel: Node3D, eltern: Node, pos: Vector3, wert: float) -> void:
	var id := ziel.get_instance_id()
	var jetzt := Time.get_ticks_msec() / 1000.0
	var summe := wert
	if _laufend.has(id):
		var alt: Array = _laufend[id]
		if jetzt - float(alt[2]) < 0.45 and is_instance_valid(alt[0]):
			summe += float(alt[1])
			alt[0].queue_free()
	var l := schadenszahl(eltern, pos, "%d" % maxi(int(round(summe)), 1), summe)
	_laufend[id] = [l, summe, jetzt]


static func schadenszahl(eltern: Node, pos: Vector3, text: String, wert := 0.0, geblockt := false) -> Label3D:
	if eltern == null or not eltern.is_inside_tree():
		return null
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.font_size = 40 if wert < 30.0 else (52 if wert < 80.0 else 64)
	l.outline_size = 10
	l.pixel_size = 0.0011
	if geblockt:
		l.modulate = Color(0.5, 0.75, 1.0)
	elif wert >= 80.0:
		l.modulate = Color(1.0, 0.5, 0.2)
	elif wert >= 30.0:
		l.modulate = Color(1.0, 0.88, 0.3)
	else:
		l.modulate = Color(1.0, 1.0, 1.0)
	l.outline_modulate = Color(0, 0, 0, 0.9)
	eltern.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.5, 0.5), randf_range(0.6, 1.0), randf_range(-0.5, 0.5))
	l.scale = Vector3.ONE * 1.35
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 1.6, 0), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "scale", Vector3.ONE, 0.15)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.45)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.45).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)
	return l


static func explosion(eltern: Node, pos: Vector3, farbe: Color, groesse: float, mit_ton := true) -> void:
	if eltern == null or not eltern.is_inside_tree():
		return
	if mit_ton:
		if groesse <= 1.5:
			ton("einschlag", pos, -12.0)
		elif groesse <= 5.0:
			ton("explosion", pos, 0.0)
		else:
			ton("explosion_gross", pos, 0.0)
	# Aussehen (Blitz, Feuerball, Funken, Druckwelle, Licht) steht in Optik.gd — Stev 2026-10-10
	Optik.explosion(eltern, pos, farbe, groesse)

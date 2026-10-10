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
static func schadenszahl(eltern: Node, pos: Vector3, text: String, wert := 0.0, geblockt := false) -> void:
	if eltern == null or not eltern.is_inside_tree():
		return
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


static func explosion(eltern: Node, pos: Vector3, farbe: Color, groesse: float) -> void:
	if eltern == null or not eltern.is_inside_tree():
		return
	if groesse <= 1.5:
		ton("einschlag", pos, -12.0)
	elif groesse <= 5.0:
		ton("explosion", pos, 0.0)
	else:
		ton("explosion_gross", pos, 0.0)
	var k := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = 0.5
	kugel.height = 1.0
	kugel.radial_segments = 10
	kugel.rings = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(farbe.r * 2.0, farbe.g * 2.0, farbe.b * 2.0, 1.0)
	kugel.material = m
	k.mesh = kugel
	eltern.add_child(k)
	k.global_position = pos
	k.scale = Vector3.ONE * 0.2
	var licht := OmniLight3D.new()
	licht.light_color = farbe
	licht.omni_range = groesse * 4.0
	licht.light_energy = 4.0
	eltern.add_child(licht)
	licht.global_position = pos
	var tw := k.create_tween().set_parallel()
	tw.tween_property(k, "scale", Vector3.ONE * groesse, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(licht, "light_energy", 0.0, 0.5)
	tw.chain().tween_callback(func():
		k.queue_free()
		licht.queue_free())

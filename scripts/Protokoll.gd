extends Node
## Schreibt jeden Wendepunkt des Spiels nach abstieg.log neben dem Projekt.
## Kürzt sich beim Start selbst, damit die Datei nicht unbegrenzt wächst.

const MAX_ZEILEN := 3000

var _pfad := ""


func _ready() -> void:
	# Auf dem Handy ist res:// schreibgeschützt — dort in den App-Speicher schreiben.
	_pfad = ProjectSettings.globalize_path("user://abstieg.log" if OS.has_feature("android") else "res://abstieg.log")
	if FileAccess.file_exists(_pfad):
		var f := FileAccess.open(_pfad, FileAccess.READ)
		var zeilen := f.get_as_text().split("\n")
		f.close()
		if zeilen.size() > MAX_ZEILEN:
			var w := FileAccess.open(_pfad, FileAccess.WRITE)
			w.store_string("\n".join(zeilen.slice(zeilen.size() - MAX_ZEILEN / 2)))
			w.close()
	schreib("start", "Godot %s, Argumente %s, Bildschirm %s" % [
		Engine.get_version_info().string, OS.get_cmdline_user_args(), DisplayServer.screen_get_size()])


func schreib(rolle: String, text: String) -> void:
	var zeile := "%s [%s] %s" % [Time.get_datetime_string_from_system(), rolle, text]
	print(zeile)
	var f: FileAccess
	if FileAccess.file_exists(_pfad):
		f = FileAccess.open(_pfad, FileAccess.READ_WRITE)
	else:
		f = FileAccess.open(_pfad, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(zeile)
	f.close()

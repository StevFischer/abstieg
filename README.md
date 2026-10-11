# Abstieg

Descent-artiges Roguelite: Flieg mit einem 6DOF-Schiff durch prozedural erzeugte Minen, zerstöre den Reaktor,
entkomme vor der Explosion und steig tiefer, endlos. Zwischen den Läufen Aufrüstungen, Forschung, Module und
eine Bergbaustation ausbauen.

- **Im Browser spielen:** https://stevfischer.github.io/abstieg/ (auch auf [Hugging Face](https://huggingface.co/spaces/StevFischer/abstieg))
- **Downloads (Windows, Linux, Android):** [Releases](https://github.com/StevFischer/abstieg/releases/latest)

## Steuerung

| | Tastatur & Maus | Controller | Handy (Touch) |
|---|---|---|---|
| Fliegen | WASD | linker Stick | Stick links (Daumen aufsetzen) |
| Drehen | Maus | rechter Stick | rechte Bildseite ziehen |
| Hoch / runter | Leertaste / Strg | A / B | ▲ / ▼ |
| Rollen | Q / E | LB / RB | ↺ / ↻ |
| Laser / Rakete | linke / rechte Maustaste | RT / LT | FEUER halten / RAKETE |
| Pause | Esc | Start | II |

Tastatur und Controller lassen sich unter Optionen umbelegen, am Handy gibt es dort einen Regler für die
Touch-Empfindlichkeit.

## Bauen

Godot 4.7 (Forward+, auf Android Mobile). Projekt öffnen: `godot --path .`

Exporte: `godot --headless --path . --export-release "Web" build/web/index.html` (ebenso `Linux`, `Windows`;
Android mit `--export-debug "Android" build/Abstieg.apk`).

Tests laufen als Autotest, z. B. `godot --audio-driver Dummy --path . -- --autotest --besetzung-test`;
das Ergebnis steht in `abstieg.log`.

Alle Texturen, Modelle (Blender-Skripte unter `tools/`), Töne und Musik sind im Code erzeugt.

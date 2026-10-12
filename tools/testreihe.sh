#!/usr/bin/env bash
# Testreihe: alle Spieltests nacheinander, headless, je Test eigene Mitschrift.
#
#   bash tools/testreihe.sh                 Standardliste
#   bash tools/testreihe.sh --pakt-test …   nur diese Tests ("" = Autopilot-Autotest)
#
# Das Urteil kommt aus der Ausgabe des Godot-Laufs selbst (Protokoll.schreib druckt jede
# Zeile auch nach stdout), NICHT aus abstieg.log: Protokoll.gd kürzt abstieg.log beim Start
# von über 3000 auf 1500 Zeilen. Eine Reihe, die sich die Zeilenzahl vorher merkt und danach
# ab dort liest, sah deshalb beim kürzenden Lauf nichts (2026-10-10 zweimal, 2026-10-12 nachgestellt).
#
# Mitschrift je Test: pruefung/testreihe/<test>.out (stdout+stderr).
# Zusammenfassung je Lauf: testreihe.log (Zeit, Test, Urteil, Rückgabewert, Sekunden, ERROR-Zeilen).
# Rückgabewert 0 = alle bestanden, 1 = mindestens einer nicht.

cd "$(dirname "$0")/.." || exit 2
GRENZE=300
AUS=pruefung/testreihe
LOG=testreihe.log
mkdir -p "$AUS"

if [ $# -gt 0 ]; then
	TESTS=("$@")
else
	TESTS=(--aufwertungs-test --tasten-test --controller-test --gegner-neu-test --sicht-test
		--forschung-test --module-test --pakt-test --station-test --boss-jagd-test
		--starttiefe-test --sammel-test --raketen-test --boss-reset --pad-test --besetzung-test "")
fi

schlecht=0
echo "$(date +%FT%T) [reihe] Start, ${#TESTS[@]} Tests, Grenze ${GRENZE} s" >> "$LOG"
for t in "${TESTS[@]}"; do
	name=${t#--}; name=${name:-autotest}
	out="$AUS/$name.out"
	t0=$(date +%s)
	timeout "$GRENZE" godot --headless --path . --audio-driver Dummy -- --autotest $t > "$out" 2>&1
	rc=$?
	dauer=$(( $(date +%s) - t0 ))
	zeile=$(grep '\[test\]' "$out" | grep -E 'BESTANDEN|FEHLGESCHLAGEN' | tail -1)
	fehler=$(grep -c -E '^(SCRIPT )?ERROR' "$out")
	if [ $rc -eq 124 ]; then urteil="ZEITGRENZE"
	elif [[ $zeile == *BESTANDEN* ]]; then urteil="BESTANDEN"
	elif [[ $zeile == *FEHLGESCHLAGEN* ]]; then urteil="FEHLGESCHLAGEN"
	elif [ $rc -ne 0 ]; then urteil="ABSTURZ"
	else urteil="KEINE-ZEILE"
	fi
	[ "$urteil" = BESTANDEN ] || schlecht=$((schlecht + 1))
	text="${t:-autotest}: $urteil (rc $rc, ${dauer} s, ERROR-Zeilen $fehler)"
	echo "== $text"
	echo "$(date +%FT%T) [reihe] $text" >> "$LOG"
	if [ "$urteil" != BESTANDEN ]; then
		echo "   letzte Zeilen aus $out:"; tail -5 "$out" | sed 's/^/   | /'
		tail -20 "$out" | sed 's/^/    | /' >> "$LOG"
	fi
done
echo "$(date +%FT%T) [reihe] Ende: $(( ${#TESTS[@]} - schlecht )) von ${#TESTS[@]} bestanden" | tee -a "$LOG"
# Nicht unbegrenzt wachsen
if [ "$(wc -l < "$LOG")" -gt 2000 ]; then tail -1000 "$LOG" > "$LOG.neu" && mv "$LOG.neu" "$LOG"; fi
[ $schlecht -eq 0 ]

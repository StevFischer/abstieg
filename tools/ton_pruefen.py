#!/usr/bin/env python3
"""Pegel je Abschnitt in pruefung/spielton.wav (aus --ton-test). Marken aus der Logzeile: name=sekunden.
Jeder Ton muss mindestens 20 dB über der Stille liegen."""
import sys, wave, struct, math, re

def pegel(daten, rate, kanaele, von, bis):
    a, b = int(von * rate) * kanaele, int(bis * rate) * kanaele
    teil = daten[a:b]
    if not teil:
        return -120.0
    rms = math.sqrt(sum(x * x for x in teil) / len(teil)) / 32768.0
    return 20 * math.log10(max(rms, 1e-6))

zeile = open("abstieg.log").read().splitlines()
zeile = [z for z in zeile if "Ton: Aufnahme" in z][-1]
marken = dict((m.group(1), float(m.group(2))) for m in re.finditer(r"(\w+)=([\d.]+)", zeile.split("Marken")[1].split("Zähler")[0]))
w = wave.open("pruefung/spielton.wav")
rate, kanaele, n = w.getframerate(), w.getnchannels(), w.getnframes()
daten = struct.unpack("<%dh" % (n * kanaele), w.readframes(n))
namen = list(marken)
still = pegel(daten, rate, kanaele, marken["stille"], marken["stille"] + 0.6)
print("Stille: %.1f dBFS" % still)
ok = True
for i, name in enumerate(namen):
    if name in ("stille", "ende"):
        continue
    ende = marken[namen[i + 1]] if i + 1 < len(namen) else marken[name] + 1.0
    db = pegel(daten, rate, kanaele, marken[name], min(marken[name] + 1.0, ende))
    gut = db > still + 20
    ok = ok and gut
    print("%-15s %6.1f dBFS  %s" % (name, db, "hörbar" if gut else "ZU LEISE"))
print("TON-PRUEFUNG", "BESTANDEN" if ok else "FEHLGESCHLAGEN")

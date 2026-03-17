# BgColor

Hintergrundfarbe in AutoCAD per Toggle zwischen zwei konfigurierbaren Farben umschalten.
Setzt Modellbereich und Layout gleichzeitig mit einem einzigen Befehl.

## Befehle

| Befehl  | Beschreibung                                      |
|---------|---------------------------------------------------|
| BGCOLOR | Toggle zwischen Farbe A/B oder Einstellungen öffnen |

## Features

- ✅ Ein Befehl für alles — Toggle und Konfiguration
- ✅ Modellbereich und Layout werden immer gleichzeitig gesetzt
- ✅ Frei konfigurierbare Farben A und B via DCL-Dialog
- ✅ Toggle-Status bleibt über mehrere Aufrufe stabil
- ✅ Farben bleiben für die gesamte AutoCAD-Session gespeichert

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausführen
2. `BgColor.lsp` auswählen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufügen

### Support-Ordner (Alternative)

Kopieren nach:
```
%APPDATA%\Autodesk\AutoCAD 2024\R24.3\deu\Support\
```

## Verwendung

### BGCOLOR - Hintergrundfarbe umschalten

Wechselt beim Aufruf sofort zwischen Farbe A und Farbe B. Über die Option `Einstellungen`
lassen sich die beiden Farben jederzeit anpassen.

**Aufruf:**
```
Command: BGCOLOR
```

**Optionen:**
- `Enter` — Toggle: wechselt zur jeweils anderen Farbe
- `E` — Einstellungen: öffnet den Farbverwaltungs-Dialog

**Beispiel Toggle:**
```
Command: BGCOLOR
BgColor [Einstellungen] <Toggle>:
→ [BgColor] -> (43,43,43)  [A]

Command: BGCOLOR
BgColor [Einstellungen] <Toggle>:
→ [BgColor] -> (255,255,255)  [B]
```

**Beispiel Einstellungen:**
```
Command: BGCOLOR
BgColor [Einstellungen] <Toggle>: E
→ DCL-Dialog öffnet sich
```

### Einstellungen-Dialog

Ermöglicht das Anpassen der beiden Toggle-Farben. Die Eingabe erfolgt als `R,G,B`
mit Werten von 0 bis 255.

**Workflow:**
1. `BGCOLOR` aufrufen und `E` eingeben
2. Farbe A und/oder Farbe B anpassen
3. `Speichern` — Werte werden sofort übernommen

**Beispiel:**
```
Farbe A: 43,43,43       ← Dunkel (Standard)
Farbe B: 255,255,255    ← Hell (Standard)
```

## Konfiguration

### Standardfarben im Code ändern

Die Standardfarben beim ersten Laden sind in `BgColor.lsp` hinterlegt:

```lisp
(if (not *BGC:color-a*) (setq *BGC:color-a* '(43 43 43)))     ; Dunkel
(if (not *BGC:color-b*) (setq *BGC:color-b* '(255 255 255)))  ; Hell
```

Diese Werte gelten nur beim allerersten Laden. Danach bleiben die zuletzt
gesetzten Werte für die gesamte AutoCAD-Session erhalten — auch wenn das
Script mehrfach neu geladen wird.

**Farben zur Laufzeit ändern:** über `BGCOLOR` → `E` (Einstellungen-Dialog).

### Farbformat

Alle Farben werden als `R,G,B` (Rot, Grün, Blau) mit Werten von 0–255 angegeben.

| Beispiel        | Farbe              |
|-----------------|--------------------|
| `0,0,0`         | Schwarz            |
| `255,255,255`   | Weiß               |
| `43,43,43`      | Dunkelgrau         |
| `30,30,30`      | Fast Schwarz       |

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** `vl-load-com` wird verwendet
- **AutoCAD LT:** ❌ Nicht kompatibel (kein AutoLISP Support)
- **Abhängigkeiten:** Keine externen Libraries
- **Blockeditor-Hintergrund:** Nicht setzbar via AutoLISP in AutoCAD 2024
- **Methode:** `vla-put-GraphicsWinModelBackgrndColor` / `vla-put-GraphicsWinLayoutBackgrndColor`
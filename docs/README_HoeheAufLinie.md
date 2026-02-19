# HoeheAufLinie

Automatische Höheninterpolation entlang einer Linie zwischen zwei Fixpunkten.
Nutzt BlockImport.lsp für zentrale Block-Verwaltung.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| HoeheAufLinie | Höheninterpolation entlang Linie |
| HAL | Kurzbefehl für HoeheAufLinie |
| ManageBlockImportHAL | Block-Verwaltung für HoeheAufLinie |
| ShowBlockPath | Zeigt konfigurierten Block-Pfad |
| ResetBlockPath | Löscht gespeicherten Block-Pfad |

## Features

- ✅ Automatische Höhenberechnung durch Skalarprojektion
- ✅ Funktioniert auch für Punkte außerhalb der Strecke (Extrapolation)
- ✅ Beliebig viele Zwischenpunkte setzen
- ✅ XY-Skalierung mit Keyword-Option (wie SetHK)
- ✅ Höhenwerte werden aus letzter Eingabe vorgeschlagen
- ✅ BlockImport.lsp Integration mit Config-Verwaltung
- ✅ Context-Namespace "HoeheAufLinie" für Isolation
- ✅ OSMODE bleibt aktiv für präzise Punktwahl
- ✅ Vollständiges Error-Handling mit Systemvariablen-Restore

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausführen
2. `HoeheAufLinie.lsp` auswählen und laden
3. **Beim ersten Mal:** File-Dialog erscheint - wähle `BlockImport.lsp`
4. Pfad wird gespeichert für zukünftige Sitzungen
5. **Automatisches Laden:** Zu Startup Suite hinzufügen

**Wichtig:** BlockImport.lsp wird automatisch gefunden oder abgefragt!

## Verwendung

### HoeheAufLinie - Höheninterpolation entlang Linie

Berechnet interpolierte Höhen für beliebig viele Punkte zwischen (oder außerhalb!) zwei Fixpunkten.

**Aufruf:**
```
Command: HoeheAufLinie
```

**Workflow - Beim ersten Mal:**

1. **Skalierung einstellen (erste Verwendung):**
```
=== Höheninterpolation entlang Linie ===
Setzen Sie zwei Fixpunkte mit bekannten Höhen.
Dann können Sie beliebig viele Zwischenpunkte setzen.

*** Keine Skalierung konfiguriert ***
Neue XY-Skalierung <1.0>: 0.5
✓ Skalierung gespeichert: 0.50

Fixpunkt 1 wählen (oder [S]kalierung <0.50>): [Klick]
Höhe Fixpunkt 1 eingeben: 100.00
  ✓ Höhenkote gesetzt: +100.00 | Z=100.000 | XY-Scale=0.50
```

**Workflow - Normale Verwendung:**

2. **Fixpunkte setzen:**
```
Command: HoeheAufLinie

Fixpunkt 1 wählen (oder [S]kalierung <0.50>): [Klick]
Höhe Fixpunkt 1 eingeben: 100.00
  ✓ Höhenkote gesetzt: +100.00 | Z=100.000 | XY-Scale=0.50

Fixpunkt 2 wählen (oder [S]kalierung <0.50>): [Klick]
Höhe Fixpunkt 2 eingeben: 110.00
  ✓ Höhenkote gesetzt: +110.00 | Z=110.000 | XY-Scale=0.50
```

3. **Zwischenpunkte setzen:**
```
--- Zwischenpunkte setzen (ESC = Ende) ---

Gesuchten Punkt wählen (oder [S]kalierung/ESC <0.50>): [Klick Mitte]
  Berechnete Höhe: 105.00
  ✓ Höhenkote gesetzt: +105.00 | Z=105.000 | XY-Scale=0.50

Gesuchten Punkt wählen (oder [S]kalierung/ESC <0.50>): [Klick]
  Berechnete Höhe: 107.50
  ✓ Höhenkote gesetzt: +107.50 | Z=107.500 | XY-Scale=0.50

Gesuchten Punkt wählen (oder [S]kalierung/ESC <0.50>): [ESC]

✓ Höheninterpolation abgeschlossen.
```

4. **Skalierung ändern während Verwendung:**
```
Gesuchten Punkt wählen (oder [S]kalierung/ESC <0.50>): S
Neue XY-Skalierung <0.50>: 1.0
✓ Skalierung gespeichert: 1.00

Gesuchten Punkt wählen (oder [S]kalierung/ESC <1.00>): [Klick]
  Berechnete Höhe: 103.20
  ✓ Höhenkote gesetzt: +103.20 | Z=103.200 | XY-Scale=1.00
```

**Keyword-Option:**
- **[S]kalierung** - Ändert XY-Skalierung während Verwendung
- Direkt klicken - Nutzt gespeicherte Skalierung
- **Rechtsklick** - Zeigt Menü mit "Skalierung" Option
- **Kein** extra ENTER nötig!

**Besonderheit - Extrapolation:**

Die Höhenberechnung funktioniert auch für Punkte **außerhalb** der Strecke PF1-PF2:

```
PF1 (100m) ----------- PF2 (110m)
    ^                      ^
    |                      |
Punkt links          Punkt rechts
  → 95m              → 115m
```

- **Links von PF1:** Extrapoliert rückwärts
- **Zwischen PF1 und PF2:** Interpolation (normal)
- **Rechts von PF2:** Extrapoliert vorwärts

---

### HAL - Kurzbefehl

Alias für `HoeheAufLinie`.

**Aufruf:**
```
Command: HAL
```

---

### ManageBlockImportHAL - Block-Verwaltung

Öffnet Block-Import Manager für HoeheAufLinie-Context.

**Aufruf:**
```
Command: ManageBlockImportHAL
```

**Funktionen:**
- Liste aller konfigurierten Blocks anzeigen
- Standard-Block wählen
- Neuen Block hinzufügen
- Block entfernen

---

### ShowBlockPath - Pfade anzeigen

Zeigt alle konfigurierten Block-Pfade im HoeheAufLinie-Context.

**Aufruf:**
```
Command: ShowBlockPath
```

**Ausgabe:**
```
=== Konfigurierte Block-Pfade (Context: HoeheAufLinie) ===
*STANDARD*: BLK_Hoehenkote
BLK_Hoehenkote: D:/Pfad/zu/BLK_Hoehenkote.dwg [✓ Existiert]

Config-Datei: C:\Users\...\AppData\Roaming\AutoCAD\BlockImportConfig.txt
```

---

### ResetBlockPath - Pfade zurücksetzen

Löscht alle gespeicherten Block-Pfade im HoeheAufLinie-Context.

**Aufruf:**
```
Command: ResetBlockPath
```

**Hinweis:** Beim nächsten Block-Import wird erneut nach Dateien gefragt.

## Konfiguration

### BlockImport.lsp Pfad

**Speicherort:**
```
%APPDATA%\AutoCAD\HoeheAufLinieConfig.txt
```

**Format:**
```
1.0
D:/OneDrive/.../lisp/lib/BlockImport.lsp
```

**Erste Zeile:** Versions-Nummer (1.0)  
**Zweite Zeile:** Pfad zu BlockImport.lsp

### Block-Konfiguration

**Speicherort:**
```
%APPDATA%\AutoCAD\BlockImportConfig.txt
```

**Format (mit Context "HoeheAufLinie"):**
```
1.0
*STANDARD:HoeheAufLinie*=BLK_Hoehenkote
HoeheAufLinie:BLK_Hoehenkote=D:/Pfad/zu/BLK_Hoehenkote.dwg
```

### Skalierungs-Konfiguration

**Speicherort:**
```
%APPDATA%\AutoCAD\HoeheAufLinieScale.txt
```

**Format:**
```
1.0
0.5
```

**Erste Zeile:** Versions-Nummer (1.0)  
**Zweite Zeile:** XY-Skalierung (z.B. 0.5)

### Context-Namespace

HoeheAufLinie nutzt den Context "HoeheAufLinie" für:
- Isolation von anderen Scripts
- Eigene Block-Liste in BlockImport
- Eigener Standard-Block
- Keine Konflikte mit SetHK oder anderen Tools

**Interner Aufruf:**
```lisp
(setq *block-import-context* "HoeheAufLinie")
(ensure-block-available *hoehenkote-blockname*)
```

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet
- **AutoCAD LT:** ❌ Nicht kompatibel (kein AutoLISP Support)
- **Abhängigkeiten:** BlockImport.lsp (v1.5.0+)

### Mathematik - Höhenberechnung

**Skalarprojektion:**
```
scalar = (vpg · vpf) / |vpf|²

wobei:
  vpg = Vektor von PF1 zu gesuchtem Punkt
  vpf = Vektor von PF1 zu PF2
  · = Skalarprodukt
```

**Höhenformel:**
```
height = height1 + scalar × (height2 - height1)
```

**Scalar-Werte:**
- `scalar = 0.0` → Punkt bei PF1 → height1
- `scalar = 0.5` → Punkt in Mitte → (height1 + height2) / 2
- `scalar = 1.0` → Punkt bei PF2 → height2
- `scalar < 0.0` → Punkt links von PF1 → Extrapolation
- `scalar > 1.0` → Punkt rechts von PF2 → Extrapolation

**Beispiel:**
```
PF1: (0, 0) → 100m
PF2: (10, 0) → 110m
Punkt: (5, 0) → ?

scalar = 5 / 10 = 0.5
height = 100 + 0.5 × (110 - 100) = 105m ✓

Punkt links: (-5, 0)
scalar = -5 / 10 = -0.5
height = 100 + (-0.5) × 10 = 95m ✓
```

### Funktionsweise

**Block-Import:**
- Nutzt `ensure-block-available` von BlockImport.lsp
- Lädt Block automatisch aus konfigurierter DWG-Datei
- Temporärer Import wird nach Verwendung wieder entfernt

**Skalierung:**
- Nur X und Y werden skaliert
- Z bleibt immer 1.0 (Block wird später auf Höhe verschoben)
- Persistente Speicherung über Sessions
- Keyword-Option direkt bei Punktwahl

**OSMODE:**
- Wird NICHT geändert
- User kann Objektfang (Endpunkt, Schnittpunkt, etc.) nutzen
- Wichtig für präzise Vermessungsarbeit

**Höhen-Eingabe:**
- Akzeptiert Dezimalzahlen
- Fehlerbehandlung bei ungültigen Eingaben
- Formatierung auf 2 Dezimalstellen für Block-Attribut
- Letzte Höhe wird als Default vorgeschlagen

## Workflow-Beispiele

**Vermessung einer Böschung:**
```
Command: HAL

Fixpunkt 1 wählen: [Klick oben]
Höhe: 105.50

Fixpunkt 2 wählen: [Klick unten]
Höhe: 100.00

--- Zwischenpunkte ---
[Klick] → 104.25
[Klick] → 103.00
[Klick] → 101.75
[ESC]
```

**Interpolation mit Skalierung:**
```
Command: HoeheAufLinie

Fixpunkt 1 <0.5>: S
Skalierung: 0.3

Fixpunkt 1 <0.3>: [Klick]
Höhe: 100.00

Fixpunkt 2 <0.3>: [Klick]
Höhe: 102.00

Punkt <0.3>: [Klick] → 101.00
Punkt <0.3>: S → 1.0
Punkt <1.0>: [Klick] → 101.50
```

**Extrapolation über Fixpunkte hinaus:**
```
PF1: 100m --------- PF2: 110m

Punkt links von PF1: → 95m (extrapoliert)
Punkt zwischen: → 105m (interpoliert)
Punkt rechts von PF2: → 115m (extrapoliert)
```

## Block-Anforderungen

Der Höhenkote-Block muss folgende Attribute enthalten:

**Attribut-Tags:**
- `HOEHE` - Höhenwert (wird automatisch gefüllt)

**Format:**
- Höhe wird als 2-stelliger Dezimalwert formatiert
- Beispiel: 123.456 → "+123.46"
- Vorzeichen: "+" für positive, "-" für negative, "±" für 0

**Empfohlener Block-Name:**
- `BLK_Hoehenkote` (Standard)
- Kann beliebig benannt sein

## Vergleich mit SetHK

| Feature | SetHK | HoeheAufLinie |
|---------|-------|---------------|
| Einzelpunkte setzen | ✅ | ❌ |
| Interpolation | ❌ | ✅ |
| XY-Skalierung | ✅ | ✅ |
| Keyword-Option | ✅ | ✅ |
| Context-Namespace | SetHK | HoeheAufLinie |
| BlockImport.lsp | ✅ | ✅ |

**Wann was verwenden:**
- **SetHK:** Einzelne Höhenkoten an beliebigen Punkten
- **HoeheAufLinie:** Mehrere Punkte entlang einer Linie interpolieren

## Lizenz

Nutzt BlockImport.lsp Library.

---

**Version:** 1.4.2  
**Datum:** 2026-02-19  
**Autor:** Herbert Schrotter

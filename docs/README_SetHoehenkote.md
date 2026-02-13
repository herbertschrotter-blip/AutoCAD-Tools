# SetHoehenkote

Automatisches Setzen von Höhenkoten-Blocks in AutoCAD mit konfigurierbarer XY-Skalierung.
Nutzt BlockImport.lsp für zentrale Block-Verwaltung.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| SetHK | Höhenkote-Block an gewähltem Punkt setzen |
| ShowBlockPath | Zeigt konfigurierten Block-Pfad |
| ResetBlockPath | Löscht gespeicherten Block-Pfad |

## Features

- ✅ Keyword-basierte Skalierungs-Option am Punkt-Prompt
- ✅ Persistente XY-Skalierung über Sessions
- ✅ Automatische Block-Verwaltung via BlockImport.lsp
- ✅ Context-Namespace "SetHK" für Isolation
- ✅ Höhenwert-Eingabe mit Fehlerbehandlung
- ✅ Kein manuelles ENTER nötig

## Installation

### APPLOAD (Empfohlen)

1. **BlockImport.lsp** laden (Voraussetzung!)
2. Befehl `APPLOAD` in AutoCAD ausführen
3. `SetHoehenkote.lsp` auswählen und laden
4. **Automatisches Laden:** Zu Startup Suite hinzufügen

### Support-Ordner (Alternative)

Kopieren nach:
```
%APPDATA%\Autodesk\AutoCAD 2024\R24.3\deu\Support\
```

**Wichtig:** BlockImport.lsp muss vorher geladen sein!

## Verwendung

### SetHK - Höhenkote setzen

Platziert einen Höhenkote-Block an einem gewählten Punkt mit optionaler XY-Skalierung.

**Aufruf:**
```
Command: SetHK
```

**Workflow - Beim ersten Mal:**

1. **Skalierung einstellen (erste Verwendung):**
```
*** Keine Skalierung konfiguriert ***
XY-Skalierung eingeben <1.0>: 0.5
✓ Skalierung gespeichert: 0.5

Punkt wählen (oder [S]kalierung <0.5>): [Klick]
Höhe: 100.500
✓ Höhenkote gesetzt: +100.50 | Z=100.500 | XY-Scale=0.50
```

**Workflow - Normale Verwendung:**

2. **Punkt wählen (mit gespeicherter Skalierung):**
```
Punkt wählen (oder [S]kalierung <0.5>): [Klick direkt]
Höhe: 123.456
✓ Höhenkote gesetzt: +123.46 | Z=123.456 | XY-Scale=0.50
```

3. **Skalierung ändern:**
```
Punkt wählen (oder [S]kalierung <0.5>): S
Neue XY-Skalierung <0.5>: 2.0
✓ Skalierung gespeichert: 2.0

Punkt wählen (oder [S]kalierung <2.0>): [Klick]
Höhe: 150.250
✓ Höhenkote gesetzt: +150.25 | Z=150.250 | XY-Scale=2.00
```

**Keyword-Option:**
- **[S]kalierung** - Ändert XY-Skalierung
- Direkt klicken - Nutzt gespeicherte Skalierung
- **Kein** extra ENTER nötig!

---

### ShowBlockPath - Block-Pfad anzeigen

Zeigt den konfigurierten Pfad zum Höhenkote-Block.

**Aufruf:**
```
Command: ShowBlockPath
```

**Ausgabe:**
```
=== Konfigurierte Block-Pfade (Context: SetHK) ===
*STANDARD*: BLK_Hoehenkote
BLK_Hoehenkote: D:/Pfad/zu/BLK_Hoehenkote.dwg [✓ Existiert]

Config-Datei: C:\Users\...\AppData\Roaming\AutoCAD\BlockImportConfig.txt
```

---

### ResetBlockPath - Block-Pfad zurücksetzen

Löscht den gespeicherten Block-Pfad.

**Aufruf:**
```
Command: ResetBlockPath
```

**Hinweis:** Beim nächsten `SetHK` Aufruf wird nach dem Block gefragt.

## Konfiguration

### Block-Konfiguration

**Speicherort:**
```
%APPDATA%\AutoCAD\BlockImportConfig.txt
```

**Format (mit Context "SetHK"):**
```
1.0
*STANDARD:SetHK*=BLK_Hoehenkote
SetHK:BLK_Hoehenkote=D:/Pfad/zu/BLK_Hoehenkote.dwg
SetHK:BLK_Anderer=D:/Pfad/zu/BLK_Anderer.dwg
```

### Skalierungs-Konfiguration

**Speicherort:**
```
%APPDATA%\AutoCAD\SetHoehenkoteScale.txt
```

**Format:**
```
1.0
0.5
```

**Erste Zeile:** Versions-Nummer (1.0)  
**Zweite Zeile:** XY-Skalierung (z.B. 0.5)

### Context-Namespace

SetHoehenkote nutzt den Context "SetHK" für:
- Isolation von anderen Scripts
- Eigene Block-Liste in BlockImport
- Eigener Standard-Block
- Keine Konflikte mit anderen Tools

**Interner Aufruf:**
```lisp
(setq *block-import-context* "SetHK")
(ensure-block-available *hoehenkote-blockname*)
```

## Block-Anforderungen

Der Höhenkote-Block muss folgende Attribute enthalten:

**Attribut-Tags:**
- `HOEHE` - Höhenwert (wird automatisch gefüllt)

**Format:**
- Höhe wird als 2-stelliger Dezimalwert formatiert
- Beispiel: 123.456 → "+123.46"

**Empfohlener Block-Name:**
- `BLK_Hoehenkote` (Standard)
- Kann beliebig benannt sein

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet
- **AutoCAD LT:** ❌ Nicht kompatibel (kein AutoLISP Support)
- **Abhängigkeiten:** BlockImport.lsp (v1.5.0+)

### Funktionsweise

**Block-Import:**
- Nutzt `ensure-block-available` von BlockImport.lsp
- Lädt Block automatisch aus konfigurierter DWG-Datei
- Temporärer Import wird nach Verwendung wieder entfernt

**Skalierung:**
- Nur X und Y werden skaliert
- Z bleibt immer 1.0
- Persistente Speicherung über Sessions
- Keyword-Option direkt am Punkt-Prompt

**Höhen-Eingabe:**
- Akzeptiert Dezimalzahlen
- Fehlerbehandlung bei ungültigen Eingaben
- Formatierung auf 2 Dezimalstellen für Anzeige

## Workflow-Beispiele

**Erstes Setup:**
```
Command: SetHK
*** Keine Skalierung konfiguriert ***
XY-Skalierung: 0.5
✓ Gespeichert

Punkt wählen: [Klick]
Höhe: 100.0
✓ Höhenkote gesetzt: +100.00 | Z=100.000 | XY-Scale=0.50
```

**Tägliche Nutzung:**
```
Command: SetHK
Punkt wählen <0.5>: [Klick] [Klick] [Klick]
Höhe: 101.5
Höhe: 102.0  
Höhe: 102.5
✓ ✓ ✓
```

**Skalierung anpassen:**
```
Command: SetHK
Punkt wählen <0.5>: S
Neue Skalierung: 1.0
Punkt wählen <1.0>: [Klick]
```

## Lizenz

Nutzt BlockImport.lsp Library.

---

**Version:** 1.5.0  
**Datum:** 2026-02-13  
**Autor:** Herbert Schrotter

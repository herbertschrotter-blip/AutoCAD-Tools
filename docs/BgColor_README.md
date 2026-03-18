# BgColor

Hintergrundfarbe in AutoCAD per Toggle zwischen zwei konfigurierbaren Farben umschalten.
Setzt Modellbereich und Layout gleichzeitig mit einem einzigen Befehl.

## Befehle

| Befehl  | Beschreibung                                        |
|---------|-----------------------------------------------------|
| BGCOLOR | Toggle zwischen Farbe A/B oder Einstellungen oeffnen |

## Features

- Ein Befehl fuer alles — Toggle und Konfiguration
- Modellbereich und Layout werden immer gleichzeitig gesetzt
- Frei konfigurierbare Farben A und B via DCL-Dialog
- Persistente Konfiguration in %APPDATA% (ueberlebt AutoCAD-Neustart)
- Ausfuehrliches Session-Logging (max 5 Sessions)

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausfuehren
2. `BgColor.lsp` auswaehlen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufuegen

### Support-Ordner (Alternative)

Kopieren nach:
```
%APPDATA%\Autodesk\AutoCAD 2024\R24.3\deu\Support\
```

## Verwendung

### BGCOLOR - Hintergrundfarbe umschalten

Wechselt beim Aufruf sofort zwischen Farbe A und Farbe B. Ueber die Option `Einstellungen`
lassen sich die beiden Farben jederzeit anpassen.

**Aufruf:**
```
Command: BGCOLOR
```

**Optionen:**
- `Enter` — Toggle: wechselt zur jeweils anderen Farbe
- `E` — Einstellungen: oeffnet den Farbverwaltungs-Dialog

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
→ DCL-Dialog oeffnet sich
```

### Einstellungen-Dialog

Ermoeglicht das Anpassen der beiden Toggle-Farben. Die Eingabe erfolgt als `R,G,B`
mit Werten von 0 bis 255. Aenderungen werden automatisch in der Config-Datei gespeichert.

**Workflow:**
1. `BGCOLOR` aufrufen und `E` eingeben
2. Farbe A und/oder Farbe B anpassen
3. `Speichern` — Werte werden sofort uebernommen und persistent gespeichert

**Standardfarben:**
```
Farbe A: 43,43,43       ← Dunkel (Standard)
Farbe B: 255,255,255    ← Hell (Standard)
```

### Farbformat

Alle Farben werden als `R,G,B` (Rot, Gruen, Blau) mit Werten von 0–255 angegeben.

| Beispiel        | Farbe              |
|-----------------|--------------------|
| `0,0,0`         | Schwarz            |
| `255,255,255`   | Weiss              |
| `43,43,43`      | Dunkelgrau         |
| `30,30,30`      | Fast Schwarz       |

## Konfiguration

### AppData-Ordner

```
%APPDATA%\AutoCAD\Lisp\BgColor\
```

Unterordner:
- `Log\` — Session-Logs
- `Config\` — Konfigurationsdateien
- `Backup\` — Sicherungen (falls noetig)

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\Lisp\BgColor\Config\BgColor.cfg
```

**Format:**
```
VERSION=1.0
COLOR_A=43,43,43
COLOR_B=255,255,255
```

**Einstellungen:**
- `VERSION` — Config-Format Versionsnummer
- `COLOR_A` — Farbe A als R,G,B (0-255)
- `COLOR_B` — Farbe B als R,G,B (0-255)

### Einstellungen aendern

Ueber den Befehl `BGCOLOR` → `E` (Einstellungen-Dialog)
koennen beide Farben interaktiv geaendert werden.
Aenderungen werden automatisch in die Config-Datei geschrieben.

## Log-Datei

### Speicherort

```
%APPDATA%\AutoCAD\Lisp\BgColor\Log\BgColor_YYYYMMDD_HHMMSS.log
```

Pro Session wird eine neue Log-Datei erstellt.
Maximal 5 Session-Logs werden aufbewahrt, aeltere werden automatisch geloescht.

### Log-Format

```
[2026-03-18 11:14:31] [INFO ] Config geladen: A=(43,43,43) B=(255,255,255)
[2026-03-18 11:14:31] [INFO ] === BgColor v1.9.1 initialisiert ===
[2026-03-18 11:14:31] [INFO ] Befehl BGCOLOR gestartet
[2026-03-18 11:14:31] [INFO ] Toggle: B -> (255,255,255)
[2026-03-18 11:14:31] [INFO ] Befehl BGCOLOR beendet
[2026-03-18 11:14:33] [INFO ] Befehl BGCOLOR gestartet
[2026-03-18 11:14:34] [INFO ] Toggle: A -> (43,43,43)
[2026-03-18 11:14:34] [INFO ] Befehl BGCOLOR beendet
```

### Log-Level

| Level | Bedeutung |
|-------|-----------|
| INFO  | Normaler Ablauf |
| WARN  | Unerwartetes, nicht kritisch |
| ERROR | Fehler, Funktion abgebrochen |
| DEBUG | Detaillierte Infos (nur bei Debug-Modus) |

## Context-Namespace

Prefix: `BGC:` (BgColor)

### Wichtige Funktionen

| Funktion | Beschreibung |
|----------|--------------|
| BGC:ensure-init | Lazy-Init (erster Aufruf) |
| BGC:log-write | Log-Eintrag schreiben |
| BGC:log-rotate | Log-Rotation (max 5 Sessions) |
| BGC:load-config | Config aus .cfg laden |
| BGC:save-config | Config in .cfg speichern |
| BGC:get-appdata-path | AppData-Ordner ermitteln/erstellen |
| BGC:get-display | VLA Display-Objekt holen |
| BGC:set-all | Model + Layout Farbe setzen |
| BGC:rgb->ole | RGB-Liste zu BGR-Integer |
| BGC:ole->rgb | BGR-Integer zu RGB-Liste |
| BGC:rgb->str | RGB-Liste zu "R,G,B" String |
| BGC:str->rgb | "R,G,B" String zu RGB-Liste |
| BGC:show-settings | DCL Einstellungen-Dialog |

### Globale Variablen

| Variable | Beschreibung |
|----------|--------------|
| *BGC:color-a* | Farbe A als RGB-Liste |
| *BGC:color-b* | Farbe B als RGB-Liste |
| *BGC:state* | Toggle-Status ("a" / "b") |
| *BGC:initialized* | Init-Status (T/nil) |
| *BGC:appdata-folder* | AppData-Ordnername |
| *BGC:log-session-id* | Aktueller Log-Dateiname |
| *BGC:debug-mode* | Debug ein/aus (T/nil) |

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet (Lazy-Init)
- **AutoCAD LT:** Nicht kompatibel (kein AutoLISP Support)
- **Abhaengigkeiten:** Keine externen Libraries
- **AppData:** %APPDATA%\AutoCAD\Lisp\BgColor\
- **Namespace:** BGC (BgColor)
- **Blockeditor:** Hintergrund nicht setzbar via AutoLISP in AutoCAD 2024
- **Farbcodierung:** BGR-Integer (B*65536 + G*256 + R)
- **VLA Getter:** vlax-variant-change-type → vlax-vbLong → vlax-variant-value
- **VLA Setter:** plain Integer (kein vlax-make-variant noetig)
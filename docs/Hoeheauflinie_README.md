# HoeheAufLinie

Automatische Hoeheninterpolation entlang einer Linie zwischen zwei Fixpunkten.
Speziell fuer Leica-Vermessungsarbeiten mit BlockImport.lsp Integration.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| HoeheAufLinie | Hoeheninterpolation entlang Linie (S/K/E Keywords) |
| HAL | Kurzbefehl fuer HoeheAufLinie |
| HALDEBUG | Debug-Modus ein/aus |
| ManageBlockImportHAL | Block-Verwaltung fuer HoeheAufLinie |
| ShowBlockPath | Zeigt konfigurierten Block-Pfad |
| ResetBlockPath | Loescht gespeicherten Block-Pfad |

## Features

- Automatische Hoehenberechnung durch Skalarprojektion (2D)
- Konstruktionslinie (XLINE) bei Zielhoehe im rechten Winkel (Keyword K)
- Linie A-B zwischen Fixpunkten (LINE oder XLINE Modus waehlbar)
- DCL Settings-Dialog fuer alle Einstellungen (Keyword E)
- HK-Layer Suffix: Bloecke auf eigenen Layer mit kopierten Properties
- Skalierung als DWG Custom Property (geht mit der Zeichnung mit)
- Linie A-B und Konstruktionslinie: behalten oder entfernen (konfigurierbar)
- Funktioniert auch fuer Punkte ausserhalb der Strecke (Extrapolation)
- Gelbe Linie verlaengert sich bei Extrapolation automatisch (LINE-Modus)
- XLINE ist OSNAP-fangbar fuer praezise Punktwahl
- Session-basiertes Logging mit Rotation (max 5 Sessions)
- Lazy-Init Pattern fuer DokaCAD-Kompatibilitaet
- Context-Namespace HAL fuer Isolation
- Persistente Konfiguration in %APPDATA%
- Block-Verwaltung ueber DCL Settings oder ManageBlockImportHAL

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausfuehren
2. `HoeheAufLinie.lsp` auswaehlen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufuegen

### Abhaengigkeiten

- `BlockImport.lsp` muss im selben Ordner oder Support-Pfad liegen
- Wird automatisch gefunden (3-Fallback Pfadsuche) oder per File-Dialog abgefragt

## Verwendung

### HoeheAufLinie - Hoeheninterpolation entlang Linie

Berechnet interpolierte Hoehen fuer beliebig viele Punkte zwischen (oder ausserhalb) zwei Fixpunkten. Zeigt eine temporaere Linie A-B und ermoeglicht Konstruktionslinien bei bestimmten Zielhoehen.

**Aufruf:**
```
Command: HoeheAufLinie
```

**Workflow:**
1. Fixpunkt 1 waehlen + Hoehe eingeben
2. Fixpunkt 2 waehlen + Hoehe eingeben
3. Beliebig viele Zwischenpunkte setzen (Hoehe wird automatisch berechnet)
4. ESC zum Beenden

**Beispiel:**
```
Command: HAL

=== Hoeheninterpolation entlang Linie ===

Fixpunkt 1 waehlen [Skalierung/Einstellungen] <1.00>: [Klick]
Hoehe Fixpunkt 1 eingeben: 322.00
  Hoehenkote gesetzt: +322.00 | Z=322.000 | XY-Scale=1.00

Fixpunkt 2 waehlen [Skalierung/Einstellungen] <1.00>: [Klick]
Hoehe Fixpunkt 2 eingeben: 344.00
  Hoehenkote gesetzt: +344.00 | Z=344.000 | XY-Scale=1.00

--- Zwischenpunkte setzen (K=Konstruktionslinie, S=Skalierung, E=Einstellungen, ESC=Ende) ---

Punkt waehlen [Skalierung/Konstruktion/Einstellungen] <1.00>: [Klick]
  Berechnete Hoehe: 333.00
  Hoehenkote gesetzt: +333.00 | Z=333.000 | XY-Scale=1.00

Punkt waehlen [Skalierung/Konstruktion/Einstellungen] <1.00>: [ESC]

Hoeheninterpolation abgeschlossen.
```

**Keywords bei Punktwahl:**
- `S` (Skalierung) - XY-Skalierung aendern und in DWG speichern
- `K` (Konstruktion) - Rote XLINE bei Zielhoehe im rechten Winkel zu A-B
- `E` (Einstellungen) - DCL Settings-Dialog oeffnen
- `ESC` - Beenden

### Konstruktionslinie (Keyword K)

Erzeugt eine rote XLINE im rechten Winkel zur Linie A-B bei einer eingegebenen Zielhoehe. OSNAP-fangbar fuer praezise Schnittpunkt-Wahl.

**Beispiel:**
```
Punkt waehlen [Skalierung/Konstruktion/Einstellungen] <1.00>: K
Zielhoehe fuer Konstruktionslinie eingeben: 327.50
  Konstruktionslinie bei Hoehe 327.50 | Punkt=(58100.50, 20150.30)

Punkt waehlen [...]: [Klick auf XLINE-Schnittpunkt]
  Berechnete Hoehe: 327.50
  Hoehenkote gesetzt: +327.50
```

Bei erneutem K wird die vorherige Konstruktionslinie durch eine neue ersetzt. Im LINE-Modus verlaengert sich die gelbe Linie A-B automatisch wenn die Zielhoehe ausserhalb der Strecke liegt.

### Einstellungen (Keyword E)

Oeffnet den DCL Settings-Dialog mit folgenden Optionen:

- **XY-Skalierung** - Aktuelle Zeichnung (DWG Custom Property)
- **Layer** - HK-Layer Suffix ein/aus + Suffix-Name konfigurierbar
- **Linie A-B (gelb)** - Modus LINE oder XLINE + am Ende behalten/entfernen
- **Konstruktionslinie (rot)** - Am Ende behalten/entfernen
- **Hoehenkoten-Block** - Block-Verwaltung oeffnen
- **Debug** - Debug-Modus ein/aus

Alle Einstellungen werden persistent in der Config-Datei gespeichert.

### Extrapolation

Die Hoehenberechnung funktioniert auch fuer Punkte ausserhalb der Strecke PF1-PF2:

- Links von PF1 (scalar < 0): Extrapoliert rueckwaerts
- Zwischen PF1 und PF2 (0 < scalar < 1): Interpolation
- Rechts von PF2 (scalar > 1): Extrapoliert vorwaerts

### HAL - Kurzbefehl

Alias fuer `HoeheAufLinie`.

```
Command: HAL
```

### HALDEBUG - Debug-Modus

Schaltet Debug-Ausgaben auf der Command-Line ein/aus. Die Log-Datei wird unabhaengig davon immer geschrieben. Debug-Modus wird persistent in der Config gespeichert.

```
Command: HALDEBUG
Debug-Modus: EIN
```

### ManageBlockImportHAL - Block-Verwaltung

Oeffnet Block-Import Manager fuer den HoeheAufLinie-Context. Funktionen: Blocks auflisten, Standard-Block waehlen, neuen Block hinzufuegen, Block entfernen.

```
Command: ManageBlockImportHAL
```

## Konfiguration

### AppData-Ordner

Alle Daten werden gespeichert in:
```
%APPDATA%\AutoCAD\Lisp\HoeheAufLinie\
```

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\Lisp\HoeheAufLinie\Config\HoeheAufLinie.cfg
```

**Format:**
```
VERSION=2.3.1
BLOCKIMPORTPATH=D:\OneDrive\...\lisp\lib\BlockImport.lsp
DEBUG=0
USE_LAYER_SUFFIX=1
LAYER_SUFFIX=HK
LINEAB_MODE=LINE
LINEAB_KEEP=0
XLINE_KEEP=0
```

**Einstellungen:**
- `VERSION` - Script-Version
- `BLOCKIMPORTPATH` - Pfad zu BlockImport.lsp
- `DEBUG` - Debug-Modus (0/1)
- `USE_LAYER_SUFFIX` - HK-Layer Suffix aktiv (0/1)
- `LAYER_SUFFIX` - Suffix-Name, wird mit _ getrennt (z.B. "HK" ergibt "Vermessung_HK")
- `LINEAB_MODE` - Linie A-B Modus: LINE (nur zwischen A-B) oder XLINE (unendlich)
- `LINEAB_KEEP` - Linie A-B am Ende behalten (0/1)
- `XLINE_KEEP` - Rote Konstruktionslinie am Ende behalten (0/1)

### Einstellungen aendern

Ueber das Keyword `E` (Einstellungen) waehrend der Punktwahl oder ueber den DCL Settings-Dialog.

### Skalierung (DWG Custom Property)

Die XY-Skalierung wird als Custom Property `HoehenkoteScale` direkt in der DWG gespeichert. Sichtbar unter `DWGPROPS > Benutzerdefiniert`. Geht mit der Zeichnung mit (ueberlebt SaveAs, Kopie, anderer PC).

### Block-Konfiguration

Block-Pfade werden ueber BlockImport.lsp verwaltet mit Context "HoeheAufLinie":
```
%APPDATA%\AutoCAD\BlockImportConfig.txt
```

## Log-Datei

### Speicherort

```
%APPDATA%\AutoCAD\Lisp\HoeheAufLinie\Log\HoeheAufLinie_YYYYMMDD_HHMMSS.log
```

Pro Session wird eine neue Log-Datei erstellt.
Maximal 5 Session-Logs werden aufbewahrt, aeltere werden automatisch geloescht.

### Log-Format

```
[2026-03-19 14:30:22] [INFO ] === HoeheAufLinie v2.3.1 initialisiert ===
[2026-03-19 14:30:22] [INFO ] Config geladen
[2026-03-19 14:30:25] [INFO ] Befehl HoeheAufLinie gestartet
[2026-03-19 14:30:28] [INFO ] Fixpunkt 1: (1234.567 890.123)
[2026-03-19 14:30:28] [INFO ] Hoehe 1: 322.0000
[2026-03-19 14:30:35] [INFO ] Interpolation: (1237.000 892.500) -> 333.1200
[2026-03-19 14:30:35] [INFO ] Block gesetzt: +333.12 Z=333.120 Scale=1.00
[2026-03-19 14:30:40] [INFO ] Benutzer-Abbruch: *Abbruch*
[2026-03-19 14:30:40] [INFO ] Befehl HoeheAufLinie beendet
```

### Log-Level

| Level | Bedeutung |
|-------|-----------|
| INFO  | Normaler Ablauf |
| WARN  | Unerwartetes, nicht kritisch |
| ERROR | Fehler, Funktion abgebrochen |
| DEBUG | Detaillierte Infos (nur bei Debug-Modus) |

### Debug-Modus

Debug-Modus aktivieren:
```
Command: HALDEBUG
→ Debug-Modus: EIN
```

Im Debug-Modus werden zusaetzliche DEBUG-Eintraege ins Log geschrieben und auf der Command-Line angezeigt.

## Context-Namespace

Prefix: `HAL:` (HoeheAufLinie)

### Kernfunktionen

| Funktion | Beschreibung |
|----------|--------------|
| HAL:ensure-init | Lazy-Init (erster Aufruf) |
| HAL:calc-interpolated-height | Skalarprojektion Hoehe berechnen |
| HAL:calc-point-for-height | Umgekehrte Interpolation (Hoehe -> Punkt) |
| HAL:create-perp-xline | XLINE im rechten Winkel erstellen |
| HAL:create-line-ab | Linie A-B erstellen (LINE oder XLINE) |
| HAL:update-construction-line | Konstruktionslinie aktualisieren |
| HAL:insert-block | Hoehenkoten-Block einfuegen |
| HAL:block-exists-at-position | Duplikat-Pruefung (BKS->WKS) |
| HAL:ensure-hk-layer | HK-Layer erstellen mit kopierten Properties |
| HAL:show-settings | DCL Settings-Dialog |
| HAL:dwg-custom-read | DWG Custom Property lesen |
| HAL:dwg-custom-write | DWG Custom Property schreiben |
| HAL:read-dwg-scale | Skalierung aus DWG lesen |
| HAL:write-dwg-scale | Skalierung in DWG schreiben |
| HAL:safe-variant-value | VLA String/Variant Handler |
| HAL:log-write | Log-Eintrag schreiben |
| HAL:log-rotate | Log-Rotation (max 5 Sessions) |
| HAL:load-config | Config laden |
| HAL:save-config | Config speichern |
| HAL:load-library | BlockImport.lsp laden (3-Fallback) |

### Globale Variablen

| Variable | Beschreibung |
|----------|--------------|
| *HAL:version* | Script-Version |
| *HAL:initialized* | Init-Status (T/nil) |
| *HAL:debug-mode* | Debug-Modus (T/nil) |
| *HAL:log-session-id* | Aktueller Log-Dateiname |
| *HAL:blockname* | Name des Hoehenkoten-Blocks |
| *HAL:last-height* | Letzte eingegebene Hoehe |
| *HAL:use-layer-suffix* | HK-Layer Suffix aktiv (T/nil) |
| *HAL:layer-suffix* | Layer-Suffix Name |
| *HAL:lineab-mode* | Linie A-B Modus (LINE/XLINE) |
| *HAL:lineab-keep* | Linie A-B behalten (T/nil) |
| *HAL:xline-keep* | Konstruktionslinie behalten (T/nil) |

## Vergleich

| Feature | SetHK | HoeheAufLinie |
|---------|-------|---------------|
| Einzelpunkte setzen | Ja | Nein |
| Interpolation | Nein | Ja |
| Konstruktionslinie | Nein | Ja |
| Linie A-B Anzeige | Nein | Ja |
| XY-Skalierung (DWG) | Ja | Ja |
| DCL Settings-Dialog | Ja | Ja |
| HK-Layer Suffix | Ja | Ja |
| Context-Namespace | SetHK | HAL |
| BlockImport.lsp | Ja | Ja |
| Session-Logging | Ja | Ja |
| Lazy-Init | Ja | Ja |

**Wann was verwenden:**
- **SetHK:** Einzelne Hoehenkoten an beliebigen Punkten
- **HoeheAufLinie:** Mehrere Punkte entlang einer Linie interpolieren

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet (via Lazy-Init)
- **AutoCAD LT:** Nicht kompatibel (kein AutoLISP Support)
- **Abhaengigkeiten:** BlockImport.lsp (v1.5.0+)
- **AppData:** %APPDATA%\AutoCAD\Lisp\HoeheAufLinie\
- **Namespace:** HAL (HoeheAufLinie)
- **DWG Custom Property:** HoehenkoteScale (Skalierung pro Zeichnung)
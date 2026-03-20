# HoeheAufLinie

Automatische Hoeheninterpolation entlang einer Linie zwischen zwei Fixpunkten.
Speziell fuer Vermessungsarbeiten mit BlockImport.lsp Integration.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| HoeheAufLinie | Hoeheninterpolation entlang Linie (S/K/E Keywords) |
| HAL | Kurzbefehl fuer HoeheAufLinie |
| HALSETTINGS | Einstellungen (Skalierung, Block, Layer, Linien, Debug) |
| HALBlock | Block-Verwaltung oeffnen (DCL-Dialog) |
| HALDEBUG | Debug-Modus ein/aus |

## Features

- Automatische Hoehenberechnung durch Skalarprojektion (2D)
- Konstruktionslinie (XLINE) bei Zielhoehe im rechten Winkel (Keyword K)
- Linie A-B zwischen Fixpunkten (LINE oder XLINE Modus waehlbar)
- DCL Settings-Dialog fuer alle Einstellungen (Keyword E)
- HK-Layer Suffix: Bloecke auf eigenen Layer mit kopierten Properties
- Skalierung pro Zeichnung als DWG Custom Property (reist mit der Datei)
- Konfigurierbarer Default fuer neue Zeichnungen
- Block-Name wird zentral von BlockImport.lsp gesteuert
- Auto-Open Block Manager wenn kein Block konfiguriert
- HOEHE-Attribut mit 2 Dezimalstellen + 3DEZ-Attribut (wie SetHK)
- Linie A-B und Konstruktionslinie: behalten oder entfernen (konfigurierbar)
- Funktioniert auch fuer Punkte ausserhalb der Strecke (Extrapolation)
- Gelbe Linie verlaengert sich bei Extrapolation automatisch (LINE-Modus)
- XLINE ist OSNAP-fangbar fuer praezise Punktwahl
- Session-basiertes Logging mit Rotation (max 5 Sessions)
- Lazy-Init Pattern fuer DokaCAD-Kompatibilitaet
- Persistente Konfiguration in %APPDATA%

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausfuehren
2. `HoeheAufLinie.lsp` auswaehlen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufuegen

### Abhaengigkeiten

- `BlockImport.lsp` muss im selben Ordner, Support-Pfad oder `lib/` Unterordner liegen
- Wird automatisch gefunden (3-Fallback Pfadsuche) oder per File-Dialog abgefragt
- Pfad wird persistent in Config gespeichert und ist im Settings-Dialog aenderbar

## Block-Anforderungen

Der Hoehenkoten-Block kann frei erstellt werden. Er muss als DWG-Datei vorliegen und wird ueber BlockImport.lsp in die Zeichnung importiert.

### Pflicht-Attribut

| Attribut-Tag | Typ | Beschreibung |
|-------------|-----|--------------|
| `HOEHE` | String | Hoehenwert mit 2 Dezimalstellen und Vorzeichen, z.B. `+333.12` |

### Optionales Attribut

| Attribut-Tag | Typ | Beschreibung |
|-------------|-----|--------------|
| `3DEZ` | String | Dritte Dezimalstelle, nur wenn ungleich 0, z.B. `5` bei 333.125 |

### Formatierung der Hoehe

| Eingabe | HOEHE | 3DEZ |
|---------|-------|------|
| 333.125 | +333.12 | 5 |
| 333.120 | +333.12 | (leer) |
| -12.300 | -12.30 | (leer) |
| 0.000 | %%p0.00 | (leer) |

Das Sonderzeichen `%%p` erzeugt in AutoCAD das Plus-Minus-Zeichen (±).

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

**Beispiel - Erste Verwendung (kein Block konfiguriert):**
```
Command: HAL
→ Kein Block konfiguriert! Block-Verwaltung wird geoeffnet...
→ DCL Block-Manager: Block-DWG auswaehlen
→ Block wird automatisch importiert
→ Weiter mit Fixpunkt 1...
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

### HALSETTINGS - Einstellungen

Oeffnet den Einstellungen-Dialog (DCL) mit allen konfigurierbaren Optionen. Dialog-Aufbau ist einheitlich mit SetHK.

**Aufruf:**
```
Command: HALSETTINGS
```

**Einstellungen im Dialog:**

| Bereich | Feld | Beschreibung |
|---------|------|--------------|
| XY-Skalierung | Aktuelle Zeichnung | Skalierung fuer diese DWG (Custom Property) |
| XY-Skalierung | Default (neue Zeichnungen) | Fallback fuer DWGs ohne eigene Skalierung |
| Hoehenkoten-Block | Aktueller Block | Read-only Anzeige des aktiven Blocks |
| Hoehenkoten-Block | Block-Verwaltung oeffnen... | Oeffnet DCL Block-Manager |
| Layer | Eigener Layer fuer Hoehenkoten | Toggle: Automatische Layer-Erstellung |
| Layer | Suffix (nach _) | Frei konfigurierbares Suffix mit Live-Vorschau |
| Linie A-B (gelb) | Modus | LINE (nur zwischen A-B) oder XLINE (unendlich) |
| Linie A-B (gelb) | Am Ende behalten | Toggle: Linie nach ESC nicht loeschen |
| Konstruktionslinie (rot) | Am Ende behalten | Toggle: XLINE nach ESC nicht loeschen |
| BlockImport.lsp | Pfad | Pfad zur BlockImport.lsp Library |
| BlockImport.lsp | Durchsuchen... | File-Dialog zur Pfadauswahl |
| Debug | Debug-Modus aktivieren | Toggle: Zusaetzliche DEBUG-Eintraege im Log |

### HALBlock - Block-Verwaltung

Oeffnet den DCL Block-Manager von BlockImport.lsp mit Context "HAL".

**Aufruf:**
```
Command: HALBlock
```

Siehe BlockImport README fuer Details zum Block-Manager.

### HALDEBUG - Debug-Modus

Schaltet Debug-Ausgaben auf der Command-Line ein/aus. Die Log-Datei wird unabhaengig davon immer geschrieben. Debug-Modus wird persistent in der Config gespeichert.

**Aufruf:**
```
Command: HALDEBUG
→ Debug-Modus: EIN
```

Im Debug-Modus werden zusaetzliche DEBUG-Eintraege ins Log geschrieben und auf der Command-Line angezeigt (z.B. Punkt-Koordinaten, Skalarwerte, VLA-Aufrufe).

## Layer-Verhalten

Wenn der Layer-Suffix aktiviert ist (Standard: ein), wird der Hoehenkoten-Block automatisch auf einen eigenen Layer gesetzt:

| Aktueller Layer | Suffix | Block-Layer |
|-----------------|--------|-------------|
| `Vermessung` | `HK` | `Vermessung_HK` |
| `Vermessung_HK` | `HK` | `Vermessung_HK` (direkt, keine Kopie) |
| `Gelaende` | `KOTE` | `Gelaende_KOTE` |
| `0` | `HK` | `0_HK` |

Der Layer wird automatisch erstellt falls er nicht existiert. Alle Eigenschaften werden vom aktuellen Layer kopiert: Farbe (ACI und TrueColor), Linientyp, Linienstaerke, Plot-Flag und Transparenz. Wenn der aktuelle Layer bereits auf `_<Suffix>` endet, wird er direkt verwendet ohne einen neuen anzulegen.

## Skalierung

Die Skalierung wird **pro Zeichnung** als DWG Custom Property `HAL_Scale` gespeichert. Dadurch reist die Skalierung mit der Zeichnungsdatei mit, auch bei Weitergabe an andere PCs.

**Reihenfolge beim Lesen:**
1. DWG Custom Property `HAL_Scale` → gefunden? → verwenden
2. Config `DEFAULT_SCALE` → gefunden? → verwenden
3. Fallback: 1.0

Die Skalierung betrifft nur X und Y. Z bleibt immer 1.0.

## DWG Custom Properties

HoeheAufLinie speichert folgende Properties in den Zeichnungseigenschaften (Benutzerspezifisch):

| Property | Beschreibung |
|----------|--------------|
| `HAL_Scale` | XY-Skalierung fuer diese Zeichnung |
| `HAL_Block` | Block-Name fuer diese Zeichnung (von BlockImport gesetzt) |

Sichtbar unter Datei → Zeichnungseigenschaften → Benutzerspezifisch.

## Konfiguration

### AppData-Ordner

Alle Daten werden gespeichert in:
```
%APPDATA%\AutoCAD\Lisp\HoeheAufLinie\
  ├── Log\        (Session-Logs)
  ├── Config\     (Konfiguration)
  └── Backup\     (reserviert)
```

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\Lisp\HoeheAufLinie\Config\HoeheAufLinie.cfg
```

**Format:**
```
VERSION=2.5.2
BLOCKIMPORTPATH=D:\OneDrive\...\lisp\lib\BlockImport.lsp
DEBUG=0
USE_LAYER_SUFFIX=1
LAYER_SUFFIX=HK
LINEAB_MODE=LINE
LINEAB_KEEP=0
XLINE_KEEP=0
DEFAULT_SCALE=1.000000
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
- `DEFAULT_SCALE` - Standard-Skalierung fuer neue Zeichnungen

### Einstellungen aendern

Ueber den Befehl `HALSETTINGS` oder das Keyword `E` waehrend der Punktwahl.

## Log-Datei

### Speicherort

```
%APPDATA%\AutoCAD\Lisp\HoeheAufLinie\Log\HoeheAufLinie_YYYYMMDD_HHMMSS.log
```

Pro Session wird eine neue Log-Datei erstellt.
Maximal 5 Session-Logs werden aufbewahrt, aeltere werden automatisch geloescht.

### Log-Format

```
[2026-03-20 14:30:22] [INFO ] === HoeheAufLinie v2.5.2 initialisiert ===
[2026-03-20 14:30:22] [INFO ] Config geladen
[2026-03-20 14:30:25] [INFO ] Befehl HoeheAufLinie gestartet
[2026-03-20 14:30:28] [INFO ] Fixpunkt 1: (1234.567 890.123)
[2026-03-20 14:30:28] [INFO ] Hoehe 1: 322.0000
[2026-03-20 14:30:30] [INFO ] Linie A-B erstellt (LINE)
[2026-03-20 14:30:35] [INFO ] Interpolation: (1237.000 892.500) -> 333.1200
[2026-03-20 14:30:35] [INFO ] Block gesetzt: +333.12 Z=333.120 Scale=1.00
[2026-03-20 14:30:38] [INFO ] Konstruktionslinie bei Hoehe 327.50
[2026-03-20 14:30:40] [INFO ] Benutzer-Abbruch: *Abbruch*
[2026-03-20 14:30:40] [INFO ] Cleanup: Linie A-B entfernt, Konstruktionslinie entfernt
[2026-03-20 14:30:40] [INFO ] Befehl HoeheAufLinie beendet
```

### Log-Level

| Level | Bedeutung |
|-------|-----------|
| INFO  | Normaler Ablauf |
| WARN  | Unerwartetes, nicht kritisch |
| ERROR | Fehler, Funktion abgebrochen |
| DEBUG | Detaillierte Infos (nur bei Debug-Modus) |

## Context-Namespace

Prefix: `HAL:` (HoeheAufLinie)

### Kernfunktionen

| Funktion | Beschreibung |
|----------|--------------|
| HAL:ensure-init | Lazy-Init (erster Aufruf) |
| HAL:calc-interpolated-height | Skalarprojektion Hoehe berechnen |
| HAL:calc-point-for-height | Umgekehrte Interpolation (Hoehe → Punkt) |
| HAL:create-perp-xline | XLINE im rechten Winkel erstellen |
| HAL:create-line-ab | Linie A-B erstellen (LINE oder XLINE) |
| HAL:update-construction-line | Konstruktionslinie aktualisieren |
| HAL:insert-block | Hoehenkoten-Block einfuegen mit HOEHE + 3DEZ |
| HAL:ensure-three-decimals | Hoehe auf 3 Dezimalstellen formatieren |
| HAL:block-exists-at-position | Duplikat-Pruefung (BKS→WKS) |
| HAL:ensure-hk-layer | HK-Layer erstellen mit kopierten Properties |
| HAL:show-settings | DCL Settings-Dialog |
| HAL:write-settings-dcl | DCL Temp-Datei schreiben |
| HAL:dwg-custom-read | DWG Custom Property lesen |
| HAL:dwg-custom-write | DWG Custom Property schreiben |
| HAL:read-dwg-scale | Skalierung aus DWG lesen |
| HAL:write-dwg-scale | Skalierung in DWG schreiben |
| HAL:safe-variant-value | VLA String/Variant Handler |
| HAL:log-write | Log-Eintrag schreiben |
| HAL:log-rotate | Log-Rotation (max 5 Sessions) |
| HAL:load-config | Config laden |
| HAL:save-config | Config speichern |
| HAL:load-config-value | Einzelnen Config-Wert lesen |
| HAL:save-config-value | Einzelnen Config-Wert schreiben |
| HAL:load-library | BlockImport.lsp laden (3-Fallback) |
| HAL:cancel-p | Cancel-Erkennung (DE+EN) |

### Globale Variablen

| Variable | Beschreibung |
|----------|--------------|
| *HAL:version* | Script-Version |
| *HAL:initialized* | Init-Status (T/nil) |
| *HAL:debug-mode* | Debug-Modus (T/nil) |
| *HAL:log-session-id* | Aktueller Log-Dateiname |
| *HAL:last-height* | Letzte eingegebene Hoehe |
| *HAL:use-layer-suffix* | HK-Layer Suffix aktiv (T/nil) |
| *HAL:layer-suffix* | Layer-Suffix Name |
| *HAL:lineab-mode* | Linie A-B Modus ("LINE"/"XLINE") |
| *HAL:lineab-keep* | Linie A-B behalten (T/nil) |
| *HAL:xline-keep* | Konstruktionslinie behalten (T/nil) |
| *HAL:blockimport-path* | Pfad zu BlockImport.lsp |

## Vergleich

| Feature | SetHK | HoeheAufLinie |
|---------|-------|---------------|
| Einzelpunkte setzen | Ja | Nein |
| Interpolation | Nein | Ja |
| Konstruktionslinie | Nein | Ja (rot, XLINE) |
| Linie A-B Anzeige | Nein | Ja (gelb, LINE/XLINE) |
| XY-Skalierung (pro DWG) | Ja | Ja |
| Default-Skalierung | Ja | Ja |
| Eigener Layer | Ja (konfigurierbar) | Ja (konfigurierbar) |
| Einstellungen-Dialog | Ja (DCL) | Ja (DCL) |
| BlockImport.lsp | Ja (zentral) | Ja (zentral) |
| HOEHE + 3DEZ Attribute | Ja | Ja |
| BlockImport.lsp Pfad | Ja (im Dialog) | Ja (im Dialog) |
| Log-Datei | Ja | Ja |
| Context-Namespace | SetHK | HAL |
| Lazy-Init | Ja | Ja |

**Wann was verwenden:**
- **SetHK:** Einzelne Hoehenkoten an beliebigen Punkten setzen
- **HoeheAufLinie:** Mehrere Punkte entlang einer Linie interpolieren

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet (via Lazy-Init)
- **AutoCAD LT:** Nicht kompatibel (kein AutoLISP Support)
- **Abhaengigkeiten:** BlockImport.lsp (lib/)
- **AppData:** %APPDATA%\AutoCAD\Lisp\HoeheAufLinie\
- **Namespace:** HAL (HoeheAufLinie)
- **DWG Custom Properties:** HAL_Scale, HAL_Block
- **BlockImport Context:** "HAL"

### Bekannte Einschraenkungen

- DWG Custom Properties verwenden direkte VLA-Calls statt `vl-catch-all-apply` mit Lambda, da letzteres pass-by-reference bei `GetCustomByIndex` bricht.
- Property-Keys verwenden Unterstrich statt Doppelpunkt (AutoCAD verbietet `:` in Custom Property Keys).
- Die Hoehenberechnung erfolgt durch 2D-Skalarprojektion. Z-Koordinaten der Fixpunkte werden ignoriert, nur die eingegebenen Hoehenwerte zaehlen.

---

**Version:** 2.5.2
**Datum:** 2026-03-20
**Autor:** Herbert Schrotter
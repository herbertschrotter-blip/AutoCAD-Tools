# SetHoehenkote

Automatisches Setzen von Hoehenkoten-Bloecken in AutoCAD.
Speziell fuer Leica-Vermessungsarbeiten mit konfigurierbarer Skalierung pro Zeichnung.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| SetHK | Hoehenkote-Block an gewaehltem Punkt setzen |
| HKSETTINGS | Einstellungen (Skalierung, Block, Layer, Pfad, Debug) |
| HKBLOCK | Block-Verwaltung (Liste/Standard/Hinzufuegen/Entfernen) |

## Features

- Skalierung pro Zeichnung (DWG Custom Property, reist mit der Datei)
- Konfigurierbarer Default fuer neue Zeichnungen
- Automatischer Layer mit konfigurierbarem Suffix (z.B. `_HK`, `_KOTE`)
- Einstellungen-Dialog (DCL) mit Live-Vorschau fuer Layer-Suffix
- Einstellungen direkt aus SetHK erreichbar (Keyword `E`)
- Ausfuehrliches Session-Logging (max 5 Sessions)
- Persistente Konfiguration in %APPDATA%
- Lazy-Init fuer DokaCAD-Kompatibilitaet

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausfuehren
2. `SetHoehenkote.lsp` auswaehlen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufuegen

### Abhaengigkeiten

- `BlockImport.lsp` muss im selben Ordner, Support-Pfad oder `lib/` Unterordner liegen
- Wird beim ersten Befehlsaufruf automatisch gesucht (3-Fallback Pfadaufloesung)
- Falls nicht gefunden: File-Dialog zur manuellen Auswahl, Pfad wird gespeichert

## Block-Anforderungen

Der Hoehenkoten-Block kann frei erstellt werden. Er muss als DWG-Datei vorliegen und wird ueber BlockImport.lsp in die Zeichnung importiert.

### Pflicht-Attribut

| Attribut-Tag | Typ | Beschreibung |
|-------------|-----|--------------|
| `HOEHE` | String | Hoehenwert mit Vorzeichen. Wird automatisch gefuellt, z.B. `+322.45` oder `-12.30` oder `%%p0.00` (fuer Hoehe 0) |

### Optionales Attribut

| Attribut-Tag | Typ | Beschreibung |
|-------------|-----|--------------|
| `3DEZ` | String | Dritte Dezimalstelle der Hoehe. Wird nur gefuellt wenn die 3. Dezimalstelle ungleich 0 ist. Z.B. bei Hoehe 322.456 wird `3DEZ` auf `6` gesetzt |

### Formatierung der Hoehe

Die Hoehe wird im Attribut `HOEHE` als 2-Dezimalstellen-Wert mit Vorzeichen gespeichert:

| Eingabe | HOEHE | 3DEZ |
|---------|-------|------|
| 322.456 | +322.45 | 6 |
| 322.450 | +322.45 | (leer) |
| -12.300 | -12.30 | (leer) |
| 0.000 | %%p0.00 | (leer) |

Das Sonderzeichen `%%p` erzeugt in AutoCAD das Plus-Minus-Zeichen (±).

### Block erstellen

1. Neue DWG-Datei erstellen
2. Block mit `ATTDEF` erstellen:
   - Tag `HOEHE`: Sichtbar, Texthoehe nach Bedarf
   - Tag `3DEZ` (optional): Sichtbar, kleinere Texthoehe, positioniert nach der 2. Dezimalstelle
3. Block definieren (`BLOCK` Befehl)
4. DWG speichern
5. In HKSETTINGS oder HKBLOCK den Pfad zur DWG konfigurieren

### Empfohlener Block-Name

- `BLK_Hoehenkote` (Standard)
- Kann beliebig benannt und in HKSETTINGS geaendert werden

## Verwendung

### SetHK - Hoehenkote setzen

Platziert einen Hoehenkoten-Block an einem gewaehlten Punkt. Die Skalierung wird pro Zeichnung gespeichert.

**Aufruf:**
```
Command: SetHK
```

**Optionen waehrend Punktwahl:**
- `S` - Skalierung aendern (wird in DWG gespeichert)
- `E` - Einstellungen oeffnen (DCL-Dialog)

**Workflow - Erste Verwendung:**
```
Command: SetHK
Punkt waehlen [Skalierung/Einstellungen] <1.00>: [Klick]
Hoehe eingeben: 322.456
Hoehenkote gesetzt: +322.45 | Z=322.456 | XY-Scale=1.00 | Layer=Vermessung_HK
```

**Workflow - Skalierung aendern:**
```
Command: SetHK
Punkt waehlen [Skalierung/Einstellungen] <1.00>: S
Neue XY-Skalierung <1.00>: 0.50
Skalierung gespeichert: 0.50 (in DWG)
Punkt waehlen [Skalierung/Einstellungen] <0.50>: [Klick]
Hoehe eingeben <322.456>: 323.100
Hoehenkote gesetzt: +323.10 | Z=323.100 | XY-Scale=0.50 | Layer=Vermessung_HK
```

**Workflow - Einstellungen oeffnen:**
```
Command: SetHK
Punkt waehlen [Skalierung/Einstellungen] <0.50>: E
→ DCL-Dialog oeffnet sich
→ Aenderungen vornehmen, OK klicken
Punkt waehlen [Skalierung/Einstellungen] <0.50>: [Klick]
```

### HKSETTINGS - Einstellungen

Oeffnet den Einstellungen-Dialog (DCL) mit allen konfigurierbaren Optionen.

**Aufruf:**
```
Command: HKSETTINGS
```

**Einstellungen im Dialog:**

| Bereich | Feld | Beschreibung |
|---------|------|--------------|
| XY-Skalierung | Aktuelle Zeichnung | Skalierung fuer diese DWG (Custom Property) |
| XY-Skalierung | Default (neue Zeichnungen) | Fallback fuer DWGs ohne eigene Skalierung |
| Hoehenkoten-Block | Block-Name | Name des zu verwendenden Blocks |
| Hoehenkoten-Block | Block-Verwaltung oeffnen... | Oeffnet HKBLOCK Manager |
| Layer | Eigener Layer fuer Hoehenkoten | Toggle: Automatische Layer-Erstellung |
| Layer | Suffix (nach _) | Frei konfigurierbares Suffix mit Live-Vorschau |
| BlockImport.lsp | Pfad | Pfad zur BlockImport.lsp Library |
| BlockImport.lsp | Durchsuchen... | File-Dialog zur Pfadauswahl |
| Debug | Debug-Modus aktivieren | Toggle: Zusaetzliche DEBUG-Eintraege im Log |

### HKBLOCK - Block-Verwaltung

Interaktives Keyword-Menue zur Verwaltung der konfigurierten Hoehenkoten-Bloecke.

**Aufruf:**
```
Command: HKBLOCK
```

**Optionen:**
- `L` - Liste aller konfigurierten Bloecke
- `S` - Standard-Block waehlen
- `H` - Neuen Block hinzufuegen
- `E` - Block entfernen
- `A` - Abbrechen

## Layer-Verhalten

Wenn der Layer-Suffix aktiviert ist (Standard: ein), wird der Hoehenkoten-Block automatisch auf einen eigenen Layer gesetzt:

| Aktueller Layer | Suffix | Block-Layer |
|-----------------|--------|-------------|
| `Vermessung` | `HK` | `Vermessung_HK` |
| `Vermessung_HK` | `HK` | `Vermessung_HK` (direkt, keine Kopie) |
| `Gelaende` | `KOTE` | `Gelaende_KOTE` |
| `0` | `HK` | `0_HK` |

Der Layer wird automatisch erstellt falls er nicht existiert. Farbe und Linientyp werden vom aktuellen Layer kopiert. Wenn der aktuelle Layer bereits auf `_<Suffix>` endet, wird er direkt verwendet ohne einen neuen anzulegen.

## Skalierung

Die Skalierung wird **pro Zeichnung** als DWG Custom Property `SetHK_Scale` gespeichert. Dadurch reist die Skalierung mit der Zeichnungsdatei mit, auch bei Weitergabe an andere PCs.

**Reihenfolge beim Lesen:**
1. DWG Custom Property `SetHK_Scale` → gefunden? → verwenden
2. Config `DEFAULT_SCALE` → gefunden? → verwenden
3. Fallback: 1.0

Die Skalierung betrifft nur X und Y. Z bleibt immer 1.0.

Der Wert ist sichtbar unter Datei → Zeichnungseigenschaften → Benutzerdefiniert.

## Konfiguration

### AppData-Ordner

Alle Daten werden gespeichert in:
```
%APPDATA%\AutoCAD\Lisp\SetHoehenkote\
  ├── Log\        (Session-Logs)
  ├── Config\     (Konfiguration)
  └── Backup\     (reserviert)
```

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\Lisp\SetHoehenkote\Config\SetHoehenkote.cfg
```

**Format:**
```
LAYER_SUFFIX=HK
BLOCKNAME=BLK_Hoehenkote
DEFAULT_SCALE=1.000000
BLOCKIMPORT_PATH=D:\Pfad\zu\lib\BlockImport.lsp
USE_LAYER_SUFFIX=1
```

**Einstellungen:**
- `LAYER_SUFFIX` - Suffix fuer automatischen Layer (nach `_`)
- `BLOCKNAME` - Name des Hoehenkoten-Blocks
- `DEFAULT_SCALE` - Standard-Skalierung fuer neue Zeichnungen
- `BLOCKIMPORT_PATH` - Pfad zur BlockImport.lsp Library
- `USE_LAYER_SUFFIX` - Automatischer Layer ein/aus (1/0)

### Einstellungen aendern

Ueber den Befehl `HKSETTINGS` oder das Keyword `E` im SetHK-Befehl.

## Log-Datei

### Speicherort

```
%APPDATA%\AutoCAD\Lisp\SetHoehenkote\Log\SetHoehenkote_YYYYMMDD_HHMMSS.log
```

Pro Session wird eine neue Log-Datei erstellt.
Maximal 5 Session-Logs werden aufbewahrt, aeltere werden automatisch geloescht.

### Log-Format

```
[2026-03-18 14:30:22] [INFO ] === SetHoehenkote v2.3.1 ===
[2026-03-18 14:30:22] [INFO ] Befehl SetHK gestartet
[2026-03-18 14:30:22] [INFO ] Zeichnung: Projekt_001.dwg
[2026-03-18 14:30:25] [INFO ] Punkt: (1234.567 890.123 0.000) Scale=1.00
[2026-03-18 14:30:28] [INFO ] Hoehe: 322.456
[2026-03-18 14:30:28] [INFO ] Layer erstellt: Vermessung_HK (Farbe=7, Linientyp=Continuous)
[2026-03-18 14:30:28] [INFO ] Block gesetzt: +322.45 | Z=322.456 | Scale=1.00 | Layer=Vermessung_HK
[2026-03-18 14:30:30] [INFO ] User: Abbruch (Funktion abgebrochen)
[2026-03-18 14:30:30] [INFO ] Befehl SetHK beendet (Error/Cancel)
```

### Log-Level

| Level | Bedeutung |
|-------|-----------|
| INFO | Normaler Ablauf |
| WARN | Unerwartetes, nicht kritisch |
| ERROR | Fehler, Funktion abgebrochen |
| DEBUG | Detaillierte Infos (nur bei Debug-Modus) |

### Debug-Modus

Debug-Modus aktivieren ueber HKSETTINGS (Toggle im Dialog).

Im Debug-Modus werden zusaetzliche DEBUG-Eintraege ins Log geschrieben (z.B. Punkt-Koordinaten, VLA-Aufrufe, Layer-Entscheidungen).

## Context-Namespace

Prefix: `SetHK:` (SetHoehenkote)

### Wichtige Funktionen

| Funktion | Beschreibung |
|----------|--------------|
| SetHK:ensure-init | Lazy-Init (VLA + BlockImport laden) |
| SetHK:log-write | Log-Eintrag schreiben |
| SetHK:load-config | Config laden |
| SetHK:save-config | Config speichern |
| SetHK:read-scale | Skalierung lesen (DWG → Config → 1.0) |
| SetHK:read-dwg-scale | Skalierung aus DWG Custom Property |
| SetHK:write-dwg-scale | Skalierung in DWG Custom Property |
| SetHK:ensure-hk-layer | Layer mit Suffix erstellen/pruefen |
| SetHK:insert-block | Block einfuegen mit Attributen |
| SetHK:cancel-p | Cancel-Erkennung (DE+EN) |
| SetHK:safe-variant-value | VLA String/Variant Handler |

### Globale Variablen

| Variable | Beschreibung |
|----------|--------------|
| *SetHK:version* | Script-Version |
| *SetHK:initialized* | Init-Status (T/nil) |
| *SetHK:debug-mode* | Debug ein/aus |
| *SetHK:blockname* | Aktueller Block-Name |
| *SetHK:layer-suffix* | Aktuelles Layer-Suffix |
| *SetHK:use-layer-suffix* | Layer-Suffix aktiv (T/nil) |
| *SetHK:last-height* | Zuletzt eingegebene Hoehe |
| *SetHK:log-session-id* | Aktueller Log-Dateiname |

## Vergleich

| Feature | SetHK | HoeheAufLinie |
|---------|-------|---------------|
| Einzelpunkte setzen | Ja | Nein |
| Interpolation | Nein | Ja |
| Konstruktionslinie | Nein | Ja |
| XY-Skalierung | Ja (pro DWG) | Ja |
| Eigener Layer | Ja (konfigurierbar) | Nein |
| Einstellungen-Dialog | Ja (DCL) | Nein |
| BlockImport.lsp | Ja | Ja |
| Log-Datei | Ja | Ja |

**Wann was verwenden:**
- **SetHK:** Einzelne Hoehenkoten an beliebigen Punkten setzen
- **HoeheAufLinie:** Mehrere Punkte entlang einer Linie interpolieren

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet (Lazy-Init)
- **AutoCAD LT:** Nicht kompatibel (kein AutoLISP Support)
- **Abhaengigkeiten:** BlockImport.lsp (lib/)
- **AppData:** %APPDATA%\AutoCAD\Lisp\SetHoehenkote\
- **Namespace:** SetHK (SetHoehenkote)
- **DWG Custom Property:** SetHK_Scale (Skalierung pro Zeichnung)
# SetHoehenkote

Automatisches Setzen von Hoehenkoten-Bloecken in AutoCAD.
Speziell fuer Vermessungsarbeiten mit konfigurierbarer Skalierung pro Zeichnung.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| SetHK | Hoehenkote-Block an gewaehltem Punkt setzen |
| HKSETTINGS | Einstellungen (Skalierung, Block, Layer, Pfad, Debug) |
| HKBLOCK | Block-Verwaltung oeffnen (DCL-Dialog) |

## Features

- Skalierung pro Zeichnung (DWG Custom Property, reist mit der Datei)
- Konfigurierbarer Default fuer neue Zeichnungen
- Automatischer Layer mit konfigurierbarem Suffix (z.B. `_HK`, `_KOTE`)
- Einstellungen-Dialog (DCL) mit Live-Vorschau fuer Layer-Suffix
- Einstellungen direkt aus SetHK erreichbar (Keyword `E`)
- Block-Name wird zentral von BlockImport.lsp gesteuert
- Auto-Open Block Manager wenn kein Block konfiguriert
- HOEHE-Attribut mit 2 Dezimalstellen + optionales 3DEZ-Attribut
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
- Pfad ist im Settings-Dialog unter "BlockImport.lsp → Durchsuchen..." aenderbar

## Block-Anforderungen

Der Hoehenkoten-Block kann frei erstellt werden. Er muss als DWG-Datei vorliegen und wird ueber BlockImport.lsp in die Zeichnung importiert.

### Pflicht-Attribut

| Attribut-Tag | Typ | Beschreibung |
|-------------|-----|--------------|
| `HOEHE` | String | Hoehenwert mit 2 Dezimalstellen und Vorzeichen, z.B. `+322.45` |

### Optionales Attribut

| Attribut-Tag | Typ | Beschreibung |
|-------------|-----|--------------|
| `3DEZ` | String | Dritte Dezimalstelle, nur wenn ungleich 0, z.B. `6` bei 322.456 |

### Formatierung der Hoehe

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
5. In HKBLOCK den Pfad zur DWG konfigurieren

### Empfohlener Block-Name

- `BLK_Hoehenkote` (Standard)
- Kann beliebig benannt und ueber den Block-Manager geaendert werden

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

**Workflow - Erste Verwendung (kein Block konfiguriert):**
```
Command: SetHK
→ Kein Block konfiguriert! Block-Verwaltung wird geoeffnet...
→ DCL Block-Manager: Block-DWG auswaehlen
→ Block wird automatisch importiert und als Standard gesetzt
Punkt waehlen [Skalierung/Einstellungen] <1.00>: [Klick]
Hoehe eingeben: 322.456
→ Hoehenkote gesetzt: +322.45 | Z=322.456 | XY-Scale=1.00 | Layer=Vermessung_HK
```

**Workflow - Normale Verwendung:**
```
Command: SetHK
Punkt waehlen [Skalierung/Einstellungen] <1.00>: [Klick]
Hoehe eingeben: 322.456
→ Hoehenkote gesetzt: +322.45 | Z=322.456 | XY-Scale=1.00 | Layer=Vermessung_HK
Punkt waehlen [Skalierung/Einstellungen] <1.00>: [Klick]
Hoehe eingeben <322.456>: 323.100
→ Hoehenkote gesetzt: +323.10 | Z=323.100 | XY-Scale=1.00 | Layer=Vermessung_HK
Punkt waehlen [Skalierung/Einstellungen] <1.00>: [ESC]
```

**Workflow - Skalierung aendern:**
```
Command: SetHK
Punkt waehlen [Skalierung/Einstellungen] <1.00>: S
Neue XY-Skalierung <1.00>: 0.50
→ Skalierung gespeichert: 0.50 (in DWG)
Punkt waehlen [Skalierung/Einstellungen] <0.50>: [Klick]
Hoehe eingeben <322.456>: 323.100
→ Hoehenkote gesetzt: +323.10 | Z=323.100 | XY-Scale=0.50
```

**Workflow - Einstellungen oeffnen:**
```
Command: SetHK
Punkt waehlen [Skalierung/Einstellungen] <0.50>: E
→ DCL-Dialog oeffnet sich
→ Aenderungen vornehmen, OK klicken
Punkt waehlen [Skalierung/Einstellungen] <0.50>: [Klick]
```

---

### HKSETTINGS - Einstellungen

Oeffnet den Einstellungen-Dialog (DCL) mit allen konfigurierbaren Optionen. Dialog-Aufbau ist einheitlich mit HoeheAufLinie.

**Aufruf:**
```
Command: HKSETTINGS
```

**Einstellungen im Dialog:**

| Bereich | Feld | Beschreibung |
|---------|------|--------------|
| XY-Skalierung | Aktuelle Zeichnung | Skalierung fuer diese DWG (Custom Property). Zeigt "(nicht gesetzt)" wenn noch keine Skalierung gespeichert wurde |
| XY-Skalierung | Default (neue Zeichnungen) | Fallback fuer DWGs ohne eigene Skalierung |
| Hoehenkoten-Block | Aktueller Block | Read-only Anzeige des aktiven Blocks (von BlockImport gesteuert) |
| Hoehenkoten-Block | Block-Verwaltung oeffnen... | Oeffnet DCL Block-Manager von BlockImport.lsp |
| Layer | Eigener Layer fuer Hoehenkoten | Toggle: Automatische Layer-Erstellung ein/aus |
| Layer | Suffix (nach _) | Frei konfigurierbares Suffix mit Live-Vorschau (z.B. "HK" → "Vermessung_HK") |
| BlockImport.lsp | Pfad | Aktueller Pfad zur BlockImport.lsp Library |
| BlockImport.lsp | Durchsuchen... | File-Dialog zur Pfadauswahl |
| Debug | Debug-Modus aktivieren | Toggle: Zusaetzliche DEBUG-Eintraege im Log |

**Hinweis:** Der Block-Name kann nicht direkt in HKSETTINGS geaendert werden. Er wird zentral ueber den Block-Manager von BlockImport.lsp gesteuert. Klick auf "Block-Verwaltung oeffnen..." um den Block zu aendern.

---

### HKBLOCK - Block-Verwaltung

Oeffnet den DCL Block-Manager von BlockImport.lsp mit Context "SetHK".

**Aufruf:**
```
Command: HKBLOCK
```

**Beispiel - Block hinzufuegen:**
```
Command: HKBLOCK
→ DCL Block-Manager oeffnet sich
→ Klick "Hinzufuegen"
→ File-Dialog: BLK_Hoehenkote.dwg auswaehlen
→ Block erscheint in Liste, wird als Standard gesetzt
→ "Schliessen"
```

**Beispiel - Block fuer einzelne Zeichnung aendern:**
```
Command: HKBLOCK
→ BLK_Hoehenkote_3DEZ in Liste auswaehlen
→ Klick "Fuer Zeichnung"
→ Nur diese Zeichnung verwendet ab jetzt BLK_Hoehenkote_3DEZ
→ Andere Zeichnungen behalten ihren bisherigen Block
```

Siehe BlockImport README fuer vollstaendige Details zum Block-Manager.

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

Die Skalierung wird **pro Zeichnung** als DWG Custom Property `SetHK_Scale` gespeichert. Dadurch reist die Skalierung mit der Zeichnungsdatei mit, auch bei Weitergabe an andere PCs.

**Reihenfolge beim Lesen:**
1. DWG Custom Property `SetHK_Scale` → gefunden? → verwenden
2. Config `DEFAULT_SCALE` → gefunden? → verwenden
3. Fallback: 1.0

Die Skalierung betrifft nur X und Y. Z bleibt immer 1.0.

Der Wert ist sichtbar unter Datei → Zeichnungseigenschaften → Benutzerspezifisch.

## DWG Custom Properties

SetHK speichert folgende Properties in den Zeichnungseigenschaften (Benutzerspezifisch):

| Property | Beschreibung |
|----------|--------------|
| `SetHK_Scale` | XY-Skalierung fuer diese Zeichnung |
| `SetHK_Block` | Block-Name fuer diese Zeichnung (von BlockImport gesetzt) |

Sichtbar unter Datei → Zeichnungseigenschaften → Benutzerspezifisch.

**Lookup-Reihenfolge fuer Block-Name (via BlockImport):**
1. DWG Custom Property `SetHK_Block` → zeichnungsspezifisch
2. Globaler Standard `*STANDARD:SetHK*` aus BlockImport Config → Fallback
3. nil → Block Manager wird automatisch geoeffnet

Beim ersten Aufruf wird der globale Standard automatisch in die DWG Custom Property uebernommen.

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
VERSION=2.4.1
LAYER_SUFFIX=HK
DEFAULT_SCALE=1.000000
BLOCKIMPORT_PATH=D:\OneDrive\...\lisp\lib\BlockImport.lsp
USE_LAYER_SUFFIX=1
```

**Einstellungen:**
- `VERSION` - Script-Version
- `LAYER_SUFFIX` - Suffix fuer automatischen Layer (nach `_`)
- `DEFAULT_SCALE` - Standard-Skalierung fuer neue Zeichnungen
- `BLOCKIMPORT_PATH` - Pfad zur BlockImport.lsp Library
- `USE_LAYER_SUFFIX` - Automatischer Layer ein/aus (1/0)

**Hinweis:** Block-Name wird nicht in der SetHK Config gespeichert. Er wird zentral von BlockImport.lsp verwaltet (siehe BlockImport README).

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
[2026-03-20 14:30:22] [INFO ] === SetHoehenkote v2.4.1 ===
[2026-03-20 14:30:22] [INFO ] Befehl SetHK gestartet
[2026-03-20 14:30:22] [INFO ] Zeichnung: Projekt_001.dwg
[2026-03-20 14:30:25] [INFO ] Punkt: (1234.567 890.123 0.000) Scale=1.00
[2026-03-20 14:30:28] [INFO ] Hoehe: 322.456
[2026-03-20 14:30:28] [INFO ] DWG Custom Property: SetHK_Block=BLK_Hoehenkote
[2026-03-20 14:30:28] [INFO ] Layer erstellt: Vermessung_HK (Farbe=7, Linientyp=Continuous)
[2026-03-20 14:30:28] [INFO ] Block gesetzt: +322.45 | Z=322.456 | Scale=1.00 | Layer=Vermessung_HK
[2026-03-20 14:30:30] [INFO ] User: Abbruch (Funktion abgebrochen)
[2026-03-20 14:30:30] [INFO ] Befehl SetHK beendet (Error/Cancel)
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

Im Debug-Modus werden zusaetzliche DEBUG-Eintraege ins Log geschrieben (z.B. Punkt-Koordinaten, VLA-Aufrufe, Layer-Entscheidungen, Attribut-Werte).

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
| SetHK:ensure-three-decimals | Hoehe auf 3 Dezimalstellen formatieren |
| SetHK:ensure-hk-layer | Layer mit Suffix erstellen/pruefen |
| SetHK:insert-block | Block einfuegen mit HOEHE + 3DEZ Attributen |
| SetHK:show-settings | DCL Settings-Dialog |
| SetHK:write-settings-dcl | DCL Temp-Datei schreiben |
| SetHK:cancel-p | Cancel-Erkennung (DE+EN) |
| SetHK:safe-variant-value | VLA String/Variant Handler |
| SetHK:dwg-custom-read | DWG Custom Property lesen |
| SetHK:dwg-custom-write | DWG Custom Property schreiben |
| SetHK:load-library | BlockImport.lsp laden (3-Fallback) |

### Globale Variablen

| Variable | Beschreibung |
|----------|--------------|
| *SetHK:version* | Script-Version |
| *SetHK:initialized* | Init-Status (T/nil) |
| *SetHK:debug-mode* | Debug ein/aus |
| *SetHK:block-context* | BlockImport Context ("SetHK") |
| *SetHK:layer-suffix* | Aktuelles Layer-Suffix |
| *SetHK:use-layer-suffix* | Layer-Suffix aktiv (T/nil) |
| *SetHK:last-height* | Zuletzt eingegebene Hoehe |
| *SetHK:log-session-id* | Aktueller Log-Dateiname |
| *SetHK:blockimport-path* | Pfad zu BlockImport.lsp |

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
- **Visual LISP:** vl-load-com wird verwendet (Lazy-Init)
- **AutoCAD LT:** Nicht kompatibel (kein AutoLISP Support)
- **Abhaengigkeiten:** BlockImport.lsp (lib/)
- **AppData:** %APPDATA%\AutoCAD\Lisp\SetHoehenkote\
- **Namespace:** SetHK (SetHoehenkote)
- **DWG Custom Properties:** SetHK_Scale, SetHK_Block
- **BlockImport Context:** "SetHK"

### Bekannte Einschraenkungen

- DWG Custom Properties verwenden direkte VLA-Calls statt `vl-catch-all-apply` mit Lambda, da letzteres pass-by-reference bei `GetCustomByIndex` bricht.
- Property-Keys verwenden Unterstrich statt Doppelpunkt (AutoCAD verbietet `:` in Custom Property Keys).
- `vla-put-BlockEditorBackgrndColor` existiert nicht in AutoCAD 2024. Block Editor Background kann nicht per AutoLISP gesetzt werden.
- `setvar "BKGDCOLOR"` ist read-only in AutoCAD 2024.

---

**Version:** 2.4.1
**Datum:** 2026-03-20
**Autor:** Herbert Schrotter
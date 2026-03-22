# SetBlockZ

Setzt die Z-Koordinate von Vermessungs-Bloecken aus Attribut-Hoehenwerten.
Erstellt optional einen Kopie-Block mit absoluter, relativer und Bau-0-Hoehe als separate Attribute auf eigenen Layern.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| SETBLOCKZ | Block waehlen, Attribut-Hoehe → Z-Koordinate setzen |
| SBZSETTINGS | Einstellungen: Gruppen, Block, Attribute, Farben |
| SBZPURGE | Nicht mehr verwendete Kopie-Block-Definitionen loeschen |
| SBZDEBUG | Debug-Modus ein/aus |

## Features

- Z-Koordinate aus beliebigem Attribut-Wert (Hoehe) auslesen
- Kopie-Block mit 3 Attributen: Absolut, Relativ (nach Bau-0), Bau-0-Referenz
- Gruppenmanagement: mehrere Gruppen pro Zeichnung mit eigenen Einstellungen
- Ein Quell-Block kann in mehreren Gruppen sein (Handle-basierte Zuordnung)
- Hinzufuegen/Entfernen von Bloecken zu bestehenden Gruppen
- Layer-Naming nach OENORM A 6241: `VM_<Gruppe>_<Gruppenname>`
- Attribut-Sichtbarkeit ueber Layer Freeze/Thaw steuerbar
- Block-Ausrichtung nach aktuellem BKS (nicht WKS)
- Attribut-Position gesperrt (nicht verschiebbar)
- Konfigurierbare Schriftart, Farbe, Skalierung pro Gruppe
- Ausfuehrliches Session-Logging (max 5 Sessions)
- Persistente Konfiguration in %APPDATA% und DWG Custom Properties

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausfuehren
2. `SetBlockZ.lsp` auswaehlen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufuegen

### Abhaengigkeiten

Keine externen Abhaengigkeiten. SetBlockZ.lsp ist eigenstaendig.

## Verwendung

### SETBLOCKZ - Hoehen-Bloecke verarbeiten

Hauptbefehl: Block anklicken, Attribut waehlen, Bau-0 eingeben, Bloecke verarbeiten.

**Aufruf:**
```
Command: SETBLOCKZ
```

**Workflow:**
1. Block im Modelspace anklicken → Blockname wird erkannt
2. Attribut fuer Hoehe waehlen (Listbox bei mehreren Attributen)
3. Bau-0-Hoehe: aus DWG Custom Property oder manuell eingeben
4. Alle Instanzen werden gesucht und markiert
5. Auswahl: Fortfahren (alle), Waehlen (interaktiv), Abbruch
6. Z-Modus: Absolut oder Relativ (bei Bau-0 = 0 automatisch Absolut)
7. Gruppenname eingeben (Default = Blockname)
8. Bei bestehender Gruppe: Ueberschreiben, Hinzufuegen oder Abbrechen
9. Verarbeitung: Z-Koordinate setzen + Kopie-Bloecke erstellen

**Optionen bei Bau-0:**
- `A` - Bau-0-Hoehe aendern (auch wenn Custom Property existiert)

**Auswahl-Modus:**
- `F` - Fortfahren: Alle gefundenen Bloecke verarbeiten
- `W` - Waehlen: Interaktive Auswahl (Einzelklick oder Fenster)
- `A` - Abbruch: Befehl beenden

**Beispiel:**
```
Command: SETBLOCKZ
Block waehlen: [Klick auf STAB137]
→ Block: STAB137 (3 Attribute)
Attribut fuer Hoehe: [Listbox → "HOEHE" waehlen]
Bau-0-Hoehe (gespeichert: 320.00) [Aendern]: [Enter]
→ 342 Bloecke 'STAB137' gefunden
342 Bloecke 'STAB137' gefunden. [Fortfahren/Waehlen/Abbruch] <Fortfahren>: F
Z-Koordinate? [Absolut/Relativ]: R
Gruppenname <STAB137>: [Enter]
→ 342 Bloecke verarbeitet
```

### SBZSETTINGS - Einstellungen

Dialog mit Gruppen-Verwaltung, Block-Einstellungen, Attribut-Konfiguration.

**Aufruf:**
```
Command: SBZSETTINGS
```

**Dialog-Bereiche:**

**Gruppe (oben):**
- Dropdown: Vorhandene Gruppen waehlen oder "(keine Gruppe)"
- Loeschen: Gruppe mit allen Kopie-Bloecken entfernen
- Info-Zeile: Anzahl Bloecke in der gewaehlten Gruppe
- Hinzufuegen: Quell-Bloecke interaktiv zur Gruppe hinzufuegen
- Entfernen: Kopie-Bloecke interaktiv aus Gruppe entfernen

**Zeichnung (Box 1):**
- DWG Bau-0: Globaler Bau-0-Wert fuer die gesamte Zeichnung
- Gruppen Bau-0: Eigener Bau-0 pro Gruppe (Toggle "Eigener")

**Modus (Box 2):**
- Kopie-Block einfuegen: Original bleibt unveraendert, Kopie wird erstellt

**Block (Box 3):**
- Name: Basis-Blockname fuer Kopie-Bloecke (z.B. VM_Hoehe)
- Layer: Gegenstandsgruppe fuer Layer-Naming (z.B. HP)
- Farbe: ACI-Farbcode fuer Block-Symbol
- Skalierung: Einfuege-Skalierung (z.B. 10 fuer 1:1000)

**Attribut (Box 4):**
- Schriftart: Auswahl aus 25 Schriftarten (Arial, Calibri, etc.)
- Pro Attribut (Absolut, Relativ, Bau-0): Farbe, Frieren, Suffix

**Buttons:**
- Standard: Alle Felder auf Werkseinstellungen
- Aendern: Gruppe loeschen und mit Dialog-Werten neu erstellen
- Speichern: Einstellungen in Config + DWG Custom Properties schreiben
- Schliessen: Dialog beenden ohne zu speichern

### SBZPURGE - Block-Definitionen aufraeumen

Loescht nicht mehr verwendete Kopie-Block-Definitionen (VM_Hoehe_*).

**Aufruf:**
```
Command: SBZPURGE
```

**Beispiel:**
```
Command: SBZPURGE
→ 2 Block-Definitionen geloescht (VM_Hoehe_alt1, VM_Hoehe_alt2)
```

### SBZDEBUG - Debug-Modus

Schaltet erweiterte Log-Ausgabe ein/aus. Im Debug-Modus werden zusaetzliche DEBUG-Eintraege ins Session-Log geschrieben.

**Aufruf:**
```
Command: SBZDEBUG
→ SBZ Debug-Modus: EIN
```

## Kopie-Block (VM_Hoehe)

Der automatisch erstellte Kopie-Block besteht aus:

**Symbol:**
- Kreis (Radius 0.05m)
- Fadenkreuz (±0.08m)
- Schachbrett-Muster (4 gefuellte Viertelkreise)
- Alle Entities: Farbe ByBlock, Linientyp ByBlock

**Attribute:**
- HOEHE_ABS: Absolute Hoehe mit Suffix (z.B. "320.49 m ue. A.")
- HOEHE_REL: Relative Hoehe nach Bau-0 (z.B. "+0.49")
- HOEHE_BAU0: Bau-0-Referenz (z.B. "±0.00 = 320.00 m ue. A.")
- Alle Attribute: Position gesperrt (nicht verschiebbar)

**Pro Gruppe eine eigene Block-Definition:**
```
VM_Hoehe_STAB137
VM_Hoehe_Grenzpunkte
VM_Hoehe_Baufeld_Nord
```

## Layer-Standard

Layer-Naming angelehnt an OENORM A 6241-1 / ISO 13567.

**Schema:**
```
VM_<Gruppe>_<Gruppenname>
```

| Bestandteil | Beschreibung | Beispiel |
|---|---|---|
| `VM` | Fachbereich: Vermessung (fix) | `VM` |
| `<Gruppe>` | Gegenstandsgruppe (konfigurierbar) | `HP` |
| `<Gruppenname>` | SETBLOCKZ-Gruppenname | `STAB137` |

**Attribut-Sub-Layer:**

| Layer | Inhalt |
|---|---|
| `VM_HP_STAB137` | Block-Symbol |
| `VM_HP_STAB137-AttABS` | Attribut: Absolute Hoehe |
| `VM_HP_STAB137-AttREL` | Attribut: Relative Hoehe |
| `VM_HP_STAB137-AttBAU0` | Attribut: Bau-0-Referenz |

**Vordefinierte Gegenstandsgruppen:**

| Code | Bedeutung |
|---|---|
| `HP` | Hoehenpunkt (Standard) |
| `GP` | Grenzpunkt |
| `GE` | Gelaende |
| `FP` | Festpunkt |

Siehe `docs/LayerStandards_README.md` fuer vollstaendige Layer-Dokumentation.

## Gruppen-System

Jede Gruppe wird als XRecord im Named Object Dictionary der DWG gespeichert.

**XRecord-Felder:**

| Feld | Beschreibung | Beispiel |
|---|---|---|
| GROUPNAME | Gruppenname | STAB137 |
| QUELLBLOCK | Quell-Blockname | STAB137 |
| ATTRTAG | Attribut-Tag fuer Hoehe | HOEHE |
| BAU0 | Eigener Bau-0 (leer = DWG-Standard) | 320.000 |
| ZMODE | Absolut oder Relativ | REL |
| COPYBLOCK | Kopie-Block Name | VM_Hoehe_STAB137 |
| COPYLAYER | Gegenstandsgruppe | HP |
| SCALE | Skalierung | 10.0000 |
| SUFFIX | Hoehen-Suffix | m ue. A. |
| FONT | Schriftart | Arial |
| COLORBLOCK | Block-Farbe (ACI) | 7 |
| COLORABS | Attribut ABS Farbe | 0 |
| COLORREL | Attribut REL Farbe | 0 |
| COLORBAU0 | Attribut BAU0 Farbe | 0 |
| FREEZEABS | AttABS gefroren | 0 |
| FREEZEREL | AttREL gefroren | 0 |
| FREEZEBAU0 | AttBAU0 gefroren | 1 |

**Block-Zuordnung via XData:**

Jeder Kopie-Block traegt XData der App "SBZ":

| DXF Code | Inhalt | Beispiel |
|---|---|---|
| 1000 | Gruppenname | STAB137 |
| 1005 | Quell-Block Handle | 2A3F |

Ein Quell-Block kann in mehreren Gruppen sein. Jede Gruppe erzeugt einen eigenen Kopie-Block mit eigenem Handle-Verweis auf den Quell-Block.

## Konfiguration

### AppData-Ordner

```
%APPDATA%\AutoCAD\Lisp\SetBlockZ\
```

Unterordner:
- `Log\` — Session-Logs
- `Config\` — Konfigurationsdatei
- `Backup\` — Sicherungen

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\Lisp\SetBlockZ\Config\SetBlockZ.cfg
```

**Format:**
```
BYBLOCK=1
MOVELAYER=0
TARGETLAYER=
COPYMODE=1
COPYBLOCK=VM_Hoehe
COPYLAYER=HP
FREEZEABS=0
FREEZEREL=0
FREEZEBAU0=1
FONT=Arial
COLORBLOCK=7
COLORABS=0
COLORREL=0
COLORBAU0=0
```

### DWG Custom Properties

Zeichnungsspezifische Einstellungen werden als SummaryInfo Custom Properties gespeichert:

| Property | Beschreibung |
|---|---|
| SetBlockZ_Bau0 | Bau-0-Hoehe der Zeichnung |
| SetBlockZ_BlockName | Zuletzt verwendeter Blockname |
| SetBlockZ_AttrTag | Zuletzt verwendetes Attribut |
| SetBlockZ_Scale | Einfuege-Skalierung |
| SetBlockZ_Suffix | Hoehen-Suffix |
| SetBlockZ_Font | Schriftart |

### Einstellungen aendern

Ueber den Befehl `SBZSETTINGS` koennen alle Einstellungen interaktiv geaendert werden.

## Log-Datei

### Speicherort

```
%APPDATA%\AutoCAD\Lisp\SetBlockZ\Log\SetBlockZ_YYYYMMDD_HHMMSS.log
```

Pro Session wird eine neue Log-Datei erstellt.
Maximal 5 Session-Logs werden aufbewahrt, aeltere werden automatisch geloescht.

### Log-Format

```
[2026-03-22 19:30:22] [INFO ] === SetBlockZ v1.22.1 gestartet ===
[2026-03-22 19:30:22] [INFO ] Lazy-Init abgeschlossen
[2026-03-22 19:30:25] [INFO ] Block gewaehlt: STAB137
[2026-03-22 19:30:28] [INFO ] Attribut: HOEHE
[2026-03-22 19:30:30] [INFO ] Bau-0: 320.000 (DWG Custom Property)
[2026-03-22 19:30:32] [INFO ] 342 Bloecke gefunden
[2026-03-22 19:30:33] [INFO ] Z-Modus: REL
[2026-03-22 19:30:35] [INFO ] Gruppe: STAB137
[2026-03-22 19:30:40] [INFO ] 342 Bloecke verarbeitet (0 Fehler)
[2026-03-22 19:30:40] [INFO ] Gruppe gespeichert: STAB137
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
Command: SBZDEBUG
→ SBZ Debug-Modus: EIN
```

## Context-Namespace

Prefix: `SBZ:` (SetBlockZ)

### Kernfunktionen

| Funktion | Beschreibung |
|----------|--------------|
| SBZ:ensure-init | Lazy-Init (erster Aufruf) |
| SBZ:process-blocks | Bloecke verarbeiten (Z setzen + Kopie erstellen) |
| SBZ:insert-copyblock | Einzelnen Kopie-Block einfuegen |
| SBZ:ensure-copyblock-def | Block-Definition erstellen falls nicht vorhanden |
| SBZ:get-copy-layername | Layer-Name berechnen (VM_HP_Gruppenname) |
| SBZ:ensure-attr-layers | Attribut-Sub-Layer erstellen |
| SBZ:log-write | Log-Eintrag schreiben |
| SBZ:load-config | Config laden |
| SBZ:save-config | Config speichern |

### Gruppen-Funktionen

| Funktion | Beschreibung |
|----------|--------------|
| SBZ:save-group | Gruppe als XRecord speichern |
| SBZ:load-group | Gruppe aus XRecord laden |
| SBZ:delete-group | Gruppe + Bloecke + Layer loeschen |
| SBZ:get-group-names | Alle Gruppennamen aus NOD lesen |
| SBZ:get-group-entities | Alle Entities einer Gruppe (via XData) |
| SBZ:get-source-ss-for-group | Quell-Bloecke via Handle finden |
| SBZ:apply-group-settings | Gruppen-Settings in globale Vars laden |
| SBZ:cleanup-group-layers | Leere Layer nach Gruppen-Loeschung aufraeumen |

### XData-Funktionen

| Funktion | Beschreibung |
|----------|--------------|
| SBZ:regapp | App "SBZ" registrieren |
| SBZ:set-xdata | Gruppenname + Quell-Handle auf Entity |
| SBZ:get-xdata | Gruppenname aus Entity lesen |
| SBZ:get-xdata-handle | Quell-Handle aus Entity lesen |

### Globale Variablen

| Variable | Beschreibung |
|----------|--------------|
| *SBZ:version* | Script-Version |
| *SBZ:initialized* | Init-Status (T/nil) |
| *SBZ:debug-mode* | Debug-Modus (T/nil) |
| *SBZ:log-session-id* | Aktueller Log-Dateiname |
| *SBZ:cfg-copymode* | Kopie-Modus (0/1) |
| *SBZ:cfg-copyblock* | Basis-Blockname (VM_Hoehe) |
| *SBZ:cfg-copylayer* | Gegenstandsgruppe (HP) |
| *SBZ:cfg-font* | Schriftart (Arial) |
| *SBZ:cfg-color-block* | Block-Farbe ACI (7) |
| *SBZ:cfg-color-abs* | AttABS Farbe ACI (0) |
| *SBZ:cfg-color-rel* | AttREL Farbe ACI (0) |
| *SBZ:cfg-color-bau0* | AttBAU0 Farbe ACI (0) |
| *SBZ:cfg-freeze-abs* | AttABS gefroren (0) |
| *SBZ:cfg-freeze-rel* | AttREL gefroren (0) |
| *SBZ:cfg-freeze-bau0* | AttBAU0 gefroren (1) |

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet
- **AutoCAD LT:** Nicht kompatibel (kein AutoLISP Support)
- **Abhaengigkeiten:** Keine
- **AppData:** %APPDATA%\AutoCAD\Lisp\SetBlockZ\
- **Namespace:** SBZ (SetBlockZ)
- **DWG-Daten:** XRecords in Named Object Dictionary, XData auf Entities
- **Layer-Standard:** VM_<Gruppe>_<n> (OENORM A 6241 angelehnt)
- **Block-Rotation:** BKS-orientiert (UCSXDIR)
- **Attribut-Position:** Gesperrt (DXF 70 Bit 16)
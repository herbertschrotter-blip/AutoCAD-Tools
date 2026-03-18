# AutoLoadDimStyle

Automatisches Laden von Bemassungsstilen aus Master-DWG-Dateien fuer AutoCAD.
Vereinfacht die Verwaltung und Verteilung einheitlicher Bemassungsstile ueber mehrere Zeichnungen hinweg.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| DimStyleManager | DCL-Dialog fuer Master-Dateien Verwaltung |
| AutoLoadDimStyles | Silent Autostart (wird via S::STARTUP aufgerufen) |
| ADSDEBUG | Debug-Modus ein/aus |

## Features

- DCL-Dialog mit Dateiliste, Status-Anzeige und Einstellungen
- Automatisches Laden beim Zeichnungsstart (silent via S::STARTUP)
- First-Time Setup Dialog beim allerersten Start
- Mehrere Master-Dateien verwalten
- Persistente Konfiguration in %APPDATA%
- Ausfuehrliches Session-Logging (max 5 Sessions, rotierend)
- Automatische Migration von aelteren Config-Formaten
- Lazy-Init Pattern (DokaCAD kompatibel)

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausfuehren
2. `AutoLoadDimStyle.lsp` auswaehlen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufuegen

### Support-Ordner (Alternative)

Kopieren nach:
```
%APPDATA%\Autodesk\AutoCAD 2024\R24.3\deu\Support\
```

## Verwendung

### DimStyleManager - DCL-Dialog

Hauptbefehl fuer alle Verwaltungsaufgaben. Oeffnet einen DCL-Dialog mit Dateiliste und Aktions-Buttons.

**Aufruf:**
```
Command: DimStyleManager
```

**Dialog-Elemente:**

Der Haupt-Dialog zeigt eine Liste aller konfigurierten Master-Dateien mit Status (`[OK]` oder `[FEHLER]`). Klick auf einen Eintrag zeigt den vollen Pfad an.

**Buttons:**
- `Alle laden` - Importiert Bemassungsstile aus allen konfigurierten Dateien
- `Oeffnen` - Oeffnet die selektierte Master-Datei zum Bearbeiten in AutoCAD
- `Hinzufuegen...` - Dateiauswahl-Dialog fuer neue Master-DWG
- `Entfernen` - Loescht den selektierten Eintrag aus der Konfiguration
- `Einstellungen...` - Oeffnet Sub-Dialog mit Pfaden, Debug-Modus und Reset
- `Schliessen` - Beendet den Dialog

**Einstellungen Sub-Dialog:**
- Zeigt Config-, Log- und AppData-Pfade an
- Debug-Modus Toggle (ausfuehrliches Logging ein/aus)
- Reset-Button (alle Pfade zuruecksetzen)

**Erster Start (First-Time Setup):**

Beim allerersten Aufruf (keine Config vorhanden) erscheint automatisch ein Dateiauswahl-Dialog zur Auswahl der ersten Master-DWG. Danach wird diese Datei bei jedem Zeichnungsstart automatisch geladen.

### AutoLoadDimStyles - Silent Autostart

Wird automatisch via `S::STARTUP` beim Oeffnen jeder Zeichnung aufgerufen. Laedt alle konfigurierten Master-Dateien ohne Ausgabe. Falls keine Konfiguration vorhanden, wird der First-Time Setup Dialog angezeigt.

**Aufruf:**
```
Command: AutoLoadDimStyles
```

### ADSDEBUG - Debug-Modus

Schaltet den Debug-Modus ein oder aus. Im Debug-Modus werden zusaetzliche DEBUG-Eintraege ins Log geschrieben.

**Aufruf:**
```
Command: ADSDEBUG
→ Debug-Modus: EIN
```

## Konfiguration

### AppData-Ordner

Alle Daten werden gespeichert in:
```
%APPDATA%\AutoCAD\Lisp\AutoLoadDimStyle\
  ├── Log\        Session-Logs
  ├── Config\     Konfigurationsdatei
  └── Backup\     (reserviert)
```

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\Lisp\AutoLoadDimStyle\Config\AutoLoadDimStyle.cfg
```

**Format:**
```
2.9.0
D:\OneDrive\Projekte\CAD\BueroStandard.dwg
D:\OneDrive\Projekte\CAD\ProjektXY.dwg
```

Erste Zeile: Versionsnummer. Alle weiteren Zeilen: Volle Pfade zu Master-DWG-Dateien.

### Einstellungen aendern

Ueber den Befehl `DimStyleManager` → `Einstellungen...` koennen alle Einstellungen interaktiv geaendert werden.

### Config-Migration

Beim Upgrade von aelteren Versionen wird die Konfiguration automatisch migriert:
- v1: `%APPDATA%\AutoCAD\DimStyleConfig.txt` → neuer Pfad
- v2: `%APPDATA%\AutoCAD\AutoLoadDimStyle\AutoLoadDimStyle.cfg` → neuer Pfad mit `Lisp\` Unterordner

Die alte Config-Datei wird nach erfolgreicher Migration geloescht.

## Log-Datei

### Speicherort

```
%APPDATA%\AutoCAD\Lisp\AutoLoadDimStyle\Log\AutoLoadDimStyle_YYYYMMDD_HHMMSS.log
```

Pro Session wird eine neue Log-Datei erstellt.
Maximal 5 Session-Logs werden aufbewahrt, aeltere werden automatisch geloescht.

### Log-Format

```
[2026-03-18 14:30:22] [INFO ] Initialisierung abgeschlossen (Lazy-Init)
[2026-03-18 14:30:22] [INFO ] === Befehl AutoLoadDimStyles (Autostart) gestartet ===
[2026-03-18 14:30:22] [INFO ] Autostart geladen: BueroStandard
[2026-03-18 14:30:23] [INFO ] Autostart abgeschlossen: 1 Datei(en)
[2026-03-18 14:35:10] [INFO ] === Befehl DimStyleManager gestartet ===
[2026-03-18 14:35:12] [INFO ] Dialog: Hinzufuegen
[2026-03-18 14:35:15] [INFO ] Master-Datei hinzugefuegt: D:\Projekte\ProjektXY.dwg
[2026-03-18 14:35:18] [INFO ] Dialog: Schliessen
[2026-03-18 14:35:18] [INFO ] === Befehl DimStyleManager beendet ===
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
Command: ADSDEBUG
→ Debug-Modus: EIN
```

Im Debug-Modus werden zusaetzliche DEBUG-Eintraege ins Log geschrieben.
Alternativ ueber `DimStyleManager` → `Einstellungen...` → Debug-Modus Toggle.

## Context-Namespace

Prefix: `ADS:` (AutoLoadDimStyle)

### Wichtige Funktionen

| Funktion | Beschreibung |
|----------|--------------|
| ADS:ensure-init | Lazy-Init (VLA laden, AppData erstellen) |
| ADS:get-appdata-path | AppData-Basispfad ermitteln/erstellen |
| ADS:get-config-file | Voller Pfad zur Config-Datei |
| ADS:get-log-path | Pfad zum Log-Ordner |
| ADS:read-master-files | Config lesen (mit Migration) |
| ADS:save-master-files | Config speichern |
| ADS:add-master-file | Master-Datei hinzufuegen |
| ADS:remove-master-file | Master-Datei entfernen |
| ADS:log-write | Log-Eintrag schreiben |
| ADS:log-rotate | Alte Logs loeschen (max 5) |
| ADS:cancel-p | Cancel-Erkennung (DE+EN) |
| ADS:valid-dwg-file-p | DWG-Datei Validierung |
| ADS:first-time-setup | Erst-Konfiguration |
| ADS:write-main-dcl | DCL-Datei schreiben (embedded) |
| ADS:show-main-dialog | Haupt-Dialog anzeigen |
| ADS:show-settings-dialog | Einstellungen Sub-Dialog |

### Globale Variablen

| Variable | Beschreibung |
|----------|--------------|
| *ADS:version* | Script-Version |
| *ADS:namespace* | Namespace-Prefix ("ADS") |
| *ADS:appdata-folder* | AppData-Ordnername |
| *ADS:initialized* | Init-Status (T/nil) |
| *ADS:log-session-id* | Aktueller Log-Dateiname |
| *ADS:debug-mode* | Debug-Modus (T/nil) |

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet (via Lazy-Init)
- **AutoCAD LT:** Nicht kompatibel (kein AutoLISP Support)
- **DokaCAD:** Kompatibel (Lazy-Init Pattern)
- **Abhaengigkeiten:** Keine
- **AppData:** %APPDATA%\AutoCAD\Lisp\AutoLoadDimStyle\
- **Namespace:** ADS (AutoLoadDimStyle)
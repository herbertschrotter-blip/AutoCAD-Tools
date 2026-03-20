# BlockImport

Zentrale Bibliothek fuer Block-Import und Block-Verwaltung in AutoCAD.
Verwaltet Block-Dateipfade global und steuert die Block-Zuordnung pro Script und pro Zeichnung.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| ManageBlockImport | Block-Verwaltung (DCL-Dialog) |
| ShowBlockPath | Zeigt alle konfigurierten Block-Pfade |
| ResetBlockPath | Loescht alle gespeicherten Pfade |
| BlockImportDebug | Debug-Modus ein/aus |

## Features

- Globaler Block-Pool: Alle Scripts sehen alle verfuegbaren Bloecke
- Globaler Standard pro Script (SetHK und HAL koennen verschiedene Defaults haben)
- Block-Zuordnung pro Zeichnung via DWG Custom Property
- DCL-Dialog mit Listbox, Pfad-Anzeige und Status-Info
- ObjectDBX Block-Import aus externen DWG-Dateien (Lee Mac Utilities)
- Auto-Open Block Manager wenn kein Block konfiguriert
- Persistente Speicherung in AppData Config-Datei
- Session-basiertes Logging (max 5 Sessions)

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausfuehren
2. `BlockImport.lsp` auswaehlen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufuegen

**Wichtig:** BlockImport.lsp wird normalerweise von anderen Scripts geladen (SetHK, HAL), nicht direkt vom User.

### Abhaengigkeiten

Keine externen Libraries. Nutzt Lee Mac ObjectDBX Utilities (integriert).

## Verwendung

### ManageBlockImport - Block-Verwaltung

DCL-Dialog zur Verwaltung aller Block-Pfade. Zeigt immer ALLE verfuegbaren Bloecke, unabhaengig davon welches Script den Manager geoeffnet hat.

**Aufruf:**
```
Command: ManageBlockImport
```

**Dialog-Elemente:**

- Listbox mit allen konfigurierten Bloecken
- Globaler Standard: Zeigt den Standard-Block fuer das aktuelle Script
- Zeichnungs-Block: Zeigt den Block fuer die aktuelle DWG (oder "verwendet Global")
- Pfad-Anzeige: Zeigt den Dateipfad des gewaehlten Blocks mit Existenz-Pruefung

**Buttons:**

- `Globaler Standard` - Setzt gewaehlten Block als Standard fuer dieses Script
- `Fuer Zeichnung` - Setzt gewaehlten Block nur fuer die aktuelle DWG
- `Hinzufuegen` - Neue Block-DWG auswaehlen und hinzufuegen
- `Entfernen` - Block aus Config entfernen
- `Pfad` - Dateipfad eines Blocks aendern

**Beispiel - Erster Start (keine Bloecke konfiguriert):**
```
Command: ManageBlockImport
→ Dialog oeffnet sich mit "(keine Bloecke konfiguriert)"
→ Klick auf "Hinzufuegen"
→ File-Dialog: BLK_Hoehenkote.dwg auswaehlen
→ Block erscheint in Listbox, wird automatisch als Standard gesetzt
→ Klick auf "Schliessen"
```

**Beispiel - Block fuer eine Zeichnung aendern:**
```
Command: ManageBlockImport
→ Dialog zeigt alle Bloecke: BLK_Hoehenkote, BLK_Hoehenkote_3DEZ
→ BLK_Hoehenkote_3DEZ auswaehlen
→ Klick auf "Fuer Zeichnung"
→ Zeichnungs-Block zeigt: BLK_Hoehenkote_3DEZ
→ Ab jetzt verwendet nur DIESE Zeichnung den 3DEZ-Block
```

**Beispiel - Verschiedene Standards pro Script:**
```
→ Aus SetHK geoeffnet (Context: SetHK):
  → BLK_Hoehenkote auswaehlen → "Globaler Standard"
  → Globaler Standard zeigt: BLK_Hoehenkote

→ Aus HAL geoeffnet (Context: HAL):
  → BLK_Hoehenkote_3DEZ auswaehlen → "Globaler Standard"
  → Globaler Standard zeigt: BLK_Hoehenkote_3DEZ

→ Beide Scripts sehen BEIDE Bloecke in der Liste!
→ Aber jedes Script hat seinen eigenen Standard.
```

---

### ShowBlockPath - Pfade anzeigen

Zeigt alle konfigurierten Block-Pfade mit Existenz-Status.

**Aufruf:**
```
Command: ShowBlockPath
```

**Beispiel:**
```
=== Konfigurierte Block-Pfade ===
BLK_Hoehenkote: D:\OneDrive\Vorlagen\BLK_Hoehenkote.dwg [✓ Existiert]
BLK_Hoehenkote_3DEZ: D:\OneDrive\Vorlagen\BLK_Hoehenkote_3DEZ.dwg [✓ Existiert]

Config-Datei: C:\Users\Herbert\AppData\Roaming\AutoCAD\Lisp\BlockImport\Config\BlockImportConfig.txt
```

---

### ResetBlockPath - Pfade zuruecksetzen

Loescht die Config-Datei. Beim naechsten Block-Import wird erneut nach Dateien gefragt.

**Aufruf:**
```
Command: ResetBlockPath
```

**Beispiel:**
```
Command: ResetBlockPath
→ Gespeicherte Block-Pfade wurden zurueckgesetzt.
→ Beim naechsten Laden wird nach der Datei gefragt.
```

**Hinweis:** DWG Custom Properties (pro Zeichnung) bleiben erhalten. Nur die globale Config wird geloescht.

## Architektur

### Block-Pfade (globaler Pool)

Block-Pfade werden **ohne Context-Praefix** gespeichert. Jedes Script sieht alle verfuegbaren Bloecke im Block Manager. Das verhindert das Problem dass ein Script weniger Bloecke sieht als ein anderes.

**Config-Eintraege:**
```
BLK_Hoehenkote=D:\Pfad\BLK_Hoehenkote.dwg          ← Fuer ALLE Scripts sichtbar
BLK_Hoehenkote_3DEZ=D:\Pfad\BLK_Hoehenkote_3DEZ.dwg ← Fuer ALLE Scripts sichtbar
```

### Globaler Standard (pro Script)

Jedes Script hat einen eigenen Standard-Block, gespeichert als `*STANDARD:<Context>*` in der Config. SetHK kann z.B. `BLK_Hoehenkote` als Standard haben, waehrend HAL `BLK_Hoehenkote_3DEZ` verwendet.

**Config-Eintraege:**
```
*STANDARD:SetHK*=BLK_Hoehenkote          ← SetHK Default
*STANDARD:HAL*=BLK_Hoehenkote_3DEZ       ← HAL Default
```

### DWG Custom Property (pro Zeichnung + pro Script)

Jede Zeichnung kann pro Script einen eigenen Block haben. Gespeichert als `<Context>_Block` in den DWG SummaryInfo Custom Properties. Sichtbar unter Datei → Zeichnungseigenschaften → Benutzerspezifisch.

**Property-Namen in der DWG:**

| Property | Script | Beschreibung |
|----------|--------|--------------|
| `SetHK_Block` | SetHoehenkote | Block fuer Hoehenkoten |
| `SetHK_Scale` | SetHoehenkote | XY-Skalierung |
| `HAL_Block` | HoeheAufLinie | Block fuer Interpolation |
| `HAL_Scale` | HoeheAufLinie | XY-Skalierung |

### Lookup-Reihenfolge (BLI:resolve-blockname)

Wenn ein Script einen Blocknamen braucht, wird in dieser Reihenfolge gesucht:

1. **DWG Custom Property** `<Context>_Block` → zeichnungsspezifisch, hoechste Prioritaet
2. **Globaler Standard** `*STANDARD:<Context>*` aus Config → Fallback fuer alle Zeichnungen
3. **nil** → kein Block konfiguriert → Block Manager wird automatisch geoeffnet

Beim ersten Aufruf wird der globale Standard automatisch in die DWG Custom Property uebernommen. Danach liest die Zeichnung immer ihren eigenen Wert.

**Beispiel Ablauf:**
```
1. Neue Zeichnung, kein SetHK_Block Property
2. SetHK ruft BLI:resolve-blockname("SetHK") auf
3. DWG Property: nil → weiter
4. Globaler Standard: BLK_Hoehenkote → gefunden!
5. Schreibt SetHK_Block=BLK_Hoehenkote in DWG
6. Gibt "BLK_Hoehenkote" zurueck
7. Naechster Aufruf: DWG Property liefert direkt "BLK_Hoehenkote"
```

## Konfiguration

### AppData-Ordner

Alle Daten werden gespeichert in:
```
%APPDATA%\AutoCAD\Lisp\BlockImport\
  ├── Log\        (Session-Logs)
  ├── Config\     (Konfiguration)
  └── Backup\     (reserviert)
```

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\Lisp\BlockImport\Config\BlockImportConfig.txt
```

**Vollstaendiges Format-Beispiel:**
```
1.0
BLK_Hoehenkote=D:\OneDrive\Dokumente\02 Arbeit\05 Vorlagen\BLK_Hoehenkote.dwg
BLK_Hoehenkote_3DEZ=D:\OneDrive\Dokumente\02 Arbeit\05 Vorlagen\BLK_Hoehenkote_3DEZ.dwg
*STANDARD:SetHK*=BLK_Hoehenkote
*STANDARD:HAL*=BLK_Hoehenkote_3DEZ
```

**Aufbau:**
- **Erste Zeile:** Versions-Nummer (1.0)
- **Block-Pfade:** `BlockName=Dateipfad` (ohne Context-Praefix, globaler Pool)
- **Standards:** `*STANDARD:<Context>*=BlockName` (pro Script, jeweils eigener Standard)

## Log-Datei

### Speicherort

```
%APPDATA%\AutoCAD\Lisp\BlockImport\Log\BlockImport_YYYYMMDD_HHMMSS.log
```

Pro Session wird eine neue Log-Datei erstellt.
Maximal 5 Session-Logs werden aufbewahrt, aeltere werden automatisch geloescht.

### Log-Format

```
[2026-03-20 14:30:22] [INFO ] === BlockImport.lsp v1.12.1 geladen ===
[2026-03-20 14:30:25] [INFO ] Block-Manager DCL geoeffnet (Context: SetHK)
[2026-03-20 14:30:28] [INFO ] Block hinzugefuegt: BLK_Hoehenkote -> D:\Pfad\BLK_Hoehenkote.dwg
[2026-03-20 14:30:30] [INFO ] Standard-Block gesetzt: BLK_Hoehenkote (Context: SetHK)
[2026-03-20 14:30:35] [INFO ] DWG-Block gespeichert: SetHK_Block=BLK_Hoehenkote
[2026-03-20 14:31:00] [INFO ] Block-Import gestartet: BLK_Hoehenkote aus D:\Pfad\BLK_Hoehenkote.dwg
[2026-03-20 14:31:01] [INFO ] Block erfolgreich importiert: BLK_Hoehenkote
[2026-03-20 14:31:05] [INFO ] Block-Manager DCL geschlossen
```

### Log-Level

| Level | Bedeutung |
|-------|-----------|
| INFO | Normaler Ablauf |
| WARN | Unerwartetes, nicht kritisch |
| ERROR | Fehler, Funktion abgebrochen |
| DEBUG | Detaillierte Infos (nur bei Debug-Modus) |

### Debug-Modus

Debug-Modus aktivieren:
```
Command: BlockImportDebug
→ BlockImport Debug-Modus: EIN
```

Im Debug-Modus werden zusaetzliche DEBUG-Eintraege ins Log geschrieben (z.B. Config-Lese-Operationen, DWG Property Lookups, Block-Existenz-Pruefungen).

## Context-Namespace

Prefix: `BLI:` (BlockImport)

### Wichtige Funktionen

| Funktion | Beschreibung |
|----------|--------------|
| BLI:resolve-blockname | Blockname ermitteln (DWG → Global → nil) |
| BLI:dwg-block-read | Block aus DWG Custom Property lesen |
| BLI:dwg-block-write | Block in DWG Custom Property schreiben |
| BLI:safe-variant-value | VLA String/Variant Handler |
| BLI:get-appdata-path | AppData-Pfad ermitteln/erstellen |
| BLI:log-write | Log-Eintrag schreiben |
| BLI:log-rotate | Log-Rotation (max 5 Sessions) |
| BLI:write-dcl | DCL-Dialog Temp-Datei schreiben |
| BLI:build-block-list | Listbox-Eintraege erstellen |
| BLI:extract-blockname | Blocknamen aus Listbox-Eintrag |
| BLI:remove-block-from-config | Block aus Config entfernen |
| ensure-block-available | Block laden wenn noetig |
| manage-block-import | DCL Block-Manager oeffnen |
| get-standard-block | Standard-Block fuer Context lesen |
| set-standard-block | Standard-Block fuer Context setzen |
| read-all-block-paths | Alle Block-Pfade aus Config lesen |
| read-block-path | Pfad fuer einzelnen Block lesen |
| save-block-path | Pfad fuer Block speichern |
| select-block-file | File-Dialog fuer Block-DWG |
| import-block-from-file | ObjectDBX Block-Import |

### Globale Variablen

| Variable | Beschreibung |
|----------|--------------|
| *block-import-context* | Aktueller Context (z.B. "SetHK", "HAL") |
| *block-config-file* | Pfad zur Config-Datei |
| *default-block-file* | Standard Block-Datei (Legacy) |
| *BLI:appdata-folder* | AppData Ordnername ("BlockImport") |
| *BLI:debug-mode* | Debug ein/aus (T/nil) |
| *BLI:log-session-id* | Aktueller Log-Dateiname |

### API fuer Script-Entwickler

**Block-Zuordnung ermitteln (empfohlen):**
```lisp
;; Context setzen (WICHTIG!)
(setq *block-import-context* "MeinScript")

;; Blockname ermitteln: DWG Property → Globaler Standard → nil
(setq blockname (BLI:resolve-blockname "MeinScript"))

;; Wenn nil: Block Manager oeffnen, dann nochmal versuchen
(if (null blockname)
  (progn
    (manage-block-import "MeinScript")
    (setq blockname (BLI:resolve-blockname "MeinScript"))
  )
)
```

**Block importieren (wird automatisch geladen wenn noetig):**
```lisp
(setq result (ensure-block-available blockname))
;; result: (T nil) bei Erfolg
;; result: (nil nil) bei Fehler
(if (car result)
  (princ "\nBlock verfuegbar!")
  (princ "\nFehler beim Laden!")
)
```

**Block-Manager direkt oeffnen:**
```lisp
(manage-block-import "MeinScript")  ; Mit Context
(manage-block-import nil)           ; Nutzt globale *block-import-context*
```

**Standard-Block abfragen/setzen:**
```lisp
(setq *block-import-context* "MeinScript")
(get-standard-block)                    ;; → "BLK_Hoehenkote" oder nil
(set-standard-block "BLK_Hoehenkote")   ;; Setzt Standard fuer diesen Context
```

**DWG Custom Property direkt lesen/schreiben:**
```lisp
(BLI:dwg-block-read "MeinScript")                  ;; → Blockname oder nil
(BLI:dwg-block-write "MeinScript" "BLK_Hoehenkote") ;; → T
```

### BlockImport.lsp Pfad-Management fuer aufrufende Scripts

Aufrufende Scripts sollten den Pfad zu BlockImport.lsp persistent speichern, um wiederholte File-Dialoge zu vermeiden.

**Empfohlene 3-Fallback Pfadaufloesung:**
```lisp
;; 1. Gespeicherter Pfad aus eigener Config
(setq path *MeinScript:blockimport-path*)

;; 2. findfile im Support-Pfad
(if (null path)
  (setq path
    (cond
      ((findfile "lib/BlockImport.lsp"))
      ((findfile "BlockImport.lsp"))
    )
  )
)

;; 3. File-Dialog als letzter Fallback
(if (null path)
  (progn
    (princ "\n*** BlockImport.lsp nicht gefunden ***")
    (setq path
      (getfiled "BlockImport.lsp auswaehlen"
                (cond ((getvar "DWGPREFIX")) ((getenv "USERPROFILE")) (T ""))
                "lsp" 0))
    ;; Pfad in eigener Config speichern
    (if path (MeinScript:save-config))
  )
)

;; Laden
(if path (load path))
```

Beide mitgelieferten Scripts (SetHK, HAL) implementieren diese 3-Fallback Suche. Der Pfad wird in der jeweiligen Script-Config gespeichert und ist im Settings-Dialog unter "BlockImport.lsp → Durchsuchen..." aenderbar.

### Lee Mac Utilities

BlockImport.lsp nutzt folgende Funktionen von Lee Mac:

- `LM:GetDocumentObject` - ObjectDBX Interface fuer externe DWG-Dateien
- `LM:getitem` - VLA Collection Item Retrieval mit Error-Handling

Quelle: [Lee Mac Programming](https://www.lee-mac.com/)

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet (von aufrufendem Script geladen)
- **AutoCAD LT:** Nicht kompatibel (kein AutoLISP Support)
- **Abhaengigkeiten:** Keine (Lee Mac Utilities integriert)
- **AppData:** %APPDATA%\AutoCAD\Lisp\BlockImport\
- **Namespace:** BLI (BlockImport)
- **DWG Properties:** `<Context>_Block` (z.B. SetHK_Block, HAL_Block)

### Bekannte Einschraenkungen

- `vla-GetCustomByIndex` gibt manchmal Strings direkt, manchmal Variants zurueck. `BLI:safe-variant-value` behandelt beide Faelle.
- `vl-catch-all-apply` mit Lambda-Funktionen bricht pass-by-reference bei `GetCustomByIndex`. Daher werden direkte VLA-Calls verwendet statt Lambda-Wrapper.
- DWG Custom Property Keys duerfen keinen Doppelpunkt (`:`) enthalten. Properties verwenden daher Unterstrich: `SetHK_Block` statt `SetHK:Block`.

---

**Version:** 1.12.1
**Datum:** 2026-03-20
**Autor:** Herbert Schrotter
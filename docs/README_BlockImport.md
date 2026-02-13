# BlockImport

Gemeinsame Bibliothek für Block-Import in AutoCAD.
Verwaltet Block-Dateipfade zentral mit Context-Namespaces und lädt Blocks automatisch aus externen DWG-Dateien.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| ManageBlockImport | Block-Verwaltung mit Rechtsklick-Menü |
| ShowBlockPath | Zeigt alle konfigurierten Block-Pfade |
| ResetBlockPath | Löscht alle gespeicherten Pfade |

## Features

- ✅ Context-Namespace System für Multi-Script Support
- ✅ Eine zentrale Config-Datei für alle Scripts
- ✅ Automatischer Standard-Block bei neuem Block
- ✅ Interaktives Rechtsklick-Menü
- ✅ Intelligente Pfad-Suche mit Fallback-Mechanismen
- ✅ Persistente Speicherung in Config-Datei
- ✅ Keine Code-Duplikation zwischen Scripts

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausführen
2. `BlockImport.lsp` auswählen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufügen

### Support-Ordner (Alternative)

Kopieren nach:
```
%APPDATA%\Autodesk\AutoCAD 2024\R24.3\deu\Support\lib\
```

**Wichtig:** Bibliothek wird normalerweise von anderen Scripts geladen, nicht direkt vom User!

## Verwendung

### Für Script-Entwickler

**In Ihrem AutoLISP-Script:**

```lisp
;; Context setzen (WICHTIG für Namespace-Isolation!)
(setq *block-import-context* "SetHK")  ; Eindeutige ID für Ihr Script

;; BlockImport.lsp laden
(load "lib/BlockImport.lsp")

;; Block importieren (wird automatisch geladen wenn nötig)
(setq result (ensure-block-available "BLK_MeinBlock"))

;; result ist (T importEnt) bei Erfolg oder (nil nil) bei Fehler
(if (car result)
  (progn
    ;; Block erfolgreich verfügbar
    ;; importEnt ggf. später löschen: (entdel (cadr result))
  )
)
```

**Block-Manager intern aufrufen:**

```lisp
;; Öffnet Block-Manager für aktuellen Context
(manage-block-import "SetHK")
```

**Beim ersten Aufruf:**
- User wählt DWG-Datei für den Block
- Pfad wird mit Context-Präfix gespeichert
- Block wird importiert
- Automatisch als Standard gesetzt

**Bei weiteren Aufrufen:**
- Pfad aus Config gelesen (gefiltert nach Context)
- Block automatisch geladen
- Keine User-Interaktion nötig

---

### ManageBlockImport - Block-Verwaltung

Interaktives Rechtsklick-Menü zur Verwaltung aller Block-Pfade im aktuellen Context.

**Aufruf:**
```
Command: ManageBlockImport
```

**Menü-Optionen:**

```
========================================
     BLOCK IMPORT MANAGER
========================================
Standard-Block: BLK_Hoehenkote

[L]iste      - Alle Blocks anzeigen
[S]tandard   - Standard-Block wählen
[H]inzufügen - Neuen Block hinzufügen
[E]ntfernen  - Block löschen
[A]bbrechen  - Beenden

Option: [Rechtsklick für Menü]
```

**Rechtsklick-Menü:**
- Zeigt alle Optionen als visuelles Menü
- Klick auf Option führt Aktion aus
- Alternativ: Buchstabe tippen (L/S/H/E/A)

**[L]iste - Alle Blocks anzeigen:**
```
=== Konfigurierte Blocks ===
  BLK_Hoehenkote [STANDARD] - ✓
  BLK_Anderer - ✓
  
Drücken Sie eine beliebige Taste...
```
*Menü wird nach Liste beendet*

**[S]tandard - Standard-Block wählen:**
- Zeigt nummerierte Liste aller Blocks
- Wählt Standard-Block per Nummer
- Standard wird in Config gespeichert

**[H]inzufügen - Neuen Block hinzufügen:**
- Öffnet File-Dialog zur Auswahl der DWG-Datei
- Block-Name wird automatisch aus Dateinamen extrahiert
- Speichert Pfad mit Context-Präfix in Config
- Setzt neuen Block automatisch als Standard

**[E]ntfernen - Block löschen:**
- Zeigt nummerierte Liste mit [STANDARD] Markierung
- Entfernt gewählten Block aus Config
- Wenn Standard entfernt: Fragt nach neuem Standard

---

### ShowBlockPath - Pfade anzeigen

Zeigt alle konfigurierten Block-Pfade im aktuellen Context.

**Aufruf:**
```
Command: ShowBlockPath
```

**Ausgabe:**
```
=== Konfigurierte Block-Pfade (Context: SetHK) ===
*STANDARD*: BLK_Hoehenkote
BLK_Hoehenkote: D:/Pfad/zu/BLK_Hoehenkote.dwg [✓ Existiert]
BLK_Anderer: D:/Pfad/zu/BLK_Anderer.dwg [✓ Existiert]

Config-Datei: C:\Users\...\AppData\Roaming\AutoCAD\BlockImportConfig.txt
```

---

### ResetBlockPath - Pfade zurücksetzen

Löscht alle gespeicherten Block-Pfade im aktuellen Context.

**Aufruf:**
```
Command: ResetBlockPath
```

**Hinweis:** Beim nächsten Block-Import wird erneut nach Dateien gefragt.

## Konfiguration

### Config-Datei mit Context-Namespaces

**Speicherort:**
```
%APPDATA%\AutoCAD\BlockImportConfig.txt
```

**Format mit Namespaces:**
```
1.0
*STANDARD:SetHK*=BLK_Hoehenkote
SetHK:BLK_Hoehenkote=D:/Pfad/zu/BLK_Hoehenkote.dwg
SetHK:BLK_Anderer=D:/Pfad/zu/BLK_Anderer.dwg
*STANDARD:HoeheAufLinie*=BLK_Height
HoeheAufLinie:BLK_Height=D:/Pfad/zu/BLK_Height.dwg
```

**Erste Zeile:** Versions-Nummer (1.0)  
**Format:** `Context:BlockName=Pfad`  
**Standard:** `*STANDARD:Context*=BlockName`

### Context-Namespace System

**Was sind Contexts?**
- Eindeutige ID für jedes Script (z.B. "SetHK", "HoeheAufLinie")
- Isoliert Blocks zwischen verschiedenen Scripts
- Verhindert Konflikte bei gleichen Block-Namen

**Warum Namespaces?**
- Mehrere Scripts können BlockImport.lsp nutzen
- Jedes Script hat eigene Block-Liste
- Eine zentrale Config-Datei
- Keine gegenseitige Beeinflussung

**Beispiel:**
```
SetHK:BLK_Hoehenkote        → Für SetHoehenkote.lsp
HoeheAufLinie:BLK_Hoehenkote → Für HoeheAufLinie.lsp
```
*Gleicher Block-Name, verschiedene Contexts!*

### Standard-Block Konzept

**Was ist der Standard-Block?**
- Wird verwendet wenn `ensure-block-available` ohne Parameter aufgerufen wird
- Jeder Context hat eigenen Standard-Block
- Bei nur einem Block: Automatisch als Standard gesetzt
- Bei mehreren Blocks: Manuell über `ManageBlockImport` wählen

**Warum Standard-Block?**
- Scripts können `ensure-block-available` ohne Blockname aufrufen
- Vereinfacht Code in aufrufenden Scripts
- Flexibel: User kann Standard ändern ohne Script-Änderung

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet
- **AutoCAD LT:** ❌ Nicht kompatibel (kein AutoLISP Support)
- **Abhängigkeiten:** Keine externen Libraries

### Lee Mac Utilities

BlockImport.lsp nutzt folgende Funktionen von Lee Mac:
- `LM:GetDocumentObject` - ObjectDBX Interface
- `LM:getitem` - VLA Collection Item Retrieval

Quelle: [Lee Mac Programming](https://www.lee-mac.com/)

### API für Script-Entwickler

**Context setzen (WICHTIG!):**
```lisp
(setq *block-import-context* "MeinScript")
```

**Hauptfunktion:**
```lisp
(ensure-block-available blockname)
```

**Parameter:**
- `blockname` - Name des Blocks (String) oder nil für Standard-Block

**Rückgabe:**
- `(T importEnt)` bei Erfolg - importEnt ist Entity zum späteren Löschen
- `(nil nil)` bei Fehler

**Block-Manager aufrufen:**
```lisp
(manage-block-import "MeinScript")  ; Mit Context
(manage-block-import nil)           ; Nutzt globale *block-import-context*
```

**Hilfsfunktionen:**
```lisp
(get-standard-block)           ;; Gibt Standard-Block für aktuellen Context zurück
(set-standard-block blockname) ;; Setzt Standard-Block für aktuellen Context
(read-block-path blockname)    ;; Liest Pfad für Block im aktuellen Context
(save-block-path blockname filepath) ;; Speichert Pfad mit Context-Präfix
```

**Beispiel vollständig:**
```lisp
;; Am Anfang Ihres Scripts:
(setq *block-import-context* "MeinTool")
(load "lib/BlockImport.lsp")

;; Block importieren:
(setq result (ensure-block-available "BLK_MeinBlock"))
(if (car result)
  (princ "\nBlock verfügbar!")
  (progn
    (princ "\nFehler beim Laden!")
    ;; Optional: Block-Manager öffnen
    (manage-block-import "MeinTool")
  )
)
```

## Lizenz

Dieses Script nutzt Code von Lee Mac (www.lee-mac.com).  
Lee Mac's Code ist frei verfügbar für nicht-kommerzielle und kommerzielle Nutzung.

---

**Version:** 1.5.1  
**Datum:** 2026-02-13  
**Autor:** Herbert Schrotter
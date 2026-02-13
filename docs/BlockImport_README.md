# BlockImport

Gemeinsame Bibliothek für Block-Import in AutoCAD.
Verwaltet Block-Dateipfade zentral und lädt Blocks automatisch aus externen DWG-Dateien.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| ManageBlockImport | Block-Verwaltung mit Keyword-Menü |
| ShowBlockPath | Zeigt alle konfigurierten Block-Pfade |
| ResetBlockPath | Löscht alle gespeicherten Pfade |

## Features

- ✅ Zentrale Konfiguration für alle Block-Pfade
- ✅ Automatischer Standard-Block bei nur einem Block
- ✅ Interaktives Management-Menü
- ✅ Intelligente Pfad-Suche mit Fallback-Mechanismen
- ✅ Persistente Speicherung in Config-Datei
- ✅ Keine Code-Änderung in aufrufenden Scripts nötig

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

**Beim ersten Aufruf:**
- User wählt DWG-Datei für den Block
- Pfad wird gespeichert in Config
- Block wird importiert

**Bei weiteren Aufrufen:**
- Pfad aus Config gelesen
- Block automatisch geladen
- Keine User-Interaktion nötig

---

### ManageBlockImport - Block-Verwaltung

Interaktives Menü zur Verwaltung aller Block-Pfade.

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

Option:
```

**[L]iste - Alle Blocks anzeigen:**
```
=== Konfigurierte Blocks ===
  BLK_Hoehenkote [STANDARD] - ✓
  BLK_Anderer - ✓
  BLK_Dritter - ✗ Nicht gefunden!
```

**[S]tandard - Standard-Block wählen:**
- Zeigt nummerierte Liste aller Blocks
- Wählt Standard-Block per Nummer
- Standard wird in Config gespeichert

**[H]inzufügen - Neuen Block hinzufügen:**
- Fragt nach Block-Namen
- Öffnet File-Dialog zur Auswahl der DWG-Datei
- Speichert Pfad in Config

**[E]ntfernen - Block löschen:**
- Zeigt nummerierte Liste
- Entfernt gewählten Block aus Config

---

### ShowBlockPath - Pfade anzeigen

Zeigt alle konfigurierten Block-Pfade mit Status.

**Aufruf:**
```
Command: ShowBlockPath
```

**Ausgabe:**
```
=== Konfigurierte Block-Pfade ===
*STANDARD*: BLK_Hoehenkote
BLK_Hoehenkote: D:/Pfad/zu/BLK_Hoehenkote.dwg [✓ Existiert]
BLK_Anderer: D:/Pfad/zu/BLK_Anderer.dwg [✓ Existiert]

Config-Datei: C:\Users\...\AppData\Roaming\AutoCAD\BlockImportConfig.txt
```

---

### ResetBlockPath - Pfade zurücksetzen

Löscht alle gespeicherten Block-Pfade.

**Aufruf:**
```
Command: ResetBlockPath
```

**Hinweis:** Beim nächsten Block-Import wird erneut nach Dateien gefragt.

## Konfiguration

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\BlockImportConfig.txt
```

**Format:**
```
1.0
*STANDARD*=BLK_Hoehenkote
BLK_Hoehenkote=D:/Pfad/zu/BLK_Hoehenkote.dwg
BLK_Anderer=D:/Pfad/zu/BLK_Anderer.dwg
```

**Erste Zeile:** Versions-Nummer (1.0)  
**Zweite Zeile:** Standard-Block (optional)  
**Weitere Zeilen:** Blockname=Dateipfad

### Standard-Block Konzept

**Was ist der Standard-Block?**
- Wird verwendet wenn `ensure-block-available` ohne Parameter aufgerufen wird
- Bei nur einem konfigurierten Block: Automatisch als Standard gesetzt
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

**Hauptfunktion:**
```lisp
(ensure-block-available blockname)
```

**Parameter:**
- `blockname` - Name des Blocks (String) oder nil für Standard-Block

**Rückgabe:**
- `(T importEnt)` bei Erfolg - importEnt ist Entity zum späteren Löschen
- `(nil nil)` bei Fehler

**Beispiel:**
```lisp
(setq result (ensure-block-available "BLK_Hoehenkote"))
(if (car result)
  (princ "\nBlock verfügbar!")
  (princ "\nFehler beim Laden!")
)
```

**Hilfsfunktionen:**
```lisp
(get-standard-block)           ;; Gibt Standard-Block zurück
(set-standard-block blockname) ;; Setzt Standard-Block
(read-block-path blockname)    ;; Liest Pfad für Block
(save-block-path blockname filepath) ;; Speichert Pfad
```

## Lizenz

Dieses Script nutzt Code von Lee Mac (www.lee-mac.com).  
Lee Mac's Code ist frei verfügbar für nicht-kommerzielle und kommerzielle Nutzung.

---

**Version:** 1.3.1  
**Datum:** 2026-02-13  
**Autor:** Herbert Schrotter

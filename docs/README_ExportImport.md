# LayerExportImport

Layer-Synchronisation zwischen AutoCAD-Zeichnungen ueber eine zentrale Master-Datei.
Haelt alle 10 Layer-Eigenschaften (Farbe, Linientyp, Linienstaerke, Plot, OnOff, Freeze, Lock, VP-Default, Beschreibung, Transparenz) in allen Zeichnungen konsistent.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| LAYSYNC | Import + Export mit Batch-Option |
| LAYSYNCALL | Alle registrierten Zeichnungen synchronisieren |
| LAYEXP | Nur Export: Layer in Master schreiben |
| LAYIMP | Nur Import: Layer aus Master holen |
| LAYLOG | Aenderungshistorie anzeigen |
| LAYSTATUS | Uebersicht aller Zeichnungen und Sync-Stand |
| LAYCFG | Konfiguration (Pfad, Praefix, Debug) |

## Features

- ✅ Alle 10 Layer-Properties synchronisiert (Farbe, Linientyp, Linienstaerke, Plot, OnOff, Freeze, Lock, VP-Default, Beschreibung, Transparenz)
- ✅ MasterID-System fuer zeichnungsuebergreifendes Layer-Tracking
- ✅ Automatische Erkennung von Layer-Umbenennungen (Handle-basiert)
- ✅ DWG-Umbenennungserkennung via Custom Property GUID
- ✅ SyncLog: Konflikterkennung bei gleichzeitiger Bearbeitung durch mehrere Zeichnungen
- ✅ Batch-Sync: Offene DWGs via Documents, geschlossene via ObjectDBX
- ✅ Interaktive Konfliktloesung (Master/Lokal/alleMaster/alleLokal)
- ✅ Export-Konflikterkennung (Ueberschreiben/Behalten/AlleUeber/AlleBehalten)
- ✅ Automatisches Laden fehlender Linientypen aus acadiso.lin
- ✅ Export-Schutz: Continuous-Fallback ueberschreibt Master-Linientyp nicht
- ✅ Layer-Loeschung: Entfernte Layer werden in anderen DWGs geloescht/deaktiviert
- ✅ Append-Only History fuer lueckenloses Aenderungsprotokoll
- ✅ LAYSTATUS mit Letzter-Sync-Zeitpunkt pro Zeichnung

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausfuehren
2. `LayerExportImport.lsp` auswaehlen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufuegen

### Support-Ordner (Alternative)

Kopieren nach:
```
%APPDATA%\Autodesk\AutoCAD 2024\R24.3\deu\Support\
```

### Tastenkuerzel

`LAYSYNC` auf `Strg+Shift+L` legen ueber AutoCAD CUI (Benutzeroberflaechenanpassung).

## Verwendung

### LAYSYNC - Hauptbefehl

Fuehrt Import und Export in einem Schritt aus. Empfohlener Standardbefehl fuer den taeglichen Einsatz.

**Aufruf:**
```
Command: LAYSYNC
```

**Ablauf:**
1. Import: Liest Master-Datei und gleicht Layer in der aktuellen Zeichnung ab
2. Export: Schreibt lokale Layer-Aenderungen in die Master-Datei zurueck
3. Fragt am Ende: "Alle Zeichnungen syncen? [Ja/Nein]"

**Beispiel - Erster Sync:**
```
Command: LAYSYNC
========================================
  LAYSYNC: Einreichplan Nicole.dwg
  LayerSyncGUID erstellt: LXI-20260309040113-85359
  GUID:    LXI-20260309040113-85359
========================================
>> Schritt 1/2: Import (Master -> Zeichnung)
  Import: Kein Master gefunden.
>> Schritt 2/2: Export (Zeichnung -> Master)
  --- Export (Einreichplan Nicole.dwg) ---
    + 44 neu in Master
    Master gesamt: 44 Layer
========================================
  Export OK (Master war leer).
========================================
Alle Zeichnungen syncen? [Ja/Nein] <Nein>:
```

**Beispiel - Folgende Syncs:**
```
Command: LAYSYNC
========================================
  LAYSYNC: Schnitt A-A.dwg
  GUID:    LXI-20260309045133-05250
========================================
>> Schritt 1/2: Import (Master -> Zeichnung)
  66 Layer im Master.
  53 Layer bekannt.
  --- Import (Schnitt A-A.dwg) ---
    + 13 neu angelegt
>> Schritt 2/2: Export (Schnitt A-A.dwg)
  --- Export (Schnitt A-A.dwg) ---
    = Master ist aktuell
    Master gesamt: 66 Layer
========================================
  Sync erfolgreich.
========================================
```

**Konflikte:**

Wenn die Layer-Eigenschaften zwischen Master und Zeichnung abweichen, erscheint ein Auswahldialog:

```
========================================
  KONFLIKT: S_01_S-Fassade-EPS-Schraff
  Unterschiede zwischen Master und dieser Zeichnung:
  Linientyp: Master=ZICKZACK  Lokal=Continuous

  Master     = Wert aus Master uebernehmen
  Lokal      = Lokalen Wert behalten
  alleMaster = Master fuer ALLE weiteren Konflikte
  alleLokal  = Lokal fuer ALLE weiteren Konflikte
Entscheidung [Master/Lokal/alleMaster/alleLokal]:
```

### LAYSYNCALL - Batch-Synchronisation

Synchronisiert alle registrierten Zeichnungen automatisch. Die aktuelle Zeichnung wird zuerst normal gesynced, dann werden alle anderen Zeichnungen aktualisiert.

**Aufruf:**
```
Command: LAYSYNCALL
```

**Zwei Methoden je nach Dateistatus:**
- **[O] Offen:** Zeichnung ist als Tab geoeffnet → Sync ueber Documents-Collection (schnell, sicher, kann Layer loeschen)
- **[D] ObjectDBX:** Zeichnung ist geschlossen → Sync ueber ObjectDBX im Hintergrund (kann Layer nur auf OFF setzen)

**Beispiel:**
```
========================================
  LAYSYNCALL - Batch-Synchronisation
========================================
>> Aktuelle Zeichnung: Ansicht Sued.dwg
  ...
>> 6 Zeichnungen registriert.
   [O]=Offen  [D]=ObjectDBX  [!]=Fehler
  [1] Ansicht Ost.dwg              [O] +0 ~0 =66
  [2] Einreichplan Nicole.dwg      [O] +1 ~0 =66
  [3] Schnitt A-A.dwg              [O] +0 ~0 =67
  [4] Schnitt B-B.dwg              [O] +0 ~0 =67
  [5] Schnitt C-C.dwg              [D] +0 ~0 =67
========================================
  BATCH-ERGEBNIS:
    Zeichnungen:  6 (4 offen, 1 DBX, 0 Fehler)
    Neu angelegt: 1
    Aktualisiert: 0
    Synchron:     333
    Keine Konflikte.
========================================
```

**Ausgabe-Legende:**
- `+N` = N Layer neu angelegt
- `~N` = N Layer aktualisiert (Eigenschaften geaendert)
- `=N` = N Layer bereits synchron
- `-N` = N Layer entfernt/deaktiviert (nicht mehr im Master)

**Layer-Loeschung:**

Wenn ein Layer aus dem Master geloescht wurde:
- Offene DWGs: Layer wird geloescht. Falls Objekte auf dem Layer liegen, wird er auf OFF gesetzt.
- Geschlossene DWGs: Layer wird nur auf OFF gesetzt (kein Loeschen via ObjectDBX).

Die Zusammenfassung zeigt Details:
```
  ENTFERNTE LAYER (nicht mehr im Master):
  Ansicht Ost.dwg:
    S_00_Test                      -> geloescht
  Schnitt C-C.dwg:
    S_00_Test                      -> OFF
```

### LAYEXP - Nur Export

Exportiert alle S_-Layer der aktuellen Zeichnung in die Master-Datei. Neue Layer bekommen eine MasterID, bestehende werden aktualisiert, Umbenennungen erkannt.

**Aufruf:**
```
Command: LAYEXP
```

**Wann verwenden:** Wenn nur die lokalen Aenderungen in den Master geschrieben werden sollen, ohne aus dem Master zu importieren.

### LAYIMP - Nur Import

Importiert Layer aus der Master-Datei in die aktuelle Zeichnung. Interaktive Konfliktloesung bei Abweichungen.

**Aufruf:**
```
Command: LAYIMP
```

**Wann verwenden:** Wenn nur der Master-Stand in die Zeichnung uebernommen werden soll, ohne lokale Layer zu exportieren.

**Besondere Situationen beim Import:**

**Fehlender Layer (lokal geloescht):**
```
========================================
  FEHLEND: S_00_Test [M000067]
  Layer im Master, aber lokal geloescht.

  Neu       = Layer wieder anlegen (aus Master)
  Ignorieren = Nichts tun
  Loeschen  = Aus Master entfernen!
Entscheidung [Neu/Ignorieren/Loeschen]:
```

**Umbenennung erkannt:**
```
========================================
  UMBENENNUNG erkannt: [M000042]
  Master: S_01_A-Holz
  Lokal:  S_01_A-Holzbalken

  Master = Lokal auf Master-Name umbenennen
  Lokal  = Lokalen Namen behalten
Entscheidung [Master/Lokal]:
```

### LAYLOG - Aenderungshistorie

Zeigt die Layer-Aenderungshistorie aus der History-Datei. Kann nach Layer gefiltert werden.

**Aufruf:**
```
Command: LAYLOG
```

**Optionen:**
- `Alle` - Letzte 30 Aenderungen anzeigen
- `Layer` - Nach Layername filtern (Teilname moeglich)

**Beispiel:**
```
Command: LAYLOG
66 History-Eintraege.
[Alle/Layer] <Alle>: Layer
Layername (Teil): Fassade
> S_01_S-Fassade-EPS-Schraff [M000051]

=== S_01_S-Fassade-EPS-Schraff [M000051] ===
Datum              Aktion        Layer                    Quelle          Detail
-----------------------------------------------------------------------------
2026-03-09 04:01   NEU           S_01_S-Fassade-EPS-..   Schnitt C-C..
2026-03-09 04:54   AENDERUNG     S_01_S-Fassade-EPS-..   Schnitt A-A..   Linientyp:..
```

**Aktionen in der History:**
- `NEU` - Layer zum ersten Mal im Master registriert
- `AENDERUNG` - Eigenschaften geaendert (Farbe, Linientyp, Linienstaerke, Plot, OnOff, etc.)
- `UMBENENNUNG` - Layer wurde umbenannt

### LAYSTATUS - Uebersicht

Zeigt den Sync-Stand aller registrierten Zeichnungen als Tabelle mit letztem Sync-Zeitpunkt.

**Aufruf:**
```
Command: LAYSTATUS
```

**Beispiel:**
```
====== LayerSync Status ======
Master: 68 Layer | Praefix: S_*
Properties: Farbe, Linientyp, Linienstaerke, Plot, OnOff,
            Freeze, Lock, VP-Default, Beschreibung, Transparenz
Zeichnung                   Layer  Fehlend   Letzter Sync
----------------------------  -------  ----------  --------------------
Ansicht Ost.dwg             68     OK        2026-03-10 01:12
Ansicht Sued.dwg            68     OK        2026-03-10 01:11
Einreichplan Nicole.dwg     68     OK        2026-03-10 01:13
Schnitt A-A.dwg             68     OK        2026-03-10 01:14
Schnitt B-B.dwg             68     OK        2026-03-10 01:14
Schnitt C-C.dwg             68     OK        2026-03-10 01:15

  * Aktuell: Ansicht Sued.dwg
==============================
```

### LAYCFG - Konfiguration

Zeigt und aendert die Konfiguration: Sync-Ordner, Layer-Praefix und Debug-Modus.

**Aufruf:**
```
Command: LAYCFG
```

**Beispiel:**
```
=== LayerSync Konfiguration ===
  [P]fad:    D:\OneDrive\...\LayerSync
  P[r]aefix: S_
  [D]ebug:   OFF
  DWG-GUID:  LXI-20260309052751-83250
===============================
[Pfad/pRaefix/Debug] <Abbruch>:
```

**Einstellungen:**
- **Pfad:** Ordner fuer Master-, Mapper-, History- und Config-Dateien (OneDrive-kompatibel)
- **Praefix:** Nur Layer mit diesem Praefix werden synchronisiert (Standard: `S_`)
- **Debug:** Ausfuehrliche Konsolenausgabe fuer Fehlersuche

## Konfiguration

### Config-Datei

**Speicherort:**
```
D:\OneDrive\Dokumente\02 Arbeit\05 Vorlagen - Scripte\02_Autocad_Tools\LayerSync\LayerSync.cfg
```

**Format:**
```
;;; LayerSync Konfiguration v2.0.0
PATH=D:\OneDrive\Dokumente\02 Arbeit\05 Vorlagen - Scripte\02_Autocad_Tools\LayerSync
PREFIX=S_
DEBUG=OFF
```

### Sync-Dateien

Alle Dateien liegen im konfigurierten Sync-Ordner (semikolon-getrennte CSV, ANSI-Encoding):

**LayerMaster.csv** - Zentrale Layer-Datenbank (14 Felder):
```
MasterID;Name;Color;Linetype;Lineweight;Plot;OnOff;Freeze;Lock;VPDefault;Description;Transparency;Source;LastModified
M000001;S_00_Abbruch_Tueren;50;Continuous;-3;PLOT;ON;THAWED;UNLOCKED;0;;0;Schnitt C-C.dwg;2026-03-10 01:11
```

**LayerMapper.csv** - Verknuepfung DWG ↔ Layer (6 Felder):
```
MasterID;LayerName;Handle;DwgName;DwgPath;DwgGUID
M000001;S_00_Abbruch_Tueren;40505E2;Ansicht Sued.dwg;D:\OneDrive\...\;LXI-20260310011155-25640
```

**LayerHistory.csv** - Aenderungsprotokoll (6 Felder, append-only):
```
MasterID;LayerName;Datum;Aktion;Detail;Source
M000001;S_00_Abbruch_Tueren;2026-03-10 01:11;NEU;;Ansicht Sued.dwg
```

**LayerSyncLog.csv** - Letzter Sync-Zeitpunkt pro DWG (3 Felder):
```
DwgName;DwgGUID;LastSync
Ansicht Sued.dwg;LXI-20260310011155-25640;2026-03-10 01:12
```

Wird fuer Konflikterkennung beim Export genutzt: Wenn der Master-Eintrag neuer ist als der letzte Sync dieser DWG und von einer anderen Zeichnung stammt, wird ein Konflikt angezeigt.

### LayerSyncGUID

Jede Zeichnung bekommt beim ersten LAYSYNC eine eindeutige GUID als Custom Property. Diese ist in AutoCAD unter `DWGPROPS` → Reiter "Benutzerdefiniert" sichtbar als `LayerSyncGUID`.

Die GUID bleibt bei SaveAs, Kopie und Umbenennung erhalten. So erkennt das Script wenn eine DWG umbenannt wird und aktualisiert die Mapper-Eintraege automatisch.

**Format:** `LXI-YYYYMMDDHHMMSS-NNNNN` (Datum + 5-stellige Zufallszahl)

**Wichtig:** Nach dem ersten LAYSYNC die Zeichnung speichern, damit die GUID permanent in der DWG bleibt.

## Konzepte

### MasterID-System

Jeder Layer bekommt beim ersten Export eine eindeutige MasterID (z.B. `M000001`). Diese ID ist der Primary Key und bleibt auch bei Umbenennungen gleich. Der Mapper verknuepft die MasterID mit dem Handle des Layers in jeder Zeichnung.

### Handle-basiertes Tracking

Jedes AutoCAD-Objekt (auch Layer) hat ein eindeutiges Handle. Dieses Handle aendert sich nicht bei Umbenennungen. Darüber erkennt das Script: "Layer mit Handle 4050008 hiess im Master S_00_Dachvorsprung, heisst lokal aber S_00_Dachueberstand → Umbenennung erkannt."

### Linientyp-Laden

Wenn ein Layer aus dem Master einen Sonder-Linientyp hat (z.B. ZICKZACK), der lokal nicht vorhanden ist:
1. Automatisches Laden aus `acadiso.lin`
2. Falls nicht gefunden: Dateiauswahl-Dialog fuer .lin-Datei
3. Falls abgebrochen: Fallback auf Continuous

### Export-Schutz fuer Linientypen

Wenn eine Zeichnung einen Layer mit Continuous hat (weil der Sonder-Linientyp nicht geladen war), aber der Master den echten Linientyp kennt, dann ueberschreibt der Export den Master-Wert **nicht**. So geht der Original-Linientyp nicht verloren.

### Sync-Reihenfolge

LAYSYNC fuehrt immer **Import zuerst, dann Export** aus. So werden neue Layer aus dem Master geholt bevor lokale Aenderungen zurueckgeschrieben werden. Konflikte werden erkannt bevor der Master ueberschrieben wird.

## Empfohlener Workflow

### Ersteinrichtung

1. `APPLOAD` → `LayerExportImport.lsp` laden
2. Zu Startup Suite hinzufuegen
3. In der Haupt-Zeichnung `LAYSYNC` ausfuehren (erstellt Master)
4. Zeichnung speichern (GUID wird permanent)
5. In jeder weiteren Zeichnung `LAYSYNC` ausfuehren
6. Jede Zeichnung speichern

### Taeglicher Einsatz

1. Zeichnung oeffnen
2. `LAYSYNC` (oder `Strg+Shift+L`)
3. Bei Konflikten: Master oder Lokal waehlen
4. Optional: "Alle Zeichnungen syncen?" → Ja

### Neuen Layer anlegen

1. Layer in einer Zeichnung erstellen (mit `S_`-Praefix)
2. `LAYSYNC` → Layer erscheint im Master
3. `LAYSYNCALL` → Layer wird in alle Zeichnungen uebertragen

### Layer loeschen

1. Layer in einer Zeichnung loeschen
2. `LAYSYNC` → Frage: "Neu anlegen / Ignorieren / aus Master Loeschen"
3. "Loeschen" waehlen → Layer wird aus Master entfernt
4. `LAYSYNCALL` → Layer wird in offenen DWGs geloescht, in geschlossenen auf OFF gesetzt

### Layer umbenennen

1. Layer in einer Zeichnung umbenennen
2. `LAYSYNC` → Umbenennung wird erkannt und im Master aktualisiert
3. `LAYSYNCALL` → Andere Zeichnungen bekommen den neuen Namen

## Technische Details

- **AutoCAD Version:** 2024 (getestet mit AutoCAD 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet
- **ObjectDBX:** Fuer Batch-Sync geschlossener Zeichnungen
- **AutoCAD LT:** ❌ Nicht kompatibel (kein AutoLISP Support)
- **Abhaengigkeiten:** Keine externen Libraries
- **Encoding:** ANSI (Windows-1252) fuer CSV-Dateien
- **OneDrive:** Kompatibel (Sync-Ordner auf OneDrive empfohlen)

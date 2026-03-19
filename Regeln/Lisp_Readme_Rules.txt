================================================================================
README RULES FUER AUTOLISP/LISP PROJEKTE
================================================================================
Version: 2.0
Erstellt: 2026-02-13
Aktualisiert: 2026-03-17
Autor: Herbert Schrotter
Zweck: Standardisierte README-Struktur fuer AutoLISP-Scripte

WICHTIG: Diese Regeln sind VERBINDLICH fuer alle AutoLISP READMEs!
         Dateiname: docs/ScriptName_README.md


================================================================================
1. GRUNDSTRUKTUR
================================================================================

Reihenfolge (von oben nach unten):

 1. Header (Projekt-Name + Kurzbeschreibung)
 2. Befehle (Tabelle - WICHTIGSTE SEKTION!)
 3. Features (optional - nur wenn besonders)
 4. Installation (APPLOAD-Methode)
 5. Verwendung (Befehle ausfuehrlich)
 6. Konfiguration (AppData-Pfade, Config-Datei)
 7. Log-Datei (VERPFLICHTEND!)
 8. Context-Namespace (VERPFLICHTEND!)
 9. Vergleich mit verwandten Tools (optional)
10. Technische Details (AutoCAD-Version, LT-Kompatibilitaet)

SPEICHERORT:
------------
docs/ScriptName_README.md

BEISPIELE:
- docs/LayerExportImport_README.md
- docs/SetHoehenkote_README.md
- docs/HoeheAufLinie_README.md
- docs/AutoLoadDimStyle_README.md

NIEMALS im Projekt-Root! Immer in docs/ Ordner!


================================================================================
2. HEADER
================================================================================

FORMAT:
-------
# Projekt-Name

Kurzbeschreibung in 1-2 Saetzen: WAS macht es und FUER WEN.

BEISPIEL:
---------
# AutoLoadDimStyle

Automatisches Laden von Bemassungsstilen fuer AutoCAD.
Vereinfacht die Verwaltung von Master-Dateien.

REGELN:
-------
- H1 nur fuer Projekt-Name
- Erste Zeile: WAS
- Zweite Zeile (optional): Nutzen/Zielgruppe
- Keine Marketing-Sprache
- Klar & direkt


================================================================================
3. BEFEHLE-TABELLE (KRITISCH!)
================================================================================

POSITION:
---------
Direkt nach Header, VOR Features, VOR Installation!

FORMAT:
-------
## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| CMD1   | Kurzbeschreibung was es macht |
| CMD2   | Kurzbeschreibung was es macht |

REGELN:
-------
- Tabelle mit genau 2 Spalten
- Spalte 1: Befehlsname (wie in AutoCAD einzugeben)
- Spalte 2: Eine Zeile Beschreibung (max 60 Zeichen)
- Sortierung: Wichtigster Befehl zuerst
- Keine technischen Details hier
- Nur ausfuehrbare Befehle (keine internen Funktionen)
- Debug-Befehle ans Ende der Tabelle

BEISPIEL GUT:
-------------
| LAYSYNC         | Synchronisiert Layer mit Master-CSV       |
| LAYSYNCALL      | Batch-Sync aller Mapper-Zeichnungen       |
| LAYDIFF         | Zeigt Unterschiede ohne zu syncen         |
| LAYCOUNT        | Einzeilige Status-Zusammenfassung         |
| LAYCFG          | Einstellungen (AutoSync, Notify, Pfad)    |
| HALDEBUG        | Debug-Modus ein/aus (Entwicklung)         |

BEISPIEL SCHLECHT:
------------------
| DimStyleManager | Oeffnet ein interaktives Keyword-basiertes Menue... |
→ Zu lang!

| LXI:read-master | Interne Funktion zum CSV-Lesen |
→ Kein User-Befehl! Gehoert in Namespace-Sektion!


================================================================================
4. FEATURES (OPTIONAL)
================================================================================

WANN VERWENDEN:
---------------
- Projekt hat mehrere besondere Features
- Features sind nicht offensichtlich
- Features sind Verkaufsargument

WANN WEGLASSEN:
---------------
- Einfaches Utility-Script
- Features sind selbstverstaendlich

FORMAT:
-------
## Features

- Automatisches Laden beim Zeichnungsstart
- Mehrere Master-Dateien verwalten
- Persistente Konfiguration in %APPDATA%
- Ausfuehrliches Session-Logging (max 5 Sessions)
- AutoSync via Reactor beim Speichern

REGELN:
-------
- Bullet-Liste (ohne Emoji)
- Max 5-7 Features
- Konkret, nicht vage
- Nutzen klar machen
- Keine technischen Details

BEISPIEL SCHLECHT:
------------------
- Verwendet modernste AutoLISP-Techniken  → Zu vage!
- Performant durch O(n) Algorithmen       → Zu technisch!


================================================================================
5. INSTALLATION
================================================================================

FORMAT:
-------
## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausfuehren
2. `Dateiname.lsp` auswaehlen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufuegen

### Support-Ordner (Alternative)

Kopieren nach:
```
%APPDATA%\Autodesk\AutoCAD 2024\R24.3\deu\Support\
```

REGELN:
-------
- APPLOAD immer als erste Methode
- Nummerierte Schritte
- Startup Suite erwaehnen
- Support-Ordner als Alternative
- Pfade als Code-Block
- Kurz & knapp

BEI ABHAENGIGKEITEN:
--------------------
Wenn Script eine Library braucht (z.B. BlockImport.lsp),
explizit erwaehnen:

### Abhaengigkeiten

- `BlockImport.lsp` muss im selben Ordner oder Support-Pfad liegen
- Wird automatisch geladen (3-Fallback Pfadsuche)

NIEMALS:
--------
- Komplizierte acaddoc.lsp Manipulation
- Registry-Aenderungen
- Systemvariablen setzen


================================================================================
6. VERWENDUNG
================================================================================

STRUKTUR:
---------
Zweistufig:
1. Oben in Befehle-Tabelle: Kurz (1 Zeile)
2. Hier ausfuehrlich: Mit Beispielen

FORMAT PRO BEFEHL:
------------------
### BefehlsName - Titel

Kurze Beschreibung was der Befehl macht (1-2 Saetze).

**Aufruf:**
```
Command: BefehlsName
```

**Optionen:** (falls vorhanden)
- `Option1` - Was sie macht
- `Option2` - Was sie macht

**Workflow:** (falls mehrstufig)
1. Schritt 1
2. Schritt 2
3. Schritt 3

**Beispiel:**
```
Command: BefehlsName
[Prompt]: [Eingabe]
→ [Was passiert]
```

REGELN:
-------
- Wichtigster Befehl zuerst
- Aufruf immer zeigen (Command: ...)
- Beispiele mit → fuer Output
- Copy-Paste ready
- AutoCAD Command-Line Format

BEISPIEL:
---------
### HAL - Hoeheninterpolation auf Linie

Interpoliert Hoehen zwischen zwei Fixpunkten entlang einer Geraden.

**Aufruf:**
```
Command: HAL
```

**Optionen waehrend Punktwahl:**
- `S` - Skalierung aendern
- `K` - Konstruktionslinie (XLINE) bei Zielhoehe

**Workflow:**
1. Fixpunkt 1 waehlen + Hoehe eingeben
2. Fixpunkt 2 waehlen + Hoehe eingeben
3. Beliebig viele Punkte entlang der Linie waehlen
4. ESC zum Beenden

**Beispiel:**
```
Command: HAL
Fixpunkt 1 waehlen: [Klick]
Hoehe Fixpunkt 1: 322.00
Fixpunkt 2 waehlen: [Klick]
Hoehe Fixpunkt 2: 344.00
Punkt waehlen [Skalierung/Konstruktion]: [Klick]
→ Hoehenkote: +333.12 (Block gesetzt)
Punkt waehlen [Skalierung/Konstruktion]: [ESC]
→ 1 Punkt gesetzt, Konstruktionslinien entfernt
```


================================================================================
7. KONFIGURATION (VERPFLICHTEND!)
================================================================================

Jedes Script hat einen AppData-Ordner. Dieser MUSS dokumentiert sein.

FORMAT:
-------
## Konfiguration

### AppData-Ordner

Alle Daten werden gespeichert in:
```
%APPDATA%\AutoCAD\Lisp\<ScriptName>\
```

Unterordner:
- `Log\` — Session-Logs
- `Config\` — Konfigurationsdateien
- `Backup\` — Sicherungen (falls noetig)

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\Lisp\<ScriptName>\Config\<ScriptName>.cfg
```

**Format:**
```
VERSION=1.0
PATH=D:\OneDrive\Projekte\LayerSync
AUTOSYNC=1
NOTIFY=1
DEBUG=0
```

**Einstellungen:**
- `VERSION` - Config-Versionsnummer
- `PATH` - Arbeitspfad fuer Daten
- `AUTOSYNC` - Automatischer Sync beim Speichern (0/1)
- `NOTIFY` - Benachrichtigung bei aelterem Master (0/1)
- `DEBUG` - Debug-Modus (0/1)

### Einstellungen aendern

Ueber den Befehl `LAYCFG` (oder entsprechenden Config-Befehl)
koennen alle Einstellungen interaktiv geaendert werden.

REGELN:
-------
- Speicherort als Code-Block
- Format-Beispiel zeigen
- Jede Einstellung erklaeren
- Befehl zum Aendern nennen
- Windows-Pfad mit %APPDATA%
- KEINE hardcodierten Pfade zeigen


================================================================================
8. LOG-DATEI (VERPFLICHTEND!)
================================================================================

Jedes Script fuehrt ein ausfuehrliches Log. MUSS dokumentiert sein.

FORMAT:
-------
## Log-Datei

### Speicherort

```
%APPDATA%\AutoCAD\Lisp\<ScriptName>\Log\<ScriptName>_YYYYMMDD_HHMMSS.log
```

Pro Session wird eine neue Log-Datei erstellt.
Maximal 5 Session-Logs werden aufbewahrt, aeltere werden automatisch geloescht.

### Log-Format

```
[2026-03-17 14:30:22] [INFO ] Script gestartet v1.6.3
[2026-03-17 14:30:22] [INFO ] Config geladen
[2026-03-17 14:30:25] [INFO ] Befehl HAL gestartet
[2026-03-17 14:30:28] [INFO ] Fixpunkt 1: (1234.567 890.123) H=322.00
[2026-03-17 14:30:30] [WARN ] Hoehe ausserhalb Strecke: 350.00
[2026-03-17 14:30:35] [ERROR] VLA-Fehler: Object not found
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
Command: <ScriptName>DEBUG
→ Debug-Modus: EIN
```

Im Debug-Modus werden zusaetzliche DEBUG-Eintraege ins Log geschrieben.

REGELN:
-------
- Speicherort immer als Code-Block
- Log-Format mit Beispielzeilen zeigen
- Level-Tabelle immer einfuegen
- Debug-Befehl dokumentieren
- Max 5 Sessions erwaehnen


================================================================================
9. CONTEXT-NAMESPACE (VERPFLICHTEND!)
================================================================================

Jedes Script verwendet einen Namespace-Prefix. MUSS dokumentiert sein.

FORMAT:
-------
## Context-Namespace

Alle internen Funktionen verwenden den Prefix `HAL:` (HoeheAufLinie).

### Oeffentliche API

| Funktion | Beschreibung |
|----------|--------------|
| HAL:interpolate | Berechnet interpolierte Hoehe |
| HAL:log-write | Schreibt Log-Eintrag |

### Globale Variablen

| Variable | Beschreibung |
|----------|--------------|
| *HAL:version* | Aktuelle Script-Version |
| *HAL:initialized* | Init-Status (T/nil) |
| *HAL:debug-mode* | Debug-Modus (T/nil) |
| *HAL:log-session-id* | Aktueller Log-Dateiname |

REGELN:
-------
- Prefix erklaeren (Abkuerzung + voller Name)
- Wichtige Funktionen als Tabelle (nicht alle!)
- Globale Variablen auflisten
- Nur fuer Entwickler relevant, nicht fuer Endbenutzer
- Fuer einfache Scripts: kurze Liste reicht
- Fuer komplexe Scripts: nach Kategorie gruppieren

BEISPIEL KOMPLEX (LayerExportImport):
-------------------------------------
## Context-Namespace

Prefix: `LXI:` (LayerExportImport)

### Kernfunktionen

| Funktion | Beschreibung |
|----------|--------------|
| LXI:ensure-init | Lazy-Init (erster Aufruf) |
| LXI:read-master | Master-CSV lesen |
| LXI:write-master | Master-CSV schreiben |
| LXI:do-import | Layer importieren |
| LXI:do-export | Layer exportieren |
| LXI:cancel-p | Cancel-Erkennung (DE+EN) |
| LXI:safe-variant-value | VLA String/Variant Handler |
| LXI:dwg-guid-read | GUID lesen (read-only) |
| LXI:log-write | Log-Eintrag schreiben |


================================================================================
10. VERGLEICH MIT VERWANDTEN TOOLS (OPTIONAL)
================================================================================

WANN VERWENDEN:
---------------
- Es gibt ein verwandtes Tool im selben Projekt
- User koennte verwechseln was wann zu verwenden ist
- Klaert Abgrenzung und Empfehlung

FORMAT:
-------
## Vergleich

| Feature | SetHK | HoeheAufLinie |
|---------|-------|---------------|
| Einzelpunkte setzen | Ja | Nein |
| Interpolation | Nein | Ja |
| Konstruktionslinie | Nein | Ja |
| XY-Skalierung | Ja | Ja |
| BlockImport.lsp | Ja | Ja |
| Log-Datei | Ja | Ja |

**Wann was verwenden:**
- **SetHK:** Einzelne Hoehenkoten an beliebigen Punkten
- **HoeheAufLinie:** Mehrere Punkte entlang einer Linie interpolieren

REGELN:
-------
- Nur Tabelle wenn sinnvoll (min. 2 Tools vergleichen)
- "Wann was verwenden" Empfehlung immer dazu
- Kurz halten, nicht ueberladen
- Ja/Nein bevorzugen, keine langen Texte in Zellen


================================================================================
11. TECHNISCHE DETAILS
================================================================================

FORMAT:
-------
## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet
- **AutoCAD LT:** Nicht kompatibel (kein AutoLISP Support)
- **Abhaengigkeiten:** BlockImport.lsp (lib/)
- **AppData:** %APPDATA%\AutoCAD\Lisp\<ScriptName>\
- **Namespace:** HAL (HoeheAufLinie)

REGELN:
-------
- Bullet-Liste
- Kurz & praegnant
- AutoCAD LT Kompatibilitaet IMMER erwaehnen
- Getestete Versionen nennen
- Abhaengigkeiten auflisten
- AppData-Pfad erwaehnen
- Namespace angeben

AutoCAD LT HINWEIS (Standard-Text):
-----------------------------------
- **AutoCAD LT:** Nicht kompatibel (kein AutoLISP Support)

ODER ausfuehrlicher fuer LT 2024+:
- **AutoCAD LT 2024+:** Eingeschraenkt (kein ObjectDBX, kein VLA)
- **AutoCAD LT pre-2024:** Nicht kompatibel (kein AutoLISP)


================================================================================
12. WAS NICHT REINGEHOERT
================================================================================

WEGLASSEN:
----------
- Troubleshooting-Sektion (NIEMALS! Separate Doku falls noetig)
- Changelog (separate CHANGELOG.md)
- Contributing Guidelines (fuer simple Scripts)
- Lizenz-Texte (separate LICENSE)
- Code-Kommentare (gehoert in .lsp Datei)
- Entwickler-Dokumentation (separate DEV.md)
- API-Referenz im Detail (gehoert in Code-Kommentare)

AUSNAHMEN:
----------
- Kurzer Changelog (3-5 Zeilen) am Ende erlaubt
- Lizenz-Erwaehnung (1 Zeile) am Ende erlaubt


================================================================================
13. FORMATIERUNG
================================================================================

HEADERS:
--------
# H1 - Nur Projekt-Name
## H2 - Haupt-Sektionen (Befehle, Installation, etc.)
### H3 - Unter-Sektionen (einzelne Befehle, Config-Details)
#### H4 - Nur in Ausnahmefaellen

LISTEN:
-------
- Ungeordnet fuer Features, technische Details
1. Nummeriert fuer Installations-Schritte, Workflows

EMPHASIS:
---------
**Fett** fuer Wichtiges (Speicherort, Aufruf, etc.)
*Kursiv* fuer Betonung (sparsam verwenden)
`Code` fuer Befehle, Variablen, Dateinamen, Pfade

CODE-BLOECKE:
-------------
```
Command-Line Beispiele (kein Syntax-Highlighting)
```
```lisp
(defun beispiel ()
  (princ "AutoLISP Code")
)
```
```
Dateipfade, Config-Beispiele
```

TABELLEN:
---------
- Befehls-Uebersicht (immer)
- Log-Level Tabelle (immer)
- Namespace-Funktionen (immer)
- Vergleichstabelle (optional)
- Nicht fuer Fliesstext oder Features


================================================================================
14. LAENGE & KOMPLEXITAET
================================================================================

EINFACHES SCRIPT (1-3 Befehle):
-------------------------------
- 100-200 Zeilen README
- Pflicht: Befehle, Installation, Verwendung, Config, Log, Namespace, Tech
- Optional: Features, Vergleich

MITTLERES TOOL (3-10 Befehle):
------------------------------
- 200-400 Zeilen README
- Alles Pflicht + Features-Sektion
- Ausfuehrlichere Beispiele
- Evtl. Vergleichstabelle

KOMPLEXES PROJEKT (>10 Befehle):
--------------------------------
- 400-600 Zeilen README
- Alle Sektionen ausfuehrlich
- Mehrere Beispiele pro Befehl
- Vergleichstabelle wenn verwandte Tools existieren
- Evtl. separate Detail-Doku in docs/


================================================================================
15. TONE & STYLE
================================================================================

SPRACHE:
--------
- Deutsch (fuer deutsche AutoCAD-Version)
- Oder Englisch (fuer internationale Projekte / App Store)
- Konsistent eine Sprache waehlen
- NICHT mischen

TON:
----
- Klar & direkt
- Technisch aber verstaendlich
- Keine Marketing-Sprache
- Keine Uebertreibungen ("revolutionaer", "einzigartig")

ZIELGRUPPE:
-----------
- AutoCAD-User (nicht Programmierer)
- Kennt AutoCAD-Befehle
- Kennt evtl. kein AutoLISP
- Will schnell loslegen

BEISPIEL GUT:
-------------
"Laedt Bemassungsstile automatisch beim Zeichnungsstart."

BEISPIEL SCHLECHT:
------------------
"Unser revolutionaeres Tool bietet Ihnen moeglicherweise..."


================================================================================
16. CHECKLISTE VOR VEROEFFENTLICHUNG
================================================================================

README QUALITAET:
-----------------
[ ] Header vorhanden (Name + Beschreibung)
[ ] Befehle-Tabelle direkt nach Header
[ ] Installation mit APPLOAD-Methode
[ ] Jeder Befehl hat ausfuehrliches Beispiel
[ ] Config-Sektion mit AppData-Pfad
[ ] Log-Datei Sektion mit Format und Levels
[ ] Context-Namespace mit Funktions-Tabelle
[ ] Vergleichstabelle (falls verwandte Tools existieren)
[ ] AutoCAD LT Kompatibilitaet erwaehnt
[ ] Technische Details vollstaendig
[ ] Keine Rechtschreibfehler
[ ] Code-Bloecke korrekt formatiert
[ ] Alle Pfade korrekt (%APPDATA%, Slashes)
[ ] Kein Troubleshooting-Abschnitt!

INHALT:
-------
[ ] Befehle stimmen mit .lsp Datei ueberein
[ ] Namespace stimmt mit Code ueberein
[ ] Beispiele getestet
[ ] Versions-Nummer aktuell
[ ] Kein veralteter Content
[ ] AppData-Pfad korrekt


================================================================================
17. BEISPIEL TEMPLATE
================================================================================

# ScriptName

Kurzbeschreibung in 1-2 Saetzen.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| CMD1   | Macht X |
| CMD2   | Macht Y |
| CMD1DEBUG | Debug-Modus ein/aus |

## Features

- Feature 1
- Feature 2
- Ausfuehrliches Session-Logging
- Persistente Konfiguration in %APPDATA%

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausfuehren
2. `ScriptName.lsp` auswaehlen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufuegen

### Abhaengigkeiten

- `BlockImport.lsp` muss im selben Ordner oder Support-Pfad liegen

## Verwendung

### CMD1 - Beschreibung

Ausfuehrliche Beschreibung.

**Aufruf:**
```
Command: CMD1
```

**Optionen:**
- `A` - Option A
- `B` - Option B

**Beispiel:**
```
Command: CMD1
[Prompt]: [Eingabe]
→ [Output]
```

### CMD2 - Beschreibung

Ausfuehrliche Beschreibung.

**Aufruf:**
```
Command: CMD2
```

**Beispiel:**
```
Command: CMD2
→ [Output]
```

## Konfiguration

### AppData-Ordner

```
%APPDATA%\AutoCAD\Lisp\ScriptName\
```

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\Lisp\ScriptName\Config\ScriptName.cfg
```

**Format:**
```
VERSION=1.0
SETTING1=value
SETTING2=value
```

## Log-Datei

### Speicherort

```
%APPDATA%\AutoCAD\Lisp\ScriptName\Log\ScriptName_YYYYMMDD_HHMMSS.log
```

Maximal 5 Session-Logs, aeltere werden automatisch geloescht.

### Log-Format

```
[2026-03-17 14:30:22] [INFO ] Script gestartet v1.0.0
[2026-03-17 14:30:25] [INFO ] Befehl CMD1 gestartet
[2026-03-17 14:30:30] [ERROR] Fehlermeldung
```

### Log-Level

| Level | Bedeutung |
|-------|-----------|
| INFO  | Normaler Ablauf |
| WARN  | Unerwartetes, nicht kritisch |
| ERROR | Fehler, Funktion abgebrochen |
| DEBUG | Detaillierte Infos (nur bei Debug-Modus) |

## Context-Namespace

Prefix: `MNS:` (MeinNameSpace)

### Wichtige Funktionen

| Funktion | Beschreibung |
|----------|--------------|
| MNS:ensure-init | Lazy-Init |
| MNS:log-write | Log-Eintrag schreiben |
| MNS:load-config | Config laden |

### Globale Variablen

| Variable | Beschreibung |
|----------|--------------|
| *MNS:version* | Script-Version |
| *MNS:initialized* | Init-Status |
| *MNS:debug-mode* | Debug ein/aus |

## Technische Details

- **AutoCAD Version:** 2024+
- **AutoLISP:** Erforderlich
- **AutoCAD LT:** Nicht kompatibel
- **Abhaengigkeiten:** BlockImport.lsp
- **AppData:** %APPDATA%\AutoCAD\Lisp\ScriptName\
- **Namespace:** MNS


================================================================================
ENDE - LISP README RULES v2.0
================================================================================
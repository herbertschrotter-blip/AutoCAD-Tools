# AutoLoadDimStyle

Automatisches Laden und Verwalten von Bemaßungsstilen für AutoCAD.
Vereinfacht die Arbeit mit Master-Dateien durch automatisches Laden beim Zeichnungsstart und ein interaktives Verwaltungsmenü.

---

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| DimStyleManager | Verwaltungsmenü für Master-Dateien (Laden/Öffnen/Hinzufügen/Entfernen) |
| AutoLoadDimStyles | Automatisches Laden beim Start (silent, wird beim Öffnen jeder Zeichnung ausgeführt) |

---

## Features

- ✅ Automatisches Laden beim Zeichnungsstart (silent, keine Unterbrechung)
- ✅ Mehrere Master-Dateien verwalten
- ✅ Interaktives Keyword-Menü (wie bei AutoCAD-Befehlen)
- ✅ First-Time Setup Dialog (beim allerersten Aufruf)
- ✅ Master-Dateien direkt zum Bearbeiten öffnen
- ✅ Persistente Konfiguration (wird automatisch gespeichert)
- ✅ Keine hardcoded Pfade

---

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausführen
2. `AutoLoadDimStyle.lsp` auswählen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufügen für automatisches Laden bei jedem AutoCAD-Start

### Support-Ordner (Alternative)

Kopieren nach:
```
%APPDATA%\Autodesk\AutoCAD 2024\R24.3\deu\Support\
```

AutoCAD neu starten.

---

## Verwendung

### DimStyleManager - Verwaltungsmenü

Interaktives Menü zur Verwaltung von Master-Dateien mit Bemaßungsstilen.

**Aufruf:**
```
Command: DimStyleManager
```

**Beim allerersten Aufruf:**
```
+===========================================================+
|  WILLKOMMEN BEI AUTOLOADDIMSTYLE                          |
+===========================================================+

Keine Konfiguration gefunden.
Bitte waehlen Sie Ihre erste Master-Datei mit Bemassungsstilen.

[Datei-Dialog öffnet sich]

OK Konfiguration erstellt: D:\...\Master_BemStile.dwg
Die Datei wird ab jetzt automatisch geladen.
```

**Menü-Optionen:**

Das Menü bietet Keyword-basierte Auswahl (wie bei AutoCAD-Befehlen):
```
+===========================================================+
|         BEMASSTIL-MANAGER                                 |
+===========================================================+

Konfigurierte Dateien: 1
  * Master_BemStile [OK]

Aktion [Laden/Oeffnen/Hinzufuegen/Entfernen/Pfade/Reset/Beenden] <Beenden>: _
```

**Eingabe:**
- Erster Buchstabe: `L` für Laden, `O` für Oeffnen, etc.
- Oder ganzes Wort: `Laden`, `Oeffnen`, etc.
- Tab-Completion funktioniert
- Enter = Beenden (Standard)

---

#### Laden

Lädt alle konfigurierten Bemaßungsstile in die aktuelle Zeichnung.

**Verwendung:**
```
Aktion: Laden

+===========================================================+
|  LADE BEMASSTILE                                          |
+===========================================================+
  -> Lade: Master_BemStile [OK]

OK 1 Datei(en) erfolgreich geladen

Bemassungsstile verfuegbar unter: BEMASSTIL (DIMSTYLE)
```

**Details:**
- Stile werden mittels INSERT-Befehl geladen (nur Definitionen, keine Geometrie)
- Verfügbar über AutoCAD-Befehl `BEMASSTIL` oder `DIMSTYLE`
- Mehrfaches Laden überschreibt bestehende Stile

---

#### Oeffnen

Öffnet eine Master-Datei zum Bearbeiten.

**Verwendung:**
```
Aktion: Oeffnen

+===========================================================+
|  MASTER-DATEI OEFFNEN                                     |
+===========================================================+

Verfuegbare Dateien:
  [1] Master_BemStile [OK]
  [2] Master_Architektur [OK]

Welche Datei oeffnen? (Nummer eingeben, Enter = Abbruch): 1

OK Oeffne: Master_BemStile
OK Datei geoeffnet und aktiviert
```

**Hinweis:** Das Menü beendet sich automatisch nach dem Öffnen, damit Sie in der geöffneten Datei arbeiten können.

---

#### Hinzufuegen

Fügt eine weitere Master-Datei zur Konfiguration hinzu.

**Verwendung:**
```
Aktion: Hinzufuegen

+===========================================================+
|  MASTER-DATEI HINZUFUEGEN                                 |
+===========================================================+

Aktuell konfiguriert:
  * Master_BemStile

[Datei-Dialog öffnet sich]

OK Hinzugefuegt: D:\Projekte\Master_Architektur.dwg
Die Datei wird beim naechsten Laden automatisch verwendet.
```

**Validierung:**
- Nur .DWG-Dateien werden akzeptiert
- Duplikate werden erkannt und abgelehnt

---

#### Entfernen

Entfernt eine Master-Datei aus der Konfiguration.

**Verwendung:**
```
Aktion: Entfernen

+===========================================================+
|  MASTER-DATEI ENTFERNEN                                   |
+===========================================================+

Konfigurierte Dateien:
  [1] Master_BemStile
  [2] Master_Architektur

Welche Datei entfernen? (Nummer eingeben, Enter = Abbruch): 2

OK Entfernt: Master_Architektur
```

---

#### Pfade

Zeigt alle konfigurierten Master-Dateien mit vollständigem Pfad und Status.

**Verwendung:**
```
Aktion: Pfade

+===========================================================+
|  KONFIGURIERTE PFADE                                      |
+===========================================================+

Master-Dateien:
  1. D:\OneDrive\...\Master_BemStile.dwg [OK]
  2. D:\Projekte\Master_Architektur.dwg [FEHLER - Nicht gefunden!]
```

**Status-Anzeigen:**
- `[OK]` - Datei existiert und ist erreichbar
- `[FEHLER]` - Datei nicht gefunden oder nicht zugänglich

---

#### Reset

Löscht alle gespeicherten Konfigurationen.

**Verwendung:**
```
Aktion: Reset

+===========================================================+
|  PFADE ZURUECKSETZEN                                      |
+===========================================================+

OK Alle gespeicherten Pfade wurden zurueckgesetzt.

Beim naechsten Aufruf werden Sie nach einer Master-Datei gefragt.
```

**Warnung:** Diese Aktion kann nicht rückgängig gemacht werden!

---

#### Beenden

Schließt das Menü und kehrt zur Zeichnung zurück.

---

### AutoLoadDimStyles - Automatisches Laden

Wird automatisch beim Öffnen jeder Zeichnung ausgeführt (via S::STARTUP).

**Verhalten:**

**Allererster Start (keine Config vorhanden):**
```
AutoCAD startet
→ AutoLoadDimStyles läuft
→ First-Time Setup Dialog öffnet sich
→ User wählt Master-Datei
→ Config wird gespeichert
→ Stile werden geladen
```

**Alle weiteren Starts:**
```
AutoCAD startet
→ AutoLoadDimStyles läuft
→ Lädt automatisch alle konfigurierten Master-Dateien
→ Komplett silent (keine Ausgaben, keine Dialoge)
→ Stile sind sofort verfügbar
```

**Details:**
- Komplett silent (keine Unterbrechung des Workflows)
- Keine Konsolenausgaben
- Funktioniert auch wenn DokaCAD oder andere Tools laden
- Bei fehlender Config (nach Reset): Lädt nichts, Dialog erscheint beim ersten manuellen `DimStyleManager` Aufruf

---

## Konfiguration

### Config-Datei

**Speicherort:**
```
%APPDATA%\AutoCAD\DimStyleConfig.txt
```

**Vollständiger Pfad (Beispiel):**
```
C:\Users\[Benutzername]\AppData\Roaming\AutoCAD\DimStyleConfig.txt
```

**Ordner öffnen:**
1. Windows + R drücken
2. `%APPDATA%\AutoCAD` eingeben
3. Enter drücken

**Format:**
```
2.7
D:\OneDrive\Dokumente\...\Master_BemStile.dwg
D:\Projekte\Master_Architektur.dwg
```

- **Erste Zeile:** Versions-Nummer (für zukünftige Kompatibilität)
- **Weitere Zeilen:** Vollständige Pfade zu Master-DWG-Dateien (einer pro Zeile)

**Tipp:** Verwenden Sie Forward-Slashes `/` auch unter Windows für bessere Kompatibilität.

---

## Technische Details

- **AutoCAD Version:** 2024 oder höher (getestet mit 2024 Deutsch)
- **AutoLISP Support:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet (für vl-filename-directory, vl-file-delete, vla-open, etc.)
- **AutoCAD LT:** ❌ Nicht kompatibel - AutoCAD LT unterstützt keine AutoLISP-Programme
- **Abhängigkeiten:** Keine externen Libraries

**AutoCAD LT Hinweis:**

AutoCAD LT 2024+ hat zwar begrenzte AutoLISP-Unterstützung, aber dieses Script verwendet Visual LISP Funktionen (vl-*, vla-*) die in AutoCAD LT nicht verfügbar sind. Das Script funktioniert nur in der Vollversion von AutoCAD.

---

## Changelog

### v2.7.1 (2026-02-13)
- First-Time Setup auch beim Autostart (wenn keine Config vorhanden)
- Garantiert Bemaßungsstile ab erstem AutoCAD-Start

### v2.7.0 (2026-02-13)
- Entfernung hardcoded Pfade
- First-Time Setup Dialog beim ersten Aufruf
- Keine Code-Änderungen für verschiedene User nötig

### v2.6.3 (2026-02-13)
- Datei-Aktivierung nach Öffnen (vla-activate)
- Menü beendet sich nach Datei-Öffnen

### v2.6.0 (2026-02-13)
- Interaktives Keyword-Menü statt einzelner Befehle
- Bessere User Experience

### v2.5.0 (2026-02-12)
- Performance-Optimierungen (O(n) statt O(n²))
- Memory Management verbessert

---

## Lizenz

MIT License - Frei verwendbar für private und kommerzielle Zwecke.
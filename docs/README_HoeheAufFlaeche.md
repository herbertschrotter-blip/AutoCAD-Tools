# HoeheAufFlaeche

Höheninterpolation auf Flächen für Vermessungsarbeiten in AutoCAD.
Berechnet Höhenkoten innerhalb oder außerhalb definierter Dreieck- oder Vierecksflächen mittels mathematischer Interpolation.

## Befehle

| Befehl | Beschreibung |
|--------|--------------|
| HoeheAufFlaeche (HAF) | Höheninterpolation auf 3-4 Eckpunkte mit Triangulation |
| ManageBlockImportHAF | Block-Verwaltung für Höhenkoten-Block |
| ShowBlockPath | Zeigt aktuell konfigurierten Block-Pfad |
| ResetBlockPath | Löscht gespeicherten Block-Pfad |

## Features

- ✅ **3-Punkt-Interpolation** - Ebenengleichung für planare Flächen
- ✅ **4-Punkt-Interpolation** - Triangulation in 2 Dreiecke mit baryzentrischen Koordinaten
- ✅ **Undo-Funktion** - [Z]urück während Eckpunkt-Eingabe, löscht auch bereits gesetzte Blöcke
- ✅ **XY-Skalierung** - [S]kalierung für Koordinaten-Transformation
- ✅ **Automatische Triangulation** - Erkennt automatisch ob Punkt in Dreieck 1 oder 2 liegt
- ✅ **Extrapolation** - Funktioniert auch außerhalb der definierten Fläche
- ✅ **Block nach vorne** - Höhenkoten erscheinen über anderen Objekten (DRAWORDER)
- ✅ **Persistente Konfiguration** - Block-Pfad und Skalierung werden gespeichert
- ✅ **Mindestens 2 Dezimalstellen** - Höhenwerte immer mit .00 Format

## Installation

### APPLOAD (Empfohlen)

1. Befehl `APPLOAD` in AutoCAD ausführen
2. `HoeheAufFlaeche.lsp` auswählen und laden
3. **Automatisches Laden:** Zu Startup Suite hinzufügen

### BlockImport.lsp Bibliothek

HoeheAufFlaeche benötigt die Bibliothek `lib/BlockImport.lsp`:

1. **Automatische Suche:** Script sucht in 3 Pfaden:
   - Gleiches Verzeichnis wie HoeheAufFlaeche.lsp
   - Unterordner `lib/`
   - AutoCAD Support-Pfade
2. **Manuelle Auswahl:** Falls nicht gefunden, erscheint Datei-Dialog
3. **Pfad wird gespeichert** für zukünftige Sitzungen

## Verwendung

### HoeheAufFlaeche (HAF) - Hauptbefehl

Berechnet interpolierte Höhen auf einer durch 3 oder 4 Eckpunkte definierten Fläche.

**Aufruf:**
```
Command: HAF
```

**Workflow:**

1. **Eckpunkt 1-3 setzen** (obligatorisch)
   - Punkt wählen mit Maus
   - Höhe eingeben
   - Bestätigung: "✓ Eckpunkt N gesetzt"

2. **Eckpunkt 4 setzen** (optional)
   - ENTER drücken = 3-Punkt-Modus
   - Punkt wählen = 4-Punkt-Modus

3. **Gesuchte Punkte setzen**
   - Beliebig viele Punkte wählen
   - Höhe wird automatisch berechnet und angezeigt
   - Block "BLK_Hoehenkote" wird eingefügt
   - ESC = Beenden

**Optionen während Eckpunkt-Eingabe:**

- `[S]kalierung` - Ändert XY-Skalierungsfaktor
- `[Z]urück` - Löscht letzten Eckpunkt (ab Punkt 2)

**Beispiel - 3 Punkte (Ebene):**
```
Command: HAF
Eckpunkt 1 wählen: [Klick]
Höhe Eckpunkt 1 eingeben: 100.00
✓ Eckpunkt 1 gesetzt

Eckpunkt 2 wählen: [Klick]
Höhe Eckpunkt 2 eingeben: 105.00
✓ Eckpunkt 2 gesetzt

Eckpunkt 3 wählen: [Klick]
Höhe Eckpunkt 3 eingeben: 102.00
✓ Eckpunkt 3 gesetzt

Eckpunkt 4 wählen (ENTER=Fertig): [ENTER]
✓ 3 Eckpunkte definiert
  Methode: Ebenengleichung

--- Gesuchte Punkte setzen (ESC = Ende) ---
Punkt wählen: [Klick]
→ Berechnete Höhe: 102.50 (Ebene)
✓ Block eingefügt
```

**Beispiel - 4 Punkte (Triangulation):**
```
Command: HAF
[... Eckpunkte 1-3 wie oben ...]

Eckpunkt 4 wählen: [Klick]
Höhe Eckpunkt 4 eingeben: 108.00
✓ Eckpunkt 4 gesetzt

✓ 4 Eckpunkte definiert
  Methode: Triangulation (2 Dreiecke)

--- Gesuchte Punkte setzen (ESC = Ende) ---
Punkt wählen: [Klick im Dreieck 1]
→ Berechnete Höhe: 103.25 (Dreieck 1)
✓ Block eingefügt

Punkt wählen: [Klick im Dreieck 2]
→ Berechnete Höhe: 106.80 (Dreieck 2)
✓ Block eingefügt
```

**Beispiel - Undo-Funktion:**
```
Eckpunkt 1 wählen: [Klick]
Höhe eingeben: 100.00
✓ Eckpunkt 1 gesetzt

Eckpunkt 2 wählen: [Klick - falscher Punkt!]
Höhe eingeben: 105.00
✓ Eckpunkt 2 gesetzt

Eckpunkt 3 wählen (oder [Z]urück): Z
→ Eckpunkt 2 wurde entfernt

Eckpunkt 2 wählen: [Klick - richtiger Punkt]
Höhe eingeben: 105.00
✓ Eckpunkt 2 gesetzt
```

**Beispiel - XY-Skalierung:**
```
Eckpunkt 1 wählen (oder [S]kalierung): S
Neue XY-Skalierung <1.0>: 0.5
✓ Skalierung gespeichert: 0.5

Eckpunkt 1 wählen: [Klick bei X=10, Y=20]
→ Wird als X=5, Y=10 gespeichert (mit Faktor 0.5)
```

### ManageBlockImportHAF - Block-Verwaltung

Interaktives Menü zur Verwaltung des Höhenkoten-Blocks.

**Aufruf:**
```
Command: ManageBlockImportHAF
```

**Optionen:**
- `Importieren` - Block aus Datei laden
- `Zeigen` - Aktuellen Pfad anzeigen
- `Zurücksetzen` - Gespeicherten Pfad löschen

### ShowBlockPath - Pfad anzeigen

Zeigt den aktuell konfigurierten Block-Pfad.

**Aufruf:**
```
Command: ShowBlockPath
```

**Beispiel:**
```
Command: ShowBlockPath
→ Aktueller Block-Pfad: C:/AutoCAD/Blocks/BLK_Hoehenkote.dwg
```

### ResetBlockPath - Pfad zurücksetzen

Löscht den gespeicherten Block-Pfad aus der Konfigurationsdatei.

**Aufruf:**
```
Command: ResetBlockPath
```

**Beispiel:**
```
Command: ResetBlockPath
→ Block-Pfad wurde zurückgesetzt
  Beim nächsten Aufruf wird nach dem Block gefragt
```

## Konfiguration

### Config-Dateien

HoeheAufFlaeche verwendet 2 Konfigurationsdateien:

#### 1. Block-Pfad Konfiguration

**Speicherort:**
```
%APPDATA%/AutoCAD/HoeheAufFlaecheConfig.txt
```

**Format:**
```
1.0
C:/Pfad/zum/Block/BLK_Hoehenkote.dwg
```

**Erste Zeile:** Version (immer "1.0")  
**Zweite Zeile:** Vollständiger Pfad zur Block-Datei

#### 2. XY-Skalierung Konfiguration

**Speicherort:**
```
%APPDATA%/AutoCAD/HoeheAufFlaecheScale.txt
```

**Format:**
```
1.0
0.500000
```

**Erste Zeile:** Version (immer "1.0")  
**Zweite Zeile:** Skalierungsfaktor (6 Dezimalstellen)

### Block-Anforderungen

Der Höhenkoten-Block muss folgende Eigenschaften haben:

- **Block-Name:** `BLK_Hoehenkote`
- **Attribut-Tag:** `HOEHE` (für Höhenwert)
- **Format:** Höhenwert wird mit Vorzeichen eingefügt (+2.00, -1.50, ±0.00)
- **Einfügepunkt:** Wird an gewählter Position eingefügt
- **Z-Koordinate:** Wird automatisch auf berechnete Höhe gesetzt

## Mathematische Grundlagen

### 3-Punkt-Interpolation (Ebenengleichung)

Für 3 Eckpunkte wird eine Ebene durch die Gleichung **ax + by + cz = d** definiert.

**Methode:**
1. Berechne Normalenvektor durch Kreuzprodukt
2. Bestimme Ebenenkoeffizienten a, b, c
3. Löse nach z auf: z = (d - ax - by) / c

**Vorteil:** Exakte Lösung für planare Flächen

### 4-Punkt-Interpolation (Triangulation)

Für 4 Eckpunkte wird die Fläche in 2 Dreiecke unterteilt:
- **Dreieck 1:** Punkte 1-2-3
- **Dreieck 2:** Punkte 1-3-4

**Methode:**
1. Teste in welchem Dreieck der gesuchte Punkt liegt
2. Berechne baryzentrische Koordinaten (u, v, w)
3. Interpoliere Höhe: h = u·h₁ + v·h₃ + w·h₂

**Baryzentrische Koordinaten:**
- Beschreiben Position innerhalb eines Dreiecks
- u + v + w = 1.0
- Ermöglichen präzise Interpolation
- Funktionieren auch außerhalb (Extrapolation)

**Korrekte Zuordnung (wichtig!):**
```lisp
;; Vektoren: v0=p3-p1, v1=p2-p1
;; Daraus folgt:
u → Gewicht für p1/h1
v → Gewicht für p3/h3  (nicht p2!)
w → Gewicht für p2/h2  (nicht p3!)

;; Höhe = u·h1 + w·h2 + v·h3
```

### XY-Skalierung

Alle X- und Y-Koordinaten werden mit dem Skalierungsfaktor multipliziert:

```
X_intern = X_geklickt × Skalierung
Y_intern = Y_geklickt × Skalierung
Z_intern = Höhe (unverändert)
```

**Anwendung:** Transformation zwischen verschiedenen Koordinatensystemen

## Technische Details

- **AutoCAD Version:** 2024+ (getestet mit 2024 Deutsch)
- **AutoLISP:** Erforderlich
- **Visual LISP:** vl-load-com wird verwendet
- **AutoCAD LT:** ❌ Nicht kompatibel (kein AutoLISP Support)
- **Abhängigkeiten:** 
  - lib/BlockImport.lsp (mitgeliefert, wird automatisch gesucht)
  - Block "BLK_Hoehenkote" (muss vom Benutzer bereitgestellt werden)
- **Koordinatensystem:** Arbeitet in 2D (XY), Z-Werte für Höhe
- **Genauigkeit:** Mindestens 2 Dezimalstellen (z.B. 2.00 statt 2)
- **Fehlerbehandlung:** Lokaler Error-Handler stellt Systemvariablen wieder her

## Fehlerbehandlung

Das Script behandelt folgende Fehler:

- **Block nicht gefunden:** Automatische Suche und Datei-Dialog
- **Punkte kollinear:** Warnung wenn keine gültige Ebene möglich
- **ESC während Eingabe:** Sauberes Beenden, Systemvariablen wiederhergestellt
- **Ungültige Eingaben:** Wiederholte Eingabe-Aufforderung
- **Config-Dateien:** Werden erstellt falls nicht vorhanden

## Workflow-Hinweise

**Best Practice für Vermessungsarbeiten:**

1. **Eckpunkte wählen:**
   - Wähle Fixpunkte mit bekannten Höhen
   - Bei 4 Punkten: Möglichst gleichmäßige Verteilung
   - Vermeide sehr spitze Dreiecke

2. **Kontrolle:**
   - Prüfe berechnete Höhen auf Plausibilität
   - Bei 4 Punkten wird angezeigt in welchem Dreieck der Punkt liegt
   - Nutze [Z]urück bei falscher Eingabe

3. **Skalierung:**
   - Setze XY-Skalierung vor dem ersten Punkt
   - Wird gespeichert für folgende Sessions
   - Kann jederzeit mit [S] geändert werden

## Versionsverlauf

**v1.5.3** (2026-02-19)
- Fix: Mindestens 2 Dezimalstellen erzwingen (2.00 statt 2)

**v1.5.2** (2026-02-19)
- Fix: Baryzentrische Koordinaten korrekt zugeordnet (u→h1, w→h2, v→h3)

**v1.5.1** (2026-02-19)
- Fix: DRAWORDER nach Block-Insert (Blocks erscheinen vorne)

**v1.5.0** (2026-02-19)
- Refactor: Temporäre Visualisierung entfernt

**v1.1.0** (2026-02-19)
- Feature: [Z]urück Funktion während Eckpunkt-Eingabe
- Feature: Löscht auch bereits gesetzte Blöcke bei Undo

**v1.0.0** (2026-02-19)
- Initial Release
- 3-Punkt-Interpolation (Ebenengleichung)
- 4-Punkt-Interpolation (Triangulation)
- XY-Skalierung
- BlockImport.lsp Integration
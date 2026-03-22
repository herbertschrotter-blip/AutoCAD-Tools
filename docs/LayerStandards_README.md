# Layer-Standards — AutoCAD-Tools Vermessung

Verbindliche Layer-Namenskonventionen fuer alle Vermessungs-Scripts im AutoCAD-Tools Projekt.
Angelehnt an ÖNORM A 6241-1 / ISO 13567 (2-Buchstaben Fachbereichs-Codes).

## Allgemeines Schema

```
VM_<Gruppe>_<Gruppenname>
```

| Bestandteil | Laenge | Beschreibung | Beispiel |
|---|---|---|---|
| `VM` | 2 Zeichen | Fachbereich: Vermessung (fix) | `VM` |
| `<Gruppe>` | 2 Zeichen | Gegenstandsgruppe (konfigurierbar) | `HP` |
| `<Gruppenname>` | frei | SETBLOCKZ-Gruppenname | `STAB137` |

### ÖNORM-Bezug

| ÖNORM-Feld | Position | Unser Wert | Bedeutung |
|---|---|---|---|
| Verantwortliche Stelle | 1-2 | `VM` | Vermessung |
| Gegenstand-Gruppe | 3-4 | `HP` | Hoehenpunkt |
| Benutzerfeld | ab 21 | Gruppenname | Frei waehlbar |

Die ÖNORM A 6241-1 definiert keinen Fachbereich fuer Vermessung/Gelaendeaufnahme.
`VM` ist eine projektspezifische Erweiterung im Stil der bestehenden Codes
(AR=Architektur, TR=Tragwerk, BS=Brandschutz, GS=Sanitaer, etc.).

### Vordefinierte Gegenstandsgruppen

| Code | Bedeutung | Einsatz |
|---|---|---|
| `HP` | Hoehenpunkt | Standard fuer Vermessungs-Hoehenkoten (SetBlockZ) |
| `GP` | Grenzpunkt | Grenzpunkte (Kataster) |
| `GE` | Gelaende | Gelaendepunkte allgemein |
| `FP` | Festpunkt | Geodaetische Festpunkte |

Die Gruppe ist im Settings-Dialog konfigurierbar (Standard: `HP`).

## Block-Symbol Layer

```
VM_HP_STAB137
VM_HP_Grenzpunkte
VM_HP_Baufeld_Nord
```

## Attribut-Sub-Layer

Jedes Attribut des Kopie-Blocks liegt auf einem eigenen Sub-Layer.
Das ermoeglicht gezielte Sichtbarkeit ueber Freeze/Thaw.

| Sub-Layer | Inhalt | Beispiel |
|---|---|---|
| `<Basis>-AttABS` | Absolute Hoehe (z.B. "320.71 m ue. A.") | `VM_HP_STAB137-AttABS` |
| `<Basis>-AttREL` | Relative Hoehe (z.B. "+0.02") | `VM_HP_STAB137-AttREL` |
| `<Basis>-AttBAU0` | Bau-0-Bezug (z.B. "±0.00 = 320.69") | `VM_HP_STAB137-AttBAU0` |

## Vollstaendiges Beispiel

Gruppe "STAB137" mit Gegenstandsgruppe "HP":

```
VM_HP_STAB137              ← Block-Symbol (Vermessungspunkt-Marker)
VM_HP_STAB137-AttABS       ← Attribut: Absolute Hoehe
VM_HP_STAB137-AttREL       ← Attribut: Relative Hoehe (nach Bau-0)
VM_HP_STAB137-AttBAU0      ← Attribut: Bau-0-Referenz
```

## Mehrere Gruppen in einer Zeichnung

```
VM_HP_STAB137              ← Gruppe 1: Stabpunkte
VM_HP_STAB137-AttABS
VM_HP_STAB137-AttREL
VM_HP_STAB137-AttBAU0

VM_HP_Grenzpunkte          ← Gruppe 2: Grenzpunkte
VM_HP_Grenzpunkte-AttABS
VM_HP_Grenzpunkte-AttREL
VM_HP_Grenzpunkte-AttBAU0

VM_HP_Baufeld_Nord         ← Gruppe 3: Baufeld Nord
VM_HP_Baufeld_Nord-AttABS
VM_HP_Baufeld_Nord-AttREL
VM_HP_Baufeld_Nord-AttBAU0
```

## Block-Definitionen

Jede Gruppe hat eine eigene Block-Definition:

```
<BasisBlockname>_<Gruppenname>
```

**Beispiele:**
```
VM_Hoehe_STAB137
VM_Hoehe_Grenzpunkte
VM_Hoehe_Baufeld_Nord
```

## Freeze/Thaw Steuerung

| Layer | Standard | Beschreibung |
|---|---|---|
| `*-AttABS` | Thawed (sichtbar) | Absolute Hoehe immer sichtbar |
| `*-AttREL` | Thawed (sichtbar) | Relative Hoehe immer sichtbar |
| `*-AttBAU0` | Frozen (unsichtbar) | Bau-0-Referenz standardmaessig ausgeblendet |

Die Freeze-Einstellungen sind pro Gruppe im Settings-Dialog konfigurierbar.

## Farb-Steuerung

| Element | Standard | Steuerung |
|---|---|---|
| Block-Symbol | 7 - Weiss | ACI-Code im Settings-Dialog (Block-Box) |
| Attribut ABS | Von Block (0) | ACI-Code im Settings-Dialog (Attribut-Box) |
| Attribut REL | Von Block (0) | ACI-Code im Settings-Dialog (Attribut-Box) |
| Attribut BAU0 | Von Block (0) | ACI-Code im Settings-Dialog (Attribut-Box) |

"Von Block" (ACI 0) bedeutet: Das Attribut erbt die Farbe des Block-Symbols.

## Layer-Cleanup

Beim Loeschen einer Gruppe (SBZSETTINGS → Loeschen) werden alle zugehoerigen Layer
automatisch aufgeraeumt — aber nur wenn sie leer sind (keine Entities darauf).

## Zuordnung Block → Gruppe

Jeder Kopie-Block traegt XData mit:

| DXF Code | Inhalt | Beispiel |
|---|---|---|
| 1000 | Gruppenname | "STAB137" |
| 1005 | Quell-Block Handle | "2A3F" |

Ein Quell-Block kann in mehreren Gruppen sein. Jede Gruppe erzeugt einen eigenen
Kopie-Block mit eigenem Handle-Verweis auf den Quell-Block.

## Verwandte Dokumente

- `docs/SetBlockZ_README.md` — SetBlockZ Befehlsreferenz
- `AutoLISP_BEST_PRACTICES.txt` — Coding Standards
- ÖNORM A 6241-1:2015 / ÖNORM A 6141-1:2025 — CAD-Datenstrukturen
- ISO 13567-1/2 — Gliederung und Benennung von Layern fuer CAD

## Technische Details

- **Erstellt von:** SetBlockZ.lsp (SETBLOCKZ Befehl)
- **Verwaltet in:** SBZSETTINGS Dialog
- **Gespeichert in:** DWG (XRecords im Named Object Dictionary)
- **Fachbereich:** `VM` (Vermessung, fix)
- **Gegenstandsgruppe:** konfigurierbar (Standard: `HP`)
- **Trennzeichen:** `_` zwischen Bestandteilen, `-` vor Attribut-Suffix
- **ÖNORM-Referenz:** Angelehnt an A 6241-1 Anhang B (Layergliederung)
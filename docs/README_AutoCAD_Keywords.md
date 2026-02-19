# AutoCAD Keywords & Rechtsklick-Menüs

Technische Dokumentation für interaktive Keyword-Menüs in AutoLISP.

## Übersicht

AutoCAD zeigt automatisch ein Rechtsklick-Menü wenn `getkword` mit korrekt formatierten Keywords verwendet wird. Diese Dokumentation beschreibt die exakten Regeln für funktionierende Rechtsklick-Menüs.

## Die Drei Kritischen Regeln

### 1. Keywords in Eckigen Klammern

AutoCAD liest die Keywords aus den **eckigen Klammern** im Prompt-String.

```lisp
(getkword "\nOption [Liste/Standard/Hinzufuegen/Abbrechen]: ")
                   ^--- Rechtsklick-Menü zeigt diese! ---^
```

**Ohne eckige Klammern:**
```lisp
(getkword "\nOption: ")  ; ❌ Kein Rechtsklick-Menü!
```

### 2. Erster Buchstabe GROẞGESCHRIEBEN

Der **erste Buchstabe** jedes Keywords MUSS großgeschrieben sein.

```lisp
✅ [Liste/Standard/Hinzufuegen]  → Rechtsklick-Menü erscheint
❌ [liste/standard/hinzufuegen]  → Kein Menü!
```

**Warum:** AutoCAD nutzt Großbuchstaben zur Menü-Erkennung.

### 3. initget mit EXAKT denselben Wörtern

Die Keywords in `initget` müssen **exakt** mit denen in den eckigen Klammern übereinstimmen.

```lisp
(initget "Liste Standard Hinzufuegen Abbrechen")
(getkword "\nOption [Liste/Standard/Hinzufuegen/Abbrechen]: ")
         //       ^-------- Muss identisch sein! --------^
```

**Bei Unterschied:**
```lisp
(initget "L S H A")  ; ❌ Nicht identisch mit Prompt!
(getkword "\nOption [Liste/Standard/Hinzufuegen/Abbrechen]: ")
; → Fehler oder unerwartetes Verhalten
```

## Vollständiges Beispiel

```lisp
;;; Block-Verwaltungs-Menü mit Rechtsklick
(defun manage-blocks ( / option continue)
  (setq continue T)
  
  (while continue
    ;; Menü anzeigen
    (princ "\n========================================")
    (princ "\n     BLOCK MANAGER")
    (princ "\n========================================")
    (princ "\n")
    (princ "\n[L]iste      - Alle Blocks anzeigen")
    (princ "\n[S]tandard   - Standard-Block wählen")
    (princ "\n[H]inzufügen - Neuen Block hinzufügen")
    (princ "\n[E]ntfernen  - Block löschen")
    (princ "\n[A]bbrechen  - Beenden")
    (princ "\n")
    
    ;; Keywords definieren (WICHTIG: Erste Buchstaben groß!)
    (initget "Liste Standard Hinzufuegen Entfernen Abbrechen")
    
    ;; Prompt mit eckigen Klammern (WICHTIG: Identisch mit initget!)
    (setq option (getkword "\nOption [Liste/Standard/Hinzufuegen/Entfernen/Abbrechen]: "))
    
    ;; Optionen verarbeiten
    (cond
      ((eq option "Liste")
       (princ "\n=== Blocks auflisten ===")
       (list-all-blocks))
      
      ((eq option "Standard")
       (princ "\n=== Standard-Block wählen ===")
       (select-standard-block))
      
      ((eq option "Hinzufuegen")
       (princ "\n=== Neuen Block hinzufügen ===")
       (add-new-block))
      
      ((eq option "Entfernen")
       (princ "\n=== Block entfernen ===")
       (remove-block))
      
      ((eq option "Abbrechen")
       (setq continue nil))
      
      ;; ESC oder ungültige Eingabe
      ((null option)
       (setq continue nil))
    )
  )
  
  (princ)
)
```

## User-Interaktion

### Rechtsklick-Menü

Wenn alle Regeln befolgt sind:

1. **User macht Rechtsklick** → AutoCAD zeigt Menü:
```
Liste
Standard
Hinzufuegen
Entfernen
Abbrechen
```

2. **User klickt auf "Hinzufuegen"** → `option` wird `"Hinzufuegen"`

3. **User tippt "H"** → AutoCAD matcht automatisch zu `"Hinzufuegen"`

### Tasten-Abkürzungen

AutoCAD matcht automatisch auf Basis des ersten Buchstabens:

- **L** → Liste
- **S** → Standard
- **H** → Hinzufuegen
- **E** → Entfernen
- **A** → Abbrechen

**Bei Mehrdeutigkeit:** AutoCAD zeigt Auswahlmöglichkeiten.

### ESC-Verhalten

```lisp
(setq option (getkword "..."))
; User drückt ESC → option wird nil
```

Immer prüfen:
```lisp
(if (null option)
  (princ "\nAbgebrochen")
)
```

## Häufige Fehler & Lösungen

### Fehler 1: Kein Rechtsklick-Menü erscheint

**Ursache:** Kleinbuchstaben oder keine eckigen Klammern

```lisp
❌ (getkword "\nOption [liste/standard]: ")  ; Kleinbuchstaben
❌ (getkword "\nOption: ")                    ; Keine Klammern
```

**Lösung:**
```lisp
✅ (getkword "\nOption [Liste/Standard]: ")  ; Großbuchstaben + Klammern
```

### Fehler 2: Keywords werden nicht erkannt

**Ursache:** Unterschied zwischen `initget` und Prompt

```lisp
❌ (initget "L S H")
   (getkword "\nOption [Liste/Standard/Hinzufuegen]: ")
   ; → Keywords stimmen nicht überein!
```

**Lösung:**
```lisp
✅ (initget "Liste Standard Hinzufuegen")
   (getkword "\nOption [Liste/Standard/Hinzufuegen]: ")
   ; → Exakt identisch!
```

### Fehler 3: Umlaute problematisch

**Problem:** ä, ö, ü können zu Encoding-Problemen führen

```lisp
⚠️ (initget "Ändern Löschen")  ; Kann Probleme machen
```

**Lösung:** Umlaute umschreiben

```lisp
✅ (initget "Aendern Loeschen")
   (getkword "\nOption [Aendern/Loeschen]: ")
```

### Fehler 4: Leerzeichen in Keywords

**Problem:** Keywords mit Leerzeichen

```lisp
❌ (initget "Block Hinzufügen")  ; Leerzeichen!
   ; → AutoCAD interpretiert als zwei separate Keywords
```

**Lösung:** Ohne Leerzeichen

```lisp
✅ (initget "BlockHinzufuegen")
   (getkword "\nOption [BlockHinzufuegen]: ")
```

## Best Practices

### 1. Konsistente Namenskonvention

```lisp
; Gut: Verb-basiert
[Hinzufuegen/Entfernen/Aendern/Abbrechen]

; Gut: Nomen-basiert
[Liste/Auswahl/Einstellungen/Beenden]

; Schlecht: Gemischt
[Liste/Hinzufuegen/Auswahl/Beenden]  ; Gemischte Typen
```

### 2. Eindeutige Anfangsbuchstaben

```lisp
✅ [Liste/Standard/Hinzufuegen/Entfernen/Abbrechen]
   ; L, S, H, E, A - alle unterschiedlich

❌ [Liste/Laden/Loeschen/Abbrechen]
   ; L, L, L - mehrdeutig!
```

### 3. Maximal 5-7 Optionen

```lisp
✅ 5 Optionen: Übersichtlich
⚠️ 10+ Optionen: Zu viele, schwer zu überblicken
```

**Bei vielen Optionen:** Untermenüs verwenden.

### 4. "Abbrechen" immer als letzte Option

```lisp
✅ [Liste/Standard/Hinzufuegen/Entfernen/Abbrechen]
                                            ^-- Am Ende

❌ [Abbrechen/Liste/Standard/Hinzufuegen]
    ^-- Am Anfang (unüblich)
```

### 5. Klare Beschreibungen im Menü-Text

```lisp
✅ (princ "\n[L]iste      - Alle Blocks anzeigen")
   (princ "\n[H]inzufuegen - Neuen Block hinzufügen")
   ; → Klar was passiert

❌ (princ "\n[L]iste")
   (princ "\n[H]inzufuegen")
   ; → Unklar was passiert
```

## Testing-Checkliste

Bei jedem Keyword-Menü testen:

- [ ] Rechtsklick zeigt Menü
- [ ] Alle Keywords erscheinen im Menü
- [ ] Klick auf Keyword funktioniert
- [ ] Tasten-Abkürzungen funktionieren (L, S, H, etc.)
- [ ] ESC bricht ab (option wird nil)
- [ ] ENTER ohne Eingabe verhält sich korrekt
- [ ] Mehrdeutige Anfangsbuchstaben werden erkannt

## Beispiel-Scripts

### Einfaches Ja/Nein-Menü

```lisp
(defun confirm-action (message / choice)
  (princ (strcat "\n" message))
  (initget "Ja Nein")
  (setq choice (getkword "\n[Ja/Nein]: "))
  (eq choice "Ja")  ; Gibt T bei Ja, nil bei Nein/ESC zurück
)

;; Verwendung:
(if (confirm-action "Wirklich löschen?")
  (princ "\nGelöscht!")
  (princ "\nAbgebrochen.")
)
```

### Auswahl mit Default

```lisp
(defun get-option-with-default (default / option)
  (initget "Option1 Option2 Option3")
  (setq option (getkword 
    (strcat "\nWählen Sie [Option1/Option2/Option3] <" default ">: ")))
  
  ;; Wenn ENTER: Verwende Default
  (if (null option)
    default
    option
  )
)

;; Verwendung:
(setq selected (get-option-with-default "Option1"))
```

### Menü mit Schleife bis gültige Eingabe

```lisp
(defun get-valid-option ( / option valid)
  (setq valid nil)
  
  (while (not valid)
    (initget "Option1 Option2 Option3")
    (setq option (getkword "\nWählen [Option1/Option2/Option3]: "))
    
    (if option
      (setq valid T)
      (princ "\n*** Bitte eine Option wählen oder ESC zum Abbrechen ***")
    )
  )
  
  option
)
```

## Referenz

### AutoCAD-Version

Diese Regeln gelten für:
- AutoCAD 2024
- AutoCAD 2023
- AutoCAD 2022
- Ältere Versionen (getestet bis 2018)

### Verwandte Funktionen

- `initget` - Definiert erlaubte Keywords
- `getkword` - Holt Keyword vom User
- `getint` - Integer mit Keywords
- `getreal` - Real mit Keywords
- `getdist` - Distance mit Keywords

### Weitere Ressourcen

- Autodesk Developer's Guide: initget/getkword
- Lee Mac Programming: User Input Tutorials
- AfraLISP: Interactive Commands

---

**Version:** 1.0  
**Datum:** 2026-02-19  
**Autor:** Herbert Schrotter

**Verwendet in:**
- BlockImport.lsp (ManageBlockImport)
- SetHoehenkote.lsp (getEinfügepunktMitScale)

;;; SetHoehenkote.lsp
;;; Automatisches Setzen von Höhenkoten-Blöcken in AutoCAD
;;; Speziell für Leica-Vermessungsarbeiten
;;;
;;; Installation:
;;; 1. Diese Datei in den AutoCAD Support-Ordner kopieren
;;; 2. lib/BlockImport.lsp muss ebenfalls im Support-Ordner sein
;;; 3. AutoCAD neu starten oder mit (load "SetHoehenkote.lsp") laden
;;;
;;; Verwendung:
;;; - Befehl: SetHK
;;; - Punkt wählen, Höhe eingeben
;;; - Block wird automatisch mit Attributen eingefügt
;;;
;;; Version: 1.3.2
;;; Datum: 2026-02-13
;;; Autor: Herbert Schrotter

;;; ============================================================================
;;; BIBLIOTHEKEN LADEN
;;; ============================================================================

;; Config-Datei für BlockImport.lsp Pfad
(setq *sethk-config-file* (strcat (getenv "APPDATA") "/AutoCAD/SetHoehenkoteConfig.txt"))

;;; Liest gespeicherten BlockImport.lsp Pfad aus Config
(defun read-blockimport-path ( / file path version)
  (setq path nil)
  
  ;; Prüfe ob Config-Datei existiert
  (if (not (findfile *sethk-config-file*))
    nil  ;; Datei existiert nicht
    ;; Versuche Datei zu öffnen mit Error-Handling
    (if (vl-catch-all-error-p
          (setq file (vl-catch-all-apply 'open (list *sethk-config-file* "r"))))
      (progn
        (princ (strcat "\n*** Fehler beim Öffnen der Config-Datei: " *sethk-config-file* " ***"))
        nil
      )
      (progn
        ;; Erste Zeile: Version
        (setq version (read-line file))
        ;; Zweite Zeile: Pfad
        (setq path (read-line file))
        (close file)
        path
      )
    )
  )
)

;;; Speichert BlockImport.lsp Pfad in Config
(defun save-blockimport-path (filepath / file dir)
  ;; Erstelle Verzeichnis falls nicht vorhanden
  (setq dir (vl-filename-directory *sethk-config-file*))
  (if (not (vl-file-directory-p dir))
    (if (vl-catch-all-error-p (vl-catch-all-apply 'vl-mkdir (list dir)))
      (progn
        (princ (strcat "\n*** Fehler beim Erstellen des Config-Verzeichnis: " dir " ***"))
        nil
      )
      ;; Verzeichnis erfolgreich erstellt
      T
    )
  )
  
  ;; Speichere Pfad mit Error-Handling
  (if (vl-catch-all-error-p
        (setq file (vl-catch-all-apply 'open (list *sethk-config-file* "w"))))
    (progn
      (princ (strcat "\n*** Fehler beim Schreiben der Config-Datei: " *sethk-config-file* " ***"))
      nil
    )
    (progn
      (write-line "1.0" file)
      (write-line filepath file)
      (close file)
      T
    )
  )
)

;; Lade gemeinsame Block-Import Bibliothek
;; Intelligente Pfad-Suche mit mehreren Fallbacks

(setq default-start-dir nil)  ;; Lokale Variable für File-Dialog

;; Versuche gespeicherten Pfad zu laden
(setq *blockimport-lib-path* (read-blockimport-path))

;; Wenn gespeicherter Pfad existiert, prüfe ob Datei noch da ist
(if (and *blockimport-lib-path* (not (findfile *blockimport-lib-path*)))
  (setq *blockimport-lib-path* nil)  ;; Pfad ungültig
)

;; Wenn kein gültiger Pfad: Suche in Standard-Orten
(if (null *blockimport-lib-path*)
  (setq *blockimport-lib-path*
    (cond
      ;; 1. Versuch: lib/ Unterordner im Support-Ordner
      ((findfile "lib/BlockImport.lsp"))
      
      ;; 2. Versuch: Direkt im Support-Ordner
      ((findfile "BlockImport.lsp"))
    )
  )
)

;; Wenn immer noch nicht gefunden: Bitte User um Auswahl
(if (null *blockimport-lib-path*)
  (progn
    (princ "\n*** BlockImport.lsp wird nicht im Support-Pfad gefunden ***")
    (princ "\nBitte wählen Sie die Datei lib/BlockImport.lsp aus...")
    
    ;; Bestimme sinnvollen Start-Ordner
    (setq default-start-dir
      (cond
        ;; 1. Zeichnungs-Verzeichnis
        ((getvar "DWGPREFIX"))
        
        ;; 2. Benutzer-Dokumente
        ((getenv "USERPROFILE"))
        
        ;; 3. Fallback: Leer
        (T "")
      )
    )
    
    ;; Öffne File-Dialog
    (if (setq *blockimport-lib-path* 
          (getfiled "BlockImport.lsp auswählen" 
                    default-start-dir
                    "lsp" 
                    0))
      (progn
        (princ (strcat "\nGewählte Datei: " *blockimport-lib-path*))
        ;; Speichere Pfad für nächstes Mal
        (save-blockimport-path *blockimport-lib-path*)
        (princ "\nPfad wurde gespeichert für zukünftige Sitzungen.")
      )
      (progn
        (alert "FEHLER: Keine Datei ausgewählt!")
        (exit)
      )
    )
  )
)

;; Lade Bibliothek
(if *blockimport-lib-path*
  (progn
    (load *blockimport-lib-path*)
    (princ (strcat "\n  Bibliothek geladen: " *blockimport-lib-path*))
  )
)

;;; ============================================================================
;;; KONFIGURATION
;;; ============================================================================

;; Name des Höhenkoten-Blocks
(setq *hoehenkote-blockname* "BLK_Hoehenkote")

;; Config-Datei für XY-Skalierung
(setq *scale-config-file* (strcat (getenv "APPDATA") "/AutoCAD/SetHoehenkoteScale.txt"))

;;; Liest gespeicherte XY-Skalierung aus Config
(defun read-scale-config ( / file scale version)
  (setq scale nil)
  
  (if (not (findfile *scale-config-file*))
    nil
    (if (vl-catch-all-error-p
          (setq file (vl-catch-all-apply 'open (list *scale-config-file* "r"))))
      nil
      (progn
        (setq version (read-line file))
        (setq scale (read-line file))
        (close file)
        (if scale
          (atof scale)
          nil
        )
      )
    )
  )
)

;;; Speichert XY-Skalierung in Config
(defun save-scale-config (scale-value / file dir)
  (setq dir (vl-filename-directory *scale-config-file*))
  (if (not (vl-file-directory-p dir))
    (vl-catch-all-apply 'vl-mkdir (list dir))
  )
  
  (if (vl-catch-all-error-p
        (setq file (vl-catch-all-apply 'open (list *scale-config-file* "w"))))
    nil
    (progn
      (write-line "1.0" file)
      (write-line (rtos scale-value 2 6) file)
      (close file)
      T
    )
  )
)

;;; ============================================================================
;;; GLOBALE VARIABLEN
;;; ============================================================================

;; Speichert die zuletzt eingegebene Höhe
(setq g_lastHeight nil)

;;; ============================================================================
;;; HILFSFUNKTIONEN - FORMATIERUNG
;;; ============================================================================

;;; Formatiert Höhenwert für Anzeige (3 Dezimalstellen)
(defun format-height (heightValue)
  (rtos heightValue 2 3)
)

;;; Konvertiert Höhe in String mit exakt 3 Dezimalstellen
(defun ensure-three-decimals (heightValue / heightStr decimalPos decimals)
  (setq heightStr (rtos heightValue 2 3))
  
  ;; Überprüfen, ob der Wert eine Dezimalstelle hat
  (if (not (vl-string-search "." heightStr))
    (setq heightStr (strcat heightStr ".000"))
    (progn
      ;; Wenn der Wert eine Dezimalstelle enthält, sicherstellen, dass drei Dezimalstellen vorhanden sind
      (setq decimalPos (vl-string-search "." heightStr))
      (setq decimals (substr heightStr (+ decimalPos 2)))
      (while (< (strlen decimals) 3)
        (setq decimals (strcat decimals "0"))
      )
      (setq heightStr (strcat (substr heightStr 1 (+ decimalPos 1)) decimals))
    )
  )
  heightStr
)

;;; Formatiert Höhenwert mit Vorzeichen (+ oder %%p für ±0)
(defun format-height-value (heightValue / formattedHeight)
  (setq formattedHeight (ensure-three-decimals heightValue))
  (cond
    ((= heightValue 0.0) (setq formattedHeight (strcat "%%p" formattedHeight)))
    ((> heightValue 0.0) (setq formattedHeight (strcat "+" formattedHeight)))
  )
  formattedHeight
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - BENUTZEREINGABEN MIT FEHLERBEHANDLUNG
;;; ============================================================================

;;; Fragt Benutzer nach Einfügepunkt mit ESC-Behandlung
(defun getEinfügepunkt ( / pt)
  (setq pt (getpoint "\nWählen Sie einen Punkt zum Einfügen des Blocks: "))
  (if (null pt)
    (progn
      (princ "\n*** Abbruch: Kein Punkt gewählt ***")
      nil
    )
    pt
  )
)

;;; Fragt Benutzer nach Einfügepunkt mit Keyword für Skalierung
;;; Rückgabe: Liste (punkt scale) oder nil bei Abbruch
(defun getEinfügepunktMitScale ( / pt scale current-scale)
  ;; Aktuelle Skalierung aus Config lesen
  (setq current-scale (read-scale-config))
  
  ;; Wenn keine Skalierung gespeichert: Zuerst fragen
  (if (null current-scale)
    (progn
      (princ "\n*** Keine Skalierung konfiguriert ***")
      (setq scale (getScale))
    )
    (setq scale current-scale)
  )
  
  ;; Punkt mit Keyword-Option abfragen
  (initget "Skalierung")
  (setq pt (getpoint (strcat "\nPunkt wählen (oder [S]kalierung <" (rtos scale 2 2) ">): ")))
  
  ;; Prüfe ob Keyword "Skalierung" gewählt wurde
  (while (= pt "Skalierung")
    ;; Skalierung ändern
    (setq scale (getScale))
    
    ;; Nochmal Punkt abfragen
    (initget "Skalierung")
    (setq pt (getpoint (strcat "\nPunkt wählen (oder [S]kalierung <" (rtos scale 2 2) ">): ")))
  )
  
  ;; Wenn pt = nil (ESC) → Abbruch
  (if (null pt)
    (progn
      (princ "\n*** Abbruch: Kein Punkt gewählt ***")
      nil
    )
    (list pt scale)  ;; Rückgabe: (punkt scale)
  )
)

;;; Fragt Benutzer nach Höhe mit Wiederholung bei fehlender Eingabe
(defun getHöhe ( / heightValue prompt)
  (setq prompt (strcat "\nGeben Sie die Höhe ein" 
                       (if g_lastHeight 
                         (strcat " <" (format-height g_lastHeight) ">") 
                         "") 
                       ": "))
  
  (setq heightValue (getreal prompt))
  
  ;; Wenn ENTER gedrückt und letzte Höhe vorhanden
  (if (null heightValue)
    (if g_lastHeight
      (setq heightValue g_lastHeight)
      ;; Beim ersten Aufruf ohne vorherige Höhe: Schleife
      (progn
        (while (null heightValue)
          (princ "\n*** Bitte geben Sie eine Höhe ein ***")
          (setq heightValue (getreal "\nGeben Sie die Höhe ein: "))
        )
      )
    )
  )
  
  ;; Neue Höhe speichern
  (setq g_lastHeight heightValue)
  heightValue
)

;;; Fragt Benutzer nach XY-Skalierung und speichert in Config
(defun getScale ( / scaleValue prompt current-scale)
  ;; Aktuelle Skalierung aus Config lesen
  (setq current-scale (read-scale-config))
  
  (setq prompt (strcat "\nNeue XY-Skalierung" 
                       (if current-scale 
                         (strcat " <" (rtos current-scale 2 2) ">") 
                         " <1.0>") 
                       ": "))
  
  (setq scaleValue (getreal prompt))
  
  ;; Wenn ENTER gedrückt
  (if (null scaleValue)
    (if current-scale
      (setq scaleValue current-scale)
      (setq scaleValue 1.0)
    )
  )
  
  ;; Validierung: Skalierung muss > 0 sein
  (if (<= scaleValue 0.0)
    (progn
      (princ "\n*** Skalierung muss größer als 0 sein! Verwende 1.0 ***")
      (setq scaleValue 1.0)
    )
  )
  
  ;; Skalierung in Config speichern
  (save-scale-config scaleValue)
  (princ (strcat "\n✓ Skalierung gespeichert: " (rtos scaleValue 2 2)))
  
  scaleValue
)

;;; ============================================================================
;;; HAUPTFUNKTIONEN
;;; ============================================================================

;;; Fügt Höhenkoten-Block an gegebenem Punkt mit Höhe und Skalierung ein
(defun CopyBlockAutomatisch (einfügepunkt höhe scale / blockName heightStr intPart decPart height2DecStr attdia ent attribs insertionPoint block-available importEnt)
  (setq blockName *hoehenkote-blockname*)
  
  ;; Parameter-Prüfung
  (if (and einfügepunkt höhe scale)
    (progn
      ;; Block verfügbar machen (nutzt BlockImport.lsp Bibliothek)
      ;; Rückgabe: (T importEnt) oder (nil nil)
      (setq block-available (ensure-block-available blockName))
      
      (if (car block-available)  ;; Erstes Element = Erfolg?
        (progn
          (setq importEnt (cadr block-available))  ;; Zweites Element = importEnt
          
          ;; Höhe als String mit genau 3 Dezimalstellen
          (setq heightStr (ensure-three-decimals höhe))
          
          ;; Höhe in Ganzzahl- und Dezimalteil aufteilen
          (setq intPart (substr heightStr 1 (vl-string-search "." heightStr)))
          (setq decPart (substr heightStr (+ (strlen intPart) 2)))
          
          ;; Dezimalteil auf 3 Stellen begrenzen, falls notwendig
          (if (< (strlen decPart) 3)
            (setq decPart (strcat decPart (apply 'strcat (repeat (- 3 (strlen decPart)) "0"))))
          )
          
          ;; Höhe als String mit 2 Dezimalstellen für HOEHE und Formatierung
          (setq height2DecStr (strcat intPart "." (substr decPart 1 2)))
          
          ;; Vorzeichen hinzufügen
          (setq height2DecStr (cond
                                ((= höhe 0.0) (strcat "%%p" height2DecStr))
                                ((> höhe 0.0) (strcat "+" height2DecStr))
                                (T height2DecStr))) ;; Negativer Wert bleibt unverändert
          
          ;; ATTDIA-Variable speichern und auf 0 setzen
          (setq attdia (getvar "ATTDIA"))
          (setvar "ATTDIA" 0)
          
          ;; Block einfügen mit XY-Skalierung (Z bleibt 1.0)
          (command "._-insert" blockName einfügepunkt scale scale "" "")
          
          ;; ATTDIA-Variable auf den ursprünglichen Wert zurücksetzen
          (setvar "ATTDIA" attdia)
          
          ;; Attribute im eingefügten Block setzen
          (setq ent (entlast))
          (if (and ent (eq (cdr (assoc 0 (entget ent))) "INSERT"))
            (progn
              (setq attribs (entnext ent))
              (while (and attribs (eq (cdr (assoc 0 (entget attribs))) "ATTRIB"))
                (cond
                  ((eq (cdr (assoc 2 (entget attribs))) "HOEHE")
                   (entmod (subst (cons 1 height2DecStr) (assoc 1 (entget attribs)) (entget attribs)))
                  )
                  ((eq (cdr (assoc 2 (entget attribs))) "3DEZ")
                   (if (not (= (substr decPart 3 1) "0"))
                     (entmod (subst (cons 1 (substr decPart 3 1)) (assoc 1 (entget attribs)) (entget attribs)))
                   )
                  )
                )
                (setq attribs (entnext attribs))
              )
            )
          )
          
          ;; Block auf die Eingabehöhe verschieben
          (setq insertionPoint (cdr (assoc 10 (entget ent))))
          (command "._move" ent "" "_non" insertionPoint "_non" (list (car insertionPoint) (cadr insertionPoint) höhe))
          
          ;; Den während des Imports eingefügten Block wieder entfernen (falls vorhanden)
          (if importEnt
            (entdel importEnt)
          )
          
          (princ (strcat "\n✓ Höhenkote gesetzt: " height2DecStr 
                        " | Z=" (rtos höhe 2 3) 
                        " | XY-Scale=" (rtos scale 2 2)))
        )
        (princ "\n*** FEHLER: Block konnte nicht geladen werden ***")
      )
    )
    (princ "\n*** Fehler: Ungültige Parameter ***")
  )
  (princ)
)

;;; ============================================================================
;;; BEFEHLE
;;; ============================================================================

;;; Hauptbefehl: Höhenkote setzen
(defun c:SetHK ( / *error* result pt scale höhe old-cmdecho)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    ;; ESC und ENTER unterdrücken
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\nFehler: " msg))
    )
    ;; Systemvariablen wiederherstellen
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  
  ;; Systemvariablen setzen für Command
  (setvar "CMDECHO" 0)     ;; Command-Echo aus
  
  ;; Einfügepunkt mit Skalierungs-Option abfragen
  ;; Rückgabe: (punkt scale) oder nil
  (setq result (getEinfügepunktMitScale))
  
  ;; Nur weitermachen wenn Punkt gewählt
  (if result
    (progn
      (setq pt (car result))     ;; Punkt
      (setq scale (cadr result)) ;; Skalierung
      
      ;; Höhe abfragen
      (setq höhe (getHöhe))
      
      ;; Block einfügen
      (if höhe
        (CopyBlockAutomatisch pt höhe scale)
      )
    )
  )
  
  ;; Cleanup bei normalem Ende
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

;;; Zeigt aktuell konfigurierten Block-Pfad (nutzt BlockImport.lsp)
(defun c:ShowBlockPath ( / )
  (show-block-path)
)

;;; Löscht gespeicherten Block-Pfad (nutzt BlockImport.lsp)
(defun c:ResetBlockPath ( / )
  (reset-block-path)
)

;;; ============================================================================
;;; LADE-MELDUNG
;;; ============================================================================

(vl-load-com)
(princ "\nSetHoehenkote.lsp v1.3.2 geladen.")
(princ "\nBefehle: SetHK - Höhenkote setzen (S für Skalierung)")
(princ "\n         ShowBlockPath - Zeigt konfigurierten Block-Pfad")
(princ "\n         ResetBlockPath - Löscht gespeicherten Pfad")
(princ)

;;; Ende der Datei
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
;;; Version: 1.1.2
;;; Datum: 2026-02-13
;;; Autor: Herbert Schrotter

;;; ============================================================================
;;; BIBLIOTHEKEN LADEN
;;; ============================================================================

;; Lade gemeinsame Block-Import Bibliothek
;; Intelligente Pfad-Suche mit mehreren Fallbacks
(setq *blockimport-lib-path*
  (cond
    ;; 1. Versuch: lib/ Unterordner im Support-Ordner
    ((findfile "lib/BlockImport.lsp"))
    
    ;; 2. Versuch: Direkt im Support-Ordner
    ((findfile "BlockImport.lsp"))
    
    ;; 3. Versuch: Relativ zum Script-Verzeichnis (falls via voller Pfad geladen)
    ((and (setq *temp-script-path* (findfile "SetHoehenkote.lsp"))
          (setq *temp-dir* (vl-filename-directory *temp-script-path*))
          (findfile (strcat *temp-dir* "/lib/BlockImport.lsp"))))
  )
)

;; Prüfe ob Bibliothek gefunden wurde
(if (null *blockimport-lib-path*)
  (progn
    (alert (strcat "FEHLER: BlockImport.lsp nicht gefunden!\n\n"
                   "Bitte stelle sicher, dass eine der folgenden Dateien existiert:\n"
                   "1. lib/BlockImport.lsp (im Support-Ordner)\n"
                   "2. BlockImport.lsp (im Support-Ordner)\n"
                   "3. lib/BlockImport.lsp (neben diesem Script)"))
    (exit)
  )
  (progn
    ;; Lade Bibliothek
    (load *blockimport-lib-path*)
    (princ (strcat "\n  Bibliothek geladen: " *blockimport-lib-path*))
  )
)

;;; ============================================================================
;;; KONFIGURATION
;;; ============================================================================

;; Name des Höhenkoten-Blocks
(setq *hoehenkote-blockname* "BLK_Hoehenkote")

;; Standard-Pfad zur Block-Datei (wird von BlockImport.lsp verwendet)
(if (not *default-block-file*)
  (setq *default-block-file* "D:/OneDrive/Dokumente/02 Arbeit/05 Vorlagen - Scripte/02_AutoCAD Tools/templates/Blöcke/BLK_Hoehenkote.dwg")
)

;; Pfad zur Konfigurationsdatei (wird von BlockImport.lsp verwendet)
(if (not *block-config-file*)
  (setq *block-config-file* (strcat (getenv "APPDATA") "/AutoCAD/HoehenkoteBlockConfig.txt"))
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

;;; ============================================================================
;;; HAUPTFUNKTIONEN
;;; ============================================================================

;;; Fügt Höhenkoten-Block an gegebenem Punkt mit Höhe ein
(defun CopyBlockAutomatisch (einfügepunkt höhe / blockName heightStr intPart decPart height2DecStr attdia ent attribs insertionPoint block-available importEnt)
  (setq blockName *hoehenkote-blockname*)
  
  ;; Parameter-Prüfung
  (if (and einfügepunkt höhe)
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
          
          ;; Block einfügen
          (command "._-insert" blockName einfügepunkt "" "" "" "")
          
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
          
          (princ (strcat "\n✓ Höhenkote gesetzt: " height2DecStr " auf Z=" (rtos höhe 2 3)))
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
(defun c:SetHK ( / *error* pt höhe old-osmode old-cmdecho)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    ;; ESC und ENTER unterdrücken
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\nFehler: " msg))
    )
    ;; Systemvariablen wiederherstellen
    (if old-osmode (setvar "OSMODE" old-osmode))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  
  ;; Systemvariablen sichern
  (setq old-osmode (getvar "OSMODE"))
  (setq old-cmdecho (getvar "CMDECHO"))
  
  ;; Systemvariablen setzen für Command
  (setvar "OSMODE" 0)      ;; OSNAP aus
  (setvar "CMDECHO" 0)     ;; Command-Echo aus
  
  ;; Einfügepunkt abfragen
  (setq pt (getEinfügepunkt))
  
  ;; Nur weitermachen wenn Punkt gewählt
  (if pt
    (progn
      ;; Höhe abfragen
      (setq höhe (getHöhe))
      
      ;; Block einfügen
      (if höhe
        (CopyBlockAutomatisch pt höhe)
      )
    )
  )
  
  ;; Cleanup bei normalem Ende
  (setvar "OSMODE" old-osmode)
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

;;; Alias für Abwärtskompatibilität
(defun c:CopyBlock ()
  (princ "\n*** Hinweis: Befehl wurde umbenannt zu 'SetHK' ***")
  (c:SetHK)
)

;;; ============================================================================
;;; LADE-MELDUNG
;;; ============================================================================

(vl-load-com)
(princ "\nSetHoehenkote.lsp v1.1.2 geladen.")
(princ "\nBefehle: SetHK - Höhenkote an Punkt setzen")
(princ "\n         ShowBlockPath - Zeigt konfigurierten Block-Pfad")
(princ "\n         ResetBlockPath - Löscht gespeicherten Pfad")
(princ "\n         CopyBlock (veraltet) - Alias für SetHK")
(princ)

;;; Ende der Datei

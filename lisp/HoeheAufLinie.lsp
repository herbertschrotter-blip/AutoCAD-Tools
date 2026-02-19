;;; HoeheAufLinie.lsp
;;; Höheninterpolation entlang einer Linie zwischen zwei Fixpunkten
;;; Speziell für Leica-Vermessungsarbeiten
;;;
;;; Installation:
;;; 1. Diese Datei in den AutoCAD Support-Ordner kopieren
;;; 2. lib/BlockImport.lsp muss ebenfalls im Support-Ordner sein
;;; 3. AutoCAD neu starten oder mit (load "HoeheAufLinie.lsp") laden
;;;
;;; Verwendung:
;;; - Befehl: HoeheAufLinie (oder HAL)
;;; - Zwei Fixpunkte mit bekannten Höhen setzen
;;; - Beliebig viele Zwischenpunkte setzen mit automatisch interpolierter Höhe
;;; - ESC zum Beenden
;;;
;;; Version: 1.1.1
;;; Datum: 2026-02-10
;;; Autor: Herbert Schrotter

;;; ============================================================================
;;; BIBLIOTHEKEN LADEN
;;; ============================================================================

;; Lade gemeinsame Block-Import Bibliothek
;; Intelligente Pfad-Suche mit mehreren Fallbacks
(setq *blockimport-lib-path*
  (cond
    ;; 1. Versuch: Relativ zum aktuellen Script (lisp/lib/BlockImport.lsp)
    ((findfile (strcat (vl-filename-directory (findfile "HoeheAufLinie.lsp")) 
                       "/lib/BlockImport.lsp")))
    
    ;; 2. Versuch: lib/ Unterordner im Support-Ordner
    ((findfile "lib/BlockImport.lsp"))
    
    ;; 3. Versuch: Direkt im Support-Ordner (falls lib/ dort kopiert wurde)
    ((findfile "BlockImport.lsp"))
  )
)

;; Prüfe ob Bibliothek gefunden wurde
(if (null *blockimport-lib-path*)
  (progn
    (alert (strcat "FEHLER: BlockImport.lsp nicht gefunden!\n\n"
                   "Bitte stelle sicher, dass eine der folgenden Dateien existiert:\n"
                   "1. lisp/lib/BlockImport.lsp (neben diesem Script)\n"
                   "2. lib/BlockImport.lsp (im Support-Ordner)\n"
                   "3. BlockImport.lsp (im Support-Ordner)"))
    (exit)
  )
  (progn
    (princ (strcat "\nLade BlockImport.lsp von: " *blockimport-lib-path*))
    (load *blockimport-lib-path*)
  )
)

;;; ============================================================================
;;; KONFIGURATION
;;; ============================================================================

;; Name des Höhenkoten-Blocks
(setq *hoehenkote-blockname* "BLK_Hoehenkote")

;; Standard-Pfad zur Block-Datei (wird von BlockImport.lsp verwendet)
(setq *default-block-file* "D:/OneDrive/Dokumente/02 Arbeit/05 Vorlagen - Scripte/02_AutoCAD Tools/templates/Blöcke/BLK_Hoehenkote.dwg")

;; Pfad zur Konfigurationsdatei (wird von BlockImport.lsp verwendet)
(setq *block-config-file* (strcat (getenv "APPDATA") "/AutoCAD/HoehenkoteBlockConfig.txt"))

;;; ============================================================================
;;; GLOBALE VARIABLEN
;;; ============================================================================

;; Speichert die zuletzt eingegebene Höhe
(setq g_lastHeight nil)

;;; ============================================================================
;;; HILFSFUNKTIONEN - FORMATIERUNG
;;; ============================================================================

;;; Konvertiert Höhe in String mit genau 2 Dezimalstellen
(defun ensure-two-decimals (heightValue)
  (rtos heightValue 2 2)
)

;;; Formatiert Höhenwert für Anzeige (mit 2 Dezimalstellen)
(defun format-height (heightValue)
  (rtos heightValue 2 2)
)

;;; Formatiert Höhenwert mit Vorzeichen (+ oder %%p für ±0)
(defun format-height-value (heightValue / formattedHeight)
  (setq formattedHeight (ensure-two-decimals heightValue))
  (cond
    ((= heightValue 0.0) (setq formattedHeight (strcat "%%p" formattedHeight)))
    ((> heightValue 0.0) (setq formattedHeight (strcat "+" formattedHeight)))
  )
  formattedHeight
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - MATHEMATIK
;;; ============================================================================

;;; Berechnet interpolierte Höhe für Punkt auf Linie zwischen zwei Fixpunkten
;;; pf1, pf2 = Fixpunkte (Listen mit x,y,z)
;;; height1, height2 = Höhen der Fixpunkte
;;; pg = Gesuchter Punkt (Liste mit x,y,z)
;;; Rückgabe: Interpolierte Höhe (Zahl)
(defun calculate-interpolated-height (pf1 height1 pf2 height2 pg / vpf vpg scalar proj dist-pf1-pf2 dist-pf1-proj slope interpolated-height)
  ;; Vektor von pf1 zu pf2
  (setq vpf (list (- (car pf2) (car pf1)) 
                  (- (cadr pf2) (cadr pf1))))
  
  ;; Vektor von pf1 zu pg
  (setq vpg (list (- (car pg) (car pf1)) 
                  (- (cadr pg) (cadr pf1))))
  
  ;; Skalarprojektion: Wie weit liegt pg auf der Linie pf1-pf2?
  (setq scalar (/ (+ (* (car vpg) (car vpf)) 
                     (* (cadr vpg) (cadr vpf))) 
                  (expt (distance pf1 pf2) 2)))
  
  ;; Projizierter Punkt auf der Linie
  (setq proj (list (+ (car pf1) (* scalar (car vpf))) 
                   (+ (cadr pf1) (* scalar (cadr vpf)))))
  
  ;; Distanz von pf1 zum projizierten Punkt
  (setq dist-pf1-proj (distance pf1 proj))
  
  ;; Gesamtdistanz zwischen Fixpunkten
  (setq dist-pf1-pf2 (distance pf1 pf2))
  
  ;; Gefälle berechnen
  (setq slope (/ (- height2 height1) dist-pf1-pf2))
  
  ;; Interpolierte Höhe berechnen
  (setq interpolated-height (+ height1 (* slope dist-pf1-proj)))
  
  interpolated-height
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - BLOCK EINFÜGEN
;;; ============================================================================

;;; Fügt Höhenkoten-Block an gegebenem Punkt mit Höhe ein
(defun CopyBlockAutomatisch (einfügepunkt höhe / blockName heightStr attdia ent attribs insertionPoint block-available importEnt)
  (setq blockName *hoehenkote-blockname*)
  
  ;; Parameter-Prüfung
  (if (and einfügepunkt höhe)
    (progn
      ;; Block verfügbar machen (lädt automatisch wenn nötig)
      ;; Verwendet ensure-block-available aus BlockImport.lsp
      ;; Rückgabe: (T importEnt) oder (nil nil)
      (setq block-available (ensure-block-available blockName))
      
      (if (car block-available)  ;; Erstes Element = Erfolg?
        (progn
          (setq importEnt (cadr block-available))  ;; Zweites Element = importEnt
          
          ;; Höhe als String mit genau 2 Dezimalstellen formatieren
          (setq heightStr (format-height-value höhe))
          
          ;; ATTDIA-Variable speichern und auf 0 setzen (keine Dialog-Anzeige)
          (setq attdia (getvar "ATTDIA"))
          (setvar "ATTDIA" 0)
          
          ;; Block einfügen
          (command "_-insert" blockName einfügepunkt "" "" "" "")
          
          ;; ATTDIA-Variable auf den ursprünglichen Wert zurücksetzen
          (setvar "ATTDIA" attdia)
          
          ;; Attribute im eingefügten Block setzen
          (setq ent (entlast))
          (if (and ent (eq (cdr (assoc 0 (entget ent))) "INSERT"))
            (progn
              (setq attribs (entnext ent))
              (while (and attribs (eq (cdr (assoc 0 (entget attribs))) "ATTRIB"))
                ;; Nur HOEHE-Attribut setzen (3DEZ wird nicht mehr verwendet)
                (if (eq (cdr (assoc 2 (entget attribs))) "HOEHE")
                  (entmod (subst (cons 1 heightStr) (assoc 1 (entget attribs)) (entget attribs)))
                )
                (setq attribs (entnext attribs))
              )
            )
          )
          
          ;; Block auf die Eingabehöhe verschieben (Z-Koordinate)
          (setq insertionPoint (cdr (assoc 10 (entget ent))))
          (command "_move" ent "" "_non" insertionPoint "_non" 
                   (list (car insertionPoint) (cadr insertionPoint) höhe))
          
          ;; Den während des Imports eingefügten Block wieder entfernen (falls vorhanden)
          (if importEnt
            (entdel importEnt)
          )
          
          (princ (strcat "\n  ✓ Höhenkote gesetzt: " heightStr " auf Z=" (rtos höhe 2 3)))
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

;;; Hauptbefehl: Höheninterpolation entlang Linie
(defun c:HoeheAufLinie ( / pf1 height1 pf2 height2 pg interpolated-height)
  (princ "\n=== Höheninterpolation entlang Linie ===")
  (princ "\nSetzen Sie zwei Fixpunkte mit bekannten Höhen.")
  (princ "\nDann können Sie beliebig viele Zwischenpunkte setzen.")
  
  ;; ========== FIXPUNKT 1 ==========
  (princ "\n")
  (setq pf1 (getpoint "\nFixpunkt 1 wählen: "))
  
  (if (null pf1)
    (progn
      (princ "\n*** Abbruch: Kein Punkt gewählt ***")
      (princ)
    )
    (progn
      ;; Höhe für Fixpunkt 1
      (setq height1 (getreal (strcat "\nHöhe Fixpunkt 1 eingeben"
                                     (if g_lastHeight 
                                       (strcat " <" (format-height g_lastHeight) ">") 
                                       "")
                                     ": ")))
      
      ;; Falls ENTER: letzte Höhe verwenden
      (if (null height1)
        (if g_lastHeight
          (setq height1 g_lastHeight)
          (progn
            (while (null height1)
              (princ "\n*** Bitte geben Sie eine Höhe ein ***")
              (setq height1 (getreal "\nHöhe Fixpunkt 1 eingeben: "))
            )
          )
        )
      )
      
      ;; Höhe speichern
      (setq g_lastHeight height1)
      
      ;; Block an Fixpunkt 1 einfügen
      (CopyBlockAutomatisch pf1 height1)
      
      ;; ========== FIXPUNKT 2 ==========
      (princ "\n")
      (setq pf2 (getpoint "\nFixpunkt 2 wählen: "))
      
      (if (null pf2)
        (progn
          (princ "\n*** Abbruch: Kein Punkt gewählt ***")
          (princ)
        )
        (progn
          ;; Höhe für Fixpunkt 2
          (setq height2 (getreal (strcat "\nHöhe Fixpunkt 2 eingeben"
                                         (if g_lastHeight 
                                           (strcat " <" (format-height g_lastHeight) ">") 
                                           "")
                                         ": ")))
          
          ;; Falls ENTER: letzte Höhe verwenden
          (if (null height2)
            (if g_lastHeight
              (setq height2 g_lastHeight)
              (progn
                (while (null height2)
                  (princ "\n*** Bitte geben Sie eine Höhe ein ***")
                  (setq height2 (getreal "\nHöhe Fixpunkt 2 eingeben: "))
                )
              )
            )
          )
          
          ;; Höhe speichern
          (setq g_lastHeight height2)
          
          ;; Block an Fixpunkt 2 einfügen
          (CopyBlockAutomatisch pf2 height2)
          
          ;; ========== SCHLEIFE: GESUCHTE PUNKTE ==========
          (princ "\n")
          (princ "\n--- Zwischenpunkte setzen (ESC = Ende) ---")
          
          (while (setq pg (getpoint "\nGesuchten Punkt wählen (ESC = Ende): "))
            ;; Höhe interpolieren
            (setq interpolated-height (calculate-interpolated-height pf1 height1 pf2 height2 pg))
            
            ;; Ausgabe der berechneten Höhe
            (princ (strcat "\n  Berechnete Höhe: " (format-height interpolated-height)))
            
            ;; Block einfügen
            (CopyBlockAutomatisch pg interpolated-height)
          )
          
          (princ "\n\n✓ Höheninterpolation abgeschlossen.")
        )
      )
    )
  )
  (princ)
)

;;; Kurzbefehl (Alias)
(defun c:HAL ()
  (c:HoeheAufLinie)
)

;;; Zeigt aktuell konfigurierten Block-Pfad
;;; Verwendet show-block-path aus BlockImport.lsp
(defun c:ShowBlockPath ()
  (show-block-path)
)

;;; Löscht gespeicherten Block-Pfad
;;; Verwendet reset-block-path aus BlockImport.lsp
(defun c:ResetBlockPath ()
  (reset-block-path)
)

;;; ============================================================================
;;; FEHLERBEHANDLUNG
;;; ============================================================================

(defun *error* (errmsg)
  (if (/= errmsg "quit / exit abort")
    (princ (strcat "\nFehler: " errmsg))
  )
  ;; Systemvariablen wiederherstellen (falls vorhanden)
  (if attdia (setvar "ATTDIA" attdia))
  (princ)
)

;;; ============================================================================
;;; LADE-MELDUNG
;;; ============================================================================

(princ "\nHoeheAufLinie.lsp v1.1.1 geladen.")
(princ "\nBefehle: HoeheAufLinie (oder HAL) - Höheninterpolation entlang Linie")
(princ "\n         ShowBlockPath - Zeigt konfigurierten Block-Pfad")
(princ "\n         ResetBlockPath - Löscht gespeicherten Pfad")
(princ "\nBibliothek: BlockImport.lsp v1.0.0")
(princ)

;;; Ende der Datei
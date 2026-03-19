;;; HoeheAufLinie.lsp
;;; Hoeheninterpolation entlang einer Linie zwischen zwei Fixpunkten
;;; Speziell fuer Leica-Vermessungsarbeiten
;;;
;;; Installation:
;;; 1. Diese Datei mit APPLOAD laden
;;; 2. Beim ersten Mal nach lib/BlockImport.lsp gefragt werden
;;; 3. Pfad wird gespeichert fuer zukuenftige Sitzungen
;;;
;;; Verwendung:
;;; - Befehl: HoeheAufLinie (oder HAL)
;;; - Zwei Fixpunkte mit bekannten Hoehen setzen
;;; - Beliebig viele Zwischenpunkte setzen mit automatisch interpolierter Hoehe
;;; - ESC zum Beenden
;;;
;;; Version: 2.0.0
;;; Datum: 2026-03-19
;;; Autor: Herbert Schrotter
;;; Namespace: HAL (HoeheAufLinie)

;;; ============================================================================
;;; DEBUG-SYSTEM MIT CRASH-SAFE LOG-DATEI
;;; ============================================================================

;; Debug-Modus: T = ein, nil = aus
(if (not (boundp '*HAL:debug-mode*))
  (setq *HAL:debug-mode* nil)
)

;; Log-Datei Pfad: %APPDATA%/AutoCAD/log/ (neben den Config-Dateien)
(setq *HAL:log-dir*
  (strcat (getenv "APPDATA") "/AutoCAD/log")
)

;; Ordner erstellen falls nicht vorhanden
(if (not (vl-file-directory-p *HAL:log-dir*))
  (vl-mkdir *HAL:log-dir*)
)

(setq *HAL:log-path* (strcat *HAL:log-dir* "/HoeheAufLinie_debug.log"))

;;; Schreibt eine Zeile in die Log-Datei (open-append-write-close pro Zeile)
;;; Crash-safe: Jede Zeile wird sofort auf die Platte geschrieben
(defun HAL:log-write (text / file)
  (if (setq file (open *HAL:log-path* "a"))
    (progn
      (write-line text file)
      (close file)
    )
  )
)

;;; Erstellt neue Log-Datei mit Header (ueberschreibt vorherige Sitzung)
(defun HAL:log-start ( / file)
  (if (setq file (open *HAL:log-path* "w"))
    (progn
      (write-line "=== HoeheAufLinie Debug Log ===" file)
      (write-line (strcat "Datum: " (menucmd "M=$(edtime,0,DD.MO.YYYY HH:MM:SS)")) file)
      (write-line (strcat "Zeichnung: " (getvar "DWGNAME")) file)
      (write-line "===============================" file)
      (write-line "" file)
      (close file)
    )
    (princ (strcat "\n*** Fehler: Log-Datei kann nicht erstellt werden: " *HAL:log-path* " ***"))
  )
)

;;; Debug-Ausgabe: Log-Datei IMMER, Command-Line nur wenn *HAL:debug-mode* = T
(defun HAL:debug (msg / line)
  (setq line (strcat "[DEBUG] " msg))
  ;; Log-Datei: IMMER schreiben (crash-safe)
  (HAL:log-write line)
  ;; Command-Line: nur bei aktivem Debug
  (if *HAL:debug-mode*
    (princ (strcat "\n  " line))
  )
)

;;; ============================================================================
;;; BIBLIOTHEKEN LADEN
;;; ============================================================================

;; Config-Datei fuer BlockImport.lsp Pfad
(setq *HAL:config-file* 
  (if (getenv "APPDATA")
    (strcat (getenv "APPDATA") "/AutoCAD/HoeheAufLinieConfig.txt")
    "C:/Temp/HoeheAufLinieConfig.txt"
  )
)

;;; Liest gespeicherten BlockImport.lsp Pfad aus Config
(defun HAL:read-blockimport-path ( / file path version)
  (setq path nil)
  
  ;; Pruefe ob Config-Datei existiert
  (if (not (findfile *HAL:config-file*))
    nil  ;; Datei existiert nicht
    ;; Versuche Datei zu oeffnen mit Error-Handling
    (if (vl-catch-all-error-p
          (setq file (vl-catch-all-apply 'open (list *HAL:config-file* "r"))))
      (progn
        (princ (strcat "\n*** Fehler beim Oeffnen der Config-Datei: " *HAL:config-file* " ***"))
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
(defun HAL:save-blockimport-path (filepath / file dir)
  ;; Erstelle Verzeichnis falls nicht vorhanden
  (setq dir (vl-filename-directory *HAL:config-file*))
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
        (setq file (vl-catch-all-apply 'open (list *HAL:config-file* "w"))))
    (progn
      (princ (strcat "\n*** Fehler beim Schreiben der Config-Datei: " *HAL:config-file* " ***"))
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

;; Versuche gespeicherten Pfad zu laden
(setq *HAL:blockimport-path* (HAL:read-blockimport-path))

;; Wenn gespeicherter Pfad existiert, pruefe ob Datei noch da ist
(if (and *HAL:blockimport-path* (not (findfile *HAL:blockimport-path*)))
  (setq *HAL:blockimport-path* nil)  ;; Pfad ungueltig
)

;; Wenn kein gueltiger Pfad: Suche in Standard-Orten
(if (null *HAL:blockimport-path*)
  (setq *HAL:blockimport-path*
    (cond
      ;; 1. Versuch: lib/ Unterordner im Support-Ordner
      ((findfile "lib/BlockImport.lsp"))
      
      ;; 2. Versuch: Direkt im Support-Ordner
      ((findfile "BlockImport.lsp"))
    )
  )
)

;; Wenn immer noch nicht gefunden: Bitte User um Auswahl
(if (null *HAL:blockimport-path*)
  (progn
    (princ "\n*** BlockImport.lsp wird nicht im Support-Pfad gefunden ***")
    (princ "\nBitte waehlen Sie die Datei lib/BlockImport.lsp aus...")
    
    ;; Oeffne File-Dialog
    (if (setq *HAL:blockimport-path* 
          (getfiled "BlockImport.lsp auswaehlen" 
                    ;; Start-Ordner: Zeichnungs-Verzeichnis oder User-Profile
                    (cond
                      ((getvar "DWGPREFIX"))
                      ((getenv "USERPROFILE"))
                      (T "")
                    )
                    "lsp" 
                    0))
      (progn
        (princ (strcat "\nGewaehlte Datei: " *HAL:blockimport-path*))
        ;; Speichere Pfad fuer naechstes Mal
        (HAL:save-blockimport-path *HAL:blockimport-path*)
        (princ "\nPfad wurde gespeichert fuer zukuenftige Sitzungen.")
      )
      (progn
        (alert "FEHLER: Keine Datei ausgewaehlt!")
        (exit)
      )
    )
  )
)

;; Lade Bibliothek
(if *HAL:blockimport-path*
  (progn
    (load *HAL:blockimport-path*)
    (princ (strcat "\n  Bibliothek geladen: " *HAL:blockimport-path*))
  )
)

;;; ============================================================================
;;; KONFIGURATION
;;; ============================================================================

;; Block-Import Context fuer dieses Script (NACH dem Laden setzen!)
(setq *HAL:block-import-context* "HoeheAufLinie")
(setq *block-import-context* *HAL:block-import-context*)

;; Name des Hoehenkoten-Blocks
(setq *HAL:blockname* "BLK_Hoehenkote")

;; Config-Datei fuer XY-Skalierung
(setq *HAL:scale-config-file* 
  (if (getenv "APPDATA")
    (strcat (getenv "APPDATA") "/AutoCAD/HoeheAufLinieScale.txt")
    "C:/Temp/HoeheAufLinieScale.txt"
  )
)

;;; Liest gespeicherte XY-Skalierung aus Config
(defun HAL:read-scale-config ( / file scale version)
  (setq scale nil)
  
  (if (not (findfile *HAL:scale-config-file*))
    nil
    (if (vl-catch-all-error-p
          (setq file (vl-catch-all-apply 'open (list *HAL:scale-config-file* "r"))))
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
(defun HAL:save-scale-config (scale-value / file dir)
  (setq dir (vl-filename-directory *HAL:scale-config-file*))
  (if (not (vl-file-directory-p dir))
    (vl-catch-all-apply 'vl-mkdir (list dir))
  )
  
  (if (vl-catch-all-error-p
        (setq file (vl-catch-all-apply 'open (list *HAL:scale-config-file* "w"))))
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

;; Speichert die zuletzt eingegebene Hoehe fuer Default-Vorschlag
;; Wird ueber Sessions hinweg NICHT gespeichert (nur im RAM)
(setq *HAL:last-height* nil)

;;; ============================================================================
;;; HILFSFUNKTIONEN - FORMATIERUNG
;;; ============================================================================

;;; Konvertiert Hoehe in String mit genau 2 Dezimalstellen
(defun HAL:ensure-two-decimals (heightValue)
  (rtos heightValue 2 2)
)

;;; Formatiert Hoehenwert fuer Anzeige (mit 2 Dezimalstellen)
(defun HAL:format-height (heightValue)
  (rtos heightValue 2 2)
)

;;; Formatiert Hoehenwert mit Vorzeichen (+ oder %%p fuer +/-0)
(defun HAL:format-height-value (heightValue / formattedHeight)
  (setq formattedHeight (HAL:ensure-two-decimals heightValue))
  (cond
    ((= heightValue 0.0) (setq formattedHeight (strcat "%%p" formattedHeight)))
    ((> heightValue 0.0) (setq formattedHeight (strcat "+" formattedHeight)))
  )
  formattedHeight
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - BLOCK-PRUEFUNG
;;; ============================================================================

;;; Prueft ob Block bereits nahe dieser Position+Hoehe existiert
;;; Verwendet distance-Funktion statt einzelner Koordinaten-Checks
;;; WICHTIG: Transformiert BKS->WKS fuer korrekten Vergleich!
;;; 
;;; Parameter:
;;;   pt - Punkt (Liste x y z) in BKS-Koordinaten
;;;   height - Hoehe (Zahl)
;;;   blockname - Block-Name (String)
;;; 
;;; Rueckgabe:
;;;   T wenn Block existiert, nil sonst
;;; 
;;; Toleranzen:
;;;   XY-Ebene: 0.05 Einheiten (5cm) - faengt auch Attribut-Klicks
;;;   Z-Hoehe: 0.001 Einheiten (1mm) - praezise Hoehenpruefung
(defun HAL:block-exists-at-position (pt height blockname / ss i ent inspt pt-wcs tolerance-xy tolerance-z dist-xy dist-z found)
  (setq tolerance-xy 0.05)   ; 5cm Toleranz fuer XY (OSNAP kann Attribut fangen)
  (setq tolerance-z 0.001)   ; 1mm Toleranz fuer Z (praezise Hoehe)
  (setq found nil)
  
  ;; KRITISCH: Transformiere Punkt von BKS zu WKS
  ;; Block-Einfuegepunkte (DXF 10) sind IMMER in WKS!
  ;; getpoint gibt BKS-Koordinaten zurueck!
  (setq pt-wcs (trans pt 1 0))  ; 1=UCS(BKS), 0=WCS
  
  (HAL:debug (strcat "HAL:block-exists-at-position: blockname=" blockname))
  (HAL:debug (strcat "  pt(BKS)=(" (rtos (car pt) 2 4) " " (rtos (cadr pt) 2 4) " " (rtos (caddr pt) 2 4) ")"))
  (HAL:debug (strcat "  pt(WKS)=(" (rtos (car pt-wcs) 2 4) " " (rtos (cadr pt-wcs) 2 4) " " (rtos (caddr pt-wcs) 2 4) ")"))
  (HAL:debug (strcat "  height=" (rtos height 2 4)))
  
  ;; Suche alle Bloecke mit diesem Namen
  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 blockname))))
  
  (if ss
    (progn
      (HAL:debug (strcat "  Gefundene Bloecke: " (itoa (sslength ss))))
      (setq i 0)
      (while (and (< i (sslength ss)) (not found))
        (setq ent (ssname ss i))
        (setq inspt (cdr (assoc 10 (entget ent))))
        
        ;; Berechne XY-Abstand mit distance (2D) - WKS zu WKS!
        (setq dist-xy (distance (list (car pt-wcs) (cadr pt-wcs)) 
                                (list (car inspt) (cadr inspt))))
        
        ;; Berechne Z-Abstand
        (setq dist-z (abs (- height (caddr inspt))))
        
        (HAL:debug (strcat "  Block[" (itoa i) "] inspt=(" 
                           (rtos (car inspt) 2 4) " " (rtos (cadr inspt) 2 4) " " (rtos (caddr inspt) 2 4) 
                           ") dist-xy=" (rtos dist-xy 2 4) " dist-z=" (rtos dist-z 2 4)))
        
        ;; Pruefe beide Abstaende
        (if (and (< dist-xy tolerance-xy)
                 (< dist-z tolerance-z))
          (progn
            (HAL:debug "  >>> MATCH GEFUNDEN - Block existiert bereits!")
            (setq found T)
          )
        )
        
        (setq i (1+ i))
      )
      
      ;; Selection Set freigeben
      (setq ss nil)
      
      (if (not found)
        (HAL:debug "  Kein Match gefunden")
      )
      
      found
    )
    (progn
      (HAL:debug "  Keine Bloecke mit diesem Namen in Zeichnung")
      nil
    )
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - MATHEMATIK
;;; ============================================================================

;;; Berechnet interpolierte Hoehe fuer Punkt auf Linie zwischen zwei Fixpunkten
;;; Verwendet Skalarprojektion - funktioniert auch fuer Punkte ausserhalb der Strecke
;;; 
;;; Parameter:
;;;   pf1 - Fixpunkt 1 (Liste x y z)
;;;   height1 - Hoehe bei Fixpunkt 1 (Zahl)
;;;   pf2 - Fixpunkt 2 (Liste x y z)
;;;   height2 - Hoehe bei Fixpunkt 2 (Zahl)
;;;   pg - Gesuchter Punkt (Liste x y z)
;;; 
;;; Rueckgabe:
;;;   Interpolierte Hoehe (Zahl)
;;;   
;;; Funktioniert fuer:
;;;   - Punkte zwischen PF1 und PF2 (0 < scalar < 1)
;;;   - Punkte links von PF1 (scalar < 0) -> Extrapolation
;;;   - Punkte rechts von PF2 (scalar > 1) -> Extrapolation
(defun HAL:calc-interpolated-height (pf1 height1 pf2 height2 pg / vpf vpg scalar dist-pf1-pf2 height-diff interpolated-height)
  (HAL:debug "=== HAL:calc-interpolated-height ===")
  (HAL:debug (strcat "  pf1=(" (rtos (car pf1) 2 4) " " (rtos (cadr pf1) 2 4) " " (rtos (caddr pf1) 2 4) ") h1=" (rtos height1 2 4)))
  (HAL:debug (strcat "  pf2=(" (rtos (car pf2) 2 4) " " (rtos (cadr pf2) 2 4) " " (rtos (caddr pf2) 2 4) ") h2=" (rtos height2 2 4)))
  (HAL:debug (strcat "  pg=(" (rtos (car pg) 2 4) " " (rtos (cadr pg) 2 4) " " (rtos (caddr pg) 2 4) ")"))
  
  ;; Vektor von pf1 zu pf2 (nur XY-Ebene)
  (setq vpf (list (- (car pf2) (car pf1)) 
                  (- (cadr pf2) (cadr pf1))))
  
  ;; Vektor von pf1 zu pg (nur XY-Ebene)
  (setq vpg (list (- (car pg) (car pf1)) 
                  (- (cadr pg) (cadr pf1))))
  
  (HAL:debug (strcat "  vpf=(" (rtos (car vpf) 2 4) " " (rtos (cadr vpf) 2 4) ")"))
  (HAL:debug (strcat "  vpg=(" (rtos (car vpg) 2 4) " " (rtos (cadr vpg) 2 4) ")"))
  
  ;; 2D-Distanz PF1-PF2 (nur XY!) fuer Division-by-Zero Check
  ;; WICHTIG: distance() rechnet 3D wenn Punkte Z-Werte haben!
  ;; Wir brauchen NUR die XY-Distanz, daher aus vpf-Vektor berechnen
  (setq dist-pf1-pf2 (sqrt (+ (expt (car vpf) 2) (expt (cadr vpf) 2))))
  (HAL:debug (strcat "  dist-2D(pf1,pf2)=" (rtos dist-pf1-pf2 2 6)))
  
  (if (< dist-pf1-pf2 0.0001)
    (progn
      (HAL:debug "  *** WARNUNG: PF1 und PF2 zu nahe beieinander! Division by zero vermieden ***")
      (princ "\n*** WARNUNG: Fixpunkte haben gleiche XY-Position! ***")
      height1  ; Fallback: Hoehe von PF1
    )
    (progn
      ;; Skalarprojektion: Wie weit liegt pg auf der Linie pf1-pf2?
      ;; Scalar = 0.0 bei pf1, 1.0 bei pf2, <0 links von pf1, >1 rechts von pf2
      (setq scalar (/ (+ (* (car vpg) (car vpf)) 
                         (* (cadr vpg) (cadr vpf))) 
                      (expt dist-pf1-pf2 2)))
      
      ;; Hoehendifferenz zwischen Fixpunkten
      (setq height-diff (- height2 height1))
      
      ;; Interpolierte Hoehe berechnen
      (setq interpolated-height (+ height1 (* scalar height-diff)))
      
      (HAL:debug (strcat "  scalar=" (rtos scalar 2 6)))
      (HAL:debug (strcat "  height-diff=" (rtos height-diff 2 4)))
      (HAL:debug (strcat "  interpolated-height=" (rtos interpolated-height 2 4)))
      
      (if (or (< scalar -0.1) (> scalar 1.1))
        (HAL:debug (strcat "  *** HINWEIS: Punkt liegt ausserhalb der Strecke (Extrapolation)! ***"))
      )
      
      interpolated-height
    )
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - KONSTRUKTIONSLINIE
;;; ============================================================================

;;; Berechnet den XY-Punkt auf der Linie PF1-PF2 fuer eine gegebene Zielhoehe
;;; (Umgekehrte Interpolation: Hoehe -> Punkt statt Punkt -> Hoehe)
;;;
;;; Parameter:
;;;   pf1 - Fixpunkt 1 (Liste x y z)
;;;   height1 - Hoehe bei Fixpunkt 1 (Zahl)
;;;   pf2 - Fixpunkt 2 (Liste x y z)
;;;   height2 - Hoehe bei Fixpunkt 2 (Zahl)
;;;   target-height - Gesuchte Hoehe (Zahl)
;;;
;;; Rueckgabe:
;;;   XY-Punkt auf der Linie (Liste x y 0.0) oder nil bei Fehler
(defun HAL:calc-point-for-height (pf1 height1 pf2 height2 target-height / height-diff scalar px py)
  (HAL:debug "=== HAL:calc-point-for-height ===")
  (HAL:debug (strcat "  target-height=" (rtos target-height 2 4)))
  
  (setq height-diff (- height2 height1))
  
  (if (< (abs height-diff) 0.0001)
    (progn
      (HAL:debug "  *** WARNUNG: Fixpunkte haben gleiche Hoehe! Keine Berechnung moeglich ***")
      (princ "\n*** Fixpunkte haben gleiche Hoehe - Konstruktionslinie nicht moeglich ***")
      nil
    )
    (progn
      ;; Scalar = (target - h1) / (h2 - h1)
      (setq scalar (/ (- target-height height1) height-diff))
      
      ;; XY-Punkt auf der Linie berechnen
      (setq px (+ (car pf1) (* scalar (- (car pf2) (car pf1)))))
      (setq py (+ (cadr pf1) (* scalar (- (cadr pf2) (cadr pf1)))))
      
      (HAL:debug (strcat "  scalar=" (rtos scalar 2 6)))
      (HAL:debug (strcat "  Punkt=(" (rtos px 2 4) " " (rtos py 2 4) ")"))
      
      (if (or (< scalar -0.5) (> scalar 1.5))
        (princ (strcat "\n  Hinweis: Hoehe " (HAL:format-height target-height) " liegt ausserhalb der Strecke (Extrapolation)"))
      )
      
      (list px py 0.0)
    )
  )
)

;;; Erzeugt eine XLINE (Konstruktionslinie) im rechten Winkel zur Linie PF1-PF2
;;; durch einen gegebenen Punkt
;;;
;;; Parameter:
;;;   base-pt - Durchgangspunkt (Liste x y z)
;;;   pf1 - Fixpunkt 1 (fuer Richtungsberechnung)
;;;   pf2 - Fixpunkt 2 (fuer Richtungsberechnung)
;;;
;;; Rueckgabe:
;;;   Entity-Name der XLINE oder nil bei Fehler
(defun HAL:create-perp-xline (base-pt pf1 pf2 / dx dy perp-dx perp-dy len ent base-pt-wcs dir-bks dir-wcs)
  (HAL:debug "=== HAL:create-perp-xline ===")
  (HAL:debug (strcat "  base-pt(BKS)=(" (rtos (car base-pt) 2 4) " " (rtos (cadr base-pt) 2 4) ")"))
  
  ;; Richtungsvektor PF1->PF2 (XY, in BKS)
  (setq dx (- (car pf2) (car pf1)))
  (setq dy (- (cadr pf2) (cadr pf1)))
  
  ;; Normalvektor (90 Grad gedreht): (-dy, dx)
  (setq perp-dx (- dy))
  (setq perp-dy dx)
  
  ;; Normieren auf Einheitsvektor
  (setq len (sqrt (+ (expt perp-dx 2) (expt perp-dy 2))))
  
  (if (< len 0.0001)
    (progn
      (HAL:debug "  *** Fehler: Richtungsvektor hat Laenge 0 ***")
      nil
    )
    (progn
      (setq perp-dx (/ perp-dx len))
      (setq perp-dy (/ perp-dy len))
      
      ;; KRITISCH: BKS -> WKS transformieren!
      ;; entmakex DXF 10/11 erwarten WKS-Koordinaten!
      (setq base-pt-wcs (trans (list (car base-pt) (cadr base-pt) 0.0) 1 0))
      
      ;; Richtungsvektor transformieren (als Vektor, nicht als Punkt!)
      ;; trans mit 0->0 und T-Flag fuer Vektoren (displacement)
      (setq dir-bks (list perp-dx perp-dy 0.0))
      (setq dir-wcs (trans dir-bks 1 0 T))  ; T = displacement/Vektor
      
      (HAL:debug (strcat "  Normalvektor(BKS)=(" (rtos perp-dx 2 6) " " (rtos perp-dy 2 6) ")"))
      (HAL:debug (strcat "  base-pt(WKS)=(" (rtos (car base-pt-wcs) 2 4) " " (rtos (cadr base-pt-wcs) 2 4) ")"))
      (HAL:debug (strcat "  dir(WKS)=(" (rtos (car dir-wcs) 2 6) " " (rtos (cadr dir-wcs) 2 6) ")"))
      
      ;; XLINE erzeugen mit entmakex
      ;; DXF 10 = Basispunkt (WKS), DXF 11 = Richtungsvektor (WKS)
      (setq ent (entmakex
        (list
          '(0 . "XLINE")
          '(100 . "AcDbEntity")
          '(67 . 0)
          '(8 . "0")           ; Layer 0
          '(62 . 1)            ; Farbe Rot (gut sichtbar)
          '(100 . "AcDbXline")
          (cons 10 base-pt-wcs)    ; Basispunkt in WKS
          (cons 11 dir-wcs)        ; Richtungsvektor in WKS
        )
      ))
      
      (if ent
        (progn
          (HAL:debug (strcat "  XLINE erstellt: " (vl-princ-to-string ent)))
          ent
        )
        (progn
          (HAL:debug "  *** XLINE Erstellung fehlgeschlagen ***")
          (princ "\n*** Fehler beim Erstellen der Konstruktionslinie ***")
          nil
        )
      )
    )
  )
)

;;; Loescht eine XLINE Entity (falls vorhanden)
(defun HAL:delete-xline (ent / )
  (if (and ent (entget ent))
    (progn
      (entdel ent)
      (HAL:debug "  XLINE geloescht")
      T
    )
    nil
  )
)

;;; Fragt Zielhoehe und erstellt/aktualisiert Konstruktionslinie
;;; Loescht vorherige XLINE falls vorhanden
;;; Verlaengert die gelbe Linie A-B falls Zielhoehe ausserhalb liegt
;;;
;;; Parameter:
;;;   pf1, height1, pf2, height2 - Fixpunkte
;;;   current-xline - Entity-Name der aktuellen XLINE (oder nil)
;;;   line-ab - Entity-Name der gelben Linie A-B (oder nil)
;;;
;;; Rueckgabe:
;;;   Liste (new-xline updated-line-ab) 
(defun HAL:update-construction-line (pf1 height1 pf2 height2 current-xline line-ab / target-height base-pt new-xline prompt scalar ent-data)
  ;; Vorherige XLINE loeschen
  (if current-xline
    (HAL:delete-xline current-xline)
  )
  
  ;; Zielhoehe abfragen
  (setq prompt "\nZielhoehe fuer Konstruktionslinie eingeben: ")
  (setq target-height (getreal prompt))
  
  (if (null target-height)
    (progn
      (princ "\n  Keine Hoehe eingegeben - keine Konstruktionslinie")
      (list nil line-ab)
    )
    (progn
      ;; Punkt auf der Linie fuer diese Hoehe berechnen
      (setq base-pt (HAL:calc-point-for-height pf1 height1 pf2 height2 target-height))
      
      (if base-pt
        (progn
          ;; XLINE im rechten Winkel erstellen
          (setq new-xline (HAL:create-perp-xline base-pt pf1 pf2))
          
          (if new-xline
            (princ (strcat "\n  Konstruktionslinie bei Hoehe " (HAL:format-height target-height)
                           " | Punkt=(" (rtos (car base-pt) 2 2) ", " (rtos (cadr base-pt) 2 2) ")"))
          )
          
          ;; Gelbe Linie A-B verlaengern wenn Zielhoehe ausserhalb liegt
          ;; Scalar: 0=bei A, 1=bei B, <0=vor A, >1=nach B
          (setq scalar (/ (- target-height height1) (- height2 height1)))
          (HAL:debug (strcat "  Konstruktions-Scalar=" (rtos scalar 2 6)))
          
          (if (and line-ab (or (< scalar 0.0) (> scalar 1.0)))
            (progn
              (HAL:debug "  Linie A-B wird verlaengert bis Konstruktionspunkt")
              ;; Alte Linie loeschen
              (entdel line-ab)
              ;; Neue Linie erstellen: 
              ;; Wenn scalar < 0 -> Punkt liegt vor A -> Linie von base-pt bis B
              ;; Wenn scalar > 1 -> Punkt liegt nach B -> Linie von A bis base-pt
              (setq line-ab (entmakex
                (list
                  '(0 . "LINE")
                  '(100 . "AcDbEntity")
                  '(8 . "0")
                  '(62 . 2)       ; Farbe Gelb
                  '(100 . "AcDbLine")
                  (cons 10 (if (< scalar 0.0)
                             (trans base-pt 1 0)     ; Start = Konstruktionspunkt
                             (trans pf1 1 0)))        ; Start = A
                  (cons 11 (if (> scalar 1.0)
                             (trans base-pt 1 0)     ; Ende = Konstruktionspunkt
                             (trans pf2 1 0)))        ; Ende = B
                )
              ))
              (if line-ab
                (HAL:debug "  Linie A-B verlaengert")
                (HAL:debug "  *** Linie A-B Verlaengerung fehlgeschlagen ***")
              )
            )
            ;; Innerhalb A-B: Linie auf Original zuruecksetzen
            (if line-ab
              (progn
                (entdel line-ab)
                (setq line-ab (entmakex
                  (list
                    '(0 . "LINE")
                    '(100 . "AcDbEntity")
                    '(8 . "0")
                    '(62 . 2)
                    '(100 . "AcDbLine")
                    (cons 10 (trans pf1 1 0))
                    (cons 11 (trans pf2 1 0))
                  )
                ))
              )
            )
          )
          
          (list new-xline line-ab)
        )
        (list nil line-ab)  ; Berechnung fehlgeschlagen
      )
    )
  )
)

;;; Validiert ob Punkt gueltig ist
(defun HAL:valid-point-p (pt)
  (HAL:debug (strcat "HAL:valid-point-p: pt=" (vl-princ-to-string pt)))
  (HAL:debug (strcat "  pt ist nil? " (if (null pt) "JA" "NEIN")))
  (if pt
    (progn
      (HAL:debug (strcat "  listp? " (if (listp pt) "JA" "NEIN")))
      (if (listp pt)
        (progn
          (HAL:debug (strcat "  length=" (itoa (length pt))))
          (if (= (length pt) 3)
            (progn
              (HAL:debug (strcat "  numberp(car)=" (if (numberp (car pt)) "JA" "NEIN")))
              (HAL:debug (strcat "  numberp(cadr)=" (if (numberp (cadr pt)) "JA" "NEIN")))
              (HAL:debug (strcat "  numberp(caddr)=" (if (numberp (caddr pt)) "JA" "NEIN")))
            )
          )
        )
      )
    )
  )
  
  (and pt
       (listp pt)
       (= (length pt) 3)
       (numberp (car pt))
       (numberp (cadr pt))
       (numberp (caddr pt)))
)

;;; Validiert ob Hoehenwert gueltig ist
(defun HAL:valid-height-p (height)
  (and height
       (numberp height))
)

;;; Holt Hoehenwert mit Validierung und Default
(defun HAL:get-validated-height (prompt default / height)
  (if default
    (setq prompt (strcat prompt " <" (HAL:format-height default) ">: "))
    (setq prompt (strcat prompt ": "))
  )
  
  (setq height (getreal prompt))
  
  (HAL:debug (strcat "HAL:get-validated-height: height=" (if height (rtos height 2 4) "nil") " default=" (if default (rtos default 2 4) "nil")))
  
  ;; Falls ENTER gedrueckt: Default verwenden
  (if (null height)
    (if default
      (progn
        (setq height default)
        (HAL:debug (strcat "  Verwende Default: " (rtos height 2 4)))
      )
      ;; Kein Default: Nochmal fragen
      (progn
        (while (null height)
          (princ "\n*** Bitte geben Sie eine Hoehe ein ***")
          (setq height (getreal (strcat prompt ": ")))
        )
      )
    )
  )
  
  ;; Validierung
  (if (HAL:valid-height-p height)
    height
    nil
  )
)

;;; Fragt Benutzer nach XY-Skalierung und speichert in Config
(defun HAL:get-scale ( / scaleValue prompt current-scale)
  ;; Aktuelle Skalierung aus Config lesen
  (setq current-scale (HAL:read-scale-config))
  
  (setq prompt (strcat "\nNeue XY-Skalierung" 
                       (if current-scale 
                         (strcat " <" (rtos current-scale 2 2) ">") 
                         " <1.0>") 
                       ": "))
  
  (setq scaleValue (getreal prompt))
  
  ;; Wenn ENTER gedrueckt
  (if (null scaleValue)
    (if current-scale
      (setq scaleValue current-scale)
      (setq scaleValue 1.0)
    )
  )
  
  ;; Validierung: Skalierung muss > 0 sein
  (if (<= scaleValue 0.0)
    (progn
      (princ "\n*** Skalierung muss groesser als 0 sein! Verwende 1.0 ***")
      (setq scaleValue 1.0)
    )
  )
  
  ;; Skalierung in Config speichern
  (HAL:save-scale-config scaleValue)
  (princ (strcat "\n Skalierung gespeichert: " (rtos scaleValue 2 2)))
  
  scaleValue
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - BLOCK EINFUEGEN
;;; ============================================================================

;;; Fuegt Hoehenkoten-Block an gegebenem Punkt mit Hoehe und Skalierung ein
;;; Parameter:
;;;   einfuegepunkt - XYZ Punkt (Liste)
;;;   hoehe - Hoehenwert (Zahl)
;;;   scale - XY-Skalierung (Zahl)
;;;   skip-if-exists - T = Nicht einfuegen wenn Block schon existiert (fuer Fixpunkte)
;;;                    nil = Immer einfuegen (fuer Zwischenpunkte)
(defun HAL:insert-block (einfuegepunkt hoehe scale skip-if-exists / blockName heightStr old-attdia block-available importEnt ent attribs insertionPoint)
  (setq blockName *HAL:blockname*)
  
  (HAL:debug "=== HAL:insert-block ===")
  (HAL:debug (strcat "  einfuegepunkt=(" (rtos (car einfuegepunkt) 2 4) " " (rtos (cadr einfuegepunkt) 2 4) " " (rtos (caddr einfuegepunkt) 2 4) ")"))
  (HAL:debug (strcat "  hoehe=" (rtos hoehe 2 4)))
  (HAL:debug (strcat "  scale=" (rtos scale 2 4)))
  (HAL:debug (strcat "  skip-if-exists=" (if skip-if-exists "T" "nil")))
  (HAL:debug (strcat "  blockName=" blockName))
  
  ;; Parameter-Pruefung
  (if (and (HAL:valid-point-p einfuegepunkt) (HAL:valid-height-p hoehe) scale)
    (progn
      (HAL:debug "  Parameter-Pruefung: OK")
      
      ;; NEU: Pruefe ob Block bereits existiert (nur wenn skip-if-exists = T)
      (if (and skip-if-exists (HAL:block-exists-at-position einfuegepunkt hoehe blockName))
        (progn
          (HAL:debug "  >>> Block existiert bereits - UEBERSPRUNGEN")
          (princ (strcat "\n  Block existiert bereits: " (HAL:format-height-value hoehe) " | Z=" (rtos hoehe 2 3)))
          nil  ; Kein Block eingefuegt
        )
        (progn
          (HAL:debug "  Block wird eingefuegt...")
          
          ;; BESTEHENDER CODE: Block verfuegbar machen
          (setq block-available (ensure-block-available blockName))
          (HAL:debug (strcat "  ensure-block-available Ergebnis: car=" (if (car block-available) "T" "nil")))
          
          (if (car block-available)
            (progn
              (setq importEnt (cadr block-available))
              (HAL:debug (strcat "  importEnt=" (if importEnt (vl-princ-to-string importEnt) "nil")))
              
              ;; Hoehe formatieren
              (setq heightStr (HAL:format-height-value hoehe))
              (HAL:debug (strcat "  heightStr=" heightStr))
              
              ;; ATTDIA sichern
              (setq old-attdia (getvar "ATTDIA"))
              (setvar "ATTDIA" 0)
              
              ;; Block einfuegen MIT XY-SKALIERUNG
              (HAL:debug (strcat "  _-insert: blockName=" blockName " scale=" (rtos scale 2 4)))
              (command "_-insert" blockName einfuegepunkt scale scale "" "")
              
              ;; Pruefe ob command erfolgreich war
              (setq ent (entlast))
              (HAL:debug (strcat "  entlast nach insert: " (if ent (vl-princ-to-string ent) "nil")))
              
              (if ent
                (HAL:debug (strcat "  entlast Typ: " (cdr (assoc 0 (entget ent)))))
              )
              
              ;; ATTDIA wiederherstellen
              (setvar "ATTDIA" old-attdia)
              
              ;; Attribute setzen
              (if (and ent (eq (cdr (assoc 0 (entget ent))) "INSERT"))
                (progn
                  (HAL:debug "  Block INSERT gefunden - setze Attribute...")
                  (setq attribs (entnext ent))
                  (while (and attribs (eq (cdr (assoc 0 (entget attribs))) "ATTRIB"))
                    (HAL:debug (strcat "    Attribut: " (cdr (assoc 2 (entget attribs))) " = " (cdr (assoc 1 (entget attribs)))))
                    (if (eq (cdr (assoc 2 (entget attribs))) "HOEHE")
                      (progn
                        (HAL:debug (strcat "    >>> Setze HOEHE auf: " heightStr))
                        (entmod (subst (cons 1 heightStr) (assoc 1 (entget attribs)) (entget attribs)))
                      )
                    )
                    (setq attribs (entnext attribs))
                  )
                )
                (progn
                  (HAL:debug "  *** entlast ist KEIN INSERT! Block-Einfuegung moeglicherweise fehlgeschlagen!")
                )
              )
              
              ;; Block auf Hoehe verschieben
              (setq insertionPoint (cdr (assoc 10 (entget ent))))
              (HAL:debug (strcat "  insertionPoint=(" (rtos (car insertionPoint) 2 4) " " (rtos (cadr insertionPoint) 2 4) " " (rtos (caddr insertionPoint) 2 4) ")"))
              (HAL:debug (strcat "  move to Z=" (rtos hoehe 2 4)))
              
              (command "_move" ent "" "_non" insertionPoint "_non" 
                       (list (car insertionPoint) (cadr insertionPoint) hoehe))
              
              ;; Pruefe Position nach Move
              (setq insertionPoint (cdr (assoc 10 (entget ent))))
              (HAL:debug (strcat "  Position nach Move=(" (rtos (car insertionPoint) 2 4) " " (rtos (cadr insertionPoint) 2 4) " " (rtos (caddr insertionPoint) 2 4) ")"))
              
              ;; Import-Block entfernen
              (if importEnt
                (progn
                  (HAL:debug "  Entferne importEnt...")
                  (entdel importEnt)
                )
              )
              
              (princ (strcat "\n  Hoehenkote gesetzt: " heightStr " | Z=" (rtos hoehe 2 3) " | XY-Scale=" (rtos scale 2 2)))
              T
            )
            (progn
              (HAL:debug "  *** ensure-block-available FEHLGESCHLAGEN!")
              (princ "\n*** FEHLER: Block konnte nicht geladen werden ***")
              nil
            )
          )
        )
      )
    )
    (progn
      (HAL:debug (strcat "  *** Parameter-Pruefung FEHLGESCHLAGEN!"
                         " valid-point=" (if (HAL:valid-point-p einfuegepunkt) "T" "nil")
                         " valid-height=" (if (HAL:valid-height-p hoehe) "T" "nil")
                         " scale=" (if scale "OK" "nil")))
      (princ "\n*** Fehler: Ungueltige Parameter ***")
      nil
    )
  )
)

;;; ============================================================================
;;; BEFEHLE
;;; ============================================================================

;;; Hauptbefehl: Hoeheninterpolation entlang Linie
(defun c:HoeheAufLinie ( / *error* old-cmdecho old-attdia pf1 height1 pf2 height2 pg interpolated-height scale current-xline line-ab result-list)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (progn
        (princ (strcat "\nFehler: " msg))
        (HAL:debug (strcat "*** ERROR: " msg " ***"))
      )
      (HAL:debug (strcat "Benutzer-Abbruch: " msg))
    )
    ;; Konstruktionslinien aufraeumen
    (if current-xline (HAL:delete-xline current-xline))
    (if line-ab (entdel line-ab))
    ;; Systemvariablen wiederherstellen
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-attdia (setvar "ATTDIA" old-attdia))
    (princ)
  )
  
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-attdia (getvar "ATTDIA"))
  
  ;; Systemvariablen setzen
  (setvar "CMDECHO" 0)      ;; Command-Echo aus
  (setvar "ATTDIA" 0)       ;; Attribut-Dialog aus
  ;; OSMODE wird NICHT geaendert - User braucht Objektfang fuer praezise Punktwahl!
  
  ;; Log-Datei starten (IMMER, jede Sitzung ueberschreibt vorherige)
  (HAL:log-start)
  
  ;; Hauptprogramm
  (princ "\n=== Hoeheninterpolation entlang Linie ===")
  (if *HAL:debug-mode* (princ "\n*** DEBUG-MODUS AKTIV ***"))
  (princ "\nSetzen Sie zwei Fixpunkte mit bekannten Hoehen.")
  (princ "\nDann koennen Sie beliebig viele Zwischenpunkte setzen.")
  
  ;; Skalierung laden oder initialisieren
  (setq scale (HAL:read-scale-config))
  (HAL:debug (strcat "Scale aus Config: " (if scale (rtos scale 2 4) "nil")))
  
  (if (null scale)
    (progn
      (princ "\n*** Keine Skalierung konfiguriert ***")
      (setq scale (HAL:get-scale))
    )
  )
  
  ;; Fixpunkt 1 mit Skalierungs-Option
  (princ "\n")
  (initget "Skalierung")
  (setq pf1 (getpoint (strcat "\nFixpunkt 1 waehlen (oder Skalierung <" (rtos scale 2 2) ">): ")))
  
  (HAL:debug (strcat "pf1 raw=" (vl-princ-to-string pf1)))
  
  ;; Pruefe ob Keyword "Skalierung" gewaehlt wurde
  (while (= pf1 "Skalierung")
    (setq scale (HAL:get-scale))
    (initget "Skalierung")
    (setq pf1 (getpoint (strcat "\nFixpunkt 1 waehlen (oder Skalierung <" (rtos scale 2 2) ">): ")))
    (HAL:debug (strcat "pf1 raw (nach Skalierung)=" (vl-princ-to-string pf1)))
  )
  
  (if (not (HAL:valid-point-p pf1))
    (progn
      (HAL:debug "pf1 ungueltig - Abbruch")
      (princ "\n*** Abbruch: Kein gueltiger Punkt gewaehlt ***")
    )
    (progn
      (HAL:debug (strcat "pf1 gueltig: (" (rtos (car pf1) 2 4) " " (rtos (cadr pf1) 2 4) " " (rtos (caddr pf1) 2 4) ")"))
      
      (setq height1 (HAL:get-validated-height "\nHoehe Fixpunkt 1 eingeben" *HAL:last-height*))
      
      (if (not height1)
        (princ "\n*** Abbruch: Keine gueltige Hoehe eingegeben ***")
        (progn
          (HAL:debug (strcat "height1=" (rtos height1 2 4)))
          (setq *HAL:last-height* height1)
          ;; NEU: T = skip-if-exists fuer Fixpunkte
          (HAL:insert-block pf1 height1 scale T)
          
          ;; Fixpunkt 2 mit Skalierungs-Option
          (princ "\n")
          (initget "Skalierung")
          (setq pf2 (getpoint (strcat "\nFixpunkt 2 waehlen (oder Skalierung <" (rtos scale 2 2) ">): ")))
          
          (HAL:debug (strcat "pf2 raw=" (vl-princ-to-string pf2)))
          
          ;; Pruefe ob Keyword "Skalierung" gewaehlt wurde
          (while (= pf2 "Skalierung")
            (setq scale (HAL:get-scale))
            (initget "Skalierung")
            (setq pf2 (getpoint (strcat "\nFixpunkt 2 waehlen (oder Skalierung <" (rtos scale 2 2) ">): ")))
            (HAL:debug (strcat "pf2 raw (nach Skalierung)=" (vl-princ-to-string pf2)))
          )
          
          (if (not (HAL:valid-point-p pf2))
            (progn
              (HAL:debug "pf2 ungueltig - Abbruch")
              (princ "\n*** Abbruch: Kein gueltiger Punkt gewaehlt ***")
            )
            (progn
              (HAL:debug (strcat "pf2 gueltig: (" (rtos (car pf2) 2 4) " " (rtos (cadr pf2) 2 4) " " (rtos (caddr pf2) 2 4) ")"))
              
              (setq height2 (HAL:get-validated-height "\nHoehe Fixpunkt 2 eingeben" *HAL:last-height*))
              
              (if (not height2)
                (princ "\n*** Abbruch: Keine gueltige Hoehe eingegeben ***")
                (progn
                  (HAL:debug (strcat "height2=" (rtos height2 2 4)))
                  (setq *HAL:last-height* height2)
                  ;; NEU: T = skip-if-exists fuer Fixpunkte
                  (HAL:insert-block pf2 height2 scale T)
                  
                  ;; Temporaere Linie A->B zeichnen (gelb, wird am Ende geloescht)
                  (setq line-ab (entmakex
                    (list
                      '(0 . "LINE")
                      '(100 . "AcDbEntity")
                      '(8 . "0")
                      '(62 . 2)       ; Farbe Gelb
                      '(100 . "AcDbLine")
                      (cons 10 (trans pf1 1 0))   ; Startpunkt BKS->WKS
                      (cons 11 (trans pf2 1 0))   ; Endpunkt BKS->WKS
                    )
                  ))
                  (if line-ab
                    (HAL:debug "Linie A-B erstellt (gelb)")
                    (HAL:debug "*** Linie A-B Erstellung fehlgeschlagen ***")
                  )
                  
                  ;; Schleife: Gesuchte Punkte mit Skalierungs- und Konstruktionslinien-Option
                  (princ "\n")
                  (princ "\n--- Zwischenpunkte setzen (K=Konstruktionslinie, S=Skalierung, ESC=Ende) ---")
                  
                  (setq current-xline nil)
                  
                  (initget "Skalierung Konstruktion")
                  (setq pg (getpoint (strcat "\nPunkt waehlen [Skalierung/Konstruktion] <" (rtos scale 2 2) ">: ")))
                  
                  (HAL:debug (strcat "pg raw=" (vl-princ-to-string pg)))
                  
                  (while pg
                    (cond
                      ;; Keyword "Skalierung" gewaehlt
                      ((= pg "Skalierung")
                       (setq scale (HAL:get-scale))
                      )
                      
                      ;; Keyword "Konstruktion" gewaehlt
                      ((= pg "Konstruktion")
                       (setq result-list 
                         (HAL:update-construction-line pf1 height1 pf2 height2 current-xline line-ab))
                       (setq current-xline (car result-list))
                       (setq line-ab (cadr result-list))
                      )
                      
                      ;; Normal: Punkt gewaehlt
                      (T
                       (HAL:debug (strcat "--- Zwischenpunkt-Berechnung ---"))
                       
                       (if (HAL:valid-point-p pg)
                         (progn
                           (HAL:debug (strcat "pg gueltig: (" (rtos (car pg) 2 4) " " (rtos (cadr pg) 2 4) " " (rtos (caddr pg) 2 4) ")"))
                           
                           (setq interpolated-height (HAL:calc-interpolated-height pf1 height1 pf2 height2 pg))
                           (HAL:debug (strcat "interpolated-height=" (if interpolated-height (rtos interpolated-height 2 4) "nil")))
                           
                           (princ (strcat "\n  Berechnete Hoehe: " (HAL:format-height interpolated-height)))
                           ;; nil = immer einfuegen fuer Zwischenpunkte
                           (HAL:insert-block pg interpolated-height scale nil)
                         )
                         (progn
                           (HAL:debug "pg UNGUELTIG - uebersprungen!")
                           (princ "\n*** Ungueltiger Punkt - uebersprungen ***")
                         )
                       )
                      )
                    )
                    
                    ;; Naechsten Punkt abfragen
                    (initget "Skalierung Konstruktion")
                    (setq pg (getpoint (strcat "\nPunkt waehlen [Skalierung/Konstruktion] <" (rtos scale 2 2) ">: ")))
                    (HAL:debug (strcat "pg raw (naechster)=" (vl-princ-to-string pg)))
                  )
                  
                  ;; Konstruktionslinien aufraeumen
                  (if current-xline (HAL:delete-xline current-xline))
                  (if line-ab (entdel line-ab))
                  
                  (princ "\n\n Hoeheninterpolation abgeschlossen.")
                )
              )
            )
          )
        )
      )
    )
  )
  
  ;; Cleanup
  (if current-xline (HAL:delete-xline current-xline))
  (if line-ab (entdel line-ab))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (if old-attdia (setvar "ATTDIA" old-attdia))
  
  (princ)
)

;;; Kurzbefehl
(defun c:HAL ()
  (c:HoeheAufLinie)
)

;;; Debug Command-Line Ausgabe ein/ausschalten
;;; Log-Datei wird IMMER geschrieben, unabhaengig von diesem Schalter
(defun c:HALDEBUG ()
  (setq *HAL:debug-mode* (not *HAL:debug-mode*))
  (princ (strcat "\nDebug Command-Line: " (if *HAL:debug-mode* "EIN" "AUS")))
  (princ (strcat "\nLog-Datei (immer aktiv): " *HAL:log-path*))
  (princ)
)

;;; Zeigt konfigurierten Block-Pfad
(defun c:ShowBlockPath ()
  (show-block-path)
)

;;; Loescht gespeicherten Pfad
(defun c:ResetBlockPath ()
  (reset-block-path)
)

;;; Block Import Manager
(defun c:ManageBlockImportHAL ()
  (manage-block-import "HoeheAufLinie")
)

;;; ============================================================================
;;; LADE-MELDUNG
;;; ============================================================================

(vl-load-com)
(princ "\nHoeheAufLinie.lsp v2.0.0 geladen.")
(princ "\nBefehle:")
(princ "\n  HoeheAufLinie (HAL)      - Hoeheninterpolation (S=Skalierung, K=Konstruktionslinie)")
(princ "\n  HALDEBUG                 - Debug ein/aus + Log-Datei")
(princ "\n  ManageBlockImportHAL     - Block-Verwaltung fuer HoeheAufLinie")
(princ "\n  ShowBlockPath            - Zeigt konfigurierten Block-Pfad")
(princ "\n  ResetBlockPath           - Loescht gespeicherten Pfad")
(princ (strcat "\n  Log-Pfad:                  " *HAL:log-path*))
(princ "\n")
(princ)

;;; Ende der Datei
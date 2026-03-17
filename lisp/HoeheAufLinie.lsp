;;; HoeheAufLinie.lsp
;;; Höheninterpolation entlang einer Linie zwischen zwei Fixpunkten
;;; Speziell für Leica-Vermessungsarbeiten
;;;
;;; Installation:
;;; 1. Diese Datei mit APPLOAD laden
;;; 2. Beim ersten Mal nach lib/BlockImport.lsp gefragt werden
;;; 3. Pfad wird gespeichert für zukünftige Sitzungen
;;;
;;; Verwendung:
;;; - Befehl: HoeheAufLinie (oder HAL)
;;; - Zwei Fixpunkte mit bekannten Höhen setzen
;;; - Beliebig viele Zwischenpunkte setzen mit automatisch interpolierter Höhe
;;; - ESC zum Beenden
;;;
;;; Version: 1.5.3-debug
;;; Datum: 2026-03-17
;;; Autor: Herbert Schrotter

;;; ============================================================================
;;; DEBUG-SYSTEM MIT LOG-DATEI
;;; ============================================================================

;; Debug-Modus: T = ein, nil = aus
(if (not (boundp '*hal-debug*))
  (setq *hal-debug* nil)
)

;; Log-Datei Handle (globl, bleibt offen während Debug-Sitzung)
(if (not (boundp '*hal-log-file*))
  (setq *hal-log-file* nil)
)

;; Log-Datei Pfad: lisp/log/ Ordner (abgeleitet von BlockImport.lsp Pfad)
;; *blockimport-lib-path* zeigt auf .../lisp/lib/BlockImport.lsp
;; → 1x vl-filename-directory = .../lisp/lib
;; → 2x vl-filename-directory = .../lisp
;; → + /log/ = .../lisp/log/
(setq *hal-log-dir*
  (if (and *blockimport-lib-path* (vl-filename-directory *blockimport-lib-path*))
    (strcat (vl-filename-directory (vl-filename-directory *blockimport-lib-path*)) "/log")
    ;; Fallback: Zeichnungs-Ordner
    (strcat (vl-string-right-trim "\\" (getvar "DWGPREFIX")) "/log")
  )
)

;; Ordner erstellen falls nicht vorhanden
(if (not (vl-file-directory-p *hal-log-dir*))
  (vl-mkdir *hal-log-dir*)
)

(setq *hal-log-path* (strcat *hal-log-dir* "/HoeheAufLinie_debug.log"))

;;; Öffnet Log-Datei (überschreibt vorherige Sitzung)
(defun hal-log-open ( / )
  ;; Falls noch offen: schließen
  (if *hal-log-file*
    (progn
      (close *hal-log-file*)
      (setq *hal-log-file* nil)
    )
  )
  ;; Neu öffnen im Write-Modus (überschreibt!)
  (if (vl-catch-all-error-p
        (setq *hal-log-file* (vl-catch-all-apply 'open (list *hal-log-path* "w"))))
    (progn
      (princ (strcat "\n*** Fehler: Log-Datei kann nicht geöffnet werden: " *hal-log-path* " ***"))
      (setq *hal-log-file* nil)
    )
    (progn
      ;; Header schreiben
      (write-line (strcat "=== HoeheAufLinie Debug Log ===" ) *hal-log-file*)
      (write-line (strcat "Datum: " (menucmd "M=$(edtime,0,DD.MO.YYYY HH:MM:SS)")) *hal-log-file*)
      (write-line (strcat "Zeichnung: " (getvar "DWGNAME")) *hal-log-file*)
      (write-line "===============================" *hal-log-file*)
      (write-line "" *hal-log-file*)
    )
  )
)

;;; Schließt Log-Datei sauber
(defun hal-log-close ( / )
  (if *hal-log-file*
    (progn
      (write-line "" *hal-log-file*)
      (write-line "=== Log Ende ===" *hal-log-file*)
      (close *hal-log-file*)
      (setq *hal-log-file* nil)
    )
  )
)

;;; Debug-Ausgabe: Command-Line + Log-Datei
;;; Gibt nur aus wenn *hal-debug* = T
(defun hal-debug (msg / line)
  (if *hal-debug*
    (progn
      (setq line (strcat "[DEBUG] " msg))
      ;; Command-Line Ausgabe
      (princ (strcat "\n  " line))
      ;; Log-Datei Ausgabe
      (if *hal-log-file*
        (write-line line *hal-log-file*)
      )
    )
  )
)

;;; ============================================================================
;;; BIBLIOTHEKEN LADEN
;;; ============================================================================

;; Config-Datei für BlockImport.lsp Pfad
(setq *hal-config-file* 
  (if (getenv "APPDATA")
    (strcat (getenv "APPDATA") "/AutoCAD/HoeheAufLinieConfig.txt")
    "C:/Temp/HoeheAufLinieConfig.txt"
  )
)

;;; Liest gespeicherten BlockImport.lsp Pfad aus Config
(defun read-blockimport-path ( / file path version)
  (setq path nil)
  
  ;; Prüfe ob Config-Datei existiert
  (if (not (findfile *hal-config-file*))
    nil  ;; Datei existiert nicht
    ;; Versuche Datei zu öffnen mit Error-Handling
    (if (vl-catch-all-error-p
          (setq file (vl-catch-all-apply 'open (list *hal-config-file* "r"))))
      (progn
        (princ (strcat "\n*** Fehler beim Öffnen der Config-Datei: " *hal-config-file* " ***"))
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
  (setq dir (vl-filename-directory *hal-config-file*))
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
        (setq file (vl-catch-all-apply 'open (list *hal-config-file* "w"))))
    (progn
      (princ (strcat "\n*** Fehler beim Schreiben der Config-Datei: " *hal-config-file* " ***"))
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
    
    ;; Öffne File-Dialog
    (if (setq *blockimport-lib-path* 
          (getfiled "BlockImport.lsp auswählen" 
                    ;; Start-Ordner: Zeichnungs-Verzeichnis oder User-Profile
                    (cond
                      ((getvar "DWGPREFIX"))
                      ((getenv "USERPROFILE"))
                      (T "")
                    )
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

;; Block-Import Context für dieses Script (NACH dem Laden setzen!)
(setq *block-import-context* "HoeheAufLinie")

;; Name des Höhenkoten-Blocks
(setq *hoehenkote-blockname* "BLK_Hoehenkote")

;; Config-Datei für XY-Skalierung
(setq *scale-config-file* 
  (if (getenv "APPDATA")
    (strcat (getenv "APPDATA") "/AutoCAD/HoeheAufLinieScale.txt")
    "C:/Temp/HoeheAufLinieScale.txt"
  )
)

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

;; Speichert die zuletzt eingegebene Höhe für Default-Vorschlag
;; Wird über Sessions hinweg NICHT gespeichert (nur im RAM)
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
;;; HILFSFUNKTIONEN - BLOCK-PRÜFUNG
;;; ============================================================================

;;; Prüft ob Block bereits nahe dieser Position+Höhe existiert
;;; Verwendet distance-Funktion statt einzelner Koordinaten-Checks
;;; WICHTIG: Transformiert BKS→WKS für korrekten Vergleich!
;;; 
;;; Parameter:
;;;   pt - Punkt (Liste x y z) in BKS-Koordinaten
;;;   height - Höhe (Zahl)
;;;   blockname - Block-Name (String)
;;; 
;;; Rückgabe:
;;;   T wenn Block existiert, nil sonst
;;; 
;;; Toleranzen:
;;;   XY-Ebene: 0.05 Einheiten (5cm) - fängt auch Attribut-Klicks
;;;   Z-Höhe: 0.001 Einheiten (1mm) - präzise Höhenprüfung
(defun block-exists-at-position (pt height blockname / ss i ent inspt pt-wcs tolerance-xy tolerance-z dist-xy dist-z found)
  (setq tolerance-xy 0.05)   ; 5cm Toleranz für XY (OSNAP kann Attribut fangen)
  (setq tolerance-z 0.001)   ; 1mm Toleranz für Z (präzise Höhe)
  (setq found nil)
  
  ;; KRITISCH: Transformiere Punkt von BKS zu WKS
  ;; Block-Einfügepunkte (DXF 10) sind IMMER in WKS!
  ;; getpoint gibt BKS-Koordinaten zurück!
  (setq pt-wcs (trans pt 1 0))  ; 1=UCS(BKS), 0=WCS
  
  (hal-debug (strcat "block-exists-at-position: blockname=" blockname))
  (hal-debug (strcat "  pt(BKS)=(" (rtos (car pt) 2 4) " " (rtos (cadr pt) 2 4) " " (rtos (caddr pt) 2 4) ")"))
  (hal-debug (strcat "  pt(WKS)=(" (rtos (car pt-wcs) 2 4) " " (rtos (cadr pt-wcs) 2 4) " " (rtos (caddr pt-wcs) 2 4) ")"))
  (hal-debug (strcat "  height=" (rtos height 2 4)))
  
  ;; Suche alle Blöcke mit diesem Namen
  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 blockname))))
  
  (if ss
    (progn
      (hal-debug (strcat "  Gefundene Blöcke: " (itoa (sslength ss))))
      (setq i 0)
      (while (and (< i (sslength ss)) (not found))
        (setq ent (ssname ss i))
        (setq inspt (cdr (assoc 10 (entget ent))))
        
        ;; Berechne XY-Abstand mit distance (2D) - WKS zu WKS!
        (setq dist-xy (distance (list (car pt-wcs) (cadr pt-wcs)) 
                                (list (car inspt) (cadr inspt))))
        
        ;; Berechne Z-Abstand
        (setq dist-z (abs (- height (caddr inspt))))
        
        (hal-debug (strcat "  Block[" (itoa i) "] inspt=(" 
                           (rtos (car inspt) 2 4) " " (rtos (cadr inspt) 2 4) " " (rtos (caddr inspt) 2 4) 
                           ") dist-xy=" (rtos dist-xy 2 4) " dist-z=" (rtos dist-z 2 4)))
        
        ;; Prüfe beide Abstände
        (if (and (< dist-xy tolerance-xy)
                 (< dist-z tolerance-z))
          (progn
            (hal-debug "  >>> MATCH GEFUNDEN - Block existiert bereits!")
            (setq found T)
          )
        )
        
        (setq i (1+ i))
      )
      
      (if (not found)
        (hal-debug "  Kein Match gefunden")
      )
      
      found
    )
    (progn
      (hal-debug "  Keine Blöcke mit diesem Namen in Zeichnung")
      nil
    )
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - MATHEMATIK
;;; ============================================================================

;;; Berechnet interpolierte Höhe für Punkt auf Linie zwischen zwei Fixpunkten
;;; Verwendet Skalarprojektion - funktioniert auch für Punkte außerhalb der Strecke
;;; 
;;; Parameter:
;;;   pf1 - Fixpunkt 1 (Liste x y z)
;;;   height1 - Höhe bei Fixpunkt 1 (Zahl)
;;;   pf2 - Fixpunkt 2 (Liste x y z)
;;;   height2 - Höhe bei Fixpunkt 2 (Zahl)
;;;   pg - Gesuchter Punkt (Liste x y z)
;;; 
;;; Rückgabe:
;;;   Interpolierte Höhe (Zahl)
;;;   
;;; Funktioniert für:
;;;   - Punkte zwischen PF1 und PF2 (0 < scalar < 1)
;;;   - Punkte links von PF1 (scalar < 0) → Extrapolation
;;;   - Punkte rechts von PF2 (scalar > 1) → Extrapolation
(defun calculate-interpolated-height (pf1 height1 pf2 height2 pg / vpf vpg scalar dist-pf1-pf2 height-diff interpolated-height)
  (hal-debug "=== calculate-interpolated-height ===")
  (hal-debug (strcat "  pf1=(" (rtos (car pf1) 2 4) " " (rtos (cadr pf1) 2 4) " " (rtos (caddr pf1) 2 4) ") h1=" (rtos height1 2 4)))
  (hal-debug (strcat "  pf2=(" (rtos (car pf2) 2 4) " " (rtos (cadr pf2) 2 4) " " (rtos (caddr pf2) 2 4) ") h2=" (rtos height2 2 4)))
  (hal-debug (strcat "  pg=(" (rtos (car pg) 2 4) " " (rtos (cadr pg) 2 4) " " (rtos (caddr pg) 2 4) ")"))
  
  ;; Vektor von pf1 zu pf2 (nur XY-Ebene)
  (setq vpf (list (- (car pf2) (car pf1)) 
                  (- (cadr pf2) (cadr pf1))))
  
  ;; Vektor von pf1 zu pg (nur XY-Ebene)
  (setq vpg (list (- (car pg) (car pf1)) 
                  (- (cadr pg) (cadr pf1))))
  
  (hal-debug (strcat "  vpf=(" (rtos (car vpf) 2 4) " " (rtos (cadr vpf) 2 4) ")"))
  (hal-debug (strcat "  vpg=(" (rtos (car vpg) 2 4) " " (rtos (cadr vpg) 2 4) ")"))
  
  ;; 2D-Distanz PF1-PF2 (nur XY!) für Division-by-Zero Check
  ;; WICHTIG: distance() rechnet 3D wenn Punkte Z-Werte haben!
  ;; Wir brauchen NUR die XY-Distanz, daher aus vpf-Vektor berechnen
  (setq dist-pf1-pf2 (sqrt (+ (expt (car vpf) 2) (expt (cadr vpf) 2))))
  (hal-debug (strcat "  dist-2D(pf1,pf2)=" (rtos dist-pf1-pf2 2 6)))
  
  (if (< dist-pf1-pf2 0.0001)
    (progn
      (hal-debug "  *** WARNUNG: PF1 und PF2 zu nahe beieinander! Division by zero vermieden ***")
      (princ "\n*** WARNUNG: Fixpunkte haben gleiche XY-Position! ***")
      height1  ; Fallback: Höhe von PF1
    )
    (progn
      ;; Skalarprojektion: Wie weit liegt pg auf der Linie pf1-pf2?
      ;; Scalar = 0.0 bei pf1, 1.0 bei pf2, <0 links von pf1, >1 rechts von pf2
      (setq scalar (/ (+ (* (car vpg) (car vpf)) 
                         (* (cadr vpg) (cadr vpf))) 
                      (expt dist-pf1-pf2 2)))
      
      ;; Höhendifferenz zwischen Fixpunkten
      (setq height-diff (- height2 height1))
      
      ;; Interpolierte Höhe berechnen
      (setq interpolated-height (+ height1 (* scalar height-diff)))
      
      (hal-debug (strcat "  scalar=" (rtos scalar 2 6)))
      (hal-debug (strcat "  height-diff=" (rtos height-diff 2 4)))
      (hal-debug (strcat "  interpolated-height=" (rtos interpolated-height 2 4)))
      
      (if (or (< scalar -0.1) (> scalar 1.1))
        (hal-debug (strcat "  *** HINWEIS: Punkt liegt ausserhalb der Strecke (Extrapolation)! ***"))
      )
      
      interpolated-height
    )
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - INPUT-VALIDIERUNG
;;; ============================================================================

;;; Validiert ob Punkt gültig ist
(defun valid-point-p (pt)
  (hal-debug (strcat "valid-point-p: pt=" (vl-princ-to-string pt)))
  (hal-debug (strcat "  pt ist nil? " (if (null pt) "JA" "NEIN")))
  (if pt
    (progn
      (hal-debug (strcat "  listp? " (if (listp pt) "JA" "NEIN")))
      (if (listp pt)
        (progn
          (hal-debug (strcat "  length=" (itoa (length pt))))
          (if (= (length pt) 3)
            (progn
              (hal-debug (strcat "  numberp(car)=" (if (numberp (car pt)) "JA" "NEIN")))
              (hal-debug (strcat "  numberp(cadr)=" (if (numberp (cadr pt)) "JA" "NEIN")))
              (hal-debug (strcat "  numberp(caddr)=" (if (numberp (caddr pt)) "JA" "NEIN")))
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

;;; Validiert ob Höhenwert gültig ist
(defun valid-height-p (height)
  (and height
       (numberp height))
)

;;; Holt Höhenwert mit Validierung und Default
(defun get-validated-height (prompt default / height)
  (if default
    (setq prompt (strcat prompt " <" (format-height default) ">: "))
    (setq prompt (strcat prompt ": "))
  )
  
  (setq height (getreal prompt))
  
  (hal-debug (strcat "get-validated-height: height=" (if height (rtos height 2 4) "nil") " default=" (if default (rtos default 2 4) "nil")))
  
  ;; Falls ENTER gedrückt: Default verwenden
  (if (null height)
    (if default
      (progn
        (setq height default)
        (hal-debug (strcat "  Verwende Default: " (rtos height 2 4)))
      )
      ;; Kein Default: Nochmal fragen
      (progn
        (while (null height)
          (princ "\n*** Bitte geben Sie eine Höhe ein ***")
          (setq height (getreal (strcat prompt ": ")))
        )
      )
    )
  )
  
  ;; Validierung
  (if (valid-height-p height)
    height
    nil
  )
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
;;; HILFSFUNKTIONEN - BLOCK EINFÜGEN
;;; ============================================================================

;;; Fügt Höhenkoten-Block an gegebenem Punkt mit Höhe und Skalierung ein
;;; Parameter:
;;;   einfuegepunkt - XYZ Punkt (Liste)
;;;   hoehe - Höhenwert (Zahl)
;;;   scale - XY-Skalierung (Zahl)
;;;   skip-if-exists - T = Nicht einfügen wenn Block schon existiert (für Fixpunkte)
;;;                    nil = Immer einfügen (für Zwischenpunkte)
(defun insert-hoehenkote-block (einfuegepunkt hoehe scale skip-if-exists / blockName heightStr old-attdia block-available importEnt ent attribs insertionPoint)
  (setq blockName *hoehenkote-blockname*)
  
  (hal-debug "=== insert-hoehenkote-block ===")
  (hal-debug (strcat "  einfuegepunkt=(" (rtos (car einfuegepunkt) 2 4) " " (rtos (cadr einfuegepunkt) 2 4) " " (rtos (caddr einfuegepunkt) 2 4) ")"))
  (hal-debug (strcat "  hoehe=" (rtos hoehe 2 4)))
  (hal-debug (strcat "  scale=" (rtos scale 2 4)))
  (hal-debug (strcat "  skip-if-exists=" (if skip-if-exists "T" "nil")))
  (hal-debug (strcat "  blockName=" blockName))
  
  ;; Parameter-Prüfung
  (if (and (valid-point-p einfuegepunkt) (valid-height-p hoehe) scale)
    (progn
      (hal-debug "  Parameter-Prüfung: OK")
      
      ;; NEU: Prüfe ob Block bereits existiert (nur wenn skip-if-exists = T)
      (if (and skip-if-exists (block-exists-at-position einfuegepunkt hoehe blockName))
        (progn
          (hal-debug "  >>> Block existiert bereits - ÜBERSPRUNGEN")
          (princ (strcat "\n  ✓ Block existiert bereits: " (format-height-value hoehe) " | Z=" (rtos hoehe 2 3)))
          nil  ; Kein Block eingefügt
        )
        (progn
          (hal-debug "  Block wird eingefügt...")
          
          ;; BESTEHENDER CODE: Block verfügbar machen
          (setq block-available (ensure-block-available blockName))
          (hal-debug (strcat "  ensure-block-available Ergebnis: car=" (if (car block-available) "T" "nil")))
          
          (if (car block-available)
            (progn
              (setq importEnt (cadr block-available))
              (hal-debug (strcat "  importEnt=" (if importEnt (vl-princ-to-string importEnt) "nil")))
              
              ;; Höhe formatieren
              (setq heightStr (format-height-value hoehe))
              (hal-debug (strcat "  heightStr=" heightStr))
              
              ;; ATTDIA sichern
              (setq old-attdia (getvar "ATTDIA"))
              (setvar "ATTDIA" 0)
              
              ;; Block einfügen MIT XY-SKALIERUNG
              (hal-debug (strcat "  _-insert: blockName=" blockName " scale=" (rtos scale 2 4)))
              (command "_-insert" blockName einfuegepunkt scale scale "" "")
              
              ;; Prüfe ob command erfolgreich war
              (setq ent (entlast))
              (hal-debug (strcat "  entlast nach insert: " (if ent (vl-princ-to-string ent) "nil")))
              
              (if ent
                (hal-debug (strcat "  entlast Typ: " (cdr (assoc 0 (entget ent)))))
              )
              
              ;; ATTDIA wiederherstellen
              (setvar "ATTDIA" old-attdia)
              
              ;; Attribute setzen
              (if (and ent (eq (cdr (assoc 0 (entget ent))) "INSERT"))
                (progn
                  (hal-debug "  Block INSERT gefunden - setze Attribute...")
                  (setq attribs (entnext ent))
                  (while (and attribs (eq (cdr (assoc 0 (entget attribs))) "ATTRIB"))
                    (hal-debug (strcat "    Attribut: " (cdr (assoc 2 (entget attribs))) " = " (cdr (assoc 1 (entget attribs)))))
                    (if (eq (cdr (assoc 2 (entget attribs))) "HOEHE")
                      (progn
                        (hal-debug (strcat "    >>> Setze HOEHE auf: " heightStr))
                        (entmod (subst (cons 1 heightStr) (assoc 1 (entget attribs)) (entget attribs)))
                      )
                    )
                    (setq attribs (entnext attribs))
                  )
                )
                (progn
                  (hal-debug "  *** entlast ist KEIN INSERT! Block-Einfügung möglicherweise fehlgeschlagen!")
                )
              )
              
              ;; Block auf Höhe verschieben
              (setq insertionPoint (cdr (assoc 10 (entget ent))))
              (hal-debug (strcat "  insertionPoint=(" (rtos (car insertionPoint) 2 4) " " (rtos (cadr insertionPoint) 2 4) " " (rtos (caddr insertionPoint) 2 4) ")"))
              (hal-debug (strcat "  move to Z=" (rtos hoehe 2 4)))
              
              (command "_move" ent "" "_non" insertionPoint "_non" 
                       (list (car insertionPoint) (cadr insertionPoint) hoehe))
              
              ;; Prüfe Position nach Move
              (setq insertionPoint (cdr (assoc 10 (entget ent))))
              (hal-debug (strcat "  Position nach Move=(" (rtos (car insertionPoint) 2 4) " " (rtos (cadr insertionPoint) 2 4) " " (rtos (caddr insertionPoint) 2 4) ")"))
              
              ;; Import-Block entfernen
              (if importEnt
                (progn
                  (hal-debug "  Entferne importEnt...")
                  (entdel importEnt)
                )
              )
              
              (princ (strcat "\n  ✓ Höhenkote gesetzt: " heightStr " | Z=" (rtos hoehe 2 3) " | XY-Scale=" (rtos scale 2 2)))
              T
            )
            (progn
              (hal-debug "  *** ensure-block-available FEHLGESCHLAGEN!")
              (princ "\n*** FEHLER: Block konnte nicht geladen werden ***")
              nil
            )
          )
        )
      )
    )
    (progn
      (hal-debug (strcat "  *** Parameter-Prüfung FEHLGESCHLAGEN!"
                         " valid-point=" (if (valid-point-p einfuegepunkt) "T" "nil")
                         " valid-height=" (if (valid-height-p hoehe) "T" "nil")
                         " scale=" (if scale "OK" "nil")))
      (princ "\n*** Fehler: Ungültige Parameter ***")
      nil
    )
  )
)

;;; ============================================================================
;;; BEFEHLE
;;; ============================================================================

;;; Hauptbefehl: Höheninterpolation entlang Linie
(defun c:HoeheAufLinie ( / *error* old-cmdecho old-attdia pf1 height1 pf2 height2 pg interpolated-height scale)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (progn
        (princ (strcat "\nFehler: " msg))
        (hal-debug (strcat "*** ERROR: " msg " ***"))
      )
      (hal-debug (strcat "Benutzer-Abbruch: " msg))
    )
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
  ;; OSMODE wird NICHT geändert - User braucht Objektfang für präzise Punktwahl!
  
  ;; Hauptprogramm
  (princ "\n=== Höheninterpolation entlang Linie ===")
  (if *hal-debug* (princ "\n*** DEBUG-MODUS AKTIV ***"))
  (princ "\nSetzen Sie zwei Fixpunkte mit bekannten Höhen.")
  (princ "\nDann können Sie beliebig viele Zwischenpunkte setzen.")
  
  ;; Skalierung laden oder initialisieren
  (setq scale (read-scale-config))
  (hal-debug (strcat "Scale aus Config: " (if scale (rtos scale 2 4) "nil")))
  
  (if (null scale)
    (progn
      (princ "\n*** Keine Skalierung konfiguriert ***")
      (setq scale (getScale))
    )
  )
  
  ;; Fixpunkt 1 mit Skalierungs-Option
  (princ "\n")
  (initget "Skalierung")
  (setq pf1 (getpoint (strcat "\nFixpunkt 1 wählen (oder Skalierung <" (rtos scale 2 2) ">): ")))
  
  (hal-debug (strcat "pf1 raw=" (vl-princ-to-string pf1)))
  
  ;; Prüfe ob Keyword "Skalierung" gewählt wurde
  (while (= pf1 "Skalierung")
    (setq scale (getScale))
    (initget "Skalierung")
    (setq pf1 (getpoint (strcat "\nFixpunkt 1 wählen (oder Skalierung <" (rtos scale 2 2) ">): ")))
    (hal-debug (strcat "pf1 raw (nach Skalierung)=" (vl-princ-to-string pf1)))
  )
  
  (if (not (valid-point-p pf1))
    (progn
      (hal-debug "pf1 ungültig - Abbruch")
      (princ "\n*** Abbruch: Kein gültiger Punkt gewählt ***")
    )
    (progn
      (hal-debug (strcat "pf1 gültig: (" (rtos (car pf1) 2 4) " " (rtos (cadr pf1) 2 4) " " (rtos (caddr pf1) 2 4) ")"))
      
      (setq height1 (get-validated-height "\nHöhe Fixpunkt 1 eingeben" g_lastHeight))
      
      (if (not height1)
        (princ "\n*** Abbruch: Keine gültige Höhe eingegeben ***")
        (progn
          (hal-debug (strcat "height1=" (rtos height1 2 4)))
          (setq g_lastHeight height1)
          ;; NEU: T = skip-if-exists für Fixpunkte
          (insert-hoehenkote-block pf1 height1 scale T)
          
          ;; Fixpunkt 2 mit Skalierungs-Option
          (princ "\n")
          (initget "Skalierung")
          (setq pf2 (getpoint (strcat "\nFixpunkt 2 wählen (oder Skalierung <" (rtos scale 2 2) ">): ")))
          
          (hal-debug (strcat "pf2 raw=" (vl-princ-to-string pf2)))
          
          ;; Prüfe ob Keyword "Skalierung" gewählt wurde
          (while (= pf2 "Skalierung")
            (setq scale (getScale))
            (initget "Skalierung")
            (setq pf2 (getpoint (strcat "\nFixpunkt 2 wählen (oder Skalierung <" (rtos scale 2 2) ">): ")))
            (hal-debug (strcat "pf2 raw (nach Skalierung)=" (vl-princ-to-string pf2)))
          )
          
          (if (not (valid-point-p pf2))
            (progn
              (hal-debug "pf2 ungültig - Abbruch")
              (princ "\n*** Abbruch: Kein gültiger Punkt gewählt ***")
            )
            (progn
              (hal-debug (strcat "pf2 gültig: (" (rtos (car pf2) 2 4) " " (rtos (cadr pf2) 2 4) " " (rtos (caddr pf2) 2 4) ")"))
              
              (setq height2 (get-validated-height "\nHöhe Fixpunkt 2 eingeben" g_lastHeight))
              
              (if (not height2)
                (princ "\n*** Abbruch: Keine gültige Höhe eingegeben ***")
                (progn
                  (hal-debug (strcat "height2=" (rtos height2 2 4)))
                  (setq g_lastHeight height2)
                  ;; NEU: T = skip-if-exists für Fixpunkte
                  (insert-hoehenkote-block pf2 height2 scale T)
                  
                  ;; Schleife: Gesuchte Punkte mit Skalierungs-Option
                  (princ "\n")
                  (princ "\n--- Zwischenpunkte setzen (ESC = Ende) ---")
                  
                  (initget "Skalierung")
                  (setq pg (getpoint (strcat "\nGesuchten Punkt wählen (oder Skalierung/ESC <" (rtos scale 2 2) ">): ")))
                  
                  (hal-debug (strcat "pg raw=" (vl-princ-to-string pg)))
                  
                  (while pg
                    ;; Prüfe ob Keyword "Skalierung" gewählt wurde
                    (if (= pg "Skalierung")
                      (progn
                        (setq scale (getScale))
                        (initget "Skalierung")
                        (setq pg (getpoint (strcat "\nGesuchten Punkt wählen (oder Skalierung/ESC <" (rtos scale 2 2) ">): ")))
                        (hal-debug (strcat "pg raw (nach Skalierung)=" (vl-princ-to-string pg)))
                      )
                      ;; Normal: Punkt gewählt
                      (progn
                        (hal-debug (strcat "--- Zwischenpunkt-Berechnung ---"))
                        
                        (if (valid-point-p pg)
                          (progn
                            (hal-debug (strcat "pg gültig: (" (rtos (car pg) 2 4) " " (rtos (cadr pg) 2 4) " " (rtos (caddr pg) 2 4) ")"))
                            
                            (setq interpolated-height (calculate-interpolated-height pf1 height1 pf2 height2 pg))
                            (hal-debug (strcat "interpolated-height=" (if interpolated-height (rtos interpolated-height 2 4) "nil")))
                            
                            (princ (strcat "\n  Berechnete Höhe: " (format-height interpolated-height)))
                            ;; NEU: nil = immer einfügen für Zwischenpunkte
                            (insert-hoehenkote-block pg interpolated-height scale nil)
                          )
                          (progn
                            (hal-debug "pg UNGÜLTIG - übersprungen!")
                            (princ "\n*** Ungültiger Punkt - übersprungen ***")
                          )
                        )
                        ;; Nächsten Punkt abfragen
                        (initget "Skalierung")
                        (setq pg (getpoint (strcat "\nGesuchten Punkt wählen (oder Skalierung/ESC <" (rtos scale 2 2) ">): ")))
                        (hal-debug (strcat "pg raw (nächster)=" (vl-princ-to-string pg)))
                      )
                    )
                  )
                  
                  (princ "\n\n✓ Höheninterpolation abgeschlossen.")
                )
              )
            )
          )
        )
      )
    )
  )
  
  ;; Cleanup
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (if old-attdia (setvar "ATTDIA" old-attdia))
  
  (princ)
)

;;; Kurzbefehl
(defun c:HAL ()
  (c:HoeheAufLinie)
)

;;; Debug ein/ausschalten + Log-Datei öffnen/schließen
(defun c:HALDEBUG ()
  (setq *hal-debug* (not *hal-debug*))
  (if *hal-debug*
    (progn
      ;; Debug EIN: Log-Datei öffnen (überschreibt vorherige Sitzung)
      (hal-log-open)
      (princ (strcat "\nDebug-Modus: EIN"))
      (princ (strcat "\nLog-Datei: " *hal-log-path*))
    )
    (progn
      ;; Debug AUS: Log-Datei schließen
      (hal-log-close)
      (princ "\nDebug-Modus: AUS")
      (princ (strcat "\nLog gespeichert: " *hal-log-path*))
    )
  )
  (princ)
)

;;; Zeigt konfigurierten Block-Pfad
(defun c:ShowBlockPath ()
  (show-block-path)
)

;;; Löscht gespeicherten Pfad
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
(princ "\nHoeheAufLinie.lsp v1.5.3-debug geladen.")
(princ "\nBefehle:")
(princ "\n  HoeheAufLinie (HAL)      - Höheninterpolation entlang Linie (S für Skalierung)")
(princ "\n  HALDEBUG                 - Debug ein/aus + Log-Datei")
(princ "\n  ManageBlockImportHAL     - Block-Verwaltung für HoeheAufLinie")
(princ "\n  ShowBlockPath            - Zeigt konfigurierten Block-Pfad")
(princ "\n  ResetBlockPath           - Löscht gespeicherten Pfad")
(princ (strcat "\n  Log-Pfad:                  " *hal-log-path*))
(princ "\n")
(princ)

;;; Ende der Datei
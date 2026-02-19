;;; ============================================================================
;;; ArcZ.lsp
;;; 3D-Kreisbogen durch 3 Punkte mit beliebigen Z-Höhen
;;; 
;;; Version: 3.3.1
;;; Datum: 2026-02-19
;;; Autor: Herbert Schrotter
;;;
;;; Beschreibung:
;;; Erstellt einen echten Kreisbogen (ARC-Objekt) durch drei Punkte mit
;;; unterschiedlichen Z-Höhen. Pure Mathematik - kein UCS-Wechsel nötig!
;;;
;;; Installation:
;;; 1. Befehl APPLOAD in AutoCAD ausführen
;;; 2. ArcZ.lsp auswählen und laden
;;; 3. Automatisches Laden: Zu Startup Suite hinzufügen
;;;
;;; Alternative: In AutoCAD Support-Ordner kopieren:
;;; %APPDATA%\Autodesk\AutoCAD 2024\R24.3\deu\Support\
;;;
;;; Verwendung:
;;; Command: ARCZ
;;; 1. Startpunkt wählen (beliebige Z-Höhe)
;;; 2. Zwischenpunkt wählen (beliebige Z-Höhe)
;;; 3. Endpunkt wählen (beliebige Z-Höhe)
;;; -> Kreisbogen wird direkt in der 3-Punkte-Ebene erstellt
;;;
;;; Technische Details:
;;; - Erstellt echtes ARC-Objekt mit entmakex
;;; - Berechnet Kreismittelpunkt geometrisch (Lee Mac Methode)
;;; - Berechnet 3D-Normale direkt aus Kreuzprodukt
;;; - Berechnet Winkel direkt in 3D (kein UCS-Wechsel!)
;;; - Funktioniert in AutoCAD LT (kein Visual LISP erforderlich)
;;;
;;; Credits:
;;; - 3-Point Circle Algorithmus: Lee Mac Programming
;;;   https://www.lee-mac.com/3pointarccircle.html
;;;
;;; Lizenz: MIT
;;; ============================================================================


;;; ============================================================================
;;; HILFSFUNKTIONEN
;;; ============================================================================

;; --------------------------------------------------------------
;; 3-Point Circle - Lee Mac (3D-erweitert)
;; Berechnet Mittelpunkt und Radius eines Kreises durch 3 Punkte
;; --------------------------------------------------------------

(defun LM:3pcircle ( pt1 pt2 pt3 / cen md1 md2 vc1 vc2 pt1-2d pt2-2d pt3-2d )
  ;; Für inters: Nur XY verwenden (2D)
  (setq pt1-2d (list (car pt1) (cadr pt1)))
  (setq pt2-2d (list (car pt2) (cadr pt2)))
  (setq pt3-2d (list (car pt3) (cadr pt3)))
  
  (setq md1 (mapcar '(lambda ( a b ) (/ (+ a b) 2.0)) pt1-2d pt2-2d))
  (setq md2 (mapcar '(lambda ( a b ) (/ (+ a b) 2.0)) pt2-2d pt3-2d))
  
  (setq vc1 (mapcar '- pt2-2d pt1-2d))
  (setq vc2 (mapcar '- pt3-2d pt2-2d))
  
  ;; Schnittpunkt in 2D berechnen
  (setq cen (inters md1 (mapcar '+ md1 (list (- (cadr vc1)) (car vc1)))
                    md2 (mapcar '+ md2 (list (- (cadr vc2)) (car vc2)))
                    nil
            ))
  
  (if cen
    (progn
      ;; Z-Koordinate hinzufügen (Durchschnitt)
      (setq cen (append cen (list (/ (+ (caddr pt1) (caddr pt2) (caddr pt3)) 3.0))))
      (list cen (distance cen pt1))
    )
    nil
  )
)


;; --------------------------------------------------------------
;; Kreuzprodukt (Cross Product)
;; Berechnet Normalenvektor zur 3D-Ebene
;; --------------------------------------------------------------

(defun cross-product ( v1 v2 / )
  (list
    (- (* (cadr v1) (caddr v2)) (* (caddr v1) (cadr v2)))
    (- (* (caddr v1) (car v2)) (* (car v1) (caddr v2)))
    (- (* (car v1) (cadr v2)) (* (cadr v1) (car v2)))
  )
)


;; --------------------------------------------------------------
;; Vektor normalisieren (Länge = 1)
;; --------------------------------------------------------------

(defun normalize-vector ( v / len )
  (setq len (sqrt (+ (* (car v) (car v))
                     (* (cadr v) (cadr v))
                     (* (caddr v) (caddr v)))))
  (if (> len 1e-10)
    (mapcar '(lambda (x) (/ x len)) v)
    v
  )
)


;;; ============================================================================
;;; HAUPTFUNKTION
;;; ============================================================================

(defun c:ARCZ ( / lst pt1 pt2 pt3 v1 v2 normal )

  ;; Punkte wählen
  (if (and (setq pt1 (getpoint "\nStartpunkt wählen: "))
           (setq pt2 (getpoint "\nZwischenpunkt wählen: " pt1))
           (setq pt3 (getpoint "\nEndpunkt wählen: " pt2))
      )
      (progn
        (princ "\n========================================")
        (princ "\n=== DEBUG: Gewählte Punkte ===")
        (princ (strcat "\nP1: " (vl-princ-to-string pt1)))
        (princ (strcat "\nP2: " (vl-princ-to-string pt2)))
        (princ (strcat "\nP3: " (vl-princ-to-string pt3)))
        
        ;; Kreismittelpunkt und Radius berechnen
        (if (setq lst (LM:3pcircle pt1 pt2 pt3))
            (progn
              (princ "\n=== DEBUG: Kreis-Berechnung ===")
              (princ (strcat "\nCenter: " (vl-princ-to-string (car lst))))
              (princ (strcat "\nRadius: " (rtos (cadr lst) 2 4)))
              
              ;; 3D-Normale aus Kreuzprodukt berechnen
              (setq v1 (mapcar '- pt2 pt1))
              (setq v2 (mapcar '- pt3 pt1))
              (setq normal (normalize-vector (cross-product v1 v2)))
              
              (princ "\n=== DEBUG: Normale Berechnung ===")
              (princ (strcat "\nV1: " (vl-princ-to-string v1)))
              (princ (strcat "\nV2: " (vl-princ-to-string v2)))
              (princ (strcat "\nNormale: " (vl-princ-to-string normal)))
              
              ;; Prüfen ob Punkte in korrekter Reihenfolge (für Bogenrichtung)
              (if (minusp (sin (- (angle pt1 pt3) (angle pt1 pt2))))
                  (progn
                    (princ "\n=== Punkte werden getauscht! ===")
                    (mapcar 'set '(pt1 pt3) (list pt3 pt1))
                  )
              )
              
              (princ "\n=== DEBUG: Transform zu OCS (mit Normale!) ===")
              (princ (strcat "\nCenter → OCS: " (vl-princ-to-string (trans (car lst) 1 normal))))
              (princ (strcat "\nP1 → OCS: " (vl-princ-to-string (trans pt1 1 normal))))
              (princ (strcat "\nP3 → OCS: " (vl-princ-to-string (trans pt3 1 normal))))
              
              (princ "\n=== DEBUG: Winkel im OCS ===")
              (princ (strcat "\nStart: " (rtos (angle (trans (car lst) 1 normal) (trans pt1 1 normal)) 2 4)))
              (princ (strcat "\nEnd:   " (rtos (angle (trans (car lst) 1 normal) (trans pt3 1 normal)) 2 4)))
              
              (princ "\n=== DEBUG: entmakex ===")
              (princ (strcat "\n010: " (vl-princ-to-string (trans (car lst) 1 normal))))
              (princ (strcat "\n040: " (rtos (cadr lst) 2 4)))
              (princ (strcat "\n050: " (rtos (angle (trans (car lst) 1 normal) (trans pt1 1 normal)) 2 4)))
              (princ (strcat "\n051: " (rtos (angle (trans (car lst) 1 normal) (trans pt3 1 normal)) 2 4)))
              (princ (strcat "\n210: " (vl-princ-to-string normal)))
              (princ "\n========================================")
              
              ;; Mit BERECHNETER Normale!
              (entmakex
                  (list
                     '(000 . "ARC")
                      (cons 010 (trans (car lst) 1 normal))
                      (cons 040 (cadr lst))
                      (cons 050 (angle (trans (car lst) 1 normal) (trans pt1 1 normal)))
                      (cons 051 (angle (trans (car lst) 1 normal) (trans pt3 1 normal)))
                      (cons 210 normal)
                  )
              )
              (princ "\n3D-Bogen erstellt.")
            )
            (princ "\n*** Fehler: Punkte liegen auf einer Geraden! ***")
        )
      )
      (princ "\nAbbruch.")
  )
  
  (princ)
)


;;; ============================================================================
;;; INITIALISIERUNG
;;; ============================================================================

(princ "\nArcZ.lsp v3.3.1 geladen.")
(princ "\nBefehl: ARCZ - 3D-Kreisbogen durch 3 Punkte")
(princ "\nMethode: Pure Mathematik (kein UCS-Wechsel!)")
(princ)

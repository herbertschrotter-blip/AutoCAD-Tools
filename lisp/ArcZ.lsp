;;; ============================================================================
;;; ArcZ.lsp
;;; 3D-Kreisbogen durch 3 Punkte mit beliebigen Z-Höhen
;;; 
;;; Version: 1.3.0
;;; Datum: 2026-02-19
;;; Autor: Herbert Schrotter
;;;
;;; Beschreibung:
;;; Erstellt einen echten Kreisbogen (ARC-Objekt) durch drei Punkte mit
;;; unterschiedlichen Z-Höhen. Berechnet 3D-Ebene und verwendet entmakex.
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
;;; -> Kreisbogen wird in der 3-Punkte-Ebene erstellt
;;;
;;; Technische Details:
;;; - Erstellt echtes ARC-Objekt (kein Spline/Polylinie)
;;; - Berechnet Kreismittelpunkt geometrisch (Lee Mac Methode)
;;; - Berechnet 3D-Normale aus Kreuzprodukt der Vektoren
;;; - Verwendet entmakex statt command (schneller & zuverlässiger)
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
;; 3-Point Circle - Lee Mac (modifiziert für 3D)
;; Berechnet Mittelpunkt und Radius eines Kreises durch 3 Punkte
;; Parameter:
;;   pt1, pt2, pt3 - WCS Punkte (mit Z)
;; Rückgabe:
;;   Liste: (Mittelpunkt Radius) oder nil wenn kollinear
;; --------------------------------------------------------------

(defun LM:3pcircle ( pt1 pt2 pt3 / cen md1 md2 vc1 vc2 )
  ;; Mittelpunkte der Sehnen berechnen (in 3D)
  (if (setq md1 (mapcar '(lambda ( a b ) (/ (+ a b) 2.0)) pt1 pt2)
            md2 (mapcar '(lambda ( a b ) (/ (+ a b) 2.0)) pt2 pt3)
            ;; Vektoren der Sehnen (in 3D)
            vc1 (mapcar '- pt2 pt1)
            vc2 (mapcar '- pt3 pt2)
            ;; Schnittpunkt der Mittelsenkrechten = Kreismittelpunkt
            ;; WICHTIG: Nur XY für inters, dann Z interpolieren
            cen (inters (list (car md1) (cadr md1) 0)
                        (list (+ (car md1) (- (cadr vc1))) (+ (cadr md1) (car vc1)) 0)
                        (list (car md2) (cadr md2) 0)
                        (list (+ (car md2) (- (cadr vc2))) (+ (cadr md2) (car vc2)) 0)
                        nil
                )
      )
      (progn
        ;; Z-Koordinate des Mittelpunkts interpolieren (ersetze Z von inters)
        (setq cen (list (car cen) 
                        (cadr cen) 
                        (/ (+ (caddr pt1) (caddr pt2) (caddr pt3)) 3.0)))
        ;; Rückgabe: (Mittelpunkt Radius)
        (list cen (distance cen pt1))
      )
  )
)


;; --------------------------------------------------------------
;; Kreuzprodukt (Cross Product) für 3D-Normale
;; Parameter:
;;   v1, v2 - Vektoren als Listen (x y z)
;; Rückgabe:
;;   Normalenvektor senkrecht zu v1 und v2
;; --------------------------------------------------------------

(defun cross-product ( v1 v2 / )
  (list
    (- (* (cadr v1) (caddr v2)) (* (caddr v1) (cadr v2)))  ;; x
    (- (* (caddr v1) (car v2)) (* (car v1) (caddr v2)))    ;; y
    (- (* (car v1) (cadr v2)) (* (cadr v1) (car v2)))      ;; z
  )
)


;; --------------------------------------------------------------
;; Vektor normalisieren (Länge = 1)
;; --------------------------------------------------------------

(defun normalize-vector ( v / len )
  (setq len (sqrt (+ (* (car v) (car v))
                     (* (cadr v) (cadr v))
                     (* (caddr v) (caddr v)))))
  (if (> len 0.0)
    (mapcar '(lambda (x) (/ x len)) v)
    v
  )
)


;;; ============================================================================
;;; HAUPTFUNKTION
;;; ============================================================================

;; --------------------------------------------------------------
;; ARCZ - 3D-Kreisbogen durch 3 Punkte
;; Erstellt echten ARC in 3D-Ebene durch drei Punkte
;; Verwendet entmakex für zuverlässige Erstellung
;; --------------------------------------------------------------

(defun c:ARCZ ( / pt1 pt2 pt3 lst v1 v2 normal ang1 ang3)

  ;; Punkte wählen
  (if (and (setq pt1 (getpoint "\nStartpunkt wählen: "))
           (setq pt2 (getpoint "\nZwischenpunkt wählen: " pt1))
           (setq pt3 (getpoint "\nEndpunkt wählen: " pt2))
      )
      (progn
        ;; Kreismittelpunkt und Radius berechnen
        (if (setq lst (LM:3pcircle pt1 pt2 pt3))
            (progn
              ;; Vektoren für Normale berechnen
              (setq v1 (mapcar '- pt2 pt1))
              (setq v2 (mapcar '- pt3 pt1))
              
              ;; Normale (senkrecht zur 3-Punkte-Ebene)
              (setq normal (normalize-vector (cross-product v1 v2)))
              
              ;; Winkel von Mittelpunkt zu Start/Endpunkt berechnen
              ;; (in der 3D-Ebene, relativ zur Normalen)
              (setq ang1 (angle (list (car (car lst)) (cadr (car lst)))
                               (list (car pt1) (cadr pt1))))
              (setq ang3 (angle (list (car (car lst)) (cadr (car lst)))
                               (list (car pt3) (cadr pt3))))
              
              ;; Prüfen ob Punkte in korrekter Reihenfolge (für Bogenrichtung)
              (if (minusp (sin (- ang3 ang1)))
                  ;; Winkel tauschen wenn Bogen in falsche Richtung geht
                  (mapcar 'set '(ang1 ang3) (list ang3 ang1))
              )
              
              ;; ARC mit entmakex erstellen
              (entmakex
                  (list
                     '(000 . "ARC")                 ;; Entity-Typ
                      (cons 010 (car lst))          ;; Mittelpunkt (3D)
                      (cons 040 (cadr lst))         ;; Radius
                      (cons 050 ang1)               ;; Startwinkel
                      (cons 051 ang3)               ;; Endwinkel
                      (cons 210 normal)             ;; Normale (3D-Ebene)
                  )
              )
              (princ "\n3D-Bogen erstellt.")
            )
            ;; Fehler: Punkte sind kollinear (auf einer Geraden)
            (princ "\n*** Fehler: Punkte liegen auf einer Geraden! ***")
        )
      )
      ;; Benutzer hat ESC gedrückt
      (princ "\nAbbruch.")
  )
  
  (princ)
)


;;; ============================================================================
;;; INITIALISIERUNG
;;; ============================================================================

(princ "\nArcZ.lsp v1.3.0 geladen.")
(princ "\nBefehl: ARCZ - 3D-Kreisbogen durch 3 Punkte")
(princ "\nMethode: entmakex + 3D-Normale (Kreuzprodukt)")
(princ)
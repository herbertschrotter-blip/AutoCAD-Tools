;;; ============================================================================
;;; ArcZ.lsp
;;; 3D-Kreisbogen durch 3 Punkte mit beliebigen Z-Höhen
;;; 
;;; Version: 1.0.1
;;; Datum: 2026-02-19
;;; Autor: Herbert Schrotter
;;;
;;; Beschreibung:
;;; Erstellt einen echten Kreisbogen (ARC-Objekt) durch drei Punkte mit
;;; unterschiedlichen Z-Höhen. Nutzt temporäres UCS für die Bogen-Ebene.
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
;;; - Berechnet UCS-Ebene durch 3 Punkte
;;; - Stellt ursprüngliches UCS wieder her
;;; - Funktioniert in AutoCAD LT (kein Visual LISP erforderlich)
;;;
;;; Lizenz: MIT
;;; ============================================================================


;;; ============================================================================
;;; HAUPTFUNKTION
;;; ============================================================================

;; --------------------------------------------------------------
;; ARCZ - 3D-Kreisbogen durch 3 Punkte
;; Erstellt echten ARC in 3D-Ebene durch drei Punkte
;; Sichert und restauriert UCS
;; --------------------------------------------------------------

(defun c:ARCZ ( / p1 p2 p3 oldUCS)

  ;; Aktuelles UCS sichern
  (setq oldUCS (getvar "UCSNAME"))

  ;; Punkte wählen
  (princ "\nStartpunkt wählen...")
  (setq p1 (getpoint))

  (princ "\nZwischenpunkt wählen...")
  (setq p2 (getpoint))

  (princ "\nEndpunkt wählen...")
  (setq p3 (getpoint))

  ;; UCS auf 3-Punkte-Ebene setzen
  (command "_.UCS" "_3" p1 p2 p3)

  ;; 3-Punkte-Kreisbogen zeichnen
  (command "_.ARC" "_3P" p1 p2 p3)

  ;; UCS wiederherstellen
  (if oldUCS
    (command "_.UCS" oldUCS)   ;; Benanntes UCS zurück
    (command "_.UCS" "_W")     ;; Falls kein UCS benannt war → Welt
  )

  (princ "\n3D-Bogen erstellt – UCS wiederhergestellt.")
  (princ)
)


;;; ============================================================================
;;; INITIALISIERUNG
;;; ============================================================================

(princ "\nArcZ.lsp v1.0.1 geladen.")
(princ "\nBefehl: ARCZ - 3D-Kreisbogen durch 3 Punkte")
(princ)
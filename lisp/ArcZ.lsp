;;; ============================================================================
;;; ArcZ.lsp
;;; 3D-Kreisbogen durch 3 Punkte mit beliebigen Z-Höhen
;;; 
;;; Version: 3.1.0
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
;;; 4. Gleiche 3 Punkte nochmal für Bogen wählen
;;; -> Kreisbogen wird in der 3-Punkte-Ebene erstellt
;;;
;;; Technische Details:
;;; - Erstellt echtes ARC-Objekt (kein Spline/Polylinie)
;;; - Berechnet UCS-Ebene durch 3 Punkte
;;; - Punkte werden 2x gewählt (vor und nach UCS-Änderung)
;;; - Stellt ursprüngliches UCS automatisch wieder her
;;; - Funktioniert in AutoCAD LT (kein Visual LISP erforderlich)
;;; - Vollständige Fehlerbehandlung nach AutoLISP Best Practices
;;;
;;; Lizenz: MIT
;;; ============================================================================


;;; ============================================================================
;;; HAUPTFUNKTION
;;; ============================================================================

;; --------------------------------------------------------------
;; ARCZ - 3D-Kreisbogen durch 3 Punkte
;; Erstellt echten ARC in 3D-Ebene durch drei Punkte
;; Sichert und restauriert UCS mit Error-Handler
;; --------------------------------------------------------------

(defun c:ARCZ ( / *error* p1 p2 p3 oldUCS old-cmdecho ucs-changed)

  ;; Lokaler Error-Handler (ohne command!)
  (defun *error* (msg)
    ;; Nur echte Fehler melden (ESC und ENTER unterdrücken)
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\nFehler: " msg))
    )
    ;; UCS wiederherstellen wenn geändert
    (if ucs-changed
      (progn
        (if (= oldUCS "")
          (setvar "UCSNAME" "")
          (setvar "UCSNAME" oldUCS)
        )
        (command "_.UCS" "_W")  ;; Fallback zu World
      )
    )
    ;; Systemvariablen wiederherstellen
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )

  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  ;; Aktuelles UCS sichern
  (setq oldUCS (getvar "UCSNAME"))
  (setq ucs-changed nil)

  ;; Punkte wählen
  (if (and (setq p1 (getpoint "\nStartpunkt wählen: "))
           (setq p2 (getpoint "\nZwischenpunkt wählen: " p1))
           (setq p3 (getpoint "\nEndpunkt wählen: " p2))
      )
      (progn
        ;; UCS auf 3-Punkte-Ebene setzen
        (command "_.UCS" "_3" p1 p2 p3)
        (setq ucs-changed T)

        ;; ARC zeichnen - mit pause für User-Input
        (princ "\nJetzt Bogen zeichnen (gleiche 3 Punkte wählen):")
        (command "_.ARC" "_3P" pause pause pause)

        ;; UCS wiederherstellen
        (if (= oldUCS "")
          (command "_.UCS" "_W")
          (command "_.UCS" oldUCS)
        )
        (setq ucs-changed nil)

        (princ "\n3D-Bogen erstellt.")
      )
      ;; Benutzer hat ESC gedrückt
      (princ "\nAbbruch.")
  )

  ;; Systemvariablen wiederherstellen (bei normalem Ende)
  (setvar "CMDECHO" old-cmdecho)

  (princ)
)


;;; ============================================================================
;;; INITIALISIERUNG
;;; ============================================================================

(princ "\nArcZ.lsp v3.1.0 geladen.")
(princ "\nBefehl: ARCZ - 3D-Kreisbogen durch 3 Punkte")
(princ "\nHinweis: Punkte werden 2x gewählt (vor und nach UCS-Änderung)")
(princ)

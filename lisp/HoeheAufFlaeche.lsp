;;; HoeheAufFlaeche.lsp
;;; Höheninterpolation auf einer Fläche definiert durch 3-4 Eckpunkte
;;; Speziell für Leica-Vermessungsarbeiten
;;;
;;; Installation:
;;; 1. Diese Datei mit APPLOAD laden
;;; 2. Beim ersten Mal nach lib/BlockImport.lsp gefragt werden
;;; 3. Pfad wird gespeichert für zukünftige Sitzungen
;;;
;;; Verwendung:
;;; - Befehl: HoeheAufFlaeche (oder HAF)
;;; - 3 oder 4 Eckpunkte mit bekannten Höhen setzen
;;; - Beliebig viele Punkte innerhalb/außerhalb setzen
;;; - ESC zum Beenden
;;;
;;; Version: 1.3.0
;;; Datum: 2026-02-19
;;; Autor: Herbert Schrotter

;;; ============================================================================
;;; BIBLIOTHEKEN LADEN
;;; ============================================================================

;; Config-Datei für BlockImport.lsp Pfad
(setq *haf-config-file* 
  (if (getenv "APPDATA")
    (strcat (getenv "APPDATA") "/AutoCAD/HoeheAufFlaecheConfig.txt")
    "C:/Temp/HoeheAufFlaecheConfig.txt"
  )
)

;;; Liest gespeicherten BlockImport.lsp Pfad aus Config
(defun read-blockimport-path ( / file path version)
  (setq path nil)
  
  (if (not (findfile *haf-config-file*))
    nil
    (if (vl-catch-all-error-p
          (setq file (vl-catch-all-apply 'open (list *haf-config-file* "r"))))
      (progn
        (princ (strcat "\n*** Fehler beim Öffnen der Config-Datei: " *haf-config-file* " ***"))
        nil
      )
      (progn
        (setq version (read-line file))
        (setq path (read-line file))
        (close file)
        path
      )
    )
  )
)

;;; Speichert BlockImport.lsp Pfad in Config
(defun save-blockimport-path (filepath / file dir)
  (setq dir (vl-filename-directory *haf-config-file*))
  (if (not (vl-file-directory-p dir))
    (if (vl-catch-all-error-p (vl-catch-all-apply 'vl-mkdir (list dir)))
      (progn
        (princ (strcat "\n*** Fehler beim Erstellen des Config-Verzeichnis: " dir " ***"))
        nil
      )
      T
    )
  )
  
  (if (vl-catch-all-error-p
        (setq file (vl-catch-all-apply 'open (list *haf-config-file* "w"))))
    (progn
      (princ (strcat "\n*** Fehler beim Schreiben der Config-Datei: " *haf-config-file* " ***"))
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
  (setq *blockimport-lib-path* nil)
)

;; Wenn kein gültiger Pfad: Suche in Standard-Orten
(if (null *blockimport-lib-path*)
  (setq *blockimport-lib-path*
    (cond
      ((findfile "lib/BlockImport.lsp"))
      ((findfile "BlockImport.lsp"))
    )
  )
)

;; Wenn immer noch nicht gefunden: Bitte User um Auswahl
(if (null *blockimport-lib-path*)
  (progn
    (princ "\n*** BlockImport.lsp wird nicht im Support-Pfad gefunden ***")
    (princ "\nBitte wählen Sie die Datei lib/BlockImport.lsp aus...")
    
    (if (setq *blockimport-lib-path* 
          (getfiled "BlockImport.lsp auswählen" 
                    (cond
                      ((getvar "DWGPREFIX"))
                      ((getenv "USERPROFILE"))
                      (T "")
                    )
                    "lsp" 
                    0))
      (progn
        (princ (strcat "\nGewählte Datei: " *blockimport-lib-path*))
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

;; Block-Import Context für dieses Script
(setq *block-import-context* "HoeheAufFlaeche")

;; Name des Höhenkoten-Blocks
(setq *hoehenkote-blockname* "BLK_Hoehenkote")

;; Config-Datei für XY-Skalierung
(setq *scale-config-file* 
  (if (getenv "APPDATA")
    (strcat (getenv "APPDATA") "/AutoCAD/HoeheAufFlaecheScale.txt")
    "C:/Temp/HoeheAufFlaecheScale.txt"
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
;;; HILFSFUNKTIONEN - VISUALISIERUNG (TEMPORÄR)
;;; ============================================================================

;;; Zeichnet temporäre Polyline um Eckpunkte mit grdraw
;;; grdraw verschwindet automatisch bei (redraw) - kein Entity!
(defun draw-temp-boundary (points / i p1 p2)
  ;; Zeichne Linien zwischen allen Punkten
  (setq i 0)
  (while (< i (length points))
    (setq p1 (nth i points))
    (setq p2 (nth (rem (+ i 1) (length points)) points))  ;; Nächster Punkt (zyklisch)
    
    ;; Zeichne rote Linie mit grdraw (Farbe 1 = Rot)
    (grdraw p1 p2 1 0)
    
    (setq i (+ i 1))
  )
  T  ;; Rückgabe: erfolgreich
)

;;; Zeichnet temporäre Dreiecks-Linien mit grdraw
;;; grdraw verschwindet automatisch bei (redraw) - kein Entity!
(defun draw-temp-triangles (p1 p2 p3 p4 / )
  ;; Dreieck 1: p1-p2-p3 (grau gestrichelt)
  ;; Farbe 8 = grau, highlight=1 → gestrichelt
  (grdraw p1 p2 8 1)
  (grdraw p2 p3 8 1)
  (grdraw p3 p1 8 1)
  
  ;; Wenn 4 Punkte: Dreieck 2 und Trennlinie
  (if p4
    (progn
      (grdraw p1 p3 8 1)  ;; Trennlinie
      (grdraw p3 p4 8 1)
      (grdraw p4 p1 8 1)
    )
  )
  T  ;; Rückgabe: erfolgreich
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - MATHEMATIK (GEOMETRIE)
;;; ============================================================================

;;; Berechnet Höhe auf einer Ebene definiert durch 3 Punkte
;;; Verwendet Ebenengleichung: ax + by + cz = d
;;; 
;;; Parameter:
;;;   p1, p2, p3 - 3 Punkte die Ebene definieren (Listen x y z)
;;;   h1, h2, h3 - Höhen der 3 Punkte (Zahlen)
;;;   pg - Gesuchter Punkt (Liste x y z)
;;; 
;;; Rückgabe:
;;;   Interpolierte Höhe (Zahl) oder nil bei Fehler
(defun calculate-height-on-plane (p1 h1 p2 h2 p3 h3 pg / v1 v2 normal a b c d z)
  ;; Zwei Vektoren in der Ebene
  (setq v1 (list (- (car p2) (car p1))
                 (- (cadr p2) (cadr p1))
                 (- h2 h1)))
  
  (setq v2 (list (- (car p3) (car p1))
                 (- (cadr p3) (cadr p1))
                 (- h3 h1)))
  
  ;; Normalenvektor durch Kreuzprodukt
  (setq normal (list
    (- (* (cadr v1) (caddr v2)) (* (caddr v1) (cadr v2)))
    (- (* (caddr v1) (car v2)) (* (car v1) (caddr v2)))
    (- (* (car v1) (cadr v2)) (* (cadr v1) (car v2)))
  ))
  
  (setq a (car normal))
  (setq b (cadr normal))
  (setq c (caddr normal))
  
  ;; Prüfe ob Ebene nicht vertikal (c darf nicht 0 sein)
  (if (equal c 0.0 0.0001)
    (progn
      (princ "\n*** Fehler: Punkte sind kollinear oder Ebene ist vertikal ***")
      nil
    )
    (progn
      ;; d aus Punkt p1 berechnen
      (setq d (+ (* a (car p1)) (* b (cadr p1)) (* c h1)))
      
      ;; z für gesuchten Punkt berechnen: z = (d - ax - by) / c
      (setq z (/ (- d (* a (car pg)) (* b (cadr pg))) c))
      
      z
    )
  )
)

;;; Berechnet baryzentrische Koordinaten für Punkt in Dreieck
;;; 
;;; Parameter:
;;;   p1, p2, p3 - Eckpunkte des Dreiecks (Listen x y)
;;;   pg - Gesuchter Punkt (Liste x y)
;;; 
;;; Rückgabe:
;;;   Liste (u v w) oder nil wenn Punkt außerhalb
;;;   u + v + w = 1.0
(defun barycentric-coordinates (p1 p2 p3 pg / v0 v1 v2 dot00 dot01 dot02 dot11 dot12 inv-denom u v w)
  ;; Vektoren
  (setq v0 (list (- (car p3) (car p1)) (- (cadr p3) (cadr p1))))
  (setq v1 (list (- (car p2) (car p1)) (- (cadr p2) (cadr p1))))
  (setq v2 (list (- (car pg) (car p1)) (- (cadr pg) (cadr p1))))
  
  ;; Skalarprodukte
  (setq dot00 (+ (* (car v0) (car v0)) (* (cadr v0) (cadr v0))))
  (setq dot01 (+ (* (car v0) (car v1)) (* (cadr v0) (cadr v1))))
  (setq dot02 (+ (* (car v0) (car v2)) (* (cadr v0) (cadr v2))))
  (setq dot11 (+ (* (car v1) (car v1)) (* (cadr v1) (cadr v1))))
  (setq dot12 (+ (* (car v1) (car v2)) (* (cadr v1) (cadr v2))))
  
  ;; Baryzentrische Koordinaten berechnen
  (setq inv-denom (/ 1.0 (- (* dot00 dot11) (* dot01 dot01))))
  (setq v (* (- (* dot11 dot02) (* dot01 dot12)) inv-denom))
  (setq w (* (- (* dot00 dot12) (* dot01 dot02)) inv-denom))
  (setq u (- 1.0 v w))
  
  ;; Rückgabe: Liste (u v w)
  ;; WICHTIG: Auch wenn außerhalb - Extrapolation ist erlaubt!
  (list u v w)
)

;;; Berechnet Höhe in Dreieck mit baryzentrischen Koordinaten
;;; 
;;; Parameter:
;;;   p1, p2, p3 - Eckpunkte (Listen x y z)
;;;   h1, h2, h3 - Höhen (Zahlen)
;;;   pg - Gesuchter Punkt (Liste x y z)
;;; 
;;; Rückgabe:
;;;   Interpolierte Höhe (Zahl)
(defun calculate-height-in-triangle (p1 h1 p2 h2 p3 h3 pg / bary u v w height)
  ;; Baryzentrische Koordinaten berechnen
  (setq bary (barycentric-coordinates p1 p2 p3 pg))
  
  (if bary
    (progn
      (setq u (car bary))
      (setq v (cadr bary))
      (setq w (caddr bary))
      
      ;; Höhe = gewichtete Summe
      (setq height (+ (* u h1) (* v h2) (* w h3)))
      
      height
    )
    nil
  )
)

;;; Testet ob Punkt in Dreieck liegt (für Info-Ausgabe)
;;; 
;;; Parameter:
;;;   bary - Baryzentrische Koordinaten (u v w)
;;; 
;;; Rückgabe:
;;;   T wenn innerhalb, nil wenn außerhalb
(defun point-in-triangle-p (bary / u v w)
  (setq u (car bary))
  (setq v (cadr bary))
  (setq w (caddr bary))
  
  ;; Punkt ist innerhalb wenn alle Koordinaten >= 0
  (and (>= u 0.0) (>= v 0.0) (>= w 0.0))
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - INPUT-VALIDIERUNG
;;; ============================================================================

;;; Validiert ob Punkt gültig ist
(defun valid-point-p (pt)
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
  
  (if (null height)
    (if default
      (setq height default)
      (progn
        (while (null height)
          (princ "\n*** Bitte geben Sie eine Höhe ein ***")
          (setq height (getreal (strcat prompt ": ")))
        )
      )
    )
  )
  
  (if (valid-height-p height)
    height
    nil
  )
)

;;; Fragt Benutzer nach XY-Skalierung und speichert in Config
(defun getScale ( / scaleValue prompt current-scale)
  (setq current-scale (read-scale-config))
  
  (setq prompt (strcat "\nNeue XY-Skalierung" 
                       (if current-scale 
                         (strcat " <" (rtos current-scale 2 2) ">") 
                         " <1.0>") 
                       ": "))
  
  (setq scaleValue (getreal prompt))
  
  (if (null scaleValue)
    (if current-scale
      (setq scaleValue current-scale)
      (setq scaleValue 1.0)
    )
  )
  
  (if (<= scaleValue 0.0)
    (progn
      (princ "\n*** Skalierung muss größer als 0 sein! Verwende 1.0 ***")
      (setq scaleValue 1.0)
    )
  )
  
  (save-scale-config scaleValue)
  (princ (strcat "\n✓ Skalierung gespeichert: " (rtos scaleValue 2 2)))
  
  scaleValue
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - BLOCK EINFÜGEN
;;; ============================================================================

;;; Fügt Höhenkoten-Block an gegebenem Punkt mit Höhe und Skalierung ein
;;; Rückgabe: Entity-Name des eingefügten Blocks oder nil bei Fehler
(defun insert-hoehenkote-block (einfuegepunkt hoehe scale / blockName heightStr old-attdia block-available importEnt ent attribs insertionPoint)
  (setq blockName *hoehenkote-blockname*)
  
  (if (and (valid-point-p einfuegepunkt) (valid-height-p hoehe) scale)
    (progn
      (setq block-available (ensure-block-available blockName))
      
      (if (car block-available)
        (progn
          (setq importEnt (cadr block-available))
          (setq heightStr (format-height-value hoehe))
          
          (setq old-attdia (getvar "ATTDIA"))
          (setvar "ATTDIA" 0)
          
          (command "_-insert" blockName einfuegepunkt scale scale "" "")
          
          (setvar "ATTDIA" old-attdia)
          
          (setq ent (entlast))
          (if (and ent (eq (cdr (assoc 0 (entget ent))) "INSERT"))
            (progn
              (setq attribs (entnext ent))
              (while (and attribs (eq (cdr (assoc 0 (entget attribs))) "ATTRIB"))
                (if (eq (cdr (assoc 2 (entget attribs))) "HOEHE")
                  (entmod (subst (cons 1 heightStr) (assoc 1 (entget attribs)) (entget attribs)))
                )
                (setq attribs (entnext attribs))
              )
            )
          )
          
          (setq insertionPoint (cdr (assoc 10 (entget ent))))
          (command "_move" ent "" "_non" insertionPoint "_non" 
                   (list (car insertionPoint) (cadr insertionPoint) hoehe))
          
          (if importEnt
            (entdel importEnt)
          )
          
          ent  ;; Rückgabe: Entity-Name des Blocks
        )
        (progn
          (princ "\n*** FEHLER: Block konnte nicht geladen werden ***")
          nil
        )
      )
    )
    (progn
      (princ "\n*** Fehler: Ungültige Parameter ***")
      nil
    )
  )
)

;;; ============================================================================
;;; BEFEHLE
;;; ============================================================================

;;; Hauptbefehl: Höheninterpolation auf Fläche
(defun c:HoeheAufFlaeche ( / *error* old-cmdecho old-attdia 
                           corner-points corner-heights corner-entities corner-number done
                           p1 h1 p2 h2 p3 h3 p4 h4
                           num-corners pg interpolated-height scale
                           bary inside tri-info
                           pt ht prompt-str block-ent last-ent)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\nFehler: " msg))
    )
    ;; Redraw löscht automatisch alle grdraw-Linien
    (redraw)
    ;; Systemvariablen wiederherstellen
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-attdia (setvar "ATTDIA" old-attdia))
    (princ)
  )
  
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-attdia (getvar "ATTDIA"))
  
  (setvar "CMDECHO" 0)
  (setvar "ATTDIA" 0)
  
  ;; Listen für Eckpunkte
  (setq corner-points nil)
  (setq corner-heights nil)
  
  ;; Skalierung laden oder initialisieren
  (setq scale (read-scale-config))
  (if (null scale)
    (progn
      (princ "\n*** Keine Skalierung konfiguriert ***")
      (setq scale (getScale))
    )
  )
  
  ;; Hauptprogramm
  (princ "\n=== Höheninterpolation auf Fläche ===")
  (princ "\nSetzen Sie 3 oder 4 Eckpunkte mit bekannten Höhen.")
  (princ "\nDann können Sie beliebig viele Punkte setzen.")
  
  ;; Skalierung laden oder initialisieren
  (setq scale (read-scale-config))
  (if (null scale)
    (progn
      (princ "\n*** Keine Skalierung konfiguriert ***")
      (setq scale (getScale))
    )
  )
  
  ;; ======================================================================
  ;; ECKPUNKTE SAMMELN (mit Zurück-Option)
  ;; ======================================================================
  
  (setq corner-points nil)
  (setq corner-heights nil)
  (setq corner-entities nil)  ;; Speichert Entity-Namen der eingefügten Blocks
  (setq corner-number 1)
  (setq done nil)
  
  (while (and (not done) (< corner-number 5))
    (princ "\n")
    
    ;; Keyword-String für initget
    (if (> corner-number 1)
      (initget "Skalierung Zurueck")
      (initget "Skalierung")
    )
    
    ;; Prompt-String
    (setq prompt-str 
      (strcat "\nEckpunkt " (itoa corner-number) " wählen (oder "))
    
    (if (> corner-number 1)
      (setq prompt-str (strcat prompt-str "[Z]urück/"))
    )
    
    (setq prompt-str (strcat prompt-str "[S]kalierung"))
    
    (if (>= corner-number 4)
      (setq prompt-str (strcat prompt-str "/ENTER=Fertig"))
    )
    
    (setq prompt-str (strcat prompt-str " <" (rtos scale 2 2) ">): "))
    
    ;; Punkt abfragen
    (setq pt (getpoint prompt-str))
    
    (cond
      ;; Skalierung ändern
      ((= pt "Skalierung")
       (setq scale (getScale))
      )
      
      ;; Zurück
      ((= pt "Zurueck")
       (if (> corner-number 1)
         (progn
           ;; Letzten Block löschen
           (setq last-ent (last corner-entities))
           (if last-ent
             (entdel last-ent)
           )
           
           ;; Letzten Punkt entfernen
           (setq corner-points (reverse (cdr (reverse corner-points))))
           (setq corner-heights (reverse (cdr (reverse corner-heights))))
           (setq corner-entities (reverse (cdr (reverse corner-entities))))
           (setq corner-number (- corner-number 1))
           (princ (strcat "\n  ← Eckpunkt " (itoa corner-number) " entfernt (Block gelöscht)"))
         )
         (princ "\n*** Kein Punkt zum Entfernen vorhanden ***")
       )
      )
      
      ;; ENTER bei >= 3 Punkten → Fertig
      ((and (null pt) (>= corner-number 4))
       (setq done T)
       (princ "\n  ✓ Eckpunkte-Eingabe abgeschlossen")
      )
      
      ;; Gültiger Punkt
      ((valid-point-p pt)
       (setq ht (get-validated-height (strcat "\nHöhe Eckpunkt " (itoa corner-number) " eingeben") g_lastHeight))
       
       (if ht
         (progn
           (setq g_lastHeight ht)
           (setq block-ent (insert-hoehenkote-block pt ht scale))
           
           (if block-ent
             (progn
               (princ (strcat "\n  ✓ Eckpunkt " (itoa corner-number) " gesetzt"))
               
               ;; Zu Listen hinzufügen
               (setq corner-points (append corner-points (list pt)))
               (setq corner-heights (append corner-heights (list ht)))
               (setq corner-entities (append corner-entities (list block-ent)))
               (setq corner-number (+ corner-number 1))
               
               ;; Bei 3 Punkten: Optional fertig
               (if (= corner-number 4)
                 (princ "\n  (Sie können ENTER drücken oder einen 4. Punkt setzen)")
               )
             )
             (princ "\n*** Fehler beim Block-Einfügen - Punkt übersprungen ***")
           )
         )
         (princ "\n*** Ungültige Höhe - Punkt übersprungen ***")
       )
      )
      
      ;; ESC oder ungültiger Punkt
      (T
       (if (< corner-number 4)
         (progn
           (princ "\n*** Abbruch: Mindestens 3 Eckpunkte erforderlich ***")
           (setq done T)
           (setq corner-points nil)  ;; Abbruch
         )
         (setq done T)
       )
      )
    )
  )
  
  ;; ======================================================================
  ;; NUR WEITERMACHEN WENN GENUG ECKPUNKTE
  ;; ======================================================================
  
  (if (>= (length corner-points) 3)
    (progn
      ;; Anzahl Eckpunkte
      (setq num-corners (length corner-points))
      (princ (strcat "\n\n✓ " (itoa num-corners) " Eckpunkte definiert"))
      
      (if (= num-corners 3)
        (princ "\n  Methode: Ebenengleichung (1 Dreieck)")
        (princ "\n  Methode: Triangulation (2 Dreiecke)")
      )
      
      ;; Punkte für einfachen Zugriff
      (setq p1 (nth 0 corner-points))
      (setq h1 (nth 0 corner-heights))
      (setq p2 (nth 1 corner-points))
      (setq h2 (nth 1 corner-heights))
      (setq p3 (nth 2 corner-points))
      (setq h3 (nth 2 corner-heights))
      
      (if (= num-corners 4)
        (progn
          (setq p4 (nth 3 corner-points))
          (setq h4 (nth 3 corner-heights))
        )
      )
      
      ;; ====================================================================
      ;; TEMPORÄRE VISUALISIERUNG ZEICHNEN (mit grdraw)
      ;; ====================================================================
      
      (princ "\n  Zeichne Flächen-Begrenzung...")
      (draw-temp-boundary corner-points)
      
      (princ "\n  Zeichne Dreiecks-Netz...")
      (draw-temp-triangles p1 p2 p3 p4)
      
      (princ "\n  ✓ Visualisierung aktiv (verschwindet bei REDRAW)")
      
      ;; Schleife: Gesuchte Punkte
      (princ "\n")
      (princ "\n--- Gesuchte Punkte setzen (ESC = Ende) ---")
      
      (initget "Skalierung")
      (setq pg (getpoint (strcat "\nPunkt wählen (oder [S]kalierung/ESC <" (rtos scale 2 2) ">): ")))
      
      (while pg
        (if (= pg "Skalierung")
          (progn
            (setq scale (getScale))
            (initget "Skalierung")
            (setq pg (getpoint (strcat "\nPunkt wählen (oder [S]kalierung/ESC <" (rtos scale 2 2) ">): ")))
          )
          (progn
            (if (valid-point-p pg)
              (progn
                ;; Höhe berechnen je nach Anzahl Eckpunkte
                (if (= num-corners 3)
                  ;; 3 Punkte: Einfache Ebenengleichung
                  (progn
                    (setq interpolated-height 
                      (calculate-height-on-plane p1 h1 p2 h2 p3 h3 pg))
                    (setq tri-info "Ebene 1-2-3")
                  )
                  ;; 4 Punkte: 2 Dreiecke
                  (progn
                    ;; Dreieck 1: p1-p2-p3
                    (setq bary (barycentric-coordinates p1 p2 p3 pg))
                    (setq inside (point-in-triangle-p bary))
                    
                    (if inside
                      ;; Punkt in Dreieck 1
                      (progn
                        (setq interpolated-height 
                          (calculate-height-in-triangle p1 h1 p2 h2 p3 h3 pg))
                        (setq tri-info "Dreieck 1-2-3")
                      )
                      ;; Versuche Dreieck 2: p1-p3-p4
                      (progn
                        (setq interpolated-height 
                          (calculate-height-in-triangle p1 h1 p3 h3 p4 h4 pg))
                        (setq tri-info "Dreieck 1-3-4")
                      )
                    )
                  )
                )
                
                (if interpolated-height
                  (progn
                    (princ (strcat "\n  Berechnete Höhe: " (format-height interpolated-height) " (" tri-info ")"))
                    (insert-hoehenkote-block pg interpolated-height scale)
                    (princ (strcat "  | XY-Scale=" (rtos scale 2 2)))
                  )
                  (princ "\n*** Fehler bei Höhenberechnung ***")
                )
              )
              (princ "\n*** Ungültiger Punkt - übersprungen ***")
            )
            
            (initget "Skalierung")
            (setq pg (getpoint (strcat "\nPunkt wählen (oder [S]kalierung/ESC <" (rtos scale 2 2) ">): ")))
          )
        )
      )
      
      (princ "\n\n✓ Höheninterpolation abgeschlossen.")
      
      ;; ====================================================================
      ;; REDRAW LÖSCHT AUTOMATISCH ALLE grdraw-LINIEN
      ;; ====================================================================
      (princ "\n  Lösche temporäre Visualisierung...")
      (redraw)
      (princ " ✓")
    )
  )
  
  ;; Cleanup
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (if old-attdia (setvar "ATTDIA" old-attdia))
  
  (princ)
)

;;; Kurzbefehl
(defun c:HAF ()
  (c:HoeheAufFlaeche)
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
(defun c:ManageBlockImportHAF ()
  (manage-block-import "HoeheAufFlaeche")
)

;;; ============================================================================
;;; LADE-MELDUNG
;;; ============================================================================

(vl-load-com)
(princ "\nHoeheAufFlaeche.lsp v1.3.0 geladen.")
(princ "\nBefehle:")
(princ "\n  HoeheAufFlaeche (HAF)    - Höheninterpolation auf Fläche (S/Z)")
(princ "\n                             Temporäre Visualisierung mit grdraw")
(princ "\n  ManageBlockImportHAF     - Block-Verwaltung für HoeheAufFlaeche")
(princ "\n  ShowBlockPath            - Zeigt konfigurierten Block-Pfad")
(princ "\n  ResetBlockPath           - Löscht gespeicherten Pfad")
(princ "\n")
(princ)

;;; Ende der Datei
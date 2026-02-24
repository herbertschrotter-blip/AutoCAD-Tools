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
;;; Version: 1.5.1
;;; Datum: 2026-02-24
;;; Autor: Herbert Schrotter

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
  
  ;; Suche alle Blöcke mit diesem Namen
  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 blockname))))
  
  (if ss
    (progn
      (setq i 0)
      (while (and (< i (sslength ss)) (not found))
        (setq ent (ssname ss i))
        (setq inspt (cdr (assoc 10 (entget ent))))
        
        ;; Berechne XY-Abstand mit distance (2D) - WKS zu WKS!
        (setq dist-xy (distance (list (car pt-wcs) (cadr pt-wcs)) 
                                (list (car inspt) (cadr inspt))))
        
        ;; Berechne Z-Abstand
        (setq dist-z (abs (- height (caddr inspt))))
        
        ;; Prüfe beide Abstände
        (if (and (< dist-xy tolerance-xy)
                 (< dist-z tolerance-z))
          (setq found T)  ; Block in Nähe gefunden!
        )
        
        (setq i (1+ i))
      )
      
      found
    )
    nil  ; Keine Blöcke gefunden
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
  ;; Vektor von pf1 zu pf2 (nur XY-Ebene)
  (setq vpf (list (- (car pf2) (car pf1)) 
                  (- (cadr pf2) (cadr pf1))))
  
  ;; Vektor von pf1 zu pg (nur XY-Ebene)
  (setq vpg (list (- (car pg) (car pf1)) 
                  (- (cadr pg) (cadr pf1))))
  
  ;; Skalarprojektion: Wie weit liegt pg auf der Linie pf1-pf2?
  ;; Scalar = 0.0 bei pf1, 1.0 bei pf2, <0 links von pf1, >1 rechts von pf2
  (setq scalar (/ (+ (* (car vpg) (car vpf)) 
                     (* (cadr vpg) (cadr vpf))) 
                  (expt (distance pf1 pf2) 2)))
  
  ;; Höhendifferenz zwischen Fixpunkten
  (setq height-diff (- height2 height1))
  
  ;; Interpolierte Höhe berechnen
  ;; WICHTIG: Verwende Skalar direkt - funktioniert auch für Punkte außerhalb!
  (setq interpolated-height (+ height1 (* scalar height-diff)))
  
  interpolated-height
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
  
  ;; Falls ENTER gedrückt: Default verwenden
  (if (null height)
    (if default
      (setq height default)
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
  
  ;; Parameter-Prüfung
  (if (and (valid-point-p einfuegepunkt) (valid-height-p hoehe) scale)
    (progn
      
      ;; NEU: Prüfe ob Block bereits existiert (nur wenn skip-if-exists = T)
      (if (and skip-if-exists (block-exists-at-position einfuegepunkt hoehe blockName))
        (progn
          (princ (strcat "\n  ✓ Block existiert bereits: " (format-height-value hoehe) " | Z=" (rtos hoehe 2 3)))
          nil  ; Kein Block eingefügt
        )
        (progn
          ;; BESTEHENDER CODE: Block verfügbar machen
          (setq block-available (ensure-block-available blockName))
          
          (if (car block-available)
            (progn
              (setq importEnt (cadr block-available))
              
              ;; Höhe formatieren
              (setq heightStr (format-height-value hoehe))
              
              ;; ATTDIA sichern
              (setq old-attdia (getvar "ATTDIA"))
              (setvar "ATTDIA" 0)
              
              ;; Block einfügen MIT XY-SKALIERUNG
              (command "_-insert" blockName einfuegepunkt scale scale "" "")
              
              ;; ATTDIA wiederherstellen
              (setvar "ATTDIA" old-attdia)
              
              ;; Attribute setzen
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
              
              ;; Block auf Höhe verschieben
              (setq insertionPoint (cdr (assoc 10 (entget ent))))
              (command "_move" ent "" "_non" insertionPoint "_non" 
                       (list (car insertionPoint) (cadr insertionPoint) hoehe))
              
              ;; Import-Block entfernen
              (if importEnt
                (entdel importEnt)
              )
              
              (princ (strcat "\n  ✓ Höhenkote gesetzt: " heightStr " | Z=" (rtos hoehe 2 3) " | XY-Scale=" (rtos scale 2 2)))
              T
            )
            (progn
              (princ "\n*** FEHLER: Block konnte nicht geladen werden ***")
              nil
            )
          )
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

;;; Hauptbefehl: Höheninterpolation entlang Linie
(defun c:HoeheAufLinie ( / *error* old-cmdecho old-attdia pf1 height1 pf2 height2 pg interpolated-height scale)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (princ (strcat "\nFehler: " msg))
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
  (princ "\nSetzen Sie zwei Fixpunkte mit bekannten Höhen.")
  (princ "\nDann können Sie beliebig viele Zwischenpunkte setzen.")
  
  ;; Skalierung laden oder initialisieren
  (setq scale (read-scale-config))
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
  
  ;; Prüfe ob Keyword "Skalierung" gewählt wurde
  (while (= pf1 "Skalierung")
    (setq scale (getScale))
    (initget "Skalierung")
    (setq pf1 (getpoint (strcat "\nFixpunkt 1 wählen (oder Skalierung <" (rtos scale 2 2) ">): ")))
  )
  
  (if (not (valid-point-p pf1))
    (princ "\n*** Abbruch: Kein gültiger Punkt gewählt ***")
    (progn
      (setq height1 (get-validated-height "\nHöhe Fixpunkt 1 eingeben" g_lastHeight))
      
      (if (not height1)
        (princ "\n*** Abbruch: Keine gültige Höhe eingegeben ***")
        (progn
          (setq g_lastHeight height1)
          ;; NEU: T = skip-if-exists für Fixpunkte
          (insert-hoehenkote-block pf1 height1 scale T)
          
          ;; Fixpunkt 2 mit Skalierungs-Option
          (princ "\n")
          (initget "Skalierung")
          (setq pf2 (getpoint (strcat "\nFixpunkt 2 wählen (oder Skalierung <" (rtos scale 2 2) ">): ")))
          
          ;; Prüfe ob Keyword "Skalierung" gewählt wurde
          (while (= pf2 "Skalierung")
            (setq scale (getScale))
            (initget "Skalierung")
            (setq pf2 (getpoint (strcat "\nFixpunkt 2 wählen (oder Skalierung <" (rtos scale 2 2) ">): ")))
          )
          
          (if (not (valid-point-p pf2))
            (princ "\n*** Abbruch: Kein gültiger Punkt gewählt ***")
            (progn
              (setq height2 (get-validated-height "\nHöhe Fixpunkt 2 eingeben" g_lastHeight))
              
              (if (not height2)
                (princ "\n*** Abbruch: Keine gültige Höhe eingegeben ***")
                (progn
                  (setq g_lastHeight height2)
                  ;; NEU: T = skip-if-exists für Fixpunkte
                  (insert-hoehenkote-block pf2 height2 scale T)
                  
                  ;; Schleife: Gesuchte Punkte mit Skalierungs-Option
                  (princ "\n")
                  (princ "\n--- Zwischenpunkte setzen (ESC = Ende) ---")
                  
                  (initget "Skalierung")
                  (setq pg (getpoint (strcat "\nGesuchten Punkt wählen (oder Skalierung/ESC <" (rtos scale 2 2) ">): ")))
                  
                  (while pg
                    ;; Prüfe ob Keyword "Skalierung" gewählt wurde
                    (if (= pg "Skalierung")
                      (progn
                        (setq scale (getScale))
                        (initget "Skalierung")
                        (setq pg (getpoint (strcat "\nGesuchten Punkt wählen (oder Skalierung/ESC <" (rtos scale 2 2) ">): ")))
                      )
                      ;; Normal: Punkt gewählt
                      (progn
                        (if (valid-point-p pg)
                          (progn
                            (setq interpolated-height (calculate-interpolated-height pf1 height1 pf2 height2 pg))
                            (princ (strcat "\n  Berechnete Höhe: " (format-height interpolated-height)))
                            ;; NEU: nil = immer einfügen für Zwischenpunkte
                            (insert-hoehenkote-block pg interpolated-height scale nil)
                          )
                          (princ "\n*** Ungültiger Punkt - übersprungen ***")
                        )
                        ;; Nächsten Punkt abfragen
                        (initget "Skalierung")
                        (setq pg (getpoint (strcat "\nGesuchten Punkt wählen (oder Skalierung/ESC <" (rtos scale 2 2) ">): ")))
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
(princ "\nHoeheAufLinie.lsp v1.5.1 geladen.")
(princ "\nBefehle:")
(princ "\n  HoeheAufLinie (HAL)      - Höheninterpolation entlang Linie (S für Skalierung)")
(princ "\n  ManageBlockImportHAL     - Block-Verwaltung für HoeheAufLinie")
(princ "\n  ShowBlockPath            - Zeigt konfigurierten Block-Pfad")
(princ "\n  ResetBlockPath           - Löscht gespeicherten Pfad")
(princ "\n")
(princ)

;;; Ende der Datei
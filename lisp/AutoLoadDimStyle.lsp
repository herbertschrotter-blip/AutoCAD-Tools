;;; AutoLoadDimStyle.lsp
;;; Automatisches Laden von Bemaßungsstilen für AutoCAD
;;;
;;; Installation:
;;; 1. Datei speichern (z.B. in AutoCAD-Tools Ordner)
;;; 2. In AutoCAD: APPLOAD ausführen
;;; 3. AutoLoadDimStyle.lsp auswählen und laden
;;; 4. Optional: In Startup Suite hinzufügen für automatisches Laden
;;;
;;; Version: 2.7.0
;;; Datum: 2026-02-13

;;; ============================================================================
;;; INITIALISIERUNG - VISUAL LISP
;;; ============================================================================

;; Lade Visual LISP COM/ActiveX Schnittstelle
;; Erforderlich für: vl-filename-directory, vl-file-directory-p, vl-mkdir,
;;                    vl-remove, vl-filename-base, vl-filename-extension,
;;                    vl-file-delete, vla-open
(vl-load-com)

;;; ============================================================================
;;; KONFIGURATION
;;; ============================================================================

;; Pfad zur Konfigurationsdatei (speichert Liste der Master-Dateien)
(setq *config-file* (strcat (getenv "APPDATA") "/AutoCAD/DimStyleConfig.txt"))

;;; ============================================================================
;;; HILFSFUNKTIONEN - CONFIG MANAGEMENT
;;; ============================================================================

;;; Liest alle gespeicherten Pfade aus Konfigurationsdatei
(defun read-master-files ( / file line files version)
  (setq files '())
  (if (and (findfile *config-file*)
           (setq file (open *config-file* "r")))
    (progn
      ;; Erste Zeile: Version
      (setq version (read-line file))
      
      ;; Restliche Zeilen: Dateipfade (cons statt append für Performance)
      (while (setq line (read-line file))
        (if (and line (> (strlen line) 0))
          (setq files (cons line files))
        )
      )
      
      ;; Reverse weil cons in umgekehrter Reihenfolge einfügt
      (setq files (reverse files))
      
      ;; File-Handle immer schließen
      (if file 
        (progn
          (close file)
          (setq file nil)
        )
      )
    )
  )
  files
)

;;; Speichert Liste von Pfaden in Konfigurationsdatei
(defun save-master-files (filepaths / file dir)
  ;; Erstelle Verzeichnis falls nicht vorhanden
  (setq dir (vl-filename-directory *config-file*))
  (if (not (vl-file-directory-p dir))
    (vl-mkdir dir)
  )
  
  ;; Speichere Pfade
  (if (setq file (open *config-file* "w"))
    (progn
      ;; Erste Zeile: Version
      (write-line "2.7" file)
      
      ;; Dateipfade
      (foreach filepath filepaths
        (write-line filepath file)
      )
      
      ;; File-Handle immer schließen
      (if file
        (progn
          (close file)
          (setq file nil)
        )
      )
      T
    )
    nil
  )
)

;;; Fügt einen Pfad zur Liste hinzu
(defun add-master-file (filepath / files)
  (setq files (read-master-files))
  
  ;; Prüfe ob bereits in Liste
  (if (not (member filepath files))
    (progn
      (setq files (append files (list filepath)))
      (save-master-files files)
      T
    )
    nil
  )
)

;;; Entfernt einen Pfad aus der Liste
(defun remove-master-file (filepath / files)
  (setq files (read-master-files))
  (setq files (vl-remove filepath files))
  (save-master-files files)
)

;;; Prüft ob Pfad eine gültige DWG-Datei ist
(defun valid-dwg-file-p (filepath / ext)
  (if (and filepath 
           (> (strlen filepath) 0))
    (progn
      (setq ext (strcase (vl-filename-extension filepath)))
      (or (equal ext ".DWG")
          (equal ext ".dwg"))
    )
    nil
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - ERST-KONFIGURATION
;;; ============================================================================

;;; Führt Erst-Konfiguration durch (beim ersten Aufruf)
(defun first-time-setup ( / selected-file)
  (princ "\n+===========================================================+")
  (princ "\n|  WILLKOMMEN BEI AUTOLOADDIMSTYLE                          |")
  (princ "\n+===========================================================+")
  (princ "\n\nKeine Konfiguration gefunden.")
  (princ "\nBitte waehlen Sie Ihre erste Master-Datei mit Bemassungsstilen.")
  (princ "\n")
  
  (if (setq selected-file (getfiled "Master-Datei mit Bemassungsstilen auswaehlen" "" "dwg" 0))
    (if (valid-dwg-file-p selected-file)
      (progn
        (save-master-files (list selected-file))
        (princ (strcat "\n\nOK Konfiguration erstellt: " selected-file))
        (princ "\nDie Datei wird ab jetzt automatisch geladen.")
        T  ; Erfolg
      )
      (progn
        (princ "\n\nFEHLER Keine gueltige DWG-Datei ausgewaehlt.")
        nil  ; Fehler
      )
    )
    (progn
      (princ "\n\nKeine Datei ausgewaehlt.")
      (princ "\nSie koennen spaeter 'DimStyleManager' -> 'Hinzufuegen' verwenden.")
      nil  ; Abgebrochen
    )
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - INTERAKTIVE AKTIONEN (FÜR MENÜ)
;;; ============================================================================

;;; Lädt Bemaßungsstile interaktiv
(defun load-dimstyles-interactive ( / master-files loaded-count failed-count 
                                      old-cmdecho old-attreq)
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-attreq (getvar "ATTREQ"))
  (setvar "CMDECHO" 0)
  (setvar "ATTREQ" 0)
  
  (setq loaded-count 0)
  (setq failed-count 0)
  (setq master-files (read-master-files))
  
  ;; Falls keine Dateien
  (if (null master-files)
    (progn
      (princ "\n*** Keine Master-Dateien konfiguriert ***")
      (princ "\nVerwenden Sie 'Hinzufuegen' um eine Master-Datei zu konfigurieren.")
    )
    (progn
      (princ "\n+===========================================================+")
      (princ "\n|  LADE BEMASSTILE                                          |")
      (princ "\n+===========================================================+")
      
      (foreach master-file master-files
        (if (findfile master-file)
          (progn
            (princ (strcat "\n  -> Lade: " (vl-filename-base master-file)))
            (command "._-insert" master-file nil)
            (princ " [OK]")
            (setq loaded-count (1+ loaded-count))
          )
          (progn
            (princ (strcat "\n  -> Nicht gefunden: " (vl-filename-base master-file)))
            (princ " [FEHLER]")
            (setq failed-count (1+ failed-count))
          )
        )
      )
      
      (princ (strcat "\n\nOK " (itoa loaded-count) " Datei(en) erfolgreich geladen"))
      (if (> failed-count 0)
        (princ (strcat "\nFEHLER " (itoa failed-count) " Datei(en) fehlgeschlagen"))
      )
      (princ "\n\nBemassungsstile verfuegbar unter: BEMASSTIL (DIMSTYLE)")
    )
  )
  
  ;; Systemvariablen wiederherstellen
  (setvar "CMDECHO" old-cmdecho)
  (setvar "ATTREQ" old-attreq)
  
  ;; Memory freigeben
  (setq master-files nil)
  (setq old-cmdecho nil)
  (setq old-attreq nil)
)

;;; Öffnet eine Master-Datei zum Bearbeiten
(defun open-master-file-interactive ( / master-files choice idx selected-file max-files
                                        acad-obj docs new-doc)
  (setq master-files (read-master-files))
  
  (if (null master-files)
    (princ "\nFEHLER Keine Master-Dateien konfiguriert.")
    (progn
      (princ "\n+===========================================================+")
      (princ "\n|  MASTER-DATEI OEFFNEN                                     |")
      (princ "\n+===========================================================+")
      (princ "\n\nVerfuegbare Dateien:")
      
      (setq max-files (length master-files))
      (setq idx 1)
      (foreach mf master-files
        (princ (strcat "\n  [" (itoa idx) "] " (vl-filename-base mf)))
        (if (findfile mf)
          (princ " [OK]")
          (princ " [FEHLER]")
        )
        (setq idx (1+ idx))
      )
      
      ;; Auswahl
      (princ "\n\nWelche Datei oeffnen? (Nummer eingeben, Enter = Abbruch): ")
      (setq choice (getint))
      
      (if (and choice 
               (>= choice 1) 
               (<= choice max-files))
        (progn
          (setq selected-file (nth (1- choice) master-files))
          (if (findfile selected-file)
            (progn
              (princ (strcat "\nOK Oeffne: " (vl-filename-base selected-file)))
              
              ;; Verwende vla-open (funktioniert mit allen Pfaden)
              (setq acad-obj (vlax-get-acad-object))
              (setq docs (vla-get-documents acad-obj))
              (setq new-doc (vla-open docs selected-file))
              
              ;; WICHTIG: Aktiviere die geöffnete Datei
              (vla-activate new-doc)
              
              (princ "\nOK Datei geoeffnet und aktiviert")
            )
            (princ "\nFEHLER Datei nicht gefunden.")
          )
        )
        (princ "\nAbgebrochen.")
      )
    )
  )
  
  ;; Memory freigeben
  (setq master-files nil)
  (setq selected-file nil)
  (setq acad-obj nil)
  (setq docs nil)
  (setq new-doc nil)
)

;;; Fügt eine Master-Datei hinzu
(defun add-master-file-interactive ( / new-file master-files)
  (princ "\n+===========================================================+")
  (princ "\n|  MASTER-DATEI HINZUFUEGEN                                 |")
  (princ "\n+===========================================================+")
  
  ;; Zeige aktuelle Liste
  (setq master-files (read-master-files))
  (if master-files
    (progn
      (princ "\n\nAktuell konfiguriert:")
      (foreach mf master-files
        (princ (strcat "\n  * " (vl-filename-base mf)))
      )
      (princ "\n")
    )
  )
  
  ;; Wähle neue Datei
  (if (setq new-file (getfiled "Weitere Master-Datei hinzufuegen" "" "dwg" 0))
    ;; Validiere DWG-Datei
    (if (valid-dwg-file-p new-file)
      (if (add-master-file new-file)
        (progn
          (princ (strcat "\nOK Hinzugefuegt: " new-file))
          (princ "\nDie Datei wird beim naechsten Laden automatisch verwendet.")
        )
        (princ "\nFEHLER Diese Datei ist bereits in der Liste.")
      )
      (princ "\nFEHLER Keine gueltige DWG-Datei ausgewaehlt.")
    )
    (princ "\nFEHLER Keine Datei ausgewaehlt.")
  )
  
  ;; Memory freigeben
  (setq master-files nil)
  (setq new-file nil)
)

;;; Entfernt eine Master-Datei
(defun remove-master-file-interactive ( / master-files choice idx removed-file max-files)
  (setq master-files (read-master-files))
  
  (if (null master-files)
    (princ "\nFEHLER Keine Master-Dateien konfiguriert.")
    (progn
      (princ "\n+===========================================================+")
      (princ "\n|  MASTER-DATEI ENTFERNEN                                   |")
      (princ "\n+===========================================================+")
      (princ "\n\nKonfigurierte Dateien:")
      
      (setq max-files (length master-files))
      (setq idx 1)
      (foreach mf master-files
        (princ (strcat "\n  [" (itoa idx) "] " (vl-filename-base mf)))
        (setq idx (1+ idx))
      )
      
      ;; Auswahl
      (princ "\n\nWelche Datei entfernen? (Nummer eingeben, Enter = Abbruch): ")
      (setq choice (getint))
      
      (if (and choice 
               (>= choice 1) 
               (<= choice max-files))
        (progn
          (setq removed-file (nth (1- choice) master-files))
          (remove-master-file removed-file)
          (princ (strcat "\nOK Entfernt: " (vl-filename-base removed-file)))
        )
        (princ "\nAbgebrochen.")
      )
    )
  )
  
  ;; Memory freigeben
  (setq master-files nil)
  (setq removed-file nil)
)

;;; Zeigt alle konfigurierten Pfade
(defun show-paths-interactive ( / master-files idx)
  (setq master-files (read-master-files))
  
  (princ "\n+===========================================================+")
  (princ "\n|  KONFIGURIERTE PFADE                                      |")
  (princ "\n+===========================================================+")
  
  (if master-files
    (progn
      (princ "\n\nMaster-Dateien:")
      (setq idx 1)
      (foreach master-file master-files
        (princ (strcat "\n  " (itoa idx) ". " master-file))
        (if (findfile master-file)
          (princ " [OK]")
          (princ " [FEHLER - Nicht gefunden!]")
        )
        (setq idx (1+ idx))
      )
    )
    (princ "\n\nKeine Master-Dateien konfiguriert.")
  )
  
  ;; Memory freigeben
  (setq master-files nil)
)

;;; Setzt alle Pfade zurück
(defun reset-paths-interactive ( / )
  (princ "\n+===========================================================+")
  (princ "\n|  PFADE ZURUECKSETZEN                                      |")
  (princ "\n+===========================================================+")
  
  (if (findfile *config-file*)
    (progn
      (vl-file-delete *config-file*)
      (princ "\nOK Alle gespeicherten Pfade wurden zurueckgesetzt.")
      (princ "\n\nBeim naechsten Aufruf werden Sie nach einer Master-Datei gefragt.")
    )
    (princ "\nFEHLER Keine gespeicherten Pfade vorhanden.")
  )
)

;;; ============================================================================
;;; HAUPTFUNKTIONEN
;;; ============================================================================

;;; Interaktives Menü für Bemaßungsstil-Verwaltung (HAUPTBEFEHL)
(defun c:DimStyleManager ( / *error* master-files kword running)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (progn
        (princ "\n*** Fehler im Bemasstil-Manager ***")
        (princ (strcat "\nFehlermeldung: " msg))
      )
    )
    (princ)
  )
  
  ;; ERST-KONFIGURATION wenn keine Config vorhanden
  (if (null (read-master-files))
    (if (not (first-time-setup))
      ;; User hat abgebrochen oder Fehler - beende
      (progn
        (princ)
        (exit)
      )
    )
  )
  
  (setq running T)
  
  (while running
    ;; Hole aktuelle Master-Dateien
    (setq master-files (read-master-files))
    
    ;; Zeige Header
    (princ "\n")
    (princ "\n+===========================================================+")
    (princ "\n|         BEMASSTIL-MANAGER                                 |")
    (princ "\n+===========================================================+")
    
    ;; Zeige konfigurierte Dateien
    (if master-files
      (progn
        (princ (strcat "\n\nKonfigurierte Dateien: " (itoa (length master-files))))
        (foreach mf master-files
          (princ (strcat "\n  * " (vl-filename-base mf)))
          (if (findfile mf)
            (princ " [OK]")
            (princ " [FEHLER]")
          )
        )
      )
      (princ "\n\nKeine Master-Dateien konfiguriert.")
    )
    
    (princ "\n")
    
    ;; Keyword-Auswahl mit initget
    (initget "Laden Oeffnen Hinzufuegen Entfernen Pfade Reset Beenden")
    (setq kword (getkword "\nAktion [Laden/Oeffnen/Hinzufuegen/Entfernen/Pfade/Reset/Beenden] <Beenden>: "))
    
    ;; Wenn Enter gedrückt (nil) → Beenden
    (if (null kword)
      (setq kword "Beenden")
    )
    
    (cond
      ;; Laden
      ((equal kword "Laden")
        (load-dimstyles-interactive)
      )
      
      ;; Öffnen - BEENDET Schleife nach Öffnen
      ((equal kword "Oeffnen")
        (progn
          (open-master-file-interactive)
          (setq running nil)  ; Beende Menü - Datei bleibt offen
        )
      )
      
      ;; Hinzufügen
      ((equal kword "Hinzufuegen")
        (add-master-file-interactive)
      )
      
      ;; Entfernen
      ((equal kword "Entfernen")
        (remove-master-file-interactive)
      )
      
      ;; Pfade anzeigen
      ((equal kword "Pfade")
        (show-paths-interactive)
      )
      
      ;; Reset
      ((equal kword "Reset")
        (reset-paths-interactive)
      )
      
      ;; Beenden
      ((equal kword "Beenden")
        (progn
          (princ "\n\nOK Bemasstil-Manager beendet.")
          (setq running nil)
        )
      )
    )
    
    ;; Pause nur wenn nicht beendet
    (if running
      (progn
        (princ "\n")
        (princ "\n-----------------------------------------------------------")
        (princ "\nEnter druecken um fortzufahren...")
        (getstring)
      )
    )
  )
  
  ;; Memory freigeben
  (setq master-files nil)
  (princ)
)

;;; Lädt alle Bemaßungsstile AUTOMATISCH (silent, für S::STARTUP)
(defun c:AutoLoadDimStyles ( / master-files old-cmdecho old-attreq)
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-attreq (getvar "ATTREQ"))
  (setvar "CMDECHO" 0)
  (setvar "ATTREQ" 0)
  
  ;; Hole Master-Dateien
  (setq master-files (read-master-files))
  
  ;; Falls keine Config: ERST-KONFIGURATION (auch beim Autostart!)
  (if (null master-files)
    (progn
      ;; First-Time Setup
      (if (first-time-setup)
        ;; Setup erfolgreich - hole neue Liste
        (setq master-files (read-master-files))
      )
    )
  )
  
  ;; Lade Master-Dateien (falls vorhanden)
  (if master-files
    (foreach master-file master-files
      (if (findfile master-file)
        (command "._-insert" master-file nil)
      )
    )
  )
  
  ;; Systemvariablen wiederherstellen
  (setvar "CMDECHO" old-cmdecho)
  (setvar "ATTREQ" old-attreq)
  
  ;; Memory freigeben
  (setq master-files nil)
  (setq old-cmdecho nil)
  (setq old-attreq nil)
  
  (princ)  ; Keine Ausgabe
)

;;; ============================================================================
;;; AUTOSTART - Wird beim Öffnen jeder Zeichnung ausgeführt
;;; ============================================================================

;;; Wird beim Öffnen jeder Zeichnung ausgeführt (automatisch von AutoCAD)
(defun S::STARTUP ( / )
  (c:AutoLoadDimStyles)  ; Silent, keine Ausgaben
  (princ)
)

;;; ============================================================================
;;; INITIALISIERUNG - AUSGABE
;;; ============================================================================

(princ "\nAutoLoadDimStyle.lsp v2.7.0 geladen.")
(princ "\n+===========================================================+")
(princ "\n|  Hauptbefehl: DimStyleManager                             |")
(princ "\n|  Autostart:   AutoLoadDimStyles (silent)                  |")
(princ "\n+===========================================================+")
(princ)
```

---

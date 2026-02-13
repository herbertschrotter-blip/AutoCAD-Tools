;;; AutoLoadDimStyle.lsp
;;; Automatisches Laden von Bemaßungsstilen für AutoCAD
;;;
;;; Installation:
;;; 1. Datei speichern (z.B. in AutoCAD-Tools Ordner)
;;; 2. In AutoCAD: APPLOAD ausführen
;;; 3. AutoLoadDimStyle.lsp auswählen und laden
;;; 4. Optional: In Startup Suite hinzufügen für automatisches Laden
;;;
;;; Version: 2.5.0
;;; Datum: 2026-02-12

;;; ============================================================================
;;; KONFIGURATION
;;; ============================================================================

;; Standard-Pfad (wird verwendet wenn noch keine Konfiguration existiert)
(setq *default-master-file* "D:/OneDrive/Dokumente/02 Arbeit/05 Vorlagen - Scripte/02_AutoCAD Tools/templates/Bemaßungs_Stile/Master_BemStile.dwg")

;; Pfad zur Konfigurationsdatei (speichert Liste der Master-Dateien)
(setq *config-file* (strcat (getenv "APPDATA") "/AutoCAD/DimStyleConfig.txt"))

;; Globale Variable für stillen Modus
(setq *dimstyle-silent-mode* nil)

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
      (write-line "2.5" file)
      
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
;;; HILFSFUNKTIONEN - LADEN
;;; ============================================================================

;;; Lädt eine Master-Datei
(defun load-master-file-safe (filepath / )
  ;; Info ausgeben
  (if (not *dimstyle-silent-mode*)
    (princ (strcat "\n  Lade: " (vl-filename-base filepath)))
  )
  
  ;; Laden - AutoCAD gibt eigene Fehlermeldungen aus falls nötig
  (command "._-insert" filepath nil)
  
  (if (not *dimstyle-silent-mode*)
    (princ "\n  ✓ Geladen")
  )
  
  T  ; Rückgabe: Erfolgreich
)

;;; Fordert Benutzer auf, Master-Datei auszuwählen
(defun select-master-file ( / filepath)
  (if (not *dimstyle-silent-mode*)
    (progn
      (princ "\n*** Keine Master-Datei konfiguriert ***")
      (princ "\nBitte wählen Sie die Master-Datei mit den Bemaßungsstilen aus...")
    )
  )
  
  (if (setq filepath (getfiled "Master-Datei wählen" *default-master-file* "dwg" 0))
    (progn
      (if (not *dimstyle-silent-mode*)
        (princ (strcat "\nGewählte Datei: " filepath))
      )
      
      ;; Speichere als erste Datei in Config
      (save-master-files (list filepath))
      
      (if (not *dimstyle-silent-mode*)
        (princ "\nPfad wurde gespeichert.")
      )
      filepath
    )
    nil
  )
)

;;; ============================================================================
;;; HAUPTFUNKTIONEN
;;; ============================================================================

;;; Lädt alle Bemaßungsstile aus konfigurierten Master-Dateien
(defun c:LoadDimStyles ( / *error* master-files loaded-count failed-count selected-file 
                           old-cmdecho old-attreq file-count)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    ;; ESC und ENTER unterdrücken
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (progn
        (princ "\n*** Fehler beim Laden der Bemaßungsstile ***")
        (princ (strcat "\nFehlermeldung: " msg))
      )
    )
    ;; Systemvariablen wiederherstellen
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-attreq (setvar "ATTREQ" old-attreq))
    (princ)
  )
  
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-attreq (getvar "ATTREQ"))
  
  ;; Setzen für optimale Performance
  (setvar "CMDECHO" 0)  ; Keine Command-Ausgaben
  (setvar "ATTREQ" 0)   ; Keine Attribut-Dialoge
  
  (setq loaded-count 0)
  (setq failed-count 0)
  
  ;; Hole Liste der Master-Dateien
  (setq master-files (read-master-files))
  
  ;; Falls keine Dateien konfiguriert, prüfe Standard-Pfad oder frage
  (if (null master-files)
    (if (findfile *default-master-file*)
      (setq master-files (list *default-master-file*))
      (if (setq selected-file (select-master-file))
        (setq master-files (list selected-file))
      )
    )
  )
  
  ;; Lade alle konfigurierten Dateien
  (if master-files
    (progn
      ;; Berechne Anzahl nur einmal (Performance)
      (setq file-count (length master-files))
      
      (if (not *dimstyle-silent-mode*)
        (progn
          (princ "\n=== Lade Bemaßungsstile ===")
          (princ (strcat "\nAnzahl Master-Dateien: " (itoa file-count)))
        )
      )
      
      (foreach master-file master-files
        (if (findfile master-file)
          (if (load-master-file-safe master-file)
            (setq loaded-count (1+ loaded-count))
            (setq failed-count (1+ failed-count))
          )
          (progn
            (if (not *dimstyle-silent-mode*)
              (princ (strcat "\n  ✗ Datei nicht gefunden: " master-file))
            )
            (setq failed-count (1+ failed-count))
          )
        )
      )
      
      ;; Zusammenfassung
      (if (not *dimstyle-silent-mode*)
        (progn
          (princ (strcat "\n\n✓ " (itoa loaded-count) " Datei(en) geladen"))
          (if (> failed-count 0)
            (princ (strcat "\n✗ " (itoa failed-count) " Datei(en) fehlgeschlagen"))
          )
          (princ "\n\nVerfügbar unter: BEMASSTIL (DIMSTYLE)")
        )
      )
    )
    ;; Keine Dateien gefunden oder gewählt
    (if (not *dimstyle-silent-mode*)
      (princ "\nKeine Master-Dateien konfiguriert.")
    )
  )
  
  ;; Cleanup (normales Ende)
  (setvar "CMDECHO" old-cmdecho)
  (setvar "ATTREQ" old-attreq)
  
  ;; Memory freigeben
  (setq master-files nil)
  (setq old-cmdecho nil)
  (setq old-attreq nil)
  
  (princ)
)

;;; Zeigt alle konfigurierten Master-Dateien
(defun c:ShowDimStylePath ( / master-files i)
  (setq master-files (read-master-files))
  
  (princ "\n=== Konfigurierte Master-Dateien ===")
  
  (if master-files
    (progn
      (setq i 1)
      (foreach master-file master-files
        (princ (strcat "\n" (itoa i) ". " master-file))
        (if (findfile master-file)
          (princ " [✓ Existiert]")
          (princ " [✗ Nicht gefunden!]")
        )
        (setq i (1+ i))
      )
    )
    (progn
      (princ "\nKeine Master-Dateien konfiguriert.")
      (princ "\n\nStandard-Pfad:")
      (princ (strcat "\n  " *default-master-file*))
      (if (findfile *default-master-file*)
        (princ " [✓ Existiert]")
        (princ " [✗ Nicht gefunden]")
      )
    )
  )
  (princ "\n")
  (princ)
)

;;; Löscht alle gespeicherten Pfade
(defun c:ResetDimStylePath ( / *error*)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    ;; ESC und ENTER unterdrücken
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (progn
        (princ "\n*** Fehler beim Zurücksetzen der Pfade ***")
        (princ (strcat "\nFehlermeldung: " msg))
      )
    )
    (princ)
  )
  
  (if (findfile *config-file*)
    (progn
      (vl-file-delete *config-file*)
      (princ "\nAlle gespeicherten Pfade wurden zurückgesetzt.")
      (princ "\nBeim nächsten Aufruf von LoadDimStyles werden Sie nach der Datei gefragt.")
    )
    (princ "\nKeine gespeicherten Pfade vorhanden.")
  )
  (princ)
)

;;; Fügt eine weitere Master-Datei hinzu
(defun c:AddMasterFile ( / *error* new-file master-files)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    ;; ESC und ENTER unterdrücken
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (progn
        (princ "\n*** Fehler beim Hinzufügen der Master-Datei ***")
        (princ (strcat "\nFehlermeldung: " msg))
      )
    )
    (princ)
  )
  
  (princ "\n=== Master-Datei hinzufügen ===")
  
  ;; Zeige aktuelle Liste
  (setq master-files (read-master-files))
  (if master-files
    (progn
      (princ "\n\nAktuell konfiguriert:")
      (foreach mf master-files
        (princ (strcat "\n  - " (vl-filename-base mf)))
      )
      (princ "\n")
    )
  )
  
  ;; Wähle neue Datei
  (if (setq new-file (getfiled "Weitere Master-Datei hinzufügen" "" "dwg" 0))
    ;; Validiere DWG-Datei
    (if (valid-dwg-file-p new-file)
      (if (add-master-file new-file)
        (progn
          (princ (strcat "\n✓ Hinzugefügt: " new-file))
          (princ "\nDie Datei wird beim nächsten Laden automatisch verwendet.")
        )
        (princ "\n✗ Diese Datei ist bereits in der Liste.")
      )
      (princ "\n✗ Keine gültige DWG-Datei ausgewählt.")
    )
    (princ "\n✗ Keine Datei ausgewählt.")
  )
  
  ;; Memory freigeben
  (setq master-files nil)
  (setq new-file nil)
  
  (princ)
)

;;; Entfernt eine Master-Datei aus der Liste
(defun c:RemoveMasterFile ( / *error* master-files selection idx removed-file input max-files)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    ;; ESC und ENTER unterdrücken
    (if (not (member msg '("Function cancelled" "quit / exit abort")))
      (progn
        (princ "\n*** Fehler beim Entfernen der Master-Datei ***")
        (princ (strcat "\nFehlermeldung: " msg))
      )
    )
    (princ)
  )
  
  (setq master-files (read-master-files))
  
  (if (null master-files)
    (progn
      (princ "\nKeine Master-Dateien konfiguriert.")
      (princ)
    )
    (progn
      (princ "\n=== Master-Datei entfernen ===")
      (princ "\n\nKonfigurierte Dateien:")
      
      ;; Berechne Anzahl nur einmal (Performance)
      (setq max-files (length master-files))
      
      ;; Liste anzeigen
      (setq idx 1)
      (foreach mf master-files
        (princ (strcat "\n" (itoa idx) ". " (vl-filename-base mf)))
        (setq idx (1+ idx))
      )
      
      ;; Auswahl mit Validierung und Wiederholung
      (setq selection nil)
      (while (not selection)
        ;; Ein princ statt mehrere (effizienter)
        (princ (strcat "\n\nWelche Datei soll entfernt werden? (Nummer 1-"
                       (itoa max-files)
                       ", 0 = Abbruch): "))
        (setq input (getint))
        
        (cond
          ;; User will abbrechen
          ((equal input 0)
            (progn
              (princ "\n✗ Abgebrochen.")
              (setq selection 0)
            )
          )
          ;; Gültige Nummer
          ((and input 
                (>= input 1) 
                (<= input max-files))
            (setq selection input)
          )
          ;; Ungültige Eingabe
          (T
            (princ (strcat "\n✗ Ungültige Auswahl. Bitte Zahl zwischen 1 und "
                           (itoa max-files)
                           " eingeben, oder 0 für Abbruch."))
          )
        )
      )
      
      ;; Nur ausführen wenn nicht abgebrochen
      (if (> selection 0)
        (progn
          (setq removed-file (nth (1- selection) master-files))
          (remove-master-file removed-file)
          (princ (strcat "\n✓ Entfernt: " (vl-filename-base removed-file)))
        )
      )
      
      ;; Memory freigeben
      (setq master-files nil)
      (setq removed-file nil)
      
      (princ)
    )
  )
)

;;; Alias für Abwärtskompatibilität
(defun c:LoadBemMeter ( / )
  (c:LoadDimStyles)
)

;;; ============================================================================
;;; AUTOSTART - Wird beim Öffnen jeder Zeichnung ausgeführt
;;; ============================================================================

;;; Wird beim Öffnen jeder Zeichnung ausgeführt (automatisch von AutoCAD)
(defun S::STARTUP ( / )
  (setq *dimstyle-silent-mode* T)  ; Still beim Autostart
  (c:LoadDimStyles)
  (setq *dimstyle-silent-mode* nil) ; Laut bei manuellem Aufruf
  (princ)
)

;;; ============================================================================
;;; INITIALISIERUNG
;;; ============================================================================

(princ "\nAutoLoadDimStyle.lsp v2.5.0 geladen.")
(princ "\nBefehle: LoadDimStyles, ShowDimStylePath, ResetDimStylePath")
(princ "\n         AddMasterFile, RemoveMasterFile")
(princ)
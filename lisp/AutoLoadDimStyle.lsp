;;; AutoLoadDimStyle.lsp
;;; Automatisches Laden von Bemaßungsstilen für AutoCAD
;;; Speziell für Leica-Vermessungsarbeiten (Meter-Bemaßungen)
;;;
;;; Installation:
;;; 1. Diese Datei in "acaddoc.lsp" umbenennen
;;; 2. In den AutoCAD Support-Ordner kopieren
;;; 3. AutoCAD neu starten
;;;
;;; Version: 2.2.1
;;; Datum: 2026-02-09

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
      ;; Erste Zeile: Version (für zukünftige Kompatibilität)
      (setq version (read-line file))
      
      ;; Restliche Zeilen: Dateipfade
      (while (setq line (read-line file))
        (if (and line (> (strlen line) 0))
          (setq files (append files (list line)))
        )
      )
      (close file)
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
      (write-line "2.2" file)
      
      ;; Dateipfade
      (foreach filepath filepaths
        (write-line filepath file)
      )
      (close file)
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
(defun c:LoadDimStyles ( / master-files loaded-count failed-count selected-file)
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
      (if (not *dimstyle-silent-mode*)
        (progn
          (princ "\n=== Lade Bemaßungsstile ===")
          (princ (strcat "\nAnzahl Master-Dateien: " (itoa (length master-files))))
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
(defun c:ResetDimStylePath ( / )
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
(defun c:AddMasterFile ( / new-file master-files)
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
    (if (add-master-file new-file)
      (progn
        (princ (strcat "\n✓ Hinzugefügt: " new-file))
        (princ "\nDie Datei wird beim nächsten Laden automatisch verwendet.")
      )
      (princ "\n✗ Diese Datei ist bereits in der Liste.")
    )
    (princ "\n✗ Keine Datei ausgewählt.")
  )
  (princ)
)

;;; Entfernt eine Master-Datei aus der Liste
(defun c:RemoveMasterFile ( / master-files selection idx removed-file)
  (setq master-files (read-master-files))
  
  (if (null master-files)
    (progn
      (princ "\nKeine Master-Dateien konfiguriert.")
      (princ)
    )
    (progn
      (princ "\n=== Master-Datei entfernen ===")
      (princ "\n\nKonfigurierte Dateien:")
      
      ;; Liste anzeigen
      (setq idx 1)
      (foreach mf master-files
        (princ (strcat "\n" (itoa idx) ". " (vl-filename-base mf)))
        (setq idx (1+ idx))
      )
      
      ;; Auswahl
      (princ "\n\nWelche Datei soll entfernt werden? (Nummer eingeben): ")
      (setq selection (getint))
      
      (if (and selection 
               (>= selection 1) 
               (<= selection (length master-files)))
        (progn
          (setq removed-file (nth (1- selection) master-files))
          (remove-master-file removed-file)
          (princ (strcat "\n✓ Entfernt: " (vl-filename-base removed-file)))
        )
        (princ "\n✗ Ungültige Auswahl.")
      )
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

(princ "\nAutoLoadDimStyle.lsp v2.2.1 geladen.")
(princ "\nBefehle: LoadDimStyles, ShowDimStylePath, ResetDimStylePath")
(princ "\n         AddMasterFile, RemoveMasterFile")
(princ)
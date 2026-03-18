;;; AutoLoadDimStyle.lsp
;;; Automatisches Laden von Bemassungsstilen fuer AutoCAD
;;;
;;; Version: 2.9.0
;;; Datum: 2026-03-18
;;; Autor: Herbert Schrotter
;;; Namespace: ADS (AutoLoadDimStyle)
;;;
;;; AppData: %APPDATA%\AutoCAD\Lisp\AutoLoadDimStyle\
;;;   - Log\       AutoLoadDimStyle_YYYYMMDD_HHMMSS.log (max 5 Sessions)
;;;   - Config\    AutoLoadDimStyle.cfg
;;;   - Backup\    (reserviert)
;;;
;;; Installation:
;;; 1. APPLOAD ausfuehren
;;; 2. AutoLoadDimStyle.lsp auswaehlen und laden
;;; 3. Optional: Zu Startup Suite hinzufuegen
;;;
;;; Befehle:
;;; DimStyleManager   - DCL-Dialog fuer Verwaltung
;;; AutoLoadDimStyles - Silent Autostart (S::STARTUP)
;;; ADSDEBUG          - Debug-Modus ein/aus

;;; ============================================================================
;;; KONSTANTEN
;;; ============================================================================

(setq *ADS:version* "2.9.0")
(setq *ADS:namespace* "ADS")
(setq *ADS:appdata-folder* "AutoLoadDimStyle")

;;; ============================================================================
;;; GLOBALE VARIABLEN
;;; ============================================================================

(setq *ADS:initialized* nil)
(setq *ADS:log-session-id* nil)
(setq *ADS:debug-mode* nil)

;;; ============================================================================
;;; APPDATA-PFAD
;;; ============================================================================

;;; Gibt den Basis-AppData-Ordner fuer dieses Script zurueck
;;; Erstellt die komplette Ordnerstruktur falls nicht vorhanden
;;; Rueckgabe: Basis-Pfad-String
(defun ADS:get-appdata-path ( / acad-dir lisp-dir base-dir)
  (setq acad-dir (strcat (getenv "APPDATA") "\\AutoCAD"))
  (setq lisp-dir (strcat acad-dir "\\Lisp"))
  (setq base-dir (strcat lisp-dir "\\" *ADS:appdata-folder*))

  ;; Ordnerhierarchie sicherstellen
  (if (not (vl-file-directory-p acad-dir))
    (vl-mkdir acad-dir)
  )
  (if (not (vl-file-directory-p lisp-dir))
    (vl-mkdir lisp-dir)
  )
  (if (not (vl-file-directory-p base-dir))
    (vl-mkdir base-dir)
  )

  ;; Unterordner sicherstellen
  (if (not (vl-file-directory-p (strcat base-dir "\\Log")))
    (vl-mkdir (strcat base-dir "\\Log"))
  )
  (if (not (vl-file-directory-p (strcat base-dir "\\Config")))
    (vl-mkdir (strcat base-dir "\\Config"))
  )
  (if (not (vl-file-directory-p (strcat base-dir "\\Backup")))
    (vl-mkdir (strcat base-dir "\\Backup"))
  )

  base-dir
)

;;; Gibt den Log-Ordner zurueck
(defun ADS:get-log-path ( / )
  (strcat (ADS:get-appdata-path) "\\Log")
)

;;; Gibt den Config-Ordner zurueck
(defun ADS:get-config-path ( / )
  (strcat (ADS:get-appdata-path) "\\Config")
)

;;; Gibt den vollen Pfad zur Config-Datei zurueck
(defun ADS:get-config-file ( / )
  (strcat (ADS:get-config-path) "\\" *ADS:appdata-folder* ".cfg")
)

;;; Stellt sicher dass der AppData-Ordner existiert
(defun ADS:ensure-appdata ( / path)
  (setq path (ADS:get-appdata-path))
  (if (vl-file-directory-p path)
    T
    nil
  )
)

;;; ============================================================================
;;; LOGGING
;;; ============================================================================

;;; Schreibt eine Zeile ins Session-Log
(defun ADS:log-write (level message / log-dir log-path fp timestamp)
  (if (and (= level "DEBUG") (not *ADS:debug-mode*))
    nil
    (progn
      ;; Session-Log-Pfad ermitteln (einmal pro Session)
      (if (not *ADS:log-session-id*)
        (progn
          (setq *ADS:log-session-id*
            (strcat *ADS:appdata-folder* "_"
              (menucmd "M=$(edtime,0,YYYYMMDD\"_\"HHMMSS)")
            )
          )
          (ADS:log-rotate)
        )
      )

      (setq log-dir (ADS:get-log-path))
      (setq log-path (strcat log-dir "\\" *ADS:log-session-id* ".log"))
      (setq timestamp (menucmd "M=$(edtime,0,YYYY\"-\"MO\"-\"DD\" \"HH\":\"MM\":\"SS)"))

      (setq fp (open log-path "a"))
      (if fp
        (progn
          (write-line
            (strcat "[" timestamp "] ["
              (substr (strcat level "     ") 1 5)
              "] " message)
            fp)
          (close fp)
        )
      )
    )
  )
)

;;; Loescht alte Logs, behaelt nur die 5 neuesten
(defun ADS:log-rotate ( / log-dir files sorted-files delete-count i)
  (setq log-dir (ADS:get-log-path))
  (setq files (vl-directory-files log-dir (strcat *ADS:appdata-folder* "_*.log") 1))

  (if files
    (progn
      (setq sorted-files (vl-sort files '<))
      (setq delete-count (- (length sorted-files) 4))
      (if (> delete-count 0)
        (progn
          (setq i 0)
          (repeat delete-count
            (vl-file-delete (strcat log-dir "\\" (nth i sorted-files)))
            (setq i (1+ i))
          )
        )
      )
    )
  )
)

;;; ============================================================================
;;; CANCEL-DETECTION
;;; ============================================================================

;;; Prueft ob User abgebrochen hat (ESC, Cancel, etc.)
;;; Funktioniert in deutscher UND englischer AutoCAD-Version
(defun ADS:cancel-p (msg / )
  (wcmatch (strcase msg)
    "*ABBRUCH*,*ABGEBROCHEN*,*CANCEL*,*QUIT*,*EXIT*"
  )
)

;;; ============================================================================
;;; DEBUG
;;; ============================================================================

;;; Debug-Modus umschalten
(defun c:ADSDEBUG ( / )
  (setq *ADS:debug-mode* (not *ADS:debug-mode*))
  (princ (strcat "\nDebug-Modus: "
    (if *ADS:debug-mode* "EIN" "AUS")))
  (ADS:log-write "INFO"
    (strcat "Debug-Modus: " (if *ADS:debug-mode* "EIN" "AUS")))
  (princ)
)

;;; ============================================================================
;;; LAZY-INIT
;;; ============================================================================

;;; Initialisierung (wird nur 1x ausgefuehrt, beim ersten Befehlsaufruf)
(defun ADS:ensure-init ( / )
  (if (not *ADS:initialized*)
    (progn
      (vl-load-com)
      (ADS:ensure-appdata)
      (setq *ADS:initialized* T)
      (ADS:log-write "INFO" "Initialisierung abgeschlossen (Lazy-Init)")
    )
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - CONFIG MANAGEMENT
;;; ============================================================================

;;; Liest alle gespeicherten Pfade aus Konfigurationsdatei
(defun ADS:read-master-files ( / cfg-path file line files version)
  (setq files '())
  (setq cfg-path (ADS:get-config-file))

  ;; Migration: alte Config v1
  (if (and (not (findfile cfg-path))
           (findfile (strcat (getenv "APPDATA") "\\AutoCAD\\DimStyleConfig.txt")))
    (progn
      (ADS:log-write "INFO" "Migration: Alte Config v1 gefunden (DimStyleConfig.txt)")
      (ADS:migrate-old-config)
    )
  )

  ;; Migration: alte Config v2
  (if (and (not (findfile cfg-path))
           (findfile (strcat (getenv "APPDATA") "\\AutoCAD\\AutoLoadDimStyle\\AutoLoadDimStyle.cfg")))
    (progn
      (ADS:log-write "INFO" "Migration: Alte Config v2 gefunden (ohne Lisp\\)")
      (ADS:migrate-old-config-v2)
    )
  )

  (if (and (findfile cfg-path)
           (setq file (open cfg-path "r")))
    (progn
      (setq version (read-line file))
      (while (setq line (read-line file))
        (if (and line (> (strlen line) 0))
          (setq files (cons line files))
        )
      )
      (setq files (reverse files))
      (close file)
      (setq file nil)
      (ADS:log-write "DEBUG"
        (strcat "Config geladen: " (itoa (length files)) " Master-Datei(en)"))
    )
  )
  files
)

;;; Speichert Liste von Pfaden in Konfigurationsdatei
(defun ADS:save-master-files (filepaths / cfg-path file)
  (ADS:ensure-appdata)
  (setq cfg-path (ADS:get-config-file))

  (if (setq file (open cfg-path "w"))
    (progn
      (write-line *ADS:version* file)
      (foreach filepath filepaths
        (write-line filepath file)
      )
      (close file)
      (setq file nil)
      (ADS:log-write "INFO"
        (strcat "Config gespeichert: " (itoa (length filepaths)) " Master-Datei(en)"))
      T
    )
    (progn
      (ADS:log-write "ERROR" (strcat "Config schreiben fehlgeschlagen: " cfg-path))
      nil
    )
  )
)

;;; Migriert alte Config von %APPDATA%\AutoCAD\DimStyleConfig.txt
(defun ADS:migrate-old-config ( / old-path old-file line files version new-ok)
  (setq old-path (strcat (getenv "APPDATA") "\\AutoCAD\\DimStyleConfig.txt"))
  (setq files '())

  (if (and (findfile old-path)
           (setq old-file (open old-path "r")))
    (progn
      (setq version (read-line old-file))
      (while (setq line (read-line old-file))
        (if (and line (> (strlen line) 0))
          (setq files (cons line files))
        )
      )
      (setq files (reverse files))
      (close old-file)

      (if files
        (progn
          (setq new-ok (ADS:save-master-files files))
          (if new-ok
            (progn
              (ADS:log-write "INFO"
                (strcat "Migration v1 erfolgreich: " (itoa (length files)) " Datei(en)"))
              (vl-file-delete old-path)
            )
            (ADS:log-write "ERROR" "Migration v1 fehlgeschlagen")
          )
        )
        (ADS:log-write "WARN" "Migration v1: Alte Config war leer")
      )
    )
  )
)

;;; Migriert alte Config von %APPDATA%\AutoCAD\AutoLoadDimStyle\AutoLoadDimStyle.cfg
(defun ADS:migrate-old-config-v2 ( / old-path old-file line files version new-ok)
  (setq old-path (strcat (getenv "APPDATA") "\\AutoCAD\\AutoLoadDimStyle\\AutoLoadDimStyle.cfg"))
  (setq files '())

  (if (and (findfile old-path)
           (setq old-file (open old-path "r")))
    (progn
      (setq version (read-line old-file))
      (while (setq line (read-line old-file))
        (if (and line (> (strlen line) 0))
          (setq files (cons line files))
        )
      )
      (setq files (reverse files))
      (close old-file)

      (if files
        (progn
          (setq new-ok (ADS:save-master-files files))
          (if new-ok
            (progn
              (ADS:log-write "INFO"
                (strcat "Migration v2 erfolgreich: " (itoa (length files)) " Datei(en)"))
              (vl-file-delete old-path)
            )
            (ADS:log-write "ERROR" "Migration v2 fehlgeschlagen")
          )
        )
        (ADS:log-write "WARN" "Migration v2: Alte Config war leer")
      )
    )
  )
)

;;; Fuegt einen Pfad zur Liste hinzu
(defun ADS:add-master-file (filepath / files)
  (setq files (ADS:read-master-files))
  (if (not (member filepath files))
    (progn
      (setq files (append files (list filepath)))
      (ADS:save-master-files files)
      (ADS:log-write "INFO" (strcat "Master-Datei hinzugefuegt: " filepath))
      T
    )
    (progn
      (ADS:log-write "WARN" (strcat "Master-Datei bereits vorhanden: " filepath))
      nil
    )
  )
)

;;; Entfernt einen Pfad aus der Liste
(defun ADS:remove-master-file (filepath / files)
  (setq files (ADS:read-master-files))
  (setq files (vl-remove filepath files))
  (ADS:save-master-files files)
  (ADS:log-write "INFO" (strcat "Master-Datei entfernt: " filepath))
)

;;; Prueft ob Pfad eine gueltige DWG-Datei ist
(defun ADS:valid-dwg-file-p (filepath / ext)
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

;;; Fuehrt Erst-Konfiguration durch (beim ersten Aufruf)
(defun ADS:first-time-setup ( / selected-file)
  (ADS:log-write "INFO" "First-Time Setup gestartet")

  (princ "\n+===========================================================+")
  (princ "\n|  WILLKOMMEN BEI AUTOLOADDIMSTYLE                          |")
  (princ "\n+===========================================================+")
  (princ "\n\nKeine Konfiguration gefunden.")
  (princ "\nBitte waehlen Sie Ihre erste Master-Datei mit Bemassungsstilen.")
  (princ "\n")

  (if (setq selected-file (getfiled "Master-Datei mit Bemassungsstilen auswaehlen" "" "dwg" 0))
    (if (ADS:valid-dwg-file-p selected-file)
      (progn
        (ADS:save-master-files (list selected-file))
        (princ (strcat "\n\nOK Konfiguration erstellt: " selected-file))
        (princ "\nDie Datei wird ab jetzt automatisch geladen.")
        (ADS:log-write "INFO" (strcat "First-Time Setup abgeschlossen: " selected-file))
        T
      )
      (progn
        (princ "\n\nFEHLER Keine gueltige DWG-Datei ausgewaehlt.")
        (ADS:log-write "WARN" "First-Time Setup: Keine gueltige DWG gewaehlt")
        nil
      )
    )
    (progn
      (princ "\n\nKeine Datei ausgewaehlt.")
      (princ "\nSie koennen spaeter 'DimStyleManager' -> 'Hinzufuegen' verwenden.")
      (ADS:log-write "INFO" "First-Time Setup: User hat abgebrochen")
      nil
    )
  )
)

;;; ============================================================================
;;; DCL DIALOG - EMBEDDED DCL PATTERN
;;; ============================================================================

;;; Schreibt den Haupt-Dialog als temporaere DCL-Datei
;;; Rueckgabe: Pfad zur temporaeren DCL-Datei
(defun ADS:write-main-dcl ( / dcl-file fp)
  (setq dcl-file (vl-filename-mktemp "ads_main" nil ".dcl"))
  (setq fp (open dcl-file "w"))

  ;; ---- Haupt-Dialog ----
  (write-line "ads_main : dialog {" fp)
  (write-line (strcat "  label = \"Bemasstil-Manager v" *ADS:version* "\";") fp)
  (write-line "  initial_focus = \"btn_laden\";" fp)
  (write-line "" fp)

  ;; Info-Text
  (write-line "  : text {" fp)
  (write-line "    label = \"Master-Dateien:\";" fp)
  (write-line "  }" fp)
  (write-line "" fp)

  ;; Datei-Liste
  (write-line "  : list_box {" fp)
  (write-line "    key = \"file_list\";" fp)
  (write-line "    width = 65;" fp)
  (write-line "    height = 10;" fp)
  (write-line "    multiple_select = false;" fp)
  (write-line "    fixed_width_font = true;" fp)
  (write-line "  }" fp)
  (write-line "" fp)

  ;; Status-Text (zeigt Pfad der selektierten Datei)
  (write-line "  : text {" fp)
  (write-line "    key = \"status_text\";" fp)
  (write-line "    width = 65;" fp)
  (write-line "    label = \"\";" fp)
  (write-line "  }" fp)
  (write-line "" fp)

  ;; Buttons: Laden / Oeffnen
  (write-line "  : row {" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_laden\";" fp)
  (write-line "      label = \"Alle laden\";" fp)
  (write-line "      width = 16;" fp)
  (write-line "      mnemonic = \"L\";" fp)
  (write-line "    }" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_oeffnen\";" fp)
  (write-line "      label = \"Oeffnen\";" fp)
  (write-line "      width = 16;" fp)
  (write-line "      mnemonic = \"O\";" fp)
  (write-line "    }" fp)
  (write-line "    : spacer { width = 2; }" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_hinzu\";" fp)
  (write-line "      label = \"Hinzufuegen...\";" fp)
  (write-line "      width = 16;" fp)
  (write-line "      mnemonic = \"H\";" fp)
  (write-line "    }" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_entfernen\";" fp)
  (write-line "      label = \"Entfernen\";" fp)
  (write-line "      width = 16;" fp)
  (write-line "      mnemonic = \"E\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "" fp)

  ;; Trennlinie
  (write-line "  : spacer { height = 0.3; }" fp)
  (write-line "" fp)

  ;; Buttons: Einstellungen / Schliessen
  (write-line "  : row {" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_settings\";" fp)
  (write-line "      label = \"Einstellungen...\";" fp)
  (write-line "      width = 16;" fp)
  (write-line "    }" fp)
  (write-line "    : spacer { width = 34; }" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_close\";" fp)
  (write-line "      label = \"Schliessen\";" fp)
  (write-line "      width = 16;" fp)
  (write-line "      is_cancel = true;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)

  (write-line "}" fp)
  (write-line "" fp)

  ;; ---- Einstellungen Sub-Dialog ----
  (write-line "ads_settings : dialog {" fp)
  (write-line "  label = \"Einstellungen\";" fp)
  (write-line "" fp)

  ;; Pfade anzeigen
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Pfade\";" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"txt_config_path\";" fp)
  (write-line "      label = \"Config:\";" fp)
  (write-line "      width = 65;" fp)
  (write-line "      is_enabled = false;" fp)
  (write-line "    }" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"txt_log_path\";" fp)
  (write-line "      label = \"Log:\";" fp)
  (write-line "      width = 65;" fp)
  (write-line "      is_enabled = false;" fp)
  (write-line "    }" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"txt_appdata_path\";" fp)
  (write-line "      label = \"AppData:\";" fp)
  (write-line "      width = 65;" fp)
  (write-line "      is_enabled = false;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "" fp)

  ;; Optionen
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Optionen\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"tgl_debug\";" fp)
  (write-line "      label = \"Debug-Modus (ausfuehrliches Logging)\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "" fp)

  ;; Reset + Buttons
  (write-line "  : row {" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_reset\";" fp)
  (write-line "      label = \"Alle Pfade zuruecksetzen\";" fp)
  (write-line "      width = 25;" fp)
  (write-line "    }" fp)
  (write-line "    : spacer { width = 10; }" fp)
  (write-line "    : ok_button {" fp)
  (write-line "      label = \"OK\";" fp)
  (write-line "      width = 12;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)

  (write-line "}" fp)

  (close fp)
  (ADS:log-write "DEBUG" (strcat "DCL geschrieben: " dcl-file))
  dcl-file
)

;;; Erstellt die Anzeigeliste fuer die list_box
;;; Format pro Zeile: "Dateiname.dwg                    [OK]" oder "[FEHLER]"
;;; Rueckgabe: Liste von Strings
(defun ADS:build-file-list-strings (master-files / result name status line pad-len)
  (setq result '())
  (foreach mf master-files
    (setq name (strcat (vl-filename-base mf) (vl-filename-extension mf)))
    (if (findfile mf)
      (setq status "[OK]")
      (setq status "[FEHLER]")
    )
    ;; Padding auf 50 Zeichen fuer Ausrichtung
    (setq pad-len (- 50 (strlen name)))
    (if (< pad-len 1) (setq pad-len 1))
    (setq line (strcat name (ADS:make-spaces pad-len) status))
    (setq result (cons line result))
  )
  (reverse result)
)

;;; Erzeugt einen String aus n Leerzeichen
(defun ADS:make-spaces (n / result)
  (setq result "")
  (repeat n
    (setq result (strcat result " "))
  )
  result
)

;;; Fuellt die list_box mit Master-Dateien
(defun ADS:refresh-file-list (dcl-id master-files / display-list)
  (setq display-list (ADS:build-file-list-strings master-files))
  (start_list "file_list")
  (foreach item display-list
    (add_list item)
  )
  (end_list)
  ;; Status-Text aktualisieren
  (set_tile "status_text"
    (strcat (itoa (length master-files)) " Master-Datei(en) konfiguriert"))
)

;;; ============================================================================
;;; DCL DIALOG - HAUPT-DIALOG ANZEIGEN
;;; ============================================================================

;;; Zeigt den Haupt-Dialog an und verarbeitet Aktionen
;;; Rueckgabe: nil
(defun ADS:show-main-dialog ( / dcl-file dcl-id dialog-result master-files
                                selected-idx selected-file new-file
                                acad-obj docs new-doc
                                old-cmdecho old-attreq loaded-count failed-count)

  ;; DCL schreiben
  (setq dcl-file (ADS:write-main-dcl))
  (setq dcl-id (load_dialog dcl-file))

  (if (not (new_dialog "ads_main" dcl-id))
    (progn
      (ADS:log-write "ERROR" "Haupt-Dialog konnte nicht geoeffnet werden")
      (alert "FEHLER: Dialog konnte nicht geoeffnet werden!")
      (unload_dialog dcl-id)
      (vl-file-delete dcl-file)
      (exit)
    )
  )

  ;; Master-Dateien laden und Liste fuellen
  (setq master-files (ADS:read-master-files))
  (ADS:refresh-file-list dcl-id master-files)

  ;; --- Action Tiles ---

  ;; Liste: Bei Selektion Pfad im Status anzeigen
  (action_tile "file_list"
    "(progn
       (setq *ADS:dlg-selected-idx* (atoi $value))
       (if (and master-files (nth *ADS:dlg-selected-idx* master-files))
         (set_tile \"status_text\" (nth *ADS:dlg-selected-idx* master-files))
       )
     )"
  )

  ;; Button: Alle laden → done_dialog mit Code 2
  (action_tile "btn_laden" "(done_dialog 2)")

  ;; Button: Oeffnen → done_dialog mit Code 3
  (action_tile "btn_oeffnen" "(done_dialog 3)")

  ;; Button: Hinzufuegen → done_dialog mit Code 4
  (action_tile "btn_hinzu" "(done_dialog 4)")

  ;; Button: Entfernen → done_dialog mit Code 5
  (action_tile "btn_entfernen"
    "(progn
       (setq *ADS:dlg-selected-idx* (get_tile \"file_list\"))
       (if (= *ADS:dlg-selected-idx* \"\")
         (setq *ADS:dlg-selected-idx* nil)
         (setq *ADS:dlg-selected-idx* (atoi *ADS:dlg-selected-idx*))
       )
       (done_dialog 5)
     )"
  )

  ;; Button: Einstellungen → done_dialog mit Code 6
  (action_tile "btn_settings" "(done_dialog 6)")

  ;; Button: Schliessen → done_dialog mit Code 1
  (action_tile "btn_close" "(done_dialog 1)")

  ;; --- Dialog-Schleife (Re-Open nach Aktionen) ---
  (setq *ADS:dlg-selected-idx* nil)
  (setq dialog-result (start_dialog))
  (unload_dialog dcl-id)

  ;; Aktion ausfuehren basierend auf dialog-result
  (cond
    ;; 1 = Schliessen
    ((= dialog-result 1)
      (ADS:log-write "INFO" "Dialog: Schliessen")
    )

    ;; 2 = Alle laden
    ((= dialog-result 2)
      (ADS:log-write "INFO" "Dialog: Alle laden")
      (setq master-files (ADS:read-master-files))
      (if master-files
        (progn
          (setq old-cmdecho (getvar "CMDECHO"))
          (setq old-attreq (getvar "ATTREQ"))
          (setvar "CMDECHO" 0)
          (setvar "ATTREQ" 0)
          (setq loaded-count 0)
          (setq failed-count 0)

          (foreach mf master-files
            (if (findfile mf)
              (progn
                (command "._-insert" mf nil)
                (ADS:log-write "INFO" (strcat "Geladen: " (vl-filename-base mf)))
                (setq loaded-count (1+ loaded-count))
              )
              (progn
                (ADS:log-write "ERROR" (strcat "Nicht gefunden: " mf))
                (setq failed-count (1+ failed-count))
              )
            )
          )

          (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
          (if old-attreq (setvar "ATTREQ" old-attreq))

          (princ (strcat "\n" (itoa loaded-count) " Datei(en) geladen"))
          (if (> failed-count 0)
            (princ (strcat ", " (itoa failed-count) " fehlgeschlagen"))
          )
          (ADS:log-write "INFO"
            (strcat "Laden: " (itoa loaded-count) " OK, " (itoa failed-count) " Fehler"))
        )
        (princ "\nKeine Master-Dateien konfiguriert.")
      )
      ;; Dialog erneut oeffnen
      (ADS:show-main-dialog)
    )

    ;; 3 = Oeffnen
    ((= dialog-result 3)
      (ADS:log-write "INFO" "Dialog: Oeffnen")
      (setq master-files (ADS:read-master-files))
      (if (and *ADS:dlg-selected-idx*
               master-files
               (nth *ADS:dlg-selected-idx* master-files))
        (progn
          (setq selected-file (nth *ADS:dlg-selected-idx* master-files))
          (if (findfile selected-file)
            (progn
              (ADS:log-write "INFO" (strcat "Oeffne: " selected-file))
              (setq acad-obj (vlax-get-acad-object))
              (setq docs (vla-get-documents acad-obj))
              (setq new-doc (vla-open docs selected-file))
              (vla-activate new-doc)
              (princ (strcat "\nGeoeffnet: " (vl-filename-base selected-file)))
              (ADS:log-write "INFO" "Master-Datei geoeffnet und aktiviert")
            )
            (progn
              (alert (strcat "Datei nicht gefunden:\n" selected-file))
              (ADS:log-write "ERROR" (strcat "Datei nicht gefunden: " selected-file))
              (ADS:show-main-dialog)
            )
          )
        )
        (progn
          (alert "Bitte waehlen Sie zuerst eine Datei aus der Liste.")
          (ADS:show-main-dialog)
        )
      )
    )

    ;; 4 = Hinzufuegen
    ((= dialog-result 4)
      (ADS:log-write "INFO" "Dialog: Hinzufuegen")
      (if (setq new-file (getfiled "Master-Datei hinzufuegen" "" "dwg" 0))
        (if (ADS:valid-dwg-file-p new-file)
          (if (ADS:add-master-file new-file)
            (princ (strcat "\nHinzugefuegt: " (vl-filename-base new-file)))
            (alert "Diese Datei ist bereits in der Liste.")
          )
          (alert "Keine gueltige DWG-Datei ausgewaehlt.")
        )
        (ADS:log-write "INFO" "Hinzufuegen: Abgebrochen")
      )
      ;; Dialog erneut oeffnen
      (ADS:show-main-dialog)
    )

    ;; 5 = Entfernen
    ((= dialog-result 5)
      (ADS:log-write "INFO" "Dialog: Entfernen")
      (setq master-files (ADS:read-master-files))
      (if (and *ADS:dlg-selected-idx*
               (numberp *ADS:dlg-selected-idx*)
               master-files
               (nth *ADS:dlg-selected-idx* master-files))
        (progn
          (setq selected-file (nth *ADS:dlg-selected-idx* master-files))
          (ADS:remove-master-file selected-file)
          (princ (strcat "\nEntfernt: " (vl-filename-base selected-file)))
        )
        (alert "Bitte waehlen Sie zuerst eine Datei aus der Liste.")
      )
      ;; Dialog erneut oeffnen
      (ADS:show-main-dialog)
    )

    ;; 6 = Einstellungen
    ((= dialog-result 6)
      (ADS:log-write "INFO" "Dialog: Einstellungen")
      (ADS:show-settings-dialog dcl-file)
      ;; Dialog erneut oeffnen
      (ADS:show-main-dialog)
    )
  )

  ;; DCL-Datei aufraeumen
  (if (findfile dcl-file)
    (vl-file-delete dcl-file)
  )
)

;;; ============================================================================
;;; DCL DIALOG - EINSTELLUNGEN SUB-DIALOG
;;; ============================================================================

;;; Zeigt den Einstellungen-Dialog
;;; dcl-file: Pfad zur bereits geschriebenen DCL-Datei (enthaelt ads_settings)
(defun ADS:show-settings-dialog (dcl-file / dcl-id dialog-result)

  (setq dcl-id (load_dialog dcl-file))

  (if (not (new_dialog "ads_settings" dcl-id))
    (progn
      (ADS:log-write "ERROR" "Einstellungen-Dialog konnte nicht geoeffnet werden")
      (unload_dialog dcl-id)
      (exit)
    )
  )

  ;; Pfade anzeigen
  (set_tile "txt_config_path" (ADS:get-config-file))
  (set_tile "txt_log_path" (ADS:get-log-path))
  (set_tile "txt_appdata_path" (ADS:get-appdata-path))

  ;; Debug-Toggle setzen
  (if *ADS:debug-mode*
    (set_tile "tgl_debug" "1")
    (set_tile "tgl_debug" "0")
  )

  ;; Action: Debug-Toggle Wert in globale Variable speichern (VOR done_dialog!)
  (action_tile "tgl_debug"
    "(setq *ADS:dlg-debug-val* $value)"
  )

  ;; Action: Reset
  (action_tile "btn_reset"
    "(progn
       (setq *ADS:dlg-reset-flag* T)
       (done_dialog 2)
     )"
  )

  ;; Action: OK
  (action_tile "accept"
    "(progn
       (setq *ADS:dlg-debug-val* (get_tile \"tgl_debug\"))
       (done_dialog 1)
     )"
  )

  ;; Defaults
  (setq *ADS:dlg-debug-val* (if *ADS:debug-mode* "1" "0"))
  (setq *ADS:dlg-reset-flag* nil)

  (setq dialog-result (start_dialog))
  (unload_dialog dcl-id)

  ;; Ergebnis verarbeiten
  (cond
    ;; OK
    ((= dialog-result 1)
      ;; Debug-Modus uebernehmen
      (setq *ADS:debug-mode* (= *ADS:dlg-debug-val* "1"))
      (ADS:log-write "INFO"
        (strcat "Einstellungen: Debug-Modus " (if *ADS:debug-mode* "EIN" "AUS")))
    )

    ;; Reset
    ((= dialog-result 2)
      (if *ADS:dlg-reset-flag*
        (progn
          (setq cfg-path (ADS:get-config-file))
          (if (findfile cfg-path)
            (progn
              (vl-file-delete cfg-path)
              (ADS:log-write "INFO" "Config zurueckgesetzt (Reset via Einstellungen)")
              (alert "Alle Pfade wurden zurueckgesetzt.\nBeim naechsten Aufruf werden Sie nach einer Master-Datei gefragt.")
            )
            (alert "Keine gespeicherten Pfade vorhanden.")
          )
        )
      )
    )
  )
)

;;; ============================================================================
;;; HAUPTFUNKTIONEN
;;; ============================================================================

;;; DCL-Dialog fuer Bemassungsstil-Verwaltung (HAUPTBEFEHL)
(defun c:DimStyleManager ( / *error*)

  ;; Lazy-Init (IMMER erste Zeile!)
  (ADS:ensure-init)

  ;; Lokaler Error-Handler mit wcmatch Cancel-Detection (DE + EN)
  (defun *error* (msg)
    (if (not (ADS:cancel-p msg))
      (progn
        (princ "\n*** Fehler im Bemasstil-Manager ***")
        (princ (strcat "\nFehlermeldung: " msg))
        (ADS:log-write "ERROR" (strcat "DimStyleManager Error-Handler: " msg))
      )
    )
    (princ)
  )

  (ADS:log-write "INFO" "=== Befehl DimStyleManager gestartet ===")

  ;; ERST-KONFIGURATION wenn keine Config vorhanden
  (if (null (ADS:read-master-files))
    (if (not (ADS:first-time-setup))
      (progn
        (ADS:log-write "INFO" "DimStyleManager: First-Time Setup abgebrochen, beende")
        (princ)
        (exit)
      )
    )
  )

  ;; DCL-Dialog anzeigen
  (ADS:show-main-dialog)

  (ADS:log-write "INFO" "=== Befehl DimStyleManager beendet ===")
  (princ)
)

;;; Laedt alle Bemassungsstile AUTOMATISCH (silent, fuer S::STARTUP)
(defun c:AutoLoadDimStyles ( / *error* master-files old-cmdecho old-attreq)

  ;; Lazy-Init (IMMER erste Zeile!)
  (ADS:ensure-init)

  ;; Lokaler Error-Handler mit wcmatch Cancel-Detection (DE + EN)
  (defun *error* (msg)
    (if (not (ADS:cancel-p msg))
      (ADS:log-write "ERROR" (strcat "AutoLoadDimStyles Error-Handler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-attreq (setvar "ATTREQ" old-attreq))
    (princ)
  )

  (ADS:log-write "INFO" "=== Befehl AutoLoadDimStyles (Autostart) gestartet ===")

  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-attreq (getvar "ATTREQ"))
  (setvar "CMDECHO" 0)
  (setvar "ATTREQ" 0)

  ;; Hole Master-Dateien
  (setq master-files (ADS:read-master-files))

  ;; Falls keine Config: ERST-KONFIGURATION
  (if (null master-files)
    (progn
      (ADS:log-write "INFO" "Autostart: Keine Config, starte First-Time Setup")
      (if (ADS:first-time-setup)
        (setq master-files (ADS:read-master-files))
      )
    )
  )

  ;; Lade Master-Dateien
  (if master-files
    (progn
      (foreach master-file master-files
        (if (findfile master-file)
          (progn
            (command "._-insert" master-file nil)
            (ADS:log-write "INFO" (strcat "Autostart geladen: " (vl-filename-base master-file)))
          )
          (ADS:log-write "ERROR" (strcat "Autostart nicht gefunden: " master-file))
        )
      )
      (ADS:log-write "INFO"
        (strcat "Autostart abgeschlossen: " (itoa (length master-files)) " Datei(en)"))
    )
    (ADS:log-write "WARN" "Autostart: Keine Master-Dateien zum Laden")
  )

  ;; Systemvariablen wiederherstellen
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (if old-attreq (setvar "ATTREQ" old-attreq))

  ;; Memory freigeben
  (setq master-files nil)
  (princ)
)

;;; ============================================================================
;;; AUTOSTART
;;; ============================================================================

(defun S::STARTUP ( / )
  (c:AutoLoadDimStyles)
  (princ)
)

;;; ============================================================================
;;; INITIALISIERUNG - AUSGABE (NUR PRINC AUF TOP-LEVEL!)
;;; ============================================================================

(princ (strcat "\nAutoLoadDimStyle.lsp v" *ADS:version* " geladen."))
(princ "\n+===========================================================+")
(princ "\n|  Hauptbefehl: DimStyleManager (DCL-Dialog)                |")
(princ "\n|  Autostart:   AutoLoadDimStyles (silent)                  |")
(princ "\n|  Debug:       ADSDEBUG                                    |")
(princ "\n+===========================================================+")
(princ)

;;; HoeheAufLinie.lsp
;;; Hoeheninterpolation entlang einer Linie zwischen zwei Fixpunkten
;;; Speziell fuer Leica-Vermessungsarbeiten
;;;
;;; Version: 2.3.5
;;; Datum: 2026-03-19
;;; Autor: Herbert Schrotter
;;; Namespace: HAL (HoeheAufLinie)
;;;
;;; AppData: %APPDATA%\AutoCAD\Lisp\HoeheAufLinie\
;;;   - Log\    HoeheAufLinie_YYYYMMDD_HHMMSS.log (max 5 Sessions)
;;;   - Config\ HoeheAufLinie.cfg
;;;
;;; Installation:
;;; 1. Befehl APPLOAD in AutoCAD ausfuehren
;;; 2. HoeheAufLinie.lsp auswaehlen und laden
;;; 3. lib/BlockImport.lsp muss im selben Ordner oder Support-Pfad liegen
;;;
;;; Befehle:
;;; HoeheAufLinie (HAL) - Hoeheninterpolation (S/K/E Keywords)
;;; HALDEBUG            - Debug ein/aus

;;; ============================================================================
;;; KONSTANTEN (Top-Level erlaubt)
;;; ============================================================================

(setq *HAL:version* "2.3.1")
(setq *HAL:appdata-folder* "HoeheAufLinie")
(setq *HAL:blockname* "BLK_Hoehenkote")

;;; ============================================================================
;;; GLOBALE VARIABLEN (Top-Level erlaubt)
;;; ============================================================================

(if (not (boundp '*HAL:debug-mode*))
  (setq *HAL:debug-mode* nil)
)
(setq *HAL:initialized* nil)
(setq *HAL:last-height* nil)
(setq *HAL:log-session-id* nil)

;; Settings (Defaults, werden von Config ueberschrieben)
(setq *HAL:use-layer-suffix* T)
(setq *HAL:layer-suffix* "HK")
(setq *HAL:lineab-mode* "LINE")     ; "LINE" oder "XLINE"
(setq *HAL:lineab-keep* nil)        ; T = am Ende behalten
(setq *HAL:xline-keep* nil)         ; T = rote Konstruktionslinie behalten

;;; ============================================================================
;;; APPDATA & LOGGING (frueh definieren!)
;;; ============================================================================

(defun HAL:get-appdata-path ( / base parent)
  (setq parent (strcat (getenv "APPDATA") "\\AutoCAD\\Lisp"))
  (setq base (strcat parent "\\" *HAL:appdata-folder*))
  (if (not (vl-file-directory-p base))
    (progn
      (if (not (vl-file-directory-p (strcat (getenv "APPDATA") "\\AutoCAD")))
        (vl-mkdir (strcat (getenv "APPDATA") "\\AutoCAD"))
      )
      (if (not (vl-file-directory-p parent))
        (vl-mkdir parent)
      )
      (vl-mkdir base)
    )
  )
  base
)

(defun HAL:ensure-log-dir ( / appdata log-dir)
  (setq appdata (HAL:get-appdata-path))
  (setq log-dir (strcat appdata "\\Log"))
  (if (not (vl-file-directory-p log-dir))
    (vl-mkdir log-dir)
  )
  log-dir
)

(defun HAL:log-write (level message / log-dir log-path fp timestamp)
  (if (and (= level "DEBUG") (not *HAL:debug-mode*))
    nil
    (progn
      (if (not *HAL:log-session-id*)
        (progn
          (setq *HAL:log-session-id*
            (strcat *HAL:appdata-folder* "_"
              (menucmd "M=$(edtime,0,YYYYMMDD_HHMMSS)")))
          (HAL:log-rotate)
        )
      )
      (setq log-dir (HAL:ensure-log-dir))
      (setq log-path (strcat log-dir "\\" *HAL:log-session-id* ".log"))
      (setq timestamp (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM:SS)"))
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

(defun HAL:log-rotate ( / log-dir pattern files sorted-files delete-count i)
  (setq log-dir (HAL:ensure-log-dir))
  (setq pattern (strcat *HAL:appdata-folder* "_*.log"))
  (setq files (vl-directory-files log-dir pattern 1))
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

(defun HAL:debug (msg / )
  (HAL:log-write "DEBUG" msg)
  (if *HAL:debug-mode*
    (princ (strcat "\n  [DEBUG] " msg))
  )
)

;;; ============================================================================
;;; CONFIG-MANAGEMENT
;;; ============================================================================

(defun HAL:load-config ( / appdata cfg-path fp line pos key value)
  (setq appdata (HAL:get-appdata-path))
  (setq cfg-path (strcat appdata "\\Config\\" *HAL:appdata-folder* ".cfg"))
  
  (if (findfile cfg-path)
    (progn
      (setq fp (open cfg-path "r"))
      (if fp
        (progn
          (while (setq line (read-line fp))
            (if (setq pos (vl-string-search "=" line))
              (progn
                (setq key (substr line 1 pos))
                (setq value (substr line (+ pos 2)))
                (cond
                  ((= key "BLOCKIMPORTPATH")
                   (setq *HAL:blockimport-path* value)
                   (if (= *HAL:blockimport-path* "") (setq *HAL:blockimport-path* nil))
                  )
                  ((= key "DEBUG")
                   (setq *HAL:debug-mode* (= value "1"))
                  )
                  ((= key "USE_LAYER_SUFFIX")
                   (setq *HAL:use-layer-suffix* (/= value "0"))
                  )
                  ((= key "LAYER_SUFFIX")
                   (if (/= value "") (setq *HAL:layer-suffix* value))
                  )
                  ((= key "LINEAB_MODE")
                   (if (member value '("LINE" "XLINE")) (setq *HAL:lineab-mode* value))
                  )
                  ((= key "LINEAB_KEEP")
                   (setq *HAL:lineab-keep* (= value "1"))
                  )
                  ((= key "XLINE_KEEP")
                   (setq *HAL:xline-keep* (= value "1"))
                  )
                )
              )
            )
          )
          (close fp)
          (HAL:log-write "INFO" (strcat "Config geladen: " cfg-path))
        )
      )
    )
    (HAL:log-write "WARN" "Keine Config gefunden, verwende Defaults")
  )
)

(defun HAL:save-config ( / appdata cfg-dir cfg-path fp)
  (setq appdata (HAL:get-appdata-path))
  (setq cfg-dir (strcat appdata "\\Config"))
  (if (not (vl-file-directory-p cfg-dir))
    (vl-mkdir cfg-dir)
  )
  (setq cfg-path (strcat cfg-dir "\\" *HAL:appdata-folder* ".cfg"))
  
  (setq fp (open cfg-path "w"))
  (if fp
    (progn
      (write-line (strcat "VERSION=" *HAL:version*) fp)
      (write-line (strcat "BLOCKIMPORTPATH=" (if (and (boundp '*HAL:blockimport-path*) *HAL:blockimport-path*) *HAL:blockimport-path* "")) fp)
      (write-line (strcat "DEBUG=" (if *HAL:debug-mode* "1" "0")) fp)
      (write-line (strcat "USE_LAYER_SUFFIX=" (if *HAL:use-layer-suffix* "1" "0")) fp)
      (write-line (strcat "LAYER_SUFFIX=" *HAL:layer-suffix*) fp)
      (write-line (strcat "LINEAB_MODE=" *HAL:lineab-mode*) fp)
      (write-line (strcat "LINEAB_KEEP=" (if *HAL:lineab-keep* "1" "0")) fp)
      (write-line (strcat "XLINE_KEEP=" (if *HAL:xline-keep* "1" "0")) fp)
      (close fp)
      (HAL:log-write "INFO" (strcat "Config gespeichert: " cfg-path))
      T
    )
    (progn
      (HAL:log-write "ERROR" (strcat "Config schreiben fehlgeschlagen: " cfg-path))
      nil
    )
  )
)

;;; ============================================================================
;;; BIBLIOTHEK LADEN
;;; ============================================================================

(defun HAL:load-library ( / path)
  (setq path (if (boundp '*HAL:blockimport-path*) *HAL:blockimport-path* nil))
  (if (and path (not (findfile path)))
    (setq path nil)
  )
  (if (null path)
    (setq path
      (cond
        ((findfile "lib/BlockImport.lsp"))
        ((findfile "BlockImport.lsp"))
      )
    )
  )
  (if (null path)
    (progn
      (princ "\n*** BlockImport.lsp wird nicht im Support-Pfad gefunden ***")
      (princ "\nBitte waehlen Sie die Datei lib/BlockImport.lsp aus...")
      (setq path
        (getfiled "BlockImport.lsp auswaehlen"
                  (cond ((getvar "DWGPREFIX")) ((getenv "USERPROFILE")) (T ""))
                  "lsp" 0))
      (if (null path)
        (progn
          (HAL:log-write "ERROR" "BlockImport.lsp: User hat Auswahl abgebrochen")
          (alert "FEHLER: Keine Datei ausgewaehlt!")
          (exit)
        )
      )
    )
  )
  (if path
    (progn
      (load path)
      (setq *HAL:blockimport-path* path)
      (HAL:save-config)
      (HAL:log-write "INFO" (strcat "Library geladen: " path))
      T
    )
    nil
  )
)

;;; ============================================================================
;;; DWG CUSTOM PROPERTIES (Skalierung pro Zeichnung)
;;; ============================================================================

(defun HAL:safe-variant-value (val / )
  (cond
    ((= (type val) 'STR) val)
    ((= (type val) 'VLA-OBJECT) val)
    ((not (null val))
      (vl-catch-all-apply 'vlax-variant-value (list val))
    )
    (T nil)
  )
)

(defun HAL:dwg-custom-read (prop-name / si num-props i key val found result)
  (setq si (vl-catch-all-apply 'vla-get-SummaryInfo
             (list (vla-get-ActiveDocument (vlax-get-acad-object)))))
  (if (vl-catch-all-error-p si)
    (progn (HAL:log-write "ERROR" "SummaryInfo nicht verfuegbar") nil)
    (progn
      (setq found nil result nil)
      (setq num-props (vla-NumCustomInfo si))
      (if (> num-props 0)
        (progn
          (setq i 0)
          (while (and (< i num-props) (null found))
            (setq key "" val "")
            (vl-catch-all-apply
              '(lambda ()
                (vla-GetCustomByIndex si i 'key 'val)
                (setq key (HAL:safe-variant-value key))
                (setq val (HAL:safe-variant-value val))
                (if (= (strcase key) (strcase prop-name))
                  (progn (setq result val) (setq found T))
                )
              )
            )
            (setq i (1+ i))
          )
        )
      )
      (HAL:debug (strcat "HAL:dwg-custom-read: " prop-name "=" (if result result "nil")))
      result
    )
  )
)

(defun HAL:dwg-custom-write (prop-name prop-value / si num-props i key val found)
  (setq si (vl-catch-all-apply 'vla-get-SummaryInfo
             (list (vla-get-ActiveDocument (vlax-get-acad-object)))))
  (if (vl-catch-all-error-p si)
    (progn (HAL:log-write "ERROR" "SummaryInfo nicht verfuegbar") nil)
    (progn
      (setq found nil)
      (setq num-props (vla-NumCustomInfo si))
      (if (> num-props 0)
        (progn
          (setq i 0)
          (while (and (< i num-props) (null found))
            (setq key "" val "")
            (vl-catch-all-apply
              '(lambda ()
                (vla-GetCustomByIndex si i 'key 'val)
                (setq key (HAL:safe-variant-value key))
                (if (= (strcase key) (strcase prop-name))
                  (progn
                    (vla-SetCustomByIndex si i prop-name prop-value)
                    (setq found T)
                  )
                )
              )
            )
            (setq i (1+ i))
          )
        )
      )
      (if (not found)
        (vl-catch-all-apply 'vla-AddCustomInfo (list si prop-name prop-value))
      )
      (HAL:debug (strcat "HAL:dwg-custom-write: " prop-name "=" prop-value))
      (HAL:log-write "INFO" (strcat "DWG Custom Property: " prop-name "=" prop-value))
      T
    )
  )
)

(defun HAL:read-dwg-scale ( / val)
  (setq val (HAL:dwg-custom-read "HoehenkoteScale"))
  (if (and val (/= val ""))
    (atof val)
    nil
  )
)

(defun HAL:write-dwg-scale (scale-value / )
  (HAL:dwg-custom-write "HoehenkoteScale" (rtos scale-value 2 6))
)

;;; ============================================================================
;;; LAZY-INIT
;;; ============================================================================

(defun HAL:ensure-init ( / )
  (if (not *HAL:initialized*)
    (progn
      (vl-load-com)
      (HAL:load-config)
      (HAL:load-library)
      (setq *HAL:initialized* T)
      (HAL:log-write "INFO" (strcat "=== HoeheAufLinie v" *HAL:version* " initialisiert ==="))
    )
  )
)

;;; ============================================================================
;;; HK-LAYER MANAGEMENT
;;; ============================================================================

;;; Erstellt Layer mit konfiguriertem Suffix basierend auf aktuellem Layer
;;; Kopiert via VLA: Farbe (ACI+TrueColor), Linientyp, Linienstaerke, Plot, Transparenz
;;; Rueckgabe: Name des Ziel-Layers (String) oder nil bei Fehler
(defun HAL:ensure-hk-layer ( / cur-layer hk-layer-name suffix-with-sep suffix-len
                                doc layers src-layer new-layer color-obj transp-val)
  (setq cur-layer (getvar "CLAYER"))
  (setq suffix-with-sep (strcat "_" *HAL:layer-suffix*))
  (setq suffix-len (strlen suffix-with-sep))
  
  ;; Pruefen ob aktueller Layer schon auf _<suffix> endet
  (if (and (>= (strlen cur-layer) suffix-len)
           (= (strcase (substr cur-layer (- (strlen cur-layer) suffix-len -1)))
              (strcase suffix-with-sep)))
    (progn
      (HAL:debug (strcat "Layer endet auf " suffix-with-sep ", verwende direkt: " cur-layer))
      cur-layer
    )
    (progn
      (setq hk-layer-name (strcat cur-layer suffix-with-sep))
      (HAL:debug (strcat "Layer: " cur-layer " -> " hk-layer-name))
      
      (if (tblsearch "LAYER" hk-layer-name)
        (progn
          (HAL:debug (strcat "Layer existiert bereits: " hk-layer-name))
          hk-layer-name
        )
        (progn
          (setq doc (vla-get-activedocument (vlax-get-acad-object)))
          (setq layers (vla-get-layers doc))
          (setq src-layer (vla-item layers cur-layer))
          
          (setq new-layer
            (vl-catch-all-apply 'vla-add (list layers hk-layer-name)))
          
          (if (vl-catch-all-error-p new-layer)
            (progn
              (HAL:log-write "ERROR"
                (strcat "Layer erstellen fehlgeschlagen: " hk-layer-name
                        " - " (vl-catch-all-error-message new-layer)))
              nil
            )
            (progn
              ;; Properties vom Quell-Layer kopieren
              (vl-catch-all-apply 'vla-put-color
                (list new-layer (vla-get-color src-layer)))
              
              (setq color-obj
                (vl-catch-all-apply 'vla-get-truecolor (list src-layer)))
              (if (and color-obj (not (vl-catch-all-error-p color-obj)))
                (vl-catch-all-apply 'vla-put-truecolor (list new-layer color-obj))
              )
              
              (vl-catch-all-apply 'vla-put-linetype
                (list new-layer (vla-get-linetype src-layer)))
              (vl-catch-all-apply 'vla-put-lineweight
                (list new-layer (vla-get-lineweight src-layer)))
              (vl-catch-all-apply 'vla-put-plottable
                (list new-layer (vla-get-plottable src-layer)))
              ;; Transparency: Getter separat absichern (nicht alle Layer haben Transparency)
              (setq transp-val
                (vl-catch-all-apply 'vla-get-transparency (list src-layer)))
              (if (and transp-val (not (vl-catch-all-error-p transp-val)))
                (vl-catch-all-apply 'vla-put-transparency (list new-layer transp-val))
              )
              
              (HAL:log-write "INFO"
                (strcat "Layer erstellt: " hk-layer-name " (kopiert von " cur-layer ")"))
              hk-layer-name
            )
          )
        )
      )
    )
  )
)

;;; ============================================================================
;;; DCL SETTINGS DIALOG
;;; ============================================================================

;;; Schreibt die DCL-Datei als Temp-Datei
(defun HAL:write-settings-dcl ( / dcl-file fp)
  (setq dcl-file (vl-filename-mktemp "hal" nil ".dcl"))
  (setq fp (open dcl-file "w"))
  
  (write-line "hal_settings : dialog {" fp)
  (write-line "  label = \"HoeheAufLinie - Einstellungen\";" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Skalierung ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"XY-Skalierung\";" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"scale\";" fp)
  (write-line "      label = \"Aktuelle Zeichnung:\";" fp)
  (write-line "      edit_width = 10;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Layer ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Layer\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"use_suffix\";" fp)
  (write-line "      label = \"Eigener Layer fuer Hoehenkoten\";" fp)
  (write-line "    }" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"layer_suffix\";" fp)
  (write-line "      label = \"Suffix (nach _):\";" fp)
  (write-line "      edit_width = 15;" fp)
  (write-line "    }" fp)
  (write-line "    : text {" fp)
  (write-line "      key = \"layer_preview\";" fp)
  (write-line "      label = \"\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Linie A-B ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Linie A-B (gelb)\";" fp)
  (write-line "    : radio_column {" fp)
  (write-line "      key = \"lineab_mode\";" fp)
  (write-line "      : radio_button {" fp)
  (write-line "        key = \"mode_line\";" fp)
  (write-line "        label = \"Linie (nur zwischen A und B)\";" fp)
  (write-line "      }" fp)
  (write-line "      : radio_button {" fp)
  (write-line "        key = \"mode_xline\";" fp)
  (write-line "        label = \"XLine (unendlich, verlaengerbar)\";" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"lineab_keep\";" fp)
  (write-line "      label = \"Am Ende behalten (nicht loeschen)\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Konstruktionslinie (rot) ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Konstruktionslinie (rot)\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"xline_keep\";" fp)
  (write-line "      label = \"Am Ende behalten (nicht loeschen)\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Block-Verwaltung ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Hoehenkoten-Block\";" fp)
  (write-line "    : text {" fp)
  (write-line "      key = \"blockname_info\";" fp)
  (write-line "      label = \"\";" fp)
  (write-line "    }" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_block\";" fp)
  (write-line "      label = \"Block-Verwaltung oeffnen...\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Debug ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Debug\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"debug\";" fp)
  (write-line "      label = \"Debug-Modus aktivieren\";" fp)
  (write-line "    }" fp)
  (write-line "    : text {" fp)
  (write-line "      key = \"logpath\";" fp)
  (write-line "      label = \"\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Info ---
  (write-line "  : text {" fp)
  (write-line "    key = \"info\";" fp)
  (write-line "    label = \"\";" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- OK / Abbrechen ---
  (write-line "  ok_cancel;" fp)
  (write-line "}" fp)
  
  (close fp)
  dcl-file
)

;;; Oeffnet Settings-Dialog, speichert bei OK
(defun HAL:show-settings ( / dcl-file dcl-id result cur-scale)
  (HAL:log-write "INFO" "Settings-Dialog geoeffnet")
  
  ;; Aktuelle DWG-Scale lesen
  (setq cur-scale (HAL:read-dwg-scale))
  (if (null cur-scale) (setq cur-scale 1.0))
  
  ;; DCL schreiben und laden
  (setq dcl-file (HAL:write-settings-dcl))
  (setq dcl-id (load_dialog dcl-file))
  
  (if (not (new_dialog "hal_settings" dcl-id))
    (progn
      (HAL:log-write "ERROR" "DCL Dialog konnte nicht geoeffnet werden")
      (princ "\n*** Fehler: Dialog konnte nicht geoeffnet werden ***")
      (unload_dialog dcl-id)
      (vl-file-delete dcl-file)
    )
    (progn
      ;; Werte in Dialog setzen
      (set_tile "scale" (rtos cur-scale 2 2))
      (set_tile "use_suffix" (if *HAL:use-layer-suffix* "1" "0"))
      (set_tile "layer_suffix" *HAL:layer-suffix*)
      (set_tile "layer_preview" (strcat "Vorschau: " (getvar "CLAYER") "_" *HAL:layer-suffix*))
      (set_tile "mode_line" (if (= *HAL:lineab-mode* "LINE") "1" "0"))
      (set_tile "mode_xline" (if (= *HAL:lineab-mode* "XLINE") "1" "0"))
      (set_tile "lineab_keep" (if *HAL:lineab-keep* "1" "0"))
      (set_tile "xline_keep" (if *HAL:xline-keep* "1" "0"))
      (set_tile "debug" (if *HAL:debug-mode* "1" "0"))
      (set_tile "logpath" (strcat "Log: " (HAL:get-appdata-path) "\\Log"))
      (set_tile "blockname_info" (strcat "Block: " *HAL:blockname*))
      (set_tile "info" (strcat "HoeheAufLinie v" *HAL:version*))
      
      ;; Live-Vorschau Layer-Suffix
      (action_tile "layer_suffix"
        "(set_tile \"layer_preview\" (strcat \"Vorschau: \" (getvar \"CLAYER\") \"_\" (get_tile \"layer_suffix\")))"
      )
      
      ;; Block-Verwaltung Button: Werte speichern VOR done_dialog (Sub-Dialog Bug!)
      (action_tile "btn_block"
        (strcat
          "(setq *HAL:tmp-scale* (get_tile \"scale\"))"
          "(setq *HAL:tmp-use-suffix* (get_tile \"use_suffix\"))"
          "(setq *HAL:tmp-layer-suffix* (get_tile \"layer_suffix\"))"
          "(setq *HAL:tmp-mode-line* (get_tile \"mode_line\"))"
          "(setq *HAL:tmp-lineab-keep* (get_tile \"lineab_keep\"))"
          "(setq *HAL:tmp-xline-keep* (get_tile \"xline_keep\"))"
          "(setq *HAL:tmp-debug* (get_tile \"debug\"))"
          "(done_dialog 2)"
        )
      )
      
      ;; OK: Werte in globale Vars speichern VOR done_dialog (Sub-Dialog Bug!)
      (action_tile "accept"
        (strcat
          "(setq *HAL:tmp-scale* (get_tile \"scale\"))"
          "(setq *HAL:tmp-use-suffix* (get_tile \"use_suffix\"))"
          "(setq *HAL:tmp-layer-suffix* (get_tile \"layer_suffix\"))"
          "(setq *HAL:tmp-mode-line* (get_tile \"mode_line\"))"
          "(setq *HAL:tmp-lineab-keep* (get_tile \"lineab_keep\"))"
          "(setq *HAL:tmp-xline-keep* (get_tile \"xline_keep\"))"
          "(setq *HAL:tmp-debug* (get_tile \"debug\"))"
          "(done_dialog 1)"
        )
      )
      
      ;; Dialog starten
      (setq result (start_dialog))
      
      ;; Auswerten
      (cond
        ;; OK gedrueckt (result = 1)
        ((= result 1)
          ;; Skalierung
          (if (> (atof *HAL:tmp-scale*) 0.0)
            (progn
              (HAL:write-dwg-scale (atof *HAL:tmp-scale*))
              (HAL:log-write "INFO" (strcat "DWG-Skalierung: " *HAL:tmp-scale*))
            )
            (progn
              (princ "\n*** Skalierung muss > 0 sein, nicht geaendert ***")
              (HAL:log-write "WARN" (strcat "Ungueltige Skalierung: " *HAL:tmp-scale*))
            )
          )
          
          ;; Layer-Suffix
          (setq *HAL:use-layer-suffix* (= *HAL:tmp-use-suffix* "1"))
          (if (and *HAL:tmp-layer-suffix* (/= *HAL:tmp-layer-suffix* ""))
            (setq *HAL:layer-suffix* *HAL:tmp-layer-suffix*)
            (progn
              (princ "\n*** Layer-Suffix darf nicht leer sein, nicht geaendert ***")
              (HAL:log-write "WARN" "Leeres Layer-Suffix ignoriert")
            )
          )
          
          ;; Linie A-B Modus
          (setq *HAL:lineab-mode* (if (= *HAL:tmp-mode-line* "1") "LINE" "XLINE"))
          (setq *HAL:lineab-keep* (= *HAL:tmp-lineab-keep* "1"))
          
          ;; Konstruktionslinie
          (setq *HAL:xline-keep* (= *HAL:tmp-xline-keep* "1"))
          
          ;; Debug
          (setq *HAL:debug-mode* (= *HAL:tmp-debug* "1"))
          
          ;; Config speichern
          (HAL:save-config)
          
          (HAL:log-write "INFO" (strcat "Settings: Layer=" (if *HAL:use-layer-suffix* "aktiv" "aus")
                                        " Suffix=_" *HAL:layer-suffix*
                                        " LinieAB=" *HAL:lineab-mode*
                                        " KeepAB=" (if *HAL:lineab-keep* "ja" "nein")
                                        " KeepXL=" (if *HAL:xline-keep* "ja" "nein")
                                        " Debug=" (if *HAL:debug-mode* "ein" "aus")))
          (princ "\nEinstellungen gespeichert.")
        )
        
        ;; Block-Manager oeffnen (result = 2)
        ((= result 2)
          (HAL:log-write "INFO" "Block-Verwaltung geoeffnet aus Settings")
          (unload_dialog dcl-id)
          (vl-file-delete dcl-file)
          (manage-block-import "HoeheAufLinie")
          ;; Nach Block-Manager: Settings erneut oeffnen
          (HAL:log-write "INFO" "Settings erneut oeffnen nach Block-Verwaltung")
          (HAL:show-settings)
        )
        
        ;; Abbrechen (result = 0)
        (T
          (HAL:log-write "INFO" "Settings abgebrochen")
          (princ "\nAbgebrochen.")
        )
      )
      
      ;; Aufraeumen (nur wenn nicht schon durch result=2 aufgeraeumt)
      (if (/= result 2)
        (progn
          (unload_dialog dcl-id)
          (vl-file-delete dcl-file)
        )
      )
    )
  )
  
  ;; Temp-Variablen aufraeumen

  (setq *HAL:tmp-scale* nil)
  (setq *HAL:tmp-use-suffix* nil)
  (setq *HAL:tmp-layer-suffix* nil)
  (setq *HAL:tmp-mode-line* nil)
  (setq *HAL:tmp-lineab-keep* nil)
  (setq *HAL:tmp-xline-keep* nil)
  (setq *HAL:tmp-debug* nil)
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - FORMATIERUNG
;;; ============================================================================

(defun HAL:ensure-two-decimals (heightValue)
  (rtos heightValue 2 2)
)

(defun HAL:format-height (heightValue)
  (rtos heightValue 2 2)
)

(defun HAL:format-height-value (heightValue / formattedHeight)
  (setq formattedHeight (HAL:ensure-two-decimals heightValue))
  (cond
    ((= heightValue 0.0) (setq formattedHeight (strcat "%%p" formattedHeight)))
    ((> heightValue 0.0) (setq formattedHeight (strcat "+" formattedHeight)))
  )
  formattedHeight
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - BLOCK-PRUEFUNG
;;; ============================================================================

(defun HAL:block-exists-at-position (pt height blockname / ss i ent inspt pt-wcs tolerance-xy tolerance-z dist-xy dist-z found)
  (setq tolerance-xy 0.05)
  (setq tolerance-z 0.001)
  (setq found nil)
  (setq pt-wcs (trans pt 1 0))
  
  (HAL:debug (strcat "HAL:block-exists-at-position: blockname=" blockname))
  (HAL:debug (strcat "  pt(BKS)=(" (rtos (car pt) 2 4) " " (rtos (cadr pt) 2 4) " " (rtos (caddr pt) 2 4) ")"))
  (HAL:debug (strcat "  pt(WKS)=(" (rtos (car pt-wcs) 2 4) " " (rtos (cadr pt-wcs) 2 4) " " (rtos (caddr pt-wcs) 2 4) ")"))
  (HAL:debug (strcat "  height=" (rtos height 2 4)))
  
  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 blockname))))
  
  (if ss
    (progn
      (HAL:debug (strcat "  Gefundene Bloecke: " (itoa (sslength ss))))
      (setq i 0)
      (while (and (< i (sslength ss)) (not found))
        (setq ent (ssname ss i))
        (setq inspt (cdr (assoc 10 (entget ent))))
        (setq dist-xy (distance (list (car pt-wcs) (cadr pt-wcs))
                                (list (car inspt) (cadr inspt))))
        (setq dist-z (abs (- height (caddr inspt))))
        (HAL:debug (strcat "  Block[" (itoa i) "] inspt=("
                           (rtos (car inspt) 2 4) " " (rtos (cadr inspt) 2 4) " " (rtos (caddr inspt) 2 4)
                           ") dist-xy=" (rtos dist-xy 2 4) " dist-z=" (rtos dist-z 2 4)))
        (if (and (< dist-xy tolerance-xy) (< dist-z tolerance-z))
          (progn
            (HAL:debug "  >>> MATCH GEFUNDEN - Block existiert bereits!")
            (setq found T)
          )
        )
        (setq i (1+ i))
      )
      (setq ss nil)
      (if (not found) (HAL:debug "  Kein Match gefunden"))
      found
    )
    (progn
      (HAL:debug "  Keine Bloecke mit diesem Namen in Zeichnung")
      nil
    )
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - MATHEMATIK
;;; ============================================================================

(defun HAL:calc-interpolated-height (pf1 height1 pf2 height2 pg / vpf vpg scalar dist-pf1-pf2 height-diff interpolated-height)
  (HAL:debug "=== HAL:calc-interpolated-height ===")
  (HAL:debug (strcat "  pf1=(" (rtos (car pf1) 2 4) " " (rtos (cadr pf1) 2 4) " " (rtos (caddr pf1) 2 4) ") h1=" (rtos height1 2 4)))
  (HAL:debug (strcat "  pf2=(" (rtos (car pf2) 2 4) " " (rtos (cadr pf2) 2 4) " " (rtos (caddr pf2) 2 4) ") h2=" (rtos height2 2 4)))
  (HAL:debug (strcat "  pg=(" (rtos (car pg) 2 4) " " (rtos (cadr pg) 2 4) " " (rtos (caddr pg) 2 4) ")"))
  
  (setq vpf (list (- (car pf2) (car pf1)) (- (cadr pf2) (cadr pf1))))
  (setq vpg (list (- (car pg) (car pf1)) (- (cadr pg) (cadr pf1))))
  
  (HAL:debug (strcat "  vpf=(" (rtos (car vpf) 2 4) " " (rtos (cadr vpf) 2 4) ")"))
  (HAL:debug (strcat "  vpg=(" (rtos (car vpg) 2 4) " " (rtos (cadr vpg) 2 4) ")"))
  
  (setq dist-pf1-pf2 (sqrt (+ (expt (car vpf) 2) (expt (cadr vpf) 2))))
  (HAL:debug (strcat "  dist-2D(pf1,pf2)=" (rtos dist-pf1-pf2 2 6)))
  
  (if (< dist-pf1-pf2 0.0001)
    (progn
      (HAL:debug "  *** WARNUNG: PF1 und PF2 zu nahe beieinander! ***")
      (princ "\n*** WARNUNG: Fixpunkte haben gleiche XY-Position! ***")
      height1
    )
    (progn
      (setq scalar (/ (+ (* (car vpg) (car vpf)) (* (cadr vpg) (cadr vpf)))
                      (expt dist-pf1-pf2 2)))
      (setq height-diff (- height2 height1))
      (setq interpolated-height (+ height1 (* scalar height-diff)))
      (HAL:debug (strcat "  scalar=" (rtos scalar 2 6)))
      (HAL:debug (strcat "  height-diff=" (rtos height-diff 2 4)))
      (HAL:debug (strcat "  interpolated-height=" (rtos interpolated-height 2 4)))
      (if (or (< scalar -0.1) (> scalar 1.1))
        (HAL:debug "  *** HINWEIS: Punkt liegt ausserhalb der Strecke (Extrapolation)! ***")
      )
      interpolated-height
    )
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - KONSTRUKTIONSLINIE
;;; ============================================================================

(defun HAL:calc-point-for-height (pf1 height1 pf2 height2 target-height / height-diff scalar px py)
  (HAL:debug "=== HAL:calc-point-for-height ===")
  (HAL:debug (strcat "  target-height=" (rtos target-height 2 4)))
  (setq height-diff (- height2 height1))
  (if (< (abs height-diff) 0.0001)
    (progn
      (HAL:debug "  *** Fixpunkte haben gleiche Hoehe! ***")
      (princ "\n*** Fixpunkte haben gleiche Hoehe - Konstruktionslinie nicht moeglich ***")
      nil
    )
    (progn
      (setq scalar (/ (- target-height height1) height-diff))
      (setq px (+ (car pf1) (* scalar (- (car pf2) (car pf1)))))
      (setq py (+ (cadr pf1) (* scalar (- (cadr pf2) (cadr pf1)))))
      (HAL:debug (strcat "  scalar=" (rtos scalar 2 6)))
      (HAL:debug (strcat "  Punkt=(" (rtos px 2 4) " " (rtos py 2 4) ")"))
      (if (or (< scalar -0.5) (> scalar 1.5))
        (princ (strcat "\n  Hinweis: Hoehe " (HAL:format-height target-height) " liegt ausserhalb der Strecke (Extrapolation)"))
      )
      (list px py 0.0)
    )
  )
)

(defun HAL:create-perp-xline (base-pt pf1 pf2 / dx dy perp-dx perp-dy len ent base-pt-wcs dir-bks dir-wcs)
  (HAL:debug "=== HAL:create-perp-xline ===")
  (HAL:debug (strcat "  base-pt(BKS)=(" (rtos (car base-pt) 2 4) " " (rtos (cadr base-pt) 2 4) ")"))
  (setq dx (- (car pf2) (car pf1)))
  (setq dy (- (cadr pf2) (cadr pf1)))
  (setq perp-dx (- dy))
  (setq perp-dy dx)
  (setq len (sqrt (+ (expt perp-dx 2) (expt perp-dy 2))))
  (if (< len 0.0001)
    (progn (HAL:debug "  *** Richtungsvektor hat Laenge 0 ***") nil)
    (progn
      (setq perp-dx (/ perp-dx len))
      (setq perp-dy (/ perp-dy len))
      (setq base-pt-wcs (trans (list (car base-pt) (cadr base-pt) 0.0) 1 0))
      (setq dir-bks (list perp-dx perp-dy 0.0))
      (setq dir-wcs (trans dir-bks 1 0 T))
      (HAL:debug (strcat "  Normalvektor(BKS)=(" (rtos perp-dx 2 6) " " (rtos perp-dy 2 6) ")"))
      (HAL:debug (strcat "  base-pt(WKS)=(" (rtos (car base-pt-wcs) 2 4) " " (rtos (cadr base-pt-wcs) 2 4) ")"))
      (setq ent (entmakex
        (list '(0 . "XLINE") '(100 . "AcDbEntity") '(67 . 0) '(8 . "0") '(62 . 1)
              '(100 . "AcDbXline") (cons 10 base-pt-wcs) (cons 11 dir-wcs))))
      (if ent
        (progn (HAL:debug (strcat "  XLINE erstellt: " (vl-princ-to-string ent))) ent)
        (progn (HAL:debug "  *** XLINE Erstellung fehlgeschlagen ***")
               (princ "\n*** Fehler beim Erstellen der Konstruktionslinie ***") nil)
      )
    )
  )
)

(defun HAL:delete-xline (ent / )
  (if (and ent (entget ent))
    (progn (entdel ent) (HAL:debug "  XLINE geloescht") T)
    nil
  )
)

;;; Erstellt Linie A-B je nach Modus (LINE oder XLINE)
(defun HAL:create-line-ab (pf1 pf2 / ent)
  (if (= *HAL:lineab-mode* "XLINE")
    ;; XLINE Modus: unendliche Linie durch A und B
    (progn
      (setq ent (entmakex
        (list '(0 . "XLINE") '(100 . "AcDbEntity") '(67 . 0) '(8 . "0") '(62 . 2)
              '(100 . "AcDbXline")
              (cons 10 (trans pf1 1 0))
              ;; Richtungsvektor = PF1->PF2 (normiert nicht noetig fuer XLINE)
              (cons 11 (trans (list (- (car pf2) (car pf1))
                                    (- (cadr pf2) (cadr pf1))
                                    0.0) 1 0 T))
        )
      ))
      (if ent
        (HAL:debug "Linie A-B erstellt (gelb XLINE)")
        (HAL:debug "*** Linie A-B XLINE Erstellung fehlgeschlagen ***")
      )
      ent
    )
    ;; LINE Modus: nur zwischen A und B
    (progn
      (setq ent (entmakex
        (list '(0 . "LINE") '(100 . "AcDbEntity") '(8 . "0") '(62 . 2) '(100 . "AcDbLine")
              (cons 10 (trans pf1 1 0))
              (cons 11 (trans pf2 1 0))
        )
      ))
      (if ent
        (HAL:debug "Linie A-B erstellt (gelb LINE)")
        (HAL:debug "*** Linie A-B LINE Erstellung fehlgeschlagen ***")
      )
      ent
    )
  )
)

(defun HAL:update-construction-line (pf1 height1 pf2 height2 current-xline line-ab / target-height base-pt new-xline prompt scalar)
  (if current-xline (HAL:delete-xline current-xline))
  
  (setq prompt "\nZielhoehe fuer Konstruktionslinie eingeben: ")
  (setq target-height (getreal prompt))
  
  (if (null target-height)
    (progn
      (princ "\n  Keine Hoehe eingegeben - keine Konstruktionslinie")
      (list nil line-ab)
    )
    (progn
      (setq base-pt (HAL:calc-point-for-height pf1 height1 pf2 height2 target-height))
      (if base-pt
        (progn
          (setq new-xline (HAL:create-perp-xline base-pt pf1 pf2))
          (if new-xline
            (princ (strcat "\n  Konstruktionslinie bei Hoehe " (HAL:format-height target-height)
                           " | Punkt=(" (rtos (car base-pt) 2 2) ", " (rtos (cadr base-pt) 2 2) ")"))
          )
          
          ;; Linie A-B verlaengern nur im LINE-Modus (XLINE ist schon unendlich)
          (if (= *HAL:lineab-mode* "LINE")
            (progn
              (setq scalar (/ (- target-height height1) (- height2 height1)))
              (HAL:debug (strcat "  Konstruktions-Scalar=" (rtos scalar 2 6)))
              (if (and line-ab (or (< scalar 0.0) (> scalar 1.0)))
                (progn
                  (HAL:debug "  Linie A-B wird verlaengert bis Konstruktionspunkt")
                  (entdel line-ab)
                  (setq line-ab (entmakex
                    (list '(0 . "LINE") '(100 . "AcDbEntity") '(8 . "0") '(62 . 2) '(100 . "AcDbLine")
                          (cons 10 (if (< scalar 0.0) (trans base-pt 1 0) (trans pf1 1 0)))
                          (cons 11 (if (> scalar 1.0) (trans base-pt 1 0) (trans pf2 1 0))))))
                  (if line-ab (HAL:debug "  Linie A-B verlaengert")
                              (HAL:debug "  *** Linie A-B Verlaengerung fehlgeschlagen ***"))
                )
                ;; Innerhalb A-B: zuruecksetzen
                (if line-ab
                  (progn
                    (entdel line-ab)
                    (setq line-ab (entmakex
                      (list '(0 . "LINE") '(100 . "AcDbEntity") '(8 . "0") '(62 . 2) '(100 . "AcDbLine")
                            (cons 10 (trans pf1 1 0)) (cons 11 (trans pf2 1 0)))))))
              )
            )
          )
          
          (list new-xline line-ab)
        )
        (list nil line-ab)
      )
    )
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - VALIDIERUNG & EINGABE
;;; ============================================================================

(defun HAL:valid-point-p (pt)
  (HAL:debug (strcat "HAL:valid-point-p: pt=" (vl-princ-to-string pt)))
  (HAL:debug (strcat "  pt ist nil? " (if (null pt) "JA" "NEIN")))
  (if pt
    (progn
      (HAL:debug (strcat "  listp? " (if (listp pt) "JA" "NEIN")))
      (if (listp pt)
        (progn
          (HAL:debug (strcat "  length=" (itoa (length pt))))
          (if (= (length pt) 3)
            (progn
              (HAL:debug (strcat "  numberp(car)=" (if (numberp (car pt)) "JA" "NEIN")))
              (HAL:debug (strcat "  numberp(cadr)=" (if (numberp (cadr pt)) "JA" "NEIN")))
              (HAL:debug (strcat "  numberp(caddr)=" (if (numberp (caddr pt)) "JA" "NEIN")))
            )
          )
        )
      )
    )
  )
  (and pt (listp pt) (= (length pt) 3)
       (numberp (car pt)) (numberp (cadr pt)) (numberp (caddr pt)))
)

(defun HAL:valid-height-p (height)
  (and height (numberp height))
)

(defun HAL:get-validated-height (prompt default / height)
  (if default
    (setq prompt (strcat prompt " <" (HAL:format-height default) ">: "))
    (setq prompt (strcat prompt ": "))
  )
  (setq height (getreal prompt))
  (HAL:debug (strcat "HAL:get-validated-height: height=" (if height (rtos height 2 4) "nil") " default=" (if default (rtos default 2 4) "nil")))
  (if (null height)
    (if default
      (progn (setq height default) (HAL:debug (strcat "  Verwende Default: " (rtos height 2 4))))
      (progn
        (while (null height)
          (princ "\n*** Bitte geben Sie eine Hoehe ein ***")
          (setq height (getreal (strcat prompt ": ")))
        )
      )
    )
  )
  (if (HAL:valid-height-p height) height nil)
)

(defun HAL:get-scale ( / scaleValue prompt current-scale)
  (setq current-scale (HAL:read-dwg-scale))
  (setq prompt (strcat "\nNeue XY-Skalierung"
                       (if current-scale (strcat " <" (rtos current-scale 2 2) ">") " <1.0>")
                       ": "))
  (setq scaleValue (getreal prompt))
  (if (null scaleValue)
    (if current-scale (setq scaleValue current-scale) (setq scaleValue 1.0))
  )
  (if (<= scaleValue 0.0)
    (progn (princ "\n*** Skalierung muss groesser als 0 sein! Verwende 1.0 ***") (setq scaleValue 1.0))
  )
  (HAL:write-dwg-scale scaleValue)
  (HAL:log-write "INFO" (strcat "Skalierung gesetzt: " (rtos scaleValue 2 2)))
  (princ (strcat "\n Skalierung: " (rtos scaleValue 2 2) " (in DWG gespeichert)"))
  scaleValue
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - BLOCK EINFUEGEN
;;; ============================================================================

(defun HAL:insert-block (einfuegepunkt hoehe scale skip-if-exists / blockName heightStr old-attdia block-available importEnt ent attribs insertionPoint hk-layer ent-data)
  (setq blockName *HAL:blockname*)
  
  (HAL:debug "=== HAL:insert-block ===")
  (HAL:debug (strcat "  einfuegepunkt=(" (rtos (car einfuegepunkt) 2 4) " " (rtos (cadr einfuegepunkt) 2 4) " " (rtos (caddr einfuegepunkt) 2 4) ")"))
  (HAL:debug (strcat "  hoehe=" (rtos hoehe 2 4) " scale=" (rtos scale 2 4) " skip=" (if skip-if-exists "T" "nil")))
  
  (if (and (HAL:valid-point-p einfuegepunkt) (HAL:valid-height-p hoehe) scale)
    (progn
      (if (and skip-if-exists (HAL:block-exists-at-position einfuegepunkt hoehe blockName))
        (progn
          (HAL:debug "  >>> Block existiert bereits - UEBERSPRUNGEN")
          (princ (strcat "\n  Block existiert bereits: " (HAL:format-height-value hoehe) " | Z=" (rtos hoehe 2 3)))
          nil
        )
        (progn
          (HAL:debug "  Block wird eingefuegt...")
          (setq *block-import-context* "HoeheAufLinie")
          (setq block-available (ensure-block-available blockName))
          (HAL:debug (strcat "  ensure-block-available: car=" (if (car block-available) "T" "nil")))
          
          (if (car block-available)
            (progn
              (setq importEnt (cadr block-available))
              (HAL:debug (strcat "  importEnt=" (if importEnt (vl-princ-to-string importEnt) "nil")))
              (setq heightStr (HAL:format-height-value hoehe))
              (HAL:debug (strcat "  heightStr=" heightStr))
              
              ;; HK-Layer VOR dem Einfuegen erstellen (VLA-Calls duerfen nicht waehrend command laufen)
              (if *HAL:use-layer-suffix*
                (setq hk-layer (HAL:ensure-hk-layer))
              )
              
              (setq old-attdia (getvar "ATTDIA"))
              (setvar "ATTDIA" 0)
              (HAL:debug (strcat "  _-insert: blockName=" blockName " scale=" (rtos scale 2 4)))
              (command "_-insert" blockName einfuegepunkt scale scale "" "")
              (setq ent (entlast))
              (HAL:debug (strcat "  entlast nach insert: " (if ent (vl-princ-to-string ent) "nil")))
              (if ent (HAL:debug (strcat "  entlast Typ: " (cdr (assoc 0 (entget ent))))))
              (setvar "ATTDIA" old-attdia)
              
              ;; Attribute setzen
              (if (and ent (eq (cdr (assoc 0 (entget ent))) "INSERT"))
                (progn
                  (HAL:debug "  Block INSERT gefunden - setze Attribute...")
                  (setq attribs (entnext ent))
                  (while (and attribs (eq (cdr (assoc 0 (entget attribs))) "ATTRIB"))
                    (HAL:debug (strcat "    Attribut: " (cdr (assoc 2 (entget attribs))) " = " (cdr (assoc 1 (entget attribs)))))
                    (if (eq (cdr (assoc 2 (entget attribs))) "HOEHE")
                      (progn
                        (HAL:debug (strcat "    >>> Setze HOEHE auf: " heightStr))
                        (entmod (subst (cons 1 heightStr) (assoc 1 (entget attribs)) (entget attribs)))
                      )
                    )
                    (setq attribs (entnext attribs))
                  )
                )
                (HAL:debug "  *** entlast ist KEIN INSERT! Block-Einfuegung moeglicherweise fehlgeschlagen!")
              )
              
              ;; Block auf Hoehe verschieben
              (setq insertionPoint (cdr (assoc 10 (entget ent))))
              (HAL:debug (strcat "  insertionPoint=(" (rtos (car insertionPoint) 2 4) " " (rtos (cadr insertionPoint) 2 4) " " (rtos (caddr insertionPoint) 2 4) ")"))
              (HAL:debug (strcat "  move to Z=" (rtos hoehe 2 4)))
              (command "_move" ent "" "_non" insertionPoint "_non"
                       (list (car insertionPoint) (cadr insertionPoint) hoehe))
              (setq insertionPoint (cdr (assoc 10 (entget ent))))
              (HAL:debug (strcat "  Position nach Move=(" (rtos (car insertionPoint) 2 4) " " (rtos (cadr insertionPoint) 2 4) " " (rtos (caddr insertionPoint) 2 4) ")"))
              
                            ;; HK-Layer zuweisen (Layer wurde VOR insert erstellt)
              (if (and *HAL:use-layer-suffix* hk-layer)
                (progn
                  (setq ent-data (entget ent))
                  (entmod (subst (cons 8 hk-layer) (assoc 8 ent-data) ent-data))
                  (HAL:debug (strcat "  Block auf Layer: " hk-layer))
                )
              )
              
              ;; Import-Block entfernen
              (if importEnt
                (progn (HAL:debug "  Entferne importEnt...") (entdel importEnt))
              )
              
              (HAL:log-write "INFO" (strcat "Block gesetzt: " heightStr " Z=" (rtos hoehe 2 3) " Scale=" (rtos scale 2 2)
                                            (if (and *HAL:use-layer-suffix* hk-layer) (strcat " Layer=" hk-layer) "")))
              (princ (strcat "\n  Hoehenkote gesetzt: " heightStr " | Z=" (rtos hoehe 2 3) " | XY-Scale=" (rtos scale 2 2)
                            (if (and *HAL:use-layer-suffix* hk-layer) (strcat " | Layer=" hk-layer) "")))
              T
            )
            (progn
              (HAL:log-write "ERROR" "ensure-block-available fehlgeschlagen")
              (princ "\n*** FEHLER: Block konnte nicht geladen werden ***")
              nil
            )
          )
        )
      )
    )
    (progn
      (HAL:debug (strcat "  *** Parameter-Pruefung FEHLGESCHLAGEN!"
                         " valid-point=" (if (HAL:valid-point-p einfuegepunkt) "T" "nil")
                         " valid-height=" (if (HAL:valid-height-p hoehe) "T" "nil")
                         " scale=" (if scale "OK" "nil")))
      (princ "\n*** Fehler: Ungueltige Parameter ***")
      nil
    )
  )
)

;;; ============================================================================
;;; BEFEHLE
;;; ============================================================================

;;; Hauptbefehl: Hoeheninterpolation entlang Linie
(defun c:HoeheAufLinie ( / *error* old-cmdecho old-attdia pf1 height1 pf2 height2 pg interpolated-height scale current-xline line-ab result-list)
  
  (HAL:ensure-init)
  
  ;; Lokaler Error-Handler mit wcmatch Cancel-Detection (DE+EN)
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg) "*ABBRUCH*,*ABGEBROCHEN*,*CANCEL*,*QUIT*,*EXIT*"))
      (progn
        (princ (strcat "\nFehler: " msg))
        (HAL:log-write "ERROR" (strcat "Error-Handler: " msg))
      )
      (HAL:log-write "INFO" (strcat "Benutzer-Abbruch: " msg))
    )
    ;; Aufraeumen (je nach Setting behalten oder loeschen)
    (if current-xline
      (if (not *HAL:xline-keep*) (HAL:delete-xline current-xline))
    )
    (if line-ab
      (if (not *HAL:lineab-keep*) (entdel line-ab))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-attdia (setvar "ATTDIA" old-attdia))
    (princ)
  )
  
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-attdia (getvar "ATTDIA"))
  (setvar "CMDECHO" 0)
  (setvar "ATTDIA" 0)
  
  (HAL:log-write "INFO" "Befehl HoeheAufLinie gestartet")
  
  (princ "\n=== Hoeheninterpolation entlang Linie ===")
  (if *HAL:debug-mode* (princ "\n*** DEBUG-MODUS AKTIV ***"))
  (princ "\nSetzen Sie zwei Fixpunkte mit bekannten Hoehen.")
  (princ "\nDann koennen Sie beliebig viele Zwischenpunkte setzen.")
  
  ;; Skalierung aus DWG
  (setq scale (HAL:read-dwg-scale))
  (if (null scale) (setq scale 1.0))
  (HAL:debug (strcat "Scale aus DWG: " (rtos scale 2 4)))
  
  ;; Fixpunkt 1
  (princ "\n")
  (initget "Skalierung Einstellungen")
  (setq pf1 (getpoint (strcat "\nFixpunkt 1 waehlen [Skalierung/Einstellungen] <" (rtos scale 2 2) ">: ")))
  (HAL:debug (strcat "pf1 raw=" (vl-princ-to-string pf1)))
  
  (while (and pf1 (= (type pf1) 'STR))
    (cond
      ((= pf1 "Skalierung") (setq scale (HAL:get-scale)))
      ((= pf1 "Einstellungen")
       (HAL:show-settings)
       ;; Scale neu lesen (koennte geaendert worden sein)
       (setq scale (HAL:read-dwg-scale))
       (if (null scale) (setq scale 1.0))
      )
    )
    (initget "Skalierung Einstellungen")
    (setq pf1 (getpoint (strcat "\nFixpunkt 1 waehlen [Skalierung/Einstellungen] <" (rtos scale 2 2) ">: ")))
  )
  
  (if (not (HAL:valid-point-p pf1))
    (progn
      (HAL:debug "pf1 ungueltig - Abbruch")
      (princ "\n*** Abbruch: Kein gueltiger Punkt gewaehlt ***")
    )
    (progn
      (HAL:log-write "INFO" (strcat "Fixpunkt 1: (" (rtos (car pf1) 2 3) " " (rtos (cadr pf1) 2 3) ")"))
      (setq height1 (HAL:get-validated-height "\nHoehe Fixpunkt 1 eingeben" *HAL:last-height*))
      
      (if (not height1)
        (princ "\n*** Abbruch: Keine gueltige Hoehe eingegeben ***")
        (progn
          (HAL:log-write "INFO" (strcat "Hoehe 1: " (rtos height1 2 4)))
          (setq *HAL:last-height* height1)
          (HAL:insert-block pf1 height1 scale T)
          
          ;; Fixpunkt 2
          (princ "\n")
          (initget "Skalierung Einstellungen")
          (setq pf2 (getpoint (strcat "\nFixpunkt 2 waehlen [Skalierung/Einstellungen] <" (rtos scale 2 2) ">: ")))
          (HAL:debug (strcat "pf2 raw=" (vl-princ-to-string pf2)))
          
          (while (and pf2 (= (type pf2) 'STR))
            (cond
              ((= pf2 "Skalierung") (setq scale (HAL:get-scale)))
              ((= pf2 "Einstellungen")
               (HAL:show-settings)
               (setq scale (HAL:read-dwg-scale))
               (if (null scale) (setq scale 1.0))
              )
            )
            (initget "Skalierung Einstellungen")
            (setq pf2 (getpoint (strcat "\nFixpunkt 2 waehlen [Skalierung/Einstellungen] <" (rtos scale 2 2) ">: ")))
          )
          
          (if (not (HAL:valid-point-p pf2))
            (progn
              (HAL:debug "pf2 ungueltig - Abbruch")
              (princ "\n*** Abbruch: Kein gueltiger Punkt gewaehlt ***")
            )
            (progn
              (HAL:log-write "INFO" (strcat "Fixpunkt 2: (" (rtos (car pf2) 2 3) " " (rtos (cadr pf2) 2 3) ")"))
              (setq height2 (HAL:get-validated-height "\nHoehe Fixpunkt 2 eingeben" *HAL:last-height*))
              
              (if (not height2)
                (princ "\n*** Abbruch: Keine gueltige Hoehe eingegeben ***")
                (progn
                  (HAL:log-write "INFO" (strcat "Hoehe 2: " (rtos height2 2 4)))
                  (setq *HAL:last-height* height2)
                  (HAL:insert-block pf2 height2 scale T)
                  
                  ;; Linie A-B erstellen (je nach Modus LINE oder XLINE)
                  (setq line-ab (HAL:create-line-ab pf1 pf2))
                  
                  ;; Zwischenpunkte-Schleife
                  (princ "\n")
                  (princ "\n--- Zwischenpunkte setzen (K=Konstruktionslinie, S=Skalierung, E=Einstellungen, ESC=Ende) ---")
                  (setq current-xline nil)
                  
                  (initget "Skalierung Konstruktion Einstellungen")
                  (setq pg (getpoint (strcat "\nPunkt waehlen [Skalierung/Konstruktion/Einstellungen] <" (rtos scale 2 2) ">: ")))
                  (HAL:debug (strcat "pg raw=" (vl-princ-to-string pg)))
                  
                  (while pg
                    (cond
                      ((= pg "Skalierung")
                       (setq scale (HAL:get-scale))
                      )
                      ((= pg "Konstruktion")
                       (setq result-list
                         (HAL:update-construction-line pf1 height1 pf2 height2 current-xline line-ab))
                       (setq current-xline (car result-list))
                       (setq line-ab (cadr result-list))
                      )
                      ((= pg "Einstellungen")
                       (HAL:show-settings)
                       (setq scale (HAL:read-dwg-scale))
                       (if (null scale) (setq scale 1.0))
                      )
                      (T
                       (if (HAL:valid-point-p pg)
                         (progn
                           (setq interpolated-height (HAL:calc-interpolated-height pf1 height1 pf2 height2 pg))
                           (princ (strcat "\n  Berechnete Hoehe: " (HAL:format-height interpolated-height)))
                           (HAL:log-write "INFO" (strcat "Interpolation: (" (rtos (car pg) 2 3) " " (rtos (cadr pg) 2 3) ") -> " (rtos interpolated-height 2 4)))
                           (HAL:insert-block pg interpolated-height scale nil)
                         )
                         (progn
                           (HAL:debug "pg UNGUELTIG - uebersprungen!")
                           (princ "\n*** Ungueltiger Punkt - uebersprungen ***")
                         )
                       )
                      )
                    )
                    
                    (initget "Skalierung Konstruktion Einstellungen")
                    (setq pg (getpoint (strcat "\nPunkt waehlen [Skalierung/Konstruktion/Einstellungen] <" (rtos scale 2 2) ">: ")))
                    (HAL:debug (strcat "pg raw (naechster)=" (vl-princ-to-string pg)))
                  )
                  
                  ;; Aufraeumen je nach Settings
                  (if current-xline
                    (if (not *HAL:xline-keep*)
                      (HAL:delete-xline current-xline)
                      (HAL:log-write "INFO" "Konstruktionslinie beibehalten (Setting)")
                    )
                  )
                  (if line-ab
                    (if (not *HAL:lineab-keep*)
                      (entdel line-ab)
                      (HAL:log-write "INFO" "Linie A-B beibehalten (Setting)")
                    )
                  )
                  
                  (HAL:log-write "INFO" "Befehl HoeheAufLinie beendet")
                  (princ "\n\n Hoeheninterpolation abgeschlossen.")
                )
              )
            )
          )
        )
      )
    )
  )
  
  ;; Cleanup (doppelt fuer Sicherheit - Error-Handler + hier)
  (if (and current-xline (not *HAL:xline-keep*)) (HAL:delete-xline current-xline))
  (if (and line-ab (not *HAL:lineab-keep*)) (entdel line-ab))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (if old-attdia (setvar "ATTDIA" old-attdia))
  
  (princ)
)

;;; Kurzbefehl
(defun c:HAL ()
  (c:HoeheAufLinie)
)

;;; Debug-Modus ein/aus (persistiert in Config)
(defun c:HALDEBUG ( / )
  (HAL:ensure-init)
  (setq *HAL:debug-mode* (not *HAL:debug-mode*))
  (HAL:save-config)
  (princ (strcat "\nDebug-Modus: " (if *HAL:debug-mode* "EIN" "AUS")))
  (HAL:log-write "INFO" (strcat "Debug-Modus: " (if *HAL:debug-mode* "EIN" "AUS")))
  (princ)
)

;;; Block-Verwaltung (HAL-eigene Namen, ueberschreiben nicht BlockImport-Befehle)
(defun c:HALBlock ()
  (HAL:ensure-init)
  (manage-block-import "HoeheAufLinie")
)

;;; ============================================================================
;;; LADE-MELDUNG (NUR PRINC auf Top-Level!)
;;; ============================================================================

(princ (strcat "\nHoeheAufLinie.lsp v" *HAL:version* " geladen."))
(princ "\nBefehle:")
(princ "\n  HoeheAufLinie (HAL)      - Hoeheninterpolation (S/K/E Keywords)")
(princ "\n  HALDEBUG                 - Debug ein/aus")
(princ "\n  HALBlock                 - Block-Verwaltung")
(princ "\n")
(princ)

;;; Ende der Datei
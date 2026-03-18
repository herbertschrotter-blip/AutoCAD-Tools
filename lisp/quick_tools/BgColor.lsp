;;; ============================================================
;;; BgColor.lsp
;;; Hintergrundfarbe per Toggle umschalten
;;;
;;; Version: 1.9.1
;;; Datum:   2026-03-18
;;; Autor:   Herbert Schrotter
;;; Namespace: BGC (BgColor)
;;;
;;; AppData: %APPDATA%\AutoCAD\Lisp\BgColor\
;;;   - Log:    Log\BgColor_YYYYMMDD_HHMMSS.log
;;;   - Config: Config\BgColor.cfg
;;;
;;; Installation:
;;;   APPLOAD > BgColor.lsp > Startup Suite hinzufuegen
;;;
;;; Befehle:
;;;   BGCOLOR  - Wechselt Hintergrund (Toggle) oder [E]instellungen
;;;
;;; Technische Details:
;;;   Model + Layout  : GraphicsWinModel/LayoutBackgrndColor (immer beide)
;;;   OLE-Color       : BGR-Integer (B*65536 + G*256 + R)
;;;   vlax-variant-change-type zum Lesen (Variant Type 19 -> Long)
;;;   Toggle-Status   : *BGC:state* Flag ("a" / "b"), unabhaengig von
;;;                     aktueller Farbe (robust bei manuellen Aenderungen)
;;; ============================================================

;;; ============================================================
;;; Globale Variablen - nur setzen wenn noch nil (Session-persistent)
;;; ============================================================
(if (not *BGC:color-a*) (setq *BGC:color-a* '(43 43 43)))     ; Dunkel
(if (not *BGC:color-b*) (setq *BGC:color-b* '(255 255 255)))  ; Hell
(if (not *BGC:state*)   (setq *BGC:state* "b"))                 ; "b" -> erster Toggle -> A

(setq *BGC:appdata-folder* "BgColor")
(setq *BGC:log-session-id* nil)
(setq *BGC:debug-mode* nil)
(setq *BGC:initialized* nil)

;;; ============================================================
;;; AppData & Logging
;;; ============================================================

;; AppData-Ordner ermitteln und ggf. erstellen
;; Pfad: %APPDATA%\AutoCAD\Lisp\BgColor\
(defun BGC:get-appdata-path ( / base)
  (setq base (strcat (getenv "APPDATA") "\\AutoCAD\\Lisp\\" *BGC:appdata-folder*))
  (if (not (vl-file-directory-p base))
    (progn
      (vl-mkdir (strcat (getenv "APPDATA") "\\AutoCAD"))
      (vl-mkdir (strcat (getenv "APPDATA") "\\AutoCAD\\Lisp"))
      (vl-mkdir base)
      (vl-mkdir (strcat base "\\Log"))
      (vl-mkdir (strcat base "\\Config"))
      (vl-mkdir (strcat base "\\Backup"))
    )
  )
  base
)

;; Log-Rotation: max 5 Session-Logs behalten
;; Wird beim ersten log-write der Session aufgerufen
(defun BGC:log-rotate ( / appdata log-dir pattern files sorted-files delete-count i f)
  (setq appdata (BGC:get-appdata-path))
  (setq log-dir (strcat appdata "\\Log"))
  (setq pattern (strcat *BGC:appdata-folder* "_*.log"))
  (setq files nil)
  (setq f (vl-directory-files log-dir pattern 1))
  (if f (setq files f))
  (setq sorted-files (vl-sort files '<))
  ;; 5. ist die aktuelle (noch nicht erstellt) → 4 behalten
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

;; Log-Eintrag schreiben
;; level: "INFO", "WARN", "ERROR", "DEBUG"
;; message: Beliebiger String
(defun BGC:log-write (level message / appdata log-path fp timestamp)
  ;; Debug nur wenn aktiviert
  (if (and (= level "DEBUG") (not *BGC:debug-mode*))
    (progn) ; Skip
    (progn
      ;; Session-ID einmal pro Session erzeugen
      (if (not *BGC:log-session-id*)
        (progn
          (setq *BGC:log-session-id*
            (strcat *BGC:appdata-folder* "_"
              (menucmd "M=$(edtime,0,YYYYMMDD_HHMMSS)")
            )
          )
          ;; Log-Rotation beim ersten Schreiben
          (BGC:log-rotate)
        )
      )
      (setq appdata (BGC:get-appdata-path))
      (setq log-path (strcat appdata "\\Log\\" *BGC:log-session-id* ".log"))
      ;; Timestamp erzeugen
      (setq timestamp (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM:SS)"))
      ;; Schreiben
      (setq fp (open log-path "a"))
      (if fp
        (progn
          (write-line
            (strcat "[" timestamp "] ["
              (substr (strcat level "     ") 1 5) ; Padding auf 5 Zeichen
              "] " message)
            fp)
          (close fp)
        )
      )
    )
  )
)

;;; ============================================================
;;; Config-Management
;;; ============================================================

;; Config lesen aus %APPDATA%\AutoCAD\Lisp\BgColor\Config\BgColor.cfg
;; Format: KEY=VALUE pro Zeile
;; Setzt Defaults wenn Datei nicht existiert oder Werte ungueltig
(defun BGC:load-config ( / appdata cfg-path fp line key val parsed)
  (setq appdata (BGC:get-appdata-path))
  (setq cfg-path (strcat appdata "\\Config\\" *BGC:appdata-folder* ".cfg"))
  (if (findfile cfg-path)
    (progn
      (setq fp (open cfg-path "r"))
      (if fp
        (progn
          (while (setq line (read-line fp))
            ;; Zeile an "=" splitten
            (if (vl-string-search "=" line)
              (progn
                (setq key (substr line 1 (vl-string-search "=" line)))
                (setq val (substr line (+ 2 (vl-string-search "=" line))))
                (cond
                  ((= key "COLOR_A")
                   (setq parsed (BGC:str->rgb val))
                   (if parsed (setq *BGC:color-a* parsed))
                  )
                  ((= key "COLOR_B")
                   (setq parsed (BGC:str->rgb val))
                   (if parsed (setq *BGC:color-b* parsed))
                  )
                ) ;end cond
              )
            ) ;end if "="
          ) ;end while
          (close fp)
          (BGC:log-write "INFO"
            (strcat "Config geladen: A=(" (BGC:rgb->str *BGC:color-a*)
                    ") B=(" (BGC:rgb->str *BGC:color-b*) ")"))
        )
      )
    )
    ;; Keine Config vorhanden → Defaults beibehalten, Config erstellen
    (progn
      (BGC:log-write "INFO" "Keine Config gefunden, verwende Defaults")
      (BGC:save-config)
    )
  )
)

;; Config schreiben
(defun BGC:save-config ( / appdata cfg-path fp)
  (setq appdata (BGC:get-appdata-path))
  (setq cfg-path (strcat appdata "\\Config\\" *BGC:appdata-folder* ".cfg"))
  (setq fp (open cfg-path "w"))
  (if fp
    (progn
      (write-line (strcat "VERSION=1.0") fp)
      (write-line (strcat "COLOR_A=" (BGC:rgb->str *BGC:color-a*)) fp)
      (write-line (strcat "COLOR_B=" (BGC:rgb->str *BGC:color-b*)) fp)
      (close fp)
      (BGC:log-write "INFO"
        (strcat "Config gespeichert: A=(" (BGC:rgb->str *BGC:color-a*)
                ") B=(" (BGC:rgb->str *BGC:color-b*) ")"))
    )
    (BGC:log-write "ERROR" (strcat "Config nicht schreibbar: " cfg-path))
  )
)

;;; ============================================================
;;; Lazy-Init
;;; ============================================================

(defun BGC:ensure-init ( / )
  (if (not *BGC:initialized*)
    (progn
      (vl-load-com)
      (BGC:load-config)
      (setq *BGC:initialized* T)
      (BGC:log-write "INFO" "=== BgColor v1.9.1 initialisiert ===")
    )
  )
)

;;; ============================================================
;;; Hilfsfunktionen
;;; ============================================================

;; Display-Objekt holen
(defun BGC:get-display ( / )
  (vla-get-display
    (vla-get-preferences
      (vlax-get-acad-object)))
)

;; RGB-Liste -> OLE-Color Integer (BGR: B*65536 + G*256 + R)
(defun BGC:rgb->ole (rgb)
  (+ (* (caddr rgb) 65536)
     (* (cadr  rgb) 256)
     (car rgb))
)

;; OLE-Color Integer -> RGB-Liste
(defun BGC:ole->rgb (c / )
  (list (rem c 256)
        (rem (/ c 256) 256)
        (/ c 65536))
)

;; RGB-Liste -> "R,G,B" String
(defun BGC:rgb->str (rgb)
  (strcat (itoa (car rgb)) ","
          (itoa (cadr rgb)) ","
          (itoa (caddr rgb)))
)

;; "R,G,B" String -> RGB-Liste, nil bei ungueltigem Format
(defun BGC:str->rgb (s / parts r g b)
  (setq parts (BGC:split-csv s))
  (if (= (length parts) 3)
    (progn
      (setq r (atoi (car parts))
            g (atoi (cadr parts))
            b (atoi (caddr parts)))
      (if (and (>= r 0) (<= r 255)
               (>= g 0) (<= g 255)
               (>= b 0) (<= b 255))
        (list r g b)
        nil
      )
    )
    nil
  )
)

;; String an Kommas splitten
(defun BGC:split-csv (s / result cur i ch)
  (setq result '() cur "" i 0)
  (while (< i (strlen s))
    (setq i (1+ i) ch (substr s i 1))
    (if (= ch ",")
      (progn (setq result (append result (list cur))) (setq cur ""))
      (setq cur (strcat cur ch))
    )
  )
  (append result (list cur))
)

;; Beide Bereiche setzen (Model + Layout immer gleichzeitig)
;; plain Integer zum Schreiben
(defun BGC:set-all (rgb / disp ole)
  (setq disp (BGC:get-display)
        ole  (BGC:rgb->ole rgb))
  (vla-put-GraphicsWinModelBackgrndColor  disp ole)
  (vla-put-GraphicsWinLayoutBackgrndColor disp ole)
  (BGC:log-write "DEBUG"
    (strcat "VLA: Model+Layout gesetzt, OLE=" (itoa ole)))
)

;;; ============================================================
;;; DCL Einstellungen-Dialog
;;; ============================================================

(defun BGC:write-dcl (filepath / f)
  (setq f (open filepath "w"))
  (write-line "bgcolor_settings : dialog {" f)
  (write-line "  label = \"BgColor - Farbverwaltung\";" f)
  (write-line "  : text { label = \"Format: R,G,B  (je 0-255)\"; }" f)
  (write-line "  spacer;" f)
  (write-line "  : row {" f)
  (write-line "    : text { label = \"Farbe A:\"; width = 9; fixed_width = true; }" f)
  (write-line "    : edit_box { key = \"edit_a\"; width = 16; fixed_width = true; }" f)
  (write-line "  }" f)
  (write-line "  : text { key = \"preview_a\"; label = \"Farbe A: -\"; }" f)
  (write-line "  spacer;" f)
  (write-line "  : row {" f)
  (write-line "    : text { label = \"Farbe B:\"; width = 9; fixed_width = true; }" f)
  (write-line "    : edit_box { key = \"edit_b\"; width = 16; fixed_width = true; }" f)
  (write-line "  }" f)
  (write-line "  : text { key = \"preview_b\"; label = \"Farbe B: -\"; }" f)
  (write-line "  spacer;" f)
  (write-line "  : row {" f)
  (write-line "    : button { key = \"btn_save\";   label = \"Speichern\";  is_default = true;  width = 12; fixed_width = true; }" f)
  (write-line "    : button { key = \"btn_cancel\"; label = \"Abbrechen\"; is_cancel = true; width = 12; fixed_width = true; }" f)
  (write-line "  }" f)
  (write-line "}" f)
  (close f)
)

(defun BGC:show-settings ( / dcl-file dcl-id result str-a str-b new-a new-b old-a-str old-b-str)
  (BGC:log-write "INFO" "Einstellungen-Dialog geoeffnet")
  (setq dcl-file (strcat (getvar "TEMPPREFIX") "bgcolor_settings.dcl"))
  (BGC:write-dcl dcl-file)
  (setq dcl-id (load_dialog dcl-file))
  (if (< dcl-id 0)
    (progn
      (BGC:log-write "ERROR" "DCL nicht geladen")
      (princ "\n[BgColor] Fehler: DCL nicht geladen.")
      (exit)
    )
  )
  (if (not (new_dialog "bgcolor_settings" dcl-id))
    (progn
      (BGC:log-write "ERROR" "Dialog nicht geoeffnet")
      (princ "\n[BgColor] Fehler: Dialog nicht geoeffnet.")
      (unload_dialog dcl-id)
      (exit)
    )
  )
  (setq str-a (BGC:rgb->str *BGC:color-a*)
        str-b (BGC:rgb->str *BGC:color-b*))
  ;; Alte Werte merken fuer Log-Vergleich
  (setq old-a-str str-a
        old-b-str str-b)
  (set_tile "edit_a" str-a)
  (set_tile "edit_b" str-b)
  (set_tile "preview_a" (strcat "Farbe A: " str-a))
  (set_tile "preview_b" (strcat "Farbe B: " str-b))
  (action_tile "edit_a"
    "(set_tile \"preview_a\" (strcat \"Farbe A: \" $value))")
  (action_tile "edit_b"
    "(set_tile \"preview_b\" (strcat \"Farbe B: \" $value))")
  (action_tile "btn_save"
    "(setq str-a (get_tile \"edit_a\") str-b (get_tile \"edit_b\")) (done_dialog 1)")
  (action_tile "btn_cancel"
    "(done_dialog 0)")
  (setq result (start_dialog))
  (unload_dialog dcl-id)
  (vl-catch-all-apply 'vl-file-delete (list dcl-file))
  (if (= result 1)
    (progn
      (setq new-a (BGC:str->rgb str-a)
            new-b (BGC:str->rgb str-b))
      (cond
        ((not new-a)
         (BGC:log-write "WARN" (strcat "Ungueltige Farbe A: '" str-a "'"))
         (princ (strcat "\n[BgColor] Ungueltige Farbe A: '" str-a "' - Format: R,G,B")))
        ((not new-b)
         (BGC:log-write "WARN" (strcat "Ungueltige Farbe B: '" str-b "'"))
         (princ (strcat "\n[BgColor] Ungueltige Farbe B: '" str-b "' - Format: R,G,B")))
        (T
         (setq *BGC:color-a* new-a
               *BGC:color-b* new-b)
         ;; Config persistent speichern
         (BGC:save-config)
         ;; Log: was hat sich geaendert?
         (if (not (equal old-a-str (BGC:rgb->str *BGC:color-a*)))
           (BGC:log-write "INFO"
             (strcat "Farbe A geaendert: (" old-a-str ") -> (" (BGC:rgb->str *BGC:color-a*) ")"))
         )
         (if (not (equal old-b-str (BGC:rgb->str *BGC:color-b*)))
           (BGC:log-write "INFO"
             (strcat "Farbe B geaendert: (" old-b-str ") -> (" (BGC:rgb->str *BGC:color-b*) ")"))
         )
         (if (and (equal old-a-str (BGC:rgb->str *BGC:color-a*))
                  (equal old-b-str (BGC:rgb->str *BGC:color-b*)))
           (BGC:log-write "INFO" "Einstellungen: keine Aenderung")
         )
         (princ (strcat "\n[BgColor] A: (" (BGC:rgb->str *BGC:color-a*)
                        ")  B: (" (BGC:rgb->str *BGC:color-b*) ")"))
         (princ "\n[BgColor] Einstellungen gespeichert.")
        )
      )
    )
    (progn
      (BGC:log-write "INFO" "Einstellungen: Abgebrochen")
      (princ "\n[BgColor] Abgebrochen.")
    )
  )
)

;;; ============================================================
;;; c:BGCOLOR - Toggle oder [E]instellungen
;;; ============================================================
(defun c:BGCOLOR ( / *error* old-cmdecho choice next-rgb next-state)

  (defun *error* (msg)
    (if (not (wcmatch (strcase msg) "*ABBRUCH*,*ABGEBROCHEN*,*CANCEL*,*QUIT*,*EXIT*"))
      (progn
        (BGC:log-write "ERROR" (strcat "Error-Handler: " msg))
        (princ (strcat "\n[BgColor] Fehler: " msg))
      )
      (BGC:log-write "INFO" "User: Abbruch (ESC/Cancel)")
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )

  (BGC:ensure-init)

  (BGC:log-write "INFO" "Befehl BGCOLOR gestartet")

  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  (initget "Einstellungen")
  (setq choice (getkword
    "\nBgColor [Einstellungen] <Toggle>: "))

  (cond
    ((= choice "Einstellungen")
     (BGC:log-write "INFO" "Option: Einstellungen")
     (BGC:show-settings)
    )
    (T
     ;; State-Flag: stur abwechseln, unabhaengig von aktueller Farbe
     (if (equal *BGC:state* "a")
       (setq next-rgb *BGC:color-b*  next-state "b")
       (setq next-rgb *BGC:color-a*  next-state "a")
     )
     ;; Beide Bereiche setzen
     (BGC:set-all next-rgb)
     (setq *BGC:state* next-state)
     (BGC:log-write "INFO"
       (strcat "Toggle: " (strcase *BGC:state*) " -> ("
               (BGC:rgb->str next-rgb) ")"))
     (princ (strcat "\n[BgColor] -> (" (BGC:rgb->str next-rgb) ")"
                    "  [" (strcase next-state) "]"))
    )
  )

  (BGC:log-write "INFO" "Befehl BGCOLOR beendet")
  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

;;; ============================================================
;;; Ladebestaetigung
;;; ============================================================
(princ "\nBgColor.lsp v1.9.1 geladen.")
(princ (strcat "\n  A: (" (BGC:rgb->str *BGC:color-a*)
               ")  B: (" (BGC:rgb->str *BGC:color-b*) ")"))
(princ "\nBefehl: BGCOLOR  [Enter=Toggle | E=Einstellungen]")
(princ)
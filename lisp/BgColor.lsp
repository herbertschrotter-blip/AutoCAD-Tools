;;; ============================================================
;;; BgColor.lsp
;;; Hintergrundfarbe per Toggle umschalten
;;;
;;; Version: 1.7.1
;;; Datum:   2026-03-17
;;; Autor:   Herbert Schrotter
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

(vl-load-com)

;;; ============================================================
;;; Globale Variablen - nur setzen wenn noch nil (Session-persistent)
;;; ============================================================
(if (not *BGC:color-a*) (setq *BGC:color-a* '(43 43 43)))     ; Dunkel
(if (not *BGC:color-b*) (setq *BGC:color-b* '(255 255 255)))  ; Hell
(if (not *BGC:state*)   (setq *BGC:state* "b"))                 ; "b" -> erster Toggle -> A

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
;; vlax-variant-change-type zum Lesen (Variant Type 19 -> Long)
;; plain Integer zum Schreiben
(defun BGC:set-all (rgb / disp ole)
  (setq disp (BGC:get-display)
        ole  (BGC:rgb->ole rgb))
  (vla-put-GraphicsWinModelBackgrndColor  disp ole)
  (vla-put-GraphicsWinLayoutBackgrndColor disp ole)
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

(defun BGC:show-settings ( / dcl-file dcl-id result str-a str-b new-a new-b)
  (setq dcl-file (strcat (getvar "TEMPPREFIX") "bgcolor_settings.dcl"))
  (BGC:write-dcl dcl-file)
  (setq dcl-id (load_dialog dcl-file))
  (if (< dcl-id 0)
    (progn (princ "\n[BgColor] Fehler: DCL nicht geladen.") (exit))
  )
  (if (not (new_dialog "bgcolor_settings" dcl-id))
    (progn
      (princ "\n[BgColor] Fehler: Dialog nicht geoeffnet.")
      (unload_dialog dcl-id)
      (exit)
    )
  )
  (setq str-a (BGC:rgb->str *BGC:color-a*)
        str-b (BGC:rgb->str *BGC:color-b*))
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
         (princ (strcat "\n[BgColor] Ungueltige Farbe A: '" str-a "' - Format: R,G,B")))
        ((not new-b)
         (princ (strcat "\n[BgColor] Ungueltige Farbe B: '" str-b "' - Format: R,G,B")))
        (T
         (setq *BGC:color-a* new-a
               *BGC:color-b* new-b)
         (princ (strcat "\n[BgColor] A: (" (BGC:rgb->str *BGC:color-a*)
                        ")  B: (" (BGC:rgb->str *BGC:color-b*) ")"))
         (princ "\n[BgColor] Einstellungen gespeichert.")
        )
      )
    )
    (princ "\n[BgColor] Abgebrochen.")
  )
)

;;; ============================================================
;;; c:BGCOLOR - Toggle oder [E]instellungen
;;; ============================================================
(defun c:BGCOLOR ( / *error* old-cmdecho choice next-rgb next-state)

  (defun *error* (msg)
    (if (not (wcmatch (strcase msg) "*ABBRUCH*,*CANCEL*,*QUIT*"))
      (princ (strcat "\n[BgColor] Fehler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )

  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  (initget "Einstellungen")
  (setq choice (getkword
    "\nBgColor [Enter=Toggle / Einstellungen] <Toggle>: "))

  (cond
    ((= choice "Einstellungen")
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
     (princ (strcat "\n[BgColor] -> (" (BGC:rgb->str next-rgb) ")"
                    "  [" (strcase next-state) "]"))
    )
  )

  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

;;; ============================================================
;;; Ladebestaetigung
;;; ============================================================
(princ "\nBgColor.lsp v1.7.1 geladen.")
(princ (strcat "\n  A: (" (BGC:rgb->str *BGC:color-a*)
               ")  B: (" (BGC:rgb->str *BGC:color-b*) ")"))
(princ "\nBefehl: BGCOLOR  [Enter=Toggle | E=Einstellungen]")
(princ)
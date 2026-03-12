;;; ============================================================
;;; BgColor.lsp
;;; Hintergrundfarbe per Toggle umschalten
;;;
;;; Version: 1.1.0
;;; Datum:   2026-03-12
;;; Autor:   Herbert Schrotter
;;;
;;; Installation:
;;;   APPLOAD > BgColor.lsp > Startup Suite hinzufuegen
;;;
;;; Befehle:
;;;   BGCOLOR  - Wechselt Hintergrund (Toggle) oder [E]instellungen
;;; ============================================================

(vl-load-com)

;;; ============================================================
;;; Globale Defaults (werden beim Laden gesetzt falls noch nil)
;;; Format: (R G B) als Liste
;;; ============================================================
(if (not *BGC:color-a*) (setq *BGC:color-a* '(43 43 43)))      ; Dunkel
(if (not *BGC:color-b*) (setq *BGC:color-b* '(255 255 255)))   ; Hell

;;; ============================================================
;;; Hilfsfunktionen
;;; ============================================================

;; RGB-Liste -> TrueColor-Integer
(defun BGC:rgb-to-int (rgb / r g b)
  (setq r (car rgb)
        g (cadr rgb)
        b (caddr rgb))
  (+ (* r 65536) (* g 256) b)
)

;; TrueColor-Integer -> RGB-Liste
(defun BGC:int-to-rgb (n / r g b)
  (setq r (/ n 65536))
  (setq g (/ (rem n 65536) 256))
  (setq b (rem n 256))
  (list r g b)
)

;; RGB-Liste -> "R,G,B" String
(defun BGC:rgb-to-str (rgb)
  (strcat (itoa (car rgb)) ","
          (itoa (cadr rgb)) ","
          (itoa (caddr rgb)))
)

;; "R,G,B" String -> RGB-Liste (nil bei Fehler)
(defun BGC:str-to-rgb (s / parts r g b)
  (setq parts (BGC:split-csv s))
  (if (and parts (= (length parts) 3))
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

;; Einfacher CSV-Splitter fuer "R,G,B"
(defun BGC:split-csv (s / result cur i ch)
  (setq result '()
        cur ""
        i 0)
  (while (< i (strlen s))
    (setq i (1+ i)
          ch (substr s i 1))
    (if (= ch ",")
      (progn
        (setq result (append result (list cur)))
        (setq cur "")
      )
      (setq cur (strcat cur ch))
    )
  )
  (setq result (append result (list cur)))
  result
)

;; Alle 3 Bereiche setzen
(defun BGC:set-all (rgb / color-int)
  (setq color-int (BGC:rgb-to-int rgb))
  (setvar "BACKGROUND" color-int)
  (if (vl-catch-all-error-p
        (vl-catch-all-apply 'setvar (list "LAYOUTBACKGROUNDCOLOR" color-int)))
    (princ "\n[BgColor] LAYOUTBACKGROUNDCOLOR nicht verfuegbar.")
  )
  (if (vl-catch-all-error-p
        (vl-catch-all-apply 'setvar (list "BKGDCOLOR" color-int)))
    (princ "\n[BgColor] BKGDCOLOR nicht verfuegbar.")
  )
)

;; Aktuellen BACKGROUND als RGB holen
(defun BGC:current-rgb ()
  (BGC:int-to-rgb (getvar "BACKGROUND"))
)

;; Pruefen ob aktuell Farbe A aktiv ist (Toleranz 0)
(defun BGC:is-color-a-p ()
  (equal (BGC:current-rgb) *BGC:color-a*)
)

;;; ============================================================
;;; DCL - Einstellungen-Dialog (temp file Methode)
;;; ============================================================
(defun BGC:show-settings ( / dcl-id dcl-file result
                             str-a str-b new-a new-b)

  ;; DCL-Inhalt als Temp-Datei schreiben
  (setq dcl-file (vl-filename-mktemp "bgcolor" nil ".dcl"))

  (vl-file-copy
    dcl-file dcl-file  ; dummy - wir schreiben direkt
  )

  ;; DCL schreiben
  (setq dcl-file (strcat (getvar "TEMPPREFIX") "bgcolor_settings.dcl"))
  (BGC:write-dcl dcl-file)

  ;; Dialog laden
  (setq dcl-id (load_dialog dcl-file))
  (if (< dcl-id 0)
    (progn
      (princ "\n[BgColor] Fehler: DCL konnte nicht geladen werden.")
      (exit)
    )
  )
  (if (not (new_dialog "bgcolor_settings" dcl-id))
    (progn
      (princ "\n[BgColor] Fehler: Dialog konnte nicht geoeffnet werden.")
      (unload_dialog dcl-id)
      (exit)
    )
  )

  ;; Felder mit aktuellen Werten befuellen
  (setq str-a (BGC:rgb-to-str *BGC:color-a*)
        str-b (BGC:rgb-to-str *BGC:color-b*))
  (set_tile "edit_a" str-a)
  (set_tile "edit_b" str-b)
  (set_tile "preview_a" (strcat "Farbe A: " str-a))
  (set_tile "preview_b" (strcat "Farbe B: " str-b))

  ;; Live-Preview bei Eingabe
  (action_tile "edit_a"
    "(set_tile \"preview_a\" (strcat \"Farbe A: \" $value))"
  )
  (action_tile "edit_b"
    "(set_tile \"preview_b\" (strcat \"Farbe B: \" $value))"
  )

  ;; Speichern
  (action_tile "btn_save"
    "(setq str-a (get_tile \"edit_a\") str-b (get_tile \"edit_b\")) (done_dialog 1)"
  )

  ;; Abbrechen
  (action_tile "btn_cancel"
    "(done_dialog 0)"
  )

  (setq result (start_dialog))
  (unload_dialog dcl-id)

  ;; Temp-Datei aufraumen
  (vl-catch-all-apply 'vl-file-delete (list dcl-file))

  ;; Bei Speichern: validieren und uebernehmen
  (if (= result 1)
    (progn
      (setq new-a (BGC:str-to-rgb str-a))
      (setq new-b (BGC:str-to-rgb str-b))
      (cond
        ((not new-a)
         (princ (strcat "\n[BgColor] Ungueltige Farbe A: '" str-a "' - Format: R,G,B (0-255)"))
        )
        ((not new-b)
         (princ (strcat "\n[BgColor] Ungueltige Farbe B: '" str-b "' - Format: R,G,B (0-255)"))
        )
        (T
         (setq *BGC:color-a* new-a
               *BGC:color-b* new-b)
         (princ (strcat "\n[BgColor] Farbe A: " (BGC:rgb-to-str *BGC:color-a*)))
         (princ (strcat "\n[BgColor] Farbe B: " (BGC:rgb-to-str *BGC:color-b*)))
         (princ "\n[BgColor] Einstellungen gespeichert.")
        )
      )
    )
    (princ "\n[BgColor] Einstellungen unveraendert.")
  )
)

;; DCL-Datei schreiben
(defun BGC:write-dcl (filepath / f)
  (setq f (open filepath "w"))
  (write-line "bgcolor_settings : dialog {" f)
  (write-line "  label = \"BgColor - Farbverwaltung\";" f)
  (write-line "  : text { label = \"Farben als R,G,B (je 0-255) eingeben:\"; }" f)
  (write-line "  spacer;" f)
  (write-line "  : row {" f)
  (write-line "    : text { label = \"Farbe A:\"; width = 8; fixed_width = true; }" f)
  (write-line "    : edit_box { key = \"edit_a\"; width = 16; fixed_width = true; }" f)
  (write-line "  }" f)
  (write-line "  : text { key = \"preview_a\"; label = \"Farbe A: -\"; }" f)
  (write-line "  spacer;" f)
  (write-line "  : row {" f)
  (write-line "    : text { label = \"Farbe B:\"; width = 8; fixed_width = true; }" f)
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

;;; ============================================================
;;; c:BGCOLOR - Toggle oder [E]instellungen
;;; ============================================================
(defun c:BGCOLOR ( / *error* old-cmdecho choice next-rgb)

  (defun *error* (msg)
    (if (not (wcmatch (strcase msg) "*ABBRUCH*,*CANCEL*,*QUIT*"))
      (princ (strcat "\n[BgColor] Fehler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )

  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  ;; Keyword-Prompt: Enter = Toggle, E = Einstellungen
  (initget "Einstellungen")
  (setq choice (getkword
    (strcat "\nBgColor [Enter=Toggle / Einstellungen] <Toggle>: ")))

  (cond

    ;; Einstellungen-Dialog oeffnen
    ((= choice "Einstellungen")
     (BGC:show-settings)
    )

    ;; Toggle (Enter oder nil)
    (T
     ;; Naechste Farbe bestimmen: wenn A aktiv -> B, sonst -> A
     (if (BGC:is-color-a-p)
       (setq next-rgb *BGC:color-b*)
       (setq next-rgb *BGC:color-a*)
     )
     (BGC:set-all next-rgb)
     (princ (strcat "\n[BgColor] -> (" (BGC:rgb-to-str next-rgb) ")"))
    )

  ) ;end cond

  (setvar "CMDECHO" old-cmdecho)
  (princ)
)

;;; ============================================================
;;; Ladebestaetigung
;;; ============================================================
(princ "\nBgColor.lsp v1.1.0 geladen.")
(princ (strcat "\n  Farbe A: (" (BGC:rgb-to-str *BGC:color-a*) ")"))
(princ (strcat "\n  Farbe B: (" (BGC:rgb-to-str *BGC:color-b*) ")"))
(princ "\nBefehl: BGCOLOR  [Enter=Toggle | E=Einstellungen]")
(princ)
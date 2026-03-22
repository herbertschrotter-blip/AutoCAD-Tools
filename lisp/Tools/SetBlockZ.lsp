;;; ============================================================================
;;; SetBlockZ.lsp
;;; Setzt Block-Z-Koordinaten aus Attributwerten (Vermessungshöhen)
;;;
;;; Version: 1.15.1
;;; Datum: 2026-03-22
;;; Autor: Herbert Schrotter
;;; Namespace: SBZ (SetBlockZ)
;;;
;;; Beschreibung:
;;; Architekten liefern Pläne bei denen Vermessungsblöcke auf Z=0 stehen.
;;; Die tatsächliche Höhe steht als Attributwert im Block.
;;; Dieses Script setzt die Z-Koordinate aller Blockinstanzen auf den
;;; Attributwert (abzüglich Bau-0-Höhe), damit ein 3D-Geländemodell
;;; erstellt werden kann (z.B. für Leica).
;;;
;;; AppData: %APPDATA%\AutoCAD\Lisp\SetBlockZ\
;;;   - Log:    Log\SetBlockZ_YYYYMMDD_HHMMSS.log
;;;   - Config: Config\SetBlockZ.cfg
;;;
;;; Installation:
;;; 1. APPLOAD ausführen
;;; 2. SetBlockZ.lsp laden
;;; 3. Optional: Startup Suite für automatisches Laden
;;;
;;; Befehle:
;;; SETBLOCKZ    - Hauptbefehl: Blöcke nach Attribut auf Z setzen
;;; SBZSETTINGS  - Einstellungen (Bau-0, Toggles, Neuberechnung)
;;; SBZPURGE     - Kopie-Blöcke löschen + Block-Definition purgen
;;; SBZDEBUG     - Debug-Modus ein/aus
;;; ============================================================================


;;; ============================================================================
;;; KONFIGURATION (KONSTANTEN)
;;; ============================================================================

(setq *SBZ:version* "1.15.1")
(setq *SBZ:namespace* "SBZ")
(setq *SBZ:appdata-folder* "SetBlockZ")

;; Custom Property Name fuer Bau-0-Hoehe in DWG SummaryInfo
(setq *SBZ:cp-bau0* "SetBlockZ_Bau0")
;; Custom Property fuer letzten Blockname und Attribut-Tag (pro DWG!)
(setq *SBZ:cp-blockname* "SetBlockZ_BlockName")
(setq *SBZ:cp-attrtag* "SetBlockZ_AttrTag")
(setq *SBZ:cp-scale* "SetBlockZ_Scale")
(setq *SBZ:cp-suffix* "SetBlockZ_Suffix")
(setq *SBZ:cp-font* "SetBlockZ_Font")


;;; ============================================================================
;;; GLOBALE VARIABLEN
;;; ============================================================================

(setq *SBZ:initialized* nil)
(setq *SBZ:log-session-id* nil)
(setq *SBZ:debug-mode* nil)

;; Config-Werte (Defaults) — nur Toggles, NICHT zeichnungsspezifisch
(setq *SBZ:cfg-byblock* 1)          ;; Farbe auf ByBlock setzen (0/1)
(setq *SBZ:cfg-movelayer* 0)        ;; Block auf Ziel-Layer verschieben (0/1)
(setq *SBZ:cfg-target-layer* "")    ;; Ziel-Layer Name
(setq *SBZ:cfg-copymode* 1)         ;; Kopie-Modus: Standard EIN (0/1)
(setq *SBZ:cfg-copyblock* "VermesserGOK") ;; Blockname fuer Kopie-Block
(setq *SBZ:cfg-copylayer* "GOK")    ;; Basis-Layername fuer Kopie-Block (Suffix wird angehaengt)
(setq *SBZ:cfg-freeze-abs* 0)       ;; AttABS Layer einfrieren (0=sichtbar, 1=gefroren)
(setq *SBZ:cfg-freeze-rel* 0)       ;; AttREL Layer einfrieren (0=sichtbar, 1=gefroren)
(setq *SBZ:cfg-freeze-bau0* 1)      ;; AttBAU0 Layer einfrieren (0=sichtbar, 1=gefroren)
(setq *SBZ:cfg-font* "Arial")       ;; Schriftart fuer Attribute (TTF-Name)
;; Farben: ACI-Index (1=Rot,2=Gelb,3=Gruen,4=Cyan,5=Blau,6=Magenta,7=Weiss,256=VonLayer)
;; Attribut-Farbe 0 = Von Block (ByBlock)
(setq *SBZ:cfg-color-block* 7)      ;; Block-Symbol Farbe (ACI, Default: Weiss)
(setq *SBZ:cfg-color-abs* 0)        ;; HOEHE_ABS Attribut-Farbe (0=Von Block)
(setq *SBZ:cfg-color-rel* 0)        ;; HOEHE_REL Attribut-Farbe (0=Von Block)
(setq *SBZ:cfg-color-bau0* 0)       ;; HOEHE_BAU0 Attribut-Farbe (0=Von Block)


;;; ============================================================================
;;; APPDATA & LOGGING
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; SBZ:get-appdata-path
;;; Gibt den AppData-Basisordner zurueck, erstellt Struktur falls noetig
;;; Rueckgabe: Pfad-String (ohne trailing Backslash)
;;; ----------------------------------------------------------------------------
(defun SBZ:get-appdata-path ( / base)
  (setq base (strcat (getenv "APPDATA") "\\AutoCAD\\Lisp\\" *SBZ:appdata-folder*))
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


;;; ----------------------------------------------------------------------------
;;; SBZ:log-write
;;; Schreibt eine Zeile ins Session-Log
;;; Parameter:
;;;   level   - "INFO", "WARN", "ERROR", "DEBUG"
;;;   message - Beliebiger String
;;; ----------------------------------------------------------------------------
(defun SBZ:log-write (level message / appdata log-path fp timestamp)
  ;; DEBUG nur wenn aktiviert
  (if (and (= level "DEBUG") (not *SBZ:debug-mode*))
    nil ;; Skip
    (progn
      ;; Session-Log-Pfad beim ersten Schreiben erstellen
      (if (not *SBZ:log-session-id*)
        (progn
          (setq *SBZ:log-session-id*
            (strcat *SBZ:appdata-folder* "_"
              (menucmd "M=$(edtime,0,YYYYMMDD_HHMMSS)")
            )
          )
          ;; Log-Rotation beim ersten Schreiben
          (SBZ:log-rotate)
        )
      )
      (setq appdata (SBZ:get-appdata-path))
      (setq log-path (strcat appdata "\\Log\\" *SBZ:log-session-id* ".log"))
      ;; Timestamp
      (setq timestamp (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM:SS)"))
      ;; Schreiben
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


;;; ----------------------------------------------------------------------------
;;; SBZ:log-rotate
;;; Loescht alte Logs, behaelt nur die 5 neuesten
;;; ----------------------------------------------------------------------------
(defun SBZ:log-rotate ( / appdata log-dir files sorted-files delete-count i)
  (setq appdata (SBZ:get-appdata-path))
  (setq log-dir (strcat appdata "\\Log"))
  ;; Alle Log-Dateien finden
  (setq files (vl-directory-files log-dir (strcat *SBZ:appdata-folder* "_*.log") 1))
  (if files
    (progn
      ;; Sortieren (Dateiname enthaelt Timestamp = chronologisch)
      (setq sorted-files (vl-sort files '<))
      ;; Wenn mehr als 4 vorhanden (5. ist die aktuelle, noch nicht erstellt)
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
;;; CONFIG-MANAGEMENT (AppData - fuer Toggles und Letzte-Wahl)
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; SBZ:load-config
;;; Laedt Config aus AppData\Config\SetBlockZ.cfg
;;; Format: KEY=VALUE pro Zeile
;;; ----------------------------------------------------------------------------
(defun SBZ:load-config ( / appdata cfg-path fp line pos key val)
  (setq appdata (SBZ:get-appdata-path))
  (setq cfg-path (strcat appdata "\\Config\\" *SBZ:appdata-folder* ".cfg"))
  (if (findfile cfg-path)
    (progn
      (setq fp (open cfg-path "r"))
      (while (setq line (read-line fp))
        (setq pos (vl-string-search "=" line))
        (if pos
          (progn
            (setq key (substr line 1 pos))
            (setq val (substr line (+ pos 2)))
            (cond
              ((= key "BYBLOCK")    (setq *SBZ:cfg-byblock* (atoi val)))
              ((= key "MOVELAYER")  (setq *SBZ:cfg-movelayer* (atoi val)))
              ((= key "TARGETLAYER")(setq *SBZ:cfg-target-layer* val))
              ((= key "COPYMODE")   (setq *SBZ:cfg-copymode* (atoi val)))
              ((= key "COPYBLOCK")  (setq *SBZ:cfg-copyblock* val))
              ((= key "COPYLAYER")  (setq *SBZ:cfg-copylayer* val))
              ((= key "FREEZEABS") (setq *SBZ:cfg-freeze-abs* (atoi val)))
              ((= key "FREEZEREL") (setq *SBZ:cfg-freeze-rel* (atoi val)))
              ((= key "FREEZEBAU0")(setq *SBZ:cfg-freeze-bau0* (atoi val)))
              ((= key "FONT")      (setq *SBZ:cfg-font* val))
              ((= key "COLORBLOCK")(setq *SBZ:cfg-color-block* (atoi val)))
              ((= key "COLORABS")  (setq *SBZ:cfg-color-abs* (atoi val)))
              ((= key "COLORREL")  (setq *SBZ:cfg-color-rel* (atoi val)))
              ((= key "COLORBAU0") (setq *SBZ:cfg-color-bau0* (atoi val)))
            )
          )
        )
      )
      (close fp)
      (SBZ:log-write "INFO" (strcat "Config geladen: " cfg-path))
    )
    ;; Keine Config → Defaults bleiben
    (SBZ:log-write "WARN" "Keine Config gefunden, verwende Defaults")
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:save-config
;;; Speichert Config in AppData\Config\SetBlockZ.cfg
;;; ----------------------------------------------------------------------------
(defun SBZ:save-config ( / appdata cfg-path fp)
  (setq appdata (SBZ:get-appdata-path))
  (setq cfg-path (strcat appdata "\\Config\\" *SBZ:appdata-folder* ".cfg"))
  (setq fp (open cfg-path "w"))
  (if fp
    (progn
      (write-line (strcat "VERSION=" *SBZ:version*) fp)
      (write-line (strcat "BYBLOCK=" (itoa *SBZ:cfg-byblock*)) fp)
      (write-line (strcat "MOVELAYER=" (itoa *SBZ:cfg-movelayer*)) fp)
      (write-line (strcat "TARGETLAYER=" *SBZ:cfg-target-layer*) fp)
      (write-line (strcat "COPYMODE=" (itoa *SBZ:cfg-copymode*)) fp)
      (write-line (strcat "COPYBLOCK=" *SBZ:cfg-copyblock*) fp)
      (write-line (strcat "COPYLAYER=" *SBZ:cfg-copylayer*) fp)
      (write-line (strcat "FREEZEABS=" (itoa *SBZ:cfg-freeze-abs*)) fp)
      (write-line (strcat "FREEZEREL=" (itoa *SBZ:cfg-freeze-rel*)) fp)
      (write-line (strcat "FREEZEBAU0=" (itoa *SBZ:cfg-freeze-bau0*)) fp)
      (write-line (strcat "FONT=" *SBZ:cfg-font*) fp)
      (write-line (strcat "COLORBLOCK=" (itoa *SBZ:cfg-color-block*)) fp)
      (write-line (strcat "COLORABS=" (itoa *SBZ:cfg-color-abs*)) fp)
      (write-line (strcat "COLORREL=" (itoa *SBZ:cfg-color-rel*)) fp)
      (write-line (strcat "COLORBAU0=" (itoa *SBZ:cfg-color-bau0*)) fp)
      (close fp)
      (SBZ:log-write "INFO" (strcat "Config gespeichert: " cfg-path))
    )
    (SBZ:log-write "ERROR" (strcat "Config konnte nicht geschrieben werden: " cfg-path))
  )
)


;;; ============================================================================
;;; CUSTOM PROPERTIES (in DWG SummaryInfo - wandern mit der Zeichnung!)
;;; ============================================================================
;;; Gespeichert werden:
;;;   SetBlockZ_Bau0      — Bau-0-Hoehe (String, z.B. "322.450")
;;;   SetBlockZ_BlockName  — Zuletzt verarbeiteter Blockname
;;;   SetBlockZ_AttrTag    — Zuletzt gewaehltes Attribut-Tag

;;; ----------------------------------------------------------------------------
;;; SBZ:get-custom-prop
;;; Generisch: Liest eine Custom Property aus DWG SummaryInfo
;;; Parameter: prop-name - Name der Property (String)
;;; Rueckgabe: Wert als String oder nil wenn nicht vorhanden
;;; ----------------------------------------------------------------------------
(defun SBZ:get-custom-prop (prop-name / doc si num-props i key val result)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq si (vla-get-summaryinfo doc))
  (setq num-props (vla-numcustominfo si))
  (setq result nil)
  (setq i 0)
  (while (and (not result) (< i num-props))
    (vla-getcustombyindex si i 'key 'val)
    (setq key (SBZ:safe-variant-value key))
    (setq val (SBZ:safe-variant-value val))
    (if (= (strcase key) (strcase prop-name))
      (setq result val)
    )
    (setq i (1+ i))
  )
  result
)


;;; ----------------------------------------------------------------------------
;;; SBZ:set-custom-prop
;;; Generisch: Schreibt/aktualisiert eine Custom Property in DWG SummaryInfo
;;; Parameter:
;;;   prop-name  - Name der Property (String)
;;;   prop-value - Wert als String
;;; Rueckgabe: T bei Erfolg
;;; ----------------------------------------------------------------------------
(defun SBZ:set-custom-prop (prop-name prop-value / doc si num-props i key val found)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq si (vla-get-summaryinfo doc))
  (setq num-props (vla-numcustominfo si))
  (setq found nil)
  ;; Pruefen ob Property schon existiert → Update
  (setq i 0)
  (while (and (not found) (< i num-props))
    (vla-getcustombyindex si i 'key 'val)
    (setq key (SBZ:safe-variant-value key))
    (if (= (strcase key) (strcase prop-name))
      (progn
        (vla-setcustombyindex si i prop-name prop-value)
        (setq found T)
      )
    )
    (setq i (1+ i))
  )
  ;; Nicht vorhanden → neu anlegen
  (if (not found)
    (progn
      (vla-addcustominfo si prop-name prop-value)
      (setq found T)
    )
  )
  (SBZ:log-write "DEBUG" (strcat "Custom Property '" prop-name "' = '" prop-value "'"))
  found
)


;;; --- Convenience-Wrapper fuer die 3 Properties ---

;;; Bau-0-Hoehe lesen (Real oder nil)
(defun SBZ:get-bau0 ( / val)
  (setq val (SBZ:get-custom-prop *SBZ:cp-bau0*))
  (if val
    (atof (vl-string-subst "." "," val))
    nil
  )
)

;;; Bau-0-Hoehe schreiben
(defun SBZ:set-bau0 (hoehe)
  (SBZ:set-custom-prop *SBZ:cp-bau0* (rtos hoehe 2 3))
  (SBZ:log-write "INFO" (strcat "Bau-0 gespeichert: " (rtos hoehe 2 3)))
)

;;; Letzter Blockname lesen (String oder nil)
(defun SBZ:get-last-blockname ()
  (SBZ:get-custom-prop *SBZ:cp-blockname*)
)

;;; Letzter Blockname schreiben
(defun SBZ:set-last-blockname (name)
  (SBZ:set-custom-prop *SBZ:cp-blockname* name)
)

;;; Letztes Attribut-Tag lesen (String oder nil)
(defun SBZ:get-last-attrtag ()
  (SBZ:get-custom-prop *SBZ:cp-attrtag*)
)

;;; Letztes Attribut-Tag schreiben
(defun SBZ:set-last-attrtag (tag)
  (SBZ:set-custom-prop *SBZ:cp-attrtag* tag)
)

;;; Block-Skalierung lesen (Real, Default 1.0)
(defun SBZ:get-scale ( / val)
  (setq val (SBZ:get-custom-prop *SBZ:cp-scale*))
  (if (and val (/= val ""))
    (atof val)
    1.0
  )
)

;;; Block-Skalierung schreiben
(defun SBZ:set-scale (scale)
  (SBZ:set-custom-prop *SBZ:cp-scale* (rtos scale 2 4))
  (SBZ:log-write "INFO" (strcat "Skalierung gespeichert: " (rtos scale 2 4)))
)

;;; Suffix lesen (String, Default "m ue. A.")
(defun SBZ:get-suffix ( / val)
  (setq val (SBZ:get-custom-prop *SBZ:cp-suffix*))
  (if (and val (/= val ""))
    val
    "m ue. A."
  )
)

;;; Suffix schreiben
(defun SBZ:set-suffix (s)
  (SBZ:set-custom-prop *SBZ:cp-suffix* s)
  (SBZ:log-write "INFO" (strcat "Suffix gespeichert: '" s "'"))
)

;;; Schriftart lesen (String, Default "Arial")
(defun SBZ:get-font ( / val)
  (setq val (SBZ:get-custom-prop *SBZ:cp-font*))
  (if (and val (/= val ""))
    val
    *SBZ:cfg-font*
  )
)

;;; Schriftart schreiben
(defun SBZ:set-font (f)
  (SBZ:set-custom-prop *SBZ:cp-font* f)
  (SBZ:log-write "INFO" (strcat "Schriftart gespeichert: '" f "'"))
)


;;; ============================================================================
;;; HILFSFUNKTIONEN
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; SBZ:rtos-fixed
;;; rtos mit erzwungenen Nachkommastellen (DIMZIN wird temporaer auf 0 gesetzt)
;;; AutoCADs rtos unterdrueckt trailing Zeros wenn DIMZIN Bit 8 gesetzt ist.
;;; Parameter:
;;;   val  - Zahl (Real)
;;;   prec - Anzahl Nachkommastellen (Integer)
;;; Rueckgabe: String mit exakt prec Nachkommastellen
;;; ----------------------------------------------------------------------------
(defun SBZ:rtos-fixed (val prec / old-dimzin result)
  (setq old-dimzin (getvar "DIMZIN"))
  (setvar "DIMZIN" 0)
  (setq result (rtos val 2 prec))
  (setvar "DIMZIN" old-dimzin)
  result
)


;;; ----------------------------------------------------------------------------
;;; SBZ:safe-variant-value
;;; Sicheres Auslesen: String oder Variant
;;; GetCustomByIndex gibt manchmal Strings direkt, manchmal Variants zurueck
;;; Parameter: val - String oder Variant
;;; Rueckgabe: String
;;; ----------------------------------------------------------------------------
(defun SBZ:safe-variant-value (val / )
  (cond
    ((= (type val) 'STR) val)
    ((= (type val) 'VLA-OBJECT) (vlax-variant-value val))
    ((not (null val))
      (vl-catch-all-apply 'vlax-variant-value (list val))
    )
    (T "")
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:cancel-p
;;; Prueft ob User abgebrochen hat (ESC, Cancel, etc.)
;;; Funktioniert in deutscher UND englischer AutoCAD-Version
;;; Parameter: msg - Fehlermeldung-String
;;; Rueckgabe: T wenn Cancel, nil sonst
;;; ----------------------------------------------------------------------------
(defun SBZ:cancel-p (msg)
  (wcmatch (strcase msg)
    "*ABBRUCH*,*ABGEBROCHEN*,*CANCEL*,*QUIT*,*EXIT*"
  )
)


;;; ============================================================================
;;; LAZY-INIT
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; SBZ:ensure-init
;;; Initialisierung beim ersten Befehlsaufruf
;;; Laedt VLA, Config, schreibt Start-Log
;;; ----------------------------------------------------------------------------
(defun SBZ:ensure-init ( / )
  (if (not *SBZ:initialized*)
    (progn
      ;; VLA laden
      (vl-load-com)
      ;; AppData-Ordner sicherstellen
      (SBZ:get-appdata-path)
      ;; Start-Log
      (SBZ:log-write "INFO"
        (strcat "=== SetBlockZ v" *SBZ:version* " gestartet ==="))
      ;; Config laden
      (SBZ:load-config)
      ;; Fertig
      (setq *SBZ:initialized* T)
      (SBZ:log-write "INFO" "Initialisierung abgeschlossen")
    )
  )
)


;;; ============================================================================
;;; DCL: FILTER-LISTBOX (Lee Mac Pattern, Embedded DCL)
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; SBZ:filtlistbox
;;; Filterbarer Auswahldialog (Lee Mac Pattern)
;;; Parameter:
;;;   msg - Dialog-Titel
;;;   lst - Liste der Eintraege (Strings)
;;;   mtp - T fuer Multi-Select, nil fuer Single-Select
;;; Rueckgabe: Liste der gewaehlten Strings oder nil bei Abbruch
;;; ----------------------------------------------------------------------------
(defun SBZ:filtlistbox (msg lst mtp / dch des tmp rtn)
  (cond
    ((not
      (and
        (setq tmp (vl-filename-mktemp nil nil ".dcl"))
        (setq des (open tmp "w"))
        (write-line
          (strcat
            "sbz_listbox : dialog { label = \"" msg "\";"
            " spacer;"
            " : edit_box { key = \"filter\"; label = \"Filter:\"; value = \"*\"; }"
            " spacer;"
            " : list_box { key = \"list\"; multiple_select = "
            (if mtp "true" "false")
            "; width = 50; height = 15; }"
            " spacer; ok_cancel; }"
          )
          des
        )
        (not (close des))
        (< 0 (setq dch (load_dialog tmp)))
        (new_dialog "sbz_listbox" dch)
      )
    )
    (princ "\nFehler: Listbox-Dialog konnte nicht geladen werden.")
    )
    (t
      ;; Liste fuellen
      (start_list "list")
      (foreach itm lst (add_list itm))
      (end_list)
      ;; Default-Auswahl: erstes Element
      (set_tile "list" "0")
      (setq rtn "0")
      ;; Filter-Aktion: Liste bei Eingabe neu aufbauen
      (action_tile "filter"
        (strcat
          "(progn"
          "  (start_list \"list\")"
          "  (foreach itm (vl-remove-if-not"
          "    (function (lambda (x) (wcmatch (strcase x) (strcase $value))))"
          "    lst)"
          "    (add_list itm))"
          "  (end_list))"
        )
      )
      ;; Auswahl merken
      (action_tile "list" "(setq rtn $value)")
      ;; Dialog starten
      (setq rtn
        (if (= 1 (start_dialog))
          (mapcar
            '(lambda (x) (nth x lst))
            (read (strcat "(" rtn ")"))
          )
        )
      )
    )
  )
  ;; Cleanup
  (if (and dch (< 0 dch)) (unload_dialog dch))
  (if (and tmp (findfile tmp)) (vl-file-delete tmp))
  rtn
)


;;; ============================================================================
;;; BLOCK-VERARBEITUNG
;;; ============================================================================

;;; --- Font-Anzeigename → TTF-Dateiname ---
(defun SBZ:font-to-ttf (font-name / )
  (cond
    ((= font-name "Arial") "arial.ttf")
    ((= font-name "Arial Bold") "arialbd.ttf")
    ((= font-name "Arial Italic") "ariali.ttf")
    ((= font-name "Arial Bold Italic") "arialbi.ttf")
    ((= font-name "Calibri") "calibri.ttf")
    ((= font-name "Calibri Bold") "calibrib.ttf")
    ((= font-name "Calibri Light") "calibril.ttf")
    ((= font-name "Cambria") "cambria.ttc")
    ((= font-name "Consolas") "consola.ttf")
    ((= font-name "Courier New") "cour.ttf")
    ((= font-name "Courier New Bold") "courbd.ttf")
    ((= font-name "Georgia") "georgia.ttf")
    ((= font-name "Impact") "impact.ttf")
    ((= font-name "Microsoft Sans Serif") "micross.ttf")
    ((= font-name "Palatino Linotype") "pala.ttf")
    ((= font-name "Segoe UI") "segoeui.ttf")
    ((= font-name "Segoe UI Bold") "segoeuib.ttf")
    ((= font-name "Tahoma") "tahoma.ttf")
    ((= font-name "Tahoma Bold") "tahomabd.ttf")
    ((= font-name "Times New Roman") "times.ttf")
    ((= font-name "Times New Roman Bold") "timesbd.ttf")
    ((= font-name "Trebuchet MS") "trebuc.ttf")
    ((= font-name "Trebuchet MS Bold") "trebucbd.ttf")
    ((= font-name "Verdana") "verdana.ttf")
    ((= font-name "Verdana Bold") "verdanab.ttf")
    (T (strcat font-name ".ttf"))  ;; Fallback
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:ensure-textstyle
;;; Erstellt einen Text Style fuer die angegebene TTF-Schriftart
;;; Style-Name: "SBZ_<FontName>" (z.B. "SBZ_Arial")
;;; Parameter: font-name - TTF-Schriftname (z.B. "Arial")
;;; Rueckgabe: Style-Name (String)
;;; ----------------------------------------------------------------------------
(defun SBZ:ensure-textstyle (font-name / style-name doc styles style-obj)
  (setq style-name (strcat "SBZ_" font-name))
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq styles (vla-get-textstyles doc))
  ;; Pruefen ob Style schon existiert
  (if (vl-catch-all-error-p
        (vl-catch-all-apply 'vla-item (list styles style-name)))
    ;; Nicht vorhanden → erstellen
    (progn
      (setq style-obj (vla-add styles style-name))
      ;; TTF-Dateiname setzen (AutoCAD sucht automatisch in Fonts-Ordner)
      (vl-catch-all-apply 'vla-put-fontFile
        (list style-obj (SBZ:font-to-ttf font-name)))
      (SBZ:log-write "INFO"
        (strcat "Text Style erstellt: '" style-name
                "' → " font-name ".ttf"))
    )
    (SBZ:log-write "DEBUG"
      (strcat "Text Style '" style-name "' existiert bereits"))
  )
  style-name
)

;;; ----------------------------------------------------------------------------
;;; SBZ:get-attr-tags
;;; Liest alle Attribut-Tag-Namen eines Block-Objekts
;;; Parameter: blk-ent - Entity-Name (ename) eines INSERT
;;; Rueckgabe: Liste von Tag-Strings oder nil
;;; ----------------------------------------------------------------------------
(defun SBZ:get-attr-tags (blk-ent / blk-ref attrs tags)
  (setq blk-ref (vlax-ename->vla-object blk-ent))
  (if (= (vla-get-HasAttributes blk-ref) :vlax-true)
    (progn
      (setq attrs (vlax-invoke blk-ref 'GetAttributes))
      (setq tags (mapcar '(lambda (a) (vla-get-TagString a)) attrs))
      tags
    )
    nil
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:get-attr-value
;;; Liest den TextString eines bestimmten Attribut-Tags
;;; Parameter:
;;;   blk-ent  - Entity-Name (ename) eines INSERT
;;;   tag-name - Attribut-Tag (String), Case-insensitive
;;; Rueckgabe: TextString oder nil wenn nicht gefunden
;;; ----------------------------------------------------------------------------
(defun SBZ:get-attr-value (blk-ent tag-name / blk-ref attrs result)
  (setq blk-ref (vlax-ename->vla-object blk-ent))
  (if (= (vla-get-HasAttributes blk-ref) :vlax-true)
    (progn
      (setq attrs (vlax-invoke blk-ref 'GetAttributes))
      (foreach attr attrs
        (if (= (strcase (vla-get-TagString attr)) (strcase tag-name))
          (setq result (vla-get-TextString attr))
        )
      )
    )
  )
  result
)


;;; ----------------------------------------------------------------------------
;;; SBZ:parse-height-string
;;; Konvertiert Hoehen-String in Real-Zahl
;;; Behandelt Komma als Dezimaltrenner und optionales + Vorzeichen
;;; Parameter: str - Hoehen-String (z.B. "322,45" oder "+322.45")
;;; Rueckgabe: Real-Zahl oder nil bei ungueltigem String
;;; ----------------------------------------------------------------------------
(defun SBZ:parse-height-string (str / cleaned)
  (if (and str (/= str ""))
    (progn
      ;; Komma durch Punkt ersetzen
      (setq cleaned (vl-string-subst "." "," str))
      ;; Fuehrendes + entfernen
      (if (= (substr cleaned 1 1) "+")
        (setq cleaned (substr cleaned 2))
      )
      ;; Leerzeichen entfernen
      (setq cleaned (vl-string-trim " " cleaned))
      ;; Parsen
      (if (/= cleaned "")
        (atof cleaned)
        nil
      )
    )
    nil
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:set-block-z
;;; Setzt die Z-Koordinate eines Blocks via vla-Move
;;; vla-Move verschiebt den INSERT INKLUSIVE aller Attribute!
;;; (entmod auf DXF 10 verschiebt nur den Einfuegepunkt, nicht die ATTRIBs)
;;; Parameter:
;;;   blk-ent - Entity-Name (ename) eines INSERT
;;;   new-z   - Neue Z-Koordinate (Real)
;;; Rueckgabe: T bei Erfolg, nil bei Fehler
;;; ----------------------------------------------------------------------------
(defun SBZ:set-block-z (blk-ent new-z / blk-ref ins-pt old-z delta result)
  (setq blk-ref (vlax-ename->vla-object blk-ent))
  (setq ins-pt (vlax-get blk-ref 'InsertionPoint))
  (if ins-pt
    (progn
      (setq old-z (caddr ins-pt))
      (setq delta (- new-z old-z))
      ;; Nur verschieben wenn tatsaechlich eine Aenderung
      (if (not (equal delta 0.0 1e-6))
        (progn
          (setq result
            (vl-catch-all-apply 'vla-Move
              (list blk-ref
                (vlax-3d-point 0.0 0.0 0.0)
                (vlax-3d-point 0.0 0.0 delta)
              )
            )
          )
          (if (vl-catch-all-error-p result)
            (progn
              (SBZ:log-write "ERROR"
                (strcat "vla-Move fehlgeschlagen: " (vl-catch-all-error-message result)))
              nil
            )
            T
          )
        )
        T ;; Kein Delta = bereits auf richtiger Hoehe
      )
    )
    nil
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:set-blockdef-byblock
;;; Setzt Farbe aller Entities in der Block-Definition auf ByBlock
;;; Wird nur EINMAL pro Blockname aufgerufen (nicht pro Instanz!)
;;; Parameter: blk-name - Blockname (String)
;;; ----------------------------------------------------------------------------
(defun SBZ:set-blockdef-byblock (blk-name / blocks blk-def)
  (setq blocks (vla-get-blocks (vla-get-activedocument (vlax-get-acad-object))))
  (if (not (vl-catch-all-error-p
        (setq blk-def (vl-catch-all-apply 'vla-item (list blocks blk-name)))))
    (progn
      (vlax-for obj blk-def
        (vl-catch-all-apply 'vla-put-Color (list obj acByBlock))
      )
      (SBZ:log-write "INFO" (strcat "Block-Definition '" blk-name "': Farbe auf ByBlock gesetzt"))
    )
    (SBZ:log-write "WARN" (strcat "Block-Definition '" blk-name "' nicht gefunden"))
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:process-blocks
;;; Kernfunktion: Verarbeitet alle Blockinstanzen
;;; Parameter:
;;;   blk-name  - Blockname (String)
;;;   attr-tag  - Attribut-Tag fuer Hoehe (String)
;;;   bau0      - Bau-0-Hoehe (Real)
;;;   z-mode    - "ABS" oder "REL" (Z-Koordinate fuer Kopie-Block)
;;; Rueckgabe: Anzahl verarbeiteter Bloecke (Integer)
;;; ----------------------------------------------------------------------------
(defun SBZ:process-blocks (blk-name attr-tag bau0 z-mode
                           / ss i ent val-str abs-h rel-z ins-z count-ok count-err
                             copy-mode copy-blk-name copy-def-ok target-layer)
  (setq count-ok 0)
  (setq count-err 0)
  ;; Kopie-Modus Variablen lokal cachen
  (setq copy-mode (= *SBZ:cfg-copymode* 1))
  (setq copy-blk-name *SBZ:cfg-copyblock*)
  (setq target-layer (if (and (= *SBZ:cfg-movelayer* 1)
                               (/= *SBZ:cfg-target-layer* ""))
                       *SBZ:cfg-target-layer* ""))
  ;; Alle Bloecke mit dem Namen im Modelspace suchen
  (setq ss (ssget "X" (list (cons 2 blk-name) (cons 410 "Model"))))
  (if (and ss (> (sslength ss) 0))
    (progn
      (SBZ:log-write "INFO"
        (strcat "Verarbeite " (itoa (sslength ss)) " Bloecke '"
                blk-name "' mit Attribut '" attr-tag
                "', Bau-0=" (rtos bau0 2 3)
                (if copy-mode (strcat ", Kopie-Modus → '" copy-blk-name "'") "")))
      ;; ByBlock auf Block-Definition setzen (einmal, nicht pro Instanz!)
      (if (and (= *SBZ:cfg-byblock* 1) (not copy-mode))
        (SBZ:set-blockdef-byblock blk-name)
      )
      ;; Im Kopie-Modus: Block-Definition sicherstellen
      (setq copy-def-ok T)
      (if copy-mode
        (if (not (SBZ:ensure-copyblock-def copy-blk-name))
          (progn
            (SBZ:log-write "ERROR"
              (strcat "Block-Definition '" copy-blk-name "' konnte nicht erstellt werden"))
            (setq copy-def-ok nil)
          )
        )
      )
      (if copy-def-ok
        (progn
          ;; Dekrementierende Schleife (Lee Mac Performance-Pattern)
          (setq i (sslength ss))
          (while (> (setq i (1- i)) -1)
            (setq ent (ssname ss i))
            ;; Attributwert lesen
            (setq val-str (SBZ:get-attr-value ent attr-tag))
            (if val-str
              (progn
                (setq abs-h (SBZ:parse-height-string val-str))
                (if abs-h
                  (progn
                    ;; Relative Hoehe berechnen (absolut minus Bau-0)
                    (setq rel-z (- abs-h bau0))
                    ;; Z-Koordinate fuer Kopie je nach Modus
                    (setq ins-z (if (= z-mode "ABS") abs-h rel-z))
                    (if copy-mode
                      ;; === KOPIE-MODUS: Original beibehalten, Kopie-Block einfuegen ===
                      (if (SBZ:insert-copyblock ent copy-blk-name abs-h rel-z ins-z bau0 z-mode)
                        (progn
                          (setq count-ok (1+ count-ok))
                          (SBZ:log-write "DEBUG"
                            (strcat "Block " (itoa (1+ i)) ": Kopie eingefuegt"
                                    " ABS=" (rtos abs-h 2 3)
                                    " REL=" (rtos rel-z 2 3)
                                    " Z=" (rtos ins-z 2 3) " (" z-mode ")"))
                        )
                        (progn
                          (setq count-err (1+ count-err))
                          (SBZ:log-write "ERROR"
                            (strcat "Block " (itoa (1+ i)) ": Kopie-Insert fehlgeschlagen"))
                        )
                      )
                      ;; === STANDARD-MODUS: Original verschieben ===
                      (if (SBZ:set-block-z ent ins-z)
                        (progn
                          (setq count-ok (1+ count-ok))
                          (SBZ:log-write "DEBUG"
                            (strcat "Block " (itoa (1+ i)) ": Attr='" val-str
                                    "' abs=" (rtos abs-h 2 3)
                                    " rel=" (rtos rel-z 2 3)
                                    " Z=" (rtos ins-z 2 3) " (" z-mode ") → verschoben"))
                          ;; Layer verschieben (nur Standard-Modus)
                          (if (/= target-layer "")
                            (vl-catch-all-apply 'vla-put-Layer
                              (list (vlax-ename->vla-object ent) target-layer))
                          )
                        )
                        (progn
                          (setq count-err (1+ count-err))
                          (SBZ:log-write "ERROR"
                            (strcat "Block " (itoa (1+ i)) ": vla-Move fehlgeschlagen"))
                        )
                      )
                    )
                  )
                  (progn
                    (setq count-err (1+ count-err))
                    (SBZ:log-write "WARN"
                      (strcat "Block " (itoa (1+ i))
                              ": Attribut '" val-str "' ist keine gueltige Zahl"))
                  )
                )
              )
              (progn
                (setq count-err (1+ count-err))
                (SBZ:log-write "WARN"
                  (strcat "Block " (itoa (1+ i)) ": Attribut '" attr-tag "' nicht gefunden"))
              )
            )
          ) ;end while
        )
      ) ;end copy-def-ok
      ;; Zusammenfassung
      (SBZ:log-write "INFO"
        (strcat "Fertig: " (itoa count-ok) " OK, " (itoa count-err) " Fehler"))
      (if (> count-err 0)
        (SBZ:log-write "WARN"
          (strcat count-err " Bloecke konnten nicht verarbeitet werden (siehe Log)"))
      )
      count-ok
    )
    (progn
      (SBZ:log-write "WARN" (strcat "Keine Bloecke '" blk-name "' im Modelspace gefunden"))
      0
    )
  )
)


;;; ============================================================================
;;; KOPIE-BLOCK: DEFINITION ERSTELLEN + EINFUEGEN
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; SBZ:make-filled-quarter
;;; Erstellt gefuellte Viertelkreis-Segmente als SOLID-Faecher innerhalb
;;; einer laufenden Block-Definition (zwischen BLOCK und ENDBLK).
;;; Verwendet Pizza-Slice SOLIDs vom Mittelpunkt zum Kreisrand.
;;; Parameter:
;;;   blk-name   - Blockname (nur fuer Logging)
;;;   radius     - Kreisradius (Real)
;;;   ang-start  - Startwinkel in Radians
;;;   ang-end    - Endwinkel in Radians
;;;   segments   - Anzahl Segmente (8 = gute Approximation)
;;; ----------------------------------------------------------------------------
(defun SBZ:make-filled-quarter (blk-name radius ang-start ang-end segments
                                / i ang-step a1 a2 p1 p2)
  (setq ang-step (/ (- ang-end ang-start) (float segments)))
  (setq i 0)
  (repeat segments
    (setq a1 (+ ang-start (* i ang-step)))
    (setq a2 (+ ang-start (* (1+ i) ang-step)))
    (setq p1 (list (* radius (cos a1)) (* radius (sin a1)) 0.0))
    (setq p2 (list (* radius (cos a2)) (* radius (sin a2)) 0.0))
    ;; SOLID: Dreieck vom Mittelpunkt zu zwei Kreisrand-Punkten
    ;; DXF 10=Ecke1, 11=Ecke2, 12=Ecke3, 13=Ecke4 (=Ecke3 fuer Dreieck)
    (entmake (list '(0 . "SOLID") '(8 . "0")
                   '(62 . 0) '(6 . "ByBlock") '(370 . -2)
                   '(10 0.0 0.0 0.0)     ;; Mittelpunkt
                   (cons 11 p1)           ;; Kreisrand 1
                   (cons 12 p2)           ;; Kreisrand 2
                   (cons 13 p2)           ;; = Ecke3 (Dreieck)
             ))
    (setq i (1+ i))
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:ensure-copyblock-def
;;; Erstellt die Block-Definition fuer den Kopie-Block falls nicht vorhanden.
;;; Block enthaelt: Punkt-Marker + 2 Attribute (HOEHE_ABS, HOEHE_REL)
;;; Parameter: blk-name - Blockname (String)
;;; Rueckgabe: T wenn vorhanden/erstellt, nil bei Fehler
;;; ----------------------------------------------------------------------------
(defun SBZ:ensure-copyblock-def (blk-name / blocks blk-exists style-name)
  (setq blocks (vla-get-blocks (vla-get-activedocument (vlax-get-acad-object))))
  ;; Text Style fuer Schriftart sicherstellen
  (setq style-name (SBZ:ensure-textstyle (SBZ:get-font)))
  ;; Pruefen ob Block schon existiert
  (setq blk-exists
    (not (vl-catch-all-error-p
      (vl-catch-all-apply 'vla-item (list blocks blk-name)))))
  (if blk-exists
    (progn
      (SBZ:log-write "DEBUG" (strcat "Block-Definition '" blk-name "' existiert bereits"))
      T
    )
    ;; Block-Definition erstellen via entmake
    (progn
      (SBZ:log-write "INFO" (strcat "Erstelle Block-Definition '" blk-name "'"))
      ;; BLOCK-Header
      (if (entmake (list '(0 . "BLOCK")
                         (cons 2 blk-name)
                         '(10 0.0 0.0 0.0)
                         '(70 . 2)))    ;; Bit 2 = hat Attribute
        (progn
          ;; === Vermessungspunkt: Schachbrett mit Fadenkreuz ===
          ;; Radius 0.05m (Durchmesser 0.1m), Einfuegepunkt = Mitte
          ;; ByBlock Properties fuer alle Entities
          ;; DXF 62=0, DXF 6="ByBlock", DXF 370=-2

          ;; --- Gefuellte Viertelkreise (Schachbrett) ---
          ;; Oben-links (Q2) und unten-rechts (Q4) gefuellt
          ;; Approximiert mit SOLID-Faechern (8 Segmente pro Viertel)
          (SBZ:make-filled-quarter blk-name 0.05  (/ pi 2) pi       8) ;; Q2: oben-links
          (SBZ:make-filled-quarter blk-name 0.05  (* pi 1.5) (* pi 2) 8) ;; Q4: unten-rechts

          ;; --- Kreisumriss ---
          (entmake (list '(0 . "CIRCLE") '(8 . "0")
                        '(62 . 0) '(6 . "ByBlock") '(370 . -2)
                        '(10 0.0 0.0 0.0) '(40 . 0.05)))

          ;; --- Fadenkreuz (ragt ueber Kreis hinaus) ---
          (entmake (list '(0 . "LINE") '(8 . "0")
                        '(62 . 0) '(6 . "ByBlock") '(370 . -2)
                        '(10 -0.08 0.0 0.0) '(11 0.08 0.0 0.0)))
          (entmake (list '(0 . "LINE") '(8 . "0")
                        '(62 . 0) '(6 . "ByBlock") '(370 . -2)
                        '(10 0.0 -0.08 0.0) '(11 0.0 0.08 0.0)))

          ;; --- Trennlinien (horizontale und vertikale Achse im Kreis) ---
          ;; Nicht noetig — Fadenkreuz + Kreis reichen als Trennung

          ;; ATTDEF: HOEHE_ABS (absolut) — sichtbar, rechts vom Marker
          ;; Justierung: Links Unten (72=0, 74=1) → Text waechst nach oben
          ;; DXF 10 = Startpunkt, DXF 11 = Ausrichtungspunkt (bei Justierung)
          ;; Position: rechts vom Kreis, leicht ueber Mittellinie
          (entmake (list '(0 . "ATTDEF")
                        '(8 . "0")
                        '(62 . 0) '(6 . "ByBlock") '(370 . -2)
                        (cons 7 style-name)    ;; Text Style (Schriftart)
                        '(10 0.1 0.02 0.0)    ;; Startpunkt (Y = halbe Texthoehe ueber Mitte)
                        '(11 0.1 0.02 0.0)    ;; Ausrichtungspunkt
                        '(40 . 0.07)          ;; Texthoehe (wird beim Insert skaliert)
                        '(1 . "0.000")
                        '(2 . "HOEHE_ABS")
                        '(3 . "Absolute Hoehe")
                        '(70 . 0)             ;; Flags: sichtbar
                        '(72 . 0)             ;; Horizontale Justierung: Links
                        '(74 . 1)             ;; Vertikale Justierung: Unten
                  ))
          ;; ATTDEF: HOEHE_REL (relativ) — sichtbar, rechts vom Marker
          ;; Justierung: Links Oben (72=0, 74=3) → Text waechst nach unten
          ;; Position: rechts vom Kreis, leicht unter Mittellinie
          (entmake (list '(0 . "ATTDEF")
                        '(8 . "0")
                        '(62 . 0) '(6 . "ByBlock") '(370 . -2)
                        (cons 7 style-name)
                        '(10 0.1 -0.02 0.0)
                        '(11 0.1 -0.02 0.0)
                        '(40 . 0.07)
                        '(1 . "0.000")
                        '(2 . "HOEHE_REL")
                        '(3 . "Relative Hoehe (nach Bau-0)")
                        '(70 . 0)
                        '(72 . 0)             ;; Links
                        '(74 . 3)             ;; Oben
                  ))
          ;; ATTDEF: HOEHE_BAU0 (Bau-0-Hoehe) — unsichtbar, unter HOEHE_REL
          ;; Justierung: Links Oben (72=0, 74=3)
          ;; Position: REL.Y - 1.7*Texthoehe = -0.02 - 0.119 ≈ -0.14
          ;; ABS=+0.02, REL=-0.02, BAU0=-0.14
          (entmake (list '(0 . "ATTDEF")
                        '(8 . "0")
                        '(62 . 0) '(6 . "ByBlock") '(370 . -2)
                        (cons 7 style-name)
                        '(10 0.1 -0.14 0.0)
                        '(11 0.1 -0.14 0.0)
                        '(40 . 0.07)
                        '(1 . "0.000")
                        '(2 . "HOEHE_BAU0")
                        '(3 . "Bau-0-Hoehe")
                        '(70 . 0)             ;; Flags: sichtbar (Layer steuert Sichtbarkeit)
                        '(72 . 0)             ;; Links
                        '(74 . 3)             ;; Oben
                  ))
          ;; ENDBLK
          (if (entmake '((0 . "ENDBLK")))
            (progn
              (SBZ:log-write "INFO" (strcat "Block-Definition '" blk-name "' erstellt"))
              T
            )
            (progn
              (SBZ:log-write "ERROR" (strcat "ENDBLK fehlgeschlagen fuer '" blk-name "'"))
              nil
            )
          )
        )
        (progn
          (SBZ:log-write "ERROR" (strcat "BLOCK-Header fehlgeschlagen fuer '" blk-name "'"))
          nil
        )
      )
    )
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:ensure-layer
;;; Erstellt Layer falls nicht vorhanden
;;; Parameter: layer-name - Layername (String)
;;; ----------------------------------------------------------------------------
(defun SBZ:ensure-layer (layer-name / doc layers)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq layers (vla-get-layers doc))
  (if (vl-catch-all-error-p
        (vl-catch-all-apply 'vla-item (list layers layer-name)))
    (progn
      (vla-add layers layer-name)
      (SBZ:log-write "INFO" (strcat "Layer erstellt: '" layer-name "'"))
    )
  )
  layer-name
)


;;; ----------------------------------------------------------------------------
;;; SBZ:ensure-layer-with-freeze
;;; Erstellt Layer falls nicht vorhanden und setzt Freeze-Status
;;; Parameter:
;;;   layer-name - Layername (String)
;;;   freeze     - 0 = thawed (sichtbar), 1 = frozen (unsichtbar)
;;; ----------------------------------------------------------------------------
(defun SBZ:ensure-layer-with-freeze (layer-name freeze / doc layers lay-obj)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq layers (vla-get-layers doc))
  ;; Layer erstellen falls nicht vorhanden
  (if (vl-catch-all-error-p
        (setq lay-obj (vl-catch-all-apply 'vla-item (list layers layer-name))))
    (progn
      (setq lay-obj (vla-add layers layer-name))
      (SBZ:log-write "INFO" (strcat "Layer erstellt: '" layer-name "'"))
    )
  )
  ;; Freeze/Thaw setzen (aktuellen Layer kann man nicht einfrieren)
  (if (and lay-obj (/= (strcase layer-name) (strcase (getvar "CLAYER"))))
    (vl-catch-all-apply 'vla-put-Freeze
      (list lay-obj (if (= freeze 1) :vlax-true :vlax-false)))
  )
  layer-name
)


;;; ----------------------------------------------------------------------------
;;; SBZ:ensure-attr-layers
;;; Erstellt die 3 Attribut-Sub-Layer fuer einen Block-Layer
;;; Layer-Schema: <base>-AttABS, <base>-AttREL, <base>-AttBAU0
;;; Setzt Initial-Freeze je nach Config-Toggles
;;; Parameter: base-layer - Basis-Layername (z.B. "GOK_abs")
;;; ----------------------------------------------------------------------------
(defun SBZ:ensure-attr-layers (base-layer / )
  ;; Basis-Layer (fuer Block-Symbol)
  (SBZ:ensure-layer base-layer)
  ;; Attribut-Sub-Layer mit Freeze-Status
  (SBZ:ensure-layer-with-freeze
    (strcat base-layer "-AttABS") *SBZ:cfg-freeze-abs*)
  (SBZ:ensure-layer-with-freeze
    (strcat base-layer "-AttREL") *SBZ:cfg-freeze-rel*)
  (SBZ:ensure-layer-with-freeze
    (strcat base-layer "-AttBAU0") *SBZ:cfg-freeze-bau0*)
  (SBZ:log-write "INFO"
    (strcat "Attribut-Layer erstellt: " base-layer
            "-AttABS(" (if (= *SBZ:cfg-freeze-abs* 1) "frozen" "thawed") ")"
            " -AttREL(" (if (= *SBZ:cfg-freeze-rel* 1) "frozen" "thawed") ")"
            " -AttBAU0(" (if (= *SBZ:cfg-freeze-bau0* 1) "frozen" "thawed") ")"))
)


;;; ----------------------------------------------------------------------------
;;; SBZ:get-copy-layername
;;; Berechnet den Layer-Namen mit Suffix je nach Z-Modus
;;; Parameter:
;;;   z-mode - "ABS" oder "REL"
;;;   bau0   - Bau-0-Hoehe (Real)
;;; Rueckgabe: Layer-Name (z.B. "GOK_abs", "GOK_rel", "GOK")
;;; ----------------------------------------------------------------------------
(defun SBZ:get-copy-layername (z-mode bau0 / base)
  (setq base *SBZ:cfg-copylayer*)
  (cond
    ((equal bau0 0.0 0.001) base)                ;; Bau-0=0 → kein Suffix
    ((= z-mode "ABS") (strcat base "_abs"))       ;; Absolut
    ((= z-mode "REL") (strcat base "_rel"))       ;; Relativ
    (T base)
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:insert-copyblock
;;; Fuegt den Kopie-Block an der Position des Original-Blocks ein
;;; Parameter:
;;;   orig-ent  - Entity-Name des Original-Blocks (ename)
;;;   blk-name  - Name des Kopie-Blocks (String)
;;;   abs-h     - Absolute Hoehe (Real, fuer Attribut-Text)
;;;   rel-z     - Relative Hoehe nach Bau-0 (Real, fuer Attribut-Text)
;;;   ins-z     - Z-Koordinate fuer Block-Insert (Real, ABS oder REL je nach Modus)
;;;   bau0      - Bau-0-Hoehe (Real, fuer HOEHE_BAU0 Attribut)
;;;   z-mode    - "ABS" oder "REL" (fuer Layer-Suffix)
;;; Rueckgabe: T bei Erfolg, nil bei Fehler
;;; ----------------------------------------------------------------------------
(defun SBZ:insert-copyblock (orig-ent blk-name abs-h rel-z ins-z bau0 z-mode
                             / orig-data orig-pt ins-pt new-ent attrs
                               scale suffix copy-layer style-name
                               abs-str rel-str bau0-str tag-str
                               att-ent att-data)
  ;; XY vom Original, Z = je nach Modus (ABS oder REL)
  (setq orig-data (entget orig-ent))
  (setq orig-pt (cdr (assoc 10 orig-data)))
  (setq ins-pt (list (car orig-pt) (cadr orig-pt) ins-z))
  ;; Einstellungen lesen
  (setq scale (SBZ:get-scale))
  (setq suffix (SBZ:get-suffix))
  ;; Text Style sicherstellen
  (setq style-name (SBZ:ensure-textstyle (SBZ:get-font)))
  ;; Layer + Attribut-Sub-Layer erstellen
  (setq copy-layer (SBZ:get-copy-layername z-mode bau0))
  (SBZ:ensure-attr-layers copy-layer)
  ;; Block einfuegen
  (setq new-ent
    (vl-catch-all-apply
      '(lambda ()
        (vla-InsertBlock
          (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object)))
          (vlax-3d-point ins-pt)
          blk-name
          scale scale scale
          0.0
        )
      )
    )
  )
  (if (vl-catch-all-error-p new-ent)
    (progn
      (SBZ:log-write "ERROR"
        (strcat "Kopie-Block Insert fehlgeschlagen: " (vl-catch-all-error-message new-ent)))
      nil
    )
    (progn
      ;; Absolut-Hoehe: Wert + Suffix
      (setq abs-str (strcat (SBZ:rtos-fixed abs-h 2)
                            (if (and suffix (/= suffix ""))
                              (strcat " " suffix) "")))
      ;; Relativ-Hoehe: Vorzeichen + Wert
      (cond
        ((> rel-z 0.001)  (setq rel-str (strcat "+" (SBZ:rtos-fixed rel-z 2))))
        ((< rel-z -0.001) (setq rel-str (SBZ:rtos-fixed rel-z 2)))
        (T                (setq rel-str (strcat "%%P" (SBZ:rtos-fixed (abs rel-z) 2))))
      )
      ;; Bau-0 Zeile: "±0.00 = <Bau-0-Hoehe> <Suffix>"
      ;; Zeigt die Bau-0-Hoehe als fixe Info (gleich fuer ALLE Bloecke!)
      ;; ±0.00 ist symbolisch (= Nulllinie), dahinter der eingegebene Bau-0-Wert
      (setq bau0-str (strcat "%%P0.00 = " (SBZ:rtos-fixed bau0 2)
                             (if (and suffix (/= suffix ""))
                               (strcat " " suffix) "")))
      ;; Attribute: Text setzen + Layer per entmod (DXF 8)
      ;; Positionen bleiben aus Block-Definition (Skalierung regelt Groesse)
      ;; Sichtbarkeit ueber Layer Freeze/Thaw, nicht Invisible-Flag
      (setq attrs (vlax-invoke new-ent 'GetAttributes))
      (foreach attr attrs
        (setq tag-str (strcase (vla-get-TagString attr)))
        (setq att-ent (vlax-vla-object->ename attr))
        (setq att-data (entget att-ent))
        (cond
          ((= tag-str "HOEHE_ABS")
            (setq att-data (subst (cons 1 abs-str) (assoc 1 att-data) att-data))
            (setq att-data (subst (cons 70 0) (assoc 70 att-data) att-data))
            (setq att-data (subst (cons 7 style-name) (assoc 7 att-data) att-data))
            (setq att-data (subst (cons 8 (strcat copy-layer "-AttABS"))
                                  (assoc 8 att-data) att-data))
            ;; Farbe: 0=ByBlock (Default), sonst ACI-Code
            (if (/= *SBZ:cfg-color-abs* 0)
              (setq att-data (subst (cons 62 *SBZ:cfg-color-abs*) (assoc 62 att-data) att-data)))
            (entmod att-data) (entupd att-ent)
          )
          ((= tag-str "HOEHE_REL")
            (setq att-data (subst (cons 1 rel-str) (assoc 1 att-data) att-data))
            (setq att-data (subst (cons 70 0) (assoc 70 att-data) att-data))
            (setq att-data (subst (cons 7 style-name) (assoc 7 att-data) att-data))
            (setq att-data (subst (cons 8 (strcat copy-layer "-AttREL"))
                                  (assoc 8 att-data) att-data))
            (if (/= *SBZ:cfg-color-rel* 0)
              (setq att-data (subst (cons 62 *SBZ:cfg-color-rel*) (assoc 62 att-data) att-data)))
            (entmod att-data) (entupd att-ent)
          )
          ((= tag-str "HOEHE_BAU0")
            (setq att-data (subst (cons 1 bau0-str) (assoc 1 att-data) att-data))
            (setq att-data (subst (cons 70 0) (assoc 70 att-data) att-data))
            (setq att-data (subst (cons 7 style-name) (assoc 7 att-data) att-data))
            (setq att-data (subst (cons 8 (strcat copy-layer "-AttBAU0"))
                                  (assoc 8 att-data) att-data))
            (if (/= *SBZ:cfg-color-bau0* 0)
              (setq att-data (subst (cons 62 *SBZ:cfg-color-bau0*) (assoc 62 att-data) att-data)))
            (entmod att-data) (entupd att-ent)
          )
        )
      )
      ;; Block-Symbol auf Kopie-Layer
      (vl-catch-all-apply 'vla-put-Layer (list new-ent copy-layer))
      ;; Block-Farbe setzen (ACI-Code)
      (vl-catch-all-apply 'vla-put-Color (list new-ent *SBZ:cfg-color-block*))
      (SBZ:log-write "DEBUG"
        (strcat "Kopie-Block: ABS='" abs-str "' REL='" rel-str
                "' Layer='" copy-layer "'"))
      T
    )
  )
)


;;; ----------------------------------------------------------------------------
;;; SBZ:update-existing-blocks
;;; Aktualisiert alle bestehenden Kopie-Bloecke mit den aktuellen Settings:
;;; Schriftart (DXF 7), Farbe (DXF 62), Layer (DXF 8), Block-Farbe
;;; Aendert NICHT die Hoehenwerte — nur visuelle Einstellungen.
;;; Rueckgabe: Anzahl aktualisierter Bloecke
;;; ----------------------------------------------------------------------------
(defun SBZ:update-existing-blocks ( / blk-name style-name ss i ent
                                      blk-ref attrs att-ent att-data tag-str
                                      copy-layer count)
  (setq blk-name *SBZ:cfg-copyblock*)
  (setq style-name (SBZ:ensure-textstyle (SBZ:get-font)))
  (setq count 0)
  ;; Alle Kopie-Bloecke im Modelspace suchen
  (setq ss (ssget "X" (list (cons 2 blk-name) (cons 410 "Model"))))
  (if (and ss (> (sslength ss) 0))
    (progn
      (SBZ:log-write "INFO"
        (strcat "Update: " (itoa (sslength ss)) " '" blk-name "' Bloecke gefunden"))
      ;; Dekrementierende Schleife
      (setq i (sslength ss))
      (while (> (setq i (1- i)) -1)
        (setq ent (ssname ss i))
        (setq blk-ref (vlax-ename->vla-object ent))
        ;; Block-Farbe setzen
        (vl-catch-all-apply 'vla-put-Color (list blk-ref *SBZ:cfg-color-block*))
        ;; Attribute durchlaufen
        (setq attrs (vlax-invoke blk-ref 'GetAttributes))
        (foreach attr attrs
          (setq tag-str (strcase (vla-get-TagString attr)))
          (setq att-ent (vlax-vla-object->ename attr))
          (setq att-data (entget att-ent))
          ;; Layer-Name vom aktuellen Attribut-Layer ableiten
          ;; Bestehender Layer = aktueller DXF 8 Wert → Basis extrahieren
          (setq copy-layer (cdr (assoc 8 (entget ent))))
          (cond
            ((= tag-str "HOEHE_ABS")
              ;; Schriftart
              (if (assoc 7 att-data)
                (setq att-data (subst (cons 7 style-name) (assoc 7 att-data) att-data))
                (setq att-data (append att-data (list (cons 7 style-name))))
              )
              ;; Farbe
              (if (/= *SBZ:cfg-color-abs* 0)
                (if (assoc 62 att-data)
                  (setq att-data (subst (cons 62 *SBZ:cfg-color-abs*) (assoc 62 att-data) att-data))
                  (setq att-data (append att-data (list (cons 62 *SBZ:cfg-color-abs*))))
                )
                ;; Von Block: Farbe auf 0 (ByBlock)
                (if (assoc 62 att-data)
                  (setq att-data (subst (cons 62 0) (assoc 62 att-data) att-data))
                )
              )
              ;; Layer
              (setq att-data (subst (cons 8 (strcat copy-layer "-AttABS"))
                                    (assoc 8 att-data) att-data))
              (entmod att-data) (entupd att-ent)
            )
            ((= tag-str "HOEHE_REL")
              (if (assoc 7 att-data)
                (setq att-data (subst (cons 7 style-name) (assoc 7 att-data) att-data))
                (setq att-data (append att-data (list (cons 7 style-name))))
              )
              (if (/= *SBZ:cfg-color-rel* 0)
                (if (assoc 62 att-data)
                  (setq att-data (subst (cons 62 *SBZ:cfg-color-rel*) (assoc 62 att-data) att-data))
                  (setq att-data (append att-data (list (cons 62 *SBZ:cfg-color-rel*))))
                )
                (if (assoc 62 att-data)
                  (setq att-data (subst (cons 62 0) (assoc 62 att-data) att-data))
                )
              )
              (setq att-data (subst (cons 8 (strcat copy-layer "-AttREL"))
                                    (assoc 8 att-data) att-data))
              (entmod att-data) (entupd att-ent)
            )
            ((= tag-str "HOEHE_BAU0")
              (if (assoc 7 att-data)
                (setq att-data (subst (cons 7 style-name) (assoc 7 att-data) att-data))
                (setq att-data (append att-data (list (cons 7 style-name))))
              )
              (if (/= *SBZ:cfg-color-bau0* 0)
                (if (assoc 62 att-data)
                  (setq att-data (subst (cons 62 *SBZ:cfg-color-bau0*) (assoc 62 att-data) att-data))
                  (setq att-data (append att-data (list (cons 62 *SBZ:cfg-color-bau0*))))
                )
                (if (assoc 62 att-data)
                  (setq att-data (subst (cons 62 0) (assoc 62 att-data) att-data))
                )
              )
              (setq att-data (subst (cons 8 (strcat copy-layer "-AttBAU0"))
                                    (assoc 8 att-data) att-data))
              (entmod att-data) (entupd att-ent)
            )
          )
        )
        (setq count (1+ count))
      )
      (SBZ:log-write "INFO" (strcat "Update: " (itoa count) " Bloecke aktualisiert"))
    )
    (SBZ:log-write "INFO" (strcat "Update: Keine '" blk-name "' Bloecke gefunden"))
  )
  count
)


;;; ============================================================================
;;; BEFEHLE
;;; ============================================================================

;;; ----------------------------------------------------------------------------
;;; c:SETBLOCKZ - Hauptbefehl
;;; Workflow:
;;;   1. Block anklicken → Blockname + Attribute ermitteln
;;;   2. Attribut fuer Hoehe waehlen (Filter-Listbox)
;;;   3. Bau-0-Hoehe: aus Custom Property oder User-Eingabe
;;;   4. Alle Instanzen verarbeiten (Z setzen)
;;;   5. Optional: ByBlock, Layer verschieben
;;; ----------------------------------------------------------------------------
(defun c:SETBLOCKZ ( / *error* old-cmdecho
                       sel blk-ent blk-name attr-tags selected-attr
                       bau0 bau0-input ss-preview num-found confirm z-mode count)
  (SBZ:ensure-init)
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (SBZ:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (SBZ:log-write "ERROR" (strcat "SETBLOCKZ Error-Handler: " msg))
      )
      (SBZ:log-write "INFO" "SETBLOCKZ: Abbruch durch User")
    )
    ;; Markierung aufheben falls aktiv
    (sssetfirst nil nil)
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  (SBZ:log-write "INFO" "Befehl SETBLOCKZ gestartet")

  ;; --- Schritt 1: Block auswaehlen ---
  (setq sel (entsel "\nBlock waehlen (Referenz fuer Blockname + Attribute): "))
  (if (not sel)
    (progn
      (princ "\nKein Objekt gewaehlt.")
      (SBZ:log-write "INFO" "Kein Objekt gewaehlt, Abbruch")
      (setvar "CMDECHO" old-cmdecho)
      (princ)
    )
    (progn
      (setq blk-ent (car sel))
      ;; Pruefen ob INSERT (Block)
      (if (/= (cdr (assoc 0 (entget blk-ent))) "INSERT")
        (progn
          (princ "\nGewaeltes Objekt ist kein Block.")
          (SBZ:log-write "WARN" "Gewaehltes Objekt ist kein Block")
          (setvar "CMDECHO" old-cmdecho)
          (princ)
        )
        (progn
          ;; Blockname ermitteln (EffectiveName fuer dynamische Bloecke)
          (setq blk-name (cdr (assoc 2 (entget blk-ent))))
          (SBZ:log-write "INFO" (strcat "Block gewaehlt: '" blk-name "'"))

          ;; --- Schritt 2: Attribut-Tags lesen ---
          (setq attr-tags (SBZ:get-attr-tags blk-ent))
          (if (not attr-tags)
            (progn
              (princ (strcat "\nBlock '" blk-name "' hat keine Attribute."))
              (SBZ:log-write "WARN" (strcat "Block '" blk-name "' hat keine Attribute"))
              (setvar "CMDECHO" old-cmdecho)
              (princ)
            )
            (progn
              (SBZ:log-write "INFO"
                (strcat "Attribute gefunden: " (vl-princ-to-string attr-tags)))

              ;; --- Schritt 3: Attribut waehlen (Filter-Listbox) ---
              (setq selected-attr (car (SBZ:filtlistbox "Attribut fuer Hoehenwert waehlen" attr-tags nil)))
              (if (not selected-attr)
                (progn
                  (princ "\nKein Attribut gewaehlt.")
                  (SBZ:log-write "INFO" "Kein Attribut gewaehlt, Abbruch")
                  (setvar "CMDECHO" old-cmdecho)
                  (princ)
                )
                (progn
                  (SBZ:log-write "INFO" (strcat "Attribut gewaehlt: '" selected-attr "'"))

                  ;; --- Schritt 4: Bau-0-Hoehe ---
                  ;; Zuerst aus Custom Property lesen
                  (setq bau0 (SBZ:get-bau0))
                  (if bau0
                    ;; Custom Property vorhanden → anzeigen, aenderbar
                    (progn
                      (princ (strcat "\nBau-0-Hoehe aus Zeichnung: " (rtos bau0 2 3)))
                      (SBZ:log-write "INFO" (strcat "Bau-0 aus DWG: " (rtos bau0 2 3)))
                      (initget "Aendern")
                      (setq bau0-input
                        (getreal (strcat "\nBau-0-Hoehe [" (rtos bau0 2 3)
                                         "] <Enter = beibehalten> [Aendern]: ")))
                      (cond
                        ((= bau0-input "Aendern")
                          (setq bau0 (getreal "\nNeue Bau-0-Hoehe eingeben: "))
                          (if bau0
                            (progn
                              (SBZ:set-bau0 bau0)
                              (SBZ:log-write "INFO" (strcat "Bau-0 geaendert auf: " (rtos bau0 2 3)))
                            )
                            (progn
                              (princ "\nUngueltige Eingabe, Abbruch.")
                              (setvar "CMDECHO" old-cmdecho)
                              (princ)
                            )
                          )
                        )
                        ((numberp bau0-input)
                          ;; User hat direkt neue Zahl eingegeben
                          (setq bau0 bau0-input)
                          (SBZ:set-bau0 bau0)
                          (SBZ:log-write "INFO" (strcat "Bau-0 geaendert auf: " (rtos bau0 2 3)))
                        )
                        ;; nil = Enter = beibehalten
                      )
                    )
                    ;; Keine Custom Property → User muss eingeben
                    (progn
                      (princ "\nKeine Bau-0-Hoehe in Zeichnung gespeichert.")
                      (setq bau0 (getreal "\nBau-0-Hoehe eingeben (0 = absolute Hoehen): "))
                      (if (not bau0) (setq bau0 0.0))
                      (SBZ:set-bau0 bau0)
                      (SBZ:log-write "INFO" (strcat "Bau-0 neu gesetzt: " (rtos bau0 2 3)))
                    )
                  )

                  ;; --- Schritt 5: Vorschau + Bestaetigung ---
                  (if bau0
                    (progn
                      ;; Alle Bloecke mit dem Namen im Modelspace suchen
                      (setq ss-preview (ssget "X" (list (cons 2 blk-name) (cons 410 "Model"))))
                      (if (and ss-preview (> (sslength ss-preview) 0))
                        (progn
                          (setq num-found (sslength ss-preview))
                          ;; Bloecke visuell markieren (blaue Griffe)
                          (sssetfirst nil ss-preview)
                          (SBZ:log-write "INFO"
                            (strcat (itoa num-found) " Bloecke '" blk-name "' gefunden, Vorschau angezeigt"))

                          ;; User bestaetigen lassen
                          (initget "Ja Nein")
                          (setq confirm
                            (getkword
                              (strcat "\n" (itoa num-found) " Bloecke '" blk-name
                                      "' gefunden (markiert). Fortfahren? [Ja/Nein] <Ja>: ")))
                          ;; nil (Enter) = Ja (Default)
                          (if (or (not confirm) (= confirm "Ja"))
                            (progn
                              ;; Markierung aufheben
                              (sssetfirst nil nil)

                              ;; Z-Koordinate waehlen: Absolut oder Relativ
                              ;; Bei Bau-0=0 sind beide gleich → automatisch ABS
                              (if (equal bau0 0.0 0.001)
                                (progn
                                  (setq z-mode "ABS")
                                  (SBZ:log-write "INFO" "Z-Modus: ABS (Bau-0=0, kein Unterschied)")
                                )
                                (progn
                                  (initget "Absolut Relativ")
                                  (setq z-mode
                                    (getkword "\nZ-Koordinate? [Absolut/Relativ] <Relativ>: "))
                                  (if (not z-mode) (setq z-mode "Relativ"))
                                  (setq z-mode (if (= z-mode "Absolut") "ABS" "REL"))
                                  (SBZ:log-write "INFO" (strcat "Z-Modus: " z-mode))
                                )
                              )

                              ;; Blockname + Attribut in DWG Custom Properties merken
                              (SBZ:set-last-blockname blk-name)
                              (SBZ:set-last-attrtag selected-attr)
                              ;; Toggles speichern (AppData)
                              (SBZ:save-config)

                              ;; --- Schritt 6: Verarbeitung ---
                              (setq count (SBZ:process-blocks blk-name selected-attr bau0 z-mode))
                              (princ (strcat "\n" (itoa count) " Bloecke verarbeitet."))
                              (if (and (= *SBZ:cfg-movelayer* 1)
                                       (/= *SBZ:cfg-target-layer* ""))
                                (princ (strcat "\nBloecke auf Layer '" *SBZ:cfg-target-layer* "' verschoben."))
                              )
                              (if (= *SBZ:cfg-byblock* 1)
                                (princ "\nBlock-Definition: Farbe auf ByBlock gesetzt.")
                              )
                            )
                            ;; Nein → Abbruch
                            (progn
                              (sssetfirst nil nil)
                              (princ "\nAbgebrochen.")
                              (SBZ:log-write "INFO" "User hat Verarbeitung abgelehnt")
                            )
                          )
                        )
                        ;; Keine Bloecke gefunden
                        (progn
                          (princ (strcat "\nKeine Bloecke '" blk-name "' im Modelspace gefunden."))
                          (SBZ:log-write "WARN" (strcat "Keine Bloecke '" blk-name "' im Modelspace"))
                        )
                      )
                    )
                  )
                ) ;end selected-attr progn
              ) ;end selected-attr if
            ) ;end attr-tags progn
          ) ;end attr-tags if
        ) ;end INSERT progn
      ) ;end INSERT if
    ) ;end sel progn
  ) ;end sel if

  ;; Cleanup
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (SBZ:log-write "INFO" "Befehl SETBLOCKZ beendet")
  (princ)
)


;;; ----------------------------------------------------------------------------
;;; c:SBZSETTINGS - Einstellungen-Dialog
;;; DCL mit: Bau-0, ByBlock Toggle, Layer Toggle + Auswahl,
;;;          letzte Verarbeitung anzeigen, Neu berechnen Button
;;; ----------------------------------------------------------------------------

;;; --- Gaengige TTF-Schriftarten (kuratierte Liste) ---
;;; Rueckgabe: Liste von Font-Namen (ohne .ttf Extension)
(defun SBZ:get-font-list ( / )
  (list
    "Arial"
    "Arial Bold"
    "Arial Italic"
    "Arial Bold Italic"
    "Calibri"
    "Calibri Bold"
    "Calibri Light"
    "Cambria"
    "Consolas"
    "Courier New"
    "Courier New Bold"
    "Georgia"
    "Impact"
    "Microsoft Sans Serif"
    "Palatino Linotype"
    "Segoe UI"
    "Segoe UI Bold"
    "Tahoma"
    "Tahoma Bold"
    "Times New Roman"
    "Times New Roman Bold"
    "Trebuchet MS"
    "Trebuchet MS Bold"
    "Verdana"
    "Verdana Bold"
  )
)


;;; --- ACI-Farbliste fuer Block (ohne "Von Block") ---
;;; Rueckgabe: Assoziationsliste ((label . aci-code) ...)
(defun SBZ:get-block-color-list ( / )
  (list
    '("1 - Rot" . 1)
    '("2 - Gelb" . 2)
    '("3 - Gruen" . 3)
    '("4 - Cyan" . 4)
    '("5 - Blau" . 5)
    '("6 - Magenta" . 6)
    '("7 - Weiss" . 7)
    '("256 - VonLayer" . 256)
  )
)

;;; --- ACI-Farbliste fuer Attribute (mit "Von Block" am Anfang) ---
(defun SBZ:get-attr-color-list ( / )
  (list
    '("Von Block" . 0)
    '("1 - Rot" . 1)
    '("2 - Gelb" . 2)
    '("3 - Gruen" . 3)
    '("4 - Cyan" . 4)
    '("5 - Blau" . 5)
    '("6 - Magenta" . 6)
    '("7 - Weiss" . 7)
    '("256 - VonLayer" . 256)
  )
)

;;; --- ACI-Code → Index in Farbliste finden ---
(defun SBZ:color-to-index (aci-code color-list / idx i)
  (setq idx 0 i 0)
  (foreach item color-list
    (if (= (cdr item) aci-code) (setq idx i))
    (setq i (1+ i))
  )
  idx
)


;;; --- DCL schreiben (Embedded, Temp-Datei) ---
;;; Layout: 4 Boxen (Zeichnung, Modus, Block, Attribut) + 3 Buttons
(defun SBZ:write-settings-dcl ( / dcl-file fp)
  (setq dcl-file (vl-filename-mktemp "sbz_set" nil ".dcl"))
  (setq fp (open dcl-file "w"))
  (write-line "sbz_settings : dialog {" fp)
  (write-line "  label = \"SetBlockZ - Einstellungen\";" fp)
  (write-line "  width = 55;" fp)
  (write-line "  spacer;" fp)

  ;; ===== BOX 1: ZEICHNUNG =====
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Zeichnung\";" fp)
  (write-line "    : edit_box { key = \"bau0\"; label = \"Bau-0-Hoehe (m):\"; edit_width = 12; }" fp)
  (write-line "    : text { key = \"last_info\"; value = \"\"; }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)

  ;; ===== BOX 2: MODUS =====
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Modus\";" fp)
  (write-line "    : toggle { key = \"copymode\"; label = \"Kopie-Block einfuegen (Original unveraendert)\"; }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)

  ;; ===== BOX 3: BLOCK =====
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Block\";" fp)
  (write-line "    : edit_box { key = \"copyblock\"; label = \"Name:\"; }" fp)
  (write-line "    : row {" fp)
  (write-line "      : edit_box { key = \"copylayer\"; label = \"Layer:\"; edit_width = 10; }" fp)
  (write-line "      : edit_box { key = \"scale\"; label = \"Skalierung:\"; edit_width = 10; }" fp)
  (write-line "    }" fp)
  (write-line "    : popup_list { key = \"colorblock\"; label = \"Farbe:\"; }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)

  ;; ===== BOX 4: ATTRIBUT =====
  ;; Schriftart oben, dann Tabelle (Farbe + Frieren + Suffix in Absolut-Zeile)
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Attribut\";" fp)
  (write-line "    : popup_list { key = \"font\"; label = \"Schriftart:\"; }" fp)
  (write-line "    spacer;" fp)
  ;; Spalten-Header
  (write-line "    : row {" fp)
  (write-line "      : text { width = 8; value = \"\"; }" fp)
  (write-line "      : text { width = 14; value = \"Farbe\"; }" fp)
  (write-line "      : text { width = 6; value = \"Frieren\"; }" fp)
  (write-line "      : text { width = 14; value = \"Suffix\"; }" fp)
  (write-line "    }" fp)
  ;; Absolut (mit Suffix)
  (write-line "    : row {" fp)
  (write-line "      : text { width = 8; value = \"Absolut\"; }" fp)
  (write-line "      : popup_list { key = \"colorabs\"; width = 14; }" fp)
  (write-line "      : toggle { key = \"freezeabs\"; label = \"\"; width = 6; }" fp)
  (write-line "      : edit_box { key = \"suffix\"; label = \"\"; edit_width = 10; }" fp)
  (write-line "    }" fp)
  ;; Relativ
  (write-line "    : row {" fp)
  (write-line "      : text { width = 8; value = \"Relativ\"; }" fp)
  (write-line "      : popup_list { key = \"colorrel\"; width = 14; }" fp)
  (write-line "      : toggle { key = \"freezerel\"; label = \"\"; width = 6; }" fp)
  (write-line "    }" fp)
  ;; Bau-0
  (write-line "    : row {" fp)
  (write-line "      : text { width = 8; value = \"Bau-0\"; }" fp)
  (write-line "      : popup_list { key = \"colorbau0\"; width = 14; }" fp)
  (write-line "      : toggle { key = \"freezebau0\"; label = \"\"; width = 6; }" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)

  ;; ===== BUTTONS: Standard | Aendern | Speichern | Schliessen =====
  (write-line "  : row {" fp)
  (write-line "    : button { key = \"defaults\"; label = \"Standard\"; width = 10; fixed_width = true; }" fp)
  (write-line "    : spacer { width = 1; }" fp)
  (write-line "    : button { key = \"update\"; label = \"Aendern\"; width = 10; fixed_width = true; }" fp)
  (write-line "    : button { key = \"save\"; label = \"Speichern\"; is_default = true; width = 10; fixed_width = true; }" fp)
  (write-line "    : button { key = \"close\"; label = \"Schliessen\"; is_cancel = true; width = 10; fixed_width = true; }" fp)
  (write-line "  }" fp)
  (write-line "}" fp)
  (close fp)
  dcl-file
)


;;; --- Kopie-Modus Felder enabled/disabled je nach Toggle ---
(defun SBZ:settings-update-copyblock-state (toggle-val / mode)
  (setq mode (if (= toggle-val "1") 0 1))
  (mode_tile "copyblock" mode)
  (mode_tile "copylayer" mode)
  (mode_tile "scale" mode)
  (mode_tile "suffix" mode)
  (mode_tile "colorblock" mode)
  (mode_tile "font" mode)
  (mode_tile "colorabs" mode)
  (mode_tile "colorrel" mode)
  (mode_tile "colorbau0" mode)
  (mode_tile "freezeabs" mode)
  (mode_tile "freezerel" mode)
  (mode_tile "freezebau0" mode)
  (mode_tile "update" mode)
)


;;; --- Standard-Werte in Dialog-Felder zuruecksetzen (Dialog bleibt offen) ---
;;; Wird vom "Standard" Button aufgerufen
;;; Benoetigt font-names, block-colors, attr-colors als globale Variablen im Dialog-Scope
(defun SBZ:reset-defaults ( / idx)
  ;; Zeichnung
  (set_tile "bau0" "0.000")
  ;; Modus
  (set_tile "copymode" "1")
  ;; Block
  (set_tile "copyblock" "VermesserGOK")
  (set_tile "copylayer" "GOK")
  (set_tile "suffix" "m ue. A.")
  (set_tile "scale" "1.0000")
  ;; Block-Farbe: 7 = Weiss
  (setq idx (SBZ:color-to-index 7 block-colors))
  (set_tile "colorblock" (itoa idx))
  ;; Schriftart: Arial
  (setq idx (vl-position "Arial" font-names))
  (if (not idx) (setq idx 0))
  (set_tile "font" (itoa idx))
  ;; Attribut-Farben: Von Block (0)
  (setq idx (SBZ:color-to-index 0 attr-colors))
  (set_tile "colorabs" (itoa idx))
  (set_tile "colorrel" (itoa idx))
  (set_tile "colorbau0" (itoa idx))
  ;; Freeze
  (set_tile "freezeabs" "0")
  (set_tile "freezerel" "0")
  (set_tile "freezebau0" "1")
  ;; Felder aktivieren (Kopie-Modus = ein)
  (SBZ:settings-update-copyblock-state "1")
)


;;; --- Hauptfunktion SBZSETTINGS ---
(defun c:SBZSETTINGS ( / *error* dcl-file dcl-id
                         bau0 scale suffix
                         font-names font-idx
                         block-colors attr-colors
                         last-blk last-attr
                         dlg-bau0
                         dlg-copymode dlg-copyblock dlg-scale dlg-suffix
                         dlg-copylayer dlg-font
                         dlg-colorblock dlg-colorabs dlg-colorrel dlg-colorbau0
                         dlg-freezeabs dlg-freezerel dlg-freezebau0
                         dlg-action result count ss blocks blk-def)
  (SBZ:ensure-init)
  (defun *error* (msg)
    (if (not (SBZ:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (SBZ:log-write "ERROR" (strcat "SBZSETTINGS Error-Handler: " msg))
      )
    )
    (if (and dcl-id (< 0 dcl-id)) (unload_dialog dcl-id))
    (if (and dcl-file (findfile dcl-file)) (vl-file-delete dcl-file))
    (princ)
  )

  (SBZ:log-write "INFO" "Befehl SBZSETTINGS gestartet")

  ;; Werte lesen
  (setq bau0 (SBZ:get-bau0))
  (if (not bau0) (setq bau0 0.0))
  (setq last-blk (SBZ:get-last-blockname))
  (setq last-attr (SBZ:get-last-attrtag))
  (setq font-names (SBZ:get-font-list))
  (setq block-colors (SBZ:get-block-color-list))
  (setq attr-colors (SBZ:get-attr-color-list))

  ;; DCL schreiben und laden
  (setq dcl-file (SBZ:write-settings-dcl))
  (setq dcl-id (load_dialog dcl-file))

  (if (not (new_dialog "sbz_settings" dcl-id))
    (progn
      (princ "\nFehler: Settings-Dialog konnte nicht geoeffnet werden.")
      (SBZ:log-write "ERROR" "Settings-Dialog konnte nicht geoeffnet werden")
      (if (< 0 dcl-id) (unload_dialog dcl-id))
      (vl-file-delete dcl-file)
      (princ)
    )
    (progn
      ;; === BOX 1: Zeichnung ===
      (set_tile "bau0" (rtos bau0 2 3))
      (if (and last-blk last-attr)
        (set_tile "last_info" (strcat "Letzter Lauf: " last-blk " / " last-attr))
        (set_tile "last_info" "Noch nicht ausgefuehrt")
      )

      ;; === BOX 2: Modus ===
      (set_tile "copymode" (itoa *SBZ:cfg-copymode*))

      ;; === BOX 3: Block ===
      ;; Block-Farbe Popup
      (start_list "colorblock")
      (foreach c block-colors (add_list (car c)))
      (end_list)
      (set_tile "colorblock" (itoa (SBZ:color-to-index *SBZ:cfg-color-block* block-colors)))
      (set_tile "copyblock" *SBZ:cfg-copyblock*)
      (set_tile "copylayer" *SBZ:cfg-copylayer*)
      (setq scale (SBZ:get-scale))
      (setq suffix (SBZ:get-suffix))
      (set_tile "scale" (rtos scale 2 4))
      (set_tile "suffix" suffix)

      ;; === BOX 4: Attribut ===
      ;; Schriftart
      (start_list "font")
      (foreach fn font-names (add_list fn))
      (end_list)
      (setq font-idx (vl-position (strcase (SBZ:get-font)) (mapcar 'strcase font-names)))
      (if font-idx
        (set_tile "font" (itoa font-idx))
        (set_tile "font" "0")
      )
      ;; Freeze Toggles
      (set_tile "freezeabs" (itoa *SBZ:cfg-freeze-abs*))
      (set_tile "freezerel" (itoa *SBZ:cfg-freeze-rel*))
      (set_tile "freezebau0" (itoa *SBZ:cfg-freeze-bau0*))
      ;; Attribut-Farben
      (start_list "colorabs")
      (foreach c attr-colors (add_list (car c)))
      (end_list)
      (set_tile "colorabs" (itoa (SBZ:color-to-index *SBZ:cfg-color-abs* attr-colors)))
      (start_list "colorrel")
      (foreach c attr-colors (add_list (car c)))
      (end_list)
      (set_tile "colorrel" (itoa (SBZ:color-to-index *SBZ:cfg-color-rel* attr-colors)))
      (start_list "colorbau0")
      (foreach c attr-colors (add_list (car c)))
      (end_list)
      (set_tile "colorbau0" (itoa (SBZ:color-to-index *SBZ:cfg-color-bau0* attr-colors)))
      ;; Kopie-Block Felder deaktivieren wenn Modus aus
      (SBZ:settings-update-copyblock-state (itoa *SBZ:cfg-copymode*))

      ;; --- Action Tiles ---
      (action_tile "copymode" "(SBZ:settings-update-copyblock-state $value)")

      ;; Standard: Setzt alle Felder auf Werkseinstellungen
      (action_tile "defaults" "(SBZ:reset-defaults)")


      ;; Alle get_tile Strings fuer save/update/recalc (Sub-Dialog-Bug!)
      ;; Gemeinsamer Block: alle Werte in globale Variablen lesen
      (setq *SBZ:dlg-get-all*
        (strcat
          "(setq dlg-bau0 (get_tile \"bau0\"))"
          
          "(setq dlg-copymode (get_tile \"copymode\"))"
          "(setq dlg-copyblock (get_tile \"copyblock\"))"
          "(setq dlg-copylayer (get_tile \"copylayer\"))"
          "(setq dlg-scale (get_tile \"scale\"))"
          "(setq dlg-suffix (get_tile \"suffix\"))"
          "(setq dlg-colorblock (get_tile \"colorblock\"))"
          "(setq dlg-font (get_tile \"font\"))"
          "(setq dlg-colorabs (get_tile \"colorabs\"))"
          "(setq dlg-colorrel (get_tile \"colorrel\"))"
          "(setq dlg-colorbau0 (get_tile \"colorbau0\"))"
          "(setq dlg-freezeabs (get_tile \"freezeabs\"))"
          "(setq dlg-freezerel (get_tile \"freezerel\"))"
          "(setq dlg-freezebau0 (get_tile \"freezebau0\"))"
        )
      )

      ;; Speichern
      (action_tile "save"
        (strcat *SBZ:dlg-get-all*
          "(setq dlg-action \"save\")(done_dialog 1)"))

      ;; Aendern (= Speichern + bestehende Bloecke loeschen + neu erstellen)
      (action_tile "update"
        (strcat *SBZ:dlg-get-all*
          "(setq dlg-action \"update\")(done_dialog 3)"))

      ;; Schliessen
      (action_tile "close" "(setq dlg-action \"close\")(done_dialog 0)")

      ;; --- Dialog starten ---
      (setq result (start_dialog))

      ;; --- Dialog geschlossen, Werte auswerten ---
      (if (and dlg-action (/= dlg-action "close"))
        (progn
          ;; Bau-0
          (setq bau0 (atof (vl-string-subst "." "," dlg-bau0)))
          (SBZ:set-bau0 bau0)
          ;; Toggles
          (setq *SBZ:cfg-copymode* (atoi dlg-copymode))
          ;; Block-Settings
          (if (and dlg-copyblock (/= dlg-copyblock ""))
            (setq *SBZ:cfg-copyblock* dlg-copyblock))
          (if (and dlg-copylayer (/= dlg-copylayer ""))
            (setq *SBZ:cfg-copylayer* dlg-copylayer))
          (if (and dlg-scale (/= dlg-scale ""))
            (progn
              (setq scale (atof dlg-scale))
              (if (> scale 0.0) (SBZ:set-scale scale))))
          (if dlg-suffix (SBZ:set-suffix dlg-suffix))
          ;; Schriftart
          (if (and dlg-font font-names)
            (progn
              (setq *SBZ:cfg-font* (nth (atoi dlg-font) font-names))
              (SBZ:set-font *SBZ:cfg-font*)))
          ;; Farben
          (if dlg-colorblock
            (setq *SBZ:cfg-color-block* (cdr (nth (atoi dlg-colorblock) block-colors))))
          (if dlg-colorabs
            (setq *SBZ:cfg-color-abs* (cdr (nth (atoi dlg-colorabs) attr-colors))))
          (if dlg-colorrel
            (setq *SBZ:cfg-color-rel* (cdr (nth (atoi dlg-colorrel) attr-colors))))
          (if dlg-colorbau0
            (setq *SBZ:cfg-color-bau0* (cdr (nth (atoi dlg-colorbau0) attr-colors))))
          ;; Freeze
          (setq *SBZ:cfg-freeze-abs* (atoi dlg-freezeabs))
          (setq *SBZ:cfg-freeze-rel* (atoi dlg-freezerel))
          (setq *SBZ:cfg-freeze-bau0* (atoi dlg-freezebau0))

          ;; Logging
          (SBZ:log-write "INFO"
            (strcat "Settings gespeichert: Bau0=" (rtos bau0 2 3)
                    " CopyMode=" (itoa *SBZ:cfg-copymode*)
                    " Block='" *SBZ:cfg-copyblock* "'"
                    " Font='" *SBZ:cfg-font* "'"))

          ;; Config schreiben
          (SBZ:save-config)
          (princ "\nEinstellungen gespeichert.")

          ;; Aendern? → Alle Kopie-Bloecke loeschen + neu erstellen
          (if (= dlg-action "update")
            (if (and last-blk last-attr)
              (progn
                (SBZ:log-write "INFO"
                  (strcat "Aendern: Loesche + Neu erstellen mit Block='"
                          last-blk "' Attr='" last-attr "'"))
                ;; 1. Alte Kopie-Bloecke loeschen
                (setq count 0)
                (setq ss (ssget "X" (list (cons 2 *SBZ:cfg-copyblock*) (cons 410 "Model"))))
                (if (and ss (> (sslength ss) 0))
                  (progn
                    (setq count (sslength ss))
                    (command "._erase" ss "")
                    (SBZ:log-write "INFO" (strcat (itoa count) " alte Kopie-Bloecke geloescht"))
                  )
                )
                ;; 2. Block-Definition purgen (damit neue Settings wirken)
                (setq blocks (vla-get-blocks
                  (vla-get-activedocument (vlax-get-acad-object))))
                (if (not (vl-catch-all-error-p
                      (setq blk-def (vl-catch-all-apply 'vla-item
                        (list blocks *SBZ:cfg-copyblock*)))))
                  (vl-catch-all-apply 'vla-delete (list blk-def))
                )
                ;; 3. Neu erstellen mit process-blocks
                (setq count (SBZ:process-blocks last-blk last-attr bau0 "REL"))
                (princ (strcat "\n" (itoa count) " Bloecke neu erstellt."))
              )
              (progn
                (princ "\nAendern nicht moeglich: Kein Block/Attribut gespeichert.")
                (princ "\nFuehre zuerst SETBLOCKZ aus.")
                (SBZ:log-write "WARN" "Aendern: Keine gespeicherten Block/Attr-Daten")
              )
            )
          )
        )
        ;; Schliessen ohne Speichern
        (progn
          (princ "\nEinstellungen nicht geaendert.")
          (SBZ:log-write "INFO" "Settings: Geschlossen ohne Speichern")
        )
      )

      ;; Cleanup DCL
      (unload_dialog dcl-id)
      (vl-file-delete dcl-file)
    )
  )

  (SBZ:log-write "INFO" "Befehl SBZSETTINGS beendet")
  (princ)
)


;;; ----------------------------------------------------------------------------
;;; c:SBZDEBUG - Debug-Modus Toggle
;;; ----------------------------------------------------------------------------
(defun c:SBZDEBUG ( / )
  (SBZ:ensure-init)
  (setq *SBZ:debug-mode* (not *SBZ:debug-mode*))
  (princ (strcat "\nSBZ Debug-Modus: "
    (if *SBZ:debug-mode* "EIN" "AUS")))
  (SBZ:log-write "INFO"
    (strcat "Debug-Modus: " (if *SBZ:debug-mode* "EIN" "AUS")))
  (princ)
)


;;; ----------------------------------------------------------------------------
;;; c:SBZPURGE - Kopie-Bloecke loeschen + Block-Definition purgen
;;; Loescht alle Instanzen des Kopie-Blocks und entfernt die Definition.
;;; Beim naechsten SETBLOCKZ wird die Definition mit aktuellen Settings
;;; (Schriftart, Farben, Texthoehe) neu erstellt.
;;; ----------------------------------------------------------------------------
(defun c:SBZPURGE ( / *error* old-cmdecho blk-name ss count blocks blk-def)
  (SBZ:ensure-init)
  (defun *error* (msg)
    (if (not (SBZ:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (SBZ:log-write "ERROR" (strcat "SBZPURGE Error-Handler: " msg))
      )
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  (setq blk-name *SBZ:cfg-copyblock*)
  (SBZ:log-write "INFO" (strcat "SBZPURGE: Starte fuer Block '" blk-name "'"))

  ;; Schritt 1: Alle Instanzen im Modelspace loeschen
  (setq ss (ssget "X" (list (cons 2 blk-name) (cons 410 "Model"))))
  (if (and ss (> (sslength ss) 0))
    (progn
      (setq count (sslength ss))
      (command "._erase" ss "")
      (princ (strcat "\n" (itoa count) " '" blk-name "' Bloecke geloescht."))
      (SBZ:log-write "INFO" (strcat (itoa count) " Instanzen geloescht"))
    )
    (progn
      (princ (strcat "\nKeine '" blk-name "' Bloecke im Modelspace gefunden."))
      (SBZ:log-write "INFO" "Keine Instanzen gefunden")
    )
  )

  ;; Schritt 2: Block-Definition purgen
  (setq blocks (vla-get-blocks (vla-get-activedocument (vlax-get-acad-object))))
  (if (not (vl-catch-all-error-p
        (setq blk-def (vl-catch-all-apply 'vla-item (list blocks blk-name)))))
    (progn
      (if (not (vl-catch-all-error-p
            (vl-catch-all-apply 'vla-delete (list blk-def))))
        (progn
          (princ (strcat "\nBlock-Definition '" blk-name "' geloescht."))
          (SBZ:log-write "INFO" (strcat "Block-Definition '" blk-name "' geloescht"))
        )
        (progn
          (princ (strcat "\nBlock-Definition konnte nicht geloescht werden (noch in Verwendung?)."))
          (princ "\nVersuche: PURGE → Bloecke → " blk-name)
          (SBZ:log-write "WARN" "Block-Definition konnte nicht geloescht werden")
        )
      )
    )
    (progn
      (princ (strcat "\nBlock-Definition '" blk-name "' existiert nicht."))
      (SBZ:log-write "INFO" "Block-Definition existiert nicht")
    )
  )

  (princ "\nBeim naechsten SETBLOCKZ wird der Block mit aktuellen Settings neu erstellt.")
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (SBZ:log-write "INFO" "SBZPURGE beendet")
  (princ)
)


;;; ============================================================================
;;; INITIALISIERUNG (NUR PRINC!)
;;; ============================================================================

(princ (strcat "\nSetBlockZ.lsp v" *SBZ:version* " geladen."))
(princ "\nBefehle: SETBLOCKZ | SBZSETTINGS | SBZPURGE | SBZDEBUG")
(princ)
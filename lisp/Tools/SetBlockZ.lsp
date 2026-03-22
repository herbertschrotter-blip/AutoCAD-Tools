;;; ============================================================================
;;; SetBlockZ.lsp
;;; Setzt Block-Z-Koordinaten aus Attributwerten (Vermessungshöhen)
;;;
;;; Version: 1.4.1
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
;;; SBZDEBUG     - Debug-Modus ein/aus
;;; ============================================================================


;;; ============================================================================
;;; KONFIGURATION (KONSTANTEN)
;;; ============================================================================

(setq *SBZ:version* "1.4.1")
(setq *SBZ:namespace* "SBZ")
(setq *SBZ:appdata-folder* "SetBlockZ")

;; Custom Property Name fuer Bau-0-Hoehe in DWG SummaryInfo
(setq *SBZ:cp-bau0* "SetBlockZ_Bau0")
;; Custom Property fuer letzten Blockname und Attribut-Tag (pro DWG!)
(setq *SBZ:cp-blockname* "SetBlockZ_BlockName")
(setq *SBZ:cp-attrtag* "SetBlockZ_AttrTag")
(setq *SBZ:cp-scale* "SetBlockZ_Scale")
(setq *SBZ:cp-textheight* "SetBlockZ_TextHeight")
(setq *SBZ:cp-suffix* "SetBlockZ_Suffix")


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
(setq *SBZ:cfg-copymode* 0)         ;; Kopie-Modus: Original beibehalten + Kopie-Block (0/1)
(setq *SBZ:cfg-copyblock* "VermesserGOK") ;; Blockname fuer Kopie-Block


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

;;; Texthoehe lesen (Real, Default 0.5)
(defun SBZ:get-textheight ( / val)
  (setq val (SBZ:get-custom-prop *SBZ:cp-textheight*))
  (if (and val (/= val ""))
    (atof val)
    0.5
  )
)

;;; Texthoehe schreiben
(defun SBZ:set-textheight (h)
  (SBZ:set-custom-prop *SBZ:cp-textheight* (rtos h 2 4))
  (SBZ:log-write "INFO" (strcat "Texthoehe gespeichert: " (rtos h 2 4)))
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
;;; Rueckgabe: Anzahl verarbeiteter Bloecke (Integer)
;;; ----------------------------------------------------------------------------
(defun SBZ:process-blocks (blk-name attr-tag bau0
                           / ss i ent val-str abs-h rel-z count-ok count-err
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
                    (if copy-mode
                      ;; === KOPIE-MODUS: Original beibehalten, Kopie-Block einfuegen ===
                      (if (SBZ:insert-copyblock ent copy-blk-name abs-h rel-z target-layer)
                        (progn
                          (setq count-ok (1+ count-ok))
                          (SBZ:log-write "DEBUG"
                            (strcat "Block " (itoa (1+ i)) ": Kopie eingefuegt"
                                    " ABS=" (rtos abs-h 2 3)
                                    " REL=" (rtos rel-z 2 3)))
                        )
                        (progn
                          (setq count-err (1+ count-err))
                          (SBZ:log-write "ERROR"
                            (strcat "Block " (itoa (1+ i)) ": Kopie-Insert fehlgeschlagen"))
                        )
                      )
                      ;; === STANDARD-MODUS: Original verschieben ===
                      (if (SBZ:set-block-z ent rel-z)
                        (progn
                          (setq count-ok (1+ count-ok))
                          (SBZ:log-write "DEBUG"
                            (strcat "Block " (itoa (1+ i)) ": Attr='" val-str
                                    "' abs=" (rtos abs-h 2 3)
                                    " rel=" (rtos rel-z 2 3) " → Z gesetzt"))
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
(defun SBZ:ensure-copyblock-def (blk-name / blocks blk-exists)
  (setq blocks (vla-get-blocks (vla-get-activedocument (vlax-get-acad-object))))
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
                        '(10 0.1 0.01 0.0)    ;; Startpunkt
                        '(11 0.1 0.01 0.0)    ;; Ausrichtungspunkt
                        '(40 . 0.03)          ;; Texthoehe (wird beim Insert skaliert)
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
                        '(10 0.1 -0.01 0.0)
                        '(11 0.1 -0.01 0.0)
                        '(40 . 0.03)
                        '(1 . "0.000")
                        '(2 . "HOEHE_REL")
                        '(3 . "Relative Hoehe (nach Bau-0)")
                        '(70 . 0)
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
;;; SBZ:insert-copyblock
;;; Fuegt den Kopie-Block an der Position des Original-Blocks ein
;;; Parameter:
;;;   orig-ent  - Entity-Name des Original-Blocks (ename)
;;;   blk-name  - Name des Kopie-Blocks (String)
;;;   abs-h     - Absolute Hoehe (Real)
;;;   rel-z     - Relative Hoehe nach Bau-0 (Real)
;;;   layer     - Ziel-Layer (String, "" = aktueller Layer)
;;; Rueckgabe: T bei Erfolg, nil bei Fehler
;;; ----------------------------------------------------------------------------
(defun SBZ:insert-copyblock (orig-ent blk-name abs-h rel-z layer
                             / orig-data orig-pt ins-pt new-ent attrs
                               scale th suffix abs-str rel-str sign)
  ;; XY vom Original, Z = relative Hoehe
  (setq orig-data (entget orig-ent))
  (setq orig-pt (cdr (assoc 10 orig-data)))
  (setq ins-pt (list (car orig-pt) (cadr orig-pt) rel-z))
  ;; Einstellungen aus DWG Custom Properties lesen
  (setq scale (SBZ:get-scale))
  (setq th (SBZ:get-textheight))
  (setq suffix (SBZ:get-suffix))
  ;; Block einfuegen
  (setq new-ent
    (vl-catch-all-apply
      '(lambda ()
        (vla-InsertBlock
          (vla-get-modelspace (vla-get-activedocument (vlax-get-acad-object)))
          (vlax-3d-point ins-pt)
          blk-name
          scale scale scale  ;; Scale X Y Z
          0.0                ;; Rotation
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
      ;; Absolut-Hoehe: Wert + Suffix (z.B. "320.18 m ue. A.")
      ;; 2 Nachkommastellen, DIMZIN=0 erzwingt trailing Zeros
      (setq abs-str (strcat (SBZ:rtos-fixed abs-h 2)
                            (if (and suffix (/= suffix ""))
                              (strcat " " suffix) "")))
      ;; Relativ-Hoehe: Vorzeichen + Wert
      ;; 2 Nachkommastellen mit erzwungenen trailing Zeros
      ;; Positiv = "+", Negativ = "-" (kommt automatisch), Null = "%%P" (Plus-Minus)
      (cond
        ((> rel-z 0.001)
          (setq rel-str (strcat "+" (SBZ:rtos-fixed rel-z 2)))
        )
        ((< rel-z -0.001)
          (setq rel-str (SBZ:rtos-fixed rel-z 2))
        )
        (T
          (setq rel-str (strcat "%%P" (SBZ:rtos-fixed (abs rel-z) 2)))
        )
      )
      ;; Attribute setzen
      (setq attrs (vlax-invoke new-ent 'GetAttributes))
      (foreach attr attrs
        (cond
          ((= (strcase (vla-get-TagString attr)) "HOEHE_ABS")
            (vla-put-TextString attr abs-str)
            ;; Texthoehe setzen (skaliert mit Block, also Basis-Wert)
            (vl-catch-all-apply 'vla-put-Height (list attr th))
          )
          ((= (strcase (vla-get-TagString attr)) "HOEHE_REL")
            (vla-put-TextString attr rel-str)
            (vl-catch-all-apply 'vla-put-Height (list attr th))
          )
        )
      )
      ;; Layer setzen falls angegeben
      (if (and layer (/= layer ""))
        (vl-catch-all-apply 'vla-put-Layer (list new-ent layer))
      )
      (SBZ:log-write "DEBUG"
        (strcat "Kopie-Block: ABS='" abs-str "' REL='" rel-str
                "' Scale=" (rtos scale 2 2) " TH=" (rtos th 2 3)))
      T
    )
  )
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
                       bau0 bau0-input ss-preview num-found confirm count)
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

                              ;; Blockname + Attribut in DWG Custom Properties merken
                              (SBZ:set-last-blockname blk-name)
                              (SBZ:set-last-attrtag selected-attr)
                              ;; Toggles speichern (AppData)
                              (SBZ:save-config)

                              ;; --- Schritt 6: Verarbeitung ---
                              (setq count (SBZ:process-blocks blk-name selected-attr bau0))
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

;;; --- DCL schreiben (Embedded, Temp-Datei) ---
(defun SBZ:write-settings-dcl ( / dcl-file fp)
  (setq dcl-file (vl-filename-mktemp "sbz_set" nil ".dcl"))
  (setq fp (open dcl-file "w"))
  (write-line "sbz_settings : dialog {" fp)
  (write-line "  label = \"SetBlockZ - Einstellungen\";" fp)
  (write-line "  spacer;" fp)
  ;; --- Bau-0-Hoehe ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Bau-0-Hoehe\";" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"bau0\";" fp)
  (write-line "      label = \"Hoehe (m):\";" fp)
  (write-line "      edit_width = 14;" fp)
  (write-line "      value = \"0.000\";" fp)
  (write-line "    }" fp)
  (write-line "    : text { key = \"bau0_info\"; value = \"\"; }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  ;; --- Optionen ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Optionen\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"byblock\";" fp)
  (write-line "      label = \"Farbe auf ByBlock setzen\";" fp)
  (write-line "    }" fp)
  (write-line "    spacer;" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"movelayer\";" fp)
  (write-line "      label = \"Bloecke auf Ziel-Layer verschieben\";" fp)
  (write-line "    }" fp)
  (write-line "    : popup_list {" fp)
  (write-line "      key = \"layerlist\";" fp)
  (write-line "      label = \"Ziel-Layer:\";" fp)
  (write-line "      width = 30;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  ;; --- Kopie-Modus ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Kopie-Modus\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"copymode\";" fp)
  (write-line "      label = \"Original beibehalten + Kopie-Block einfuegen\";" fp)
  (write-line "    }" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"copyblock\";" fp)
  (write-line "      label = \"Kopie-Blockname:\";" fp)
  (write-line "      edit_width = 25;" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : edit_box {" fp)
  (write-line "        key = \"scale\";" fp)
  (write-line "        label = \"Skalierung:\";" fp)
  (write-line "        edit_width = 10;" fp)
  (write-line "      }" fp)
  (write-line "      : edit_box {" fp)
  (write-line "        key = \"textheight\";" fp)
  (write-line "        label = \"Texthoehe:\";" fp)
  (write-line "        edit_width = 10;" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"suffix\";" fp)
  (write-line "      label = \"Suffix Absoluthoehe:\";" fp)
  (write-line "      edit_width = 20;" fp)
  (write-line "    }" fp)
  (write-line "    : text { key = \"copyinfo\"; value = \"Relativ: +/- automatisch, %%P bei 0\"; }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  ;; --- Letzte Verarbeitung ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Letzte Verarbeitung\";" fp)
  (write-line "    : text { key = \"last_block\"; value = \"Block: -\"; }" fp)
  (write-line "    : text { key = \"last_attr\"; value = \"Attribut: -\"; }" fp)
  (write-line "    spacer;" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"recalc\";" fp)
  (write-line "      label = \"Neu berechnen\";" fp)
  (write-line "      width = 20;" fp)
  (write-line "      fixed_width = true;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  ;; --- Buttons ---
  (write-line "  : row {" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"save\";" fp)
  (write-line "      label = \"Speichern\";" fp)
  (write-line "      is_default = true;" fp)
  (write-line "      width = 14;" fp)
  (write-line "      fixed_width = true;" fp)
  (write-line "    }" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"close\";" fp)
  (write-line "      label = \"Schliessen\";" fp)
  (write-line "      is_cancel = true;" fp)
  (write-line "      width = 14;" fp)
  (write-line "      fixed_width = true;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "}" fp)
  (close fp)
  dcl-file
)


;;; --- Layer-Liste fuer Popup aufbauen ---
(defun SBZ:get-layer-names ( / doc layers result)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq layers (vla-get-layers doc))
  (setq result nil)
  (vlax-for lay layers
    (setq result (cons (vla-get-Name lay) result))
  )
  (setq result (vl-sort (reverse result) '<))
  result
)


;;; --- Popup-Liste aktualisieren (Layer enabled/disabled je nach Toggle) ---
(defun SBZ:settings-update-layer-state (toggle-val / )
  (mode_tile "layerlist" (if (= toggle-val "1") 0 1))
)

;;; --- Kopie-Blockname + Skalierung + Text enabled/disabled je nach Toggle ---
(defun SBZ:settings-update-copyblock-state (toggle-val / mode)
  (setq mode (if (= toggle-val "1") 0 1))
  (mode_tile "copyblock" mode)
  (mode_tile "scale" mode)
  (mode_tile "textheight" mode)
  (mode_tile "suffix" mode)
)


;;; --- Hauptfunktion SBZSETTINGS ---
(defun c:SBZSETTINGS ( / *error* dcl-file dcl-id
                         bau0 scale th suffix layer-names layer-idx
                         last-blk last-attr
                         ;; Werte die aus Dialog gelesen werden (vor done_dialog!)
                         dlg-bau0 dlg-byblock dlg-movelayer dlg-layer-idx
                         dlg-copymode dlg-copyblock dlg-scale dlg-textheight dlg-suffix
                         dlg-action result count)
  (SBZ:ensure-init)
  (defun *error* (msg)
    (if (not (SBZ:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (SBZ:log-write "ERROR" (strcat "SBZSETTINGS Error-Handler: " msg))
      )
    )
    ;; Cleanup DCL
    (if (and dcl-id (< 0 dcl-id)) (unload_dialog dcl-id))
    (if (and dcl-file (findfile dcl-file)) (vl-file-delete dcl-file))
    (princ)
  )

  (SBZ:log-write "INFO" "Befehl SBZSETTINGS gestartet")

  ;; Bau-0 aus Custom Property lesen
  (setq bau0 (SBZ:get-bau0))
  (if (not bau0) (setq bau0 0.0))

  ;; Letzter Block/Attr aus DWG Custom Properties lesen
  (setq last-blk (SBZ:get-last-blockname))
  (setq last-attr (SBZ:get-last-attrtag))

  ;; Layer-Liste aufbauen
  (setq layer-names (SBZ:get-layer-names))

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
      ;; --- Werte in Dialog setzen ---

      ;; Bau-0
      (set_tile "bau0" (rtos bau0 2 3))
      (set_tile "bau0_info" "(gespeichert in DWG Custom Property)")

      ;; ByBlock Toggle
      (set_tile "byblock" (itoa *SBZ:cfg-byblock*))

      ;; Layer Toggle + Popup
      (set_tile "movelayer" (itoa *SBZ:cfg-movelayer*))
      ;; Layer-Popup fuellen
      (start_list "layerlist")
      (foreach ln layer-names (add_list ln))
      (end_list)
      ;; Aktuellen Ziel-Layer vorselektieren
      (setq layer-idx (vl-position *SBZ:cfg-target-layer* layer-names))
      (if layer-idx
        (set_tile "layerlist" (itoa layer-idx))
        (set_tile "layerlist" "0")
      )
      ;; Layer-Popup aktivieren/deaktivieren
      (SBZ:settings-update-layer-state (itoa *SBZ:cfg-movelayer*))

      ;; Kopie-Modus
      (set_tile "copymode" (itoa *SBZ:cfg-copymode*))
      (set_tile "copyblock" *SBZ:cfg-copyblock*)
      ;; Skalierung, Texthoehe, Suffix aus DWG Custom Properties
      (setq scale (SBZ:get-scale))
      (setq th (SBZ:get-textheight))
      (setq suffix (SBZ:get-suffix))
      (set_tile "scale" (rtos scale 2 4))
      (set_tile "textheight" (rtos th 2 4))
      (set_tile "suffix" suffix)
      (SBZ:settings-update-copyblock-state (itoa *SBZ:cfg-copymode*))

      ;; Letzte Verarbeitung (aus DWG Custom Properties)
      (if last-blk
        (set_tile "last_block" (strcat "Block: " last-blk))
        (set_tile "last_block" "Block: (noch nicht verwendet)")
      )
      (if last-attr
        (set_tile "last_attr" (strcat "Attribut: " last-attr))
        (set_tile "last_attr" "Attribut: (noch nicht verwendet)")
      )

      ;; Neu-Berechnen Button nur aktiv wenn letzte Werte vorhanden
      (if (or (not last-blk) (not last-attr))
        (mode_tile "recalc" 1) ;; deaktiviert
      )

      ;; --- Action Tiles ---
      ;; Layer-Toggle steuert Popup-Status
      (action_tile "movelayer"
        "(SBZ:settings-update-layer-state $value)"
      )
      ;; Kopie-Toggle steuert Blockname-Feld
      (action_tile "copymode"
        "(SBZ:settings-update-copyblock-state $value)"
      )

      ;; Speichern: Werte in globale Variablen BEVOR done_dialog (Sub-Dialog-Bug!)
      (action_tile "save"
        (strcat
          "(setq dlg-bau0 (get_tile \"bau0\"))"
          "(setq dlg-byblock (get_tile \"byblock\"))"
          "(setq dlg-movelayer (get_tile \"movelayer\"))"
          "(setq dlg-layer-idx (get_tile \"layerlist\"))"
          "(setq dlg-copymode (get_tile \"copymode\"))"
          "(setq dlg-copyblock (get_tile \"copyblock\"))"
          "(setq dlg-scale (get_tile \"scale\"))"
          "(setq dlg-textheight (get_tile \"textheight\"))"
          "(setq dlg-suffix (get_tile \"suffix\"))"
          "(setq dlg-action \"save\")"
          "(done_dialog 1)"
        )
      )

      ;; Neu berechnen: Werte speichern + Aktion merken
      (action_tile "recalc"
        (strcat
          "(setq dlg-bau0 (get_tile \"bau0\"))"
          "(setq dlg-byblock (get_tile \"byblock\"))"
          "(setq dlg-movelayer (get_tile \"movelayer\"))"
          "(setq dlg-layer-idx (get_tile \"layerlist\"))"
          "(setq dlg-copymode (get_tile \"copymode\"))"
          "(setq dlg-copyblock (get_tile \"copyblock\"))"
          "(setq dlg-scale (get_tile \"scale\"))"
          "(setq dlg-textheight (get_tile \"textheight\"))"
          "(setq dlg-suffix (get_tile \"suffix\"))"
          "(setq dlg-action \"recalc\")"
          "(done_dialog 2)"
        )
      )

      ;; Schliessen
      (action_tile "close" "(setq dlg-action \"close\")(done_dialog 0)")

      ;; --- Dialog starten ---
      (setq result (start_dialog))

      ;; --- Dialog geschlossen, Werte auswerten ---
      (if (and dlg-action (/= dlg-action "close"))
        (progn
          ;; Bau-0 auswerten und speichern
          (setq bau0 (atof (vl-string-subst "." "," dlg-bau0)))
          (SBZ:set-bau0 bau0)
          (SBZ:log-write "INFO" (strcat "Settings: Bau-0 = " (rtos bau0 2 3)))

          ;; Toggles speichern
          (setq *SBZ:cfg-byblock* (atoi dlg-byblock))
          (setq *SBZ:cfg-movelayer* (atoi dlg-movelayer))
          (SBZ:log-write "INFO"
            (strcat "Settings: ByBlock=" dlg-byblock
                    " MoveLayer=" dlg-movelayer))

          ;; Ziel-Layer speichern
          (if (and dlg-layer-idx layer-names)
            (progn
              (setq *SBZ:cfg-target-layer*
                (nth (atoi dlg-layer-idx) layer-names))
              (SBZ:log-write "INFO"
                (strcat "Settings: Ziel-Layer = '" *SBZ:cfg-target-layer* "'"))
            )
          )

          ;; Kopie-Modus speichern
          (setq *SBZ:cfg-copymode* (atoi dlg-copymode))
          (if (and dlg-copyblock (/= dlg-copyblock ""))
            (setq *SBZ:cfg-copyblock* dlg-copyblock)
          )
          ;; Skalierung in DWG Custom Property speichern
          (if (and dlg-scale (/= dlg-scale ""))
            (progn
              (setq scale (atof dlg-scale))
              (if (> scale 0.0)
                (SBZ:set-scale scale)
                (SBZ:log-write "WARN" (strcat "Ungueltige Skalierung: " dlg-scale))
              )
            )
          )
          ;; Texthoehe in DWG Custom Property speichern
          (if (and dlg-textheight (/= dlg-textheight ""))
            (progn
              (setq th (atof dlg-textheight))
              (if (> th 0.0)
                (SBZ:set-textheight th)
                (SBZ:log-write "WARN" (strcat "Ungueltige Texthoehe: " dlg-textheight))
              )
            )
          )
          ;; Suffix in DWG Custom Property speichern
          (if dlg-suffix
            (SBZ:set-suffix dlg-suffix)
          )
          (SBZ:log-write "INFO"
            (strcat "Settings: CopyMode=" dlg-copymode
                    " CopyBlock='" *SBZ:cfg-copyblock*
                    "' Scale=" (rtos (SBZ:get-scale) 2 4)
                    " TH=" (rtos (SBZ:get-textheight) 2 4)
                    " Suffix='" (SBZ:get-suffix) "'"))

          ;; Config schreiben
          (SBZ:save-config)
          (princ "\nEinstellungen gespeichert.")

          ;; Neu berechnen?
          (if (= dlg-action "recalc")
            (if (and last-blk last-attr)
              (progn
                (SBZ:log-write "INFO"
                  (strcat "Neuberechnung: Block='" last-blk
                          "' Attr='" last-attr
                          "' Bau-0=" (rtos bau0 2 3)))
                (setq count
                  (SBZ:process-blocks last-blk last-attr bau0))
                (princ (strcat "\nNeuberechnung: " (itoa count) " Bloecke verarbeitet."))
              )
              (progn
                (princ "\nNeuberechnung nicht moeglich: Kein Block/Attribut in Zeichnung gespeichert.")
                (SBZ:log-write "WARN" "Neuberechnung: Keine gespeicherten Block/Attr-Daten")
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


;;; ============================================================================
;;; INITIALISIERUNG (NUR PRINC!)
;;; ============================================================================

(princ (strcat "\nSetBlockZ.lsp v" *SBZ:version* " geladen."))
(princ "\nBefehle: SETBLOCKZ | SBZSETTINGS | SBZDEBUG")
(princ)
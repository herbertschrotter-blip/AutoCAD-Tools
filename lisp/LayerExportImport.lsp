;;; ========================================================================
;;; LayerExportImport.lsp
;;; Layer-Synchronisation zwischen Zeichnungen via Master-Datei
;;; MasterID-System | Custom Property GUID | ObjectDBX Batch-Sync
;;; 
;;; Version: 1.1.0
;;; Datum:   2026-03-09
;;; Autor:   Herbert Schrotter
;;;
;;; Installation:
;;;   1. APPLOAD in AutoCAD ausfuehren
;;;   2. LayerExportImport.lsp auswaehlen und laden
;;;   3. Automatisches Laden: Zu Startup Suite hinzufuegen
;;;   4. Tastenkuerzel: CUI > Strg+Shift+L auf LAYSYNC legen
;;;
;;; Befehle:
;;;   LAYSYNC    - Import + Export (mit Option fuer Batch-Sync)
;;;   LAYSYNCALL - Alle registrierten Zeichnungen synchronisieren
;;;   LAYEXP     - Nur Export: Layer in Master-Datei schreiben
;;;   LAYIMP     - Nur Import: Layer aus Master holen (interaktiv)
;;;   LAYLOG     - Layer-Aenderungshistorie anzeigen
;;;   LAYSTATUS  - Uebersicht aller Zeichnungen und Sync-Stand
;;;   LAYCFG     - Konfiguration anzeigen / aendern
;;;
;;; Dateien im LayerSync-Ordner:
;;;   LayerMaster.csv  - Layer-Daten mit MasterID (Primary Key)
;;;   LayerMapper.csv  - Handle+GUID+Pfad-Zuordnung (6 Felder)
;;;   LayerHistory.csv - Aenderungsprotokoll (append-only)
;;;   LayerSync.cfg    - Konfiguration
;;; ========================================================================


;;; ========================================================================
;;; KONFIGURATION
;;; ========================================================================
(setq *LXI:default-path*
  "D:\\OneDrive\\Dokumente\\02 Arbeit\\05 Vorlagen - Scripte\\02_Autocad_Tools\\LayerSync"
)
(setq *LXI:default-prefix* "S_")
(setq *LXI:default-debug*  "OFF")
(setq *LXI:base-path* *LXI:default-path*)
(setq *LXI:prefix*    *LXI:default-prefix*)
(setq *LXI:debug*     nil)
(setq *LXI:sep* ";")
(setq *LXI:cached-guid* nil)
(setq *LXI:cached-guid-dwg* nil)


;;; ========================================================================
;;; CONFIG (ANSI)
;;; ========================================================================

(defun LXI:get-config-path ( / )
  (strcat *LXI:base-path* "\\LayerSync.cfg"))

(defun LXI:read-config ( / filepath fp line pos key val)
  (setq filepath (LXI:get-config-path))
  (if (findfile filepath)
    (progn
      (setq fp (open filepath "r"))
      (if fp (progn
        (while (setq line (read-line fp))
          (if (and (> (strlen line) 0)
                   (/= (substr line 1 1) ";")
                   (setq pos (vl-string-search "=" line)))
            (progn
              (setq key (substr line 1 pos))
              (setq val (substr line (+ pos 2)))
              (cond
                ((= key "PATH")   (setq *LXI:base-path* val))
                ((= key "PREFIX") (setq *LXI:prefix* val))
                ((= key "DEBUG")  (setq *LXI:debug* (= (strcase val) "ON")))))))
        (close fp))))))

(defun LXI:write-config ( / filepath fp)
  (LXI:ensure-directory *LXI:base-path*)
  (setq filepath (LXI:get-config-path))
  (setq fp (open filepath "w"))
  (if fp (progn
    (write-line ";;; LayerSync Konfiguration v1.1.0" fp)
    (write-line (strcat "PATH=" *LXI:base-path*) fp)
    (write-line (strcat "PREFIX=" *LXI:prefix*) fp)
    (write-line (strcat "DEBUG=" (if *LXI:debug* "ON" "OFF")) fp)
    (close fp) T)))


;;; ========================================================================
;;; ALLGEMEINE HILFSFUNKTIONEN
;;; ========================================================================

(defun LXI:xref-layer-p (lay-name / ) (wcmatch lay-name "*|*"))

(defun LXI:sync-layer-p (lay-name / )
  (wcmatch lay-name (strcat *LXI:prefix* "*")))

(defun LXI:ensure-directory (dir-path / )
  (if (not (vl-file-directory-p dir-path)) (vl-mkdir dir-path))
  (vl-file-directory-p dir-path))

(defun LXI:get-sync-folder ( / )
  (if (LXI:ensure-directory *LXI:base-path*) *LXI:base-path*
    (progn (princ (strcat "\n*** Ordner nicht verfuegbar: " *LXI:base-path*)) nil)))

(defun LXI:split-string (str del / pos result part)
  (setq result nil)
  (while (setq pos (vl-string-search del str))
    (setq part (substr str 1 pos))
    (setq result (cons part result))
    (setq str (substr str (+ pos 2))))
  (setq result (cons str result))
  (reverse result))

(defun LXI:debug-print (msg / )
  (if *LXI:debug* (princ (strcat "\n  [DBG] " msg))))

(defun LXI:timestamp ( / ) (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM)"))

(defun LXI:dwg-name ( / )
  (strcat (vl-filename-base (getvar "DWGNAME")) ".dwg"))

(defun LXI:dwg-path ( / )
  (getvar "DWGPREFIX"))

(defun LXI:dwg-fullpath ( / prefix)
  (setq prefix (getvar "DWGPREFIX"))
  (strcat prefix (vl-filename-base (getvar "DWGNAME")) ".dwg"))

(defun LXI:pad-str (str width / pad)
  (if (null str) (setq str ""))
  (if (> (strlen str) width)
    (strcat (substr str 1 (- width 2)) "..")
    (progn
      (setq pad (- width (strlen str)))
      (while (> pad 0) (setq str (strcat str " ")) (setq pad (1- pad)))
      str)))


;;; ========================================================================
;;; GUID (Custom Property)
;;; ========================================================================

(defun LXI:dwg-guid ( / si guid num-props i key val found)
  (if (and *LXI:cached-guid*
           (/= *LXI:cached-guid* "")
           (= *LXI:cached-guid-dwg* (LXI:dwg-name)))
    (progn
      (LXI:debug-print (strcat "GUID (cached): " *LXI:cached-guid*))
      *LXI:cached-guid*)
    (progn
      (setq si (vla-get-SummaryInfo
                 (vla-get-ActiveDocument (vlax-get-acad-object))))
      (setq found nil guid nil)
      (setq num-props (vla-NumCustomInfo si))
      (if (> num-props 0)
        (progn
          (setq i 0)
          (while (and (< i num-props) (null found))
            (setq key (vlax-make-variant "" vlax-vbString))
            (setq val (vlax-make-variant "" vlax-vbString))
            (vl-catch-all-apply
              '(lambda ()
                (vla-GetCustomByIndex si i 'key 'val)
                (if (= (strcase (vlax-variant-value key)) "LAYERSYNCGUID")
                  (progn
                    (setq guid (vlax-variant-value val))
                    (setq found T)))))
            (setq i (1+ i)))))
      (if (or (null guid) (= guid ""))
        (progn
          (setq guid (LXI:generate-guid))
          (vl-catch-all-apply
            '(lambda () (vla-AddCustomInfo si "LayerSyncGUID" guid)))
          (LXI:debug-print (strcat "Neue GUID: " guid))
          (princ (strcat "\n  LayerSyncGUID erstellt: " guid))
          (princ "\n  Zeichnung speichern damit GUID permanent wird!"))
        (LXI:debug-print (strcat "GUID: " guid)))
      (setq *LXI:cached-guid* guid)
      (setq *LXI:cached-guid-dwg* (LXI:dwg-name))
      guid)))

(defun LXI:generate-guid ( / date-str rand-str)
  (setq date-str (menucmd "M=$(edtime,0,YYYYMODDHHMMSS)"))
  (setq rand-str (itoa (rem (getvar "MILLISECS") 100000)))
  (while (< (strlen rand-str) 5) (setq rand-str (strcat "0" rand-str)))
  (strcat "LXI-" date-str "-" rand-str))


;;; ========================================================================
;;; MASTERID
;;; ========================================================================

(defun LXI:format-id (num / str)
  (setq str (itoa num))
  (while (< (strlen str) 6) (setq str (strcat "0" str)))
  (strcat "M" str))

(defun LXI:next-master-id (master-data / max-num id-str id-num)
  (setq max-num 0)
  (foreach lay master-data
    (setq id-str (car lay))
    (if (and id-str (> (strlen id-str) 1) (= (substr id-str 1 1) "M"))
      (progn
        (setq id-num (atoi (substr id-str 2)))
        (if (> id-num max-num) (setq max-num id-num)))))
  (LXI:format-id (1+ max-num)))


;;; ========================================================================
;;; MASTER (.csv) - 11 Felder
;;; MasterID;Name;Color;Linetype;Lineweight;Plot;OnOff;Freeze;Lock;Source;LastModified
;;; ========================================================================

(defun LXI:read-master ( / sync-dir filepath fp line fields result)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir) nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMaster.csv"))
      (if (not (findfile filepath)) nil
        (progn
          (setq fp (open filepath "r"))
          (if (null fp) nil
            (progn
              (setq result nil)
              (while (setq line (read-line fp))
                (if (and (> (strlen line) 0)
                         (= (substr line 1 1) "M")
                         (/= (substr line 1 8) "MasterID"))
                  (progn
                    (setq fields (LXI:split-string line *LXI:sep*))
                    (if (= (length fields) 11)
                      (setq result (cons fields result))))))
              (close fp) (reverse result))))))))

(defun LXI:write-master (master-data / sync-dir filepath fp lay s)
  (setq sync-dir (LXI:get-sync-folder)) (setq s *LXI:sep*)
  (if (null sync-dir) nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMaster.csv"))
      (setq fp (open filepath "w"))
      (if (null fp) nil
        (progn
          (write-line
            (strcat "MasterID" s "Name" s "Color" s "Linetype" s "Lineweight"
                    s "Plot" s "OnOff" s "Freeze" s "Lock" s "Source" s "LastModified") fp)
          (setq master-data (vl-sort master-data '(lambda (a b) (< (car a) (car b)))))
          (foreach lay master-data
            (write-line
              (strcat (nth 0 lay) s (nth 1 lay) s (nth 2 lay) s (nth 3 lay) s
                      (nth 4 lay) s (nth 5 lay) s (nth 6 lay) s (nth 7 lay) s
                      (nth 8 lay) s (nth 9 lay) s (nth 10 lay)) fp))
          (close fp) T)))))

(defun LXI:find-by-id (master-data mid / result)
  (setq result nil)
  (foreach lay master-data
    (if (= (strcase (car lay)) (strcase mid)) (setq result lay)))
  result)

(defun LXI:find-by-name (master-data lay-name / result)
  (setq result nil)
  (foreach lay master-data
    (if (= (strcase (nth 1 lay)) (strcase lay-name)) (setq result lay)))
  result)

(defun LXI:remove-by-id (master-data mid / )
  (vl-remove-if '(lambda (lay) (= (strcase (car lay)) (strcase mid))) master-data))


;;; ========================================================================
;;; MAPPER (.csv) - 6 Felder (NEU: DwgPath)
;;; DwgName;DwgGUID;DwgPath;LayerName;Handle;MasterID
;;; ========================================================================

(defun LXI:read-mapper ( / sync-dir filepath fp line fields result)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir) nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMapper.csv"))
      (if (not (findfile filepath)) nil
        (progn
          (setq fp (open filepath "r"))
          (if (null fp) nil
            (progn
              (setq result nil)
              (while (setq line (read-line fp))
                (if (and (> (strlen line) 0) (/= (substr line 1 7) "DwgName"))
                  (progn
                    (setq fields (LXI:split-string line *LXI:sep*))
                    (cond
                      ;; 6 Felder = aktuelles Format
                      ((= (length fields) 6)
                        (setq result (cons fields result)))
                      ;; 5 Felder = v0.10 Format (ohne Pfad)
                      ((= (length fields) 5)
                        (setq result
                          (cons (list (nth 0 fields) (nth 1 fields) ""
                                      (nth 2 fields) (nth 3 fields) (nth 4 fields))
                                result)))
                      ;; 4 Felder = altes Format
                      ((= (length fields) 4)
                        (setq result
                          (cons (list (nth 0 fields) "" ""
                                      (nth 1 fields) (nth 2 fields) (nth 3 fields))
                                result)))))))
              (close fp) (reverse result))))))))

(defun LXI:write-mapper (mapper-data / sync-dir filepath fp entry s)
  (setq sync-dir (LXI:get-sync-folder)) (setq s *LXI:sep*)
  (if (null sync-dir) nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMapper.csv"))
      (setq fp (open filepath "w"))
      (if (null fp) nil
        (progn
          (write-line
            (strcat "DwgName" s "DwgGUID" s "DwgPath" s "LayerName" s "Handle" s "MasterID") fp)
          (setq mapper-data (vl-sort mapper-data
            '(lambda (a b)
              (if (= (car a) (car b))
                (< (nth 3 a) (nth 3 b))
                (< (car a) (car b))))))
          (foreach entry mapper-data
            (write-line
              (strcat (nth 0 entry) s (nth 1 entry) s (nth 2 entry) s
                      (nth 3 entry) s (nth 4 entry) s (nth 5 entry)) fp))
          (close fp) T)))))

;;; Mapper-Lookup: GUID + Handle -> MasterID
(defun LXI:mapper-get-mid (mapper-data guid dwg handle / result)
  (setq result nil)
  (if (and guid (/= guid "") (/= guid "NO-GUID"))
    (foreach entry mapper-data
      (if (and (= (strcase (nth 1 entry)) (strcase guid))
               (= (strcase (nth 4 entry)) (strcase handle)))
        (setq result (nth 5 entry)))))
  (if (null result)
    (foreach entry mapper-data
      (if (and (= (strcase (nth 0 entry)) (strcase dwg))
               (= (strcase (nth 4 entry)) (strcase handle)))
        (setq result (nth 5 entry)))))
  result)

;;; Mapper-Eintraege fuer Zeichnung (GUID oder Name), erkennt Umbenennung
(defun LXI:mapper-get-dwg-entries (mapper-data guid dwg / guid-entries old-name)
  (setq guid-entries nil)
  (if (and guid (/= guid "") (/= guid "NO-GUID"))
    (setq guid-entries
      (vl-remove-if-not
        '(lambda (e) (= (strcase (nth 1 e)) (strcase guid)))
        mapper-data)))
  (if guid-entries
    (progn
      (setq old-name (nth 0 (car guid-entries)))
      (if (/= (strcase old-name) (strcase dwg))
        (progn
          (princ (strcat "\n  DWG umbenannt: " old-name " -> " dwg))
          (setq guid-entries
            (mapcar
              '(lambda (e)
                (list dwg (nth 1 e) (nth 2 e) (nth 3 e) (nth 4 e) (nth 5 e)))
              guid-entries))))
      guid-entries)
    (vl-remove-if-not
      '(lambda (e) (= (strcase (car e)) (strcase dwg)))
      mapper-data)))

;;; Entfernt Eintraege (GUID und Name)
(defun LXI:mapper-remove-dwg (mapper-data guid dwg / )
  (vl-remove-if
    '(lambda (entry)
      (or (and guid (/= guid "") (/= guid "NO-GUID")
               (= (strcase (nth 1 entry)) (strcase guid)))
          (= (strcase (car entry)) (strcase dwg))))
    mapper-data))

;;; Gibt eindeutige Zeichnungen aus Mapper zurueck
;;; Rueckgabe: Liste von '("DwgName" "DwgGUID" "DwgPath")
(defun LXI:mapper-get-dwg-list (mapper-data / result dwg-name dwg-guid dwg-path found)
  (setq result nil)
  (foreach entry mapper-data
    (setq dwg-name (nth 0 entry)
          dwg-guid (nth 1 entry)
          dwg-path (nth 2 entry))
    ;; Pruefen ob schon in Liste (nach Name)
    (setq found nil)
    (foreach r result
      (if (= (strcase (car r)) (strcase dwg-name))
        (setq found T)))
    (if (not found)
      (setq result (cons (list dwg-name dwg-guid dwg-path) result))))
  (reverse result))


;;; ========================================================================
;;; HISTORY (.csv) - APPEND ONLY - 6 Felder
;;; ========================================================================

(defun LXI:append-history (entries / sync-dir filepath fp entry s needs-header)
  (setq sync-dir (LXI:get-sync-folder)) (setq s *LXI:sep*)
  (if (null sync-dir) nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerHistory.csv"))
      (setq needs-header (not (findfile filepath)))
      (setq fp (open filepath "a"))
      (if (null fp) nil
        (progn
          (if needs-header
            (write-line (strcat "Datum" s "Aktion" s "LayerName" s "Detail" s "Source" s "MasterID") fp))
          (foreach entry entries
            (write-line (strcat (nth 0 entry) s (nth 1 entry) s (nth 2 entry) s
                                (nth 3 entry) s (nth 4 entry) s (nth 5 entry)) fp))
          (close fp) T)))))

(defun LXI:read-history ( / sync-dir filepath fp line fields result)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir) nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerHistory.csv"))
      (if (not (findfile filepath)) nil
        (progn
          (setq fp (open filepath "r"))
          (if (null fp) nil
            (progn
              (setq result nil)
              (while (setq line (read-line fp))
                (if (and (> (strlen line) 0) (/= (substr line 1 5) "Datum"))
                  (progn
                    (setq fields (LXI:split-string line *LXI:sep*))
                    (if (= (length fields) 6)
                      (setq result (cons fields result))))))
              (close fp) (reverse result))))))))


;;; ========================================================================
;;; LAYER SAMMELN (aktuelle Zeichnung)
;;; ========================================================================

(defun LXI:collect-layers ( / lay-tbl lay-name result ent-data
                              col ltype lw plot-flag on-off frz lck handle)
  (while (setq lay-tbl (tblnext "LAYER" (not lay-tbl)))
    (setq lay-name (cdr (assoc 2 lay-tbl)))
    (if (and (not (LXI:xref-layer-p lay-name))
             (LXI:sync-layer-p lay-name))
      (progn
        (setq ent-data (entget (tblobjname "LAYER" lay-name)))
        (setq handle (cdr (assoc 5 ent-data)))
        (if (null handle) (setq handle "0"))
        (setq col (cdr (assoc 62 ent-data)))
        (if (null col) (setq col 7))
        (setq on-off (if (< col 0) "OFF" "ON"))
        (setq col (abs col))
        (setq ltype (cdr (assoc 6 ent-data)))
        (if (null ltype) (setq ltype "Continuous"))
        (setq frz (cdr (assoc 70 ent-data)))
        (if (null frz) (setq frz 0))
        (setq lck frz)
        (setq frz (if (= (logand frz 1) 1) "FROZEN" "THAWED"))
        (setq lck (if (= (logand lck 4) 4) "LOCKED" "UNLOCKED"))
        (setq lw "Default")
        (setq plot-flag (cdr (assoc 290 ent-data)))
        (setq plot-flag (if (or (null plot-flag) (= plot-flag 1)) "PLOT" "NOPLOT"))
        (LXI:debug-print (strcat "Gefunden: " lay-name " [" handle "] Farbe=" (itoa col)))
        (setq result
          (cons (list lay-name (itoa col) ltype lw plot-flag on-off frz lck handle) result)))))
  (if result (vl-sort result '(lambda (a b) (< (car a) (car b))))))

(defun LXI:compare-field (old-val new-val / )
  (if (/= (strcase old-val) (strcase new-val))
    (strcat old-val "->" new-val) nil))


;;; ========================================================================
;;; LINIENTYP LADEN
;;; ========================================================================

(defun LXI:ensure-linetype (ltype / lin-file)
  (if (or (= (strcase ltype) "CONTINUOUS") (tblsearch "LTYPE" ltype))
    ltype
    (progn
      (LXI:debug-print (strcat "  Linientyp \"" ltype "\" fehlt, lade..."))
      (setq lin-file (findfile "acadiso.lin"))
      (if lin-file
        (progn
          (vl-catch-all-apply
            '(lambda () (command "._-LINETYPE" "L" ltype lin-file "")))
          (if (tblsearch "LTYPE" ltype)
            (progn (princ (strcat "\n  Linientyp \"" ltype "\" geladen.")) ltype)
            (LXI:load-linetype-dialog ltype)))
        (LXI:load-linetype-dialog ltype)))))

(defun LXI:load-linetype-dialog (ltype / lin-file)
  (princ (strcat "\n  Bitte .lin-Datei fuer \"" ltype "\" waehlen:"))
  (setq lin-file (getfiled (strcat "LIN-Datei fuer \"" ltype "\"") "" "lin" 4))
  (if lin-file
    (progn
      (vl-catch-all-apply
        '(lambda () (command "._-LINETYPE" "L" ltype lin-file "")))
      (if (tblsearch "LTYPE" ltype)
        (progn (princ (strcat "\n  Linientyp \"" ltype "\" geladen.")) ltype)
        (progn (princ (strcat "\n  *** \"" ltype "\" nicht ladbar. Continuous.")) "Continuous")))
    (progn (princ (strcat "\n  *** Abbruch. Continuous fuer \"" ltype "\".")) "Continuous")))


;;; ========================================================================
;;; IMPORT HILFSFUNKTIONEN
;;; ========================================================================

(defun LXI:find-local-by-handle (handle / lay-tbl ent-data lay-handle found)
  (setq found nil)
  (while (and (setq lay-tbl (tblnext "LAYER" (not lay-tbl))) (null found))
    (setq ent-data (entget (tblobjname "LAYER" (cdr (assoc 2 lay-tbl)))))
    (setq lay-handle (cdr (assoc 5 ent-data)))
    (if (and lay-handle (= (strcase lay-handle) (strcase handle)))
      (setq found (cdr (assoc 2 lay-tbl)))))
  found)

(defun LXI:create-layer (lay-name col ltype plot-flag on-off frz lck / new-col)
  (setq ltype (LXI:ensure-linetype ltype))
  (setq new-col (if (= on-off "OFF") (- col) col))
  (if (entmake
        (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
              '(100 . "AcDbLayerTableRecord")
              (cons 2 lay-name) (cons 62 new-col) (cons 6 ltype) '(370 . -3)
              (cons 290 (if (= plot-flag "PLOT") 1 0))
              (cons 70 (+ (if (= frz "FROZEN") 1 0) (if (= lck "LOCKED") 4 0)))))
    T nil))

(defun LXI:update-layer-props (lay-name col ltype plot-flag on-off / ent-data new-col)
  (setq ent-data (entget (tblobjname "LAYER" lay-name)))
  (if (null ent-data) nil
    (progn
      (setq new-col (if (= on-off "OFF") (- col) col))
      (setq ent-data (subst (cons 62 new-col) (assoc 62 ent-data) ent-data))
      (setq ltype (LXI:ensure-linetype ltype))
      (if (and (/= (strcase ltype) "CONTINUOUS") (assoc 6 ent-data))
        (setq ent-data (subst (cons 6 ltype) (assoc 6 ent-data) ent-data)))
      (if (assoc 290 ent-data)
        (setq ent-data (subst (cons 290 (if (= plot-flag "PLOT") 1 0))
                              (assoc 290 ent-data) ent-data)))
      (entmod ent-data) T)))

(defun LXI:compare-layer-props (lay-name col ltype plot-flag on-off
                                 / ent-data diffs local-col local-ltype
                                   local-plot local-onoff)
  (setq ent-data (entget (tblobjname "LAYER" lay-name)))
  (if (null ent-data) nil
    (progn
      (setq diffs nil)
      (setq local-col (cdr (assoc 62 ent-data)))
      (if (null local-col) (setq local-col 7))
      (setq local-onoff (if (< local-col 0) "OFF" "ON"))
      (setq local-col (abs local-col))
      (if (/= local-col col)
        (setq diffs (cons (strcat "  Farbe:     Master=" (itoa col) "  Lokal=" (itoa local-col)) diffs)))
      (if (/= (strcase local-onoff) (strcase on-off))
        (setq diffs (cons (strcat "  OnOff:     Master=" on-off "  Lokal=" local-onoff) diffs)))
      (setq local-ltype (cdr (assoc 6 ent-data)))
      (if (null local-ltype) (setq local-ltype "Continuous"))
      (if (/= (strcase local-ltype) (strcase ltype))
        (setq diffs (cons (strcat "  Linientyp: Master=" ltype "  Lokal=" local-ltype) diffs)))
      (setq local-plot (cdr (assoc 290 ent-data)))
      (if (null local-plot) (setq local-plot 1))
      (if (/= local-plot (if (= plot-flag "PLOT") 1 0))
        (setq diffs (cons (strcat "  Plot:      Master=" plot-flag
                                  "  Lokal=" (if (= local-plot 1) "PLOT" "NOPLOT")) diffs)))
      (if diffs (reverse diffs) nil))))

(defun LXI:ask-conflict (lay-name diffs / choice)
  (princ (strcat "\n\n========================================"))
  (princ (strcat "\n  KONFLIKT: " lay-name))
  (princ "\n  Unterschiede zwischen Master und dieser Zeichnung:")
  (foreach d diffs (princ (strcat "\n" d)))
  (princ "\n\n  Master     = Wert aus Master uebernehmen")
  (princ "\n  Lokal      = Lokalen Wert behalten")
  (princ "\n  alleMaster = Master fuer ALLE weiteren Konflikte")
  (princ "\n  alleLokal  = Lokal fuer ALLE weiteren Konflikte")
  (initget "Master Lokal alleMaster alleLokal")
  (setq choice (getkword "\nEntscheidung [Master/Lokal/alleMaster/alleLokal]: "))
  (if (null choice) "Lokal" choice))

(defun LXI:ask-deleted (lay-name mid / choice confirm)
  (princ (strcat "\n\n========================================"))
  (princ (strcat "\n  FEHLEND: " lay-name " [" mid "]"))
  (princ "\n  Layer im Master, aber lokal geloescht.")
  (princ "\n\n  Neu       = Layer wieder anlegen (aus Master)")
  (princ "\n  Ignorieren = Nichts tun")
  (princ "\n  Loeschen  = Aus Master entfernen!")
  (initget "Neu Ignorieren Loeschen")
  (setq choice (getkword "\nEntscheidung [Neu/Ignorieren/Loeschen]: "))
  (if (null choice) (setq choice "Ignorieren"))
  (if (= choice "Loeschen")
    (progn
      (princ (strcat "\n  !!! " lay-name " wird aus Master entfernt!"))
      (initget "Ja Nein")
      (setq confirm (getkword "\n  Wirklich? [Ja/Nein]: "))
      (if (= confirm "Ja") "Loeschen" "Ignorieren"))
    choice))

(defun LXI:ask-rename (master-name local-name mid / choice)
  (princ (strcat "\n\n========================================"))
  (princ (strcat "\n  UMBENENNUNG erkannt: [" mid "]"))
  (princ (strcat "\n  Master: " master-name))
  (princ (strcat "\n  Lokal:  " local-name))
  (princ "\n\n  Master = Lokal auf Master-Name umbenennen")
  (princ "\n  Lokal  = Lokalen Namen behalten")
  (initget "Master Lokal")
  (setq choice (getkword "\nEntscheidung [Master/Lokal]: "))
  (if (null choice) "Master" choice))


;;; ========================================================================
;;; EXPORT-KERNFUNKTION
;;; ========================================================================
(defun LXI:do-export ( / dwg guid dwg-path layers master-data mapper-data
                         lay lay-name handle mid old-name
                         existing-master change-details detail
                         timestamp history-entries new-mid
                         cnt-new cnt-upd cnt-ren)
  (setq dwg (LXI:dwg-name))
  (setq guid (LXI:dwg-guid))
  (setq dwg-path (LXI:dwg-path))
  (setq timestamp (LXI:timestamp))
  (setq cnt-new 0 cnt-upd 0 cnt-ren 0)
  (setq history-entries nil)
  (LXI:debug-print (strcat "Export: " dwg " GUID: " guid))
  (setq layers (LXI:collect-layers))
  (if (null layers)
    (progn
      (princ (strcat "\n  Export: Keine " *LXI:prefix* "* Layer gefunden."))
      nil)
    (progn
      (setq master-data (LXI:read-master))
      (if (null master-data) (setq master-data nil))
      (setq mapper-data (LXI:read-mapper))
      (if (null mapper-data) (setq mapper-data nil))
      (foreach lay layers
        (setq lay-name (nth 0 lay) handle (nth 8 lay))
        (setq mid (LXI:mapper-get-mid mapper-data guid dwg handle))
        (cond
          ;; FALL 1: Bekannter Layer
          (mid
            (progn
              (setq existing-master (LXI:find-by-id master-data mid))
              (if existing-master
                (progn
                  (setq old-name (nth 1 existing-master))
                  (if (/= (strcase old-name) (strcase lay-name))
                    (progn
                      (princ (strcat "\n  > Umbenennung: " old-name " -> " lay-name))
                      (setq history-entries
                        (cons (list timestamp "UMBENENNUNG" lay-name
                                    (strcat old-name "->" lay-name) dwg mid)
                              history-entries))
                      (setq cnt-ren (1+ cnt-ren))))
                  ;; Aenderungen pruefen
                  (setq change-details nil)
                  (setq detail (LXI:compare-field (nth 2 existing-master) (nth 1 lay)))
                  (if detail (setq change-details (cons (strcat "Farbe:" detail) change-details)))
                  (if (and (/= (strcase (nth 2 lay)) "CONTINUOUS")
                           (LXI:compare-field (nth 3 existing-master) (nth 2 lay)))
                    (setq change-details
                      (cons (strcat "Linientyp:" (LXI:compare-field (nth 3 existing-master) (nth 2 lay)))
                            change-details)))
                  (setq detail (LXI:compare-field (nth 6 existing-master) (nth 5 lay)))
                  (if detail (setq change-details (cons (strcat "OnOff:" detail) change-details)))
                  (setq detail (LXI:compare-field (nth 5 existing-master) (nth 4 lay)))
                  (if detail (setq change-details (cons (strcat "Plot:" detail) change-details)))
                  (if change-details
                    (progn
                      (setq history-entries
                        (cons (list timestamp "AENDERUNG" lay-name
                                    (apply 'strcat (mapcar '(lambda (d) (strcat d " "))
                                                           (reverse change-details)))
                                    dwg mid) history-entries))
                      (setq cnt-upd (1+ cnt-upd))))
                  ;; Master aktualisieren (Linientyp-Schutz)
                  (setq master-data (LXI:remove-by-id master-data mid))
                  (setq master-data
                    (cons (list mid lay-name (nth 1 lay)
                                (if (and (= (strcase (nth 2 lay)) "CONTINUOUS")
                                         (/= (strcase (nth 3 existing-master)) "CONTINUOUS"))
                                  (nth 3 existing-master) (nth 2 lay))
                                (nth 3 lay) (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                                dwg timestamp) master-data))))))
          ;; FALL 2: Name-Match
          ((setq existing-master (LXI:find-by-name master-data lay-name))
            (progn
              (setq mid (car existing-master))
              (setq master-data (LXI:remove-by-id master-data mid))
              (setq master-data
                (cons (list mid lay-name (nth 1 lay) (nth 2 lay) (nth 3 lay)
                            (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                            dwg timestamp) master-data))
              (setq cnt-upd (1+ cnt-upd))))
          ;; FALL 3: Neuer Layer
          (T
            (progn
              (setq new-mid (LXI:next-master-id master-data))
              (setq master-data
                (cons (list new-mid lay-name (nth 1 lay) (nth 2 lay) (nth 3 lay)
                            (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                            dwg timestamp) master-data))
              (setq history-entries
                (cons (list timestamp "NEU" lay-name "" dwg new-mid) history-entries))
              (setq cnt-new (1+ cnt-new))))))
      ;; Mapper mit Pfad
      (setq mapper-data (LXI:mapper-remove-dwg mapper-data guid dwg))
      (foreach lay layers
        (setq lay-name (nth 0 lay) handle (nth 8 lay))
        (setq mid (car (LXI:find-by-name master-data lay-name)))
        (if mid (setq mapper-data
          (cons (list dwg guid dwg-path lay-name handle mid) mapper-data))))
      (if (and (LXI:write-master master-data) (LXI:write-mapper mapper-data))
        (progn
          (if history-entries (LXI:append-history (reverse history-entries)))
          (princ (strcat "\n  --- Export (" dwg ") ---"))
          (if (> cnt-new 0) (princ (strcat "\n    + " (itoa cnt-new) " neu in Master")))
          (if (> cnt-upd 0) (princ (strcat "\n    ~ " (itoa cnt-upd) " aktualisiert")))
          (if (> cnt-ren 0) (princ (strcat "\n    > " (itoa cnt-ren) " umbenannt")))
          (if (and (= cnt-new 0) (= cnt-upd 0) (= cnt-ren 0))
            (princ "\n    = Master ist aktuell"))
          (princ (strcat "\n    Master gesamt: " (itoa (length master-data)) " Layer"))
          T)
        (progn (princ "\n  *** Fehler beim Schreiben.") nil)))))


;;; ========================================================================
;;; IMPORT-KERNFUNKTION
;;; ========================================================================
(defun LXI:do-import ( / dwg guid dwg-path master-data mapper-data dwg-mapper
                         is-first-import global-choice
                         lay mid master-name col ltype lw plot-flag on-off frz lck
                         mapped-entry mapped-handle mapped-name
                         local-name diffs choice
                         lay-tbl handle new-mapper ent-data delete-list
                         cnt-new cnt-upd cnt-skip cnt-ren cnt-del)
  (setq dwg (LXI:dwg-name))
  (setq guid (LXI:dwg-guid))
  (setq dwg-path (LXI:dwg-path))
  (setq cnt-new 0 cnt-upd 0 cnt-skip 0 cnt-ren 0 cnt-del 0)
  (setq global-choice nil delete-list nil)
  (setq master-data (LXI:read-master))
  (if (null master-data)
    (progn (princ "\n  Import: Kein Master gefunden.") nil)
    (progn
      (princ (strcat "\n  " (itoa (length master-data)) " Layer im Master."))
      (setq mapper-data (LXI:read-mapper))
      (if (null mapper-data) (setq mapper-data nil))
      (setq dwg-mapper (LXI:mapper-get-dwg-entries mapper-data guid dwg))
      (setq is-first-import (null dwg-mapper))
      (if is-first-import
        (princ "\n  Erster Import fuer diese Zeichnung.")
        (princ (strcat "\n  " (itoa (length dwg-mapper)) " Layer bekannt.")))
      (foreach lay master-data
        (setq mid (nth 0 lay) master-name (nth 1 lay)
              col (atoi (nth 2 lay)) ltype (nth 3 lay) lw (nth 4 lay)
              plot-flag (nth 5 lay) on-off (nth 6 lay) frz (nth 7 lay) lck (nth 8 lay))
        (LXI:debug-print (strcat "Import: " master-name " [" mid "]"))
        (setq mapped-entry nil)
        (foreach e dwg-mapper
          (if (= (strcase (nth 5 e)) (strcase mid)) (setq mapped-entry e)))
        (cond
          ;; FALL A: Im Mapper
          (mapped-entry
            (progn
              (setq mapped-handle (nth 4 mapped-entry)
                    mapped-name (nth 3 mapped-entry))
              (setq local-name (LXI:find-local-by-handle mapped-handle))
              (cond
                (local-name
                  (progn
                    (LXI:debug-print (strcat "  Handle " mapped-handle " -> " local-name))
                    (cond
                      ((= (strcase local-name) (strcase master-name))
                        (progn
                          (setq diffs (LXI:compare-layer-props local-name col ltype plot-flag on-off))
                          (if diffs
                            (progn
                              (if (or (= global-choice "alleMaster") (= global-choice "alleLokal"))
                                (setq choice global-choice)
                                (progn
                                  (setq choice (LXI:ask-conflict local-name diffs))
                                  (if (= choice "alleMaster") (setq global-choice "alleMaster"))
                                  (if (= choice "alleLokal") (setq global-choice "alleLokal"))))
                              (if (or (= choice "Master") (= choice "alleMaster"))
                                (progn (LXI:update-layer-props local-name col ltype plot-flag on-off)
                                       (setq cnt-upd (1+ cnt-upd)))
                                (setq cnt-skip (1+ cnt-skip))))
                            (progn
                              (LXI:debug-print (strcat "  Skip: " local-name))
                              (setq cnt-skip (1+ cnt-skip))))))
                      (T ;; Umbenennung
                        (progn
                          (setq choice (LXI:ask-rename master-name local-name mid))
                          (if (= choice "Master")
                            (progn
                              (command "._-RENAME" "LA" local-name master-name)
                              (princ (strcat "\n  > " local-name " -> " master-name))
                              (LXI:update-layer-props master-name col ltype plot-flag on-off)
                              (setq cnt-ren (1+ cnt-ren)))
                            (progn
                              (princ (strcat "\n  = Beibehalten: " local-name))
                              (setq cnt-skip (1+ cnt-skip)))))))))
                (T ;; Lokal geloescht
                  (progn
                    (LXI:debug-print (strcat "  Handle " mapped-handle " nicht gefunden"))
                    (setq choice (LXI:ask-deleted master-name mid))
                    (cond
                      ((= choice "Neu")
                        (if (LXI:create-layer master-name col ltype plot-flag on-off frz lck)
                          (progn (princ (strcat "\n  + " master-name)) (setq cnt-new (1+ cnt-new)))
                          (princ (strcat "\n  *** Fehler: " master-name))))
                      ((= choice "Loeschen")
                        (setq delete-list (cons mid delete-list) cnt-del (1+ cnt-del)))
                      (T (setq cnt-skip (1+ cnt-skip)))))))))
          ;; FALL B: Nicht im Mapper
          (T
            (progn
              (LXI:debug-print (strcat "  Neuer Layer: " master-name))
              (if (tblsearch "LAYER" master-name)
                (progn
                  (LXI:debug-print "  Name lokal vorhanden, verknuepfe")
                  (setq diffs (LXI:compare-layer-props master-name col ltype plot-flag on-off))
                  (if diffs
                    (progn
                      (if (or (= global-choice "alleMaster") (= global-choice "alleLokal"))
                        (setq choice global-choice)
                        (progn
                          (setq choice (LXI:ask-conflict master-name diffs))
                          (if (= choice "alleMaster") (setq global-choice "alleMaster"))
                          (if (= choice "alleLokal") (setq global-choice "alleLokal"))))
                      (if (or (= choice "Master") (= choice "alleMaster"))
                        (progn (LXI:update-layer-props master-name col ltype plot-flag on-off)
                               (setq cnt-upd (1+ cnt-upd)))
                        (setq cnt-skip (1+ cnt-skip))))
                    (setq cnt-skip (1+ cnt-skip))))
                (if (LXI:create-layer master-name col ltype plot-flag on-off frz lck)
                  (progn (LXI:debug-print (strcat "  + " master-name))
                         (setq cnt-new (1+ cnt-new)))
                  (princ (strcat "\n  *** Fehler: " master-name))))))))
      ;; Loeschen
      (if delete-list
        (progn
          (foreach del-mid delete-list
            (setq master-data (LXI:remove-by-id master-data del-mid)))
          (LXI:write-master master-data)))
      ;; Mapper mit Pfad
      (setq mapper-data (LXI:mapper-remove-dwg mapper-data guid dwg))
      (setq new-mapper nil)
      (while (setq lay-tbl (tblnext "LAYER" (not lay-tbl)))
        (setq lay-name (cdr (assoc 2 lay-tbl)))
        (if (and (not (LXI:xref-layer-p lay-name)) (LXI:sync-layer-p lay-name))
          (progn
            (setq ent-data (entget (tblobjname "LAYER" lay-name)))
            (setq handle (cdr (assoc 5 ent-data)))
            (setq mid (car (LXI:find-by-name master-data lay-name)))
            (if mid (setq new-mapper
              (cons (list dwg guid dwg-path lay-name handle mid) new-mapper))))))
      (setq mapper-data (append mapper-data new-mapper))
      (LXI:write-mapper mapper-data)
      ;; Ergebnis
      (princ (strcat "\n  --- Import (" dwg ") ---"))
      (if (> cnt-new 0) (princ (strcat "\n    + " (itoa cnt-new) " neu angelegt")))
      (if (> cnt-upd 0) (princ (strcat "\n    ~ " (itoa cnt-upd) " aktualisiert")))
      (if (> cnt-ren 0) (princ (strcat "\n    > " (itoa cnt-ren) " umbenannt")))
      (if (> cnt-del 0) (princ (strcat "\n    - " (itoa cnt-del) " aus Master gel.")))
      (if (and (= cnt-new 0) (= cnt-upd 0) (= cnt-ren 0) (= cnt-del 0))
        (princ (strcat "\n    = Synchron (" (itoa cnt-skip) " Layer)")))
      T)))


;;; ========================================================================
;;; BATCH-SYNC FUNKTIONEN (Documents + ObjectDBX)
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Prueft ob eine DWG gerade in AutoCAD geoeffnet ist
;;; Rueckgabe: VLA Document-Objekt oder nil
;;; ------------------------------------------------------------------------
(defun LXI:find-open-document (dwg-name / docs doc found result)
  (setq docs (vla-get-Documents (vlax-get-acad-object)))
  (setq found nil result nil)
  (vlax-for doc docs
    (if (and (null found)
             (= (strcase (vla-get-Name doc)) (strcase dwg-name)))
      (progn (setq result doc found T))))
  result)


;;; ------------------------------------------------------------------------
;;; Liest GUID aus einer geoeffneten Zeichnung (SummaryInfo)
;;; Rueckgabe: GUID-String oder ""
;;; ------------------------------------------------------------------------
(defun LXI:doc-get-guid (doc / si num-props i key val guid found)
  (setq guid "" found nil)
  (setq si (vl-catch-all-apply 'vla-get-SummaryInfo (list doc)))
  (if (and si (not (vl-catch-all-error-p si)))
    (progn
      (setq num-props
        (vl-catch-all-apply 'vla-NumCustomInfo (list si)))
      (if (and (not (vl-catch-all-error-p num-props)) (> num-props 0))
        (progn
          (setq i 0)
          (while (and (< i num-props) (null found))
            (setq key (vlax-make-variant "" vlax-vbString))
            (setq val (vlax-make-variant "" vlax-vbString))
            (vl-catch-all-apply
              '(lambda ()
                (vla-GetCustomByIndex si i 'key 'val)
                (if (= (strcase (vlax-variant-value key)) "LAYERSYNCGUID")
                  (progn
                    (setq guid (vlax-variant-value val))
                    (setq found T)))))
            (setq i (1+ i)))))))
  guid)


;;; ------------------------------------------------------------------------
;;; Oeffnet eine DWG via ObjectDBX (nur fuer geschlossene Dateien!)
;;; Rueckgabe: DBX-Document Object oder nil bei Fehler
;;; ------------------------------------------------------------------------
(defun LXI:dbx-open (fullpath / dbx-doc acad-ver prog-id open-result)
  (if (not (findfile fullpath))
    (progn (LXI:debug-print (strcat "  DBX: Nicht gefunden: " fullpath)) nil)
    (progn
      (setq acad-ver (substr (getvar "ACADVER") 1 2))
      (setq prog-id (strcat "ObjectDBX.AxDbDocument." acad-ver))
      (setq dbx-doc
        (vl-catch-all-apply 'vlax-create-object (list prog-id)))
      (if (vl-catch-all-error-p dbx-doc)
        (progn (princ "\n  *** ObjectDBX nicht verfuegbar.") nil)
        (progn
          (setq open-result
            (vl-catch-all-apply 'vla-Open (list dbx-doc fullpath)))
          (if (vl-catch-all-error-p open-result)
            (progn
              (LXI:debug-print
                (strcat "  DBX: Kann nicht oeffnen (gesperrt?): " fullpath))
              (vlax-release-object dbx-doc)
              nil)
            dbx-doc))))))


;;; ------------------------------------------------------------------------
;;; Synced Layer in einer geoeffneten Zeichnung (Documents-Collection)
;;; Master gewinnt, Konflikte werden gesammelt
;;; Entfernt/deaktiviert Layer die nicht mehr im Master sind
;;; Rueckgabe: Liste '(cnt-new cnt-upd cnt-skip conflicts cnt-del del-info)
;;; del-info = Liste von '("LayerName" "geloescht"|"OFF")
;;; ------------------------------------------------------------------------
(defun LXI:doc-sync-layers (doc master-data / layers-coll lay-obj
                              lay master-name col ltype plot-flag on-off
                              local-col local-onoff local-plot
                              cnt-new cnt-upd cnt-skip conflicts
                              cnt-del del-info
                              master-names lay-name del-result ss)
  (setq cnt-new 0 cnt-upd 0 cnt-skip 0 cnt-del 0 conflicts nil del-info nil)
  (setq layers-coll (vla-get-Layers doc))
  
  ;; Master-Layernamen sammeln (fuer Loeschpruefung)
  (setq master-names nil)
  (foreach lay master-data
    (setq master-names (cons (strcase (nth 1 lay)) master-names)))
  
  ;; 1) Layer anlegen/aktualisieren
  (foreach lay master-data
    (setq master-name (nth 1 lay) col (atoi (nth 2 lay))
          ltype (nth 3 lay) plot-flag (nth 5 lay) on-off (nth 6 lay))
    (setq lay-obj
      (vl-catch-all-apply 'vla-Item (list layers-coll master-name)))
    (if (vl-catch-all-error-p lay-obj)
      ;; Neuer Layer
      (progn
        (setq lay-obj
          (vl-catch-all-apply 'vla-Add (list layers-coll master-name)))
        (if (not (vl-catch-all-error-p lay-obj))
          (progn
            (vl-catch-all-apply 'vla-put-Color (list lay-obj col))
            (vl-catch-all-apply 'vla-put-Linetype (list lay-obj ltype))
            (vla-put-LayerOn lay-obj (if (= on-off "ON") :vlax-true :vlax-false))
            (vla-put-Plottable lay-obj (if (= plot-flag "PLOT") :vlax-true :vlax-false))
            (setq cnt-new (1+ cnt-new)))))
      ;; Existiert: vergleichen
      (progn
        (setq local-col (abs (vla-get-Color lay-obj)))
        (setq local-onoff (if (= (vla-get-LayerOn lay-obj) :vlax-true) "ON" "OFF"))
        (setq local-plot (if (= (vla-get-Plottable lay-obj) :vlax-true) "PLOT" "NOPLOT"))
        (if (or (/= local-col col)
                (/= (strcase local-onoff) (strcase on-off))
                (/= (strcase local-plot) (strcase plot-flag)))
          (progn
            (if (/= local-col col)
              (setq conflicts (cons (list master-name "Farbe" (itoa col) (itoa local-col)) conflicts)))
            (if (/= (strcase local-onoff) (strcase on-off))
              (setq conflicts (cons (list master-name "OnOff" on-off local-onoff) conflicts)))
            (if (/= (strcase local-plot) (strcase plot-flag))
              (setq conflicts (cons (list master-name "Plot" plot-flag local-plot) conflicts)))
            (vla-put-Color lay-obj col)
            (vla-put-LayerOn lay-obj (if (= on-off "ON") :vlax-true :vlax-false))
            (vla-put-Plottable lay-obj (if (= plot-flag "PLOT") :vlax-true :vlax-false))
            (setq cnt-upd (1+ cnt-upd)))
          (setq cnt-skip (1+ cnt-skip))))))
  
  ;; 2) Layer entfernen die nicht mehr im Master sind
  (vlax-for lay-obj layers-coll
    (setq lay-name (vla-get-Name lay-obj))
    (if (and (LXI:sync-layer-p lay-name)
             (not (LXI:xref-layer-p lay-name))
             (not (member (strcase lay-name) master-names)))
      (progn
        ;; Versuche zu loeschen
        (setq del-result
          (vl-catch-all-apply 'vla-Delete (list lay-obj)))
        (if (vl-catch-all-error-p del-result)
          ;; Loeschen fehlgeschlagen (Objekte drauf) -> OFF setzen
          (progn
            (vl-catch-all-apply 'vla-put-LayerOn (list lay-obj :vlax-false))
            (setq del-info (cons (list lay-name "OFF") del-info))
            (setq cnt-del (1+ cnt-del)))
          ;; Erfolgreich geloescht
          (progn
            (setq del-info (cons (list lay-name "geloescht") del-info))
            (setq cnt-del (1+ cnt-del)))))))
  
  (list cnt-new cnt-upd cnt-skip conflicts cnt-del del-info))


;;; ------------------------------------------------------------------------
;;; Aktualisiert Mapper fuer eine geoeffnete Zeichnung
;;; ------------------------------------------------------------------------
(defun LXI:doc-update-mapper (doc dwg-name dwg-guid dwg-path
                               master-data mapper-data
                               / layers-coll lay-obj lay-name handle mid
                                 new-entries)
  (setq mapper-data (LXI:mapper-remove-dwg mapper-data dwg-guid dwg-name))
  (setq new-entries nil)
  (setq layers-coll (vla-get-Layers doc))
  (vlax-for lay-obj layers-coll
    (setq lay-name (vla-get-Name lay-obj))
    (if (and (not (LXI:xref-layer-p lay-name)) (LXI:sync-layer-p lay-name))
      (progn
        (setq handle (vla-get-Handle lay-obj))
        (setq mid (car (LXI:find-by-name master-data lay-name)))
        (if mid
          (setq new-entries
            (cons (list dwg-name dwg-guid dwg-path lay-name handle mid)
                  new-entries))))))
  (append mapper-data new-entries))


;;; ------------------------------------------------------------------------
;;; Synced Layer in einer DBX-Zeichnung (geschlossen)
;;; Layer die nicht im Master sind werden auf OFF gesetzt (kein Loeschen)
;;; Rueckgabe: Liste '(cnt-new cnt-upd cnt-skip conflicts cnt-del del-info)
;;; ------------------------------------------------------------------------
(defun LXI:dbx-sync-layers (dbx-doc master-data / layers-coll lay-obj
                              lay master-name col ltype plot-flag on-off
                              local-col local-ltype local-onoff local-plot
                              cnt-new cnt-upd cnt-skip conflicts
                              cnt-del del-info master-names lay-name)
  (setq cnt-new 0 cnt-upd 0 cnt-skip 0 cnt-del 0 conflicts nil del-info nil)
  (setq layers-coll (vla-get-Layers dbx-doc))
  
  ;; Master-Layernamen sammeln
  (setq master-names nil)
  (foreach lay master-data
    (setq master-names (cons (strcase (nth 1 lay)) master-names)))
  
  ;; 1) Layer anlegen/aktualisieren
  (foreach lay master-data
    (setq master-name (nth 1 lay) col (atoi (nth 2 lay))
          ltype (nth 3 lay) plot-flag (nth 5 lay) on-off (nth 6 lay))
    (setq lay-obj
      (vl-catch-all-apply 'vla-Item (list layers-coll master-name)))
    (if (vl-catch-all-error-p lay-obj)
      (progn
        (setq lay-obj
          (vl-catch-all-apply 'vla-Add (list layers-coll master-name)))
        (if (not (vl-catch-all-error-p lay-obj))
          (progn
            (vl-catch-all-apply 'vla-put-Color (list lay-obj col))
            (vl-catch-all-apply 'vla-put-Linetype (list lay-obj ltype))
            (vla-put-LayerOn lay-obj (if (= on-off "ON") :vlax-true :vlax-false))
            (vla-put-Plottable lay-obj (if (= plot-flag "PLOT") :vlax-true :vlax-false))
            (setq cnt-new (1+ cnt-new)))))
      (progn
        (setq local-col (abs (vla-get-Color lay-obj)))
        (setq local-onoff (if (= (vla-get-LayerOn lay-obj) :vlax-true) "ON" "OFF"))
        (setq local-plot (if (= (vla-get-Plottable lay-obj) :vlax-true) "PLOT" "NOPLOT"))
        (if (or (/= local-col col)
                (/= (strcase local-onoff) (strcase on-off))
                (/= (strcase local-plot) (strcase plot-flag)))
          (progn
            (if (/= local-col col)
              (setq conflicts (cons (list master-name "Farbe" (itoa col) (itoa local-col)) conflicts)))
            (if (/= (strcase local-onoff) (strcase on-off))
              (setq conflicts (cons (list master-name "OnOff" on-off local-onoff) conflicts)))
            (if (/= (strcase local-plot) (strcase plot-flag))
              (setq conflicts (cons (list master-name "Plot" plot-flag local-plot) conflicts)))
            (vla-put-Color lay-obj col)
            (vla-put-LayerOn lay-obj (if (= on-off "ON") :vlax-true :vlax-false))
            (vla-put-Plottable lay-obj (if (= plot-flag "PLOT") :vlax-true :vlax-false))
            (setq cnt-upd (1+ cnt-upd)))
          (setq cnt-skip (1+ cnt-skip))))))
  
  ;; 2) Layer auf OFF setzen die nicht mehr im Master sind
  (vlax-for lay-obj layers-coll
    (setq lay-name (vla-get-Name lay-obj))
    (if (and (LXI:sync-layer-p lay-name)
             (not (LXI:xref-layer-p lay-name))
             (not (member (strcase lay-name) master-names)))
      (progn
        (vl-catch-all-apply 'vla-put-LayerOn (list lay-obj :vlax-false))
        (setq del-info (cons (list lay-name "OFF") del-info))
        (setq cnt-del (1+ cnt-del)))))
  
  (list cnt-new cnt-upd cnt-skip conflicts cnt-del del-info))


;;; ------------------------------------------------------------------------
;;; Aktualisiert Mapper-Eintraege fuer eine DBX-Zeichnung
;;; ------------------------------------------------------------------------
(defun LXI:dbx-update-mapper (dbx-doc dwg-name dwg-guid dwg-path
                               master-data mapper-data
                               / layers-coll lay-obj lay-name handle mid
                                 new-entries)
  (setq mapper-data (LXI:mapper-remove-dwg mapper-data dwg-guid dwg-name))
  (setq new-entries nil)
  (setq layers-coll (vla-get-Layers dbx-doc))
  
  (vlax-for lay-obj layers-coll
    (setq lay-name (vla-get-Name lay-obj))
    (if (and (not (LXI:xref-layer-p lay-name))
             (LXI:sync-layer-p lay-name))
      (progn
        (setq handle (vla-get-Handle lay-obj))
        (setq mid (car (LXI:find-by-name master-data lay-name)))
        (if mid
          (setq new-entries
            (cons (list dwg-name dwg-guid dwg-path lay-name handle mid)
                  new-entries))))))
  
  (append mapper-data new-entries))


;;; ========================================================================
;;; Hauptbefehl: LAYSYNCALL
;;; Geoeffnete DWGs via Documents, geschlossene via ObjectDBX
;;; ========================================================================
(defun c:LAYSYNCALL ( / *error* old-cmdecho
                        master-data mapper-data dwg-list
                        dwg-entry dwg-name dwg-guid dwg-path fullpath
                        open-doc dbx-doc result current-dwg
                        all-conflicts all-del-info total-new total-upd total-skip total-del
                        cnt cnt-open cnt-dbx cnt-err)
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg)))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (setq current-dwg (LXI:dwg-name))
  
  (princ "\n\n========================================")
  (princ "\n  LAYSYNCALL - Batch-Synchronisation")
  (princ "\n========================================")
  
  ;; Zuerst: Aktuelle Zeichnung normal syncen
  (princ (strcat "\n\n>> Aktuelle Zeichnung: " current-dwg))
  (LXI:do-import)
  (LXI:do-export)
  
  ;; Master und Mapper neu lesen
  (setq master-data (LXI:read-master))
  (setq mapper-data (LXI:read-mapper))
  
  (if (null master-data)
    (princ "\n*** Kein Master vorhanden.")
    (progn
      (setq dwg-list (LXI:mapper-get-dwg-list mapper-data))
      (setq all-conflicts nil all-del-info nil
            total-new 0 total-upd 0 total-skip 0 total-del 0
            cnt 0 cnt-open 0 cnt-dbx 0 cnt-err 0)
      
      (princ (strcat "\n\n>> " (itoa (length dwg-list)) " Zeichnungen registriert."))
      (princ "\n   [O]=Offen  [D]=ObjectDBX  [!]=Fehler")
      
      (foreach dwg-entry dwg-list
        (setq dwg-name (nth 0 dwg-entry)
              dwg-guid (nth 1 dwg-entry)
              dwg-path (nth 2 dwg-entry))
        
        ;; Aktuelle Zeichnung ueberspringen
        (if (/= (strcase dwg-name) (strcase current-dwg))
          (progn
            (setq cnt (1+ cnt))
            (princ (strcat "\n  [" (itoa cnt) "] "
                           (LXI:pad-str dwg-name 28) " "))
            
            ;; Pruefen ob DWG geoeffnet ist
            (setq open-doc (LXI:find-open-document dwg-name))
            
            (cond
              ;; === GEOEFFNET: via Documents-Collection ===
              (open-doc
                (progn
                  (setq cnt-open (1+ cnt-open))
                  ;; GUID aus offener Zeichnung lesen falls noetig
                  (if (or (null dwg-guid) (= dwg-guid "") (= dwg-guid "NO-GUID"))
                    (setq dwg-guid (LXI:doc-get-guid open-doc)))
                  ;; Pfad aktualisieren
                  (setq dwg-path (strcat (vla-get-Path open-doc) "\\"))
                  ;; Layer syncen
                  (setq result (LXI:doc-sync-layers open-doc master-data))
                  (setq total-new (+ total-new (nth 0 result))
                        total-upd (+ total-upd (nth 1 result))
                        total-skip (+ total-skip (nth 2 result))
                        total-del (+ total-del (nth 4 result)))
                  (if (nth 3 result)
                    (setq all-conflicts
                      (cons (list dwg-name (nth 3 result)) all-conflicts)))
                  (if (nth 5 result)
                    (setq all-del-info
                      (cons (list dwg-name (nth 5 result)) all-del-info)))
                  ;; Mapper
                  (setq mapper-data
                    (LXI:doc-update-mapper open-doc dwg-name dwg-guid
                                           dwg-path master-data mapper-data))
                  (princ (strcat "[O] +" (itoa (nth 0 result))
                                 " ~"   (itoa (nth 1 result))
                                 " ="   (itoa (nth 2 result))
                                 (if (> (nth 4 result) 0)
                                   (strcat " -" (itoa (nth 4 result))) "")))))
              
              ;; === GESCHLOSSEN: via ObjectDBX ===
              (T
                (progn
                  (setq fullpath
                    (if (and dwg-path (/= dwg-path ""))
                      (strcat dwg-path dwg-name) nil))
                  (cond
                    ((null fullpath)
                      (progn (princ "[!] KEIN PFAD") (setq cnt-err (1+ cnt-err))))
                    ((not (findfile fullpath))
                      (progn (princ "[!] NICHT GEFUNDEN") (setq cnt-err (1+ cnt-err))))
                    (T
                      (progn
                        (setq dbx-doc (LXI:dbx-open fullpath))
                        (if dbx-doc
                          (progn
                            (setq cnt-dbx (1+ cnt-dbx))
                            (setq result (LXI:dbx-sync-layers dbx-doc master-data))
                            (setq total-new (+ total-new (nth 0 result))
                                  total-upd (+ total-upd (nth 1 result))
                                  total-skip (+ total-skip (nth 2 result))
                                  total-del (+ total-del (nth 4 result)))
                            (if (nth 3 result)
                              (setq all-conflicts
                                (cons (list dwg-name (nth 3 result)) all-conflicts)))
                            (if (nth 5 result)
                              (setq all-del-info
                                (cons (list dwg-name (nth 5 result)) all-del-info)))
                            (setq mapper-data
                              (LXI:dbx-update-mapper dbx-doc dwg-name dwg-guid
                                                     dwg-path master-data mapper-data))
                            (vl-catch-all-apply 'vla-SaveAs (list dbx-doc fullpath))
                            (vlax-release-object dbx-doc)
                            (princ (strcat "[D] +" (itoa (nth 0 result))
                                           " ~"   (itoa (nth 1 result))
                                           " ="   (itoa (nth 2 result))
                                           (if (> (nth 4 result) 0)
                                             (strcat " -" (itoa (nth 4 result))) ""))))
                          (progn
                            (princ "[!] GESPERRT")
                            (setq cnt-err (1+ cnt-err)))))))))))))
      
      ;; Mapper schreiben
      (LXI:write-mapper mapper-data)
      
      ;; Zusammenfassung
      (princ "\n\n========================================")
      (princ "\n  BATCH-ERGEBNIS:")
      (princ (strcat "\n    Zeichnungen:  " (itoa (length dwg-list))
                     " (" (itoa cnt-open) " offen, "
                     (itoa cnt-dbx) " DBX, "
                     (itoa cnt-err) " Fehler)"))
      (princ (strcat "\n    Neu angelegt: " (itoa total-new)))
      (princ (strcat "\n    Aktualisiert: " (itoa total-upd)))
      (princ (strcat "\n    Synchron:     " (itoa total-skip)))
      (if (> total-del 0)
        (princ (strcat "\n    Entfernt/OFF: " (itoa total-del))))
      
      ;; Konflikte anzeigen
      (if all-conflicts
        (progn
          (princ "\n\n  KONFLIKTE (Master wurde angewendet):")
          (foreach c all-conflicts
            (princ (strcat "\n  " (car c) ":"))
            (foreach detail (cadr c)
              (princ (strcat "\n    " (LXI:pad-str (nth 0 detail) 25)
                             (LXI:pad-str (nth 1 detail) 8)
                             "Master=" (nth 2 detail) " war=" (nth 3 detail)))))
        )
        (princ "\n    Keine Konflikte."))
      
      ;; Geloeschte/deaktivierte Layer anzeigen
      (if all-del-info
        (progn
          (princ "\n\n  ENTFERNTE LAYER (nicht mehr im Master):")
          (foreach d all-del-info
            (princ (strcat "\n  " (car d) ":"))
            (foreach detail (cadr d)
              (princ (strcat "\n    " (LXI:pad-str (nth 0 detail) 30)
                             " -> " (nth 1 detail)))))))
      
      (princ "\n========================================")))
  
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYSYNC (mit Option fuer Batch)
;;; ========================================================================
(defun c:LAYSYNC ( / *error* old-cmdecho imp-ok exp-ok choice)
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg)))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (princ "\n")
  (princ "\n========================================")
  (princ (strcat "\n  LAYSYNC: " (LXI:dwg-name)))
  (princ (strcat "\n  GUID:    " (LXI:dwg-guid)))
  (princ "\n========================================")
  (princ "\n\n>> Schritt 1/2: Import (Master -> Zeichnung)")
  (setq imp-ok (LXI:do-import))
  (princ "\n\n>> Schritt 2/2: Export (Zeichnung -> Master)")
  (setq exp-ok (LXI:do-export))
  (princ "\n")
  (princ "\n========================================")
  (cond
    ((and imp-ok exp-ok) (princ "\n  Sync erfolgreich."))
    ((and (null imp-ok) exp-ok) (princ "\n  Export OK (Master war leer)."))
    ((and imp-ok (null exp-ok)) (princ "\n  Import OK, Export fehlgeschlagen!"))
    (T (princ "\n  *** Sync fehlgeschlagen!")))
  (princ "\n========================================")
  ;; Batch-Option anbieten
  (princ "\n")
  (initget "Ja Nein")
  (setq choice (getkword "\nAlle Zeichnungen syncen? [Ja/Nein] <Nein>: "))
  (if (= choice "Ja")
    (c:LAYSYNCALL))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYEXP
;;; ========================================================================
(defun c:LAYEXP ( / *error* old-cmdecho)
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg)))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:do-export)
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYIMP
;;; ========================================================================
(defun c:LAYIMP ( / *error* old-cmdecho)
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg)))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:do-import)
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYLOG
;;; ========================================================================
(defun c:LAYLOG ( / *error* old-cmdecho choice history filter-name filter-mid
                    master-data results count entry)
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg)))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (setq history (LXI:read-history))
  (if (null history)
    (princ "\n*** Keine History vorhanden.")
    (progn
      (princ (strcat "\n" (itoa (length history)) " History-Eintraege."))
      (initget "Alle Layer")
      (setq choice (getkword "\n[Alle/Layer] <Alle>: "))
      (if (null choice) (setq choice "Alle"))
      (cond
        ((= choice "Alle")
          (progn
            (setq results (reverse history) count (min 30 (length results)))
            (princ (strcat "\n\n=== Letzte " (itoa count) " ==="))
            (princ "\nDatum              Aktion        Layer                    Quelle          Detail")
            (princ "\n-----------------------------------------------------------------------------")
            (repeat count
              (setq entry (car results))
              (princ (strcat "\n" (nth 0 entry) "  "
                (LXI:pad-str (nth 1 entry) 13)
                (LXI:pad-str (nth 2 entry) 25)
                (LXI:pad-str (nth 4 entry) 16) (nth 3 entry)))
              (setq results (cdr results)))
            (princ "\n")))
        ((= choice "Layer")
          (progn
            (setq filter-name (getstring T "\nLayername (Teil): "))
            (if (and filter-name (/= filter-name ""))
              (progn
                (setq master-data (LXI:read-master) filter-mid nil)
                (if master-data
                  (foreach lay master-data
                    (if (wcmatch (strcase (nth 1 lay))
                                 (strcat "*" (strcase filter-name) "*"))
                      (progn (setq filter-mid (car lay))
                             (princ (strcat "\n> " (nth 1 lay) " [" filter-mid "]"))))))
                (if filter-mid
                  (progn
                    (setq results
                      (vl-remove-if-not
                        '(lambda (e) (= (strcase (nth 5 e)) (strcase filter-mid)))
                        history))
                    (if results
                      (progn
                        (princ (strcat "\n\n=== " filter-name " [" filter-mid "] ==="))
                        (princ "\nDatum              Aktion        Layer                    Quelle          Detail")
                        (princ "\n-----------------------------------------------------------------------------")
                        (foreach entry results
                          (princ (strcat "\n" (nth 0 entry) "  "
                            (LXI:pad-str (nth 1 entry) 13)
                            (LXI:pad-str (nth 2 entry) 25)
                            (LXI:pad-str (nth 4 entry) 16) (nth 3 entry))))
                        (princ "\n"))
                      (princ "\n*** Keine History.")))
                  (princ (strcat "\n*** \"" filter-name "\" nicht gefunden."))))
              (princ "\n*** Kein Name.")))))))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYSTATUS
;;; ========================================================================
(defun c:LAYSTATUS ( / *error* old-cmdecho master-data mapper-data
                       dwg-list dwg-entry dwg-name dwg-guid dwg-path
                       total-master master-ids dwg-mids dwg-count dwg-missing mid)
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg)))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (setq master-data (LXI:read-master) mapper-data (LXI:read-mapper))
  (if (null master-data)
    (princ "\n*** Kein Master.")
    (progn
      (setq total-master (length master-data))
      (setq master-ids nil)
      (foreach lay master-data (setq master-ids (cons (car lay) master-ids)))
      (if mapper-data
        (progn
          (setq dwg-list (LXI:mapper-get-dwg-list mapper-data))
          (princ "\n\n====== LayerSync Status ======")
          (princ (strcat "\nMaster: " (itoa total-master) " Layer | Praefix: " *LXI:prefix* "*"))
          (princ (strcat "\n" (LXI:pad-str "Zeichnung" 30) (LXI:pad-str "Layer" 8)
                         (LXI:pad-str "Fehlend" 10) "Pfad"))
          (princ (strcat "\n" (LXI:pad-str "------------------------------" 30)
                         (LXI:pad-str "--------" 8) (LXI:pad-str "----------" 10)
                         "--------------------"))
          (foreach dwg-entry dwg-list
            (setq dwg-name (nth 0 dwg-entry) dwg-guid (nth 1 dwg-entry)
                  dwg-path (nth 2 dwg-entry))
            (setq dwg-mids nil)
            (foreach entry mapper-data
              (if (= (strcase (nth 0 entry)) (strcase dwg-name))
                (setq dwg-mids (cons (nth 5 entry) dwg-mids))))
            (setq dwg-count (length dwg-mids) dwg-missing 0)
            (foreach mid master-ids
              (if (not (member mid dwg-mids)) (setq dwg-missing (1+ dwg-missing))))
            (princ (strcat "\n" (LXI:pad-str dwg-name 30)
                           (LXI:pad-str (itoa dwg-count) 8)
                           (LXI:pad-str (if (= dwg-missing 0) "OK"
                                          (strcat (itoa dwg-missing) " fehlen")) 10)
                           (if (and dwg-path (/= dwg-path ""))
                             (substr dwg-path 1 (min 40 (strlen dwg-path)))
                             "KEIN PFAD"))))
          (princ (strcat "\n\n  * Aktuell: " (LXI:dwg-name)))
          (princ "\n=============================="))
        (progn
          (princ "\n\n====== LayerSync Status ======")
          (princ (strcat "\nMaster: " (itoa total-master) " Layer"))
          (princ "\nNoch keine Zeichnung synchronisiert.")
          (princ "\n==============================")))))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYCFG
;;; ========================================================================
(defun c:LAYCFG ( / *error* old-cmdecho choice new-val)
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg)))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (princ "\n\n=== LayerSync Konfiguration ===")
  (princ (strcat "\n  [P]fad:    " *LXI:base-path*))
  (princ (strcat "\n  P[r]aefix: " *LXI:prefix*))
  (princ (strcat "\n  [D]ebug:   " (if *LXI:debug* "ON" "OFF")))
  (princ (strcat "\n  DWG-GUID:  " (LXI:dwg-guid)))
  (princ "\n===============================\n")
  (initget "Pfad pRaefix Debug")
  (setq choice (getkword "\n[Pfad/pRaefix/Debug] <Abbruch>: "))
  (cond
    ((= choice "Pfad")
      (progn
        (setq new-val (getstring T "\nNeuer Pfad (Enter=behalten): "))
        (if (and new-val (/= new-val ""))
          (progn
            (setq *LXI:base-path* new-val)
            (if (LXI:ensure-directory *LXI:base-path*)
              (progn (LXI:write-config) (princ (strcat "\nPfad: " *LXI:base-path*)))
              (progn (princ "\n*** Fehler!") (setq *LXI:base-path* *LXI:default-path*)))))))
    ((= choice "pRaefix")
      (progn
        (setq new-val (getstring T "\nNeues Praefix (Enter=behalten): "))
        (if (and new-val (/= new-val ""))
          (progn (setq *LXI:prefix* new-val) (LXI:write-config)
                 (princ (strcat "\nPraefix: " *LXI:prefix* "*"))))))
    ((= choice "Debug")
      (progn (setq *LXI:debug* (not *LXI:debug*)) (LXI:write-config)
             (princ (strcat "\nDebug: " (if *LXI:debug* "ON" "OFF"))))))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Initialisierung
;;; ========================================================================
(vl-load-com)
(LXI:read-config)
(if (not (findfile (LXI:get-config-path)))
  (progn (LXI:ensure-directory *LXI:base-path*) (LXI:write-config)))
(princ "\nLayerExportImport.lsp v1.1.0 geladen.")
(princ "\nBefehle: LAYSYNC | LAYSYNCALL | LAYEXP | LAYIMP | LAYLOG | LAYSTATUS | LAYCFG")
(princ (strcat "\nPraefix: " *LXI:prefix* "* | Speicherort: " *LXI:base-path*))
(princ)
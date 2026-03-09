;;; ========================================================================
;;; LayerExportImport.lsp
;;; Layer-Synchronisation zwischen Zeichnungen via Master-Datei
;;; MasterID-System fuer zeichnungsuebergreifendes Tracking
;;; FINGERPRINTGUID durch Custom Property LayerSyncGUID ersetzt
;;; 
;;; Version: 0.12.1
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
;;;   LAYSYNC   - Import + Export in einem Schritt (Strg+Shift+L)
;;;   LAYEXP    - Nur Export: Layer in Master-Datei schreiben
;;;   LAYIMP    - Nur Import: Layer aus Master holen (interaktiv)
;;;   LAYLOG    - Layer-Aenderungshistorie anzeigen
;;;   LAYSTATUS - Uebersicht aller Zeichnungen und Sync-Stand
;;;   LAYCFG    - Konfiguration anzeigen / aendern
;;;
;;; Dateien im LayerSync-Ordner:
;;;   LayerMaster.csv  - Layer-Daten mit MasterID (Primary Key)
;;;   LayerMapper.csv  - Handle+GUID-Zuordnung (5 Felder)
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
    (write-line ";;; LayerSync Konfiguration v0.12.1" fp)
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

;;; Gibt die LayerSyncGUID der aktuellen Zeichnung zurueck
;;; Liest aus Custom Property "LayerSyncGUID"
;;; Erstellt eine neue GUID falls nicht vorhanden
;;; Cached in globaler Variable fuer die Session
;;; Bleibt permanent in der DWG (ueberlebt SaveAs, Kopie, Umbenennung)
(defun LXI:dwg-guid ( / si guid num-props i key val found)
  ;; Session-Cache: wenn schon gelesen, direkt zurueckgeben
  (if (and *LXI:cached-guid*
           (/= *LXI:cached-guid* "")
           ;; Cache nur gueltig fuer gleiche Zeichnung
           (= *LXI:cached-guid-dwg* (LXI:dwg-name)))
    (progn
      (LXI:debug-print (strcat "GUID (cached): " *LXI:cached-guid*))
      *LXI:cached-guid*)
    ;; Nicht gecached: aus DWG lesen
    (progn
      (setq si (vla-get-SummaryInfo
                 (vla-get-ActiveDocument (vlax-get-acad-object))))
      (setq found nil)
      (setq guid nil)
      
      ;; Custom Properties durchsuchen
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
      
      ;; Falls keine GUID vorhanden: neue generieren und speichern
      (if (or (null guid) (= guid ""))
        (progn
          (setq guid (LXI:generate-guid))
          (vl-catch-all-apply
            '(lambda ()
              (vla-AddCustomInfo si "LayerSyncGUID" guid)))
          (LXI:debug-print (strcat "Neue LayerSyncGUID erstellt: " guid))
          (princ (strcat "\n  LayerSyncGUID erstellt: " guid))
          (princ "\n  WICHTIG: Zeichnung speichern damit GUID permanent wird!"))
        (LXI:debug-print (strcat "LayerSyncGUID: " guid)))
      
      ;; In Session-Cache speichern
      (setq *LXI:cached-guid* guid)
      (setq *LXI:cached-guid-dwg* (LXI:dwg-name))
      
      guid)))

;; Session-Cache initialisieren
(setq *LXI:cached-guid* nil)
(setq *LXI:cached-guid-dwg* nil)


;;; Generiert eine eindeutige ID
;;; Format: LXI-YYYYMMDD-HHMMSS-RAND
(defun LXI:generate-guid ( / date-str rand-str)
  (setq date-str (menucmd "M=$(edtime,0,YYYYMODDHHMMSS)"))
  ;; Zufallszahl aus Millisekunden-Anteil der Zeit
  (setq rand-str (itoa (rem (getvar "MILLISECS") 100000)))
  (while (< (strlen rand-str) 5)
    (setq rand-str (strcat "0" rand-str)))
  (strcat "LXI-" date-str "-" rand-str))

(defun LXI:pad-str (str width / pad)
  (if (null str) (setq str ""))
  (if (> (strlen str) width)
    (strcat (substr str 1 (- width 2)) "..")
    (progn
      (setq pad (- width (strlen str)))
      (while (> pad 0) (setq str (strcat str " ")) (setq pad (1- pad)))
      str)))


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
;;; MASTER (.csv) - 11 Felder (unveraendert)
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
;;; MAPPER (.csv) - 5 Felder (NEU: DwgGUID)
;;; DwgName;DwgGUID;LayerName;Handle;MasterID
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
                    ;; Akzeptiere 5 Felder (neu) und 4 Felder (alt, Migration)
                    (cond
                      ((= (length fields) 5)
                        (setq result (cons fields result)))
                      ((= (length fields) 4)
                        ;; Altes Format: DwgName;LayerName;Handle;MasterID
                        ;; -> Migriere: fuege leere GUID ein
                        (setq result
                          (cons
                            (list (nth 0 fields) "" (nth 1 fields)
                                  (nth 2 fields) (nth 3 fields))
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
            (strcat "DwgName" s "DwgGUID" s "LayerName" s "Handle" s "MasterID") fp)
          (setq mapper-data (vl-sort mapper-data
            '(lambda (a b)
              (if (= (car a) (car b))
                (< (nth 2 a) (nth 2 b))
                (< (car a) (car b))))))
          (foreach entry mapper-data
            (write-line
              (strcat (nth 0 entry) s (nth 1 entry) s (nth 2 entry) s
                      (nth 3 entry) s (nth 4 entry)) fp))
          (close fp) T)))))


;;; ------------------------------------------------------------------------
;;; Sucht im Mapper: GUID + Handle -> MasterID
;;; Fallback: DwgName + Handle falls GUID leer
;;; ------------------------------------------------------------------------
(defun LXI:mapper-get-mid (mapper-data guid dwg handle / result)
  (setq result nil)
  ;; Zuerst ueber GUID suchen
  (if (and guid (/= guid "") (/= guid "NO-GUID"))
    (foreach entry mapper-data
      (if (and (= (strcase (nth 1 entry)) (strcase guid))
               (= (strcase (nth 3 entry)) (strcase handle)))
        (setq result (nth 4 entry)))))
  ;; Fallback: DwgName
  (if (null result)
    (foreach entry mapper-data
      (if (and (= (strcase (nth 0 entry)) (strcase dwg))
               (= (strcase (nth 3 entry)) (strcase handle)))
        (setq result (nth 4 entry)))))
  result)


;;; ------------------------------------------------------------------------
;;; Filtert Mapper-Eintraege fuer aktuelle Zeichnung (GUID oder Name)
;;; Erkennt DWG-Umbenennung: GUID gleich, Name anders -> aktualisiert
;;; Rueckgabe: Gefilterte Liste + ggf. aktualisierte mapper-data
;;; ------------------------------------------------------------------------
(defun LXI:mapper-get-dwg-entries (mapper-data guid dwg / result
                                    guid-entries name-entries old-name)
  ;; Zuerst ueber GUID suchen
  (setq guid-entries nil)
  (if (and guid (/= guid "") (/= guid "NO-GUID"))
    (setq guid-entries
      (vl-remove-if-not
        '(lambda (e) (= (strcase (nth 1 e)) (strcase guid)))
        mapper-data)))
  
  (if guid-entries
    (progn
      ;; GUID gefunden - pruefe ob DWG umbenannt wurde
      (setq old-name (nth 0 (car guid-entries)))
      (if (/= (strcase old-name) (strcase dwg))
        (progn
          ;; DWG wurde umbenannt! Namen in allen Eintraegen aktualisieren
          (princ (strcat "\n  DWG umbenannt: " old-name " -> " dwg))
          (setq guid-entries
            (mapcar
              '(lambda (e)
                (list dwg (nth 1 e) (nth 2 e) (nth 3 e) (nth 4 e)))
              guid-entries))))
      guid-entries)
    ;; Fallback: ueber DwgName suchen
    (vl-remove-if-not
      '(lambda (e) (= (strcase (car e)) (strcase dwg)))
      mapper-data)))


;;; ------------------------------------------------------------------------
;;; Entfernt alle Eintraege einer Zeichnung (ueber GUID UND Name)
;;; Entfernt beides um alte Eintraege mit anderer GUID zu bereinigen
;;; ------------------------------------------------------------------------
(defun LXI:mapper-remove-dwg (mapper-data guid dwg / )
  ;; Entferne ALLE Eintraege die entweder gleiche GUID oder gleichen Namen haben
  (vl-remove-if
    '(lambda (entry)
      (or
        ;; Ueber GUID entfernen
        (and guid (/= guid "") (/= guid "NO-GUID")
             (= (strcase (nth 1 entry)) (strcase guid)))
        ;; Ueber Name entfernen (raeumt alte Eintraege mit anderer GUID auf)
        (= (strcase (car entry)) (strcase dwg))))
    mapper-data))


;;; ========================================================================
;;; HISTORY (.csv) - APPEND ONLY - 6 Felder (unveraendert)
;;; Datum;Aktion;LayerName;Detail;Source;MasterID
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
;;; LAYER SAMMELN
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

;;; ------------------------------------------------------------------------
;;; Stellt sicher dass ein Linientyp verfuegbar ist
;;; Versucht: 1) acadiso.lin  2) Dateiauswahl-Dialog  3) Fallback Continuous
;;; Parameter:
;;;   ltype - Gewuenschter Linientyp-Name
;;; Rueckgabe: Verfuegbarer Linientyp-Name (original oder "Continuous")
;;; ------------------------------------------------------------------------
(defun LXI:ensure-linetype (ltype / lin-file)
  ;; Wenn Continuous oder schon vorhanden: nichts tun
  (if (or (= (strcase ltype) "CONTINUOUS")
          (tblsearch "LTYPE" ltype))
    ltype
    ;; Versuche aus acadiso.lin zu laden
    (progn
      (LXI:debug-print (strcat "  Linientyp \"" ltype "\" fehlt, versuche zu laden..."))
      (setq lin-file (findfile "acadiso.lin"))
      (if lin-file
        (progn
          (vl-catch-all-apply
            '(lambda ()
              (command "._-LINETYPE" "L" ltype lin-file "")))
          ;; Pruefen ob erfolgreich geladen
          (if (tblsearch "LTYPE" ltype)
            (progn
              (princ (strcat "\n  Linientyp \"" ltype "\" aus acadiso.lin geladen."))
              ltype)
            ;; Nicht in acadiso.lin -> Dateiauswahl
            (progn
              (princ (strcat "\n  Linientyp \"" ltype
                             "\" nicht in acadiso.lin gefunden."))
              (LXI:load-linetype-from-dialog ltype))))
        ;; acadiso.lin nicht gefunden -> Dateiauswahl
        (progn
          (princ "\n  acadiso.lin nicht gefunden.")
          (LXI:load-linetype-from-dialog ltype))))))


;;; ------------------------------------------------------------------------
;;; Versucht Linientyp ueber Dateiauswahl-Dialog zu laden
;;; Rueckgabe: Linientyp-Name oder "Continuous" bei Abbruch
;;; ------------------------------------------------------------------------
(defun LXI:load-linetype-from-dialog (ltype / lin-file)
  (princ (strcat "\n  Bitte .lin-Datei fuer \"" ltype "\" waehlen:"))
  (setq lin-file
    (getfiled (strcat "LIN-Datei fuer Linientyp \"" ltype "\"")
              "" "lin" 4))
  (if lin-file
    (progn
      (vl-catch-all-apply
        '(lambda ()
          (command "._-LINETYPE" "L" ltype lin-file "")))
      (if (tblsearch "LTYPE" ltype)
        (progn
          (princ (strcat "\n  Linientyp \"" ltype "\" geladen aus " lin-file))
          ltype)
        (progn
          (princ (strcat "\n  *** Linientyp \"" ltype
                         "\" konnte nicht geladen werden. Verwende Continuous."))
          "Continuous")))
    (progn
      (princ (strcat "\n  *** Abbruch. Verwende Continuous fuer \"" ltype "\"."))
      "Continuous")))


(defun LXI:create-layer (lay-name col ltype plot-flag on-off frz lck / new-col)
  ;; Linientyp sicherstellen (laden wenn noetig)
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
      ;; Linientyp sicherstellen (laden wenn noetig)
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
        (setq diffs (cons (strcat "  Farbe:     Master=" (itoa col)
                                  "  Lokal=" (itoa local-col)) diffs)))
      (if (/= (strcase local-onoff) (strcase on-off))
        (setq diffs (cons (strcat "  OnOff:     Master=" on-off
                                  "  Lokal=" local-onoff) diffs)))
      (setq local-ltype (cdr (assoc 6 ent-data)))
      (if (null local-ltype) (setq local-ltype "Continuous"))
      (if (/= (strcase local-ltype) (strcase ltype))
        (setq diffs (cons (strcat "  Linientyp: Master=" ltype
                                  "  Lokal=" local-ltype) diffs)))
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
  (princ "\n")
  (princ "\n  Master    = Wert aus Master-Datei uebernehmen")
  (princ "\n  Lokal     = Lokalen Wert dieser Zeichnung behalten")
  (princ "\n  alleMaster = Master fuer ALLE weiteren Konflikte")
  (princ "\n  alleLokal  = Lokal fuer ALLE weiteren Konflikte")
  (initget "Master Lokal alleMaster alleLokal")
  (setq choice (getkword "\nEntscheidung [Master/Lokal/alleMaster/alleLokal]: "))
  (if (null choice) "Lokal" choice))

(defun LXI:ask-deleted (lay-name mid / choice confirm)
  (princ (strcat "\n\n========================================"))
  (princ (strcat "\n  FEHLEND: " lay-name " [" mid "]"))
  (princ "\n  Dieser Layer existiert im Master, aber nicht mehr")
  (princ "\n  in dieser Zeichnung (wurde lokal geloescht).")
  (princ "\n")
  (princ "\n  Neu       = Layer hier wieder anlegen (aus Master)")
  (princ "\n  Ignorieren = Nichts tun (Layer bleibt im Master)")
  (princ "\n  Loeschen  = Layer komplett aus Master entfernen!")
  (initget "Neu Ignorieren Loeschen")
  (setq choice (getkword "\nEntscheidung [Neu/Ignorieren/Loeschen]: "))
  (if (null choice) (setq choice "Ignorieren"))
  (if (= choice "Loeschen")
    (progn
      (princ (strcat "\n\n  !!! WARNUNG: " lay-name " wird aus dem Master"))
      (princ "\n  entfernt und steht keiner Zeichnung mehr zur Verfuegung!")
      (initget "Ja Nein")
      (setq confirm (getkword "\n  Wirklich loeschen? [Ja/Nein]: "))
      (if (= confirm "Ja") "Loeschen" "Ignorieren"))
    choice))

(defun LXI:ask-rename (master-name local-name mid / choice)
  (princ (strcat "\n\n========================================"))
  (princ (strcat "\n  UMBENENNUNG erkannt: [" mid "]"))
  (princ "\n  Dieser Layer hat in Master und Zeichnung verschiedene Namen.")
  (princ (strcat "\n  Master-Name: " master-name))
  (princ (strcat "\n  Lokal-Name:  " local-name))
  (princ "\n")
  (princ "\n  Master = Lokalen Layer auf Master-Name umbenennen")
  (princ "\n  Lokal  = Lokalen Namen behalten (Master unberuehrt)")
  (initget "Master Lokal")
  (setq choice (getkword "\nEntscheidung [Master/Lokal]: "))
  (if (null choice) "Master" choice))


;;; ========================================================================
;;; EXPORT-KERNFUNKTION
;;; ========================================================================
(defun LXI:do-export ( / dwg guid layers master-data mapper-data
                         lay lay-name handle mid old-name
                         existing-master change-details detail
                         timestamp history-entries new-mid
                         cnt-new cnt-upd cnt-ren)
  
  (setq dwg (LXI:dwg-name))
  (setq guid (LXI:dwg-guid))
  (setq timestamp (LXI:timestamp))
  (setq cnt-new 0 cnt-upd 0 cnt-ren 0)
  (setq history-entries nil)
  
  (LXI:debug-print (strcat "DWG: " dwg " GUID: " guid))
  
  (setq layers (LXI:collect-layers))
  
  (if (null layers)
    (progn
      (princ (strcat "\n  Export: Keine Layer mit Praefix \""
                     *LXI:prefix* "\" gefunden."))
      nil)
    (progn
      (setq master-data (LXI:read-master))
      (if (null master-data) (setq master-data nil))
      (setq mapper-data (LXI:read-mapper))
      (if (null mapper-data) (setq mapper-data nil))
      
      (foreach lay layers
        (setq lay-name (nth 0 lay))
        (setq handle   (nth 8 lay))
        (setq mid (LXI:mapper-get-mid mapper-data guid dwg handle))
        
        (cond
          ;; FALL 1: Handle hat MasterID
          (mid
            (progn
              (setq existing-master (LXI:find-by-id master-data mid))
              (if existing-master
                (progn
                  (setq old-name (nth 1 existing-master))
                  (if (/= (strcase old-name) (strcase lay-name))
                    (progn
                      (princ (strcat "\n  Umbenennung: " old-name " -> " lay-name " [" mid "]"))
                      (setq history-entries
                        (cons (list timestamp "UMBENENNUNG" lay-name
                                    (strcat old-name "->" lay-name) dwg mid)
                              history-entries))
                      (setq cnt-ren (1+ cnt-ren))))
                  (setq change-details nil)
                  (setq detail (LXI:compare-field (nth 2 existing-master) (nth 1 lay)))
                  (if detail (setq change-details (cons (strcat "Farbe:" detail) change-details)))
                  ;; Linientyp: Nur loggen wenn lokal NICHT Continuous ist
                  ;; (Continuous koennte Fallback sein weil Sonder-Linientyp fehlt)
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
                                    dwg mid)
                              history-entries))
                      (setq cnt-upd (1+ cnt-upd))))
                  ;; Master aktualisieren - Linientyp: Master behalten wenn lokal Continuous
                  ;; und Master etwas anderes hat (= Fallback-Schutz)
                  (setq master-data (LXI:remove-by-id master-data mid))
                  (setq master-data
                    (cons (list mid lay-name (nth 1 lay)
                                ;; Linientyp: Master behalten wenn lokal Continuous
                                ;; und Master einen Sonder-Linientyp hat
                                (if (and (= (strcase (nth 2 lay)) "CONTINUOUS")
                                         (/= (strcase (nth 3 existing-master)) "CONTINUOUS"))
                                  (progn
                                    (LXI:debug-print
                                      (strcat "  Linientyp beibehalten: "
                                              (nth 3 existing-master)
                                              " (lokal=Continuous)"))
                                    (nth 3 existing-master))
                                  (nth 2 lay))
                                (nth 3 lay)
                                (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                                dwg timestamp) master-data))))))
          
          ;; FALL 2: Name existiert im Master
          ((setq existing-master (LXI:find-by-name master-data lay-name))
            (progn
              (setq mid (car existing-master))
              (LXI:debug-print (strcat "Name-Match: " lay-name " -> " mid))
              (setq master-data (LXI:remove-by-id master-data mid))
              (setq master-data
                (cons (list mid lay-name (nth 1 lay) (nth 2 lay) (nth 3 lay)
                            (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                            dwg timestamp) master-data))
              (setq cnt-upd (1+ cnt-upd))))
          
          ;; FALL 3: Komplett neuer Layer
          (T
            (progn
              (setq new-mid (LXI:next-master-id master-data))
              (LXI:debug-print (strcat "Neu: " lay-name " -> " new-mid))
              (setq master-data
                (cons (list new-mid lay-name (nth 1 lay) (nth 2 lay) (nth 3 lay)
                            (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                            dwg timestamp) master-data))
              (setq history-entries
                (cons (list timestamp "NEU" lay-name "" dwg new-mid) history-entries))
              (setq cnt-new (1+ cnt-new))))))
      
      ;; Mapper aktualisieren (mit GUID)
      (setq mapper-data (LXI:mapper-remove-dwg mapper-data guid dwg))
      (foreach lay layers
        (setq lay-name (nth 0 lay)) (setq handle (nth 8 lay))
        (setq mid (car (LXI:find-by-name master-data lay-name)))
        (if mid (setq mapper-data
          (cons (list dwg guid lay-name handle mid) mapper-data))))
      
      ;; Schreiben
      (if (and (LXI:write-master master-data) (LXI:write-mapper mapper-data))
        (progn
          (if history-entries (LXI:append-history (reverse history-entries)))
          (princ (strcat "\n  --- Export (" dwg ") ---"))
          (if (> cnt-new 0)
            (princ (strcat "\n    + " (itoa cnt-new) " Layer neu in Master")))
          (if (> cnt-upd 0)
            (princ (strcat "\n    ~ " (itoa cnt-upd) " Layer im Master aktualisiert")))
          (if (> cnt-ren 0)
            (princ (strcat "\n    > " (itoa cnt-ren) " Layer im Master umbenannt")))
          (if (and (= cnt-new 0) (= cnt-upd 0) (= cnt-ren 0))
            (princ "\n    = Master ist aktuell"))
          (princ (strcat "\n    Master gesamt: " (itoa (length master-data)) " Layer"))
          T)
        (progn (princ "\n  *** Fehler beim Schreiben.") nil)))))


;;; ========================================================================
;;; IMPORT-KERNFUNKTION
;;; ========================================================================
(defun LXI:do-import ( / dwg guid master-data mapper-data dwg-mapper
                         is-first-import global-choice
                         lay mid master-name col ltype lw plot-flag on-off frz lck
                         mapped-entry mapped-handle mapped-name
                         local-name diffs choice
                         lay-tbl handle new-mapper ent-data
                         delete-list
                         cnt-new cnt-upd cnt-skip cnt-ren cnt-del)
  
  (setq dwg (LXI:dwg-name))
  (setq guid (LXI:dwg-guid))
  (setq cnt-new 0 cnt-upd 0 cnt-skip 0 cnt-ren 0 cnt-del 0)
  (setq global-choice nil)
  (setq delete-list nil)
  
  (LXI:debug-print (strcat "DWG: " dwg " GUID: " guid))
  
  (setq master-data (LXI:read-master))
  
  (if (null master-data)
    (progn
      (princ "\n  Import: Kein Master gefunden oder leer.")
      nil)
    (progn
      (princ (strcat "\n  " (itoa (length master-data)) " Layer im Master."))
      
      (setq mapper-data (LXI:read-mapper))
      (if (null mapper-data) (setq mapper-data nil))
      
      ;; Mapper-Eintraege fuer diese Zeichnung (ueber GUID oder Name)
      (setq dwg-mapper
        (LXI:mapper-get-dwg-entries mapper-data guid dwg))
      (setq is-first-import (null dwg-mapper))
      
      (if is-first-import
        (princ "\n  Erster Import fuer diese Zeichnung.")
        (princ (strcat "\n  " (itoa (length dwg-mapper)) " Layer bereits bekannt.")))
      
      ;; Jeden Master-Layer verarbeiten
      (foreach lay master-data
        (setq mid         (nth 0 lay)
              master-name (nth 1 lay)
              col         (atoi (nth 2 lay))
              ltype       (nth 3 lay)
              lw          (nth 4 lay)
              plot-flag   (nth 5 lay)
              on-off      (nth 6 lay)
              frz         (nth 7 lay)
              lck         (nth 8 lay))
        
        (LXI:debug-print (strcat "Import: " master-name " [" mid "]"))
        
        ;; Mapper-Eintrag fuer diese MasterID suchen
        ;; Mapper: (DwgName DwgGUID LayerName Handle MasterID) = nth 4 = MasterID
        (setq mapped-entry nil)
        (foreach e dwg-mapper
          (if (= (strcase (nth 4 e)) (strcase mid))
            (setq mapped-entry e)))
        
        (cond
          ;; FALL A: MasterID im Mapper
          (mapped-entry
            (progn
              (setq mapped-handle (nth 3 mapped-entry))  ; Handle
              (setq mapped-name   (nth 2 mapped-entry))  ; LayerName
              (setq local-name (LXI:find-local-by-handle mapped-handle))
              
              (cond
                ;; Layer existiert lokal
                (local-name
                  (progn
                    (LXI:debug-print (strcat "  Handle " mapped-handle " -> " local-name))
                    (cond
                      ;; Name gleich
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
                              (LXI:debug-print (strcat "  Skip: " local-name " (identisch)"))
                              (setq cnt-skip (1+ cnt-skip))))))
                      ;; Name anders (Umbenennung)
                      (T
                        (progn
                          (setq choice (LXI:ask-rename master-name local-name mid))
                          (if (= choice "Master")
                            (progn
                              (command "._-RENAME" "LA" local-name master-name)
                              (princ (strcat "\n  Umbenannt: " local-name " -> " master-name))
                              (LXI:update-layer-props master-name col ltype plot-flag on-off)
                              (setq cnt-ren (1+ cnt-ren)))
                            (progn
                              (princ (strcat "\n  Beibehalten: " local-name))
                              (setq cnt-skip (1+ cnt-skip)))))))))
                
                ;; Layer lokal geloescht
                (T
                  (progn
                    (LXI:debug-print (strcat "  Handle " mapped-handle " nicht gefunden"))
                    (setq choice (LXI:ask-deleted master-name mid))
                    (cond
                      ((= choice "Neu")
                        (if (LXI:create-layer master-name col ltype plot-flag on-off frz lck)
                          (progn (princ (strcat "\n  Neu angelegt: " master-name))
                                 (setq cnt-new (1+ cnt-new)))
                          (princ (strcat "\n  *** Fehler: " master-name))))
                      ((= choice "Loeschen")
                        (progn (setq delete-list (cons mid delete-list))
                               (setq cnt-del (1+ cnt-del))))
                      (T (progn (princ (strcat "\n  Ignoriert: " master-name))
                                (setq cnt-skip (1+ cnt-skip))))))))))
          
          ;; FALL B: MasterID NICHT im Mapper
          (T
            (progn
              (LXI:debug-print (strcat "  Neuer Layer: " master-name))
              (if (tblsearch "LAYER" master-name)
                (progn
                  (LXI:debug-print "  Name existiert lokal, verknuepfe")
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
                  (progn (LXI:debug-print (strcat "  Angelegt: " master-name))
                         (setq cnt-new (1+ cnt-new)))
                  (princ (strcat "\n  *** Fehler beim Anlegen: " master-name))))))))
      
      ;; Layer aus Master loeschen
      (if delete-list
        (progn
          (foreach del-mid delete-list
            (setq master-data (LXI:remove-by-id master-data del-mid))
            (princ (strcat "\n  Aus Master geloescht: " del-mid)))
          (LXI:write-master master-data)))
      
      ;; Mapper aktualisieren (mit GUID)
      (setq mapper-data (LXI:mapper-remove-dwg mapper-data guid dwg))
      (setq new-mapper nil)
      (while (setq lay-tbl (tblnext "LAYER" (not lay-tbl)))
        (setq lay-name (cdr (assoc 2 lay-tbl)))
        (if (and (not (LXI:xref-layer-p lay-name))
                 (LXI:sync-layer-p lay-name))
          (progn
            (setq ent-data (entget (tblobjname "LAYER" lay-name)))
            (setq handle (cdr (assoc 5 ent-data)))
            (setq mid (car (LXI:find-by-name master-data lay-name)))
            (if mid
              (setq new-mapper
                (cons (list dwg guid lay-name handle mid) new-mapper))))))
      (setq mapper-data (append mapper-data new-mapper))
      (LXI:write-mapper mapper-data)
      
      ;; Ergebnis (nur relevante Zeilen anzeigen)
      (princ (strcat "\n  --- Import (" dwg ") ---"))
      (if (> cnt-new 0)
        (princ (strcat "\n    + " (itoa cnt-new) " Layer neu angelegt")))
      (if (> cnt-upd 0)
        (princ (strcat "\n    ~ " (itoa cnt-upd) " Layer aktualisiert (Master)")))
      (if (> cnt-ren 0)
        (princ (strcat "\n    > " (itoa cnt-ren) " Layer umbenannt")))
      (if (> cnt-del 0)
        (princ (strcat "\n    - " (itoa cnt-del) " Layer aus Master geloescht")))
      (if (and (= cnt-new 0) (= cnt-upd 0) (= cnt-ren 0) (= cnt-del 0))
        (princ (strcat "\n    = Alles synchron (" (itoa cnt-skip) " Layer)")))
      T)))


;;; ========================================================================
;;; Hauptbefehl: LAYSYNC
;;; ========================================================================
(defun c:LAYSYNC ( / *error* old-cmdecho imp-ok exp-ok)
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
    ((and imp-ok exp-ok)
      (princ "\n  ERGEBNIS: Sync erfolgreich."))
    ((and (null imp-ok) exp-ok)
      (princ "\n  ERGEBNIS: Export OK. Master war leer (erster Sync)."))
    ((and imp-ok (null exp-ok))
      (princ "\n  ERGEBNIS: Import OK, Export fehlgeschlagen!"))
    (T
      (princ "\n  ERGEBNIS: *** Sync fehlgeschlagen!")))
  (princ "\n========================================")
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
(defun c:LAYLOG ( / *error* old-cmdecho
                    choice history filter-name filter-mid
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
    (princ "\n*** Keine History-Daten vorhanden.")
    (progn
      (princ (strcat "\n" (itoa (length history)) " History-Eintraege vorhanden."))
      (initget "Alle Layer")
      (setq choice (getkword "\nAnzeige? [Alle/Layer] <Alle>: "))
      (if (null choice) (setq choice "Alle"))
      (cond
        ((= choice "Alle")
          (progn
            (setq results (reverse history))
            (setq count (min 30 (length results)))
            (princ (strcat "\n\n=== Letzte " (itoa count) " Aenderungen ==="))
            (princ "\nDatum              Aktion        Layer                    Quelle          Detail")
            (princ "\n-----------------------------------------------------------------------------")
            (repeat count
              (setq entry (car results))
              (princ (strcat "\n" (nth 0 entry) "  "
                (LXI:pad-str (nth 1 entry) 13)
                (LXI:pad-str (nth 2 entry) 25)
                (LXI:pad-str (nth 4 entry) 16)
                (nth 3 entry)))
              (setq results (cdr results)))
            (princ "\n")))
        ((= choice "Layer")
          (progn
            (setq filter-name (getstring T "\nLayername (oder Teil davon): "))
            (if (and filter-name (/= filter-name ""))
              (progn
                (setq master-data (LXI:read-master))
                (setq filter-mid nil)
                (if master-data
                  (foreach lay master-data
                    (if (wcmatch (strcase (nth 1 lay))
                                 (strcat "*" (strcase filter-name) "*"))
                      (progn
                        (setq filter-mid (car lay))
                        (princ (strcat "\nGefunden: " (nth 1 lay) " [" filter-mid "]"))))))
                (if filter-mid
                  (progn
                    (setq results
                      (vl-remove-if-not
                        '(lambda (e) (= (strcase (nth 5 e)) (strcase filter-mid)))
                        history))
                    (if results
                      (progn
                        (princ (strcat "\n\n=== Historie fuer " filter-name " [" filter-mid "] ==="))
                        (princ "\nDatum              Aktion        LayerName                Quelle          Detail")
                        (princ "\n-----------------------------------------------------------------------------")
                        (foreach entry results
                          (princ (strcat "\n" (nth 0 entry) "  "
                            (LXI:pad-str (nth 1 entry) 13)
                            (LXI:pad-str (nth 2 entry) 25)
                            (LXI:pad-str (nth 4 entry) 16)
                            (nth 3 entry))))
                        (princ "\n"))
                      (princ "\n*** Keine History fuer diesen Layer.")))
                  (progn
                    (setq results
                      (vl-remove-if-not
                        '(lambda (e) (wcmatch (strcase (nth 2 e))
                                              (strcat "*" (strcase filter-name) "*")))
                        history))
                    (if results
                      (progn
                        (princ (strcat "\n\n=== Historie fuer *" filter-name "* ==="))
                        (princ "\nDatum              Aktion        LayerName                Quelle          MID")
                        (princ "\n-----------------------------------------------------------------------------")
                        (foreach entry results
                          (princ (strcat "\n" (nth 0 entry) "  "
                            (LXI:pad-str (nth 1 entry) 13)
                            (LXI:pad-str (nth 2 entry) 25)
                            (LXI:pad-str (nth 4 entry) 16)
                            (nth 5 entry))))
                        (princ "\n"))
                      (princ (strcat "\n*** Kein Layer mit \"" filter-name "\" gefunden."))))))
              (princ "\n*** Kein Name eingegeben.")))))))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYSTATUS
;;; Zeigt Uebersicht aller registrierten Zeichnungen und deren Sync-Stand
;;; ========================================================================
(defun c:LAYSTATUS ( / *error* old-cmdecho
                       master-data mapper-data
                       dwg-list dwg-entry dwg-name dwg-guid
                       total-master dwg-count dwg-missing
                       master-ids dwg-mids mid)
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg)))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  
  (setq master-data (LXI:read-master))
  (setq mapper-data (LXI:read-mapper))
  
  (if (null master-data)
    (princ "\n*** Kein Master gefunden.")
    (progn
      (setq total-master (length master-data))
      
      ;; Alle MasterIDs sammeln
      (setq master-ids nil)
      (foreach lay master-data
        (setq master-ids (cons (car lay) master-ids)))
      
      ;; Eindeutige Zeichnungen aus Mapper extrahieren (nach GUID gruppiert)
      ;; Format: '(("dwgname" "guid" count missing) ...)
      (setq dwg-list nil)
      
      (if mapper-data
        (progn
          ;; Alle eindeutigen DWG+GUID Kombinationen finden
          (foreach entry mapper-data
            (setq dwg-name (nth 0 entry))
            (setq dwg-guid (nth 1 entry))
            ;; Pruefen ob schon in dwg-list
            (if (not (assoc dwg-name dwg-list))
              (setq dwg-list
                (cons (list dwg-name dwg-guid) dwg-list))))
          
          ;; Pro Zeichnung: Layer zaehlen und fehlende ermitteln
          (princ "\n\n====== LayerSync Status ======")
          (princ (strcat "\nMaster: " (itoa total-master) " Layer"))
          (princ (strcat "\nPraefix: " *LXI:prefix* "*"))
          (princ (strcat "\nSpeicherort: " *LXI:base-path*))
          (princ "\n")
          (princ (strcat "\n"
            (LXI:pad-str "Zeichnung" 35)
            (LXI:pad-str "Layer" 8)
            (LXI:pad-str "Fehlend" 10)
            "GUID"))
          (princ (strcat "\n"
            (LXI:pad-str "-----------------------------------" 35)
            (LXI:pad-str "--------" 8)
            (LXI:pad-str "----------" 10)
            "--------------------"))
          
          (foreach dwg-entry (reverse dwg-list)
            (setq dwg-name (nth 0 dwg-entry))
            (setq dwg-guid (nth 1 dwg-entry))
            
            ;; MasterIDs dieser Zeichnung sammeln
            (setq dwg-mids nil)
            (foreach entry mapper-data
              (if (= (strcase (nth 0 entry)) (strcase dwg-name))
                (setq dwg-mids (cons (nth 4 entry) dwg-mids))))
            
            (setq dwg-count (length dwg-mids))
            
            ;; Fehlende zaehlen: MasterIDs die nicht im Mapper dieser DWG sind
            (setq dwg-missing 0)
            (foreach mid master-ids
              (if (not (member mid dwg-mids))
                (setq dwg-missing (1+ dwg-missing))))
            
            (princ (strcat "\n"
              (LXI:pad-str dwg-name 35)
              (LXI:pad-str (itoa dwg-count) 8)
              (LXI:pad-str
                (if (= dwg-missing 0) "OK"
                  (strcat (itoa dwg-missing) " fehlen"))
                10)
              (if (or (null dwg-guid) (= dwg-guid "") (= dwg-guid "NO-GUID"))
                "KEINE GUID!"
                (substr dwg-guid 1 (min 20 (strlen dwg-guid)))))))
          
          ;; Aktuelle Zeichnung markieren
          (princ "\n")
          (princ (strcat "\n  * Aktuelle Zeichnung: " (LXI:dwg-name)))
          (princ (strcat "\n  * Aktuelle GUID: " (LXI:dwg-guid)))
          (princ "\n=============================="))
        ;; Kein Mapper
        (progn
          (princ "\n\n====== LayerSync Status ======")
          (princ (strcat "\nMaster: " (itoa total-master) " Layer"))
          (princ "\nMapper: Keine Eintraege.")
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
  (setq choice (getkword "\nWas aendern? [Pfad/pRaefix/Debug] <Enter=Abbruch>: "))
  (cond
    ((= choice "Pfad")
      (progn
        (princ (strcat "\nAktuell: " *LXI:base-path*))
        (setq new-val (getstring T "\nNeuer Pfad (oder Enter=behalten): "))
        (if (and new-val (/= new-val ""))
          (progn
            (setq *LXI:base-path* new-val)
            (if (LXI:ensure-directory *LXI:base-path*)
              (progn (LXI:write-config) (princ (strcat "\nPfad geaendert: " *LXI:base-path*)))
              (progn (princ "\n*** Ordner nicht erstellt!") (setq *LXI:base-path* *LXI:default-path*))))
          (princ "\nBeibehalten."))))
    ((= choice "pRaefix")
      (progn
        (princ (strcat "\nAktuell: " *LXI:prefix*))
        (setq new-val (getstring T "\nNeues Praefix (oder Enter=behalten): "))
        (if (and new-val (/= new-val ""))
          (progn (setq *LXI:prefix* new-val) (LXI:write-config)
                 (princ (strcat "\nPraefix: " *LXI:prefix* "*")))
          (princ "\nBeibehalten."))))
    ((= choice "Debug")
      (progn (setq *LXI:debug* (not *LXI:debug*)) (LXI:write-config)
             (princ (strcat "\nDebug: " (if *LXI:debug* "ON" "OFF")))))
    (T (princ "\nKeine Aenderung.")))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Initialisierung
;;; ========================================================================
(vl-load-com)
(LXI:read-config)
(if (not (findfile (LXI:get-config-path)))
  (progn (LXI:ensure-directory *LXI:base-path*) (LXI:write-config)))
(princ "\nLayerExportImport.lsp v0.12.1 geladen.")
(princ "\nBefehle: LAYSYNC | LAYEXP | LAYIMP | LAYLOG | LAYSTATUS | LAYCFG")
(princ (strcat "\nPraefix: " *LXI:prefix* "* | Speicherort: " *LXI:base-path*))
(princ "\nTipp: LAYSYNC auf Strg+Shift+L legen (CUI)")
(princ)
;;; ========================================================================
;;; LayerExportImport.lsp
;;; Layer-Synchronisation zwischen Zeichnungen via Master-Datei
;;; MasterID-System fuer zeichnungsuebergreifendes Tracking
;;; 
;;; Version: 0.7.0
;;; Datum:   2026-03-09
;;; Autor:   Herbert Schrotter
;;;
;;; Installation:
;;;   1. APPLOAD in AutoCAD ausfuehren
;;;   2. LayerExportImport.lsp auswaehlen und laden
;;;   3. Automatisches Laden: Zu Startup Suite hinzufuegen
;;;
;;; Befehle:
;;;   LAYEXP - Exportiert Layer (S_*) in Master-Datei
;;;   LAYIMP - Importiert Layer aus Master (Master gewinnt immer)
;;;   LAYLOG - Zeigt Layer-Aenderungshistorie an
;;;   LAYCFG - Konfiguration anzeigen / aendern
;;;
;;; Dateien im LayerSync-Ordner:
;;;   LayerMaster.csv  - Layer-Daten mit MasterID (Primary Key)
;;;   LayerMapper.csv  - Handle-Zuordnung (Zeichnung+Handle -> MasterID)
;;;   LayerHistory.csv - Aenderungsprotokoll (append-only, loescht nie)
;;;   LayerSync.cfg    - Konfiguration (Pfad, Praefix, Debug)
;;; ========================================================================


;;; ========================================================================
;;; KONFIGURATION - Defaults
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
;;; CONFIG-DATEI FUNKTIONEN
;;; ========================================================================

(defun LXI:get-config-path ( / )
  (strcat *LXI:base-path* "\\LayerSync.cfg")
)

(defun LXI:read-config ( / filepath fp line pos key val)
  (setq filepath (LXI:get-config-path))
  (if (findfile filepath)
    (progn
      (setq fp (open filepath "r"))
      (if fp
        (progn
          (while (setq line (read-line fp))
            (if (and (> (strlen line) 0)
                     (/= (substr line 1 1) ";")
                     (setq pos (vl-string-search "=" line))
                )
              (progn
                (setq key (substr line 1 pos))
                (setq val (substr line (+ pos 2)))
                (cond
                  ((= key "PATH")   (setq *LXI:base-path* val))
                  ((= key "PREFIX") (setq *LXI:prefix* val))
                  ((= key "DEBUG")
                    (setq *LXI:debug* (= (strcase val) "ON")))
                )
              )
            )
          )
          (close fp)
        )
      )
    )
  )
)

(defun LXI:write-config ( / filepath fp)
  (LXI:ensure-directory *LXI:base-path*)
  (setq filepath (LXI:get-config-path))
  (setq fp (open filepath "w"))
  (if (null fp)
    nil
    (progn
      (write-line ";;; LayerSync Konfiguration v0.7.0" fp)
      (write-line ";;;" fp)
      (write-line (strcat "PATH=" *LXI:base-path*) fp)
      (write-line (strcat "PREFIX=" *LXI:prefix*) fp)
      (write-line (strcat "DEBUG=" (if *LXI:debug* "ON" "OFF")) fp)
      (close fp)
      T
    )
  )
)


;;; ========================================================================
;;; ALLGEMEINE HILFSFUNKTIONEN
;;; ========================================================================

(defun LXI:xref-layer-p (lay-name / )
  (wcmatch lay-name "*|*")
)

(defun LXI:sync-layer-p (lay-name / )
  (wcmatch lay-name (strcat *LXI:prefix* "*"))
)

(defun LXI:ensure-directory (dir-path / )
  (if (not (vl-file-directory-p dir-path))
    (vl-mkdir dir-path)
  )
  (vl-file-directory-p dir-path)
)

(defun LXI:get-sync-folder ( / )
  (if (LXI:ensure-directory *LXI:base-path*)
    *LXI:base-path*
    (progn
      (princ (strcat "\n*** Fehler: Ordner nicht verfuegbar: " *LXI:base-path*))
      nil
    )
  )
)

(defun LXI:split-string (str del / pos result part)
  (setq result nil)
  (while (setq pos (vl-string-search del str))
    (setq part (substr str 1 pos))
    (setq result (cons part result))
    (setq str (substr str (+ pos 2)))
  )
  (setq result (cons str result))
  (reverse result)
)

(defun LXI:debug-print (msg / )
  (if *LXI:debug*
    (princ (strcat "\n  [DBG] " msg))
  )
)

(defun LXI:timestamp ( / )
  (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM)")
)

(defun LXI:dwg-name ( / )
  (strcat (vl-filename-base (getvar "DWGNAME")) ".dwg")
)


;;; ========================================================================
;;; MASTERID FUNKTIONEN
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Formatiert eine ID-Nummer als M000001
;;; ------------------------------------------------------------------------
(defun LXI:format-id (num / str)
  (setq str (itoa num))
  (while (< (strlen str) 6)
    (setq str (strcat "0" str))
  )
  (strcat "M" str)
)


;;; ------------------------------------------------------------------------
;;; Ermittelt die naechste freie MasterID aus dem Master
;;; Parameter:
;;;   master-data - Aktuelle Master-Liste
;;; Rueckgabe: Naechste ID als String "M000001"
;;; ------------------------------------------------------------------------
(defun LXI:next-master-id (master-data / max-num id-str id-num)
  (setq max-num 0)
  (foreach lay master-data
    (setq id-str (car lay))
    ;; "M000042" -> 42
    (if (and id-str (> (strlen id-str) 1) (= (substr id-str 1 1) "M"))
      (progn
        (setq id-num (atoi (substr id-str 2)))
        (if (> id-num max-num)
          (setq max-num id-num)
        )
      )
    )
  )
  (LXI:format-id (1+ max-num))
)


;;; ========================================================================
;;; MASTER-DATEI FUNKTIONEN (.csv)
;;; ========================================================================
;;; Format (11 Felder):
;;;   MasterID;Name;Color;Linetype;Lineweight;Plot;OnOff;Freeze;Lock;Source;LastModified


(defun LXI:read-master ( / sync-dir filepath fp line fields result)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir)
    nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMaster.csv"))
      (if (not (findfile filepath))
        nil
        (progn
          (setq fp (open filepath "r"))
          (if (null fp)
            nil
            (progn
              (setq result nil)
              (while (setq line (read-line fp))
                (if (and (> (strlen line) 0)
                         (/= (substr line 1 1) "M")
                         (/= (substr line 1 8) "MasterID")
                    )
                  ;; Ueberspringe nur Header-Zeile
                  nil
                  ;; Datenzeilen: beginnen mit M und nicht "MasterID"
                  (if (and (> (strlen line) 0)
                           (= (substr line 1 1) "M")
                           (/= (substr line 1 8) "MasterID")
                      )
                    (progn
                      (setq fields (LXI:split-string line *LXI:sep*))
                      (if (= (length fields) 11)
                        (setq result (cons fields result))
                      )
                    )
                  )
                )
              )
              (close fp)
              (reverse result)
            )
          )
        )
      )
    )
  )
)


(defun LXI:write-master (master-data / sync-dir filepath fp lay s)
  (setq sync-dir (LXI:get-sync-folder))
  (setq s *LXI:sep*)
  (if (null sync-dir)
    nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMaster.csv"))
      (setq fp (open filepath "w"))
      (if (null fp)
        nil
        (progn
          ;; Header
          (write-line
            (strcat "MasterID" s "Name" s "Color" s "Linetype" s "Lineweight"
                    s "Plot" s "OnOff" s "Freeze" s "Lock"
                    s "Source" s "LastModified")
            fp
          )
          ;; Sortiert nach MasterID
          (setq master-data
            (vl-sort master-data '(lambda (a b) (< (car a) (car b))))
          )
          (foreach lay master-data
            (write-line
              (strcat (nth 0 lay) s (nth 1 lay) s (nth 2 lay) s
                      (nth 3 lay) s (nth 4 lay) s (nth 5 lay) s
                      (nth 6 lay) s (nth 7 lay) s (nth 8 lay) s
                      (nth 9 lay) s (nth 10 lay))
              fp
            )
          )
          (close fp)
          T
        )
      )
    )
  )
)


;;; ------------------------------------------------------------------------
;;; Sucht im Master nach MasterID
;;; ------------------------------------------------------------------------
(defun LXI:find-by-id (master-data mid / result)
  (setq result nil)
  (foreach lay master-data
    (if (= (strcase (car lay)) (strcase mid))
      (setq result lay)
    )
  )
  result
)


;;; ------------------------------------------------------------------------
;;; Sucht im Master nach Layername
;;; ------------------------------------------------------------------------
(defun LXI:find-by-name (master-data lay-name / result)
  (setq result nil)
  (foreach lay master-data
    (if (= (strcase (nth 1 lay)) (strcase lay-name))
      (setq result lay)
    )
  )
  result
)


;;; ------------------------------------------------------------------------
;;; Entfernt einen Layer aus dem Master nach MasterID
;;; ------------------------------------------------------------------------
(defun LXI:remove-by-id (master-data mid / )
  (vl-remove-if
    '(lambda (lay) (= (strcase (car lay)) (strcase mid)))
    master-data
  )
)


;;; ========================================================================
;;; MAPPER-DATEI FUNKTIONEN (.csv)
;;; ========================================================================
;;; Format (4 Felder):
;;;   DwgName;LayerName;Handle;MasterID


(defun LXI:read-mapper ( / sync-dir filepath fp line fields result)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir)
    nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMapper.csv"))
      (if (not (findfile filepath))
        nil
        (progn
          (setq fp (open filepath "r"))
          (if (null fp)
            nil
            (progn
              (setq result nil)
              (while (setq line (read-line fp))
                (if (and (> (strlen line) 0)
                         (/= (substr line 1 7) "DwgName")
                    )
                  (progn
                    (setq fields (LXI:split-string line *LXI:sep*))
                    (if (= (length fields) 4)
                      (setq result (cons fields result))
                    )
                  )
                )
              )
              (close fp)
              (reverse result)
            )
          )
        )
      )
    )
  )
)


(defun LXI:write-mapper (mapper-data / sync-dir filepath fp entry s)
  (setq sync-dir (LXI:get-sync-folder))
  (setq s *LXI:sep*)
  (if (null sync-dir)
    nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMapper.csv"))
      (setq fp (open filepath "w"))
      (if (null fp)
        nil
        (progn
          (write-line (strcat "DwgName" s "LayerName" s "Handle" s "MasterID") fp)
          (setq mapper-data
            (vl-sort mapper-data
              '(lambda (a b)
                (if (= (car a) (car b))
                  (< (cadr a) (cadr b))
                  (< (car a) (car b))
                )
              )
            )
          )
          (foreach entry mapper-data
            (write-line
              (strcat (nth 0 entry) s (nth 1 entry) s
                      (nth 2 entry) s (nth 3 entry))
              fp
            )
          )
          (close fp)
          T
        )
      )
    )
  )
)


;;; ------------------------------------------------------------------------
;;; Sucht im Mapper: Zeichnung + Handle -> MasterID
;;; ------------------------------------------------------------------------
(defun LXI:mapper-get-mid (mapper-data dwg handle / result)
  (setq result nil)
  (foreach entry mapper-data
    (if (and (= (strcase (nth 0 entry)) (strcase dwg))
             (= (strcase (nth 2 entry)) (strcase handle))
        )
      (setq result (nth 3 entry))
    )
  )
  result
)


;;; ------------------------------------------------------------------------
;;; Sucht im Mapper: Zeichnung + MasterID -> Layername
;;; ------------------------------------------------------------------------
(defun LXI:mapper-get-name (mapper-data dwg mid / result)
  (setq result nil)
  (foreach entry mapper-data
    (if (and (= (strcase (nth 0 entry)) (strcase dwg))
             (= (strcase (nth 3 entry)) (strcase mid))
        )
      (setq result (nth 1 entry))
    )
  )
  result
)


;;; ------------------------------------------------------------------------
;;; Entfernt alle Eintraege einer Zeichnung
;;; ------------------------------------------------------------------------
(defun LXI:mapper-remove-dwg (mapper-data dwg / )
  (vl-remove-if
    '(lambda (entry) (= (strcase (car entry)) (strcase dwg)))
    mapper-data
  )
)


;;; ========================================================================
;;; HISTORY-DATEI FUNKTIONEN (.csv) - APPEND ONLY
;;; ========================================================================
;;; Format (6 Felder):
;;;   Datum;Aktion;LayerName;Detail;Source;MasterID


;;; ------------------------------------------------------------------------
;;; Haengt Eintraege an die History an (erstellt Datei falls noetig)
;;; Parameter:
;;;   entries - Liste von '("datum" "aktion" "name" "detail" "source" "mid")
;;; ------------------------------------------------------------------------
(defun LXI:append-history (entries / sync-dir filepath fp entry s needs-header)
  (setq sync-dir (LXI:get-sync-folder))
  (setq s *LXI:sep*)
  (if (null sync-dir)
    nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerHistory.csv"))
      ;; Pruefen ob Header geschrieben werden muss
      (setq needs-header (not (findfile filepath)))
      ;; Append-Modus
      (setq fp (open filepath "a"))
      (if (null fp)
        nil
        (progn
          (if needs-header
            (write-line
              (strcat "Datum" s "Aktion" s "LayerName" s "Detail"
                      s "Source" s "MasterID")
              fp
            )
          )
          (foreach entry entries
            (write-line
              (strcat (nth 0 entry) s (nth 1 entry) s (nth 2 entry) s
                      (nth 3 entry) s (nth 4 entry) s (nth 5 entry))
              fp
            )
          )
          (close fp)
          T
        )
      )
    )
  )
)


;;; ------------------------------------------------------------------------
;;; Liest die komplette History
;;; Rueckgabe: Liste von History-Eintraegen (6 Felder) oder nil
;;; ------------------------------------------------------------------------
(defun LXI:read-history ( / sync-dir filepath fp line fields result)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir)
    nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerHistory.csv"))
      (if (not (findfile filepath))
        nil
        (progn
          (setq fp (open filepath "r"))
          (if (null fp)
            nil
            (progn
              (setq result nil)
              (while (setq line (read-line fp))
                (if (and (> (strlen line) 0)
                         (/= (substr line 1 5) "Datum")
                    )
                  (progn
                    (setq fields (LXI:split-string line *LXI:sep*))
                    (if (= (length fields) 6)
                      (setq result (cons fields result))
                    )
                  )
                )
              )
              (close fp)
              (reverse result)
            )
          )
        )
      )
    )
  )
)


;;; ========================================================================
;;; LAYER SAMMELN (aus aktueller Zeichnung)
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Sammelt Layer-Daten inkl. Handle (nur Sync-Praefix, ohne Xref)
;;; Rueckgabe: Liste von '("Name" "Color" ... "Handle") - 9 Felder
;;; ------------------------------------------------------------------------
(defun LXI:collect-layers ( / lay-tbl lay-name result ent-data
                              col ltype lw plot-flag on-off frz lck handle)
  (while (setq lay-tbl (tblnext "LAYER" (not lay-tbl)))
    (setq lay-name (cdr (assoc 2 lay-tbl)))
    
    (if (and (not (LXI:xref-layer-p lay-name))
             (LXI:sync-layer-p lay-name)
        )
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
        (setq plot-flag (if (or (null plot-flag) (= plot-flag 1))
                           "PLOT" "NOPLOT"))
        
        (LXI:debug-print
          (strcat "Gefunden: " lay-name " [" handle "] Farbe=" (itoa col))
        )
        
        (setq result
          (cons
            (list lay-name (itoa col) ltype lw plot-flag on-off frz lck handle)
            result
          )
        )
      )
    )
  )
  
  (if result
    (vl-sort result '(lambda (a b) (< (car a) (car b))))
  )
)


;;; ========================================================================
;;; EXPORT-LOGIK (Layer -> Master + Mapper + History)
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Vergleicht zwei Werte und gibt Aenderungs-Detail zurueck
;;; Rueckgabe: "alt->neu" oder nil wenn gleich
;;; ------------------------------------------------------------------------
(defun LXI:compare-field (old-val new-val / )
  (if (/= (strcase old-val) (strcase new-val))
    (strcat old-val "->" new-val)
    nil
  )
)


;;; ========================================================================
;;; Hauptbefehl: LAYEXP
;;; ========================================================================
(defun c:LAYEXP ( / *error* old-cmdecho
                    dwg layers master-data mapper-data
                    lay lay-name handle mid old-mid old-name
                    existing-master change-details detail
                    timestamp history-entries new-mid
                    cnt-new cnt-upd cnt-ren)
  
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (setq dwg (LXI:dwg-name))
  (setq timestamp (LXI:timestamp))
  (setq cnt-new 0 cnt-upd 0 cnt-ren 0)
  (setq history-entries nil)
  
  (setq layers (LXI:collect-layers))
  
  (if (null layers)
    (princ (strcat "\n*** Keine Layer mit Praefix \""
                   *LXI:prefix* "\" gefunden."))
    (progn
      (setq master-data (LXI:read-master))
      (if (null master-data) (setq master-data nil))
      (setq mapper-data (LXI:read-mapper))
      (if (null mapper-data) (setq mapper-data nil))
      
      (foreach lay layers
        (setq lay-name (nth 0 lay))
        (setq handle   (nth 8 lay))
        
        ;; MasterID ueber Mapper suchen (Zeichnung + Handle)
        (setq mid (LXI:mapper-get-mid mapper-data dwg handle))
        
        (cond
          ;; ============================================================
          ;; FALL 1: Handle hat MasterID -> Layer ist bekannt
          ;; ============================================================
          (mid
            (progn
              (setq existing-master (LXI:find-by-id master-data mid))
              
              (if existing-master
                (progn
                  (setq old-name (nth 1 existing-master))
                  
                  ;; Umbenennung pruefen
                  (if (/= (strcase old-name) (strcase lay-name))
                    (progn
                      (princ (strcat "\n  Umbenennung: "
                                     old-name " -> " lay-name
                                     " [" mid "]"))
                      (setq history-entries
                        (cons
                          (list timestamp "UMBENENNUNG" lay-name
                                (strcat old-name "->" lay-name) dwg mid)
                          history-entries
                        )
                      )
                      (setq cnt-ren (1+ cnt-ren))
                    )
                  )
                  
                  ;; Eigenschafts-Aenderungen pruefen und loggen
                  (setq change-details nil)
                  
                  (setq detail (LXI:compare-field (nth 2 existing-master) (nth 1 lay)))
                  (if detail
                    (setq change-details (cons (strcat "Farbe:" detail) change-details))
                  )
                  (setq detail (LXI:compare-field (nth 3 existing-master) (nth 2 lay)))
                  (if detail
                    (setq change-details (cons (strcat "Linientyp:" detail) change-details))
                  )
                  (setq detail (LXI:compare-field (nth 6 existing-master) (nth 5 lay)))
                  (if detail
                    (setq change-details (cons (strcat "OnOff:" detail) change-details))
                  )
                  (setq detail (LXI:compare-field (nth 5 existing-master) (nth 4 lay)))
                  (if detail
                    (setq change-details (cons (strcat "Plot:" detail) change-details))
                  )
                  (setq detail (LXI:compare-field (nth 7 existing-master) (nth 6 lay)))
                  (if detail
                    (setq change-details (cons (strcat "Freeze:" detail) change-details))
                  )
                  (setq detail (LXI:compare-field (nth 8 existing-master) (nth 7 lay)))
                  (if detail
                    (setq change-details (cons (strcat "Lock:" detail) change-details))
                  )
                  
                  ;; Wenn Aenderungen: History-Eintrag + Master updaten
                  (if change-details
                    (progn
                      (setq history-entries
                        (cons
                          (list timestamp "AENDERUNG" lay-name
                                (apply 'strcat
                                  (mapcar '(lambda (d) (strcat d " "))
                                    (reverse change-details)))
                                dwg mid)
                          history-entries
                        )
                      )
                      (setq cnt-upd (1+ cnt-upd))
                    )
                  )
                  
                  ;; Master-Eintrag aktualisieren (immer, auch ohne Aenderung)
                  (setq master-data (LXI:remove-by-id master-data mid))
                  (setq master-data
                    (cons
                      (list mid lay-name
                            (nth 1 lay) (nth 2 lay) (nth 3 lay)
                            (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                            dwg timestamp)
                      master-data
                    )
                  )
                )
              ) ;_ if existing-master
            )
          )
          
          ;; ============================================================
          ;; FALL 2: Kein Handle im Mapper, aber Name existiert im Master
          ;; (z.B. Layer aus Import, Mapper war noch leer fuer diese DWG)
          ;; ============================================================
          ((setq existing-master (LXI:find-by-name master-data lay-name))
            (progn
              (setq mid (car existing-master))
              (LXI:debug-print
                (strcat "Name-Match: " lay-name " -> " mid))
              ;; Master-Eintrag aktualisieren
              (setq master-data (LXI:remove-by-id master-data mid))
              (setq master-data
                (cons
                  (list mid lay-name
                        (nth 1 lay) (nth 2 lay) (nth 3 lay)
                        (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                        dwg timestamp)
                  master-data
                )
              )
              (setq cnt-upd (1+ cnt-upd))
            )
          )
          
          ;; ============================================================
          ;; FALL 3: Komplett neuer Layer
          ;; ============================================================
          (T
            (progn
              (setq new-mid (LXI:next-master-id master-data))
              (LXI:debug-print
                (strcat "Neu: " lay-name " -> " new-mid))
              (setq master-data
                (cons
                  (list new-mid lay-name
                        (nth 1 lay) (nth 2 lay) (nth 3 lay)
                        (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                        dwg timestamp)
                  master-data
                )
              )
              ;; History: NEU
              (setq history-entries
                (cons
                  (list timestamp "NEU" lay-name "" dwg new-mid)
                  history-entries
                )
              )
              (setq cnt-new (1+ cnt-new))
            )
          )
        ) ;_ cond
      ) ;_ foreach
      
      ;; Mapper aktualisieren: Eintraege dieser Zeichnung ersetzen
      (setq mapper-data (LXI:mapper-remove-dwg mapper-data dwg))
      (foreach lay layers
        (setq lay-name (nth 0 lay))
        (setq handle   (nth 8 lay))
        ;; MasterID fuer diesen Layer finden
        (setq mid (car (LXI:find-by-name master-data lay-name)))
        (if mid
          (setq mapper-data
            (cons (list dwg lay-name handle mid) mapper-data)
          )
        )
      )
      
      ;; Dateien schreiben
      (if (and (LXI:write-master master-data)
               (LXI:write-mapper mapper-data))
        (progn
          ;; History schreiben (nur wenn Eintraege vorhanden)
          (if history-entries
            (LXI:append-history (reverse history-entries))
          )
          (princ (strcat "\n--- Export Ergebnis (" dwg ") ---"))
          (princ (strcat "\n  Neu im Master:  " (itoa cnt-new)))
          (princ (strcat "\n  Aktualisiert:   " (itoa cnt-upd)))
          (princ (strcat "\n  Umbenannt:      " (itoa cnt-ren)))
          (princ (strcat "\n  Master gesamt:  "
                         (itoa (length master-data)) " Layer"))
        )
        (princ "\n*** Fehler beim Schreiben der Dateien.")
      )
    ) ;_ progn
  ) ;_ if layers
  
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ)
)


;;; ========================================================================
;;; Hauptbefehl: LAYIMP
;;; Importiert Layer aus Master. Master gewinnt immer.
;;; ========================================================================
(defun c:LAYIMP ( / *error* old-cmdecho
                    dwg master-data mapper-data
                    lay mid master-name col ltype lw plot-flag on-off frz lck
                    existing ent-data new-col changed
                    lay-tbl handle new-mapper
                    cnt-new cnt-upd cnt-skip)
  
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (setq dwg (LXI:dwg-name))
  (setq cnt-new 0 cnt-upd 0 cnt-skip 0)
  
  (setq master-data (LXI:read-master))
  
  (if (null master-data)
    (progn
      (princ "\n*** Kein LayerMaster.csv gefunden oder leer.")
      (princ (strcat "\n    Ordner: " *LXI:base-path*))
      (princ "\n    Zuerst LAYEXP in einer Zeichnung ausfuehren.")
    )
    (progn
      (princ (strcat "\n" (itoa (length master-data))
                     " Layer im Master gefunden."))
      
      (setq mapper-data (LXI:read-mapper))
      (if (null mapper-data) (setq mapper-data nil))
      
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
              lck         (nth 8 lay)
        )
        
        (LXI:debug-print (strcat "Import: " master-name " [" mid "]"))
        
        (setq existing (tblsearch "LAYER" master-name))
        
        (if existing
          ;; --- Layer existiert: Eigenschaften pruefen ---
          (progn
            (setq changed nil)
            (setq ent-data (entget (tblobjname "LAYER" master-name)))
            
            (if (/= (abs (cdr (assoc 62 ent-data))) col)
              (setq changed T))
            (if (and (cdr (assoc 6 ent-data))
                     (/= (strcase (cdr (assoc 6 ent-data))) (strcase ltype)))
              (setq changed T))
            (if (and (= on-off "OFF") (> (cdr (assoc 62 ent-data)) 0))
              (setq changed T))
            (if (and (= on-off "ON") (< (cdr (assoc 62 ent-data)) 0))
              (setq changed T))
            (if (cdr (assoc 290 ent-data))
              (if (/= (cdr (assoc 290 ent-data))
                       (if (= plot-flag "PLOT") 1 0))
                (setq changed T)))
            
            (if changed
              (progn
                (LXI:debug-print (strcat "  Update: " master-name))
                (setq new-col (if (= on-off "OFF") (- col) col))
                (setq ent-data (subst (cons 62 new-col) (assoc 62 ent-data) ent-data))
                (if (assoc 6 ent-data)
                  (setq ent-data (subst (cons 6 ltype) (assoc 6 ent-data) ent-data)))
                (if (assoc 290 ent-data)
                  (setq ent-data
                    (subst (cons 290 (if (= plot-flag "PLOT") 1 0))
                           (assoc 290 ent-data) ent-data)))
                (entmod ent-data)
                (setq cnt-upd (1+ cnt-upd))
              )
              (setq cnt-skip (1+ cnt-skip))
            )
          )
          ;; --- Neu anlegen ---
          (progn
            (LXI:debug-print (strcat "  Neu: " master-name))
            (setq new-col (if (= on-off "OFF") (- col) col))
            (entmake
              (list
                '(0 . "LAYER")
                '(100 . "AcDbSymbolTableRecord")
                '(100 . "AcDbLayerTableRecord")
                (cons 2 master-name)
                (cons 62 new-col)
                (cons 6 ltype)
                '(370 . -3)
                (cons 290 (if (= plot-flag "PLOT") 1 0))
                (cons 70 (+ (if (= frz "FROZEN") 1 0)
                            (if (= lck "LOCKED") 4 0)))
              )
            )
            (setq cnt-new (1+ cnt-new))
          )
        ) ;_ if existing
      ) ;_ foreach
      
      ;; Mapper aktualisieren mit aktuellen Handles
      (setq mapper-data (LXI:mapper-remove-dwg mapper-data dwg))
      (setq new-mapper nil)
      (while (setq lay-tbl (tblnext "LAYER" (not lay-tbl)))
        (setq lay-name (cdr (assoc 2 lay-tbl)))
        (if (and (not (LXI:xref-layer-p lay-name))
                 (LXI:sync-layer-p lay-name)
            )
          (progn
            (setq existing (LXI:find-by-name master-data lay-name))
            (if existing
              (progn
                (setq handle (cdr (assoc 5
                  (entget (tblobjname "LAYER" lay-name)))))
                (setq mid (car existing))
                (setq new-mapper
                  (cons (list dwg lay-name handle mid) new-mapper))
              )
            )
          )
        )
      )
      (setq mapper-data (append mapper-data new-mapper))
      (LXI:write-mapper mapper-data)
      
      ;; Ergebnis
      (princ (strcat "\n--- Import Ergebnis (" dwg ") ---"))
      (princ (strcat "\n  Neu angelegt:   " (itoa cnt-new)))
      (princ (strcat "\n  Aktualisiert:   " (itoa cnt-upd)))
      (princ (strcat "\n  Unveraendert:   " (itoa cnt-skip)))
    ) ;_ progn
  ) ;_ if master-data
  
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ)
)


;;; ========================================================================
;;; Hauptbefehl: LAYLOG
;;; Zeigt Layer-Aenderungshistorie an
;;; Optionen: Alle letzte / Nach Layer filtern / Nach MasterID
;;; ========================================================================
(defun c:LAYLOG ( / *error* old-cmdecho
                    choice history filter-name filter-mid
                    mapper-data master-data
                    handle mid results count entry)
  
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  
  (setq history (LXI:read-history))
  
  (if (null history)
    (princ "\n*** Keine History-Daten vorhanden.")
    (progn
      (princ (strcat "\n" (itoa (length history)) " History-Eintraege vorhanden."))
      
      ;; Auswahl
      (initget "Alle Layer")
      (setq choice
        (getkword "\nAnzeige? [Alle/Layer] <Alle>: ")
      )
      (if (null choice) (setq choice "Alle"))
      
      (cond
        ;; Alle (letzte 30)
        ((= choice "Alle")
          (progn
            (setq results (reverse history))
            (setq count (min 30 (length results)))
            (princ (strcat "\n\n=== Letzte " (itoa count) " Aenderungen ==="))
            (princ "\nDatum              Aktion        Layer                    Quelle          Detail")
            (princ "\n-----------------------------------------------------------------------------")
            (repeat count
              (setq entry (car results))
              (princ (strcat "\n"
                (nth 0 entry) "  "
                (LXI:pad-str (nth 1 entry) 13)
                (LXI:pad-str (nth 2 entry) 25)
                (LXI:pad-str (nth 4 entry) 16)
                (nth 3 entry)
              ))
              (setq results (cdr results))
            )
            (princ "\n")
          )
        )
        
        ;; Nach Layer filtern
        ((= choice "Layer")
          (progn
            (setq filter-name
              (getstring T "\nLayername (oder Teil davon): ")
            )
            (if (and filter-name (/= filter-name ""))
              (progn
                ;; Zuerst: MasterID fuer diesen Layer suchen
                ;; (ueber Mapper der aktuellen Zeichnung)
                (setq mapper-data (LXI:read-mapper))
                (setq master-data (LXI:read-master))
                (setq filter-mid nil)
                
                ;; Exakten Match im Master suchen
                (if master-data
                  (foreach lay master-data
                    (if (wcmatch (strcase (nth 1 lay))
                                 (strcat "*" (strcase filter-name) "*"))
                      (progn
                        (setq filter-mid (car lay))
                        (princ (strcat "\nGefunden: " (nth 1 lay)
                                       " [" filter-mid "]"))
                      )
                    )
                  )
                )
                
                ;; History filtern
                (if filter-mid
                  (progn
                    (setq results
                      (vl-remove-if-not
                        '(lambda (e) (= (strcase (nth 5 e)) (strcase filter-mid)))
                        history
                      )
                    )
                    (if results
                      (progn
                        (princ (strcat "\n\n=== Historie fuer " filter-name
                                       " [" filter-mid "] ==="))
                        (princ "\nDatum              Aktion        LayerName                Quelle          Detail")
                        (princ "\n-----------------------------------------------------------------------------")
                        (foreach entry results
                          (princ (strcat "\n"
                            (nth 0 entry) "  "
                            (LXI:pad-str (nth 1 entry) 13)
                            (LXI:pad-str (nth 2 entry) 25)
                            (LXI:pad-str (nth 4 entry) 16)
                            (nth 3 entry)
                          ))
                        )
                        (princ "\n")
                      )
                      (princ "\n*** Keine History-Eintraege fuer diesen Layer.")
                    )
                  )
                  ;; Fallback: nach Name in History suchen
                  (progn
                    (setq results
                      (vl-remove-if-not
                        '(lambda (e)
                          (wcmatch (strcase (nth 2 e))
                                   (strcat "*" (strcase filter-name) "*"))
                        )
                        history
                      )
                    )
                    (if results
                      (progn
                        (princ (strcat "\n\n=== Historie fuer *"
                                       filter-name "* (Namenssuche) ==="))
                        (princ "\nDatum              Aktion        LayerName                Quelle          MasterID")
                        (princ "\n-----------------------------------------------------------------------------")
                        (foreach entry results
                          (princ (strcat "\n"
                            (nth 0 entry) "  "
                            (LXI:pad-str (nth 1 entry) 13)
                            (LXI:pad-str (nth 2 entry) 25)
                            (LXI:pad-str (nth 4 entry) 16)
                            (nth 5 entry)
                          ))
                        )
                        (princ "\n")
                      )
                      (princ (strcat "\n*** Kein Layer mit \""
                                     filter-name "\" gefunden."))
                    )
                  )
                ) ;_ if filter-mid
              )
              (princ "\n*** Kein Name eingegeben.")
            )
          )
        )
      ) ;_ cond
    ) ;_ progn
  ) ;_ if history
  
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ)
)


;;; ------------------------------------------------------------------------
;;; Hilfsfunktion: String rechts mit Leerzeichen auffuellen (fuer LAYLOG)
;;; ------------------------------------------------------------------------
(defun LXI:pad-str (str width / pad)
  (if (null str) (setq str ""))
  (if (> (strlen str) width)
    (strcat (substr str 1 (- width 2)) "..")
    (progn
      (setq pad (- width (strlen str)))
      (while (> pad 0)
        (setq str (strcat str " "))
        (setq pad (1- pad))
      )
      str
    )
  )
)


;;; ========================================================================
;;; Hauptbefehl: LAYCFG
;;; ========================================================================
(defun c:LAYCFG ( / *error* old-cmdecho choice new-val)
  
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  
  (princ "\n\n=== LayerSync Konfiguration ===")
  (princ (strcat "\n  [P]fad:    " *LXI:base-path*))
  (princ (strcat "\n  P[r]aefix: " *LXI:prefix*))
  (princ (strcat "\n  [D]ebug:   " (if *LXI:debug* "ON" "OFF")))
  (princ "\n===============================\n")
  
  (initget "Pfad pRaefix Debug")
  (setq choice
    (getkword "\nWas aendern? [Pfad/pRaefix/Debug] <Enter=Abbruch>: ")
  )
  
  (cond
    ((= choice "Pfad")
      (progn
        (princ (strcat "\nAktuell: " *LXI:base-path*))
        (setq new-val (getstring T "\nNeuer Pfad (oder Enter=behalten): "))
        (if (and new-val (/= new-val ""))
          (progn
            (setq *LXI:base-path* new-val)
            (if (LXI:ensure-directory *LXI:base-path*)
              (progn
                (LXI:write-config)
                (princ (strcat "\nPfad geaendert: " *LXI:base-path*))
              )
              (progn
                (princ "\n*** Fehler: Ordner nicht erstellt!")
                (setq *LXI:base-path* *LXI:default-path*)
              )
            )
          )
          (princ "\nPfad beibehalten.")
        )
      )
    )
    ((= choice "pRaefix")
      (progn
        (princ (strcat "\nAktuell: " *LXI:prefix*))
        (setq new-val (getstring T "\nNeues Praefix (oder Enter=behalten): "))
        (if (and new-val (/= new-val ""))
          (progn
            (setq *LXI:prefix* new-val)
            (LXI:write-config)
            (princ (strcat "\nPraefix geaendert: " *LXI:prefix*))
          )
          (princ "\nPraefix beibehalten.")
        )
      )
    )
    ((= choice "Debug")
      (progn
        (setq *LXI:debug* (not *LXI:debug*))
        (LXI:write-config)
        (princ (strcat "\nDebug: " (if *LXI:debug* "ON" "OFF")))
      )
    )
    (T (princ "\nKeine Aenderung."))
  )
  
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ)
)


;;; ========================================================================
;;; Initialisierung
;;; ========================================================================
(vl-load-com)

(LXI:read-config)

(if (not (findfile (LXI:get-config-path)))
  (progn
    (LXI:ensure-directory *LXI:base-path*)
    (LXI:write-config)
  )
)

(princ "\nLayerExportImport.lsp v0.7.0 geladen.")
(princ "\nBefehle: LAYEXP | LAYIMP | LAYLOG | LAYCFG")
(princ (strcat "\nPraefix: " *LXI:prefix*
               "* | Speicherort: " *LXI:base-path*))
(princ)
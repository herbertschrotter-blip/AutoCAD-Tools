;;; ========================================================================
;;; LayerPlansatz.lsp
;;; Plansatzmanager fuer LayerSync
;;; Gruppiert Zeichnungen in Plansaetze fuer gezielten Batch-Sync
;;;
;;; Version: 1.0.1
;;; Datum:   2026-03-10
;;; Autor:   Herbert Schrotter
;;;
;;; Installation:
;;;   Wird automatisch von LayerExportImport.lsp geladen
;;;   Oder: APPLOAD > LayerPlansatz.lsp
;;;
;;; Befehle:
;;;   LAYPLAN - Plansatzmanager oeffnen
;;;
;;; Dateien:
;;;   LayerPlansatz.csv - PlansatzName;DwgName;DwgGUID
;;; ========================================================================


;;; ========================================================================
;;; PLANSATZ CSV - Lesen/Schreiben
;;; Format: PlansatzName;DwgName;DwgGUID
;;; ========================================================================

;;; Liest Plansatz-CSV
;;; Rueckgabe: Liste von '("PlansatzName" "DwgName" "DwgGUID")
(defun LXP:read-plansatz ( / sync-dir filepath fp line fields result)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir) nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerPlansatz.csv"))
      (if (not (findfile filepath)) nil
        (progn
          (setq fp (open filepath "r"))
          (if (null fp) nil
            (progn
              (setq result nil)
              (while (setq line (read-line fp))
                (if (and (> (strlen line) 0)
                         (/= (substr line 1 11) "PlansatzNam"))
                  (progn
                    (setq fields (LXI:split-string line *LXI:sep*))
                    (if (= (length fields) 3)
                      (setq result (cons fields result))))))
              (close fp) (reverse result))))))))

;;; Schreibt Plansatz-CSV
(defun LXP:write-plansatz (data / sync-dir filepath fp entry s)
  (setq sync-dir (LXI:get-sync-folder)) (setq s *LXI:sep*)
  (if (null sync-dir) nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerPlansatz.csv"))
      (setq fp (open filepath "w"))
      (if (null fp) nil
        (progn
          (write-line (strcat "PlansatzName" s "DwgName" s "DwgGUID") fp)
          (setq data (vl-sort data
            '(lambda (a b)
              (if (= (strcase (car a)) (strcase (car b)))
                (< (strcase (nth 1 a)) (strcase (nth 1 b)))
                (< (strcase (car a)) (strcase (car b)))))))
          (foreach entry data
            (if (and (nth 0 entry) (nth 1 entry))
              (write-line (strcat (nth 0 entry) s (nth 1 entry) s
                                  (if (nth 2 entry) (nth 2 entry) "")) fp)))
          (close fp) T)))))


;;; ========================================================================
;;; PLANSATZ HILFSFUNKTIONEN
;;; ========================================================================

;;; Gibt eindeutige Plansatz-Namen zurueck
(defun LXP:get-names (data / result name)
  (setq result nil)
  (foreach entry data
    (setq name (car entry))
    (if (and name (not (member (strcase name)
          (mapcar 'strcase result))))
      (setq result (cons name result))))
  (reverse result))

;;; Gibt DWGs eines Plansatzes zurueck
;;; Rueckgabe: Liste von '("DwgName" "DwgGUID")
(defun LXP:get-dwgs (data ps-name / result)
  (setq result nil)
  (foreach entry data
    (if (= (strcase (car entry)) (strcase ps-name))
      (setq result (cons (list (nth 1 entry) (nth 2 entry)) result))))
  (reverse result))

;;; Gibt alle bekannten DWGs aus dem Mapper zurueck
;;; Rueckgabe: Liste von '("DwgName" "DwgGUID")
(defun LXP:get-all-dwgs ( / mapper-data dwg-list)
  (setq mapper-data (LXI:read-mapper))
  (if (null mapper-data) nil
    (progn
      (setq dwg-list (LXI:mapper-get-dwg-list mapper-data))
      (mapcar '(lambda (e) (list (car e) (nth 1 e))) dwg-list))))

;;; Prueft ob DWG in einem Plansatz ist
;;; Rueckgabe: Plansatz-Name oder nil
(defun LXP:dwg-in-plansatz (data dwg-name / result)
  (setq result nil)
  (foreach entry data
    (if (and (null result)
             (= (strcase (nth 1 entry)) (strcase dwg-name)))
      (setq result (car entry))))
  result)

;;; Gibt alle Plansaetze einer DWG zurueck
(defun LXP:dwg-plansaetze (data dwg-name / result)
  (setq result nil)
  (foreach entry data
    (if (= (strcase (nth 1 entry)) (strcase dwg-name))
      (if (not (member (car entry) result))
        (setq result (cons (car entry) result)))))
  (reverse result))

;;; Entfernt eine DWG aus einem Plansatz
(defun LXP:remove-dwg (data ps-name dwg-name / )
  (vl-remove-if
    '(lambda (e)
      (and (= (strcase (car e)) (strcase ps-name))
           (= (strcase (nth 1 e)) (strcase dwg-name))))
    data))

;;; Fuegt eine DWG zu einem Plansatz hinzu
(defun LXP:add-dwg (data ps-name dwg-name dwg-guid / )
  (if (null dwg-guid) (setq dwg-guid ""))
  (cons (list ps-name dwg-name dwg-guid) data))

;;; Entfernt einen kompletten Plansatz
(defun LXP:remove-plansatz (data ps-name / )
  (vl-remove-if
    '(lambda (e) (= (strcase (car e)) (strcase ps-name)))
    data))


;;; ========================================================================
;;; DCL SCHREIBEN (Embedded - temp-Datei)
;;; ========================================================================

(defun LXP:write-dcl ( / filepath fp)
  (setq filepath (strcat (getvar "TEMPPREFIX") "LayerPlansatz.dcl"))
  (setq fp (open filepath "w"))
  (if (null fp) nil
    (progn
      ;; Hauptdialog
      (write-line "lxi_plansatz : dialog {" fp)
      (write-line "  label = \"LayerSync - Plansatzmanager\";" fp)
      (write-line "  initial_focus = \"ps_list\";" fp)
      (write-line "  : row {" fp)
      (write-line "    : popup_list { key = \"ps_list\"; label = \"Plansatz:\"; width = 35; }" fp)
      (write-line "    : button { key = \"ps_neu\"; label = \"Neu\"; width = 10; }" fp)
      (write-line "    : button { key = \"ps_del\"; label = \"Loeschen\"; width = 10; }" fp)
      (write-line "  }" fp)
      (write-line "  : spacer { height = 0.5; }" fp)
      (write-line "  : row {" fp)
      ;; Links: Verfuegbar
      (write-line "    : boxed_column { label = \"Verfuegbar\";" fp)
      (write-line "      : list_box { key = \"lst_free\"; multiple_select = true; height = 12; width = 35; }" fp)
      (write-line "    }" fp)
      ;; Mitte: Buttons
      (write-line "    : column {" fp)
      (write-line "      : spacer { height = 2; }" fp)
      (write-line "      : button { key = \"btn_add\"; label = \"  >>  \"; width = 8; }" fp)
      (write-line "      : spacer { height = 0.3; }" fp)
      (write-line "      : button { key = \"btn_rem\"; label = \"  <<  \"; width = 8; }" fp)
      (write-line "      : spacer { height = 0.5; }" fp)
      (write-line "      : button { key = \"btn_add_all\"; label = \"Alle>>\"; width = 8; }" fp)
      (write-line "      : spacer { height = 0.3; }" fp)
      (write-line "      : button { key = \"btn_rem_all\"; label = \"<<Alle\"; width = 8; }" fp)
      (write-line "    }" fp)
      ;; Rechts: Im Plansatz
      (write-line "    : boxed_column { label = \"Im Plansatz\";" fp)
      (write-line "      : list_box { key = \"lst_plan\"; multiple_select = true; height = 12; width = 35; }" fp)
      (write-line "    }" fp)
      (write-line "  }" fp)
      ;; Info
      (write-line "  : text { key = \"info\"; label = \"\"; }" fp)
      (write-line "  : spacer { height = 0.3; }" fp)
      ;; Aktionen
      (write-line "  : boxed_row { label = \"Aktionen\";" fp)
      (write-line "    : button { key = \"sync_plan\"; label = \"Sync Plansatz\"; width = 16; }" fp)
      (write-line "    : button { key = \"diff_plan\"; label = \"Diff Plansatz\"; width = 16; }" fp)
      (write-line "  }" fp)
      ;; Optionen
      (write-line "  : boxed_row { label = \"Optionen\";" fp)
      (write-line "    : toggle { key = \"autosync\"; label = \"AutoSync beim Speichern\"; }" fp)
      (write-line "    : toggle { key = \"notify\"; label = \"Notification beim Oeffnen\"; }" fp)
      (write-line "  }" fp)
      (write-line "  ok_cancel;" fp)
      (write-line "}" fp)
      (write-line "" fp)
      ;; Sub-Dialog: Neuer Plansatz
      (write-line "lxi_ps_neu : dialog {" fp)
      (write-line "  label = \"Neuer Plansatz\";" fp)
      (write-line "  : edit_box { key = \"ps_name\"; label = \"Name:\"; width = 30; }" fp)
      (write-line "  ok_cancel;" fp)
      (write-line "}" fp)
      (close fp)
      filepath)))


;;; ========================================================================
;;; DIALOG HILFSFUNKTIONEN
;;; ========================================================================

;;; Fuellt eine Listbox mit String-Liste
(defun LXP:fill-listbox (key items / idx)
  (start_list key)
  (foreach item items (add_list item))
  (end_list))

;;; Liest Mehrfachauswahl aus Listbox
;;; Rueckgabe: Liste von Indices (Integer)
(defun LXP:get-selection (key / sel-str)
  (setq sel-str (get_tile key))
  (if (or (null sel-str) (= sel-str ""))
    nil
    (mapcar 'atoi (LXI:split-string sel-str " "))))

;;; Gibt Sync-Status einer DWG als String
(defun LXP:dwg-status (dwg-name / master-data cnt-sync cnt-diff
                         lay master-name col ltype lw plot-flag
                         on-off frz lck vpdef desc trans diffs)
  (setq master-data (LXI:read-master))
  (if (null master-data) "kein Master"
    (progn
      (setq cnt-sync 0 cnt-diff 0)
      (foreach lay master-data
        (setq master-name (nth 1 lay))
        (if (tblsearch "LAYER" master-name)
          (progn
            (setq col (nth 2 lay) ltype (nth 3 lay) lw (nth 4 lay)
                  plot-flag (nth 5 lay) on-off (nth 6 lay)
                  frz (nth 7 lay) lck (nth 8 lay)
                  vpdef (nth 9 lay) desc (nth 10 lay) trans (nth 11 lay))
            (setq diffs (LXI:compare-layer-props
              master-name col ltype lw plot-flag on-off frz lck vpdef desc trans))
            (if diffs (setq cnt-diff (1+ cnt-diff))
              (setq cnt-sync (1+ cnt-sync))))))
      (if (= cnt-diff 0)
        (strcat (itoa cnt-sync) " sync")
        (strcat (itoa cnt-sync) " sync, " (itoa cnt-diff) " diff")))))


;;; ========================================================================
;;; DIALOG STATE (Globale Variablen fuer Dialog-Callbacks)
;;; ========================================================================
(setq *LXP:ps-data*     nil)  ;; Plansatz-CSV Daten
(setq *LXP:ps-names*    nil)  ;; Liste der Plansatz-Namen
(setq *LXP:cur-ps*      nil)  ;; Aktueller Plansatz-Name
(setq *LXP:all-dwgs*    nil)  ;; Alle bekannten DWGs '("Name" "GUID")
(setq *LXP:free-dwgs*   nil)  ;; Verfuegbare DWGs (nicht im Plansatz)
(setq *LXP:plan-dwgs*   nil)  ;; DWGs im aktuellen Plansatz
(setq *LXP:changed*     nil)  ;; Wurde etwas geaendert?
(setq *LXP:dcl-id*      nil)  ;; DCL-File Handle
(setq *LXP:new-name*    nil)  ;; Temp: Name aus Sub-Dialog


;;; ========================================================================
;;; DIALOG REFRESH - Aktualisiert Listen nach Aenderung
;;; ========================================================================

(defun LXP:refresh-lists ( / plan-names free-names)
  ;; DWGs im Plansatz
  (setq *LXP:plan-dwgs* (LXP:get-dwgs *LXP:ps-data* *LXP:cur-ps*))
  ;; Verfuegbare = Alle minus im Plansatz
  (setq *LXP:free-dwgs*
    (vl-remove-if
      '(lambda (d)
        (member (strcase (car d))
          (mapcar '(lambda (p) (strcase (car p))) *LXP:plan-dwgs*)))
      *LXP:all-dwgs*))
  ;; Listen fuellen
  (setq free-names (mapcar 'car *LXP:free-dwgs*))
  (setq plan-names (mapcar 'car *LXP:plan-dwgs*))
  (LXP:fill-listbox "lst_free" free-names)
  (LXP:fill-listbox "lst_plan" plan-names)
  ;; Info-Zeile
  (set_tile "info"
    (strcat "Plansatz \"" *LXP:cur-ps* "\": "
            (itoa (length *LXP:plan-dwgs*)) " Zeichnungen")))


;;; ========================================================================
;;; DIALOG CALLBACKS
;;; ========================================================================

;;; Plansatz im Dropdown geaendert
(defun LXP:cb-plansatz-changed (val / )
  (setq *LXP:cur-ps* (nth (atoi val) *LXP:ps-names*))
  (LXP:refresh-lists))

;;; >> Button: Ausgewaehlte von links nach rechts
(defun LXP:cb-add ( / sel-indices dwg)
  (setq sel-indices (LXP:get-selection "lst_free"))
  (if sel-indices
    (progn
      (foreach idx sel-indices
        (setq dwg (nth idx *LXP:free-dwgs*))
        (if dwg
          (setq *LXP:ps-data*
            (LXP:add-dwg *LXP:ps-data* *LXP:cur-ps*
                          (car dwg) (nth 1 dwg)))))
      (setq *LXP:changed* T)
      (LXP:refresh-lists))))

;;; << Button: Ausgewaehlte von rechts nach links
(defun LXP:cb-remove ( / sel-indices dwg)
  (setq sel-indices (LXP:get-selection "lst_plan"))
  (if sel-indices
    (progn
      (foreach idx sel-indices
        (setq dwg (nth idx *LXP:plan-dwgs*))
        (if dwg
          (setq *LXP:ps-data*
            (LXP:remove-dwg *LXP:ps-data* *LXP:cur-ps* (car dwg)))))
      (setq *LXP:changed* T)
      (LXP:refresh-lists))))

;;; Alle>> Button
(defun LXP:cb-add-all ( / dwg)
  (foreach dwg *LXP:free-dwgs*
    (setq *LXP:ps-data*
      (LXP:add-dwg *LXP:ps-data* *LXP:cur-ps*
                    (car dwg) (nth 1 dwg))))
  (setq *LXP:changed* T)
  (LXP:refresh-lists))

;;; <<Alle Button
(defun LXP:cb-remove-all ( / dwg)
  (foreach dwg *LXP:plan-dwgs*
    (setq *LXP:ps-data*
      (LXP:remove-dwg *LXP:ps-data* *LXP:cur-ps* (car dwg))))
  (setq *LXP:changed* T)
  (LXP:refresh-lists))

;;; Neuer Plansatz
(defun LXP:cb-neu ( / dcl-id2 result ps-name)
  (setq *LXP:new-name* nil)
  ;; Sub-Dialog oeffnen
  (setq dcl-id2 (load_dialog
    (strcat (getvar "TEMPPREFIX") "LayerPlansatz.dcl")))
  (if (and dcl-id2 (new_dialog "lxi_ps_neu" dcl-id2))
    (progn
      ;; Name vor done_dialog in globale Variable speichern
      (action_tile "accept"
        "(setq *LXP:new-name* (get_tile \"ps_name\")) (done_dialog 1)")
      (action_tile "cancel" "(done_dialog 0)")
      (setq result (start_dialog))
      (unload_dialog dcl-id2)
      (if (and (= result 1) *LXP:new-name* (/= *LXP:new-name* ""))
        (progn
          (setq ps-name *LXP:new-name*)
          ;; Plansatz-Namen zur Liste hinzufuegen
          (setq *LXP:ps-names* (append *LXP:ps-names* (list ps-name)))
          (setq *LXP:cur-ps* ps-name)
          (setq *LXP:changed* T)
          ;; Dropdown aktualisieren
          (LXP:fill-listbox "ps_list" *LXP:ps-names*)
          (set_tile "ps_list"
            (itoa (1- (length *LXP:ps-names*))))
          (LXP:refresh-lists))))))
;;; Plansatz loeschen
(defun LXP:cb-del ( / )
  (if (and *LXP:cur-ps* (/= *LXP:cur-ps* ""))
    (progn
      (setq *LXP:ps-data* (LXP:remove-plansatz *LXP:ps-data* *LXP:cur-ps*))
      (setq *LXP:ps-names* (vl-remove *LXP:cur-ps* *LXP:ps-names*))
      (setq *LXP:changed* T)
      (if *LXP:ps-names*
        (setq *LXP:cur-ps* (car *LXP:ps-names*))
        (setq *LXP:cur-ps* ""))
      (LXP:fill-listbox "ps_list" *LXP:ps-names*)
      (if *LXP:ps-names*
        (progn
          (set_tile "ps_list" "0")
          (LXP:refresh-lists))
        (progn
          (LXP:fill-listbox "lst_free" nil)
          (LXP:fill-listbox "lst_plan" nil)
          (set_tile "info" "Kein Plansatz vorhanden."))))))

;;; Sync Plansatz
(defun LXP:cb-sync ( / )
  (if (and *LXP:cur-ps* *LXP:plan-dwgs*)
    (progn
      ;; Speichern wenn geaendert
      (if *LXP:changed*
        (progn (LXP:write-plansatz *LXP:ps-data*)
               (setq *LXP:changed* nil)))
      ;; Dialog schliessen, dann syncen
      (done_dialog 2))))

;;; Diff Plansatz
(defun LXP:cb-diff ( / )
  (if (and *LXP:cur-ps* *LXP:plan-dwgs*)
    (progn
      (if *LXP:changed*
        (progn (LXP:write-plansatz *LXP:ps-data*)
               (setq *LXP:changed* nil)))
      (done_dialog 3))))


;;; ========================================================================
;;; HAUPTDIALOG
;;; ========================================================================

(defun LXP:show-dialog ( / dcl-path dcl-id result ps-idx)
  ;; DCL schreiben
  (setq dcl-path (LXP:write-dcl))
  (if (null dcl-path)
    (progn (princ "\n*** Fehler: DCL konnte nicht erstellt werden.") nil)
    (progn
      ;; Daten laden
      (setq *LXP:ps-data* (LXP:read-plansatz))
      (if (null *LXP:ps-data*) (setq *LXP:ps-data* nil))
      (setq *LXP:all-dwgs* (LXP:get-all-dwgs))
      (setq *LXP:ps-names* (LXP:get-names *LXP:ps-data*))
      (setq *LXP:changed* nil)

      ;; Wenn keine Plansaetze: "Standard" anlegen
      (if (null *LXP:ps-names*)
        (setq *LXP:ps-names* (list "Standard")))
      (setq *LXP:cur-ps* (car *LXP:ps-names*))

      ;; DCL laden
      (setq dcl-id (load_dialog dcl-path))
      (if (null dcl-id)
        (progn (princ "\n*** Fehler: DCL konnte nicht geladen werden.") nil)
        (progn
          (if (not (new_dialog "lxi_plansatz" dcl-id))
            (progn (princ "\n*** Fehler: Dialog konnte nicht geoeffnet werden.") nil)
            (progn
              ;; Dropdown fuellen
              (LXP:fill-listbox "ps_list" *LXP:ps-names*)
              (set_tile "ps_list" "0")

              ;; Listen fuellen
              (LXP:refresh-lists)

              ;; Optionen setzen
              (set_tile "autosync" (if *LXI:autosync* "1" "0"))
              (set_tile "notify" (if *LXI:notify* "1" "0"))

              ;; Callbacks
              (action_tile "ps_list"    "(LXP:cb-plansatz-changed $value)")
              (action_tile "ps_neu"     "(LXP:cb-neu)")
              (action_tile "ps_del"     "(LXP:cb-del)")
              (action_tile "btn_add"    "(LXP:cb-add)")
              (action_tile "btn_rem"    "(LXP:cb-remove)")
              (action_tile "btn_add_all" "(LXP:cb-add-all)")
              (action_tile "btn_rem_all" "(LXP:cb-remove-all)")
              (action_tile "sync_plan"  "(LXP:cb-sync)")
              (action_tile "diff_plan"  "(LXP:cb-diff)")

              ;; OK/Cancel
              (action_tile "accept"
                (strcat "(progn"
                  " (setq *LXI:autosync* (= (get_tile \"autosync\") \"1\"))"
                  " (setq *LXI:notify* (= (get_tile \"notify\") \"1\"))"
                  " (done_dialog 1))"))
              (action_tile "cancel" "(done_dialog 0)")

              ;; Dialog starten
              (setq result (start_dialog))
              (unload_dialog dcl-id)

              ;; Temp-DCL loeschen
              (vl-catch-all-apply 'vl-file-delete (list dcl-path))

              ;; Ergebnis verarbeiten
              (cond
                ;; OK: Speichern
                ((= result 1)
                  (progn
                    (if *LXP:changed* (LXP:write-plansatz *LXP:ps-data*))
                    (if *LXI:autosync* (LXI:reactor-enable) (LXI:reactor-disable))
                    (LXI:write-config)
                    (princ "\n  Plansatzmanager: Gespeichert.")))
                ;; Sync Plansatz
                ((= result 2)
                  (progn
                    (princ (strcat "\n  Sync Plansatz: " *LXP:cur-ps*))
                    (LXP:sync-plansatz *LXP:cur-ps*)))
                ;; Diff Plansatz
                ((= result 3)
                  (progn
                    (princ (strcat "\n  Diff Plansatz: " *LXP:cur-ps*))
                    (LXP:diff-plansatz *LXP:cur-ps*)))
                ;; Cancel
                (T (princ "\n  Abgebrochen.")))

              result)))))))


;;; ========================================================================
;;; PLANSATZ SYNC/DIFF
;;; ========================================================================

;;; Synced alle DWGs im Plansatz (nutzt bestehende Batch-Logik)
(defun LXP:sync-plansatz (ps-name / ps-data plan-dwgs dwg-names
                            master-data mapper-data)
  (setq ps-data (LXP:read-plansatz))
  (setq plan-dwgs (LXP:get-dwgs ps-data ps-name))
  (if (null plan-dwgs)
    (princ (strcat "\n*** Plansatz \"" ps-name "\" ist leer."))
    (progn
      (setq dwg-names (mapcar 'car plan-dwgs))
      (princ (strcat "\n\n========================================"))
      (princ (strcat "\n  Plansatz-Sync: " ps-name
                     " (" (itoa (length dwg-names)) " Zeichnungen)"))
      (princ "\n========================================")
      ;; Zuerst aktuelle Zeichnung wenn im Plansatz
      (if (member (strcase (LXI:dwg-name))
                  (mapcar 'strcase dwg-names))
        (progn
          (princ (strcat "\n\n>> Aktuelle: " (LXI:dwg-name)))
          (LXI:do-import)
          (LXI:do-export)))
      ;; Dann die anderen (via bestehende Batch-Logik)
      (setq master-data (LXI:read-master))
      (setq mapper-data (LXI:read-mapper))
      (if master-data
        (LXP:batch-sync-dwgs dwg-names master-data mapper-data))
      (princ "\n========================================"))))

;;; Batch-Sync fuer eine Liste von DWG-Namen
(defun LXP:batch-sync-dwgs (dwg-names master-data mapper-data
                              / dwg-list dwg-entry dwg-name dwg-guid dwg-path
                                fullpath open-doc dbx-doc result current-dwg
                                cnt cnt-open cnt-dbx cnt-err
                                total-new total-upd total-skip)
  (setq current-dwg (LXI:dwg-name))
  (setq cnt 0 cnt-open 0 cnt-dbx 0 cnt-err 0
        total-new 0 total-upd 0 total-skip 0)
  (setq dwg-list (LXI:mapper-get-dwg-list mapper-data))
  (foreach dwg-entry dwg-list
    (setq dwg-name (nth 0 dwg-entry)
          dwg-guid (nth 1 dwg-entry)
          dwg-path (nth 2 dwg-entry))
    ;; Nur DWGs im Plansatz, nicht aktuelle
    (if (and (member (strcase dwg-name) (mapcar 'strcase dwg-names))
             (/= (strcase dwg-name) (strcase current-dwg)))
      (progn
        (setq cnt (1+ cnt))
        (princ (strcat "\n  [" (itoa cnt) "] " (LXI:pad-str dwg-name 28) " "))
        (setq open-doc (LXI:find-open-document dwg-name))
        (cond
          (open-doc
            (progn
              (setq cnt-open (1+ cnt-open))
              (if (or (null dwg-guid) (= dwg-guid "") (= dwg-guid "NO-GUID"))
                (setq dwg-guid (LXI:doc-get-guid open-doc)))
              (setq dwg-path (strcat (vla-get-Path open-doc) "\\"))
              (setq result (LXI:doc-sync-layers open-doc master-data))
              (setq total-new (+ total-new (nth 0 result))
                    total-upd (+ total-upd (nth 1 result))
                    total-skip (+ total-skip (nth 2 result)))
              (setq mapper-data
                (LXI:doc-update-mapper open-doc dwg-name dwg-guid
                                       dwg-path master-data mapper-data))
              (princ (strcat "[O] +" (itoa (nth 0 result))
                             " ~" (itoa (nth 1 result))
                             " =" (itoa (nth 2 result))))))
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
                              total-skip (+ total-skip (nth 2 result)))
                        (setq mapper-data
                          (LXI:dbx-update-mapper dbx-doc dwg-name dwg-guid
                                                 dwg-path master-data mapper-data))
                        (vl-catch-all-apply 'vla-SaveAs (list dbx-doc fullpath))
                        (vlax-release-object dbx-doc)
                        (princ (strcat "[D] +" (itoa (nth 0 result))
                                       " ~" (itoa (nth 1 result))
                                       " =" (itoa (nth 2 result)))))
                      (progn (princ "[!] GESPERRT")
                             (setq cnt-err (1+ cnt-err)))))))))))))
  (LXI:write-mapper mapper-data)
  (princ (strcat "\n\n  Ergebnis: " (itoa cnt) " DWGs"
                 " (" (itoa cnt-open) " offen, "
                 (itoa cnt-dbx) " DBX, "
                 (itoa cnt-err) " Fehler)"
                 " +" (itoa total-new) " ~" (itoa total-upd)
                 " =" (itoa total-skip))))

;;; Diff fuer alle DWGs im Plansatz
(defun LXP:diff-plansatz (ps-name / ps-data plan-dwgs dwg-names)
  (setq ps-data (LXP:read-plansatz))
  (setq plan-dwgs (LXP:get-dwgs ps-data ps-name))
  (if (null plan-dwgs)
    (princ (strcat "\n*** Plansatz \"" ps-name "\" ist leer."))
    (progn
      (princ (strcat "\n\n====== Diff Plansatz: " ps-name " ======"))
      (foreach dwg plan-dwgs
        (princ (strcat "\n\n>> " (car dwg) ":"))
        ;; Nur aktuelle DWG kann per compare geprueft werden
        (if (= (strcase (car dwg)) (strcase (LXI:dwg-name)))
          (c:LAYCOUNT)
          (princ "  (nur mit LAYSYNC in dieser Zeichnung pruefbar)")))
      (princ "\n======================================"))))


;;; ========================================================================
;;; HAUPTBEFEHL: LAYPLAN
;;; ========================================================================
(defun c:LAYPLAN ( / *error* old-cmdecho)
  (defun *error* (msg)
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER: " msg))))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:log-write "=== LAYPLAN gestartet ===")
  (LXP:show-dialog)
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; API fuer LayerExportImport.lsp
;;; ========================================================================

;;; Prueft ob DWG zugeordnet ist, oeffnet ggf. Plansatzmanager
;;; Rueckgabe: T wenn DWG zugeordnet, nil wenn nicht
(defun LXP:ensure-assigned (dwg-name / ps-data ps-name)
  (setq ps-data (LXP:read-plansatz))
  (if (null ps-data)
    ;; Keine Plansaetze -> Manager oeffnen
    (progn
      (princ (strcat "\n  " dwg-name " ist keinem Plansatz zugeordnet."))
      (princ "\n  Plansatzmanager wird geoeffnet...")
      (LXP:show-dialog)
      ;; Nochmal pruefen
      (setq ps-data (LXP:read-plansatz))
      (not (null (LXP:dwg-in-plansatz ps-data dwg-name))))
    ;; Plansaetze vorhanden: ist DWG drin?
    (progn
      (setq ps-name (LXP:dwg-in-plansatz ps-data dwg-name))
      (if ps-name T
        ;; Nicht zugeordnet -> Manager oeffnen
        (progn
          (princ (strcat "\n  " dwg-name " ist keinem Plansatz zugeordnet."))
          (princ "\n  Plansatzmanager wird geoeffnet...")
          (LXP:show-dialog)
          (setq ps-data (LXP:read-plansatz))
          (not (null (LXP:dwg-in-plansatz ps-data dwg-name))))))))

;;; Gibt DWG-Namen im Plansatz der aktuellen Zeichnung zurueck
;;; Rueckgabe: Liste von DWG-Namen oder nil
(defun LXP:get-sync-targets (dwg-name / ps-data ps-names all-dwg-names)
  (setq ps-data (LXP:read-plansatz))
  (if (null ps-data) nil
    (progn
      ;; Alle Plansaetze dieser DWG
      (setq ps-names (LXP:dwg-plansaetze ps-data dwg-name))
      (if (null ps-names) nil
        (progn
          ;; Alle DWGs aus allen Plansaetzen sammeln (eindeutig)
          (setq all-dwg-names nil)
          (foreach ps ps-names
            (foreach dwg (LXP:get-dwgs ps-data ps)
              (if (not (member (strcase (car dwg))
                    (mapcar 'strcase all-dwg-names)))
                (setq all-dwg-names (cons (car dwg) all-dwg-names)))))
          (reverse all-dwg-names))))))


;;; ========================================================================
;;; Initialisierung
;;; ========================================================================
(princ "\nLayerPlansatz.lsp v1.0.1 geladen.")
(princ "\nBefehl: LAYPLAN")
(princ)
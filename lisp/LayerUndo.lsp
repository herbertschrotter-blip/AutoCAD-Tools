;;; ========================================================================
;;; LayerUndo.lsp
;;; Sync-Vorgaenge rueckgaengig machen via DCL Dialog
;;; Wird von LayerExportImport.lsp (LAYUNDO Befehl) nachgeladen
;;;
;;; Version: 1.0.0
;;; Datum:   2026-03-16
;;; Autor:   Herbert Schrotter
;;;
;;; Voraussetzungen:
;;;   LayerExportImport.lsp muss geladen sein (LXI:* Funktionen)
;;; ========================================================================


;;; ========================================================================
;;; HISTORY GRUPPIERUNG
;;; ========================================================================

;;; Gruppiert History-Eintraege nach Sync-Vorgang (Datum + Source)
;;; Nur AENDERUNG-Eintraege (die haben OldValue/NewValue fuer Undo)
;;; Rueckgabe: Liste von (("key" "label" count (entry1 entry2 ...)) ...)
;;;   Sortiert nach Datum absteigend (neuester zuerst)
(defun LXI:group-sync-ops (history / groups key label entry
                             grp found cnt)
  (setq groups nil)
  (foreach entry (reverse history)
    ;; Nur AENDERUNG hat OldValue/NewValue
    (if (= (nth 3 entry) "AENDERUNG")
      (progn
        ;; Key = Datum|Source (z.B. "2026-03-16 20:10|Schnitt B-B.dwg")
        (setq key (strcat (nth 2 entry) "|" (nth 7 entry)))
        (setq found nil)
        (setq groups
          (mapcar
            '(lambda (grp)
              (if (= (nth 0 grp) key)
                (progn
                  (setq found T)
                  (list (nth 0 grp) (nth 1 grp)
                        (1+ (nth 2 grp))
                        (append (nth 3 grp) (list entry))))
                grp))
            groups))
        (if (null found)
          (progn
            (setq label (strcat (nth 2 entry) "  "
                                (nth 7 entry)))
            (setq groups
              (append groups
                (list (list key label 1 (list entry))))))))))
  ;; Umkehren: neuester zuerst
  (reverse groups))

;;; Erzeugt Anzeige-Strings fuer die Sync-Liste
;;; Rueckgabe: Liste von Strings "2026-03-16 20:10 | DWG-A.dwg | 3 Aenderungen"
(defun LXI:format-sync-list (groups / )
  (mapcar
    '(lambda (grp)
      (strcat (nth 1 grp) "  (" (itoa (nth 2 grp)) ")"))
    groups))

;;; Erzeugt Detail-Strings fuer die Aenderungs-Liste
;;; Parameter: entries - Liste von History-Eintraegen (8 Felder)
;;; Rueckgabe: Liste von Strings "S_00_Wand | Color | 7 | 1"
(defun LXI:format-detail-list (entries / )
  (mapcar
    '(lambda (e)
      (strcat (LXI:pad-str (nth 1 e) 25)
              (LXI:pad-str (nth 4 e) 14)
              (LXI:pad-str (nth 5 e) 14)
              (nth 6 e)))
    entries))


;;; ========================================================================
;;; DCL DEFINITION (Embedded)
;;; ========================================================================

(defun LXI:undo-dcl-content ( / )
  (strcat
    "layundo : dialog {\n"
    "  label = \"LayerSync Undo\";\n"
    "  : column {\n"
    "    : text { label = \"Sync-Vorgaenge (neueste zuerst):\"; }\n"
    "    : list_box {\n"
    "      key = \"sync_list\";\n"
    "      width = 70;\n"
    "      height = 8;\n"
    "    }\n"
    "    spacer;\n"
    "    : text { label = \"Aenderungen im gewaehlten Sync:\"; }\n"
    "    : text { key = \"detail_header\"; label = \"Layer                    Property      Alt           Neu\"; }\n"
    "    : list_box {\n"
    "      key = \"detail_list\";\n"
    "      width = 70;\n"
    "      height = 12;\n"
    "      multiple_select = false;\n"
    "    }\n"
    "    spacer;\n"
    "    : text { key = \"info_text\"; label = \"\"; }\n"
    "  }\n"
    "  : row {\n"
    "    : button {\n"
    "      key = \"undo_btn\";\n"
    "      label = \"Rueckgaengig\";\n"
    "      width = 18;\n"
    "      is_enabled = false;\n"
    "    }\n"
    "    : button {\n"
    "      key = \"cancel\";\n"
    "      label = \"Schliessen\";\n"
    "      width = 18;\n"
    "      is_cancel = true;\n"
    "    }\n"
    "  }\n"
    "}\n"))


;;; ========================================================================
;;; UNDO AUSFUEHREN
;;; ========================================================================

;;; Schreibt OldValues aus History zurueck in den Master
;;; Parameter: entries - Liste von History-Eintraegen (8 Felder)
;;; Rueckgabe: Anzahl zurueckgeschriebener Properties
(defun LXI:execute-undo (entries / master-data mid lay entry
                           prop-name old-val existing prop-idx
                           cnt timestamp dwg history-entries)
  (setq master-data (LXI:read-master))
  (if (null master-data)
    (progn (princ "\n*** Kein Master.") 0)
    (progn
      (setq cnt 0)
      (setq timestamp (LXI:timestamp))
      (setq dwg (LXI:dwg-name))
      (setq history-entries nil)
      (foreach entry entries
        (setq mid (nth 0 entry)
              prop-name (nth 4 entry)
              old-val (nth 5 entry))
        (setq existing (LXI:find-by-id master-data mid))
        (if existing
          (progn
            ;; Property-Index im Master bestimmen
            ;; Master: 2=Color 3=Ltype 4=LW 5=Plot 6=OnOff
            ;;         7=Frz 8=Lock 9=VPDef 10=Desc 11=Trans
            (setq prop-idx
              (cond
                ((= prop-name "Color") 2)
                ((= prop-name "Linetype") 3)
                ((= prop-name "Lineweight") 4)
                ((= prop-name "Plot") 5)
                ((= prop-name "OnOff") 6)
                ((= prop-name "Freeze") 7)
                ((= prop-name "Lock") 8)
                ((= prop-name "VPDefault") 9)
                ((= prop-name "Description") 10)
                ((= prop-name "Transparency") 11)
                (T nil)))
            (if prop-idx
              (progn
                ;; Master-Eintrag aktualisieren
                (setq master-data (LXI:remove-by-id master-data mid))
                ;; Neuen Eintrag mit OldValue an der richtigen Stelle
                (setq lay (copy-list existing))
                ;; nth setzen via subst-nth
                (setq lay (LXI:list-set-nth lay prop-idx old-val))
                ;; Mod-Stamp fuer dieses Feld aktualisieren (Index + 10)
                (setq lay (LXI:list-set-nth lay (+ prop-idx 10)
                            (LXI:make-mod-stamp timestamp dwg)))
                ;; Source + LastModified
                (setq lay (LXI:list-set-nth lay 22 dwg))
                (setq lay (LXI:list-set-nth lay 23 timestamp))
                (setq master-data (cons lay master-data))
                ;; History-Eintrag fuer Undo
                (setq history-entries
                  (cons (list mid (nth 1 existing) timestamp "UNDO"
                              prop-name (nth prop-idx existing) old-val dwg)
                        history-entries))
                (setq cnt (1+ cnt)))))))
      ;; Master schreiben
      (if (> cnt 0)
        (progn
          (LXI:write-master master-data)
          (if history-entries
            (LXI:append-history (reverse history-entries)))
          (LXI:log-write (strcat "UNDO: " (itoa cnt) " Properties zurueckgesetzt"))))
      cnt)))

;;; Hilfsfunktion: Element an Index in Liste ersetzen
(defun LXI:list-set-nth (lst idx val / i result)
  (setq i 0 result nil)
  (foreach elem lst
    (if (= i idx)
      (setq result (cons val result))
      (setq result (cons elem result)))
    (setq i (1+ i)))
  (reverse result))

;;; Kopiert eine Liste (flach)
(defun copy-list (lst / ) (mapcar '(lambda (x) x) lst))


;;; ========================================================================
;;; DCL DIALOG
;;; ========================================================================

;;; Globale Variablen fuer Dialog-Callbacks
(setq *LXI:undo-groups* nil)
(setq *LXI:undo-selected* nil)
(setq *LXI:undo-result* nil)

(defun LXI:run-undo-dialog ( / history groups dcl-path dcl-fp
                               dcl-id dlg-id sync-strings sel-idx)
  ;; History lesen und gruppieren
  (setq history (LXI:read-history))
  (if (or (null history) (= (length history) 0))
    (progn (princ "\n*** Keine History vorhanden.") nil)
    (progn
      (setq groups (LXI:group-sync-ops history))
      (if (or (null groups) (= (length groups) 0))
        (progn (princ "\n*** Keine Aenderungen in History.") nil)
        (progn
          ;; Max 10 Gruppen anzeigen
          (if (> (length groups) 10)
            (setq groups (LXI:take-n groups 10)))
          (setq *LXI:undo-groups* groups)
          (setq *LXI:undo-selected* nil)
          (setq *LXI:undo-result* nil)
          ;; DCL temp-Datei schreiben
          (setq dcl-path (strcat (getvar "TEMPPREFIX") "layundo.dcl"))
          (setq dcl-fp (open dcl-path "w"))
          (if (null dcl-fp)
            (progn (princ "\n*** DCL-Datei konnte nicht erstellt werden.") nil)
            (progn
              (write-line (LXI:undo-dcl-content) dcl-fp)
              (close dcl-fp)
              ;; Dialog laden
              (setq dcl-id (load_dialog dcl-path))
              (if (< dcl-id 0)
                (progn (princ "\n*** DCL konnte nicht geladen werden.") nil)
                (progn
                  (if (not (new_dialog "layundo" dcl-id))
                    (progn (princ "\n*** Dialog konnte nicht erstellt werden.")
                           (unload_dialog dcl-id) nil)
                    (progn
                      ;; Sync-Liste fuellen
                      (setq sync-strings (LXI:format-sync-list groups))
                      (start_list "sync_list")
                      (foreach s sync-strings (add_list s))
                      (end_list)
                      ;; Detail-Liste leer
                      (start_list "detail_list")
                      (end_list)
                      ;; Callbacks
                      (action_tile "sync_list"
                        "(LXI:undo-on-sync-select $value)")
                      (action_tile "undo_btn"
                        "(LXI:undo-on-confirm)(done_dialog 1)")
                      (action_tile "cancel"
                        "(done_dialog 0)")
                      ;; Dialog anzeigen
                      (setq dlg-id (start_dialog))
                      (unload_dialog dcl-id)
                      ;; Temp-Datei loeschen
                      (vl-file-delete dcl-path)
                      ;; Ergebnis verarbeiten
                      (if (and (= dlg-id 1) *LXI:undo-result*)
                        (progn
                          (princ (strcat "\n  UNDO: "
                            (itoa *LXI:undo-result*)
                            " Properties zurueckgesetzt."))
                          (princ "\n  LAYSYNC empfohlen um Aenderungen zu uebernehmen."))
                        (princ "\n  Abgebrochen."))))))
              )))))))

;;; Hilfsfunktion: Erste n Elemente einer Liste
(defun LXI:take-n (lst n / result i)
  (setq result nil i 0)
  (foreach elem lst
    (if (< i n) (setq result (cons elem result)))
    (setq i (1+ i)))
  (reverse result))


;;; ========================================================================
;;; DCL CALLBACKS
;;; ========================================================================

;;; Sync-Vorgang ausgewaehlt -> Details anzeigen
(defun LXI:undo-on-sync-select (val / idx grp entries detail-strings)
  (setq idx (atoi val))
  (if (and *LXI:undo-groups* (< idx (length *LXI:undo-groups*)))
    (progn
      (setq grp (nth idx *LXI:undo-groups*))
      (setq entries (nth 3 grp))
      (setq *LXI:undo-selected* entries)
      ;; Detail-Liste fuellen
      (setq detail-strings (LXI:format-detail-list entries))
      (start_list "detail_list")
      (foreach s detail-strings (add_list s))
      (end_list)
      ;; Info-Text
      (set_tile "info_text"
        (strcat (itoa (length entries))
                " Aenderungen. Rueckgaengig setzt alle auf Alt-Werte."))
      ;; Undo-Button aktivieren
      (mode_tile "undo_btn" 0))))

;;; Undo bestaetigt -> ausfuehren
(defun LXI:undo-on-confirm ( / cnt)
  (if *LXI:undo-selected*
    (progn
      (setq cnt (LXI:execute-undo *LXI:undo-selected*))
      (setq *LXI:undo-result* cnt))))


;;; ========================================================================
;;; Initialisierung
;;; ========================================================================
(princ "\nLayerUndo.lsp v1.0.0 geladen.")
(princ)
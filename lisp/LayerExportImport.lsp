;;; ========================================================================
;;; LayerExportImport.lsp
;;; Layer-Synchronisation zwischen Zeichnungen via Master-Datei
;;; Erkennt Umbenennungen via Handle-Mapping
;;; 
;;; Version: 0.5.0
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
;;;   LAYCFG - Konfiguration anzeigen / aendern
;;;
;;; Dateien im LayerSync-Ordner:
;;;   LayerMaster.txt  - Layer-Daten (Name, Farbe, Linientyp, ...)
;;;   LayerMapper.txt  - Handle-Zuordnung (Zeichnung > Layer > Handle)
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

;; Aktive Config (wird beim Laden aus .cfg gelesen)
(setq *LXI:base-path* *LXI:default-path*)
(setq *LXI:prefix*    *LXI:default-prefix*)
(setq *LXI:debug*     nil)


;;; ========================================================================
;;; CONFIG-DATEI FUNKTIONEN
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Gibt Pfad zur Config-Datei zurueck
;;; Config liegt immer im Basispfad (auch wenn Pfad geaendert wird,
;;; wird Config im AKTUELLEN Pfad gesucht/geschrieben)
;;; ------------------------------------------------------------------------
(defun LXI:get-config-path ( / )
  (strcat *LXI:base-path* "\\LayerSync.cfg")
)


;;; ------------------------------------------------------------------------
;;; Liest Config-Datei und setzt globale Variablen
;;; Format: Key=Value pro Zeile
;;; ------------------------------------------------------------------------
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
                    (setq *LXI:debug* (= (strcase val) "ON"))
                  )
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


;;; ------------------------------------------------------------------------
;;; Schreibt Config-Datei mit aktuellen Einstellungen
;;; Rueckgabe: T bei Erfolg
;;; ------------------------------------------------------------------------
(defun LXI:write-config ( / filepath fp)
  ;; Ordner sicherstellen
  (LXI:ensure-directory *LXI:base-path*)
  (setq filepath (LXI:get-config-path))
  (setq fp (open filepath "w"))
  (if (null fp)
    (progn
      (princ (strcat "\n*** Fehler: Kann Config nicht schreiben: " filepath))
      nil
    )
    (progn
      (write-line ";;; LayerSync Konfiguration v0.5.0" fp)
      (write-line ";;; Aenderungen ueber LAYCFG Befehl oder manuell hier" fp)
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


;;; ------------------------------------------------------------------------
;;; Prueft ob ein Layername von einem Xref stammt
;;; ------------------------------------------------------------------------
(defun LXI:xref-layer-p (lay-name / )
  (wcmatch lay-name "*|*")
)


;;; ------------------------------------------------------------------------
;;; Prueft ob ein Layer zum Sync-Praefix passt
;;; ------------------------------------------------------------------------
(defun LXI:sync-layer-p (lay-name / pattern)
  (setq pattern (strcat *LXI:prefix* "*"))
  (wcmatch lay-name pattern)
)


;;; ------------------------------------------------------------------------
;;; Erstellt Ordner falls nicht vorhanden
;;; ------------------------------------------------------------------------
(defun LXI:ensure-directory (dir-path / )
  (if (not (vl-file-directory-p dir-path))
    (vl-mkdir dir-path)
  )
  (vl-file-directory-p dir-path)
)


;;; ------------------------------------------------------------------------
;;; Gibt den LayerSync-Ordner zurueck, erstellt ihn falls noetig
;;; ------------------------------------------------------------------------
(defun LXI:get-sync-folder ( / )
  (if (LXI:ensure-directory *LXI:base-path*)
    *LXI:base-path*
    (progn
      (princ (strcat "\n*** Fehler: Ordner nicht verfuegbar: " *LXI:base-path*))
      nil
    )
  )
)


;;; ------------------------------------------------------------------------
;;; Splittet einen String am Trennzeichen
;;; ------------------------------------------------------------------------
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


;;; ------------------------------------------------------------------------
;;; Debug-Ausgabe (nur wenn Debug aktiv)
;;; ------------------------------------------------------------------------
(defun LXI:debug-print (msg / )
  (if *LXI:debug*
    (princ (strcat "\n  [DBG] " msg))
  )
)


;;; ------------------------------------------------------------------------
;;; Aktuelles Datum/Uhrzeit als String
;;; ------------------------------------------------------------------------
(defun LXI:timestamp ( / )
  (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM)")
)


;;; ------------------------------------------------------------------------
;;; Aktueller Zeichnungsname (Dateiname mit .dwg)
;;; ------------------------------------------------------------------------
(defun LXI:dwg-name ( / )
  (strcat (vl-filename-base (getvar "DWGNAME")) ".dwg")
)


;;; ========================================================================
;;; MASTER-DATEI FUNKTIONEN
;;; ========================================================================
;;; Format (Tab-getrennt, 10 Felder):
;;;   Name  Color  Linetype  Lineweight  Plot  OnOff  Freeze  Lock  Source  LastModified


;;; ------------------------------------------------------------------------
;;; Liest den Master ein
;;; Rueckgabe: Liste von Layer-Listen (10 Felder) oder nil
;;; ------------------------------------------------------------------------
(defun LXI:read-master ( / sync-dir filepath fp line fields result sep)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir)
    nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMaster.txt"))
      (setq sep "\t")
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
                         (/= (substr line 1 3) ";;;")
                         (/= (substr line 1 4) "Name")
                    )
                  (progn
                    (setq fields (LXI:split-string line sep))
                    (if (= (length fields) 10)
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


;;; ------------------------------------------------------------------------
;;; Schreibt den Master
;;; Rueckgabe: T bei Erfolg
;;; ------------------------------------------------------------------------
(defun LXI:write-master (master-data / sync-dir filepath fp lay sep)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir)
    nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMaster.txt"))
      (setq sep "\t")
      (setq fp (open filepath "w"))
      (if (null fp)
        (progn
          (princ (strcat "\n*** Fehler: Kann Master nicht schreiben: " filepath))
          nil
        )
        (progn
          (write-line ";;; LayerMaster v0.5.0" fp)
          (write-line (strcat ";;; Letzte Aktualisierung: " (LXI:timestamp)) fp)
          (write-line (strcat ";;; Anzahl Layer: " (itoa (length master-data))) fp)
          (write-line (strcat ";;; Praefix: " *LXI:prefix*) fp)
          (write-line ";;;" fp)
          (write-line
            (strcat "Name" sep "Color" sep "Linetype" sep "Lineweight"
                    sep "Plot" sep "OnOff" sep "Freeze" sep "Lock"
                    sep "Source" sep "LastModified")
            fp
          )
          ;; Alphabetisch sortiert
          (setq master-data
            (vl-sort master-data '(lambda (a b) (< (car a) (car b))))
          )
          (foreach lay master-data
            (write-line
              (strcat (nth 0 lay) sep (nth 1 lay) sep (nth 2 lay) sep
                      (nth 3 lay) sep (nth 4 lay) sep (nth 5 lay) sep
                      (nth 6 lay) sep (nth 7 lay) sep (nth 8 lay) sep
                      (nth 9 lay))
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
;;; Sucht einen Layer im Master nach Name
;;; ------------------------------------------------------------------------
(defun LXI:find-in-master (master-data lay-name / result)
  (setq result nil)
  (foreach lay master-data
    (if (= (strcase (car lay)) (strcase lay-name))
      (setq result lay)
    )
  )
  result
)


;;; ------------------------------------------------------------------------
;;; Entfernt einen Layer aus der Master-Liste nach Name
;;; ------------------------------------------------------------------------
(defun LXI:remove-from-master (master-data lay-name / )
  (vl-remove-if
    '(lambda (lay) (= (strcase (car lay)) (strcase lay-name)))
    master-data
  )
)


;;; ========================================================================
;;; MAPPER-DATEI FUNKTIONEN
;;; ========================================================================
;;; Format (Tab-getrennt, 3 Felder):
;;;   DwgName  LayerName  Handle


;;; ------------------------------------------------------------------------
;;; Liest den Mapper ein
;;; Rueckgabe: Liste von '("dwg" "layername" "handle") oder nil
;;; ------------------------------------------------------------------------
(defun LXI:read-mapper ( / sync-dir filepath fp line fields result sep)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir)
    nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMapper.txt"))
      (setq sep "\t")
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
                         (/= (substr line 1 3) ";;;")
                         (/= (substr line 1 3) "Dwg")
                    )
                  (progn
                    (setq fields (LXI:split-string line sep))
                    (if (= (length fields) 3)
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


;;; ------------------------------------------------------------------------
;;; Schreibt den Mapper
;;; Rueckgabe: T bei Erfolg
;;; ------------------------------------------------------------------------
(defun LXI:write-mapper (mapper-data / sync-dir filepath fp entry sep)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir)
    nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerMapper.txt"))
      (setq sep "\t")
      (setq fp (open filepath "w"))
      (if (null fp)
        (progn
          (princ (strcat "\n*** Fehler: Kann Mapper nicht schreiben: " filepath))
          nil
        )
        (progn
          (write-line ";;; LayerMapper v0.5.0" fp)
          (write-line (strcat ";;; Letzte Aktualisierung: " (LXI:timestamp)) fp)
          (write-line ";;;" fp)
          (write-line (strcat "DwgName" sep "LayerName" sep "Handle") fp)
          ;; Sortiert nach Zeichnung, dann Layer
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
              (strcat (nth 0 entry) sep (nth 1 entry) sep (nth 2 entry))
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
;;; Sucht im Mapper: Zeichnung + Handle -> Layername
;;; ------------------------------------------------------------------------
(defun LXI:mapper-find-by-handle (mapper-data dwg handle / result)
  (setq result nil)
  (foreach entry mapper-data
    (if (and (= (strcase (nth 0 entry)) (strcase dwg))
             (= (strcase (nth 2 entry)) (strcase handle))
        )
      (setq result (nth 1 entry))
    )
  )
  result
)


;;; ------------------------------------------------------------------------
;;; Sucht im Mapper: Zeichnung + Layername -> Handle
;;; ------------------------------------------------------------------------
(defun LXI:mapper-find-by-name (mapper-data dwg lay-name / result)
  (setq result nil)
  (foreach entry mapper-data
    (if (and (= (strcase (nth 0 entry)) (strcase dwg))
             (= (strcase (nth 1 entry)) (strcase lay-name))
        )
      (setq result (nth 2 entry))
    )
  )
  result
)


;;; ------------------------------------------------------------------------
;;; Entfernt alle Eintraege einer Zeichnung aus dem Mapper
;;; ------------------------------------------------------------------------
(defun LXI:mapper-remove-dwg (mapper-data dwg / )
  (vl-remove-if
    '(lambda (entry) (= (strcase (car entry)) (strcase dwg)))
    mapper-data
  )
)


;;; ========================================================================
;;; LAYER SAMMELN (aus aktueller Zeichnung)
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Sammelt Layer-Daten inkl. Handle (nur Sync-Praefix, ohne Xref)
;;; Rueckgabe: Liste von '("Name" "Color" ... "Handle") - 9 Felder
;;; ------------------------------------------------------------------------
(defun LXI:collect-layers ( / lay-tbl lay-name result
                              col ltype lw plot-flag on-off frz lck handle)
  (while (setq lay-tbl (tblnext "LAYER" (not lay-tbl)))
    (setq lay-name (cdr (assoc 2 lay-tbl)))
    
    (if (and (not (LXI:xref-layer-p lay-name))
             (LXI:sync-layer-p lay-name)
        )
      (progn
        (setq col (cdr (assoc 62 lay-tbl)))
        (setq on-off (if (< col 0) "OFF" "ON"))
        (setq col (abs col))
        (setq ltype (cdr (assoc 6 lay-tbl)))
        (if (null ltype) (setq ltype "Continuous"))
        (setq frz (cdr (assoc 70 lay-tbl)))
        (setq lck frz)
        (setq frz (if (= (logand frz 1) 1) "FROZEN" "THAWED"))
        (setq lck (if (= (logand lck 4) 4) "LOCKED" "UNLOCKED"))
        (setq lw "Default")
        (setq plot-flag (cdr (assoc 290 lay-tbl)))
        (setq plot-flag (if (or (null plot-flag) (= plot-flag 1))
                           "PLOT" "NOPLOT"))
        (setq handle (cdr (assoc 5 lay-tbl)))
        
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
;;; LAYER ANWENDEN (Import in aktuelle Zeichnung)
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Wendet Master-Daten auf die aktuelle Zeichnung an
;;; Master gewinnt immer. Erkennt Umbenennungen via Mapper.
;;; Rueckgabe: Liste '(neue aktualisierte umbenannte uebersprungene)
;;; ------------------------------------------------------------------------
(defun LXI:apply-layers (master-data mapper-data dwg
                          / lay master-name col ltype lw plot-flag
                            on-off frz lck
                            existing ent-data new-col changed
                            cnt-new cnt-upd cnt-ren cnt-skip)
  (setq cnt-new 0 cnt-upd 0 cnt-ren 0 cnt-skip 0)
  
  (foreach lay master-data
    (setq master-name (nth 0 lay)
          col         (atoi (nth 1 lay))
          ltype       (nth 2 lay)
          lw          (nth 3 lay)
          plot-flag   (nth 4 lay)
          on-off      (nth 5 lay)
          frz         (nth 6 lay)
          lck         (nth 7 lay)
    )
    
    (LXI:debug-print (strcat "Verarbeite: " master-name))
    
    (setq existing (tblsearch "LAYER" master-name))
    
    (if existing
      ;; --- Layer existiert mit gleichem Namen: Eigenschaften pruefen ---
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
          (progn
            (LXI:debug-print (strcat "  Skip: " master-name " (identisch)"))
            (setq cnt-skip (1+ cnt-skip))
          )
        )
      )
      ;; --- Layer existiert NICHT: neu anlegen ---
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
  
  (list cnt-new cnt-upd cnt-ren cnt-skip)
)


;;; ========================================================================
;;; Hauptbefehl: LAYEXP
;;; Exportiert Layer in Master + aktualisiert Mapper
;;; ========================================================================
(defun c:LAYEXP ( / *error* old-cmdecho
                    dwg layers master-data mapper-data
                    lay lay-name handle old-master-name
                    timestamp cnt-new cnt-upd cnt-ren)
  
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
  
  ;; Layer sammeln
  (setq layers (LXI:collect-layers))
  
  (if (null layers)
    (princ (strcat "\n*** Keine Layer mit Praefix \""
                   *LXI:prefix* "\" zum Exportieren gefunden."))
    (progn
      ;; Master und Mapper einlesen
      (setq master-data (LXI:read-master))
      (if (null master-data) (setq master-data nil))
      (setq mapper-data (LXI:read-mapper))
      (if (null mapper-data) (setq mapper-data nil))
      
      ;; Jeden Layer verarbeiten
      (foreach lay layers
        (setq lay-name (nth 0 lay))
        (setq handle   (nth 8 lay))
        
        ;; Umbenennung pruefen via Mapper
        (setq old-master-name
          (LXI:mapper-find-by-handle mapper-data dwg handle)
        )
        
        (cond
          ;; FALL 1: Handle bekannt unter anderem Namen = Umbenennung
          ((and old-master-name
                (/= (strcase old-master-name) (strcase lay-name))
           )
            (progn
              (princ (strcat "\n  Umbenennung: "
                             old-master-name " -> " lay-name))
              (LXI:debug-print
                (strcat "Handle " handle " war " old-master-name
                        " jetzt " lay-name))
              ;; Im Master umbenennen
              (setq master-data
                (mapcar
                  '(lambda (m)
                    (if (= (strcase (car m)) (strcase old-master-name))
                      (list lay-name
                            (nth 1 lay) (nth 2 lay) (nth 3 lay)
                            (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                            dwg timestamp)
                      m
                    )
                  )
                  master-data
                )
              )
              (setq cnt-ren (1+ cnt-ren))
            )
          )
          
          ;; FALL 2: Layer existiert im Master -> updaten
          ((LXI:find-in-master master-data lay-name)
            (progn
              (LXI:debug-print (strcat "Update: " lay-name))
              (setq master-data (LXI:remove-from-master master-data lay-name))
              (setq master-data
                (cons
                  (list lay-name
                        (nth 1 lay) (nth 2 lay) (nth 3 lay)
                        (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                        dwg timestamp)
                  master-data
                )
              )
              (setq cnt-upd (1+ cnt-upd))
            )
          )
          
          ;; FALL 3: Neuer Layer -> hinzufuegen
          (T
            (progn
              (LXI:debug-print (strcat "Neu: " lay-name))
              (setq master-data
                (cons
                  (list lay-name
                        (nth 1 lay) (nth 2 lay) (nth 3 lay)
                        (nth 4 lay) (nth 5 lay) (nth 6 lay) (nth 7 lay)
                        dwg timestamp)
                  master-data
                )
              )
              (setq cnt-new (1+ cnt-new))
            )
          )
        ) ;_ cond
      ) ;_ foreach
      
      ;; Mapper: Eintraege dieser Zeichnung ersetzen
      (setq mapper-data (LXI:mapper-remove-dwg mapper-data dwg))
      (foreach lay layers
        (setq mapper-data
          (cons (list dwg (nth 0 lay) (nth 8 lay)) mapper-data)
        )
      )
      
      ;; Dateien schreiben
      (if (and (LXI:write-master master-data)
               (LXI:write-mapper mapper-data))
        (progn
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
;;; Aktualisiert Mapper nach Import.
;;; ========================================================================
(defun c:LAYIMP ( / *error* old-cmdecho
                    dwg master-data mapper-data counts
                    lay-tbl lay-name handle new-mapper)
  
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
  
  ;; Master lesen
  (setq master-data (LXI:read-master))
  
  (if (null master-data)
    (progn
      (princ "\n*** Kein LayerMaster.txt gefunden oder leer.")
      (princ (strcat "\n    Ordner: " *LXI:base-path*))
      (princ "\n    Zuerst LAYEXP in einer Zeichnung ausfuehren.")
    )
    (progn
      (princ (strcat "\n" (itoa (length master-data))
                     " Layer im Master gefunden."))
      
      ;; Mapper lesen
      (setq mapper-data (LXI:read-mapper))
      (if (null mapper-data) (setq mapper-data nil))
      
      ;; Layer anwenden (Master gewinnt)
      (setq counts (LXI:apply-layers master-data mapper-data dwg))
      
      ;; Mapper aktualisieren mit aktuellen Handles
      (setq mapper-data (LXI:mapper-remove-dwg mapper-data dwg))
      (setq new-mapper nil)
      (while (setq lay-tbl (tblnext "LAYER" (not lay-tbl)))
        (setq lay-name (cdr (assoc 2 lay-tbl)))
        (if (and (not (LXI:xref-layer-p lay-name))
                 (LXI:sync-layer-p lay-name)
                 (LXI:find-in-master master-data lay-name)
            )
          (progn
            (setq handle (cdr (assoc 5 lay-tbl)))
            (setq new-mapper
              (cons (list dwg lay-name handle) new-mapper))
          )
        )
      )
      (setq mapper-data (append mapper-data new-mapper))
      (LXI:write-mapper mapper-data)
      
      ;; Ergebnis
      (princ (strcat "\n--- Import Ergebnis (" dwg ") ---"))
      (princ (strcat "\n  Neu angelegt:   " (itoa (nth 0 counts))))
      (princ (strcat "\n  Aktualisiert:   " (itoa (nth 1 counts))))
      (princ (strcat "\n  Umbenannt:      " (itoa (nth 2 counts))))
      (princ (strcat "\n  Unveraendert:   " (itoa (nth 3 counts))))
    ) ;_ progn
  ) ;_ if master-data
  
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ)
)


;;; ========================================================================
;;; Hauptbefehl: LAYCFG
;;; Konfiguration anzeigen und interaktiv aendern
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
  
  ;; Aktuelle Config anzeigen
  (princ "\n\n=== LayerSync Konfiguration ===")
  (princ (strcat "\n  [P]fad:    " *LXI:base-path*))
  (princ (strcat "\n  P[r]aefix: " *LXI:prefix*))
  (princ (strcat "\n  [D]ebug:   " (if *LXI:debug* "ON" "OFF")))
  (princ "\n===============================\n")
  
  ;; Auswahl
  (initget "Pfad pRaefix Debug")
  (setq choice
    (getkword "\nWas aendern? [Pfad/pRaefix/Debug] <Enter=Abbruch>: ")
  )
  
  (cond
    ;; Pfad aendern
    ((= choice "Pfad")
      (progn
        (princ (strcat "\nAktuell: " *LXI:base-path*))
        (setq new-val (getstring T "\nNeuer Pfad (oder Enter=behalten): "))
        (if (and new-val (/= new-val ""))
          (progn
            (setq *LXI:base-path* new-val)
            ;; Ordner erstellen falls noetig
            (if (LXI:ensure-directory *LXI:base-path*)
              (progn
                (LXI:write-config)
                (princ (strcat "\nPfad geaendert: " *LXI:base-path*))
              )
              (progn
                (princ "\n*** Fehler: Ordner konnte nicht erstellt werden!")
                (setq *LXI:base-path* *LXI:default-path*)
              )
            )
          )
          (princ "\nPfad beibehalten.")
        )
      )
    )
    
    ;; Praefix aendern
    ((= choice "pRaefix")
      (progn
        (princ (strcat "\nAktuell: " *LXI:prefix*))
        (setq new-val (getstring T "\nNeues Praefix (oder Enter=behalten): "))
        (if (and new-val (/= new-val ""))
          (progn
            (setq *LXI:prefix* new-val)
            (LXI:write-config)
            (princ (strcat "\nPraefix geaendert: " *LXI:prefix*))
            (princ (strcat "\nLayer-Filter ist jetzt: " *LXI:prefix* "*"))
          )
          (princ "\nPraefix beibehalten.")
        )
      )
    )
    
    ;; Debug umschalten
    ((= choice "Debug")
      (progn
        (setq *LXI:debug* (not *LXI:debug*))
        (LXI:write-config)
        (princ (strcat "\nDebug ist jetzt: " (if *LXI:debug* "ON" "OFF")))
      )
    )
    
    ;; Abbruch
    (T (princ "\nKeine Aenderung."))
  )
  
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ)
)


;;; ========================================================================
;;; Initialisierung
;;; ========================================================================
(vl-load-com)

;; Config laden (falls vorhanden)
(LXI:read-config)

;; Config-Datei erstellen falls nicht vorhanden
(if (not (findfile (LXI:get-config-path)))
  (progn
    (LXI:ensure-directory *LXI:base-path*)
    (LXI:write-config)
  )
)

(princ "\nLayerExportImport.lsp v0.5.0 geladen.")
(princ "\nBefehle: LAYEXP | LAYIMP | LAYCFG")
(princ (strcat "\nPraefix: " *LXI:prefix*
               "* | Speicherort: " *LXI:base-path*))
(princ)
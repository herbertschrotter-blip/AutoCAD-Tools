;;; ========================================================================
;;; LayerExportImport.lsp
;;; Export und Import von Layer-Informationen zwischen Zeichnungen
;;; Speichert in OneDrive: ..\02_Autocad_Tools\LayerSync\
;;; 
;;; Version: 0.3.0
;;; Datum:   2026-03-09
;;; Autor:   Herbert Schrotter
;;;
;;; Installation:
;;;   1. APPLOAD in AutoCAD ausfuehren
;;;   2. LayerExportImport.lsp auswaehlen und laden
;;;   3. Automatisches Laden: Zu Startup Suite hinzufuegen
;;;
;;; Befehle:
;;;   LAYEXP - Exportiert Layer (00_, 01_, 02_) nach LayerSync-Ordner
;;;   LAYIMP - Importiert Layer aus gewaehlter TXT (Dropdown-Auswahl)
;;;
;;; Speicherort:
;;;   D:\OneDrive\Dokumente\02 Arbeit\05 Vorlagen - Scripte\
;;;   02_Autocad_Tools\LayerSync\<Zeichnungsname>_layers.txt
;;; ========================================================================


;;; ========================================================================
;;; KONFIGURATION
;;; ========================================================================
;;; Basispfad zum LayerSync-Ordner (anpassen falls OneDrive anders liegt)
(setq *LXI:base-path*
  "D:\\OneDrive\\Dokumente\\02 Arbeit\\05 Vorlagen - Scripte\\02_Autocad_Tools\\LayerSync"
)


;;; ========================================================================
;;; HILFSFUNKTIONEN
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Prueft ob ein Layername von einem Xref stammt
;;; ------------------------------------------------------------------------
(defun LXI:xref-layer-p (lay-name / )
  (wcmatch lay-name "*|*")
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
;;; Rueckgabe:
;;;   Pfad als String oder nil bei Fehler
;;; ------------------------------------------------------------------------
(defun LXI:get-sync-folder ( / )
  (if (LXI:ensure-directory *LXI:base-path*)
    *LXI:base-path*
    (progn
      (princ (strcat "\n*** Fehler: Ordner kann nicht erstellt werden:"))
      (princ (strcat "\n    " *LXI:base-path*))
      nil
    )
  )
)


;;; ------------------------------------------------------------------------
;;; Gibt den Dateipfad fuer die aktuelle Zeichnung zurueck
;;; Rueckgabe:
;;;   Voller Pfad zur Layer-TXT als String oder nil
;;; ------------------------------------------------------------------------
(defun LXI:get-layer-filepath ( / sync-dir dwg-name)
  (setq sync-dir (LXI:get-sync-folder))
  (if sync-dir
    (progn
      (setq dwg-name (vl-filename-base (getvar "DWGNAME")))
      (strcat sync-dir "\\" dwg-name "_layers.txt")
    )
  )
)


;;; ------------------------------------------------------------------------
;;; Listet alle *_layers.txt Dateien im LayerSync-Ordner
;;; Rueckgabe:
;;;   Liste von Dateinamen (nur Name ohne Pfad) oder nil
;;; ------------------------------------------------------------------------
(defun LXI:list-layer-files ( / sync-dir files result f)
  (setq sync-dir (LXI:get-sync-folder))
  (if sync-dir
    (progn
      (setq result nil)
      ;; Erste Datei suchen
      (setq f (vl-directory-files sync-dir "*_layers.txt" 1))
      (if f (setq result f))
      result
    )
  )
)


;;; ------------------------------------------------------------------------
;;; Interaktive Dateiauswahl per Keyword-Menu auf der Command-Line
;;; Parameter:
;;;   files - Liste von Dateinamen
;;; Rueckgabe:
;;;   Gewaehlter Dateiname als String oder nil bei Abbruch
;;; ------------------------------------------------------------------------
(defun LXI:select-file-interactive (files / idx display-names kw-list
                                     kw-string choice num)
  ;; Nummerierte Liste anzeigen
  (princ "\n\n=== Verfuegbare Layer-Dateien ===")
  (setq idx 0)
  (foreach f files
    (setq idx (1+ idx))
    ;; Dateiname ohne _layers.txt anzeigen (= Zeichnungsname)
    (princ (strcat "\n  [" (itoa idx) "] "
                   (vl-string-right-trim ".txt"
                     (vl-string-right-trim "_layers"
                       (vl-filename-base f)
                     )
                   )
                   "  (" f ")"
           )
    )
  )
  (princ "\n================================\n")
  
  ;; Keyword-Liste fuer initget aufbauen
  ;; Nummern 1 bis n als Keywords
  (setq kw-list nil)
  (setq idx 0)
  (foreach f files
    (setq idx (1+ idx))
    (setq kw-list (cons (itoa idx) kw-list))
  )
  (setq kw-list (reverse kw-list))
  (setq kw-string (LXI:join-strings kw-list " "))
  
  ;; User-Eingabe mit initget
  (initget kw-string)
  (setq choice
    (getkword
      (strcat "\nNummer waehlen [1-" (itoa (length files)) "]: ")
    )
  )
  
  ;; Auswahl auswerten
  (if choice
    (progn
      (setq num (atoi choice))
      (if (and (> num 0) (<= num (length files)))
        (nth (1- num) files)
        nil
      )
    )
  )
)


;;; ------------------------------------------------------------------------
;;; Verbindet eine Liste von Strings mit Trennzeichen
;;; ------------------------------------------------------------------------
(defun LXI:join-strings (str-list sep / result)
  (setq result (car str-list))
  (foreach s (cdr str-list)
    (setq result (strcat result sep s))
  )
  result
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


;;; ========================================================================
;;; LAYER SAMMELN & SCHREIBEN
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Sammelt alle Layer-Daten (nur 00_, 01_, 02_, ohne Xref)
;;; Rueckgabe:
;;;   Sortierte Liste von Layer-Datenlisten oder nil
;;; ------------------------------------------------------------------------
(defun LXI:collect-layers ( / lay-tbl lay-name result
                              col ltype lw plot-flag on-off frz lck)
  (while (setq lay-tbl (tblnext "LAYER" (not lay-tbl)))
    (setq lay-name (cdr (assoc 2 lay-tbl)))
    
    ;; Nur Layer mit Praefix 00_, 01_, 02_ (und keine Xref-Layer)
    (if (and (not (LXI:xref-layer-p lay-name))
             (wcmatch lay-name "00_*,01_*,02_*")
        )
      (progn
        ;; Farbe (DXF 62): Negativer Wert = Layer aus
        (setq col (cdr (assoc 62 lay-tbl)))
        (setq on-off (if (< col 0) "OFF" "ON"))
        (setq col (abs col))
        
        ;; Linientyp (DXF 6)
        (setq ltype (cdr (assoc 6 lay-tbl)))
        (if (null ltype) (setq ltype "Continuous"))
        
        ;; Gefroren-Status (DXF 70): Bit 1 = gefroren
        (setq frz (cdr (assoc 70 lay-tbl)))
        (setq frz (if (= (logand frz 1) 1) "FROZEN" "THAWED"))
        
        ;; Gesperrt-Status (DXF 70): Bit 4 = gesperrt
        (setq lck (cdr (assoc 70 lay-tbl)))
        (setq lck (if (= (logand lck 4) 4) "LOCKED" "UNLOCKED"))
        
        ;; Linienstaerke & Plot-Flag
        (setq lw "Default")
        (setq plot-flag (cdr (assoc 290 lay-tbl)))
        (setq plot-flag (if (or (null plot-flag) (= plot-flag 1))
                           "PLOT" "NOPLOT"))
        
        (setq result
          (cons
            (list lay-name (itoa col) ltype lw plot-flag on-off frz lck)
            result
          )
        )
      ) ;_ progn
    ) ;_ if
  ) ;_ while
  
  ;; Alphabetisch sortieren
  (if result
    (vl-sort result '(lambda (a b) (< (car a) (car b))))
  )
)


;;; ------------------------------------------------------------------------
;;; Schreibt Layer-Daten in eine TXT-Datei
;;; Rueckgabe: T bei Erfolg, nil bei Fehler
;;; ------------------------------------------------------------------------
(defun LXI:write-layer-file (filepath layer-data / fp lay sep)
  (setq sep "\t")
  (setq fp (open filepath "w"))
  (if (null fp)
    (progn
      (princ (strcat "\n*** Fehler: Kann Datei nicht oeffnen: " filepath))
      nil
    )
    (progn
      ;; Header
      (write-line ";;; LayerExport v0.3.0" fp)
      (write-line (strcat ";;; Zeichnung: " (getvar "DWGNAME")) fp)
      (write-line (strcat ";;; Datum: " (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM)")) fp)
      (write-line (strcat ";;; Anzahl Layer: " (itoa (length layer-data))) fp)
      (write-line ";;;" fp)
      
      ;; Spalten-Header
      (write-line
        (strcat "Name" sep "Color" sep "Linetype" sep "Lineweight"
                sep "Plot" sep "OnOff" sep "Freeze" sep "Lock")
        fp
      )
      
      ;; Layer-Daten
      (foreach lay layer-data
        (write-line
          (strcat (nth 0 lay) sep (nth 1 lay) sep (nth 2 lay) sep
                  (nth 3 lay) sep (nth 4 lay) sep (nth 5 lay) sep
                  (nth 6 lay) sep (nth 7 lay))
          fp
        )
      )
      (close fp)
      T
    )
  )
)


;;; ------------------------------------------------------------------------
;;; Liest Layer-Daten aus einer TXT-Datei
;;; Rueckgabe: Liste von Layer-Datenlisten oder nil
;;; ------------------------------------------------------------------------
(defun LXI:read-layer-file (filepath / fp line fields result sep)
  (setq sep "\t")
  (setq fp (open filepath "r"))
  (if (null fp)
    (progn
      (princ (strcat "\n*** Fehler: Kann Datei nicht oeffnen: " filepath))
      nil
    )
    (progn
      (setq result nil)
      (while (setq line (read-line fp))
        ;; Kommentarzeilen und Header-Zeile ueberspringen
        (if (and (> (strlen line) 0)
                 (/= (substr line 1 3) ";;;")
                 (/= (substr line 1 4) "Name")
            )
          (progn
            (setq fields (LXI:split-string line sep))
            (if (= (length fields) 8)
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


;;; ========================================================================
;;; LAYER IMPORTIEREN (ANLEGEN / UPDATEN)
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Wendet Layer-Daten auf die aktuelle Zeichnung an
;;; Rueckgabe: Liste '(neue geaenderte uebersprungene)
;;; ------------------------------------------------------------------------
(defun LXI:apply-layers (layer-data / lay lay-name col ltype lw
                          plot-flag on-off frz lck
                          existing ent-data new-col
                          cnt-new cnt-upd cnt-skip changed)
  (setq cnt-new 0 cnt-upd 0 cnt-skip 0)
  
  (foreach lay layer-data
    (setq lay-name  (nth 0 lay)
          col       (atoi (nth 1 lay))
          ltype     (nth 2 lay)
          lw        (nth 3 lay)
          plot-flag (nth 4 lay)
          on-off    (nth 5 lay)
          frz       (nth 6 lay)
          lck       (nth 7 lay)
    )
    
    (setq existing (tblsearch "LAYER" lay-name))
    
    (if (null existing)
      ;; --- NEUER LAYER ---
      (progn
        (setq new-col (if (= on-off "OFF") (- col) col))
        (entmake
          (list
            '(0 . "LAYER")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbLayerTableRecord")
            (cons 2 lay-name)
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
      ;; --- VORHANDENER LAYER: vergleichen & updaten ---
      (progn
        (setq changed nil)
        (setq ent-data (entget (tblobjname "LAYER" lay-name)))
        
        ;; Farbe pruefen
        (if (/= (abs (cdr (assoc 62 ent-data))) col)
          (setq changed T)
        )
        ;; Linientyp pruefen
        (if (and (cdr (assoc 6 ent-data))
                 (/= (strcase (cdr (assoc 6 ent-data)))
                      (strcase ltype)))
          (setq changed T)
        )
        ;; On/Off pruefen
        (if (and (= on-off "OFF") (> (cdr (assoc 62 ent-data)) 0))
          (setq changed T)
        )
        (if (and (= on-off "ON") (< (cdr (assoc 62 ent-data)) 0))
          (setq changed T)
        )
        ;; Plot-Flag pruefen
        (if (cdr (assoc 290 ent-data))
          (if (/= (cdr (assoc 290 ent-data))
                   (if (= plot-flag "PLOT") 1 0))
            (setq changed T)
          )
        )
        
        (if changed
          (progn
            (setq new-col (if (= on-off "OFF") (- col) col))
            (setq ent-data (subst (cons 62 new-col) (assoc 62 ent-data) ent-data))
            (if (assoc 6 ent-data)
              (setq ent-data (subst (cons 6 ltype) (assoc 6 ent-data) ent-data))
            )
            (if (assoc 290 ent-data)
              (setq ent-data
                (subst (cons 290 (if (= plot-flag "PLOT") 1 0))
                       (assoc 290 ent-data) ent-data))
            )
            (entmod ent-data)
            (setq cnt-upd (1+ cnt-upd))
          )
          (setq cnt-skip (1+ cnt-skip))
        ) ;_ if changed
      ) ;_ progn existing
    ) ;_ if null existing
  ) ;_ foreach
  
  (list cnt-new cnt-upd cnt-skip)
)


;;; ========================================================================
;;; Hauptbefehl: LAYEXP
;;; Exportiert Layer (00_, 01_, 02_) nach LayerSync-Ordner
;;; ========================================================================
(defun c:LAYEXP ( / *error* old-cmdecho filepath layer-data)
  
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  
  ;; Dateipfad automatisch ermitteln
  (setq filepath (LXI:get-layer-filepath))
  
  (if (null filepath)
    (princ "\n*** Abbruch: LayerSync-Ordner nicht verfuegbar.")
    (progn
      (setq layer-data (LXI:collect-layers))
      
      (if (null layer-data)
        (princ "\n*** Keine Layer (00_, 01_, 02_) zum Exportieren gefunden.")
        (if (LXI:write-layer-file filepath layer-data)
          (progn
            (princ (strcat "\n" (itoa (length layer-data))
                           " Layer exportiert nach:"))
            (princ (strcat "\n" filepath))
          )
          (princ "\n*** Fehler beim Schreiben der Datei.")
        )
      )
    )
  )
  
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ)
)


;;; ========================================================================
;;; Hauptbefehl: LAYIMP
;;; Importiert Layer aus gewaehlter TXT-Datei (interaktive Auswahl)
;;; ========================================================================
(defun c:LAYIMP ( / *error* old-cmdecho
                    sync-dir files chosen filepath layer-data counts)
  
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  
  ;; Verfuegbare Dateien auflisten
  (setq files (LXI:list-layer-files))
  
  (if (null files)
    (progn
      (princ "\n*** Keine Layer-Dateien im LayerSync-Ordner gefunden.")
      (princ (strcat "\n    Ordner: " *LXI:base-path*))
      (princ "\n    Zuerst LAYEXP in einer Zeichnung ausfuehren.")
    )
    (progn
      ;; Interaktive Auswahl
      (setq chosen (LXI:select-file-interactive files))
      
      (if (null chosen)
        (princ "\n*** Abbruch: Keine Datei gewaehlt.")
        (progn
          (setq sync-dir (LXI:get-sync-folder))
          (setq filepath (strcat sync-dir "\\" chosen))
          
          ;; Layer-Daten lesen
          (setq layer-data (LXI:read-layer-file filepath))
          
          (if (null layer-data)
            (princ "\n*** Keine Layer-Daten in Datei gefunden.")
            (progn
              (princ (strcat "\n" (itoa (length layer-data))
                             " Layer aus \"" chosen "\" geladen."))
              
              ;; Layer anwenden
              (setq counts (LXI:apply-layers layer-data))
              
              ;; Ergebnis
              (princ "\n--- Import Ergebnis ---")
              (princ (strcat "\n  Neu angelegt: " (itoa (nth 0 counts))))
              (princ (strcat "\n  Aktualisiert: " (itoa (nth 1 counts))))
              (princ (strcat "\n  Unveraendert: " (itoa (nth 2 counts))))
            )
          )
        )
      )
    )
  )
  
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ)
)


;;; ========================================================================
;;; Initialisierung
;;; ========================================================================
(vl-load-com)
(princ "\nLayerExportImport.lsp v0.3.0 geladen.")
(princ "\nBefehle: LAYEXP | LAYIMP")
(princ (strcat "\nSpeicherort: " *LXI:base-path*))
(princ)
;;; ========================================================================
;;; LayerExportImport.lsp
;;; Export und Import von Layer-Informationen zwischen Zeichnungen
;;; 
;;; Version: 0.2.0
;;; Datum:   2026-03-09
;;; Autor:   Herbert Schrotter
;;;
;;; Installation:
;;;   1. APPLOAD in AutoCAD ausfuehren
;;;   2. LayerExportImport.lsp auswaehlen und laden
;;;   3. Automatisches Laden: Zu Startup Suite hinzufuegen
;;;
;;; Befehle:
;;;   LAYEXP - Exportiert Layer (00_, 01_, 02_) in eine TXT-Datei
;;;   LAYIMP - Importiert Layer aus TXT (neue anlegen, vorhandene updaten)
;;; ========================================================================


;;; ------------------------------------------------------------------------
;;; Hilfsfunktion: Prueft ob ein Layername von einem Xref stammt
;;; Parameter:
;;;   lay-name - Layername als String
;;; Rueckgabe:
;;;   T wenn Xref-Layer (enthaelt "|"), nil wenn lokaler Layer
;;; ------------------------------------------------------------------------
(defun LXI:xref-layer-p (lay-name / )
  (wcmatch lay-name "*|*")
)


;;; ------------------------------------------------------------------------
;;; Hilfsfunktion: Sammelt alle Layer-Daten (ohne Xref-Layer)
;;; Parameter: keine
;;; Rueckgabe:
;;;   Liste von Layer-Datenlisten:
;;;   '(("Name" "Color" "Linetype" "Lineweight" "PlotFlag" "OnOff" "Freeze" "Lock")
;;;     ...)
;;;   oder nil bei Fehler
;;; ------------------------------------------------------------------------
(defun LXI:collect-layers ( / lay-tbl lay-name lay-data result
                              col ltype lw plot-flag on-off frz lck)
  ;; Ueber Layer-Tabelle iterieren
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
        
        ;; Linienstärke: via VLA falls verfügbar, sonst Default
        (setq lw "Default")
        
        ;; Plot-Flag: via DXF 290 (1=plottbar, 0=nicht plottbar)
        (setq plot-flag (cdr (assoc 290 lay-tbl)))
        (setq plot-flag (if (or (null plot-flag) (= plot-flag 1))
                           "PLOT"
                           "NOPLOT"
                         )
        )
        
        ;; Layer-Daten als Liste sammeln
        (setq result
          (cons
            (list
              lay-name
              (itoa col)
              ltype
              lw
              plot-flag
              on-off
              frz
              lck
            )
            result
          )
        )
      ) ;_ progn
    ) ;_ if xref
  ) ;_ while
  
  ;; Alphabetisch sortieren nach Layername
  (if result
    (vl-sort result
      '(lambda (a b) (< (car a) (car b)))
    )
  )
)


;;; ------------------------------------------------------------------------
;;; Hilfsfunktion: Schreibt Layer-Daten in eine TXT-Datei
;;; Parameter:
;;;   filepath   - Voller Dateipfad als String
;;;   layer-data - Liste von Layer-Datenlisten (aus LXI:collect-layers)
;;; Rueckgabe:
;;;   T bei Erfolg, nil bei Fehler
;;; ------------------------------------------------------------------------
(defun LXI:write-layer-file (filepath layer-data / fp lay sep)
  ;; Trennzeichen fuer die Spalten
  (setq sep "\t")
  
  ;; Datei zum Schreiben oeffnen
  (setq fp (open filepath "w"))
  (if (null fp)
    (progn
      (princ (strcat "\n*** Fehler: Kann Datei nicht oeffnen: " filepath))
      nil
    )
    (progn
      ;; Header-Zeile mit Versionsinfo
      (write-line ";;; LayerExport v0.2.0" fp)
      (write-line (strcat ";;; Zeichnung: " (getvar "DWGNAME")) fp)
      (write-line (strcat ";;; Datum: " (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM)")) fp)
      (write-line (strcat ";;; Anzahl Layer: " (itoa (length layer-data))) fp)
      (write-line ";;;" fp)
      
      ;; Spalten-Header
      (write-line
        (strcat "Name" sep "Color" sep "Linetype" sep "Lineweight"
                sep "Plot" sep "OnOff" sep "Freeze" sep "Lock"
        )
        fp
      )
      
      ;; Layer-Daten schreiben
      (foreach lay layer-data
        (write-line
          (strcat
            (nth 0 lay) sep   ; Name
            (nth 1 lay) sep   ; Color
            (nth 2 lay) sep   ; Linetype
            (nth 3 lay) sep   ; Lineweight
            (nth 4 lay) sep   ; Plot
            (nth 5 lay) sep   ; OnOff
            (nth 6 lay) sep   ; Freeze
            (nth 7 lay)       ; Lock
          )
          fp
        )
      )
      
      ;; Datei schliessen
      (close fp)
      T
    ) ;_ progn
  ) ;_ if
)


;;; ========================================================================
;;; Hauptbefehl: LAYEXP
;;; Exportiert alle lokalen Layer in eine TXT-Datei
;;; ========================================================================
(defun c:LAYEXP ( / *error* old-cmdecho
                    folder filepath layer-data dwg-name)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  
  ;; Ordner per Dialog auswaehlen
  (setq folder (LXI:get-folder-dialog "Zielordner fuer Layer-Export waehlen"))
  
  (if (null folder)
    (princ "\n*** Abbruch: Kein Ordner gewaehlt.")
    (progn
      ;; Dateiname aus Zeichnungsname ableiten
      (setq dwg-name (vl-filename-base (getvar "DWGNAME")))
      (setq filepath (strcat folder "\\" dwg-name "_layers.txt"))
      
      ;; Layer sammeln
      (setq layer-data (LXI:collect-layers))
      
      (if (null layer-data)
        (princ "\n*** Keine Layer zum Exportieren gefunden.")
        (progn
          ;; In Datei schreiben
          (if (LXI:write-layer-file filepath layer-data)
            (progn
              (princ (strcat "\n" (itoa (length layer-data))
                             " Layer exportiert nach:"))
              (princ (strcat "\n" filepath))
            )
            (princ "\n*** Fehler beim Schreiben der Datei.")
          )
        ) ;_ progn
      ) ;_ if layer-data
    ) ;_ progn
  ) ;_ if folder
  
  ;; Cleanup
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ)
)


;;; ------------------------------------------------------------------------
;;; Hilfsfunktion: Ordnerauswahl-Dialog
;;; Parameter:
;;;   title - Dialog-Titel als String
;;; Rueckgabe:
;;;   Ordnerpfad als String oder nil bei Abbruch
;;; ------------------------------------------------------------------------
(defun LXI:get-folder-dialog (title / shell folder result)
  (vl-load-com)
  (setq shell (vlax-create-object "Shell.Application"))
  (if shell
    (progn
      (setq folder
        (vlax-invoke-method shell 'BrowseForFolder
          (vla-get-HWND (vlax-get-acad-object))
          title
          0    ; Optionen (0 = Standard)
          ""   ; Root-Ordner (leer = Desktop)
        )
      )
      (if folder
        (progn
          (setq result (vlax-get-property
                         (vlax-get-property folder 'Self)
                         'Path
                       )
          )
          ;; Trailing Backslash entfernen falls vorhanden
          (if (= (substr result (strlen result) 1) "\\")
            (setq result (substr result 1 (1- (strlen result))))
          )
        )
      )
      ;; COM-Objekt freigeben
      (vlax-release-object shell)
    )
    (princ "\n*** Fehler: Shell.Application konnte nicht erstellt werden.")
  )
  result
)


;;; ------------------------------------------------------------------------
;;; Hilfsfunktion: Liest Layer-Daten aus einer TXT-Datei
;;; Parameter:
;;;   filepath - Voller Dateipfad als String
;;; Rueckgabe:
;;;   Liste von Layer-Datenlisten (gleiches Format wie LXI:collect-layers)
;;;   oder nil bei Fehler
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
            ;; Tab-getrennte Felder aufsplitten
            (setq fields (LXI:split-string line sep))
            ;; Nur Zeilen mit 8 Feldern akzeptieren
            (if (= (length fields) 8)
              (setq result (cons fields result))
            )
          )
        )
      )
      (close fp)
      ;; Reihenfolge umkehren (cons baut rueckwaerts)
      (reverse result)
    ) ;_ progn
  ) ;_ if
)


;;; ------------------------------------------------------------------------
;;; Hilfsfunktion: Splittet einen String am Trennzeichen
;;; Parameter:
;;;   str - Eingabestring
;;;   del - Trennzeichen (String, 1 Zeichen)
;;; Rueckgabe:
;;;   Liste von Teilstrings
;;; ------------------------------------------------------------------------
(defun LXI:split-string (str del / pos result part)
  (setq result nil)
  (while (setq pos (vl-string-search del str))
    (setq part (substr str 1 pos))
    (setq result (cons part result))
    (setq str (substr str (+ pos 2)))
  )
  ;; Letztes Element (nach dem letzten Trennzeichen)
  (setq result (cons str result))
  (reverse result)
)


;;; ------------------------------------------------------------------------
;;; Hilfsfunktion: Wendet Layer-Daten auf die aktuelle Zeichnung an
;;; Erstellt neue Layer oder aktualisiert vorhandene
;;; Parameter:
;;;   layer-data - Liste von Layer-Datenlisten
;;; Rueckgabe:
;;;   Liste '(neue geaenderte uebersprungene) als Zaehler
;;; ------------------------------------------------------------------------
(defun LXI:apply-layers (layer-data / lay lay-name col ltype lw
                          plot-flag on-off frz lck
                          existing ent-data new-col
                          cnt-new cnt-upd cnt-skip changed)
  (setq cnt-new 0)
  (setq cnt-upd 0)
  (setq cnt-skip 0)
  
  (foreach lay layer-data
    (setq lay-name  (nth 0 lay))
    (setq col       (atoi (nth 1 lay)))
    (setq ltype     (nth 2 lay))
    (setq lw        (nth 3 lay))
    (setq plot-flag (nth 4 lay))
    (setq on-off    (nth 5 lay))
    (setq frz       (nth 6 lay))
    (setq lck       (nth 7 lay))
    
    ;; Pruefen ob Layer bereits existiert
    (setq existing (tblsearch "LAYER" lay-name))
    
    (if (null existing)
      ;; --- NEUER LAYER: anlegen via command ---
      (progn
        ;; Farbe negativ setzen wenn Layer aus
        (setq new-col (if (= on-off "OFF") (- col) col))
        (entmake
          (list
            '(0 . "LAYER")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbLayerTableRecord")
            (cons 2 lay-name)
            (cons 62 new-col)
            (cons 6 ltype)
            '(370 . -3)          ; Default Lineweight
            (cons 290 (if (= plot-flag "PLOT") 1 0))
            (cons 70 (+ (if (= frz "FROZEN") 1 0)
                        (if (= lck "LOCKED") 4 0)
                     )
            )
          )
        )
        (setq cnt-new (1+ cnt-new))
      )
      ;; --- VORHANDENER LAYER: Eigenschaften vergleichen & updaten ---
      (progn
        (setq changed nil)
        (setq ent-data (entget (tblobjname "LAYER" lay-name)))
        
        ;; Farbe pruefen (abs wegen On/Off-Flag)
        (if (/= (abs (cdr (assoc 62 ent-data))) col)
          (setq changed T)
        )
        
        ;; Linientyp pruefen
        (if (and (cdr (assoc 6 ent-data))
                 (/= (strcase (cdr (assoc 6 ent-data)))
                      (strcase ltype)
                 )
            )
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
                   (if (= plot-flag "PLOT") 1 0)
              )
            (setq changed T)
          )
        )
        
        (if changed
          (progn
            ;; Farbe mit On/Off-Flag setzen
            (setq new-col (if (= on-off "OFF") (- col) col))
            (setq ent-data (subst (cons 62 new-col) (assoc 62 ent-data) ent-data))
            
            ;; Linientyp setzen
            (if (assoc 6 ent-data)
              (setq ent-data (subst (cons 6 ltype) (assoc 6 ent-data) ent-data))
            )
            
            ;; Plot-Flag setzen
            (if (assoc 290 ent-data)
              (setq ent-data
                (subst (cons 290 (if (= plot-flag "PLOT") 1 0))
                       (assoc 290 ent-data)
                       ent-data
                )
              )
            )
            
            ;; Aenderungen anwenden
            (entmod ent-data)
            (setq cnt-upd (1+ cnt-upd))
          )
          ;; Keine Aenderung noetig
          (setq cnt-skip (1+ cnt-skip))
        ) ;_ if changed
      ) ;_ progn existing
    ) ;_ if null existing
  ) ;_ foreach
  
  ;; Zaehler zurueckgeben
  (list cnt-new cnt-upd cnt-skip)
)


;;; ========================================================================
;;; Hauptbefehl: LAYIMP
;;; Importiert Layer aus einer TXT-Datei in die aktuelle Zeichnung
;;; Neue Layer werden angelegt, vorhandene bei Abweichung aktualisiert
;;; ========================================================================
(defun c:LAYIMP ( / *error* old-cmdecho
                    filepath layer-data counts)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg T) "*cancel*,*quit*"))
      (princ (strcat "\nFehler: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ)
  )
  
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  
  ;; TXT-Datei per Dialog auswaehlen
  (setq filepath
    (getfiled "Layer-TXT auswaehlen" "" "txt" 4)
  )
  
  (if (null filepath)
    (princ "\n*** Abbruch: Keine Datei gewaehlt.")
    (progn
      ;; Layer-Daten aus Datei lesen
      (setq layer-data (LXI:read-layer-file filepath))
      
      (if (null layer-data)
        (princ "\n*** Keine Layer-Daten in Datei gefunden.")
        (progn
          (princ (strcat "\n" (itoa (length layer-data))
                         " Layer in Datei gefunden."))
          
          ;; Layer anwenden (neu anlegen / updaten)
          (setq counts (LXI:apply-layers layer-data))
          
          ;; Ergebnis ausgeben
          (princ (strcat "\n--- Import Ergebnis ---"))
          (princ (strcat "\n  Neu angelegt: " (itoa (nth 0 counts))))
          (princ (strcat "\n  Aktualisiert: " (itoa (nth 1 counts))))
          (princ (strcat "\n  Unveraendert: " (itoa (nth 2 counts))))
        ) ;_ progn
      ) ;_ if layer-data
    ) ;_ progn
  ) ;_ if filepath
  
  ;; Cleanup
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ)
)


;;; ========================================================================
;;; Initialisierung
;;; ========================================================================
(vl-load-com)
(princ "\nLayerExportImport.lsp v0.2.0 geladen.")
(princ "\nBefehle: LAYEXP | LAYIMP")
(princ)
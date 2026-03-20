;;; ========================================================================
;;; LayerExportImport.lsp
;;; Layer-Synchronisation zwischen Zeichnungen via Master-Datei
;;; MasterID-System | Custom Property GUID | ObjectDBX Batch-Sync
;;; 
;;; Version: 3.0.0
;;; Datum:   2026-03-10
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
;;;   LAYDIFF    - Vorschau: Unterschiede ohne Sync
;;;   LAYCOUNT   - Schnellinfo: Sync-Stand Einzeiler
;;;   LAYUNDO    - Sync-Vorgang rueckgaengig machen (DCL Dialog)
;;;
;;; Dateien im LayerSync-Ordner:
;;;   LayerMaster.csv  - Layer-Daten mit MasterID (14 Felder)
;;;   LayerMapper.csv  - MasterID;LayerName;Handle;DwgName;DwgPath;DwgGUID
;;;   LayerHistory.csv - MasterID;LayerName;Datum;Aktion;Detail;Source
;;;   LayerSyncLog.csv - Letzter Sync-Zeitpunkt pro DWG (3 Felder)
;;;   LayerSync.cfg    - Konfiguration
;;;   LayerSync.log    - Debug-Log (pro Session neu)
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
(setq *LXI:autosync*  nil)
(setq *LXI:notify*    T)
(setq *LXI:sep* ";")
(setq *LXI:cached-guid* nil)
(setq *LXI:cached-guid-dwg* nil)
(setq *LXI:reactor* nil)


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
                ((= key "DEBUG")  (setq *LXI:debug* (= (strcase val) "ON")))
                ((= key "AUTOSYNC") (setq *LXI:autosync* (= (strcase val) "ON")))
                ((= key "NOTIFY") (setq *LXI:notify* (= (strcase val) "ON")))))))
        (close fp))))))

(defun LXI:write-config ( / filepath fp)
  (LXI:ensure-directory *LXI:base-path*)
  (setq filepath (LXI:get-config-path))
  (setq fp (open filepath "w"))
  (if fp (progn
    (write-line ";;; LayerSync Konfiguration v3.0.0" fp)
    (write-line (strcat "PATH=" *LXI:base-path*) fp)
    (write-line (strcat "PREFIX=" *LXI:prefix*) fp)
    (write-line (strcat "DEBUG=" (if *LXI:debug* "ON" "OFF")) fp)
    (write-line (strcat "AUTOSYNC=" (if *LXI:autosync* "ON" "OFF")) fp)
    (write-line (strcat "NOTIFY=" (if *LXI:notify* "ON" "OFF")) fp)
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
  (if *LXI:debug* (princ (strcat "\n  [DBG] " msg)))
  (LXI:log-write msg))

(defun LXI:timestamp ( / ) (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM)"))

(defun LXI:timestamp-sec ( / ) (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM:SS)"))

;;; Log-Datei: Wird bei APPLOAD neu erstellt, danach append
(defun LXI:log-init ( / filepath fp)
  (setq filepath (strcat *LXI:base-path* "\\LayerSync.log"))
  (setq fp (open filepath "w"))
  (if fp (progn
    (write-line (strcat "=== LayerSync Log - " (LXI:timestamp-sec) " ===") fp)
    (write-line (strcat "Version: 3.0.0") fp)
    (write-line (strcat "DWG: " (vl-filename-base (getvar "DWGNAME")) ".dwg") fp)
    (write-line "" fp)
    (close fp))))

(defun LXI:log-write (msg / filepath fp)
  (if (and *LXI:base-path* (vl-file-directory-p *LXI:base-path*))
    (progn
      (setq filepath (strcat *LXI:base-path* "\\LayerSync.log"))
      (setq fp (open filepath "a"))
      (if fp (progn
        (write-line (strcat "[" (LXI:timestamp-sec) "] " msg) fp)
        (close fp))))))

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

;;; Prueft ob Error-Message ein Abbruch ist (Deutsch + Englisch)
(defun LXI:cancel-p (msg / m)
  (setq m (strcase msg T))
  (or (wcmatch m "*cancel*")
      (wcmatch m "*quit*")
      (wcmatch m "*abgebrochen*")
      (wcmatch m "*abbruch*")))

;;; Sichere String-zu-Integer Konvertierung mit Default
;;; Rueckgabe: Integer, Default bei leerem/ungueltigem String
(defun LXI:safe-atoi (str default / val)
  (if (or (null str) (= str ""))
    default
    (progn
      (setq val (atoi str))
      (if (and (= val 0) (/= str "0")) default val))))

;;; Ersetzt Element an Index in einer Liste
;;; Rueckgabe: Neue Liste mit ersetztem Element
(defun LXI:list-set-nth (lst idx val / i result)
  (setq i 0 result nil)
  (foreach elem lst
    (if (= i idx)
      (setq result (cons val result))
      (setq result (cons elem result)))
    (setq i (1+ i)))
  (reverse result))


;;; ========================================================================
;;; GUID (Custom Property)
;;; ========================================================================

;;; Sicheres Auslesen: vla-GetCustomByIndex schreibt manchmal
;;; direkt Strings statt Variants in die Symbole
(defun LXI:safe-variant-value (v / )
  (cond
    ((= (type v) 'STR) v)
    ((= (type v) 'VARIANT) (vlax-variant-value v))
    (T nil)))

(defun LXI:dwg-guid ( / si guid num-props i key val found key-str)
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
                (setq key-str (LXI:safe-variant-value key))
                (if (and key-str (= (strcase key-str) "LAYERSYNCGUID"))
                  (progn
                    (setq guid (LXI:safe-variant-value val))
                    (setq found T)))))
            (setq i (1+ i)))))
      (if (or (null guid) (= guid ""))
        (progn
          (setq guid (LXI:generate-guid))
          (vl-catch-all-apply
            '(lambda () (vla-AddCustomInfo si "LayerSyncGUID" guid)))
          (LXI:debug-print (strcat "Neue GUID: " guid))
          (princ (strcat "\n  LayerSyncGUID erstellt: " guid))
          (initget "Ja Nein")
          (if (= (getkword "\n  Zeichnung speichern? [Ja/Nein] <Ja>: ") "Nein")
            (princ "\n  GUID wird beim naechsten Speichern permanent.")
            (progn
              (vla-Save (vla-get-ActiveDocument (vlax-get-acad-object)))
              (princ "\n  Gespeichert."))))
        (LXI:debug-print (strcat "GUID: " guid)))
      (setq *LXI:cached-guid* guid)
      (setq *LXI:cached-guid-dwg* (LXI:dwg-name))
      guid)))

(defun LXI:generate-guid ( / date-str rand-str)
  (setq date-str (menucmd "M=$(edtime,0,YYYYMODDHHMMSS)"))
  (setq rand-str (itoa (rem (getvar "MILLISECS") 100000)))
  (while (< (strlen rand-str) 5) (setq rand-str (strcat "0" rand-str)))
  (strcat "LXI-" date-str "-" rand-str))

;;; Read-Only GUID: Liest vorhandene GUID, erstellt KEINE neue
;;; Fuer automatische Aufrufe (check-on-open) ohne User-Dialog
;;; Rueckgabe: GUID-String oder nil wenn nicht vorhanden
(defun LXI:dwg-guid-read ( / si guid num-props i key val found key-str)
  ;; Cache pruefen
  (if (and *LXI:cached-guid*
           (/= *LXI:cached-guid* "")
           (= *LXI:cached-guid-dwg* (LXI:dwg-name)))
    *LXI:cached-guid*
    ;; Aus Custom Properties lesen
    (progn
      (setq si (vl-catch-all-apply
                 '(lambda ()
                   (vla-get-SummaryInfo
                     (vla-get-ActiveDocument (vlax-get-acad-object))))))
      (if (vl-catch-all-error-p si) nil
        (progn
          (setq found nil guid nil)
          (setq num-props (vl-catch-all-apply
                            '(lambda () (vla-NumCustomInfo si))))
          (if (vl-catch-all-error-p num-props) (setq num-props 0))
          (if (> num-props 0)
            (progn
              (setq i 0)
              (while (and (< i num-props) (null found))
                (setq key (vlax-make-variant "" vlax-vbString))
                (setq val (vlax-make-variant "" vlax-vbString))
                (vl-catch-all-apply
                  '(lambda ()
                    (vla-GetCustomByIndex si i 'key 'val)
                    (setq key-str (LXI:safe-variant-value key))
                    (if (and key-str (= (strcase key-str) "LAYERSYNCGUID"))
                      (progn
                        (setq guid (LXI:safe-variant-value val))
                        (setq found T)))))
                (setq i (1+ i)))))
          (if (and guid (/= guid ""))
            (progn
              (setq *LXI:cached-guid* guid)
              (setq *LXI:cached-guid-dwg* (LXI:dwg-name))
              guid)
            nil))))))


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
;;; MASTER (.csv) - 24 Felder (v2.5)
;;; MasterID;Name;Color;Linetype;Lineweight;Plot;OnOff;Freeze;Lock;
;;; VPDefault;Description;Transparency;
;;; ColorMod;LtypeMod;LwMod;PlotMod;OnOffMod;FreezeMod;LockMod;
;;; VPDefMod;DescMod;TransMod;
;;; Source;LastModified
;;;
;;; Index: 0=MID 1=Name
;;;   2=Color 3=Linetype 4=Lineweight 5=Plot 6=OnOff
;;;   7=Freeze 8=Lock 9=VPDefault 10=Description 11=Transparency
;;;   12=ColorMod 13=LtypeMod 14=LwMod 15=PlotMod 16=OnOffMod
;;;   17=FreezeMod 18=LockMod 19=VPDefMod 20=DescMod 21=TransMod
;;;   22=Source 23=LastModified
;;;
;;; *Mod Format: "YYYY-MO-DD HH:MM|DwgName.dwg"
;;; ========================================================================

(defun LXI:read-master ( / sync-dir filepath fp line fields result nf
                           old-src old-mod mod-stamp)
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
                    (setq nf (length fields))
                    (cond
                      ;; 24 Felder = aktuelles Format v2.5
                      ((= nf 24)
                        (setq result (cons fields result)))
                      ;; 14 Felder = v2.0 -> migrieren
                      ((= nf 14)
                        (progn
                          (setq old-src (nth 12 fields)
                                old-mod (nth 13 fields))
                          ;; Mod-Stamp aus altem Source+LastModified
                          (setq mod-stamp
                            (if (and old-mod (/= old-mod ""))
                              (strcat old-mod "|" (if old-src old-src ""))
                              ""))
                          (setq result
                            (cons
                              (list (nth 0 fields) (nth 1 fields)
                                    (nth 2 fields) (nth 3 fields)
                                    (nth 4 fields) (nth 5 fields)
                                    (nth 6 fields) (nth 7 fields)
                                    (nth 8 fields) (nth 9 fields)
                                    (nth 10 fields) (nth 11 fields)
                                    mod-stamp mod-stamp mod-stamp mod-stamp
                                    mod-stamp mod-stamp mod-stamp mod-stamp
                                    mod-stamp mod-stamp
                                    old-src old-mod)
                              result))))
                      ;; 11 Felder = altes Format v1.x -> migrieren
                      ((= nf 11)
                        (progn
                          (setq old-src (nth 9 fields)
                                old-mod (nth 10 fields))
                          (setq mod-stamp
                            (if (and old-mod (/= old-mod ""))
                              (strcat old-mod "|" (if old-src old-src ""))
                              ""))
                          (setq result
                            (cons
                              (list (nth 0 fields) (nth 1 fields)
                                    (nth 2 fields) (nth 3 fields)
                                    (nth 4 fields) (nth 5 fields)
                                    (nth 6 fields) (nth 7 fields)
                                    (nth 8 fields)
                                    "0" "" "0"
                                    mod-stamp mod-stamp mod-stamp mod-stamp
                                    mod-stamp mod-stamp mod-stamp mod-stamp
                                    mod-stamp mod-stamp
                                    old-src old-mod)
                              result))))))))
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
                    s "Plot" s "OnOff" s "Freeze" s "Lock"
                    s "VPDefault" s "Description" s "Transparency"
                    s "ColorMod" s "LtypeMod" s "LwMod" s "PlotMod"
                    s "OnOffMod" s "FreezeMod" s "LockMod"
                    s "VPDefMod" s "DescMod" s "TransMod"
                    s "Source" s "LastModified") fp)
          (setq master-data (vl-sort master-data '(lambda (a b) (< (car a) (car b)))))
          (foreach lay master-data
            (write-line
              (strcat (if (nth 0 lay) (nth 0 lay) "") s
                      (if (nth 1 lay) (nth 1 lay) "") s
                      (if (nth 2 lay) (nth 2 lay) "") s
                      (if (nth 3 lay) (nth 3 lay) "") s
                      (if (nth 4 lay) (nth 4 lay) "") s
                      (if (nth 5 lay) (nth 5 lay) "") s
                      (if (nth 6 lay) (nth 6 lay) "") s
                      (if (nth 7 lay) (nth 7 lay) "") s
                      (if (nth 8 lay) (nth 8 lay) "") s
                      (if (nth 9 lay) (nth 9 lay) "") s
                      (if (nth 10 lay) (nth 10 lay) "") s
                      (if (nth 11 lay) (nth 11 lay) "") s
                      (if (nth 12 lay) (nth 12 lay) "") s
                      (if (nth 13 lay) (nth 13 lay) "") s
                      (if (nth 14 lay) (nth 14 lay) "") s
                      (if (nth 15 lay) (nth 15 lay) "") s
                      (if (nth 16 lay) (nth 16 lay) "") s
                      (if (nth 17 lay) (nth 17 lay) "") s
                      (if (nth 18 lay) (nth 18 lay) "") s
                      (if (nth 19 lay) (nth 19 lay) "") s
                      (if (nth 20 lay) (nth 20 lay) "") s
                      (if (nth 21 lay) (nth 21 lay) "") s
                      (if (nth 22 lay) (nth 22 lay) "") s
                      (if (nth 23 lay) (nth 23 lay) "")) fp))
          (close fp) T)))))

;;; Hilfsfunktion: Mod-Stamp erzeugen ("YYYY-MO-DD HH:MM|DwgName.dwg")
(defun LXI:make-mod-stamp (timestamp dwg / )
  (strcat timestamp "|" dwg))

;;; Hilfsfunktion: Timestamp aus Mod-Stamp extrahieren
(defun LXI:mod-stamp-time (mod-stamp / pos)
  (if (or (null mod-stamp) (= mod-stamp "")) ""
    (progn
      (setq pos (vl-string-search "|" mod-stamp))
      (if pos (substr mod-stamp 1 pos) mod-stamp))))

;;; Hilfsfunktion: DWG-Name aus Mod-Stamp extrahieren
(defun LXI:mod-stamp-source (mod-stamp / pos)
  (if (or (null mod-stamp) (= mod-stamp "")) ""
    (progn
      (setq pos (vl-string-search "|" mod-stamp))
      (if pos (substr mod-stamp (+ pos 2)) ""))))

;;; Prueft ob mod-stamp-a neuer ist als mod-stamp-b
;;; Rueckgabe: T wenn a neuer
(defun LXI:mod-newer-p (mod-a mod-b / time-a time-b)
  (setq time-a (LXI:mod-stamp-time mod-a)
        time-b (LXI:mod-stamp-time mod-b))
  (if (or (= time-a "") (= time-b "")) nil
    (> (strcase time-a) (strcase time-b))))

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
;;; MAPPER (.csv) - 6 Felder
;;; MasterID;LayerName;Handle;DwgName;DwgPath;DwgGUID
;;; Index: 0=MID 1=LayerName 2=Handle 3=DwgName 4=DwgPath 5=DwgGUID
;;; ========================================================================

(defun LXI:read-mapper ( / sync-dir filepath fp line fields result nf)
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
                (if (and (> (strlen line) 0)
                         (/= (substr line 1 8) "MasterID")
                         (/= (substr line 1 7) "DwgName"))
                  (progn
                    (setq fields (LXI:split-string line *LXI:sep*))
                    (setq nf (length fields))
                    (cond
                      ;; 6 Felder, erstes = M -> neues v2.0 Format
                      ((and (= nf 6) (= (substr (nth 0 fields) 1 1) "M"))
                        (setq result (cons fields result)))
                      ;; 6 Felder, altes v1.x Format: DwgName;DwgGUID;DwgPath;LayerName;Handle;MasterID
                      ((= nf 6)
                        (setq result
                          (cons (list (nth 5 fields) (nth 3 fields) (nth 4 fields)
                                      (nth 0 fields) (nth 2 fields) (nth 1 fields))
                                result)))
                      ;; 5 Felder = v0.10: DwgName;DwgGUID;LayerName;Handle;MasterID
                      ((= nf 5)
                        (setq result
                          (cons (list (nth 4 fields) (nth 2 fields) (nth 3 fields)
                                      (nth 0 fields) "" (nth 1 fields))
                                result)))
                      ;; 4 Felder = altes: DwgName;LayerName;Handle;MasterID
                      ((= nf 4)
                        (setq result
                          (cons (list (nth 3 fields) (nth 1 fields) (nth 2 fields)
                                      (nth 0 fields) "" "")
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
            (strcat "MasterID" s "LayerName" s "Handle" s "DwgName" s "DwgPath" s "DwgGUID") fp)
          ;; Sortierung: MasterID primaer, DwgName sekundaer
          (setq mapper-data (vl-sort mapper-data
            '(lambda (a b)
              (if (= (car a) (car b))
                (< (nth 3 a) (nth 3 b))
                (< (car a) (car b))))))
          (foreach entry mapper-data
            (if (and (nth 0 entry) (nth 1 entry) (nth 3 entry))
              (write-line
                (strcat (nth 0 entry) s (nth 1 entry) s
                        (if (nth 2 entry) (nth 2 entry) "") s
                        (nth 3 entry) s
                        (if (nth 4 entry) (nth 4 entry) "") s
                        (if (nth 5 entry) (nth 5 entry) "")) fp)))
          (close fp) T)))))

;;; Mapper-Lookup: DwgGUID + Handle -> MasterID
;;; Neues Format: 0=MID 1=LayerName 2=Handle 3=DwgName 4=DwgPath 5=DwgGUID
(defun LXI:mapper-get-mid (mapper-data guid dwg handle / result e5 e2 e3)
  (setq result nil)
  ;; Zuerst GUID + Handle
  (if (and guid (/= guid "") (/= guid "NO-GUID"))
    (foreach entry mapper-data
      (setq e5 (nth 5 entry) e2 (nth 2 entry))
      (if (and e5 e2
               (= (strcase e5) (strcase guid))
               (= (strcase e2) (strcase handle)))
        (setq result (nth 0 entry)))))
  ;; Fallback: DwgName + Handle
  (if (null result)
    (foreach entry mapper-data
      (setq e3 (nth 3 entry) e2 (nth 2 entry))
      (if (and e3 e2
               (= (strcase e3) (strcase dwg))
               (= (strcase e2) (strcase handle)))
        (setq result (nth 0 entry)))))
  result)

;;; Mapper-Eintraege fuer Zeichnung (GUID oder Name), erkennt Umbenennung
(defun LXI:mapper-get-dwg-entries (mapper-data guid dwg / guid-entries old-name)
  (setq guid-entries nil)
  (if (and guid (/= guid "") (/= guid "NO-GUID"))
    (setq guid-entries
      (vl-remove-if-not
        '(lambda (e) (and (nth 5 e) (= (strcase (nth 5 e)) (strcase guid))))
        mapper-data)))
  (if guid-entries
    (progn
      (setq old-name (nth 3 (car guid-entries)))
      (if (and old-name (/= (strcase old-name) (strcase dwg)))
        (progn
          (princ (strcat "\n  DWG umbenannt: " old-name " -> " dwg))
          (setq guid-entries
            (mapcar
              '(lambda (e)
                (list (nth 0 e) (nth 1 e) (nth 2 e) dwg (nth 4 e) (nth 5 e)))
              guid-entries))))
      guid-entries)
    (vl-remove-if-not
      '(lambda (e) (and (nth 3 e) (= (strcase (nth 3 e)) (strcase dwg))))
      mapper-data)))

;;; Entfernt Eintraege (GUID und Name)
(defun LXI:mapper-remove-dwg (mapper-data guid dwg / e5 e3)
  (vl-remove-if
    '(lambda (entry)
      (setq e5 (nth 5 entry) e3 (nth 3 entry))
      (or (and guid (/= guid "") (/= guid "NO-GUID")
               e5 (= (strcase e5) (strcase guid)))
          (and e3 (= (strcase e3) (strcase dwg)))))
    mapper-data))

;;; Gibt eindeutige Zeichnungen aus Mapper zurueck
;;; Rueckgabe: Liste von '("DwgName" "DwgGUID" "DwgPath")
(defun LXI:mapper-get-dwg-list (mapper-data / result dwg-name dwg-guid dwg-path found)
  (setq result nil)
  (foreach entry mapper-data
    (setq dwg-name (nth 3 entry)
          dwg-guid (nth 5 entry)
          dwg-path (nth 4 entry))
    (if (null dwg-name) (setq dwg-name ""))
    (if (null dwg-guid) (setq dwg-guid ""))
    (if (null dwg-path) (setq dwg-path ""))
    (if (/= dwg-name "")
      (progn
        (setq found nil)
        (foreach r result
          (if (= (strcase (car r)) (strcase dwg-name))
            (setq found T)))
        (if (not found)
          (setq result (cons (list dwg-name dwg-guid dwg-path) result))))))
  (reverse result))


;;; ========================================================================
;;; HISTORY (.csv) - APPEND ONLY - 8 Felder (v2.6)
;;; MasterID;LayerName;Datum;Aktion;Property;OldValue;NewValue;Source
;;; Index: 0=MID 1=LayerName 2=Datum 3=Aktion 4=Property 5=OldValue 6=NewValue 7=Source
;;; Aktion: NEU, AENDERUNG, UMBENENNUNG, LOESCHUNG
;;; Property: Color, Linetype, Lineweight, Plot, OnOff, Freeze, Lock,
;;;           VPDefault, Description, Transparency, Name
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
            (write-line (strcat "MasterID" s "LayerName" s "Datum" s "Aktion"
                                s "Property" s "OldValue" s "NewValue" s "Source") fp))
          (foreach entry entries
            (write-line (strcat (if (nth 0 entry) (nth 0 entry) "") s
                                (if (nth 1 entry) (nth 1 entry) "") s
                                (if (nth 2 entry) (nth 2 entry) "") s
                                (if (nth 3 entry) (nth 3 entry) "") s
                                (if (nth 4 entry) (nth 4 entry) "") s
                                (if (nth 5 entry) (nth 5 entry) "") s
                                (if (nth 6 entry) (nth 6 entry) "") s
                                (if (nth 7 entry) (nth 7 entry) "")) fp))
          (close fp) T)))))

(defun LXI:read-history ( / sync-dir filepath fp line fields result nf)
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
                (if (and (> (strlen line) 0)
                         (/= (substr line 1 8) "MasterID")
                         (/= (substr line 1 5) "Datum"))
                  (progn
                    (setq fields (LXI:split-string line *LXI:sep*))
                    (setq nf (length fields))
                    (cond
                      ;; 8 Felder = v2.6 Format
                      ((and (= nf 8) (= (substr (nth 0 fields) 1 1) "M"))
                        (setq result (cons fields result)))
                      ;; 6 Felder, erstes = M -> v2.0 Format migrieren
                      ((and (= nf 6) (= (substr (nth 0 fields) 1 1) "M"))
                        (setq result
                          (cons (list (nth 0 fields) (nth 1 fields) (nth 2 fields)
                                      (nth 3 fields) "" "" (nth 4 fields) (nth 5 fields))
                                result)))
                      ;; 6 Felder altes Format
                      ((= nf 6)
                        (setq result
                          (cons (list (nth 5 fields) (nth 2 fields) (nth 0 fields)
                                      (nth 1 fields) "" "" (nth 3 fields) (nth 4 fields))
                                result)))))))
              (close fp) (reverse result))))))))

;;; Property-Namen fuer History/Undo
(defun LXI:prop-names ( / )
  '("Color" "Linetype" "Lineweight" "Plot" "OnOff"
    "Freeze" "Lock" "VPDefault" "Description" "Transparency"))



;;; ========================================================================
;;; SYNCLOG (.csv) - Letzter Sync-Zeitpunkt pro DWG
;;; DwgName;DwgGUID;LastSync
;;; Fuer Konflikterkennung: Master.LastModified > DWG.LastSync = Warnung
;;; ========================================================================

;;; Liest SyncLog
;;; Rueckgabe: Liste von '("DwgName" "DwgGUID" "LastSync")
(defun LXI:read-synclog ( / sync-dir filepath fp line fields result)
  (setq sync-dir (LXI:get-sync-folder))
  (if (null sync-dir) nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerSyncLog.csv"))
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
                    (if (= (length fields) 3)
                      (setq result (cons fields result))))))
              (close fp) (reverse result))))))))

;;; Schreibt SyncLog (komplett neu)
(defun LXI:write-synclog (synclog-data / sync-dir filepath fp entry s)
  (setq sync-dir (LXI:get-sync-folder)) (setq s *LXI:sep*)
  (if (null sync-dir) nil
    (progn
      (setq filepath (strcat sync-dir "\\LayerSyncLog.csv"))
      (setq fp (open filepath "w"))
      (if (null fp) nil
        (progn
          (write-line (strcat "DwgName" s "DwgGUID" s "LastSync") fp)
          (foreach entry synclog-data
            (write-line (strcat (nth 0 entry) s (nth 1 entry) s (nth 2 entry)) fp))
          (close fp) T)))))

;;; Holt LastSync fuer eine DWG (ueber GUID, Fallback Name)
;;; Rueckgabe: Timestamp-String oder nil (noch nie gesynced)
(defun LXI:get-last-sync (synclog-data guid dwg / result)
  (setq result nil)
  ;; Zuerst ueber GUID
  (if (and guid (/= guid "") (/= guid "NO-GUID"))
    (foreach entry synclog-data
      (if (and (null result)
               (= (strcase (nth 1 entry)) (strcase guid)))
        (setq result (nth 2 entry)))))
  ;; Fallback: Name
  (if (null result)
    (foreach entry synclog-data
      (if (and (null result)
               (= (strcase (nth 0 entry)) (strcase dwg)))
        (setq result (nth 2 entry)))))
  result)

;;; Aktualisiert LastSync fuer eine DWG (oder fuegt neu ein)
;;; Rueckgabe: Aktualisierte synclog-data Liste
(defun LXI:update-last-sync (synclog-data dwg guid / found new-entry timestamp)
  (if (null synclog-data) (setq synclog-data nil))
  (setq timestamp (LXI:timestamp))
  (setq new-entry (list dwg guid timestamp))
  (setq found nil)
  ;; Bestehenden Eintrag ersetzen (ueber GUID oder Name)
  (setq synclog-data
    (mapcar
      '(lambda (entry)
        (if (or (and guid (/= guid "") (/= guid "NO-GUID")
                     (= (strcase (nth 1 entry)) (strcase guid)))
                (= (strcase (nth 0 entry)) (strcase dwg)))
          (progn (setq found T) new-entry)
          entry))
      synclog-data))
  ;; Wenn nicht gefunden: neuen Eintrag anhaengen
  (if (null found)
    (setq synclog-data (append synclog-data (list new-entry))))
  synclog-data)

;;; Prueft ob Master-Eintrag neuer ist als letzter Sync
;;; Parameter: master-modified - Timestamp aus Master, last-sync - aus SyncLog
;;; Rueckgabe: T wenn Master neuer (= jemand anders hat geaendert)
(defun LXI:master-newer-p (master-modified last-sync / )
  (if (or (null last-sync) (= last-sync ""))
    nil  ;; Noch nie gesynced -> kein Konflikt (erster Sync)
    (if (or (null master-modified) (= master-modified ""))
      nil  ;; Kein Master-Timestamp -> kein Konflikt
      ;; String-Vergleich funktioniert weil Format "YYYY-MO-DD HH:MM"
      (> (strcase master-modified) (strcase last-sync)))))


;;; ========================================================================
;;; SNAPSHOT (.csv) - Zustand der Layer beim letzten Sync (Three-Way-Merge)
;;; Eine Datei pro DWG: LayerSnapshot_<GUID>.csv
;;; 11 Felder: Name;Color;Linetype;Lineweight;Plot;OnOff;Freeze;Lock;
;;;            VPDefault;Description;Transparency
;;; Index: 0=Name 1=Color 2=Ltype 3=LW 4=Plot 5=OnOff
;;;        6=Frz 7=Lock 8=VPDef 9=Desc 10=Trans
;;; ACHTUNG: Reihenfolge wie Master (nicht wie collect-layers!)
;;; ========================================================================

;;; Snapshot-Dateipfad fuer eine DWG
(defun LXI:snapshot-path (guid / sync-dir)
  (setq sync-dir (LXI:get-sync-folder))
  (if sync-dir
    (strcat sync-dir "\\LayerSnapshot_" guid ".csv")
    nil))

;;; Liest Snapshot einer DWG
;;; Rueckgabe: Association-Liste ((LAYERNAME . (col ltype lw plot onoff frz lck vpdef desc trans)) ...)
(defun LXI:read-snapshot (guid / filepath fp line fields result nf)
  (setq filepath (LXI:snapshot-path guid))
  (if (or (null filepath) (not (findfile filepath))) nil
    (progn
      (setq fp (open filepath "r"))
      (if (null fp) nil
        (progn
          (setq result nil)
          (while (setq line (read-line fp))
            (if (and (> (strlen line) 0)
                     (/= (substr line 1 4) "Name"))
              (progn
                (setq fields (LXI:split-string line *LXI:sep*))
                (if (= (length fields) 11)
                  (setq result
                    (cons (cons (strcase (nth 0 fields))
                                (cdr fields))
                          result))))))
          (close fp)
          result)))))

;;; Schreibt Snapshot nach Sync
;;; Parameter: layers - collect-layers Ergebnis (12 Felder)
;;;   0=Name 1=Color 2=Ltype 3=LW 4=OnOff 5=Frz 6=Lock 7=Plot 8=VPDef 9=Desc 10=Trans 11=Handle
;;; Gespeichert in Master-Reihenfolge: Name;Color;Ltype;LW;Plot;OnOff;Frz;Lock;VPDef;Desc;Trans
(defun LXI:write-snapshot (guid layers / filepath fp lay s)
  (setq filepath (LXI:snapshot-path guid))
  (if (null filepath) nil
    (progn
      (setq s *LXI:sep*)
      (setq fp (open filepath "w"))
      (if (null fp) nil
        (progn
          (write-line
            (strcat "Name" s "Color" s "Linetype" s "Lineweight" s "Plot"
                    s "OnOff" s "Freeze" s "Lock" s "VPDefault"
                    s "Description" s "Transparency") fp)
          (foreach lay layers
            (write-line
              (strcat (nth 0 lay) s (nth 1 lay) s (nth 2 lay) s
                      (nth 3 lay) s (nth 7 lay) s (nth 4 lay) s
                      (nth 5 lay) s (nth 6 lay) s (nth 8 lay) s
                      (nth 9 lay) s (nth 10 lay)) fp))
          (close fp) T)))))

;;; Holt Snapshot-Werte fuer einen Layer
;;; Rueckgabe: Liste (col ltype lw plot onoff frz lck vpdef desc trans) oder nil
(defun LXI:snapshot-get (snapshot lay-name / entry)
  (if (null snapshot) nil
    (progn
      (setq entry (assoc (strcase lay-name) snapshot))
      (if entry (cdr entry) nil))))

;;; Three-Way-Merge fuer eine Property
;;; Parameter: base-val (Snapshot), local-val, master-val
;;; Rueckgabe: Liste (winner-val source)
;;;   source = "NONE" (identisch) / "LOCAL" / "MASTER" / "CONFLICT"
(defun LXI:three-way-merge-field (base-val local-val master-val / )
  (cond
    ;; Alle gleich -> nichts tun
    ((and (= (strcase local-val) (strcase master-val)))
      (list local-val "NONE"))
    ;; Kein Base (erster Sync) -> Master gewinnt
    ((null base-val)
      (if (= (strcase local-val) (strcase master-val))
        (list local-val "NONE")
        (list master-val "MASTER")))
    ;; Nur Lokal geaendert
    ((and (/= (strcase local-val) (strcase base-val))
          (= (strcase master-val) (strcase base-val)))
      (list local-val "LOCAL"))
    ;; Nur Master geaendert
    ((and (= (strcase local-val) (strcase base-val))
          (/= (strcase master-val) (strcase base-val)))
      (list master-val "MASTER"))
    ;; Beide geaendert, gleicher Wert
    ((= (strcase local-val) (strcase master-val))
      (list local-val "NONE"))
    ;; Beide geaendert, unterschiedlicher Wert -> Konflikt
    (T
      (list master-val "CONFLICT"))))

;;; ========================================================================
;;; LAYER SAMMELN (VLA-basiert, aktuelle Zeichnung)

(defun LXI:collect-layers ( / doc layers-coll lay-obj lay-name lay-data result)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layers-coll (vla-get-Layers doc))
  (setq result nil)
  (vlax-for lay-obj layers-coll
    (setq lay-name (vla-get-Name lay-obj))
    (if (and (not (LXI:xref-layer-p lay-name))
             (LXI:sync-layer-p lay-name))
      (progn
        (setq lay-data (LXI:read-layer-vla lay-obj))
        (LXI:debug-print
          (strcat "Gefunden: " (nth 0 lay-data)
                  " [" (nth 11 lay-data) "]"
                  " Farbe=" (nth 1 lay-data)))
        (setq result (cons lay-data result)))))
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
;;; TRANSPARENZ (XData-basiert)
;;; ========================================================================

;;; ------------------------------------------------------------------------
;;; Liest Transparenz eines Layers in Prozent (0-90)
;;; Zugriff ueber XData "AcCmTransparency" (kein VLA-Property verfuegbar)
;;; Parameter: lay-name - Layername als String
;;; Rueckgabe: Integer 0-90 (0 = keine Transparenz)
;;; ------------------------------------------------------------------------
(defun LXI:get-transparency (lay-name / ent xdata trans-val)
  (setq ent (tblobjname "LAYER" lay-name))
  (if (null ent) 0
    (progn
      (setq xdata
        (cdr (assoc -3
          (entget ent '("AcCmTransparency")))))
      (if (null xdata) 0
        (progn
          (setq trans-val
            (cdr (assoc 1071 (cdar xdata))))
          (if (or (null trans-val) (= trans-val 0)) 0
            (progn
              ;; Unteres Byte extrahieren (0..255 = 100%..0%)
              (setq trans-val (lsh (lsh trans-val 24) -24))
              ;; In Prozent umrechnen (0-100 Bereich)
              (fix (- 100 (/ trans-val 2.55))))))))))


;;; ------------------------------------------------------------------------
;;; Setzt Transparenz eines Layers (0-90)
;;; Nur in aktueller Zeichnung und offenen DWGs moeglich (command-basiert)
;;; Parameter: lay-name - Layername, trans-pct - Prozent 0-90
;;; Rueckgabe: T bei Erfolg
;;; ------------------------------------------------------------------------
(defun LXI:set-transparency (lay-name trans-pct / )
  (if (or (null trans-pct) (= trans-pct 0))
    ;; Transparenz entfernen (auf 0 setzen)
    (progn
      (vl-catch-all-apply
        '(lambda () (command "._-LAYER" "TR" "0" lay-name "")))
      T)
    ;; Transparenz setzen
    (progn
      (vl-catch-all-apply
        '(lambda () (command "._-LAYER" "TR" (itoa trans-pct) lay-name "")))
      T)))


;;; ------------------------------------------------------------------------
;;; Setzt Transparenz ueber SendCommand (fuer offene DWGs via Documents)
;;; Parameter: doc - VLA Document, lay-name - Layername, trans-pct - 0-90
;;; Rueckgabe: T (fire-and-forget, keine Fehlerprüfung moeglich)
;;; ------------------------------------------------------------------------
(defun LXI:set-transparency-doc (doc lay-name trans-pct / cmd)
  (setq cmd (strcat "._-LAYER TR " (itoa trans-pct) " " lay-name " \n"))
  (vl-catch-all-apply 'vla-SendCommand (list doc cmd))
  T)


;;; ========================================================================
;;; FARBE (Index + TrueColor)
;;; Format im CSV: "7" (Indexfarbe) oder "RGB:255,128,0" (TrueColor)
;;; ========================================================================

;;; Liest Farbe eines VLA Layer-Objekts
;;; Erkennt automatisch ob Index oder TrueColor
;;; Rueckgabe: String "7" oder "RGB:255,128,0"
(defun LXI:read-color (lay-obj / tc-obj method r g b col)
  (setq tc-obj (vl-catch-all-apply 'vla-get-TrueColor (list lay-obj)))
  (if (vl-catch-all-error-p tc-obj)
    ;; Fallback: nur Indexfarbe
    (progn
      (setq col (vla-get-Color lay-obj))
      (if (< col 0) (setq col (abs col)))
      (itoa col))
    ;; TrueColor-Objekt vorhanden
    (progn
      (setq method (vl-catch-all-apply 'vla-get-ColorMethod (list tc-obj)))
      (if (vl-catch-all-error-p method) (setq method 195))
      (if (= method 194)
        ;; acColorMethodByRGB = 194 -> TrueColor
        (progn
          (setq r (vla-get-Red tc-obj)
                g (vla-get-Green tc-obj)
                b (vla-get-Blue tc-obj))
          (strcat "RGB:" (itoa r) "," (itoa g) "," (itoa b)))
        ;; acColorMethodByACI = 195 -> Indexfarbe
        (progn
          (setq col (vla-get-Color lay-obj))
          (if (< col 0) (setq col (abs col)))
          (itoa col))))))

;;; Setzt Farbe auf einem VLA Layer-Objekt
;;; Parameter: lay-obj - VLA Layer, col-str - "7" oder "RGB:255,128,0"
;;; Rueckgabe: T bei Erfolg
(defun LXI:apply-color (lay-obj col-str / tc-obj parts r g b col)
  (if (and col-str (> (strlen col-str) 4)
           (= (strcase (substr col-str 1 4)) "RGB:"))
    ;; TrueColor setzen
    (progn
      (setq parts (LXI:split-string (substr col-str 5) ","))
      (if (= (length parts) 3)
        (progn
          (setq r (atoi (nth 0 parts))
                g (atoi (nth 1 parts))
                b (atoi (nth 2 parts)))
          (setq tc-obj (vl-catch-all-apply 'vla-get-TrueColor (list lay-obj)))
          (if (not (vl-catch-all-error-p tc-obj))
            (progn
              (vla-put-ColorMethod tc-obj 194)
              (vla-SetRGB tc-obj r g b)
              (vl-catch-all-apply 'vla-put-TrueColor (list lay-obj tc-obj))
              T)
            nil))
        nil))
    ;; Indexfarbe setzen
    (progn
      (setq col (LXI:safe-atoi col-str 7))
      (vl-catch-all-apply 'vla-put-Color (list lay-obj col))
      T)))


;;; ========================================================================
;;; VLA LAYER-ZUGRIFF (einheitlich fuer lokal, Documents, ObjectDBX)
;;; ========================================================================

;;; ------------------------------------------------------------------------
;;; Liest alle Properties eines VLA Layer-Objekts in eine Liste
;;; Funktioniert mit: aktuellem Document, Documents-Collection, ObjectDBX
;;; Parameter: lay-obj - VLA Layer-Objekt
;;; Rueckgabe: Liste mit 12 Werten:
;;;   (Name Color Linetype Lineweight OnOff Freeze Lock
;;;    Plot VPDefault Description Transparency Handle)
;;; Indices: 0=Name 1=Color 2=Linetype 3=Lineweight 4=OnOff 5=Freeze
;;;          6=Lock 7=Plot 8=VPDefault 9=Description 10=Transparency 11=Handle
;;; ------------------------------------------------------------------------
(defun LXI:read-layer-vla (lay-obj / lay-name col ltype lw
                            on-off frz lck plot-flag vpdef desc trans handle)
  ;; Name und Handle
  (setq lay-name (vla-get-Name lay-obj))
  (setq handle (vla-get-Handle lay-obj))
  
  ;; Farbe (Index oder TrueColor, automatische Erkennung)
  (setq col (LXI:read-color lay-obj))
  
  ;; Linientyp
  (setq ltype (vla-get-Linetype lay-obj))
  (if (null ltype) (setq ltype "Continuous"))
  
  ;; Linienstaerke (Integer: -3=Default, -2=ByBlock, -1=ByLayer, 0+ in 1/100mm)
  (setq lw (vla-get-Lineweight lay-obj))
  
  ;; OnOff
  (setq on-off
    (if (= (vla-get-LayerOn lay-obj) :vlax-true) "ON" "OFF"))
  
  ;; Freeze
  (setq frz
    (if (= (vla-get-Freeze lay-obj) :vlax-true) "FROZEN" "THAWED"))
  
  ;; Lock
  (setq lck
    (if (= (vla-get-Lock lay-obj) :vlax-true) "LOCKED" "UNLOCKED"))
  
  ;; Plottable
  (setq plot-flag
    (if (= (vla-get-Plottable lay-obj) :vlax-true) "PLOT" "NOPLOT"))
  
  ;; ViewportDefault (Frieren in neuen Ansichtsfenstern)
  (setq vpdef
    (vl-catch-all-apply 'vlax-get-property (list lay-obj 'ViewportDefault)))
  (if (vl-catch-all-error-p vpdef) (setq vpdef 0))
  (setq vpdef (if (or (= vpdef :vlax-true) (= vpdef -1) (= vpdef 1)) "1" "0"))
  
  ;; Beschreibung
  (setq desc
    (vl-catch-all-apply 'vla-get-Description (list lay-obj)))
  (if (vl-catch-all-error-p desc) (setq desc ""))
  (if (null desc) (setq desc ""))
  
  ;; Transparenz (XData, nur bei aktuellem Dokument lesbar)
  ;; Bei ObjectDBX/Documents: XData nicht zugreifbar, default 0
  (setq trans 0)
  (vl-catch-all-apply
    '(lambda ()
      (setq trans (LXI:get-transparency lay-name))))
  
  ;; Rueckgabe als Liste (alle als Strings fuer CSV-Kompatibilitaet)
  (list lay-name
        col
        ltype
        (itoa lw)
        on-off
        frz
        lck
        plot-flag
        vpdef
        desc
        (itoa trans)
        handle))


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
;;; Erstellt einen neuen Layer via VLA mit allen 10 Properties
;;; Parameter: Master-Layer-Daten als Liste (14 Felder aus Master-CSV)
;;;   oder Einzelwerte: lay-name col ltype lw plot on-off frz lck vpdef desc trans
;;; Rueckgabe: T bei Erfolg, nil bei Fehler
;;; ------------------------------------------------------------------------
(defun LXI:create-layer (lay-name col ltype lw plot-flag on-off frz lck
                          vpdef desc trans
                          / doc layers-coll lay-obj)
  ;; Linientyp sicherstellen
  (setq ltype (LXI:ensure-linetype ltype))
  ;; Defaults fuer neue Parameter (Abwaertskompatibilitaet)
  (if (null lw) (setq lw -3))
  (if (null vpdef) (setq vpdef "0"))
  (if (null desc) (setq desc ""))
  (if (null trans) (setq trans 0))
  ;; col bleibt String ("7" oder "RGB:255,128,0")
  (if (numberp col) (setq col (itoa col)))
  (if (null col) (setq col "7"))
  (if (numberp lw) nil (setq lw (LXI:safe-atoi lw -3)))
  (if (numberp trans) nil (setq trans (LXI:safe-atoi trans 0)))
  
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layers-coll (vla-get-Layers doc))
  (setq lay-obj
    (vl-catch-all-apply 'vla-Add (list layers-coll lay-name)))
  (if (vl-catch-all-error-p lay-obj) nil
    (progn
      (LXI:apply-color lay-obj col)
      (vl-catch-all-apply 'vla-put-Linetype (list lay-obj ltype))
      (vl-catch-all-apply 'vla-put-Lineweight (list lay-obj lw))
      (vla-put-LayerOn lay-obj (if (= on-off "ON") :vlax-true :vlax-false))
      (vl-catch-all-apply 'vla-put-Freeze
        (list lay-obj (if (= frz "FROZEN") :vlax-true :vlax-false)))
      (vla-put-Lock lay-obj (if (= lck "LOCKED") :vlax-true :vlax-false))
      (vla-put-Plottable lay-obj (if (= plot-flag "PLOT") :vlax-true :vlax-false))
      ;; ViewportDefault
      (if (= vpdef "1")
        (vl-catch-all-apply 'vlax-put-property
          (list lay-obj 'ViewportDefault :vlax-true)))
      ;; Beschreibung
      (if (and desc (/= desc ""))
        (vl-catch-all-apply 'vla-put-Description (list lay-obj desc)))
      ;; Transparenz (command-basiert)
      (if (and trans (> trans 0))
        (LXI:set-transparency lay-name trans))
      T)))


;;; ------------------------------------------------------------------------
;;; Aktualisiert einen bestehenden Layer via VLA mit allen 10 Properties
;;; Parameter: lay-name + Master-Werte
;;; Rueckgabe: T bei Erfolg
;;; ------------------------------------------------------------------------
(defun LXI:update-layer-props (lay-name col ltype lw plot-flag on-off frz lck
                                vpdef desc trans
                                / doc layers-coll lay-obj)
  ;; Linientyp sicherstellen
  (setq ltype (LXI:ensure-linetype ltype))
  ;; Typ-Konvertierung
  (if (null lw) (setq lw -3))
  (if (null vpdef) (setq vpdef "0"))
  (if (null desc) (setq desc ""))
  (if (null trans) (setq trans 0))
  ;; col bleibt String ("7" oder "RGB:255,128,0")
  (if (numberp col) (setq col (itoa col)))
  (if (null col) (setq col "7"))
  (if (numberp lw) nil (setq lw (LXI:safe-atoi lw -3)))
  (if (numberp trans) nil (setq trans (LXI:safe-atoi trans 0)))
  
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layers-coll (vla-get-Layers doc))
  (setq lay-obj
    (vl-catch-all-apply 'vla-Item (list layers-coll lay-name)))
  (if (vl-catch-all-error-p lay-obj) nil
    (progn
      (LXI:apply-color lay-obj col)
      (vl-catch-all-apply 'vla-put-Linetype (list lay-obj ltype))
      (vl-catch-all-apply 'vla-put-Lineweight (list lay-obj lw))
      (vla-put-LayerOn lay-obj (if (= on-off "ON") :vlax-true :vlax-false))
      ;; Freeze: Nicht setzen wenn Layer aktuell ist (wuerde Fehler geben)
      (vl-catch-all-apply 'vla-put-Freeze
        (list lay-obj (if (= frz "FROZEN") :vlax-true :vlax-false)))
      (vla-put-Lock lay-obj (if (= lck "LOCKED") :vlax-true :vlax-false))
      (vla-put-Plottable lay-obj (if (= plot-flag "PLOT") :vlax-true :vlax-false))
      ;; ViewportDefault
      (vl-catch-all-apply 'vlax-put-property
        (list lay-obj 'ViewportDefault
              (if (= vpdef "1") :vlax-true :vlax-false)))
      ;; Beschreibung
      (vl-catch-all-apply 'vla-put-Description (list lay-obj desc))
      ;; Transparenz
      (LXI:set-transparency lay-name trans)
      T)))


;;; ------------------------------------------------------------------------
;;; Vergleicht Layer-Properties: Master vs. Lokal (alle 10 Properties)
;;; Parameter: lay-name + Master-Werte (als Strings)
;;; Rueckgabe: Liste der Unterschiede oder nil wenn identisch
;;; ------------------------------------------------------------------------
(defun LXI:compare-layer-props (lay-name col ltype lw plot-flag on-off frz lck
                                  vpdef desc trans
                                  / doc layers-coll lay-obj local-data diffs)
  ;; Defaults
  (if (null lw) (setq lw "-3"))
  (if (null vpdef) (setq vpdef "0"))
  (if (null desc) (setq desc ""))
  (if (null trans) (setq trans "0"))
  ;; Strings sicherstellen
  (if (numberp col) (setq col (itoa col)))
  (if (numberp lw) (setq lw (itoa lw)))
  (if (numberp trans) (setq trans (itoa trans)))
  
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layers-coll (vla-get-Layers doc))
  (setq lay-obj
    (vl-catch-all-apply 'vla-Item (list layers-coll lay-name)))
  (if (vl-catch-all-error-p lay-obj) nil
    (progn
      ;; Lokale Werte lesen
      (setq local-data (LXI:read-layer-vla lay-obj))
      ;; local-data: (Name Color Ltype LW OnOff Frz Lck Plot VPDef Desc Trans Handle)
      (setq diffs nil)
      ;; Farbe (Index 1)
      (if (/= (nth 1 local-data) col)
        (setq diffs (cons (strcat "  Farbe:       Master=" col
                                  "  Lokal=" (nth 1 local-data)) diffs)))
      ;; Linientyp (Index 2)
      (if (/= (strcase (nth 2 local-data)) (strcase ltype))
        (setq diffs (cons (strcat "  Linientyp:   Master=" ltype
                                  "  Lokal=" (nth 2 local-data)) diffs)))
      ;; Linienstaerke (Index 3)
      (if (/= (nth 3 local-data) lw)
        (setq diffs (cons (strcat "  Linienstaerke: Master=" lw
                                  "  Lokal=" (nth 3 local-data)) diffs)))
      ;; OnOff (Index 4)
      (if (/= (strcase (nth 4 local-data)) (strcase on-off))
        (setq diffs (cons (strcat "  OnOff:       Master=" on-off
                                  "  Lokal=" (nth 4 local-data)) diffs)))
      ;; Freeze (Index 5)
      (if (/= (strcase (nth 5 local-data)) (strcase frz))
        (setq diffs (cons (strcat "  Freeze:      Master=" frz
                                  "  Lokal=" (nth 5 local-data)) diffs)))
      ;; Lock (Index 6)
      (if (/= (strcase (nth 6 local-data)) (strcase lck))
        (setq diffs (cons (strcat "  Lock:        Master=" lck
                                  "  Lokal=" (nth 6 local-data)) diffs)))
      ;; Plot (Index 7)
      (if (/= (strcase (nth 7 local-data)) (strcase plot-flag))
        (setq diffs (cons (strcat "  Plot:        Master=" plot-flag
                                  "  Lokal=" (nth 7 local-data)) diffs)))
      ;; VPDefault (Index 8)
      (if (/= (nth 8 local-data) vpdef)
        (setq diffs (cons (strcat "  VP-Default:  Master=" vpdef
                                  "  Lokal=" (nth 8 local-data)) diffs)))
      ;; Beschreibung (Index 9)
      (if (/= (nth 9 local-data) desc)
        (setq diffs (cons (strcat "  Beschreibung: Master=" desc
                                  "  Lokal=" (nth 9 local-data)) diffs)))
      ;; Transparenz (Index 10)
      (if (/= (nth 10 local-data) trans)
        (setq diffs (cons (strcat "  Transparenz: Master=" trans
                                  "  Lokal=" (nth 10 local-data)) diffs)))
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
;;; EXPORT-KERNFUNKTION (14-Feld Master, SyncLog Konflikterkennung)
;;; collect-layers: 0=Name 1=Color 2=Ltype 3=LW 4=OnOff 5=Frz
;;;   6=Lock 7=Plot 8=VPDef 9=Desc 10=Trans 11=Handle
;;; Master: 0=MID 1=Name 2=Color 3=Ltype 4=LW 5=Plot 6=OnOff
;;;   7=Frz 8=Lock 9=VPDef 10=Desc 11=Trans 12=Source 13=LastMod
;;; ========================================================================
(defun LXI:do-export ( / dwg guid dwg-path layers master-data mapper-data
                         synclog-data last-sync
                         lay lay-name handle mid old-name
                         existing-master change-details detail
                         timestamp history-entries new-mid
                         master-modified master-source exp-choice skip-layer
                         cnt-new cnt-upd cnt-ren cnt-conflict)
  (setq dwg (LXI:dwg-name))
  (setq guid (LXI:dwg-guid))
  (setq dwg-path (LXI:dwg-path))
  (setq timestamp (LXI:timestamp))
  (setq cnt-new 0 cnt-upd 0 cnt-ren 0 cnt-conflict 0)
  (setq history-entries nil)
  (setq exp-choice nil)
  (LXI:debug-print (strcat "Export: " dwg " GUID: " guid))
  
  ;; SyncLog lesen
  (setq synclog-data (LXI:read-synclog))
  (setq last-sync (LXI:get-last-sync synclog-data guid dwg))
  (if last-sync
    (LXI:debug-print (strcat "Letzter Sync: " last-sync))
    (LXI:debug-print "Erster Export"))
  
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
        (setq lay-name (nth 0 lay) handle (nth 11 lay))
        (setq mid (LXI:mapper-get-mid mapper-data guid dwg handle))
        
        (cond
          ;; FALL 1: Bekannter Layer
          (mid
            (progn
              (setq existing-master (LXI:find-by-id master-data mid))
              (if existing-master
                (progn
                  ;; Umbenennung
                  (setq old-name (nth 1 existing-master))
                  (if (/= (strcase old-name) (strcase lay-name))
                    (progn
                      (princ (strcat "\n  > Umbenennung: " old-name " -> " lay-name))
                      (setq history-entries
                        (cons (list mid lay-name timestamp "UMBENENNUNG"
                                    "Name" old-name lay-name dwg)
                              history-entries))
                      (setq cnt-ren (1+ cnt-ren))))
                  
                  ;; Konflikterkennung
                  (setq master-modified (nth 23 existing-master))
                  (setq master-source (nth 22 existing-master))
                  (setq skip-layer nil)
                  
                  (if (and (LXI:master-newer-p master-modified last-sync)
                           (/= (strcase master-source) (strcase dwg)))
                    ;; KONFLIKT
                    (progn
                      (if (not (or (= exp-choice "AlleUeber") (= exp-choice "AlleBehalten")))
                        (progn
                          (princ (strcat "\n\n========================================"))
                          (princ (strcat "\n  EXPORT-KONFLIKT: " lay-name " [" mid "]"))
                          (princ (strcat "\n  Master geaendert von " master-source
                                         " (" master-modified ")"))
                          (princ (strcat "\n  Dein letzter Sync: "
                                         (if last-sync last-sync "nie")))
                          (princ "\n\n  Ueberschreiben = Deine Werte in Master")
                          (princ "\n  Behalten       = Master-Werte behalten")
                          (princ "\n  AlleUeber      = Alle ueberschreiben")
                          (princ "\n  AlleBehalten   = Alle behalten")
                          (initget "Ueberschreiben Behalten AlleUeber AlleBehalten")
                          (setq exp-choice
                            (getkword "\n[Ueberschreiben/Behalten/AlleUeber/AlleBehalten]: "))
                          (if (null exp-choice) (setq exp-choice "Behalten"))))
                      (if (or (= exp-choice "Behalten") (= exp-choice "AlleBehalten"))
                        (progn
                          (setq cnt-conflict (1+ cnt-conflict))
                          (setq skip-layer T)
                          (if (= exp-choice "Behalten") (setq exp-choice nil)))
                        ;; Ueberschreiben
                        (progn
                          (if (= exp-choice "Ueberschreiben") (setq exp-choice nil))))))
                  
                  ;; Normal exportieren (wenn nicht uebersprungen)
                  (if (null skip-layer)
                    (progn
                      ;; Aenderungen pruefen und einzeln in History loggen
                      ;; Master-Indizes: 2=Color 3=Ltype 4=LW 5=Plot 6=OnOff 7=Frz 8=Lock 9=VPDef 10=Desc 11=Trans
                      ;; Lay-Indizes:    1=Color 2=Ltype 3=LW 7=Plot 4=OnOff 5=Frz 6=Lock 8=VPDef 9=Desc 10=Trans
                      (setq change-details nil)
                      (if (/= (nth 2 existing-master) (nth 1 lay))
                        (setq history-entries (cons (list mid lay-name timestamp "AENDERUNG"
                          "Color" (nth 2 existing-master) (nth 1 lay) dwg) history-entries)
                          change-details (cons "Color" change-details)))
                      (if (/= (strcase (nth 3 existing-master)) (strcase (nth 2 lay)))
                        (if (/= (strcase (nth 2 lay)) "CONTINUOUS")
                          (setq history-entries (cons (list mid lay-name timestamp "AENDERUNG"
                            "Linetype" (nth 3 existing-master) (nth 2 lay) dwg) history-entries)
                            change-details (cons "Linetype" change-details))))
                      (if (/= (nth 4 existing-master) (nth 3 lay))
                        (setq history-entries (cons (list mid lay-name timestamp "AENDERUNG"
                          "Lineweight" (nth 4 existing-master) (nth 3 lay) dwg) history-entries)
                          change-details (cons "Lineweight" change-details)))
                      (if (/= (strcase (nth 5 existing-master)) (strcase (nth 7 lay)))
                        (setq history-entries (cons (list mid lay-name timestamp "AENDERUNG"
                          "Plot" (nth 5 existing-master) (nth 7 lay) dwg) history-entries)
                          change-details (cons "Plot" change-details)))
                      (if (/= (strcase (nth 6 existing-master)) (strcase (nth 4 lay)))
                        (setq history-entries (cons (list mid lay-name timestamp "AENDERUNG"
                          "OnOff" (nth 6 existing-master) (nth 4 lay) dwg) history-entries)
                          change-details (cons "OnOff" change-details)))
                      (if (/= (strcase (nth 7 existing-master)) (strcase (nth 5 lay)))
                        (setq history-entries (cons (list mid lay-name timestamp "AENDERUNG"
                          "Freeze" (nth 7 existing-master) (nth 5 lay) dwg) history-entries)
                          change-details (cons "Freeze" change-details)))
                      (if (/= (strcase (nth 8 existing-master)) (strcase (nth 6 lay)))
                        (setq history-entries (cons (list mid lay-name timestamp "AENDERUNG"
                          "Lock" (nth 8 existing-master) (nth 6 lay) dwg) history-entries)
                          change-details (cons "Lock" change-details)))
                      (if (/= (nth 9 existing-master) (nth 8 lay))
                        (setq history-entries (cons (list mid lay-name timestamp "AENDERUNG"
                          "VPDefault" (nth 9 existing-master) (nth 8 lay) dwg) history-entries)
                          change-details (cons "VPDefault" change-details)))
                      (if (/= (nth 10 existing-master) (nth 9 lay))
                        (setq history-entries (cons (list mid lay-name timestamp "AENDERUNG"
                          "Description" (nth 10 existing-master) (nth 9 lay) dwg) history-entries)
                          change-details (cons "Description" change-details)))
                      (if (/= (nth 11 existing-master) (nth 10 lay))
                        (setq history-entries (cons (list mid lay-name timestamp "AENDERUNG"
                          "Transparency" (nth 11 existing-master) (nth 10 lay) dwg) history-entries)
                          change-details (cons "Transparency" change-details)))
                      (if change-details (setq cnt-upd (1+ cnt-upd)))
                      ;; Master aktualisieren (24 Felder, Field-Level Timestamps)
                      (setq master-data (LXI:remove-by-id master-data mid))
                      (setq master-data
                        (cons (list mid lay-name
                                    (nth 1 lay)
                                    (if (and (= (strcase (nth 2 lay)) "CONTINUOUS")
                                             (/= (strcase (nth 3 existing-master)) "CONTINUOUS"))
                                      (nth 3 existing-master) (nth 2 lay))
                                    (nth 3 lay) (nth 7 lay) (nth 4 lay)
                                    (nth 5 lay) (nth 6 lay) (nth 8 lay)
                                    (nth 9 lay) (nth 10 lay)
                                    ;; Mod-Stamps: nur geaenderte Properties aktualisieren
                                    (if (/= (nth 2 existing-master) (nth 1 lay))
                                      (LXI:make-mod-stamp timestamp dwg) (nth 12 existing-master))
                                    (if (/= (strcase (nth 3 existing-master)) (strcase (nth 2 lay)))
                                      (LXI:make-mod-stamp timestamp dwg) (nth 13 existing-master))
                                    (if (/= (nth 4 existing-master) (nth 3 lay))
                                      (LXI:make-mod-stamp timestamp dwg) (nth 14 existing-master))
                                    (if (/= (strcase (nth 5 existing-master)) (strcase (nth 7 lay)))
                                      (LXI:make-mod-stamp timestamp dwg) (nth 15 existing-master))
                                    (if (/= (strcase (nth 6 existing-master)) (strcase (nth 4 lay)))
                                      (LXI:make-mod-stamp timestamp dwg) (nth 16 existing-master))
                                    (if (/= (strcase (nth 7 existing-master)) (strcase (nth 5 lay)))
                                      (LXI:make-mod-stamp timestamp dwg) (nth 17 existing-master))
                                    (if (/= (strcase (nth 8 existing-master)) (strcase (nth 6 lay)))
                                      (LXI:make-mod-stamp timestamp dwg) (nth 18 existing-master))
                                    (if (/= (nth 9 existing-master) (nth 8 lay))
                                      (LXI:make-mod-stamp timestamp dwg) (nth 19 existing-master))
                                    (if (/= (nth 10 existing-master) (nth 9 lay))
                                      (LXI:make-mod-stamp timestamp dwg) (nth 20 existing-master))
                                    (if (/= (nth 11 existing-master) (nth 10 lay))
                                      (LXI:make-mod-stamp timestamp dwg) (nth 21 existing-master))
                                    dwg timestamp)
                              master-data))))))))
          
          ;; FALL 2: Name-Match
          ((setq existing-master (LXI:find-by-name master-data lay-name))
            (progn
              (setq mid (car existing-master))
              (setq master-data (LXI:remove-by-id master-data mid))
              (setq master-data
                (cons (list mid lay-name
                            (nth 1 lay) (nth 2 lay) (nth 3 lay)
                            (nth 7 lay) (nth 4 lay) (nth 5 lay) (nth 6 lay)
                            (nth 8 lay) (nth 9 lay) (nth 10 lay)
                            ;; Alle Mod-Stamps neu (erster Match)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            dwg timestamp)
                      master-data))
              (setq cnt-upd (1+ cnt-upd))))
          
          ;; FALL 3: Neuer Layer
          (T
            (progn
              (setq new-mid (LXI:next-master-id master-data))
              (setq master-data
                (cons (list new-mid lay-name
                            (nth 1 lay) (nth 2 lay) (nth 3 lay)
                            (nth 7 lay) (nth 4 lay) (nth 5 lay) (nth 6 lay)
                            (nth 8 lay) (nth 9 lay) (nth 10 lay)
                            ;; Alle Mod-Stamps neu
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            (LXI:make-mod-stamp timestamp dwg)
                            dwg timestamp)
                      master-data))
              (setq history-entries
                (cons (list new-mid lay-name timestamp "NEU" "" "" "" dwg) history-entries))
              (setq cnt-new (1+ cnt-new))))))
      
      ;; Mapper (Handle = Index 11)
      (setq mapper-data (LXI:mapper-remove-dwg mapper-data guid dwg))
      (foreach lay layers
        (setq lay-name (nth 0 lay) handle (nth 11 lay))
        (setq mid (car (LXI:find-by-name master-data lay-name)))
        (if mid (setq mapper-data
          (cons (list mid lay-name handle dwg dwg-path guid) mapper-data))))
      
      ;; Schreiben + SyncLog
      (if (and (LXI:write-master master-data) (LXI:write-mapper mapper-data))
        (progn
          (if history-entries (LXI:append-history (reverse history-entries)))
          (setq synclog-data (LXI:update-last-sync synclog-data dwg guid))
          (LXI:write-synclog synclog-data)
          (LXI:log-write (strcat "--- Export (" dwg ") ---"))
          (princ (strcat "\n  --- Export (" dwg ") ---"))
          (if (> cnt-new 0) (progn (LXI:log-write (strcat "  + " (itoa cnt-new) " neu in Master"))
            (princ (strcat "\n    + " (itoa cnt-new) " neu in Master"))))
          (if (> cnt-upd 0) (progn (LXI:log-write (strcat "  ~ " (itoa cnt-upd) " aktualisiert"))
            (princ (strcat "\n    ~ " (itoa cnt-upd) " aktualisiert"))))
          (if (> cnt-ren 0) (progn (LXI:log-write (strcat "  > " (itoa cnt-ren) " umbenannt"))
            (princ (strcat "\n    > " (itoa cnt-ren) " umbenannt"))))
          (if (> cnt-conflict 0) (progn (LXI:log-write (strcat "  ! " (itoa cnt-conflict) " Konflikte (behalten)"))
            (princ (strcat "\n    ! " (itoa cnt-conflict) " Konflikte (behalten)"))))
          (if (and (= cnt-new 0) (= cnt-upd 0) (= cnt-ren 0) (= cnt-conflict 0))
            (progn (LXI:log-write "  = Master ist aktuell")
              (princ "\n    = Master ist aktuell")))
          (LXI:log-write (strcat "  Master gesamt: " (itoa (length master-data)) " Layer"))
          (princ (strcat "\n    Master gesamt: " (itoa (length master-data)) " Layer"))
          T)
        (progn (LXI:log-write "*** Fehler beim Schreiben!")
               (princ "\n  *** Fehler beim Schreiben.") nil)))))


;;; ========================================================================
;;; IMPORT-KERNFUNKTION (24-Feld Master, Field-Level Merge)
;;; Master: 0=MID 1=Name 2=Color 3=Ltype 4=LW 5=Plot 6=OnOff
;;;   7=Frz 8=Lock 9=VPDef 10=Desc 11=Trans
;;;   12=ColorMod 13=LtypeMod 14=LwMod 15=PlotMod 16=OnOffMod
;;;   17=FreezeMod 18=LockMod 19=VPDefMod 20=DescMod 21=TransMod
;;;   22=Source 23=LastMod
;;; collect-layers: 0=Name 1=Color 2=Ltype 3=LW 4=OnOff 5=Frz
;;;   6=Lock 7=Plot 8=VPDef 9=Desc 10=Trans 11=Handle
;;; ========================================================================

;;; Field-Level Merge: Vergleicht Master vs. Lokal pro Property
;;; Neuester Mod-Stamp gewinnt. Gibt merged values zurueck.
;;; Parameter: master-lay (24 Felder), local-data (12 Felder aus read-layer-vla)
;;;            dwg - aktueller DWG-Name, timestamp - aktueller Zeitstempel
;;; Rueckgabe: Liste (merged-values cnt-from-master cnt-from-local)
;;;   merged-values = (col ltype lw plot on-off frz lck vpdef desc trans)
(defun LXI:field-merge (master-lay local-data dwg timestamp
                         / master-vals local-vals mod-stamps
                           merged cnt-master cnt-local
                           i m-val l-val mod-stamp mod-src local-mod
                           result-vals)
  (setq master-vals (list (nth 2 master-lay) (nth 3 master-lay)
                          (nth 4 master-lay) (nth 5 master-lay)
                          (nth 6 master-lay) (nth 7 master-lay)
                          (nth 8 master-lay) (nth 9 master-lay)
                          (nth 10 master-lay) (nth 11 master-lay)))
  ;; local-data: 0=Name 1=Color 2=Ltype 3=LW 4=OnOff 5=Frz 6=Lock 7=Plot 8=VPDef 9=Desc 10=Trans
  ;; Master-Reihenfolge: Color Ltype LW Plot OnOff Frz Lock VPDef Desc Trans
  ;; Lokal-Reihenfolge:  Color Ltype LW OnOff Frz Lock Plot VPDef Desc Trans
  ;; Mapping: Master-idx -> Local-idx
  ;;   0=Color->1  1=Ltype->2  2=LW->3  3=Plot->7  4=OnOff->4
  ;;   5=Frz->5  6=Lock->6  7=VPDef->8  8=Desc->9  9=Trans->10
  (setq local-vals (list (nth 1 local-data) (nth 2 local-data)
                         (nth 3 local-data) (nth 7 local-data)
                         (nth 4 local-data) (nth 5 local-data)
                         (nth 6 local-data) (nth 8 local-data)
                         (nth 9 local-data) (nth 10 local-data)))
  (setq mod-stamps (list (nth 12 master-lay) (nth 13 master-lay)
                         (nth 14 master-lay) (nth 15 master-lay)
                         (nth 16 master-lay) (nth 17 master-lay)
                         (nth 18 master-lay) (nth 19 master-lay)
                         (nth 20 master-lay) (nth 21 master-lay)))
  (setq result-vals nil cnt-master 0 cnt-local 0 i 0)
  (repeat 10
    (setq m-val (nth i master-vals)
          l-val (nth i local-vals)
          mod-stamp (nth i mod-stamps))
    (if (= (strcase m-val) (strcase l-val))
      ;; Gleich -> Master-Wert behalten
      (setq result-vals (cons m-val result-vals))
      ;; Unterschied -> wer ist neuer?
      (progn
        (setq mod-src (LXI:mod-stamp-source mod-stamp))
        (if (= (strcase mod-src) (strcase dwg))
          ;; Aenderung kam von dieser DWG -> lokal ist neuer
          (progn
            (setq result-vals (cons l-val result-vals))
            (setq cnt-local (1+ cnt-local))
            (LXI:debug-print (strcat "  Merge: " (nth 1 master-lay)
                                     " Feld " (itoa i) " -> Lokal: " l-val)))
          ;; Aenderung kam von anderer DWG -> Master ist neuer
          (progn
            (setq result-vals (cons m-val result-vals))
            (setq cnt-master (1+ cnt-master))
            (LXI:debug-print (strcat "  Merge: " (nth 1 master-lay)
                                     " Feld " (itoa i) " -> Master: " m-val))))))
    (setq i (1+ i)))
  (setq result-vals (reverse result-vals))
  (list result-vals cnt-master cnt-local))

(defun LXI:do-import ( / dwg guid dwg-path master-data mapper-data dwg-mapper
                         is-first-import
                         lay mid master-name col ltype lw plot-flag on-off frz lck
                         vpdef desc trans
                         mapped-entry mapped-handle mapped-name
                         local-name local-data merge-result merged-vals
                         choice
                         lay-obj handle new-mapper delete-list
                         doc layers-coll
                         cnt-new cnt-upd cnt-skip cnt-ren cnt-del cnt-merge)
  (setq dwg (LXI:dwg-name))
  (setq guid (LXI:dwg-guid))
  (setq dwg-path (LXI:dwg-path))
  (setq cnt-new 0 cnt-upd 0 cnt-skip 0 cnt-ren 0 cnt-del 0 cnt-merge 0)
  (setq delete-list nil)
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
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
      (setq layers-coll (vla-get-Layers doc))
      (foreach lay master-data
        ;; Master 24 Felder auslesen (Properties: Index 2-11)
        (setq mid (nth 0 lay) master-name (nth 1 lay)
              col (nth 2 lay) ltype (nth 3 lay) lw (nth 4 lay)
              plot-flag (nth 5 lay) on-off (nth 6 lay)
              frz (nth 7 lay) lck (nth 8 lay)
              vpdef (nth 9 lay) desc (nth 10 lay) trans (nth 11 lay))
        (LXI:debug-print (strcat "Import: " master-name " [" mid "]"))
        (setq mapped-entry nil)
        (foreach e dwg-mapper
          (if (= (strcase (nth 0 e)) (strcase mid)) (setq mapped-entry e)))
        (cond
          ;; FALL A: Im Mapper (bekannter Layer)
          (mapped-entry
            (progn
              (setq mapped-handle (nth 2 mapped-entry)
                    mapped-name (nth 1 mapped-entry))
              (setq local-name (LXI:find-local-by-handle mapped-handle))
              (cond
                (local-name
                  (progn
                    (LXI:debug-print (strcat "  Handle " mapped-handle " -> " local-name))
                    (cond
                      ;; Name gleich -> Field-Level Merge
                      ((= (strcase local-name) (strcase master-name))
                        (progn
                          ;; Lokale Werte lesen
                          (setq lay-obj
                            (vl-catch-all-apply 'vla-Item (list layers-coll local-name)))
                          (if (not (vl-catch-all-error-p lay-obj))
                            (progn
                              (setq local-data (LXI:read-layer-vla lay-obj))
                              (setq merge-result
                                (LXI:field-merge lay local-data dwg (LXI:timestamp)))
                              (setq merged-vals (nth 0 merge-result))
                              ;; merged-vals: (col ltype lw plot on-off frz lck vpdef desc trans)
                              (if (or (> (nth 1 merge-result) 0) (> (nth 2 merge-result) 0))
                                ;; Unterschiede -> anwenden
                                (progn
                                  (if (> (nth 1 merge-result) 0)
                                    (progn
                                      (LXI:update-layer-props local-name
                                        (nth 0 merged-vals) (nth 1 merged-vals)
                                        (nth 2 merged-vals) (nth 3 merged-vals)
                                        (nth 4 merged-vals) (nth 5 merged-vals)
                                        (nth 6 merged-vals) (nth 7 merged-vals)
                                        (nth 8 merged-vals) (nth 9 merged-vals))
                                      (setq cnt-upd (1+ cnt-upd))
                                      (setq cnt-merge (+ cnt-merge (nth 1 merge-result))))
                                    (setq cnt-skip (1+ cnt-skip))))
                                ;; Identisch
                                (progn
                                  (LXI:debug-print (strcat "  Skip: " local-name))
                                  (setq cnt-skip (1+ cnt-skip)))))
                            (setq cnt-skip (1+ cnt-skip)))))
                      ;; Name anders (Umbenennung)
                      (T
                        (progn
                          (setq choice (LXI:ask-rename master-name local-name mid))
                          (if (= choice "Master")
                            (progn
                              (command "._-RENAME" "LA" local-name master-name)
                              (princ (strcat "\n  > " local-name " -> " master-name))
                              (LXI:update-layer-props master-name
                                col ltype lw plot-flag on-off frz lck vpdef desc trans)
                              (setq cnt-ren (1+ cnt-ren)))
                            (progn
                              (princ (strcat "\n  = Beibehalten: " local-name))
                              ;; Master-Name auf lokalen Namen aktualisieren
                              ;; damit kein Duplikat angelegt wird
                              (setq master-data (LXI:remove-by-id master-data mid))
                              (setq master-data
                                (cons (LXI:list-set-nth lay 1 local-name) master-data))
                              (LXI:write-master master-data)
                              (LXI:debug-print (strcat "  Master umbenannt: "
                                master-name " -> " local-name))
                              (setq cnt-skip (1+ cnt-skip)))))))))
                ;; Lokal geloescht
                (T
                  (progn
                    (LXI:debug-print (strcat "  Handle " mapped-handle " nicht gefunden"))
                    (setq choice (LXI:ask-deleted master-name mid))
                    (cond
                      ((= choice "Neu")
                        (if (LXI:create-layer master-name
                              col ltype lw plot-flag on-off frz lck
                              vpdef desc trans)
                          (progn (princ (strcat "\n  + " master-name))
                                 (setq cnt-new (1+ cnt-new)))
                          (princ (strcat "\n  *** Fehler: " master-name))))
                      ((= choice "Loeschen")
                        (setq delete-list (cons mid delete-list)
                              cnt-del (1+ cnt-del)))
                      (T (setq cnt-skip (1+ cnt-skip)))))))))
          ;; FALL B: Nicht im Mapper (neuer Layer)
          (T
            (progn
              (LXI:debug-print (strcat "  Neuer Layer: " master-name))
              (if (tblsearch "LAYER" master-name)
                ;; Name lokal vorhanden -> Field-Level Merge
                (progn
                  (LXI:debug-print "  Name lokal vorhanden, verknuepfe")
                  (setq lay-obj
                    (vl-catch-all-apply 'vla-Item (list layers-coll master-name)))
                  (if (not (vl-catch-all-error-p lay-obj))
                    (progn
                      (setq local-data (LXI:read-layer-vla lay-obj))
                      (setq merge-result
                        (LXI:field-merge lay local-data dwg (LXI:timestamp)))
                      (setq merged-vals (nth 0 merge-result))
                      (if (> (nth 1 merge-result) 0)
                        (progn
                          (LXI:update-layer-props master-name
                            (nth 0 merged-vals) (nth 1 merged-vals)
                            (nth 2 merged-vals) (nth 3 merged-vals)
                            (nth 4 merged-vals) (nth 5 merged-vals)
                            (nth 6 merged-vals) (nth 7 merged-vals)
                            (nth 8 merged-vals) (nth 9 merged-vals))
                          (setq cnt-upd (1+ cnt-upd))
                          (setq cnt-merge (+ cnt-merge (nth 1 merge-result))))
                        (setq cnt-skip (1+ cnt-skip))))
                    (setq cnt-skip (1+ cnt-skip))))
                ;; Neuer Layer anlegen
                (if (LXI:create-layer master-name
                      col ltype lw plot-flag on-off frz lck
                      vpdef desc trans)
                  (progn (LXI:debug-print (strcat "  + " master-name))
                         (setq cnt-new (1+ cnt-new)))
                  (princ (strcat "\n  *** Fehler: " master-name))))))))
      ;; Loeschen
      (if delete-list
        (progn
          (foreach del-mid delete-list
            (setq master-data (LXI:remove-by-id master-data del-mid)))
          (LXI:write-master master-data)))
      ;; Mapper aktualisieren (VLA-basiert)
      (setq mapper-data (LXI:mapper-remove-dwg mapper-data guid dwg))
      (setq new-mapper nil)
      (vlax-for lay-obj layers-coll
        (setq lay-name (vla-get-Name lay-obj))
        (if (and (not (LXI:xref-layer-p lay-name)) (LXI:sync-layer-p lay-name))
          (progn
            (setq handle (vla-get-Handle lay-obj))
            (setq mid (car (LXI:find-by-name master-data lay-name)))
            (if mid (setq new-mapper
              (cons (list mid lay-name handle dwg dwg-path guid) new-mapper))))))
      (setq mapper-data (append mapper-data new-mapper))
      (LXI:write-mapper mapper-data)
      ;; SyncLog aktualisieren
      (setq synclog-data (LXI:read-synclog))
      (setq synclog-data (LXI:update-last-sync synclog-data dwg guid))
      (LXI:write-synclog synclog-data)
      ;; Ergebnis
      (LXI:log-write (strcat "--- Import (" dwg ") ---"))
      (princ (strcat "\n  --- Import (" dwg ") ---"))
      (if (> cnt-new 0) (progn (LXI:log-write (strcat "  + " (itoa cnt-new) " neu angelegt"))
        (princ (strcat "\n    + " (itoa cnt-new) " neu angelegt"))))
      (if (> cnt-upd 0) (progn (LXI:log-write (strcat "  ~ " (itoa cnt-upd) " aktualisiert"))
        (princ (strcat "\n    ~ " (itoa cnt-upd) " aktualisiert"))))
      (if (> cnt-merge 0) (progn (LXI:log-write (strcat "  m " (itoa cnt-merge) " Felder gemerged"))
        (princ (strcat "\n    m " (itoa cnt-merge) " Felder gemerged (neuester gewinnt)"))))
      (if (> cnt-ren 0) (progn (LXI:log-write (strcat "  > " (itoa cnt-ren) " umbenannt"))
        (princ (strcat "\n    > " (itoa cnt-ren) " umbenannt"))))
      (if (> cnt-del 0) (progn (LXI:log-write (strcat "  - " (itoa cnt-del) " aus Master gel."))
        (princ (strcat "\n    - " (itoa cnt-del) " aus Master gel."))))
      (if (and (= cnt-new 0) (= cnt-upd 0) (= cnt-ren 0) (= cnt-del 0))
        (progn (LXI:log-write (strcat "  = Synchron (" (itoa cnt-skip) " Layer)"))
          (princ (strcat "\n    = Synchron (" (itoa cnt-skip) " Layer)"))))
      T)))


;;; ========================================================================
;;; SYNC-KERNFUNKTION (Three-Way-Merge mit Snapshot)
;;; Ersetzt do-import + do-export in LAYSYNC
;;;
;;; Ablauf:
;;; 1. Master, Lokale Layer, Mapper, Snapshot lesen
;;; 2. Fuer jeden Master-Layer:
;;;    - Lokal nicht vorhanden -> anlegen
;;;    - Lokal vorhanden -> Three-Way-Merge pro Property
;;;    - Lokal geloescht (Handle weg) -> Fragen
;;;    - Name geaendert (Handle-Match) -> Fragen
;;; 3. Fuer jeden lokalen Layer nicht im Master -> exportieren
;;; 4. Master + Mapper + Snapshot + SyncLog + History schreiben
;;; ========================================================================
(defun LXI:do-sync ( / dwg guid dwg-path timestamp
                       master-data mapper-data dwg-mapper snapshot
                       layers local-layer local-data
                       lay mid master-name col ltype lw plot-flag on-off frz lck
                       vpdef desc trans
                       mapped-entry mapped-handle mapped-name local-name
                       base-vals merge-result winner source
                       master-vals local-vals prop-names prop-idx
                       apply-to-local apply-to-master
                       choice lay-obj handle new-mapper delete-list
                       doc layers-coll
                       history-entries new-mid existing-master
                       synclog-data is-first-sync
                       cnt-new cnt-upd-local cnt-upd-master cnt-skip
                       cnt-ren cnt-del cnt-conflict cnt-export
                       master-names)
  (setq dwg (LXI:dwg-name))
  (setq guid (LXI:dwg-guid))
  (setq dwg-path (LXI:dwg-path))
  (setq timestamp (LXI:timestamp))
  (setq cnt-new 0 cnt-upd-local 0 cnt-upd-master 0 cnt-skip 0
        cnt-ren 0 cnt-del 0 cnt-conflict 0 cnt-export 0)
  (setq delete-list nil history-entries nil)
  (setq prop-names '("Color" "Linetype" "Lineweight" "Plot" "OnOff"
                      "Freeze" "Lock" "VPDefault" "Description" "Transparency"))
  
  (LXI:debug-print (strcat "=== do-sync: " dwg " GUID: " guid " ==="))
  
  ;; 1. Alles lesen
  (setq master-data (LXI:read-master))
  (if (null master-data) (setq master-data nil))
  (setq mapper-data (LXI:read-mapper))
  (if (null mapper-data) (setq mapper-data nil))
  (setq dwg-mapper (LXI:mapper-get-dwg-entries mapper-data guid dwg))
  (setq snapshot (LXI:read-snapshot guid))
  (setq layers (LXI:collect-layers))
  (setq is-first-sync (and (null dwg-mapper) (null snapshot)))
  
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layers-coll (vla-get-Layers doc))
  
  (if is-first-sync
    (princ "\n  Erster Sync fuer diese Zeichnung.")
    (princ (strcat "\n  " (if snapshot
      (strcat "Snapshot vorhanden (" (itoa (length snapshot)) " Layer)")
      "Kein Snapshot") ".")))
  (princ (strcat "\n  Master: " (itoa (length master-data)) " Layer"))
  (princ (strcat "\n  Lokal:  " (itoa (if layers (length layers) 0))
                 " " *LXI:prefix* "* Layer"))
  
  ;; Master-Namen sammeln (fuer Schritt 3)
  (setq master-names nil)
  (foreach lay master-data
    (setq master-names (cons (strcase (nth 1 lay)) master-names)))
  
  ;; 2. Fuer jeden Master-Layer
  (foreach lay master-data
    (setq mid (nth 0 lay) master-name (nth 1 lay)
          col (nth 2 lay) ltype (nth 3 lay) lw (nth 4 lay)
          plot-flag (nth 5 lay) on-off (nth 6 lay)
          frz (nth 7 lay) lck (nth 8 lay)
          vpdef (nth 9 lay) desc (nth 10 lay) trans (nth 11 lay))
    ;; Master-Werte in einheitlicher Reihenfolge (wie Snapshot)
    (setq master-vals (list col ltype lw plot-flag on-off frz lck vpdef desc trans))
    
    ;; Mapper-Eintrag suchen
    (setq mapped-entry nil)
    (foreach e dwg-mapper
      (if (= (strcase (nth 0 e)) (strcase mid)) (setq mapped-entry e)))
    
    (cond
      ;; FALL A: Im Mapper (bekannter Layer)
      (mapped-entry
        (progn
          (setq mapped-handle (nth 2 mapped-entry))
          (setq local-name (LXI:find-local-by-handle mapped-handle))
          (cond
            ;; A1: Lokal vorhanden
            (local-name
              (cond
                ;; Name gleich -> Three-Way-Merge
                ((= (strcase local-name) (strcase master-name))
                  (progn
                    (setq lay-obj
                      (vl-catch-all-apply 'vla-Item (list layers-coll local-name)))
                    (if (not (vl-catch-all-error-p lay-obj))
                      (progn
                        (setq local-data (LXI:read-layer-vla lay-obj))
                        ;; Lokale Werte in Master-Reihenfolge
                        (setq local-vals
                          (list (nth 1 local-data) (nth 2 local-data)
                                (nth 3 local-data) (nth 7 local-data)
                                (nth 4 local-data) (nth 5 local-data)
                                (nth 6 local-data) (nth 8 local-data)
                                (nth 9 local-data) (nth 10 local-data)))
                        ;; Snapshot (Base)
                        (setq base-vals (LXI:snapshot-get snapshot local-name))
                        ;; Pro Property mergen
                        (setq apply-to-local nil apply-to-master nil prop-idx 0)
                        (repeat 10
                          (setq merge-result
                            (LXI:three-way-merge-field
                              (if base-vals (nth prop-idx base-vals) nil)
                              (nth prop-idx local-vals)
                              (nth prop-idx master-vals)))
                          (setq winner (nth 0 merge-result)
                                source (nth 1 merge-result))
                          (cond
                            ((= source "LOCAL")
                              (progn
                                (setq apply-to-master (cons prop-idx apply-to-master))
                                ;; History
                                (setq history-entries
                                  (cons (list mid master-name timestamp "AENDERUNG"
                                    (nth prop-idx prop-names)
                                    (nth prop-idx master-vals)
                                    (nth prop-idx local-vals) dwg)
                                    history-entries))))
                            ((= source "MASTER")
                              (setq apply-to-local (cons prop-idx apply-to-local)))
                            ((= source "CONFLICT")
                              (progn
                                ;; Neuester Mod-Stamp gewinnt
                                (setq apply-to-local (cons prop-idx apply-to-local))
                                (setq cnt-conflict (1+ cnt-conflict))
                                (LXI:debug-print
                                  (strcat "  Konflikt: " master-name
                                          " " (nth prop-idx prop-names)
                                          " L=" (nth prop-idx local-vals)
                                          " M=" (nth prop-idx master-vals)
                                          " -> Master")))))
                          (setq prop-idx (1+ prop-idx)))
                        ;; Lokal aktualisieren (Master -> Lokal)
                        (if apply-to-local
                          (progn
                            (LXI:update-layer-props local-name
                              (nth 0 master-vals) (nth 1 master-vals)
                              (nth 2 master-vals) (nth 3 master-vals)
                              (nth 4 master-vals) (nth 5 master-vals)
                              (nth 6 master-vals) (nth 7 master-vals)
                              (nth 8 master-vals) (nth 9 master-vals))
                            (setq cnt-upd-local
                              (+ cnt-upd-local (length apply-to-local)))))
                        ;; Master aktualisieren (Lokal -> Master)
                        (if apply-to-master
                          (progn
                            (setq master-data (LXI:remove-by-id master-data mid))
                            ;; Neuen Master-Eintrag bauen mit lokalen Werten
                            (setq master-data
                              (cons
                                (list mid master-name
                                  (nth 0 local-vals) (nth 1 local-vals)
                                  (nth 2 local-vals) (nth 3 local-vals)
                                  (nth 4 local-vals) (nth 5 local-vals)
                                  (nth 6 local-vals) (nth 7 local-vals)
                                  (nth 8 local-vals) (nth 9 local-vals)
                                  ;; Mod-Stamps: geaenderte aktualisieren
                                  (if (member 0 apply-to-master)
                                    (LXI:make-mod-stamp timestamp dwg) (nth 12 lay))
                                  (if (member 1 apply-to-master)
                                    (LXI:make-mod-stamp timestamp dwg) (nth 13 lay))
                                  (if (member 2 apply-to-master)
                                    (LXI:make-mod-stamp timestamp dwg) (nth 14 lay))
                                  (if (member 3 apply-to-master)
                                    (LXI:make-mod-stamp timestamp dwg) (nth 15 lay))
                                  (if (member 4 apply-to-master)
                                    (LXI:make-mod-stamp timestamp dwg) (nth 16 lay))
                                  (if (member 5 apply-to-master)
                                    (LXI:make-mod-stamp timestamp dwg) (nth 17 lay))
                                  (if (member 6 apply-to-master)
                                    (LXI:make-mod-stamp timestamp dwg) (nth 18 lay))
                                  (if (member 7 apply-to-master)
                                    (LXI:make-mod-stamp timestamp dwg) (nth 19 lay))
                                  (if (member 8 apply-to-master)
                                    (LXI:make-mod-stamp timestamp dwg) (nth 20 lay))
                                  (if (member 9 apply-to-master)
                                    (LXI:make-mod-stamp timestamp dwg) (nth 21 lay))
                                  dwg timestamp)
                                master-data))
                            (setq cnt-upd-master
                              (+ cnt-upd-master (length apply-to-master)))))
                        ;; Nichts geaendert
                        (if (and (null apply-to-local) (null apply-to-master))
                          (setq cnt-skip (1+ cnt-skip))))
                      (setq cnt-skip (1+ cnt-skip)))))
                ;; Name anders (Umbenennung)
                (T
                  (progn
                    (setq choice (LXI:ask-rename master-name local-name mid))
                    (if (= choice "Master")
                      (progn
                        (command "._-RENAME" "LA" local-name master-name)
                        (princ (strcat "\n  > " local-name " -> " master-name))
                        (LXI:update-layer-props master-name
                          col ltype lw plot-flag on-off frz lck vpdef desc trans)
                        (setq history-entries
                          (cons (list mid master-name timestamp "UMBENENNUNG"
                                      "Name" local-name master-name dwg)
                                history-entries))
                        (setq cnt-ren (1+ cnt-ren)))
                      (progn
                        (princ (strcat "\n  = Beibehalten: " local-name))
                        ;; Master-Name auf lokalen Namen aendern
                        (setq master-data (LXI:remove-by-id master-data mid))
                        (setq master-data
                          (cons (LXI:list-set-nth lay 1 local-name) master-data))
                        (setq cnt-skip (1+ cnt-skip))))))))
            ;; A2: Lokal geloescht (Handle nicht gefunden)
            (T
              (progn
                (setq choice (LXI:ask-deleted master-name mid))
                (cond
                  ((= choice "Neu")
                    (if (LXI:create-layer master-name
                          col ltype lw plot-flag on-off frz lck vpdef desc trans)
                      (progn (princ (strcat "\n  + " master-name))
                             (setq cnt-new (1+ cnt-new)))
                      (princ (strcat "\n  *** Fehler: " master-name))))
                  ((= choice "Loeschen")
                    (setq delete-list (cons mid delete-list)
                          cnt-del (1+ cnt-del)))
                  (T (setq cnt-skip (1+ cnt-skip)))))))))
      ;; FALL B: Nicht im Mapper
      (T
        (progn
          (if (tblsearch "LAYER" master-name)
            ;; Lokal vorhanden aber nicht gemappt -> Three-Way ohne Base
            (progn
              (setq lay-obj
                (vl-catch-all-apply 'vla-Item (list layers-coll master-name)))
              (if (not (vl-catch-all-error-p lay-obj))
                (progn
                  (setq local-data (LXI:read-layer-vla lay-obj))
                  (setq local-vals
                    (list (nth 1 local-data) (nth 2 local-data)
                          (nth 3 local-data) (nth 7 local-data)
                          (nth 4 local-data) (nth 5 local-data)
                          (nth 6 local-data) (nth 8 local-data)
                          (nth 9 local-data) (nth 10 local-data)))
                  ;; Ohne Base: Master gewinnt bei Unterschied
                  (setq apply-to-local nil prop-idx 0)
                  (repeat 10
                    (if (/= (strcase (nth prop-idx local-vals))
                            (strcase (nth prop-idx master-vals)))
                      (setq apply-to-local (cons prop-idx apply-to-local)))
                    (setq prop-idx (1+ prop-idx)))
                  (if apply-to-local
                    (progn
                      (LXI:update-layer-props master-name
                        col ltype lw plot-flag on-off frz lck vpdef desc trans)
                      (setq cnt-upd-local (+ cnt-upd-local (length apply-to-local))))
                    (setq cnt-skip (1+ cnt-skip))))
                (setq cnt-skip (1+ cnt-skip))))
            ;; Lokal nicht vorhanden -> anlegen
            (if (LXI:create-layer master-name
                  col ltype lw plot-flag on-off frz lck vpdef desc trans)
              (progn
                (LXI:debug-print (strcat "  + " master-name))
                (setq cnt-new (1+ cnt-new)))
              (princ (strcat "\n  *** Fehler: " master-name))))))))
  
  ;; 3. Lokale Layer die nicht im Master sind -> exportieren
  (if layers
    (foreach local-layer layers
      (setq local-name (nth 0 local-layer))
      (if (not (member (strcase local-name) master-names))
        (progn
          (setq new-mid (LXI:next-master-id master-data))
          (setq master-data
            (cons (list new-mid local-name
                        (nth 1 local-layer) (nth 2 local-layer) (nth 3 local-layer)
                        (nth 7 local-layer) (nth 4 local-layer) (nth 5 local-layer)
                        (nth 6 local-layer) (nth 8 local-layer)
                        (nth 9 local-layer) (nth 10 local-layer)
                        (LXI:make-mod-stamp timestamp dwg)
                        (LXI:make-mod-stamp timestamp dwg)
                        (LXI:make-mod-stamp timestamp dwg)
                        (LXI:make-mod-stamp timestamp dwg)
                        (LXI:make-mod-stamp timestamp dwg)
                        (LXI:make-mod-stamp timestamp dwg)
                        (LXI:make-mod-stamp timestamp dwg)
                        (LXI:make-mod-stamp timestamp dwg)
                        (LXI:make-mod-stamp timestamp dwg)
                        (LXI:make-mod-stamp timestamp dwg)
                        dwg timestamp)
                  master-data))
          (setq master-names (cons (strcase local-name) master-names))
          (setq history-entries
            (cons (list new-mid local-name timestamp "NEU" "" "" "" dwg)
                  history-entries))
          (setq cnt-export (1+ cnt-export))))))
  
  ;; 4. Geloeschte Layer aus Master entfernen
  (if delete-list
    (foreach del-mid delete-list
      (setq master-data (LXI:remove-by-id master-data del-mid))))
  
  ;; 5. Mapper aktualisieren
  (setq mapper-data (LXI:mapper-remove-dwg mapper-data guid dwg))
  (setq new-mapper nil)
  ;; Aktuelle Layer neu lesen (nach Aenderungen)
  (setq layers (LXI:collect-layers))
  (if layers
    (foreach local-layer layers
      (setq local-name (nth 0 local-layer)
            handle (nth 11 local-layer))
      (setq mid (car (LXI:find-by-name master-data local-name)))
      (if mid
        (setq new-mapper
          (cons (list mid local-name handle dwg dwg-path guid) new-mapper)))))
  (setq mapper-data (append mapper-data new-mapper))
  
  ;; 6. Alles schreiben
  (LXI:write-master master-data)
  (LXI:write-mapper mapper-data)
  ;; Snapshot schreiben (aktueller Zustand nach Sync)
  (if layers (LXI:write-snapshot guid layers))
  ;; History
  (if history-entries (LXI:append-history (reverse history-entries)))
  ;; SyncLog
  (setq synclog-data (LXI:read-synclog))
  (setq synclog-data (LXI:update-last-sync synclog-data dwg guid))
  (LXI:write-synclog synclog-data)
  
  ;; 7. Ergebnis
  (LXI:log-write (strcat "--- Sync (" dwg ") ---"))
  (princ (strcat "\n\n  --- Sync (" dwg ") ---"))
  (if (> cnt-new 0)
    (princ (strcat "\n    + " (itoa cnt-new) " neu aus Master angelegt")))
  (if (> cnt-export 0)
    (princ (strcat "\n    + " (itoa cnt-export) " neu in Master exportiert")))
  (if (> cnt-upd-local 0)
    (princ (strcat "\n    < " (itoa cnt-upd-local) " Properties Master -> Lokal")))
  (if (> cnt-upd-master 0)
    (princ (strcat "\n    > " (itoa cnt-upd-master) " Properties Lokal -> Master")))
  (if (> cnt-ren 0)
    (princ (strcat "\n    ~ " (itoa cnt-ren) " umbenannt")))
  (if (> cnt-del 0)
    (princ (strcat "\n    - " (itoa cnt-del) " aus Master entfernt")))
  (if (> cnt-conflict 0)
    (princ (strcat "\n    ! " (itoa cnt-conflict) " Konflikte (Master gewinnt)")))
  (if (and (= cnt-new 0) (= cnt-export 0) (= cnt-upd-local 0)
           (= cnt-upd-master 0) (= cnt-ren 0) (= cnt-del 0))
    (princ (strcat "\n    = Synchron (" (itoa cnt-skip) " Layer)")))
  (princ (strcat "\n    Master gesamt: " (itoa (length master-data)) " Layer"))
  T)


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
;;; Gemeinsame Batch-Sync Logik fuer Documents und ObjectDBX
;;; Setzt alle 10 Properties auf einem VLA Layer-Objekt
;;; Parameter: lay-obj - VLA Layer, Master-Werte als Strings
;;; Rueckgabe: Liste von Konflikten oder nil
;;; ------------------------------------------------------------------------
(defun LXI:batch-apply-props (lay-obj col ltype lw plot-flag on-off frz lck
                               vpdef desc / local-data conflicts)
  (setq conflicts nil)
  ;; Lokale Werte lesen via read-layer-vla
  (setq local-data (LXI:read-layer-vla lay-obj))
  ;; local-data: 0=Name 1=Color 2=Ltype 3=LW 4=OnOff 5=Frz 6=Lock 7=Plot 8=VPDef 9=Desc 10=Trans 11=Handle
  
  ;; Konflikte sammeln (nur fuer Report, Master wird trotzdem angewendet)
  (if (/= (nth 1 local-data) col)
    (setq conflicts (cons (list (nth 0 local-data) "Farbe" col (nth 1 local-data)) conflicts)))
  (if (/= (strcase (nth 4 local-data)) (strcase on-off))
    (setq conflicts (cons (list (nth 0 local-data) "OnOff" on-off (nth 4 local-data)) conflicts)))
  (if (/= (strcase (nth 7 local-data)) (strcase plot-flag))
    (setq conflicts (cons (list (nth 0 local-data) "Plot" plot-flag (nth 7 local-data)) conflicts)))
  (if (/= (nth 3 local-data) lw)
    (setq conflicts (cons (list (nth 0 local-data) "LStaerke" lw (nth 3 local-data)) conflicts)))
  (if (/= (strcase (nth 5 local-data)) (strcase frz))
    (setq conflicts (cons (list (nth 0 local-data) "Freeze" frz (nth 5 local-data)) conflicts)))
  (if (/= (strcase (nth 6 local-data)) (strcase lck))
    (setq conflicts (cons (list (nth 0 local-data) "Lock" lck (nth 6 local-data)) conflicts)))
  
  ;; Master anwenden
  (LXI:apply-color lay-obj col)
  (vl-catch-all-apply 'vla-put-Linetype (list lay-obj ltype))
  (vl-catch-all-apply 'vla-put-Lineweight (list lay-obj (LXI:safe-atoi lw -3)))
  (vla-put-LayerOn lay-obj (if (= on-off "ON") :vlax-true :vlax-false))
  (vl-catch-all-apply 'vla-put-Freeze
    (list lay-obj (if (= frz "FROZEN") :vlax-true :vlax-false)))
  (vla-put-Lock lay-obj (if (= lck "LOCKED") :vlax-true :vlax-false))
  (vla-put-Plottable lay-obj (if (= plot-flag "PLOT") :vlax-true :vlax-false))
  (vl-catch-all-apply 'vlax-put-property
    (list lay-obj 'ViewportDefault (if (= vpdef "1") :vlax-true :vlax-false)))
  (if desc (vl-catch-all-apply 'vla-put-Description (list lay-obj desc)))
  ;; Transparenz: nicht via VLA moeglich (nur command)
  
  conflicts)


;;; ------------------------------------------------------------------------
;;; Synced Layer in einer geoeffneten Zeichnung (Documents-Collection)
;;; Alle 10 Properties + Loeschen nicht mehr vorhandener Layer
;;; Master: 0=MID 1=Name 2=Color 3=Ltype 4=LW 5=Plot 6=OnOff
;;;   7=Frz 8=Lock 9=VPDef 10=Desc 11=Trans 12=Source 13=LastMod
;;; Rueckgabe: Liste '(cnt-new cnt-upd cnt-skip conflicts cnt-del del-info)
;;; ------------------------------------------------------------------------
(defun LXI:doc-sync-layers (doc master-data / layers-coll lay-obj
                              lay master-name col ltype lw plot-flag on-off frz lck
                              vpdef desc trans
                              local-data local-conflicts has-diff
                              cnt-new cnt-upd cnt-skip conflicts
                              cnt-del del-info master-names lay-name del-result)
  (setq cnt-new 0 cnt-upd 0 cnt-skip 0 cnt-del 0 conflicts nil del-info nil)
  (setq layers-coll (vla-get-Layers doc))
  
  ;; Master-Namen sammeln
  (setq master-names nil)
  (foreach lay master-data
    (setq master-names (cons (strcase (nth 1 lay)) master-names)))
  
  ;; 1) Layer anlegen/aktualisieren
  (foreach lay master-data
    (setq master-name (nth 1 lay) col (nth 2 lay) ltype (nth 3 lay)
          lw (nth 4 lay) plot-flag (nth 5 lay) on-off (nth 6 lay)
          frz (nth 7 lay) lck (nth 8 lay) vpdef (nth 9 lay)
          desc (nth 10 lay) trans (nth 11 lay))
    (setq lay-obj
      (vl-catch-all-apply 'vla-Item (list layers-coll master-name)))
    (if (vl-catch-all-error-p lay-obj)
      ;; Neuer Layer
      (progn
        (setq lay-obj
          (vl-catch-all-apply 'vla-Add (list layers-coll master-name)))
        (if (not (vl-catch-all-error-p lay-obj))
          (progn
            (LXI:apply-color lay-obj col)
            (vl-catch-all-apply 'vla-put-Linetype (list lay-obj ltype))
            (vl-catch-all-apply 'vla-put-Lineweight (list lay-obj (LXI:safe-atoi lw -3)))
            (vla-put-LayerOn lay-obj (if (= on-off "ON") :vlax-true :vlax-false))
            (vl-catch-all-apply 'vla-put-Freeze
              (list lay-obj (if (= frz "FROZEN") :vlax-true :vlax-false)))
            (vla-put-Lock lay-obj (if (= lck "LOCKED") :vlax-true :vlax-false))
            (vla-put-Plottable lay-obj (if (= plot-flag "PLOT") :vlax-true :vlax-false))
            (if (= vpdef "1")
              (vl-catch-all-apply 'vlax-put-property
                (list lay-obj 'ViewportDefault :vlax-true)))
            (if (and desc (/= desc ""))
              (vl-catch-all-apply 'vla-put-Description (list lay-obj desc)))
            (setq cnt-new (1+ cnt-new)))))
      ;; Existiert: vergleichen und aktualisieren
      (progn
        (setq local-conflicts
          (LXI:batch-apply-props lay-obj col ltype lw plot-flag on-off frz lck vpdef desc))
        (if local-conflicts
          (progn
            (setq conflicts (append conflicts local-conflicts))
            (setq cnt-upd (1+ cnt-upd)))
          (setq cnt-skip (1+ cnt-skip))))))
  
  ;; 2) Layer entfernen die nicht im Master sind
  (vlax-for lay-obj layers-coll
    (setq lay-name (vla-get-Name lay-obj))
    (if (and (LXI:sync-layer-p lay-name)
             (not (LXI:xref-layer-p lay-name))
             (not (member (strcase lay-name) master-names)))
      (progn
        (setq del-result
          (vl-catch-all-apply 'vla-Delete (list lay-obj)))
        (if (vl-catch-all-error-p del-result)
          (progn
            (vl-catch-all-apply 'vla-put-LayerOn (list lay-obj :vlax-false))
            (setq del-info (cons (list lay-name "OFF") del-info))
            (setq cnt-del (1+ cnt-del)))
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
            (cons (list mid lay-name handle dwg-name dwg-path dwg-guid)
                  new-entries))))))
  (append mapper-data new-entries))


;;; ------------------------------------------------------------------------
;;; Synced Layer in einer DBX-Zeichnung (geschlossen)
;;; Alle 10 Properties + OFF fuer entfernte Layer
;;; Transparenz nicht moeglich via ObjectDBX
;;; Rueckgabe: Liste '(cnt-new cnt-upd cnt-skip conflicts cnt-del del-info)
;;; ------------------------------------------------------------------------
(defun LXI:dbx-sync-layers (dbx-doc master-data / layers-coll lay-obj
                              lay master-name col ltype lw plot-flag on-off frz lck
                              vpdef desc trans
                              local-conflicts
                              cnt-new cnt-upd cnt-skip conflicts
                              cnt-del del-info master-names lay-name)
  (setq cnt-new 0 cnt-upd 0 cnt-skip 0 cnt-del 0 conflicts nil del-info nil)
  (setq layers-coll (vla-get-Layers dbx-doc))
  
  (setq master-names nil)
  (foreach lay master-data
    (setq master-names (cons (strcase (nth 1 lay)) master-names)))
  
  ;; 1) Layer anlegen/aktualisieren
  (foreach lay master-data
    (setq master-name (nth 1 lay) col (nth 2 lay) ltype (nth 3 lay)
          lw (nth 4 lay) plot-flag (nth 5 lay) on-off (nth 6 lay)
          frz (nth 7 lay) lck (nth 8 lay) vpdef (nth 9 lay)
          desc (nth 10 lay) trans (nth 11 lay))
    (setq lay-obj
      (vl-catch-all-apply 'vla-Item (list layers-coll master-name)))
    (if (vl-catch-all-error-p lay-obj)
      (progn
        (setq lay-obj
          (vl-catch-all-apply 'vla-Add (list layers-coll master-name)))
        (if (not (vl-catch-all-error-p lay-obj))
          (progn
            (LXI:apply-color lay-obj col)
            (vl-catch-all-apply 'vla-put-Linetype (list lay-obj ltype))
            (vl-catch-all-apply 'vla-put-Lineweight (list lay-obj (LXI:safe-atoi lw -3)))
            (vla-put-LayerOn lay-obj (if (= on-off "ON") :vlax-true :vlax-false))
            (vl-catch-all-apply 'vla-put-Freeze
              (list lay-obj (if (= frz "FROZEN") :vlax-true :vlax-false)))
            (vla-put-Lock lay-obj (if (= lck "LOCKED") :vlax-true :vlax-false))
            (vla-put-Plottable lay-obj (if (= plot-flag "PLOT") :vlax-true :vlax-false))
            (if (= vpdef "1")
              (vl-catch-all-apply 'vlax-put-property
                (list lay-obj 'ViewportDefault :vlax-true)))
            (if (and desc (/= desc ""))
              (vl-catch-all-apply 'vla-put-Description (list lay-obj desc)))
            (setq cnt-new (1+ cnt-new)))))
      ;; Existiert: vergleichen
      (progn
        (setq local-conflicts
          (LXI:batch-apply-props lay-obj col ltype lw plot-flag on-off frz lck vpdef desc))
        (if local-conflicts
          (progn
            (setq conflicts (append conflicts local-conflicts))
            (setq cnt-upd (1+ cnt-upd)))
          (setq cnt-skip (1+ cnt-skip))))))
  
  ;; 2) OFF setzen
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
;;; Aktualisiert Mapper fuer eine DBX-Zeichnung
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
    (if (and (not (LXI:xref-layer-p lay-name)) (LXI:sync-layer-p lay-name))
      (progn
        (setq handle (vla-get-Handle lay-obj))
        (setq mid (car (LXI:find-by-name master-data lay-name)))
        (if mid
          (setq new-entries
            (cons (list mid lay-name handle dwg-name dwg-path dwg-guid)
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
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER in LAYSYNCALL: " msg))))
    (if (and (boundp 'dbx-doc) dbx-doc)
      (progn
        (vl-catch-all-apply 'vlax-release-object (list dbx-doc))
        (setq dbx-doc nil)))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:ensure-init)
  (setq current-dwg (LXI:dwg-name))
  (LXI:log-write (strcat "=== LAYSYNCALL gestartet von: " current-dwg " ==="))
  
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
(defun c:LAYSYNC ( / *error* old-cmdecho sync-ok choice)
  (defun *error* (msg)
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER: " msg))))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:ensure-init)
  (LXI:log-write (strcat "=== LAYSYNC gestartet: " (LXI:dwg-name) " ==="))
  (princ "\n")
  (princ "\n========================================")
  (princ (strcat "\n  LAYSYNC: " (LXI:dwg-name)))
  (princ (strcat "\n  GUID:    " (LXI:dwg-guid)))
  (princ "\n========================================")
  (setq sync-ok (LXI:do-sync))
  (princ "\n")
  (princ "\n========================================")
  (if sync-ok
    (princ "\n  Sync erfolgreich.")
    (princ "\n  *** Sync fehlgeschlagen!"))
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
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER: " msg))))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:ensure-init)
  (LXI:log-write (strcat "=== LAYEXP gestartet: " (LXI:dwg-name) " ==="))
  (LXI:do-export)
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYIMP
;;; ========================================================================
(defun c:LAYIMP ( / *error* old-cmdecho)
  (defun *error* (msg)
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER: " msg))))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:ensure-init)
  (LXI:log-write (strcat "=== LAYIMP gestartet: " (LXI:dwg-name) " ==="))
  (LXI:do-import)
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYLOG
;;; ========================================================================
(defun c:LAYLOG ( / *error* old-cmdecho choice history filter-name filter-mid
                    master-data results count entry)
  (defun *error* (msg)
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER: " msg))))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:ensure-init)
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
            (princ "\nDatum              Aktion        Layer                    Property     Alt          Neu          Quelle")
            (princ "\n------------------------------------------------------------------------------------------------------")
            (repeat count
              (setq entry (car results))
              (princ (strcat "\n" (LXI:pad-str (nth 2 entry) 19)
                (LXI:pad-str (nth 3 entry) 13)
                (LXI:pad-str (nth 1 entry) 25)
                (LXI:pad-str (if (nth 4 entry) (nth 4 entry) "") 13)
                (LXI:pad-str (if (nth 5 entry) (nth 5 entry) "") 13)
                (LXI:pad-str (if (nth 6 entry) (nth 6 entry) "") 13)
                (if (nth 7 entry) (nth 7 entry) "")))
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
                        '(lambda (e) (= (strcase (nth 0 e)) (strcase filter-mid)))
                        history))
                    (if results
                      (progn
                        (princ (strcat "\n\n=== " filter-name " [" filter-mid "] ==="))
                        (princ "\nDatum              Aktion        Layer                    Property     Alt          Neu          Quelle")
                        (princ "\n------------------------------------------------------------------------------------------------------")
                        (foreach entry results
                          (princ (strcat "\n" (LXI:pad-str (nth 2 entry) 19)
                            (LXI:pad-str (nth 3 entry) 13)
                            (LXI:pad-str (nth 1 entry) 25)
                            (LXI:pad-str (if (nth 4 entry) (nth 4 entry) "") 13)
                            (LXI:pad-str (if (nth 5 entry) (nth 5 entry) "") 13)
                            (LXI:pad-str (if (nth 6 entry) (nth 6 entry) "") 13)
                            (if (nth 7 entry) (nth 7 entry) ""))))
                        (princ "\n"))
                      (princ "\n*** Keine History.")))
                  (princ (strcat "\n*** \"" filter-name "\" nicht gefunden."))))
              (princ "\n*** Kein Name.")))))))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYSTATUS
;;; ========================================================================
(defun c:LAYSTATUS ( / *error* old-cmdecho master-data mapper-data synclog-data
                       dwg-list dwg-entry dwg-name dwg-guid dwg-path last-sync
                       total-master master-ids dwg-mids dwg-count dwg-missing mid)
  (defun *error* (msg)
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER: " msg))))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:ensure-init)
  (setq master-data (LXI:read-master)
        mapper-data (LXI:read-mapper)
        synclog-data (LXI:read-synclog))
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
          (princ (strcat "\nMaster: " (itoa total-master)
                         " Layer | Praefix: " *LXI:prefix* "*"))
          (princ (strcat "\nProperties: Farbe, Linientyp, Linienstaerke, Plot, OnOff,"))
          (princ "\n            Freeze, Lock, VP-Default, Beschreibung, Transparenz")
          (princ (strcat "\n" (LXI:pad-str "Zeichnung" 28)
                         (LXI:pad-str "Layer" 7)
                         (LXI:pad-str "Fehlend" 10)
                         (LXI:pad-str "Letzter Sync" 20)))
          (princ (strcat "\n" (LXI:pad-str "----------------------------" 28)
                         (LXI:pad-str "-------" 7)
                         (LXI:pad-str "----------" 10)
                         "--------------------"))
          (foreach dwg-entry dwg-list
            (setq dwg-name (nth 0 dwg-entry)
                  dwg-guid (nth 1 dwg-entry)
                  dwg-path (nth 2 dwg-entry))
            (setq dwg-mids nil)
            (foreach entry mapper-data
              (if (= (strcase (nth 3 entry)) (strcase dwg-name))
                (setq dwg-mids (cons (nth 0 entry) dwg-mids))))
            (setq dwg-count (length dwg-mids) dwg-missing 0)
            (foreach mid master-ids
              (if (not (member mid dwg-mids))
                (setq dwg-missing (1+ dwg-missing))))
            ;; LastSync aus SyncLog
            (setq last-sync
              (if synclog-data
                (LXI:get-last-sync synclog-data dwg-guid dwg-name)
                nil))
            (princ (strcat "\n"
              (LXI:pad-str dwg-name 28)
              (LXI:pad-str (itoa dwg-count) 7)
              (LXI:pad-str
                (if (= dwg-missing 0) "OK"
                  (strcat (itoa dwg-missing) " fehlen")) 10)
              (if last-sync last-sync "nie"))))
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
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER: " msg))))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:ensure-init)
  (princ "\n\n=== LayerSync Konfiguration ===")
  (princ (strcat "\n  [P]fad:      " *LXI:base-path*))
  (princ (strcat "\n  P[r]aefix:   " *LXI:prefix*))
  (princ (strcat "\n  [D]ebug:     " (if *LXI:debug* "ON" "OFF")))
  (princ (strcat "\n  [A]utoSync:  " (if *LXI:autosync* "ON" "OFF")))
  (princ (strcat "\n  [N]otify:    " (if *LXI:notify* "ON" "OFF")))
  (princ (strcat "\n  DWG-GUID:    " (LXI:dwg-guid)))
  (princ "\n===============================\n")
  (initget "Pfad pRaefix Debug Autosync Notify")
  (setq choice (getkword "\n[Pfad/pRaefix/Debug/Autosync/Notify] <Abbruch>: "))
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
             (princ (strcat "\nDebug: " (if *LXI:debug* "ON" "OFF")))))
    ((= choice "Autosync")
      (progn
        (setq *LXI:autosync* (not *LXI:autosync*))
        (if *LXI:autosync* (LXI:reactor-enable) (LXI:reactor-disable))
        (LXI:write-config)
        (princ (strcat "\nAutoSync: " (if *LXI:autosync* "ON" "OFF")))))
    ((= choice "Notify")
      (progn (setq *LXI:notify* (not *LXI:notify*)) (LXI:write-config)
             (princ (strcat "\nNotify: " (if *LXI:notify* "ON" "OFF"))))))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYDIFF - Vorschau ohne Sync
;;; Zeigt alle Unterschiede zwischen Master und aktueller Zeichnung
;;; ========================================================================
(defun c:LAYDIFF ( / *error* old-cmdecho dwg guid master-data mapper-data
                     dwg-mapper lay mid master-name col ltype lw plot-flag
                     on-off frz lck vpdef desc trans
                     mapped-entry mapped-handle local-name diffs
                     cnt-diff cnt-missing cnt-extra cnt-sync
                     master-names local-layers lay-obj lay-name)
  (defun *error* (msg)
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER: " msg))))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:ensure-init)
  (setq dwg (LXI:dwg-name) guid (LXI:dwg-guid))
  (LXI:log-write (strcat "=== LAYDIFF gestartet: " dwg " ==="))
  (setq master-data (LXI:read-master))
  (if (null master-data)
    (princ "\n*** Kein Master vorhanden.")
    (progn
      (setq mapper-data (LXI:read-mapper))
      (if (null mapper-data) (setq mapper-data nil))
      (setq dwg-mapper (LXI:mapper-get-dwg-entries mapper-data guid dwg))
      (setq cnt-diff 0 cnt-missing 0 cnt-extra 0 cnt-sync 0)
      
      (princ "\n\n====== LAYDIFF: Vorschau ======")
      (princ (strcat "\n" dwg " vs. Master (" (itoa (length master-data)) " Layer)"))
      (princ "\n================================")
      
      ;; 1) Master-Layer pruefen: Unterschiede und fehlende
      (setq master-names nil)
      (foreach lay master-data
        (setq mid (nth 0 lay) master-name (nth 1 lay)
              col (nth 2 lay) ltype (nth 3 lay) lw (nth 4 lay)
              plot-flag (nth 5 lay) on-off (nth 6 lay)
              frz (nth 7 lay) lck (nth 8 lay)
              vpdef (nth 9 lay) desc (nth 10 lay) trans (nth 11 lay))
        (setq master-names (cons (strcase master-name) master-names))
        
        ;; Lokal vorhanden?
        (if (tblsearch "LAYER" master-name)
          (progn
            ;; Vergleich aller Properties
            (setq diffs (LXI:compare-layer-props
              master-name col ltype lw plot-flag on-off frz lck vpdef desc trans))
            (if diffs
              (progn
                (setq cnt-diff (1+ cnt-diff))
                (princ (strcat "\n  ~ " (LXI:pad-str master-name 30) " UNTERSCHIEDE:"))
                (foreach d diffs
                  (princ (strcat "\n      " d))))
              (setq cnt-sync (1+ cnt-sync))))
          ;; Nicht lokal vorhanden
          (progn
            (setq cnt-missing (1+ cnt-missing))
            (princ (strcat "\n  - " (LXI:pad-str master-name 30) " FEHLT lokal")))))
      
      ;; 2) Lokale Layer die nicht im Master sind
      (setq local-layers nil)
      (vlax-for lay-obj (vla-get-Layers
        (vla-get-ActiveDocument (vlax-get-acad-object)))
        (setq lay-name (vla-get-Name lay-obj))
        (if (and (LXI:sync-layer-p lay-name)
                 (not (LXI:xref-layer-p lay-name))
                 (not (member (strcase lay-name) master-names)))
          (progn
            (setq cnt-extra (1+ cnt-extra))
            (princ (strcat "\n  + " (LXI:pad-str lay-name 30) " NUR LOKAL (nicht im Master)")))))
      
      ;; Zusammenfassung
      (princ "\n\n--------------------------------")
      (princ (strcat "\n  Synchron:     " (itoa cnt-sync)))
      (princ (strcat "\n  Unterschiede: " (itoa cnt-diff)))
      (princ (strcat "\n  Fehlt lokal:  " (itoa cnt-missing)))
      (princ (strcat "\n  Nur lokal:    " (itoa cnt-extra)))
      (if (and (= cnt-diff 0) (= cnt-missing 0) (= cnt-extra 0))
        (princ "\n\n  Alles synchron!")
        (princ "\n\n  LAYSYNC ausfuehren um zu synchronisieren."))
      (princ "\n================================")
      (LXI:log-write (strcat "LAYDIFF: " (itoa cnt-sync) " sync, "
                              (itoa cnt-diff) " diff, "
                              (itoa cnt-missing) " fehlen, "
                              (itoa cnt-extra) " extra"))))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYCOUNT - Schnellinfo
;;; ========================================================================
(defun c:LAYCOUNT ( / *error* old-cmdecho dwg guid master-data mapper-data
                      dwg-mapper lay mid master-name
                      col ltype lw plot-flag on-off frz lck vpdef desc trans
                      diffs cnt-sync cnt-diff cnt-missing cnt-extra
                      master-names lay-obj lay-name)
  (defun *error* (msg)
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER: " msg))))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:ensure-init)
  (setq dwg (LXI:dwg-name) guid (LXI:dwg-guid))
  (setq master-data (LXI:read-master))
  (if (null master-data)
    (princ "\n*** Kein Master.")
    (progn
      (setq cnt-sync 0 cnt-diff 0 cnt-missing 0 cnt-extra 0)
      (setq master-names nil)
      (foreach lay master-data
        (setq master-name (nth 1 lay)
              col (nth 2 lay) ltype (nth 3 lay) lw (nth 4 lay)
              plot-flag (nth 5 lay) on-off (nth 6 lay)
              frz (nth 7 lay) lck (nth 8 lay)
              vpdef (nth 9 lay) desc (nth 10 lay) trans (nth 11 lay))
        (setq master-names (cons (strcase master-name) master-names))
        (if (tblsearch "LAYER" master-name)
          (progn
            (setq diffs (LXI:compare-layer-props
              master-name col ltype lw plot-flag on-off frz lck vpdef desc trans))
            (if diffs
              (setq cnt-diff (1+ cnt-diff))
              (setq cnt-sync (1+ cnt-sync))))
          (setq cnt-missing (1+ cnt-missing))))
      ;; Lokale Extras
      (vlax-for lay-obj (vla-get-Layers
        (vla-get-ActiveDocument (vlax-get-acad-object)))
        (setq lay-name (vla-get-Name lay-obj))
        (if (and (LXI:sync-layer-p lay-name)
                 (not (LXI:xref-layer-p lay-name))
                 (not (member (strcase lay-name) master-names)))
          (setq cnt-extra (1+ cnt-extra))))
      ;; Einzeiler-Ausgabe
      (princ (strcat "\n" dwg ": "
        (itoa (length master-data)) " Master | "
        (itoa cnt-sync) " sync"
        (if (> cnt-diff 0) (strcat " | " (itoa cnt-diff) " Unterschiede") "")
        (if (> cnt-missing 0) (strcat " | " (itoa cnt-missing) " fehlen") "")
        (if (> cnt-extra 0) (strcat " | " (itoa cnt-extra) " nur lokal") "")
        (if (and (= cnt-diff 0) (= cnt-missing 0) (= cnt-extra 0))
          " | OK" "")))))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; Hauptbefehl: LAYUNDO - Sync rueckgaengig machen (DCL Dialog)
;;; Laedt LayerUndo.lsp nach und ruft LXI:run-undo-dialog auf
;;; ========================================================================
(defun c:LAYUNDO ( / *error* old-cmdecho undo-path)
  (defun *error* (msg)
    (if (not (LXI:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (LXI:log-write (strcat "*** FEHLER: " msg))))
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (princ))
  (setq old-cmdecho (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (LXI:ensure-init)
  ;; LayerUndo.lsp laden (nur wenn noch nicht geladen)
  (if (not (eval 'LXI:run-undo-dialog))
    (progn
      (setq undo-path
        (cond
          ((findfile "LayerUndo.lsp"))
          ((findfile (strcat (vl-filename-directory
                      (findfile "LayerExportImport.lsp"))
                    "\\LayerUndo.lsp")))))
      (if undo-path
        (load undo-path)
        (progn
          (princ "\n*** LayerUndo.lsp nicht gefunden!")
          (princ "\n    Muss neben LayerExportImport.lsp liegen.")
          (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
          (princ)))))
  ;; Dialog ausfuehren
  (if (eval 'LXI:run-undo-dialog)
    (LXI:run-undo-dialog)
    (princ "\n*** LAYUNDO nicht verfuegbar."))
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (princ))


;;; ========================================================================
;;; AUTO-SYNC REACTOR (bei Speichern)
;;; ========================================================================

;;; Callback: Wird vor dem Speichern aufgerufen
(defun LXI:on-save-callback (reactor args / )
  (if *LXI:autosync*
    (progn
      (LXI:log-write "=== Auto-Sync (Speichern) ===")
      (princ "\n  [AutoSync] Layer synchronisieren...")
      (LXI:do-import)
      (LXI:do-export)
      (princ "\n  [AutoSync] Fertig."))))

;;; Reactor registrieren/entfernen
(defun LXI:reactor-enable ( / )
  (if (null *LXI:reactor*)
    (progn
      (setq *LXI:reactor*
        (vlr-dwg-reactor nil '((:vlr-beginSave . LXI:on-save-callback))))
      (LXI:log-write "Reactor registriert (Auto-Sync ON)")
      T)
    T))

(defun LXI:reactor-disable ( / )
  (if *LXI:reactor*
    (progn
      (vl-catch-all-apply 'vlr-remove (list *LXI:reactor*))
      (setq *LXI:reactor* nil)
      (LXI:log-write "Reactor entfernt (Auto-Sync OFF)")
      T)
    T))


;;; ========================================================================
;;; NOTIFICATION beim Zeichnungsstart
;;; Prueft ob Master neuer ist als letzter Sync
;;; ========================================================================
(defun LXI:check-on-open ( / dwg guid synclog-data last-sync master-data
                             master-modified cnt-newer)
  (if (null *LXI:notify*) nil
    (progn
      (setq dwg (LXI:dwg-name))
      ;; Read-only: Keine GUID erstellen, nur pruefen
      (setq guid (LXI:dwg-guid-read))
      (if (null guid)
        (LXI:debug-print "check-on-open: Keine GUID, ueberspringe")
        (progn
          (setq synclog-data (LXI:read-synclog))
          (setq last-sync (LXI:get-last-sync synclog-data guid dwg))
          (if (null last-sync)
            ;; GUID vorhanden aber noch nie gesynced
            (progn
              (setq master-data (LXI:read-master))
              (if master-data
                (princ (strcat "\n  [LayerSync] Noch nie synchronisiert! "
                               (itoa (length master-data)) " Layer im Master. "
                               "LAYSYNC ausfuehren."))))
            ;; Schon mal gesynced: pruefen ob Master neuer
            (progn
              (setq master-data (LXI:read-master))
              (if master-data
                (progn
                  (setq cnt-newer 0)
                  (foreach lay master-data
                    (setq master-modified (nth 23 lay))
                    (if (and master-modified
                             (LXI:master-newer-p master-modified last-sync))
                      (setq cnt-newer (1+ cnt-newer))))
                  (if (> cnt-newer 0)
                    (princ (strcat "\n  [LayerSync] " (itoa cnt-newer)
                                   " Layer seit letztem Sync geaendert. "
                                   "LAYSYNC empfohlen."))))))))))))


;;; ========================================================================
;;; Lazy-Init: Wird beim ersten Befehlsaufruf ausgefuehrt
;;; Kein VLA, kein Datei-Zugriff, kein Dialog beim Laden
;;; ========================================================================
(setq *LXI:initialized* nil)

(defun LXI:ensure-init ( / )
  (if (null *LXI:initialized*)
    (progn
      (vl-load-com)
      (LXI:read-config)
      (if (not (findfile (LXI:get-config-path)))
        (progn (LXI:ensure-directory *LXI:base-path*) (LXI:write-config)))
      (LXI:log-init)
      (if *LXI:autosync* (LXI:reactor-enable))
      (if *LXI:notify* (LXI:check-on-open))
      (setq *LXI:initialized* T)
      (LXI:debug-print "Initialisierung abgeschlossen"))))


;;; ========================================================================
;;; Initialisierung (nur Minimum beim Laden)
;;; ========================================================================
(LXI:read-config)
(princ "\nLayerExportImport.lsp v3.0.0 geladen.")
(princ "\nBefehle: LAYSYNC | LAYSYNCALL | LAYEXP | LAYIMP | LAYLOG | LAYSTATUS | LAYCFG | LAYDIFF | LAYCOUNT | LAYUNDO")
(princ)
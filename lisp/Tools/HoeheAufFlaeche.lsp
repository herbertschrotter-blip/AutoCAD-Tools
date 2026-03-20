;;; HoeheAufFlaeche.lsp
;;; Hoeheninterpolation auf einer Flaeche definiert durch 3-4 Eckpunkte
;;; Speziell fuer Leica-Vermessungsarbeiten
;;;
;;; Version: 2.0.0
;;; Datum: 2026-03-20
;;; Autor: Herbert Schrotter
;;; Namespace: HAF (HoeheAufFlaeche)
;;;
;;; AppData: %APPDATA%\AutoCAD\Lisp\HoeheAufFlaeche\
;;;   - Log:    Log\HoeheAufFlaeche_YYYYMMDD_HHMMSS.log (max 5 Sessions)
;;;   - Config: Config\HoeheAufFlaeche.cfg
;;;   - Backup: Backup\
;;;
;;; Installation:
;;; 1. Befehl APPLOAD in AutoCAD ausfuehren
;;; 2. HoeheAufFlaeche.lsp auswaehlen und laden
;;; 3. lib/BlockImport.lsp muss im selben Ordner oder Support-Pfad liegen
;;;
;;; Befehle:
;;; HoeheAufFlaeche (HAF) - Hoeheninterpolation auf Flaeche (S/Z/E Keywords)
;;; HAFSETTINGS           - Einstellungen (Skalierung, Block, Layer, Debug)
;;; HAFBLOCK              - Block-Verwaltung
;;; HAFDEBUG              - Debug ein/aus

;;; ============================================================================
;;; KONSTANTEN (Top-Level erlaubt)
;;; ============================================================================

(setq *HAF:version* "2.0.0")
(setq *HAF:appdata-folder* "HoeheAufFlaeche")
(setq *HAF:blockname* "BLK_Hoehenkote")

;;; ============================================================================
;;; GLOBALE VARIABLEN (Top-Level erlaubt)
;;; ============================================================================

(if (not (boundp '*HAF:debug-mode*))
  (setq *HAF:debug-mode* nil)
)
(setq *HAF:initialized* nil)
(setq *HAF:last-height* nil)
(setq *HAF:log-session-id* nil)

;; Settings (Defaults, werden von Config ueberschrieben)
(setq *HAF:use-layer-suffix* T)
(setq *HAF:layer-suffix* "HK")

;;; ============================================================================
;;; APPDATA & LOGGING (frueh definieren!)
;;; ============================================================================

;;; Gibt den AppData-Basisordner fuer dieses Script zurueck
;;; Erstellt alle Ebenen falls nicht vorhanden
;;; Rueckgabe: Pfad als String
(defun HAF:get-appdata-path ( / lvl1 lvl2 base)
  (setq lvl1 (strcat (getenv "APPDATA") "\\AutoCAD"))
  (if (not (vl-file-directory-p lvl1))
    (vl-mkdir lvl1)
  )
  (setq lvl2 (strcat lvl1 "\\Lisp"))
  (if (not (vl-file-directory-p lvl2))
    (vl-mkdir lvl2)
  )
  (setq base (strcat lvl2 "\\" *HAF:appdata-folder*))
  (if (not (vl-file-directory-p base))
    (vl-mkdir base)
  )
  base
)

;;; Stellt sicher dass Unterordner existieren (Log, Config, Backup)
;;; Wird einmal beim ersten Log-Write aufgerufen
(defun HAF:ensure-appdata-dirs ( / base)
  (setq base (HAF:get-appdata-path))
  (if (not (vl-file-directory-p (strcat base "\\Log")))
    (vl-mkdir (strcat base "\\Log"))
  )
  (if (not (vl-file-directory-p (strcat base "\\Config")))
    (vl-mkdir (strcat base "\\Config"))
  )
  (if (not (vl-file-directory-p (strcat base "\\Backup")))
    (vl-mkdir (strcat base "\\Backup"))
  )
)

;;; Loescht alte Logs, behaelt nur die 4 neuesten
;;; (5. ist die aktuelle Session, noch nicht erstellt)
;;; Wird beim ersten log-write der Session aufgerufen
(defun HAF:log-rotate ( / log-dir pattern files sorted-files delete-count i)
  (setq log-dir (strcat (HAF:get-appdata-path) "\\Log"))
  (setq pattern (strcat *HAF:appdata-folder* "_*.log"))
  (setq files (vl-directory-files log-dir pattern 1))
  (if files
    (progn
      (setq sorted-files (vl-sort files '<))
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

;;; Schreibt eine Zeile ins Session-Log
;;; level: "INFO", "WARN", "ERROR", "DEBUG"
;;; message: Beliebiger String
;;; Crash-safe: open-write-close pro Zeile
(defun HAF:log-write (level message / log-dir log-path fp timestamp)
  ;; Debug nur wenn aktiviert
  (if (and (= level "DEBUG") (not *HAF:debug-mode*))
    nil
    (progn
      ;; Session-Log-Pfad ermitteln (einmal pro Session)
      (if (not *HAF:log-session-id*)
        (progn
          (setq *HAF:log-session-id*
            (strcat *HAF:appdata-folder* "_"
              (menucmd "M=$(edtime,0,YYYYMMDD_HHMMSS)")))
          ;; Unterordner sicherstellen + Rotation beim ersten Schreiben
          (HAF:ensure-appdata-dirs)
          (HAF:log-rotate)
        )
      )
      (setq log-dir (strcat (HAF:get-appdata-path) "\\Log"))
      (setq log-path (strcat log-dir "\\" *HAF:log-session-id* ".log"))
      ;; Timestamp erzeugen
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

;;; Debug-Ausgabe (Log + Command-Line wenn Debug aktiv)
(defun HAF:debug (msg / )
  (HAF:log-write "DEBUG" msg)
  (if *HAF:debug-mode*
    (princ (strcat "\n  [DEBUG] " msg))
  )
)

;;; Cancel-Detection (DE + EN)
;;; Prueft ob User abgebrochen hat (ESC, Cancel, etc.)
;;; Funktioniert in deutscher UND englischer AutoCAD-Version
;;; Rueckgabe: T wenn Cancel, nil wenn echter Fehler
(defun HAF:cancel-p (msg)
  (wcmatch (strcase msg)
    "*ABBRUCH*,*ABGEBROCHEN*,*CANCEL*,*QUIT*,*EXIT*"
  )
)

;;; ============================================================================
;;; CONFIG-MANAGEMENT
;;; ============================================================================

;;; Liest Config aus %APPDATA%\AutoCAD\Lisp\HoeheAufFlaeche\Config\HoeheAufFlaeche.cfg
;;; Config-Format: KEY=VALUE pro Zeile
;;; Rueckgabe: Association-Liste ((key . value) ...) oder nil
(defun HAF:load-config ( / cfg-path fp line pos key value result)
  (setq cfg-path (strcat (HAF:get-appdata-path) "\\Config\\" *HAF:appdata-folder* ".cfg"))
  (setq result nil)
  (if (findfile cfg-path)
    (progn
      (if (vl-catch-all-error-p
            (setq fp (vl-catch-all-apply 'open (list cfg-path "r"))))
        (progn
          (HAF:log-write "ERROR" (strcat "Config lesen fehlgeschlagen: " cfg-path))
          nil
        )
        (progn
          (while (setq line (read-line fp))
            (if (setq pos (vl-string-search "=" line))
              (progn
                (setq key (substr line 1 pos))
                (setq value (substr line (+ pos 2)))
                (setq result (cons (cons key value) result))
              )
            )
          )
          (close fp)
          (HAF:log-write "INFO" (strcat "Config geladen: " cfg-path))
          result
        )
      )
    )
    (progn
      (HAF:log-write "WARN" "Keine Config gefunden, verwende Defaults")
      nil
    )
  )
)

;;; Speichert Config in %APPDATA%\AutoCAD\Lisp\HoeheAufFlaeche\Config\HoeheAufFlaeche.cfg
;;; Parameter: config-data - Association-Liste ((key . value) ...)
;;; Rueckgabe: T bei Erfolg, nil bei Fehler
(defun HAF:save-config (config-data / cfg-path fp)
  (HAF:ensure-appdata-dirs)
  (setq cfg-path (strcat (HAF:get-appdata-path) "\\Config\\" *HAF:appdata-folder* ".cfg"))
  (if (vl-catch-all-error-p
        (setq fp (vl-catch-all-apply 'open (list cfg-path "w"))))
    (progn
      (HAF:log-write "ERROR" (strcat "Config schreiben fehlgeschlagen: " cfg-path))
      nil
    )
    (progn
      (foreach pair config-data
        (write-line (strcat (car pair) "=" (cdr pair)) fp)
      )
      (close fp)
      (HAF:log-write "INFO" (strcat "Config gespeichert: " cfg-path))
      T
    )
  )
)

;;; Liest einzelnen Wert aus Config
;;; Parameter: search-key - Schluessel (String)
;;; Rueckgabe: Wert (String) oder nil
(defun HAF:get-config-value (search-key / config)
  (setq config (HAF:load-config))
  (if config
    (cdr (assoc search-key config))
    nil
  )
)

;;; Setzt einzelnen Wert in Config (laedt, aendert, speichert)
;;; Parameter: set-key - Schluessel, set-value - Wert (beides Strings)
(defun HAF:set-config-value (set-key set-value / config)
  (setq config (HAF:load-config))
  (if (null config) (setq config '()))
  ;; Existierenden Key ersetzen oder neuen hinzufuegen
  (if (assoc set-key config)
    (setq config (subst (cons set-key set-value) (assoc set-key config) config))
    (setq config (cons (cons set-key set-value) config))
  )
  (HAF:save-config config)
)

;;; Wendet Config-Werte auf globale Variablen an
;;; Wird in Lazy-Init aufgerufen
(defun HAF:apply-config ( / val)
  ;; Debug-Modus
  (setq val (HAF:get-config-value "DEBUG"))
  (if val (setq *HAF:debug-mode* (= val "1")))
  ;; HK-Layer Toggle
  (setq val (HAF:get-config-value "USE_LAYER_SUFFIX"))
  (if val (setq *HAF:use-layer-suffix* (/= val "0")))
  ;; Layer-Suffix
  (setq val (HAF:get-config-value "LAYER_SUFFIX"))
  (if (and val (/= val "")) (setq *HAF:layer-suffix* val))
  (HAF:log-write "INFO" (strcat "Config angewendet: Debug=" (if *HAF:debug-mode* "EIN" "AUS")
                                " LayerSuffix=" (if *HAF:use-layer-suffix* (strcat "aktiv (_" *HAF:layer-suffix* ")") "aus")))
)

;;; ============================================================================
;;; DWG CUSTOM PROPERTIES (Skalierung pro Zeichnung)
;;; ============================================================================

;;; Custom Property Name fuer Skalierung in DWG SummaryInfo
(setq *HAF:scale-property* "HAF_Scale")

;;; Safe-Variant-Value Pattern (GetCustomByIndex Quirk)
;;; Gibt manchmal Strings direkt, manchmal Variants zurueck
(defun HAF:safe-variant-value (val / )
  (cond
    ((= (type val) 'STR) val)
    ((= (type val) 'VLA-OBJECT) val)
    ((not (null val))
      (vl-catch-all-apply 'vlax-variant-value (list val))
    )
    (T nil)
  )
)

;;; Liest Skalierung aus DWG Custom Property
;;; Verwendet safe-variant-value Pattern
;;; Rueckgabe: Skalierung als Real oder nil
(defun HAF:read-dwg-scale ( / doc info num-props i key val scale-str)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq info (vla-get-summaryinfo doc))
  (setq num-props (vla-numcustominfo info))
  (setq scale-str nil)
  (setq i 0)
  (while (and (< i num-props) (null scale-str))
    (vla-getcustombyindex info i 'key 'val)
    (setq key (HAF:safe-variant-value key))
    (setq val (HAF:safe-variant-value val))
    (if (and key (= (strcase key) (strcase *HAF:scale-property*)))
      (setq scale-str val)
    )
    (setq i (1+ i))
  )
  (if (and scale-str (/= scale-str ""))
    (progn
      (HAF:debug (strcat "DWG-Scale gelesen: " scale-str))
      (atof scale-str)
    )
    nil
  )
)

;;; Schreibt Skalierung in DWG Custom Property
;;; Erstellt Property falls nicht vorhanden, aktualisiert falls vorhanden
(defun HAF:write-dwg-scale (scale-value / doc info num-props i key val found)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq info (vla-get-summaryinfo doc))
  (setq num-props (vla-numcustominfo info))
  (setq found nil)
  (setq i 0)
  (while (and (< i num-props) (not found))
    (vla-getcustombyindex info i 'key 'val)
    (setq key (HAF:safe-variant-value key))
    (if (and key (= (strcase key) (strcase *HAF:scale-property*)))
      (progn
        (vla-setcustombyindex info i *HAF:scale-property* (rtos scale-value 2 6))
        (setq found T)
      )
    )
    (setq i (1+ i))
  )
  (if (not found)
    (vla-addcustominfo info *HAF:scale-property* (rtos scale-value 2 6))
  )
  (HAF:debug (strcat "DWG-Scale geschrieben: " (rtos scale-value 2 6)))
  (HAF:log-write "INFO" (strcat "DWG Custom Property: " *HAF:scale-property* "=" (rtos scale-value 2 6)))
  T
)

;;; Liest Skalierung: Erst DWG, dann Config-Default, dann 1.0
;;; Rueckgabe: Skalierung als Real (immer ein Wert, nie nil)
(defun HAF:read-scale ( / dwg-scale cfg-val)
  ;; 1. Aus DWG Custom Property
  (setq dwg-scale (HAF:read-dwg-scale))
  (if (and dwg-scale (> dwg-scale 0.0))
    (progn
      (HAF:debug (strcat "Scale aus DWG: " (rtos dwg-scale 2 2)))
      dwg-scale
    )
    ;; 2. Fallback: Config-Default
    (progn
      (setq cfg-val (HAF:get-config-value "DEFAULT_SCALE"))
      (if (and cfg-val (/= cfg-val ""))
        (progn
          (HAF:debug (strcat "Scale aus Config-Default: " cfg-val))
          (atof cfg-val)
        )
        ;; 3. Fallback: 1.0
        (progn
          (HAF:debug "Scale: kein Wert gefunden, verwende 1.0")
          1.0
        )
      )
    )
  )
)

;;; Speichert Skalierung in DWG Custom Property
(defun HAF:save-scale (scale-value / )
  (HAF:write-dwg-scale scale-value)
)

;;; Speichert Default-Skalierung in Config (fuer neue Zeichnungen)
(defun HAF:save-default-scale (scale-value / )
  (HAF:set-config-value "DEFAULT_SCALE" (rtos scale-value 2 6))
  (HAF:log-write "INFO" (strcat "Default-Scale in Config: " (rtos scale-value 2 2)))
)

;;; Fragt Benutzer nach XY-Skalierung und speichert in DWG
(defun HAF:get-scale ( / scaleValue prompt current-scale)
  (setq current-scale (HAF:read-scale))
  (setq prompt (strcat "\nNeue XY-Skalierung"
                       (if current-scale
                         (strcat " <" (rtos current-scale 2 2) ">")
                         " <1.0>")
                       ": "))
  (setq scaleValue (getreal prompt))
  (if (null scaleValue)
    (if current-scale
      (setq scaleValue current-scale)
      (setq scaleValue 1.0)
    )
  )
  (if (<= scaleValue 0.0)
    (progn
      (princ "\n*** Skalierung muss groesser als 0 sein! Verwende 1.0 ***")
      (HAF:log-write "WARN" (strcat "Ungueltige Skalierung: " (rtos scaleValue 2 4) " -> 1.0"))
      (setq scaleValue 1.0)
    )
  )
  (HAF:save-scale scaleValue)
  (HAF:log-write "INFO" (strcat "Skalierung gesetzt: " (rtos scaleValue 2 2) " (in DWG)"))
  (princ (strcat "\nSkalierung gespeichert: " (rtos scaleValue 2 2) " (in DWG)"))
  scaleValue
)

;;; ============================================================================
;;; BIBLIOTHEK LADEN (in Lazy-Init, NICHT auf Top-Level!)
;;; ============================================================================

;;; Laedt BlockImport.lsp mit 3-Fallback Pfadaufloesung + File-Dialog
;;; 1. Gespeicherter Pfad aus Config (BLOCKIMPORT_PATH)
;;; 2. findfile (Support-Pfade: lib/BlockImport.lsp, BlockImport.lsp)
;;; 3. File-Dialog als letzter Fallback
;;; Rueckgabe: T bei Erfolg, nil bei Fehler
(defun HAF:load-library ( / path)
  (HAF:log-write "INFO" "BlockImport.lsp wird gesucht...")
  
  ;; Fallback 1: Gespeicherter Pfad aus Config
  (setq path (HAF:get-config-value "BLOCKIMPORT_PATH"))
  (if (and path (not (findfile path)))
    (progn
      (HAF:log-write "WARN" (strcat "Config-Pfad ungueltig: " path))
      (setq path nil)
    )
  )
  
  ;; Fallback 2: findfile (AutoCAD Support-Pfade)
  (if (null path)
    (setq path
      (cond
        ((findfile "lib/BlockImport.lsp"))
        ((findfile "BlockImport.lsp"))
      )
    )
  )
  
  ;; Fallback 3: File-Dialog
  (if (null path)
    (progn
      (HAF:log-write "WARN" "BlockImport.lsp nicht automatisch gefunden")
      (princ "\n*** BlockImport.lsp wird nicht im Support-Pfad gefunden ***")
      (princ "\nBitte waehlen Sie die Datei lib/BlockImport.lsp aus...")
      (setq path
        (getfiled "BlockImport.lsp auswaehlen"
                  (cond ((getvar "DWGPREFIX")) ((getenv "USERPROFILE")) (T ""))
                  "lsp" 0))
      (if (null path)
        (progn
          (HAF:log-write "ERROR" "BlockImport.lsp: User hat Auswahl abgebrochen")
          (alert "FEHLER: Keine Datei ausgewaehlt!")
          (exit)
        )
      )
    )
  )
  
  ;; Laden und Pfad speichern
  (if path
    (progn
      (load path)
      (HAF:set-config-value "BLOCKIMPORT_PATH" path)
      (HAF:log-write "INFO" (strcat "Library geladen: " path))
      T
    )
    (progn
      (HAF:log-write "ERROR" "BlockImport.lsp konnte nicht geladen werden!")
      (alert "FEHLER: BlockImport.lsp nicht gefunden!\nHAF kann ohne BlockImport.lsp nicht arbeiten.")
      nil
    )
  )
)

;;; ============================================================================
;;; LAZY-INIT (CRITICAL bei DokaCAD!)
;;; ============================================================================

;;; Initialisierung beim ersten Befehlsaufruf
;;; Laedt VLA, Config, BlockImport.lsp
;;; Wird nur 1x ausgefuehrt, erste Zeile in jedem c:Befehl
(defun HAF:ensure-init ( / )
  (if (not *HAF:initialized*)
    (progn
      (HAF:log-write "INFO" "Lazy-Init gestartet...")
      
      ;; VLA laden (NICHT auf Top-Level wegen DokaCAD!)
      (vl-load-com)
      (HAF:log-write "INFO" "vl-load-com geladen")
      
      ;; Config anwenden (Debug, Layer-Suffix, etc.)
      (HAF:apply-config)
      
      ;; BlockImport.lsp laden
      (if (not (HAF:load-library))
        (progn
          (HAF:log-write "ERROR" "Lazy-Init FEHLGESCHLAGEN: BlockImport.lsp nicht geladen")
          ;; NICHT *HAF:initialized* setzen → naechster Versuch moeglich
        )
        (progn
          ;; Fertig
          (setq *HAF:initialized* T)
          (HAF:log-write "INFO" (strcat "=== HoeheAufFlaeche v" *HAF:version* " initialisiert ==="))
        )
      )
    )
  )
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - FORMATIERUNG
;;; ============================================================================

;;; Formatiert Hoehenwert fuer Anzeige (2 Dezimalstellen)
(defun HAF:format-height (heightValue)
  (rtos heightValue 2 2)
)

;;; Konvertiert Hoehe in String mit exakt 3 Dezimalstellen
(defun HAF:ensure-three-decimals (heightValue / heightStr decimalPos decimals)
  (setq heightStr (rtos heightValue 2 3))
  (if (not (vl-string-search "." heightStr))
    (setq heightStr (strcat heightStr ".000"))
    (progn
      (setq decimalPos (vl-string-search "." heightStr))
      (setq decimals (substr heightStr (+ decimalPos 2)))
      (while (< (strlen decimals) 3)
        (setq decimals (strcat decimals "0"))
      )
      (setq heightStr (strcat (substr heightStr 1 (+ decimalPos 1)) decimals))
    )
  )
  heightStr
)

;;; Formatiert Hoehenwert mit Vorzeichen (+ oder %%p fuer +/-0)
(defun HAF:format-height-value (heightValue / formattedHeight)
  (setq formattedHeight (rtos heightValue 2 2))
  (cond
    ((= heightValue 0.0) (setq formattedHeight (strcat "%%p" formattedHeight)))
    ((> heightValue 0.0) (setq formattedHeight (strcat "+" formattedHeight)))
  )
  formattedHeight
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - VALIDIERUNG & EINGABE
;;; ============================================================================

;;; Validiert ob Punkt gueltig ist (3D-Liste mit Zahlen)
(defun HAF:valid-point-p (pt)
  (and pt (listp pt) (= (length pt) 3)
       (numberp (car pt)) (numberp (cadr pt)) (numberp (caddr pt)))
)

;;; Validiert ob Hoehenwert gueltig ist
(defun HAF:valid-height-p (height)
  (and height (numberp height))
)

;;; Holt Hoehenwert mit Validierung und Default
;;; Parameter: prompt - Prompt-Text, default - Default-Wert oder nil
;;; Rueckgabe: Hoehe als Real oder nil
(defun HAF:get-validated-height (prompt default / height)
  (if default
    (setq prompt (strcat prompt " <" (HAF:format-height default) ">: "))
    (setq prompt (strcat prompt ": "))
  )
  (setq height (getreal prompt))
  (HAF:debug (strcat "get-validated-height: height=" (if height (rtos height 2 4) "nil")
                     " default=" (if default (rtos default 2 4) "nil")))
  (if (null height)
    (if default
      (progn
        (setq height default)
        (HAF:debug (strcat "  Verwende Default: " (rtos height 2 4)))
      )
      (progn
        (while (null height)
          (princ "\n*** Bitte geben Sie eine Hoehe ein ***")
          (setq height (getreal (strcat prompt ": ")))
        )
      )
    )
  )
  (if (HAF:valid-height-p height) height nil)
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - BLOCK-PRUEFUNG
;;; ============================================================================

;;; Prueft ob Block bereits nahe dieser Position+Hoehe existiert
;;; WICHTIG: Transformiert BKS->WKS fuer korrekten Vergleich!
;;;
;;; Parameter:
;;;   pt - Punkt (Liste x y z) in BKS-Koordinaten
;;;   height - Hoehe (Zahl)
;;;   blockname - Block-Name (String)
;;;
;;; Toleranzen:
;;;   XY-Ebene: 0.05 Einheiten (5cm)
;;;   Z-Hoehe: 0.001 Einheiten (1mm)
;;;
;;; Rueckgabe: T wenn Block existiert, nil sonst
(defun HAF:block-exists-at-position (pt height blockname / ss i ent inspt pt-wcs tolerance-xy tolerance-z dist-xy dist-z found)
  (setq tolerance-xy 0.05)
  (setq tolerance-z 0.001)
  (setq found nil)
  ;; KRITISCH: getpoint gibt BKS, Block-Einfuegepunkte (DXF 10) sind WKS
  (setq pt-wcs (trans pt 1 0))
  (HAF:debug (strcat "block-exists-at-position: " blockname
                     " pt(BKS)=(" (rtos (car pt) 2 4) " " (rtos (cadr pt) 2 4) ")"
                     " pt(WKS)=(" (rtos (car pt-wcs) 2 4) " " (rtos (cadr pt-wcs) 2 4) ")"
                     " h=" (rtos height 2 4)))
  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 blockname))))
  (if ss
    (progn
      (HAF:debug (strcat "  Gefundene Bloecke: " (itoa (sslength ss))))
      (setq i 0)
      (while (and (< i (sslength ss)) (not found))
        (setq ent (ssname ss i))
        (setq inspt (cdr (assoc 10 (entget ent))))
        (setq dist-xy (distance (list (car pt-wcs) (cadr pt-wcs))
                                (list (car inspt) (cadr inspt))))
        (setq dist-z (abs (- height (caddr inspt))))
        (if (and (< dist-xy tolerance-xy) (< dist-z tolerance-z))
          (progn
            (HAF:debug (strcat "  >>> MATCH bei Block[" (itoa i) "] dist-xy=" (rtos dist-xy 2 4) " dist-z=" (rtos dist-z 2 4)))
            (setq found T)
          )
        )
        (setq i (1+ i))
      )
      (setq ss nil) ;; Selection Set freigeben
      (if (not found) (HAF:debug "  Kein Match gefunden"))
      found
    )
    (progn
      (HAF:debug "  Keine Bloecke mit diesem Namen in Zeichnung")
      nil
    )
  )
)

;;; ============================================================================
;;; HK-LAYER MANAGEMENT
;;; ============================================================================

;;; Erstellt Layer mit konfiguriertem Suffix basierend auf aktuellem Layer
;;; Kopiert via VLA: Farbe (ACI+TrueColor), Linientyp, Linienstaerke, Plot, Transparenz
;;; Wenn aktueller Layer schon auf _<suffix> endet → direkt verwenden
;;; Rueckgabe: Name des Ziel-Layers (String) oder nil bei Fehler
(defun HAF:ensure-hk-layer ( / cur-layer hk-layer-name suffix-with-sep suffix-len
                                doc layers src-layer new-layer color-obj transp-val)
  (setq cur-layer (getvar "CLAYER"))
  (setq suffix-with-sep (strcat "_" *HAF:layer-suffix*))
  (setq suffix-len (strlen suffix-with-sep))
  ;; Pruefen ob aktueller Layer schon auf _<suffix> endet
  (if (and (>= (strlen cur-layer) suffix-len)
           (= (strcase (substr cur-layer (- (strlen cur-layer) suffix-len -1)))
              (strcase suffix-with-sep)))
    (progn
      (HAF:debug (strcat "Layer endet auf " suffix-with-sep ", verwende direkt: " cur-layer))
      cur-layer
    )
    (progn
      (setq hk-layer-name (strcat cur-layer suffix-with-sep))
      (HAF:debug (strcat "Layer: " cur-layer " -> " hk-layer-name))
      (if (tblsearch "LAYER" hk-layer-name)
        (progn
          (HAF:debug (strcat "Layer existiert bereits: " hk-layer-name))
          hk-layer-name
        )
        (progn
          (setq doc (vla-get-activedocument (vlax-get-acad-object)))
          (setq layers (vla-get-layers doc))
          (setq src-layer (vla-item layers cur-layer))
          (setq new-layer
            (vl-catch-all-apply 'vla-add (list layers hk-layer-name)))
          (if (vl-catch-all-error-p new-layer)
            (progn
              (HAF:log-write "ERROR"
                (strcat "Layer erstellen fehlgeschlagen: " hk-layer-name
                        " - " (vl-catch-all-error-message new-layer)))
              nil
            )
            (progn
              ;; Properties vom Quell-Layer kopieren
              (vl-catch-all-apply 'vla-put-color
                (list new-layer (vla-get-color src-layer)))
              (setq color-obj
                (vl-catch-all-apply 'vla-get-truecolor (list src-layer)))
              (if (and color-obj (not (vl-catch-all-error-p color-obj)))
                (vl-catch-all-apply 'vla-put-truecolor (list new-layer color-obj))
              )
              (vl-catch-all-apply 'vla-put-linetype
                (list new-layer (vla-get-linetype src-layer)))
              (vl-catch-all-apply 'vla-put-lineweight
                (list new-layer (vla-get-lineweight src-layer)))
              (vl-catch-all-apply 'vla-put-plottable
                (list new-layer (vla-get-plottable src-layer)))
              (setq transp-val
                (vl-catch-all-apply 'vla-get-transparency (list src-layer)))
              (if (and transp-val (not (vl-catch-all-error-p transp-val)))
                (vl-catch-all-apply 'vla-put-transparency (list new-layer transp-val))
              )
              (HAF:log-write "INFO"
                (strcat "Layer erstellt: " hk-layer-name " (kopiert von " cur-layer ")"))
              hk-layer-name
            )
          )
        )
      )
    )
  )
)

;;; ============================================================================
;;; BLOCK EINFUEGEN
;;; ============================================================================

;;; Fuegt Hoehenkoten-Block an gegebenem Punkt mit Hoehe und Skalierung ein
;;; Verwendet BLI:resolve-blockname fuer Context-basierte Block-Aufloesung
;;; Setzt HOEHE-Attribut (2 Dez + Vorzeichen) und 3DEZ-Attribut (3. Dezimalstelle)
;;; Verschiebt Block auf Z-Hoehe, weist HK-Layer zu wenn aktiviert
;;;
;;; Parameter:
;;;   einfuegepunkt - XYZ Punkt (Liste)
;;;   hoehe - Hoehenwert (Zahl)
;;;   scale - XY-Skalierung (Zahl)
;;;   skip-if-exists - T = Nicht einfuegen wenn Block schon da (Eckpunkte)
;;;                    nil = Immer einfuegen (gesuchte Punkte)
;;;
;;; Rueckgabe:
;;;   T bei Erfolg
;;;   nil bei Fehler oder wenn Block existiert (bei skip-if-exists)
(defun HAF:insert-block (einfuegepunkt hoehe scale skip-if-exists
                         / blockName heightStr intPart decPart height2DecStr
                           old-attdia block-available importEnt ent attribs
                           insertionPoint hk-layer ent-data)
  ;; Blockname aus BlockImport (DWG Property → Globaler Standard)
  (setq *block-import-context* "HAF")
  (setq blockName (BLI:resolve-blockname "HAF"))
  ;; Wenn kein Block konfiguriert: Block-Manager automatisch oeffnen
  (if (null blockName)
    (progn
      (HAF:log-write "WARN" "Kein Block konfiguriert - oeffne Block-Verwaltung")
      (princ "\n*** Kein Block konfiguriert! Block-Verwaltung wird geoeffnet... ***")
      (manage-block-import "HAF")
      ;; Nochmal versuchen
      (setq blockName (BLI:resolve-blockname "HAF"))
    )
  )
  
  (HAF:debug (strcat "insert-block: pt=(" (rtos (car einfuegepunkt) 2 4) " "
                     (rtos (cadr einfuegepunkt) 2 4) " " (rtos (caddr einfuegepunkt) 2 4) ")"
                     " h=" (rtos hoehe 2 4) " s=" (rtos scale 2 4)
                     " skip=" (if skip-if-exists "T" "nil")))
  
  (if (and (HAF:valid-point-p einfuegepunkt) (HAF:valid-height-p hoehe) scale)
    (progn
      ;; Duplikat-Pruefung (nur bei Eckpunkten)
      (if (and skip-if-exists (HAF:block-exists-at-position einfuegepunkt hoehe blockName))
        (progn
          (HAF:debug "Block existiert bereits - UEBERSPRUNGEN")
          (princ (strcat "\n  Block existiert bereits: " (HAF:format-height-value hoehe)
                         " | Z=" (rtos hoehe 2 3)))
          nil
        )
        (progn
          ;; Block verfuegbar machen
          (setq block-available (ensure-block-available blockName))
          (HAF:debug (strcat "ensure-block-available: " (if (car block-available) "OK" "FEHLER")))
          
          (if (car block-available)
            (progn
              (setq importEnt (cadr block-available))
              
              ;; Hoehe als String mit genau 3 Dezimalstellen
              (setq heightStr (HAF:ensure-three-decimals hoehe))
              
              ;; Aufteilen in Ganzzahl- und Dezimalteil
              (setq intPart (substr heightStr 1 (vl-string-search "." heightStr)))
              (setq decPart (substr heightStr (+ (strlen intPart) 2)))
              
              ;; Dezimalteil auf 3 Stellen sicherstellen
              (while (< (strlen decPart) 3)
                (setq decPart (strcat decPart "0"))
              )
              
              ;; HOEHE Attribut: 2 Dezimalstellen + Vorzeichen
              (setq height2DecStr (strcat intPart "." (substr decPart 1 2)))
              (setq height2DecStr (cond
                                    ((= hoehe 0.0) (strcat "%%p" height2DecStr))
                                    ((> hoehe 0.0) (strcat "+" height2DecStr))
                                    (T height2DecStr)))
              
              (HAF:debug (strcat "heightStr=" heightStr " height2DecStr=" height2DecStr
                                 " 3DEZ=" (substr decPart 3 1)))
              
              ;; HK-Layer VOR dem Einfuegen erstellen (VLA darf nicht waehrend command laufen)
              (if *HAF:use-layer-suffix*
                (setq hk-layer (HAF:ensure-hk-layer))
              )
              
              ;; Block einfuegen
              (setq old-attdia (getvar "ATTDIA"))
              (setvar "ATTDIA" 0)
              (command "_-insert" blockName einfuegepunkt scale scale "")
              (while (> (getvar "CMDACTIVE") 0) (command ""))
              (setq ent (entlast))
              (setvar "ATTDIA" old-attdia)
              
              ;; Attribute setzen (HOEHE + 3DEZ)
              (if (and ent (eq (cdr (assoc 0 (entget ent))) "INSERT"))
                (progn
                  (HAF:debug "Block INSERT gefunden - setze Attribute")
                  (setq attribs (entnext ent))
                  (while (and attribs (eq (cdr (assoc 0 (entget attribs))) "ATTRIB"))
                    (cond
                      ((eq (cdr (assoc 2 (entget attribs))) "HOEHE")
                        (HAF:debug (strcat "  HOEHE -> " height2DecStr))
                        (entmod (subst (cons 1 height2DecStr) (assoc 1 (entget attribs)) (entget attribs)))
                      )
                      ((eq (cdr (assoc 2 (entget attribs))) "3DEZ")
                        (if (not (= (substr decPart 3 1) "0"))
                          (progn
                            (HAF:debug (strcat "  3DEZ -> " (substr decPart 3 1)))
                            (entmod (subst (cons 1 (substr decPart 3 1)) (assoc 1 (entget attribs)) (entget attribs)))
                          )
                        )
                      )
                    )
                    (setq attribs (entnext attribs))
                  )
                )
                (HAF:debug "*** entlast ist KEIN INSERT! Block-Einfuegung moeglicherweise fehlgeschlagen!")
              )
              
              ;; Block auf Hoehe verschieben
              (setq insertionPoint (cdr (assoc 10 (entget ent))))
              (command "_move" ent "" "_non" insertionPoint "_non"
                       (list (car insertionPoint) (cadr insertionPoint) hoehe))
              
              ;; HK-Layer zuweisen
              (if (and *HAF:use-layer-suffix* hk-layer)
                (progn
                  (setq ent-data (entget ent))
                  (entmod (subst (cons 8 hk-layer) (assoc 8 ent-data) ent-data))
                  (HAF:debug (strcat "Block auf Layer: " hk-layer))
                )
              )
              
              ;; Import-Block entfernen
              (if importEnt (entdel importEnt))
              
              (HAF:log-write "INFO" (strcat "Block gesetzt: " height2DecStr
                                            " Z=" (rtos hoehe 2 3)
                                            " Scale=" (rtos scale 2 2)
                                            (if (and *HAF:use-layer-suffix* hk-layer)
                                              (strcat " Layer=" hk-layer) "")))
              (princ (strcat "\n  Hoehenkote: " height2DecStr
                            " | Z=" (rtos hoehe 2 3)
                            " | Scale=" (rtos scale 2 2)
                            (if (and *HAF:use-layer-suffix* hk-layer)
                              (strcat " | Layer=" hk-layer) "")))
              T
            )
            (progn
              (HAF:log-write "ERROR" "ensure-block-available fehlgeschlagen")
              (princ "\n*** FEHLER: Block konnte nicht geladen werden ***")
              nil
            )
          )
        )
      )
    )
    (progn
      (HAF:debug "*** Parameter-Pruefung FEHLGESCHLAGEN!")
      (princ "\n*** Fehler: Ungueltige Parameter ***")
      nil
    )
  )
)

;;; ============================================================================
;;; MATHEMATIK - EBENENGLEICHUNG (3 Punkte)
;;; ============================================================================

;;; Berechnet Hoehe auf einer Ebene definiert durch 3 Punkte
;;; Verwendet Ebenengleichung: ax + by + cz = d
;;;
;;; Parameter:
;;;   pts - Liste von 3 Punkten ((x y z) (x y z) (x y z))
;;;   heights - Liste von 3 Hoehen (h1 h2 h3)
;;;   pg - Gesuchter Punkt (x y z)
;;;
;;; Rueckgabe: Liste (hoehe methoden-info) oder nil bei Fehler
(defun HAF:interpolate-plane (pts heights pg
                              / p1 p2 p3 h1 h2 h3 v1 v2 normal a b c d z)
  (setq p1 (nth 0 pts) p2 (nth 1 pts) p3 (nth 2 pts))
  (setq h1 (nth 0 heights) h2 (nth 1 heights) h3 (nth 2 heights))
  ;; Zwei Vektoren in der Ebene
  (setq v1 (list (- (car p2) (car p1)) (- (cadr p2) (cadr p1)) (- h2 h1)))
  (setq v2 (list (- (car p3) (car p1)) (- (cadr p3) (cadr p1)) (- h3 h1)))
  ;; Normalenvektor (Kreuzprodukt)
  (setq normal (list
    (- (* (cadr v1) (caddr v2)) (* (caddr v1) (cadr v2)))
    (- (* (caddr v1) (car v2)) (* (car v1) (caddr v2)))
    (- (* (car v1) (cadr v2)) (* (cadr v1) (car v2)))))
  (setq a (car normal) b (cadr normal) c (caddr normal))
  (if (equal c 0.0 0.0001)
    (progn
      (HAF:log-write "ERROR" "interpolate-plane: Punkte sind kollinear oder Ebene vertikal")
      nil
    )
    (progn
      (setq d (+ (* a (car p1)) (* b (cadr p1)) (* c h1)))
      (setq z (/ (- d (* a (car pg)) (* b (cadr pg))) c))
      (HAF:debug (strcat "interpolate-plane: z=" (rtos z 2 4)))
      (list z "Ebene 1-2-3")
    )
  )
)

;;; ============================================================================
;;; MATHEMATIK - BARYZENTRISCHE KOORDINATEN
;;; ============================================================================

;;; Berechnet baryzentrische Koordinaten fuer Punkt in Dreieck
;;; Rueckgabe: Liste (u v w) — u+v+w=1.0
;;; u gehoert zu p1, w zu p2, v zu p3 (wegen Vektordefinition)
(defun HAF:barycentric (p1 p2 p3 pg
                        / v0 v1 v2 dot00 dot01 dot02 dot11 dot12 inv-denom u v w)
  (setq v0 (list (- (car p3) (car p1)) (- (cadr p3) (cadr p1))))
  (setq v1 (list (- (car p2) (car p1)) (- (cadr p2) (cadr p1))))
  (setq v2 (list (- (car pg) (car p1)) (- (cadr pg) (cadr p1))))
  (setq dot00 (+ (* (car v0) (car v0)) (* (cadr v0) (cadr v0))))
  (setq dot01 (+ (* (car v0) (car v1)) (* (cadr v0) (cadr v1))))
  (setq dot02 (+ (* (car v0) (car v2)) (* (cadr v0) (cadr v2))))
  (setq dot11 (+ (* (car v1) (car v1)) (* (cadr v1) (cadr v1))))
  (setq dot12 (+ (* (car v1) (car v2)) (* (cadr v1) (cadr v2))))
  (setq inv-denom (/ 1.0 (- (* dot00 dot11) (* dot01 dot01))))
  (setq v (* (- (* dot11 dot02) (* dot01 dot12)) inv-denom))
  (setq w (* (- (* dot00 dot12) (* dot01 dot02)) inv-denom))
  (setq u (- 1.0 v w))
  (list u v w)
)

;;; Testet ob Punkt in Dreieck liegt
;;; Parameter: bary - baryzentrische Koordinaten (u v w)
;;; Rueckgabe: T wenn innerhalb, nil wenn ausserhalb
(defun HAF:point-in-triangle-p (bary)
  (and (>= (car bary) 0.0) (>= (cadr bary) 0.0) (>= (caddr bary) 0.0))
)

;;; Berechnet Hoehe in Dreieck mit baryzentrischen Koordinaten
;;; u->p1/h1, w->p2/h2, v->p3/h3 (wegen Vektordefinition)
(defun HAF:height-in-triangle (p1 h1 p2 h2 p3 h3 pg / bary u v w)
  (setq bary (HAF:barycentric p1 p2 p3 pg))
  (if bary
    (progn
      (setq u (car bary) v (cadr bary) w (caddr bary))
      (+ (* u h1) (* w h2) (* v h3))
    )
    nil
  )
)

;;; ============================================================================
;;; MATHEMATIK - TERRAIN-KLASSIFIKATION (4 Punkte)
;;; ============================================================================

;;; Klassifiziert Viereck nach Hoehenverteilung
;;; Bestimmt ob Mulde, Kuppe, Sattel oder flach
;;;
;;; Rueckgabe: (typ [index])
;;;   ("flat")            - alle Hoehen gleich
;;;   ("mulde" index)     - genau ein Minimum an Punkt index (1-4)
;;;   ("kuppe" index)     - genau ein Maximum an Punkt index (1-4)
;;;   ("sattel")          - gegenueberliegende Paare gleich
;;;   ("ambiguous")       - keine eindeutige Klassifikation
(defun HAF:classify-quad (h1 h2 h3 h4
                          / eps all-heights minv maxv mincount maxcount
                            min-idx max-idx i)
  (setq eps 0.01)
  (setq all-heights (list h1 h2 h3 h4))
  (setq minv (apply 'min all-heights))
  (setq maxv (apply 'max all-heights))
  ;; Zaehle Vorkommen von min/max
  (setq mincount 0 maxcount 0 min-idx 0 max-idx 0 i 0)
  (foreach val all-heights
    (setq i (1+ i))
    (if (< (abs (- val minv)) eps) (progn (setq mincount (1+ mincount)) (setq min-idx i)))
    (if (< (abs (- val maxv)) eps) (progn (setq maxcount (1+ maxcount)) (setq max-idx i)))
  )
  (HAF:debug (strcat "classify-quad: h=(" (rtos h1 2 2) " " (rtos h2 2 2) " "
                     (rtos h3 2 2) " " (rtos h4 2 2) ") min=" (rtos minv 2 2)
                     " max=" (rtos maxv 2 2) " mincount=" (itoa mincount)
                     " maxcount=" (itoa maxcount)))
  (cond
    ;; Alle gleich → FLACH
    ((and (< (abs (- h1 h2)) eps) (< (abs (- h1 h3)) eps) (< (abs (- h1 h4)) eps))
     (HAF:debug "  -> flat")
     (list "flat"))
    ;; Genau EIN Minimum → MULDE
    ((= mincount 1)
     (HAF:debug (strcat "  -> mulde an Punkt " (itoa min-idx)))
     (list "mulde" min-idx))
    ;; Genau EIN Maximum → KUPPE
    ((= maxcount 1)
     (HAF:debug (strcat "  -> kuppe an Punkt " (itoa max-idx)))
     (list "kuppe" max-idx))
    ;; Gegenueberliegende Paare gleich → SATTEL
    ((and (< (abs (- h1 h3)) eps) (< (abs (- h2 h4)) eps) (>= (abs (- h1 h2)) eps))
     (HAF:debug "  -> sattel")
     (list "sattel"))
    ;; Unklar
    (T
     (HAF:debug "  -> ambiguous")
     (list "ambiguous"))
  )
)

;;; Bestimmt welche Diagonale verwendet werden soll
;;; Verwendet hydrologische Klassifikation
;;;
;;; Rueckgabe: "13" (p1-p3) oder "24" (p2-p4) oder "USER" (Sattel)
(defun HAF:determine-diagonal (h1 h2 h3 h4
                               / classification class-type class-idx diff-13 diff-24)
  (setq classification (HAF:classify-quad h1 h2 h3 h4))
  (setq class-type (car classification))
  (setq class-idx (cadr classification))
  (cond
    ;; FLACH → egal
    ((= class-type "flat")
     (HAF:log-write "INFO" "Diagonale: flat -> 13")
     (princ "\n  Flaeche eben - verwende Diagonale 1-3")
     "13")
    ;; MULDE → Diagonale DURCH den tiefsten Punkt
    ((= class-type "mulde")
     (HAF:log-write "INFO" (strcat "Diagonale: mulde Punkt " (itoa class-idx)))
     (princ (strcat "\n  Mulde an Punkt " (itoa class-idx)))
     (if (or (= class-idx 1) (= class-idx 3)) "13" "24"))
    ;; KUPPE → Diagonale DURCH den hoechsten Punkt
    ((= class-type "kuppe")
     (HAF:log-write "INFO" (strcat "Diagonale: kuppe Punkt " (itoa class-idx)))
     (princ (strcat "\n  Kuppe an Punkt " (itoa class-idx)))
     (if (or (= class-idx 1) (= class-idx 3)) "13" "24"))
    ;; SATTEL → User muss entscheiden (Bruchlinie)
    ((= class-type "sattel")
     (HAF:log-write "INFO" "Diagonale: sattel -> USER")
     (princ "\n  Sattelflaeche erkannt - bitte Bruchlinie definieren")
     "USER")
    ;; UNKLAR → kleinere Hoehendifferenz
    ((= class-type "ambiguous")
     (setq diff-13 (abs (- h1 h3)))
     (setq diff-24 (abs (- h2 h4)))
     (if (< diff-13 diff-24)
       (progn
         (HAF:log-write "INFO" "Diagonale: ambiguous -> 13 (kleinere Diff)")
         (princ "\n  Unklare Geometrie - waehle Diagonale 1-3")
         "13")
       (progn
         (HAF:log-write "INFO" "Diagonale: ambiguous -> 24 (kleinere Diff)")
         (princ "\n  Unklare Geometrie - waehle Diagonale 2-4")
         "24")
     ))
    ;; Fallback
    (T
     (HAF:log-write "WARN" "Diagonale: Fallback -> 13")
     "13")
  )
)

;;; ============================================================================
;;; INTERPOLATION - TRIANGULATION (4 Punkte)
;;; ============================================================================

;;; Interpoliert Hoehe in Viereck mittels Triangulation
;;; Teilt Viereck in 2 Dreiecke je nach Diagonale
;;;
;;; Parameter:
;;;   pts - Liste von 4 Punkten
;;;   heights - Liste von 4 Hoehen
;;;   pg - Gesuchter Punkt
;;;   diagonal - "13" oder "24"
;;;
;;; Rueckgabe: Liste (hoehe methoden-info) oder nil
(defun HAF:interpolate-triangulation (pts heights pg diagonal
                                      / p1 p2 p3 p4 h1 h2 h3 h4
                                        bary inside height tri-info)
  (setq p1 (nth 0 pts) p2 (nth 1 pts) p3 (nth 2 pts) p4 (nth 3 pts))
  (setq h1 (nth 0 heights) h2 (nth 1 heights) h3 (nth 2 heights) h4 (nth 3 heights))
  (if (= diagonal "13")
    ;; Diagonale 1-3: Dreiecke 1-2-3 und 1-3-4
    (progn
      (setq bary (HAF:barycentric p1 p2 p3 pg))
      (setq inside (HAF:point-in-triangle-p bary))
      (if inside
        (progn
          (setq height (HAF:height-in-triangle p1 h1 p2 h2 p3 h3 pg))
          (setq tri-info "Dreieck 1-2-3"))
        (progn
          (setq height (HAF:height-in-triangle p1 h1 p3 h3 p4 h4 pg))
          (setq tri-info "Dreieck 1-3-4"))
      )
    )
    ;; Diagonale 2-4: Dreiecke 1-2-4 und 2-3-4
    (progn
      (setq bary (HAF:barycentric p1 p2 p4 pg))
      (setq inside (HAF:point-in-triangle-p bary))
      (if inside
        (progn
          (setq height (HAF:height-in-triangle p1 h1 p2 h2 p4 h4 pg))
          (setq tri-info "Dreieck 1-2-4"))
        (progn
          (setq height (HAF:height-in-triangle p2 h2 p3 h3 p4 h4 pg))
          (setq tri-info "Dreieck 2-3-4"))
      )
    )
  )
  (if height
    (progn
      (HAF:debug (strcat "interpolate-triangulation: " tri-info " h=" (rtos height 2 4)))
      (list height tri-info)
    )
    nil
  )
)

;;; ============================================================================
;;; DISPATCHER - Waehlt Interpolationsmethode
;;; ============================================================================

;;; Zentrale Interpolationsfunktion
;;; Waehlt automatisch: 3 Punkte → Ebene, 4 Punkte → Triangulation
;;;
;;; Parameter:
;;;   pts - Liste von 3 oder 4 Punkten
;;;   heights - Liste von 3 oder 4 Hoehen
;;;   pg - Gesuchter Punkt
;;;   diagonal - "13" oder "24" (nur bei 4 Punkten, sonst nil)
;;;
;;; Rueckgabe: Liste (hoehe methoden-info) oder nil
(defun HAF:interpolate (pts heights pg diagonal / num-pts)
  (setq num-pts (length pts))
  (HAF:debug (strcat "HAF:interpolate: " (itoa num-pts) " Punkte"
                     (if diagonal (strcat " diag=" diagonal) "")))
  (cond
    ((= num-pts 3)
     (HAF:interpolate-plane pts heights pg))
    ((= num-pts 4)
     (HAF:interpolate-triangulation pts heights pg diagonal))
    (T
     (HAF:log-write "ERROR" (strcat "interpolate: ungueltige Punktzahl " (itoa num-pts)))
     nil)
  )
)

;;; ============================================================================
;;; HOEHENLINIEN - Berechnung
;;; ============================================================================

;;; Berechnet Schnittpunkt einer Dreiecks-Kante mit einer Hoehenebene
;;; Lineare Interpolation entlang Kante pa->pb bei Zielhoehe
;;;
;;; Parameter:
;;;   pa, pb - Endpunkte der Kante (x y z)
;;;   ha, hb - Hoehen der Endpunkte
;;;   target-h - Zielhoehe
;;;
;;; Rueckgabe: Punkt (x y z) oder nil wenn Hoehe nicht auf Kante liegt
(defun HAF:edge-height-point (pa pb ha hb target-h / t-val px py)
  ;; Pruefe ob Zielhoehe zwischen ha und hb liegt
  (if (or (and (<= ha target-h) (>= hb target-h))
          (and (>= ha target-h) (<= hb target-h)))
    (progn
      ;; Sonderfall: gleiche Hoehe (ganze Kante auf Zielhoehe)
      (if (equal ha hb 0.001)
        nil ;; Kante liegt komplett auf Hoehe - kein einzelner Schnittpunkt
        (progn
          (setq t-val (/ (- target-h ha) (- hb ha)))
          (setq px (+ (car pa) (* t-val (- (car pb) (car pa)))))
          (setq py (+ (cadr pa) (* t-val (- (cadr pb) (cadr pa)))))
          (list px py target-h)
        )
      )
    )
    nil ;; Zielhoehe liegt nicht auf dieser Kante
  )
)

;;; Berechnet Hoehenlinie in einem Dreieck
;;; Findet die 2 Kanten die von der Zielhoehe geschnitten werden
;;;
;;; Parameter:
;;;   p1, p2, p3 - Eckpunkte des Dreiecks
;;;   h1, h2, h3 - Hoehen
;;;   target-h - Zielhoehe
;;;
;;; Rueckgabe: Liste (punkt1 punkt2) oder nil wenn kein Schnitt
(defun HAF:contour-in-triangle (p1 h1 p2 h2 p3 h3 target-h / hit1 hit2 hit3 result)
  ;; Pruefe alle 3 Kanten
  (setq hit1 (HAF:edge-height-point p1 p2 h1 h2 target-h))  ;; Kante 1-2
  (setq hit2 (HAF:edge-height-point p2 p3 h2 h3 target-h))  ;; Kante 2-3
  (setq hit3 (HAF:edge-height-point p3 p1 h3 h1 target-h))  ;; Kante 3-1
  ;; Sammle Treffer (genau 2 erwartet, oder 0 wenn Hoehe ausserhalb)
  (setq result nil)
  (if hit1 (setq result (cons hit1 result)))
  (if hit2 (setq result (cons hit2 result)))
  (if hit3 (setq result (cons hit3 result)))
  (HAF:debug (strcat "contour-in-triangle: target=" (rtos target-h 2 2)
                     " hits=" (itoa (length result))))
  (if (= (length result) 2)
    result ;; (punkt1 punkt2)
    nil
  )
)

;;; Berechnet Hoehenlinie fuer 3 Punkte (Ebene)
;;; Schnitt Ebene mit Hoehenebene = eine gerade Linie
;;;
;;; Parameter:
;;;   pts - 3 Punkte, heights - 3 Hoehen, target-h - Zielhoehe
;;;
;;; Rueckgabe: Liste von Liniensegmenten ((p1 p2) ...) oder nil
(defun HAF:contour-3pt (pts heights target-h / p1 p2 p3 h1 h2 h3 seg)
  (setq p1 (nth 0 pts) p2 (nth 1 pts) p3 (nth 2 pts))
  (setq h1 (nth 0 heights) h2 (nth 1 heights) h3 (nth 2 heights))
  (setq seg (HAF:contour-in-triangle p1 h1 p2 h2 p3 h3 target-h))
  (if seg (list seg) nil)
)

;;; Berechnet Hoehenlinie fuer 4 Punkte (Triangulation)
;;; 2 Dreiecke je nach Diagonale — Linie mit Knick moeglich
;;;
;;; Parameter:
;;;   pts - 4 Punkte, heights - 4 Hoehen, target-h - Zielhoehe
;;;   diagonal - "13" oder "24"
;;;
;;; Rueckgabe: Liste von Liniensegmenten ((p1 p2) ...) oder nil
(defun HAF:contour-4pt (pts heights target-h diagonal
                        / p1 p2 p3 p4 h1 h2 h3 h4 seg1 seg2 result)
  (setq p1 (nth 0 pts) p2 (nth 1 pts) p3 (nth 2 pts) p4 (nth 3 pts))
  (setq h1 (nth 0 heights) h2 (nth 1 heights) h3 (nth 2 heights) h4 (nth 3 heights))
  (setq result nil)
  (if (= diagonal "13")
    ;; Dreiecke 1-2-3 und 1-3-4
    (progn
      (setq seg1 (HAF:contour-in-triangle p1 h1 p2 h2 p3 h3 target-h))
      (setq seg2 (HAF:contour-in-triangle p1 h1 p3 h3 p4 h4 target-h))
    )
    ;; Dreiecke 1-2-4 und 2-3-4
    (progn
      (setq seg1 (HAF:contour-in-triangle p1 h1 p2 h2 p4 h4 target-h))
      (setq seg2 (HAF:contour-in-triangle p2 h2 p3 h3 p4 h4 target-h))
    )
  )
  (if seg1 (setq result (cons seg1 result)))
  (if seg2 (setq result (cons seg2 result)))
  (HAF:debug (strcat "contour-4pt: " (itoa (length result)) " Segmente"))
  (if result (reverse result) nil)
)

;;; Zentrale Hoehenlinien-Funktion (Dispatcher)
;;;
;;; Parameter:
;;;   pts, heights - Punkte und Hoehen (3 oder 4)
;;;   target-h - Zielhoehe
;;;   diagonal - "13"/"24" (nur bei 4 Punkten)
;;;
;;; Rueckgabe: Liste von Liniensegmenten ((p1 p2) ...) oder nil
(defun HAF:compute-contour (pts heights target-h diagonal / num-pts)
  (setq num-pts (length pts))
  (HAF:debug (strcat "compute-contour: " (itoa num-pts) " Punkte, target=" (rtos target-h 2 2)))
  (cond
    ((= num-pts 3) (HAF:contour-3pt pts heights target-h))
    ((= num-pts 4) (HAF:contour-4pt pts heights target-h diagonal))
    (T nil)
  )
)

;;; Zeichnet Hoehenlinie als temporaere 3D-Polylinie (rot, Layer 0)
;;; Rueckgabe: Liste der Entity-Names (zum spaeteren Loeschen)
(defun HAF:draw-contour (segments / entities ent p1 p2)
  (setq entities nil)
  (foreach seg segments
    (setq p1 (car seg))
    (setq p2 (cadr seg))
    (if (and p1 p2)
      (progn
        (setq ent (entmakex
          (list '(0 . "LINE") '(100 . "AcDbEntity") '(8 . "0") '(62 . 1)
                '(100 . "AcDbLine")
                (cons 10 (trans p1 1 0))
                (cons 11 (trans p2 1 0)))))
        (if ent
          (progn
            (setq entities (cons ent entities))
            (HAF:debug (strcat "  Contour-Linie gezeichnet: ("
                               (rtos (car p1) 2 2) "," (rtos (cadr p1) 2 2) ") -> ("
                               (rtos (car p2) 2 2) "," (rtos (cadr p2) 2 2) ")"))
          )
        )
      )
    )
  )
  (HAF:log-write "INFO" (strcat "Hoehenlinie gezeichnet: " (itoa (length entities)) " Segmente"))
  entities
)

;;; Loescht Hoehenlinien-Entities
(defun HAF:delete-contours (entities / )
  (foreach ent entities
    (if (and ent (entget ent))
      (entdel ent)
    )
  )
  (HAF:debug (strcat "Contours geloescht: " (itoa (length entities))))
)

;;; Zeichnet Diagonale als 3D-Polylinie (gelb, zur Visualisierung)
(defun HAF:draw-diagonal (pt1 h1 pt2 h2 / p1-3d p2-3d)
  (setq p1-3d (list (car pt1) (cadr pt1) h1))
  (setq p2-3d (list (car pt2) (cadr pt2) h2))
  (command "_3DPOLY" p1-3d p2-3d "")
  (HAF:log-write "INFO" "Diagonale gezeichnet (3D-Polylinie)")
  (entlast)
)

;;; ============================================================================
;;; HILFSFUNKTIONEN - BRUCHLINIE (User-Eckpunkt-Auswahl)
;;; ============================================================================

;;; Laesst User einen Eckpunkt aus der Liste waehlen (naechster zum Klick)
;;; Rueckgabe: (punkt index) oder nil
(defun HAF:select-corner (corner-points prompt / pt i min-dist index selected-pt dist)
  (princ (strcat "\n" prompt))
  (setq pt (getpoint))
  (if (HAF:valid-point-p pt)
    (progn
      (setq i 0 min-dist 999999 index -1)
      (while (< i (length corner-points))
        (setq dist (distance pt (nth i corner-points)))
        (if (< dist min-dist)
          (progn (setq min-dist dist) (setq index i) (setq selected-pt (nth i corner-points)))
        )
        (setq i (1+ i))
      )
      (if (< min-dist 100)
        (list selected-pt index)
        nil
      )
    )
    nil
  )
)

;;; Fuehrt User durch Bruchlinien-Definition (2 Eckpunkte waehlen)
;;; Rueckgabe: "13" oder "24" oder "13" (Fallback)
(defun HAF:user-select-diagonal (corner-points corner-heights
                                  / c1-result c1-idx c1-h c2-result c2-idx c2-h)
  (princ "\n\nBitte definieren Sie die Bruchlinie:")
  ;; Erster Eckpunkt
  (setq c1-result (HAF:select-corner corner-points "  1. Eckpunkt waehlen: "))
  (if c1-result
    (progn
      (setq c1-idx (cadr c1-result))
      (setq c1-h (nth c1-idx corner-heights))
      (princ (strcat "\n     Eckpunkt " (itoa (1+ c1-idx))
                     " (Hoehe: " (rtos c1-h 2 2) ")"))
      ;; Zweiter Eckpunkt
      (setq c2-result (HAF:select-corner corner-points "  2. Eckpunkt waehlen: "))
      (if c2-result
        (progn
          (setq c2-idx (cadr c2-result))
          (setq c2-h (nth c2-idx corner-heights))
          (princ (strcat "\n     Eckpunkt " (itoa (1+ c2-idx))
                         " (Hoehe: " (rtos c2-h 2 2) ")"))
          (HAF:log-write "INFO" (strcat "Bruchlinie: Punkt " (itoa (1+ c1-idx))
                                        " -> Punkt " (itoa (1+ c2-idx))))
          ;; Bestimme welche Diagonale
          (cond
            ((or (and (= c1-idx 0) (= c2-idx 2)) (and (= c1-idx 2) (= c2-idx 0)))
             (princ "\n  Diagonale 1-3 gewaehlt") "13")
            ((or (and (= c1-idx 1) (= c2-idx 3)) (and (= c1-idx 3) (= c2-idx 1)))
             (princ "\n  Diagonale 2-4 gewaehlt") "24")
            (T
             (princ "\n  *** Keine Diagonale (benachbarte Punkte) - verwende 1-3 ***")
             (HAF:log-write "WARN" "Bruchlinie: benachbarte Punkte gewaehlt, Fallback 13")
             "13")
          )
        )
        (progn (princ "\n  *** Kein 2. Punkt - verwende 1-3 ***") "13")
      )
    )
    (progn (princ "\n  *** Kein 1. Punkt - verwende 1-3 ***") "13")
  )
)

;;; ============================================================================
;;; HAUPTBEFEHL: c:HoeheAufFlaeche
;;; ============================================================================

(defun c:HoeheAufFlaeche ( / *error* old-cmdecho old-attdia
                             corner-points corner-heights corner-entities corner-number done
                             num-corners scale pg result interpolated-height tri-info
                             prompt-str pt ht block-ent last-ent
                             diagonal-choice use-diagonal diagonal-ent
                             contour-entities target-h segments
                             p1 h1 p2 h2 p3 h3 p4 h4)
  
  (HAF:ensure-init)
  
  ;; Lokaler Error-Handler mit wcmatch Cancel-Detection (DE+EN)
  (defun *error* (msg)
    (if (not (HAF:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (HAF:log-write "ERROR" (strcat "Error-Handler: " msg))
      )
      (HAF:log-write "INFO" (strcat "User-Abbruch: " msg))
    )
    ;; Temporaere Entities aufraeumen
    (if contour-entities (HAF:delete-contours contour-entities))
    (if diagonal-ent (if (entget diagonal-ent) (entdel diagonal-ent)))
    ;; Systemvariablen wiederherstellen
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-attdia (setvar "ATTDIA" old-attdia))
    (princ)
  )
  
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-attdia (getvar "ATTDIA"))
  (setvar "CMDECHO" 0)
  (setvar "ATTDIA" 0)
  
  (HAF:log-write "INFO" (strcat "=== HoeheAufFlaeche v" *HAF:version* " ==="))
  (HAF:log-write "INFO" (strcat "Zeichnung: " (getvar "DWGNAME")))
  (HAF:log-write "INFO" "Befehl HoeheAufFlaeche gestartet")
  
  (princ "\n=== Hoeheninterpolation auf Flaeche ===")
  (princ "\nSetzen Sie 3 oder 4 Eckpunkte mit bekannten Hoehen.")
  
  ;; Skalierung aus DWG
  (setq scale (HAF:read-scale))
  (HAF:debug (strcat "Scale: " (rtos scale 2 4)))
  
  ;; ====================================================================
  ;; PHASE 1: ECKPUNKTE SAMMELN
  ;; ====================================================================
  
  (setq corner-points nil corner-heights nil corner-entities nil)
  (setq corner-number 1 done nil)
  (setq contour-entities nil diagonal-ent nil)
  
  (while (and (not done) (< corner-number 5))
    ;; Keywords je nach Zustand
    (if (> corner-number 1)
      (initget "Skalierung Zurueck Einstellungen")
      (initget "Skalierung Einstellungen")
    )
    ;; Prompt zusammenbauen
    (setq prompt-str (strcat "\nEckpunkt " (itoa corner-number) " waehlen ["))
    (if (> corner-number 1) (setq prompt-str (strcat prompt-str "Zurueck/")))
    (setq prompt-str (strcat prompt-str "Skalierung/Einstellungen"))
    (if (>= corner-number 4) (setq prompt-str (strcat prompt-str "/ENTER=Fertig")))
    (setq prompt-str (strcat prompt-str "] <" (rtos scale 2 2) ">: "))
    
    (setq pt (getpoint prompt-str))
    
    (cond
      ;; Skalierung
      ((= pt "Skalierung")
       (setq scale (HAF:get-scale))
      )
      ;; Einstellungen
      ((= pt "Einstellungen")
       (HAF:show-settings)
       (setq scale (HAF:read-scale))
      )
      ;; Zurueck
      ((= pt "Zurueck")
       (if (> corner-number 1)
         (progn
           ;; Letzten Block loeschen (wenn wir einen eingefuegt haben)
           (setq last-ent (last corner-entities))
           (if last-ent (entdel last-ent))
           ;; Listen kuerzen
           (setq corner-points (reverse (cdr (reverse corner-points))))
           (setq corner-heights (reverse (cdr (reverse corner-heights))))
           (setq corner-entities (reverse (cdr (reverse corner-entities))))
           (setq corner-number (1- corner-number))
           (HAF:log-write "INFO" (strcat "Eckpunkt " (itoa corner-number) " entfernt (Zurueck)"))
           (princ (strcat "\n  Eckpunkt " (itoa corner-number) " entfernt"))
         )
         (princ "\n*** Kein Punkt zum Entfernen ***")
       )
      )
      ;; ENTER bei >= 4 Punkten (corner-number ist schon 4 = 3 Punkte gesetzt)
      ((and (null pt) (>= corner-number 4))
       (setq done T)
       (HAF:log-write "INFO" "Eckpunkte-Eingabe abgeschlossen (ENTER)")
      )
      ;; Gueltiger Punkt
      ((HAF:valid-point-p pt)
       (setq ht (HAF:get-validated-height
                  (strcat "\nHoehe Eckpunkt " (itoa corner-number))
                  *HAF:last-height*))
       (if ht
         (progn
           (setq *HAF:last-height* ht)
           ;; Block einfuegen (skip-if-exists=T fuer Eckpunkte)
           (setq block-ent (HAF:insert-block pt ht scale T))
           ;; Zu Listen hinzufuegen
           (setq corner-points (append corner-points (list pt)))
           (setq corner-heights (append corner-heights (list ht)))
           (setq corner-entities (append corner-entities (list block-ent)))
           (HAF:log-write "INFO" (strcat "Eckpunkt " (itoa corner-number)
                                         ": (" (rtos (car pt) 2 3) " " (rtos (cadr pt) 2 3)
                                         ") H=" (rtos ht 2 3)))
           (setq corner-number (1+ corner-number))
           ;; Hinweis bei 3 Punkten
           (if (= corner-number 4)
             (princ "\n  (ENTER fuer 3 Punkte oder 4. Punkt setzen)")
           )
         )
         (princ "\n*** Ungueltige Hoehe ***")
       )
      )
      ;; ESC oder nil (bei < 4 Punkten = zu wenig)
      (T
       (if (< corner-number 4)
         (progn
           (princ "\n*** Abbruch: Mindestens 3 Eckpunkte noetig ***")
           (HAF:log-write "INFO" "Abbruch: zu wenig Eckpunkte")
           (setq done T corner-points nil)
         )
         (setq done T)
       )
      )
    )
  ) ;; end while Eckpunkte
  
  ;; ====================================================================
  ;; PHASE 2: DIAGONALE BESTIMMEN (nur bei 4 Punkten)
  ;; ====================================================================
  
  (if (>= (length corner-points) 3)
    (progn
      (setq num-corners (length corner-points))
      (princ (strcat "\n\n" (itoa num-corners) " Eckpunkte definiert"))
      
      ;; Punkte fuer einfachen Zugriff
      (setq p1 (nth 0 corner-points) h1 (nth 0 corner-heights))
      (setq p2 (nth 1 corner-points) h2 (nth 1 corner-heights))
      (setq p3 (nth 2 corner-points) h3 (nth 2 corner-heights))
      
      (if (= num-corners 4)
        (progn
          (setq p4 (nth 3 corner-points) h4 (nth 3 corner-heights))
          ;; Automatische Diagonalen-Wahl
          (setq diagonal-choice (HAF:determine-diagonal h1 h2 h3 h4))
          ;; Bei Sattel: User muss Bruchlinie definieren
          (if (= diagonal-choice "USER")
            (setq diagonal-choice
              (HAF:user-select-diagonal corner-points corner-heights))
          )
          ;; Diagonale zeichnen
          (if (= diagonal-choice "13")
            (setq diagonal-ent (HAF:draw-diagonal p1 h1 p3 h3))
            (setq diagonal-ent (HAF:draw-diagonal p2 h2 p4 h4))
          )
          (setq use-diagonal diagonal-choice)
        )
        (setq use-diagonal nil) ;; 3 Punkte: keine Diagonale
      )
      
      ;; ====================================================================
      ;; PHASE 3: GESUCHTE PUNKTE SETZEN
      ;; ====================================================================
      
      (princ "\n")
      (princ "\n--- Punkte setzen (S=Skalierung, B=Bruchlinie, H=Hoehenlinie, E=Einstellungen, ESC=Ende) ---")
      
      (if (= num-corners 4)
        (initget "Skalierung Bruchlinie Hoehenlinie Einstellungen")
        (initget "Skalierung Hoehenlinie Einstellungen")
      )
      (setq pg (getpoint (strcat "\nPunkt waehlen [Skalierung"
                                 (if (= num-corners 4) "/Bruchlinie" "")
                                 "/Hoehenlinie/Einstellungen] <" (rtos scale 2 2) ">: ")))
      
      (while pg
        (cond
          ;; Skalierung
          ((= pg "Skalierung")
           (setq scale (HAF:get-scale))
          )
          ;; Einstellungen
          ((= pg "Einstellungen")
           (HAF:show-settings)
           (setq scale (HAF:read-scale))
          )
          ;; Bruchlinie (nur bei 4 Punkten) — Diagonale aendern
          ((= pg "Bruchlinie")
           (if diagonal-ent (if (entget diagonal-ent) (entdel diagonal-ent)))
           (setq diagonal-choice
             (HAF:user-select-diagonal corner-points corner-heights))
           (setq use-diagonal diagonal-choice)
           ;; Neue Diagonale zeichnen
           (if (= use-diagonal "13")
             (setq diagonal-ent (HAF:draw-diagonal p1 h1 p3 h3))
             (setq diagonal-ent (HAF:draw-diagonal p2 h2 p4 h4))
           )
          )
          ;; Hoehenlinie
          ((= pg "Hoehenlinie")
           ;; Alte Hoehenlinien loeschen
           (if contour-entities (HAF:delete-contours contour-entities))
           (setq contour-entities nil)
           ;; Zielhoehe abfragen
           (setq target-h (getreal "\nZielhoehe fuer Hoehenlinie: "))
           (if target-h
             (progn
               (HAF:log-write "INFO" (strcat "Hoehenlinie: H=" (rtos target-h 2 2)))
               (setq segments (HAF:compute-contour corner-points corner-heights
                                                    target-h use-diagonal))
               (if segments
                 (progn
                   (setq contour-entities (HAF:draw-contour segments))
                   (princ (strcat "\n  Hoehenlinie bei " (rtos target-h 2 2)
                                  " (" (itoa (length segments)) " Segment(e))"))
                 )
                 (princ (strcat "\n  Keine Hoehenlinie bei " (rtos target-h 2 2)
                                " (ausserhalb der Flaeche)"))
               )
             )
             (princ "\n  Keine Hoehe eingegeben")
           )
          )
          ;; Gueltiger Punkt — interpolieren
          (T
           (if (HAF:valid-point-p pg)
             (progn
               (setq result (HAF:interpolate corner-points corner-heights pg use-diagonal))
               (if result
                 (progn
                   (setq interpolated-height (car result))
                   (setq tri-info (cadr result))
                   (princ (strcat "\n  Hoehe: " (HAF:format-height interpolated-height)
                                  " (" tri-info ")"))
                   (HAF:insert-block pg interpolated-height scale nil)
                   (HAF:log-write "INFO" (strcat "Interpolation: ("
                                                 (rtos (car pg) 2 3) " " (rtos (cadr pg) 2 3)
                                                 ") -> " (rtos interpolated-height 2 4)
                                                 " (" tri-info ")"))
                 )
                 (princ "\n*** Fehler bei Hoehenberechnung ***")
               )
             )
             (princ "\n*** Ungueltiger Punkt ***")
           )
          )
        )
        
        ;; Naechster Punkt
        (if (= num-corners 4)
          (initget "Skalierung Bruchlinie Hoehenlinie Einstellungen")
          (initget "Skalierung Hoehenlinie Einstellungen")
        )
        (setq pg (getpoint (strcat "\nPunkt waehlen [Skalierung"
                                   (if (= num-corners 4) "/Bruchlinie" "")
                                   "/Hoehenlinie/Einstellungen] <" (rtos scale 2 2) ">: ")))
      ) ;; end while Punkte
      
      ;; ====================================================================
      ;; PHASE 4: AUFRAEUMEN
      ;; ====================================================================
      
      ;; Hoehenlinien loeschen (temporaer)
      (if contour-entities
        (progn
          (HAF:delete-contours contour-entities)
          (setq contour-entities nil)
        )
      )
      ;; Diagonale loeschen
      (if diagonal-ent
        (progn
          (if (entget diagonal-ent) (entdel diagonal-ent))
          (setq diagonal-ent nil)
        )
      )
      
      (HAF:log-write "INFO" "Befehl HoeheAufFlaeche beendet")
      (princ "\n\nHoeheninterpolation abgeschlossen.")
    )
  ) ;; end if >= 3 Punkte
  
  ;; Cleanup
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (if old-attdia (setvar "ATTDIA" old-attdia))
  (princ)
)

;;; Kurzbefehl
(defun c:HAF ()
  (c:HoeheAufFlaeche)
)

;;; Block-Verwaltung
(defun c:HAFBLOCK ( / )
  (HAF:ensure-init)
  (HAF:log-write "INFO" "Befehl HAFBLOCK gestartet")
  (manage-block-import "HAF")
  (HAF:log-write "INFO" "Befehl HAFBLOCK beendet")
  (princ)
)

;;; ============================================================================
;;; DCL SETTINGS DIALOG
;;; ============================================================================

;;; Schreibt die DCL-Datei als Temp-Datei
(defun HAF:write-settings-dcl ( / dcl-file fp)
  (setq dcl-file (vl-filename-mktemp "haf" nil ".dcl"))
  (setq fp (open dcl-file "w"))
  
  (write-line "haf_settings : dialog {" fp)
  (write-line "  label = \"HoeheAufFlaeche - Einstellungen\";" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Skalierung ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"XY-Skalierung\";" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"scale\";" fp)
  (write-line "      label = \"Aktuelle Zeichnung:\";" fp)
  (write-line "      edit_width = 10;" fp)
  (write-line "    }" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"default_scale\";" fp)
  (write-line "      label = \"Default (neue Zeichnungen):\";" fp)
  (write-line "      edit_width = 10;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Block ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Hoehenkoten-Block\";" fp)
  (write-line "    : text {" fp)
  (write-line "      key = \"blockname_info\";" fp)
  (write-line "      label = \"\";" fp)
  (write-line "    }" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_block\";" fp)
  (write-line "      label = \"Block-Verwaltung oeffnen...\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Layer ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Layer\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"use_suffix\";" fp)
  (write-line "      label = \"Eigener Layer fuer Hoehenkoten\";" fp)
  (write-line "    }" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"layer_suffix\";" fp)
  (write-line "      label = \"Suffix (nach _):\";" fp)
  (write-line "      edit_width = 15;" fp)
  (write-line "    }" fp)
  (write-line "    : text {" fp)
  (write-line "      key = \"layer_preview\";" fp)
  (write-line "      label = \"\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- BlockImport Pfad ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"BlockImport.lsp\";" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"libpath\";" fp)
  (write-line "      label = \"Pfad:\";" fp)
  (write-line "      edit_width = 40;" fp)
  (write-line "    }" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_browse\";" fp)
  (write-line "      label = \"Durchsuchen...\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Debug ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Debug\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"debug\";" fp)
  (write-line "      label = \"Debug-Modus aktivieren\";" fp)
  (write-line "    }" fp)
  (write-line "    : text {" fp)
  (write-line "      key = \"logpath\";" fp)
  (write-line "      label = \"\";" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Info ---
  (write-line "  : text {" fp)
  (write-line "    key = \"info\";" fp)
  (write-line "    label = \"\";" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- OK / Abbrechen ---
  (write-line "  ok_cancel;" fp)
  (write-line "}" fp)
  
  (close fp)
  dcl-file
)

;;; Oeffnet Settings-Dialog, speichert bei OK
(defun HAF:show-settings ( / dcl-file dcl-id result cur-scale cur-default-scale cur-libpath cfg-val)
  (HAF:log-write "INFO" "Settings-Dialog geoeffnet")
  
  ;; Aktuelle Werte lesen
  (setq cur-scale (HAF:read-dwg-scale))
  (if (null cur-scale) (setq cur-scale 0.0))
  (setq cfg-val (HAF:get-config-value "DEFAULT_SCALE"))
  (setq cur-default-scale (if (and cfg-val (/= cfg-val "")) (atof cfg-val) 1.0))
  (setq cur-libpath (HAF:get-config-value "BLOCKIMPORT_PATH"))
  (if (null cur-libpath) (setq cur-libpath "(nicht konfiguriert)"))
  
  ;; DCL schreiben und laden
  (setq dcl-file (HAF:write-settings-dcl))
  (setq dcl-id (load_dialog dcl-file))
  
  (if (not (new_dialog "haf_settings" dcl-id))
    (progn
      (HAF:log-write "ERROR" "DCL Dialog konnte nicht geoeffnet werden")
      (princ "\n*** Fehler: Dialog konnte nicht geoeffnet werden ***")
      (unload_dialog dcl-id)
      (vl-file-delete dcl-file)
    )
    (progn
      ;; Werte in Dialog setzen
      (set_tile "scale" (if (> cur-scale 0.0) (rtos cur-scale 2 2) "(nicht gesetzt)"))
      (set_tile "default_scale" (rtos cur-default-scale 2 2))
      (set_tile "use_suffix" (if *HAF:use-layer-suffix* "1" "0"))
      (set_tile "layer_suffix" *HAF:layer-suffix*)
      (set_tile "layer_preview" (strcat "Vorschau: " (getvar "CLAYER") "_" *HAF:layer-suffix*))
      (set_tile "libpath" cur-libpath)
      (set_tile "debug" (if *HAF:debug-mode* "1" "0"))
      (set_tile "logpath" (strcat "Log: " (HAF:get-appdata-path) "\\Log"))
      (setq *block-import-context* "HAF")
      (set_tile "blockname_info"
        (strcat "Aktueller Block: "
          (if (BLI:resolve-blockname "HAF")
            (BLI:resolve-blockname "HAF")
            "(nicht konfiguriert)")))
      (set_tile "info" (strcat "HoeheAufFlaeche v" *HAF:version*))
      
      ;; Live-Vorschau Layer-Suffix
      (action_tile "layer_suffix"
        "(set_tile \"layer_preview\" (strcat \"Vorschau: \" (getvar \"CLAYER\") \"_\" (get_tile \"layer_suffix\")))"
      )
      
      ;; Durchsuchen-Button fuer BlockImport.lsp
      (action_tile "btn_browse"
        (strcat
          "(progn"
          "  (setq *HAF:tmp-path*"
          "    (getfiled \"BlockImport.lsp auswaehlen\""
          "      (if (findfile (get_tile \"libpath\"))"
          "        (vl-filename-directory (get_tile \"libpath\"))"
          "        (cond ((getvar \"DWGPREFIX\")) ((getenv \"USERPROFILE\")) (T \"\"))"
          "      )"
          "      \"lsp\" 0))"
          "  (if *HAF:tmp-path*"
          "    (set_tile \"libpath\" *HAF:tmp-path*)"
          "  )"
          ")"
        )
      )
      
      ;; Block-Verwaltung Button: Werte speichern VOR done_dialog (Sub-Dialog Bug!)
      (action_tile "btn_block"
        (strcat
          "(setq *HAF:tmp-scale* (get_tile \"scale\"))"
          "(setq *HAF:tmp-default-scale* (get_tile \"default_scale\"))"
          "(setq *HAF:tmp-use-suffix* (get_tile \"use_suffix\"))"
          "(setq *HAF:tmp-layer-suffix* (get_tile \"layer_suffix\"))"
          "(setq *HAF:tmp-libpath* (get_tile \"libpath\"))"
          "(setq *HAF:tmp-debug* (get_tile \"debug\"))"
          "(done_dialog 2)"
        )
      )
      
      ;; OK: Werte in globale Vars speichern VOR done_dialog (Sub-Dialog Bug!)
      (action_tile "accept"
        (strcat
          "(setq *HAF:tmp-scale* (get_tile \"scale\"))"
          "(setq *HAF:tmp-default-scale* (get_tile \"default_scale\"))"
          "(setq *HAF:tmp-use-suffix* (get_tile \"use_suffix\"))"
          "(setq *HAF:tmp-layer-suffix* (get_tile \"layer_suffix\"))"
          "(setq *HAF:tmp-libpath* (get_tile \"libpath\"))"
          "(setq *HAF:tmp-debug* (get_tile \"debug\"))"
          "(done_dialog 1)"
        )
      )
      
      ;; Dialog starten
      (setq result (start_dialog))
      
      ;; Auswerten
      (cond
        ;; OK (result = 1)
        ((= result 1)
          ;; DWG-Skalierung
          (if (> (atof *HAF:tmp-scale*) 0.0)
            (progn
              (HAF:write-dwg-scale (atof *HAF:tmp-scale*))
              (HAF:log-write "INFO" (strcat "DWG-Skalierung: " *HAF:tmp-scale*))
            )
            (if (/= *HAF:tmp-scale* "(nicht gesetzt)")
              (progn
                (princ "\n*** DWG-Skalierung muss > 0 sein ***")
                (HAF:log-write "WARN" (strcat "Ungueltige DWG-Skalierung: " *HAF:tmp-scale*))
              )
            )
          )
          ;; Default-Skalierung
          (if (> (atof *HAF:tmp-default-scale*) 0.0)
            (progn
              (HAF:save-default-scale (atof *HAF:tmp-default-scale*))
              (HAF:log-write "INFO" (strcat "Default-Skalierung: " *HAF:tmp-default-scale*))
            )
            (progn
              (princ "\n*** Default-Skalierung muss > 0 sein ***")
              (HAF:log-write "WARN" (strcat "Ungueltige Default-Skalierung: " *HAF:tmp-default-scale*))
            )
          )
          ;; Layer-Suffix
          (setq *HAF:use-layer-suffix* (= *HAF:tmp-use-suffix* "1"))
          (HAF:set-config-value "USE_LAYER_SUFFIX" (if *HAF:use-layer-suffix* "1" "0"))
          (if (and *HAF:tmp-layer-suffix* (/= *HAF:tmp-layer-suffix* ""))
            (progn
              (setq *HAF:layer-suffix* *HAF:tmp-layer-suffix*)
              (HAF:set-config-value "LAYER_SUFFIX" *HAF:layer-suffix*)
            )
            (progn
              (princ "\n*** Layer-Suffix darf nicht leer sein ***")
              (HAF:log-write "WARN" "Leeres Layer-Suffix ignoriert")
            )
          )
          ;; BlockImport Pfad
          (if (and *HAF:tmp-libpath*
                   (/= *HAF:tmp-libpath* "(nicht konfiguriert)")
                   (/= *HAF:tmp-libpath* cur-libpath))
            (progn
              (HAF:set-config-value "BLOCKIMPORT_PATH" *HAF:tmp-libpath*)
              (HAF:log-write "INFO" (strcat "BlockImport Pfad: " *HAF:tmp-libpath*))
            )
          )
          ;; Debug
          (setq *HAF:debug-mode* (= *HAF:tmp-debug* "1"))
          (HAF:set-config-value "DEBUG" (if *HAF:debug-mode* "1" "0"))
          
          (HAF:log-write "INFO" (strcat "Settings: Layer=" (if *HAF:use-layer-suffix* "aktiv" "aus")
                                        " Suffix=_" *HAF:layer-suffix*
                                        " Debug=" (if *HAF:debug-mode* "ein" "aus")))
          (princ "\nEinstellungen gespeichert.")
        )
        
        ;; Block-Manager (result = 2)
        ((= result 2)
          (HAF:log-write "INFO" "Block-Verwaltung geoeffnet aus Settings")
          (unload_dialog dcl-id)
          (vl-file-delete dcl-file)
          (manage-block-import "HAF")
          ;; Settings erneut oeffnen
          (HAF:log-write "INFO" "Settings erneut oeffnen nach Block-Verwaltung")
          (HAF:show-settings)
        )
        
        ;; Abbrechen (result = 0)
        (T
          (HAF:log-write "INFO" "Settings abgebrochen")
          (princ "\nAbgebrochen.")
        )
      )
      
      ;; Aufraeumen (nur wenn nicht schon durch result=2)
      (if (/= result 2)
        (progn
          (unload_dialog dcl-id)
          (vl-file-delete dcl-file)
        )
      )
    )
  )
  
  ;; Temp-Variablen aufraeumen
  (setq *HAF:tmp-scale* nil)
  (setq *HAF:tmp-default-scale* nil)
  (setq *HAF:tmp-use-suffix* nil)
  (setq *HAF:tmp-layer-suffix* nil)
  (setq *HAF:tmp-libpath* nil)
  (setq *HAF:tmp-debug* nil)
  (setq *HAF:tmp-path* nil)
)

;;; Settings-Befehl
(defun c:HAFSETTINGS ( / )
  (HAF:ensure-init)
  (HAF:show-settings)
  (princ)
)

;;; ============================================================================
;;; BEFEHLE - DEBUG
;;; ============================================================================

;;; Debug-Modus ein/aus (persistiert in Config)
(defun c:HAFDEBUG ( / )
  (HAF:ensure-init)
  (setq *HAF:debug-mode* (not *HAF:debug-mode*))
  (HAF:set-config-value "DEBUG" (if *HAF:debug-mode* "1" "0"))
  (HAF:log-write "INFO" (strcat "Debug-Modus: " (if *HAF:debug-mode* "EIN" "AUS")))
  (princ (strcat "\nDebug-Modus: " (if *HAF:debug-mode* "EIN" "AUS")))
  (princ)
)

;;; ============================================================================
;;; LADE-MELDUNG (NUR PRINC auf Top-Level!)
;;; ============================================================================

(princ (strcat "\nHoeheAufFlaeche.lsp v" *HAF:version* " geladen."))
(princ "\nBefehle:")
(princ "\n  HoeheAufFlaeche (HAF)  - Hoeheninterpolation (S/Z/B/H/E Keywords)")
(princ "\n  HAFSETTINGS            - Einstellungen (Skalierung, Block, Layer, Debug)")
(princ "\n  HAFBLOCK               - Block-Verwaltung")
(princ "\n  HAFDEBUG               - Debug ein/aus")
(princ "\n")
(princ)

;;; Ende der Datei
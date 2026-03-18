;;; SetHoehenkote.lsp
;;; Automatisches Setzen von Hoehenkoten-Bloecken in AutoCAD
;;; Speziell fuer Leica-Vermessungsarbeiten
;;;
;;; Version: 2.3.2
;;; Datum: 2026-03-18
;;; Autor: Herbert Schrotter
;;; Namespace: SetHK (SetHoehenkote)
;;;
;;; AppData: %APPDATA%\AutoCAD\Lisp\SetHoehenkote\
;;;   - Log:    Log\SetHoehenkote_YYYYMMDD_HHMMSS.log (max 5 Sessions)
;;;   - Config: Config\SetHoehenkote.cfg
;;;   - Backup: Backup\
;;;
;;; Installation:
;;; 1. Befehl APPLOAD in AutoCAD ausfuehren
;;; 2. SetHoehenkote.lsp auswaehlen und laden
;;; 3. lib/BlockImport.lsp muss im selben Ordner oder Support-Pfad liegen
;;;
;;; Befehle:
;;; SetHK       - Hoehenkote setzen (S fuer Skalierung)
;;; HKSETTINGS  - Einstellungen (Skalierung, Block, Pfad, Debug)
;;; HKBLOCK     - Block-Verwaltung (Liste/Standard/Hinzufuegen/Entfernen)


;;; ============================================================================
;;; KONSTANTEN & GLOBALE VARIABLEN
;;; ============================================================================

(setq *SetHK:version* "2.3.2")
(setq *SetHK:appdata-folder* "SetHoehenkote")
(setq *SetHK:log-session-id* nil)
(setq *SetHK:debug-mode* nil)
(setq *SetHK:initialized* nil)

;; Speichert die zuletzt eingegebene Hoehe
(setq *SetHK:last-height* nil)

;; Name des Hoehenkoten-Blocks
(setq *SetHK:blockname* "BLK_Hoehenkote")

;; Block-Import Context fuer Namespace in BlockImport.lsp Config
(setq *SetHK:block-context* "SetHK")


;;; ============================================================================
;;; APPDATA & LOGGING
;;; ============================================================================

;;; Gibt den AppData-Basis-Ordner fuer dieses Script zurueck
;;; Struktur: %APPDATA%\AutoCAD\Lisp\SetHoehenkote\
;;; Erstellt alle Ebenen falls nicht vorhanden
;;; Rueckgabe: Pfad als String
(defun SetHK:get-appdata-path ( / lvl1 lvl2 base)
  ;; %APPDATA%\AutoCAD\
  (setq lvl1 (strcat (getenv "APPDATA") "\\AutoCAD"))
  (if (not (vl-file-directory-p lvl1))
    (vl-mkdir lvl1)
  )
  ;; %APPDATA%\AutoCAD\Lisp\
  (setq lvl2 (strcat lvl1 "\\Lisp"))
  (if (not (vl-file-directory-p lvl2))
    (vl-mkdir lvl2)
  )
  ;; %APPDATA%\AutoCAD\Lisp\SetHoehenkote\
  (setq base (strcat lvl2 "\\" *SetHK:appdata-folder*))
  (if (not (vl-file-directory-p base))
    (vl-mkdir base)
  )
  base
)

;;; Stellt sicher dass Unterordner existieren (Log, Config, Backup)
;;; Wird einmal beim ersten Log-Write aufgerufen
(defun SetHK:ensure-appdata-dirs ( / base)
  (setq base (SetHK:get-appdata-path))
  ;; Log\
  (if (not (vl-file-directory-p (strcat base "\\Log")))
    (vl-mkdir (strcat base "\\Log"))
  )
  ;; Config\
  (if (not (vl-file-directory-p (strcat base "\\Config")))
    (vl-mkdir (strcat base "\\Config"))
  )
  ;; Backup\
  (if (not (vl-file-directory-p (strcat base "\\Backup")))
    (vl-mkdir (strcat base "\\Backup"))
  )
)

;;; Loescht alte Logs, behaelt nur die 4 neuesten
;;; (5. ist die aktuelle Session, noch nicht erstellt)
;;; Wird beim ersten log-write der Session aufgerufen
(defun SetHK:log-rotate ( / log-dir pattern files sorted-files delete-count i)
  (setq log-dir (strcat (SetHK:get-appdata-path) "\\Log"))
  (setq pattern (strcat *SetHK:appdata-folder* "_*.log"))
  
  ;; Alle Log-Dateien finden
  (setq files (vl-directory-files log-dir pattern 1))
  
  (if files
    (progn
      ;; Sortieren (Dateiname enthaelt Timestamp = chronologisch)
      (setq sorted-files (vl-sort files '<))
      
      ;; Wenn mehr als 4 vorhanden → aelteste loeschen
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
(defun SetHK:log-write (level message / log-dir log-path fp timestamp)
  ;; Debug nur wenn aktiviert
  (if (and (= level "DEBUG") (not *SetHK:debug-mode*))
    nil ;; Skip
    (progn
      ;; Session-Log-Pfad ermitteln (einmal pro Session)
      (if (not *SetHK:log-session-id*)
        (progn
          (setq *SetHK:log-session-id*
            (strcat *SetHK:appdata-folder* "_"
              (menucmd "M=$(edtime,0,YYYYMMDD_HHMMSS)")
            )
          )
          ;; Unterordner sicherstellen + Rotation beim ersten Schreiben
          (SetHK:ensure-appdata-dirs)
          (SetHK:log-rotate)
        )
      )
      
      (setq log-dir (strcat (SetHK:get-appdata-path) "\\Log"))
      (setq log-path (strcat log-dir "\\" *SetHK:log-session-id* ".log"))
      
      ;; Timestamp erzeugen
      (setq timestamp (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM:SS)"))
      
      ;; Schreiben
      (setq fp (open log-path "a"))
      (if fp
        (progn
          (write-line
            (strcat "[" timestamp "] ["
              (substr (strcat level "     ") 1 5) ;; Padding auf 5 Zeichen
              "] " message)
            fp)
          (close fp)
        )
      )
    )
  )
)

;;; Cancel-Detection (DE + EN)
;;; Prueft ob User abgebrochen hat (ESC, Cancel, etc.)
;;; Rueckgabe: T wenn Cancel, nil wenn echter Fehler
(defun SetHK:cancel-p (msg)
  (wcmatch (strcase msg)
    "*ABBRUCH*,*ABGEBROCHEN*,*CANCEL*,*QUIT*,*EXIT*"
  )
)


;;; ============================================================================
;;; CONFIG-MANAGEMENT
;;; ============================================================================

;;; Liest Config aus %APPDATA%\AutoCAD\Lisp\SetHoehenkote\Config\SetHoehenkote.cfg
;;; Config-Format: KEY=VALUE pro Zeile
;;; Rueckgabe: Association-Liste ((key . value) ...) oder nil
(defun SetHK:load-config ( / cfg-path fp line pos key value result)
  (setq cfg-path (strcat (SetHK:get-appdata-path) "\\Config\\" *SetHK:appdata-folder* ".cfg"))
  (setq result nil)
  
  (if (findfile cfg-path)
    (progn
      (if (vl-catch-all-error-p
            (setq fp (vl-catch-all-apply 'open (list cfg-path "r"))))
        (progn
          (SetHK:log-write "ERROR" (strcat "Config lesen fehlgeschlagen: " cfg-path))
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
          (SetHK:log-write "INFO" (strcat "Config geladen: " cfg-path))
          result
        )
      )
    )
    (progn
      (SetHK:log-write "WARN" "Keine Config gefunden, verwende Defaults")
      nil
    )
  )
)

;;; Speichert Config in %APPDATA%\AutoCAD\Lisp\SetHoehenkote\Config\SetHoehenkote.cfg
;;; Parameter: config-data - Association-Liste ((key . value) ...)
;;; Rueckgabe: T bei Erfolg, nil bei Fehler
(defun SetHK:save-config (config-data / cfg-path fp)
  (SetHK:ensure-appdata-dirs)
  (setq cfg-path (strcat (SetHK:get-appdata-path) "\\Config\\" *SetHK:appdata-folder* ".cfg"))
  
  (if (vl-catch-all-error-p
        (setq fp (vl-catch-all-apply 'open (list cfg-path "w"))))
    (progn
      (SetHK:log-write "ERROR" (strcat "Config schreiben fehlgeschlagen: " cfg-path))
      nil
    )
    (progn
      (foreach pair config-data
        (write-line (strcat (car pair) "=" (cdr pair)) fp)
      )
      (close fp)
      (SetHK:log-write "INFO" (strcat "Config gespeichert: " cfg-path))
      T
    )
  )
)

;;; Liest einzelnen Wert aus Config
;;; Parameter: key - Schluessel (String)
;;; Rueckgabe: Wert (String) oder nil
(defun SetHK:get-config-value (key / config)
  (setq config (SetHK:load-config))
  (if config
    (cdr (assoc key config))
    nil
  )
)

;;; Setzt einzelnen Wert in Config (laedt, aendert, speichert)
;;; Parameter: key - Schluessel, value - Wert (beides Strings)
(defun SetHK:set-config-value (key value / config)
  (setq config (SetHK:load-config))
  (if (null config) (setq config '()))
  ;; Existierenden Key ersetzen oder neuen hinzufuegen
  (if (assoc key config)
    (setq config (subst (cons key value) (assoc key config) config))
    (setq config (cons (cons key value) config))
  )
  (SetHK:save-config config)
)


;;; ============================================================================
;;; BIBLIOTHEKEN LADEN (in Lazy-Init, NICHT auf Top-Level!)
;;; ============================================================================

;;; Laedt BlockImport.lsp mit 3-Fallback Pfadaufloesung
;;; 1. Gespeicherter Pfad aus Config (BLOCKIMPORT_PATH)
;;; 2. Legacy Config (%APPDATA%/AutoCAD/SetHoehenkoteConfig.txt)
;;; 3. findfile (Support-Pfade: lib/BlockImport.lsp, BlockImport.lsp)
;;; 4. File-Dialog als letzter Fallback
;;; Rueckgabe: T bei Erfolg, nil bei Fehler
(defun SetHK:load-blockimport ( / path legacy-path legacy-file version)
  (SetHK:log-write "INFO" "BlockImport.lsp wird gesucht...")
  
  ;; Fallback 1: Neuer Config-Pfad
  (setq path (SetHK:get-config-value "BLOCKIMPORT_PATH"))
  (if (and path (not (findfile path)))
    (progn
      (SetHK:log-write "WARN" (strcat "Config-Pfad ungueltig: " path))
      (setq path nil)
    )
  )
  
  ;; Fallback 2: Legacy Config (Migration von v1.5.1)
  (if (null path)
    (progn
      (setq legacy-path (strcat (getenv "APPDATA") "/AutoCAD/SetHoehenkoteConfig.txt"))
      (if (findfile legacy-path)
        (progn
          (SetHK:log-write "INFO" (strcat "Legacy Config gefunden: " legacy-path))
          (if (not (vl-catch-all-error-p
                     (setq legacy-file (vl-catch-all-apply 'open (list legacy-path "r")))))
            (progn
              (setq version (read-line legacy-file)) ;; Erste Zeile: Version
              (setq path (read-line legacy-file))     ;; Zweite Zeile: Pfad
              (close legacy-file)
              (if (and path (findfile path))
                (progn
                  ;; Migration: In neue Config uebernehmen
                  (SetHK:set-config-value "BLOCKIMPORT_PATH" path)
                  (SetHK:log-write "INFO" (strcat "Legacy-Pfad migriert: " path))
                )
                (setq path nil)
              )
            )
          )
        )
      )
    )
  )
  
  ;; Fallback 3: findfile (AutoCAD Support-Pfade)
  (if (null path)
    (setq path
      (cond
        ((findfile "lib/BlockImport.lsp"))
        ((findfile "BlockImport.lsp"))
      )
    )
  )
  
  ;; Fallback 4: File-Dialog
  (if (null path)
    (progn
      (SetHK:log-write "WARN" "BlockImport.lsp nicht automatisch gefunden")
      (princ "\n*** BlockImport.lsp wird nicht im Support-Pfad gefunden ***")
      (princ "\nBitte waehlen Sie die Datei lib/BlockImport.lsp aus...")
      
      (setq path
        (getfiled "BlockImport.lsp auswaehlen"
                  (cond
                    ((getvar "DWGPREFIX"))
                    ((getenv "USERPROFILE"))
                    (T "")
                  )
                  "lsp"
                  0))
      
      (if path
        (progn
          ;; Pfad in Config speichern
          (SetHK:set-config-value "BLOCKIMPORT_PATH" path)
          (SetHK:log-write "INFO" (strcat "BlockImport Pfad gespeichert: " path))
        )
      )
    )
  )
  
  ;; Laden
  (if path
    (progn
      (load path)
      (SetHK:log-write "INFO" (strcat "BlockImport.lsp geladen: " path))
      T
    )
    (progn
      (SetHK:log-write "ERROR" "BlockImport.lsp konnte nicht geladen werden!")
      (alert "FEHLER: BlockImport.lsp nicht gefunden!\nSetHK kann ohne BlockImport.lsp nicht arbeiten.")
      nil
    )
  )
)


;;; ============================================================================
;;; LAZY-INIT (CRITICAL bei DokaCAD!)
;;; ============================================================================

;;; Initialisierung beim ersten Befehlsaufruf
;;; Laedt VLA, BlockImport.lsp, setzt Context
;;; Wird nur 1x ausgefuehrt
(defun SetHK:ensure-init ( / )
  (if (not *SetHK:initialized*)
    (progn
      (SetHK:log-write "INFO" "Lazy-Init gestartet...")
      
      ;; VLA laden (NICHT auf Top-Level wegen DokaCAD!)
      (vl-load-com)
      (SetHK:log-write "INFO" "vl-load-com geladen")
      
      ;; BlockImport.lsp laden
      (if (not (SetHK:load-blockimport))
        (progn
          (SetHK:log-write "ERROR" "Lazy-Init FEHLGESCHLAGEN: BlockImport.lsp nicht geladen")
          ;; NICHT *SetHK:initialized* setzen → naechster Versuch moeglich
        )
        (progn
          ;; Block-Import Context setzen
          (setq *block-import-context* *SetHK:block-context*)
          (SetHK:log-write "INFO" (strcat "Block-Import Context: " *SetHK:block-context*))
          
          ;; Blockname aus Config laden (falls geaendert via HKSETTINGS)
          (if (SetHK:get-config-value "BLOCKNAME")
            (progn
              (setq *SetHK:blockname* (SetHK:get-config-value "BLOCKNAME"))
              (SetHK:log-write "INFO" (strcat "Blockname aus Config: " *SetHK:blockname*))
            )
          )
          
          ;; HK-Layer Setting aus Config laden
          (setq *SetHK:use-layer-suffix* (SetHK:read-layer-suffix-setting))
          (SetHK:log-write "INFO" (strcat "HK-Layer: " (if *SetHK:use-layer-suffix* "aktiv" "deaktiviert")))
          
          ;; Layer-Suffix aus Config laden
          (if (SetHK:get-config-value "LAYER_SUFFIX")
            (progn
              (setq *SetHK:layer-suffix* (SetHK:get-config-value "LAYER_SUFFIX"))
              (SetHK:log-write "INFO" (strcat "Layer-Suffix aus Config: _" *SetHK:layer-suffix*))
            )
          )
          
          ;; Fertig
          (setq *SetHK:initialized* T)
          (SetHK:log-write "INFO" "Lazy-Init abgeschlossen")
        )
      )
    )
  )
)


;;; ============================================================================
;;; SKALIERUNG - DWG CUSTOM PROPERTY + CONFIG FALLBACK
;;; ============================================================================

;;; Custom Property Name fuer Skalierung in DWG SummaryInfo
(setq *SetHK:scale-property* "SetHK_Scale")

;;; Liest Skalierung aus DWG Custom Property
;;; Verwendet safe-variant-value Pattern (GetCustomByIndex Quirk)
;;; Rueckgabe: Skalierung als Real oder nil
(defun SetHK:read-dwg-scale ( / doc info num-props i key val scale-str)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq info (vla-get-summaryinfo doc))
  (setq num-props (vla-numcustominfo info))
  (setq scale-str nil)
  
  ;; Alle Custom Properties durchsuchen
  (setq i 0)
  (while (and (< i num-props) (null scale-str))
    (vla-getcustombyindex info i 'key 'val)
    ;; Safe-Variant-Value: kann String oder Variant sein
    (setq key (SetHK:safe-variant-value key))
    (setq val (SetHK:safe-variant-value val))
    (if (and key (= (strcase key) (strcase *SetHK:scale-property*)))
      (setq scale-str val)
    )
    (setq i (1+ i))
  )
  
  (if (and scale-str (/= scale-str ""))
    (progn
      (SetHK:log-write "DEBUG" (strcat "DWG-Scale gelesen: " scale-str))
      (atof scale-str)
    )
    nil
  )
)

;;; Schreibt Skalierung in DWG Custom Property
;;; Erstellt Property falls nicht vorhanden, aktualisiert falls vorhanden
(defun SetHK:write-dwg-scale (scale-value / doc info num-props i key val found)
  (setq doc (vla-get-activedocument (vlax-get-acad-object)))
  (setq info (vla-get-summaryinfo doc))
  (setq num-props (vla-numcustominfo info))
  (setq found nil)
  
  ;; Suche ob Property schon existiert
  (setq i 0)
  (while (and (< i num-props) (not found))
    (vla-getcustombyindex info i 'key 'val)
    (setq key (SetHK:safe-variant-value key))
    (if (and key (= (strcase key) (strcase *SetHK:scale-property*)))
      (progn
        ;; Update existierendes Property
        (vla-setcustombyindex info i *SetHK:scale-property* (rtos scale-value 2 6))
        (setq found T)
        (SetHK:log-write "INFO" (strcat "DWG-Scale aktualisiert: " (rtos scale-value 2 2)))
      )
    )
    (setq i (1+ i))
  )
  
  ;; Wenn nicht gefunden: Neu anlegen
  (if (not found)
    (progn
      (vla-addcustominfo info *SetHK:scale-property* (rtos scale-value 2 6))
      (SetHK:log-write "INFO" (strcat "DWG-Scale neu angelegt: " (rtos scale-value 2 2)))
    )
  )
)

;;; Safe-Variant-Value Pattern (GetCustomByIndex Quirk)
;;; Gibt manchmal Strings direkt, manchmal Variants zurueck
(defun SetHK:safe-variant-value (val / )
  (cond
    ((= (type val) 'STR) val)
    ((= (type val) 'VLA-OBJECT) val)
    ((not (null val))
      (vl-catch-all-apply 'vlax-variant-value (list val))
    )
    (T nil)
  )
)

;;; Liest Skalierung: Erst DWG, dann Config-Default, dann 1.0
;;; Rueckgabe: Skalierung als Real (immer ein Wert, nie nil)
(defun SetHK:read-scale ( / dwg-scale cfg-val)
  ;; 1. Aus DWG Custom Property
  (setq dwg-scale (SetHK:read-dwg-scale))
  (if (and dwg-scale (> dwg-scale 0.0))
    (progn
      (SetHK:log-write "DEBUG" (strcat "Scale aus DWG: " (rtos dwg-scale 2 2)))
      dwg-scale
    )
    ;; 2. Fallback: Config-Default
    (progn
      (setq cfg-val (SetHK:get-config-value "DEFAULT_SCALE"))
      (if (and cfg-val (/= cfg-val ""))
        (progn
          (SetHK:log-write "DEBUG" (strcat "Scale aus Config-Default: " cfg-val))
          (atof cfg-val)
        )
        ;; 3. Fallback: 1.0
        (progn
          (SetHK:log-write "DEBUG" "Scale: kein Wert gefunden, verwende 1.0")
          1.0
        )
      )
    )
  )
)

;;; Speichert Skalierung in DWG Custom Property
;;; Config-Default bleibt unveraendert (wird nur ueber HKSETTINGS geaendert)
(defun SetHK:save-scale (scale-value / )
  (SetHK:write-dwg-scale scale-value)
)

;;; Speichert Default-Skalierung in Config (fuer neue Zeichnungen)
(defun SetHK:save-default-scale (scale-value / )
  (SetHK:set-config-value "DEFAULT_SCALE" (rtos scale-value 2 6))
  (SetHK:log-write "INFO" (strcat "Default-Scale in Config: " (rtos scale-value 2 2)))
)

;;; Fragt Benutzer nach XY-Skalierung und speichert in DWG
(defun SetHK:get-scale ( / scaleValue prompt current-scale)
  (setq current-scale (SetHK:read-scale))
  
  (setq prompt (strcat "\nNeue XY-Skalierung"
                       (if current-scale
                         (strcat " <" (rtos current-scale 2 2) ">")
                         " <1.0>")
                       ": "))
  
  (setq scaleValue (getreal prompt))
  
  ;; Wenn ENTER gedrueckt
  (if (null scaleValue)
    (if current-scale
      (setq scaleValue current-scale)
      (setq scaleValue 1.0)
    )
  )
  
  ;; Validierung: Skalierung muss > 0 sein
  (if (<= scaleValue 0.0)
    (progn
      (princ "\n*** Skalierung muss groesser als 0 sein! Verwende 1.0 ***")
      (SetHK:log-write "WARN" (strcat "Ungueltige Skalierung: " (rtos scaleValue 2 4) " -> 1.0"))
      (setq scaleValue 1.0)
    )
  )
  
  ;; Skalierung in DWG speichern
  (SetHK:save-scale scaleValue)
  (SetHK:log-write "INFO" (strcat "Skalierung gesetzt: " (rtos scaleValue 2 2) " (in DWG)"))
  (princ (strcat "\nSkalierung gespeichert: " (rtos scaleValue 2 2) " (in DWG)"))
  
  scaleValue
)


;;; ============================================================================
;;; HILFSFUNKTIONEN - FORMATIERUNG
;;; ============================================================================

;;; Formatiert Hoehenwert fuer Anzeige (3 Dezimalstellen)
(defun SetHK:format-height (heightValue)
  (rtos heightValue 2 3)
)

;;; Konvertiert Hoehe in String mit exakt 3 Dezimalstellen
(defun SetHK:ensure-three-decimals (heightValue / heightStr decimalPos decimals)
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

;;; Formatiert Hoehenwert mit Vorzeichen (+ oder %%p fuer ±0)
(defun SetHK:format-height-value (heightValue / formattedHeight)
  (setq formattedHeight (SetHK:ensure-three-decimals heightValue))
  (cond
    ((= heightValue 0.0) (setq formattedHeight (strcat "%%p" formattedHeight)))
    ((> heightValue 0.0) (setq formattedHeight (strcat "+" formattedHeight)))
  )
  formattedHeight
)


;;; ============================================================================
;;; HILFSFUNKTIONEN - BENUTZEREINGABEN
;;; ============================================================================

;;; Fragt Benutzer nach Einfuegepunkt mit Keywords fuer Skalierung und Einstellungen
;;; Rueckgabe: Liste (punkt scale) oder nil bei Abbruch
(defun SetHK:get-insert-point ( / pt scale current-scale)
  ;; Aktuelle Skalierung lesen (DWG → Config → 1.0)
  (setq current-scale (SetHK:read-scale))
  (setq scale current-scale)
  
  ;; Punkt mit Keyword-Optionen abfragen
  (initget "Skalierung Einstellungen")
  (setq pt (getpoint (strcat "\nPunkt waehlen [Skalierung/Einstellungen] <" (rtos scale 2 2) ">: ")))
  
  ;; Keyword-Schleife
  (while (and pt (= (type pt) 'STR))
    (cond
      ((= pt "Skalierung")
        (setq scale (SetHK:get-scale))
      )
      ((= pt "Einstellungen")
        (c:HKSETTINGS)
        ;; Nach Settings: Skalierung neu lesen (koennte geaendert sein)
        (setq scale (SetHK:read-scale))
      )
    )
    ;; Nochmal Punkt abfragen
    (initget "Skalierung Einstellungen")
    (setq pt (getpoint (strcat "\nPunkt waehlen [Skalierung/Einstellungen] <" (rtos scale 2 2) ">: ")))
  )
  
  ;; Wenn pt = nil (ESC) → Abbruch
  (if (null pt)
    (progn
      (SetHK:log-write "INFO" "User: Abbruch bei Punktwahl")
      nil
    )
    (progn
      (SetHK:log-write "INFO" (strcat "Punkt: ("
        (rtos (car pt) 2 3) " " (rtos (cadr pt) 2 3) " " (rtos (caddr pt) 2 3)
        ") Scale=" (rtos scale 2 2)))
      (list pt scale)
    )
  )
)

;;; Fragt Benutzer nach Hoehe mit Wiederholung bei fehlender Eingabe
(defun SetHK:get-height ( / heightValue prompt)
  (setq prompt (strcat "\nHoehe eingeben"
                       (if *SetHK:last-height*
                         (strcat " <" (SetHK:format-height *SetHK:last-height*) ">")
                         "")
                       ": "))
  
  (setq heightValue (getreal prompt))
  
  ;; Wenn ENTER gedrueckt und letzte Hoehe vorhanden
  (if (null heightValue)
    (if *SetHK:last-height*
      (setq heightValue *SetHK:last-height*)
      ;; Beim ersten Aufruf ohne vorherige Hoehe: Schleife
      (while (null heightValue)
        (princ "\n*** Bitte geben Sie eine Hoehe ein ***")
        (setq heightValue (getreal "\nHoehe eingeben: "))
      )
    )
  )
  
  ;; Neue Hoehe speichern
  (setq *SetHK:last-height* heightValue)
  (SetHK:log-write "INFO" (strcat "Hoehe: " (rtos heightValue 2 3)))
  heightValue
)


;;; ============================================================================
;;; HK-LAYER MANAGEMENT
;;; ============================================================================

;;; Default: HK-Layer aktiv
(setq *SetHK:use-layer-suffix* T)

;;; Layer-Suffix (frei konfigurierbar, wird mit _ getrennt)
;;; Beispiel: "HK" → Layer "Vermessung_HK"
(setq *SetHK:layer-suffix* "HK")

;;; Liest HK-Layer Einstellung aus Config
;;; Rueckgabe: T oder nil
(defun SetHK:read-layer-suffix-setting ( / val)
  (setq val (SetHK:get-config-value "USE_LAYER_SUFFIX"))
  (if val
    (/= val "0")  ;; Alles ausser "0" = aktiv
    T  ;; Default: aktiv
  )
)

;;; Erstellt den Layer mit konfiguriertem Suffix basierend auf aktuellem Layer
;;; Wenn aktueller Layer schon auf _<suffix> endet → direkt verwenden
;;; Wenn nicht → _<suffix> anhaengen, Layer erstellen falls noetig
;;; Kopiert via VLA: Farbe (ACI+TrueColor), Linientyp, Linienstaerke, Plot, Transparenz
;;; Rueckgabe: Name des Ziel-Layers (String) oder nil bei Fehler
(defun SetHK:ensure-hk-layer ( / cur-layer hk-layer-name suffix suffix-with-sep suffix-len
                                  doc layers src-layer new-layer color-obj)
  ;; Aktuellen Layer lesen
  (setq cur-layer (getvar "CLAYER"))
  
  ;; Suffix zusammenbauen: "_" + konfiguriertes Suffix
  (setq suffix *SetHK:layer-suffix*)
  (setq suffix-with-sep (strcat "_" suffix))
  (setq suffix-len (strlen suffix-with-sep))
  
  ;; Pruefen ob aktueller Layer schon auf _<suffix> endet
  (if (and (>= (strlen cur-layer) suffix-len)
           (= (strcase (substr cur-layer (- (strlen cur-layer) suffix-len -1)))
              (strcase suffix-with-sep)))
    (progn
      ;; Layer endet bereits auf _<suffix> → direkt verwenden
      (SetHK:log-write "DEBUG" (strcat "Layer endet auf " suffix-with-sep ", verwende direkt: " cur-layer))
      cur-layer
    )
    (progn
      ;; Layer endet NICHT auf _<suffix> → anhaengen
      (setq hk-layer-name (strcat cur-layer suffix-with-sep))
      
      (SetHK:log-write "DEBUG" (strcat "Layer: " cur-layer " -> " hk-layer-name))
      
      ;; Pruefen ob Layer schon existiert
      (if (tblsearch "LAYER" hk-layer-name)
        (progn
          (SetHK:log-write "DEBUG" (strcat "Layer existiert bereits: " hk-layer-name))
          hk-layer-name
        )
        (progn
          ;; VLA: Quell-Layer und Layers-Collection holen
          (setq doc (vla-get-activedocument (vlax-get-acad-object)))
          (setq layers (vla-get-layers doc))
          (setq src-layer (vla-item layers cur-layer))
          
          ;; Neuen Layer erstellen
          (setq new-layer
            (vl-catch-all-apply 'vla-add (list layers hk-layer-name)))
          
          (if (vl-catch-all-error-p new-layer)
            (progn
              (SetHK:log-write "ERROR"
                (strcat "Layer erstellen fehlgeschlagen: " hk-layer-name
                        " - " (vl-catch-all-error-message new-layer)))
              nil ;; Fallback: Block bleibt auf aktuellem Layer
            )
            (progn
              ;; === Properties vom Quell-Layer kopieren ===
              
              ;; ACI-Farbe (Index-Farbe)
              (vl-catch-all-apply 'vla-put-color
                (list new-layer (vla-get-color src-layer)))
              
              ;; TrueColor (wenn vorhanden)
              (setq color-obj
                (vl-catch-all-apply 'vla-get-truecolor (list src-layer)))
              (if (and color-obj (not (vl-catch-all-error-p color-obj)))
                (vl-catch-all-apply 'vla-put-truecolor
                  (list new-layer color-obj))
              )
              
              ;; Linientyp
              (vl-catch-all-apply 'vla-put-linetype
                (list new-layer (vla-get-linetype src-layer)))
              
              ;; Linienstaerke (Lineweight)
              (vl-catch-all-apply 'vla-put-lineweight
                (list new-layer (vla-get-lineweight src-layer)))
              
              ;; Plot-Flag (ob Layer geplottet wird)
              (vl-catch-all-apply 'vla-put-plottable
                (list new-layer (vla-get-plottable src-layer)))
              
              ;; Transparenz
              (vl-catch-all-apply 'vla-put-transparency
                (list new-layer (vla-get-transparency src-layer)))
              
              (SetHK:log-write "INFO"
                (strcat "Layer erstellt: " hk-layer-name
                        " (kopiert von " cur-layer ")"))
              hk-layer-name
            )
          )
        )
      )
    )
  )
)


;;; ============================================================================
;;; HAUPTFUNKTIONEN
;;; ============================================================================

;;; Fuegt Hoehenkoten-Block an gegebenem Punkt mit Hoehe und Skalierung ein
(defun SetHK:insert-block (einfuegepunkt hoehe scale / blockName heightStr intPart decPart height2DecStr attdia ent attribs insertionPoint block-available importEnt hk-layer ent-data)
  (setq blockName *SetHK:blockname*)
  
  (SetHK:log-write "DEBUG" (strcat "insert-block: pt=("
    (rtos (car einfuegepunkt) 2 3) " " (rtos (cadr einfuegepunkt) 2 3)
    ") h=" (rtos hoehe 2 3) " s=" (rtos scale 2 2)))
  
  ;; Parameter-Pruefung
  (if (and einfuegepunkt hoehe scale)
    (progn
      ;; Block verfuegbar machen (nutzt BlockImport.lsp Bibliothek)
      (setq block-available (ensure-block-available blockName))
      
      (if (car block-available)
        (progn
          (setq importEnt (cadr block-available))
          
          ;; Hoehe als String mit genau 3 Dezimalstellen
          (setq heightStr (SetHK:ensure-three-decimals hoehe))
          
          ;; Hoehe in Ganzzahl- und Dezimalteil aufteilen
          (setq intPart (substr heightStr 1 (vl-string-search "." heightStr)))
          (setq decPart (substr heightStr (+ (strlen intPart) 2)))
          
          ;; Dezimalteil auf 3 Stellen begrenzen
          (if (< (strlen decPart) 3)
            (setq decPart (strcat decPart (apply 'strcat (repeat (- 3 (strlen decPart)) "0"))))
          )
          
          ;; Hoehe als String mit 2 Dezimalstellen fuer HOEHE Attribut
          (setq height2DecStr (strcat intPart "." (substr decPart 1 2)))
          
          ;; Vorzeichen hinzufuegen
          (setq height2DecStr (cond
                                ((= hoehe 0.0) (strcat "%%p" height2DecStr))
                                ((> hoehe 0.0) (strcat "+" height2DecStr))
                                (T height2DecStr)))
          
          ;; ATTDIA-Variable speichern und auf 0 setzen
          (setq attdia (getvar "ATTDIA"))
          (setvar "ATTDIA" 0)
          
          ;; Block einfuegen mit XY-Skalierung (Z bleibt 1.0)
          (command "._-insert" blockName einfuegepunkt scale scale "" "")
          
          ;; ATTDIA-Variable wiederherstellen
          (setvar "ATTDIA" attdia)
          
          ;; Attribute im eingefuegten Block setzen
          (setq ent (entlast))
          (if (and ent (eq (cdr (assoc 0 (entget ent))) "INSERT"))
            (progn
              (setq attribs (entnext ent))
              (while (and attribs (eq (cdr (assoc 0 (entget attribs))) "ATTRIB"))
                (cond
                  ((eq (cdr (assoc 2 (entget attribs))) "HOEHE")
                   (entmod (subst (cons 1 height2DecStr) (assoc 1 (entget attribs)) (entget attribs)))
                  )
                  ((eq (cdr (assoc 2 (entget attribs))) "3DEZ")
                   (if (not (= (substr decPart 3 1) "0"))
                     (entmod (subst (cons 1 (substr decPart 3 1)) (assoc 1 (entget attribs)) (entget attribs)))
                   )
                  )
                )
                (setq attribs (entnext attribs))
              )
            )
          )
          
          ;; Block auf die Eingabehoehe verschieben
          (setq insertionPoint (cdr (assoc 10 (entget ent))))
          (command "._move" ent "" "_non" insertionPoint "_non" (list (car insertionPoint) (cadr insertionPoint) hoehe))
          
          ;; HK-Layer zuweisen (wenn aktiviert)
          (if *SetHK:use-layer-suffix*
            (progn
              (setq hk-layer (SetHK:ensure-hk-layer))
              (if hk-layer
                (progn
                  ;; Block auf HK-Layer setzen via entmod
                  (setq ent-data (entget ent))
                  (entmod (subst (cons 8 hk-layer) (assoc 8 ent-data) ent-data))
                  (SetHK:log-write "DEBUG" (strcat "Block auf Layer: " hk-layer))
                )
              )
            )
          )
          
          ;; Den waehrend des Imports eingefuegten Block wieder entfernen
          (if importEnt
            (entdel importEnt)
          )
          
          (SetHK:log-write "INFO" (strcat "Block gesetzt: " height2DecStr
                                          " | Z=" (rtos hoehe 2 3)
                                          " | Scale=" (rtos scale 2 2)
                                          (if (and *SetHK:use-layer-suffix* hk-layer)
                                            (strcat " | Layer=" hk-layer) "")))
          (princ (strcat "\nHoehenkote gesetzt: " height2DecStr
                        " | Z=" (rtos hoehe 2 3)
                        " | XY-Scale=" (rtos scale 2 2)
                        (if (and *SetHK:use-layer-suffix* hk-layer)
                          (strcat " | Layer=" hk-layer) "")))
        )
        (progn
          (SetHK:log-write "ERROR" "Block konnte nicht geladen werden")
          (princ "\n*** FEHLER: Block konnte nicht geladen werden ***")
        )
      )
    )
    (progn
      (SetHK:log-write "ERROR" "Ungueltige Parameter fuer insert-block")
      (princ "\n*** Fehler: Ungueltige Parameter ***")
    )
  )
  (princ)
)


;;; ============================================================================
;;; BEFEHLE
;;; ============================================================================

;;; Hauptbefehl: Hoehenkote setzen
(defun c:SetHK ( / *error* result pt scale hoehe old-cmdecho)
  
  ;; Lazy-Init: VLA + BlockImport laden (nur beim 1. Aufruf)
  (SetHK:ensure-init)
  
  ;; Logging: Befehl gestartet
  (SetHK:log-write "INFO" (strcat "=== SetHoehenkote v" *SetHK:version* " ==="))
  (SetHK:log-write "INFO" "Befehl SetHK gestartet")
  (SetHK:log-write "INFO" (strcat "Zeichnung: " (getvar "DWGNAME")))
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (SetHK:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (SetHK:log-write "ERROR" (strcat "Error-Handler: " msg))
      )
      (SetHK:log-write "INFO" (strcat "User: Abbruch (" msg ")"))
    )
    ;; Systemvariablen wiederherstellen
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (SetHK:log-write "INFO" "Befehl SetHK beendet (Error/Cancel)")
    (princ)
  )
  
  ;; Systemvariablen sichern
  (setq old-cmdecho (getvar "CMDECHO"))
  (SetHK:log-write "DEBUG" (strcat "CMDECHO gesichert: " (itoa old-cmdecho)))
  
  ;; Systemvariablen setzen fuer Command
  (setvar "CMDECHO" 0)
  
  ;; Einfuegepunkt mit Skalierungs-Option abfragen
  (setq result (SetHK:get-insert-point))
  
  ;; Nur weitermachen wenn Punkt gewaehlt
  (if result
    (progn
      (setq pt (car result))
      (setq scale (cadr result))
      
      ;; Hoehe abfragen
      (setq hoehe (SetHK:get-height))
      
      ;; Block einfuegen
      (if hoehe
        (SetHK:insert-block pt hoehe scale)
      )
    )
  )
  
  ;; Cleanup bei normalem Ende
  (setvar "CMDECHO" old-cmdecho)
  (SetHK:log-write "INFO" "Befehl SetHK beendet")
  (princ)
)

;;; Block Import Manager (interaktives Menue)
(defun c:HKBLOCK ( / )
  (SetHK:ensure-init)
  (SetHK:log-write "INFO" "Befehl HKBLOCK gestartet")
  (manage-block-import *SetHK:block-context*)
  (SetHK:log-write "INFO" "Befehl HKBLOCK beendet")
  (princ)
)


;;; ============================================================================
;;; HKSETTINGS - DCL DIALOG
;;; ============================================================================

;;; Schreibt die DCL-Datei als Temp-Datei
;;; Rueckgabe: Pfad zur DCL-Datei
(defun SetHK:write-settings-dcl ( / dcl-file fp)
  (setq dcl-file (vl-filename-mktemp "sethk" nil ".dcl"))
  (setq fp (open dcl-file "w"))
  
  (write-line "sethk_settings : dialog {" fp)
  (write-line "  label = \"SetHoehenkote - Einstellungen\";" fp)
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
  
  ;; --- Block-Name ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Hoehenkoten-Block\";" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"blockname\";" fp)
  (write-line "      label = \"Block-Name:\";" fp)
  (write-line "      edit_width = 25;" fp)
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
  
  ;; --- Info-Zeile ---
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

;;; Einstellungen-Dialog
;;; Zeigt DCL mit aktuellen Werten, speichert bei OK
(defun c:HKSETTINGS ( / *error* dcl-file dcl-id result
                        cur-scale cur-default-scale cur-blockname cur-libpath cur-debug cur-use-suffix
                        new-scale new-default-scale new-blockname new-libpath new-debug new-use-suffix
                        open-block-mgr cfg-val)
  
  ;; Lazy-Init
  (SetHK:ensure-init)
  (SetHK:log-write "INFO" "Befehl HKSETTINGS gestartet")
  
  ;; Flag fuer "Block-Verwaltung oeffnen" Button
  (setq open-block-mgr nil)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (SetHK:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (SetHK:log-write "ERROR" (strcat "HKSETTINGS Error: " msg))
      )
    )
    ;; DCL aufraeumen
    (if dcl-id (unload_dialog dcl-id))
    (if dcl-file (vl-file-delete dcl-file))
    (princ)
  )
  
  ;; Aktuelle Werte lesen
  ;; DWG-Scale: Aus Custom Property der aktuellen Zeichnung
  (setq cur-scale (SetHK:read-dwg-scale))
  (if (null cur-scale) (setq cur-scale 0.0)) ;; 0 = "nicht gesetzt"
  
  ;; Default-Scale: Aus Config (fuer neue Zeichnungen)
  (setq cfg-val (SetHK:get-config-value "DEFAULT_SCALE"))
  (setq cur-default-scale (if (and cfg-val (/= cfg-val "")) (atof cfg-val) 1.0))
  
  (setq cur-blockname *SetHK:blockname*)
  
  (setq cur-libpath (SetHK:get-config-value "BLOCKIMPORT_PATH"))
  (if (null cur-libpath) (setq cur-libpath "(nicht konfiguriert)"))
  
  (setq cur-debug *SetHK:debug-mode*)
  
  (setq cur-use-suffix *SetHK:use-layer-suffix*)
  
  ;; DCL schreiben
  (setq dcl-file (SetHK:write-settings-dcl))
  (setq dcl-id (load_dialog dcl-file))
  
  (if (not (new_dialog "sethk_settings" dcl-id))
    (progn
      (SetHK:log-write "ERROR" "DCL Dialog konnte nicht geoeffnet werden")
      (princ "\n*** Fehler: Dialog konnte nicht geoeffnet werden ***")
      (unload_dialog dcl-id)
      (vl-file-delete dcl-file)
    )
    (progn
      ;; Werte in Dialog setzen
      (set_tile "scale" (if (> cur-scale 0.0) (rtos cur-scale 2 2) "(nicht gesetzt)"))
      (set_tile "default_scale" (rtos cur-default-scale 2 2))
      (set_tile "blockname" cur-blockname)
      (set_tile "libpath" cur-libpath)
      (set_tile "debug" (if cur-debug "1" "0"))
      (set_tile "use_suffix" (if cur-use-suffix "1" "0"))
      (set_tile "layer_suffix" *SetHK:layer-suffix*)
      (set_tile "layer_preview" (strcat "Vorschau: " (getvar "CLAYER") "_" *SetHK:layer-suffix*))
      (set_tile "logpath" (strcat "Log: " (SetHK:get-appdata-path) "\\Log"))
      (set_tile "info" (strcat "SetHoehenkote v" *SetHK:version*))
      
      ;; Action: Live-Vorschau wenn Suffix geaendert wird
      (action_tile "layer_suffix"
        "(set_tile \"layer_preview\" (strcat \"Vorschau: \" (getvar \"CLAYER\") \"_\" (get_tile \"layer_suffix\")))"
      )
      
      ;; Action: Durchsuchen-Button fuer BlockImport.lsp
      (action_tile "btn_browse"
        (strcat
          "(progn"
          "  (setq *SetHK:tmp-path*"
          "    (getfiled \"BlockImport.lsp auswaehlen\""
          "      (if (findfile (get_tile \"libpath\"))"
          "        (vl-filename-directory (get_tile \"libpath\"))"
          "        (cond ((getvar \"DWGPREFIX\")) ((getenv \"USERPROFILE\")) (T \"\"))"
          "      )"
          "      \"lsp\" 0))"
          "  (if *SetHK:tmp-path*"
          "    (set_tile \"libpath\" *SetHK:tmp-path*)"
          "  )"
          ")"
        )
      )
      
      ;; Action: Block-Verwaltung Button
      ;; WICHTIG: Werte in globale Vars speichern VOR done_dialog (Sub-Dialog Bug!)
      (action_tile "btn_block"
        (strcat
          "(setq *SetHK:tmp-scale* (get_tile \"scale\"))"
          "(setq *SetHK:tmp-default-scale* (get_tile \"default_scale\"))"
          "(setq *SetHK:tmp-blockname* (get_tile \"blockname\"))"
          "(setq *SetHK:tmp-libpath* (get_tile \"libpath\"))"
          "(setq *SetHK:tmp-debug* (get_tile \"debug\"))"
          "(setq *SetHK:tmp-use-suffix* (get_tile \"use_suffix\"))"
          "(setq *SetHK:tmp-layer-suffix* (get_tile \"layer_suffix\"))"
          "(setq *SetHK:tmp-open-block-mgr* T)"
          "(done_dialog 2)"
        )
      )
      
      ;; Action: OK — Werte in globale Vars speichern VOR done_dialog
      (action_tile "accept"
        (strcat
          "(setq *SetHK:tmp-scale* (get_tile \"scale\"))"
          "(setq *SetHK:tmp-default-scale* (get_tile \"default_scale\"))"
          "(setq *SetHK:tmp-blockname* (get_tile \"blockname\"))"
          "(setq *SetHK:tmp-libpath* (get_tile \"libpath\"))"
          "(setq *SetHK:tmp-debug* (get_tile \"debug\"))"
          "(setq *SetHK:tmp-use-suffix* (get_tile \"use_suffix\"))"
          "(setq *SetHK:tmp-layer-suffix* (get_tile \"layer_suffix\"))"
          "(done_dialog 1)"
        )
      )
      
      ;; Dialog starten
      (setq result (start_dialog))
      
      ;; Dialog ist jetzt geschlossen — Werte aus globalen Vars lesen
      (cond
        ;; OK gedrueckt (result = 1)
        ((= result 1)
          (setq new-scale (atof *SetHK:tmp-scale*))
          (setq new-default-scale (atof *SetHK:tmp-default-scale*))
          (setq new-blockname *SetHK:tmp-blockname*)
          (setq new-libpath *SetHK:tmp-libpath*)
          (setq new-debug (= *SetHK:tmp-debug* "1"))
          
          ;; DWG-Skalierung speichern (nur wenn gueltig und nicht "(nicht gesetzt)")
          (if (> new-scale 0.0)
            (progn
              (SetHK:write-dwg-scale new-scale)
              (SetHK:log-write "INFO" (strcat "DWG-Skalierung: " (rtos new-scale 2 2)))
            )
            ;; Wenn 0 oder ungueltig: nicht aendern
            (if (/= *SetHK:tmp-scale* "(nicht gesetzt)")
              (progn
                (princ "\n*** DWG-Skalierung muss > 0 sein, nicht geaendert ***")
                (SetHK:log-write "WARN" (strcat "Ungueltige DWG-Skalierung: " *SetHK:tmp-scale*))
              )
            )
          )
          
          ;; Default-Skalierung speichern (in Config)
          (if (> new-default-scale 0.0)
            (progn
              (SetHK:save-default-scale new-default-scale)
              (SetHK:log-write "INFO" (strcat "Default-Skalierung: " (rtos new-default-scale 2 2)))
            )
            (progn
              (princ "\n*** Default-Skalierung muss > 0 sein, nicht geaendert ***")
              (SetHK:log-write "WARN" (strcat "Ungueltige Default-Skalierung: " *SetHK:tmp-default-scale*))
            )
          )
          
          ;; Block-Name speichern
          (if (and new-blockname (/= new-blockname ""))
            (progn
              (setq *SetHK:blockname* new-blockname)
              (SetHK:set-config-value "BLOCKNAME" new-blockname)
              (SetHK:log-write "INFO" (strcat "Blockname: " new-blockname))
            )
          )
          
          ;; BlockImport Pfad speichern (nur wenn geaendert und gueltig)
          (if (and new-libpath
                   (/= new-libpath "(nicht konfiguriert)")
                   (/= new-libpath cur-libpath))
            (progn
              (SetHK:set-config-value "BLOCKIMPORT_PATH" new-libpath)
              (SetHK:log-write "INFO" (strcat "BlockImport Pfad: " new-libpath))
            )
          )
          
          ;; Debug-Modus
          (setq *SetHK:debug-mode* new-debug)
          (SetHK:log-write "INFO" (strcat "Debug: " (if new-debug "EIN" "AUS")))
          
          ;; HK-Layer Setting
          (setq new-use-suffix (= *SetHK:tmp-use-suffix* "1"))
          (setq *SetHK:use-layer-suffix* new-use-suffix)
          (SetHK:set-config-value "USE_LAYER_SUFFIX" (if new-use-suffix "1" "0"))
          (SetHK:log-write "INFO" (strcat "HK-Layer: " (if new-use-suffix "aktiv" "deaktiviert")))
          
          ;; Layer-Suffix speichern (nur wenn nicht leer)
          (if (and *SetHK:tmp-layer-suffix* (/= *SetHK:tmp-layer-suffix* ""))
            (progn
              (setq *SetHK:layer-suffix* *SetHK:tmp-layer-suffix*)
              (SetHK:set-config-value "LAYER_SUFFIX" *SetHK:layer-suffix*)
              (SetHK:log-write "INFO" (strcat "Layer-Suffix: _" *SetHK:layer-suffix*))
            )
            (progn
              (princ "\n*** Layer-Suffix darf nicht leer sein, nicht geaendert ***")
              (SetHK:log-write "WARN" "Leeres Layer-Suffix ignoriert")
            )
          )
          
          (princ "\nEinstellungen gespeichert.")
        )
        
        ;; Block-Manager oeffnen (result = 2)
        ((= result 2)
          ;; Zwischenwerte merken (werden nach Block-Manager Dialog wiederhergestellt)
          (SetHK:log-write "INFO" "Block-Verwaltung geoeffnet aus Settings")
          (manage-block-import *SetHK:block-context*)
          ;; Nach Block-Manager: Settings nochmal oeffnen
          (princ "\nBlock-Verwaltung abgeschlossen.")
        )
        
        ;; Abbrechen (result = 0)
        (T
          (SetHK:log-write "INFO" "HKSETTINGS abgebrochen")
          (princ "\nAbgebrochen.")
        )
      )
      
      ;; Aufraeumen
      (unload_dialog dcl-id)
      (vl-file-delete dcl-file)
    )
  )
  
  ;; Temp-Variablen aufraeumen
  (setq *SetHK:tmp-scale* nil)
  (setq *SetHK:tmp-default-scale* nil)
  (setq *SetHK:tmp-blockname* nil)
  (setq *SetHK:tmp-libpath* nil)
  (setq *SetHK:tmp-debug* nil)
  (setq *SetHK:tmp-use-suffix* nil)
  (setq *SetHK:tmp-layer-suffix* nil)
  (setq *SetHK:tmp-path* nil)
  (setq *SetHK:tmp-open-block-mgr* nil)
  
  (SetHK:log-write "INFO" "Befehl HKSETTINGS beendet")
  (princ)
)


;;; ============================================================================
;;; LADE-MELDUNG (NUR PRINC! Kein vl-load-com, kein VLA auf Top-Level!)
;;; ============================================================================

(princ (strcat "\nSetHoehenkote.lsp v" *SetHK:version* " geladen."))
(princ "\nBefehle: SetHK       - Hoehenkote setzen (S fuer Skalierung)")
(princ "\n         HKSETTINGS  - Einstellungen (Skalierung, Block, Pfad, Debug)")
(princ "\n         HKBLOCK     - Block-Verwaltung")
(princ)

;;; Ende der Datei

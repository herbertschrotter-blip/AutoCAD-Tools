;;; ============================================================================
;;; HoeheAufFlaecheManager.lsp
;;; ============================================================================
;;; Oberflaechenmanager fuer Hoeheninterpolation in AutoCAD
;;; Persistente Oberflaechen mit Constrained Delaunay TIN
;;;
;;; Version: 1.0.0
;;; Datum: 2026-03-20
;;; Autor: Herbert Schrotter
;;; Namespace: HAFM (HoeheAufFlaecheManager)
;;;
;;; AppData: %APPDATA%\AutoCAD\Lisp\HoeheAufFlaecheManager\
;;;   - Log:    Log\HoeheAufFlaecheManager_YYYYMMDD_HHMMSS.log
;;;   - Config: Config\HoeheAufFlaecheManager.cfg
;;;   - Backup: Backup\
;;;
;;; Installation:
;;; 1. APPLOAD ausfuehren
;;; 2. HoeheAufFlaecheManager.lsp laden
;;; 3. Optional: BlockImport.lsp im selben Ordner oder Support-Pfad
;;;
;;; Befehle:
;;; HAFNEW      - Neue Oberflaeche erstellen
;;; HAFEDIT     - Oberflaeche bearbeiten
;;; HAFLIST     - Alle Oberflaechen auflisten
;;; HAFDELETE   - Oberflaeche loeschen
;;; HAFMSETTINGS - Einstellungen (DCL)
;;; HAFMDEBUG   - Debug-Modus ein/aus
;;;
;;; Datenstruktur: LandXML-kompatibel
;;;   Quelldaten im DWG Named Object Dictionary (HAF_Surfaces)
;;;   Berechnung immer aus Quelldaten (keine gespeicherten Indizes)
;;;
;;; Abhaengigkeiten:
;;;   BlockImport.lsp (lib/) - Shared Library fuer Block-Import
;;; ============================================================================


;;; ============================================================================
;;; KONFIGURATION (KONSTANTEN)
;;; ============================================================================

(setq *HAFM:version* "1.0.0")
(setq *HAFM:namespace* "HAFM")
(setq *HAFM:appdata-folder* "HoeheAufFlaecheManager")
(setq *HAFM:dict-name* "HAF_Surfaces")  ;; Dictionary-Name in DWG

;;; ============================================================================
;;; GLOBALE VARIABLEN
;;; ============================================================================

(setq *HAFM:initialized* nil)
(setq *HAFM:log-session-id* nil)
(setq *HAFM:debug-mode* nil)
(setq *HAFM:config-cache* nil)
(setq *HAFM:last-height* nil)

;; Skalierung
(setq *HAFM:default-scale* 1)

;; Hoehenkoten-Block
(setq *HAFM:use-layer-suffix* T)       ; Eigener Layer fuer HK-Bloecke
(setq *HAFM:layer-suffix* "HK")        ; Layer-Suffix

;; Linien-Settings: Umrandung (Magenta)
(setq *HAFM:outline-keep* T)
(setq *HAFM:outline-color* 6)
(setq *HAFM:outline-suffix* "UM")
(setq *HAFM:outline-own-layer* nil)
(setq *HAFM:outline-use-layer* nil)

;; Linien-Settings: Bruchlinie (Gelb)
(setq *HAFM:breakline-keep* T)
(setq *HAFM:breakline-color* 2)
(setq *HAFM:breakline-suffix* "BL")
(setq *HAFM:breakline-own-layer* nil)
(setq *HAFM:breakline-use-layer* nil)

;; Linien-Settings: Hoehenlinie (Rot)
(setq *HAFM:contour-keep* nil)
(setq *HAFM:contour-color* 1)
(setq *HAFM:contour-suffix* "HL")
(setq *HAFM:contour-own-layer* nil)
(setq *HAFM:contour-use-layer* nil)

;; Linien-Settings: Hoehenlinienraster (Grau)
(setq *HAFM:grid-keep* nil)
(setq *HAFM:grid-color* 8)
(setq *HAFM:grid-suffix* "HR")
(setq *HAFM:grid-own-layer* nil)
(setq *HAFM:grid-use-layer* nil)
(setq *HAFM:grid-interval* 1.0)

;; Linien-Settings: TIN-Netz (Grau)
(setq *HAFM:tin-keep* nil)
(setq *HAFM:tin-color* 8)
(setq *HAFM:tin-suffix* "TIN")
(setq *HAFM:tin-own-layer* nil)
(setq *HAFM:tin-use-layer* nil)

;; TIN Triangles (fuer aktuelle Berechnung)
(setq *HAFM:tin-triangles* nil)


;;; ============================================================================
;;; APPDATA & LOGGING
;;; ============================================================================

;;; Gibt den AppData-Basisordner zurueck, erstellt Ordnerstruktur
(defun HAFM:get-appdata-path ( / base)
  (setq base (strcat (getenv "APPDATA") "\\AutoCAD\\Lisp\\" *HAFM:appdata-folder*))
  base
)

;;; Stellt sicher dass alle AppData-Unterordner existieren
(defun HAFM:ensure-appdata-dirs ( / base)
  (setq base (HAFM:get-appdata-path))
  (if (not (vl-file-directory-p base))
    (progn
      (vl-mkdir (strcat (getenv "APPDATA") "\\AutoCAD"))
      (vl-mkdir (strcat (getenv "APPDATA") "\\AutoCAD\\Lisp"))
      (vl-mkdir base)
      (vl-mkdir (strcat base "\\Log"))
      (vl-mkdir (strcat base "\\Config"))
      (vl-mkdir (strcat base "\\Backup"))
    )
  )
)

;;; Schreibt eine Zeile ins Session-Log
;;; Crash-safe: open-write-close pro Zeile
(defun HAFM:log-write (level message / appdata log-path fp timestamp)
  ;; Debug nur wenn aktiviert
  (if (and (= level "DEBUG") (not *HAFM:debug-mode*))
    (progn) ; Skip
    (progn
      ;; Session-Log-Pfad ermitteln (einmal pro Session)
      (if (not *HAFM:log-session-id*)
        (progn
          (HAFM:ensure-appdata-dirs)
          (setq *HAFM:log-session-id*
            (strcat *HAFM:appdata-folder* "_"
              (menucmd "M=$(edtime,0,YYYYMMDD_HHMMSS)")
            )
          )
          ;; Log-Rotation beim ersten Schreiben
          (HAFM:log-rotate)
        )
      )
      (setq appdata (HAFM:get-appdata-path))
      (setq log-path (strcat appdata "\\Log\\" *HAFM:log-session-id* ".log"))
      ;; Timestamp
      (setq timestamp (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM:SS)"))
      ;; Schreiben (open-write-close = crash-safe)
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

;;; Kurzform fuer Debug-Logging
(defun HAFM:debug (message / )
  (HAFM:log-write "DEBUG" message)
)

;;; Log-Rotation: max 5 Session-Logs
(defun HAFM:log-rotate ( / appdata log-dir pattern files sorted-files delete-count i)
  (setq appdata (HAFM:get-appdata-path))
  (setq log-dir (strcat appdata "\\Log"))
  (setq pattern (strcat *HAFM:appdata-folder* "_*.log"))
  (setq files nil)
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

;;; Cancel-Detection (DE + EN, wcmatch Pattern)
(defun HAFM:cancel-p (msg)
  (wcmatch (strcase msg)
    "*ABBRUCH*,*ABGEBROCHEN*,*CANCEL*,*QUIT*,*EXIT*"
  )
)


;;; ============================================================================
;;; CONFIG-MANAGEMENT (mit Cache)
;;; ============================================================================

;;; Laedt Config von Datei in Association-Liste
(defun HAFM:load-config ( / cfg-path fp line pos key value result)
  (setq cfg-path (strcat (HAFM:get-appdata-path) "\\Config\\" *HAFM:appdata-folder* ".cfg"))
  (setq result nil)
  (if (findfile cfg-path)
    (progn
      (if (vl-catch-all-error-p
            (setq fp (vl-catch-all-apply 'open (list cfg-path "r"))))
        (progn
          (HAFM:log-write "ERROR" (strcat "Config lesen fehlgeschlagen: " cfg-path))
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
          (HAFM:log-write "INFO" (strcat "Config geladen: " cfg-path))
          result
        )
      )
    )
    (progn
      (HAFM:log-write "WARN" "Keine Config gefunden, verwende Defaults")
      nil
    )
  )
)

;;; Speichert Config auf Datei
(defun HAFM:save-config (config-data / cfg-path fp)
  (HAFM:ensure-appdata-dirs)
  (setq cfg-path (strcat (HAFM:get-appdata-path) "\\Config\\" *HAFM:appdata-folder* ".cfg"))
  (if (vl-catch-all-error-p
        (setq fp (vl-catch-all-apply 'open (list cfg-path "w"))))
    (progn
      (HAFM:log-write "ERROR" (strcat "Config schreiben fehlgeschlagen: " cfg-path))
      nil
    )
    (progn
      (foreach pair config-data
        (write-line (strcat (car pair) "=" (cdr pair)) fp)
      )
      (close fp)
      (HAFM:log-write "INFO" (strcat "Config gespeichert: " cfg-path))
      T
    )
  )
)

;;; Liest einzelnen Wert aus Config-Cache
(defun HAFM:get-config-value (search-key / )
  (if (null *HAFM:config-cache*)
    (setq *HAFM:config-cache* (HAFM:load-config))
  )
  (if *HAFM:config-cache*
    (cdr (assoc search-key *HAFM:config-cache*))
    nil
  )
)

;;; Setzt einzelnen Wert im Config-Cache (schreibt NICHT sofort!)
(defun HAFM:set-config-value (set-key set-value / )
  (if (null *HAFM:config-cache*)
    (setq *HAFM:config-cache* (HAFM:load-config))
  )
  (if (null *HAFM:config-cache*) (setq *HAFM:config-cache* '()))
  (if (assoc set-key *HAFM:config-cache*)
    (setq *HAFM:config-cache* (subst (cons set-key set-value) (assoc set-key *HAFM:config-cache*) *HAFM:config-cache*))
    (setq *HAFM:config-cache* (cons (cons set-key set-value) *HAFM:config-cache*))
  )
)

;;; Schreibt Config-Cache auf Datei
(defun HAFM:flush-config ( / )
  (if *HAFM:config-cache*
    (HAFM:save-config *HAFM:config-cache*)
  )
)

;;; Laedt Config von Datei neu in Cache
(defun HAFM:reload-config ( / )
  (setq *HAFM:config-cache* (HAFM:load-config))
)

;;; Wendet Config-Werte auf globale Variablen an
(defun HAFM:apply-config ( / val)
  (HAFM:reload-config)
  ;; Debug
  (setq val (HAFM:get-config-value "DEBUG"))
  (if val (setq *HAFM:debug-mode* (= val "1")))
  ;; Default-Scale
  (setq val (HAFM:get-config-value "DEFAULT_SCALE"))
  (if (and val (/= val "")) (setq *HAFM:default-scale* (atof val)))
  ;; HK-Layer
  (setq val (HAFM:get-config-value "USE_LAYER_SUFFIX"))
  (if val (setq *HAFM:use-layer-suffix* (= val "1")))
  (setq val (HAFM:get-config-value "LAYER_SUFFIX"))
  (if (and val (/= val "")) (setq *HAFM:layer-suffix* val))
  ;; Umrandung
  (setq val (HAFM:get-config-value "OUTLINE_KEEP"))
  (if val (setq *HAFM:outline-keep* (= val "1")))
  (setq val (HAFM:get-config-value "OUTLINE_COLOR"))
  (if (and val (/= val "")) (setq *HAFM:outline-color* (atoi val)))
  (setq val (HAFM:get-config-value "OUTLINE_SUFFIX"))
  (if (and val (/= val "")) (setq *HAFM:outline-suffix* val))
  (setq val (HAFM:get-config-value "OUTLINE_OWN_LAYER"))
  (if val (setq *HAFM:outline-own-layer* (= val "1")))
  (setq val (HAFM:get-config-value "OUTLINE_USE_LAYER"))
  (if val (setq *HAFM:outline-use-layer* (= val "1")))
  ;; Bruchlinie
  (setq val (HAFM:get-config-value "BREAKLINE_KEEP"))
  (if val (setq *HAFM:breakline-keep* (= val "1")))
  (setq val (HAFM:get-config-value "BREAKLINE_COLOR"))
  (if (and val (/= val "")) (setq *HAFM:breakline-color* (atoi val)))
  (setq val (HAFM:get-config-value "BREAKLINE_SUFFIX"))
  (if (and val (/= val "")) (setq *HAFM:breakline-suffix* val))
  (setq val (HAFM:get-config-value "BREAKLINE_OWN_LAYER"))
  (if val (setq *HAFM:breakline-own-layer* (= val "1")))
  (setq val (HAFM:get-config-value "BREAKLINE_USE_LAYER"))
  (if val (setq *HAFM:breakline-use-layer* (= val "1")))
  ;; Hoehenlinie
  (setq val (HAFM:get-config-value "CONTOUR_KEEP"))
  (if val (setq *HAFM:contour-keep* (= val "1")))
  (setq val (HAFM:get-config-value "CONTOUR_COLOR"))
  (if (and val (/= val "")) (setq *HAFM:contour-color* (atoi val)))
  (setq val (HAFM:get-config-value "CONTOUR_SUFFIX"))
  (if (and val (/= val "")) (setq *HAFM:contour-suffix* val))
  (setq val (HAFM:get-config-value "CONTOUR_OWN_LAYER"))
  (if val (setq *HAFM:contour-own-layer* (= val "1")))
  (setq val (HAFM:get-config-value "CONTOUR_USE_LAYER"))
  (if val (setq *HAFM:contour-use-layer* (= val "1")))
  ;; Raster
  (setq val (HAFM:get-config-value "GRID_KEEP"))
  (if val (setq *HAFM:grid-keep* (= val "1")))
  (setq val (HAFM:get-config-value "GRID_COLOR"))
  (if (and val (/= val "")) (setq *HAFM:grid-color* (atoi val)))
  (setq val (HAFM:get-config-value "GRID_SUFFIX"))
  (if (and val (/= val "")) (setq *HAFM:grid-suffix* val))
  (setq val (HAFM:get-config-value "GRID_OWN_LAYER"))
  (if val (setq *HAFM:grid-own-layer* (= val "1")))
  (setq val (HAFM:get-config-value "GRID_USE_LAYER"))
  (if val (setq *HAFM:grid-use-layer* (= val "1")))
  (setq val (HAFM:get-config-value "GRID_INTERVAL"))
  (if (and val (/= val "")) (setq *HAFM:grid-interval* (atof val)))
  ;; TIN
  (setq val (HAFM:get-config-value "TIN_KEEP"))
  (if val (setq *HAFM:tin-keep* (= val "1")))
  (setq val (HAFM:get-config-value "TIN_COLOR"))
  (if (and val (/= val "")) (setq *HAFM:tin-color* (atoi val)))
  (setq val (HAFM:get-config-value "TIN_SUFFIX"))
  (if (and val (/= val "")) (setq *HAFM:tin-suffix* val))
  (setq val (HAFM:get-config-value "TIN_OWN_LAYER"))
  (if val (setq *HAFM:tin-own-layer* (= val "1")))
  (setq val (HAFM:get-config-value "TIN_USE_LAYER"))
  (if val (setq *HAFM:tin-use-layer* (= val "1")))
  ;; Log
  (HAFM:log-write "INFO" (strcat "Config angewendet: Debug=" (if *HAFM:debug-mode* "EIN" "AUS")))
)


;;; ============================================================================
;;; BLOCKIMPORT LIBRARY LADEN
;;; ============================================================================

;;; Sucht und laedt BlockImport.lsp (3-Fallback Pfadaufloesung)
(defun HAFM:load-blockimport ( / path cfg-path)
  (HAFM:log-write "INFO" "BlockImport.lsp wird gesucht...")
  ;; Fallback 1: Aus Config
  (setq cfg-path (HAFM:get-config-value "BLOCKIMPORT_PATH"))
  (if (and cfg-path (findfile cfg-path))
    (setq path cfg-path)
  )
  ;; Fallback 2: findfile (AutoCAD Support-Pfade)
  (if (not path) (setq path (findfile "BlockImport.lsp")))
  ;; Fallback 3: lib/ Unterordner relativ zum Script
  (if (not path) (setq path (findfile "lib/BlockImport.lsp")))
  ;; Fallback 4: Dialog
  (if (not path)
    (progn
      (HAFM:log-write "WARN" "BlockImport.lsp nicht in Standard-Pfaden gefunden")
      (setq path (getfiled "BlockImport.lsp waehlen" "" "lsp" 0))
    )
  )
  ;; Laden
  (if path
    (progn
      (load path)
      (HAFM:set-config-value "BLOCKIMPORT_PATH" path)
      (HAFM:flush-config)
      (HAFM:log-write "INFO" (strcat "Library geladen: " path))
      T
    )
    (progn
      (HAFM:log-write "ERROR" "BlockImport.lsp konnte nicht geladen werden!")
      (alert "FEHLER: BlockImport.lsp nicht gefunden!\nHAFM kann ohne BlockImport.lsp nicht arbeiten.")
      nil
    )
  )
)


;;; ============================================================================
;;; LAZY-INIT (CRITICAL bei DokaCAD!)
;;; ============================================================================

;;; Initialisierung beim ersten Befehlsaufruf
(defun HAFM:ensure-init ( / )
  (if (not *HAFM:initialized*)
    (progn
      (HAFM:log-write "INFO" "Lazy-Init gestartet...")
      ;; VLA laden
      (vl-load-com)
      (HAFM:log-write "INFO" "vl-load-com geladen")
      ;; Config laden und anwenden
      (HAFM:apply-config)
      ;; BlockImport.lsp laden
      (HAFM:load-blockimport)
      ;; Fertig
      (setq *HAFM:initialized* T)
      (HAFM:log-write "INFO" (strcat "=== HoeheAufFlaecheManager v" *HAFM:version* " initialisiert ==="))
    )
  )
)


;;; ============================================================================
;;; SURFACE DICTIONARY (Persistente Speicherung in DWG)
;;; ============================================================================

;;; Speichert eine Oberflaeche im Dictionary
;;; Parameter:
;;;   name - Name der Oberflaeche (String)
;;;   surface-data - Association-Liste:
;;;     ("BOUNDARY"        . ((x y h) (x y h) ...))
;;;     ("BREAKLINES"      . (((x y h)(x y h)...) ...))
;;;     ("INNER_PTS"       . ((x y h) (x y h) ...))
;;;     ("HOLES"           . (((x y)(x y)...) ...))
;;;     ("SETTINGS"        . ((key . value) ...))
;;;     ("ENTITY_HANDLES"  . ("1A2B" "1A2C" ...))
(defun HAFM:save-surface (name surface-data / )
  (vlax-ldata-put *HAFM:dict-name* name surface-data)
  (HAFM:log-write "INFO" (strcat "Surface gespeichert: " name
    " (" (itoa (length (cdr (assoc "BOUNDARY" surface-data)))) " Boundary"
    ", " (itoa (length (cdr (assoc "INNER_PTS" surface-data)))) " innere"
    ", " (itoa (length (cdr (assoc "BREAKLINES" surface-data)))) " BK"
    ", " (itoa (length (cdr (assoc "HOLES" surface-data)))) " Loecher)"))
  T
)

;;; Laedt eine Oberflaeche aus dem Dictionary
(defun HAFM:load-surface (name / data)
  (setq data (vlax-ldata-get *HAFM:dict-name* name))
  (if data
    (progn
      (HAFM:log-write "INFO" (strcat "Surface geladen: " name))
      data
    )
    (progn
      (HAFM:debug (strcat "Surface nicht gefunden: " name))
      nil
    )
  )
)

;;; Loescht eine Oberflaeche (Entities + Dictionary-Eintrag)
(defun HAFM:delete-surface (name / data handles ent)
  (setq data (HAFM:load-surface name))
  (if data
    (progn
      ;; Entities loeschen
      (setq handles (cdr (assoc "ENTITY_HANDLES" data)))
      (if handles
        (foreach h handles
          (setq ent (handent h))
          (if (and ent (entget ent))
            (entdel ent)
          )
        )
      )
      ;; Dictionary-Eintrag entfernen
      (vlax-ldata-delete *HAFM:dict-name* name)
      (HAFM:log-write "INFO" (strcat "Surface geloescht: " name))
      T
    )
    nil
  )
)

;;; Listet alle Oberflaechennamen
;;; vlax-ldata-list gibt ((key . value) ...) zurueck
;;; Wir brauchen nur die Keys (Namen)
(defun HAFM:list-surfaces ( / raw)
  (setq raw (vlax-ldata-list *HAFM:dict-name*))
  (if raw
    (mapcar 'car raw)
    nil
  )
)

;;; Loescht alle Entities einer Oberflaeche per Handles
(defun HAFM:delete-surface-entities (surface-data / handles ent count)
  (setq handles (cdr (assoc "ENTITY_HANDLES" surface-data)))
  (setq count 0)
  (if handles
    (foreach h handles
      (setq ent (handent h))
      (if (and ent (entget ent))
        (progn (entdel ent) (setq count (1+ count)))
      )
    )
  )
  (HAFM:log-write "INFO" (strcat "Entities geloescht: " (itoa count) " von " (itoa (length handles))))
)

;;; Sammelt Entity-Handles aus Entity-Name-Liste
(defun HAFM:collect-handles (entities / result h)
  (setq result nil)
  (foreach ent entities
    (if (and ent (entget ent))
      (progn
        (setq h (cdr (assoc 5 (entget ent))))
        (if h (setq result (cons h result)))
      )
    )
  )
  (reverse result)
)


;;; ============================================================================
;;; TIN DATENAUFBAU (aus separaten Quell-Listen)
;;; ============================================================================

;;; Baut Punkte + Constraints aus separaten Listen zusammen
;;; Indizes werden JETZT berechnet, nie gespeichert
;;; Parameter:
;;;   boundary-pts - Umrandungspunkte
;;;   breaklines - Liste von Bruchkanten
;;;   inner-pts - Innere Punkte
;;; Rueckgabe: (all-pts num-boundary extra-constraints)
(defun HAFM:build-tin-data (boundary-pts breaklines inner-pts
                            / all-pts num-boundary extra-constraints
                              bl bl-start i bl-len)
  (setq all-pts boundary-pts)
  (setq num-boundary (length boundary-pts))
  (setq extra-constraints nil)
  ;; Bruchkanten-Punkte + Constraints
  (foreach bl breaklines
    (setq bl-start (length all-pts))
    (setq bl-len (length bl))
    (foreach pt bl
      (setq all-pts (append all-pts (list pt)))
    )
    (setq i 0)
    (while (< i (1- bl-len))
      (setq extra-constraints
        (append extra-constraints
          (list (list (+ bl-start i) (+ bl-start i 1)))))
      (setq i (1+ i))
    )
  )
  ;; Innere Punkte (keine Constraints)
  (foreach pt inner-pts
    (setq all-pts (append all-pts (list pt)))
  )
  (HAFM:log-write "INFO" (strcat "build-tin-data: " (itoa (length all-pts)) " Punkte ("
                                 (itoa num-boundary) " Boundary, "
                                 (itoa (length extra-constraints)) " Constraints)"))
  (list all-pts num-boundary extra-constraints)
)

;;; Berechnet TIN komplett neu aus Quelldaten
;;; Parameter: surface-data - Association-Liste (aus Dictionary)
;;; Rueckgabe: (all-pts triangles num-boundary) oder nil
(defun HAFM:rebuild-tin (surface-data / boundary breaklines inner-pts holes
                                        tin-data all-pts num-boundary extra-constraints
                                        triangles)
  (setq boundary   (cdr (assoc "BOUNDARY"   surface-data)))
  (setq breaklines (cdr (assoc "BREAKLINES" surface-data)))
  (setq inner-pts  (cdr (assoc "INNER_PTS"  surface-data)))
  (setq holes      (cdr (assoc "HOLES"      surface-data)))
  (if (< (length boundary) 3)
    (progn
      (HAFM:log-write "ERROR" "rebuild-tin: weniger als 3 Boundary-Punkte")
      nil
    )
    (progn
      (setq tin-data (HAFM:build-tin-data boundary breaklines inner-pts))
      (setq all-pts (car tin-data))
      (setq num-boundary (cadr tin-data))
      (setq extra-constraints (caddr tin-data))
      ;; Constrained Delaunay
      (setq triangles
        (HAFM:constrained-delaunay all-pts num-boundary extra-constraints))
      ;; Loecher ausschneiden
      (if (and holes triangles)
        (foreach hole holes
          (setq triangles
            (HAFM:remove-hole-triangles triangles all-pts hole))
        )
      )
      (if triangles
        (progn
          (HAFM:log-write "INFO" (strcat "rebuild-tin: " (itoa (length triangles)) " Dreiecke"))
          (list all-pts triangles num-boundary)
        )
        (progn
          (HAFM:log-write "ERROR" "rebuild-tin: Triangulation fehlgeschlagen")
          nil
        )
      )
    )
  )
)

;;; Entfernt Dreiecke in Loch-Bereich
(defun HAFM:remove-hole-triangles (triangles pts hole / result cx cy)
  (setq result nil)
  (foreach tri triangles
    (setq cx (/ (+ (car (nth (car tri) pts))
                   (car (nth (cadr tri) pts))
                   (car (nth (caddr tri) pts))) 3.0))
    (setq cy (/ (+ (cadr (nth (car tri) pts))
                   (cadr (nth (cadr tri) pts))
                   (cadr (nth (caddr tri) pts))) 3.0))
    (if (not (HAFM:point-in-polygon (list cx cy) hole))
      (setq result (cons tri result))
    )
  )
  (HAFM:log-write "INFO" (strcat "Hole: " (itoa (- (length triangles) (length result))) " Dreiecke entfernt"))
  result
)


;;; ============================================================================
;;; HILFSFUNKTIONEN
;;; ============================================================================

;;; Gibt den Namen einer ACI-Farbe zurueck
(defun HAFM:color-name (aci / )
  (cond
    ((= aci 1) "Rot")
    ((= aci 2) "Gelb")
    ((= aci 3) "Gruen")
    ((= aci 4) "Cyan")
    ((= aci 5) "Blau")
    ((= aci 6) "Magenta")
    ((= aci 7) "Weiss")
    ((= aci 8) "Grau")
    (T (strcat "Farbe " (itoa aci)))
  )
)

;;; Entfernt Element an Index n aus Liste (0-basiert)
(defun HAFM:remove-nth (lst n / result i)
  (setq result nil i 0)
  (foreach item lst
    (if (/= i n) (setq result (append result (list item))))
    (setq i (1+ i))
  )
  result
)

;;; Ersetzt Element an Index n in Liste (0-basiert)
(defun HAFM:replace-nth (lst n new-val / result i)
  (setq result nil i 0)
  (foreach item lst
    (if (= i n)
      (setq result (append result (list new-val)))
      (setq result (append result (list item)))
    )
    (setq i (1+ i))
  )
  result
)

;;; Formatiert Hoehe als String mit + Vorzeichen und 2 Dezimalstellen
(defun HAFM:format-height (h / )
  (strcat "+" (rtos h 2 2))
)

;;; Stellt sicher dass 3 Dezimalstellen im HOEHE-Attribut stehen
(defun HAFM:ensure-three-decimals (val / str pos dec-len)
  (setq str (rtos val 2 3))
  str
)

;;; Formatiert Hoehenwert fuer Block-Attribut (3 Dezimalstellen, kein +)
(defun HAFM:format-height-value (h / )
  (rtos h 2 3)
)

;;; Prueft ob ein Punkt gueltig ist (Liste mit min. 2 Zahlen)
(defun HAFM:valid-point-p (pt / )
  (and pt (listp pt) (>= (length pt) 2)
       (numberp (car pt)) (numberp (cadr pt)))
)

;;; Prueft ob eine Hoehe gueltig ist (Zahl)
(defun HAFM:valid-height-p (h / )
  (and h (numberp h))
)

;;; Fragt Hoehe ab mit Default-Wert
(defun HAFM:get-validated-height (prompt default-h / h)
  (if default-h
    (setq h (getreal (strcat prompt " <" (rtos default-h 2 2) ">: ")))
    (setq h (getreal (strcat prompt ": ")))
  )
  (if (null h) (setq h default-h))
  (if (HAFM:valid-height-p h) h nil)
)

;;; Erstellt Layer mit Suffix (kopiert Eigenschaften vom aktuellen Layer)
(defun HAFM:ensure-line-layer (suffix / cur-layer new-layer tbldata)
  (setq cur-layer (getvar "CLAYER"))
  (setq new-layer (strcat cur-layer "_" suffix))
  (if (not (tblsearch "LAYER" new-layer))
    (progn
      (setq tbldata (entget (tblobjname "LAYER" cur-layer)))
      (entmake
        (list '(0 . "LAYER") (cons 2 new-layer)
              (assoc 6 tbldata) (assoc 62 tbldata) '(70 . 0)))
      (HAFM:log-write "INFO" (strcat "Line-Layer erstellt: " new-layer))
    )
  )
  new-layer
)

;;; Erstellt HK-Layer mit Suffix (kopiert VLA-Eigenschaften)
(defun HAFM:ensure-hk-layer (suffix / cur-layer new-layer tbldata)
  (setq cur-layer (getvar "CLAYER"))
  (setq new-layer (strcat cur-layer "_" suffix))
  (if (not (tblsearch "LAYER" new-layer))
    (progn
      (setq tbldata (entget (tblobjname "LAYER" cur-layer)))
      (entmake
        (list '(0 . "LAYER") (cons 2 new-layer)
              (assoc 6 tbldata) (assoc 62 tbldata) '(70 . 0)))
      (HAFM:log-write "INFO" (strcat "Layer erstellt: " new-layer " (kopiert von " cur-layer ")"))
    )
  )
  new-layer
)

;;; Finalisiert eine Linie: Layer zuweisen + ByLayer setzen
(defun HAFM:finalize-line (ent own-layer use-layer suffix / layer-name ent-data)
  (if (and ent own-layer)
    (progn
      (setq layer-name (HAFM:ensure-line-layer suffix))
      (if layer-name
        (progn
          (setq ent-data (entget ent))
          (entmod (subst (cons 8 layer-name) (assoc 8 ent-data) ent-data))
          (if use-layer
            (progn
              (setq ent-data (entget ent))
              (if (assoc 62 ent-data)
                (entmod (subst (cons 62 256) (assoc 62 ent-data) ent-data))
              )
            )
          )
        )
      )
    )
  )
)

;;; Zeichnet geschlossene Umrandung als 3D-Polylinie (command-basiert)
;;; command "_3DPOLY" erzeugt eine einzelne Entity die sauber loeschbar ist
;;; Rueckgabe: Entity-Name der Polylinie
(defun HAFM:draw-outline (pts heights / i pt h ent ent-data)
  (if (>= (length pts) 2)
    (progn
      (command "_3DPOLY")
      (setq i 0)
      (while (< i (length pts))
        (setq pt (nth i pts))
        (setq h (nth i heights))
        (command (list (car pt) (cadr pt) h))
        (setq i (1+ i))
      )
      ;; Schliessen: zurueck zum ersten Punkt
      (setq pt (nth 0 pts))
      (setq h (nth 0 heights))
      (command (list (car pt) (cadr pt) h))
      (command "")
      (setq ent (entlast))
      ;; Farbe setzen
      (if ent
        (progn
          (setq ent-data (entget ent))
          (if (assoc 62 ent-data)
            (entmod (subst (cons 62 *HAFM:outline-color*) (assoc 62 ent-data) ent-data))
            (entmod (append ent-data (list (cons 62 *HAFM:outline-color*))))
          )
          (setq ent (cdr (assoc -1 ent-data)))
        )
      )
      ent
    )
    nil
  )
)

;;; Loescht alte Umrandung und zeichnet neu (fuer Live-Update)
(defun HAFM:update-outline (old-ent pts heights / new-ent)
  (if (and old-ent (entget old-ent))
    (entdel old-ent)
  )
  (if (>= (length pts) 2)
    (progn
      (setq new-ent (HAFM:draw-outline pts heights))
      new-ent
    )
    nil
  )
)

;;; Prueft ob an einer Position ein HK-Block liegt und liest seine Hoehe
;;; Rueckgabe: (pt height T) wenn Block gefunden, (pt nil nil) sonst
(defun HAFM:pick-or-place (prompt scale / pt ent ss ent-data block-name height attrib-ent attrib-data)
  (setq pt (getpoint prompt))
  (if (and pt (listp pt))
    (progn
      ;; Prüfe ob an dieser Stelle ein HK-Block liegt
      (setq ss (ssget "_C"
        (list (- (car pt) (* 0.5 scale)) (- (cadr pt) (* 0.5 scale)))
        (list (+ (car pt) (* 0.5 scale)) (+ (cadr pt) (* 0.5 scale)))
        '((0 . "INSERT"))))
      (if (and ss (> (sslength ss) 0))
        (progn
          (setq ent (ssname ss 0))
          (setq ent-data (entget ent))
          (setq block-name (cdr (assoc 2 ent-data)))
          ;; Ist es ein Hoehenkoten-Block?
          (if (wcmatch (strcase block-name) "*HOEHENKOTE*,*HK*,*BLK_H*")
            (progn
              ;; HOEHE-Attribut lesen
              (setq height nil)
              (setq attrib-ent (entnext ent))
              (while (and attrib-ent (not height))
                (setq attrib-data (entget attrib-ent))
                (if (and (= (cdr (assoc 0 attrib-data)) "ATTRIB")
                         (wcmatch (strcase (cdr (assoc 2 attrib-data))) "HOEHE,HÖHE,HEIGHT,H"))
                  (setq height (atof (cdr (assoc 1 attrib-data))))
                )
                (setq attrib-ent (entnext attrib-ent))
              )
              (if height
                (progn
                  (princ (strcat "\n  Block erkannt: " (HAFM:format-height height)))
                  (list (cdr (assoc 10 ent-data)) height T)  ;; Position aus Block, nicht aus Klick
                )
                (list pt nil nil)
              )
            )
            (list pt nil nil)
          )
        )
        (list pt nil nil)
      )
    )
    pt  ;; Keyword zurueckgeben (String)
  )
)


;;; ============================================================================
;;; BLOCK INSERT (nutzt BlockImport.lsp API)
;;; ============================================================================

;;; Prueft ob an Position bereits ein Block mit gleicher Hoehe existiert
;;; Verhindert Duplikate bei Eckpunkten
(defun HAFM:block-exists-at-position (pt height blockname / ss i ent inspt pt-wcs
                                       tolerance-xy tolerance-z dist-xy dist-z found)
  (setq tolerance-xy 0.05)
  (setq tolerance-z 0.001)
  (setq found nil)
  ;; getpoint gibt BKS, Block-Einfuegepunkte (DXF 10) sind WKS
  (setq pt-wcs (trans pt 1 0))
  (setq ss (ssget "_X" (list (cons 0 "INSERT") (cons 2 blockname))))
  (if ss
    (progn
      (setq i 0)
      (while (and (< i (sslength ss)) (not found))
        (setq ent (ssname ss i))
        (setq inspt (cdr (assoc 10 (entget ent))))
        (setq dist-xy (distance (list (car pt-wcs) (cadr pt-wcs))
                                (list (car inspt) (cadr inspt))))
        (setq dist-z (abs (- height (caddr inspt))))
        (if (and (< dist-xy tolerance-xy) (< dist-z tolerance-z))
          (setq found T)
        )
        (setq i (1+ i))
      )
      (setq ss nil)
      found
    )
    nil
  )
)

;;; Fuegt HK-Block ein an Punkt mit Hoehe
;;; Nutzt BlockImport API: BLI:resolve-blockname + ensure-block-available
;;; Parameter:
;;;   einfuegepunkt - (x y z) oder (x y)
;;;   hoehe - Hoehenwert (Real)
;;;   scale - XY-Skalierung
;;;   skip-if-exists - T = Duplikat-Pruefung
;;; Rueckgabe: Entity-Name des eingefuegten Blocks oder nil
(defun HAFM:insert-block (einfuegepunkt hoehe scale skip-if-exists
                           / blockName heightStr intPart decPart height2DecStr
                             old-attdia block-available importEnt ent attribs
                             insertionPoint hk-layer ent-data)
  ;; Blockname aus BlockImport (DWG Property → Globaler Standard)
  (setq *block-import-context* "HAFM")
  (setq blockName (BLI:resolve-blockname "HAFM"))
  ;; Wenn kein Block konfiguriert: Block-Manager automatisch oeffnen
  (if (null blockName)
    (progn
      (HAFM:log-write "WARN" "Kein Block konfiguriert - oeffne Block-Verwaltung")
      (princ "\n*** Kein Block konfiguriert! Block-Verwaltung wird geoeffnet... ***")
      (manage-block-import "HAFM")
      (setq blockName (BLI:resolve-blockname "HAFM"))
    )
  )
  
  (if (and (HAFM:valid-point-p einfuegepunkt) (HAFM:valid-height-p hoehe) scale blockName)
    (progn
      ;; Duplikat-Pruefung
      (if (and skip-if-exists (HAFM:block-exists-at-position einfuegepunkt hoehe blockName))
        (progn
          (HAFM:debug "Block existiert bereits - UEBERSPRUNGEN")
          nil
        )
        (progn
          ;; Block verfuegbar machen (BlockImport API)
          (setq block-available (ensure-block-available blockName))
          
          (if (car block-available)
            (progn
              (setq importEnt (cadr block-available))
              
              ;; Hoehe als String mit genau 3 Dezimalstellen
              (setq heightStr (HAFM:ensure-three-decimals hoehe))
              
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
              
              ;; HK-Layer VOR dem Einfuegen erstellen
              (if *HAFM:use-layer-suffix*
                (setq hk-layer (HAFM:ensure-hk-layer *HAFM:layer-suffix*))
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
              
              ;; Block auf Hoehe verschieben
              (setq insertionPoint (cdr (assoc 10 (entget ent))))
              (command "_move" ent "" "_non" insertionPoint "_non"
                       (list (car insertionPoint) (cadr insertionPoint) hoehe))
              
              ;; HK-Layer zuweisen
              (if (and *HAFM:use-layer-suffix* hk-layer)
                (progn
                  (setq ent-data (entget ent))
                  (entmod (subst (cons 8 hk-layer) (assoc 8 ent-data) ent-data))
                )
              )
              
              ;; Import-Block entfernen
              (if importEnt (entdel importEnt))
              
              (HAFM:log-write "INFO" (strcat "Block gesetzt: " height2DecStr
                                              " Z=" (rtos hoehe 2 3)
                                              " Scale=" (rtos scale 2 2)))
              (princ (strcat "\n  Hoehenkote: " height2DecStr
                            " | Z=" (rtos hoehe 2 3)))
              ent
            )
            (progn
              (HAFM:log-write "ERROR" "ensure-block-available fehlgeschlagen")
              (princ "\n*** FEHLER: Block konnte nicht geladen werden ***")
              nil
            )
          )
        )
      )
    )
    (progn
      (if (null blockName)
        (HAFM:log-write "ERROR" "Kein Block konfiguriert")
        (HAFM:log-write "ERROR" "Ungueltige Parameter fuer insert-block")
      )
      nil
    )
  )
)


;;; ============================================================================
;;; MATHEMATIK-KERN
;;; Interpolation, Delaunay, Constrained Delaunay, Contour Lines, Grid
;;; (portiert von HoeheAufFlaeche.lsp v3.5.0, Namespace HAF: → HAFM:)
;;; ============================================================================

(defun HAFM:interpolate-plane (pts heights pg
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
      (HAFM:log-write "ERROR" "interpolate-plane: Punkte sind kollinear oder Ebene vertikal")
      nil
    )
    (progn
      (setq d (+ (* a (car p1)) (* b (cadr p1)) (* c h1)))
      (setq z (/ (- d (* a (car pg)) (* b (cadr pg))) c))
      (HAFM:debug (strcat "interpolate-plane: z=" (rtos z 2 4)))
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
(defun HAFM:barycentric (p1 p2 p3 pg
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
(defun HAFM:point-in-triangle-p (bary)
  (and (>= (car bary) 0.0) (>= (cadr bary) 0.0) (>= (caddr bary) 0.0))
)

;;; Berechnet Hoehe in Dreieck mit baryzentrischen Koordinaten
;;; u->p1/h1, w->p2/h2, v->p3/h3 (wegen Vektordefinition)
(defun HAFM:height-in-triangle (p1 h1 p2 h2 p3 h3 pg / bary u v w)
  (setq bary (HAFM:barycentric p1 p2 p3 pg))
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
(defun HAFM:classify-quad (h1 h2 h3 h4
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
  (HAFM:debug (strcat "classify-quad: h=(" (rtos h1 2 2) " " (rtos h2 2 2) " "
                     (rtos h3 2 2) " " (rtos h4 2 2) ") min=" (rtos minv 2 2)
                     " max=" (rtos maxv 2 2) " mincount=" (itoa mincount)
                     " maxcount=" (itoa maxcount)))
  (cond
    ;; Alle gleich → FLACH
    ((and (< (abs (- h1 h2)) eps) (< (abs (- h1 h3)) eps) (< (abs (- h1 h4)) eps))
     (HAFM:debug "  -> flat")
     (list "flat"))
    ;; Genau EIN Minimum → MULDE
    ((= mincount 1)
     (HAFM:debug (strcat "  -> mulde an Punkt " (itoa min-idx)))
     (list "mulde" min-idx))
    ;; Genau EIN Maximum → KUPPE
    ((= maxcount 1)
     (HAFM:debug (strcat "  -> kuppe an Punkt " (itoa max-idx)))
     (list "kuppe" max-idx))
    ;; Gegenueberliegende Paare gleich → SATTEL
    ((and (< (abs (- h1 h3)) eps) (< (abs (- h2 h4)) eps) (>= (abs (- h1 h2)) eps))
     (HAFM:debug "  -> sattel")
     (list "sattel"))
    ;; Unklar
    (T
     (HAFM:debug "  -> ambiguous")
     (list "ambiguous"))
  )
)

;;; Bestimmt welche Diagonale verwendet werden soll
;;; Verwendet hydrologische Klassifikation
;;;
;;; Rueckgabe: "13" (p1-p3) oder "24" (p2-p4) oder "USER" (Sattel)
(defun HAFM:determine-diagonal (h1 h2 h3 h4
                               / classification class-type class-idx diff-13 diff-24)
  (setq classification (HAFM:classify-quad h1 h2 h3 h4))
  (setq class-type (car classification))
  (setq class-idx (cadr classification))
  (cond
    ;; FLACH → egal
    ((= class-type "flat")
     (HAFM:log-write "INFO" "Diagonale: flat -> 13")
     (princ "\n  Flaeche eben - verwende Diagonale 1-3")
     "13")
    ;; MULDE → Diagonale DURCH den tiefsten Punkt
    ((= class-type "mulde")
     (HAFM:log-write "INFO" (strcat "Diagonale: mulde Punkt " (itoa class-idx)))
     (princ (strcat "\n  Mulde an Punkt " (itoa class-idx)))
     (if (or (= class-idx 1) (= class-idx 3)) "13" "24"))
    ;; KUPPE → Diagonale DURCH den hoechsten Punkt
    ((= class-type "kuppe")
     (HAFM:log-write "INFO" (strcat "Diagonale: kuppe Punkt " (itoa class-idx)))
     (princ (strcat "\n  Kuppe an Punkt " (itoa class-idx)))
     (if (or (= class-idx 1) (= class-idx 3)) "13" "24"))
    ;; SATTEL → User muss entscheiden (Bruchlinie)
    ((= class-type "sattel")
     (HAFM:log-write "INFO" "Diagonale: sattel -> USER")
     (princ "\n  Sattelflaeche erkannt - bitte Bruchlinie definieren")
     "USER")
    ;; UNKLAR → kleinere Hoehendifferenz
    ((= class-type "ambiguous")
     (setq diff-13 (abs (- h1 h3)))
     (setq diff-24 (abs (- h2 h4)))
     (if (< diff-13 diff-24)
       (progn
         (HAFM:log-write "INFO" "Diagonale: ambiguous -> 13 (kleinere Diff)")
         (princ "\n  Unklare Geometrie - waehle Diagonale 1-3")
         "13")
       (progn
         (HAFM:log-write "INFO" "Diagonale: ambiguous -> 24 (kleinere Diff)")
         (princ "\n  Unklare Geometrie - waehle Diagonale 2-4")
         "24")
     ))
    ;; Fallback
    (T
     (HAFM:log-write "WARN" "Diagonale: Fallback -> 13")
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
(defun HAFM:interpolate-triangulation (pts heights pg diagonal
                                      / p1 p2 p3 p4 h1 h2 h3 h4
                                        bary inside height tri-info)
  (setq p1 (nth 0 pts) p2 (nth 1 pts) p3 (nth 2 pts) p4 (nth 3 pts))
  (setq h1 (nth 0 heights) h2 (nth 1 heights) h3 (nth 2 heights) h4 (nth 3 heights))
  (if (= diagonal "13")
    ;; Diagonale 1-3: Dreiecke 1-2-3 und 1-3-4
    (progn
      (setq bary (HAFM:barycentric p1 p2 p3 pg))
      (setq inside (HAFM:point-in-triangle-p bary))
      (if inside
        (progn
          (setq height (HAFM:height-in-triangle p1 h1 p2 h2 p3 h3 pg))
          (setq tri-info "Dreieck 1-2-3"))
        (progn
          (setq height (HAFM:height-in-triangle p1 h1 p3 h3 p4 h4 pg))
          (setq tri-info "Dreieck 1-3-4"))
      )
    )
    ;; Diagonale 2-4: Dreiecke 1-2-4 und 2-3-4
    (progn
      (setq bary (HAFM:barycentric p1 p2 p4 pg))
      (setq inside (HAFM:point-in-triangle-p bary))
      (if inside
        (progn
          (setq height (HAFM:height-in-triangle p1 h1 p2 h2 p4 h4 pg))
          (setq tri-info "Dreieck 1-2-4"))
        (progn
          (setq height (HAFM:height-in-triangle p2 h2 p3 h3 p4 h4 pg))
          (setq tri-info "Dreieck 2-3-4"))
      )
    )
  )
  (if height
    (progn
      (HAFM:debug (strcat "interpolate-triangulation: " tri-info " h=" (rtos height 2 4)))
      (list height tri-info)
    )
    nil
  )
)

;;; ============================================================================
;;; DELAUNAY TRIANGULATION (Bowyer-Watson Algorithmus)
;;; ============================================================================

;;; Datenstruktur fuer Dreiecke:
;;;   Ein Dreieck = Liste von 3 Punkt-Indizes (i j k)
;;;   Punkte werden als separate Liste verwaltet: ((x y h) (x y h) ...)
;;;   Index 0-basiert

;;; Berechnet Umkreis (Circumcircle) eines Dreiecks
;;; Parameter: pa pb pc - drei Punkte (x y)
;;; Rueckgabe: (cx cy r^2) - Mittelpunkt + Radius-Quadrat, oder nil
(defun HAFM:circumcircle (pa pb pc
                         / ax ay bx by cx cy d ux uy rsq)
  (setq ax (car pa) ay (cadr pa))
  (setq bx (car pb) by (cadr pb))
  (setq cx (car pc) cy (cadr pc))
  ;; Determinante (2x Flaeche des Dreiecks)
  (setq d (* 2.0 (+ (* ax (- by cy))
                     (* bx (- cy ay))
                     (* cx (- ay by)))))
  ;; Kollineare Punkte → kein Umkreis
  (if (< (abs d) 1e-10)
    nil
    (progn
      ;; Umkreis-Mittelpunkt
      (setq ux (/ (+ (* (+ (* ax ax) (* ay ay)) (- by cy))
                     (* (+ (* bx bx) (* by by)) (- cy ay))
                     (* (+ (* cx cx) (* cy cy)) (- ay by)))
                  d))
      (setq uy (/ (+ (* (+ (* ax ax) (* ay ay)) (- cx bx))
                     (* (+ (* bx bx) (* by by)) (- ax cx))
                     (* (+ (* cx cx) (* cy cy)) (- bx ax)))
                  d))
      ;; Radius-Quadrat (kein sqrt noetig fuer Vergleich)
      (setq rsq (+ (* (- ax ux) (- ax ux))
                    (* (- ay uy) (- ay uy))))
      (list ux uy rsq)
    )
  )
)

;;; Prueft ob Punkt im Umkreis eines Dreiecks liegt
;;; Parameter: pt - Punkt (x y), circle - (cx cy r^2)
;;; Rueckgabe: T wenn innerhalb (inkl. Rand), nil wenn ausserhalb
(defun HAFM:point-in-circumcircle (pt circle / dx dy dist-sq)
  (setq dx (- (car pt) (car circle)))
  (setq dy (- (cadr pt) (cadr circle)))
  (setq dist-sq (+ (* dx dx) (* dy dy)))
  (<= dist-sq (caddr circle))
)

;;; Erstellt Supertriangle das alle Punkte umschliesst
;;; Parameter: pts - Liste von Punkten ((x y h) ...)
;;; Rueckgabe: Liste von 3 Punkten ((x y 0) (x y 0) (x y 0))
(defun HAFM:supertriangle (pts / min-x max-x min-y max-y dx dy dmax mid-x mid-y)
  (setq min-x 1e30 max-x -1e30 min-y 1e30 max-y -1e30)
  (foreach pt pts
    (if (< (car pt) min-x) (setq min-x (car pt)))
    (if (> (car pt) max-x) (setq max-x (car pt)))
    (if (< (cadr pt) min-y) (setq min-y (cadr pt)))
    (if (> (cadr pt) max-y) (setq max-y (cadr pt)))
  )
  (setq dx (- max-x min-x))
  (setq dy (- max-y min-y))
  (setq dmax (if (> dx dy) dx dy))
  (setq mid-x (/ (+ min-x max-x) 2.0))
  (setq mid-y (/ (+ min-y max-y) 2.0))
  ;; Supertriangle: gross genug um alle Punkte zu umschliessen
  (list
    (list (- mid-x (* 2.0 dmax)) (- mid-y dmax) 0.0)
    (list mid-x (+ mid-y (* 2.0 dmax)) 0.0)
    (list (+ mid-x (* 2.0 dmax)) (- mid-y dmax) 0.0)
  )
)

;;; Prueft ob zwei Kanten gleich sind (ungeordnet)
(defun HAFM:edge-equal (e1 e2)
  (or (and (= (car e1) (car e2)) (= (cadr e1) (cadr e2)))
      (and (= (car e1) (cadr e2)) (= (cadr e1) (car e2))))
)

;;; Bowyer-Watson Delaunay-Triangulation
;;; Parameter:
;;;   pts - Liste von Punkten ((x y h) (x y h) ...)
;;;         Nur x,y werden fuer Triangulation verwendet
;;;         h wird mitgefuehrt fuer spaetere Interpolation
;;;
;;; Rueckgabe: Liste von Dreiecken ((i j k) (i j k) ...)
;;;            Indizes beziehen sich auf pts (0-basiert)
(defun HAFM:delaunay (pts / super-pts all-pts num-super triangles
                         i pt bad-tri polygon edge tri
                         edges e1 e2 j is-shared
                         new-tri result num-pts)
  (setq num-pts (length pts))
  (HAFM:log-write "INFO" (strcat "Delaunay: " (itoa num-pts) " Punkte"))
  
  ;; Supertriangle erstellen
  (setq super-pts (HAFM:supertriangle pts))
  ;; Alle Punkte: Original + 3 Supertriangle-Ecken am Ende
  (setq all-pts (append pts super-pts))
  (setq num-super num-pts) ;; Index ab dem Supertriangle-Punkte beginnen
  
  ;; Initiales Dreieck = Supertriangle (Indizes: n, n+1, n+2)
  (setq triangles (list (list num-super (1+ num-super) (+ num-super 2))))
  
  ;; Jeden Punkt einfuegen
  (setq i 0)
  (while (< i num-pts)
    (setq pt (nth i all-pts))
    
    ;; Finde "bad triangles" (Punkt liegt in deren Umkreis)
    (setq bad-tri nil)
    (foreach tri triangles
      (setq circle (HAFM:circumcircle
                     (nth (car tri) all-pts)
                     (nth (cadr tri) all-pts)
                     (nth (caddr tri) all-pts)))
      (if (and circle (HAFM:point-in-circumcircle pt circle))
        (setq bad-tri (cons tri bad-tri))
      )
    )
    
    ;; Finde Polygon-Rand (Kanten die nur zu EINEM bad triangle gehoeren)
    (setq polygon nil)
    (foreach tri bad-tri
      ;; 3 Kanten pro Dreieck
      (setq edges (list
        (list (car tri) (cadr tri))
        (list (cadr tri) (caddr tri))
        (list (caddr tri) (car tri))))
      (foreach edge edges
        ;; Pruefe ob Kante von anderem bad triangle geteilt wird
        (setq is-shared nil)
        (foreach other bad-tri
          (if (not (equal tri other))
            (progn
              (setq e1 (list (car other) (cadr other)))
              (setq e2 (list (cadr other) (caddr other)))
              (if (or (HAFM:edge-equal edge e1)
                      (HAFM:edge-equal edge e2)
                      (HAFM:edge-equal edge (list (caddr other) (car other))))
                (setq is-shared T)
              )
            )
          )
        )
        ;; Nicht geteilt → gehoert zum Polygon-Rand
        (if (not is-shared)
          (setq polygon (cons edge polygon))
        )
      )
    )
    
    ;; Bad triangles entfernen
    (foreach tri bad-tri
      (setq triangles (vl-remove tri triangles))
    )
    
    ;; Neue Dreiecke: Punkt i → jede Kante des Polygons
    (foreach edge polygon
      (setq triangles (cons (list i (car edge) (cadr edge)) triangles))
    )
    
    (setq i (1+ i))
  )
  
  ;; Supertriangle-Dreiecke entfernen (alle die einen Index >= num-super haben)
  (setq result nil)
  (foreach tri triangles
    (if (and (< (car tri) num-super)
             (< (cadr tri) num-super)
             (< (caddr tri) num-super))
      (setq result (cons tri result))
    )
  )
  
  (HAFM:log-write "INFO" (strcat "Delaunay fertig: " (itoa (length result)) " Dreiecke"))
  result
)

;;; ============================================================================
;;; CONSTRAINED DELAUNAY (Boundary-Kanten erzwingen)
;;; ============================================================================

;;; Prueft ob zwei Liniensegmente sich kreuzen (2D, echte Kreuzung, nicht Beruehrung)
;;; Parameter: p1,p2 - Endpunkte Segment 1; p3,p4 - Endpunkte Segment 2
;;; Rueckgabe: T wenn Kreuzung, nil sonst
(defun HAFM:segments-cross (p1 p2 p3 p4
                           / d ua ub eps
                             x1 y1 x2 y2 x3 y3 x4 y4)
  (setq eps 1e-10)
  (setq x1 (car p1) y1 (cadr p1) x2 (car p2) y2 (cadr p2))
  (setq x3 (car p3) y3 (cadr p3) x4 (car p4) y4 (cadr p4))
  (setq d (- (* (- x2 x1) (- y4 y3)) (* (- y2 y1) (- x4 x3))))
  (if (< (abs d) eps)
    nil ;; parallel
    (progn
      (setq ua (/ (- (* (- x4 x3) (- y1 y3)) (* (- y4 y3) (- x1 x3))) d))
      (setq ub (/ (- (* (- x2 x1) (- y1 y3)) (* (- y2 y1) (- x1 x3))) d))
      ;; Echte Kreuzung: ua und ub strikt zwischen 0 und 1 (nicht an Endpunkten)
      (and (> ua eps) (< ua (- 1.0 eps))
           (> ub eps) (< ub (- 1.0 eps)))
    )
  )
)

;;; Prueft ob ein Dreieck eine bestimmte Kante (als Indizes) enthaelt
;;; Rueckgabe: T wenn Dreieck die Kante i-j hat
(defun HAFM:triangle-has-edge (tri ei ej / )
  (or (and (= (car tri) ei) (= (cadr tri) ej))
      (and (= (cadr tri) ei) (= (car tri) ej))
      (and (= (cadr tri) ei) (= (caddr tri) ej))
      (and (= (caddr tri) ei) (= (cadr tri) ej))
      (and (= (caddr tri) ei) (= (car tri) ej))
      (and (= (car tri) ei) (= (caddr tri) ej)))
)

;;; Findet den dritten Punkt eines Dreiecks (nicht ei und nicht ej)
(defun HAFM:triangle-opposite (tri ei ej / )
  (cond
    ((and (/= (car tri) ei) (/= (car tri) ej)) (car tri))
    ((and (/= (cadr tri) ei) (/= (cadr tri) ej)) (cadr tri))
    ((and (/= (caddr tri) ei) (/= (caddr tri) ej)) (caddr tri))
    (T nil)
  )
)

;;; Findet die zwei Dreiecke die eine Kante teilen
;;; Rueckgabe: Liste von 0, 1 oder 2 Dreiecken
(defun HAFM:find-adjacent (triangles ei ej / result)
  (setq result nil)
  (foreach tri triangles
    (if (HAFM:triangle-has-edge tri ei ej)
      (setq result (cons tri result))
    )
  )
  result
)

;;; Edge-Flip: Ersetzt Kante ei-ej durch die andere Diagonale des Vierecks
;;; Parameter: triangles - aktuelle Dreiecksliste, ei/ej - zu flippende Kante
;;; Rueckgabe: neue Dreiecksliste (oder unveraendert wenn Flip nicht moeglich)
(defun HAFM:edge-flip (triangles ei ej / adj t1 t2 op1 op2 new-tri1 new-tri2)
  (setq adj (HAFM:find-adjacent triangles ei ej))
  (if (/= (length adj) 2)
    triangles ;; Rand-Kante oder Fehler → kein Flip
    (progn
      (setq t1 (car adj) t2 (cadr adj))
      (setq op1 (HAFM:triangle-opposite t1 ei ej))
      (setq op2 (HAFM:triangle-opposite t2 ei ej))
      (if (or (null op1) (null op2))
        triangles
        (progn
          ;; Alte Dreiecke entfernen
          (setq triangles (vl-remove t1 triangles))
          (setq triangles (vl-remove t2 triangles))
          ;; Neue Dreiecke mit geflippter Diagonale
          (setq new-tri1 (list op1 op2 ei))
          (setq new-tri2 (list op1 op2 ej))
          (cons new-tri1 (cons new-tri2 triangles))
        )
      )
    )
  )
)

;;; Prueft ob eine Constraint-Kante bereits im TIN existiert
(defun HAFM:constraint-exists (triangles ci cj / found)
  (setq found nil)
  (foreach tri triangles
    (if (and (not found) (HAFM:triangle-has-edge tri ci cj))
      (setq found T)
    )
  )
  found
)

;;; Erzwingt eine einzelne Constraint-Kante im TIN durch Edge-Flips
;;; Findet kreuzende Kanten und flippt sie bis die Constraint-Kante existiert
;;; max-iter verhindert Endlosschleifen
(defun HAFM:enforce-edge (triangles pts ci cj
                         / pi pj done iter max-iter
                           tri edges-to-flip ei ej pa pb changed)
  (setq pi (nth ci pts))
  (setq pj (nth cj pts))
  (setq done nil iter 0 max-iter 50)
  
  (while (and (not done) (< iter max-iter))
    (setq iter (1+ iter))
    ;; Pruefen ob Constraint schon existiert
    (if (HAFM:constraint-exists triangles ci cj)
      (setq done T)
      (progn
        ;; Finde eine kreuzende Kante und flippe sie
        (setq changed nil)
        (foreach tri triangles
          (if (not changed)
            (progn
              ;; 3 Kanten des Dreiecks pruefen
              (setq edges-to-flip (list
                (list (car tri) (cadr tri))
                (list (cadr tri) (caddr tri))
                (list (caddr tri) (car tri))))
              (foreach edge edges-to-flip
                (if (not changed)
                  (progn
                    (setq ei (car edge) ej (cadr edge))
                    ;; Kante darf nicht Endpunkt der Constraint sein
                    (if (and (/= ei ci) (/= ei cj) (/= ej ci) (/= ej cj))
                      (progn
                        (setq pa (nth ei pts) pb (nth ej pts))
                        (if (HAFM:segments-cross pi pj pa pb)
                          (progn
                            (setq triangles (HAFM:edge-flip triangles ei ej))
                            (setq changed T)
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
        ;; Keine kreuzende Kante mehr gefunden → fertig (oder Fehler)
        (if (not changed) (setq done T))
      )
    )
  )
  (if (>= iter max-iter)
    (HAFM:log-write "WARN" (strcat "enforce-edge: max-iter erreicht fuer "
                                   (itoa ci) "-" (itoa cj)))
  )
  triangles
)

;;; Constrained Delaunay: Normaler Delaunay + Boundary erzwingen + Aussen entfernen
;;; Parameter:
;;;   pts - Alle Punkte ((x y h) ...) — erst Boundary, dann innere Punkte
;;;   num-boundary - Anzahl Boundary-Punkte (erste N Punkte in pts)
;;;                  nil = alle Punkte sind Boundary
;;;   extra-constraints - Zusaetzliche Constraint-Kanten ((i j) (j k) ...)
;;;                       z.B. Bruchkanten. nil = keine.
;;;
;;; Rueckgabe: Liste von Dreiecken (nur innerhalb der Umrandung)
(defun HAFM:constrained-delaunay (pts num-boundary extra-constraints
                                 / triangles num-pts i ci cj
                                   boundary-pts result cx cy polygon)
  (setq num-pts (length pts))
  (if (null num-boundary) (setq num-boundary num-pts))
  (HAFM:log-write "INFO" (strcat "Constrained Delaunay: " (itoa num-pts) " Punkte ("
                                (itoa num-boundary) " Boundary, "
                                (itoa (- num-pts num-boundary)) " innere)"))
  
  ;; Schritt 1: Normaler Delaunay (alle Punkte)
  (setq triangles (HAFM:delaunay pts))
  (if (null triangles)
    (progn
      (HAFM:log-write "ERROR" "Constrained Delaunay: Basis-Delaunay fehlgeschlagen")
      (setq triangles nil)
    )
    (progn
      ;; Schritt 2: Boundary-Kanten erzwingen (nur die ersten num-boundary Punkte)
      (HAFM:log-write "INFO" (strcat "Boundary-Constraints: " (itoa num-boundary) " Kanten"))
      (setq i 0)
      (while (< i num-boundary)
        (setq ci i)
        (setq cj (rem (1+ i) num-boundary)) ;; Schliessen: letzter → erster
        (if (not (HAFM:constraint-exists triangles ci cj))
          (progn
            (setq triangles (HAFM:enforce-edge triangles pts ci cj))
            (HAFM:debug (strcat "Boundary-Constraint erzwungen: " (itoa ci) "-" (itoa cj)))
          )
        )
        (setq i (1+ i))
      )
      
      ;; Schritt 2b: Extra-Constraints erzwingen (Bruchkanten etc.)
      (if extra-constraints
        (progn
          (HAFM:log-write "INFO" (strcat "Extra-Constraints: " (itoa (length extra-constraints)) " Kanten"))
          (foreach ec extra-constraints
            (setq ci (car ec) cj (cadr ec))
            (if (not (HAFM:constraint-exists triangles ci cj))
              (progn
                (setq triangles (HAFM:enforce-edge triangles pts ci cj))
                (HAFM:debug (strcat "Extra-Constraint erzwungen: " (itoa ci) "-" (itoa cj)))
              )
            )
          )
        )
      )
      
      ;; Schritt 3: Dreiecke ausserhalb der Umrandung entfernen
      ;; Polygon = nur die Boundary-Punkte (erste num-boundary)
      (setq boundary-pts nil i 0)
      (while (< i num-boundary)
        (setq boundary-pts (append boundary-pts (list (nth i pts))))
        (setq i (1+ i))
      )
      (setq result nil)
      (foreach tri triangles
        (setq cx (/ (+ (car (nth (car tri) pts))
                       (car (nth (cadr tri) pts))
                       (car (nth (caddr tri) pts))) 3.0))
        (setq cy (/ (+ (cadr (nth (car tri) pts))
                       (cadr (nth (cadr tri) pts))
                       (cadr (nth (caddr tri) pts))) 3.0))
        (if (HAFM:point-in-polygon (list cx cy) boundary-pts)
          (setq result (cons tri result))
        )
      )
      
      (HAFM:log-write "INFO" (strcat "Constrained Delaunay fertig: "
                                     (itoa (length result)) " Dreiecke (von "
                                     (itoa (length triangles)) " total)"))
      (setq triangles result)
    )
  )
  triangles
)

;;; ============================================================================
;;; TIN-INTERPOLATION (Punkt auf TIN-Oberflaeche)
;;; ============================================================================

;;; Findet das Dreieck im TIN das den Punkt enthaelt
;;; Parameter:
;;;   pg - Gesuchter Punkt (x y)
;;;   pts - Alle Punkte ((x y h) ...)
;;;   triangles - Delaunay-Dreiecke ((i j k) ...)
;;;
;;; Rueckgabe: Dreieck (i j k) oder nil
(defun HAFM:find-triangle (pg pts triangles / tri pa pb pc bary found)
  (setq found nil)
  (foreach tri triangles
    (if (not found)
      (progn
        (setq pa (nth (car tri) pts))
        (setq pb (nth (cadr tri) pts))
        (setq pc (nth (caddr tri) pts))
        (setq bary (HAFM:barycentric pa pb pc pg))
        (if (HAFM:point-in-triangle-p bary)
          (setq found tri)
        )
      )
    )
  )
  found
)

;;; Interpoliert Hoehe auf TIN-Oberflaeche
;;; Parameter:
;;;   pg - Gesuchter Punkt (x y z)
;;;   pts - Alle Punkte ((x y h) ...)
;;;   heights - Hoehen-Liste (h1 h2 ...)
;;;   triangles - Delaunay-Dreiecke
;;;
;;; Rueckgabe: Liste (hoehe methoden-info) oder nil
(defun HAFM:interpolate-tin (pg pts heights triangles
                            / tri pa pb pc ha hb hc height tri-info)
  (setq tri (HAFM:find-triangle pg pts triangles))
  (if tri
    (progn
      (setq pa (nth (car tri) pts))
      (setq pb (nth (cadr tri) pts))
      (setq pc (nth (caddr tri) pts))
      (setq ha (nth (car tri) heights))
      (setq hb (nth (cadr tri) heights))
      (setq hc (nth (caddr tri) heights))
      (setq height (HAFM:height-in-triangle pa ha pb hb pc hc pg))
      (setq tri-info (strcat "TIN Dreieck "
                             (itoa (1+ (car tri))) "-"
                             (itoa (1+ (cadr tri))) "-"
                             (itoa (1+ (caddr tri)))))
      (HAFM:debug (strcat "interpolate-tin: " tri-info " h=" (rtos height 2 4)))
      (list height tri-info)
    )
    (progn
      (HAFM:debug "interpolate-tin: Punkt ausserhalb TIN")
      nil
    )
  )
)

;;; Hoehenlinie ueber alle TIN-Dreiecke berechnen
;;; Kein Polygon-Filter noetig: Constrained Delaunay hat bereits gefiltert
;;; Rueckgabe: Liste von Segmenten ((p1 p2) ...)
(defun HAFM:contour-tin (pts heights triangles target-h
                        / tri pa pb pc ha hb hc seg result)
  (setq result nil)
  (foreach tri triangles
    (setq pa (nth (car tri) pts))
    (setq pb (nth (cadr tri) pts))
    (setq pc (nth (caddr tri) pts))
    (setq ha (nth (car tri) heights))
    (setq hb (nth (cadr tri) heights))
    (setq hc (nth (caddr tri) heights))
    (setq seg (HAFM:contour-in-triangle pa ha pb hb pc hc target-h))
    (if seg (setq result (cons seg result)))
  )
  (HAFM:debug (strcat "contour-tin: " (itoa (length result)) " Segmente bei H=" (rtos target-h 2 2)))
  (if result (reverse result) nil)
)

;;; Prueft ob ein Punkt innerhalb eines Polygons liegt (2D, Ray-Casting)
;;; Parameter:
;;;   pt - Punkt (x y)
;;;   polygon - Liste von Punkten ((x y) (x y) ...) geschlossen
;;;
;;; Rueckgabe: T wenn innerhalb, nil wenn ausserhalb
(defun HAFM:point-in-polygon (pt polygon / n i j xi yi xj yj inside)
  (setq n (length polygon))
  (setq inside nil)
  (setq j (1- n))
  (setq i 0)
  (while (< i n)
    (setq xi (car (nth i polygon)) yi (cadr (nth i polygon)))
    (setq xj (car (nth j polygon)) yj (cadr (nth j polygon)))
    ;; Ray-Casting: zaehle Schnitte mit horizontalem Strahl nach rechts
    (if (and (/= (> yi (cadr pt)) (> yj (cadr pt)))
             (< (car pt)
                (+ xi (/ (* (- xj xi) (- (cadr pt) yi)) (- yj yi)))))
      (setq inside (not inside))
    )
    (setq j i)
    (setq i (1+ i))
  )
  inside
)

;;; Prueft ob Mittelpunkt eines Segments innerhalb der Umrandung liegt
;;; Parameter:
;;;   seg - Segment ((x1 y1 z1) (x2 y2 z2))
;;;   polygon - Umrandungs-Punkte
;;; Rueckgabe: T wenn Mittelpunkt innerhalb
(defun HAFM:segment-in-polygon (seg polygon / mid)
  (setq mid (list (/ (+ (car (car seg)) (car (cadr seg))) 2.0)
                  (/ (+ (cadr (car seg)) (cadr (cadr seg))) 2.0)))
  (HAFM:point-in-polygon mid polygon)
)

;;; Visualisiert TIN als geschlossene 3D-Polylinien (1 pro Dreieck)
;;; Verwendet entmakex mit UCS→WCS Transformation
;;; Rueckgabe: Liste von Entity-Names (POLYLINE Header-Entities)
(defun HAFM:draw-tin (pts heights triangles
                     / tri pa pb pc ha hb hc entities ent
                       p1-wcs p2-wcs p3-wcs header)
  (setq entities nil)
  (foreach tri triangles
    (setq pa (nth (car tri) pts))
    (setq pb (nth (cadr tri) pts))
    (setq pc (nth (caddr tri) pts))
    (setq ha (nth (car tri) heights))
    (setq hb (nth (cadr tri) heights))
    (setq hc (nth (caddr tri) heights))
    ;; UCS→WCS Transformation
    (setq p1-wcs (trans (list (car pa) (cadr pa) ha) 1 0))
    (setq p2-wcs (trans (list (car pb) (cadr pb) hb) 1 0))
    (setq p3-wcs (trans (list (car pc) (cadr pc) hc) 1 0))
    ;; 3D-Polylinie als POLYLINE + VERTEX + SEQEND (geschlossen)
    ;; Flag 8 = 3D polyline, Flag 1 = closed
    (setq header (entmakex
      (list '(0 . "POLYLINE") '(100 . "AcDbEntity") '(8 . "0")
            (cons 62 *HAFM:tin-color*)
            '(100 . "AcDb3dPolyline")
            '(66 . 1) '(70 . 9))))  ;; 8 (3D) + 1 (closed) = 9
    (if header
      (progn
        ;; 3 Vertices
        (entmakex (list '(0 . "VERTEX") '(100 . "AcDbEntity") '(8 . "0")
                        '(100 . "AcDbVertex") '(100 . "AcDb3dPolylineVertex")
                        (cons 10 p1-wcs) '(70 . 32)))
        (entmakex (list '(0 . "VERTEX") '(100 . "AcDbEntity") '(8 . "0")
                        '(100 . "AcDbVertex") '(100 . "AcDb3dPolylineVertex")
                        (cons 10 p2-wcs) '(70 . 32)))
        (entmakex (list '(0 . "VERTEX") '(100 . "AcDbEntity") '(8 . "0")
                        '(100 . "AcDbVertex") '(100 . "AcDb3dPolylineVertex")
                        (cons 10 p3-wcs) '(70 . 32)))
        ;; SEQEND
        (entmakex (list '(0 . "SEQEND") '(100 . "AcDbEntity") '(8 . "0")))
        (setq entities (cons header entities))
      )
    )
  )
  (HAFM:log-write "INFO" (strcat "TIN gezeichnet: " (itoa (length entities)) " Dreiecke"))
  entities
)

;;; Loescht TIN-Entities
(defun HAFM:delete-tin (entities / )
  (foreach ent entities
    (if (and ent (entget ent))
      (entdel ent)
    )
  )
  (HAFM:debug (strcat "TIN geloescht: " (itoa (length entities))))
)

;;; ============================================================================
;;; DISPATCHER - Waehlt Interpolationsmethode
;;; ============================================================================

;;; Zentrale Interpolationsfunktion
;;; Waehlt automatisch: 3 Punkte → Ebene, 4 Punkte → Triangulation, 5+ → TIN
;;;
;;; Parameter:
;;;   pts - Liste von 3+ Punkten
;;;   heights - Liste von Hoehen
;;;   pg - Gesuchter Punkt
;;;   diagonal - "13" oder "24" (nur bei 4 Punkten, sonst nil)
;;;   triangles - Delaunay-Dreiecke (nur bei 5+ Punkten, sonst nil)
;;;
;;; Rueckgabe: Liste (hoehe methoden-info) oder nil
(defun HAFM:interpolate (pts heights pg diagonal / num-pts)
  (setq num-pts (length pts))
  (HAFM:debug (strcat "HAFM:interpolate: " (itoa num-pts) " Punkte"
                     (if diagonal (strcat " diag=" diagonal) "")))
  (cond
    ((= num-pts 3)
     (HAFM:interpolate-plane pts heights pg))
    ((= num-pts 4)
     (HAFM:interpolate-triangulation pts heights pg diagonal))
    ((>= num-pts 5)
     ;; TIN-Modus: triangles muss als globale Variable *HAFM:tin-triangles* vorliegen
     (if *HAFM:tin-triangles*
       (HAFM:interpolate-tin pg pts heights *HAFM:tin-triangles*)
       (progn
         (HAFM:log-write "ERROR" "interpolate: 5+ Punkte aber kein TIN berechnet")
         nil)
     ))
    (T
     (HAFM:log-write "ERROR" (strcat "interpolate: ungueltige Punktzahl " (itoa num-pts)))
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
(defun HAFM:edge-height-point (pa pb ha hb target-h / t-val px py)
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
;;; Behandelt Spezialfaelle:
;;;   - Zielhoehe trifft genau einen Eckpunkt (3 Hits → Duplikate entfernen)
;;;   - Zielhoehe laeuft entlang einer Kante (ha=hb=target)
;;;
;;; Rueckgabe: Liste (punkt1 punkt2) oder nil wenn kein Schnitt
(defun HAFM:contour-in-triangle (p1 h1 p2 h2 p3 h3 target-h
                                 / hit1 hit2 hit3 result eps unique-result
                                   edge-on-height pa pb)
  (setq eps 0.001)
  
  ;; Spezialfall: Eine ganze Kante liegt auf Zielhoehe
  ;; (beide Endpunkte haben Zielhoehe → Kante IST die Hoehenlinie)
  (setq edge-on-height nil)
  (if (and (< (abs (- h1 target-h)) eps) (< (abs (- h2 target-h)) eps))
    (setq edge-on-height (list p1 p2))
  )
  (if (and (null edge-on-height) (< (abs (- h2 target-h)) eps) (< (abs (- h3 target-h)) eps))
    (setq edge-on-height (list p2 p3))
  )
  (if (and (null edge-on-height) (< (abs (- h3 target-h)) eps) (< (abs (- h1 target-h)) eps))
    (setq edge-on-height (list p3 p1))
  )
  
  (if edge-on-height
    (progn
      (HAFM:debug (strcat "contour-in-triangle: Kante auf Hoehe " (rtos target-h 2 2)))
      edge-on-height
    )
    (progn
      ;; Normale Berechnung: Schnittpunkte auf den 3 Kanten
      (setq hit1 (HAFM:edge-height-point p1 p2 h1 h2 target-h))
      (setq hit2 (HAFM:edge-height-point p2 p3 h2 h3 target-h))
      (setq hit3 (HAFM:edge-height-point p3 p1 h3 h1 target-h))
      
      ;; Sammle Treffer
      (setq result nil)
      (if hit1 (setq result (cons hit1 result)))
      (if hit2 (setq result (cons hit2 result)))
      (if hit3 (setq result (cons hit3 result)))
      
      (HAFM:debug (strcat "contour-in-triangle: target=" (rtos target-h 2 2)
                         " hits=" (itoa (length result))))
      
      (cond
        ;; Genau 2 Treffer → normal
        ((= (length result) 2)
         result
        )
        ;; 3 Treffer → Zielhoehe trifft Eckpunkt (Duplikate entfernen)
        ((= (length result) 3)
         ;; Entferne Duplikate (Punkte die < eps auseinander liegen)
         (setq unique-result (list (car result)))
         (foreach pt (cdr result)
           (if (not (vl-some
                      '(lambda (existing)
                         (< (distance (list (car pt) (cadr pt))
                                      (list (car existing) (cadr existing))) eps))
                      unique-result))
             (setq unique-result (cons pt unique-result))
           )
         )
         (HAFM:debug (strcat "  Nach Duplikat-Entfernung: " (itoa (length unique-result))))
         (if (= (length unique-result) 2)
           unique-result
           nil
         )
        )
        ;; 0 oder 1 Treffer → kein Schnitt
        (T nil)
      )
    )
  )
)

;;; Berechnet Hoehenlinie fuer 3 Punkte (Ebene)
;;; Schnitt Ebene mit Hoehenebene = eine gerade Linie
;;;
;;; Parameter:
;;;   pts - 3 Punkte, heights - 3 Hoehen, target-h - Zielhoehe
;;;
;;; Rueckgabe: Liste von Liniensegmenten ((p1 p2) ...) oder nil
(defun HAFM:contour-3pt (pts heights target-h / p1 p2 p3 h1 h2 h3 seg)
  (setq p1 (nth 0 pts) p2 (nth 1 pts) p3 (nth 2 pts))
  (setq h1 (nth 0 heights) h2 (nth 1 heights) h3 (nth 2 heights))
  (setq seg (HAFM:contour-in-triangle p1 h1 p2 h2 p3 h3 target-h))
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
(defun HAFM:contour-4pt (pts heights target-h diagonal
                        / p1 p2 p3 p4 h1 h2 h3 h4 seg1 seg2 result)
  (setq p1 (nth 0 pts) p2 (nth 1 pts) p3 (nth 2 pts) p4 (nth 3 pts))
  (setq h1 (nth 0 heights) h2 (nth 1 heights) h3 (nth 2 heights) h4 (nth 3 heights))
  (setq result nil)
  (if (= diagonal "13")
    ;; Dreiecke 1-2-3 und 1-3-4
    (progn
      (setq seg1 (HAFM:contour-in-triangle p1 h1 p2 h2 p3 h3 target-h))
      (setq seg2 (HAFM:contour-in-triangle p1 h1 p3 h3 p4 h4 target-h))
    )
    ;; Dreiecke 1-2-4 und 2-3-4
    (progn
      (setq seg1 (HAFM:contour-in-triangle p1 h1 p2 h2 p4 h4 target-h))
      (setq seg2 (HAFM:contour-in-triangle p2 h2 p3 h3 p4 h4 target-h))
    )
  )
  (if seg1 (setq result (cons seg1 result)))
  (if seg2 (setq result (cons seg2 result)))
  (HAFM:debug (strcat "contour-4pt: " (itoa (length result)) " Segmente"))
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
(defun HAFM:compute-contour (pts heights target-h diagonal / num-pts)
  (setq num-pts (length pts))
  (HAFM:debug (strcat "compute-contour: " (itoa num-pts) " Punkte, target=" (rtos target-h 2 2)))
  (cond
    ((= num-pts 3) (HAFM:contour-3pt pts heights target-h))
    ((= num-pts 4) (HAFM:contour-4pt pts heights target-h diagonal))
    ((>= num-pts 5)
     (if *HAFM:tin-triangles*
       (HAFM:contour-tin pts heights *HAFM:tin-triangles* target-h)
       nil))
    (T nil)
  )
)

;;; Zeichnet Hoehenlinie als Linien-Segmente
;;; Farbe aus *HAFM:contour-color* (konfigurierbar)
;;; Rueckgabe: Liste der Entity-Names (zum spaeteren Loeschen/Finalisieren)
(defun HAFM:draw-contour (segments polygon / entities ent p1 p2)
  (setq entities nil)
  (foreach seg segments
    (setq p1 (car seg))
    (setq p2 (cadr seg))
    (if (and p1 p2)
      (progn
        (setq ent (entmakex
          (list '(0 . "LINE") '(100 . "AcDbEntity") '(8 . "0")
                (cons 62 *HAFM:contour-color*)
                '(100 . "AcDbLine")
                (cons 10 (trans p1 1 0))
                (cons 11 (trans p2 1 0)))))
        (if ent
          (progn
            (setq entities (cons ent entities))
            (HAFM:debug (strcat "  Contour-Linie: ("
                               (rtos (car p1) 2 2) "," (rtos (cadr p1) 2 2) ") -> ("
                               (rtos (car p2) 2 2) "," (rtos (cadr p2) 2 2) ")"
                               " Farbe=" (itoa *HAFM:contour-color*)))
          )
        )
      )
    )
  )
  (HAFM:log-write "INFO" (strcat "Hoehenlinie gezeichnet: " (itoa (length entities))
                                " Segmente, Farbe=" (HAFM:color-name *HAFM:contour-color*)))
  entities
)

;;; Loescht Hoehenlinien-Entities
(defun HAFM:delete-contours (entities / )
  (foreach ent entities
    (if (and ent (entget ent))
      (entdel ent)
    )
  )
  (HAFM:debug (strcat "Contours geloescht: " (itoa (length entities))))
)

;;; Berechnet und zeichnet Hoehenlinienraster
;;; Vom tiefsten zum hoechsten Eckpunkt in Schritten von interval
;;;
;;; Parameter:
;;;   pts - 3 oder 4 Punkte
;;;   heights - Hoehen
;;;   diagonal - "13"/"24" (nur bei 4 Punkten)
;;;   interval - Abstand N
;;;
;;; Rueckgabe: Liste aller Entity-Names (zum Loeschen/Finalisieren)
(defun HAFM:draw-grid (pts heights diagonal interval
                      / min-h max-h target-h segments entities all-entities)
  (setq min-h (apply 'min heights))
  (setq max-h (apply 'max heights))
  (setq all-entities nil)
  ;; Erstes Raster-Niveau: aufrunden vom Minimum auf naechstes Vielfaches von interval
  (setq target-h (* (1+ (fix (/ min-h interval))) interval))
  ;; Sonderfall: wenn min-h exakt auf Raster liegt, dort starten
  (if (equal (rem min-h interval) 0.0 0.001)
    (setq target-h min-h)
  )
  (HAFM:log-write "INFO" (strcat "Hoehenraster: min=" (rtos min-h 2 2)
                                " max=" (rtos max-h 2 2)
                                " interval=" (rtos interval 2 2)
                                " start=" (rtos target-h 2 2)))
  ;; Schleife ueber alle Raster-Niveaus
  (while (<= target-h max-h)
    (setq segments (HAFM:compute-contour pts heights target-h diagonal))
    (if segments
      (progn
        ;; Zeichne Segmente mit Grid-Farbe (nur innerhalb Polygon)
        (foreach seg segments
          (if (and (car seg) (cadr seg))
            (progn
              (setq entities (entmakex
                (list '(0 . "LINE") '(100 . "AcDbEntity") '(8 . "0")
                      (cons 62 *HAFM:grid-color*)
                      '(100 . "AcDbLine")
                      (cons 10 (trans (car seg) 1 0))
                      (cons 11 (trans (cadr seg) 1 0)))))
              (if entities
                (setq all-entities (cons entities all-entities))
              )
            )
          )
        )
      )
    )
    (setq target-h (+ target-h interval))
  )
  (HAFM:log-write "INFO" (strcat "Hoehenraster gezeichnet: " (itoa (length all-entities))
                                " Linien, Farbe=" (HAFM:color-name *HAFM:grid-color*)))
  (if all-entities
    (princ (strcat "\n  Hoehenraster: " (itoa (length all-entities))
                   " Linien (N=" (rtos interval 2 2)
                   ", " (rtos min-h 2 2) " bis " (rtos max-h 2 2) ")"))
  )
  all-entities
)

;;; Loescht Raster-Entities
(defun HAFM:delete-grid (entities / )
  (foreach ent entities
    (if (and ent (entget ent))
      (entdel ent)
    )
  )
  (HAFM:debug (strcat "Grid geloescht: " (itoa (length entities))))
)



;;; ============================================================================
;;; PLACEHOLDER: BEFEHLE (werden in Schritt 3-5 eingefuegt)
;;; ============================================================================

;;; ============================================================================
;;; HAFNEW - Neue Oberflaeche erstellen
;;; ============================================================================
;;;
;;; Phase 1: Definition (Umrandung → Hauptmenue I/B/L/C)
;;; Phase 2: Berechnung (Constrained Delaunay) + Interpolation
;;;
;;; Daten werden in separaten Listen gesammelt (keine Indizes).
;;; Erst bei "Berechnen" werden sie zusammengebaut und trianguliert.
;;; Ergebnis wird im DWG Dictionary persistent gespeichert.

(defun c:HAFNEW ( / *error* old-cmdecho old-attdia
                     surface-name
                     boundary-pts boundary-heights boundary-entities
                     inner-pts inner-heights inner-entities
                     breaklines breakline-entities
                     holes hole-entities
                     current-bl current-bl-heights current-bl-entities
                     current-hole
                     all-entities
                     pt ht result block-ent scale done
                     prompt-str choice
                     corner-number bl-number hole-number bl-count hole-count
                     pick-result from-block
                     surface-data tin-result all-pts triangles num-boundary all-heights
                     tin-entities outline-ent
                     grid-entities contour-entities target-h segments
                     use-diagonal interpolated-height tri-info pg
                     ;; Sub-Menue Variablen (MUESSEN lokal sein!)
                     inner-kw done-inner
                     bl-kw done-bl done-bk-pts
                     hole-kw done-hole done-hole-pts
                     inner-count ss-result
                     ;; Allgemein
                     ent ent-data attrib-ent attrib-data block-name
                     min-dist index dist i last-ent)
  
  (HAFM:ensure-init)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (HAFM:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (HAFM:log-write "ERROR" (strcat "Error-Handler: " msg))
      )
      (HAFM:log-write "INFO" (strcat "User-Abbruch: " msg))
    )
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
  
  (HAFM:log-write "INFO" "=== HAFNEW gestartet ===")
  
  ;; Skalierung
  (setq scale *HAFM:default-scale*)
  
  ;; Name abfragen
  (setq surface-name (getstring T "\nName der Oberflaeche: "))
  (if (or (null surface-name) (= surface-name ""))
    (progn
      (princ "\n*** Kein Name angegeben ***")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "ATTDIA" old-attdia)
      (HAFM:log-write "INFO" "HAFNEW abgebrochen: kein Name")
      (princ)
    )
    (progn
      ;; Pruefen ob Name schon existiert
      (if (HAFM:load-surface surface-name)
        (progn
          (princ (strcat "\n*** Oberflaeche \"" surface-name "\" existiert bereits! ***"))
          (princ "\n  Verwende HAFEDIT zum Bearbeiten.")
          (setvar "CMDECHO" old-cmdecho)
          (setvar "ATTDIA" old-attdia)
          (HAFM:log-write "INFO" (strcat "HAFNEW abgebrochen: " surface-name " existiert"))
          (princ)
        )
        (progn
          (HAFM:log-write "INFO" (strcat "Neue Oberflaeche: " surface-name))
          
          ;; Listen initialisieren
          (setq boundary-pts nil boundary-heights nil boundary-entities nil)
          (setq inner-pts nil inner-heights nil inner-entities nil)
          (setq breaklines nil breakline-entities nil)
          (setq holes nil hole-entities nil)
          (setq all-entities nil)
          
          ;; ================================================================
          ;; PHASE 1a: UMRANDUNG (Pflicht, geschlossen, min. 3 Punkte)
          ;; ================================================================
          
          (princ "\n\n=== Umrandung definieren (min. 3 Punkte, geschlossen) ===")
          (setq corner-number 1 done nil outline-ent nil)
          
          (while (not done)
            ;; Keywords
            (cond
              ((>= corner-number 4)
               (initget "Fertig Skalierung Zurueck"))
              ((> corner-number 1)
               (initget "Skalierung Zurueck"))
              (T (initget "Skalierung"))
            )
            ;; Prompt
            (setq prompt-str (strcat "\nUmrandung " (itoa corner-number) " ["))
            (if (> corner-number 1) (setq prompt-str (strcat prompt-str "Zurueck/")))
            (if (>= corner-number 4) (setq prompt-str (strcat prompt-str "Fertig/")))
            (setq prompt-str (strcat prompt-str "Skalierung]: "))
            
            (setq pick-result (HAFM:pick-or-place prompt-str scale))
            
            (cond
              ;; Keyword Skalierung
              ((= pick-result "Skalierung")
               (setq scale (getreal (strcat "\nSkalierung <" (rtos scale 2 2) ">: ")))
               (if (null scale) (setq scale *HAFM:default-scale*))
              )
              ;; Keyword Fertig
              ((= pick-result "Fertig")
               (if (>= (length boundary-pts) 3)
                 (progn
                   (setq done T)
                   (HAFM:log-write "INFO" (strcat "Umrandung: " (itoa (length boundary-pts)) " Punkte"))
                 )
                 (princ "\n*** Mindestens 3 Punkte noetig ***")
               )
              )
              ;; Keyword Zurueck
              ((= pick-result "Zurueck")
               (if (> corner-number 1)
                 (progn
                   (setq last-ent (last boundary-entities))
                   (if last-ent (entdel last-ent))
                   (setq boundary-pts (reverse (cdr (reverse boundary-pts))))
                   (setq boundary-heights (reverse (cdr (reverse boundary-heights))))
                   (setq boundary-entities (reverse (cdr (reverse boundary-entities))))
                   (setq corner-number (1- corner-number))
                   ;; Live-Umrandung aktualisieren
                   (setq outline-ent (HAFM:update-outline outline-ent boundary-pts boundary-heights))
                   (princ (strcat "\n  Punkt entfernt (" (itoa (length boundary-pts)) " verbleibend)"))
                 )
                 (princ "\n*** Kein Punkt zum Entfernen ***")
               )
              )
              ;; ENTER bei >= 3 Punkten
              ((and (null pick-result) (>= (length boundary-pts) 3))
               (setq done T)
               (HAFM:log-write "INFO" (strcat "Umrandung: " (itoa (length boundary-pts)) " Punkte (ENTER)"))
              )
              ;; ENTER bei < 3 Punkten = Abbruch
              ((null pick-result)
               (princ "\n*** Mindestens 3 Punkte noetig ***")
              )
              ;; Gueltiger Punkt (Liste = Koordinaten)
              ((listp pick-result)
               (setq pt (car pick-result))
               (setq ht (cadr pick-result))
               (setq from-block (caddr pick-result))
               ;; Hoehe abfragen wenn nicht aus Block
               (if (not ht)
                 (setq ht (HAFM:get-validated-height
                            (strcat "\n  Hoehe Umrandung " (itoa corner-number))
                            *HAFM:last-height*))
               )
               (if ht
                 (progn
                   (setq *HAFM:last-height* ht)
                   ;; Block einfuegen (wenn nicht aus existierendem Block)
                   (if (not from-block)
                     (setq block-ent (HAFM:insert-block pt ht scale nil))
                     (setq block-ent nil) ;; Block existiert schon
                   )
                   (setq boundary-pts (append boundary-pts (list (list (car pt) (cadr pt) ht))))
                   (setq boundary-heights (append boundary-heights (list ht)))
                   (setq boundary-entities (append boundary-entities (list block-ent)))
                   (HAFM:log-write "INFO" (strcat "Umrandung " (itoa corner-number)
                     ": (" (rtos (car pt) 2 3) " " (rtos (cadr pt) 2 3)
                     ") H=" (rtos ht 2 3) (if from-block " [Block]" "")))
                   (setq corner-number (1+ corner-number))
                   ;; Live-Umrandung aktualisieren
                   (setq outline-ent (HAFM:update-outline outline-ent boundary-pts boundary-heights))
                   ;; Hinweis ab 3 Punkten
                   (if (= (length boundary-pts) 3)
                     (princ "\n  (F=Fertig, ENTER=Fertig, oder weitere Punkte)")
                   )
                 )
                 (princ "\n*** Ungueltige Hoehe ***")
               )
              )
            )
          ) ;; end while Umrandung
          
          ;; ================================================================
          ;; PHASE 1b: HAUPTMENUE (I/B/L/C)
          ;; ================================================================
          
          (if (>= (length boundary-pts) 3)
            (progn
              (princ (strcat "\n\n" (itoa (length boundary-pts)) " Umrandungspunkte definiert"))
              (setq done nil)
              
              (while (not done)
                (initget "Innere Bruchkanten Loecher Status Compute")
                (setq choice (getkword
                  "\nWas definieren [Innere/Bruchkanten/Loecher/Status/Compute]: "))
                
                (cond
                  ;; ---- BERECHNEN ----
                  ((or (= choice "Compute") (null choice))
                   (setq done T)
                   (HAFM:log-write "INFO" "Phase 1 abgeschlossen, starte Berechnung")
                  )
                  
                  ;; ---- STATUS ----
                  ((= choice "Status")
                   (princ (strcat "\n\n=== Status \"" surface-name "\" ==="))
                   (princ (strcat "\n  Umrandung:    " (itoa (length boundary-pts)) " Punkte"))
                   (princ (strcat "\n  Innere:       " (itoa (length inner-pts)) " Punkte"))
                   (princ (strcat "\n  Bruchkanten:  " (itoa (length breaklines))
                     (if breaklines
                       (strcat " (" (apply 'strcat
                         (mapcar '(lambda (bl) (strcat (itoa (length bl)) "P "))
                                 breaklines)) ")")
                       "")))
                   (princ (strcat "\n  Loecher:      " (itoa (length holes))
                     (if holes
                       (strcat " (" (apply 'strcat
                         (mapcar '(lambda (h) (strcat (itoa (length h)) "P "))
                                 holes)) ")")
                       "")))
                   (princ "\n")
                  )
                  
                  ;; ---- INNERE PUNKTE ----
                  ((= choice "Innere")
                   (princ (strcat "\n--- Innere Punkte (" (itoa (length inner-pts)) " vorhanden) ---"))
                   (setq done-inner nil)
                   (while (not done-inner)
                     (initget "Punkt Window Entfernen Fertig")
                     (setq inner-kw (getkword "\n  Innere [Punkt/Window/Entfernen/Fertig]: "))
                     (cond
                       ;; FERTIG oder ENTER → zurueck zum Hauptmenue
                       ((or (null inner-kw) (= inner-kw "Fertig"))
                        (setq done-inner T)
                       )
                       ;; EINZELN
                       ((= inner-kw "Punkt")
                        (setq pick-result (HAFM:pick-or-place
                          (strcat "\n  Innerer Punkt " (itoa (1+ (length inner-pts))) ": ") scale))
                        (if (and pick-result (listp pick-result))
                          (progn
                            (setq pt (car pick-result))
                            (setq ht (cadr pick-result))
                            (setq from-block (caddr pick-result))
                            (if (not ht)
                              (setq ht (HAFM:get-validated-height "\n    Hoehe" *HAFM:last-height*))
                            )
                            (if ht
                              (progn
                                (setq *HAFM:last-height* ht)
                                (if (not from-block)
                                  (setq block-ent (HAFM:insert-block pt ht scale nil))
                                  (setq block-ent nil)
                                )
                                (setq inner-pts (append inner-pts (list (list (car pt) (cadr pt) ht))))
                                (setq inner-heights (append inner-heights (list ht)))
                                (setq inner-entities (append inner-entities (list block-ent)))
                                (HAFM:log-write "INFO" (strcat "Innerer Punkt: ("
                                  (rtos (car pt) 2 3) " " (rtos (cadr pt) 2 3)
                                  ") H=" (rtos ht 2 3)))
                                (princ (strcat "\n    " (HAFM:format-height ht) " ("
                                  (itoa (length inner-pts)) " gesamt)"))
                              )
                            )
                          )
                        )
                       )
                       ;; FENSTER
                       ((= inner-kw "Window")
                        (princ "\n  Fenster ueber Hoehenkoten-Bloecke ziehen:")
                        (setq ss-result (ssget '((0 . "INSERT"))))
                        (if ss-result
                          (progn
                            (setq inner-count 0 i 0)
                            (while (< i (sslength ss-result))
                              (setq ent (ssname ss-result i))
                              (setq ent-data (entget ent))
                              (setq block-name (cdr (assoc 2 ent-data)))
                              (if (wcmatch (strcase block-name) "*HOEHENKOTE*,*HK*,*BLK_H*")
                                (progn
                                  (setq ht nil)
                                  (setq attrib-ent (entnext ent))
                                  (while (and attrib-ent (not ht))
                                    (setq attrib-data (entget attrib-ent))
                                    (if (and (= (cdr (assoc 0 attrib-data)) "ATTRIB")
                                             (wcmatch (strcase (cdr (assoc 2 attrib-data)))
                                                      "HOEHE,HEIGHT,H"))
                                      (setq ht (atof (cdr (assoc 1 attrib-data))))
                                    )
                                    (setq attrib-ent (entnext attrib-ent))
                                  )
                                  (if ht
                                    (progn
                                      (setq pt (cdr (assoc 10 ent-data)))
                                      (if (HAFM:point-in-polygon pt boundary-pts)
                                        (progn
                                          (setq inner-pts (append inner-pts (list (list (car pt) (cadr pt) ht))))
                                          (setq inner-heights (append inner-heights (list ht)))
                                          (setq inner-entities (append inner-entities (list nil)))
                                          (setq inner-count (1+ inner-count))
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                              (setq i (1+ i))
                            )
                            (princ (strcat "\n    " (itoa inner-count) " Punkte uebernommen ("
                              (itoa (length inner-pts)) " gesamt)"))
                            (HAFM:log-write "INFO" (strcat "Fenster: " (itoa inner-count) " Punkte"))
                          )
                          (princ "\n    Keine Objekte ausgewaehlt")
                        )
                       )
                       ;; ENTFERNEN
                       ((= inner-kw "Entfernen")
                        (if inner-pts
                          (progn
                            (setq pt (getpoint "\n  Punkt zum Entfernen waehlen: "))
                            (if pt
                              (progn
                                (setq min-dist 1e30 index nil i 0)
                                (foreach ip inner-pts
                                  (setq dist (distance pt ip))
                                  (if (< dist min-dist) (progn (setq min-dist dist) (setq index i)))
                                  (setq i (1+ i))
                                )
                                (if (and index (< min-dist (* 2.0 scale)))
                                  (progn
                                    (setq ent (nth index inner-entities))
                                    (if (and ent (entget ent)) (entdel ent))
                                    (setq inner-pts (HAFM:remove-nth inner-pts index))
                                    (setq inner-heights (HAFM:remove-nth inner-heights index))
                                    (setq inner-entities (HAFM:remove-nth inner-entities index))
                                    (princ (strcat "\n    Entfernt (" (itoa (length inner-pts)) " verbleibend)"))
                                    (HAFM:log-write "INFO" "Innerer Punkt entfernt")
                                  )
                                  (princ "\n*** Kein innerer Punkt in der Naehe ***")
                                )
                              )
                            )
                          )
                          (princ "\n  Keine inneren Punkte vorhanden")
                        )
                       )
                     ) ;; end cond
                   ) ;; end while
                  )

                  
                  ;; ---- BRUCHKANTEN ----
                  ((= choice "Bruchkanten")
                   (princ (strcat "\n--- Bruchkanten (" (itoa (length breaklines)) " vorhanden) ---"))
                   (setq done-bl nil)
                   (while (not done-bl)
                     (initget "Neu Loeschen Fertig")
                     (setq bl-kw (getkword "\n  Bruchkante [Neu/Loeschen/Fertig]: "))
                     (cond
                       ;; FERTIG oder ENTER
                       ((or (null bl-kw) (= bl-kw "Fertig"))
                        (setq done-bl T)
                       )
                       ;; NEU
                       ((= bl-kw "Neu")
                        (setq current-bl nil current-bl-heights nil current-bl-entities nil)
                        (setq bl-number 1 bl-count (1+ (length breaklines)))
                        (princ (strcat "\n  --- Bruchkante " (itoa bl-count) " (min. 2 Punkte) ---"))
                        (setq done-bk-pts nil)
                        (while (not done-bk-pts)
                          (if (>= bl-number 3) (initget "Fertig"))
                          (setq pick-result (HAFM:pick-or-place
                            (strcat "\n  BK" (itoa bl-count) " Punkt " (itoa bl-number)
                                    (if (>= bl-number 2) " [Fertig]" "") ": ") scale))
                          (cond
                            ;; Fertig oder ENTER bei >= 2 Punkten
                            ((or (= pick-result "Fertig")
                                 (and (null pick-result) (>= (length current-bl) 2)))
                             (if (>= (length current-bl) 2)
                               (progn
                                 (setq breaklines (append breaklines (list current-bl)))
                                 (setq breakline-entities (append breakline-entities (list current-bl-entities)))
                                 (HAFM:log-write "INFO" (strcat "Bruchkante " (itoa bl-count)
                                   ": " (itoa (length current-bl)) " Punkte"))
                                 (princ (strcat "\n    BK" (itoa bl-count) ": "
                                   (itoa (length current-bl)) " Punkte"))
                               )
                             )
                             (setq done-bk-pts T)
                            )
                            ;; ENTER bei < 2 Punkten = abbrechen
                            ((null pick-result)
                             (princ "\n  Bruchkante abgebrochen")
                             (setq done-bk-pts T)
                            )
                            ;; Gueltiger Punkt
                            ((listp pick-result)
                             (setq pt (car pick-result) ht (cadr pick-result) from-block (caddr pick-result))
                             (if (not ht) (setq ht (HAFM:get-validated-height "\n    Hoehe" *HAFM:last-height*)))
                             (if ht
                               (progn
                                 (setq *HAFM:last-height* ht)
                                 (if (not from-block)
                                   (setq block-ent (HAFM:insert-block pt ht scale nil))
                                   (setq block-ent nil))
                                 (setq current-bl (append current-bl (list (list (car pt) (cadr pt) ht))))
                                 (setq current-bl-heights (append current-bl-heights (list ht)))
                                 (setq current-bl-entities (append current-bl-entities (list block-ent)))
                                 (HAFM:log-write "INFO" (strcat "BK Punkt " (itoa bl-number)
                                   ": (" (rtos (car pt) 2 3) " " (rtos (cadr pt) 2 3)
                                   ") H=" (rtos ht 2 3)))
                                 (setq bl-number (1+ bl-number))
                               )
                             )
                            )
                          )
                        ) ;; end while BK-Punkte
                       )
                       ;; LOESCHEN
                       ((= bl-kw "Loeschen")
                        (if breaklines
                          (progn
                            (setq i 1)
                            (foreach bl breaklines
                              (princ (strcat "\n    " (itoa i) ". BK (" (itoa (length bl)) " Punkte)"))
                              (setq i (1+ i)))
                            (setq result (getint "\n  Welche loeschen (Nummer): "))
                            (if (and result (> result 0) (<= result (length breaklines)))
                              (progn
                                (foreach ent (nth (1- result) breakline-entities)
                                  (if (and ent (entget ent)) (entdel ent)))
                                (setq breaklines (HAFM:remove-nth breaklines (1- result)))
                                (setq breakline-entities (HAFM:remove-nth breakline-entities (1- result)))
                                (princ (strcat "\n    BK" (itoa result) " geloescht"))
                                (HAFM:log-write "INFO" (strcat "BK " (itoa result) " geloescht"))
                              )
                              (princ "\n*** Ungueltige Nummer ***")
                            )
                          )
                          (princ "\n  Keine Bruchkanten vorhanden")
                        )
                       )
                     ) ;; end cond
                   ) ;; end while
                  )
                  
                  ;; ---- LOECHER ----
                  ((= choice "Loecher")
                   (princ (strcat "\n--- Loecher (" (itoa (length holes)) " vorhanden) ---"))
                   (setq done-hole nil)
                   (while (not done-hole)
                     (initget "Neu Loeschen Fertig")
                     (setq hole-kw (getkword "\n  Loch [Neu/Loeschen/Fertig]: "))
                     (cond
                       ;; FERTIG oder ENTER
                       ((or (null hole-kw) (= hole-kw "Fertig"))
                        (setq done-hole T)
                       )
                       ;; NEU
                       ((= hole-kw "Neu")
                        (setq current-hole nil)
                        (setq hole-number 1 hole-count (1+ (length holes)))
                        (princ (strcat "\n  --- Loch " (itoa hole-count) " (min. 3 Punkte) ---"))
                        (setq done-hole-pts nil)
                        (while (not done-hole-pts)
                          (if (>= hole-number 4) (initget "Schliessen"))
                          (setq pt (getpoint (strcat "\n  Loch" (itoa hole-count)
                            " Punkt " (itoa hole-number)
                            (if (>= hole-number 4) " [Schliessen]" "") ": ")))
                          (cond
                            ((or (= pt "Schliessen")
                                 (and (null pt) (>= (length current-hole) 3)))
                             (if (>= (length current-hole) 3)
                               (progn
                                 (setq holes (append holes (list current-hole)))
                                 (HAFM:log-write "INFO" (strcat "Loch " (itoa hole-count)
                                   ": " (itoa (length current-hole)) " Punkte"))
                                 (princ (strcat "\n    Loch" (itoa hole-count) ": "
                                   (itoa (length current-hole)) " Punkte (geschlossen)"))
                               )
                             )
                             (setq done-hole-pts T)
                            )
                            ((null pt)
                             (princ "\n  Loch abgebrochen")
                             (setq done-hole-pts T)
                            )
                            ((listp pt)
                             (setq current-hole (append current-hole (list (list (car pt) (cadr pt)))))
                             (HAFM:log-write "INFO" (strcat "Loch Punkt " (itoa hole-number)
                               ": (" (rtos (car pt) 2 3) " " (rtos (cadr pt) 2 3) ")"))
                             (setq hole-number (1+ hole-number))
                            )
                          )
                        )
                       )
                       ;; LOESCHEN
                       ((= hole-kw "Loeschen")
                        (if holes
                          (progn
                            (setq i 1)
                            (foreach h holes
                              (princ (strcat "\n    " (itoa i) ". Loch (" (itoa (length h)) " Punkte)"))
                              (setq i (1+ i)))
                            (setq result (getint "\n  Welches loeschen (Nummer): "))
                            (if (and result (> result 0) (<= result (length holes)))
                              (progn
                                (setq holes (HAFM:remove-nth holes (1- result)))
                                (princ (strcat "\n    Loch" (itoa result) " geloescht"))
                              )
                              (princ "\n*** Ungueltige Nummer ***")
                            )
                          )
                          (princ "\n  Keine Loecher vorhanden")
                        )
                       )
                     ) ;; end cond
                   ) ;; end while
                  )
                )
              ) ;; end while Hauptmenue
              
              ;; ================================================================
              ;; PHASE 2: BERECHNUNG + SPEICHERUNG
              ;; ================================================================
              
              (princ "\n\n=== Berechnung ===")
              
              ;; Live-Umrandung loeschen (wird als Teil des Outputs neu gezeichnet)
              (if (and outline-ent (entget outline-ent))
                (progn (entdel outline-ent) (setq outline-ent nil))
              )
              
              ;; Surface-Data zusammenbauen
              (setq surface-data
                (list
                  (cons "BOUNDARY"    boundary-pts)
                  (cons "BREAKLINES"  breaklines)
                  (cons "INNER_PTS"   inner-pts)
                  (cons "HOLES"       holes)
                  (cons "SETTINGS"    (list (cons "SCALE" (rtos scale 2 4))))
                  (cons "ENTITY_HANDLES" nil)  ;; wird nach Zeichnen aktualisiert
                )
              )
              
              ;; TIN berechnen
              (setq tin-result (HAFM:rebuild-tin surface-data))
              
              (if tin-result
                (progn
                  (setq all-pts (car tin-result))
                  (setq triangles (cadr tin-result))
                  (setq num-boundary (caddr tin-result))
                  (setq *HAFM:tin-triangles* triangles)
                  
                  (princ (strcat "\n  " (itoa (length all-pts)) " Punkte, "
                    (itoa (length triangles)) " Dreiecke"))
                  
                  ;; TIN zeichnen
                  (setq tin-entities (HAFM:draw-tin all-pts
                    (append boundary-heights
                            (apply 'append (mapcar '(lambda (bl) 
                              (mapcar 'caddr bl)) breaklines))
                            inner-heights)
                    triangles))
                  (princ (strcat "\n  TIN gezeichnet (" (itoa (length tin-entities)) " Dreiecke)"))
                  
                  ;; Nur Zeichnungs-Entities sammeln (Outline + TIN)
                  ;; NICHT die User-Bloecke (boundary-entities, inner-entities)!
                  (setq all-entities
                    (append
                      (list outline-ent)
                      tin-entities
                    )
                  )
                  ;; nil-Werte entfernen
                  (setq all-entities (vl-remove nil all-entities))
                  
                  ;; Handles in surface-data aktualisieren
                  (setq surface-data
                    (subst
                      (cons "ENTITY_HANDLES" (HAFM:collect-handles all-entities))
                      (assoc "ENTITY_HANDLES" surface-data)
                      surface-data
                    )
                  )
                  
                  ;; Im Dictionary speichern
                  (HAFM:save-surface surface-name surface-data)
                  
                  (princ (strcat "\n\n  Oberflaeche \"" surface-name "\" gespeichert!"))
                  
                  ;; ============================================================
                  ;; PHASE 3: INTERPOLATION (Punkte setzen, Raster, Hoehenlinien)
                  ;; ============================================================
                  
                  (princ "\n\n--- Punkte setzen (S/H/R/E, ESC=Ende) ---")
                  (setq done nil grid-entities nil contour-entities nil use-diagonal nil)
                  
                  ;; Alle Hoehen zusammenbauen (gleiche Reihenfolge wie all-pts)
                  (setq all-heights
                    (append boundary-heights
                            (apply 'append (mapcar '(lambda (bl)
                              (mapcar 'caddr bl)) breaklines))
                            inner-heights))
                  
                  (while (not done)
                    (initget "Skalierung Hoehenlinie Raster Einstellungen")
                    (setq pg (getpoint
                      "\nPunkt waehlen [Skalierung/Hoehenlinie/Raster/Einstellungen]: "))
                    
                    (cond
                      ;; Skalierung
                      ((= pg "Skalierung")
                       (setq scale (getreal (strcat "\nSkalierung <" (rtos scale 2 2) ">: ")))
                       (if (null scale) (setq scale *HAFM:default-scale*))
                      )
                      ;; Raster
                      ((= pg "Raster")
                       (if grid-entities (HAFM:delete-grid grid-entities))
                       (setq grid-entities nil)
                       (setq target-h (getreal (strcat "\nRaster-Abstand N <"
                         (rtos *HAFM:grid-interval* 2 2) ">: ")))
                       (if (null target-h) (setq target-h *HAFM:grid-interval*))
                       (if (> target-h 0.0)
                         (progn
                           (setq *HAFM:grid-interval* target-h)
                           (setq grid-entities (HAFM:draw-grid all-pts all-heights
                             use-diagonal target-h))
                         )
                         (princ "\n*** Abstand muss > 0 sein ***")
                       )
                      )
                      ;; Hoehenlinie
                      ((= pg "Hoehenlinie")
                       (if contour-entities (HAFM:delete-contours contour-entities))
                       (setq contour-entities nil)
                       (setq target-h (getreal "\nHoehe fuer Hoehenlinie: "))
                       (if target-h
                         (progn
                           (setq segments (HAFM:compute-contour all-pts all-heights
                             target-h use-diagonal))
                           (if segments
                             (progn
                               (setq contour-entities (HAFM:draw-contour segments nil))
                               (princ (strcat "\n  Hoehenlinie bei " (rtos target-h 2 2)
                                 " (" (itoa (length segments)) " Segment(e))"))
                             )
                             (princ "\n  Keine Hoehenlinie bei dieser Hoehe")
                           )
                         )
                       )
                      )
                      ;; Einstellungen (placeholder)
                      ((= pg "Einstellungen")
                       (HAFM:show-settings)
                      )
                      ;; ESC / nil = Ende
                      ((null pg)
                       (setq done T)
                      )
                      ;; Gueltiger Punkt — interpolieren
                      ((HAFM:valid-point-p pg)
                       (setq result (HAFM:interpolate-tin pg all-pts all-heights triangles))
                       (if result
                         (progn
                           (setq interpolated-height (car result))
                           (setq tri-info (cadr result))
                           (princ (strcat "\n  Hoehe: " (HAFM:format-height interpolated-height)
                             " (" tri-info ")"))
                           ;; Block einfuegen
                           (HAFM:insert-block pg interpolated-height scale nil)
                           (HAFM:log-write "INFO" (strcat "Interpolation: ("
                             (rtos (car pg) 2 3) " " (rtos (cadr pg) 2 3)
                             ") -> " (rtos interpolated-height 2 4) " (" tri-info ")"))
                         )
                         (princ "\n*** Punkt ausserhalb der Oberflaeche ***")
                       )
                      )
                    )
                  ) ;; end while Interpolation
                  
                  ;; Cleanup
                  (setq *HAFM:tin-triangles* nil)
                )
                ;; TIN Berechnung fehlgeschlagen
                (princ "\n*** FEHLER: Triangulation fehlgeschlagen ***")
              )
              
              (HAFM:log-write "INFO" "=== HAFNEW beendet ===")
            )
          ) ;; end if >= 3 Boundary
        )
      ) ;; end if Name existiert
    )
  ) ;; end if Name angegeben
  
  ;; Cleanup
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (if old-attdia (setvar "ATTDIA" old-attdia))
  (princ)
)

;;; ============================================================================
;;; HAFEDIT - Oberflaeche bearbeiten
;;; ============================================================================
;;;
;;; Laedt bestehende Oberflaeche aus Dictionary
;;; Zeigt gleiches Hauptmenue wie HAFNEW (I/B/L/U/S/C)
;;; Plus: Umrandung bearbeiten (U)
;;; Aenderungen → Berechnen → Speichern

(defun c:HAFEDIT ( / *error* old-cmdecho old-attdia
                      surface-name surfaces data
                      boundary-pts boundary-heights boundary-entities
                      inner-pts inner-heights inner-entities
                      breaklines breakline-entities
                      holes hole-entities
                      current-bl current-bl-heights
                      current-hole
                      all-entities
                      pt ht result block-ent scale done
                      choice
                      bl-number hole-number bl-count hole-count
                      pick-result from-block
                      surface-data tin-result all-pts triangles num-boundary all-heights
                      tin-entities outline-ent
                      grid-entities contour-entities target-h segments
                      use-diagonal interpolated-height tri-info pg
                      ;; Sub-Menue Variablen (eigene pro Menue!)
                      inner-kw done-inner inner-count
                      bl-kw done-bl done-bk-pts
                      hole-kw done-hole done-hole-pts
                      umr-kw done-umr
                      ;; Allgemein
                      ent ent-data attrib-ent attrib-data block-name ss-result
                      min-dist index i dist)
  
  (HAFM:ensure-init)
  
  ;; Lokaler Error-Handler
  (defun *error* (msg)
    (if (not (HAFM:cancel-p msg))
      (progn
        (princ (strcat "\nFehler: " msg))
        (HAFM:log-write "ERROR" (strcat "HAFEDIT Error: " msg))
      )
      (HAFM:log-write "INFO" (strcat "User-Abbruch: " msg))
    )
    (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
    (if old-attdia (setvar "ATTDIA" old-attdia))
    (princ)
  )
  
  (setq old-cmdecho (getvar "CMDECHO"))
  (setq old-attdia (getvar "ATTDIA"))
  (setvar "CMDECHO" 0)
  (setvar "ATTDIA" 0)
  
  (HAFM:log-write "INFO" "=== HAFEDIT gestartet ===")
  
  ;; Oberflaeche waehlen
  (setq surfaces (HAFM:list-surfaces))
  (if (null surfaces)
    (progn
      (princ "\n  Keine Oberflaechen vorhanden. Verwende HAFNEW.")
      (setvar "CMDECHO" old-cmdecho)
      (setvar "ATTDIA" old-attdia)
      (princ)
    )
    (progn
      (princ "\nVorhandene Oberflaechen:")
      (foreach s surfaces (princ (strcat "\n  " s)))
      (setq surface-name (getstring T "\nOberflaeche waehlen: "))
      
      (if (not (member surface-name surfaces))
        (progn
          (princ (strcat "\n*** \"" surface-name "\" nicht gefunden ***"))
          (setvar "CMDECHO" old-cmdecho)
          (setvar "ATTDIA" old-attdia)
          (princ)
        )
        (progn
          ;; Quelldaten laden
          (setq data (HAFM:load-surface surface-name))
          (HAFM:log-write "INFO" (strcat "HAFEDIT: " surface-name " geladen"))
          
          ;; Quelldaten in lokale Listen entpacken
          (setq boundary-pts   (cdr (assoc "BOUNDARY"   data)))
          (setq breaklines     (cdr (assoc "BREAKLINES" data)))
          (setq inner-pts      (cdr (assoc "INNER_PTS"  data)))
          (setq holes          (cdr (assoc "HOLES"      data)))
          
          ;; Hoehen aus Boundary extrahieren (Z-Wert der Punkte)
          (setq boundary-heights (mapcar 'caddr boundary-pts))
          ;; Innere Hoehen
          (setq inner-heights (mapcar 'caddr inner-pts))
          ;; Entity-Listen (leer bei Edit — alte Entities bleiben)
          (setq boundary-entities (mapcar '(lambda (x) nil) boundary-pts))
          (setq inner-entities (mapcar '(lambda (x) nil) inner-pts))
          (setq breakline-entities (mapcar '(lambda (bl) (mapcar '(lambda (x) nil) bl)) breaklines))
          (setq hole-entities nil)
          (setq outline-ent nil)
          
          ;; Alte Entities loeschen
          (HAFM:delete-surface-entities data)
          
          ;; Skalierung
          (setq scale *HAFM:default-scale*)
          (setq result (cdr (assoc "SETTINGS" data)))
          (if result
            (progn
              (setq result (cdr (assoc "SCALE" result)))
              (if (and result (/= result "")) (setq scale (atof result)))
            )
          )
          
          ;; Status anzeigen
          (princ (strcat "\n\n=== Bearbeite \"" surface-name "\" ==="))
          (princ (strcat "\n  Umrandung:   " (itoa (length boundary-pts)) " Punkte"))
          (princ (strcat "\n  Innere:      " (itoa (length inner-pts)) " Punkte"))
          (princ (strcat "\n  Bruchkanten: " (itoa (length breaklines))))
          (princ (strcat "\n  Loecher:     " (itoa (length holes))))
          
          ;; ================================================================
          ;; HAUPTMENUE (gleich wie HAFNEW, plus Umrandung bearbeiten)
          ;; ================================================================
          
          (setq done nil)
          (while (not done)
            (initget "Umrandung Innere Bruchkanten Loecher Status Compute")
            (setq choice (getkword
              "\nWas aendern [Umrandung/Innere/Bruchkanten/Loecher/Status/Compute]: "))
            
            (cond
              ;; ---- BERECHNEN ----
              ((or (= choice "Compute") (null choice))
               (setq done T)
               (HAFM:log-write "INFO" "HAFEDIT: Berechnung gestartet")
              )
              
              ;; ---- STATUS ----
              ((= choice "Status")
               (princ (strcat "\n\n=== Status \"" surface-name "\" ==="))
               (princ (strcat "\n  Umrandung:    " (itoa (length boundary-pts)) " Punkte"))
               (princ (strcat "\n  Innere:       " (itoa (length inner-pts)) " Punkte"))
               (princ (strcat "\n  Bruchkanten:  " (itoa (length breaklines))))
               (princ (strcat "\n  Loecher:      " (itoa (length holes))))
               (princ "\n")
              )
              
              ;; ---- UMRANDUNG BEARBEITEN ----
              ((= choice "Umrandung")
               (princ (strcat "\n--- Umrandung (" (itoa (length boundary-pts)) " Punkte) ---"))
               (setq done-umr nil)
               (while (not done-umr)
                 (initget "Anfuegen Entfernen Hoehe Fertig")
                 (setq umr-kw (getkword "\n  Umrandung [Anfuegen/Entfernen/Hoehe/Fertig]: "))
                 (cond
                   ((or (null umr-kw) (= umr-kw "Fertig"))
                    (setq done-umr T)
                   )
                   ((= umr-kw "Anfuegen")
                    (setq pick-result (HAFM:pick-or-place "\n  Neuer Umrandungspunkt: " scale))
                    (if (and pick-result (listp pick-result))
                      (progn
                        (setq pt (car pick-result) ht (cadr pick-result))
                        (if (not ht) (setq ht (HAFM:get-validated-height "\n    Hoehe" *HAFM:last-height*)))
                        (if ht
                          (progn
                            (setq *HAFM:last-height* ht)
                            (setq boundary-pts (append boundary-pts (list (list (car pt) (cadr pt) ht))))
                            (setq boundary-heights (append boundary-heights (list ht)))
                            (setq boundary-entities (append boundary-entities (list nil)))
                            (princ (strcat "\n    Hinzugefuegt (" (itoa (length boundary-pts)) " gesamt)"))
                            (HAFM:log-write "INFO" (strcat "Umrandung +Punkt: H=" (rtos ht 2 3)))
                          )
                        )
                      )
                    )
                   )
                   ((= umr-kw "Entfernen")
                    (if (> (length boundary-pts) 3)
                      (progn
                        (setq pt (getpoint "\n  Punkt zum Entfernen waehlen: "))
                        (if pt
                          (progn
                            (setq min-dist 1e30 index nil i 0)
                            (foreach bp boundary-pts
                              (setq dist (distance pt bp))
                              (if (< dist min-dist) (progn (setq min-dist dist) (setq index i)))
                              (setq i (1+ i))
                            )
                            (if (and index (< min-dist (* 2.0 scale)))
                              (progn
                                (setq boundary-pts (HAFM:remove-nth boundary-pts index))
                                (setq boundary-heights (HAFM:remove-nth boundary-heights index))
                                (setq boundary-entities (HAFM:remove-nth boundary-entities index))
                                (princ (strcat "\n    Entfernt (" (itoa (length boundary-pts)) " verbleibend)"))
                              )
                              (princ "\n*** Kein Punkt in der Naehe ***")
                            )
                          )
                        )
                      )
                      (princ "\n*** Mindestens 3 Punkte muessen bleiben ***")
                    )
                   )
                   ((= umr-kw "Hoehe")
                    (setq pt (getpoint "\n  Punkt waehlen: "))
                    (if pt
                      (progn
                        (setq min-dist 1e30 index nil i 0)
                        (foreach bp boundary-pts
                          (setq dist (distance pt bp))
                          (if (< dist min-dist) (progn (setq min-dist dist) (setq index i)))
                          (setq i (1+ i))
                        )
                        (if (and index (< min-dist (* 2.0 scale)))
                          (progn
                            (setq ht (getreal (strcat "\n    Neue Hoehe <"
                              (rtos (nth index boundary-heights) 2 2) ">: ")))
                            (if ht
                              (progn
                                (setq boundary-heights (HAFM:replace-nth boundary-heights index ht))
                                (setq pt (nth index boundary-pts))
                                (setq boundary-pts (HAFM:replace-nth boundary-pts index
                                  (list (car pt) (cadr pt) ht)))
                                (princ (strcat "\n    Hoehe geaendert: " (HAFM:format-height ht)))
                              )
                            )
                          )
                          (princ "\n*** Kein Punkt in der Naehe ***")
                        )
                      )
                    )
                   )
                 ) ;; end cond
               ) ;; end while
              )
              
              ;; ---- INNERE PUNKTE ----
              ((= choice "Innere")
               (princ (strcat "\n--- Innere Punkte (" (itoa (length inner-pts)) " vorhanden) ---"))
               (setq done-inner nil)
               (while (not done-inner)
                 (initget "Punkt Window Entfernen Fertig")
                 (setq inner-kw (getkword "\n  Innere [Punkt/Window/Entfernen/Fertig]: "))
                 (cond
                   ((or (null inner-kw) (= inner-kw "Fertig"))
                    (setq done-inner T)
                   )
                   ((= inner-kw "Punkt")
                    (setq pick-result (HAFM:pick-or-place
                      (strcat "\n  Innerer Punkt " (itoa (1+ (length inner-pts))) ": ") scale))
                    (if (and pick-result (listp pick-result))
                      (progn
                        (setq pt (car pick-result) ht (cadr pick-result))
                        (if (not ht) (setq ht (HAFM:get-validated-height "\n    Hoehe" *HAFM:last-height*)))
                        (if ht
                          (progn
                            (setq *HAFM:last-height* ht)
                            (setq inner-pts (append inner-pts (list (list (car pt) (cadr pt) ht))))
                            (setq inner-heights (append inner-heights (list ht)))
                            (setq inner-entities (append inner-entities (list nil)))
                            (princ (strcat "\n    " (HAFM:format-height ht) " ("
                              (itoa (length inner-pts)) " gesamt)"))
                          )
                        )
                      )
                    )
                   )
                   ((= inner-kw "Window")
                    (princ "\n  Fenster ueber Hoehenkoten-Bloecke ziehen:")
                    (setq ss-result (ssget '((0 . "INSERT"))))
                    (if ss-result
                      (progn
                        (setq inner-count 0 i 0)
                        (while (< i (sslength ss-result))
                          (setq ent (ssname ss-result i))
                          (setq ent-data (entget ent))
                          (setq block-name (cdr (assoc 2 ent-data)))
                          (if (wcmatch (strcase block-name) "*HOEHENKOTE*,*HK*,*BLK_H*")
                            (progn
                              (setq ht nil attrib-ent (entnext ent))
                              (while (and attrib-ent (not ht))
                                (setq attrib-data (entget attrib-ent))
                                (if (and (= (cdr (assoc 0 attrib-data)) "ATTRIB")
                                         (wcmatch (strcase (cdr (assoc 2 attrib-data)))
                                                  "HOEHE,HEIGHT,H"))
                                  (setq ht (atof (cdr (assoc 1 attrib-data))))
                                )
                                (setq attrib-ent (entnext attrib-ent))
                              )
                              (if ht
                                (progn
                                  (setq pt (cdr (assoc 10 ent-data)))
                                  (if (HAFM:point-in-polygon pt boundary-pts)
                                    (progn
                                      (setq inner-pts (append inner-pts (list (list (car pt) (cadr pt) ht))))
                                      (setq inner-heights (append inner-heights (list ht)))
                                      (setq inner-entities (append inner-entities (list nil)))
                                      (setq inner-count (1+ inner-count))
                                    )
                                  )
                                )
                              )
                            )
                          )
                          (setq i (1+ i))
                        )
                        (princ (strcat "\n    " (itoa inner-count) " Punkte uebernommen"))
                      )
                      (princ "\n    Keine Objekte ausgewaehlt")
                    )
                   )
                   ((= inner-kw "Entfernen")
                    (if inner-pts
                      (progn
                        (setq pt (getpoint "\n  Punkt waehlen: "))
                        (if pt
                          (progn
                            (setq min-dist 1e30 index nil i 0)
                            (foreach ip inner-pts
                              (setq dist (distance pt ip))
                              (if (< dist min-dist) (progn (setq min-dist dist) (setq index i)))
                              (setq i (1+ i))
                            )
                            (if (and index (< min-dist (* 2.0 scale)))
                              (progn
                                (setq inner-pts (HAFM:remove-nth inner-pts index))
                                (setq inner-heights (HAFM:remove-nth inner-heights index))
                                (setq inner-entities (HAFM:remove-nth inner-entities index))
                                (princ (strcat "\n    Entfernt (" (itoa (length inner-pts)) " verbleibend)"))
                              )
                              (princ "\n*** Kein Punkt in der Naehe ***")
                            )
                          )
                        )
                      )
                      (princ "\n  Keine inneren Punkte vorhanden")
                    )
                   )
                 ) ;; end cond
               ) ;; end while
              )
              
              ;; ---- BRUCHKANTEN ----
              ((= choice "Bruchkanten")
               (princ (strcat "\n--- Bruchkanten (" (itoa (length breaklines)) " vorhanden) ---"))
               (setq done-bl nil)
               (while (not done-bl)
                 (initget "Neu Loeschen Fertig")
                 (setq bl-kw (getkword "\n  Bruchkante [Neu/Loeschen/Fertig]: "))
                 (cond
                   ((or (null bl-kw) (= bl-kw "Fertig"))
                    (setq done-bl T)
                   )
                   ((= bl-kw "Neu")
                    (setq current-bl nil current-bl-heights nil)
                    (setq bl-number 1 bl-count (1+ (length breaklines)))
                    (princ (strcat "\n  --- BK " (itoa bl-count) " (min. 2 Punkte) ---"))
                    (setq done-bk-pts nil)
                    (while (not done-bk-pts)
                      (if (>= bl-number 3) (initget "Fertig"))
                      (setq pick-result (HAFM:pick-or-place
                        (strcat "\n  BK" (itoa bl-count) " Punkt " (itoa bl-number)
                          (if (>= bl-number 2) " [Fertig]" "") ": ") scale))
                      (cond
                        ((or (= pick-result "Fertig")
                             (and (null pick-result) (>= (length current-bl) 2)))
                         (if (>= (length current-bl) 2)
                           (progn
                             (setq breaklines (append breaklines (list current-bl)))
                             (princ (strcat "\n    BK" (itoa bl-count) ": "
                               (itoa (length current-bl)) " Punkte"))
                           )
                         )
                         (setq done-bk-pts T)
                        )
                        ((null pick-result)
                         (princ "\n  Bruchkante abgebrochen")
                         (setq done-bk-pts T)
                        )
                        ((listp pick-result)
                         (setq pt (car pick-result) ht (cadr pick-result))
                         (if (not ht) (setq ht (HAFM:get-validated-height "\n    Hoehe" *HAFM:last-height*)))
                         (if ht
                           (progn
                             (setq *HAFM:last-height* ht)
                             (setq current-bl (append current-bl (list (list (car pt) (cadr pt) ht))))
                             (setq bl-number (1+ bl-number))
                           )
                         )
                        )
                      )
                    )
                   )
                   ((= bl-kw "Loeschen")
                    (if breaklines
                      (progn
                        (setq i 1)
                        (foreach bl breaklines
                          (princ (strcat "\n    " (itoa i) ". BK (" (itoa (length bl)) " Pkt)"))
                          (setq i (1+ i)))
                        (setq result (getint "\n  Welche loeschen: "))
                        (if (and result (> result 0) (<= result (length breaklines)))
                          (progn
                            (setq breaklines (HAFM:remove-nth breaklines (1- result)))
                            (princ (strcat "\n    BK" (itoa result) " geloescht"))
                          )
                          (princ "\n*** Ungueltig ***")
                        )
                      )
                      (princ "\n  Keine vorhanden")
                    )
                   )
                 ) ;; end cond
               ) ;; end while
              )
              
              ;; ---- LOECHER ----
              ((= choice "Loecher")
               (princ (strcat "\n--- Loecher (" (itoa (length holes)) " vorhanden) ---"))
               (setq done-hole nil)
               (while (not done-hole)
                 (initget "Neu Loeschen Fertig")
                 (setq hole-kw (getkword "\n  Loch [Neu/Loeschen/Fertig]: "))
                 (cond
                   ((or (null hole-kw) (= hole-kw "Fertig"))
                    (setq done-hole T)
                   )
                   ((= hole-kw "Neu")
                    (setq current-hole nil hole-number 1 hole-count (1+ (length holes)))
                    (princ (strcat "\n  --- Loch " (itoa hole-count) " (min. 3 Pkt) ---"))
                    (setq done-hole-pts nil)
                    (while (not done-hole-pts)
                      (if (>= hole-number 4) (initget "Schliessen"))
                      (setq pt (getpoint (strcat "\n  Loch Punkt " (itoa hole-number)
                        (if (>= hole-number 4) " [Schliessen]" "") ": ")))
                      (cond
                        ((or (= pt "Schliessen")
                             (and (null pt) (>= (length current-hole) 3)))
                         (if (>= (length current-hole) 3)
                           (progn
                             (setq holes (append holes (list current-hole)))
                             (princ (strcat "\n    Loch: " (itoa (length current-hole)) " Punkte"))
                           )
                         )
                         (setq done-hole-pts T)
                        )
                        ((null pt)
                         (princ "\n  Loch abgebrochen")
                         (setq done-hole-pts T)
                        )
                        ((listp pt)
                         (setq current-hole (append current-hole (list (list (car pt) (cadr pt)))))
                         (setq hole-number (1+ hole-number))
                        )
                      )
                    )
                   )
                   ((= hole-kw "Loeschen")
                    (if holes
                      (progn
                        (setq i 1)
                        (foreach h holes
                          (princ (strcat "\n    " (itoa i) ". Loch (" (itoa (length h)) " Pkt)"))
                          (setq i (1+ i)))
                        (setq result (getint "\n  Welches loeschen: "))
                        (if (and result (> result 0) (<= result (length holes)))
                          (progn
                            (setq holes (HAFM:remove-nth holes (1- result)))
                            (princ (strcat "\n    Loch" (itoa result) " geloescht"))
                          )
                          (princ "\n*** Ungueltig ***")
                        )
                      )
                      (princ "\n  Keine vorhanden")
                    )
                   )
                 ) ;; end cond
               ) ;; end while
              )
            )
          ) ;; end while Hauptmenue
          
          ;; ================================================================
          ;; NEU BERECHNEN + SPEICHERN
          ;; ================================================================
          
          (princ "\n\n=== Neu-Berechnung ===")
          
          (setq surface-data
            (list
              (cons "BOUNDARY"    boundary-pts)
              (cons "BREAKLINES"  breaklines)
              (cons "INNER_PTS"   inner-pts)
              (cons "HOLES"       holes)
              (cons "SETTINGS"    (list (cons "SCALE" (rtos scale 2 4))))
              (cons "ENTITY_HANDLES" nil)
            )
          )
          
          (setq tin-result (HAFM:rebuild-tin surface-data))
          
          (if tin-result
            (progn
              (setq all-pts (car tin-result))
              (setq triangles (cadr tin-result))
              (setq num-boundary (caddr tin-result))
              (setq *HAFM:tin-triangles* triangles)
              
              (princ (strcat "\n  " (itoa (length all-pts)) " Punkte, "
                (itoa (length triangles)) " Dreiecke"))
              
              ;; Alle Hoehen zusammenbauen
              (setq all-heights
                (append boundary-heights
                  (apply 'append (mapcar '(lambda (bl) (mapcar 'caddr bl)) breaklines))
                  inner-heights))
              
              ;; TIN zeichnen
              (setq tin-entities (HAFM:draw-tin all-pts all-heights triangles))
              
              ;; Umrandung zeichnen
              (setq outline-ent (HAFM:draw-outline boundary-pts boundary-heights))
              
              ;; Entities sammeln + speichern
              (setq all-entities (vl-remove nil
                (append (list outline-ent) tin-entities)))
              (setq surface-data
                (subst
                  (cons "ENTITY_HANDLES" (HAFM:collect-handles all-entities))
                  (assoc "ENTITY_HANDLES" surface-data)
                  surface-data))
              
              (HAFM:save-surface surface-name surface-data)
              (princ (strcat "\n\n  Oberflaeche \"" surface-name "\" aktualisiert!"))
              
              ;; ---- Interpolation ----
              (princ "\n\n--- Punkte setzen (S/H/R/E, ESC=Ende) ---")
              (setq done nil grid-entities nil contour-entities nil use-diagonal nil)
              
              (while (not done)
                (initget "Skalierung Hoehenlinie Raster")
                (setq pg (getpoint "\nPunkt [Skalierung/Hoehenlinie/Raster]: "))
                (cond
                  ((= pg "Skalierung")
                   (setq scale (getreal (strcat "\nSkalierung <" (rtos scale 2 2) ">: ")))
                   (if (null scale) (setq scale *HAFM:default-scale*))
                  )
                  ((= pg "Raster")
                   (if grid-entities (HAFM:delete-grid grid-entities))
                   (setq target-h (getreal (strcat "\nRaster N <" (rtos *HAFM:grid-interval* 2 2) ">: ")))
                   (if (null target-h) (setq target-h *HAFM:grid-interval*))
                   (if (> target-h 0.0)
                     (progn
                       (setq *HAFM:grid-interval* target-h)
                       (setq grid-entities (HAFM:draw-grid all-pts all-heights use-diagonal target-h))
                     )
                   )
                  )
                  ((= pg "Hoehenlinie")
                   (if contour-entities (HAFM:delete-contours contour-entities))
                   (setq target-h (getreal "\nHoehe: "))
                   (if target-h
                     (progn
                       (setq segments (HAFM:compute-contour all-pts all-heights target-h use-diagonal))
                       (if segments
                         (setq contour-entities (HAFM:draw-contour segments nil))
                         (princ "\n  Keine Hoehenlinie")
                       )
                     )
                   )
                  )
                  ((null pg) (setq done T))
                  ((HAFM:valid-point-p pg)
                   (setq result (HAFM:interpolate-tin pg all-pts all-heights triangles))
                   (if result
                     (progn
                       (princ (strcat "\n  " (HAFM:format-height (car result)) " (" (cadr result) ")"))
                       (HAFM:insert-block pg (car result) scale nil)
                     )
                     (princ "\n*** Ausserhalb ***")
                   )
                  )
                )
              )
              
              (setq *HAFM:tin-triangles* nil)
            )
            (princ "\n*** Triangulation fehlgeschlagen ***")
          )
          
          (HAFM:log-write "INFO" "=== HAFEDIT beendet ===")
        )
      )
    )
  )
  
  (if old-cmdecho (setvar "CMDECHO" old-cmdecho))
  (if old-attdia (setvar "ATTDIA" old-attdia))
  (princ)
)

;;; HAFLIST - Alle Oberflaechen auflisten
(defun c:HAFLIST ( / surfaces data boundary breaklines inner-pts holes)
  (HAFM:ensure-init)
  (HAFM:log-write "INFO" "Befehl HAFLIST gestartet")
  (setq surfaces (HAFM:list-surfaces))
  (if surfaces
    (progn
      (princ (strcat "\n\n=== HAF Oberflaechen in Zeichnung (" (itoa (length surfaces)) ") ==="))
      (foreach name surfaces
        (setq data (HAFM:load-surface name))
        (if data
          (progn
            (setq boundary   (cdr (assoc "BOUNDARY"   data)))
            (setq breaklines (cdr (assoc "BREAKLINES" data)))
            (setq inner-pts  (cdr (assoc "INNER_PTS"  data)))
            (setq holes      (cdr (assoc "HOLES"      data)))
            (princ (strcat "\n  " name
              " (" (itoa (length boundary)) " Umrandung"
              ", " (itoa (length inner-pts)) " innere"
              ", " (itoa (length breaklines)) " BK"
              ", " (itoa (length holes)) " Loecher)"))
          )
        )
      )
      (princ "\n")
    )
    (princ "\n  Keine Oberflaechen in dieser Zeichnung.\n")
  )
  (HAFM:log-write "INFO" "Befehl HAFLIST beendet")
  (princ)
)

;;; HAFDELETE - Oberflaeche loeschen
(defun c:HAFDELETE ( / surfaces name confirm)
  (HAFM:ensure-init)
  (HAFM:log-write "INFO" "Befehl HAFDELETE gestartet")
  (setq surfaces (HAFM:list-surfaces))
  (if surfaces
    (progn
      (princ "\nVorhandene Oberflaechen:")
      (foreach s surfaces (princ (strcat "\n  " s)))
      (setq name (getstring T "\nName der zu loeschenden Oberflaeche: "))
      (if (member name surfaces)
        (progn
          (initget "Ja Nein")
          (setq confirm (getkword (strcat "\n\"" name "\" wirklich loeschen? [Ja/Nein]: ")))
          (if (= confirm "Ja")
            (progn
              (HAFM:delete-surface name)
              (princ (strcat "\n  Oberflaeche \"" name "\" geloescht."))
            )
            (princ "\n  Abgebrochen.")
          )
        )
        (princ (strcat "\n*** Oberflaeche \"" name "\" nicht gefunden ***"))
      )
    )
    (princ "\n  Keine Oberflaechen vorhanden.")
  )
  (HAFM:log-write "INFO" "Befehl HAFDELETE beendet")
  (princ)
)

;;; ============================================================================
;;; SETTINGS (DCL Dialog)
;;; ============================================================================

(defun HAFM:write-settings-dcl ( / dcl-file fp)
  (setq dcl-file (vl-filename-mktemp "haf" nil ".dcl"))
  (setq fp (open dcl-file "w"))
  
  (write-line "hafm_settings : dialog {" fp)
  (write-line "  label = \"HoeheAufFlaecheManager - Einstellungen\";" fp)
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
  
  ;; --- Hoehenkote ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Hoehenkote\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"use_suffix\";" fp)
  (write-line "      label = \"Eigener Layer\";" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : edit_box {" fp)
  (write-line "        key = \"layer_suffix\";" fp)
  (write-line "        label = \"Suffix (nach _):\";" fp)
  (write-line "        edit_width = 10;" fp)
  (write-line "      }" fp)
  (write-line "      : text {" fp)
  (write-line "        key = \"layer_preview\";" fp)
  (write-line "        label = \"\";" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Umrandung ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Umrandung\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"outline_keep\";" fp)
  (write-line "      label = \"Behalten\";" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : toggle {" fp)
  (write-line "        key = \"outline_own_layer\";" fp)
  (write-line "        label = \"Eigener Layer\";" fp)
  (write-line "      }" fp)
  (write-line "      : edit_box {" fp)
  (write-line "        key = \"outline_suffix\";" fp)
  (write-line "        label = \"Suffix:\";" fp)
  (write-line "        edit_width = 6;" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : toggle {" fp)
  (write-line "        key = \"outline_bylayer\";" fp)
  (write-line "        label = \"Layer-Farbe\";" fp)
  (write-line "      }" fp)
  (write-line "      : popup_list {" fp)
  (write-line "        key = \"outline_color\";" fp)
  (write-line "        label = \"Farbe:\";" fp)
  (write-line "        list = \"Rot\\nGelb\\nGruen\\nCyan\\nBlau\\nMagenta\\nWeiss\";" fp)
  (write-line "        width = 12;" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Bruchlinie ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Bruchlinie\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"breakline_keep\";" fp)
  (write-line "      label = \"Behalten\";" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : toggle {" fp)
  (write-line "        key = \"breakline_own_layer\";" fp)
  (write-line "        label = \"Eigener Layer\";" fp)
  (write-line "      }" fp)
  (write-line "      : edit_box {" fp)
  (write-line "        key = \"breakline_suffix\";" fp)
  (write-line "        label = \"Suffix:\";" fp)
  (write-line "        edit_width = 6;" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : toggle {" fp)
  (write-line "        key = \"breakline_bylayer\";" fp)
  (write-line "        label = \"Layer-Farbe\";" fp)
  (write-line "      }" fp)
  (write-line "      : popup_list {" fp)
  (write-line "        key = \"breakline_color\";" fp)
  (write-line "        label = \"Farbe:\";" fp)
  (write-line "        list = \"Rot\\nGelb\\nGruen\\nCyan\\nBlau\\nMagenta\\nWeiss\";" fp)
  (write-line "        width = 12;" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Hoehenlinie ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Hoehenlinie\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"contour_keep\";" fp)
  (write-line "      label = \"Behalten\";" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : toggle {" fp)
  (write-line "        key = \"contour_own_layer\";" fp)
  (write-line "        label = \"Eigener Layer\";" fp)
  (write-line "      }" fp)
  (write-line "      : edit_box {" fp)
  (write-line "        key = \"contour_suffix\";" fp)
  (write-line "        label = \"Suffix:\";" fp)
  (write-line "        edit_width = 6;" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : toggle {" fp)
  (write-line "        key = \"contour_bylayer\";" fp)
  (write-line "        label = \"Layer-Farbe\";" fp)
  (write-line "      }" fp)
  (write-line "      : popup_list {" fp)
  (write-line "        key = \"contour_color\";" fp)
  (write-line "        label = \"Farbe:\";" fp)
  (write-line "        list = \"Rot\\nGelb\\nGruen\\nCyan\\nBlau\\nMagenta\\nWeiss\";" fp)
  (write-line "        width = 12;" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- Hoehenlinienraster ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Hoehenlinienraster\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"grid_keep\";" fp)
  (write-line "      label = \"Behalten\";" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : toggle {" fp)
  (write-line "        key = \"grid_own_layer\";" fp)
  (write-line "        label = \"Eigener Layer\";" fp)
  (write-line "      }" fp)
  (write-line "      : edit_box {" fp)
  (write-line "        key = \"grid_suffix\";" fp)
  (write-line "        label = \"Suffix:\";" fp)
  (write-line "        edit_width = 6;" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : toggle {" fp)
  (write-line "        key = \"grid_bylayer\";" fp)
  (write-line "        label = \"Layer-Farbe\";" fp)
  (write-line "      }" fp)
  (write-line "      : popup_list {" fp)
  (write-line "        key = \"grid_color\";" fp)
  (write-line "        label = \"Farbe:\";" fp)
  (write-line "        list = \"Rot\\nGelb\\nGruen\\nCyan\\nBlau\\nMagenta\\nWeiss\\nGrau\";" fp)
  (write-line "        width = 12;" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "    : edit_box {" fp)
  (write-line "      key = \"grid_interval\";" fp)
  (write-line "      label = \"Abstand (N):\";" fp)
  (write-line "      edit_width = 8;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)
  
  ;; --- TIN-Netz ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"TIN-Netz (5+ Punkte)\";" fp)
  (write-line "    : toggle {" fp)
  (write-line "      key = \"tin_keep\";" fp)
  (write-line "      label = \"Behalten\";" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : toggle {" fp)
  (write-line "        key = \"tin_own_layer\";" fp)
  (write-line "        label = \"Eigener Layer\";" fp)
  (write-line "      }" fp)
  (write-line "      : edit_box {" fp)
  (write-line "        key = \"tin_suffix\";" fp)
  (write-line "        label = \"Suffix:\";" fp)
  (write-line "        edit_width = 6;" fp)
  (write-line "      }" fp)
  (write-line "    }" fp)
  (write-line "    : row {" fp)
  (write-line "      : toggle {" fp)
  (write-line "        key = \"tin_bylayer\";" fp)
  (write-line "        label = \"Layer-Farbe\";" fp)
  (write-line "      }" fp)
  (write-line "      : popup_list {" fp)
  (write-line "        key = \"tin_color\";" fp)
  (write-line "        label = \"Farbe:\";" fp)
  (write-line "        list = \"Rot\\nGelb\\nGruen\\nCyan\\nBlau\\nMagenta\\nWeiss\\nGrau\";" fp)
  (write-line "        width = 12;" fp)
  (write-line "      }" fp)
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
(defun HAFM:show-settings ( / dcl-file dcl-id result cur-scale cur-default-scale cur-libpath cfg-val)
  (HAFM:log-write "INFO" "Settings-Dialog geoeffnet")
  
  ;; Aktuelle Werte lesen (HAFM: nur Config, kein DWG Property)
  (setq cfg-val (HAFM:get-config-value "DEFAULT_SCALE"))
  (setq cur-scale (if (and cfg-val (/= cfg-val "")) (atof cfg-val) 1.0))
  (setq cur-default-scale cur-scale)
  (setq cur-libpath (HAFM:get-config-value "BLOCKIMPORT_PATH"))
  (if (null cur-libpath) (setq cur-libpath "(nicht konfiguriert)"))
  
  ;; DCL schreiben und laden
  (setq dcl-file (HAFM:write-settings-dcl))
  (setq dcl-id (load_dialog dcl-file))
  
  (if (not (new_dialog "hafm_settings" dcl-id))
    (progn
      (HAFM:log-write "ERROR" "DCL Dialog konnte nicht geoeffnet werden")
      (princ "\n*** Fehler: Dialog konnte nicht geoeffnet werden ***")
      (unload_dialog dcl-id)
      (vl-file-delete dcl-file)
    )
    (progn
      ;; Werte in Dialog setzen
      (set_tile "scale" (if (> cur-scale 0.0) (rtos cur-scale 2 2) "(nicht gesetzt)"))
      (set_tile "default_scale" (rtos cur-default-scale 2 2))
      (set_tile "use_suffix" (if *HAFM:use-layer-suffix* "1" "0"))
      (set_tile "layer_suffix" *HAFM:layer-suffix*)
      (set_tile "layer_preview" (strcat "Vorschau: " (getvar "CLAYER") "_" *HAFM:layer-suffix*))
      (set_tile "libpath" cur-libpath)
      (set_tile "debug" (if *HAFM:debug-mode* "1" "0"))
      (set_tile "logpath" (strcat "Log: " (HAFM:get-appdata-path) "\\Log"))
      (setq *block-import-context* "HAFM")
      (set_tile "blockname_info"
        (strcat "Aktueller Block: "
          (if (BLI:resolve-blockname "HAFM")
            (BLI:resolve-blockname "HAFM")
            "(nicht konfiguriert)")))
      (set_tile "info" (strcat "HoeheAufFlaecheManager v" *HAFM:version*))
      
      ;; Linien-Settings in Dialog setzen
      ;; Umrandung
      (set_tile "outline_keep" (if *HAFM:outline-keep* "1" "0"))
      (set_tile "outline_own_layer" (if *HAFM:outline-own-layer* "1" "0"))
      (set_tile "outline_bylayer" (if *HAFM:outline-use-layer* "1" "0"))
      (set_tile "outline_color" (itoa (1- *HAFM:outline-color*)))  ;; ACI 1-7 -> Index 0-6
      (set_tile "outline_suffix" *HAFM:outline-suffix*)
      ;; Bruchlinie
      (set_tile "breakline_keep" (if *HAFM:breakline-keep* "1" "0"))
      (set_tile "breakline_own_layer" (if *HAFM:breakline-own-layer* "1" "0"))
      (set_tile "breakline_bylayer" (if *HAFM:breakline-use-layer* "1" "0"))
      (set_tile "breakline_color" (itoa (1- *HAFM:breakline-color*)))
      (set_tile "breakline_suffix" *HAFM:breakline-suffix*)
      ;; Hoehenlinie
      (set_tile "contour_keep" (if *HAFM:contour-keep* "1" "0"))
      (set_tile "contour_own_layer" (if *HAFM:contour-own-layer* "1" "0"))
      (set_tile "contour_bylayer" (if *HAFM:contour-use-layer* "1" "0"))
      (set_tile "contour_color" (itoa (1- *HAFM:contour-color*)))
      (set_tile "contour_suffix" *HAFM:contour-suffix*)
      ;; Hoehenlinienraster
      (set_tile "grid_keep" (if *HAFM:grid-keep* "1" "0"))
      (set_tile "grid_own_layer" (if *HAFM:grid-own-layer* "1" "0"))
      (set_tile "grid_bylayer" (if *HAFM:grid-use-layer* "1" "0"))
      (set_tile "grid_color" (itoa (1- *HAFM:grid-color*)))
      (set_tile "grid_suffix" *HAFM:grid-suffix*)
      (set_tile "grid_interval" (rtos *HAFM:grid-interval* 2 2))
      ;; TIN-Netz
      (set_tile "tin_keep" (if *HAFM:tin-keep* "1" "0"))
      (set_tile "tin_own_layer" (if *HAFM:tin-own-layer* "1" "0"))
      (set_tile "tin_bylayer" (if *HAFM:tin-use-layer* "1" "0"))
      (set_tile "tin_color" (itoa (1- *HAFM:tin-color*)))
      (set_tile "tin_suffix" *HAFM:tin-suffix*)
      
      ;; Live-Vorschau Layer-Suffix
      (action_tile "layer_suffix"
        "(set_tile \"layer_preview\" (strcat \"Vorschau: \" (getvar \"CLAYER\") \"_\" (get_tile \"layer_suffix\")))"
      )
      
      ;; Durchsuchen-Button fuer BlockImport.lsp
      (action_tile "btn_browse"
        (strcat
          "(progn"
          "  (setq *HAFM:tmp-path*"
          "    (getfiled \"BlockImport.lsp auswaehlen\""
          "      (if (findfile (get_tile \"libpath\"))"
          "        (vl-filename-directory (get_tile \"libpath\"))"
          "        (cond ((getvar \"DWGPREFIX\")) ((getenv \"USERPROFILE\")) (T \"\"))"
          "      )"
          "      \"lsp\" 0))"
          "  (if *HAFM:tmp-path*"
          "    (set_tile \"libpath\" *HAFM:tmp-path*)"
          "  )"
          ")"
        )
      )
      
      ;; Block-Verwaltung Button: Werte speichern VOR done_dialog (Sub-Dialog Bug!)
      (action_tile "btn_block"
        (strcat
          "(setq *HAFM:tmp-scale* (get_tile \"scale\"))"
          "(setq *HAFM:tmp-default-scale* (get_tile \"default_scale\"))"
          "(setq *HAFM:tmp-use-suffix* (get_tile \"use_suffix\"))"
          "(setq *HAFM:tmp-layer-suffix* (get_tile \"layer_suffix\"))"
          "(setq *HAFM:tmp-libpath* (get_tile \"libpath\"))"
          "(setq *HAFM:tmp-debug* (get_tile \"debug\"))"
          "(setq *HAFM:tmp-outline-keep* (get_tile \"outline_keep\"))"
          "(setq *HAFM:tmp-outline-own-layer* (get_tile \"outline_own_layer\"))"
          "(setq *HAFM:tmp-outline-bylayer* (get_tile \"outline_bylayer\"))"
          "(setq *HAFM:tmp-outline-color* (get_tile \"outline_color\"))"
          "(setq *HAFM:tmp-outline-suffix* (get_tile \"outline_suffix\"))"
          "(setq *HAFM:tmp-breakline-keep* (get_tile \"breakline_keep\"))"
          "(setq *HAFM:tmp-breakline-own-layer* (get_tile \"breakline_own_layer\"))"
          "(setq *HAFM:tmp-breakline-bylayer* (get_tile \"breakline_bylayer\"))"
          "(setq *HAFM:tmp-breakline-color* (get_tile \"breakline_color\"))"
          "(setq *HAFM:tmp-breakline-suffix* (get_tile \"breakline_suffix\"))"
          "(setq *HAFM:tmp-contour-keep* (get_tile \"contour_keep\"))"
          "(setq *HAFM:tmp-contour-own-layer* (get_tile \"contour_own_layer\"))"
          "(setq *HAFM:tmp-contour-bylayer* (get_tile \"contour_bylayer\"))"
          "(setq *HAFM:tmp-contour-color* (get_tile \"contour_color\"))"
          "(setq *HAFM:tmp-contour-suffix* (get_tile \"contour_suffix\"))"
          "(setq *HAFM:tmp-grid-keep* (get_tile \"grid_keep\"))"
          "(setq *HAFM:tmp-grid-own-layer* (get_tile \"grid_own_layer\"))"
          "(setq *HAFM:tmp-grid-bylayer* (get_tile \"grid_bylayer\"))"
          "(setq *HAFM:tmp-grid-color* (get_tile \"grid_color\"))"
          "(setq *HAFM:tmp-grid-suffix* (get_tile \"grid_suffix\"))"
          "(setq *HAFM:tmp-grid-interval* (get_tile \"grid_interval\"))"
          "(setq *HAFM:tmp-tin-keep* (get_tile \"tin_keep\"))"
          "(setq *HAFM:tmp-tin-own-layer* (get_tile \"tin_own_layer\"))"
          "(setq *HAFM:tmp-tin-bylayer* (get_tile \"tin_bylayer\"))"
          "(setq *HAFM:tmp-tin-color* (get_tile \"tin_color\"))"
          "(setq *HAFM:tmp-tin-suffix* (get_tile \"tin_suffix\"))"
          "(done_dialog 2)"
        )
      )
      
      ;; OK: Werte in globale Vars speichern VOR done_dialog (Sub-Dialog Bug!)
      (action_tile "accept"
        (strcat
          "(setq *HAFM:tmp-scale* (get_tile \"scale\"))"
          "(setq *HAFM:tmp-default-scale* (get_tile \"default_scale\"))"
          "(setq *HAFM:tmp-use-suffix* (get_tile \"use_suffix\"))"
          "(setq *HAFM:tmp-layer-suffix* (get_tile \"layer_suffix\"))"
          "(setq *HAFM:tmp-libpath* (get_tile \"libpath\"))"
          "(setq *HAFM:tmp-debug* (get_tile \"debug\"))"
          "(setq *HAFM:tmp-outline-keep* (get_tile \"outline_keep\"))"
          "(setq *HAFM:tmp-outline-own-layer* (get_tile \"outline_own_layer\"))"
          "(setq *HAFM:tmp-outline-bylayer* (get_tile \"outline_bylayer\"))"
          "(setq *HAFM:tmp-outline-color* (get_tile \"outline_color\"))"
          "(setq *HAFM:tmp-outline-suffix* (get_tile \"outline_suffix\"))"
          "(setq *HAFM:tmp-breakline-keep* (get_tile \"breakline_keep\"))"
          "(setq *HAFM:tmp-breakline-own-layer* (get_tile \"breakline_own_layer\"))"
          "(setq *HAFM:tmp-breakline-bylayer* (get_tile \"breakline_bylayer\"))"
          "(setq *HAFM:tmp-breakline-color* (get_tile \"breakline_color\"))"
          "(setq *HAFM:tmp-breakline-suffix* (get_tile \"breakline_suffix\"))"
          "(setq *HAFM:tmp-contour-keep* (get_tile \"contour_keep\"))"
          "(setq *HAFM:tmp-contour-own-layer* (get_tile \"contour_own_layer\"))"
          "(setq *HAFM:tmp-contour-bylayer* (get_tile \"contour_bylayer\"))"
          "(setq *HAFM:tmp-contour-color* (get_tile \"contour_color\"))"
          "(setq *HAFM:tmp-contour-suffix* (get_tile \"contour_suffix\"))"
          "(setq *HAFM:tmp-grid-keep* (get_tile \"grid_keep\"))"
          "(setq *HAFM:tmp-grid-own-layer* (get_tile \"grid_own_layer\"))"
          "(setq *HAFM:tmp-grid-bylayer* (get_tile \"grid_bylayer\"))"
          "(setq *HAFM:tmp-grid-color* (get_tile \"grid_color\"))"
          "(setq *HAFM:tmp-grid-suffix* (get_tile \"grid_suffix\"))"
          "(setq *HAFM:tmp-grid-interval* (get_tile \"grid_interval\"))"
          "(setq *HAFM:tmp-tin-keep* (get_tile \"tin_keep\"))"
          "(setq *HAFM:tmp-tin-own-layer* (get_tile \"tin_own_layer\"))"
          "(setq *HAFM:tmp-tin-bylayer* (get_tile \"tin_bylayer\"))"
          "(setq *HAFM:tmp-tin-color* (get_tile \"tin_color\"))"
          "(setq *HAFM:tmp-tin-suffix* (get_tile \"tin_suffix\"))"
          "(done_dialog 1)"
        )
      )
      
      ;; Dialog starten
      (setq result (start_dialog))
      
      ;; Auswerten
      (cond
        ;; OK (result = 1)
        ((= result 1)
          ;; Skalierung (nur Config, kein DWG Property)
          (if (> (atof *HAFM:tmp-scale*) 0.0)
            (progn
              (setq *HAFM:default-scale* (atof *HAFM:tmp-scale*))
              (HAFM:set-config-value "DEFAULT_SCALE" *HAFM:tmp-scale*)
              (HAFM:log-write "INFO" (strcat "Skalierung: " *HAFM:tmp-scale*))
            )
            (if (/= *HAFM:tmp-scale* "(nicht gesetzt)")
              (HAFM:log-write "WARN" (strcat "Ungueltige Skalierung: " *HAFM:tmp-scale*))
            )
          )
          ;; Default-Skalierung (gleich)
          (if (> (atof *HAFM:tmp-default-scale*) 0.0)
            (progn
              (setq *HAFM:default-scale* (atof *HAFM:tmp-default-scale*))
              (HAFM:set-config-value "DEFAULT_SCALE" *HAFM:tmp-default-scale*)
              (HAFM:log-write "INFO" (strcat "Default-Skalierung: " *HAFM:tmp-default-scale*))
            )
            (HAFM:log-write "WARN" (strcat "Ungueltige Default-Skalierung: " *HAFM:tmp-default-scale*))
          )
          ;; Layer-Suffix
          (setq *HAFM:use-layer-suffix* (= *HAFM:tmp-use-suffix* "1"))
          (HAFM:set-config-value "USE_LAYER_SUFFIX" (if *HAFM:use-layer-suffix* "1" "0"))
          (if (and *HAFM:tmp-layer-suffix* (/= *HAFM:tmp-layer-suffix* ""))
            (progn
              (setq *HAFM:layer-suffix* *HAFM:tmp-layer-suffix*)
              (HAFM:set-config-value "LAYER_SUFFIX" *HAFM:layer-suffix*)
            )
            (progn
              (princ "\n*** Layer-Suffix darf nicht leer sein ***")
              (HAFM:log-write "WARN" "Leeres Layer-Suffix ignoriert")
            )
          )
          ;; BlockImport Pfad
          (if (and *HAFM:tmp-libpath*
                   (/= *HAFM:tmp-libpath* "(nicht konfiguriert)")
                   (/= *HAFM:tmp-libpath* cur-libpath))
            (progn
              (HAFM:set-config-value "BLOCKIMPORT_PATH" *HAFM:tmp-libpath*)
              (HAFM:log-write "INFO" (strcat "BlockImport Pfad: " *HAFM:tmp-libpath*))
            )
          )
          ;; Debug
          (setq *HAFM:debug-mode* (= *HAFM:tmp-debug* "1"))
          (HAFM:set-config-value "DEBUG" (if *HAFM:debug-mode* "1" "0"))
          
          ;; Umrandung
          (setq *HAFM:outline-keep* (= *HAFM:tmp-outline-keep* "1"))
          (setq *HAFM:outline-own-layer* (= *HAFM:tmp-outline-own-layer* "1"))
          (setq *HAFM:outline-use-layer* (= *HAFM:tmp-outline-bylayer* "1"))
          (setq *HAFM:outline-color* (1+ (atoi *HAFM:tmp-outline-color*))) ;; Index 0-6 -> ACI 1-7
          (if (and *HAFM:tmp-outline-suffix* (/= *HAFM:tmp-outline-suffix* ""))
            (setq *HAFM:outline-suffix* *HAFM:tmp-outline-suffix*))
          (HAFM:set-config-value "OUTLINE_KEEP" (if *HAFM:outline-keep* "1" "0"))
          (HAFM:set-config-value "OUTLINE_OWN_LAYER" (if *HAFM:outline-own-layer* "1" "0"))
          (HAFM:set-config-value "OUTLINE_USE_LAYER" (if *HAFM:outline-use-layer* "1" "0"))
          (HAFM:set-config-value "OUTLINE_COLOR" (itoa *HAFM:outline-color*))
          (HAFM:set-config-value "OUTLINE_SUFFIX" *HAFM:outline-suffix*)
          
          ;; Bruchlinie
          (setq *HAFM:breakline-keep* (= *HAFM:tmp-breakline-keep* "1"))
          (setq *HAFM:breakline-own-layer* (= *HAFM:tmp-breakline-own-layer* "1"))
          (setq *HAFM:breakline-use-layer* (= *HAFM:tmp-breakline-bylayer* "1"))
          (setq *HAFM:breakline-color* (1+ (atoi *HAFM:tmp-breakline-color*)))
          (if (and *HAFM:tmp-breakline-suffix* (/= *HAFM:tmp-breakline-suffix* ""))
            (setq *HAFM:breakline-suffix* *HAFM:tmp-breakline-suffix*))
          (HAFM:set-config-value "BREAKLINE_KEEP" (if *HAFM:breakline-keep* "1" "0"))
          (HAFM:set-config-value "BREAKLINE_OWN_LAYER" (if *HAFM:breakline-own-layer* "1" "0"))
          (HAFM:set-config-value "BREAKLINE_USE_LAYER" (if *HAFM:breakline-use-layer* "1" "0"))
          (HAFM:set-config-value "BREAKLINE_COLOR" (itoa *HAFM:breakline-color*))
          (HAFM:set-config-value "BREAKLINE_SUFFIX" *HAFM:breakline-suffix*)
          
          ;; Hoehenlinie
          (setq *HAFM:contour-keep* (= *HAFM:tmp-contour-keep* "1"))
          (setq *HAFM:contour-own-layer* (= *HAFM:tmp-contour-own-layer* "1"))
          (setq *HAFM:contour-use-layer* (= *HAFM:tmp-contour-bylayer* "1"))
          (setq *HAFM:contour-color* (1+ (atoi *HAFM:tmp-contour-color*)))
          (if (and *HAFM:tmp-contour-suffix* (/= *HAFM:tmp-contour-suffix* ""))
            (setq *HAFM:contour-suffix* *HAFM:tmp-contour-suffix*))
          (HAFM:set-config-value "CONTOUR_KEEP" (if *HAFM:contour-keep* "1" "0"))
          (HAFM:set-config-value "CONTOUR_OWN_LAYER" (if *HAFM:contour-own-layer* "1" "0"))
          (HAFM:set-config-value "CONTOUR_USE_LAYER" (if *HAFM:contour-use-layer* "1" "0"))
          (HAFM:set-config-value "CONTOUR_COLOR" (itoa *HAFM:contour-color*))
          (HAFM:set-config-value "CONTOUR_SUFFIX" *HAFM:contour-suffix*)
          
          ;; Hoehenlinienraster
          (setq *HAFM:grid-keep* (= *HAFM:tmp-grid-keep* "1"))
          (setq *HAFM:grid-own-layer* (= *HAFM:tmp-grid-own-layer* "1"))
          (setq *HAFM:grid-use-layer* (= *HAFM:tmp-grid-bylayer* "1"))
          (setq *HAFM:grid-color* (1+ (atoi *HAFM:tmp-grid-color*)))
          (if (and *HAFM:tmp-grid-suffix* (/= *HAFM:tmp-grid-suffix* ""))
            (setq *HAFM:grid-suffix* *HAFM:tmp-grid-suffix*))
          (if (and *HAFM:tmp-grid-interval* (/= *HAFM:tmp-grid-interval* ""))
            (if (> (atof *HAFM:tmp-grid-interval*) 0.0)
              (setq *HAFM:grid-interval* (atof *HAFM:tmp-grid-interval*))
              (HAFM:log-write "WARN" "Raster-Abstand muss > 0 sein")
            )
          )
          (HAFM:set-config-value "GRID_KEEP" (if *HAFM:grid-keep* "1" "0"))
          (HAFM:set-config-value "GRID_OWN_LAYER" (if *HAFM:grid-own-layer* "1" "0"))
          (HAFM:set-config-value "GRID_USE_LAYER" (if *HAFM:grid-use-layer* "1" "0"))
          (HAFM:set-config-value "GRID_COLOR" (itoa *HAFM:grid-color*))
          (HAFM:set-config-value "GRID_SUFFIX" *HAFM:grid-suffix*)
          (HAFM:set-config-value "GRID_INTERVAL" (rtos *HAFM:grid-interval* 2 2))
          
          ;; TIN-Netz
          (setq *HAFM:tin-keep* (= *HAFM:tmp-tin-keep* "1"))
          (setq *HAFM:tin-own-layer* (= *HAFM:tmp-tin-own-layer* "1"))
          (setq *HAFM:tin-use-layer* (= *HAFM:tmp-tin-bylayer* "1"))
          (setq *HAFM:tin-color* (1+ (atoi *HAFM:tmp-tin-color*)))
          (if (and *HAFM:tmp-tin-suffix* (/= *HAFM:tmp-tin-suffix* ""))
            (setq *HAFM:tin-suffix* *HAFM:tmp-tin-suffix*))
          (HAFM:set-config-value "TIN_KEEP" (if *HAFM:tin-keep* "1" "0"))
          (HAFM:set-config-value "TIN_OWN_LAYER" (if *HAFM:tin-own-layer* "1" "0"))
          (HAFM:set-config-value "TIN_USE_LAYER" (if *HAFM:tin-use-layer* "1" "0"))
          (HAFM:set-config-value "TIN_COLOR" (itoa *HAFM:tin-color*))
          (HAFM:set-config-value "TIN_SUFFIX" *HAFM:tin-suffix*)
          
          (HAFM:log-write "INFO" (strcat "Settings: HK=" (if *HAFM:use-layer-suffix* (strcat "_" *HAFM:layer-suffix*) "aus")
                                        " UM=" (if *HAFM:outline-keep* "behalten" "temp") "/" (HAFM:color-name *HAFM:outline-color*)
                                        " BL=" (if *HAFM:breakline-keep* "behalten" "temp") "/" (HAFM:color-name *HAFM:breakline-color*)
                                        " HL=" (if *HAFM:contour-keep* "behalten" "temp") "/" (HAFM:color-name *HAFM:contour-color*)
                                        " HR=" (if *HAFM:grid-keep* "behalten" "temp") "/" (HAFM:color-name *HAFM:grid-color*)
                                        " TIN=" (if *HAFM:tin-keep* "behalten" "temp") "/" (HAFM:color-name *HAFM:tin-color*)
                                        " N=" (rtos *HAFM:grid-interval* 2 2)
                                        " Debug=" (if *HAFM:debug-mode* "ein" "aus")))
          (HAFM:flush-config)
          (princ "\nEinstellungen gespeichert.")
        )
        
        ;; Block-Manager (result = 2)
        ((= result 2)
          (HAFM:log-write "INFO" "Block-Verwaltung geoeffnet aus Settings")
          (unload_dialog dcl-id)
          (vl-file-delete dcl-file)
          (manage-block-import "HAFM")
          ;; Settings erneut oeffnen
          (HAFM:log-write "INFO" "Settings erneut oeffnen nach Block-Verwaltung")
          (HAFM:show-settings)
        )
        
        ;; Abbrechen (result = 0)
        (T
          (HAFM:log-write "INFO" "Settings abgebrochen")
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
  (setq *HAFM:tmp-scale* nil)
  (setq *HAFM:tmp-default-scale* nil)
  (setq *HAFM:tmp-use-suffix* nil)
  (setq *HAFM:tmp-layer-suffix* nil)
  (setq *HAFM:tmp-libpath* nil)
  (setq *HAFM:tmp-debug* nil)
  (setq *HAFM:tmp-path* nil)
  (setq *HAFM:tmp-outline-keep* nil)
  (setq *HAFM:tmp-outline-own-layer* nil)
  (setq *HAFM:tmp-outline-bylayer* nil)
  (setq *HAFM:tmp-outline-color* nil)
  (setq *HAFM:tmp-outline-suffix* nil)
  (setq *HAFM:tmp-breakline-keep* nil)
  (setq *HAFM:tmp-breakline-own-layer* nil)
  (setq *HAFM:tmp-breakline-bylayer* nil)
  (setq *HAFM:tmp-breakline-color* nil)
  (setq *HAFM:tmp-breakline-suffix* nil)
  (setq *HAFM:tmp-contour-keep* nil)
  (setq *HAFM:tmp-contour-own-layer* nil)
  (setq *HAFM:tmp-contour-bylayer* nil)
  (setq *HAFM:tmp-contour-color* nil)
  (setq *HAFM:tmp-contour-suffix* nil)
  (setq *HAFM:tmp-grid-keep* nil)
  (setq *HAFM:tmp-grid-own-layer* nil)
  (setq *HAFM:tmp-grid-bylayer* nil)
  (setq *HAFM:tmp-grid-color* nil)
  (setq *HAFM:tmp-grid-suffix* nil)
  (setq *HAFM:tmp-grid-interval* nil)
  (setq *HAFM:tmp-tin-keep* nil)
  (setq *HAFM:tmp-tin-own-layer* nil)
  (setq *HAFM:tmp-tin-bylayer* nil)
  (setq *HAFM:tmp-tin-color* nil)
  (setq *HAFM:tmp-tin-suffix* nil)
)


;;; Settings-Befehl
(defun c:HAFMSETTINGS ( / )
  (HAFM:ensure-init)
  (HAFM:show-settings)
  (princ)
)

;;; HAFMDEBUG - Debug toggle
(defun c:HAFMDEBUG ( / )
  (HAFM:ensure-init)
  (setq *HAFM:debug-mode* (not *HAFM:debug-mode*))
  (HAFM:set-config-value "DEBUG" (if *HAFM:debug-mode* "1" "0"))
  (HAFM:flush-config)
  (princ (strcat "\nDebug-Modus: " (if *HAFM:debug-mode* "EIN" "AUS")))
  (HAFM:log-write "INFO" (strcat "Debug-Modus: " (if *HAFM:debug-mode* "EIN" "AUS")))
  (princ)
)


;;; ============================================================================
;;; INITIALISIERUNG (NUR PRINC! Kein VLA auf Top-Level!)
;;; ============================================================================

(princ (strcat "\nHoeheAufFlaecheManager.lsp v" *HAFM:version* " geladen."))
(princ "\nBefehle: HAFNEW HAFEDIT HAFLIST HAFDELETE HAFMDEBUG")
(princ)
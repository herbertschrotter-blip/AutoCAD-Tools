;;; BlockImport.lsp
;;; Gemeinsame Bibliothek für Block-Import Funktionen
;;; Wird von mehreren AutoCAD-Tools verwendet
;;;
;;; Funktionen:
;;; - Block-Import via ObjectDBX (Lee Mac Utilities)
;;; - Config-Management für Block-Pfade
;;; - Automatische Fallback-Mechanismen
;;; - Session-basiertes Logging (BLI: Namespace)
;;;
;;; Verwendung:
;;; (load "lib/BlockImport.lsp")
;;; (ensure-block-available "BLK_Hoehenkote")
;;;
;;; AppData: %APPDATA%\AutoCAD\Lisp\BlockImport\
;;;   - Log:    Log\BlockImport_YYYYMMDD_HHMMSS.log (max 5 Sessions)
;;;   - Config: Config\BlockImportConfig.txt
;;;   - Backup: Backup\
;;;
;;; Befehle:
;;; ManageBlockImport - Block-Verwaltung (DCL-Dialog)
;;; ShowBlockPath     - Zeigt konfigurierte Pfade
;;; ResetBlockPath    - Löscht alle Pfade
;;;
;;; Version: 1.8.2
;;; Datum: 2026-03-19
;;; Autor: Herbert Schrotter

;;; ============================================================================
;;; KONFIGURATION
;;; ============================================================================

;; Standard-Pfad zur Block-Datei (nil = User wird beim ersten Mal gefragt)
(if (not *default-block-file*)
  (setq *default-block-file* nil)
)

;; Pfad zur Konfigurationsdatei (speichert alle Block-Dateipfade)
;; Neuer Pfad: %APPDATA%\AutoCAD\Lisp\BlockImport\Config\BlockImportConfig.txt
(if (not *block-config-file*)
  (setq *block-config-file* nil)  ;; Wird in BLI:get-appdata-path gesetzt
)

;;; ============================================================================
;;; APPDATA & LOGGING (BLI: Namespace)
;;; ============================================================================

;; AppData-Ordner für BlockImport
(setq *BLI:appdata-folder* "BlockImport")
(if (not (boundp '*BLI:log-session-id*))
  (setq *BLI:log-session-id* nil)
)
(if (not (boundp '*BLI:debug-mode*))
  (setq *BLI:debug-mode* nil)
)

;;; Gibt den AppData-Basispfad zurück, erstellt Ordnerstruktur falls nicht vorhanden
;;; Struktur: %APPDATA%\AutoCAD\Lisp\BlockImport\{Log,Config,Backup}
;;; Rückgabe: Basispfad als String
(defun BLI:get-appdata-path ( / base)
  (setq base (strcat (getenv "APPDATA") "\\AutoCAD\\Lisp\\" *BLI:appdata-folder*))
  (if (not (vl-file-directory-p base))
    (progn
      (vl-mkdir (strcat (getenv "APPDATA") "\\AutoCAD"))
      (vl-mkdir (strcat (getenv "APPDATA") "\\AutoCAD\\Lisp"))
      (vl-mkdir base)
      (vl-mkdir (strcat base "\\Log"))
      (vl-mkdir (strcat base "\\Config"))
      (vl-mkdir (strcat base "\\Backup"))
    )
    ;; Basis existiert, Unterordner sicherstellen
    (progn
      (if (not (vl-file-directory-p (strcat base "\\Log")))
        (vl-mkdir (strcat base "\\Log")))
      (if (not (vl-file-directory-p (strcat base "\\Config")))
        (vl-mkdir (strcat base "\\Config")))
      (if (not (vl-file-directory-p (strcat base "\\Backup")))
        (vl-mkdir (strcat base "\\Backup")))
    )
  )
  ;; Config-Pfad setzen (einmalig)
  (if (not *block-config-file*)
    (setq *block-config-file* (strcat base "\\Config\\BlockImportConfig.txt"))
  )
  base
)

;;; Löscht alte Logs, behält nur die 5 neuesten
;;; Wird beim ersten log-write der Session aufgerufen
(defun BLI:log-rotate ( / logdir files sorted-files delete-count i)
  (setq logdir (strcat (BLI:get-appdata-path) "\\Log"))
  (setq files (vl-directory-files logdir (strcat *BLI:appdata-folder* "_*.log") 1))
  (if files
    (progn
      (setq sorted-files (vl-sort files '<))
      ;; 4 behalten (5. ist die aktuelle, noch nicht erstellt)
      (setq delete-count (- (length sorted-files) 4))
      (if (> delete-count 0)
        (progn
          (setq i 0)
          (repeat delete-count
            (vl-file-delete (strcat logdir "\\" (nth i sorted-files)))
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
(defun BLI:log-write (level message / logdir log-path fp timestamp)
  ;; Debug nur wenn aktiviert
  (if (or (/= level "DEBUG") *BLI:debug-mode*)
    (progn
      ;; Session-ID beim ersten Aufruf erstellen
      (if (not *BLI:log-session-id*)
        (progn
          (setq *BLI:log-session-id*
            (strcat *BLI:appdata-folder* "_"
              (menucmd "M=$(edtime,0,YYYYMMDD_HHMMSS)")
            )
          )
          (BLI:log-rotate)
        )
      )

      (setq logdir (strcat (BLI:get-appdata-path) "\\Log"))
      (setq log-path (strcat logdir "\\" *BLI:log-session-id* ".log"))
      (setq timestamp (menucmd "M=$(edtime,0,YYYY-MO-DD HH:MM:SS)"))

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

;;; ============================================================================
;;; CONFIG MANAGEMENT
;;; ============================================================================

;;; Liest alle gespeicherten Block-Pfade aus Konfigurationsdatei
;;; Rückgabe: Association-Liste ((blockname . filepath) ...) oder nil
(defun read-all-block-paths ( / file line pos key value result version context-prefix)
  (setq result '())

  ;; AppData-Pfad sicherstellen (setzt *block-config-file*)
  (BLI:get-appdata-path)

  ;; Context-Präfix bestimmen (falls gesetzt)
  (setq context-prefix
    (if *block-import-context*
      (strcat *block-import-context* ":")
      nil
    )
  )

  ;; Prüfe ob Config-Datei existiert
  (if (not (findfile *block-config-file*))
    (progn
      (BLI:log-write "DEBUG" "Config-Datei nicht gefunden")
      nil  ;; Datei existiert nicht
    )
    ;; Versuche Datei zu öffnen mit Error-Handling
    (if (vl-catch-all-error-p
          (setq file (vl-catch-all-apply 'open (list *block-config-file* "r"))))
      (progn
        (princ (strcat "\n*** Fehler beim Öffnen der Config-Datei: " *block-config-file* " ***"))
        (BLI:log-write "ERROR" (strcat "Config-Datei kann nicht geöffnet werden: " *block-config-file*))
        nil
      )
      (progn
        ;; Erste Zeile: Version (überspringen)
        (setq version (read-line file))

        ;; Alle weiteren Zeilen: key=value
        (while (setq line (read-line file))
          (if (setq pos (vl-string-search "=" line))
            (progn
              ;; Blockname (vor =)
              (setq key (substr line 1 pos))
              ;; Pfad (nach =)
              (setq value (substr line (+ pos 2)))

              ;; Context-Filterung
              (if context-prefix
                ;; MIT Context: Nur "Context:BlockName" Einträge (NICHT *STANDARD*)
                (if (and (> (strlen key) (strlen context-prefix))
                         (eq (substr key 1 (strlen context-prefix)) context-prefix)
                         (not (wcmatch key "*STANDARD*")))
                  (progn
                    ;; Entferne Context-Präfix
                    (setq key (substr key (+ (strlen context-prefix) 1)))
                    (setq result (cons (cons key value) result))
                  )
                )
                ;; OHNE Context: Nur Einträge ohne ":" (legacy Support, NICHT *STANDARD*)
                (if (and (not (vl-string-search ":" key))
                         (not (wcmatch key "*STANDARD*")))
                  (setq result (cons (cons key value) result))
                )
              )
            )
          )
        )
        (close file)
        (BLI:log-write "DEBUG" (strcat "Config gelesen: " (itoa (length result)) " Einträge"
          (if context-prefix (strcat " (Context: " *block-import-context* ")") "")))
        result
      )
    )
  )
)

;;; Liest Standard-Block aus Config
;;; Berücksichtigt Context (*block-import-context*)
;;; Rückgabe: Blockname (String) oder nil
(defun get-standard-block ( / file line pos key value version standard-key found)
  ;; AppData-Pfad sicherstellen (setzt *block-config-file*)
  (BLI:get-appdata-path)

  ;; Standard-Key bestimmen (mit oder ohne Context)
  (setq standard-key
    (if *block-import-context*
      (strcat "*STANDARD:" *block-import-context* "*")
      "*STANDARD*"
    )
  )

  (setq found nil)
  (setq value nil)

  ;; Lese DIREKT aus Config-Datei (ungefiltert!)
  (if (not (findfile *block-config-file*))
    nil
    (if (not (vl-catch-all-error-p
               (setq file (vl-catch-all-apply 'open (list *block-config-file* "r")))))
      (progn
        (setq version (read-line file))
        (while (and (setq line (read-line file)) (not found))
          (if (setq pos (vl-string-search "=" line))
            (progn
              (setq key (substr line 1 pos))
              ;; Wenn Standard-Key gefunden: Speichere Wert
              (if (eq key standard-key)
                (progn
                  (setq value (substr line (+ pos 2)))
                  (setq found T)  ;; Beende Schleife
                )
              )
            )
          )
        )
        (close file)  ;; Schließe Datei NUR HIER
        (BLI:log-write "DEBUG" (strcat "Standard-Block: " (if value value "keiner")))
        value  ;; Rückgabe
      )
      nil
    )
  )
)

;;; Setzt Standard-Block in Config
;;; Parameter: blockname - Name des Standard-Blocks
;;; Rückgabe: T bei Erfolg, nil bei Fehler
(defun set-standard-block (blockname / standard-key)
  ;; Standard-Key mit Context
  (setq standard-key
    (if *block-import-context*
      (strcat "*STANDARD:" *block-import-context* "*")
      "*STANDARD*"
    )
  )
  (BLI:log-write "INFO" (strcat "Standard-Block gesetzt: " blockname
    (if *block-import-context* (strcat " (Context: " *block-import-context* ")") "")))
  (save-block-path standard-key blockname)
)

;;; Liest gespeicherten Pfad für einen spezifischen Block
;;; Parameter: blockname - Name des Blocks
;;; Rückgabe: Pfad als String oder nil
(defun read-block-path (blockname / all-paths)
  (setq all-paths (read-all-block-paths))
  (cdr (assoc blockname all-paths))
)

;;; Speichert Block-Pfad in Konfigurationsdatei (fügt hinzu oder aktualisiert)
;;; Parameter: blockname - Name des Blocks, filepath - Pfad zur Block-Datei
;;; Rückgabe: T bei Erfolg, nil bei Fehler
(defun save-block-path (blockname filepath / file dir all-paths updated key-with-context line pos key value version)
  ;; AppData-Pfad sicherstellen (setzt *block-config-file*)
  (BLI:get-appdata-path)

  ;; Erstelle Verzeichnis falls nicht vorhanden
  (setq dir (vl-filename-directory *block-config-file*))
  (if (not (vl-file-directory-p dir))
    (if (vl-catch-all-error-p (vl-catch-all-apply 'vl-mkdir (list dir)))
      (progn
        (princ (strcat "\n*** Fehler beim Erstellen des Config-Verzeichnis: " dir " ***"))
        (BLI:log-write "ERROR" (strcat "Config-Verzeichnis kann nicht erstellt werden: " dir))
        nil
      )
      ;; Verzeichnis erfolgreich erstellt
      T
    )
  )

  ;; ALLE existierenden Pfade lesen (UNGEFILTERT - alle Contexts!)
  (setq all-paths '())
  (if (findfile *block-config-file*)
    (if (not (vl-catch-all-error-p
               (setq file (vl-catch-all-apply 'open (list *block-config-file* "r")))))
      (progn
        (setq version (read-line file))
        (while (setq line (read-line file))
          (if (setq pos (vl-string-search "=" line))
            (progn
              (setq key (substr line 1 pos))
              (setq value (substr line (+ pos 2)))
              (setq all-paths (cons (cons key value) all-paths))
            )
          )
        )
        (close file)
      )
    )
  )

  ;; Key mit Context-Präfix (falls nicht schon *STANDARD*)
  (setq key-with-context
    (if (wcmatch blockname "*STANDARD*")
      blockname  ;; *STANDARD:Context* bleibt wie ist
      (if *block-import-context*
        (strcat *block-import-context* ":" blockname)
        blockname  ;; Kein Context: Blockname ohne Präfix
      )
    )
  )

  ;; Blockname aktualisieren oder hinzufügen
  (if (assoc key-with-context all-paths)
    ;; Existiert bereits - aktualisieren
    (setq all-paths (subst (cons key-with-context filepath)
                            (assoc key-with-context all-paths)
                            all-paths))
    ;; Neu hinzufügen
    (setq all-paths (cons (cons key-with-context filepath) all-paths))
  )

  ;; Zurück in Datei schreiben mit Error-Handling
  (if (vl-catch-all-error-p
        (setq file (vl-catch-all-apply 'open (list *block-config-file* "w"))))
    (progn
      (princ (strcat "\n*** Fehler beim Schreiben der Config-Datei: " *block-config-file* " ***"))
      (BLI:log-write "ERROR" (strcat "Config-Datei kann nicht geschrieben werden: " *block-config-file*))
      nil
    )
    (progn
      ;; Erste Zeile: Version
      (write-line "1.0" file)

      ;; Alle Block-Pfade schreiben (ALLE Contexts!)
      (foreach pair all-paths
        (write-line (strcat (car pair) "=" (cdr pair)) file)
      )

      (close file)
      (BLI:log-write "INFO" (strcat "Config gespeichert: " key-with-context "=" filepath))
      T
    )
  )
)

;;; Fordert Benutzer auf, Block-Datei auszuwählen
;;; Parameter: blockname - Name des Blocks (für Meldung und Speicherung)
;;; Rückgabe: Gewählter Pfad oder nil
(defun select-block-file (blockname / filepath default-dir)
  (princ (strcat "\n*** Block-Datei für '" blockname "' nicht gefunden ***"))
  (BLI:log-write "WARN" (strcat "Block-Datei nicht gefunden: " blockname))

  ;; Versuche sinnvollen Start-Ordner zu finden
  (setq default-dir
    (cond
      ;; 1. Zeichnungs-Verzeichnis
      ((getvar "DWGPREFIX"))

      ;; 2. Benutzer-Dokumente
      ((getenv "USERPROFILE"))

      ;; 3. Fallback: Leer
      (T "")
    )
  )

  (princ (strcat "\nBitte wählen Sie die DWG-Datei für Block '" blockname "' aus..."))

  (if (setq filepath (getfiled "Block-Datei wählen" default-dir "dwg" 0))
    (progn
      (princ (strcat "\nGewählte Datei: " filepath))
      (BLI:log-write "INFO" (strcat "Block-Datei gewählt: " blockname " -> " filepath))

      ;; Speichere Pfad in Config (mit blockname)
      (save-block-path blockname filepath)

      (princ "\nPfad wurde gespeichert für zukünftige Sitzungen.")
      filepath
    )
    (progn
      (BLI:log-write "INFO" (strcat "Block-Datei Auswahl abgebrochen: " blockname))
      nil
    )
  )
)

;;; ============================================================================
;;; LEE MAC UTILITIES - ObjectDBX
;;; ============================================================================

;;; Get Document Object - Lee Mac
;;; Retrieves the VLA Document Object for the supplied filename
;;; Parameter: dwg - Pfad zur DWG-Datei
;;; Rückgabe: Document Object oder nil
(defun LM:GetDocumentObject ( dwg / app dbx dwl vrs )
  (cond
    (   (not (setq dwg (findfile dwg))) nil)
    (   (cdr
          (assoc (strcase dwg)
            (vlax-for doc (vla-get-documents (setq app (vlax-get-acad-object)))
              (setq dwl (cons (cons (strcase (vla-get-fullname doc)) doc) dwl))
            )
          )
        )
    )
    (   (progn
          (setq dbx
            (vl-catch-all-apply 'vla-getinterfaceobject
              (list app
                (if (< (setq vrs (atoi (getvar 'acadver))) 16)
                  "objectdbx.axdbdocument" (strcat "objectdbx.axdbdocument." (itoa vrs))
                )
              )
            )
          )
          (or (null dbx) (vl-catch-all-error-p dbx))
        )
        (prompt "\nUnable to interface with ObjectDBX.")
    )
    (   (not (vl-catch-all-error-p (vl-catch-all-apply 'vla-open (list dbx dwg))))
        dbx
    )
  )
)

;;; VLA-Collection: Get Item - Lee Mac
;;; Retrieves the item with index 'idx' if present in the supplied collection
;;; Parameter: col - VLA Collection, idx - Index (String oder Integer)
;;; Rückgabe: Item oder nil
(defun LM:getitem ( col idx / obj )
  (if (not (vl-catch-all-error-p (setq obj (vl-catch-all-apply 'vla-item (list col idx)))))
    obj
  )
)

;;; ============================================================================
;;; BLOCK IMPORT FUNKTIONEN
;;; ============================================================================

;;; Importiert Block aus DWG-Datei ohne Benutzerinteraktion
;;; Parameter:
;;;   filepath - Pfad zur DWG-Datei
;;;   blockname - Name des zu importierenden Blocks
;;; Rückgabe: importEnt (Entity zum späteren Löschen) oder nil bei Fehler
(defun import-block-from-file (filepath blockname / dbx doc abc importEnt)
  (BLI:log-write "INFO" (strcat "Block-Import gestartet: " blockname " aus " filepath))
  (if (not (setq filepath (findfile filepath)))
    (progn
      (princ (strcat "\n  ✗ Datei nicht gefunden: " filepath))
      (BLI:log-write "ERROR" (strcat "Datei nicht gefunden: " filepath))
      nil
    )
    (progn
      (princ (strcat "\n  Importiere Block aus: " (vl-filename-base filepath)))

      ;; ObjectDBX Objekt für externe Datei erstellen
      (if (not (setq dbx (LM:GetDocumentObject filepath)))
        (progn
          (princ "\n  ✗ Fehler beim Öffnen der Datei mit ObjectDBX")
          (BLI:log-write "ERROR" (strcat "ObjectDBX kann Datei nicht öffnen: " filepath))
          nil
        )
        (progn
          (setq doc (vla-get-activedocument (vlax-get-acad-object)))

          ;; Prüfen ob Block in externer Datei existiert
          (if (not (LM:getitem (vla-get-blocks dbx) blockname))
            (progn
              (princ (strcat "\n  ✗ Block '" blockname "' nicht in Datei gefunden"))
              (BLI:log-write "ERROR" (strcat "Block nicht in Datei: " blockname))
              (vlax-release-object dbx)
              nil
            )
            (progn
              ;; Block-Definition kopieren
              (if (vl-catch-all-error-p
                    (vl-catch-all-apply 'vlax-invoke
                      (list dbx 'copyobjects
                        (list (LM:getitem (vla-get-blocks dbx) blockname))
                        (setq abc (vla-get-blocks doc))
                      )
                    )
                  )
                (progn
                  (princ "\n  ✗ Fehler beim Kopieren der Block-Definition")
                  (BLI:log-write "ERROR" (strcat "Block-Kopie fehlgeschlagen: " blockname))
                  (vlax-release-object dbx)
                  nil
                )
                (progn
                  ;; Prüfen ob Block jetzt in aktueller Zeichnung ist
                  (if (LM:getitem abc blockname)
                    (progn
                      (princ "\n  ✓ Block-Definition erfolgreich importiert")

                                            ;; REGEN damit AutoCAD die neue Block-Definition visuell registriert
                      (command "._regenall")

                      (vlax-release-object dbx)
                      (BLI:log-write "INFO" (strcat "Block erfolgreich importiert: " blockname))
                      T  ;; Rückgabe: Erfolg (Block-Definition ist in Zeichnung)
                    )
                    (progn
                      (princ "\n  ✗ Block-Definition konnte nicht übertragen werden")
                      (BLI:log-write "ERROR" (strcat "Block-Transfer fehlgeschlagen: " blockname))
                      (vlax-release-object dbx)
                      nil
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
)

;;; Stellt sicher dass Block verfügbar ist (lädt wenn nötig)
;;; Verwendet Standard-Block wenn konfiguriert
;;; Parameter: blockname - Name des benötigten Blocks (optional bei Standard-Block)
;;; Rückgabe: (T importEnt) bei Erfolg oder (nil nil) bei Fehler
;;;           importEnt ist die Entity die später gelöscht werden sollte
(defun ensure-block-available (blockname / block-path import-result standard-block actual-blockname all-paths block-list)
  ;; Wenn kein Blockname angegeben: Verwende Standard-Block
  (if (null blockname)
    (setq actual-blockname (get-standard-block))
    (setq actual-blockname blockname)
  )

  ;; Wenn immer noch kein Blockname: Prüfe ob genau 1 Block konfiguriert ist
  (if (null actual-blockname)
    (progn
      (setq all-paths (read-all-block-paths))

      ;; Erstelle Liste ohne *STANDARD* Eintrag
      (setq block-list '())
      (foreach pair all-paths
        (if (not (eq (car pair) "*STANDARD*"))
          (setq block-list (cons (car pair) block-list))
        )
      )

      ;; Wenn genau 1 Block: Automatisch als Standard setzen
      (if (= (length block-list) 1)
        (progn
          (setq actual-blockname (car block-list))
          (set-standard-block actual-blockname)
          (princ (strcat "\n✓ Einziger Block automatisch als Standard gesetzt: " actual-blockname))
        )
      )
    )
  )

  ;; Wenn immer noch kein Blockname: Fehler
  (if (null actual-blockname)
    (progn
      (princ "\n*** FEHLER: Kein Block-Name angegeben und kein Standard-Block konfiguriert ***")
      (princ "\nVerwenden Sie 'ManageBlockImport' um einen Standard-Block zu setzen.")
      (BLI:log-write "ERROR" "Kein Blockname und kein Standard-Block konfiguriert")
      (list nil nil)
    )
    (progn
      (BLI:log-write "INFO" (strcat "ensure-block-available: " actual-blockname))
      ;; Prüfen ob Block bereits in Zeichnung vorhanden
      (if (tblsearch "block" actual-blockname)
        (progn
          (BLI:log-write "DEBUG" (strcat "Block bereits in Zeichnung: " actual-blockname))
          (list T nil)  ;; Bereits vorhanden: (Erfolg, kein importEnt)
        )
        (progn
          ;; Block muss geladen werden
          (princ (strcat "\nBlock '" actual-blockname "' wird geladen..."))
          (BLI:log-write "INFO" (strcat "Block wird geladen: " actual-blockname))

          ;; Hole konfigurierten Pfad für diesen Block
          (setq block-path (read-block-path actual-blockname))

          ;; Prüfe ob Pfad existiert UND Datei erreichbar ist
          (if (or (null block-path)
                  (not (findfile block-path)))
            ;; Kein gültiger Pfad - frage Benutzer
            (setq block-path (select-block-file actual-blockname))
          )

          ;; Falls noch immer kein Pfad: Abbruch
          (if (null block-path)
            (progn
              (princ "\n  ✗ Keine Block-Datei ausgewählt")
              (BLI:log-write "WARN" (strcat "Keine Block-Datei ausgewählt für: " actual-blockname))
              (list nil nil)  ;; Fehler: (kein Erfolg, kein importEnt)
            )
                        ;; Versuche zu importieren
            (if (import-block-from-file block-path actual-blockname)
              (list T nil)  ;; Erfolg: Block-Definition importiert, kein importEnt nötig
              (progn
                (princ "\n  ✗ Block konnte nicht importiert werden")
                (BLI:log-write "ERROR" (strcat "Block-Import fehlgeschlagen: " actual-blockname))
                (list nil nil)  ;; Fehler beim Import
              )
            )
          )
        )
      )
    )
  )
)

;;; ============================================================================
;;; MANAGEMENT FUNKTIONEN
;;; ============================================================================

;;; Holt Keyword vom User
;;; Parameter: prompt - Eingabeaufforderung, keywords - String mit Keywords
;;; Rückgabe: Gewähltes Keyword oder nil bei Abbruch
(defun get-keyword-input (prompt keywords / input)
  (initget keywords)
  (setq input (getkword prompt))
  input
)

;;; Zeigt Liste aller konfigurierten Blocks
(defun list-all-blocks ( / all-paths standard-block)
  (setq all-paths (read-all-block-paths))
  (setq standard-block (get-standard-block))

  (princ "\n")
  (princ "\n=== Konfigurierte Blocks ===")

  (if all-paths
    (progn
      (foreach pair all-paths
        ;; Überspringe *STANDARD* Eintrag
        (if (not (eq (car pair) "*STANDARD*"))
          (progn
            (princ (strcat "\n  " (car pair)))
            ;; Markiere Standard-Block
            (if (eq (car pair) standard-block)
              (princ " [STANDARD]")
            )
            ;; Zeige Pfad-Status
            (if (findfile (cdr pair))
              (princ " - ✓")
              (princ " - ✗ Nicht gefunden!")
            )
          )
        )
      )
    )
    (princ "\n  Keine Blocks konfiguriert.")
  )
  (princ "\n")
)

;;; Wählt Standard-Block aus konfigurierten Blocks
(defun select-standard-block ( / all-paths block-list choice standard-block counter selected-block)
  (setq all-paths (read-all-block-paths))
  (setq standard-block (get-standard-block))

  ;; Erstelle Liste ohne *STANDARD* Eintrag
  (setq block-list '())
  (foreach pair all-paths
    (if (not (wcmatch (car pair) "*STANDARD*"))
      (setq block-list (cons (car pair) block-list))
    )
  )

  (if (null block-list)
    (progn
      (princ "\n*** Keine Blocks konfiguriert. Fügen Sie zuerst einen Block hinzu. ***")
      nil
    )
    (progn
      (princ "\n")
      (princ "\n=== Standard-Block wählen ===")
      (princ (strcat "\nAktuell: " (if standard-block standard-block "Keiner")))
      (princ "\n")

      ;; Zeige nummerierte Liste
      (setq counter 1)
      (foreach blockname block-list
        (princ (strcat "\n  " (itoa counter) ". " blockname))
        (setq counter (+ counter 1))
      )

      (princ "\n")
      (setq choice (getint "\nNummer eingeben (0 = Abbrechen): "))

      (if (and choice (> choice 0) (<= choice (length block-list)))
        (progn
          (setq selected-block (nth (- choice 1) block-list))
          (set-standard-block selected-block)
          (princ (strcat "\n✓ Standard-Block gesetzt: " selected-block))
          T
        )
        (progn
          (princ "\nAbgebrochen.")
          nil
        )
      )
    )
  )
)

;;; Fügt neuen Block hinzu
(defun add-new-block ( / filepath blockname filename default-dir result)
  (princ "\n")
  (princ "\n=== Neuen Block hinzufügen ===")
  (BLI:log-write "INFO" "Neuen Block hinzufügen gestartet")

  ;; Bestimme sinnvollen Start-Ordner
  (setq default-dir
    (cond
      ;; 1. Zeichnungs-Verzeichnis
      ((getvar "DWGPREFIX"))

      ;; 2. Benutzer-Dokumente
      ((getenv "USERPROFILE"))

      ;; 3. Fallback: Leer
      (T "")
    )
  )

  ;; Datei auswählen (ZUERST!)
  (princ "\nBitte wählen Sie die DWG-Datei aus...")
  (setq filepath (getfiled "Block-Datei wählen" default-dir "dwg" 0))

  (if (null filepath)
    (progn
      (princ "\nAbgebrochen.")
      (BLI:log-write "INFO" "Block hinzufügen abgebrochen")
      nil
    )
    (progn
      ;; Block-Name aus Dateinamen extrahieren (ohne .dwg)
      (setq blockname (vl-filename-base filepath))

      (princ (strcat "\nGewählte Datei: " filepath))
      (princ (strcat "\nBlock-Name: " blockname))

      ;; Speichere Pfad in Config
      (save-block-path blockname filepath)

      ;; Setze als Standard-Block (automatisch!)
      (set-standard-block blockname)
      (princ (strcat "\n✓ Als Standard-Block gesetzt: " blockname))

      ;; Block sofort importieren (wie beim ersten Mal!)
      (princ "\nImportiere Block...")
      (setq result (ensure-block-available blockname))

      (if (car result)
        (progn
          (princ (strcat "\n✓ Block hinzugefügt und importiert: " blockname))
          (BLI:log-write "INFO" (strcat "Block hinzugefügt und importiert: " blockname " -> " filepath))
          T
        )
        (progn
          (princ (strcat "\n*** FEHLER: Block konnte nicht importiert werden ***"))
          (BLI:log-write "ERROR" (strcat "Block hinzufügen fehlgeschlagen: " blockname))
          nil
        )
      )
    )
  )
)

;;; Entfernt Block aus Config
(defun remove-block ( / all-paths block-list choice selected-block new-paths file dir standard-block was-standard remaining-blocks line pos key value version context-prefix selected-block-with-context counter)
  ;; AppData-Pfad sicherstellen (setzt *block-config-file*)
  (BLI:get-appdata-path)

  ;; Lese ALLE Pfade UNGEFILTERT (wie in save-block-path)
  (setq all-paths '())
  (if (findfile *block-config-file*)
    (if (not (vl-catch-all-error-p
               (setq file (vl-catch-all-apply 'open (list *block-config-file* "r")))))
      (progn
        (setq version (read-line file))
        (while (setq line (read-line file))
          (if (setq pos (vl-string-search "=" line))
            (progn
              (setq key (substr line 1 pos))
              (setq value (substr line (+ pos 2)))
              (setq all-paths (cons (cons key value) all-paths))
            )
          )
        )
        (close file)
      )
    )
  )

  (setq standard-block (get-standard-block))
  (setq context-prefix
    (if *block-import-context*
      (strcat *block-import-context* ":")
      nil
    )
  )

  ;; Erstelle Anzeige-Liste (OHNE Context-Präfix und OHNE *STANDARD*)
  (setq block-list '())
  (foreach pair all-paths
    ;; Filtere für aktuellen Context
    (if context-prefix
      ;; MIT Context: Nur "Context:BlockName" (nicht *STANDARD*)
      (if (and (> (strlen (car pair)) (strlen context-prefix))
               (eq (substr (car pair) 1 (strlen context-prefix)) context-prefix)
               (not (wcmatch (car pair) "*STANDARD*")))
        (progn
          ;; Entferne Context-Präfix für Anzeige
          (setq block-list (cons (substr (car pair) (+ (strlen context-prefix) 1)) block-list))
        )
      )
      ;; OHNE Context: Nur Einträge ohne ":" (nicht *STANDARD*)
      (if (and (not (vl-string-search ":" (car pair)))
               (not (wcmatch (car pair) "*STANDARD*")))
        (setq block-list (cons (car pair) block-list))
      )
    )
  )

  (if (null block-list)
    (progn
      (princ "\n*** Keine Blocks zum Entfernen vorhanden. ***")
      nil
    )
    (progn
      (princ "\n")
      (princ "\n=== Block entfernen ===")
      (princ "\n")

      ;; Zeige nummerierte Liste (OHNE Context-Präfix)
      (setq counter 1)
      (foreach blockname block-list
        (princ (strcat "\n  " (itoa counter) ". " blockname))
        ;; Markiere Standard-Block
        (if (eq blockname standard-block)
          (princ " [STANDARD]")
        )
        (setq counter (+ counter 1))
      )

      (princ "\n")
      (setq choice (getint "\nNummer eingeben (0 = Abbrechen): "))

      (if (and choice (> choice 0) (<= choice (length block-list)))
        (progn
          ;; selected-block OHNE Context-Präfix
          (setq selected-block (nth (- choice 1) block-list))

          ;; selected-block-with-context MIT Context-Präfix (für Löschen)
          (setq selected-block-with-context
            (if context-prefix
              (strcat context-prefix selected-block)
              selected-block
            )
          )

          ;; Prüfe ob Standard-Block entfernt wird
          (setq was-standard (eq selected-block standard-block))

          ;; Erstelle neue Liste ohne den gewählten Block
          (setq new-paths '())
          (foreach pair all-paths
            (if (not (eq (car pair) selected-block-with-context))
              (setq new-paths (cons pair new-paths))
            )
          )

          ;; Wenn Standard-Block entfernt: Entferne auch *STANDARD* Eintrag
          (if was-standard
            (progn
              (setq new-paths
                (vl-remove-if
                  '(lambda (x)
                     (wcmatch (car x)
                       (if *block-import-context*
                         (strcat "*STANDARD:" *block-import-context* "*")
                         "*STANDARD*"
                       )
                     )
                   )
                  new-paths
                )
              )
            )
          )

          ;; Schreibe Config neu
          (setq dir (vl-filename-directory *block-config-file*))
          (if (not (vl-file-directory-p dir))
            (vl-catch-all-apply 'vl-mkdir (list dir))
          )

          (if (vl-catch-all-error-p
                (setq file (vl-catch-all-apply 'open (list *block-config-file* "w"))))
            (progn
              (princ "\n*** Fehler beim Schreiben der Config ***")
              (BLI:log-write "ERROR" "Config kann nicht geschrieben werden beim Entfernen")
              nil
            )
            (progn
              (write-line "1.0" file)
              (foreach pair new-paths
                (write-line (strcat (car pair) "=" (cdr pair)) file)
              )
              (close file)
              (princ (strcat "\n✓ Block entfernt: " selected-block))
              (BLI:log-write "INFO" (strcat "Block entfernt: " selected-block))

              ;; Wenn Standard-Block entfernt wurde: Frage nach neuem Standard
              (if was-standard
                (progn
                  (princ "\n")
                  (princ "\n*** Der Standard-Block wurde entfernt! ***")

                  ;; Prüfe ob noch andere Blocks vorhanden (im aktuellen Context!)
                  (setq remaining-blocks '())
                  (setq context-prefix
                    (if *block-import-context*
                      (strcat *block-import-context* ":")
                      nil
                    )
                  )

                  (foreach pair new-paths
                    ;; Nur Blocks im aktuellen Context zählen
                    (if context-prefix
                      ;; MIT Context: Prüfe auf "Context:BlockName" (nicht *STANDARD*)
                      (if (and (> (strlen (car pair)) (strlen context-prefix))
                               (eq (substr (car pair) 1 (strlen context-prefix)) context-prefix)
                               (not (wcmatch (car pair) "*STANDARD*")))
                        (setq remaining-blocks (cons pair remaining-blocks))
                      )
                      ;; OHNE Context: Nur Einträge ohne ":" und nicht *STANDARD*
                      (if (and (not (vl-string-search ":" (car pair)))
                               (not (wcmatch (car pair) "*STANDARD*")))
                        (setq remaining-blocks (cons pair remaining-blocks))
                      )
                    )
                  )

                  (if remaining-blocks
                    (progn
                      (princ "\nMöchten Sie einen neuen Standard-Block setzen?")
                      (select-standard-block)
                    )
                    (princ "\nKeine weiteren Blocks vorhanden.")
                  )
                )
              )

              T
            )
          )
        )
        (progn
          (princ "\nAbgebrochen.")
          nil
        )
      )
    )
  )
)

;;; ============================================================================
;;; DCL DIALOG - BLOCK IMPORT MANAGER
;;; ============================================================================

;;; Schreibt die DCL-Datei als Temp-Datei
(defun BLI:write-dcl ( / dcl-file fp)
  (setq dcl-file (vl-filename-mktemp "bli" nil ".dcl"))
  (setq fp (open dcl-file "w"))

  (write-line "bli_manager : dialog {" fp)
  (write-line "  label = \"Block Import Manager\";" fp)
  (write-line "  spacer;" fp)

  ;; --- Block-Liste ---
  (write-line "  : boxed_column {" fp)
  (write-line "    label = \"Konfigurierte Bloecke\";" fp)
  (write-line "    : list_box {" fp)
  (write-line "      key = \"block_list\";" fp)
  (write-line "      width = 50;" fp)
  (write-line "      height = 8;" fp)
  (write-line "      allow_accept = true;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)

  ;; --- Standard-Block Info ---
  (write-line "  : text {" fp)
  (write-line "    key = \"standard_info\";" fp)
  (write-line "    label = \"\";" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)

  ;; --- Buttons Zeile 1 ---
  (write-line "  : row {" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_standard\";" fp)
  (write-line "      label = \"Als Standard\";" fp)
  (write-line "      width = 16;" fp)
  (write-line "    }" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_path\";" fp)
  (write-line "      label = \"Pfad aendern\";" fp)
  (write-line "      width = 16;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)

  ;; --- Buttons Zeile 2 ---
  (write-line "  : row {" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_add\";" fp)
  (write-line "      label = \"Hinzufuegen\";" fp)
  (write-line "      width = 16;" fp)
  (write-line "    }" fp)
  (write-line "    : button {" fp)
  (write-line "      key = \"btn_remove\";" fp)
  (write-line "      label = \"Entfernen\";" fp)
  (write-line "      width = 16;" fp)
  (write-line "    }" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)

  ;; --- Pfad-Anzeige ---
  (write-line "  : text {" fp)
  (write-line "    key = \"path_info\";" fp)
  (write-line "    label = \"\";" fp)
  (write-line "  }" fp)
  (write-line "  spacer;" fp)

  ;; --- Schliessen ---
  (write-line "  : button {" fp)
  (write-line "    key = \"btn_close\";" fp)
  (write-line "    label = \"Schliessen\";" fp)
  (write-line "    is_default = true;" fp)
  (write-line "    width = 16;" fp)
  (write-line "    fixed_width = true;" fp)
  (write-line "    alignment = centered;" fp)
  (write-line "  }" fp)

  (write-line "}" fp)
  (close fp)
  dcl-file
)

;;; Erstellt die Listbox-Einträge für den DCL-Dialog
;;; Rückgabe: Liste von Strings für list_box (oder nil)
(defun BLI:build-block-list ( / all-paths standard-block entries)
  (setq all-paths (read-all-block-paths))
  (setq standard-block (get-standard-block))
  (setq entries '())

  (if all-paths
    (foreach pair all-paths
      (if (not (wcmatch (car pair) "*STANDARD*"))
        (setq entries
          (append entries
            (list
              (strcat (car pair)
                (if (eq (car pair) standard-block) "  [STANDARD]" "")
                (if (findfile (cdr pair)) "  OK" "  FEHLT!")
              )
            )
          )
        )
      )
    )
  )
  entries
)

;;; Gibt den reinen Blocknamen aus einem Listbox-Eintrag zurück
;;; Entfernt " [STANDARD]", " OK", " FEHLT!" Suffixe
(defun BLI:extract-blockname (entry / pos)
  (if entry
    (progn
      ;; Entferne alles ab erstem doppeltem Leerzeichen
      (setq pos (vl-string-search "  " entry))
      (if pos
        (substr entry 1 pos)
        entry
      )
    )
    nil
  )
)

;;; Gibt die reine Block-Liste zurück (nur Namen, ohne Suffixe)
(defun BLI:get-block-names ( / all-paths names)
  (setq all-paths (read-all-block-paths))
  (setq names '())
  (if all-paths
    (foreach pair all-paths
      (if (not (wcmatch (car pair) "*STANDARD*"))
        (setq names (append names (list (car pair))))
      )
    )
  )
  names
)

;;; Hauptmenü für Block-Import Management (DCL-Dialog)
;;; Parameter: context - Context-ID für Namespace (z.B. "SetHK", "HoeheAufLinie")
;;;                      Wenn nil: Verwendet globale *block-import-context*
(defun manage-block-import (context / dcl-file dcl-id result old-context
                                      entries selected-idx selected-name
                                      standard-block all-names filepath
                                      block-path blockname)
  ;; Sichere alten Context falls vorhanden
  (setq old-context *block-import-context*)

  ;; Setze Context für diese Session
  (if context
    (setq *block-import-context* context)
  )

  (BLI:log-write "INFO" (strcat "Block-Manager DCL geöffnet"
    (if *block-import-context* (strcat " (Context: " *block-import-context* ")") "")))

  ;; DCL schreiben
  (setq dcl-file (BLI:write-dcl))
  (setq dcl-id (load_dialog dcl-file))

  ;; Dialog-Schleife (bleibt offen bis Schliessen)
  (setq result 1)  ;; Start mit "Dialog neu aufbauen"

  (while (> result 0)
    (if (not (new_dialog "bli_manager" dcl-id))
      (progn
        (BLI:log-write "ERROR" "DCL Dialog konnte nicht geöffnet werden")
        (princ "\n*** Fehler: Dialog konnte nicht geöffnet werden ***")
        (setq result 0)  ;; Abbruch
      )
      (progn
        ;; --- Liste befüllen ---
        (setq entries (BLI:build-block-list))
        (if entries
          (progn
            (start_list "block_list")
            (foreach entry entries (add_list entry))
            (end_list)
            ;; Erste Zeile selektieren
            (set_tile "block_list" "0")
            ;; Pfad der ersten Zeile anzeigen
            (setq selected-name (BLI:extract-blockname (car entries)))
            (setq block-path (read-block-path selected-name))
            (set_tile "path_info"
              (if block-path (strcat "Pfad: " block-path) "Pfad: -"))
          )
          (progn
            (start_list "block_list")
            (add_list "(keine Bloecke konfiguriert)")
            (end_list)
            (set_tile "path_info" "Pfad: -")
          )
        )

        ;; Standard-Block Info
        (setq standard-block (get-standard-block))
        (set_tile "standard_info"
          (strcat "Standard-Block: " (if standard-block standard-block "Nicht gesetzt")))

        ;; --- Listbox Selection: Pfad-Anzeige aktualisieren ---
        (action_tile "block_list"
          (strcat
            "(setq *BLI:tmp-sel-idx* (atoi (get_tile \"block_list\")))"
            "(setq *BLI:tmp-sel-name* (BLI:extract-blockname (nth *BLI:tmp-sel-idx* (BLI:build-block-list))))"
            "(if *BLI:tmp-sel-name*"
            "  (set_tile \"path_info\" (strcat \"Pfad: \" (if (read-block-path *BLI:tmp-sel-name*) (read-block-path *BLI:tmp-sel-name*) \"-\")))"
            "  (set_tile \"path_info\" \"Pfad: -\")"
            ")"
          )
        )

        ;; --- Button: Als Standard ---
        (action_tile "btn_standard"
          (strcat
            "(setq *BLI:tmp-sel-idx* (atoi (get_tile \"block_list\")))"
            "(setq *BLI:tmp-sel-name* (BLI:extract-blockname (nth *BLI:tmp-sel-idx* (BLI:build-block-list))))"
            "(if *BLI:tmp-sel-name*"
            "  (progn (set-standard-block *BLI:tmp-sel-name*) (done_dialog 1))"
            "  (alert \"Bitte einen Block auswaehlen\")"
            ")"
          )
        )

        ;; --- Button: Pfad ändern ---
        (action_tile "btn_path"
          (strcat
            "(setq *BLI:tmp-sel-idx* (atoi (get_tile \"block_list\")))"
            "(setq *BLI:tmp-sel-name* (BLI:extract-blockname (nth *BLI:tmp-sel-idx* (BLI:build-block-list))))"
            "(if *BLI:tmp-sel-name*"
            "  (progn (done_dialog 3))"  ;; 3 = Pfad ändern
            "  (alert \"Bitte einen Block auswaehlen\")"
            ")"
          )
        )

        ;; --- Button: Hinzufügen ---
        (action_tile "btn_add" "(done_dialog 4)")  ;; 4 = Hinzufügen

        ;; --- Button: Entfernen ---
        (action_tile "btn_remove"
          (strcat
            "(setq *BLI:tmp-sel-idx* (atoi (get_tile \"block_list\")))"
            "(setq *BLI:tmp-sel-name* (BLI:extract-blockname (nth *BLI:tmp-sel-idx* (BLI:build-block-list))))"
            "(if *BLI:tmp-sel-name*"
            "  (done_dialog 5)"  ;; 5 = Entfernen
            "  (alert \"Bitte einen Block auswaehlen\")"
            ")"
          )
        )

        ;; --- Button: Schliessen ---
        (action_tile "btn_close" "(done_dialog 0)")

        ;; --- Dialog starten ---
        (setq result (start_dialog))

        ;; --- Auswerten ---
        (cond
          ;; result=1: Refresh (nach Standard setzen)
          ((= result 1)
            (BLI:log-write "INFO" (strcat "Standard-Block geändert: " (if *BLI:tmp-sel-name* *BLI:tmp-sel-name* "?")))
          )

          ;; result=3: Pfad ändern
          ((= result 3)
            (if *BLI:tmp-sel-name*
              (progn
                (setq filepath (getfiled "Neuen Pfad waehlen" "" "dwg" 0))
                (if filepath
                  (progn
                    (save-block-path *BLI:tmp-sel-name* filepath)
                    (BLI:log-write "INFO" (strcat "Pfad geändert: " *BLI:tmp-sel-name* " -> " filepath))
                  )
                )
              )
            )
            (setq result 1)  ;; Dialog neu öffnen
          )

          ;; result=4: Hinzufügen
          ((= result 4)
            (setq filepath (getfiled "Block-Datei waehlen" "" "dwg" 0))
            (if filepath
              (progn
                (setq blockname (vl-filename-base filepath))
                (save-block-path blockname filepath)
                ;; Wenn erster Block: automatisch als Standard
                (if (not (get-standard-block))
                  (set-standard-block blockname)
                )
                (BLI:log-write "INFO" (strcat "Block hinzugefügt: " blockname " -> " filepath))
              )
            )
            (setq result 1)  ;; Dialog neu öffnen
          )

          ;; result=5: Entfernen
          ((= result 5)
            (if *BLI:tmp-sel-name*
              (progn
                ;; Block aus Config entfernen (vereinfacht: neu schreiben ohne den Block)
                (BLI:remove-block-from-config *BLI:tmp-sel-name*)
                (BLI:log-write "INFO" (strcat "Block entfernt: " *BLI:tmp-sel-name*))
              )
            )
            (setq result 1)  ;; Dialog neu öffnen
          )

          ;; result=0: Schliessen
          (T nil)
        )
      )
    )
  )

  ;; Aufräumen
  (unload_dialog dcl-id)
  (vl-file-delete dcl-file)

  ;; Temp-Variablen aufräumen
  (setq *BLI:tmp-sel-idx* nil)
  (setq *BLI:tmp-sel-name* nil)

  ;; Stelle alten Context wieder her
  (setq *block-import-context* old-context)

  (BLI:log-write "INFO" "Block-Manager DCL geschlossen")
  (princ)
)

;;; Entfernt einen Block aus der Config-Datei
;;; Berücksichtigt Context und entfernt ggf. auch *STANDARD* Eintrag
(defun BLI:remove-block-from-config (blockname / all-paths file line pos key value version
                                      key-with-context standard-block context-prefix new-paths)
  ;; AppData sicherstellen
  (BLI:get-appdata-path)

  (setq context-prefix
    (if *block-import-context*
      (strcat *block-import-context* ":")
      nil
    )
  )

  ;; Key mit Context
  (setq key-with-context
    (if context-prefix
      (strcat context-prefix blockname)
      blockname
    )
  )

  ;; Prüfe ob es der Standard-Block war
  (setq standard-block (get-standard-block))

  ;; ALLE Pfade ungefiltert lesen
  (setq all-paths '())
  (if (findfile *block-config-file*)
    (if (not (vl-catch-all-error-p
               (setq file (vl-catch-all-apply 'open (list *block-config-file* "r")))))
      (progn
        (setq version (read-line file))
        (while (setq line (read-line file))
          (if (setq pos (vl-string-search "=" line))
            (progn
              (setq key (substr line 1 pos))
              (setq value (substr line (+ pos 2)))
              (setq all-paths (cons (cons key value) all-paths))
            )
          )
        )
        (close file)
      )
    )
  )

  ;; Block entfernen
  (setq new-paths
    (vl-remove-if
      '(lambda (x) (eq (car x) key-with-context))
      all-paths
    )
  )

  ;; Wenn es der Standard-Block war: auch *STANDARD* entfernen
  (if (eq blockname standard-block)
    (setq new-paths
      (vl-remove-if
        '(lambda (x)
           (wcmatch (car x)
             (if *block-import-context*
               (strcat "*STANDARD:" *block-import-context* "*")
               "*STANDARD*"
             )
           )
         )
        new-paths
      )
    )
  )

  ;; Config neu schreiben
  (if (not (vl-catch-all-error-p
             (setq file (vl-catch-all-apply 'open (list *block-config-file* "w")))))
    (progn
      (write-line "1.0" file)
      (foreach pair new-paths
        (write-line (strcat (car pair) "=" (cdr pair)) file)
      )
      (close file)
    )
    (BLI:log-write "ERROR" "Config schreiben fehlgeschlagen beim Entfernen")
  )
)

;;; ============================================================================
;;; VERWALTUNGS-FUNKTIONEN
;;; ============================================================================

;;; Zeigt alle konfigurierten Block-Pfade
;;; Kann als Befehl verwendet werden: (defun c:ShowBlockPath () (show-block-path))
(defun show-block-path ( / all-paths)
  (setq all-paths (read-all-block-paths))
  (BLI:log-write "INFO" "ShowBlockPath aufgerufen")

  (princ "\n=== Konfigurierte Block-Pfade ===")

  (if all-paths
    (progn
      (foreach pair all-paths
        (princ (strcat "\n" (car pair) ": " (cdr pair)))
        (if (findfile (cdr pair))
          (princ " [✓ Existiert]")
          (princ " [✗ Nicht gefunden!]")
        )
      )
    )
    (princ "\nKeine Block-Pfade konfiguriert.")
  )

  (princ (strcat "\n\nConfig-Datei: " *block-config-file*))
  (princ "\n")
  (princ)
)

;;; Löscht gespeicherten Block-Pfad
;;; Kann als Befehl verwendet werden: (defun c:ResetBlockPath () (reset-block-path))
(defun reset-block-path ( / )
  ;; AppData-Pfad sicherstellen (setzt *block-config-file*)
  (BLI:get-appdata-path)

  (if (findfile *block-config-file*)
    (progn
      (vl-file-delete *block-config-file*)
      (princ "\nGespeicherte Block-Pfade wurden zurückgesetzt.")
      (princ "\nBeim nächsten Laden wird nach der Datei gefragt.")
      (BLI:log-write "INFO" "Alle Block-Pfade zurückgesetzt (Config gelöscht)")
    )
    (princ "\nKeine gespeicherten Pfade vorhanden.")
  )
  (princ)
)

;;; ============================================================================
;;; BEFEHLE
;;; ============================================================================

;;; Block Import Manager - Hauptbefehl für User
(defun c:ManageBlockImport ( / )
  (BLI:log-write "INFO" "Befehl ManageBlockImport gestartet")
  (manage-block-import nil)  ;; nil = verwendet globale *block-import-context*
)

;;; Zeigt alle konfigurierten Block-Pfade
(defun c:ShowBlockPath ( / )
  (show-block-path)
)

;;; Löscht alle gespeicherten Block-Pfade
(defun c:ResetBlockPath ( / )
  (BLI:log-write "INFO" "Befehl ResetBlockPath gestartet")
  (reset-block-path)
)

;;; Debug-Modus Toggle
(defun c:BlockImportDebug ( / )
  (setq *BLI:debug-mode* (not *BLI:debug-mode*))
  (princ (strcat "\nBlockImport Debug-Modus: "
    (if *BLI:debug-mode* "EIN" "AUS")))
  (BLI:log-write "INFO"
    (strcat "Debug-Modus: " (if *BLI:debug-mode* "EIN" "AUS")))
  (princ)
)

;;; ============================================================================
;;; INITIALISIERUNG
;;; ============================================================================

;; COM-Objekt laden (für VLA-Funktionen)
(vl-load-com)

;; Lade-Meldung
(BLI:log-write "INFO" "=== BlockImport.lsp v1.8.2 geladen ===")
(princ "\nBlockImport.lsp v1.8.2 geladen.")
(princ "\nBefehle: ManageBlockImport - Block-Verwaltung")
(princ "\n         ShowBlockPath - Zeigt konfigurierte Pfade")
(princ "\n         ResetBlockPath - Löscht alle Pfade")
(princ "\n         BlockImportDebug - Debug-Modus ein/aus")
(princ "\nFunktionen: ensure-block-available")
(princ)

;;; Ende der Datei
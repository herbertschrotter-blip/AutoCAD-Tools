;;; BlockImport.lsp
;;; Gemeinsame Bibliothek für Block-Import Funktionen
;;; Wird von mehreren AutoCAD-Tools verwendet
;;;
;;; Funktionen:
;;; - Block-Import via ObjectDBX (Lee Mac Utilities)
;;; - Config-Management für Block-Pfade
;;; - Automatische Fallback-Mechanismen
;;;
;;; Verwendung:
;;; (load "lib/BlockImport.lsp")
;;; (ensure-block-available "BLK_Hoehenkote")
;;;
;;; Version: 1.5.0
;;; Datum: 2026-02-13
;;; Autor: Herbert Schrotter

;;; ============================================================================
;;; KONFIGURATION
;;; ============================================================================

;; Standard-Pfad zur Block-Datei (nil = User wird beim ersten Mal gefragt)
(if (not *default-block-file*)
  (setq *default-block-file* nil)
)

;; Pfad zur Konfigurationsdatei (speichert alle Block-Dateipfade)
(if (not *block-config-file*)
  (setq *block-config-file* (strcat (getenv "APPDATA") "/AutoCAD/BlockImportConfig.txt"))
)

;;; ============================================================================
;;; CONFIG MANAGEMENT
;;; ============================================================================

;;; Liest alle gespeicherten Block-Pfade aus Konfigurationsdatei
;;; Rückgabe: Association-Liste ((blockname . filepath) ...) oder nil
(defun read-all-block-paths ( / file line pos key value result version context-prefix)
  (setq result '())
  
  ;; Context-Präfix bestimmen (falls gesetzt)
  (setq context-prefix 
    (if *block-import-context*
      (strcat *block-import-context* ":")
      nil
    )
  )
  
  ;; Prüfe ob Config-Datei existiert
  (if (not (findfile *block-config-file*))
    nil  ;; Datei existiert nicht
    ;; Versuche Datei zu öffnen mit Error-Handling
    (if (vl-catch-all-error-p
          (setq file (vl-catch-all-apply 'open (list *block-config-file* "r"))))
      (progn
        (princ (strcat "\n*** Fehler beim Öffnen der Config-Datei: " *block-config-file* " ***"))
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
        result
      )
    )
  )
)

;;; Liest Standard-Block aus Config
;;; Berücksichtigt Context (*block-import-context*)
;;; Rückgabe: Blockname (String) oder nil
(defun get-standard-block ( / file line pos key value version standard-key found)
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
  ;; Erstelle Verzeichnis falls nicht vorhanden
  (setq dir (vl-filename-directory *block-config-file*))
  (if (not (vl-file-directory-p dir))
    (if (vl-catch-all-error-p (vl-catch-all-apply 'vl-mkdir (list dir)))
      (progn
        (princ (strcat "\n*** Fehler beim Erstellen des Config-Verzeichnis: " dir " ***"))
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
      T
    )
  )
)

;;; Fordert Benutzer auf, Block-Datei auszuwählen
;;; Parameter: blockname - Name des Blocks (für Meldung und Speicherung)
;;; Rückgabe: Gewählter Pfad oder nil
(defun select-block-file (blockname / filepath default-dir)
  (princ (strcat "\n*** Block-Datei für '" blockname "' nicht gefunden ***"))
  
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
      
      ;; Speichere Pfad in Config (mit blockname)
      (save-block-path blockname filepath)
      
      (princ "\nPfad wurde gespeichert für zukünftige Sitzungen.")
      filepath
    )
    nil
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
  (if (not (setq filepath (findfile filepath)))
    (progn
      (princ (strcat "\n  ✗ Datei nicht gefunden: " filepath))
      nil
    )
    (progn
      (princ (strcat "\n  Importiere Block aus: " (vl-filename-base filepath)))
      
      ;; ObjectDBX Objekt für externe Datei erstellen
      (if (not (setq dbx (LM:GetDocumentObject filepath)))
        (progn
          (princ "\n  ✗ Fehler beim Öffnen der Datei mit ObjectDBX")
          nil
        )
        (progn
          (setq doc (vla-get-activedocument (vlax-get-acad-object)))
          
          ;; Prüfen ob Block in externer Datei existiert
          (if (not (LM:getitem (vla-get-blocks dbx) blockname))
            (progn
              (princ (strcat "\n  ✗ Block '" blockname "' nicht in Datei gefunden"))
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
                  (vlax-release-object dbx)
                  nil
                )
                (progn
                  ;; Prüfen ob Block jetzt in aktueller Zeichnung ist
                  (if (LM:getitem abc blockname)
                    (progn
                      (princ "\n  ✓ Block-Definition erfolgreich importiert")
                      
                      ;; Block einmal unsichtbar einfügen (nur um Entity zu haben)
                      (vla-insertblock
                        (vlax-get-property doc (if (= 1 (getvar 'cvport)) 'paperspace 'modelspace))
                        (vlax-3D-point '(0 0 0))
                        blockname
                        1.0 1.0 1.0
                        0.0
                      )
                      (setq importEnt (entlast))
                      
                      (vlax-release-object dbx)
                      importEnt  ;; Rückgabe: Entity des eingefügten Blocks (zum späteren Löschen)
                    )
                    (progn
                      (princ "\n  ✗ Block-Definition konnte nicht übertragen werden")
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
      (list nil nil)
    )
    (progn
      ;; Prüfen ob Block bereits in Zeichnung vorhanden
      (if (tblsearch "block" actual-blockname)
        (list T nil)  ;; Bereits vorhanden: (Erfolg, kein importEnt)
        (progn
          ;; Block muss geladen werden
          (princ (strcat "\nBlock '" actual-blockname "' wird geladen..."))
          
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
              (list nil nil)  ;; Fehler: (kein Erfolg, kein importEnt)
            )
            ;; Versuche zu importieren
            (if (setq import-result (import-block-from-file block-path actual-blockname))
              (list T import-result)  ;; Erfolg: (Erfolg, importEnt zum späteren Löschen)
              (progn
                (princ "\n  ✗ Block konnte nicht importiert werden")
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
(defun select-standard-block ( / all-paths block-list choice standard-block)
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
          T
        )
        (progn
          (princ (strcat "\n*** FEHLER: Block konnte nicht importiert werden ***"))
          nil
        )
      )
    )
  )
)

;;; Entfernt Block aus Config
(defun remove-block ( / all-paths block-list choice selected-block new-paths file dir standard-block was-standard remaining-blocks)
  (setq all-paths (read-all-block-paths))
  (setq standard-block (get-standard-block))
  
  ;; Erstelle Liste ohne *STANDARD* Eintrag
  (setq block-list '())
  (foreach pair all-paths
    (if (not (wcmatch (car pair) "*STANDARD*"))
      (setq block-list (cons pair block-list))
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
      
      ;; Zeige nummerierte Liste
      (setq counter 1)
      (foreach pair block-list
        (princ (strcat "\n  " (itoa counter) ". " (car pair)))
        ;; Markiere Standard-Block
        (if (eq (car pair) standard-block)
          (princ " [STANDARD]")
        )
        (setq counter (+ counter 1))
      )
      
      (princ "\n")
      (setq choice (getint "\nNummer eingeben (0 = Abbrechen): "))
      
      (if (and choice (> choice 0) (<= choice (length block-list)))
        (progn
          (setq selected-block (car (nth (- choice 1) block-list)))
          
          ;; Prüfe ob Standard-Block entfernt wird
          (setq was-standard (eq selected-block standard-block))
          
          ;; Erstelle neue Liste ohne den gewählten Block
          (setq new-paths '())
          (foreach pair all-paths
            (if (not (eq (car pair) selected-block))
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
              nil
            )
            (progn
              (write-line "1.0" file)
              (foreach pair new-paths
                (write-line (strcat (car pair) "=" (cdr pair)) file)
              )
              (close file)
              (princ (strcat "\n✓ Block entfernt: " selected-block))
              
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

;;; Hauptmenü für Block-Import Management
;;; Parameter: context - Context-ID für Namespace (z.B. "SetHK", "HoeheAufLinie")
;;;                      Wenn nil: Verwendet globale *block-import-context*
(defun manage-block-import (context / option continue standard-block all-blocks old-context)
  ;; Sichere alten Context falls vorhanden
  (setq old-context *block-import-context*)
  
  ;; Setze Context für diese Session
  (if context
    (setq *block-import-context* context)
  )
  
  (setq continue T)
  
  ;; Prüfe beim Start: Blocks vorhanden aber kein Standard?
  (setq standard-block (get-standard-block))
  (setq all-blocks (read-all-block-paths))
  
  (if (and all-blocks (not standard-block))
    (progn
      (princ "\n*** Blocks konfiguriert aber kein Standard-Block gesetzt! ***")
      (princ "\nMöchten Sie einen Standard-Block wählen?")
      (select-standard-block)
      (princ "\n")
    )
  )
  
  (while continue
    (setq standard-block (get-standard-block))
    
    ;; Menü anzeigen
    (princ "\n")
    (princ "\n========================================")
    (princ "\n     BLOCK IMPORT MANAGER")
    (princ "\n========================================")
    (princ (strcat "\nStandard-Block: " (if standard-block standard-block "Nicht gesetzt")))
    (princ "\n")
    (princ "\n[L]iste      - Alle Blocks anzeigen")
    (princ "\n[S]tandard   - Standard-Block wählen")
    (princ "\n[H]inzufügen - Neuen Block hinzufügen")
    (princ "\n[E]ntfernen  - Block löschen")
    (princ "\n[A]bbrechen  - Beenden")
    (princ "\n")
    
    ;; Option abfragen mit Rechtsklick-Menü
    ;; WICHTIG: Rechtsklick-Menü liest Keywords aus eckigen Klammern!
    ;; Erste Buchstaben müssen GROß sein!
    (initget "Liste Standard Hinzufuegen Entfernen Abbrechen")
    (setq option (getkword "\nOption [Liste/Standard/Hinzufuegen/Entfernen/Abbrechen]: "))
    
    (cond
      ((eq option "Liste")
       (textscr)  ;; Aktiviere Textfenster
       (list-all-blocks)
       (princ "\nDrücken Sie eine beliebige Taste zum Fortfahren...")
       (grread T)  ;; Wartet auf Tastendruck
       (setq continue nil))  ;; Beende Menü nach Liste!
      
      ((eq option "Standard")
       (select-standard-block))
      
      ((eq option "Hinzufuegen")
       (add-new-block))
      
      ((eq option "Entfernen")
       (remove-block))
      
      ((eq option "Abbrechen")
       (setq continue nil))
      
      ;; ESC oder ungültige Eingabe
      ((null option)
       (setq continue nil))
      
      (T
       (setq continue nil))
    )
  )
  
  ;; Stelle alten Context wieder her
  (setq *block-import-context* old-context)
  
  (princ "\n")
  (princ)
)

;;; ============================================================================
;;; VERWALTUNGS-FUNKTIONEN
;;; ============================================================================

;;; Zeigt alle konfigurierten Block-Pfade
;;; Kann als Befehl verwendet werden: (defun c:ShowBlockPath () (show-block-path))
(defun show-block-path ( / all-paths)
  (setq all-paths (read-all-block-paths))
  
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
  (if (findfile *block-config-file*)
    (progn
      (vl-file-delete *block-config-file*)
      (princ "\nGespeicherte Block-Pfade wurden zurückgesetzt.")
      (princ "\nBeim nächsten Laden wird nach der Datei gefragt.")
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
  (manage-block-import nil)  ;; nil = verwendet globale *block-import-context*
)

;;; Zeigt alle konfigurierten Block-Pfade
(defun c:ShowBlockPath ( / )
  (show-block-path)
)

;;; Löscht alle gespeicherten Block-Pfade
(defun c:ResetBlockPath ( / )
  (reset-block-path)
)

;;; ============================================================================
;;; INITIALISIERUNG
;;; ============================================================================

;; COM-Objekt laden (für VLA-Funktionen)
(vl-load-com)

;; Lade-Meldung
(princ "\nBlockImport.lsp v1.5.0 geladen.")
(princ "\nBefehle: ManageBlockImport - Block-Verwaltung")
(princ "\n         ShowBlockPath - Zeigt konfigurierte Pfade")
(princ "\n         ResetBlockPath - Löscht alle Pfade")
(princ "\nFunktionen: ensure-block-available")
(princ)

;;; Ende der Datei
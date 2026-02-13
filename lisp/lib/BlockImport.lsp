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
;;; Version: 1.2.0
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
(defun read-all-block-paths ( / file line pos key value result version)
  (setq result '())
  (if (and (findfile *block-config-file*)
           (setq file (open *block-config-file* "r")))
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
            ;; Zur Liste hinzufügen
            (setq result (cons (cons key value) result))
          )
        )
      )
      (close file)
    )
  )
  result
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
(defun save-block-path (blockname filepath / file dir all-paths updated)
  ;; Erstelle Verzeichnis falls nicht vorhanden
  (setq dir (vl-filename-directory *block-config-file*))
  (if (not (vl-file-directory-p dir))
    (vl-mkdir dir)
  )
  
  ;; Alle existierenden Pfade lesen
  (setq all-paths (read-all-block-paths))
  
  ;; Blockname aktualisieren oder hinzufügen
  (if (assoc blockname all-paths)
    ;; Existiert bereits - aktualisieren
    (setq all-paths (subst (cons blockname filepath) 
                            (assoc blockname all-paths) 
                            all-paths))
    ;; Neu hinzufügen
    (setq all-paths (cons (cons blockname filepath) all-paths))
  )
  
  ;; Zurück in Datei schreiben
  (if (setq file (open *block-config-file* "w"))
    (progn
      ;; Erste Zeile: Version
      (write-line "1.0" file)
      
      ;; Alle Block-Pfade schreiben
      (foreach pair all-paths
        (write-line (strcat (car pair) "=" (cdr pair)) file)
      )
      
      (close file)
      T
    )
    nil
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
;;; Parameter: blockname - Name des benötigten Blocks
;;; Rückgabe: (T importEnt) bei Erfolg oder (nil nil) bei Fehler
;;;           importEnt ist die Entity die später gelöscht werden sollte
(defun ensure-block-available (blockname / block-path import-result)
  ;; Prüfen ob Block bereits in Zeichnung vorhanden
  (if (tblsearch "block" blockname)
    (list T nil)  ;; Bereits vorhanden: (Erfolg, kein importEnt)
    (progn
      ;; Block muss geladen werden
      (princ (strcat "\nBlock '" blockname "' wird geladen..."))
      
      ;; Hole konfigurierten Pfad für diesen Block
      (setq block-path (read-block-path blockname))
      
      ;; Prüfe ob Pfad existiert UND Datei erreichbar ist
      (if (or (null block-path) 
              (not (findfile block-path)))
        ;; Kein gültiger Pfad - frage Benutzer
        (setq block-path (select-block-file blockname))
      )
      
      ;; Falls noch immer kein Pfad: Abbruch
      (if (null block-path)
        (progn
          (princ "\n  ✗ Keine Block-Datei ausgewählt")
          (list nil nil)  ;; Fehler: (kein Erfolg, kein importEnt)
        )
        ;; Versuche zu importieren
        (if (setq import-result (import-block-from-file block-path blockname))
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
      (princ "\nGespeicherter Block-Pfad wurde zurückgesetzt.")
      (princ "\nBeim nächsten Laden wird nach der Datei gefragt.")
    )
    (princ "\nKein gespeicherter Pfad vorhanden.")
  )
  (princ)
)

;;; ============================================================================
;;; INITIALISIERUNG
;;; ============================================================================

;; COM-Objekt laden (für VLA-Funktionen)
(vl-load-com)

;; Lade-Meldung
(princ "\nBlockImport.lsp v1.2.0 geladen.")
(princ "\nFunktionen: ensure-block-available, show-block-path, reset-block-path")
(princ)

;;; Ende der Datei
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
;;; Version: 1.0.1
;;; Datum: 2026-02-13
;;; Autor: Herbert Schrotter

;;; ============================================================================
;;; KONFIGURATION
;;; ============================================================================

;; Standard-Pfad zur Block-Datei
(if (not *default-block-file*)
  (setq *default-block-file* "D:/OneDrive/Dokumente/02 Arbeit/05 Vorlagen - Scripte/02_AutoCAD Tools/templates/Blöcke/BLK_Hoehenkote.dwg")
)

;; Pfad zur Konfigurationsdatei (speichert Block-Dateipfad)
(if (not *block-config-file*)
  (setq *block-config-file* (strcat (getenv "APPDATA") "/AutoCAD/HoehenkoteBlockConfig.txt"))
)

;;; ============================================================================
;;; CONFIG MANAGEMENT
;;; ============================================================================

;;; Liest gespeicherten Block-Pfad aus Konfigurationsdatei
;;; Rückgabe: Pfad als String oder nil
(defun read-block-path ( / file path version)
  (setq path nil)
  (if (and (findfile *block-config-file*)
           (setq file (open *block-config-file* "r")))
    (progn
      ;; Erste Zeile: Version (für zukünftige Kompatibilität)
      (setq version (read-line file))
      
      ;; Zweite Zeile: Dateipfad
      (setq path (read-line file))
      
      (close file)
    )
  )
  path
)

;;; Speichert Block-Pfad in Konfigurationsdatei
;;; Parameter: filepath - Pfad zur Block-Datei
;;; Rückgabe: T bei Erfolg, nil bei Fehler
(defun save-block-path (filepath / file dir)
  ;; Erstelle Verzeichnis falls nicht vorhanden
  (setq dir (vl-filename-directory *block-config-file*))
  (if (not (vl-file-directory-p dir))
    (vl-mkdir dir)
  )
  
  ;; Speichere Pfad
  (if (setq file (open *block-config-file* "w"))
    (progn
      ;; Erste Zeile: Version
      (write-line "1.0" file)
      
      ;; Zweite Zeile: Dateipfad
      (write-line filepath file)
      
      (close file)
      T
    )
    nil
  )
)

;;; Fordert Benutzer auf, Block-Datei auszuwählen
;;; Rückgabe: Gewählter Pfad oder nil
(defun select-block-file ( / filepath)
  (princ "\n*** Block-Datei nicht gefunden ***")
  (princ (strcat "\nStandard-Pfad: " *default-block-file*))
  (princ "\nBitte wählen Sie die Block-Datei aus (BLK_Hoehenkote.dwg)...")
  
  (if (setq filepath (getfiled "Block-Datei wählen" *default-block-file* "dwg" 0))
    (progn
      (princ (strcat "\nGewählte Datei: " filepath))
      
      ;; Speichere Pfad in Config
      (save-block-path filepath)
      
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
      
      ;; Hole konfigurierten Pfad
      (setq block-path (read-block-path))
      
      ;; Prüfe ob Pfad existiert UND Datei erreichbar ist
      (if (or (null block-path) 
              (not (findfile block-path)))
        (progn
          ;; Gespeicherter Pfad ungültig - versuche Standard-Pfad
          (if (findfile *default-block-file*)
            (progn
              (princ (strcat "\n  Verwende Standard-Pfad: " *default-block-file*))
              (setq block-path *default-block-file*)
              ;; Speichere als neuen Config-Pfad
              (save-block-path block-path)
            )
            ;; Auch Standard-Pfad nicht gefunden - frage Benutzer
            (setq block-path (select-block-file))
          )
        )
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

;;; Zeigt aktuell konfigurierten Block-Pfad
;;; Kann als Befehl verwendet werden: (defun c:ShowBlockPath () (show-block-path))
(defun show-block-path ( / block-path)
  (setq block-path (read-block-path))
  
  (princ "\n=== Konfigurierter Block-Pfad ===")
  
  (if block-path
    (progn
      (princ (strcat "\n" block-path))
      (if (findfile block-path)
        (princ " [✓ Existiert]")
        (princ " [✗ Nicht gefunden!]")
      )
    )
    (progn
      (princ "\nKein Block-Pfad konfiguriert.")
      (princ "\n\nStandard-Pfad:")
      (princ (strcat "\n  " *default-block-file*))
      (if (findfile *default-block-file*)
        (princ " [✓ Existiert]")
        (princ " [✗ Nicht gefunden]")
      )
    )
  )
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
(princ "\nBlockImport.lsp v1.0.1 geladen.")
(princ "\nFunktionen: ensure-block-available, show-block-path, reset-block-path")
(princ)

;;; Ende der Datei
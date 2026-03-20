;; PLATTESCHRAEG.LSP
;; Punkte -> 2D Poly (WCS, Elev=maxZ) -> Extrude (nach unten) -> Slice 3P (Both)
;; Debug: Solid-Handle, SS-Handle, neue Solids nach Slice (Handles)

(vl-load-com)

(defun _rt (x) (rtos x 2 4))

(defun _handle (e / ed)
  (if (and e (setq ed (entget e)))
    (cdr (assoc 5 ed))
    "nil"
  )
)

(defun _makeLWPolyWCS (ptsW elevW closed / data flag)
  (setq flag (if closed 1 0))
  (setq data
    (append
      (list
        (cons 0 "LWPOLYLINE")
        (cons 100 "AcDbEntity")
        (cons 100 "AcDbPolyline")
        (cons 90 (length ptsW))
        (cons 70 flag)
        (cons 38 elevW)
      )
      (apply 'append
        (mapcar
          (function (lambda (pw)
            (list (cons 10 (list (car pw) (cadr pw))))
          ))
          ptsW
        )
      )
    )
  )
  (entmakex data)
)

(defun _isSolid (e)
  (and e (= (cdr (assoc 0 (entget e))) "3DSOLID"))
)

(defun _collectNewSolids (marker / out e)
  ;; sammelt 3DSOLID-Entities, die nach 'marker' kommen
  (setq out '())
  (setq e (entnext marker))
  (while e
    (if (_isSolid e) (setq out (cons e out)))
    (setq e (entnext e))
  )
  (reverse out)
)

(defun _ssFirstHandle (ss / e)
  (if (and ss (> (sslength ss) 0))
    (_handle (ssname ss 0))
    "nil"
  )
)

(defun c:PLATTESCHRAEG (/ *error* oldCE
                          ptsW pU pW i
                          minZ maxZ ans closed
                          D H pl solid ss
                          s1U s2U s3U s1W s2W s3W
                          markerBeforeSlice newSolids n)

  (setq oldCE (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)

  (defun *error* (msg)
    (setvar "CMDECHO" oldCE)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*")))
      (prompt (strcat "\nFehler: " msg))
    )
    (princ)
  )

  (prompt "\nPLATTESCHRAEG – Randpunkte (3+) klicken (ENTER beendet). UCS->WCS aktiv.")
  (setq ptsW '())
  (setq i 0)

  ;; Punkt 1
  (setq pU (getpoint "\nPunkt 1: "))
  (if (not pU) (progn (prompt "\nAbbruch.") (setvar "CMDECHO" oldCE) (princ) (exit)))
  (setq pW (trans pU 1 0)) ; UCS -> WCS

  (setq ptsW (list pW))
  (setq minZ (caddr pW))
  (setq maxZ (caddr pW))
  (setq i 1)

  (prompt
    (strcat
      "\nDBG #" (itoa i)
      " UCS=(" (_rt (car pU)) "," (_rt (cadr pU)) "," (_rt (caddr pU)) ")"
      "  WCS=(" (_rt (car pW)) "," (_rt (cadr pW)) "," (_rt (caddr pW)) ")"
      " | minZ=" (_rt minZ) " maxZ=" (_rt maxZ)
    )
  )

  ;; weitere Punkte
  (while (setq pU (getpoint (strcat "\nPunkt " (itoa (+ i 1)) " (ENTER=fertig): ")))
    (setq pW (trans pU 1 0))
    (setq ptsW (append ptsW (list pW)))
    (setq i (1+ i))

    (if (< (caddr pW) minZ) (setq minZ (caddr pW)))
    (if (> (caddr pW) maxZ) (setq maxZ (caddr pW)))

    (prompt
      (strcat
        "\nDBG #" (itoa i)
        " UCS=(" (_rt (car pU)) "," (_rt (cadr pU)) "," (_rt (caddr pU)) ")"
        "  WCS=(" (_rt (car pW)) "," (_rt (cadr pW)) "," (_rt (caddr pW)) ")"
        " | minZ=" (_rt minZ) " maxZ=" (_rt maxZ)
      )
    )
  )

  (if (< (length ptsW) 3)
    (progn (prompt "\nZu wenig Punkte (mind. 3).") (*error* "CANCEL"))
  )

  ;; schließen?
  (initget "Ja Nein")
  (setq ans (getkword "\nPolyline schließen? [Ja/Nein] <Ja>: "))
  (setq closed (if (or (null ans) (= ans "Ja")) T nil))

  ;; Dicke abfragen
  (setq D (getdist "\nDicke eingeben (z.B. 0.40 oder 40): "))
  (if (or (not D) (<= D 0.0))
    (progn (prompt "\nUngültige Dicke.") (*error* "CANCEL"))
  )

  ;; Extrusionshöhe
  (setq H (+ (- maxZ minZ) D))

  (prompt
    (strcat
      "\nDBG Ergebnis: Punkte=" (itoa (length ptsW))
      " | minZ=" (_rt minZ)
      " | maxZ=" (_rt maxZ)
      " | D=" (_rt D)
      " | H=" (_rt H)
      " | PolyElevation=" (_rt maxZ)
      " | ExtrudeHeight=" (_rt (- H)) " (nach unten)"
    )
  )

  ;; Polyline erzeugen (WCS, Elev=maxZ)
  (setq pl (_makeLWPolyWCS ptsW maxZ closed))
  (if (not pl)
    (progn (prompt "\nFehler: Polyline konnte nicht erstellt werden.") (*error* "CANCEL"))
  )

  (prompt "\nOK: Polyline erstellt. Extrudiere...")
  (command "_.EXTRUDE" pl "" (- H))
  (setq solid (entlast))

  (if (not (_isSolid solid))
    (progn
      (prompt "\nWARNUNG: Extrusion ergab keinen 3D-Solid.")
      (*error* "CANCEL")
    )
  )

  ;; SelectionSet für SLICE (Fix)
  (setq ss (ssadd solid))
  (prompt (strcat "\nDBG Solid-Handle (extrudiert): " (_handle solid)))
  (prompt (strcat "\nDBG SS[0]-Handle: " (_ssFirstHandle ss)))

  ;; Slice Punkte (UCS klicken, nach WCS transformieren)
  (prompt "\nJetzt SLICE: 3 Punkte für Schnittebene klicken (im aktuellen UCS).")
  (setq s1U (getpoint "\nSlice Punkt 1: ")) (if (not s1U) (*error* "CANCEL"))
  (setq s2U (getpoint "\nSlice Punkt 2: ")) (if (not s2U) (*error* "CANCEL"))
  (setq s3U (getpoint "\nSlice Punkt 3: ")) (if (not s3U) (*error* "CANCEL"))

  (setq s1W (trans s1U 1 0))
  (setq s2W (trans s2U 1 0))
  (setq s3W (trans s3U 1 0))

  (prompt
    (strcat
      "\nDBG Slice-WCS:"
      " P1=(" (_rt (car s1W)) "," (_rt (cadr s1W)) "," (_rt (caddr s1W)) ")"
      " P2=(" (_rt (car s2W)) "," (_rt (cadr s2W)) "," (_rt (caddr s2W)) ")"
      " P3=(" (_rt (car s3W)) "," (_rt (cadr s3W)) "," (_rt (caddr s3W)) ")"
    )
  )

  ;; Marker setzen, um neue Solids nach Slice zu finden
  (setq markerBeforeSlice (entlast))

  ;; Slice (Both sides) – mit SelectionSet
  (command "_.SLICE" ss "" "_3P" s1W s2W s3W "_Both")

  ;; neue Solids seit marker sammeln
  (setq newSolids (_collectNewSolids markerBeforeSlice))
  (setq n (length newSolids))

  (prompt (strcat "\nDBG Neue 3DSOLIDs nach SLICE: " (itoa n)))
  (if (> n 0)
    (progn
      (foreach e newSolids
        (prompt (strcat "\nDBG  - Handle: " (_handle e)))
      )
    )
  )

  (prompt "\nOK: SLICE beendet (wenn n=0, schneidet die Ebene den Körper nicht).")

  (setvar "CMDECHO" oldCE)
  (princ)
)
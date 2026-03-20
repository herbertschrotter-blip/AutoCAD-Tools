(defun c:BOGENMUSTER ( / p1 p2 ang len r pitch n rem i cen thetaEnd )

  (defun _mkLine (a b)
    (entmakex
      (list
        '(0 . "LINE")
        (cons 10 a)
        (cons 11 b)
      )
    )
  )

  (defun _mkArc (c rad a1 a2)
    (entmakex
      (list
        '(0 . "ARC")
        (cons 10 c)
        (cons 40 rad)
        (cons 50 a1)
        (cons 51 a2)
      )
    )
  )

  (setq p1 (getpoint "\nStartpunkt wählen: "))
  (setq p2 (getpoint p1 "\nEndpunkt wählen: "))

  (if (and p1 p2)
    (progn
      (setq r (getreal "\nRadius der Bögen eingeben: "))

      (if (and r (> r 0.0))
        (progn
          (setq ang   (angle p1 p2))
          (setq len   (distance p1 p2))
          (setq pitch (* 2.0 r))

          ;; obere Linie
          (_mkLine p1 p2)

          ;; Anzahl ganzer Bögen
          (setq n   (fix (/ len pitch)))
          (setq rem (- len (* n pitch)))

          ;; volle Bögen
          (setq i 0)
          (while (< i n)
            (setq cen (polar p1 ang (+ (* i pitch) r)))
            ;; unterer Halbkreis: von links nach rechts
            (_mkArc cen r (+ ang pi) ang)
            (setq i (1+ i))
          )

          ;; letzter Teilbogen, falls Rest vorhanden
          ;; rem liegt zwischen 0 und 2r
          (if (> rem 1e-8)
            (progn
              (setq cen (polar p1 ang (+ (* n pitch) r)))

              ;; Endwinkel des Teilbogens:
              ;; x = cx + r*cos(theta)
              ;; rem ist die abgeschnittene Breite des letzten Bogens
              (setq thetaEnd
                (- (* 2.0 pi)
                   (acos (/ (- rem r) r)))
              )

              (_mkArc cen r (+ ang pi) (+ ang thetaEnd))
            )
          )

          (princ "\nBogenmuster erstellt.")
        )
        (princ "\nUngültiger Radius.")
      )
    )
  )
  (princ)
)